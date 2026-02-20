local stingmanager = require"../stingmanager"
local afkmanager = require"../afkmanager"
local Primitives = require"@antiraid-core/primitives"
local KeyExpiryManager = require "@antiraid-ext/keyexpirymanager"

local isDevMode = require"../../devs".isInDevMode
local scopePrefix = if isDevMode then "builtins-dev" else "builtins"

type TempBan = {
    userid: string,
    modid: string?,
    reason: string,
}

type RemindMe = {
    userid: string,
    channelid: string,
    message: string,
    ephemeral: boolean,
}

export type Managers = {
    stingmanager: stingmanager.StingManager,
    afkmanager: afkmanager.AFKManager,
    tempbankex: KeyExpiryManager.KeyExpiryManager<TempBan>,
    remindmeexpiry: KeyExpiryManager.KeyExpiryManager<RemindMe>,
    afkexpiry: KeyExpiryManager.KeyExpiryManager<afkmanager.AFKExpiryData>,
    stingexpiry: KeyExpiryManager.KeyExpiryManager<stingmanager.StingExpiryData>,
}

local managers: Managers? = nil

--- Gets or initializes the built-in managers
local function getmanagers(ctx: Primitives.TemplateContext): Managers
    if managers then return managers end

    local tempbanExpiryManager = KeyExpiryManager<<TempBan>>(ctx, scopePrefix..".tempbans", function(loop, record) 
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
    local remindmeExpiryManager = KeyExpiryManager<<RemindMe>>(ctx, scopePrefix..".remindme", function(loop, record) 
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
    local afkExpiryManager = KeyExpiryManager<<afkmanager.AFKExpiryData>>(ctx, scopePrefix..".afk", function(loop, record) 
        if not managers then 
            loop.debugmanager.print("[BuiltinsAfkExpiry] AFKManager not initialized when trying to expire AFK for user "..record.key)
            return
        end
        managers.afkmanager.onAfkExpire(record) -- this automatically dispatches the BuiltinsAfkExpiry event as well, so no need to do that here
        return nil
    end)
    local stingExpiryManager = KeyExpiryManager<<stingmanager.StingExpiryData>>(ctx, scopePrefix..".stings", function(loop, record) 
        if not managers then 
            loop.debugmanager.print("[BuiltinsStingExpiry] StingManager not initialized when trying to expire sting "..record.key)
            return
        end
        managers.stingmanager.onStingExpire(record) -- this automatically dispatches the BuiltinsStingDelete event as well, so no need to do that here
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
    }

    return managers or error("Failed to initialize managers")
end

return {
    getmanagers = getmanagers,
}