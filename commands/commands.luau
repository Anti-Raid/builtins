local data = require"./data"

local commands = {
    whois = require"./whois/whois",
} :: { [string]: data.Command }

return {
    commands = commands
}