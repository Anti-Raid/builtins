local apiTypes = require "@discord-types/apiTypes"
local typesext = require "@antiraid/typesext"

local function avatarUrl(user: apiTypes.UserObject)
    if user.avatar then 
        return "https://cdn.discordapp.com/avatars/" .. user.id .. "/" .. user.avatar .. ".png"
    end

    local index = 0
    if user.discriminator or user.discriminator == "0" or user.discriminator == "0000" then
        index = tostring((tonumber(user.discriminator) or 0) % 5)
    else
        index = tostring(typesext.bitu64.rshift(typesext.U64((user :: any).id), 22) % 6) -- ((user_id >> 22) % 6)
    end

    local avatarUrl = "https://cdn.discordapp.com/embed/avatars/" .. (index) .. ".png"
    return avatarUrl
end

local function guildIconUrl(guild: apiTypes.GuildObject): string
    if guild.icon then
        return "https://cdn.discordapp.com/icons/" .. guild.id .. "/" .. guild.icon .. ".png" :: any
    end
    return "https://cdn.discordapp.com/embed/avatars/0.png"
end

return {
    avatarUrl = avatarUrl,
    guildIconUrl = guildIconUrl,
}