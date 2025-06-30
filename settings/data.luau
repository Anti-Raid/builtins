local settings = require"@antiraid-core/settings"
local events = require"@antiraid-core/events"
local userinfo = require"../utils/userinfo"

export type Setting = {
    schema: settings.Setting,
    execute: (event: events.SettingExecuteEvent, data: SettingsData) -> any
}

export type SettingsData = {
    userinfomanager: userinfo.UserInfoManager
}

return {}