--!strict
local commandBuilder = require "@discord-types/builders/interaction/interaction"
local apitypes = require "@discord-types/apiTypes"
local data = require "../data"
local interactionutils = require "../../utils/interaction"
local canModeratorDo = require "../../utils/modhierarchy".canModeratorDo
local ActionRowBuilder = require"@discord-types/builders/message/components/actionRow"
local ButtonBuilder = require"@discord-types/builders/message/components/button"
local typesext = require"@antiraid/typesext"
local lockdowns = require"@antiraid-core/plugins/lockdowns"

local function register() 
    return commandBuilder.new({
        name = "lockdowns",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Manage lockdowns")
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("list")
            :setDescription("List all currently active lockdowns")  
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("quick")
            :setDescription("Launch a quick server lockdown on this server")  
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("The reason for the lockdown")
                    :setRequired(true)  
                    :build()
                end
            )
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("traditional")
            :setDescription("Launch a traditional server lockdown on this server")  
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("The reason for the lockdown")
                    :setRequired(true)  
                    :build()
                end
            )
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("channel")
            :setDescription("Lock a single channel down") 
            :option(
                function(opt) 
                    return opt
                    :setType("Channel")
                    :setName("channel")
                    :setDescription("The channel to lock down")
                    :setRequired(true)  
                    :build()
                end
            ) 
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("The reason for the lockdown")
                    :setRequired(true)  
                    :build()
                end
            )
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("role")
            :setDescription("Lock a single role down") 
            :option(
                function(opt) 
                    return opt
                    :setType("Role")
                    :setName("role")
                    :setDescription("The role to lock down")
                    :setRequired(true)  
                    :build()
                end
            ) 
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("The reason for the lockdown")
                    :setRequired(true)  
                    :build()
                end
            )
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("remove")
            :setDescription("Remove a lockdown from this server")  
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("id")
                    :setDescription("The ID of the lockdown to remove")
                    :setRequired(true)
                    :setAutocompleteEnabled(true)  
                    :build()
                end
            )
            :build()      
        end
    )
    :build()
end

local lockdownSetBurstCache: {data: lockdowns.LockdownSet, createdAt: number}? = nil
local maxBurstCacheTime = 120 -- 2 minutes

local function quickGetLockdownSet(data: data.RunData | data.AutocompleteRunData): lockdowns.LockdownSet
    if not lockdownSetBurstCache or lockdownSetBurstCache.createdAt - os.clock() > maxBurstCacheTime then 
        lockdownSetBurstCache = {
            data = data.ctx.Lockdowns.Client:fetch_lockdown_set(),
            createdAt = os.clock()
        }
        return (lockdownSetBurstCache :: {data: lockdowns.LockdownSet, createdAt: number}).data
    end
    return lockdownSetBurstCache.data
end

local function createLockdown(
    data: data.RunData,
    lockdownType: lockdowns.LockdownMode, 
    reason: string,
    ephemeral: boolean
): nil
    local lockdownSet = data.ctx.Lockdowns.Client:fetch_lockdown_set()

    -- Update the burst cache
    lockdownSetBurstCache = {
        data = lockdownSet,
        createdAt = os.clock()
    }

    -- A lockdown may take a long time to apply, so we need to make sure the user knows that something is happening
    interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Lockdown in progress",
                description = "Please wait while the lockdown is applied",
            },
        },
        nil
    )

    data.sethasEdited(true)

    local result = lockdownSet:apply(lockdownType, reason)
    if result.type == "LockdownTestFailed" then 
        local autofixCustomId = `lockdowns:autofix:${typesext.randstring(16)}`
        data.attachButtonCallback(autofixCustomId, function(data: data.ButtonCallbackData): nil 
            data.removeCallback() -- Make sure to remove the callback so it doesn't get called again
            
            if not result.test_result then error("Test result is nil") end
            interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Starting lockdown autofixer",
                        description = "Please wait while the lockdown autofixer tries to fix the issues",
                    },
                },
                true
            )

            local ok, err = xpcall(result.test_result.try_auto_fix, debug.traceback :: any, result.test_result, lockdownSet)

            if not ok then
                interactionutils.editSimple(
                    data.ctx,
                    data.interaction,
                    nil,
                    {
                        {
                            title = "Lockdown autofixer failed",
                            description = "```\n" .. tostring(err) .. "\n```",
                            color = 0xFF0000,
                        },
                    },
                    nil
                )
                return nil
            end

            interactionutils.editSimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Lockdown autofixer finished",
                        description = "The lockdown autofixer has finished. You should be able to start the requested lockdown now",
                    },
                },
                nil
            )

            return nil
        end)
        interactionutils.editSimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Action Required",
                    description = "The following actions are required to proceed with the lockdown\n" .. (if result.test_result then result.test_result:display_changeset(lockdownSet) else "No changeset available"),
                    color = 0xFF0000,
                },
            },
            {
                ActionRowBuilder.new()
                    :addComponent(
                        ButtonBuilder.new()
                        :setStyle("Grey")
                        :setLabel("Try Fixing Automatically")
                        :setCustomId(autofixCustomId)
                        :build()
                    )
                    :build() :: apitypes.ComponentObjects
            }
        )
        return nil
    elseif result.type == "Error" then 
        error(result.error or "An unknown error occurred while trying to apply the lockdown")
    elseif result.type == "Ok" then
        interactionutils.editSimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Lockdown started",
                    description = "A lockdown has been started with an ID of " .. (if result.id then result.id else "unknown") .. "\n" .. (if reason then "Reason: " .. reason else "") .. ("\nType: " .. lockdownType.string_form),
                },
            }
        )
        return nil
    else
        error(result.error or "An unknown error occurred while trying to apply the lockdown. Recieved invalid type of: " .. tostring(result.type))
    end
end

local function removeLockdown(
    data: data.RunData,
    id: string
): nil
    local lockdownSet = data.ctx.Lockdowns.Client:fetch_lockdown_set()

    -- Update the burst cache
    lockdownSetBurstCache = {
        data = lockdownSet,
        createdAt = os.clock()
    }

    -- A lockdown may take a long time to remove, so we need to make sure the user knows that something is happening
    interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Lockdown removal in progress",
                description = "Please wait while the lockdown is removed",
            },
        },
        nil
    )

    data.sethasEdited(true)

    local result = lockdownSet:remove(id)
    if result.type == "LockdownTestFailed" then 
        local autofixCustomId = `lockdowns:autofix:${typesext.randstring(16)}`
        data.attachButtonCallback(autofixCustomId, function(data: data.ButtonCallbackData): nil 
            data.removeCallback() -- Make sure to remove the callback so it doesn't get called again
            
            if not result.test_result then error("Test result is nil") end
            interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Starting lockdown autofixer",
                        description = "Please wait while the lockdown autofixer tries to fix the issues",
                    },
                },
                true
            )

            local ok, err = xpcall(result.test_result.try_auto_fix, debug.traceback :: any, result.test_result, lockdownSet)

            if not ok then
                interactionutils.editSimple(
                    data.ctx,
                    data.interaction,
                    nil,
                    {
                        {
                            title = "Lockdown autofixer failed",
                            description = "```\n" .. tostring(err) .. "\n```",
                            color = 0xFF0000,
                        },
                    },
                    nil
                )
                return nil
            end

            interactionutils.editSimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Lockdown autofixer finished",
                        description = "The lockdown autofixer has finished. You should be able to start the requested lockdown now",
                    },
                },
                nil
            )

            return nil
        end)
        interactionutils.editSimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Action Required",
                    description = "The following actions are required to proceed with the lockdown\n" .. (if result.test_result then result.test_result:display_changeset(lockdownSet) else "No changeset available"),
                    color = 0xFF0000,
                },
            },
            {
                ActionRowBuilder.new()
                    :addComponent(
                        ButtonBuilder.new()
                        :setStyle("Grey")
                        :setLabel("Try Fixing Automatically")
                        :setCustomId(autofixCustomId)
                        :build()
                    )
                    :build() :: apitypes.ComponentObjects
            }
        )
        return nil
    elseif result.type == "Error" then 
        error(result.error or "An unknown error occurred while trying to remove the lockdown")
    elseif result.type == "Ok" then
        interactionutils.editSimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Lockdown removed",
                    description = "The requested lockdown has been removed"
                },
            }
        )
        return nil
    else
        error(result.error or "An unknown error occurred while trying to remove the lockdown. Recieved invalid type of: " .. tostring(result.type))
    end
end

local function run(data: data.RunData): nil
    local modid = if data.interaction.user then data.interaction.user.id elseif (data.interaction.member and data.interaction.member.user) then data.interaction.member.user.id else error("No user found")

    local cmdname = data.command.nameList[2]

    if cmdname == "list" then
        local lockdownSet = quickGetLockdownSet(data)

        if #lockdownSet.lockdowns == 0 then 
            interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "No active lockdowns",
                        description = "There are no active lockdowns on this server",
                        color = 0xFF0000,
                    },
                },
                false
            )
            return nil
        end

        local lockdownsList: {apitypes.EmbedObject} = {}
        for _, lockdown in lockdownSet.lockdowns do 
            table.insert(lockdownsList, {
                name = lockdown.type.string_form .. " [" .. lockdown.id .. "]",
                value = "Reason: " .. (if lockdown.reason then lockdown.reason else "No reason specified") .. "\n" .. (if lockdown.created_at then "Created at: <t:" .. lockdown.created_at.timestamp_seconds else "Created at: Unknown"),
            })
        end

        interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Active Lockdowns",
                    description = "The following lockdowns are currently active on this server",
                    embeds = {
                        {
                            title = "Lockdown List",
                            description = "The following lockdowns are currently active on this server",
                            fields = lockdownsList,
                        },
                    }
                },
            },
            false
        )
        return nil
    elseif cmdname == "quick" then 
        local reason: string? = nil

        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            end
        end

        if not reason then 
            error("No reason specified")
        end

        canModeratorDo(data.ctx, modid, "lockdowns.qsl")

        local lockdownType = data.ctx.Lockdowns.QuickServerLockdown()

        return createLockdown(
            data,
            lockdownType,
            reason,
            false
        )
    elseif cmdname == "traditional" then
        local reason: string? = nil

        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            end
        end

        if not reason then 
            error("No reason specified")
        end

        canModeratorDo(data.ctx, modid, "lockdowns.tsl")

        local lockdownType = data.ctx.Lockdowns.TraditionalServerLockdown()

        return createLockdown(
            data,
            lockdownType,
            reason,
            false
        )
    elseif cmdname == "channel" then
        local reason: string? = nil
        local channel: apitypes.ChannelObject? = nil

        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            end

            if opt.name == "channel" then
                if opt.value.kind == "Channel" then
                    channel = opt.value.channel
                end
            end
        end

        if not reason then 
            error("No reason specified")
        end

        local channelid: string = if channel then channel.id else error("No channel specified")
        
        canModeratorDo(data.ctx, modid, "lockdowns.scl")

        local lockdownType = data.ctx.Lockdowns.SingleChannelLockdown(channelid)

        return createLockdown(
            data,
            lockdownType,
            reason,
            false
        )    
    elseif cmdname == "role" then
        local reason: string? = nil
        local role: apitypes.GuildRoleObject? = nil

        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            end

            if opt.name == "role" then
                if opt.value.kind == "Role" then
                    role = opt.value.role
                end
            end
        end

        if not reason then 
            error("No reason specified")
        end

        local roleid: string = if role then role.id else error("No role specified")

        canModeratorDo(data.ctx, modid, "lockdowns.srl")

        local lockdownType = data.ctx.Lockdowns.RoleLockdown(roleid)

        return createLockdown(
            data,
            lockdownType,
            reason,
            false
        )
    elseif cmdname == "remove" then
        local id: string? = nil

        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "id" then
                if opt.value.kind == "String" then
                    id = opt.value.value
                end
            end
        end

        if not id then 
            error("No ID specified")
        end

        canModeratorDo(data.ctx, modid, "lockdowns.remove")

        return removeLockdown(
            data,
            id
        )
    else 
        error("Unknown subcommand: " .. tostring(cmdname))
    end
end

local function autocompleter(data: data.AutocompleteRunData): {apitypes.ApplicationCommandOptionChoiceObject}
    local cmdname = data.command.nameList[2]

    if cmdname == "remove" then 
        local id: string? = nil

        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "id" then
                if opt.value.kind == "String" then
                    id = opt.value.value
                end
            end
        end

        if not id then 
            return {}
        end

        local lockdownSet = quickGetLockdownSet(data)

        local autocompleteResults = {}  
        for _, lockdown in lockdownSet.lockdowns do 
            if #autocompleteResults >= 25 then break end
            table.insert(autocompleteResults, {
                name = lockdown.type.string_form .. " [" .. lockdown.id .. "]",
                value = lockdown.id,
            })
        end

        return autocompleteResults
    else 
        return {}
    end
end

return {
    register = register,
    run = run,
    autocompleter = autocompleter,
}