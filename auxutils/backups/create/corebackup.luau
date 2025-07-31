local Primitives = require"@antiraid-core/primitives"
local apitypes = require"@discord-types/apiTypes"
local channel = require"@discord-types/channel"
local types = require"../backups"
local channelallocs = require"../channelallocs"
local set = require"@antiraid-ext/set"
local typesext = require"@antiraid/typesext"

local function coreBackup(ctx: Primitives.TemplateContext, opts: types.BackupCreateOpts, updater: types.Updater): types.CoreBackupData 
    local guild = ctx.Discord:get_guild().data
    local channels = ctx.Discord:get_guild_channels().data

    if not guild.roles or #guild.roles == 0 then 
        local roles = ctx.Discord:get_guild_roles().data
        local rolesArr = {}
        for _, role in roles do table.insert(rolesArr, role) end
        guild.roles = rolesArr
    end

    local messages = {}
    local channelAllocationsFinal = {}
    if opts.backupMessages then 
        local botMember = ctx.Discord:get_guild_member(ctx.current_user.id).data
        local channelAllocations = channelallocs.CreateChannelAllocations(
            guild, 
            botMember,
            channels,
            set.Set("0") :: set.Set<typesext.U64Convertibles>,
            {
                channel.ChannelTypesMap.GuildText,
                channel.ChannelTypesMap.GuildNews,
                channel.ChannelTypesMap.AnnouncementThread,
                channel.ChannelTypesMap.PublicThread,
                channel.ChannelTypesMap.PrivateThread,
                channel.ChannelTypesMap.GuildForum,
            },
            opts.specialAllocations,
            opts.perChannel,
            opts.maxMessages
        )

        channelAllocationsFinal = channelAllocations.allocations

        local rolloverCount = 0
        if opts.rolloverLeftovers then
            rolloverCount = opts.perChannel
        end

        messages = channelallocs.FetchAllocatedMessages(
            channelAllocations,
            function(channelId: string, count: number): {apitypes.MessageObject}
                local finalMsgs = {}
                local currentId = ""
                while true do 
                    updater.addStatus(`Fetching messages for channel '{channelId}' and count '{count}' with current ID {currentId}...`)
                    if count <= #finalMsgs then 
                        break
                    end

                    local limit = math.min(100, count - #finalMsgs)
                    local messagesDiscord = ctx.Discord:get_channel_messages({
                        channel_id = channelId,
                        limit = limit,
                        before = currentId,
                    }).data

                    for i, msg in messagesDiscord do 
                        -- Prepend as we are going from new to old
                        table.insert(finalMsgs, 1, msg)

                        if i == #messagesDiscord then
                            currentId = msg.id
                        end
                    end
                end

                return finalMsgs
            end,
            opts.maxMessages,
            rolloverCount
        )
    end

    return {
        guild = guild,
        channels = channels,
        messages = messages,
        options = opts,
        channel_allocation = channelAllocationsFinal,
    }
end

return coreBackup