local Primitives = require"@antiraid-core/primitives"
local typesext = require"@antiraid/typesext"
local datetime = require"@antiraid/datetime"
local types = require"../backups"
local managers = require "../../managers/managers"
local impl = require"./impl"

local CHECKPOINT_EXPIRE_TIME = datetime.timedelta_seconds(60 * 15) -- 15 minutes

export type BaseCheckpointData = {
    --- The URL of the backup being restored
    source: types.RestoreSource,
    --- Backup restore options
    opts: types.BackupRestoreOpts,
    --- The encryption key used to decrypt the backup, if any
    enckey: string?,
}

export type CheckpointData = {
    step: "EditBaseGuild",
    gre: impl.GetRestored?
} | {
    step: "DeleteOldRoles",
    gre: impl.GetRestored
} | {
    step: "CreateRoles",
    gre: impl.GetRestored
} | {
    step: "DeleteOldChannels",
    gre: impl.GetRestored
} | {
    step: "CreateChannels",
    gre: impl.GetRestored
} | {
    step: "FinishBaseRestore",
    gre: impl.GetRestored
} | {
    step: "Done",
    gre: impl.GetRestored
}

export type Checkpoint = {
    --- Checkpoint ID
    id: string,
    --- Checkpoint current data
    data: CheckpointData,
    --- Base checkpoint data, used to restore the backup
    base: BaseCheckpointData,
    --- Saves a checkpoint
    ---
    --- This also updates self.data
    saveCheckpoint: (checkpoint: CheckpointData) -> (),
    --- Deletes a checkpoint
    deleteCheckpoint: () -> (),
    --- Scopes resumable/checkpointing code so that resume key is removed on finish of callback
    --- 
    --- In the event of an error, the error is caught, checkpoint is then removed and the error is then rethrown
    scope: <R>(callback: () -> R) -> R,
}

export type CheckpointConstruct = {
    type: "existing",
    id: string,
} | {
    type: "new",
    base: BaseCheckpointData,
}

--- Checkpoint is a abstraction to enable easy/simple checkpointing
local function Checkpoint(ctx: Primitives.TemplateContext, construct: CheckpointConstruct): Checkpoint
    local backuprestorecheckpointexpiry = managers.getmanagers(ctx).backuprestorecheckpointexpiry
    
    type CreatedCheckpoint = {
        checkpoint: CheckpointData,
        base: BaseCheckpointData,
    }   

    local self = {} :: Checkpoint

    local function _getCheckpoint(): CreatedCheckpoint?
        local checkpoint = ctx.KV:get(self.id, {"builtins.backups.checkpoints"})
        if checkpoint then
            return checkpoint :: CreatedCheckpoint
        end
        return nil
    end
    
    --- Saves a checkpoint to the KV store.
    local function _saveCheckpoint(checkpoint: CheckpointData): CheckpointData
        backuprestorecheckpointexpiry.add(CHECKPOINT_EXPIRE_TIME, {
            checkpoint = checkpoint,
            base = self.base
        }, self.id)
        return checkpoint
    end

    --- Saves a checkpoint to the KV store.
    local function _deleteCheckpoint()
        ctx.KV:delete(self.id, {"builtins.backups.checkpoints"})
        self.id = ""
    end

    if construct.type == "existing" then 
        self.id = construct.id
        local data = _getCheckpoint(construct.id)
        if not data then 
            error("Checkpoint with ID " .. construct.id .. " does not exist")
        end
        self.data = data.checkpoint
        self.base = data.base
    else 
        self.id = typesext.randstring(32)
        self.base = construct.base
        self.data = _saveCheckpoint({ step = "EditBaseGuild" :: "EditBaseGuild"})
    end

    assert(type(self.id) == "string", "internal error: self.id is not a string in checkpointer")
    assert(self.data, "internal error: self.data not correctly set in checkpointer")

    local function saveCheckpoint(checkpoint: CheckpointData) 
        self.data = _saveCheckpoint(checkpoint)
    end

    self.saveCheckpoint = saveCheckpoint

    self.deleteCheckpoint = _deleteCheckpoint

    local function scopedCall<R>(callback: () -> R): R 
        local ok, res = xpcall(callback, debug.traceback :: any)

        -- Remove checkpoint
        _deleteCheckpoint()

        if ok then 
            return res
        else 
            -- Rethrow the error
            error(res)
        end
    end

    self.scope = scopedCall

    return self
end

return {
    Checkpoint = Checkpoint
}