local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/frameworkv2/context"
local datetime = require "@antiraid/datetime"
local apitypes = require "@discord-types/apiTypes"
local managers = require "../../auxutils/managers/managers"
local units = require"@antiraid-ext/frameworkv2/unit"

local command = commandBuilder.new({
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
                :setType("Number")
                :setName("time")
                :setDescription("How long should the sting last for?")
                :build()
            end
        )
        :option(
            function(opt) 
                return opt
                :setType("String")
                :setName("timeunit")
                :setDescription("The unit of time")
                :setRequired(false)
                :choice(function(choice) return choice:setName("Seconds"):setValue("seconds"):build() end)
                :choice(function(choice) return choice:setName("Minutes"):setValue("minutes"):build() end)
                :choice(function(choice) return choice:setName("Hours"):setValue("hours"):build() end)
                :choice(function(choice) return choice:setName("Days"):setValue("days"):build() end)
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

local function run(data: data.CommandContext): nil
    local cmdname = data.command.nameList[2]
    local stingmanager = managers.getmanagers(data.ctx).stingmanager

    if cmdname == "list" then 
        local userid = data.args.userid("user") or data.interaction.userid()
        local stings = stingmanager.getStingsOnUser(userid)
    
        local stingEmbeds = {}
        for _, sting in stings do
            local fields = {
                { name = "Sting Count", value = tostring(sting.stings), inline = true },
                { name = "Moderator", value = if sting.modId then "<@" .. sting.modId .. ">" else "System", inline = true },
                { name = "Creation Date", value = "<t:" .. sting.created_at.timestamp_seconds .. ">", inline = true },
            }
    
            if sting.expires_at then 
            table.insert(fields, {
                name = "Sting Expiry",
                value = "<t:" .. sting.expires_at.timestamp_seconds .. ">",
                inline = true,
            })
            else
                table.insert(fields, {
                    name = "Sting Expiry",
                    value = "Never",
                    inline = true,
                })
            end
    
            local embed = {
                title = `Sting {sting.stingId}`,
                description = sting.reason,
                fields = fields,
            } :: apitypes.EmbedObject
    
            table.insert(stingEmbeds, embed)
        end
    
        if #stingEmbeds == 0 then
            return data.interaction.replysimpleembed("No stings found", `No stings found for <@{userid}>`, units.RED_COLOR)
        else
            data.interaction.reply{embeds = stingEmbeds}
            return nil
        end  
    elseif cmdname == "give" then 
        local modinfo = data.interaction.assertpermission("moderation.sting")

        local user = data.args.user("user")
        local numberOfStings = data.args.number("stings")
        local reason = data.args.string("reason")
        local stingTime = data.args.time("time", "timeunit")
            
        if not user then 
            return data.interaction.replysimpleembed("No user specified", "Please specify a user to sting", units.RED_COLOR)
        end
    
        if not numberOfStings then 
            return data.interaction.replysimpleembed("No number of stings specified", "Please specify a number of stings to give", units.RED_COLOR)
        end
    
        if not reason then 
            return data.interaction.replysimpleembed("No reason specified", "Please specify a reason for the sting", units.RED_COLOR)
        end
        
        local expiresat = if stingTime then datetime.UTC:now() + datetime.timedelta_seconds(stingTime) else nil
        local createdSting = stingmanager.createUserSting({
            userId = user.id,
            modId = modinfo.userid,
            reason = reason,
            stings = numberOfStings,
            expires_at = expiresat
        })

        data.interaction.reply{
            embeds = {
                {
                    title = "Sting created",
                    description = `Successfully stung {user.username} with \`\`{numberOfStings}\`\` stings for: \`\`{reason}\`\` with a sting ID of \`\`{createdSting.stingId}\`\``,
                    fields = {
                        {
                            name = "Expiry",
                            value = if expiresat then "<t:" .. expiresat.timestamp_seconds .. ">" else "Never",
                            inline = true,
                        }
                    },
                    color = units.GREEN_COLOR,
                },
            }
        }
        return nil
    elseif cmdname == "cure" then
        local modinfo = data.interaction.assertpermission("moderation.curesting")

        local user = data.args.userid("user")
        local stingId = data.args.string("id")
        local reason = data.args.string("reason")
        
        if not user then 
            return data.interaction.replysimpleembed("No user specified", "Please specify a user to sting", units.RED_COLOR)
        end
    
        if not stingId then 
            return data.interaction.replysimpleembed("No sting ID specified", "Please specify a sting ID to cure", units.RED_COLOR)
        end
    
        if not reason then 
            return data.interaction.replysimpleembed("No reason specified", "Please specify a reason for the cure", units.RED_COLOR)
        end
            -- Check that the sting exists
        local sting = stingmanager.getSting(user, stingId)
        if not sting then
            return data.interaction.replysimpleembed("Sting not found", `No sting with ID \`\`{stingId}\`\` found for <@{user}>`, units.RED_COLOR)
        end

        stingmanager.deleteSting(user, stingId, modinfo.userid, reason)
        return data.interaction.replysimpleembed("Sting cured",`Successfully cured <@{user}> of their sting with ID \`\`{stingId}\`\``, units.GREEN_COLOR)
    else
        return data.interaction.replysimpleembed("Error processing command", "Please use `/stings list` to see all stings on a user or `/stings give` to give a user stings", units.RED_COLOR)
    end
end

local function autocompleter(data: data.CommandAutocompleteContext): {apitypes.ApplicationCommandOptionChoiceObject}
    local cmdname = data.command.nameList[2]
    local stingmanager = managers.getmanagers(data.ctx).stingmanager

    if cmdname == "cure" then 
        local userId = data.args.userid("user")
        local typedName = data.args.string("id")

        if not userId then 
            return {}
        end

        local userStings = stingmanager.getCachedUserStings(userId)
        local choices: {apitypes.ApplicationCommandOptionChoiceObject} = {}

        for _, sting in userStings do
            if #choices >= 25 then
                break
            end
            local matches, _, _ = string.find(sting.stingId:lower(), if typedName then typedName:lower() else "")
            if typedName and not matches then
                continue
            end
            table.insert(choices, {
                name = `Sting ID: {sting.stingId}`,
                value = sting.stingId,
            } :: apitypes.ApplicationCommandOptionChoiceObject)
        end
        return choices
    end

    return {}
end

return {
    command = command,
    run = run,
    autocompleter = autocompleter,
}