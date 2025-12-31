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
local kv = require "@antiraid-core/plugins/kv"
local TemplateManager = require"./templatemanager"
local settingsext = require "@antiraid-ext/settings"

local TEMPLATE_DISPATCH_TIMEOUT = datetime.timedelta_seconds(5) -- 5 seconds

type Prop = "builtins_havetemplates" | "builtins_eventrefs" | "builtins_loadkex"
local function _getTenantStateProp(tenantState: runtime.TenantState, prop: Prop): any
    if type(tenantState.data) == "table" then 
        return tenantState.data[prop]
    else 
        return nil
    end
end

local function _setTenantStateProp(tenantState: runtime.TenantState, prop: Prop, value: any) 
    if type(tenantState.data) ~= "table" then 
        tenantState.data = {
            [prop] = value,
        }
    else
        tenantState.data[prop] = value
    end
end

local function TemplateLoopManager(baseCtx: Primitives.TemplateContext): templateloopImpl.TemplateLoopManager
    local self = {}

    local templatemanager = TemplateManager(baseCtx)
    local tenantState: runtime.TenantState = baseCtx.Runtime:gettenantstate()

    local templateCache: {templatemanagerImpl.Template} = if _getTenantStateProp(tenantState, "builtins_havetemplates") then templatemanager.list() else {templatemanager.builtins()}
    local isolates: {[string]: isolate.Isolate} = {}
    local eventRefs: {[string]: {[string]: boolean}} = _getTenantStateProp(tenantState, "builtins_eventrefs") or {}
    
    local function updateTemplateCache(id: string): {templateloopImpl.DispatchResult} 
        templateCache = templatemanager.list() -- Always refetch new template cache just to ensure we are up to date with any updates we missed
        isolates[id] = nil -- Drop the isolate and let Luau GC it as it pleases
        
        -- Now update tenant state data to reflect whether we need to fetch templates from DB or not
        --
        -- Note that builtins counts as a template, so we check for > 1 and not > 0
        if #templateCache > 1 and not _getTenantStateProp(tenantState, "builtins_havetemplates") then 
            --- If we are in the no fetch from db state, update tenant state to record that we now need to fetch templates
            --- when we need to
            _setTenantStateProp(tenantState, "builtins_havetemplates", true)
            baseCtx.Runtime:settenantstate(tenantState)
        elseif #templateCache <= 1 and _getTenantStateProp(tenantState, "builtins_havetemplates") then 
            --- Otherwise, we need to clear the fetch from db flag if we are in the fetch from db state
            _setTenantStateProp(tenantState, "builtins_havetemplates", nil)
            baseCtx.Runtime:settenantstate(tenantState)
        end

        -- Send a Startup event to the template to re-initialize it
        return self.dispatchEvent(baseCtx, {name = "OnStartup", data = { reason = "updateTemplateCache" }}, id)
    end

    local function getTenantState() 
        return tenantState
    end

    local function setTenantState(ts: runtime.TenantState) 
        tenantState = ts
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

    local function dispatchEvent(ctx: Primitives.TemplateContext, event: Primitives.Event?, targetId: string?): {templateloopImpl.DispatchResult}
        -- Fast path: if there are no templates besides builtins, we can avoid creating a new thread
        if #templateCache <= 1 and templateCache[1] and templateCache[1].source.type == "builtins" then
            -- Get or create isolate for template
            local isol = _getIsolateForTemplate(templateCache[1])
            local ret = isol.runEventResult(ctx, event)
            if ret.type == "err" then error(ret.value) end
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
            local chan = isol.dispatchEvent(ctx, event)
            table.insert(chans, chan)
        end

        local results, timedout = channel.selectoneshots(chans, TEMPLATE_DISPATCH_TIMEOUT)
        if timedout then
            -- TODO: Log warning about timeout
        end
        return results
    end

    local function subscribeEvent(event: string, system: string) 
        -- Ensure event is in tenant state events
        if not table.find(tenantState.events, event) then 
            table.insert(tenantState.events, event)
        end

        -- Update refcount
        if eventRefs[event] then eventRefs[event][system] = true
        else 
            eventRefs[event] = { [system] = true }
        end
        _setTenantStateProp(tenantState, "builtins_eventrefs", eventRefs)
        baseCtx.Runtime:settenantstate(tenantState)
    end

    local function unsubscribeEvent(event: string, system: string) 
        if eventRefs[event] and eventRefs[event][system] then 
            eventRefs[event][system] = nil
            -- Check if we have any more refs for this event
            if not next(eventRefs[event]) then
                -- No more refs, drop event
                eventRefs[event] = nil
                local idx = table.find(tenantState.events, event)
                if idx then 
                    table.remove(tenantState.events, idx)  
                end
            end
            _setTenantStateProp(tenantState, "builtins_eventrefs", eventRefs)
            baseCtx.Runtime:settenantstate(tenantState)
        end
    end

    -- Dispatch startup events to all templates initially
    --task.spawn(dispatchEvent, baseCtx, {name = "OnStartup", data = { reason = "initialization" }}, nil)

    self.updateTemplateCache = updateTemplateCache
    self.getTenantState = getTenantState
    self.setTenantState = setTenantState
    self.dispatchEvent = dispatchEvent
    self.subscribeEvent = subscribeEvent
    self.unsubscribeEvent = unsubscribeEvent

    return self
end

type KeyExpiryItem = {
    id: string,
    eventName: string,
    expiresat: datetime.DateTime,
    data: any
}

--- A key expiry manager. This is internal to templateloop
local function KeyExpiryManager(baseCtx: Primitives.TemplateContext, loop: templateloopImpl.TemplateLoopManager, tenantState: runtime.TenantState)
    local self = {}

    local function _parseKeyExpiryItem(data: kv.KvRecord): KeyExpiryItem
        assert(data.exists, "Internal error: Key expiry item does not exist")
        local eventName = settingsext.assertString("eventname", data.value.eventname)
        local expi = data.value.expiresat
        assert(type(expi) == "userdata" and expi.seconds, "Internal error: Key expiry expiresat is not userdata") -- todo: improve this
        local eventData = data.value.data

        return {
            id = data.id,
            eventName = eventName,
            data = eventData,
            expiresat = expi :: datetime.DateTime,
        }
    end

    local function _loop(delayqueue: channel.DelayChannel<KeyExpiryItem>) 
        while true do 
            local item = delayqueue:next()

            -- Dispatch event to templates
            loop.dispatchEvent(baseCtx, {name = item.eventName, data = item.data}, nil)

            -- Remove from KV store
            baseCtx.KV:deletebyid(item.id)
        end
    end

    local delayqueue = channel.DelayChannel() :: channel.DelayChannel<KeyExpiryItem>
    local th: thread? = nil

    if _getTenantStateProp(tenantState, "builtins_loadkex") then
        local recs = baseCtx.KV:find("%%", {"__kex"})
        for _, rec in recs do
            local ok, item = pcall(_parseKeyExpiryItem, rec)
            if ok then
                delayqueue:add(item, item.expiresat:duration_since(datetime.UTC:now()))
            end
        end

        -- Spawn task to process key expiries
        th = task.spawn(function() 
            _loop(delayqueue)
        end)
    end

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