--!strict
local datetime = require "@antiraid/datetime"
local discord = require "@discord-types/apiTypes"
local Primitives = require "@antiraid-core/primitives"
local typesext = require "@antiraid/typesext"
local kv = require "@antiraid-core/plugins/kv"
local assertString = require "@antiraid-ext/settings".assertString
local assertInteger = require "@antiraid-ext/settings".assertInteger
local tloop = require "@antiraid-core/templateloop"
local keyexpirymanager = require "@antiraid-ext/keyexpirymanager"

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

    Stings are internally stored in the following format:

    {"[builtins].stings", userid} => [sting id]: list of {
        userid: string,
        modId: string?,
        reason: string,
        stings: number,
    }
    stingexpirymanager: stingid -> userid, with the expiry being the sting expiry
]]
export type StingManager = {
    --- Gets all the stings a user has accrued
    getStingsOnUser: (userId: discord.Snowflake) -> {Sting},
    --- Gets cached stings on a user, which is useful for burst queries but may be stale, so use with caution
    getCachedUserStings: (userId: discord.Snowflake) -> {Sting},
    --- Gets a single sting by its ID
    getSting: (userId: discord.Snowflake, stingId: string) -> Sting?,
    --- Creates a new sting for a user returning a Sting
    createUserSting: (sting: CreateSting) -> Sting,
    --- Deletes a sting. Note that this does not delete the expiration task (use fullyDeleteSting if you want to do that)
    deleteSting: (userId: discord.Snowflake, stingId: string, mod: string?, auditReason: string) -> (),
    --- Code to be called when a sting expires, which deletes the internal sting data and dispatches an event with the sting data so other templates can react to it if needed
    onStingExpire: (record: keyexpirymanager.ExpiringKeyRecord<StingExpiryData>) -> (),
    --- Compactly stringifies a sting
    stingCompactString: (sting: Sting) -> string,
}

local _cachedUserStings: {[string]: {stings: {Sting}, createdAt: number }} = {}
local maxBurstCacheTime = 120 -- 2 minutes

export type StingExpiryData = {
    userid: discord.Snowflake,
}

local function StingManager(ctx: Primitives.TemplateContext, stingexpiry: keyexpirymanager.KeyExpiryManager<StingExpiryData>): StingManager
    local self = {}

    local loop = tloop.getRunningLoop(ctx)

    local function _parseStingData(item: kv.KvRecord): Sting?
        if not item.exists then return nil end
        local stingId = item.key
        local userId = assertString("userId", item.value.userId)
        local reason: string = assertString("reason", item.value.reason)
        local modId: string? = if item.value.modId then assertString("modId", item.value.modId) else nil
        local stings = assertInteger("stings", item.value.stings or 1)
        local createdat = item.created_at
        local stingexpiry = stingexpiry.get(stingId)
        local expiresat = if stingexpiry then stingexpiry.expiresat else nil
        return {
            stingId = stingId,
            userId = userId,
            reason = reason,
            modId = modId,
            stings = stings,
            created_at = createdat,
            expires_at = expiresat,
        } :: Sting
    end

    local function deleteSting(userId: discord.Snowflake, stingId: string, mod: string?, auditReason: string)
        if not userId or not stingId or not auditReason then
            error("User ID, Sting ID or Audit Reason is nil")
        end

        -- Fetch the sting
        local record = ctx.KV:getrecord(stingId, {"builtins.stings", userId})
        local csting = _parseStingData(record)
        if not csting then
            return
        end

        -- Dispatch event before deletion so that other templates can react to the sting deletion if needed
        loop.dispatchEvent({
            name = "BuiltinsStingDelete",
            author = mod,
            data = csting,
        })

        -- Delete the sting
        ctx.KV:delete(stingId, {"builtins.stings", userId})
        -- Delete the expiration task
        stingexpiry.remove(stingId)
        -- Cache invalidation
        _cachedUserStings[userId] = nil
    end

    local function onStingExpire(record: keyexpirymanager.ExpiringKeyRecord<StingExpiryData>)
        -- Fetch the sting
        local userid = record.value.userid
        local stingid = record.key
        local data = ctx.KV:getrecord(stingid, {"builtins.stings", userid})
        local csting = _parseStingData(data)
        if not csting then
            return
        end

        -- Dispatch event before expiration so that other templates can react to the sting expiration if needed
        loop.dispatchEvent({
            name = "BuiltinsStingExpire",
            author = nil,
            data = csting,
        })

        -- Delete the sting (the associated expiry will be automatically deleted by the stingexpiry manager since it's keyed by sting ID)
        ctx.KV:delete(stingid, {"builtins.stings", userid})
        -- Cache invalidation
        _cachedUserStings[userid] = nil
    end

    local function getStingsOnUser(userId: discord.Snowflake): {Sting}
        local stings = ctx.KV:find("%%", {"builtins.stings", userId})
        if not stings or #stings == 0 then
            return {}
        end

        local stingList: {Sting} = {}
        for _, sting in stings do
            local stingParsed = _parseStingData(sting)
            if not stingParsed then
                continue
            end
            stingList[#stingList + 1] = stingParsed
        end
        _cachedUserStings[userId] = {
            stings = stingList,
            createdAt = os.time(),
        }

        return stingList
    end

    local function getSting(userId: discord.Snowflake, stingId: string): Sting?
        local sting = ctx.KV:getrecord(stingId, {"builtins.stings", userId})
        local parsedSting = _parseStingData(sting)
        return parsedSting
    end

    local function createUserSting(sting: CreateSting): Sting
        local stingId = typesext.randstring(16)
        while stingexpiry.exists(stingId) do
            stingId = typesext.randstring(16)
        end

        -- Create the sting
        if sting.expires_at then stingexpiry.addat(sting.expires_at, {userid = sting.userId}, stingId) end
        ctx.KV:set(stingId, {
            reason = sting.reason,
            modId = sting.modId,
            stings = sting.stings or 1,
        }, {"builtins.stings", sting.userId})

        local createdAt = datetime.UTC:now()

        local csting = {
            stingId = stingId,
            userId = sting.userId,
            modId = sting.modId,
            reason = sting.reason,
            created_at = createdAt,
            expires_at = sting.expires_at,
            stings = sting.stings or 1,
        } :: Sting

        -- Cache invalidation
        _cachedUserStings[sting.userId] = nil

        -- Dispatch event upon creation so that other templates can react to the sting creation if needed
        loop.dispatchEvent({
            name = "BuiltinsStingCreated",
            author = sting.modId,
            data = csting,
        })

        return csting
    end

    local function getCachedUserStings(userId: discord.Snowflake): {Sting}
        local cache = _cachedUserStings[userId]
        if cache and (os.time() - cache.createdAt) < maxBurstCacheTime then
            return cache.stings
        end

        return getStingsOnUser(userId)
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
    self.getCachedUserStings = getCachedUserStings
    self.createUserSting = createUserSting
    self.deleteSting = deleteSting
    self.onStingExpire = onStingExpire
    self.getSting = getSting
    self.stingCompactString = stingCompactString

    return self
end

return StingManager