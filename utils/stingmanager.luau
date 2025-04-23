--!strict
local datetime = require "@antiraid/datetime"
local discord = require "@discord-types/apiTypes"
local Primitives = require "@antiraid-core/primitives"
local promise = require "@antiraid/promise"
local kv = require "@antiraid/kv"
local scheduledexec = require "@antiraid/scheduledexec"
local typesext = require "@antiraid/typesext"

export type Sting = {
    stingId: string,
    userId: discord.Snowflake,
    modId: discord.Snowflake?,
    stings: number,
    reason: string,
    created_at: datetime.DateTime,
}

export type CreateSting = {
    userId: discord.Snowflake,
    modId: discord.Snowflake?,
    stings: number?,
    reason: string,
}

--[[
    Manages the moderation 'stings' (think bee stings!) of a user.
]]
export type StingManager = {
    --- Gets all the stings a user has accrued
    getStingsOnUser: (userId: discord.Snowflake) -> {Sting},
    --- Creates a new sting for a user returning a Sting
    createUserSting: (sting: CreateSting) -> Sting,
    --- Returns the expiration of a sting. If no expiration is set, returns nil
    getStingExpiration: (sting: Sting) -> (string?, datetime.DateTime?),
    --- Sets the expiration of a sting. Repeated calls override previous expiration
    setStingExpiration: (sting: Sting, reason: string, expiresAt: datetime.DateTime) -> (),
}

local function StingManager(ctx: Primitives.TemplateContext): StingManager
    local self = setmetatable({}, {
        __index = StingManager,
    })

    -- Create a new key-value executor with the builtins.stings kv-scope
    local kv = kv.new(ctx, nil, "builtins.stings")
    local scheduledExec = scheduledexec.new(ctx)

    local function getStingExpiration(sting: Sting): (string?, datetime.DateTime?)
        local function extractStingExpiration(exp: scheduledexec.ScheduledExecution): datetime.DateTime?
            local ok, expiresAt = pcall(datetime.UTC.fromString, datetime.UTC, exp.run_at)
            if not ok then
                return nil
            end
            return expiresAt :: datetime.DateTime
        end 
        
        local stingExpirationTask = promise.yield(scheduledExec:list(`${sting.userId}/${sting.stingId}`))
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

    local function setStingExpiration(sting: Sting, reason: string, expiresAt: datetime.DateTime)
        -- Remove the old expiration task if any
        promise.yield(scheduledExec:remove(`${sting.userId}/${sting.stingId}`))
        -- Create a new expiration task
        promise.yield(scheduledExec:add({
            id = `${sting.userId}/${sting.stingId}`,
            data = {
                reason = reason,
            },
            run_at = tostring(expiresAt),
        }))
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
            } :: Sting
        end

        return stingList
    end

    local function createUserSting(sting: CreateSting): Sting
        local stingId = typesext.randstring(16)

        -- Create the sting
        promise.yield(kv:set(`{sting.userId}/{stingId}`, {
            reason = sting.reason,
            modId = sting.modId,
            stings = sting.stings or 1,
        }))

        local createdAt = datetime.UTC:now()

        return {
            stingId = stingId,
            userId = sting.userId,
            modId = sting.modId,
            reason = sting.reason,
            created_at = createdAt,
        } :: Sting
    end

    -- Save to self
    self.getStingsOnUser = getStingsOnUser
    self.getStingExpiration = getStingExpiration
    self.setStingExpiration = setStingExpiration
    self.createUserSting = createUserSting

    return self :: StingManager
end

return StingManager