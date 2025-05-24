local data = require"./data"

local commands = {
    whois = require"./whois/whois",
    remindme = require"./remindme/remindme",
    settings = require"./settings/settings",
    urlextract = require"./urlextract/urlextract",
    subcmdtest = require"./subcmdtest/subcmdtest",
    lockdowns = require"./lockdowns/lockdowns",
    stings = require"./stings/stings",
    stats = require"./stats/stats",
    help = require"./help/help",
} :: { [string]: data.Command }

return {
    commands = commands,
    b = 3
}