--!strict
local datetime = require "@antiraid/datetime"
local discord = require "@discord-types/apiTypes"
local Primitives = require "@antiraid-core/primitives"
local typesext = require "@antiraid/typesext"
local builtinSettingsManager = require "./builtinsettingsmanager"
local kv = require "@antiraid-core/plugins/kv"

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
    --- Sets the expiration of a sting. Repeated calls override previous expiration
    setStingExpiration: (userId: discord.Snowflake, stingId: string, reason: string, expiresAt: datetime.DateTime) -> (),
    --- Deletes the expiration of a sting
    deleteStingExpiration: (userId: discord.Snowflake, stingId: string) -> (),
    --- Deletes a sting. Note that this does not delete the expiration task (use fullyDeleteSting if you want to do that)
    deleteSting: (userId: discord.Snowflake, stingId: string, mod: string?, auditReason: string) -> (),
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

    local builtinsettingsmanager = builtinSettingsManager(ctx)
    local storeTab = ctx.store :: any

    local function _parseStingData(stingId: string, userId: string, sting: kv.KvRecord): Sting?
        if not sting.exists then return nil end
        local reason: string = sting.value.reason
        local modId: discord.Snowflake? = sting.value.modId
        local stingNo = sting.value.stings or 1
        local created_at = sting.created_at
        local expires_at = sting.expires_at

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

    local function setStingExpiration(userId: discord.Snowflake, stingId: string, reason: string, expiresAt: datetime.DateTime)
        -- Get the sting itself and update its internal expires_at
        local record = ctx.KV:getrecord(stingId, {"builtins.stings", userId})
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

        ctx.KV:setexpiry(stingId, {"builtins.stings", userId}, expiresAt)

        -- Send a modlog message
        local modlogschannel = builtinsettingsmanager.getModLogsChannel("sting_set_expiration")

        if modlogschannel then
            ctx.Discord:create_message({
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
            })
        end
    end

    local function deleteStingExpiration(userId: discord.Snowflake, stingId: string)
        -- Get the sting itself and update its internal expires_at
        local record = ctx.KV:getrecord(stingId, {"builtins.stings", userId})
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
        ctx.KV:set(stingId, csting, {"builtins.stings", userId})

        -- Remove the expiration task
        ctx.KV:setexpiry(stingId, {"builtins.stings", userId}, nil)

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("sting_delete_expiration")

        if modlogschannel then
            ctx.Discord:create_message({
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
            })
        end
    end

    local function deleteSting(userId: discord.Snowflake, stingId: string, mod: string?, auditReason: string)
        if not userId or not stingId or not auditReason then
            error("User ID, Sting ID or Audit Reason is nil")
        end

        -- Fetch the sting
        local record = ctx.KV:getrecord(stingId, {"builtins.stings", userId})
        local csting = _parseStingData(stingId, userId, record)
        if not csting then
            return
        end

        if storeTab.onStingDelete then
            (storeTab.onStingDelete :: any)(csting, mod, auditReason)
        end

        -- Delete the sting
        ctx.KV:delete(stingId, {"builtins.stings", userId})

        -- Clear cache
        self.clearCachedUserStings(userId)

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("sting_delete")

        if modlogschannel then
            ctx.Discord:create_message({
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
            })
        end

        self.deleteStingExpiration(userId, stingId)
    end

    local function getStingsOnUser(userId: discord.Snowflake): {Sting}
        local stings = ctx.KV:find("%%", {"builtins.stings", userId})
        if not stings or #stings == 0 then
            return {}
        end

        local stingList: {Sting} = {}
        for _, sting in stings do
            local stingParsed = _parseStingData(sting.key, userId, sting)
            if not stingParsed then
                continue
            end
            stingList[#stingList + 1] = stingParsed
        end

        self.updateCachedUserStings(userId, stingList)
        return stingList
    end

    local function getSting(userId: discord.Snowflake, stingId: string): Sting?
        local sting = ctx.KV:getrecord(stingId, {"builtins.stings", userId})

        local parsedSting = _parseStingData(stingId, userId, sting)
        
        return parsedSting
    end

    local function createUserSting(sting: CreateSting): Sting
        local stingId = typesext.randstring(16)

        -- Create the sting
        ctx.KV:set(stingId, {
            reason = sting.reason,
            modId = sting.modId,
            stings = sting.stings or 1,
        }, {"builtins.stings", sting.userId}, sting.expires_at)

        local createdAt = datetime.UTC:now()

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
            ctx.Discord:create_message({
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
            })
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
    self.setStingExpiration = setStingExpiration
    self.createUserSting = createUserSting
    self.deleteStingExpiration = deleteStingExpiration
    self.deleteSting = deleteSting
    self.getSting = getSting
    self.getCachedUserStings = getCachedUserStings
    self.clearCachedUserStings = clearCachedUserStings
    self.updateCachedUserStings = updateCachedUserStings
    self.stingCompactString = stingCompactString

    return self
end

return StingManager