local ctx = require"@antiraid-ext/frameworkv2/context"
local settings = require"@antiraid-core/settings"
local gm = require"./guildmembers"
local sb = require"@antiraid-ext/frameworkv2/settings"
local data = require"@antiraid-ext/frameworkv2/context"
local sf = require"@antiraid-ext/frameworkv2/settings"

local dummyform = sb.FormBuilder()
:text("text", "Some Text")
:button("send", "Send", "Primary", true)
:build()

local handler: ctx.SettingsHandler = {
    fetchpage = function(ctx: ctx.SettingsFetchPageContext): settings.Page 
        local sb = sb.PageBuilder(ctx.framework)
        gm.fetch(sb) -- fetch guild members

        -- dummy reorderable form
        sb
        :section("dummy", "Dummy Form", "Dummy Form", function(sb: sf.SectionBuilder<data.Framework>)
            sb
            :formset(
                "dummy", 
                dummyform,
                true
            )
        end)

        sb:addformdata("dummy", { id = "a", title = "A", data = { text = "initial1" } })
        sb:addformdata("dummy", { id = "b", title = "B", data = { text = "initial2" } })
        sb:addformdata("dummy", { id = "c", title = "C", data = { text = "initial3" } })

        return sb:build()
    end
}

return handler