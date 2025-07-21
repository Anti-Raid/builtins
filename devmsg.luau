local Framework = require"@antiraid-ext/framework"
local apitypes = require "@discord-types/apiTypes"
local string_startswith = require "@antiraid-ext/strings/startswith"
local Primitives = require "@antiraid-core/primitives"
local devData = require"./devs"
local devs = devData.devs :: {[string]: boolean}

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

    if content == "dev:register-dev" then
        local framework = Framework.getFramework()
        assert(framework, "Framework is nil")     
        local commandList = framework.base.commands()   

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
    end    
end

return dev