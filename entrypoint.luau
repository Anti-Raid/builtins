--local f = require"./cached"
--error(f())

local interop = require"@antiraid/interop"

local RECORDING = false
if not _G.memusage then 
    _G.memusage = interop.memusage()
    _G.memusage_half = interop.memusage()
    _G.memusage_quarter = interop.memusage()
    _G.memusage_initial = _G.memusage
    RECORDING = true
end

local Primitives = require "@antiraid-core/primitives"
local Message = require "@antiraid-ext/events/discord/Message"
local InteractionCreate = require "@antiraid-ext/events/discord/InteractionCreate"
local KeyExpiry = require "@antiraid-ext/events/antiraid/KeyExpiry"
local appcommands = require"@antiraid-ext/appcommands"
local interactionutils = require"./utils/interaction"
local ActionRowBuilder = require"@discord-types/builders/message/components/actionRow"
local ButtonBuilder = require"@discord-types/builders/message/components/button"

if RECORDING then 
    _G.memusage_quarter = interop.memusage() - _G.memusage_quarter
end

local apiTypes = require"@discord-types/apiTypes"
local commands = require "./commands/commands"
local data = require "./commands/data"
local apitypes = require "@discord-types/apiTypes"

if RECORDING then 
    _G.memusage_half = interop.memusage() - _G.memusage_half
end

local stingmanager = require "./utils/stingmanager"
local punishmentmanager = require"./utils/punishmentmanager"
local builtinSettingsManager = require"./utils/builtinsettingsmanager" 
local onceLocal = require"@antiraid-ext/once".onceLocal
local Interaction = require"@discord-types/interaction"
local devData = require"./devs"
local devs = devData.devs :: {[string]: boolean}
local isInDevMode = devData.isInDevMode
local cmdLabel = devData.cmdLabel

if RECORDING then 
    _G.memusage = interop.memusage() - _G.memusage
end


-- Internal function to attach a button callback
local function attachButtonCallback(buttonId: string, callback: (bcd: data.ButtonCallbackData) -> nil) 
    if not _G.attachedButtonCallbacks then
        _G.attachedButtonCallbacks = {} :: any
    end
    _G.attachedButtonCallbacks[buttonId] = callback
    return nil
end

local function dropButtonCallback(buttonId: string): nil
    if not _G.attachedButtonCallbacks then
        return nil
    end
    (_G.attachedButtonCallbacks :: any)[buttonId] = nil
    return nil
end    

local function exec(evt: Primitives.Event, ctx: Primitives.TemplateContext) 
    onceLocal("builtins.init", function(): nil
        local storeTab = ctx.store :: any
        if storeTab.onBuiltinsLoad and type(storeTab.onBuiltinsLoad) == "function" then 
            storeTab.onBuiltinsLoad()
        end

        -- Register builtins
        storeTab.stingManager = stingmanager(ctx)
        storeTab.punishmentManager = punishmentmanager(ctx, storeTab.stingManager)
        storeTab.builtinSettingsManager = builtinSettingsManager(ctx)

        _G.storeTab = storeTab
        return nil
    end)

    Message(evt, function(msg)
        require("./devmsg")(ctx, msg)
    end)  

    InteractionCreate(evt, function(interaction: apitypes.InteractionObject)              
        if interaction.type == Interaction.InteractionType.MessageComponent then 
            if not _G.attachedButtonCallbacks then
                return
            end

            if not interaction.data or not interaction.data.custom_id then 
                return
            end

            local callback: (bcd: data.ButtonCallbackData) -> nil = (_G.attachedButtonCallbacks :: any)[interaction.data.custom_id]
            if not callback then
                local comps = nil
                local linksstore = ctx.DataStores.LinksStore 
                if linksstore then 
                    comps = {
                        ActionRowBuilder.new()
                        :addComponent(
                            ButtonBuilder.new()
                            :setStyle("Blurple")
                            :setLabel("Support Server")
                            :setUrl(linksstore.links().support_server)
                            :build()
                        )
                        :build() :: apiTypes.ComponentObjects
                    }
                end
        
                interactionutils.replySimple(
                    ctx,
                    interaction :: apiTypes.InteractionObject,
                    nil,
                    {
                        {
                            title = "Unknown button clicked!",
                            description = "Make sure that the button hasn't expired! You probably waited too long! \nIf the problem persists, **please report it to our Support Server**",
                            color = 0xFF0000,
                        }
                    } :: {apiTypes.EmbedObject},
                    true,
                    comps
                )
                return
            end

            local function removeCallback(): nil
                _G.attachedButtonCallbacks[interaction.data.custom_id] = nil
                return nil
            end

            callback(
                {
                    ctx = ctx,
                    interaction = interaction, 
                    removeCallback = removeCallback,
                    event = evt,
                } :: data.ButtonCallbackData
            )
            return
        end

        local parsedcmd = appcommands.parseApplicationCommand(interaction)
        if not parsedcmd then return end

        if isInDevMode then
            local newCmdName = parsedcmd.baseName:gsub(cmdLabel, "")
            if newCmdName == parsedcmd.baseName then 
                return -- This is from the production environment, not dev!
            end
            parsedcmd.baseName = newCmdName
        end

        local command = commands.commands[parsedcmd.baseName]
        if not command then -- Likely another template's command
            return 
        end

        if command().devOnly then 
            local authorId = if interaction.user then interaction.user.id elseif (interaction.member and interaction.member.user) then interaction.member.user.id else error("No user found")
            if not authorId or not devs[authorId] then 
                error("Not a dev: " .. authorId)
                return -- Not a dev
            end 
        end

        if interaction.type == Interaction.InteractionType.ApplicationCommandAutocomplete then 
            command = command()
            if not command.autocompleter then 
                --if isInDevMode then error("Command autocompleter not found: " .. parsedcmd.baseName) end
                return
            end

            local autocompleteData: data.AutocompleteRunData = {
                ctx = ctx,
                event = evt,
                interaction = interaction,
                stingManager = _G.storeTab.stingManager,
                builtinSettingsManager = _G.storeTab.builtinSettingsManager,
                command = parsedcmd,
            }

            local results = command.autocompleter(autocompleteData) or {}
            if #results > 25 then
                -- Results are limited to 25 so we need to trim the table
                local trimmedResults = {}
                for i = 1, 25 do
                    trimmedResults[i] = results[i]
                end
                results = trimmedResults
            end

            -- Send the results
            interactionutils.replyAutocomplete(
                ctx,
                interaction,
                results :: any
            )
            return
        end

        local hasEdited = false
        local runData: data.RunData = {
            ctx = ctx,
            event = evt,
            command = parsedcmd,    
            interaction = interaction,
            stingManager = _G.storeTab.stingManager,
            punishmentmanager = _G.storeTab.punishmentManager,
            builtinSettingsManager = _G.storeTab.builtinSettingsManager,
            attachButtonCallback = attachButtonCallback,
            sethasEdited = function(to: boolean): nil
                hasEdited = to
                return nil
            end,
            dropButtonCallback = dropButtonCallback,
        }

        local ok, err = xpcall(command().run, debug.traceback :: any, runData)
        if not ok then 
            err = tostring(err) :: string
            if #err > 2000 then 
                -- Limit to 1997 chars and add a ... at the end
                err = err:sub(1, 1997) .. "..."
            end

            local comps = nil
            local linksstore = ctx.DataStores.LinksStore
            if linksstore then 
                comps = {
                    ActionRowBuilder.new()
                    :addComponent(
                        ButtonBuilder.new()
                        :setStyle("Blurple")
                        :setLabel("Support Server")
                        :setUrl(linksstore.links().support_server)
                        :build()
                    )
                    :build() :: apiTypes.ComponentObjects
                }
            end

            -- Check if ephemeral or nor
            local isResponseEphemeral = false

            -- Parse options
            for _, opt in parsedcmd.options do 
                if opt.name == "ephemeral" then
                    if opt.value.kind == "Boolean" then
                        isResponseEphemeral = opt.value.value
                    end
                end
            end 
            
            local embed = {
                {
                    title = "Something happened!",
                    description = "Something happened while trying to process your request. If the problem persists, **please report it to our Support Server**\n```lua\n" .. err .. "\n```",
                    color = 0xFF0000,
                }
            } :: {apiTypes.EmbedObject}

            if hasEdited then 
                interactionutils.editSimple(
                    ctx,
                    interaction,
                    nil,
                    embed,
                    comps
                )
                return
            end

            interactionutils.replySimple(
                ctx,
                interaction,
                nil,
                embed,
                isResponseEphemeral,
                comps
            )
        end
    end)

    KeyExpiry(evt, function(data)
        --error("KeyExpiry event triggered")
        for _, scope in data.scopes do 
            for _, cmd in commands.commands do 
                local cmdR = cmd()
                if cmdR.keyexpiries then
                    local fn = cmdR.keyexpiries[scope]
                    if fn then
                        fn({
                            ctx = ctx,
                            event = evt,
                            data = data,
                            stingManager = _G.storeTab.stingManager,
                            punishmentmanager = _G.storeTab.punishmentManager,
                            builtinSettingsManager = _G.storeTab.builtinSettingsManager,
                        })
                    end
                end
            end                
        end
    end)
end

return {
    exec = exec
}
