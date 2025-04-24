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
local onceLocal = require"@antiraid-ext/once".onceLocal
local store = require"@antiraid/stores".store

local evt: Primitives.Event, ctx: Primitives.TemplateContext = ...

-- List of users who can use dev commands
local devs = {
    ["728871946456137770"] = true,
}

local isInDevMode = true -- TODO

onceLocal("builtins.init", function() 
    local storeTab = store(ctx) :: any
    if storeTab.onBuiltinsLoad and type(storeTab.onBuiltinsLoad) == "function" then 
        storeTab.onBuiltinsLoad()
    end

    -- Register builtins
    storeTab.builtins = {
        StingManager = stingmanager(ctx),
    }
    return nil
end)

local ge: executor.GlobalExecutor = _G.globalexecutor or executor.NewGlobalExecutor(ctx)
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

        local cmdList = serde.encode("json", commandList :: any)
        if #cmdList > 2000 then
            -- Limit to 1997 chars and add a ... at the end
            cmdList = cmdList:sub(1, 1997) .. "..."
        end

        promise.yield(ge.discord:create_message({
            channel_id = msg.channel_id,
            data = {
                content = cmdList,
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
        chunk.chunk_name = "__builtindev_eval_chunk"
        chunk.environment = {
            globals = _G,
            ge = ge,
            ctx = ctx,
            msg = msg,
            commands = commands,
            data = data,
            evt = evt,
            storeTab = store(ctx),
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

InteractionCreate(evt, function(interaction: apitypes.InteractionObject)  
    local parsedcmd = appcommands.parseApplicationCommand(interaction)
    if not parsedcmd then return end

    if isInDevMode then
        parsedcmd.baseName = parsedcmd.baseName:gsub("-dev", "")
    end

    local command = commands.commands[parsedcmd.baseName]
    if not command then -- Likely another template's command
        return 
    end

    --[[
    ctx: primitives.TemplateContext, 
    event: primitives.Event, 
    interaction: discord.InteractionObject,
    ge: executor.GlobalExecutor,
    command: appcommands.ParsedApplicationCommand
    ]]
    local runData: data.RunData = {
        ctx = ctx,
        event = evt,
        command = parsedcmd,    
        interaction = interaction,
        stingManager = stingmanager(ctx),
        ge = ge,
    }

    local ok, err = pcall(command.run, runData)
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

        interactionutils.replySimple(
            ge,
            interaction,
            nil,
            {
                {
                    title = "Something happened!",
                    description = "Something happened while trying to process your request. If the problem persists, **please report it to our Support Server**\n```lua\n" .. debug.traceback(err) .. "\n```",
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
                    stingManager = stingmanager(ctx),
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
                    stingManager = stingmanager(ctx),
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
        stingManager = stingmanager(ctx),
        ge = ge,
    })
end)