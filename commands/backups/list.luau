local data = require"@antiraid-ext/frameworkv2/context"
local embed = require"../../auxutils/backups/embed"
local paginate = require "@antiraid-ext/frameworkv2/paginate"
local discord = require"@discord-types/apiTypes"
local units = require"@antiraid-ext/frameworkv2/unit"
local managers = require "../../auxutils/managers/managers"

local function list(data: data.CommandContext): nil
    data.interaction.assertpermission("backups.list")
    local mdm = managers.getmanagers(data.ctx).backupmetadata

    local backups = mdm.listarr()

    if #backups == 0 then
        return data.interaction.replysimpleembed("No backups found", "There are no backups available for this server.", units.RED_COLOR)
    end

    paginate.paginate(data, {
        id = "backups",
        numPages = #backups,
        embed = function(currentIdx: number): discord.EmbedObject 
            local backupData = backups[currentIdx]
            assert(backupData.value.filename, "Backup data does not contain a filename")
            local embed, _ = embed.toembed(
                data.ctx,
                {
                    id = backupData.key,
                    createdat = backupData.createdat.timestamp_seconds,
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