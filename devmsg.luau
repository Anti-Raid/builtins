local interop = require"@antiraid/interop"
local commands = require "./commands/commands"
local data = require "./commands/data"
local luau = require "@antiraid/luau"
local toArray = require "@antiraid-ext/array".toArray
local apitypes = require "@discord-types/apiTypes"
local string_startswith = require "@antiraid-ext/strings/startswith"
local serde = require "@lune/serde"
local Primitives = require "@antiraid-core/primitives"
local UserInfoManager = require"@antiraid-ext/utils/userinfo"
local devData = require"./devs"
local isInDevMode = devData.isInDevMode
local devs = devData.devs :: {[string]: boolean}
local cmdLabel = devData.cmdLabel

local function dev(ctx: Primitives.TemplateContext, msg: apitypes.MessageObject)
    if not msg.author then return end
    if not msg.channel_id then return end
    
    -- If the content does not starts with the bot mention, return
    assert(ctx.current_user, "ctx.current_user is nil")
    assert(ctx.current_user.id, "ctx.current_user is nil")
    local botMention = "<@" .. ctx.current_user.id .. ">"
    if not msg.content or not string_startswith(msg.content, botMention .. " ") then
        return
    end
    
    -- Luau type solver bug bypass
    local content: string = ((msg :: any).content :: string):sub(#botMention + 2)
    local authorId: string = (msg :: any).author.id
    
    if not devs[authorId] then
        return
    end

    if content == "dev:register" then     
        local commandList = {}
        for _, command in commands.commands do
            local cmd = command().register()
            if isInDevMode then 
                cmd.name = cmd.name .. cmdLabel
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
    
        ctx.Discord:create_message({
            channel_id = msg.channel_id or error("msg.channel_id is nil"),
            data = {
                content = "Registering " .. cmdList .. " [" .. (#commandsBeingRegistered) .. " commands]",
            }
        })
    
        ctx.Discord:create_guild_commands({
            data = commandList, 
        })
    
        ctx.Discord:create_message({
            channel_id = msg.channel_id or error("msg.channel_id is nil"),
            data = {
                content = "Registered commands",
            }
        })
    elseif content == "dev:stdout" then
        ctx.Discord:create_message({
            channel_id = msg.channel_id,
            data = {
                content = "stdout: " .. table.concat(_G.stdout or {} :: any, "\n"),
            }
        })
    -- If it starts with dev:eval, run the code
    elseif content and content:sub(1, 9) == "dev:eval " then
        local chunkContent = content:sub(10):gsub("`", "")
    
        local chunk = luau.load(chunkContent)
        chunk.optimization_level = 2
        chunk.chunk_name = "/init"
        chunk.environment = {
            globals = _G,
            require = require,
            serde = serde,
            jsonify = function(obj)
                return serde.encode("json", obj)
            end,
            ctx = ctx,
            msg = msg :: any,
            commands = commands,
            data = data,
            storeTab = ctx.store,
            type = type,
            typeof = typeof,
            interop = interop,
            memusage = interop.memusage,
            requirememusage = _G.memusage,
            requirememusage_half = _G.memusage_half,
            requirememusage_quarter = _G.memusage_quarter,
            requirememusage_initial = _G.memusage_initial,
            userinfomanager = UserInfoManager(ctx)
        }
    
        local ok, result = pcall(chunk.call_async, chunk, {})    

        local resp = tostring(result)
        if #resp > 4000 then
            -- Limit to 3997 chars and add a ... at the end
            resp = resp:sub(1, 3997) .. "..."   
        end
    
        ctx.Discord:create_message({
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
        })
    elseif content and content:sub(1, 10) == "dev:evalj " then
        local chunkContent = content:sub(11):gsub("`", "")
    
        local chunk = luau.load(chunkContent)
        chunk.optimization_level = 2
        chunk.chunk_name = "/init"
        chunk.environment = {
            globals = _G,
            require = require,
            serde = serde,
            jsonify = function(obj)
                return serde.encode("json", obj)
            end,
            ctx = ctx,
            msg = msg :: any,
            commands = commands,
            data = data,
            storeTab = ctx.store,
            type = type,
            typeof = typeof,
            interop = interop,
            memusage = interop.memusage,
            requirememusage = _G.memusage,
            requirememusage_half = _G.memusage_half,
            requirememusage_quarter = _G.memusage_quarter,
            requirememusage_initial = _G.memusage_initial,
            userinfomanager = UserInfoManager(ctx)
        }
    
        local ok, result = pcall(chunk.call_async, chunk, {})  
        
        local json = serde.encode("json", result)
        if #json > 4000 then
            -- Limit to 3997 chars and add a ... at the end
            json = json:sub(1, 3997) .. "..."
        end
    
        ctx.Discord:create_message({
            channel_id = msg.channel_id,
            data = {
                embeds = toArray({
                    {
                        title = "Result",
                        description = "```\n" .. json .. "\n```",
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
        })    
    end    
end

return dev