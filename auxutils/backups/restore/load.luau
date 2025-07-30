local datamgmt = require"@antiraid/datamgmt"
local blob = require"@antiraid-core/blob"
local types = require"../backups"
local serde = require"@lune/serde"
local assetfetch = require"../create/assetfetch"

local function isEncryptedBackup(filename: string): boolean
    return filename:sub(-6) == ".arb1e"
end

local function isBackupFile(filename: string): boolean
    return filename:sub(-5) == ".arb1" or filename:sub(-6) == ".arb1e"
end

local function loadBackupBlob(filename: string, blob: blob.Blob, enckey: string?): types.LoadedBackup 
    if not isBackupFile(filename) then
        error("Invalid backup file: " .. filename)
    end

    local data = blob
    if isEncryptedBackup(filename) then
        if not enckey then
            error("Cannot load encrypted backup without an encryption key")
        end
        data = datamgmt.aes256decrypt(blob, enckey)
    end

    local tarArchive = datamgmt.TarArchive(data)

    local coreDataBlob = tarArchive:takefile("core.json")
    assert(coreDataBlob, "Core backup data not found in backup archive")
    local coreData = serde.decode("json", coreDataBlob:tobuffer())

    local assets = {}
    for _, assetEntry in tarArchive:entries() do
        -- Split the `assets/` prefix
        local split = assetEntry:split("assets/")
        local assetPath = split[2]
        -- Remove the file extension
        local asplit = assetPath:split(".")
        local assetName = asplit[1]

        if not table.find(assetfetch.ASSETS, assetName) then
            continue -- Skip if the asset is not recognized
        end

        assets[assetName :: assetfetch.Asset] = tarArchive:takefile(assetEntry)
    end

    return {
        core = coreData,
        assets = assets,
    }
end

return {
    isEncryptedBackup = isEncryptedBackup,
    isBackupFile = isBackupFile,
    loadBackupBlob = loadBackupBlob,
}