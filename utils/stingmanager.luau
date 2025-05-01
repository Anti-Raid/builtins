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
    deleteSting: (userId: discord.Snowflake, stingId: string, mod: string?, auditReason: string) -> (),
    --- Given a scheduled execution ID corresponding to a sting expiry, return the user id and sting id
    getStingFromScheduledExecId: (scheduledExecId: string) -> (discord.Snowflake?, string?),
    --- Returns the cached list of stings for a user. If the cache is expired, it will fetch the stings from the kv store
    getCachedUserStings: (userId: string) -> {Sting},
    --- Manually update the cached list of stings for a user
    --- This is useful for when you know the stings have changed and you want to update the cache
    updateCachedUserStings: (userId: string, stings: {Sting}) -> nil,
    --- Clears the cached list of stings for a user
    clearCachedUserStings: (userId: string) -> nil,
    --- Compactly stringifies a sting
    stingCompactString: (sting: Sting) -> string,
}

-- Cached user stings should be captured by the StingManager class to ensure require cache keeps the cache local reference the same across
-- all StingManager instances
local _cachedUserStings: {[string]: {stings: {Sting}, createdAt: number }} = {}
local maxBurstCacheTime = 120 -- 2 minutes

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

    local function _parseStingData(stingId: string, userId: string, sting: kv.KvRecord): Sting?
        if not sting.exists then return nil end
        local reason: string = sting.value.reason
        local modId: discord.Snowflake? = sting.value.modId
        local stingNo = sting.value.stings or 1
        local created_at = sting.created_at
        local expires_at = sting.value.expires_at

        if typeof(created_at) ~= "DateTime" then
            sting.created_at = datetime.UTC:now()
        end

        if expires_at and typeof(expires_at) ~= "DateTime" then
            expires_at = nil
        end
        
        if expires_at and expires_at < datetime.UTC:now() then
            return nil
        end

        if type(stingId) ~= "string" or type(reason) ~= "string" then
            return nil
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
            created_at = created_at,
            expires_at = expires_at,
        } :: Sting
    end

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
        local record = promise.yield(kv:getrecord(`{userId}/{stingId}`))
        if not record.exists then
            return
        end
        local csting = _parseStingData(stingId, userId, record)
        if not csting then
            return
        end

        if storeTab.onStingSetExpiration then
            (storeTab.onStingSetExpiration :: any)(csting, reason, expiresAt)
        end

        csting.expires_at = expiresAt
        promise.yield(kv:set(`{userId}/{stingId}`, csting))

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

        -- Send a modlog message
        local modlogschannel = builtinsettingsmanager.getModLogsChannel("sting_set_expiration")

        if modlogschannel then
            promise.yield(discord:create_message({
                channel_id = modlogschannel,
                data = {
                    embeds = {
                        {
                            title = "Sting Expiration Set",
                            description = string.format("Sting ID: %s\nUser ID: %s\nReason: %s", csting.stingId, csting.userId, csting.reason),
                            fields = {
                                { name = "Moderator", value = if csting.modId then "<@" .. csting.modId .. ">" else "System", inline = true },
                                { name = "Created At", value = "<t:" .. csting.created_at.timestamp_seconds .. ">", inline = true },
                                { name = "Expires On", value = "<t:" .. expiresAt.timestamp_seconds .. ">", inline = true },
                                { name = "Reason", value = reason, inline = true },
                                { name = "Sting Count", value = tostring(csting.stings), inline = true },
                            },
                        }
                    } :: {discord.EmbedObject},
                }
            }))
        end
    end

    local function deleteStingExpiration(userId: discord.Snowflake, stingId: string)
        -- Get the sting itself and update its internal expires_at
        local record = promise.yield(kv:getrecord(`{userId}/{stingId}`))
        if not record.exists then
            return
        end

        local csting = _parseStingData(stingId, userId, record)

        if not csting or not csting.expires_at then
            return
        end

        if storeTab.onStingDeleteExpiration then
            (storeTab.onStingDeleteExpiration :: any)(csting)
        end

        local oldExpiresAt = csting.expires_at
        csting.expires_at = nil :: any
        promise.yield(kv:set(`{userId}/{stingId}`, csting))

        -- Remove the expiration task
        promise.yield(scheduledExec:remove(`builtins.stings/{userId}/{stingId}`))

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("sting_delete_expiration")

        if modlogschannel then
            promise.yield(discord:create_message({
                channel_id = modlogschannel,
                data = {
                    embeds = {
                        {
                            title = "Sting Expiration Removed",
                            description = string.format("Sting ID: %s\nUser ID: %s\nReason: ``%s``", csting.stingId, csting.userId, csting.reason),
                            fields = {
                                { name = "Moderator", value = if csting.modId then "<@" .. csting.modId .. ">" else "System", inline = true },
                                { name = "Created At", value = "<t:" .. csting.created_at.timestamp_seconds .. ">", inline = true },
                                { name = "Old Expiry", value = "<t:" .. oldExpiresAt.timestamp_seconds .. ">", inline = true },
                                { name = "Reason", value = csting.reason, inline = true },
                                { name = "Sting Count", value = tostring(csting.stings), inline = true },
                            },
                        }
                    } :: {discord.EmbedObject},
                }
            }))
        end
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

    local function deleteSting(userId: discord.Snowflake, stingId: string, mod: string?, auditReason: string)
        if not userId or not stingId or not auditReason then
            error("User ID, Sting ID or Audit Reason is nil")
        end

        -- Fetch the sting
        local record = promise.yield(kv:getrecord(`{userId}/{stingId}`))
        local csting = _parseStingData(stingId, userId, record)
        if not csting then
            return
        end

        if storeTab.onStingDelete then
            (storeTab.onStingDelete :: any)(csting, mod, auditReason)
        end

        -- Delete the sting
        promise.yield(kv:delete(`{userId}/{stingId}`))

        -- Clear cache
        self.clearCachedUserStings(userId)

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("sting_delete")

        if modlogschannel then
            promise.yield(discord:create_message({
                channel_id = modlogschannel,
                data = {
                    embeds = {
                        {
                            title = "Sting Deleted",
                            description = string.format("Sting ID: %s\nUser ID: %s\nReason: %s", csting.stingId, csting.userId, csting.reason),
                            fields = {
                                { name = "Original Moderator", value = if csting.modId then "<@" .. csting.modId .. ">" else "System", inline = true },
                                { name = "Deleted By", value = if mod then "<@" .. mod .. ">" else "System", inline = true },
                                { name = "Created At", value = "<t:" .. csting.created_at.timestamp_seconds .. ">", inline = true },
                                { name = "Expires On", value = if csting.expires_at then "<t:" .. csting.expires_at.timestamp_seconds .. ">" else "Never", inline = true },
                                { name = "Reason For Sting", value = csting.reason, inline = true },
                                { name = "Reason For Deletion", value = if auditReason then auditReason else "No reason provided", inline = true },
                                { name = "Sting Count", value = tostring(csting.stings), inline = true },
                                { name = "Deleted At", value = "<t:" .. datetime.UTC:now().timestamp_seconds .. ">", inline = true },
                            },
                        }
                    } :: {discord.EmbedObject},
                }
            }))
        end

        self.deleteStingExpiration(userId, stingId)
    end

    local function getStingsOnUser(userId: discord.Snowflake): {Sting}
        local stings = promise.yield(kv:find(`{userId}/%`))
        if not stings or #stings == 0 then
            return {}
        end

        local stingList: {Sting} = {}
        for _, sting in stings do
            local stingParsed = _parseStingData(sting.key:split("/")[2], userId, sting)
            if not stingParsed then
                continue
            end
            stingList[#stingList + 1] = stingParsed
        end

        self.updateCachedUserStings(userId, stingList)
        return stingList
    end

    local function getSting(userId: discord.Snowflake, stingId: string): Sting?
        local sting = promise.yield(kv:getrecord(`{userId}/{stingId}`))

        local parsedSting = _parseStingData(stingId, userId, sting)
        
        return parsedSting
    end

    local function createUserSting(sting: CreateSting): Sting
        local stingId = typesext.randstring(16)

        -- Create the sting
        promise.yield(kv:set(`{sting.userId}/{stingId}`, {
            reason = sting.reason,
            modId = sting.modId,
            expires_at = sting.expires_at,
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
                run_at = tostring(sting.expires_at), -- TODO: Support datetime in scheduledexec API
            }))
        end

        self.clearCachedUserStings(sting.userId)

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
                                { name = "Expires On", value = if csting.expires_at then "<t:" .. csting.expires_at.timestamp_seconds .. ">" else "Never", inline = true },
                                { name = "Reason", value = csting.reason, inline = true },
                                { name = "Sting Count", value = tostring(csting.stings), inline = true },
                            },
                        }
                    } :: {discord.EmbedObject},
                }
            }))
        end

        return csting
    end

    local function getCachedUserStings(userId: string): {Sting}
        if _cachedUserStings[userId] then 
            if not maxBurstCacheTime or _cachedUserStings[userId].createdAt - os.clock() < maxBurstCacheTime then 
                return _cachedUserStings[userId].stings
            end
        end
    
        local stings = self.getStingsOnUser(userId)
        _cachedUserStings[userId] = {
            stings = stings,
            createdAt = os.clock(),
        }
        return stings
    end  
    
    local function clearCachedUserStings(userId: string): nil
        if _cachedUserStings[userId] then
            _cachedUserStings[userId] = nil
        end
        return nil
    end

    local function updateCachedUserStings(userId: string, stings: {Sting}): nil
        _cachedUserStings[userId] = {
            stings = stings,
            createdAt = os.clock(),
        }
        return nil
    end

    local function stingCompactString(sting: Sting): string
        local expiresAt = if sting.expires_at then "<t:" .. sting.expires_at.timestamp_seconds .. ">" else "Never"
        local mod = if sting.modId then "<@" .. sting.modId .. ">" else "System"
        local reason = if #sting.reason > 0 then sting.reason else "No reason provided"
        if #reason > 128 then
            reason = reason:sub(1, 128) .. "..."
        end
        -- "Sting by " .. if maxSting.modId then "<@" .. maxSting.modId .. ">" else "System" .. " with ID of ``" .. maxSting.stingId .. "``",
        return string.format("Sting by %s with ID of ``%s``\nReason: %s\nCreated at: <t:%d>\nExpires at: %s\nSting count: %d", mod, sting.stingId, reason, sting.created_at.timestamp_seconds, expiresAt, sting.stings)
    end

    -- Save to self
    self.getStingsOnUser = getStingsOnUser
    self.getStingExpiration = getStingExpiration
    self.setStingExpiration = setStingExpiration
    self.createUserSting = createUserSting
    self.deleteStingExpiration = deleteStingExpiration
    self.deleteSting = deleteSting
    self.getStingFromScheduledExecId = getStingFromScheduledExecId
    self.getSting = getSting
    self.getCachedUserStings = getCachedUserStings
    self.clearCachedUserStings = clearCachedUserStings
    self.updateCachedUserStings = updateCachedUserStings
    self.stingCompactString = stingCompactString

    return self
end

return StingManager