local ctx = require"@antiraid-ext/frameworkv2/context"
local settings = require"@antiraid-core/settings"
local gm = require"./guildmembers"
local sb = require"@antiraid-ext/frameworkv2/settings"


local handler: ctx.SettingsHandler = {
    fetchpage = function(ctx: ctx.SettingsFetchPageContext): settings.Page 
        local sb = sb.PageBuilder(ctx.framework)
        gm.fetch(sb) -- fetch guild members
        return sb:build()
    end
}

return handler