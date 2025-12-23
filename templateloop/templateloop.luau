-- Experimental in-luau implementation of event dispatching to templates based on event scopes
local Primitives = require"@antiraid-core/primitives"
local datastores = require"@antiraid-core/plugins/datastores"
local isolate = require"./isolate"

local builtinsName = "$builtins"

type TemplateCache = {
    template: datastores.Template,
    isolate: isolate.Isolate?
}

--- Internal storage for all templates and their event mappings
local templates: {[string]: TemplateCache} = {}

local function canDispatchToTemplate(evt: Primitives.Event, template: datastores.Template): boolean
    if evt.scopes then 
        -- If scoped, check for event.name[{scope}]} for each scope
        for _, scope in evt.scopes do
            local scopedEventName = string.format("%s[%s]", evt.name, scope)
            if table.find(template.events, scopedEventName) then
                return true
            end
        end
        -- Also check unscoped event name
        if table.find(template.events, evt.name) then
            return true
        end
        return false
    else
        -- Unscoped event, just check name
        return table.find(template.events, evt.name) ~= nil
    end
end

local function getDispatchTemplatesForEvent(evt: Primitives.Event): {TemplateCache}
    local matchedTemplates: {TemplateCache} = {}
    for _, template in templates do
        if canDispatchToTemplate(evt, template.template) then
            table.insert(matchedTemplates, template)
        end
    end
    return matchedTemplates
end

--- Upserts a template on the template cache
local function upsertTemplate(template: datastores.Template): ()
    templates[template.name] = {
        template = template,
    }
end

return {
    canDispatchToTemplate = canDispatchToTemplate,
    getDispatchTemplatesForEvent = getDispatchTemplatesForEvent,
    upsertTemplate = upsertTemplate,
}