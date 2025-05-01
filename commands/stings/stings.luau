local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require "../data"
local interactionutils = require "../../utils/interaction"
local extractUserIdFromInteraction = require "../../utils/modhierarchy".extractUserIdFromInteraction
local datetime = require "@antiraid/datetime"
local canModeratorAffectTarget = require "../../utils/modhierarchy".canModeratorAffectTarget
local parseunit = require "../../utils/unit"
local apitypes = require "@discord-types/apiTypes"

local function register() 
    return commandBuilder.new({
        name = "stings",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Sting-related commands")
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("list")
            :setDescription("See all stings on a user")  
            :option(
                function(opt) 
                    return opt
                    :setType("User")
                    :setName("user")
                    :setDescription("The user to lookup")
                    :setRequired(false)  
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
            :setName("give")
            :setDescription("Stings/warns a user with a specified number of stings")
            :option(
                function(opt) 
                    return opt
                    :setType("User")
                    :setName("user")
                    :setDescription("The user to sting")  
                    :setRequired(true)
                    :build()      
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Number")
                    :setName("stings")
                    :setDescription("The number of stings to give")  
                    :setRequired(true)
                    :build()      
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("The reason to sting the user")  
                    :setRequired(true)
                    :build()      
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("time")
                    :setDescription("How long should the sting last for?")
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
            :setName("cure")
            :setDescription("Removes stings from a user")
            :option(
                function(opt) 
                    return opt
                    :setType("User")
                    :setName("user")
                    :setDescription("The user to cure stings from")  
                    :setRequired(true)
                    :build()      
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("id")
                    :setDescription("The sting ID to cure")  
                    :setRequired(true)
                    :setAutocompleteEnabled(true)
                    :build()      
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("The reason to cure the user of this sting")  
                    :setRequired(true)
                    :build()      
                end
            )
            :build()
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local cmdname = data.command.nameList[2]

    if cmdname == "list" then 
        local userid = extractUserIdFromInteraction(data.interaction)

        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "user" then 
                if opt.value.kind == "User" then
                    userid = opt.value.user.id
                end
            end
        end
        
        local stings = data.stingManager.getStingsOnUser(userid)
    
        local stingEmbeds = {}
        for _, sting in stings do
            local fields = {
                { name = "Sting Count", value = tostring(sting.stings), inline = true },
                { name = "Moderator", value = if sting.modId then "<@" .. sting.modId .. ">" else "System", inline = true },
                { name = "Creation Date", value = "<t:" .. sting.created_at.timestamp_seconds .. ">", inline = true },
            }
    
            if #stings < 5 then 
                local _, stingExpiry = data.stingManager.getStingExpiration(sting.userId, sting.stingId)
                if stingExpiry then 
                    table.insert(fields, {
                        name = "Sting Expiry",
                        value = "<t:" .. stingExpiry.timestamp_seconds .. ">",
                        inline = true,
                    })
                else
                    table.insert(fields, {
                        name = "Sting Expiry",
                        value = "Never",
                        inline = true,
                    })
                end
            end
    
            local embed = {
                title = `Sting {sting.stingId}`,
                description = sting.reason,
                fields = fields,
            }
    
            table.insert(stingEmbeds, embed)
        end
    
        if #stingEmbeds == 0 then
            return interactionutils.replySimple(
                data.ge,
                data.interaction,
                nil,
                {
                    {
                        title = "No stings found",
                        description = `No stings found for <@{userid}>`,
                    }
                },
                false
            )
        else
            return interactionutils.replySimple(
                data.ge,
                data.interaction,
                nil,
                stingEmbeds,
                false
            )
        end  
    elseif cmdname == "give" then 
        local user = nil
        local numberOfStings: number? = nil
        local reason: string? = nil
        local stingTime: number? = nil
    
        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "user" then 
                if opt.value.kind == "User" then
                    user = opt.value.user
                end
            elseif opt.name == "stings" then
                if opt.value.kind == "Number" then
                    numberOfStings = opt.value.value
                end
            elseif opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            elseif opt.name == "time" then
                if opt.value.kind == "String" then
                    stingTime = parseunit(opt.value.value)
                end
            end
        end
        
        if not user then 
            return interactionutils.replySimple(
                data.ge,
                data.interaction,
                nil,
                {
                    {
                        title = "No user specified",
                        description = "Please specify a user to sting",
                    },
                },
                false
            )
        end
    
        if not numberOfStings then 
            return interactionutils.replySimple(
                data.ge,
                data.interaction,
                nil,
                {
                    {
                        title = "No number of stings specified",
                        description = "Please specify a number of stings to give",
                    },
                },
                false
            )
        end
    
        if not reason then 
            return interactionutils.replySimple(
                data.ge,
                data.interaction,
                nil,
                {
                    {
                        title = "No reason specified",
                        description = "Please specify a reason for the sting",
                    },
                },
                false
            )
        end
    
        local modid = extractUserIdFromInteraction(data.interaction)
        
        canModeratorAffectTarget(data.ge, modid, user.id, "moderation.sting")
    
        local createdSting = data.stingManager.createUserSting({
            userId = user.id,
            modId = modid,
            reason = reason,
            stings = numberOfStings,
        })
    
        if stingTime then 
            data.stingManager.setStingExpiration(user.id, createdSting.stingId, reason, datetime.UTC:now() + datetime.timedelta_seconds(stingTime))
        end
    
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Sting created",
                    description = `Successfully stung {user.username} with \`\`{numberOfStings}\`\` stings for: \`\`{reason}\`\` with a sting ID of \`\`{createdSting.stingId}\`\``,
                    fields = {
                        {
                            name = "Expiry",
                            value = if stingTime then "<t:" .. (datetime.UTC:now() + datetime.timedelta_seconds(stingTime)).timestamp_seconds .. ">" else "Never",
                            inline = true,
                        }
                    }
                },
            },
            false
        )    
    elseif cmdname == "cure" then
        local user = nil
        local stingId: string? = nil
        local reason: string? = nil
    
        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "user" then 
                if opt.value.kind == "User" then
                    user = opt.value.user
                end
            elseif opt.name == "id" then
                if opt.value.kind == "String" then
                    stingId = opt.value.value
                end
            elseif opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            end
        end
    
        if not user then 
            return interactionutils.replySimple(
                data.ge,
                data.interaction,
                nil,
                {
                    {
                        title = "No user specified",
                        description = "Please specify a user to cure",
                    },
                },
                false
            )
        end
    
        if not stingId then 
            return interactionutils.replySimple(
                data.ge,
                data.interaction,
                nil,
                {
                    {
                        title = "No sting ID specified",
                        description = "Please specify a sting ID to cure",
                    },
                },
                false
            )
        end
    
        if not reason then 
            return interactionutils.replySimple(
                data.ge,
                data.interaction,
                nil,
                {
                    {
                        title = "No reason specified",
                        description = "Please specify a reason for the cure",
                    },
                },
                false
            )
        end
    
        local modId = extractUserIdFromInteraction(data.interaction)
        canModeratorAffectTarget(data.ge, modId, user.id, "moderation.curesting")
    
        data.stingManager.deleteSting(user.id, stingId, modId, reason)
    
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Sting cured",
                    description = `Successfully cured <@{user.id}> of their sting with ID \`\`{stingId}\`\``,
                }
            },
            false
        )
    end

    return interactionutils.replySimple(
        data.ge,
        data.interaction,
        nil,
        {
            {
                title = "Unknown command",
                description = "Please use `/stings list` to see all stings on a user or `/stings give` to give a user stings",
            }
        },
        false
    )
end

local function autocompleter(data: data.AutocompleteRunData): {apitypes.ApplicationCommandOptionChoiceObject}
    local cmdname = data.command.nameList[2]

    if cmdname == "cure" then 
        local userId = nil
        local typedName = nil
        for _, opt in data.command.options do 
            if opt.name == "user" then 
                if opt.value.kind == "User" then
                    userId = opt.value.user.id
                elseif opt.value.kind == "Unresolved" then
                    userId = opt.value.id
                end
            elseif opt.name == "id" then
                if opt.value.kind == "String" then
                    typedName = opt.value.value
                end
            end
        end

        if not userId then 
            return {}
        end

        local userStings = data.stingManager.getCachedUserStings(userId)
        local choices: {apitypes.ApplicationCommandOptionChoiceObject} = {}

        for _, sting in userStings do
            if #choices >= 25 then
                break
            end
            if typedName and not string.find(sting.stingId:lower(), typedName:lower()) then
                continue
            end
            table.insert(choices, {
                name = `Sting ID: {sting.stingId}`,
                value = sting.stingId,
            })
        end
        return choices
    end

    return {}
end

return {
    register = register,
    run = run,
    autocompleter = autocompleter,
}