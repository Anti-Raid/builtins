local apitypes = require "@discord-types/apiTypes"
local Primitives = require "@antiraid-core/primitives"
local HoneypotManager = require "./honeypotmanager"
local Framework = require"@antiraid-ext/framework/dispatch"

local honeypotManager: HoneypotManager.HoneypotManager? = nil
local function honeypotHandler(msg: apitypes.MessageObject, ctx: Primitives.TemplateContext): ()
    -- Honeypots
    if not msg.author then return end
    if not msg.content then return end

    if #msg.content < 10 then
        return -- Ignore short messages
    end

    local mentions = (msg.mentions or {}) :: {apitypes.UserObject}
    if #mentions > 5 then return end -- Only 3 mention allowed for AFK

    if not honeypotManager then
        honeypotManager = HoneypotManager(ctx)
    end
    assert(honeypotManager, "Internal error: HoneypotManager is nil")
    local honeypots = honeypotManager.listcached()
    for _, honeypot in honeypots do
        if msg.channel_id == honeypot.channelid then
            if msg.author.bot and honeypot.botallowed then break end -- Ignore clearly bot messages if bots are allowed in the honeypot
            local fw = Framework.getFrameworkBaseData(ctx)
            fw.punishmentmanager.createUserPunishment({
                userId = msg.author.id,
                punishment = honeypot.punishment,
                modId = nil, -- System
                reason = "Attempt to message in honeypot channel",
            })
            break -- No need to check further honeypots
        end
    end
end

return honeypotHandler