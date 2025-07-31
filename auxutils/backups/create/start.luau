local Primitives = require"@antiraid-core/primitives"
local datamgmt = require"@antiraid/datamgmt"
local coreBackup = require"./corebackup"
local types = require"../backups"
local serde = require"@lune/serde"
local finalize = require"./finalize"
local assetfetch = require"./assetfetch"
local validate = require"./validate"

local function createBackup(ctx: Primitives.TemplateContext, opts: types.BackupCreateOpts, enckey: string?, updater: types.Updater): types.BuiltBackup
    validate.validate(opts)
    return validate.scope(updater, function() 
        updater.addStatus("Collecting core backup data...")
        local coreBackup = coreBackup(ctx, opts, updater)
        local tararchive = datamgmt.TarArchive()
        tararchive:addfile("core.json", serde.encode("json", coreBackup))

        -- Add assets
        for _, asset in opts.backupGuildAssets do
            local assetBlob = assetfetch.fetchAsset(ctx, coreBackup.guild, asset)
            if assetBlob then
                tararchive:addfile(`assets/{asset}.jpg`, assetBlob)
            end
        end

        return finalize.buildBackup(tararchive, if enckey and #enckey > 0 then enckey else nil)
    end)
end

return createBackup