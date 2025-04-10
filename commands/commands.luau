local data = require"./data"

local commands = {
    whois = require"./whois/whois",
    remindme = require"./remindme/remindme",
} :: { [string]: data.Command }

return {
    commands = commands
}