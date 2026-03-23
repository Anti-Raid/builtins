local Primitives = require "@antiraid-core/primitives"
local KeyManager = require"@antiraid-ext/keymanager"
local typesext = require"@antiraid/typesext"
local templatemanagerImpl = require"@antiraid-core/templatemanager"

--- Internal storage type for templates (the item.value in KV)
type ITemplateStore = {
    content: typesext.MemoryVfs,
    paused: boolean,
    type: string,
    language: "luau",
}

--- Builtin template of the bot
local BUILTINS: templatemanagerImpl.Template = {
    id = "$builtins",
    source = {
        type = "builtins",
    },
    paused = false,
}

export type UpdateCbOp = "CreateCustom" | "UpdateCustom" | "DeleteCustom"

--- A data fetcher for templates.
---
--- Note for internal use: TemplateManager only needs the loop to be attached with subscribeEvent/unsubscribeEvent/isSubscribed/debugmanager (due to KeyManager)
local function TemplateManager(ctx: Primitives.TemplateContext, updatecb: (op: UpdateCbOp, key: string) -> ()): templatemanagerImpl.TemplateManager
    local self = {}

    local templatedb = KeyManager<<ITemplateStore>>(ctx, "builtins.templates")

    local exposedvfs = ctx.Runtime:getexposedvfs()
    local VfsBuiltins = exposedvfs.Builtins or error("Internal error: Builtins VFS not found in exposed VFSs")
    local VfsTemplatingTypes = exposedvfs.TemplatingTypes or error("Internal error: TemplatingTypes VFS not found in exposed VFSs")

    local function _parseCustomTemplate(item: KeyManager.KeyRecord<ITemplateStore>): templatemanagerImpl.Template
        return {
            id = "custom/"..item.key,
            source = {
                type = "custom",
                name = item.key,
                language = item.value.language,
                content = item.value.content,
                created_at = item.createdat,
                last_updated_at = item.lastupdatedat,
            },
            paused = item.value.paused,
        }
    end

    local function builtins(): templatemanagerImpl.Template
        return BUILTINS
    end

    local function list(): {templatemanagerImpl.Template}
        local data = templatedb.list()

        local templates = {BUILTINS}
        for _, item in data do
            local template = _parseCustomTemplate(item)
            table.insert(templates, template)
        end

        return templates
    end

    local function countcustom(): number
        return templatedb.count()
    end

    local function getcustom(key: string): templatemanagerImpl.Template?
        local data = templatedb.get(key)
        if not data then
            return nil -- Not found
        end
        return _parseCustomTemplate(data)
    end

    local function setcustom(data: templatemanagerImpl.CreateTemplate)
        local storedata: ITemplateStore = {
            type = "custom",
            content = data.content,
            paused = data.paused,
            language = data.language,
        }
        if templatedb.exists(data.name) then 
            templatedb.add(storedata, data.name)
            updatecb("CreateCustom", data.name)
        else
            updatecb("UpdateCustom", data.name)
        end
    end

    local function deletecustom(key: string): ()
        templatedb.remove(key)
        updatecb("DeleteCustom", key)
    end

    local function computevfs(template: templatemanagerImpl.Template): typesext.Vfs
        if template.vfs then
            return template.vfs
        end

        if template.source.type == "builtins" then 
            local vfs = typesext.Vfs.newoverlay({
                VfsBuiltins,
                VfsTemplatingTypes,
            })
            template.vfs = vfs
            return vfs
        elseif template.source.type == "custom" then
            local vfs = typesext.Vfs.newoverlay({
                template.source.content, -- newoverlay automatically handles memoryvfs
                VfsTemplatingTypes,
            })
            template.vfs = vfs
            return vfs
        else
            error("Internal error: Unsupported template source type "..tostring(template.source.type))
        end
    end

    self.builtins = builtins
    self.list = list
    self.countcustom = countcustom
    self.getcustom = getcustom
    self.setcustom = setcustom
    self.deletecustom = deletecustom
    self.computevfs = computevfs

    return self
end

return {
    TemplateManager = TemplateManager,
    BUILTINS = BUILTINS
}