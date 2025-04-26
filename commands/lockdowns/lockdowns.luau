--!strict
local commandBuilder = require "@discord-types/builders/interaction/interaction"
local apitypes = require "@discord-types/apiTypes"
local data = require "../data"
local interactionutils = require "../../utils/interaction"
local canModeratorDo = require "../../utils/modhierarchy".canModeratorDo
local lockdowns = require"@antiraid/lockdowns"
local ActionRowBuilder = require"@discord-types/builders/message/components/actionRow"
local ButtonBuilder = require"@discord-types/builders/message/components/button"
local promise = require"@antiraid/promise"
local typesext = require"@antiraid/typesext"

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

local lockdownSetBurstCache = nil
local maxBurstCacheTime = 120 -- 2 minutes

local function quickGetLockdownSet(data: data.RunData | data.AutocompleteRunData): lockdowns.LockdownSet
    if not lockdownSetBurstCache or lockdownSetBurstCache.createdAt - os.clock() > maxBurstCacheTime then 
        lockdownSetBurstCache = {
            data = promise.yield(data.ge.lockdowns:fetch_lockdown_set()),
            createdAt = os.clock()
        }
        return lockdownSetBurstCache.data
    end
    return lockdownSetBurstCache.data
end

local function createLockdown(
    data: data.RunData,
    lockdownType: lockdowns.LockdownMode, 
    reason: string,
    ephemeral: boolean
): nil
    local lockdownSet = promise.yield(data.ge.lockdowns:fetch_lockdown_set())

    -- Update the burst cache
    lockdownSetBurstCache = {
        data = lockdownSet,
        createdAt = os.clock()
    }

    -- A lockdown may take a long time to apply, so we need to make sure the user knows that something is happening
    interactionutils.replySimple(
        data.ge,
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

    local result = promise.yield(lockdownSet:apply(lockdownType, reason))
    if result.type == "LockdownTestFailed" then 
        local autofixCustomId = `lockdowns:autofix:${typesext.randstring(16)}`
        data.attachButtonCallback(autofixCustomId, function(data: data.ButtonCallbackData): nil 
            data.removeCallback() -- Make sure to remove the callback so it doesn't get called again
            
            if not result.test_result then error("Test result is nil") end
            interactionutils.replySimple(
                data.ge,
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

            data.sethasEdited(true)

            promise.yield(result.test_result:try_auto_fix(lockdownSet))

            interactionutils.editSimple(
                data.ge,
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
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Action Required",
                    description = "The following actions are required to proceed with the lockdown\n" .. (if result.test_result then promise.yield(result.test_result:display_changeset(lockdownSet)) else "No changeset available"),
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
            data.ge,
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
    local lockdownSet = promise.yield(data.ge.lockdowns:fetch_lockdown_set())

    -- Update the burst cache
    lockdownSetBurstCache = {
        data = lockdownSet,
        createdAt = os.clock()
    }

    -- A lockdown may take a long time to remove, so we need to make sure the user knows that something is happening
    interactionutils.replySimple(
        data.ge,
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

    local result = promise.yield(lockdownSet:remove(id))
    if result.type == "LockdownTestFailed" then 
        local autofixCustomId = `lockdowns:autofix:${typesext.randstring(16)}`
        data.attachButtonCallback(autofixCustomId, function(data: data.ButtonCallbackData): nil 
            data.removeCallback() -- Make sure to remove the callback so it doesn't get called again
            
            if not result.test_result then error("Test result is nil") end
            interactionutils.replySimple(
                data.ge,
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

            data.sethasEdited(true)

            promise.yield(result.test_result:try_auto_fix(lockdownSet))

            interactionutils.editSimple(
                data.ge,
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
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Action Required",
                    description = "The following actions are required to proceed with the lockdown\n" .. (if result.test_result then promise.yield(result.test_result:display_changeset(lockdownSet)) else "No changeset available"),
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
            data.ge,
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

    if cmdname == "quick" then 
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

        canModeratorDo(data.ctx, data.ge, modid, "lockdowns.qsl")

        local lockdownType = lockdowns.QuickServerLockdown()

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

        canModeratorDo(data.ctx, data.ge, modid, "lockdowns.tsl")

        local lockdownType = lockdowns.TraditionalServerLockdown()

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
        
        canModeratorDo(data.ctx, data.ge, modid, "lockdowns.scl")

        local lockdownType = lockdowns.SingleChannelLockdown(channelid)

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

        canModeratorDo(data.ctx, data.ge, modid, "lockdowns.srl")

        local lockdownType = lockdowns.RoleLockdown(roleid)

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

        canModeratorDo(data.ctx, data.ge, modid, "lockdowns.remove")

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