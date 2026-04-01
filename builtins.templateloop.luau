--!strict

--- Builtins internal template dispatch code for AntiRaid (heavy work in progress)
---
--- Note that this is INTERNAL and specific to how AntiRaid dispatches out to templates
---
--- Do not expect this to work outside of init

local templateloop = require "./templateloop/templateloop"
local Primitives = require"@antiraid-core/primitives"
local runtime = require"@antiraid-core/plugins/runtime"

local function main(ctx: Primitives.TemplateContext, ts: runtime.TenantState, btd: runtime.BaseTenantData) 
    local function dispatch(evt: Primitives.Event) 
        local tlm = templateloop(ctx, ts, btd) -- Get or create the TemplateLoopManager instance 
        return tlm.dispatchEvent(evt)
    end

    return dispatch
end

return main