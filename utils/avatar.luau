local apiTypes = require "@discord-types/apiTypes"
local typesext = require "@antiraid/typesext"
local null = require "@antiraid/interop".null

local function avatarUrl(user: apiTypes.UserObject)
    if user.avatar and user.avatar ~= null then 
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

return {
    avatarUrl = avatarUrl,
}