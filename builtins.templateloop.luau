--- Builtins internal template dispatch code for AntiRaid (heavy work in progress)
---
--- Note that this is INTERNAL and specific to how AntiRaid gets builtin state (such as command info etc) from the builtins standard script
---
--- Do not expect this to work outside of builtins in specific

local templateloop = require "./templateloop/templateloop"
local ctx = ... 
local tlm = templateloop.getOrInit(ctx) -- Get or create the TemplateLoopManager instance 
return tlm.dispatchEvent(ctx)