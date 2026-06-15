--!strict
local array_metatable = require"@antiraid/interop".array_metatable
local verifyMemberPermOverrideChange = require"./permvalidator".verifyMemberPermOverrideChange
local data = require"@antiraid-ext/frameworkv2/context"
local settings = require"@antiraid-ext/frameworkv2/settings"
local kc = require"@antiraid-core/kittycat"

local createform = settings.FormBuilder()
:text("user_id", "User ID")
:array_text("perm_overrides", "Permission Overrides")
:build()

local updateform = settings.FormBuilder()
:text("user_id", "User ID", { disabled = true })
:array_text("perm_overrides", "Permission Overrides")
:text("created_at", "Created At", { disabled = true })
:button("delete", "Remove Member Overrides", "Danger", false) -- delete the setting
:button("update", "Update Overrides", "Primary", true)
:build()

local function view(data: data.Framework) 
    verifyMemberPermOverrideChange({op = "View"})

    local result = setmetatable({}, array_metatable)

    local mpoe = data.userinfomanager.getMemberPermissionOverrides()

    for _, memberPermissions in mpoe do             
        local permsMap = {} 
        for _, _perm in memberPermissions.perm_overrides do 
            table.insert(permsMap, tostring(_perm))
        end
        
        table.insert(result, {
            user_id = memberPermissions.userid,
            perm_overrides = permsMap,
            created_at = memberPermissions.createdat,
        })
    end

    return result
end

export type CreateData = {
    author: string,
    userid: string,
    permoverrides: {string}
}

local function create(data: data.Framework, cd: CreateData) 
    -- TODO: Optimize multiple userinfo fetches
    local targetUserInfo = data.userinfomanager.get(cd.userid)
    local authorUserinfo = data.userinfomanager.get(cd.author)

    verifyMemberPermOverrideChange({op = "Create" :: "Create", authorUserInfo = authorUserinfo, targetUserInfo = targetUserInfo, perm_overrides = cd.permoverrides, author = cd.author})

    local permsMapped = {}
    for _, perm in cd.permoverrides do 
        table.insert(permsMapped, kc.Permission.from_string(perm))
    end    

    data.userinfomanager.setMemberPermissionOverrides(cd.userid, permsMapped)
end

local function update(data: data.Framework, cd: CreateData) 
    local targetUserInfo = data.userinfomanager.get(cd.userid)

    if not targetUserInfo.permission_override_entry.createdat then
        error("This user does not have any permission overrides set. Please create them first.")
    end

    local authorUserinfo = data.userinfomanager.get(cd.author)

    verifyMemberPermOverrideChange({op = "Update" :: "Update", authorUserInfo = authorUserinfo, targetUserInfo = targetUserInfo, perm_overrides = cd.permoverrides, author = cd.author})

    local permsMapped = {}
    for _, perm in cd.permoverrides do 
        table.insert(permsMapped, kc.Permission.from_string(perm))
    end    

    data.userinfomanager.setMemberPermissionOverrides(cd.userid, permsMapped)
end

local function delete(data: data.Framework, userid: string, author: string) 
    -- TODO: Optimize multiple userinfo fetches
    local targetUserInfo = data.userinfomanager.get(userid)

    if not targetUserInfo.permission_override_entry.createdat then
        error("This user does not have any permission overrides set. Please create them first.")
    end

    local authorUserinfo = data.userinfomanager.get(author)

    verifyMemberPermOverrideChange({op = "Delete" :: "Delete", authorUserInfo = authorUserinfo, targetUserInfo = targetUserInfo, author = author})

    data.userinfomanager.deleteMemberPermissionOverrides(userid)
end

local function fetch(p: settings.PageBuilder<data.Framework>)
    p
    :section("mp", "Member Permissions", "Manage member-specific permission overrides on AntiRaid", function(sb: settings.SectionBuilder<data.Framework>)
        sb
        :formset(
            "mp_create", 
            createform,
            false
        )
        :formset(
            "mp_update", 
            updateform,
            true
        )
    end)

    -- add it to the form
    p:addformdata("mp_create", { id = "mp_create_form", title = "Create Member Override", data = {
        user_id = "",
        perm_overrides = setmetatable({}, array_metatable)
    } })
    local mpd = view(p.data)
    for _, mp in mpd do 
        p:addformdata("mp_update", { id = mp.user_id, title = mp.user_id, data = mp :: any })
    end
end

return {
    fetch = fetch,
    view = view,
    create = create,
    update = update,
    delete = delete
}