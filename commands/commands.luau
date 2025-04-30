local data = require"./data"

local commands = {
    whois = require"./whois/whois",
    remindme = require"./remindme/remindme",
    log = require"./log/log",
    urlextract = require"./urlextract/urlextract",
    subcmdtest = require"./subcmdtest/subcmdtest",
    lockdowns = require"./lockdowns/lockdowns",
    stings = require"./stings/stings",
} :: { [string]: data.Command }

return {
    commands = commands,
    b = 3
}