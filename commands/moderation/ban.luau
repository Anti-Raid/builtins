local data = require"@antiraid-ext/framework/coretypes"
local kexs = require"../../auxutils/managers/managers"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorAffectTarget = require "@antiraid-ext/utils/modhierarchy".canModeratorAffectTarget
local parseunit = require "@antiraid-ext/unit"

local function ban(data: data.RunData): nil
    local userid = nil
    local reason = nil
    local delete_message_seconds = 0
    local duration = nil

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

        if opt.name == "delete_message_days" then
            if opt.value.kind == "Integer" then
                delete_message_seconds += opt.value.value * 86400 -- Convert days to seconds
            end
        end

        if opt.name == "delete_message_seconds" then
            if opt.value.kind == "Integer" then
                delete_message_seconds += opt.value.value -- Already in seconds
            end
        end

        if opt.name == "duration" then
            if opt.value.kind == "String" then
                duration = parseunit(opt.value.value)
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
                    title = "Cannot ban unknown user!",
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
                    title = "Cannot ban user without a reason!",
                    description = "Please provide a reason for the ban",
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
        "moderation.ban"
    )

    local modid = extractUserIdFromInteraction(data.interaction)

    -- If we need this to be temporary, schedule an unban linked to a key expiry
    local tempdata = nil
    if duration and duration > 0 then
        local tempbankex = kexs.getmanagers(data.ctx).tempbankex
        if tempbankex.get(userid) then 
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "User already has an active tempban!",
                        description = "This user is already tempbanned. Please either wait for the existing tempban to expire or remove it before applying a new one.",
                        color = 0xFF0000,
                    },
                },
                false
            )
        end

        local key = tempbankex.addwithsecs(duration, {
            userid = userid,
            modid = modid,
            reason = reason
        }, userid) -- Use the userid as the key for easy lookup when unbanning
        tempdata = {
            key = key,
            duration = duration
        }
    end

    -- First ban them
    data.ctx.Discord:create_guild_ban({
        delete_message_seconds = delete_message_seconds,
        reason = reason,
        user_id = userid,
    })

    -- Then, dispatch a AntiraidBan event
    data.loop.dispatchEvent({
        name = "AntiraidBan",
        author = modid,
        data = {
            userid = userid,
            reason = reason,
            delete_message_seconds = delete_message_seconds,
            tempdata = tempdata
        },
    })

    return interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Successfully banned user",
                description = "User <@" .. userid .. "> was successfully banned from this server!",
                color = 0x00FF00
            },
        },
        false
    )
end

return ban