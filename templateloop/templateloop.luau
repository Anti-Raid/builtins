-- Experimental in-luau implementation of event dispatching to templates based on event scopes
local Primitives = require"@antiraid-core/primitives"
local runtime = require"@antiraid-core/plugins/runtime"
local isolate = require"./isolate"
local channel = require"@antiraid/channel"
local datetime = require"@antiraid/datetime"
local templateloopImpl = require"@antiraid-core/templateloop"

local FLAG_FETCH_TEMPLATES_FROM_DB = bit32.lshift(1, 1)
local TEMPLATE_DISPATCH_TIMEOUT = datetime.timedelta_seconds(5) -- 5 seconds

--- Helper to check if a bitset has a flag
local function bitsetHasFlag(bitset: number, flag: number): boolean
    return bit32.band(bitset, flag) == flag
end

local function TemplateLoopManager(baseCtx: Primitives.TemplateContext): templateloopImpl.TemplateLoopManager
    local self = {}
    local tenantState: runtime.TenantState = baseCtx.Runtime:gettenantstate()
    local templateCache: {runtime.Template} = if bitsetHasFlag(tenantState.flags, FLAG_FETCH_TEMPLATES_FROM_DB) then baseCtx.Runtime:listtemplates() else {baseCtx.Runtime:builtintemplate()}
    local isolates: {[string]: isolate.Isolate} = {}

    local function updateTemplateCache(id: string): {templateloopImpl.DispatchResult} 
        templateCache = baseCtx.Runtime:listtemplates() -- Always refetch new template cache just to ensure we are up to date with any updates we missed
        isolates[id] = nil -- Drop the isolate and let Luau GC it as it pleases
        
        -- Now update flags to toggle/clear FLAG_FETCH_TEMPLATES_FROM_DB accordingly
        --
        -- Note that builtins counts as a template, so we check for > 1 and not > 0
        if #templateCache > 1 and not bitsetHasFlag(tenantState.flags, FLAG_FETCH_TEMPLATES_FROM_DB) then 
            --- If we are in the no fetch from db state, update tenant state to record that we now need to fetch templates
            --- when we need to
            tenantState.flags = bit32.bor(tenantState.flags, FLAG_FETCH_TEMPLATES_FROM_DB)
            baseCtx.Runtime:settenantstate(tenantState)
        elseif #templateCache <= 1 and bitsetHasFlag(tenantState.flags, FLAG_FETCH_TEMPLATES_FROM_DB) then 
            --- Otherwise, we need to clear the fetch from db flag
            tenantState.flags = bit32.band(tenantState.flags, bit32.bnot(FLAG_FETCH_TEMPLATES_FROM_DB))
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
    local function _getIsolateForTemplate(template: runtime.Template): isolate.Isolate
        local isol: isolate.Isolate? = nil
        if isolates[template.id] then 
            isol = isolates[template.id] 
        else 
            isol = isolate.new(template.id, template.allowed_caps, template.vfs, {})
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

    -- Dispatch startup events to all templates initially
    --task.spawn(dispatchEvent, baseCtx, {name = "OnStartup", data = { reason = "initialization" }}, nil)

    self.updateTemplateCache = updateTemplateCache
    self.getTenantState = getTenantState
    self.setTenantState = setTenantState
    self.dispatchEvent = dispatchEvent

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