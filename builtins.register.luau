--- Builtins internal registration mechanism to AntiRaid
---
--- Note that this is INTERNAL and specific to how AntiRaid gets builtin state (such as command info etc) from the builtins standard script
---
--- Do not expect this to work outside of builtins in specific
local commands = require "./commands/commands"
local commandList = {}
for _, command in commands.commands do
    local commandD = command()

    if commandD.devOnly then continue end -- Do not register dev only commands globally

    local cmd = commandD.register()
    table.insert(commandList, cmd)
end

return {
    commands = commandList
}