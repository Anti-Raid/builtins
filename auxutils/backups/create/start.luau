local Primitives = require"@antiraid-core/primitives"
local datamgmt = require"@antiraid/datamgmt"
local coreBackup = require"./corebackup"
local types = require"../backups"
local serde = require"@lune/serde"
local finalize = require"./finalize"
local assetfetch = require"./assetfetch"
local validate = require"./validate"
local typesext = require"@antiraid/typesext"

local function createBackup(ctx: Primitives.TemplateContext, opts: types.BackupCreateOpts, enckey: string?, updater: types.Updater): types.BuiltBackup
    validate.validate(opts)
    return validate.scope(updater, function() 
        local id = typesext.randstring(24)
        updater.setId(id)

        updater.addStatus("Collecting core backup data with perChannel of " .. opts.perChannel .. " and maxMessages of " .. opts.maxMessages)
        local coreBackup = coreBackup(ctx, opts, updater)
        updater.addStatus("Generating backup archive")
        local tararchive = datamgmt.TarArchive()
        local encoded = serde.encode("json", coreBackup)
        tararchive:addfile("core.json", encoded)

        -- Add assets
        for _, asset in opts.backupGuildAssets do
            local assetBlob = assetfetch.fetchAsset(ctx, coreBackup.guild, asset)
            if assetBlob then
                tararchive:addfile(`assets/{asset}.jpg`, assetBlob)
            end
        end

        return finalize.buildBackup(id, tararchive, if enckey and #enckey > 0 then enckey else nil, updater)
    end)
end

return createBackup