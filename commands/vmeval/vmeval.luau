local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/framework/coretypes"
local luau = require "@antiraid/luau"
local toArray = require "@antiraid-ext/array".toArray
local apitypes = require "@discord-types/apiTypes"
local serde = require "@lune/serde"
local interop = require "@antiraid/interop"
local interactionutils = require "@antiraid-ext/utils/interaction"
local UserInfoManager = require"@antiraid-ext/utils/userinfo"
local modutils = require "@antiraid-ext/utils/modhierarchy"

local function register() 
    return commandBuilder.new({
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
            :setName("message")
            :setDescription("The code to run on the VM")  
            :setRequired(true)
            :build()
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    modutils.canModeratorDo(data.userinfomanager.get(modutils.extractUserIdFromInteraction(data.interaction), data.interaction), "vmeval.exec")

    local chunkContent: string? = nil

    -- Parse options
    for _, opt in data.command.options do 
        if opt.name == "message" then 
            if opt.value.kind == "String" then
                chunkContent = opt.value.value
            end
        end
    end
    
    if not chunkContent then 
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "No message specified",
                    description = "Please specify a message to extract URLs from",
                },
            },
            false
        )
    end

    local chunk = luau.load(chunkContent)
    chunk.optimization_level = 2
    chunk.chunk_name = "/entrypoint"
    chunk.environment = {
        globals = _G,
        require = require,
        serde = serde,
        jsonify = function(obj)
            return serde.encode("json", obj)
        end,
        ctx = data.ctx,
        data = data,
        interaction = data.interaction,
        storeTab = data.ctx.store,
        type = type,
        typeof = typeof,
        interop = interop,
        memusage = interop.memusage,
        userinfomanager = UserInfoManager(data.ctx)
    }

    local ok, result = pcall(chunk.call_async, chunk, {})    

    local resp = tostring(result)
    if #resp > 4000 then
        -- Limit to 3997 chars and add a ... at the end
        resp = resp:sub(1, 3997) .. "..."   
    end

    return interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Result",
                description = "```\n" .. resp .. "\n```",
                fields = toArray({
                    {
                        name = "OK",
                        value = tostring(ok),
                        inline = false,
                    },
                }),
                footer = {
                    text = "Note that all code executed runs in AntiRaids sandboxed custom scripting VM. Have fun :)"
                },
                color = if ok then 0x00FF00 else 0xFF0000,
            },
        } :: {apitypes.EmbedObject},
        false
    )
end

return {
    register = register,
    run = run,
}