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

--- Internal manager of tenant state
type TenantStateManager = {
    --- Returns if a flag is set or not
    read IsFlagSet: (flag: number) -> boolean,
    --- Returns if we have subscribed to an event or not
    read IsSubscribedToEvent: (event: string) -> boolean,
    --- Returns a clone of the current tenant state
    read ClonedTenantState: () -> runtime.TenantState,
    --- Update the cached tenant state to the provided state
    read UpdateTenantState: (newState: runtime.TenantState, with: {runtime.StateOp}) -> (),
    --- Helper method to set/unset a flag in the tenant state flags field
    ---
    --- Does nothing if the flag is already in the desired state
    read SetFlag: (flag: number, set: boolean, with: {runtime.StateOp}) -> (),
    --- Helper method to subscribe to an event and update tenant state accordingly
    ---
    --- Does nothing if already subscribed (or unsubscribed in the case of set = false)
    read SubscribeEvent: (event: string, set: boolean, with: {runtime.StateOp}) -> (),
    --- Helper method to both subscribe/unsubscribe to an event and set/unset a flag in tenant state if needed
    --- 
    --- Does nothing if we are already in the desired state returning true if we updated at all
    read SubscribeEventAndSetFlag: (event: string, setevent: boolean, flag: number, setflag: boolean, with: {runtime.StateOp}) -> boolean,
}

local function TenantStateManager(baseCtx: Primitives.TemplateContext, tenantState: runtime.TenantState): TenantStateManager
    DebugManager().print("TenantStateManager init - events:", tenantState.events, "type:", type(tenantState.events), "flags:", tenantState.flags)
    local events: {[string]: boolean} = {}

    local function _updateDerivedState() 
        local levents: {[string]: boolean} = {}
        for _, event in tenantState.events do 
            levents[event] = true
        end
        levents = table.freeze(levents)
        events = levents
    end
    
    -- Update derived state initially
    _updateDerivedState()  

    -- Basic fetching utilities
    local function IsFlagSet(flag: number): boolean return bit32.band(tenantState.flags, flag) ~= 0 end
    local function IsSubscribedToEvent(event: string): boolean return events[event] ~= nil end

    -- Other utilities for managing tenant state
    local function ClonedTenantState(): runtime.TenantState
        --DebugManager().print("ClonedTenantState - events:", tenantState.events, "type:", type(tenantState.events))
        return {
            events = table.clone(tenantState.events),
            flags = tenantState.flags,
        }
    end

    local function UpdateTenantState(newState: runtime.TenantState, with: {runtime.StateOp})
        DebugManager().print("UpdateTenantState - newState:", newState, "events:", newState and newState.events, "flags:", newState and newState.flags)
        table.insert(with, { op = "UpdateTenantState" :: "UpdateTenantState", events = newState.events, flags = newState.flags })
        basectx:syscall({ op = "State", ops = with}) -- Update tenant state in runtime
        tenantState = newState -- Update local cache
        _updateDerivedState() -- Update derived state after updating tenant state
    end

    local function SetFlag(flag: number, set: boolean, with: {runtime.StateOp}) 
        -- Check if we need to update tenant state at all
        local hasFlag = bit32.band(tenantState.flags, flag) ~= 0
        if (set and hasFlag) or (not set and not hasFlag) then
            return -- No update needed
        end

        -- Update flag in tenant state and push update in clone (to ensure original isn't mutated until we push update)
        local ts = ClonedTenantState()
        if set then 
            ts.flags = bit32.bor(ts.flags, flag)
        else 
            ts.flags = bit32.band(ts.flags, bit32.bnot(flag))
        end
        UpdateTenantState(ts, with)
    end

    local function SubscribeEvent(event: string, set: boolean, with: {runtime.StateOp}) 
        if set then 
            if not events[event] then 
                local ts = ClonedTenantState()
                table.insert(ts.events, event)
                UpdateTenantState(ts, with)
            end
        else 
            if events[event] then 
                local ts = ClonedTenantState()
                local idx = table.find(ts.events, event)
                if idx then 
                    table.remove(ts.events, idx)
                    UpdateTenantState(ts, with)
                end
            end
        end
    end

    local function SubscribeEventAndSetFlag(event: string, setevent: boolean, flag: number, setflag: boolean, with: {runtime.StateOp}): boolean
        local eventMatches = IsSubscribedToEvent(event) == setevent
        local flagMatches = IsFlagSet(flag) == setflag
        if eventMatches and flagMatches then 
            return false -- No update needed
        end

        local ts = ClonedTenantState()
        if not eventMatches then 
            if setevent then 
                if not events[event] then 
                    table.insert(ts.events, event)
                end
            else 
                if events[event] then 
                    local idx = table.find(ts.events, event)
                    if idx then 
                        table.remove(ts.events, idx)
                    end
                end
            end
        end

        if not flagMatches then
            if setflag then 
                ts.flags = bit32.bor(ts.flags, flag)
            else 
                ts.flags = bit32.band(ts.flags, bit32.bnot(flag))
            end
        end

        UpdateTenantState(ts, with)
        return true
    end

    return table.freeze{
        IsFlagSet = IsFlagSet,
        IsSubscribedToEvent = IsSubscribedToEvent,
        ClonedTenantState = ClonedTenantState,
        UpdateTenantState = UpdateTenantState,
        SetFlag = SetFlag,
        SubscribeEvent = SubscribeEvent,
        SubscribeEventAndSetFlag = SubscribeEventAndSetFlag,
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
            local records = basectx:syscall({ op = "State", ops = ops })
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
                tenantStateManager.SetFlag(FLAG_BUILTINS_HAVEEVENTREFS, false, {}) 
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
            if attachedop then basectx:syscall({op="State", ops={attachedop}}) end
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
        local haveupdated = tenantStateManager.SubscribeEventAndSetFlag(
            event, 
            true, 
            FLAG_BUILTINS_HAVEEVENTREFS, 
            true, 
            ops
        )
        if not haveupdated then basectx:syscall({op="State", ops=ops}) end
        eventrefs = refs -- update event refs in cache
    end

    local function Unsubscribe(event: string, system: string) 
        if not IsSubscribed(event, system) then return end 
        local refs = geteventrefs()
        
        if refs[event] then 
            refs[event][system] = nil 
            if next(refs[event]) == nil then 
                refs[event] = nil 
            end 
        end
        
        local isEventStillActive = (refs[event] ~= nil)
        local hasAnyRefsRemaining = (next(refs) ~= nil)

        -- Pass the dynamically calculated states to the manager
        tenantStateManager.SubscribeEventAndSetFlag(
            event, 
            isEventStillActive, 
            FLAG_BUILTINS_HAVEEVENTREFS, 
            hasAnyRefsRemaining,
            {{ op = "KvSet", key = "eventrefs", scope = "tloop.reserved" }}
        )
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