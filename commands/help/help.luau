local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/frameworkv2/context"

local command = commandBuilder.new({
    name = "help",
})
:addIntegrationType("GuildInstall")
:setType("ChatInput")
:addContext("Guild")
:setDescription("Get help using AntiRaid?")
:build()

local function run(data: data.CommandContext): nil
    data.interaction.reply({
        embeds = {
            {
                title = "AntiRaid Help" ,
                description = `Visit [Command List]({data.framework.loop.btd.website}/commands) to see a full list of all of AntiRaids commands!`,
                color = 0x00FF00,
                url = `{data.framework.loop.btd.website}/commands`
            }
        }
    })
    return nil
end

return {
    command = command,
    run = run,
}