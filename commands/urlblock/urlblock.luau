local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorDo = require "@antiraid-ext/utils/modhierarchy".canModeratorDo
local apitypes = require "@discord-types/apiTypes"
local paginate = require "@antiraid-ext/framework/paginate"
local registerEvent = require "@antiraid-ext/utils/eventmgmt".registerEvent
local getUrlBlockManager = require"../../auxutils/urlblockhandler".getUrlBlockManager


local function register() 
    return commandBuilder.new({
        name = "urlblock",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Block URLs from a message")
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("add")
            :setDescription("Block a URL from being sent in the server")  
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("url")
                    :setDescription("The URL to block")
                    :setRequired(true)
                    :build()      
                end
            )
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("delete")
            :setDescription("Unblock a URL from being sent in the server")  
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("url")
                    :setDescription("The URL to unblock")
                    :setRequired(true)
                    :build()      
                end
            )
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("enable")
            :setDescription("Enable URL blocking in the server")  
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("disable")
            :setDescription("Disable URL blocking in the server")  
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("list")
            :setDescription("List all blocked URLs")  
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("listcached")
            :setDescription("List all cached URLs")  
            :build()      
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local userid = extractUserIdFromInteraction(data.interaction)
    local urlblockmanager = getUrlBlockManager(data.ctx)

    local cmdname = data.command.nameList[2]

    if cmdname == "add" then
        canModeratorDo(
            data.userinfomanager.get(userid, data.interaction),
            "urlblock.add"
        )
        
        local url: string? = nil

        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "url" then 
                if opt.value.kind == "String" then
                    url = opt.value.value
                end
            end
        end
        
        if not url then 
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "No URL specified",
                        description = "Please specify a URL to block",
                        color = 0xff0000, -- Red color
                    },
                },
                true
            )
        end

        local urlsSplit = url:split(", ")
        for _, urlb in urlsSplit do 
            -- Ensure no spaces
            if urlb:find(" ") then
                return interactionutils.replySimple(
                    data.ctx,
                    data.interaction,
                    nil,
                    {
                        {
                            title = "Invalid URL",
                            description = "The URL cannot contain spaces. Please provide a valid URL: ``" .. urlb .. "``",
                            color = 0xff0000, -- Red color
                        },
                    },
                    true
                )
            end
        end

        local urlstoblock = {}
        for _, urlp in urlsSplit do 
            if urlp:find("://") then
                -- If the URL contains a protocol, we can use it directly
                table.insert(urlstoblock, urlp)
            else
                table.insert(urlstoblock, "https://" .. urlp)
            end
        end

        local blockedUrls = {}
        local urls = urlblockmanager.listurls()

        for _, urlToBlock in urlstoblock do
            if not urls.exists(urlToBlock) then
                table.insert(blockedUrls, urlToBlock)
                urlblockmanager.set({
                    user_id = userid,
                    url = urlToBlock,
                    reason = "Blocked at moderator request"
                })
            end
        end

        if #blockedUrls == 0 then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "No URLs blocked",
                        description = "The specified URLs are already blocked.",
                        color = 0xff0000, -- Red color
                    },
                },
                true
            )
        else 
            local blockedWithMd = {}
            for _, blockedUrl in blockedUrls do
                table.insert(blockedWithMd, "- `" .. blockedUrl .. "`")
            end

            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "URLs Blocked",
                        description = "The following URLs have been blocked:\n" .. table.concat(blockedWithMd, "\n"),
                        color = 0x00ff00, -- Green color
                    },
                },
                true
            )
        end
    elseif cmdname == "delete" then
        canModeratorDo(
            data.userinfomanager.get(userid, data.interaction),
            "urlblock.delete"
        )

        local url: string? = nil
        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "url" then
                if opt.value.kind == "String" then
                    url = opt.value.value
                end
            end
        end

        if not url then 
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "No URL specified",
                        description = "Please specify a URL to unblock",
                        color = 0xff0000, -- Red color
                    },
                },
                true
            )
        end

        local urls = urlblockmanager.listurls()

        if urls.exists(url) then
            urlblockmanager.delete(url)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "URL Unblocked",
                        description = "The URL `" .. url .. "` has been unblocked.",
                        color = 0x00ff00, -- Green color
                    },
                },
                true
            )
        else 
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "URL Not BLocked",
                        description = "The specified URL is not blocked right now and hence cannot be unblocked.",
                        color = 0xff0000, -- Red color
                    },
                },
                true
            )
        end
    elseif cmdname == "enable" then
        canModeratorDo(
            data.userinfomanager.get(userid, data.interaction),
            "urlblock.enable"
        )

        registerEvent(data.ctx, "MESSAGE")
        
        urlblockmanager.setenabled(true)
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "URL Blocking Enabled",
                    description = "URL blocking has been enabled in this server.",
                    color = 0x00ff00, -- Green color
                },
            },
            true
        )
    elseif cmdname == "disable" then
        canModeratorDo(
            data.userinfomanager.get(userid, data.interaction),
            "urlblock.disable"
        )  

        urlblockmanager.setenabled(false)
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "URL Blocking Disabled",
                    description = "URL blocking has been disabled in this server.",
                    color = 0x00ff00, -- Green color
                },
            },
            true
        )
    elseif cmdname == "list" then
        canModeratorDo(
            data.userinfomanager.get(userid, data.interaction),
            "urlblock.list"
        )

        -- Send as paginated set of embeds
        local urls = urlblockmanager.list()

        if #urls == 0 then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "No URLs Blocked",
                        description = "There are no URLs currently blocked in this server.",
                        color = 0x00ff00, -- Green color
                    },
                },
                true
            )
        end

        local function getUrlEmbed(idx: number): apitypes.EmbedObject
            if idx < 1 or idx > #urls then
                error("Index out of bounds: " .. idx .. " for URLs list of size " .. #urls)
            end
            local block = urls[idx]
            return {
                title = "Blocked URL #" .. idx,
                description = "URL: `" .. block.url .. "`\nReason: `" .. block.reason .. "`\nBlocked by: <@" .. block.user_id .. ">",
                color = 0xFF0000, -- Red color
                fields = {
                    {
                        name = "Created At",
                        value = tostring(os.date("%Y-%m-%d %H:%M:%S", block.created_at.timestamp_seconds)),
                        inline = true,
                    },
                },
            }
        end

        paginate.paginate(data, {
            id = "urlblock",
            embed = getUrlEmbed,
            numPages = #urls
        })
        return nil   
    elseif cmdname == "listcached" then
        canModeratorDo(
            data.userinfomanager.get(userid, data.interaction),
            "urlblock.list"
        )

        local urls = urlblockmanager.listurlscached()

        if #urls == 0 then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "No URLs Blocked",
                        description = "There are no URLs currently blocked in this server.",
                        color = 0x00ff00, -- Green color
                    },
                },
                true
            )
        end

        local urlsList = {}

        for url in urls do
            table.insert(urlsList, url)
        end

        local function getUrlEmbed(idx: number): apitypes.EmbedObject
            if idx < 1 or idx > #urls then
                error("Index out of bounds: " .. idx .. " for URLs list of size " .. #urls)
            end
            local url = urlsList[idx]
            return {
                title = "Blocked URL #" .. idx,
                description = "URL: `" .. url .. "`",
                color = 0xFF0000, -- Red color
            }
        end

        paginate.paginate(data, {
            id = "urlblockcached",
            embed = getUrlEmbed,
            numPages = #urls
        })
        return nil
    else 
        error("Unknown subcommand: " .. cmdname)
    end
end

return {
    register = register,
    run = run,
}