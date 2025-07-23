local Primitives = require "@antiraid-core/primitives"
local assertString = require "@antiraid-ext/settings".assertString
local assertBoolean = require "@antiraid-ext/settings".assertBoolean
local kv = require "@antiraid-core/plugins/kv"
local datetime = require "@antiraid/datetime"
local set = require"@antiraid-ext/set"
local isDevMode = require"../devs".isInDevMode

local scopePrefix = if isDevMode then "builtins-dev" else "builtins"

local cacheExpiryTime = 60 -- Cache expiry time

export type CreateURLBlock = {
    user_id: string, -- ID of the user who added the URL block
    url: string, -- The URL to block
    reason: string, -- Reason for blocking the URL
}

export type URLBlock = {
    user_id: string, -- ID of the user who added the URL block
    url: string, -- The URL that is blocked
    reason: string, -- Reason for blocking the URL
    created_at: datetime.DateTime, -- When the URL block was created
}

export type URLBlockManager = {
    --- Get the enabled status 
    enabled: () -> boolean,
    --- Get the enabled status (cached)
    enabledcached: () -> boolean,
    --- Set the enabled status
    setenabled: (enabled: boolean) -> (),
    --- Returns a list of all URL blocks
    list: () -> {URLBlock},
    --- Returns a string set of all blocked URLs
    listurls: () -> set.Set<string>,
    --- Returns a string list of all blocked URLs (cached)
    listurlscached: () -> set.Set<string>,
    --- Sets a url block
    set: (data: CreateURLBlock) -> (),
    --- Deletes a url block
    delete: (url: string) -> (),
}

--- A data fetcher for URL blocks.
local function URLBlockManager(ctx: Primitives.TemplateContext, nocache_val: boolean?): URLBlockManager
    local nocache = nocache_val or false
    local self = {}

    type CachedUrls = {
        blocked: set.Set<string>,
        isenabled: boolean?,
        made: number
    }

    local blockCache: CachedUrls = {
        blocked = set.Set() :: set.Set<string>,
        made = -math.huge
    }

    local function _parseBlock(item: kv.KvRecord): URLBlock
        assert(item.exists, "Internal error: AFK item does not exist")
        local url = item.key
        local userId = assertString("user_id", item.value.user_id)
        local reason = assertString("reason", item.value.reason)
        local createdAt = item.created_at

        return {
            user_id = userId,
            url = url,
            reason = reason,
            created_at = createdAt,
        }
    end

    local function enabled(): boolean
        local isEnabled = ctx.KV:get("status", {scopePrefix .. ".urlblock.status"}) or false
        isEnabled = assertBoolean("enabled", isEnabled)
        if not nocache then
            blockCache.isenabled = isEnabled
        end
        return isEnabled
    end

    local function enabledcached(): boolean
        if os.clock() - blockCache.made < cacheExpiryTime then
            return if blockCache.isenabled ~= nil then blockCache.isenabled else enabled()
        end

        return enabled()
    end

    local function setenabled(enabled: boolean): ()
        ctx.KV:set("status", enabled, {scopePrefix .. ".urlblock.status"})
        if not nocache then
            blockCache.isenabled = enabled
        end
    end

    local function list(): {URLBlock}
        local data = ctx.KV:find("%%", {scopePrefix .. ".urlblocks"})

        local urls = {}
        local urllinks = set.Set() :: set.Set<string>
        for _, item in data do
            local afk = _parseBlock(item)
            table.insert(urls, afk)
            urllinks.add(afk.url)
        end

        if not nocache then
            local isEnabled = enabled()

            blockCache = {
                blocked = urllinks,
                isenabled = isEnabled,
                made = os.clock(),
            }
        end

        return urls
    end

    local function listurls(): set.Set<string>
        local data = ctx.KV:find("%%", {scopePrefix .. ".urlblocks"})

        local urls = set.Set() :: set.Set<string>
        for _, item in data do
            local afk = _parseBlock(item)
            urls.add(afk.url) 
        end

        if not nocache then
            local isEnabled = enabled()

            blockCache = {
                blocked = urls,
                isenabled = isEnabled,
                made = os.clock(),
            }
        end

        return urls
    end

    local function set(url: CreateURLBlock): ()
        ctx.KV:set(url.url, {
            user_id = assertString("user_id", url.user_id),
            reason = assertString("reason", url.reason),
        }, {scopePrefix .. ".urlblocks"})

        if not nocache then
            blockCache.blocked.add(url.url)
        end
    end

    local function delete(url: string): ()
        ctx.KV:delete(url, {scopePrefix .. ".urlblocks"})
        if not nocache then
            blockCache.blocked.remove(url)
        end
    end

    local function listurlscached(): set.Set<string>
        if os.clock() - blockCache.made < cacheExpiryTime then
            return blockCache.blocked
        end

        return listurls()
    end

    self.enabled = enabled
    self.enabledcached = enabledcached
    self.setenabled = setenabled
    self.list = list
    self.listurls = listurls
    self.listurlscached = listurlscached
    self.set = set
    self.delete = delete

    return self
end

return URLBlockManager