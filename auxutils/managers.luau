local stingmanager = require"./stingmanager" 
local afkmanager = require"./afkmanager"
local Primitives = require"@antiraid-core/primitives"
-- local isDevMode = require"../devs".isInDevMode

-- local scopePrefix = if isDevMode then "builtins-dev" else "builtins"

export type Managers = {
    stingmanager: stingmanager.StingManager,
    afkmanager: afkmanager.AFKManager,
}

local managers: Managers? = nil

--- Gets or initializes the built-in managers
local function getmanagers(ctx: Primitives.TemplateContext): Managers
    if managers then return managers end

    local afkmanager = afkmanager(ctx)
    local stingmanager = stingmanager(ctx)

    managers = {
        stingmanager = stingmanager,
        afkmanager = afkmanager,
    }

    return managers or error("Failed to initialize managers")
end

return {
    getmanagers = getmanagers,
}