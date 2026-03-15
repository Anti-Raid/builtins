local data = require"@antiraid-ext/frameworkv2/context"
local canModeratorDo = require "@antiraid-ext/utils/modhierarchy".canModeratorDo
local backupTypes = require"../../auxutils/backups/backups"
local createBackup = require "../../auxutils/backups/create/start"
local units = require"@antiraid-ext/frameworkv2/unit"
local sb = require"@antiraid-ext/utils/statusbuffer"
local tempbutton = require"@antiraid-ext/frameworkv2/tempbutton"
local embed = require"../../auxutils/backups/embed"

local function create(data: data.CommandContext): nil
    canModeratorDo(
        data.framework.userinfomanager.get(data.interaction.userid(), data.interaction.interaction),
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
                        return data.interaction.replysimpleembed("Error processing command", "Invalid format for special allocations. Use channel_id=number,channel_id=number. Failing entry was: ``" .. pair .. "``", units.RED_COLOR)
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
    local buf = sb.StatusBuffer()
    local tempbutton = tempbutton.tempbutton(data, {
        title = "View Logs",
        embed = function() 
            return {
                title = "Logs",
                description = table.concat(sb.stringifybuffer(buf), "\n"),
                color = units.YELLOW_COLOR
            }
        end
    })
    data.interaction.replysimpleembed("Creating backup", "Please wait...", units.GREEN_COLOR, {tempbutton.actionrow})

    local built = createBackup(data.ctx, opts, enckey, buf)

    -- Upload and save metadata
    data.ctx.KV:set(
        built.id, 
        {
            filename = built.filename,
            created_by = data.interaction.userid(),
        },
        {"builtins.backups.metadata"}
    )
    data.ctx.ObjectStorage:upload_file(built.filename, built.backup)

    local embed, comps = embed.toembed(data.ctx, {
        id = built.id,
        finalFilePath = built.filename,
    })

    data.interaction.replyedit({
        embeds = {embed},
        components = comps
    })

    return nil
end

return create