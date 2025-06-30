local commandBuilder = require "@discord-types/builders/interaction/interaction"
local interactionutils = require "../../utils/interaction"
local NewSnowflake = require "@discord-types/snowflake"

local function getCreationTimestampFromSnowflake(snowflake: string): number
    return NewSnowflake.new(snowflake):getTimestamp().timestamp_seconds
end

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
    local discord = data.ctx.Discord
    local guild = discord:get_guild().data
    if not guild then
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            { { title = "Server Info", description = "Could not fetch server information." } },
            false
        )
    end

    local guildId = guild.id
    local preview = discord:get_guild_preview(guildId)
    local channels = discord:get_guild_channels(guildId).data or {}
    local roles = discord:get_guild_roles(guildId).data or {}
    local emojis = guild.emojis or {}
    local stickers = discord.get_guild_stickers and (discord:get_guild_stickers(guildId).data or {}) or {}

    local textChannels, voiceChannels, categories, threads, newsChannels = 0, 0, 0, 0, 0
    for _, ch in ipairs(channels) do
        if ch.type == 0 then textChannels += 1
        elseif ch.type == 2 then voiceChannels += 1
        elseif ch.type == 4 then categories += 1
        elseif ch.type == 5 then newsChannels += 1
        elseif ch.type == 10 or ch.type == 11 or ch.type == 12 then threads += 1
        end
    end

    local animatedEmojis, staticEmojis = 0, 0
    for _, emoji in ipairs(emojis) do
        if emoji.animated then
            animatedEmojis += 1
        else
            staticEmojis += 1
        end
    end

    local highestRole: { id: string, position: number }? = nil
    for _, r: { id: string, position: number } in ipairs(roles) do
        if not highestRole or r.position > highestRole.position then
            highestRole = r
        end
    end

    local memberCount = preview and preview.data and preview.data.approximate_member_count or guild.member_count or 0
    local boostLevel = guild.premium_tier or "None"
    local boostCount = guild.premium_subscription_count or 0
    local verificationLevel = guild.verification_level or "Unknown"
    local features = guild.features and table.concat(guild.features, ", ") or "None"
    local creationTimestamp = getCreationTimestampFromSnowflake(guildId)

    local afkTimeout = typeof(guild.afk_timeout) == "number" and (guild.afk_timeout / 60) or 0
    local afkChannel = guild.afk_channel_id and string.format("<#%s>", guild.afk_channel_id) or "None"
    local nsfwLevel = guild.nsfw_level or "Unknown"

    local embed = {
        title = guild.name or "Server Info",
        description = string.format(
            "ID: `%s`\nOwner: <@%s>\nCreated: <t:%d:F>",
            guildId,
            guild.owner_id or "Unknown",
            creationTimestamp
        ),
        fields = {
            { name = "Members", value = tostring(memberCount), inline = true },
            { name = "Highest Role", value = highestRole and string.format("<@&%s>", highestRole.id) or "Unknown", inline = true },

            { name = "Text Channels", value = tostring(textChannels), inline = true },
            { name = "Voice Channels", value = tostring(voiceChannels), inline = true },
            { name = "Categories", value = tostring(categories), inline = true },

            { name = "Static Emojis", value = tostring(staticEmojis), inline = true },
            { name = "Animated Emojis", value = tostring(animatedEmojis), inline = true },
            { name = "Stickers", value = tostring(#stickers), inline = true },

            { name = "Boosts", value = string.format("Level %s (%d boosts)", boostLevel, boostCount), inline = true },
            { name = "Verification", value = tostring(verificationLevel), inline = true },
            { name = "NSFW Level", value = tostring(nsfwLevel), inline = true },

            { name = "AFK Channel", value = afkChannel, inline = true },
            { name = "AFK Timeout", value = string.format("%d minutes", afkTimeout), inline = true },

            { name = "Features", value = features, inline = false },
        },
        thumbnail = { url = guild.icon_url or "" },
    }

    return interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        { embed },
        false
    )
end

return {
    register = register,
    run = run,
}
