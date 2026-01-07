local Primitives = require "@antiraid-core/primitives"
local settingsext = require "@antiraid-ext/settings"
local kv = require "@antiraid-core/plugins/kv"
local runtime = require"@antiraid-core/plugins/runtime"
local typesext = require"@antiraid/typesext"
local templatemanagerImpl = require"@antiraid-core/templatemanager"

--- Internal storage type for templates (the item.value in KV)
type ITemplateStore = {
    content: runtime.LazyContent,
    allowed_caps: { string },
    paused: boolean,
    name: string,
    type: string,
    language: string,
}

--- Builtin template of the bot
local BUILTINS: templatemanagerImpl.Template = {
    id = "$builtins",
    source = {
        type = "builtins",
    },
    allowed_caps = {"*"},
    paused = false,
}

--- A data fetcher for templates.
local function TemplateManager(ctx: Primitives.TemplateContext): templatemanagerImpl.TemplateManager
    local self = {}

    local exposedvfs = ctx.Runtime:getexposedvfs()
    local VfsBuiltins = exposedvfs.Builtins or error("Internal error: Builtins VFS not found in exposed VFSs")
    local VfsBuiltinsPatches = exposedvfs.BuiltinsPatches or error("Internal error: BuiltinsPatches VFS not found in exposed VFSs")
    local VfsTemplatingTypes = exposedvfs.TemplatingTypes or error("Internal error: TemplatingTypes VFS not found in exposed VFSs")


    local function _parseCustomTemplate(item: kv.KvRecord): templatemanagerImpl.Template
        assert(item.exists, "Internal error: Template item does not exist")
        local content = item.value.content
        local name = settingsext.assertString("name", item.value.name)
        assert(type(content) == "userdata", "Internal error: Template content is not userdata")
        local allowedCaps = settingsext.assertStringArray("allowed_caps", item.value.allowed_caps)
        local paused = settingsext.assertBoolean("paused", item.value.paused)
        local language = settingsext.assertString("language", item.value.language)
        assert(language == "luau", "Internal error: Unsupported template language "..language)
        local createdAt = item.created_at
        local lastUpdatedAt = item.last_updated_at

        return {
            id = item.id,
            source = {
                type = "custom",
                key = item.key,
                name = name,
                language = language,
                content = content :: runtime.LazyContent,
                created_at = createdAt,
                last_updated_at = lastUpdatedAt,
            },
            allowed_caps = allowedCaps,
            paused = paused,
        }
    end

    local function _parseTemplate(item: kv.KvRecord): templatemanagerImpl.Template
        assert(item.exists, "Internal error: Template item does not exist")
        if item.value.type == "custom" then
            return _parseCustomTemplate(item)
        else
            error("Internal error: Unsupported template source type "..tostring(item.value.type))
        end
    end

    local function builtins(): templatemanagerImpl.Template
        return BUILTINS
    end

    local function list(): {templatemanagerImpl.Template}
        local data = ctx.KV:find("%%", {"templates"})

        local templates = {BUILTINS}
        for _, item in data do
            local template = _parseTemplate(item)
            table.insert(templates, template)
        end

        return templates
    end

    local function getcustom(key: string): templatemanagerImpl.Template?
        local data = ctx.KV:getrecord(key, {"templates"})
        if not data or not data.exists then
            return nil -- Not found
        end
        return _parseTemplate(data)
    end

    local function setcustom(key: string?, data: templatemanagerImpl.CreateTemplate): string
        local storeData: ITemplateStore = {
            type = "custom",
            name = data.name,
            content = data.content,
            allowed_caps = data.allowed_caps,
            paused = data.paused,
            language = data.language,
        }
        local tkey = if key then key else typesext.randstring(16)
        ctx.KV:set(tkey, storeData, {"templates"})
        return tkey
    end

    local function deletecustom(key: string): ()
        ctx.KV:delete(key, {"templates"})
    end

    local function computevfs(template: templatemanagerImpl.Template): typesext.Vfs
        if template.vfs then
            return template.vfs
        end

        if template.source.type == "builtins" then 
            local vfs = typesext.Vfs.newoverlay({
                VfsBuiltinsPatches,
                VfsBuiltins,
                VfsTemplatingTypes,
            })
            template.vfs = vfs
            return vfs
        elseif template.source.type == "custom" then
            local vfs = typesext.Vfs.newoverlay({
                template.source.content, -- newoverlay automatically converts LazyContent to a memoryvfs
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
    self.getcustom = getcustom
    self.setcustom = setcustom
    self.deletecustom = deletecustom
    self.computevfs = computevfs

    return self
end

return TemplateManager