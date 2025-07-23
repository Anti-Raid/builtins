--- Builtins internal registration mechanism to AntiRaid
---
--- Note that this is INTERNAL and specific to how AntiRaid gets builtin state (such as command info etc) from the builtins standard script
---
--- Do not expect this to work outside of builtins in specific
local commands = require "./commands/commands"
local commandList = {}
for _, command in commands.commands do
    assert(command.register, "Command does not have a register function: " .. command.command.name)
    local cmd = command.register()
    table.insert(commandList, cmd)
end

return {
    commands = commandList
}
