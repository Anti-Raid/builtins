local discord = require "@discord-types/apiTypes"
local discordRestTypes = require "@discord-types/restTypes"
local executor = require "@antiraid-ext/executor"
local InteractionCallbackType = require "@discord-types/interaction".InteractionCallbackType
local MessageFlags = require "@discord-types/bitflags/message"
local promise = require "@antiraid/promise"
local array_mt = require "@antiraid/interop".array_metatable

local function edit(ge: executor.GlobalExecutor, interaction: discord.InteractionObject, data: discordRestTypes.EditWebhookMessageRequest)
    assert(array_mt, "array_mt is not set")
    return promise.yield(ge.discord:edit_original_interaction_response({
        interaction_token = interaction.token,
        data = data,
    }))
end

local function reply(ge: executor.GlobalExecutor, interaction: discord.InteractionObject, data: discordRestTypes.CreateInteractionRequest)
    assert(array_mt, "array_mt is not set")
    return promise.yield(ge.discord:create_interaction_response({
        interaction_id = interaction.id,
        interaction_token = interaction.token,
        data = data,
    }))
end

local function replySimple(ge: executor.GlobalExecutor, interaction: discord.InteractionObject, content: string?, embeds: {discord.EmbedObject}?, ephemeral: boolean?, components: {discord.ComponentObjects}?)
    local flags = MessageFlags.new(0)
    if ephemeral then
        flags:setEphemeral()
    end
    return reply(ge, interaction, {
        type = InteractionCallbackType.ChannelMessageWithSource,
        data = {
            content = content or nil,
            embeds = if embeds then setmetatable(embeds, array_mt) else nil,
            flags = flags.flag,
            components = if components then setmetatable(components, array_mt) else nil,
        },
    } :: discordRestTypes.CreateInteractionRequest)
end

local function replyAck(ge: executor.GlobalExecutor, interaction: discord.InteractionObject)
    assert(array_mt, "array_mt is not set")
    return reply(ge, interaction, {
        type = InteractionCallbackType.Pong,
    } :: discordRestTypes.CreateInteractionRequest)
end

local function replyUpdate(ge: executor.GlobalExecutor, interaction: discord.InteractionObject, content: string?, embeds: {discord.EmbedObject}?, components: {discord.ComponentObjects}?)
    return reply(ge, interaction, {
        type = InteractionCallbackType.UpdateMessage,
        data = {
            content = content or nil,
            embeds = if embeds then setmetatable(embeds, array_mt) else nil,
            components = if components then setmetatable(components, array_mt) else nil,
        },
    } :: discordRestTypes.CreateInteractionRequest)
end

-- https://discord.com/developers/docs/interactions/receiving-and-responding#interaction-response-object-autocomplete
local function replyAutocomplete(ge: executor.GlobalExecutor, interaction: discord.InteractionObject, choices: {discord.ApplicationCommandOptionChoiceObject})
    return reply(ge, interaction, {
        type = InteractionCallbackType.ApplicationCommandAutocompleteResult,
        data = {
            choices = if choices then setmetatable(choices, array_mt) else nil,
        },
    } :: discordRestTypes.CreateInteractionRequest)
end

local function editSimple(ge: executor.GlobalExecutor, interaction: discord.InteractionObject, content: string?, embeds: {discord.EmbedObject}?, components: {discord.ComponentObjects}?)
    return edit(ge, interaction, {
        content = content or nil,
        embeds = if embeds then setmetatable(embeds, array_mt) else nil,
        components = if components then setmetatable(components, array_mt) else nil,
    } :: any)
end

return {
    reply = reply,
    replySimple = replySimple,
    replyAck = replyAck,
    replyUpdate = replyUpdate,
    replyAutocomplete = replyAutocomplete,
    edit = edit,
    editSimple = editSimple,
}