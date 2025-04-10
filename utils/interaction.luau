local discord = require "@discord-types/apiTypes"
local discordRestTypes = require "@discord-types/restTypes"
local executor = require "@antiraid-ext/executor"
local InteractionCallbackType = require "@discord-types/interaction".InteractionCallbackType
local MessageFlags = require "@discord-types/bitflags/message"
local promise = require "@antiraid/promise"
local array_mt = require "@antiraid/interop".array_metatable

local function reply(ge: executor.GlobalExecutor, interaction: discord.InteractionObject, data: discordRestTypes.CreateInteractionRequest)
    assert(array_mt, "array_mt is not set")
    return promise.yield(ge.discord:create_interaction_response({
        interaction_id = interaction.id,
        interaction_token = interaction.token,
        data = data,
    }))
end

local function replySimple(ge: executor.GlobalExecutor, interaction: discord.InteractionObject, content: string?, embeds: {discord.EmbedObject}?, ephemeral: boolean?)
    local flags = MessageFlags.new(0)
    if ephemeral then
        flags:setEphemeral()
    end
    return reply(ge, interaction, {
        type = InteractionCallbackType.ChannelMessageWithSource,
        data = {
            content = content or nil,
            embeds = setmetatable(embeds, array_mt),
            flags = flags.flag
        },
    } :: discordRestTypes.CreateInteractionRequest)
end

return {
    reply = reply,
    replySimple = replySimple,
}