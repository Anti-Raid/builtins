local Primitives = require "@antiraid-core/primitives"
local KeyExpiryManager = require "@antiraid-ext/keyexpirymanager"
local assertString = require "@antiraid-ext/settings".assertString
local datetime = require "@antiraid/datetime"
local tloop = require "@antiraid-core/templateloop"

export type CreateAFK = {
    user_id: string, -- ID of the user to set AFK for
    channel_id: string?, -- ID of the channel to send an optional AFK message to when the AFK expires
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
    --- Sets a AFK for a user
    set: (data: CreateAFK) -> (),
    --- Deletes a AFK
    delete: (userid: string) -> (),
    --- Code to be called when an AFK expires, which dispatches an event with the AFK data so other templates can react to it if needed
    onAfkExpire: (record: KeyExpiryManager.ExpiringKeyRecord<AFKExpiryData>) -> (),
}

--- AFK expiry manager
export type AFKExpiryData = {
    reason: string,
}

--- A data fetcher for AFKs.
local function AFKManager(ctx: Primitives.TemplateContext, afkexpiry: KeyExpiryManager.KeyExpiryManager<AFKExpiryData>): AFKManager
    local self = {}
    local loop = tloop.getRunningLoop(ctx)

    local function _parseAfk(item: KeyExpiryManager.ExpiringKeyRecord<AFKExpiryData>): AFK
        local reason = assertString("reason", item.value.reason)
        local createdAt = item.createdat
        local expiresAt = item.expiresat

        return {
            user_id = item.key,
            reason = reason,
            expires_at = expiresAt,
            created_at = createdAt,
        }
    end

    local function list(): {AFK}
        local data = afkexpiry.list()

        local afks = {}
        for _, item in data do
            local afk = _parseAfk(item)
            table.insert(afks, afk)
        end

        return afks
    end

    local function get(userid: string): AFK | nil
        local item = afkexpiry.get(userid)
        return if item then _parseAfk(item) else nil
    end

    local function set(afk: CreateAFK): ()
        afkexpiry.add(afk.duration, {
            reason = assertString("reason", afk.reason),
        }, afk.user_id)
        loop.dispatchEvent{
            name = "BuiltinsAfkSet", 
            data = { 
                user_id = afk.user_id, 
                reason = afk.reason, 
                duration = afk.duration,
            },
            author = nil
        }
    end

    local function delete(userid: string)
        local afk = get(userid)
        if not afk then return end
        afkexpiry.remove(userid)
        loop.dispatchEvent{
            name = "BuiltinsAfkDelete", 
            data = { 
                user_id = userid,  
                afk = afk,
            }
        }
    end

    local function onAfkExpire(record: KeyExpiryManager.ExpiringKeyRecord<AFKExpiryData>)
        local afk = get(record.key)
        if not afk then 
            loop.debugmanager.print("[AFKManager] Attempted to expire AFK for user "..record.key.." but they do not have an active AFK")
            return 
        end
        -- Dispatch an event with the result of the AFK expiry so other templates can react to it if needed
        local loop = tloop.getRunningLoop(ctx)
        loop.dispatchEvent{
            name = "BuiltinsAfkExpiry", 
            data = { 
                userid = record.key,
                reason = record.value.reason,
                createdat = record.createdat, 
            },
            author = nil
        }
    end

    self.list = list
    self.get = get
    self.set = set
    self.delete = delete
    self.onAfkExpire = onAfkExpire

    return self
end

return AFKManager