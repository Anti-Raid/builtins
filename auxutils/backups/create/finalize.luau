local datamgmt = require"@antiraid/datamgmt"
local datetime = require"@antiraid/datetime"
local types = require"../backups"

--- Builds a backup from a TAR archive and an optional encryption key.
--- If the encryption key is provided, the backup will be encrypted using AES256.
--- The backup will be returned as a `BuiltBackup` object containing the backup data and the filename.
--- @param tar The TAR archive to build the backup from
--- @param enckey The optional encryption key to encrypt the backup with
--- @return A `BuiltBackup` object containing the backup data and the filename
local function buildBackup(
    tar: datamgmt.TarArchive,
    enckey: string?,
    updater: types.Updater
): types.BuiltBackup
    local filename = `antiraidbackup-{datetime.UTC:now()}`
    local fileext = ".arb1"
    local data = tar:toblob()
    if enckey then 
        data = datamgmt.aes256encrypt(data, enckey)
        fileext = ".arb1e"
    end

    updater.addStatus("Finalized archive")

    return {
        backup = data,
        filename = filename .. fileext,
    }
end

return {
    buildBackup = buildBackup,
}