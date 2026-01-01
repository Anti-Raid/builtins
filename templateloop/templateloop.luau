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

local TEMPLATE_DISPATCH_TIMEOUT = datetime.timedelta_seconds(5) -- 5 seconds
local MAX_KEYEXPIRY_KEY_LENGTH = 36

type Prop = "builtins_havetemplates" | "builtins_eventrefs" | "builtins_kex"
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

--- A key expiry manager. This is internal to templateloop
local function KeyExpiryManager(baseCtx: Primitives.TemplateContext, loop: templateloopImpl.WipTemplateLoopManager, tenantState: runtime.TenantState)
    assert(loop.__wip, "Passing `self` directly to KeyExpiryManager and not a custom table type while in the process of construction")
    
    local kexs = _getTenantStateProp(tenantState, "builtins_kex") or {} :: {[string]: number}
    local handles: {[string]: channel.KeyHandle<string>} = {}
    local delayqueue = channel.DelayChannel() :: channel.DelayChannel<string> -- Delayqueue stores a queue of all the kvs we need to dispatch
    local th: thread? = nil

    local function _loop() 
        while true do 
            local item = delayqueue:next()

            -- Dispatch event to templates
            local ok, res = xpcall(loop.dispatchEvent, debug.traceback :: any, baseCtx, {name = "KeyExpiry", data = { key = item }, author = nil}, nil)

            if not ok then 
                -- Dispatch a error event
                task.spawn(function() 
                    pcall(loop.dispatchEvent, baseCtx, {name = "Error", data = { context = "keyexpiry", key = item, error = res }, author = nil}, nil)
                end)
            end

            -- Remove the event
            handles[item] = nil
            kexs[item] = nil
            _setTenantStateProp(tenantState, "builtins_kex", kexs)
            if next(kexs) == nil and #delayqueue then 
                loop.unsubscribeEvent("OnStartup", "__kex", true) -- No more key expiries, unsubscribe but dont save yet
            end
            baseCtx.Runtime:settenantstate(tenantState)
        end
    end

    local function _loopwhile() 
        while true do pcall(_loop) end -- TODO: Support error reporting, somehow
    end

    --- Helper method to ensure the loop is running
    local function _ensureLoopRunning()
        if not th or coroutine.status(th) == "dead" then th = task.spawn(_loopwhile) end
    end

    local function add(key: string, expiresin: datetime.TimeDelta)
        -- Validate inputs 
        if #key > MAX_KEYEXPIRY_KEY_LENGTH then 
            error(`KeyExpiry key length exceeds maximum length of {MAX_KEYEXPIRY_KEY_LENGTH}`)
        end
        if kexs[key] then 
            error(`KeyExpiry with id \`{key}\` already exists`)
        end

        -- Record in tenant state
        local expiresat = (datetime.UTC:now() + expiresin)
        kexs[key] = expiresat.timestamp_seconds
        _setTenantStateProp(tenantState, "builtins_kex", kexs)
        loop.subscribeEvent("OnStartup", "__kex", true) -- We want nosave here as we have a settenantstate later
        baseCtx.Runtime:settenantstate(tenantState)

        -- Check if we've already expired either due to initial input or due to tenant state record times
        if expiresat <= datetime.UTC:now() then 
            -- Already expired, add with a random delay of 1-6s instead
            expiresat = datetime.UTC:now() + datetime.timedelta_seconds((math.random() * 5) + 1)
        end

        handles[key] = delayqueue:addwithhandle(key, expiresat:duration_since(datetime.UTC:now()))
        _ensureLoopRunning()
    end

    local function remove(id: string) 
        local handle = handles[id]
        if handle then 
            handle:cancel() -- Cancel the handle
            handles[id] = nil
        end
        if kexs[id] then -- Remove from tenant state
            kexs[id] = nil
            _setTenantStateProp(tenantState, "builtins_kex", kexs)
            if next(kexs) == nil and #delayqueue then 
                loop.unsubscribeEvent("OnStartup", "__kex", true) -- No more key expiries, unsubscribe but dont save yet
            end
            baseCtx.Runtime:settenantstate(tenantState)
        end
    end

    local function exists(id: string): boolean 
        return kexs[id] ~= nil
    end

    -- Sync if needed
    if next(kexs) then
        task.spawn(function() 
            -- Setup delayqueue
            _ensureLoopRunning()
            for key, expiryepoch in kexs do
                local expiry = datetime.UTC:fromTime(expiryepoch)
                if expiry <= datetime.UTC:now() then 
                    -- Already expired, add with a random delay > 20 seconds to avoid thundering herd
                    expiry = datetime.UTC:now() + datetime.timedelta_seconds(20 + math.random(5, 120))
                end
                handles[key] = delayqueue:addwithhandle(key, expiry:duration_since(datetime.UTC:now()))
            end
        end)
    end

    return table.freeze{
        add = add,
        remove = remove,
        exists = exists
    }
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

        -- GC any leftover isolates that are no longer active
        local activeIds = {}
        for _, t in templateCache do activeIds[t.id] = true end
        for isolId, _ in isolates do 
            if not activeIds[isolId] then isolates[isolId] = nil end
        end
        
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

    local function subscribeEvent(event: string, system: string, nosave: boolean?) 
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
        if not nosave then baseCtx.Runtime:settenantstate(tenantState) end
    end

    local function unsubscribeEvent(event: string, system: string, nosave: boolean?) 
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
            if not nosave then baseCtx.Runtime:settenantstate(tenantState) end
        end
    end

    -- Dispatch startup events to all templates initially
    --task.spawn(dispatchEvent, baseCtx, {name = "OnStartup", data = { reason = "initialization" }}, nil)

    self.updateTemplateCache = updateTemplateCache
    self.dispatchEvent = dispatchEvent
    self.subscribeEvent = subscribeEvent
    self.unsubscribeEvent = unsubscribeEvent

    self.keyExpiryManager = KeyExpiryManager(baseCtx, {
        __wip = true,
        dispatchEvent = dispatchEvent,
        subscribeEvent = subscribeEvent,
        unsubscribeEvent = unsubscribeEvent,
    }, tenantState)

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