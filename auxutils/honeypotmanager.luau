local Primitives = require "@antiraid-core/primitives"
local kv = require "@antiraid-core/plugins/kv"
local datetime = require "@antiraid/datetime"
local assertBoolean = require "@antiraid-ext/settings".assertBoolean
local assertStringChoices = require "@antiraid-ext/settings".assertStringChoices
local isDevMode = require"../devs".isInDevMode

local scopePrefix = if isDevMode then "builtins-dev" else "builtins"
local punishmentChoices = {"ban", "kick"}
local MAX_HONEYPOTS = 3 -- Maximum honeypots allowed per server

local cacheExpiryTime = 60 -- Cache expiry time

export type CreateHoneypot = {
    botallowed: boolean, -- Whether bots are allowed to message in the honeypot
    punishment: "ban" | "kick", -- Punishment to apply
    channelid: string, -- ID of the honeypot channel    
}

export type Honeypot = {
    channelid: string, -- ID of the honeypot channel
    botallowed: boolean, -- Whether bots are allowed to message in the honeypot
    punishment: "ban" | "kick", -- Punishment to apply
    created_at: datetime.DateTime, -- When the AFK was set
}

export type HoneypotManager = {
    --- Returns all setup honeypots on the server
    list: () -> {Honeypot},
    --- Returns all setup honeypots on the server (cached)
    listcached: () -> {Honeypot},
    --- Sets a honeypot for a channel
    set: (data: CreateHoneypot) -> (),
    --- Deletes a honeypot
    delete: (channelid: string) -> (),
}

--- A data fetcher for honeypots.
local function HoneypotManager(ctx: Primitives.TemplateContext): HoneypotManager
    local self = {}

    type CachedHoneypots = {
        honeypots: {Honeypot},
        made: number
    }

    local honeypotsCache: CachedHoneypots? = nil

    local function _parseHoneypot(item: kv.KvRecord): Honeypot
        assert(item.exists, "Internal error: Honeypot item does not exist")
        local channelid = item.key
        local createdAt = item.created_at
        local botallowed = assertBoolean("botallowed", item.value.botallowed or false)
        local punishment = assertStringChoices("punishment", item.value.punishment, punishmentChoices) :: "ban" | "kick"

        return {
            channelid = channelid,
            botallowed = botallowed,
            punishment = punishment,
            created_at = createdAt,
        }
    end

    local function list(): {Honeypot}
        local data = ctx.KV:find("%%", {scopePrefix .. ".honeypots"})

        local honeypots = {}
        for _, item in data do
            local honeypot = _parseHoneypot(item)
            table.freeze(honeypot)
            table.insert(honeypots, honeypot)
        end
        honeypots = table.freeze(honeypots) :: {Honeypot} -- Freeze the table to make it immutable

        honeypotsCache = {
            honeypots = honeypots,
            made = os.clock(),
        }

        return honeypots
    end

    local function set(honeypot: CreateHoneypot): ()
        local honeypots = list()
        if #honeypots >= MAX_HONEYPOTS then
            error("Maximum of 5 honeypots can be set at once")
        end

        ctx.KV:set(honeypot.channelid, {
            botallowed = assertBoolean("botallowed", honeypot.botallowed),
            punishment = assertStringChoices("punishment", honeypot.punishment, punishmentChoices),
        }, {scopePrefix .. ".honeypots"})

        honeypotsCache = nil -- Invalidate cache
    end

    local function delete(userid: string)
        ctx.KV:delete(userid, {scopePrefix .. ".afks"})
        honeypotsCache = nil -- Invalidate cache
    end

    local function listcached(): {Honeypot}
        if honeypotsCache and os.clock() - honeypotsCache.made > cacheExpiryTime then
            return honeypotsCache.honeypots
        end

        return list()
    end

    self.list = list
    self.listcached = listcached
    self.set = set
    self.delete = delete

    return self
end

return HoneypotManager