local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require "../data"
local interactionutils = require "@antiraid-ext/utils/interaction"
local datetime = require("@antiraid/datetime")
local formatTimeDelta = require "@antiraid-ext/formattimedelta"
local datastores = require"@antiraid-core/plugins/datastores"

local function register() 
    return commandBuilder.new({
        name = "stats",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("View stats about the bot")
    :build()
end

local function run(data: data.RunData): nil
    local StatsDataStore = data.ctx.DataStores.StatsStore
    if not StatsDataStore then
        interactionutils.replySimple(
            data.ctx,
            data.interaction,
            "Stats data store not found",
            {},
            true
        )
        return nil
    end
    local sds = StatsDataStore :: datastores.StatsStore
    local stats = sds.stats()

    local startedAt = datetime.UTC:now():duration_since(stats.last_started_at)

    return interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Stats",
                description = "Here are the some cool bot stats",
                fields = {
                    { name = "Bot Name", value = tostring(data.ctx.current_user.username), inline = true },
                    { name = "Total Users", value = tostring(stats.total_users), inline = true },
                    { name = "Total Servers", value = tostring(stats.total_guilds), inline = true },
                    { name = "Total Cached Servers", value = tostring(stats.total_cached_guilds), inline = true },
                    { name = "Bot Last Started", value = "<t:" .. stats.last_started_at.timestamp_seconds .. ">", inline = true },
                    { name = "Bot Uptime", value = formatTimeDelta(startedAt), inline = true }
                }
            }
        },
        false
    )
end

return {
    register = register,
    run = run,
}