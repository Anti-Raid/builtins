local commandBuilder = require "@discord-types/builders/interaction/interaction"
local interactionutils = require "../../utils/interaction"

local function register()
    return commandBuilder.new({
        name = "serverinfo",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Shows information about this server/guild")
    :build()
end

local function run(data)
    local guild = data.ctx.Guild
    if not guild then
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Server Info",
                    description = "Could not fetch server information.",
                },
            },
            false
        )
    end
    local owner = guild.owner_id or "Unknown"
    local roleCount = guild.roles and #guild.roles or 0
    local channelCount = guild.channels and #guild.channels or 0
    local emojiCount = guild.emojis and #guild.emojis or 0
    local boostLevel = guild.premium_tier or "None"
    local boostCount = guild.premium_subscription_count or 0
    local verificationLevel = guild.verification_level or "Unknown"
    local features = guild.features and table.concat(guild.features, ", ") or "None"

    local embed = {
        title = guild.name or "Server Info",
        description = string.format(
            "ID: `%s`\nOwner: <@%s>\nCreated: <t:%d:F>",
            guild.id or "Unknown",
            owner,
            math.floor((guild.created_at or os.time()) / 1000)
        ),
        fields = {
            { name = "Members", value = tostring(guild.member_count or 0), inline = true },
            { name = "Roles", value = tostring(roleCount), inline = true },
            { name = "Channels", value = tostring(channelCount), inline = true },
            { name = "Emojis", value = tostring(emojiCount), inline = true },
            { name = "Boosts", value = string.format("Level %s (%d boosts)", boostLevel, boostCount), inline = true },
            { name = "Verification", value = tostring(verificationLevel), inline = true },
            { name = "Features", value = features, inline = false },
        },
        thumbnail = { url = guild.icon_url or "" },
    }
    return interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {embed},
        false
    )
end

return {
    register = register,
    run = run,
}
