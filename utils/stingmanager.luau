--!strict
local datetime = require "@antiraid/datetime"
local discord = require "@discord-types/apiTypes"
local Primitives = require "@antiraid-core/primitives"
local promise = require "@antiraid/promise"
local kv = require "@antiraid/kv"
local scheduledexec = require "@antiraid/scheduledexec"
local typesext = require "@antiraid/typesext"
local stores = require "@antiraid/stores"
local builtinSettingsManager = require "./builtinsettingsmanager"
local discordPlugin = require "@antiraid/discord"

export type Sting = {
    stingId: string,
    userId: discord.Snowflake,
    modId: discord.Snowflake?,
    stings: number,
    reason: string,
    created_at: datetime.DateTime,
    expires_at: datetime.DateTime?,
}

export type CreateSting = {
    userId: discord.Snowflake,
    modId: discord.Snowflake?,
    stings: number?,
    reason: string,
    expires_at: datetime.DateTime?,
}

--[[
    Manages the moderation 'stings' (think bee stings!) of a user.
]]
export type StingManager = {
    --- Gets all the stings a user has accrued
    getStingsOnUser: (userId: discord.Snowflake) -> {Sting},
    --- Gets a single sting by its ID
    getSting: (userId: discord.Snowflake, stingId: string) -> Sting?,
    --- Creates a new sting for a user returning a Sting
    createUserSting: (sting: CreateSting) -> Sting,
    --- Returns the expiration of a sting from the expiration task itself. If no expiration is set, returns nil
    getStingExpiration: (userId: discord.Snowflake, stingId: string) -> (string?, datetime.DateTime?),
    --- Sets the expiration of a sting. Repeated calls override previous expiration
    setStingExpiration: (userId: discord.Snowflake, stingId: string, reason: string, expiresAt: datetime.DateTime) -> (),
    --- Deletes the expiration of a sting
    deleteStingExpiration: (userId: discord.Snowflake, stingId: string) -> (),
    --- Deletes a sting. Note that this does not delete the expiration task (use fullyDeleteSting if you want to do that)
    deleteSting: (userId: discord.Snowflake, stingId: string) -> (),
    --- Fully deletes a sting and its expiration task and anything else needed
    fullyDeleteSting: (userId: discord.Snowflake, stingId: string) -> (),
    --- Given a scheduled execution ID corresponding to a sting expiry, return the user id and sting id
    getStingFromScheduledExecId: (scheduledExecId: string) -> (discord.Snowflake?, string?),
}

local function StingManager(ctx: Primitives.TemplateContext): StingManager
    local self = setmetatable({}, {
        __index = StingManager,
    })

    -- Create a new key-value executor with the builtins.stings kv-scope
    local kv = kv.new(ctx, nil, "builtins.stings")
    local builtinsettingsmanager = builtinSettingsManager(ctx)
    local discord = discordPlugin.new(ctx)
    local storeTab = stores.store(ctx) :: any
    local scheduledExec = scheduledexec.new(ctx)

    local function getStingExpiration(userId: discord.Snowflake, stingId: string): (string?, datetime.DateTime?)
        local function extractStingExpiration(exp: scheduledexec.ScheduledExecution): datetime.DateTime?
            local ok, expiresAt = pcall(datetime.UTC.fromString, datetime.UTC, exp.run_at)
            if not ok then
                return nil
            end
            return expiresAt :: datetime.DateTime
        end 
        
        local stingExpirationTask = promise.yield(scheduledExec:list(`builtins.stings/{userId}/{stingId}`))
        if not stingExpirationTask or #stingExpirationTask == 0 then
            return nil, nil
        end
        local task = stingExpirationTask[1]
        local taskExpiresAt = extractStingExpiration(task)
        if #stingExpirationTask > 1 then 
            -- Get the minimum expiration date (as AntiRaid is not guaranteed to run multiple, only first)
            for i = 2, #stingExpirationTask do
                local potTask = stingExpirationTask[i]
                local potTaskExpiresAt = extractStingExpiration(potTask)
                if not potTaskExpiresAt then
                    continue
                end

                if not taskExpiresAt or potTaskExpiresAt < taskExpiresAt then
                    task = potTask
                    taskExpiresAt = potTaskExpiresAt
                end
            end
        end

        local reason = if task.data.reason and type(task.data.reason) == "string" then task.data.reason else nil

        return reason, taskExpiresAt
    end

    local function setStingExpiration(userId: discord.Snowflake, stingId: string, reason: string, expiresAt: datetime.DateTime)
        -- Get the sting itself and update its internal expires_at
        local sting = promise.yield(kv:get(`{userId}/{stingId}`))
        if not sting then
            return
        end
        sting.expires_at = tostring(expiresAt)
        promise.yield(kv:set(`{userId}/{stingId}`, sting))

        -- Remove the old expiration task if any
        promise.yield(scheduledExec:remove(`builtins.stings/{userId}/{stingId}`))
        -- Create a new expiration task
        promise.yield(scheduledExec:add({
            id = `builtins.stings/{userId}/{stingId}`,
            data = {
                reason = reason,
            },
            run_at = tostring(expiresAt),
        }))
    end

    local function deleteStingExpiration(userId: discord.Snowflake, stingId: string)
        -- Get the sting itself and update its internal expires_at
        local sting = promise.yield(kv:get(`{userId}/{stingId}`))
        if not sting then
            return
        end
        sting.expires_at = nil
        promise.yield(kv:set(`{userId}/{stingId}`, sting))

        -- Remove the expiration task
        promise.yield(scheduledExec:remove(`builtins.stings/{userId}/{stingId}`))
    end

    local function getStingFromScheduledExecId(scheduledExecId: string): (discord.Snowflake?, string?)
        -- Ensure it starts with builtins.stings/
        local f, _ = scheduledExecId:find("builtins.stings/")
        if f ~= 1 then
            return nil, nil
        end
        
        -- Extract the userId and stingId
        local userId, stingId = scheduledExecId:match("builtins.stings/(%d+)/(%w+)")
        if not userId or not stingId then
            return nil, nil
        end

        return userId, stingId
    end

    local function deleteSting(userId: discord.Snowflake, stingId: string)
        if not userId or not stingId then
            error("User ID or Sting ID is nil")
        end

        if storeTab.onStingDelete then
            (storeTab.onStingDelete :: any)(userId, stingId)
        end

        -- Delete the sting
        promise.yield(kv:delete(`{userId}/{stingId}`))

        self.deleteStingExpiration(userId, stingId)
    end

    local function fullyDeleteSting(userId: discord.Snowflake, stingId: string)
        deleteSting(userId, stingId)
        deleteStingExpiration(userId, stingId)
    end

    local function getStingsOnUser(userId: discord.Snowflake): {Sting}
        local stings = promise.yield(kv:find(`{userId}/%`))
        if not stings or #stings == 0 then
            return {}
        end

        local stingList: {Sting} = {}
        for _, sting in stings do
            local stingId = sting.key:split("/")[2]
            local reason: string = sting.value.reason
            local modId: discord.Snowflake? = sting.value.modId
            local stingNo = sting.value.stings or 1
            local createdAt = datetime.UTC:fromString(sting.created_at)
            local expiresAtStr = sting.value.expires_at
            local expiresAt = if expiresAtStr then datetime.UTC:fromString(expiresAtStr :: string) else nil
            
            if expiresAt and expiresAt < datetime.UTC:now() then
                -- Delete the expired sting
                promise.yield(kv:delete(sting.key))
                continue
            end
            
            -- TODO: Support expires_at later
            if type(stingId) ~= "string" or type(reason) ~= "string" then
                -- Delete the corrupt sting
                promise.yield(kv:delete(sting.key))
            end

            if modId and type(modId) ~= "string" then
                modId = nil
            end

            stingList[#stingList + 1] = {
                stingId = stingId,
                userId = userId,
                reason = reason,
                modId = modId,
                stings = stingNo,
                created_at = createdAt,
                expires_at = expiresAt,
            } :: Sting
        end

        return stingList
    end

    local function getSting(userId: discord.Snowflake, stingId: string): Sting?
        local sting = promise.yield(kv:get(`{userId}/{stingId}`))
        if not sting then
            return nil
        end

        local reason: string = sting.value.reason
        local modId: discord.Snowflake? = sting.value.modId
        local stingNo = sting.value.stings or 1
        local createdAt = datetime.UTC:fromString(sting.created_at)
        local expiresAtStr = sting.value.expires_at
        local expiresAt = if expiresAtStr then datetime.UTC:fromString(expiresAtStr :: string) else nil
        
        if expiresAt and expiresAt < datetime.UTC:now() then
            -- Delete the expired sting
            promise.yield(kv:delete(sting.key))
            return nil
        end

        -- TODO: Support expires_at later
        if type(stingId) ~= "string" or type(reason) ~= "string" then
            -- Delete the corrupt sting
            promise.yield(kv:delete(sting.key))
        end

        if modId and type(modId) ~= "string" then
            modId = nil
        end
        
        return {
            stingId = stingId,
            userId = userId,
            reason = reason,
            modId = modId,
            stings = stingNo,
            created_at = createdAt,
            expires_at = expiresAt,
        } :: Sting
    end

    local function createUserSting(sting: CreateSting): Sting
        local stingId = typesext.randstring(16)

        -- Create the sting
        promise.yield(kv:set(`{sting.userId}/{stingId}`, {
            reason = sting.reason,
            modId = sting.modId,
            expires_at = if sting.expires_at then tostring(sting.expires_at) else nil,
            stings = sting.stings or 1,
        }))

        local createdAt = datetime.UTC:now()

        if sting.expires_at then
            -- Create the expiration task
            promise.yield(scheduledExec:add({
                id = `builtins.stings/{sting.userId}/{stingId}`,
                data = {
                    reason = sting.reason,
                },
                run_at = tostring(sting.expires_at),
            }))
        end

        local csting = {
            stingId = stingId,
            userId = sting.userId,
            modId = sting.modId,
            reason = sting.reason,
            created_at = createdAt,
            expires_at = sting.expires_at,
            stings = sting.stings or 1,
        } :: Sting

        if storeTab.onStingCreate then
            (storeTab.onStingCreate :: any)(csting)
        end

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("sting_create")

        if modlogschannel then
            promise.yield(discord:create_message({
                channel_id = modlogschannel,
                data = {
                    embeds = {
                        {
                            title = "Sting Created",
                            description = string.format("Sting ID: %s\nUser ID: %s\nReason: %s", csting.stingId, csting.userId, csting.reason),
                            fields = {
                                { name = "Moderator", value = if csting.modId then "<@" .. csting.modId .. ">" else "System", inline = true },
                                { name = "Created At", value = "<t:" .. csting.created_at.timestamp_seconds .. ">", inline = true },
                            },
                        }
                    } :: {discord.EmbedObject},
                }
            }))
        end

        return csting
    end

    -- Save to self
    self.getStingsOnUser = getStingsOnUser
    self.getStingExpiration = getStingExpiration
    self.setStingExpiration = setStingExpiration
    self.createUserSting = createUserSting
    self.deleteStingExpiration = deleteStingExpiration
    self.deleteSting = deleteSting
    self.fullyDeleteSting = fullyDeleteSting
    self.getStingFromScheduledExecId = getStingFromScheduledExecId
    self.getSting = getSting

    return self
end

return StingManager