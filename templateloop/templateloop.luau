--!strict

--- Experimental in-luau implementation of event dispatching to templates based on event scopes
---
--- Extra stuff templateloop provides:
--- # Event subscription refcounting
--- Problem: when subscribing to events, it is often hard to know why an event is subscribed to 
--- (e.g. there is no refcount for event subscription). This can lead to situations where events are never unsubscribed
--- even when there are no consumers for them.
--- Solution: we maintain a map of event name to a set of "systems" that have subscribed to the event.
--- When a system subscribes to an event, we add it to the set. When it unsubscribes, we remove it from the set.
--- If the set is empty after removal, we remove the event from the tenant state entirely.
--- This way, we can ensure that events are only subscribed to when there are active consumers for them.

local Primitives = require"@antiraid-core/primitives"
local runtime = require"@antiraid-core/plugins/runtime"
local isolate = require"@antiraid-ext/isolate"
local channel = require"@antiraid/channel"
local datetime = require"@antiraid/datetime"
local templateloopImpl = require"@antiraid-core/templateloop"
local MutexFn = require"@antiraid-ext/sync/mutex"
local LazyLoad = require"@antiraid-ext/sync/lazyload"
local typesext = require"@antiraid/typesext"
local Discord = require"@antiraid-ext/system/discord"

-- Flags 

--- Tenant state flag: Whether or not we have any event refs for any events (used to determine whether we need to fetch eventrefs from the DB or not)
local FLAG_BUILTINS_HAVEEVENTREFS = bit32.lshift(1, 1)

-- Other constants

--- How long to wait for template dispatch results before timing out and moving on (to avoid hanging the entire dispatch if a template is hanging)
local TEMPLATE_DISPATCH_TIMEOUT = datetime.timedelta_seconds(5) -- 5 seconds

-- Start code

-- stdout logging for debugging
local function DebugManager(): templateloopImpl.DebugManager 
    if _G._debug then return { print = _G._debug } end
    return { print = function(...) end }
end

export type TenantStateMutations = {
    flag: number?,
    setFlag: boolean?,
    event: string?,
    setEvent: boolean?,
}

--- Internal manager of tenant state
type TenantStateManager = {
    read IsFlagSet: (flag: number) -> boolean,
    read IsSubscribedToEvent: (event: string) -> boolean,
    read ClonedTenantState: () -> runtime.TenantState,
    --- Updates state and applies extra state ops, returns true if the mutation changed somehow
    read Mutate: (mutations: TenantStateMutations, extraOps: {runtime.StateOp}?) -> boolean,
}

local function TenantStateManager(baseCtx: Primitives.TemplateContext, initialState: runtime.TenantState): TenantStateManager
    DebugManager().print("TenantStateManager init - events:", initialState.events, "flags:", initialState.flags)
    
    -- Single source of truth for the manager
    local state = { flags = initialState.flags, events = table.clone(initialState.events) }
    
    -- Fast lookup cache for events
    local activeEvents = {}
    for _, e in state.events do activeEvents[e] = true end

    local function IsFlagSet(flag: number): boolean 
        return bit32.band(state.flags, flag) ~= 0 
    end
    
    local function IsSubscribedToEvent(event: string): boolean 
        return activeEvents[event] == true 
    end

    local function ClonedTenantState(): runtime.TenantState
        return { events = table.clone(state.events), flags = state.flags }
    end

    local function Mutate(mutations: TenantStateMutations, extraOps: {runtime.StateOp}?)
        local nextFlags = state.flags
        local changed = false

        -- Only allocated if the events actually change
        local nextEvents = nil
        local nextActiveEvents = nil

        if mutations.flag ~= nil and mutations.setFlag ~= nil then
            local hasFlag = bit32.band(nextFlags, mutations.flag) ~= 0
            if hasFlag ~= mutations.setFlag then
                nextFlags = mutations.setFlag 
                    and bit32.bor(nextFlags, mutations.flag) 
                    or bit32.band(nextFlags, bit32.bnot(mutations.flag))
                changed = true
            end
        end

        -- Calculate event updates
        if mutations.event ~= nil and mutations.setEvent ~= nil then
            local hasEvent = activeEvents[mutations.event] or false
            if hasEvent ~= mutations.setEvent then
                nextEvents = table.clone(state.events)
                nextActiveEvents = table.clone(activeEvents)
                
                if mutations.setEvent then
                    table.insert(nextEvents, mutations.event)
                    nextActiveEvents[mutations.event] = true
                else
                    local idx = table.find(nextEvents, mutations.event)
                    if idx then 
                        table.remove(nextEvents, idx) 
                        nextActiveEvents[mutations.event] = nil
                    end
                end
                changed = true
            end
        end

        local ops: {runtime.StateOp} = extraOps or {}

        if changed then
            local payloadEvents = nextEvents or state.events
            table.insert(ops, { 
                op = "UpdateTenantState" :: "UpdateTenantState", 
                events = payloadEvents, 
                flags = nextFlags 
            })
        end

        if #ops > 0 then
            baseCtx:syscall({ op = "State", ops = ops })
        end

        -- 5. Syscall Succeeded! Apply calculations to the local cache.
        if changed then
            state.flags = nextFlags
            if nextEvents then
                state.events = nextEvents
                activeEvents = nextActiveEvents
            end
            DebugManager().print("TenantState Mutated locally - events:", state.events, "flags:", state.flags)
        end

        return changed
    end

    return table.freeze{
        IsFlagSet = IsFlagSet,
        IsSubscribedToEvent = IsSubscribedToEvent,
        ClonedTenantState = ClonedTenantState,
        Mutate = Mutate,
    }
end

--- Internal manager of event refs
type EventRefManager = {
    --- Subscribe to an event with a given system name (used for refcounting)
    read Subscribe: (event: string, system: string, attachedop: runtime.StateOp?) -> (),
    --- Unsubscribe from an event with a given system name (used for refcounting)
    read Unsubscribe: (event: string, system: string) -> (),
    --- Check if we are subscribed to an event with a given system name
    read IsSubscribed: (event: string, system: string) -> boolean,
}

local function EventRefManager(baseCtx: Primitives.TemplateContext, tenantStateManager: TenantStateManager): EventRefManager 
    local eventrefs: {[string]: {[string]: boolean}}? = nil

    --- Internal helper to get event refs from tenant state or cache
    local function geteventrefs(): {[string]: {[string]: boolean}} 
        if not eventrefs then 
            if not tenantStateManager.IsFlagSet(FLAG_BUILTINS_HAVEEVENTREFS) then return {} end -- No point fetching event refs if we don't have any refs, so return empty table
            
            local ops: {runtime.StateOp} = {{ op = "KvGet", key = "eventrefs", scope = "tloop.reserved" }}
            local records = baseCtx:syscall({ op = "State", ops = ops })
            assert(records.op == "State")
            if #records.res > 0 then
                local refs = records.res[1]
                assert(refs.op == "Kv")                
                -- Cache and return event refs after basic validation
                assert(type(refs.value) == "table", "Invalid event refs data in tenant state, expected table")
                local ref =  refs.value :: {[string]: {[string]: boolean}}
                eventrefs = ref
                return ref
            else
                -- Unset event refs flag if we don't have any refs to load yet had the flag set
                tenantStateManager.Mutate({ flag = FLAG_BUILTINS_HAVEEVENTREFS, setFlag = false })
                return {}
            end
        end
        return eventrefs
    end

    local function IsSubscribed(event: string, system: string): boolean 
        local refs = geteventrefs()
        return refs[event] ~= nil and refs[event][system] ~= nil
    end

    local function Subscribe(event: string, system: string, attachedop: runtime.StateOp?) 
        if IsSubscribed(event, system) then 
            if attachedop then baseCtx:syscall({op="State", ops={attachedop}}) end
            return 
        end -- No need to subscribe if we are already subscribed
        local refs = geteventrefs()
        if refs[event] then refs[event][system] = true else refs[event] = { [system] = true } end -- Update refs with new subscription

        -- Also subscribe to event in tenant state manager to ensure we are subscribed at the runtime level
        --
        -- This is anyways a no-op if we are already subscribed, so we don't need to check before subscribing
        local ops: {runtime.StateOp} = {}
        if attachedop then table.insert(ops, attachedop) end
        table.insert(ops, { op = "KvSet" :: "KvSet", key = "eventrefs", scope = "tloop.reserved", value = refs })
        tenantStateManager.Mutate({
            event = event, setEvent = true,
            flag = FLAG_BUILTINS_HAVEEVENTREFS, 
            setFlag = true
        }, ops)
        eventrefs = refs -- update event refs in cache
    end

    local function Unsubscribe(event: string, system: string) 
        if not IsSubscribed(event, system) then return end 
        local refs = geteventrefs()
        if not (refs[event] and refs[event][system]) then return end 
        
        if refs[event] then 
            refs[event][system] = nil 
            if next(refs[event]) == nil then 
                refs[event] = nil 
            end 
        end
        
        local isEventStillActive = (refs[event] ~= nil)
        local hasAnyRefsRemaining = (next(refs) ~= nil)

        -- Pass the dynamically calculated states to the manager
        tenantStateManager.Mutate({
            event = event, setEvent = isEventStillActive,
            flag = FLAG_BUILTINS_HAVEEVENTREFS, setFlag = hasAnyRefsRemaining
        }, {{ op = "KvSet", key = "eventrefs", scope = "tloop.reserved", value = refs }})
        eventrefs = refs -- update event refs in cache
    end

    return table.freeze{
        Subscribe = Subscribe,
        Unsubscribe = Unsubscribe,
        IsSubscribed = IsSubscribed,
    }
end

type Args = {
    ctx: Primitives.TemplateContext,
    ts: runtime.TenantState,
    btd: runtime.BaseTenantData
}

--- Creates a new TemplateLoopManager instance
local lazyloader = LazyLoad(function(args: Args)
    local baseCtx = args.ctx
    local ts = args.ts
    local btd = args.btd
    local discord = Discord(baseCtx)

    -- Setup base state
    local self = {}
    baseCtx.store[templateloopImpl.TEMPLATE_LOOP_KEY] = self

    local debugmanager = DebugManager()
    local tenantStateManager = TenantStateManager(baseCtx, ts)
    local eventRefManager = EventRefManager(baseCtx, tenantStateManager)
    local eventrefmu = MutexFn() -- Mutex for synchronizing access to event refs

    local exposedvfs = btd.base_vfs
    local attachedisolates: {[string]: isolate.Isolate} = {
        ["builtins"] = isolate.new("builtins", typesext.Vfs.newoverlay({
            exposedvfs.Builtins or error("Internal error: Builtins VFS not found in exposed VFSs"),
            exposedvfs.TemplatingTypes or error("Internal error: TemplatingTypes VFS not found in exposed VFSs"),
        }), {})
    } -- map of all attached isolates
    local attachedisolatescount = 1 -- initially only one attached isolate

    local function subscribeEvent(event: string, system: string, attachedop: runtime.StateOp?) 
        eventrefmu.call(function() 
            eventRefManager.Subscribe(event, system, attachedop)
            return nil
        end)
    end

    local function unsubscribeEvent(event: string, system: string) 
        eventrefmu.call(function() 
            eventRefManager.Unsubscribe(event, system)
            return nil
        end)
    end

    local function isSubscribed(event: string, system: string): boolean 
        return eventrefmu.call(function() 
            return eventRefManager.IsSubscribed(event, system)
        end)
    end

    local function dispatchEvent(event: Primitives.Event, targetId: string?): {isolate.DispatchResult}
        if attachedisolatescount == 0 then return {} end -- unlikely but could happen

        -- Fast path: if there are no attached isolates besides builtins, we can avoid creating a new thread
        debugmanager.print("[TemplateLoopManager] Dispatching event", event.name, "to ", targetId and `with id {targetId}` or "with no target id")
        if attachedisolatescount == 1 then
            local _, isol = next(attachedisolates)
            assert(isol)
            if targetId and isol.id ~= targetId then return {} end -- Ignore non-targetted template
            local ret = isol.runEventResult(baseCtx, event)
            if ret.type == "err" then 
                debugmanager.print("[TemplateLoopManager] Error dispatching event to builtins template:", ret)
                return {ret}
            end
            return {ret}
        end
        
        local chan: channel.Stream<isolate.DispatchResult> = channel.Stream<<isolate.DispatchResult>>()
        local numitems = 0
        for _, isol in attachedisolates do
            if targetId and isol.id ~= targetId then
                continue -- Ignore non-targetted template
            end

            -- Dispatch event to isolate
            isol.dispatchEvent(baseCtx, event, chan)
            numitems += 1
        end

        local results, timedout = chan.rx:recvbatch(numitems, TEMPLATE_DISPATCH_TIMEOUT)
        if timedout == "timeout" then
            -- TODO: Log warning about timeout
        end
        return results
    end

    local function attachisolate(isolate: isolate.Isolate) 
        if isolate.id == "builtins" then error("cannot modify protected isolate `builtins`") end
        if attachedisolates[isolate.id] then 
            attachedisolates[isolate.id] = isolate
        else
            attachedisolates[isolate.id] = isolate 
            attachedisolatescount += 1
        end
    end

    local function detachisolate(id: string) 
        if id == "builtins" then error("cannot modify protected isolate `builtins`") end
        if not attachedisolates[id] then return end -- no op if not already attached
        attachedisolates[id] = nil 
        attachedisolatescount -= 1
    end

    self.debugmanager = debugmanager
    self.btd = btd
    self.discord = discord
    self.subscribeEvent = subscribeEvent
    self.unsubscribeEvent = unsubscribeEvent
    self.isSubscribed = isSubscribed
    self.dispatchEvent = dispatchEvent
    self.attachisolate = attachisolate
    self.detachisolate = detachisolate

    return self
end)

--- Creates a new TemplateLoopManager instance if it doesn't already exist, otherwise creates one
local function TemplateLoopManager(baseCtx: Primitives.TemplateContext, ts: runtime.TenantState, btd: runtime.BaseTenantData): templateloopImpl.TemplateLoopManager
    local existing = baseCtx.store[templateloopImpl.TEMPLATE_LOOP_KEY] :: templateloopImpl.TemplateLoopManager?
    if existing then return existing end
    return lazyloader.get({ ctx = baseCtx, ts = ts, btd = btd }) -- The lazyloader autosets the value into the store automatically
end

return TemplateLoopManager