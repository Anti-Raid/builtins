local Primitives = require "@antiraid-core/primitives"
local Message = require "@antiraid-ext/events/discord/Message"
local commands = require "./commands/commands"
local settings = require "./settings/settings"
local afkhandler = require"./auxutils/afkhandler"
local onceLocal = require"@antiraid-ext/once".onceLocal
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

local function exec(evt: Primitives.Event, ctx: Primitives.TemplateContext): any
    onceLocal("builtins.init", function(): nil
        local storeTab = ctx.store :: any
        if storeTab.onBuiltinsLoad and type(storeTab.onBuiltinsLoad) == "function" then 
            storeTab.onBuiltinsLoad()
        end
        return nil
    end)

    -- AFK handling
    Message(evt, function(msg)
        require("./devmsg")(ctx, msg)
        afkhandler(msg, ctx)
    end)  

    return Framework.dispatch(evt, ctx)
end

return {
    exec = exec
}
