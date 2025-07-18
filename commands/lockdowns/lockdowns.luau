--!strict
local commandBuilder = require "@discord-types/builders/interaction/interaction"
local apitypes = require "@discord-types/apiTypes"
local data = require "../data"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorDo = require "@antiraid-ext/utils/modhierarchy".canModeratorDo
local ActionRowBuilder = require"@discord-types/builders/message/components/actionRow"
local ButtonBuilder = require"@discord-types/builders/message/components/button"
local typesext = require"@antiraid/typesext"
local mode = require"@antiraid-ext/lockdowns/mode"
local lockdownset = require"@antiraid-ext/lockdowns/lockdownset"

-- Lockdown modes
local QuickServerLockdown = require"@antiraid-ext/lockdowns/modes/quickserverlockdown"
local TraditionalServerLockdown = require"@antiraid-ext/lockdowns/modes/traditionalserverlockdown"
local SingleChannelLockdown = require"@antiraid-ext/lockdowns/modes/singlechannellockdown"
local RoleLockdown = require"@antiraid-ext/lockdowns/modes/rolelockdown"

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

local lockdownSetBurstCache: {data: lockdownset.LockdownSet, createdAt: number}? = nil
local maxBurstCacheTime = 120 -- 2 minutes

local function quickGetLockdownSet(data: data.RunData | data.AutocompleteRunData): lockdownset.LockdownSet
    if not lockdownSetBurstCache or lockdownSetBurstCache.createdAt - os.clock() > maxBurstCacheTime then 
        lockdownSetBurstCache = {
            data = lockdownset(data.ctx),
            createdAt = os.clock()
        }
        return (lockdownSetBurstCache :: {data: lockdownset.LockdownSet, createdAt: number}).data
    end
    return lockdownSetBurstCache.data
end

local function createLockdown(
    data: data.RunData,
    lockdownType: mode.LockdownMode, 
    reason: string,
    ephemeral: boolean
): nil
    local lockdownSet = lockdownset(data.ctx)

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

    local ok, result = pcall(lockdownSet.apply, lockdownType, reason)
    if not ok then 
        local autofixCustomId = `lockdowns:autofix:${typesext.randstring(16)}`
        data.attachButtonCallback(autofixCustomId, function(data: data.ButtonCallbackData): nil 
            data.removeCallback() -- Make sure to remove the callback so it doesn't get called again
            
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

            local ok, err = xpcall(lockdownSet.autofix, debug.traceback :: any, lockdownType)

            if not ok then
                err = tostring(err) :: string
                if #err > 2000 then 
                    -- Limit to 1997 chars and add a ... at the end
                    err = err:sub(1, 1997) .. "..."
                end

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

        result = tostring(result) :: string
        if #result > 2000 then 
            -- Limit to 1997 chars and add a ... at the end
            result = result:sub(1, 1997) .. "..."
        end

        interactionutils.editSimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Lockdown Failed",
                    description = "```\n" .. result .. "\n```",
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
    else
        result = result :: mode.Lockdown
        interactionutils.editSimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Lockdown started",
                    description = "A lockdown has been started with an ID of " .. result.id .. "\n" .. (if reason then "Reason: " .. reason else "") .. ("\nType: " .. lockdownType.string_form()),
                },
            }
        )
        return nil
    end
end

local function removeLockdown(
    data: data.RunData,
    id: string
): nil
    local lockdownSet = lockdownset(data.ctx)

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

    local ok, err = pcall(lockdownSet.remove, id)
    if not ok then 
        err = tostring(err) :: string
        if #err > 2000 then 
            -- Limit to 1997 chars and add a ... at the end
            err = err:sub(1, 1997) .. "..."
        end

        interactionutils.editSimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Lockdown Failed",
                    description = "```\n" .. err .. "\n```",
                    color = 0xFF0000,
                },
            }
        )
        return nil
    else
        interactionutils.editSimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Lockdown removed",
                    description = "The requested lockdown has been removed",
                    color = 0x00FF00,
                },
            }
        )
        return nil
    end
end

local function run(data: data.RunData): nil
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

        local lockdownsList: {apitypes.EmbedFieldObject} = {}
        --setmetatable(lockdownsList, interop.array_metatable)
        for _, lockdown in lockdownSet.lockdowns do 
            table.insert(lockdownsList, {
                name = lockdown.type.string_form,
                value = "Reason: " .. (if lockdown.reason then lockdown.reason else "No reason specified") .. "\n" .. (if lockdown.created_at then "Created at: <t:" .. lockdown.created_at.timestamp_seconds .. ">" else "Created at: Unknown") .. "\nID: ``" .. lockdown.id .. "``",
                inline = true,
            })
        end

        --error("json: " .. lockdownJson)

        interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Active Lockdowns",
                    description = "The following lockdowns are currently active on this server",
                    fields =  lockdownsList,
                    color = 0x00FF00,
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

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
            "lockdowns.qsl"
        )

        local lockdownType = QuickServerLockdown()

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

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
            "lockdowns.tsl"
        )

        local lockdownType = TraditionalServerLockdown()

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
        
        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction), 
            "lockdowns.scl"
        )

        local lockdownType = SingleChannelLockdown(channelid)

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

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
            "lockdowns.srl"
        )

        local lockdownType = RoleLockdown(roleid)

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

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
            "lockdowns.remove"
        )

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
                name = lockdown.type.string_form() .. " [" .. lockdown.id .. "]",
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