local executor = require "@antiraid-ext/executor"
local promise = require "@antiraid/promise"
local Primitives = require "@antiraid-core/primitives"
local Message = require "@antiraid-ext/events/discord/Message"
local InteractionCreate = require "@antiraid-ext/events/discord/InteractionCreate"
local appcommands = require"@antiraid-ext/appcommands"
local commands = require "./commands/commands"
local data = require "./commands/data"
local luau = require "@antiraid/luau"
local toArray = require "@antiraid-ext/array".toArray
local apitypes = require "@discord-types/apiTypes"
local string_startswith = require "@antiraid-ext/strings/startswith"
local serde = require "@lune/serde"

local evt: Primitives.Event, ctx: Primitives.TemplateContext = ...

-- List of users who can use dev commands
local devs = {
    ["728871946456137770"] = true,
}

local isInDevMode = true -- TODO

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

        promise.yield(ge.discord:create_message({
            channel_id = msg.channel_id,
            data = {
                content = serde.encode("json", commandList :: any),
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
        chunk.environment = _G
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
    if not command then 
        error("Command " .. parsedcmd.baseName .. " not found")
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
        ge = ge,
    }

    command.run(runData)
end)