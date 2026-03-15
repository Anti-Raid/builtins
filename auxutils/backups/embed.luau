local Primitives = require "@antiraid-core/primitives"
local apitypes = require "@discord-types/apiTypes"
local ActionRowBuilder = require"@discord-types/builders/message/components/actionRow"
local ButtonBuilder = require"@discord-types/builders/message/components/button"
local EmojiBuilder = require"@discord-types/builders/emoji"
local datetime = require"@antiraid/datetime"
local units = require"@antiraid-ext/frameworkv2/unit"

export type EmbedData = {
    createdat: number?,
    finalFilePath: string?,
    id: string,
}

local function toembed(
    ctx: Primitives.TemplateContext,
    job: EmbedData,
    showDownloadLink: boolean?
): (apitypes.EmbedObject, {apitypes.ComponentObjects})
    local components: {apitypes.ComponentObjects} = {}

    local description = ""
    if job.createdat then
        description ..= string.format(
            "Created at: <t:%d:R>",
            job.createdat
        )
    end

    if showDownloadLink and job.finalFilePath then 
        -- Create presigned URL
        local furl = ctx.ObjectStorage:get_file_url(job.finalFilePath, datetime.timedelta_minutes(5))
        description ..= string.format("\n\n[Download backup](%s)", furl)

        table.insert(
            components,
            ActionRowBuilder.new()
            :addComponent(
                ButtonBuilder.new()
                :setStyle("Blurple")
                :setLabel("Download")
                :setEmoji(
                    EmojiBuilder.new()
                    :setName("🔥")
                    :build()
                )
                :setUrl(furl)
                :build()
            )
            :build() :: apitypes.ComponentObjects
        )
    end

    local embed: apitypes.EmbedObject = {
        title = "Status",
        description = description,
        color = units.GREEN_COLOR,
        footer = {
            text = "Job ID: " .. (job.id or "Unset")
        },
    }

    return embed, components
end

return {
    toembed = toembed
}