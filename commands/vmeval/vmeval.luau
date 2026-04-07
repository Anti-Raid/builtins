local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/frameworkv2/context"
local luau = require "@antiraid/luau"
local json = require "@antiraid/json"
local interop = require "@antiraid/interop"
local units = require"@antiraid-ext/frameworkv2/unit"

local command = commandBuilder.new({
    name = "vmeval",
})
:addIntegrationType("GuildInstall")
:setType("ChatInput")
:addContext("Guild")
:setDescription("Run code on the VM")
:option(
    function(opt) 
        return opt
        :setType("String")
        :setName("code")
        :setDescription("The code to run on the VM")  
        :setRequired(true)
        :build()
    end
)
:build()

local function run(data: data.CommandContext): nil
    data.interaction.assertpermission("vmeval.exec")

    local chunkContent = data.args.string("code")

    if not chunkContent then 
        return data.interaction.replysimpleembed("No Code", "Please specify some code to run on the VM", units.RED_COLOR)
    end

    local chunk = luau.load(chunkContent)
    chunk.optimization_level = 2
    chunk.chunk_name = "/entrypoint"
    chunk.environment = {
        globals = _G,
        require = require,
        json = json,
        jsonify = json.tojsonstring,
        ctx = data.ctx,
        data = data,
        interaction = data.interaction,
        type = type,
        typeof = typeof,
        interop = interop,
        memusage = interop.memusage,
        framework = data.framework,
        userinfomanager = data.framework.userinfomanager
    }

    local ok, result = pcall(chunk.call_async, chunk, {})    

    local resp = tostring(result)
    if #resp > 4000 then
        -- Limit to 3997 chars and add a ... at the end
        resp = resp:sub(1, 3997) .. "..."   
    end

    data.interaction.reply({
        embeds = {
            {
                title = "Result",
                description = "```\n" .. resp .. "\n```",
                fields = {
                    {
                        name = "OK",
                        value = tostring(ok),
                        inline = false,
                    },
                },
                footer = {
                    text = "Note that all code executed runs in AntiRaids sandboxed custom scripting VM. Have fun :)"
                },
                color = if ok then units.GREEN_COLOR else units.RED_COLOR,
            },
        }
    })
    return nil
end

return {
    command = command,
    run = run,
}