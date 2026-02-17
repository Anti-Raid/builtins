local stingmanager = require"../stingmanager"
local afkmanager = require"../afkmanager"
local Primitives = require"@antiraid-core/primitives"
local KeyExpiryManager = require "@antiraid-ext/keyexpirymanager"

local isDevMode = require"../../devs".isInDevMode
local scopePrefix = if isDevMode then "builtins-dev" else "builtins"

export type Managers = {
    stingmanager: stingmanager.StingManager,
    afkmanager: afkmanager.AFKManager,
    tempbankex: KeyExpiryManager.KeyExpiryManager,
    remindmeexpiry: KeyExpiryManager.KeyExpiryManager,
    afkexpiry: KeyExpiryManager.KeyExpiryManager,
    stingexpiry: KeyExpiryManager.KeyExpiryManager,
    backuprestorecheckpointexpiry: KeyExpiryManager.KeyExpiryManager, -- backup restore checkpoint expiry manager, used to automatically delete backup restore checkpoints after a certain amount of time to prevent clutter and potential security issues
}

local managers: Managers? = nil

--- Gets or initializes the built-in managers
local function getmanagers(ctx: Primitives.TemplateContext): Managers
    if managers then return managers end

    local tempbanExpiryManager = KeyExpiryManager(ctx, scopePrefix..".tempbans", function(loop, record) 
        -- userid = userid, modid = modid, reason = reason, [createdat = createdat, expiresat = expiresat]
        local userid = record.value.userid
        local modid = record.value.modid
        local reason = record.value.reason
        if not userid or not reason then 
            loop.debugmanager.print("[BuiltinsTempBanExpiry] Missing userid or reason in record for key "..record.key)
            return
        end
        -- Unban the user
        local ok, res = xpcall(function()
            ctx.Discord:remove_guild_ban({user_id = userid, reason = "Temporary ban expired: "..reason})
            return nil
        end, debug.traceback :: any)
        -- Dispatch an event with the result of the unban attempt so other templates can react to it if needed
        loop.dispatchEvent{
            name = "BuiltinsTempBanExpiry", 
            data = { 
                userid = userid, 
                modid = modid, 
                reason = reason, 
                createdat = record.createdat, 
                expiresat = record.expiresat,
                ok = ok, 
                res = res
            }, 
            author = nil
        }
        return nil
    end)
    local remindmeExpiryManager = KeyExpiryManager(ctx, scopePrefix..".remindme", function(loop, record) 
        local userid = record.value.userid
        local channelid = record.value.channelid
        local message = record.value.message
        local ephemeral = record.value.ephemeral
        if not userid or not channelid or not message then 
            loop.debugmanager.print("[BuiltinsRemindMeExpiry] Missing userid, channelid, or message in record for key "..record.key)
            return
        end

        -- Send the reminder message
        ctx.Discord:create_message({
            channel_id = channelid,
            data = {
                embeds = {
                    {
                        title = "Reminder",
                        description = string.format("<@%s> %s", userid, message),
                    }
                }
            }
        })

        loop.dispatchEvent{
            name = "BuiltinsRemindMeExpiry", 
            data = { 
                userid = userid,
                channelid = channelid,
                message = message,
                ephemeral = ephemeral,
                createdat = record.createdat,
                expiresat = record.expiresat,
            }, 
            author = nil
        }
        return nil
    end)
    local afkExpiryManager = KeyExpiryManager(ctx, scopePrefix..".afk", function(loop, record) 
        local userid = record.key
        if not userid then 
            loop.debugmanager.print("[BuiltinsAfkExpiry] Missing userid in record for key "..record.key)
            return
        end
        if not managers then 
            loop.debugmanager.print("[BuiltinsAfkExpiry] AFKManager not initialized when trying to expire AFK for user "..record.key)
            return
        end
        managers.afkmanager.onAfkExpire(record.key) -- this automatically dispatches the BuiltinsAfkExpiry event as well, so no need to do that here
        return nil
    end)
    local stingExpiryManager = KeyExpiryManager(ctx, scopePrefix..".stings", function(loop, record) 
        local stingid = record.key
        local userid = record.value.userid
        if not stingid or not userid then
            loop.debugmanager.print("[BuiltinsStingExpiry] Missing stingid or userid in record for key "..record.key)
            return
        end
        if not managers then 
            loop.debugmanager.print("[BuiltinsStingExpiry] StingManager not initialized when trying to expire sting "..stingid)
            return
        end
        managers.stingmanager.onStingExpire(userid, stingid) -- this automatically dispatches the BuiltinsStingDelete event as well, so no need to do that here
        return nil
    end)

    local backuprestorecheckpointexpiryManager = KeyExpiryManager(ctx, scopePrefix..".backuprestorecheckpoints", function(loop, record)
        return nil
    end, function(loop, records) 
        -- on init, resume any existing checkpoints
        --
        -- for now, we just log
        loop.debugmanager.print("[BuiltinsBackupRestoreCheckpointExpiry] Resuming backup restore checkpoints", records)
        loop.debugmanager.print(records)
        return nil
    end)

    local afkmanager = afkmanager(ctx, afkExpiryManager)
    local stingmanager = stingmanager(ctx, stingExpiryManager)

    managers = {
        stingmanager = stingmanager,
        afkmanager = afkmanager,
        tempbankex = tempbanExpiryManager,
        remindmeexpiry = remindmeExpiryManager,
        afkexpiry = afkExpiryManager,
        stingexpiry = stingExpiryManager,
        backuprestorecheckpointexpiry = backuprestorecheckpointexpiryManager
    }

    return managers or error("Failed to initialize managers")
end

return {
    getmanagers = getmanagers,
}