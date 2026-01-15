local Primitives = require "@antiraid-core/primitives"
local assertString = require "@antiraid-ext/settings".assertString
local kv = require "@antiraid-core/plugins/kv"
local datetime = require "@antiraid/datetime"
local isDevMode = require"../devs".isInDevMode

local scopePrefix = if isDevMode then "builtins-dev" else "builtins"

local cacheExpiryTime = 60 -- Cache expiry time

export type CreateLog = {
    channel_id: string, -- the id of the channel to send logs to
    what: "role_delete" | "channel_delete", -- what action to log
}

export type Log = {
    channel_id: string, -- id of the channel to send logs to
    what: "role_delete" | "channel_delete", -- What action
    created_at: datetime.DateTime, -- When the log was created
}

export type AuditLogManager = {
    --- Returns a list of all audit logs
    list: () -> {Log},
    --- Returns a string list of all blocked channels (cached)
    list_cached: () -> set.Set<string>,
    --- Returns a channel's log if they have one
    get: (channel_id: string) -> Log | nil,
    --- Returns a channel's log if they have one (cached)
    get_cached: (channel_id: string) -> Log | nil,
    --- Sets an audit log for a channel
    set: (data: CreateLog) -> (),
    --- Deletes an audit log
    delete: (channel_id: string) -> (),
}

--- An audit log manager for destructive actions
local function AuditLogManager(ctx: Primitives.TemplateContext): AuditLogManager
    local self = {}

    type CachedLog = {
        log: Log,
        made: number
    }

    local logCache: {[string]: CachedLog} = {}

    local function _parseLog(item: kv.KvRecord): Log
        assert(item.exists, "Internal error: log item does not exist")
        local channelId = item.key
        local what = assertString("what", item.value.what)
        local createdAt = item.created_at

        return {
            channel_id = channelId,
            what = what,
            created_at = createdAt,
        }
    end

    local function list(): {Log}
        local data = ctx.KV:find("%%", {scopePrefix .. ".auditlogs"})

        local logs = {}
        for _, item in data do
            local log = _parseLog(item)
            logCache[log.channel_id] = {
                log = log,
                made = os.clock(),
            }
            table.insert(logs, log)
        end

        return logs
    end

    local function get(channel_id: string): Log | nil
        local item = ctx.KV:getrecord(channel_id, {scopePrefix .. ".auditlogs"})
        if not item or not item.exists then
            return nil
        end

        local log = _parseLog(item)
        logCache[channel_id] = {
            log = log,
            made = os.clock(),
        }
        return log
    end

    local function set(logData: CreateLog): ()
        ctx.KV:set(logData.channel_id, {
            what = assertString("what", logData.what),
        }, {scopePrefix .. ".auditlogs"})

        local log = {
            channel_id = logData.channel_id,
            what = logData.what,
            created_at = datetime.UTC:now(),
        }

        logCache[logData.channel_id] = {
            log = log,
            made = os.clock(),
        }
    end

    local function delete(channel_id: string)
        ctx.KV:delete(channel_id, {scopePrefix .. ".auditlogs"})
        logCache[channel_id] = nil -- Remove from cache
    end

    local function get_cached(channelid: string): Log | nil
        if logCache[channelid] and os.clock() - logCache[channelid].made < cacheExpiryTime then
            return logCache[channelid].log
        end

        return get(channelid)
    end

    local function list_cached(): {Log}
        if logCache and os.clock() - logCache.made > cacheExpiryTime then
            return logCache.log
        end

        return list()
    end

    self.list = list
    self.list_cached = list_cached
    self.get = get
    self.getcached = get_cached
    self.set = set
    self.delete = delete

    return self
end

return AuditLogManager