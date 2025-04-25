local data = require"./data"

local commands = {
    whois = require"./whois/whois",
    remindme = require"./remindme/remindme",
    warn = require"./warn/warn",
    stings = require"./stings/stings",
    log = require"./log/log",
    urlextract = require"./urlextract/urlextract",
    subcmdtest = require"./subcmdtest/subcmdtest",
} :: { [string]: data.Command }

return {
    commands = commands
}