local Primitives = require"@antiraid-core/primitives"
local typesext = require"@antiraid/typesext"
local channel = require"@antiraid/channel"

type IsolateResult = {
    type: "ok",
    id: string,
    value: any,
} | {
    type: "err",
    id: string,
    error: any,
}

export type Isolate = {
    read id: string,
    read global_table: {[any]: any},
    read requirefunc: (moduleName: string) -> any,

    --- Spawns a task to dispatch an event to this isolate
    ---
    --- Create
    read dispatchEvent: (rootctx: Primitives.TemplateContext) -> channel.OneshotChannel<IsolateResult>,
}

--- Creates a new isolate with its own global table and require function
local function new(template: Primitives.TemplateContext, vfs: typesext.Vfs): Isolate
    local id = typesext.randstring(16)
    local globaltable: {[any]: any} = typesext.createglobalproxy()
    local requirefunc = vfs:createrequirefunction(id, globaltable) -- The require function will automatically cache modules per-isolate
    globaltable.require = requirefunc

    local isolate = table.freeze({
        id = id .. "/" .. template.template_name,
        global_table = globaltable,
        requirefunc = requirefunc,
        dispatchEvent = function(rootctx: Primitives.TemplateContext): any 
            --- Create sub-context for template
            local subctx = rootctx:with({
                ext_data = {
                    template_name = template.template_name,
                    events = template.events,
                },
                capabilities = template.allowed_caps,
            })

            local chan = channel.OneshotChannel()

            task.spawn(function() 
                local ok, err = pcall(function() 
                    local initLuauFunc = requirefunc("init.luau")
                    if type(initLuauFunc) ~= "table" then
                        error("init.luau did not return a table with a `init` function")
                    end
                    if type(initLuauFunc.init) ~= "function" then
                        error("init.luau did not return a table with a `init` function")
                    end
                    return (initLuauFunc.init :: any)(subctx)
                end)

                if ok then
                    chan:send({type = "ok", id = id, value = err})
                else
                    chan:send({type = "err", id = id, error = err})
                end
            end)

            return chan
        end,
    })
    return isolate
end

return {
    new = new,
}