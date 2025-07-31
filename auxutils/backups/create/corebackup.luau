local Primitives = require"@antiraid-core/primitives"
local apitypes = require"@discord-types/apiTypes"
local channel = require"@discord-types/channel"
local types = require"../backups"
local channelallocs = require"../channelallocs"
local set = require"@antiraid-ext/set"
local typesext = require"@antiraid/typesext"
local pp = require"@antiraid-ext/prettyprint"
local interop = require"@antiraid/interop"

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
            opts.channels,
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

        messages = channelallocs.FetchAllocatedMessages(
            channelAllocations,
            function(channelId: string, count: number): {apitypes.MessageObject}
                updater.addStatus(`Fetching '{count}' messages from channel '{channelId}'...`)

                local messagesDiscord = ctx.Discord:get_channel_messages({
                    channel_id = channelId,
                    limit = count,
                }).data

                local function _assert(tab, parentKey) 
                    for k, v in tab :: any do
                        if type(k) == "number" then
                            assert(k >= 1, `Message key must be a string or >0 number, got {k} with tab {pp(tab)} and parent of {parentKey}`)
                            if getmetatable(tab) == nil then
                                setmetatable(tab, interop.array_metatable)
                            end
                        else
                            assert(type(k) == "string", `Message key must be a string, got {type(k)}`)
                        end
                        if type(v) == "table" then
                            _assert(v, parentKey .. "->".. k) -- Recursively assert nested tables
                        end
                    end
                end

                _assert(messagesDiscord, "")

                updater.addStatus(`Fetched {#messagesDiscord} messages so far from channel {channelId}`)

                return messagesDiscord
            end,
            opts.maxMessages
        ) :: any
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