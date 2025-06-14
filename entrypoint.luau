--local f = require"./cached"
--error(f())

local executor = require "@antiraid-ext/executor"
local promise = require "@antiraid/promise"
local Primitives = require "@antiraid-core/primitives"
local Message = require "@antiraid-ext/events/discord/Message"
local InteractionCreate = require "@antiraid-ext/events/discord/InteractionCreate"
local ScheduledExecution = require "@antiraid-ext/events/antiraid/ScheduledExecution"
local appcommands = require"@antiraid-ext/appcommands"
local interactionutils = require"./utils/interaction"
local ActionRowBuilder = require"@discord-types/builders/message/components/actionRow"
local ButtonBuilder = require"@discord-types/builders/message/components/button"
local apiTypes = require"@discord-types/apiTypes"
local commands = require "./commands/commands"
local data = require "./commands/data"
local luau = require "@antiraid/luau"
local toArray = require "@antiraid-ext/array".toArray
local apitypes = require "@discord-types/apiTypes"
local string_startswith = require "@antiraid-ext/strings/startswith"
local serde = require "@lune/serde"
local ds = require "@antiraid/datastores"
local fallbackScheduledExecs = require"./scheduledexecs/scheduledexecs".fallbackScheduledExecs
local stingmanager = require "./utils/stingmanager"
local punishmentmanager = require"./utils/punishmentmanager"
local builtinSettingsManager = require"./utils/builtinsettingsmanager" 
local onceLocal = require"@antiraid-ext/once".onceLocal
local store = require"@antiraid/stores".store
local Interaction = require"@discord-types/interaction"
local interop = require"@antiraid/interop"

local isInDevMode = true -- TODO
-- List of users who can use dev commands
local devs = {
    ["728871946456137770"] = true,
    ["564164277251080208"] = true,
    ["787241442770419722"] = true,
}

local function exec(evt: Primitives.Event, ctx: Primitives.TemplateContext) 
    local errorReportChannel = ctx.data.error_channel

    local ge: executor.GlobalExecutor
    if _G.globalexecutor then
        ge = _G.globalexecutor :: executor.GlobalExecutor
    else
        ge = executor.NewGlobalExecutor(ctx)
        _G.globalexecutor = (ge :: any)
    end

    onceLocal("builtins.init", function(): nil
        if _G._TEST_ASYNC_WORK then return nil end
        local storeTab = store :: any
        if storeTab.onBuiltinsLoad and type(storeTab.onBuiltinsLoad) == "function" then 
            storeTab.onBuiltinsLoad()
        end

        -- Register builtins
        storeTab.stingManager = stingmanager(ctx)
        storeTab.punishmentManager = punishmentmanager(ctx, ge, storeTab.stingManager)
        storeTab.builtinSettingsManager = builtinSettingsManager(ctx)

        _G.storeTab = storeTab
        return nil
    end)

    local function run(evt: Primitives.Event)
        Message(evt, function(msg)
            if not msg.author then return end
            if not msg.channel_id then return end
            
            -- If the content does not starts with the bot mention, return
            assert(ctx.current_user, "ctx.current_user is nil")
            assert(ctx.current_user.id, "ctx.current_user is nil")
            local botMention = "<@" .. ctx.current_user.id .. ">"
            if not msg.content or not string_startswith(msg.content, botMention .. " ") then
                return
            end

            local content = msg.content:sub(#botMention + 2)

            if content == "dev:register" then 
                if not devs[msg.author.id] then
                    return
                end

                local commandList = {}
                for _, command in commands.commands do
                    local cmd = command.register()
                    if isInDevMode then 
                        cmd.name = cmd.name .. "-dev"
                    end
                    table.insert(commandList, cmd)
                end

                local commandsBeingRegistered = {}

                for _, command in commandList do
                    table.insert(commandsBeingRegistered, command.name)
                end

                local cmdList = table.concat(commandsBeingRegistered, ", ")
                if #cmdList > 2000 then
                    -- Limit to 1997 chars and add a ... at the end
                    cmdList = cmdList:sub(1, 1997) .. "..."
                end

                promise.yield(ge.discord:create_message({
                    channel_id = msg.channel_id,
                    data = {
                        content = "Registering " .. cmdList .. " [" .. (#commandsBeingRegistered) .. " commands]",
                    }
                }))

                promise.yield(ge.discord:create_guild_commands({
                    data = commandList, 
                }))

                promise.yield(ge.discord:create_message({
                    channel_id = msg.channel_id,
                    data = {
                        content = "Registered commands",
                    }
                }))
            elseif content == "dev:stdout" then
                if not devs[msg.author.id] then
                    return
                end

                promise.yield(ge.discord:create_message({
                    channel_id = msg.channel_id,
                    data = {
                        content = "stdout: " .. table.concat(_G.stdout or {} :: any, "\n"),
                    }
                }))
            -- If it starts with dev:eval, run the code
            elseif content and content:sub(1, 9) == "dev:eval " then
                if not devs[msg.author.id] then
                    return
                end

                local chunkContent = content:sub(10)
                :gsub("`", "")

                local chunk = luau.load(ctx, chunkContent)
                chunk.optimization_level = 2
                chunk.chunk_name = "/init"
                chunk.environment = {
                    globals = _G,
                    require = require,
                    promise = promise,
                    pyield = promise.yield,
                    serde = serde,
                    jsonify = function(obj)
                        return serde.encode("json", obj)
                    end,
                    ge = ge,
                    ctx = ctx,
                    msg = msg,
                    commands = commands,
                    data = data,
                    evt = evt,
                    storeTab = store,
                    type = type,
                    typeof = typeof,
                    interop = interop,
                    memusage = interop.memusage
                }
                local ok, result = pcall(promise.yield, chunk:call_async({}))    

                promise.yield(ge.discord:create_message({
                    channel_id = msg.channel_id,
                    data = {
                        embeds = toArray({
                            {
                                title = "Result",
                                description = "```\n" .. tostring(result) .. "\n```",
                                fields = toArray({
                                    {
                                        name = "OK",
                                        value = tostring(ok),
                                        inline = false,
                                    },
                                }),
                                color = if ok then 0x00FF00 else 0xFF0000,
                            },
                        }) :: {apitypes.EmbedObject}
                    }
                }))
            end
        end)  

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
                    if ge.datastores.LinksStore then 
                        local linksstore = ge.datastores.LinksStore :: ds.LinksStore
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
                        ge,
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
                        ge = ge,
                        event = evt,
                    } :: data.ButtonCallbackData
                )
                return
            end

            local parsedcmd = appcommands.parseApplicationCommand(interaction)
            if not parsedcmd then return end

            if isInDevMode then
                parsedcmd.baseName = parsedcmd.baseName:gsub("-dev", "")
            end

            local command = commands.commands[parsedcmd.baseName]
            if not command then -- Likely another template's command
                --if isInDevMode then error("Command not found: " .. parsedcmd.baseName) end
                return 
            end

            if interaction.type == Interaction.InteractionType.ApplicationCommandAutocomplete then 
                if not command.autocompleter then 
                    --if isInDevMode then error("Command autocompleter not found: " .. parsedcmd.baseName) end
                    return
                end

                local autocompleteData: data.AutocompleteRunData = {
                    ctx = ctx,
                    event = evt,
                    interaction = interaction,
                    ge = ge,
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
                    ge,
                    interaction,
                    results
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
                ge = ge,
                attachButtonCallback = attachButtonCallback,
                sethasEdited = function(to: boolean): nil
                    hasEdited = to
                    return nil
                end,
                dropButtonCallback = dropButtonCallback,
            }

            local ok, err = xpcall(command.run, debug.traceback, runData)
            if not ok then 
                err = tostring(err) :: string
                if #err > 2000 then 
                    -- Limit to 1997 chars and add a ... at the end
                    err = err:sub(1, 1997) .. "..."
                end

                local comps = nil
                if ge.datastores.LinksStore then 
                    local linksstore = ge.datastores.LinksStore :: ds.LinksStore
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
                
                if hasEdited then 
                    interactionutils.editSimple(
                        ge,
                        interaction,
                        nil,
                        {
                            {
                                title = "Something happened!",
                                description = "Something happened while trying to process your request. If the problem persists, **please report it to our Support Server**\n```lua\n" .. err .. "\n```",
                                color = 0xFF0000,
                            }
                        } :: {apiTypes.EmbedObject},
                        comps
                    )
                    return
                end

                interactionutils.replySimple(
                    ge,
                    interaction,
                    nil,
                    {
                        {
                            title = "Something happened!",
                            description = "Something happened while trying to process your request. If the problem persists, **please report it to our Support Server**\n```lua\n" .. err .. "\n```",
                            color = 0xFF0000,
                        }
                    } :: {apiTypes.EmbedObject},
                    isResponseEphemeral,
                    comps
                )
            end
        end)

        ScheduledExecution(evt, function(data) 
            -- Split by :
            local id = data.id:split(":")
            if #id ~= 2 then
                -- Try going to the fallbacks if the id startswith builtins.
                if string_startswith(id[1], "builtins.") then
                    for _, fallback in fallbackScheduledExecs do 
                        if fallback({
                            ctx = ctx,
                            event = evt,
                            scheduledExecData = data,
                            scheduledExecId = data.id,
                            stingManager = _G.storeTab.stingManager,
                            ge = ge,
                        }) then 
                            return -- Fallback was found to have handled it
                        end
                    end
                end
                return
            end

            local command = commands.commands[id[1]]

            if not command then
                -- Try going to the fallbacks if the id startswith builtins.
                if string_startswith(id[1], "builtins.") then
                    for _, fallback in fallbackScheduledExecs do 
                        if fallback({
                            ctx = ctx,
                            event = evt,
                            scheduledExecData = data,
                            scheduledExecId = data.id,
                            stingManager = _G.storeTab.stingManager,
                            ge = ge,
                        }) then 
                            return -- Fallback was found to have handled it
                        end
                    end
                end
                return
            end

            if not command.scheduledexec then
                return
            end

            command.scheduledexec({
                ctx = ctx,
                event = evt,
                scheduledExecData = data,
                scheduledExecId = id[2],
                stingManager = _G.storeTab.stingManager,
                ge = ge,
            })
        end)
    end

    local ok, err = xpcall(run, debug.traceback :: any, evt)

    if not ok then 
        err = tostring(err) :: string
        if #err > 2000 then 
            -- Limit to 1997 chars and add a ... at the end
            err = err:sub(1, 1997) .. "..."
        end

        if errorReportChannel then 
            promise.yield(ge.discord:create_message({
                channel_id = errorReportChannel,
                data = {
                    embeds = toArray({
                        {
                            title = "An error has occurred!",
                            description = "```\n" .. tostring(err) .. "\n```",
                            fields = toArray({
                                {
                                    name = "OK",
                                    value = tostring(ok),
                                    inline = false,
                                },
                            }),
                            color = 0xFF0000,
                        },
                    }) :: {apitypes.EmbedObject}    
                }
            }))
        else
            print("Error in builtins: " .. err)
        end
    end
end

return {
    exec = exec
}
