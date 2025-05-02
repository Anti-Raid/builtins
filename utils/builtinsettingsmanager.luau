--!strict
local discord = require "@discord-types/apiTypes"
local Primitives = require "@antiraid-core/primitives"
local promise = require "@antiraid/promise"
local kv = require "@antiraid/kv"
local stores = require "@antiraid/stores"

export type BaseModLogAction = {
    name: string,
    value: string,
    description: string,
}

--[[
    Manages the builtin settings for the bot in the server
]]
export type BuiltinSettingsManager = {
    getModLogsChannel: (action: string) -> discord.Snowflake?,
    getAllModLogsChannels: () -> {[string]: discord.Snowflake},
    setModLogsChannel: (action: string?, channelId: discord.Snowflake) -> nil,   
    deleteModLogsChannel: (action: string?) -> nil,
    getAllModLogsActions: () -> {BaseModLogAction},
}

local function BuiltinSettingsManager(ctx: Primitives.TemplateContext): BuiltinSettingsManager
    local self = setmetatable({}, {
        __index = BuiltinSettingsManager,
    })

    -- Create a new key-value executor with the builtins.stings kv-scope
    local kv = kv.new(ctx, nil, "builtins.settings")
    local storeTab = stores.store :: any

    local function getModLogsChannel(action: string): discord.Snowflake?
        local mlc = promise.yield(kv:get(`modlogsChannel`))

        if type(mlc) == "string" then return mlc end
        if type(mlc) == "table" then 
            local channel = (mlc :: any)[action]
            if channel then
                return channel
            end

            local defaultChannel = (mlc :: any)["default"]
            if defaultChannel then
                return defaultChannel
            end

            return nil
        else
            return nil
        end
    end

    local function getAllModLogsChannels(): {[string]: discord.Snowflake}
        local mlc = promise.yield(kv:get(`modlogsChannel`))

        if type(mlc) == "string" then
            return { default = mlc }
        elseif type(mlc) == "table" then
            return (mlc :: any)
        else
            return {}
        end
    end

    local function setModLogsChannel(action: string?, channelId: discord.Snowflake): nil
        local mlc = promise.yield(kv:get(`modlogsChannel`))

        if type(mlc) == "string" then
            mlc = { default = mlc }
        elseif type(mlc) == "table" then
            mlc = (mlc :: any)
        else
            mlc = {}
        end

        if action then
            mlc[action] = channelId
        else
            mlc["default"] = channelId
        end

        promise.yield(kv:set(`modlogsChannel`, mlc))
        return nil
    end

    local function deleteModLogsChannel(action: string?): nil
        local mlc = promise.yield(kv:get(`modlogsChannel`))

        local newMlc = nil
        if type(mlc) == "string" then
            newMlc = nil -- Just delete the string
        elseif type(mlc) == "table" then
            newMlc = mlc :: any
            newMlc[action or "default"] = nil
        else
            newMlc = nil
        end

        promise.yield(kv:set(`modlogsChannel`, mlc))
        return nil
    end

    self.getModLogsChannel = getModLogsChannel
    self.getAllModLogsChannels = getAllModLogsChannels
    self.setModLogsChannel = setModLogsChannel
    self.deleteModLogsChannel = deleteModLogsChannel
    self.getAllModLogsActions = function()
        local base = {
            { name = "Default", value = "default", description = "The default log channel for all moderation logs" },
            { name = "Sting Create", value = "sting_create", description = "The log channel for when a sting is created" },
            { name = "Sting Delete", value = "sting_delete", description = "The log channel for when a sting is deleted" },
            { name = "Sting Expiration Set", value = "sting_set_expiration", description = "The long channel for when a stings expiration is manually set"},
            { name = "Sting Expiration Removed", value = "onStingDeleteExpiration", description = "The log channel for when a sting expiration is removed" },
        }

        if (storeTab and storeTab.getAllModLogsActions) then
            local customActions = (storeTab.getAllModLogsActions :: any)()
            for _, action in customActions do
                table.insert(base, action)
            end
        end

        return base
    end

    return self
end

return BuiltinSettingsManager