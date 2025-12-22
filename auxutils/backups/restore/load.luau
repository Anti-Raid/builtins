local datamgmt = require"@antiraid/datamgmt"
local blob = require"@antiraid-core/blob"
local types = require"../backups"
local serde = require"@lune/serde"
local assetfetch = require"../create/assetfetch"
local conditions = require"../conditions"
local array = require"@antiraid-ext/array"

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

local function stripExcessMessages(coreData: types.CoreBackupData) 
    -- Ensure the messages match our limits by removing excess messages
    for channelId, messages in coreData.messages do
        if #messages > coreData.options.perChannel then
            coreData.messages[channelId] = array.slice(messages, 1, coreData.options.perChannel)
        end
    end

    -- Ensure the total number of messages does not exceed maxMessages
    local totalMessages = 0
    for _, messages in coreData.messages do
        totalMessages += #messages
    end

    -- Drop channels until we meet this requirement
    -- if we still don't meet this requirement
    if totalMessages > coreData.options.maxMessages then
        local iters = 0
        while totalMessages > coreData.options.maxMessages and iters <= conditions.MAX_STRIP_ITERS do 
            local nextChannel = nil
            local nextMsgCount = nil

            -- Get next channel using a generalized iteration
            for channelId, messages in coreData.messages do 
                nextChannel = channelId
                nextMsgCount = #messages
                break
            end

            if nextChannel then 
                coreData.messages[nextChannel] = nil
                totalMessages -= if nextMsgCount then nextMsgCount else 0
            end
            
            iters += 1
        end

        if iters > conditions.MAX_STRIP_ITERS then 
            error("Internal Error: failed to strip out excess messages after trying " .. iters .. " times to do so")
        end
    end

    -- Ensure the total number of messages does not exceed maxMessages one final time as a sanity check
    totalMessages = 0
    for _, messages in coreData.messages do
        totalMessages += #messages
    end

    -- Drop channels until we meet this requirement
    -- if we still don't meet this requirement
    if totalMessages > coreData.options.maxMessages then 
        error("Internal Error: total messages is still above limit despite attempt to prune backup. Please contact support if you think this a bug")
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
    
    -- Ensure the messages match our limits by removing excess messages
    stripExcessMessages(coreData)

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

return {
    isEncryptedBackup = isEncryptedBackup,
    isBackupFile = isBackupFile,
    loadBackupBlob = loadBackupBlob,
}