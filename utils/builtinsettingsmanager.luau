--!strict
local discord = require "@discord-types/apiTypes"
local Primitives = require "@antiraid-core/primitives"
local promise = require "@antiraid/promise"
local kv = require "@antiraid/kv"
local stores = require "@antiraid/stores"

export type BaseAction = {
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

    -- Base mod sting endpoints
    getBaseModerationStingCounts: (action: string) -> number?,
    getAllBaseModerationStingCounts: () -> {[string]: number},
    setBaseModerationStingCounts: (action: string?, stings: number) -> nil,   
    deleteBaseModerationStingCounts: (action: string?) -> nil,

    -- Actions
    getAllModLogsActions: () -> {BaseAction},
    getAllModActions: () -> {BaseAction}
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

    local function getBaseModerationStingCounts(action: string): number?
        local mlc = promise.yield(kv:get(`baseModerationStingCounts`))

        if type(mlc) == "number" then return mlc end
        if type(mlc) == "string" then return tonumber(mlc) end
        if type(mlc) == "table" then 
            local stings = (mlc :: any)[action]
            if stings then
                return stings
            end

            local defaultStings = (mlc :: any)["default"]
            if defaultStings then
                return defaultStings
            end

            return nil
        else
            return nil
        end
    end

    local function getAllBaseModerationStingCounts(): {[string]: number}
        local mlc = promise.yield(kv:get(`baseModerationStingCounts`))

        if type(mlc) == "number" then return { default = mlc } end
        if type(mlc) == "string" then 
            local stings = tonumber(mlc)
            if not stings then return {} end
            return { default = stings }
        end
        if type(mlc) == "table" then
            return (mlc :: any)
        else
            return {}
        end
    end

    local function setBaseModerationStingCounts(action: string?, stings: number): nil
        local mlc = promise.yield(kv:get(`baseModerationStingCounts`))

        if type(mlc) == "number" then
            mlc = { default = mlc }
        elseif type(mlc) == "string" then
            local stings_num = tonumber(mlc)
            mlc = { default = stings_num }
        elseif type(mlc) == "table" then
            mlc = (mlc :: any)
        else
            mlc = {}
        end

        if action then
            mlc[action] = stings
        else
            mlc["default"] = stings
        end

        promise.yield(kv:set(`baseModerationStingCounts`, mlc))
        return nil
    end

    local function deleteBaseModerationStingCounts(action: string?): nil
        local mlc = promise.yield(kv:get(`baseModerationStingCounts`))

        local newMlc = nil
        if type(mlc) == "number" or type(mlc) == "string" then
            newMlc = nil -- Just delete the string
        elseif type(mlc) == "table" then
            newMlc = mlc :: any
            newMlc[action or "default"] = nil
        else
            newMlc = nil
        end

        promise.yield(kv:set(`baseModerationStingCounts`, mlc))
        return nil
    end

    local function getAllModLogsActions() 
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

    local function getAllModActions() 
        local base = {
            { name = "Default", value = "default", description = "The default mod action" },
            { name = "Ban Member", value = "ban_member", description = "Member banned" },
            { name = "Kick Member", value = "kick_member", description = "Member kicked" },
            { name = "Timeout Member", value = "timeout_member", description = "Member timed out" },
        }

        if (storeTab and storeTab.getAllModActions) then
            local customActions = (storeTab.getAllModActions :: any)()
            for _, action in customActions do
                table.insert(base, action)
            end
        end

        return base
    end

    self.getModLogsChannel = getModLogsChannel
    self.getAllModLogsChannels = getAllModLogsChannels
    self.setModLogsChannel = setModLogsChannel
    self.deleteModLogsChannel = deleteModLogsChannel
    self.getBaseModerationStingCounts = getBaseModerationStingCounts
    self.getAllBaseModerationStingCounts = getAllBaseModerationStingCounts
    self.setBaseModerationStingCounts = setBaseModerationStingCounts
    self.deleteBaseModerationStingCounts = deleteBaseModerationStingCounts

    self.getAllModLogsActions = getAllModLogsActions
    self.getAllModActions = getAllModActions

    return self
end

return BuiltinSettingsManager