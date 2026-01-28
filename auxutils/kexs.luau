local KeyExpiryManager = require"@antiraid-ext/keyexpirymanager"
local Primitives = require"@antiraid-core/primitives"
local isDevMode = require"../devs".isInDevMode

local scopePrefix = if isDevMode then "builtins-dev" else "builtins"

export type Managers = {
    tempbankex: KeyExpiryManager.KeyExpiryManager,
    remindmeexpiry: KeyExpiryManager.KeyExpiryManager,
    afkexpiry: KeyExpiryManager.KeyExpiryManager,
}

local managers: Managers? = nil

--- Gets or initializes the built-in managers
local function getmanagers(ctx: Primitives.TemplateContext): Managers
    if managers then return managers end

    local keyExpiryManager = KeyExpiryManager(ctx, scopePrefix..".tempbans", "BuiltinsTempBanExpiry")
    local remindmeExpiryManager = KeyExpiryManager(ctx, scopePrefix..".remindme", "BuiltinsRemindMeExpiry")
    local afkexpiryManager = KeyExpiryManager(ctx, scopePrefix..".afk", "BuiltinsAfkExpiry")

    managers = {
        tempbankex = keyExpiryManager,
        remindmeexpiry = remindmeExpiryManager,
        afkexpiry = afkexpiryManager
    }

    return managers or error("Failed to initialize managers")
end

return {
    getmanagers = getmanagers,
}