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

-- Audit log event handlers
local auditlogBan = require"./auxutils/auditlogs/AntiraidBan"
local auditlogKick = require"./auxutils/auditlogs/AntiraidKick"
local auditlogUnban = require"./auxutils/auditlogs/AntiraidUnban"
local auditlogStingCreated = require"./auxutils/auditlogs/BuiltinsStingCreated"
local auditlogStingDelete = require"./auxutils/auditlogs/BuiltinsStingDelete"

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
        managers.getmanagers(ctx) -- Ensure managers are initialized before handling any messages, it is generally a good idea to ensure all managers are ready before processing any events
        afkhandler(msg, ctx)
        urlblockhandler(msg, ctx)
        honeypothandler(msg, ctx)
    end),
    Custom("OnStartup")(function(ctx, data)
        -- Initialize afk/sting/key expiration managers on startup
        -- along with backup restore checkpoint expiry with oninit logic to resume existing checkpoints
        managers.getmanagers(ctx)
    end),
    -- Audit log event handlers
    auditlogBan,
    auditlogKick,
    auditlogUnban,
    auditlogStingCreated,
    auditlogStingDelete
)
assert(type(ret) == "table", "Framework setup did not return a table")
return ret