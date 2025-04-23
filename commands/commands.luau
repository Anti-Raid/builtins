local data = require"./data"

local commands = {
    whois = require"./whois/whois",
    remindme = require"./remindme/remindme",
    warn = require"./warn/warn",
    stings = require"./stings/stings",
} :: { [string]: data.Command }

return {
    commands = commands
}