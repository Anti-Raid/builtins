local Primitives = require"@antiraid-core/primitives"
local datamgmt = require"@antiraid/datamgmt"
local blob = require"@antiraid-core/blob"
local types = require"../backups"
local serde = require"@lune/serde"
local assetfetch = require"../create/assetfetch"
local conditions = require"../conditions"

local function isEncryptedBackup(filename: string): boolean
    return filename:sub(-1) == "e"
end

type BackupFile = "arb1" | "arb2" | nil

local function isBackupFile(filename: string): BackupFile
    if filename:sub(-5) == ".arb1" or filename:sub(-6) == ".arb1e" then
        return "arb1"
    elseif filename:sub(-5) == ".arb2" or filename:sub(-6) == ".arb2e" then
        return "arb2"  
    else 
        return nil
    end
end

local function loadBackupBlob(src: types.RestoreSource, blob: blob.Blob, enckey: string?): types.LoadedBackup 
    local filename = if src.type == "attachment" then src.filename else src.filepath
    
    local format = isBackupFile(filename)
    if not format then
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

    local coreData: types.CoreBackupData
    if format == "arb1" then 
        local coreDataBlob = tarArchive:takefile("core.json")
        assert(coreDataBlob, "Core backup data not found in backup archive")
        coreData = serde.decode("json", coreDataBlob:tobuffer())
    elseif format == "arb2" then
        local coreDataBlob = tarArchive:takefile("core.json.gz")
        assert(coreDataBlob, "Core backup data not found in backup archive")
        local decompressed = serde.decompress("gzip", coreDataBlob:tobuffer())
        coreData = serde.decode("json", decompressed)
    else
        error("Unsupported backup format: " .. format)
    end

    -- Validate create options and try to fix them if they are not within the allowed limits
    if coreData.options.maxMessages < 1 or coreData.options.maxMessages > conditions.MAX_MESSAGES then
        coreData.options.maxMessages = conditions.MAX_MESSAGES
    end

    if coreData.options.perChannel < conditions.MIN_PER_CHANNEL or coreData.options.perChannel > conditions.MAX_PER_CHANNEL then
        coreData.options.perChannel = conditions.MAX_PER_CHANNEL
    end

    if coreData.options.perChannel > coreData.options.maxMessages then
        coreData.options.perChannel = coreData.options.maxMessages
    end

    local assets = {}
    for _, assetEntry in tarArchive:entries() do
        -- Split the `assets/` prefix
        local split = assetEntry:split("assets/")
        local assetPath = split[2]
        -- Remove the file extension
        local asplit = assetPath:split(".")
        local assetName = asplit[1]

        if not table.find(assetfetch.ASSETS :: {string}, assetName) then
            continue -- Skip if the asset is not recognized
        end

        assets[assetName :: assetfetch.Asset] = tarArchive:takefile(assetEntry)
    end

    return {
        core = coreData,
        assets = assets,
    }
end

--- Loads a backup file from a given source
local function loadBackupFile(ctx: Primitives.TemplateContext, src: types.RestoreSource, enckey: string?, updater: types.Updater): types.LoadedBackup
    updater.addStatus("Loading backup data...")
    local blob = nil
    if src.type == "attachment" then 
        local resp = ctx.HTTPClient.new_request("GET", src.url):send()
        
        if resp.status ~= 200 then 
            error("Failed to download backup file from source: " .. src.type .. " with status code: " .. resp.status)
        end

        blob = resp:blob()
    else 
        blob = ctx.ObjectStorage:download_file(src.filepath)
    end
    assert(blob, "Failed to download backup file from source: " .. src.type)
    blob = blob :: blob.Blob
    updater.addStatus("Downloaded backup file of size " .. #blob .. " bytes")
    local loadedBackup = loadBackupBlob(src, blob, enckey)
    updater.addStatus("Parsed backup data successfully")

    return loadedBackup
end

--- Helper function to convert a asset to a base64 data URL
local function assetToDataURL(mimetype: string, blob: blob.Blob): string
    return "data:" .. mimetype .. ";base64," .. datamgmt.base64encode(blob)
end

return {
    isEncryptedBackup = isEncryptedBackup,
    isBackupFile = isBackupFile,
    loadBackupBlob = loadBackupBlob,
    loadBackupFile = loadBackupFile,
    assetToDataURL = assetToDataURL
}