local Message = require "@antiraid-ext/events/discord/Message"
local Custom = require "@antiraid-ext/events/antiraid/Custom"
local commands = require "./commands/commands"
local settings = require "./settings/settings"
local afkhandler = require"./auxutils/afkhandler"
local urlblockhandler = require"./auxutils/urlblockhandler".urlblockHandler
local honeypothandler = require"./auxutils/honeypothandler"
local managers = require"./auxutils/managers/managers"
local devData = require"./devs"
local isInDevMode = devData.isInDevMode
local cmdLabel = devData.cmdLabel

-- Setup framework
local Framework = require"@antiraid-ext/framework"
local suffix = if isInDevMode then cmdLabel else nil
local fw = Framework.SimpleFramework(true, suffix, commands.commands)
for name, setting in settings.settings do 
    fw.base.registerSetting(name, setting)
end

Framework.setFramework(fw)
local ret = Framework.setup(
    Message(function(ctx, msg)
        if devData.isInDevMode then
            require("./devmsg")(ctx, msg)
        end
        afkhandler(msg, ctx)
        urlblockhandler(msg, ctx)
        honeypothandler(msg, ctx)
    end),
    Custom("OnStartup")(function(ctx, data)
        managers.getmanagers(ctx) -- Initialize afk/sting/key expiration managers on startup
    end)
)
assert(type(ret) == "table", "Framework setup did not return a table")
return ret