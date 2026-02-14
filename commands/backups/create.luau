local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorDo = require "@antiraid-ext/utils/modhierarchy".canModeratorDo
local backupTypes = require"../../auxutils/backups/backups"
local embed = require "../../auxutils/backups/embed"
local createBackup = require "../../auxutils/backups/create/start"

local POLL_INTERVAL_CREATE = 3

local function create(data: data.RunData): nil
    canModeratorDo(
        data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
        "backups.create"
    )

    local opts: backupTypes.BackupCreateOpts = {
        channels = {},
        perChannel = 100,
        maxMessages = 100,
        backupMessages = false,
        backupGuildAssets = {"icon","splash","banner"},
        rolloverLeftovers = true,
        specialAllocations = {},
    }
    local enckey: string? = nil

    for _, opt in data.command.options do 
        if opt.name == "channels" then
            if opt.value.kind == "String" then 
                opts.channels = string.split(opt.value.value, ",")
            end
        elseif opt.name == "per_channel" then
            if opt.value.kind == "Integer" then
                opts.perChannel = opt.value.value
            end
        elseif opt.name == "max_messages" then
            if opt.value.kind == "Integer" then
                opts.maxMessages = opt.value.value
            end
        elseif opt.name == "messages" then
            if opt.value.kind == "Boolean" then
                opts.backupMessages = opt.value.value
            end
        elseif opt.name == "backup_guild_assets" then
            if opt.value.kind == "String" then
                opts.backupGuildAssets = string.split(opt.value.value, ",") :: any
            end
        elseif opt.name == "special_allocations" then
            if opt.value.kind == "String" then 
                local specialAllocationsStr = opt.value.value
                for _, pair in string.split(specialAllocationsStr, ",") do
                    local key, value = string.match(pair, "(%d+)=(%d+)")
                    if key and value then
                        opts.specialAllocations[key] = tonumber(value)
                    else 
                        return interactionutils.replySimple(
                            data.ctx,
                            data.interaction,
                            nil,
                            {
                                {
                                    title = "Error processing command",
                                    description = "Invalid format for special allocations. Use channel_id=number,channel_id=number. Failing entry was: ``" .. pair .. "``",
                                },
                            },
                            false
                        )
                    end
                end                    
            end
        elseif opt.name == "password" then
            if opt.value.kind == "String" then
                enckey = opt.value.value
            end
        end
    end

    -- Send spawning message
    interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Creating backup",
                description = "Starting backup...",
            },
        },
        true
    )

    data.sethasEdited(true)

    embed.updateTillComplete({
        interval = POLL_INTERVAL_CREATE,
        spawner = function(updater: backupTypes.Updater, initial: embed.EmbedData) 
            local built = createBackup(data.ctx, opts, enckey, updater)

            -- Upload and save metadata
            data.ctx.KV:set(
                built.id, 
                {
                    filename = built.filename,
                    created_by = extractUserIdFromInteraction(data.interaction),
                    num_updates = initial.numUpdates or 0,
                },
                {"builtins.backups.metadata"}
            )
            data.ctx.ObjectStorage:upload_file(built.filename, built.backup)
            initial.finalFilePath = built.filename
        end,
        callback = function(embedData: embed.EmbedData) 
            if embedData.state == "failed" then return end
            local embed, components = embed.backupJobToEmbed(
                data.ctx,
                embedData,
                true,
                true
            )

            -- Edit original interaction response with the job status
            interactionutils.editSimple(
                data.ctx,
                data.interaction,
                nil,
                {embed},
                components
            )
        end,
    })

    return nil
end

return create