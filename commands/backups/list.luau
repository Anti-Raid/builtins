local data = require"@antiraid-ext/frameworkv2/context"
local embed = require"../../auxutils/backups/embed"
local paginate = require "@antiraid-ext/frameworkv2/paginate"
local discord = require"@discord-types/apiTypes"
local units = require"@antiraid-ext/frameworkv2/unit"

local function list(data: data.CommandContext): nil
    data.interaction.assertpermission("backups.list")

    local backups = data.ctx.KV:find("%%", {"builtins.backups.metadata"})

    if #backups == 0 then
        return data.interaction.replysimpleembed("No backups found", "There are no backups available for this server.", units.RED_COLOR)
    end

    paginate.paginate(data, {
        id = "backups",
        numPages = #backups,
        embed = function(currentIdx: number): discord.EmbedObject 
            local backupData = backups[currentIdx]
            assert(backupData and backupData.exists, "Backup data not found for index " .. currentIdx)
            assert(backupData.value.filename, "Backup data does not contain a filename")
            local embed, _ = embed.toembed(
                data.ctx,
                {
                    id = backupData.key,
                    createdat = backupData.created_at.timestamp_seconds,
                    statuses = {},
                    state = "completed", -- Backups v2 doesnt store failed backups
                    numUpdates = backupData.value.num_updates or 0,
                    finalFilePath = backupData.value.filename,
                },
                true
            )
            return embed
        end
    })
    return nil
end

return list