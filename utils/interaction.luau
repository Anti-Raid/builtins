local discord = require "@discord-types/apiTypes"
local discordRestTypes = require "@discord-types/restTypes"
local InteractionCallbackType = require "@discord-types/interaction".InteractionCallbackType
local MessageFlags = require "@discord-types/bitflags/message"
local Primitives = require"@antiraid-core/primitives"
local array_mt = require "@antiraid/interop".array_metatable

local function edit(ctx: Primitives.TemplateContext, interaction: discord.InteractionObject, data: discordRestTypes.EditWebhookMessageRequest)
    assert(array_mt, "array_mt is not set")
    return ctx.Discord:edit_original_interaction_response({
        interaction_token = interaction.token,
        data = data,
    })
end

local function reply(ctx: Primitives.TemplateContext, interaction: discord.InteractionObject, data: discordRestTypes.CreateInteractionRequest)
    assert(array_mt, "array_mt is not set")
    return ctx.Discord:create_interaction_response({
        interaction_id = interaction.id,
        interaction_token = interaction.token,
        data = data,
    })
end

local function replySimple(ctx: Primitives.TemplateContext, interaction: discord.InteractionObject, content: string?, embeds: {discord.EmbedObject}?, ephemeral: boolean?, components: {discord.ComponentObjects}?)
    local flags = MessageFlags.new(0)
    if ephemeral then
        flags:setEphemeral()
    end
    return reply(ctx, interaction, {
        type = InteractionCallbackType.ChannelMessageWithSource,
        data = {
            content = content or nil,
            embeds = if embeds then setmetatable(embeds, array_mt) else nil,
            flags = flags.flag,
            components = if components then setmetatable(components, array_mt) else nil,
        },
    } :: discordRestTypes.CreateInteractionRequest)
end

local function replyAck(ctx: Primitives.TemplateContext, interaction: discord.InteractionObject)
    assert(array_mt, "array_mt is not set")
    return reply(ctx, interaction, {
        type = InteractionCallbackType.Pong,
    } :: discordRestTypes.CreateInteractionRequest)
end

local function replyUpdate(ctx: Primitives.TemplateContext, interaction: discord.InteractionObject, content: string?, embeds: {discord.EmbedObject}?, components: {discord.ComponentObjects}?)
    return reply(ctx, interaction, {
        type = InteractionCallbackType.UpdateMessage,
        data = {
            content = content or nil,
            embeds = if embeds then setmetatable(embeds, array_mt) else nil,
            components = if components then setmetatable(components, array_mt) else nil,
        },
    } :: discordRestTypes.CreateInteractionRequest)
end

-- https://discord.com/developers/docs/interactions/receiving-and-responding#interaction-response-object-autocomplete
local function replyAutocomplete(ctx: Primitives.TemplateContext, interaction: discord.InteractionObject, choices: {discord.ApplicationCommandOptionChoiceObject})
    return reply(ctx, interaction, {
        type = InteractionCallbackType.ApplicationCommandAutocompleteResult,
        data = {
            choices = if choices then setmetatable(choices, array_mt) else nil,
        },
    } :: discordRestTypes.CreateInteractionRequest)
end

local function editSimple(ctx: Primitives.TemplateContext, interaction: discord.InteractionObject, content: string?, embeds: {discord.EmbedObject}?, components: {discord.ComponentObjects}?)
    return edit(ctx, interaction, {
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