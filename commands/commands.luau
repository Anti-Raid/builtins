local commands:  { [string]: any } = {
    afk = require"./afk/afk",
    whois = require"./whois/whois",
    remindme = require"./remindme/remindme",
    settings = require"./settings/settings",
    lockdowns = require"./lockdowns/lockdowns",
    stings = require"./stings/stings",
    stats = require"./stats/stats",
    help = require"./help/help",
    moderation = require"./moderation/moderation",
    backups = require"./backups/backups",
    vmeval = require"./vmeval/vmeval",
    serverinfo = require"./serverinfo/serverinfo",
}

return {
    commands = commands,
    b = 3
}
