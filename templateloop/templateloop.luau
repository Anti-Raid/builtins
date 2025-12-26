-- Experimental in-luau implementation of event dispatching to templates based on event scopes
local Primitives = require"@antiraid-core/primitives"
local runtime = require"@antiraid-core/plugins/runtime"
local isolate = require"./isolate"
local channel = require"@antiraid/channel"
local datetime = require"@antiraid/datetime"

local FLAG_FETCH_TEMPLATES_FROM_DB = bit32.lshift(1, 1)
local TEMPLATE_DISPATCH_TIMEOUT = datetime.timedelta_seconds(5000) -- 5 seconds
local TEMPLATE_LOOP_KEY = "__antiraid-builtins-templateloop"

--- Helper to check if a bitset has a flag
local function bitsetHasFlag(bitset: number, flag: number): boolean
    return bit32.band(bitset, flag) == flag
end

--- A manager that handles template loops for a tenant
export type TemplateLoopManager = {
    --- Update the template cache due to a modification of a template with the provided `id`.
    ---
    --- Returns the result from the templates startup code.
    updateTemplateCache: (id: string) -> {isolate.IsolateResult},
    --- Dispatch an event to all cached templates, returning the result as desired
    ---
    --- If `event` is passed, the sub-context created for each template will have the event set to it.
    ---
    --- If `targetId` is passed, the event will only be sent to the targetted id
    dispatchEvent: (ctx: Primitives.TemplateContext, event: Primitives.Event?, targetId: string?) -> {isolate.IsolateResult}
}

local function TemplateLoopManager(baseCtx: Primitives.TemplateContext): TemplateLoopManager
    local self = {}
    local tenantState: runtime.TenantState = baseCtx.Runtime:gettenantstate()
    local templateCache: {runtime.Template} = if bitsetHasFlag(tenantState.flags, FLAG_FETCH_TEMPLATES_FROM_DB) then baseCtx.Runtime:listtemplates() else {}
    local isolates: {[string]: isolate.Isolate} = {}

    local function updateTemplateCache(id: string): {isolate.IsolateResult} 
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

    local function dispatchEvent(ctx: Primitives.TemplateContext, event: Primitives.Event?, targetId: string?): {isolate.IsolateResult}
        local chans: {channel.OneshotChannel<isolate.IsolateResult>} = {}
        for _, template in templateCache do
            if targetId and template.id ~= targetId then
                continue -- Ignore non-targetted template
            end

            -- Get or create isolate for template
            local isol: isolate.Isolate? = nil
            if isolates[template.id] then 
                isol = isolates[template.id] 
            else 
                isol = isolate.new(template.id, template.allowed_caps, template.vfs, {})
                isolates[template.id] = isol -- Cache isolate
            end

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
    task.spawn(dispatchEvent, baseCtx, {name = "OnStartup", data = { reason = "initialization" }}, nil)

    self.updateTemplateCache = updateTemplateCache
    self.dispatchEvent = dispatchEvent

    return self
end

--- Creates a new TemplateLoopManager instance if it doesn't already exist, otherwise creates one
local function getOrInit(ctx: Primitives.TemplateContext): TemplateLoopManager
    local tlm = ctx.store[TEMPLATE_LOOP_KEY] :: TemplateLoopManager?
    if not tlm then 
        tlm = TemplateLoopManager(ctx)
        ctx.store[TEMPLATE_LOOP_KEY] = tlm
        return tlm
    end
    return tlm
end 

return {
    TemplateLoopManager = TemplateLoopManager,
    getOrInit = getOrInit,
}