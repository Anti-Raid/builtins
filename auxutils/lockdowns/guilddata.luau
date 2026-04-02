local Primitives = require"@antiraid-core/primitives"
local discord = require("@discord-types/apiTypes")
local tloop = require"@antiraid-core/templateloop"

--- Base guild data
export type GuildData = {
    guild: discord.GuildObject,
    channels: {discord.ChannelObject},
}

--- Returns the guild data for the current context
local function guildData(ctx: Primitives.TemplateContext): GuildData 
    local loop = tloop.getRunningLoop(ctx)
    local guild = loop.discord:get_guild().data

    if not guild.roles or #guild.roles == 0 then 
        local roles = loop.discord:get_guild_roles().data

        local rolesArr = {}
        for _, role in roles do 
            table.insert(rolesArr, role)
        end

        guild.roles = rolesArr
    end

    local channels = loop.discord:get_guild_channels().data

    return {
        guild = guild,
        channels = channels
    }
end

return {
    guildData = guildData
}