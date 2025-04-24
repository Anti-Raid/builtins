--!strict
local discord = require "@discord-types/apiTypes"
local Primitives = require "@antiraid-core/primitives"
local promise = require "@antiraid/promise"
local kv = require "@antiraid/kv"

--[[
    Manages the builtin settings for the bot in the server
]]
export type BuiltinSettingsManager = {
    getModLogsChannel: (action: string) -> discord.Snowflake?,
    getAllModLogsChannels: () -> {[string]: discord.Snowflake},
    setModLogsChannel: (action: string?, channelId: discord.Snowflake) -> nil,   
    deleteModLogsChannel: (action: string?) -> nil,
}

local function BuiltinSettingsManager(ctx: Primitives.TemplateContext): BuiltinSettingsManager
    local self = setmetatable({}, {
        __index = BuiltinSettingsManager,
    })

    -- Create a new key-value executor with the builtins.stings kv-scope
    local kv = kv.new(ctx, nil, "builtins.settings")

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

    return self
end

return BuiltinSettingsManager