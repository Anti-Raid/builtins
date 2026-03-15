local data = require"@antiraid-ext/frameworkv2/context"
local units = require"@antiraid-ext/frameworkv2/unit"

local function delete(data: data.CommandContext): nil
    data.interaction.assertpermission("backups.delete")

    local backupId = nil
    for _, opt in data.command.options do
        if opt.name == "backup_id" and opt.value.kind == "String" then
            backupId = opt.value.value
        end
    end
    if not backupId then
        return data.interaction.replysimpleembed("Error processing command", "You must specify a backup ID to delete.", units.RED_COLOR)
    end

    -- Directly call delete, rely on global xpcall for error handling
    local backupData = data.ctx.KV:getrecord(backupId, {"builtins.backups.metadata"})

    if not backupData.exists then
        return data.interaction.replysimpleembed("Error processing command", "Backup with ID `" .. backupId .. "` does not exist.", units.RED_COLOR)
    end

    assert(type(backupData.value.filename) == "string", "Backup data does not contain a filename")

    -- Delete the backup from ObjectStorage first
    
    data.ctx.ObjectStorage:delete_file(backupData.value.filename)
    data.ctx.KV:delete(backupId, {"builtins.backups.metadata"})
    return data.interaction.replysimpleembed("Backup Deleted", string.format("Backup with ID `%s` has been deleted.", backupId), units.GREEN_COLOR)
end

return delete