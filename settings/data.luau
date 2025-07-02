local settings = require"@antiraid-core/settings"
local events = require"@antiraid-core/events"
local userinfo = require"../utils/userinfo"
local primitives = require "@antiraid-core/primitives"

export type Setting = {
    schema: settings.Setting,
    execute: (event: events.SettingExecuteEvent, data: SettingsData) -> any
}

export type SettingsData = {
    userinfomanager: userinfo.UserInfoManager,
    ctx: primitives.TemplateContext, 
}

return {}