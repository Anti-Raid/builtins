--- Experimental in-luau implementation of event dispatching to templates based on event scopes
---
--- Tenant state data:
--- - builtins_havetemplates: whether or not the tenant has any custom templates to fetch from the DB
--- - builtins_eventrefs: a dictionary of event name to refcount, used for event subscriptions
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
local isolate = require"./isolate"
local channel = require"@antiraid/channel"
local datetime = require"@antiraid/datetime"
local templateloopImpl = require"@antiraid-core/templateloop"
local templatemanagerImpl = require"@antiraid-core/templatemanager"
local TemplateManager = require"./templatemanager"
local MutexFn = require"@antiraid-ext/sync/mutex"

-- Flags 

--- Tenant state flag: Whether or not we have any custom templates that require fetching from the DB
local FLAG_BUILTINS_HAVETEMPLATES = bit32.lshift(1, 0) 
--- Tenant state flag: Whether or not we have any event refs for any events (used to determine whether we need to fetch eventrefs from the DB or not)
local FLAG_BUILTINS_HAVEEVENTREFS = bit32.lshift(1, 1)

-- Other constants

--- How long to wait for template dispatch results before timing out and moving on (to avoid hanging the entire dispatch if a template is hanging)
local TEMPLATE_DISPATCH_TIMEOUT = datetime.timedelta_seconds(5) -- 5 seconds

-- Start code

--- Internal manager of tenant state
type TenantStateManager = {
    --- Returns if a flag is set or not
    read IsFlagSet: (flag: number) -> boolean,
    --- Returns if we have subscribed to an event or not
    read IsSubscribedToEvent: (event: string) -> boolean,
    --- Returns a clone of the current tenant state
    read ClonedTenantState: () -> runtime.TenantState,
    --- Update the cached tenant state to the provided state
    read UpdateTenantState: (newState: runtime.TenantState) -> (),
    --- Helper method to set/unset a flag in the tenant state flags field
    ---
    --- Does nothing if the flag is already in the desired state
    read SetFlag: (flag: number, set: boolean) -> (),
    --- Helper method to subscribe to an event and update tenant state accordingly
    ---
    --- Does nothing if already subscribed (or unsubscribed in the case of set = false)
    read SubscribeEvent: (event: string, set: boolean) -> (),
    --- Helper method to both subscribe/unsubscribe to an event and set/unset a flag in tenant state if needed
    --- 
    --- Does nothing if we are already in the desired state
    read SubscribeEventAndSetFlag: (event: string, setevent: boolean, flag: number, setflag: boolean) -> (),
}

local function TenantStateManager(baseCtx: Primitives.TemplateContext): TenantStateManager
    local tenantState: runtime.TenantState = baseCtx.Runtime:gettenantstate()
    if _G._debug then _G._debug("TenantStateManager init - events:", tenantState.events, "type:", type(tenantState.events), "banned:", tenantState.banned, "flags:", tenantState.flags) end
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
        if _G._debug then _G._debug("ClonedTenantState - events:", tenantState.events, "type:", type(tenantState.events)) end
        return {
            events = table.clone(tenantState.events),
            banned = tenantState.banned,
            flags = tenantState.flags,
        }
    end

    local function UpdateTenantState(newState: runtime.TenantState)
        if _G._debug then _G._debug("UpdateTenantState - newState:", newState, "events:", newState and newState.events, "banned:", newState and newState.banned, "flags:", newState and newState.flags) end
        baseCtx.Runtime:settenantstate(newState) -- Update tenant state in runtime
        tenantState = newState -- Update local cache
        _updateDerivedState() -- Update derived state after updating tenant state
    end

    local function SetFlag(flag: number, set: boolean) 
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
        UpdateTenantState(ts)
    end

    local function SubscribeEvent(event: string, set: boolean) 
        if set then 
            if not events[event] then 
                local ts = ClonedTenantState()
                table.insert(ts.events, event)
                UpdateTenantState(ts)
            end
        else 
            if events[event] then 
                local ts = ClonedTenantState()
                local idx = table.find(ts.events, event)
                if idx then 
                    table.remove(ts.events, idx)
                    UpdateTenantState(ts)
                end
            end
        end
    end

    local function SubscribeEventAndSetFlag(event: string, setevent: boolean, flag: number, setflag: boolean) 
        local eventMatches = IsSubscribedToEvent(event) == setevent
        local flagMatches = IsFlagSet(flag) == setflag
        if eventMatches and flagMatches then 
            return -- No update needed
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

        UpdateTenantState(ts)
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
    read Subscribe: (event: string, system: string) -> (),
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
            local refs = baseCtx.KV:getrecord("eventrefs", {"tloop.reserved"})
            if refs.exists then 
                -- Cache and return event refs after basic validation
                assert(type(refs.value) == "table", "Invalid event refs data in tenant state, expected table")
                local ref =  refs.value :: {[string]: {[string]: boolean}}
                eventrefs = ref
                return ref
            else
                -- Unset event refs flag if we don't have any refs to load yet had the flag set
                tenantStateManager.SetFlag(FLAG_BUILTINS_HAVEEVENTREFS, false) 
                return {}
            end
        end
        return eventrefs
    end

    --- Internal helper to update event refs in cache
    local function updateeventrefs(refs: {[string]: {[string]: boolean}}) 
        baseCtx.KV:set("eventrefs", refs, {"tloop.reserved"})
        eventrefs = refs
    end

    local function IsSubscribed(event: string, system: string): boolean 
        local refs = geteventrefs()
        return refs[event] ~= nil and refs[event][system] ~= nil
    end

    local function Subscribe(event: string, system: string) 
        if IsSubscribed(event, system) then return end -- No need to subscribe if we are already subscribed
        local refs = geteventrefs()
        if refs[event] then refs[event][system] = true else refs[event] = { [system] = true } end -- Update refs with new subscription
        
        -- Update event refs
        updateeventrefs(refs)
        
        -- Also subscribe to event in tenant state manager to ensure we are subscribed at the runtime level
        --
        -- This is anyways a no-op if we are already subscribed, so we don't need to check before subscribing
        tenantStateManager.SubscribeEventAndSetFlag(event, true, FLAG_BUILTINS_HAVEEVENTREFS, true)
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

        -- Update event refs
        updateeventrefs(refs)
        
        local isEventStillActive = (refs[event] ~= nil)
        local hasAnyRefsRemaining = (next(refs) ~= nil)

        -- Pass the dynamically calculated states to the manager
        tenantStateManager.SubscribeEventAndSetFlag(
            event, 
            isEventStillActive, 
            FLAG_BUILTINS_HAVEEVENTREFS, 
            hasAnyRefsRemaining
        )
    end

    return table.freeze{
        Subscribe = Subscribe,
        Unsubscribe = Unsubscribe,
        IsSubscribed = IsSubscribed,
    }
end

-- stdout logging for debugging
local function DebugManager(): templateloopImpl.DebugManager 
    if _G._debug then return { print = _G._debug } end
    return { print = function(...) end }
end

local function TemplateLoopManager(baseCtx: Primitives.TemplateContext): templateloopImpl.TemplateLoopManager
    local self = {}

    local debugmanager = DebugManager()
    local templatemanager = TemplateManager(baseCtx)
    local tenantStateManager = TenantStateManager(baseCtx)
    local eventRefManager = EventRefManager(baseCtx, tenantStateManager)
    local eventrefmu = MutexFn() -- Mutex for synchronizing access to event refs

    local templateCache: {templatemanagerImpl.Template} = if tenantStateManager.IsFlagSet(FLAG_BUILTINS_HAVETEMPLATES) then templatemanager.list() else {templatemanager.builtins()}
    local isolates: {[string]: isolate.Isolate} = {}

    local function updateTemplateCache(id: string): {templateloopImpl.DispatchResult} 
        templateCache = templatemanager.list() -- Always refetch new template cache just to ensure we are up to date with any updates we missed
        isolates[id] = nil -- Drop the isolate and let Luau GC it as it pleases

        -- GC any leftover isolates that are no longer active
        local activeIds = {}
        for _, t in templateCache do activeIds[t.id] = true end
        for isolId, _ in isolates do 
            if not activeIds[isolId] then isolates[isolId] = nil end
        end
        
        -- Now update tenant state data to reflect whether we need to fetch templates from DB or not
        --
        -- Note that builtins counts as a template, so we check for > 1 and not > 0
        if #templateCache > 1 and not tenantStateManager.IsFlagSet(FLAG_BUILTINS_HAVETEMPLATES) then 
            --- If we are in the no fetch from db state, update tenant state to record that we now need to fetch templates
            --- when we need to
            tenantStateManager.SetFlag(FLAG_BUILTINS_HAVETEMPLATES, true)
        elseif #templateCache <= 1 and tenantStateManager.IsFlagSet(FLAG_BUILTINS_HAVETEMPLATES) then 
            --- Otherwise, we need to clear the fetch from db flag if we are in the fetch from db state
            tenantStateManager.SetFlag(FLAG_BUILTINS_HAVETEMPLATES, false)
        end

        -- Send a Startup event to the template to re-initialize it
        return self.dispatchEvent({name = "OnStartup", data = { reason = "updateTemplateCache" }}, id)
    end

    --- Internal helper to get or create an isolate for a template
    local function _getIsolateForTemplate(template: templatemanagerImpl.Template): isolate.Isolate
        local isol: isolate.Isolate? = nil
        if isolates[template.id] then 
            isol = isolates[template.id] 
        else 
            isol = isolate.new(template.id, template.allowed_caps, templatemanager.computevfs(template), {})
            isolates[template.id] = isol -- Cache isolate
        end
        return isol
    end

    local function dispatchEvent(event: Primitives.Event, targetId: string?): {templateloopImpl.DispatchResult}
        -- Fast path: if there are no templates besides builtins, we can avoid creating a new thread
        debugmanager.print("[TemplateLoopManager] Dispatching event", event.name, "to templates", targetId and `with id {targetId}` or "with no target id")
        if #templateCache <= 1 and templateCache[1] and templateCache[1].source.type == "builtins" then
            -- Get or create isolate for template
            local isol = _getIsolateForTemplate(templateCache[1])
            local ret = isol.runEventResult(baseCtx, event)
            if ret.type == "err" then 
                debugmanager.print("[TemplateLoopManager] Error dispatching event to builtins template:", ret)
                return {ret}
            end
            return {ret}
        end
        
        local chans: {channel.OneshotChannel<templateloopImpl.DispatchResult>} = {}

        for _, template in templateCache do
            if targetId and template.id ~= targetId then
                continue -- Ignore non-targetted template
            end

            -- Get or create isolate for template
            local isol = _getIsolateForTemplate(template)

            -- Dispatch event to isolate
            local chan = isol.dispatchEvent(baseCtx, event)
            table.insert(chans, chan)
        end

        local results, timedout = channel.selectoneshots(chans, TEMPLATE_DISPATCH_TIMEOUT)
        if timedout then
            -- TODO: Log warning about timeout
        end
        return results
    end

    local function subscribeEvent(event: string, system: string) 
        eventrefmu.call(function() 
            eventRefManager.Subscribe(event, system)
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

    self.updateTemplateCache = updateTemplateCache
    self.dispatchEvent = dispatchEvent
    self.subscribeEvent = subscribeEvent
    self.unsubscribeEvent = unsubscribeEvent
    self.isSubscribed = isSubscribed
    self.debugmanager = debugmanager

    return self
end

--- Creates a new TemplateLoopManager instance if it doesn't already exist, otherwise creates one
local function getOrInit(ctx: Primitives.TemplateContext): templateloopImpl.TemplateLoopManager
    local tlm = ctx.store[templateloopImpl.TEMPLATE_LOOP_KEY] :: templateloopImpl.TemplateLoopManager?
    if not tlm then 
        tlm = TemplateLoopManager(ctx)
        ctx.store[templateloopImpl.TEMPLATE_LOOP_KEY] = tlm
        return tlm
    end
    return tlm
end 

return {
    TemplateLoopManager = TemplateLoopManager,
    getOrInit = getOrInit,
}