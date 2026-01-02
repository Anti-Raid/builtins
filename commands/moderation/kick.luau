local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorAffectTarget = require "@antiraid-ext/utils/modhierarchy".canModeratorAffectTarget

local function kick(data: data.RunData): nil
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
                    title = "Cannot kick unknown user!",
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
                    title = "Cannot kick user without a reason!",
                    description = "Please provide a reason for the kick",
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
        "moderation.kick"
    )

    local modid = extractUserIdFromInteraction(data.interaction)

    -- First kick them
    data.ctx.Discord:remove_guild_member({
        reason = reason,
        user_id = userid,
    })

    -- Then, dispatch a AntiraidKick event
    data.loop.dispatchEvent(data.ctx, {
        name = "AntiraidKick",
        author = modid,
        data = {
            userid = userid,
            reason = reason,
        },
    })

    return interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Successfully kicked user",
                description = "User <@" .. userid .. "> was successfully kicked from this server!",
                color = 0x00FF00
            },
        },
        false
    )
end

return kick