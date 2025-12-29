local Primitives = require"@antiraid-core/primitives"
local typesext = require"@antiraid/typesext"
local channel = require"@antiraid/channel"
local templateloopImpl = require"@antiraid-core/templateloop"

export type Isolate = {
    --- The ID of the isolate.
    read id: string,

    --- The global table of the isolate.
    read global_table: {[any]: any},

    --- The require function of the isolate.
    read requirefunc: (moduleName: string) -> any,

    --- The entrypoint of the isolate
    read entrypoint: () -> any?,

    --- Spawns a task to dispatch an event to this isolate. If `event` is passed, the sub-context
    --- created for the template will have the event set to it.
    read dispatchEvent: (rootctx: Primitives.TemplateContext, event: Primitives.Event?) -> channel.OneshotChannel<templateloopImpl.DispatchResult>,

    --- Fires an event 'in-thread' and returns the result directly.
    read runEvent: (rootctx: Primitives.TemplateContext, event: Primitives.Event?) -> any,

    --- Same as runEvent, but returns a IsolateResult
    read runEventResult: (rootctx: Primitives.TemplateContext, event: Primitives.Event?) -> templateloopImpl.DispatchResult,
}

--- Creates a new isolate with its own global table and require function
---
--- The `expose` parameter can be used to expose additional values to the isolate's global table
local function new(id: string, caps: {string}, vfs: typesext.Vfs, expose: {[any]: any}): Isolate
    local isolate = {}
    
    local globaltable: {[any]: any} = typesext.createglobalproxy()

    -- The require function will automatically cache modules per-isolate and ensure functions are loaded with the proxyglobal global table
    -- as the chunk's environment
    local requirefunc = vfs:createrequirefunction(id, globaltable) 
    globaltable.require = requirefunc -- Expose our custom require function

    -- Expose any additional values to the isolate's global table
    for k, v in expose do
        globaltable[k] = v
    end

    local entrypoint = nil

    isolate.id = id
    isolate.global_table = globaltable
    isolate.requirefunc = requirefunc
    isolate.entrypoint = function() 
        return entrypoint
    end
    isolate.dispatchEvent = function(rootctx: Primitives.TemplateContext, event: Primitives.Event?): channel.OneshotChannel<templateloopImpl.DispatchResult>
        local chan = channel.OneshotChannel() :: channel.OneshotChannel<templateloopImpl.DispatchResult>

        task.spawn(function() 
            local ok, res = xpcall(isolate.runEvent, debug.traceback :: any, rootctx, event)

            if ok then
                chan:send({type = "ok", id = id, value = res})
            else
                chan:send({type = "err", id = id, error = res})
            end
        end)

        return chan
    end
    isolate.runEvent = function(rootctx: Primitives.TemplateContext, event: Primitives.Event?): any 
        --- Create sub-context for template
        local subctx = rootctx:with({
            event = event,
            capabilities = caps,
        })
        local useEvent = if event then event else rootctx:event()

        if entrypoint then
            entrypoint = requirefunc("./init.luau")
        end

        if type(entrypoint) ~= "table" then
            error(`init.luau entrypoint for template \`{id}\` did not return a table, got \`{type(entrypoint)}\``)
        end
        local func: unknown = entrypoint[useEvent.name]
        if func and type(func) == "function" then 
            return (func :: (Primitives.TemplateContext) -> any)(subctx)
        else 
            return nil
        end
    end

    isolate.runEventResult = function(rootctx: Primitives.TemplateContext, event: Primitives.Event?): templateloopImpl.DispatchResult
        local ok, res = xpcall(isolate.runEvent, debug.traceback :: any, rootctx, event)

        if ok then
            return {type = "ok", id = id, value = res}
        else
            return {type = "err", id = id, value = res}
        end
    end

    table.freeze(isolate)

    return isolate
end

return {
    new = new,
}