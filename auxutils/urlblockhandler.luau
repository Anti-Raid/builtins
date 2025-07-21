local apitypes = require "@discord-types/apiTypes"
local Primitives = require "@antiraid-core/primitives"
local URLBlockManager = require "./urlblockmanager"
local parseUrls = require"@antiraid-ext/utils/urlextractor".parseUrls

local urlblockmanager: URLBlockManager.URLBlockManager? = nil
local function urlblockHandler(msg: apitypes.MessageObject, ctx: Primitives.TemplateContext): ()
    -- URL Blocking
    if not msg.author then return end
    if msg.author.bot then return end -- Ignore bot messages
    if not msg.content then return end -- Ignore messages without content

    if not urlblockmanager then
        urlblockmanager = URLBlockManager(ctx)
    end
    assert(urlblockmanager, "Internal error: AFKManager is nil")

    if not urlblockmanager.enabledcached() then
        return -- URL blocking is disabled
    end

    local blockedUrls = urlblockmanager.listurlscached()
    if #blockedUrls == 0 then return end -- No URLs blocked

    local urls = parseUrls(msg.content)
    for _, url in urls do
        if not #url then continue end -- Ignore nil URLs
        if blockedUrls.exists(url) then
            ctx.Discord:delete_message(msg.channel_id or error("msg.channel_id is nil"), msg.id or error("msg.id is nil"), "Blocked URL")
            return -- Stop processing further URLs
        end
    end
end

return urlblockHandler