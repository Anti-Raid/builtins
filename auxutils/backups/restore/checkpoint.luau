local Primitives = require"@antiraid-core/primitives"
local typesext = require"@antiraid/typesext"
local apitypes = require"@discord-types/apiTypes"
local datetime = require"@antiraid/datetime"
local types = require"../backups"

local CHECKPOINT_EXPIRE_TIME = 60 * 15 -- 15 minutes

export type BaseCheckpointData = {
    --- The filename of the backup being restored
    filename: string, 
    --- The URL of the backup being restored
    url: string, 
    --- Backup restore options
    opts: types.BackupRestoreOpts,
    --- The encryption key used to decrypt the backup, if any
    enckey: string?,
}

export type CheckpointData = {
    step: "EditBaseGuild"
} | {
    step: "DeleteOldRoles"
} | {
    step: "CreateRoles",
    restoredRoles: {[string]: apitypes.GuildRoleObject} -- Map of old role ID on the backup to new role objects
} | {
    step: "DeleteOldChannels",
    restoredRoles: {[string]: apitypes.GuildRoleObject} 
} | {
    step: "CreateChannels",
    restoredRoles: {[string]: apitypes.GuildRoleObject},
    restoredChannels: {[string]: apitypes.ChannelObject} -- Map of old channel ID on the backup to new channel objects
} | {
    step: "FinishBaseRestore",
    restoredRoles: {[string]: apitypes.GuildRoleObject},
    restoredChannels: {[string]: apitypes.ChannelObject},
} | {
    step: "CreateWebhook",
    restoredRoles: {[string]: apitypes.GuildRoleObject},
    restoredChannels: {[string]: apitypes.ChannelObject},
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
        ctx.KV:set(self.id, { checkpoint = checkpoint, base = self.base }, {"builtins.backups.checkpoints"}, datetime.UTC:now() + datetime.timedelta_seconds(CHECKPOINT_EXPIRE_TIME), true)
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