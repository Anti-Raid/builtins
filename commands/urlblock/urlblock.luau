local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require "../data"
local interactionutils = require "@antiraid-ext/utils/interaction"
local URLBlockManager = require "../../auxutils/urlblockmanager"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorDo = require "@antiraid-ext/utils/modhierarchy".canModeratorDo
local apitypes = require "@discord-types/apiTypes"
local paginate = require "@antiraid-ext/framework/paginate"

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
            :setName("list")
            :setDescription("List all blocked URLs")  
            :build()      
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local userid = extractUserIdFromInteraction(data.interaction)

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
                -- Otherwise, we assume it's a domain and add both http and https
                table.insert(urlstoblock, "http://" .. urlp)
                table.insert(urlstoblock, "https://" .. urlp)
            end
        end

        local blockedUrls = {}
        local urls = URLBlockManager(data.ctx).listurls()

        for _, urlToBlock in urlstoblock do
            if not urls.exists(urlToBlock) then
                table.insert(blockedUrls, urlToBlock)
                URLBlockManager(data.ctx).set({
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

        local urls = URLBlockManager(data.ctx).listurls()

        if urls.exists(url) then
            URLBlockManager(data.ctx).delete(url)
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
    elseif cmdname == "list" then
        canModeratorDo(
            data.userinfomanager.get(userid, data.interaction),
            "urlblock.list"
        )

        -- Send as paginated set of embeds
        local urls = URLBlockManager(data.ctx).list()

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
                        value = os.date("%Y-%m-%d %H:%M:%S", block.created_at.timestamp_seconds),
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
    else 
        error("Unknown subcommand: " .. cmdname)
    end
end

return {
    register = register,
    run = run,
}