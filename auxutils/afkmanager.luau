local Primitives = require "@antiraid-core/primitives"
local assertString = require "@antiraid-ext/settings".assertString
local kv = require "@antiraid-core/plugins/kv"
local datetime = require "@antiraid/datetime"

local cacheExpiryTime = 60 -- Cache expiry time

export type CreateAFK = {
    user_id: string, -- ID of the user to set AFK for
    reason: string, -- Reason for the AFK status
    duration: datetime.TimeDelta, -- Duration for which the user should be AFK
}

export type AFK = {
    user_id: string, -- ID of the user who is AFK
    reason: string, -- Reason for the AFK status
    expires_at: datetime.DateTime, -- When the AFK status expires
    created_at: datetime.DateTime, -- When the AFK was set
}

export type AFKManager = {
    --- Returns a list of all AFKs
    list: () -> {AFK},
    --- Returns a user's AFK if they have one
    get: (userid: string) -> AFK | nil,
    --- Returns a user's AFK if they have one (cached)
    getcached: (userid: string) -> AFK | nil,
    --- Sets a AFK for a user
    set: (data: CreateAFK) -> (),
    --- Deletes a AFK
    delete: (userid: string) -> (),
}

--- A data fetcher for AFKs.
local function AFKManager(ctx: Primitives.TemplateContext): AFKManager
    local self = {}

    type CachedAfk = {
        afk: AFK,
        made: number
    }

    local afkCache: {[string]: CachedAfk} = {}

    local function _parseAfk(item: kv.KvRecord): AFK
        assert(item.exists, "Internal error: AFK item does not exist")
        local userid = item.key
        local reason = assertString("reason", item.value.reason)
        local createdAt = item.created_at
        local expiresAt = item.expires_at or error("Internal error: AFK item does not have an expires_at field")

        return {
            user_id = userid,
            reason = reason,
            expires_at = expiresAt,
            created_at = createdAt,
        }
    end

    local function list(): {AFK}
        local data = ctx.KV:find("%%", {"builtins.afks"})

        local afks = {}
        for _, item in data do
            local afk = _parseAfk(item)
            afkCache[afk.user_id] = {
                afk = afk,
                made = os.clock(),
            }
            table.insert(afks, afk)
        end

        return afks
    end

    local function get(userid: string): AFK | nil
        local item = ctx.KV:getrecord(userid, {"builtins.afks"})
        if not item or not item.exists then
            return nil
        end

        local afk = _parseAfk(item)
        afkCache[userid] = {
            afk = afk,
            made = os.clock(),
        }
        return afk
    end

    local function set(afk: CreateAFK): ()
        ctx.KV:set(afk.user_id, {
            reason = assertString("reason", afk.reason),
        }, {"builtins.afks"}, datetime.UTC:now() + afk.duration)

        local cacheAfk = {
            user_id = afk.user_id,
            reason = afk.reason,
            expires_at = datetime.UTC:now() + afk.duration,
            created_at = datetime.UTC:now(),
        }

        afkCache[afk.user_id] = {
            afk = cacheAfk,
            made = os.clock(),
        }
    end

    local function delete(userid: string)
        ctx.KV:delete(userid, {"builtins.afks"})
        afkCache[userid] = nil -- Remove from cache
    end

    local function getcached(userid: string): AFK | nil
        if afkCache[userid] and os.clock() - afkCache[userid].made > cacheExpiryTime then
            if afkCache[userid].afk.expires_at < datetime.UTC:now() then
                -- If the cached AFK has expired, remove it
                afkCache[userid] = nil
                return nil
            end

            return afkCache[userid].afk
        end

        return get(userid)
    end

    self.list = list
    self.get = get
    self.getcached = getcached
    self.set = set
    self.delete = delete

    return self
end

return AFKManager