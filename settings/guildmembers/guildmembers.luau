local settings = require"@antiraid-core/settings"
local settingsExt = require"@antiraid-ext/settings"
local events = require"@antiraid-core/events"
local verifyMemberPermOverrideChange = require"../permvalidator".verifyMemberPermOverrideChange
local kc = require"@antiraid-core/kittycat"
local data = require"@antiraid-ext/framework/coretypes"
local array_metatable = require"@antiraid/interop".array_metatable
local userinfoP = require"@antiraid-ext/utils/userinfo"
local typesext = require"@antiraid/typesext"

local EMPTY_ARRAY = setmetatable({}, array_metatable)
local guildmembers: settings.Setting = {
    id = "members",
    name = "Server Members",
    description = "Manage server members on AntiRaid",
    validation_template = [[
local typesext = require"@antiraid/typesext"
local data = ...

if data.op == "Create" or data.op == "Update" then
    if not data.fields.user_id or #data.fields.user_id == 0 then
        error("User ID cannot be empty")
    end
    
    local ok, err = pcall(
        typesext.U64,
        data.fields.user_id
    )

    if not ok then
        error("User ID must be a valid Discord User ID with error" .. tostring(err))
    end
end

data.fields.title = `{data.fields.user_id}, perm_overrides={table.concat(data.fields.perm_overrides, ', ')}`
return data.fields
]],
    operations = {"View", "Create", "Update", "Delete"},
    columns = {
        {
            id = "user_id",
            name = "User ID", 
            description = "The User ID",
            column_type = settingsExt.stringColumnType("Scalar", nil, 64, {}, "user"),
            primary_key = true,
            nullable = false,
            secret = false,
            readonly = {"View"}
        },
        {
            id = "perm_overrides",
            name = "Permission Overrides", 
            description = "Any permission overrides the member has. This can and should be e ted if needed",
            column_type = settingsExt.stringColumnType("Array", nil, nil, {}, "kittycat"),
            primary_key = false,
            nullable = false,
            secret = false,
            readonly = EMPTY_ARRAY
        },
        settingsExt.columnCreatedAt(),
        settingsExt.columnLastUpdatedAt(),
    }
}

local function execute(event: events.SettingExecuteEvent, data: data.SettingsData): any 
    if event.op == "View" then 
        verifyMemberPermOverrideChange({op = "View"})

        local result = setmetatable({}, array_metatable)

        local mpoe = data.userinfomanager.getMemberPermissionOverrides()

        for _, memberPermissions in mpoe do             
            local permsMap = {} 
            for _, _perm in memberPermissions.perm_overrides do 
                table.insert(permsMap, tostring(_perm))
            end

            assert(memberPermissions.raw.exists, "internal error: member data for member " .. memberPermissions.userid .. " does not exist in KV yet was found in KV at the same time")
            
            table.insert(result, {
                user_id = memberPermissions.userid,
                perm_overrides = permsMap,
                created_at = tostring(memberPermissions.raw.created_at),
                last_updated_at = tostring(memberPermissions.raw.last_updated_at),
            })
        end

        return result
    elseif event.op == "Create" then
        local userid = settingsExt.assertString("user_id", event.fields.user_id)
        local perm_overrides = settingsExt.assertStringArray("perm_overrides", event.fields.perm_overrides)

        if #userid == 0 then
            error("User ID cannot be empty")
        end

        local ok, _ = pcall(
            typesext.U64,
            userid
        )

        if not ok then
            error("User ID must be a valid Discord User ID")
        end

        -- TODO: Optimize multiple userinfo fetches
        local targetUserInfo = data.userinfomanager.get(userid)
        local authorUserinfo = data.userinfomanager.get(event.author)

        verifyMemberPermOverrideChange({op = "Create" :: "Create", authorUserInfo = authorUserinfo, targetUserInfo = targetUserInfo, perm_overrides = perm_overrides, author = event.author})

        local permsMapped = {}
        for _, perm in perm_overrides do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        data.userinfomanager.setMemberPermissionOverrides(userid, permsMapped)

        return {}
    elseif event.op == "Update" then
        local userid = settingsExt.assertString("user_id", event.fields.user_id)
        local perm_overrides = settingsExt.assertStringArray("perm_overrides", event.fields.perm_overrides)

        if #userid == 0 then
            error("User ID cannot be empty")
        end

        local ok, _ = pcall(
            typesext.U64,
            userid
        )

        if not ok then
            error("User ID must be a valid Discord User ID")
        end

        -- TODO: Optimize multiple userinfo fetches
        local targetUserInfo = data.userinfomanager.get(userid)

        if not targetUserInfo.permission_override_entry.raw.exists then
            error("This user does not have any permission overrides set. Please create them first.")
        end

        local authorUserinfo = data.userinfomanager.get(event.author)

        verifyMemberPermOverrideChange({op = "Update" :: "Update", authorUserInfo = authorUserinfo, targetUserInfo = targetUserInfo :: userinfoP.UserInfo, perm_overrides = perm_overrides, author = event.author})

        local permsMapped = {}
        for _, perm in perm_overrides do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        data.userinfomanager.setMemberPermissionOverrides(userid, permsMapped)

        return {}
    elseif event.op == "Delete" then
        local userid = settingsExt.assertString("user_id", event.fields.user_id)

        if #userid == 0 then
            error("User ID cannot be empty")
        end

        local ok, _ = pcall(
            typesext.U64,
            userid
        )

        if not ok then
            error("User ID must be a valid Discord User ID")
        end

        -- TODO: Optimize multiple userinfo fetches
        local targetUserInfo = data.userinfomanager.get(userid)

        if not targetUserInfo.permission_override_entry.raw.exists then
            error("This user does not have any permission overrides set. Please create them first.")
        end

        local authorUserinfo = data.userinfomanager.get(event.author)

        verifyMemberPermOverrideChange({op = "Delete" :: "Delete", authorUserInfo = authorUserinfo, targetUserInfo = targetUserInfo :: userinfoP.UserInfo, author = event.author})

        data.userinfomanager.deleteMemberPermissionOverrides(userid)
        
        return {user_id = userid}
    else
        error("Invalid setting being updated")
    end
end

return {
    schema = guildmembers,
    execute = execute
}