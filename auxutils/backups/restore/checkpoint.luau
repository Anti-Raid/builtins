local Primitives = require"@antiraid-core/primitives"
local typesext = require"@antiraid/typesext"

export type Checkpoint = {
    step: "EditBaseGuild"
}

--- Saves a checkpoint to the KV store.
local function saveCheckpoint(ctx: Primitives.TemplateContext, id: string, checkpoint: Checkpoint)
    ctx.KV:set(id, checkpoint, {"builtins.backups.checkpoints"}, nil, true)
end

--- Starts checkpointing, returning a unique ID for the checkpoint.
local function startCheckpointing(ctx: Primitives.TemplateContext): string
    local id = typesext.randstring(32)
    local checkpoint: Checkpoint = {
        step = "EditBaseGuild" :: "EditBaseGuild",
    }
    saveCheckpoint(ctx, id, checkpoint)
    return id
end

--- Returns the current checkpoint for the given ID.
local function getCheckpoint(ctx: Primitives.TemplateContext, id: string): Checkpoint?
    local checkpoint = ctx.KV:get(id, {"builtins.backups.checkpoints"})
    if checkpoint then
        return checkpoint :: Checkpoint
    end
    return nil
end

return {
    saveCheckpoint = saveCheckpoint,
    startCheckpointing = startCheckpointing,
    getCheckpoint = getCheckpoint,
}