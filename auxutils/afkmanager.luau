local Primitives = require "@antiraid-core/primitives"
local kexs = require "./kexs"
local KeyExpiryManager = require "@antiraid-ext/keyexpirymanager"
local assertString = require "@antiraid-ext/settings".assertString
local datetime = require "@antiraid/datetime"

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
    --- Sets a AFK for a user
    set: (data: CreateAFK) -> (),
    --- Deletes a AFK
    delete: (userid: string) -> (),
}

--- A data fetcher for AFKs.
local function AFKManager(ctx: Primitives.TemplateContext): AFKManager
    local self = {}

    local afkexpiry = kexs.getmanagers(ctx).afkexpiry

    local function _parseAfk(item: KeyExpiryManager.ExpiringKeyRecord): AFK
        local reason = assertString("reason", item.value.reason)
        local createdAt = item.created_at
        local expiresAt = item.expires_at

        return {
            user_id = item.key,
            reason = reason,
            expires_at = expiresAt,
            created_at = createdAt,
        }
    end

    local function list(): {AFK}
        local data = afkexpiry.find()

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
    end

    local function delete(userid: string)
        afkexpiry.remove(userid)
    end

    self.list = list
    self.get = get
    self.set = set
    self.delete = delete

    return self
end

return AFKManager