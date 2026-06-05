--!strict
local array_metatable = require"@antiraid/interop".array_metatable
local verifyMemberPermOverrideChange = require"./permvalidator".verifyMemberPermOverrideChange
local data = require"@antiraid-ext/frameworkv2/context"
local kc = require"@antiraid-core/kittycat"

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
            created_at = tostring(memberPermissions.createdat),
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

    return {}
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

    return {}
end

return {
    view = view,
    create = create,
    update = update
}