local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorAffectTarget = require "@antiraid-ext/utils/modhierarchy".canModeratorAffectTarget
local kexs = require"../../auxutils/managers/managers"

local function unban(data: data.RunData): nil
    local userid = nil
    local reason = nil

    for _, opt in data.command.options do
        if opt.name == "user" then
            if opt.value.kind == "User" then
                userid = opt.value.user.id
            elseif opt.value.kind == "Unresolved" then
                userid = opt.value.id
            end
        end

        if opt.name == "reason" then
            if opt.value.kind == "String" then
                reason = opt.value.value
            end
        end
    end

    if not userid then
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Cannot unban unknown user!",
                    description = "No user specified",
                    color = 0xFF0000,
                },
            },
            false
        )
    end

    if not reason or reason == "" then
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Cannot unban user without a reason!",
                    description = "Please provide a reason for the unban",
                    color = 0xFF0000,
                },
            },
            false
        )
    end

    canModeratorAffectTarget(
        data.ctx, 
        data.userinfomanager.get(extractUserIdFromInteraction(data.interaction)),
        userid, 
        "moderation.unban"
    )
    
    local modid = extractUserIdFromInteraction(data.interaction)

    -- Check if a ban exists
    local ban = data.ctx.Discord:get_guild_ban(userid)
    if not ban.data then
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Cannot unban a user who is not banned!",
                    description = "User <@" .. userid .. "> is not banned from this server!",
                    color = 0xFF0000,
                },
            },
            false
        )
    end

    -- Then unban them
    data.ctx.Discord:remove_guild_ban({
        reason = reason,
        user_id = userid,
    })

    -- Drop any tempmod key expiries for this user
    local tempbankex = kexs.getmanagers(data.ctx).tempbankex
    local tempdata = tempbankex.get(userid)
    if tempdata then
        tempbankex.remove(tempdata.key)
    end

    -- Then, dispatch a AntiraidUnban event
    data.loop.dispatchEvent({
        name = "AntiraidUnban",
        author = modid,
        data = {
            userid = userid,
            reason = reason,
            tempbanrecord = tempdata,
            modid = modid
        },
    })

    return interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Successfully unbanned user",
                description = "User <@" .. userid .. "> was successfully unbanned from this server!",
                color = 0x00FF00
            },
        },
        false
    )
end

return unban