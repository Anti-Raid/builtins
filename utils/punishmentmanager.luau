--!strict
local datetime = require "@antiraid/datetime"
local discord = require "@discord-types/apiTypes"
local executor = require"@antiraid-ext/executor"
local Primitives = require "@antiraid-core/primitives"
local promise = require "@antiraid/promise"
local kv = require "@antiraid/kv"
local scheduledexec = require "@antiraid/scheduledexec"
local typesext = require "@antiraid/typesext"
local stores = require "@antiraid/stores"
local builtinSettingsManager = require "./builtinsettingsmanager"
local stingmanager = require "./stingmanager"
local discordPlugin = require "@antiraid/discord"
local canModeratorAffectTarget = require "./modhierarchy".canModeratorAffectTarget

export type ResolutionReason = "reversed"

export type Punishment = {
    punishmentId: string,
    userId: discord.Snowflake,
    modId: discord.Snowflake?,
    punishment: string,
    reason: string,
    delete_message_seconds: number?,
    created_at: datetime.DateTime,
    expires_at: datetime.DateTime?,
    numStings: number?,
    resolved: ResolutionReason?,
}

export type CreatePunishment = {
    userId: discord.Snowflake,
    modId: discord.Snowflake?,
    punishment: string,
    reason: string,
    expires_at: datetime.DateTime?,
    delete_message_seconds: number?,
    numStings: number?,
}

--[[
    Manages the moderation 'punishments' (think bee punishments!) of a user.
]]
export type PunishmentManager = {
    --- Gets all the punishments a user has accrued
    getPunishmentsOnUser: (userId: discord.Snowflake) -> {Punishment},
    --- Gets a single punishment by its ID
    getPunishment: (userId: discord.Snowflake, punishmentId: string) -> Punishment?,
    --- Creates a new punishment for a user returning a Punishment
    createUserPunishment: (punishment: CreatePunishment) -> Punishment,
    --- Returns the expiration of a punishment from the expiration task itself. If no expiration is set, returns nil
    getPunishmentExpiration: (userId: discord.Snowflake, punishmentId: string) -> (string?, datetime.DateTime?),
    --- Sets the expiration of a punishment. Repeated calls override previous expiration
    setPunishmentExpiration: (userId: discord.Snowflake, punishmentId: string, reason: string, expiresAt: datetime.DateTime) -> (),
    --- Deletes the expiration of a punishment
    deletePunishmentExpiration: (userId: discord.Snowflake, punishmentId: string, resolve: ResolutionReason?) -> (),
    --- Deletes a punishment. This will also reverse the punishment if possible and delete the expiration if it exists
    deletePunishment: (userId: discord.Snowflake, punishmentId: string, mod: string?, auditReason: string) -> (),
    --- Reverse a whole class of punishments, this will create a dummy punishment for reversal disabling expiration for all punishments within the bot
    reversePunishmentClass: (userId: discord.Snowflake, mod: string?, punishment: string, auditReason: string) -> (),
    --- Given a scheduled execution ID corresponding to a punishment expiry, return the user id and punishment id
    getPunishmentFromScheduledExecId: (scheduledExecId: string) -> (discord.Snowflake?, string?),
    --- Returns the cached list of punishments for a user. If the cache is expired, it will fetch the punishments from the kv store
    getCachedUserPunishments: (userId: string) -> {Punishment},
    --- Manually update the cached list of punishments for a user
    ---
    --- This is useful for when you know the punishments have changed and you want to update the cache
    updateCachedUserPunishments: (userId: string, punishments: {Punishment}) -> nil,
    --- Clears the cached list of punishments for a user
    clearCachedUserPunishments: (userId: string) -> nil,
    --- Compactly stringifies a punishment
    punishmentCompactString: (punishment: Punishment) -> string,
    --- Gets the list of punishment actions. This can then be modified directly to add/remove punishment actions
    getPunishmentActions: () -> {[string]: PunishmentAction},
}

--- A punishment action stores how to apply and reverse a punishment
export type PunishmentAction = {
    name: string,
    description: string,
    check: (ctx: Primitives.TemplateContext, ge: executor.GlobalExecutor, p: Punishment) -> (),
    --- By default, a punishment only supports expiry if it implements ``reverse()`` however some support expiry even if they don't implement it (timeouts)
    ---
    --- For these, the punishment manager will still not create the scheduled task (as in no-reverse case) but will not error if expires_at is set
    supportsExpiryAnyways: boolean?, 
    apply: (ctx: Primitives.TemplateContext, discord: discordPlugin.DiscordExecutor, p: Punishment) -> (),
    reverse: ((ctx: Primitives.TemplateContext, discord: discordPlugin.DiscordExecutor, p: Punishment) -> ())?,
}

local punishmentActions: {[string]: PunishmentAction} = {
    ban = {
        name = "Ban",
        description = "Bans the user from the server",
        check = function(ctx: Primitives.TemplateContext, ge: executor.GlobalExecutor, p: Punishment) 
            if p.modId then
                canModeratorAffectTarget(ge, p.modId, p.userId, "moderation.ban")
            end
            return
        end,
        apply = function(ctx: Primitives.TemplateContext, discord: discordPlugin.DiscordExecutor, p: Punishment) 
            promise.yield(discord:create_guild_ban({
                delete_message_seconds = p.delete_message_seconds,
                reason = p.reason,
                user_id = p.userId,
            }))
        end,
        reverse = function(ctx: Primitives.TemplateContext, discord: discordPlugin.DiscordExecutor, p: Punishment) 
            promise.yield(discord:remove_guild_ban({
                user_id = p.userId,
                reason = "Reverting ban by " .. (if p.modId then "<@" .. p.modId .. ">" else "System") .. " with ID of ``" .. p.punishmentId .. "``",
            }))
        end
    },
    kick = {
        name = "Kick",
        description = "Kicks the user from the server",
        check = function(ctx: Primitives.TemplateContext, ge: executor.GlobalExecutor, p: Punishment) 
            if p.delete_message_seconds then 
                error("Kick punishments cannot have a delete_message_seconds value")
            end

            if p.modId then
                canModeratorAffectTarget(ge, p.modId, p.userId, "moderation.kick")
            end
        end,
        apply = function(ctx: Primitives.TemplateContext, discord: discordPlugin.DiscordExecutor, p: Punishment) 
            promise.yield(discord:remove_guild_member({
                reason = p.reason,
                user_id = p.userId,
            }))
        end,
    },
    timeout = {
        name = "Timeout",
        description = "Times out the user for a specified duration",
        supportsExpiryAnyways = true,
        check = function(ctx: Primitives.TemplateContext, ge: executor.GlobalExecutor, p: Punishment) 
            if not p.expires_at then 
                error("Timeout punishments must have a expires_at value")
            end

            if p.modId then
                canModeratorAffectTarget(ge, p.modId, p.userId, "moderation.timeout")
            end
        end,
        apply = function(ctx: Primitives.TemplateContext, discord: discordPlugin.DiscordExecutor, p: Punishment) 
            promise.yield(discord:modify_guild_member({
                reason = p.reason,
                user_id = p.userId,
                data = {
                    communication_disabled_until = tostring(p.expires_at),
                }
            }))
        end,
        reverse = function(ctx: Primitives.TemplateContext, discord: discordPlugin.DiscordExecutor, p: Punishment) 
            promise.yield(discord:modify_guild_member({
                user_id = p.userId,
                reason = "Reverting timeout by " .. (if p.modId then "<@" .. p.modId .. ">" else "System") .. " with ID of ``" .. p.punishmentId .. "``",
                data = {
                    communication_disabled_until = {}
                }
            }))
        end
    }
}


-- Cached user punishments should be captured by the PunishmentManager class to ensure require cache keeps the cache local reference the same across
-- all PunishmentManager instances
local _cachedUserPunishments: {[string]: {punishments: {Punishment}, createdAt: number }} = {}
local maxBurstCacheTime = 120 -- 2 minutes

local function PunishmentManager(ctx: Primitives.TemplateContext, ge: executor.GlobalExecutor, stingmanager: stingmanager.StingManager): PunishmentManager
    local self = setmetatable({}, {
        __index = PunishmentManager,
    })

    -- Create a new key-value executor with the builtins.punishments kv-scope
    local kv = kv.new(ctx, nil, "builtins.punishments")
    local builtinsettingsmanager = builtinSettingsManager(ctx)
    local discord = discordPlugin.new(ctx)
    local storeTab = stores.store :: any
    local scheduledExec = scheduledexec.new(ctx)

    local function _parsePunishmentData(punishmentId: string, userId: string, punishment: kv.KvRecord): Punishment?
        if not punishment.exists then return nil end
        local reason: string = punishment.value.reason
        local modId: discord.Snowflake? = punishment.value.modId
        local punishmentStr = punishment.value.punishment
        local created_at = punishment.created_at
        local expires_at = punishment.value.expires_at
        local delete_message_seconds = tonumber(punishment.value.delete_message_seconds)
        local numStings = tonumber(punishment.value.numStings)

        if typeof(created_at) ~= "DateTime" then
            punishment.created_at = datetime.UTC:now()
        end

        if expires_at and typeof(expires_at) ~= "DateTime" then
            expires_at = nil
        end
        
        if expires_at and expires_at < datetime.UTC:now() then
            return nil
        end

        if type(punishmentId) ~= "string" or type(reason) ~= "string" then
            return nil
        end

        if modId and type(modId) ~= "string" then
            modId = nil
        end

        return {
            punishmentId = punishmentId,
            userId = userId,
            reason = reason,
            modId = modId,
            punishment = punishmentStr,
            created_at = created_at,
            expires_at = expires_at,
            delete_message_seconds = delete_message_seconds,
            numStings = numStings,
        } :: Punishment
    end

    local function getPunishmentExpiration(userId: discord.Snowflake, punishmentId: string): (string?, datetime.DateTime?)
        local function extractPunishmentExpiration(exp: scheduledexec.ScheduledExecution): datetime.DateTime?
            local ok, expiresAt = pcall(datetime.UTC.fromString, datetime.UTC, exp.run_at)
            if not ok then
                return nil
            end
            return expiresAt :: datetime.DateTime
        end 
        
        local punishmentExpirationTask = promise.yield(scheduledExec:list(`builtins.punishments/{userId}/{punishmentId}`))
        if not punishmentExpirationTask or #punishmentExpirationTask == 0 then
            return nil, nil
        end
        local task = punishmentExpirationTask[1]
        local taskExpiresAt = extractPunishmentExpiration(task)
        if #punishmentExpirationTask > 1 then 
            -- Get the minimum expiration date (as AntiRaid is not guaranteed to run multiple, only first)
            for i = 2, #punishmentExpirationTask do
                local potTask = punishmentExpirationTask[i]
                local potTaskExpiresAt = extractPunishmentExpiration(potTask)
                if not potTaskExpiresAt then
                    continue
                end

                if not taskExpiresAt or potTaskExpiresAt < taskExpiresAt then
                    task = potTask
                    taskExpiresAt = potTaskExpiresAt
                end
            end
        end

        local reason = if task.data.reason and type(task.data.reason) == "string" then task.data.reason else nil

        return reason, taskExpiresAt
    end

    local function setPunishmentExpiration(userId: discord.Snowflake, punishmentId: string, reason: string, expiresAt: datetime.DateTime)
        -- Get the punishment itself and update its internal expires_at
        local record = promise.yield(kv:getrecord(`{userId}/{punishmentId}`))
        if not record.exists then
            return
        end
        local cpunishment = _parsePunishmentData(punishmentId, userId, record)
        if not cpunishment then
            return
        end

        if storeTab.onPunishmentSetExpiration then
            (storeTab.onPunishmentSetExpiration :: any)(cpunishment, reason, expiresAt)
        end

        cpunishment.expires_at = expiresAt
        promise.yield(kv:set(`{userId}/{punishmentId}`, cpunishment))

        -- Remove the old expiration task if any
        promise.yield(scheduledExec:remove(`builtins.punishments/{userId}/{punishmentId}`))
        -- Create a new expiration task
        promise.yield(scheduledExec:add({
            id = `builtins.punishments/{userId}/{punishmentId}`,
            data = {
                reason = reason,
            },
            run_at = tostring(expiresAt),
        }))

        -- Send a modlog message
        local modlogschannel = builtinsettingsmanager.getModLogsChannel("punishment_set_expiration")

        if modlogschannel then
            promise.yield(discord:create_message({
                channel_id = modlogschannel,
                data = {
                    embeds = {
                        {
                            title = "Punishment Expiration Set",
                            description = string.format("Punishment ID: %s\nUser ID: %s\nReason: %s", cpunishment.punishmentId, cpunishment.userId, cpunishment.reason),
                            fields = {
                                { name = "Moderator", value = if cpunishment.modId then "<@" .. cpunishment.modId .. ">" else "System", inline = true },
                                { name = "Created At", value = "<t:" .. cpunishment.created_at.timestamp_seconds .. ">", inline = true },
                                { name = "Expires On", value = "<t:" .. expiresAt.timestamp_seconds .. ">", inline = true },
                                { name = "Reason", value = reason, inline = true },
                                { name = "Punishment", value = tostring(cpunishment.punishment), inline = true },
                            },
                        }
                    } :: {discord.EmbedObject},
                }
            }))
        end
    end

    local function _deletePunishmentExpirationImpl(punishment: Punishment, resolve: ResolutionReason?) 
        local userId = punishment.userId
        if storeTab.onPunishmentDeleteExpiration then
            (storeTab.onPunishmentDeleteExpiration :: any)(punishment, resolve)
        end

        local oldExpiresAt = punishment.expires_at

        if not oldExpiresAt and not resolve then
            -- This is basically a no-op, we don't need to do anything
            return
        end

        if resolve then 
            punishment.resolved = resolve
        else
            punishment.expires_at = nil :: any
        end

        promise.yield(kv:set(`{userId}/{punishment.punishmentId}`, punishment))

        -- Remove the expiration task
        if oldExpiresAt then
            promise.yield(scheduledExec:remove(`builtins.punishments/{userId}/{punishment.punishmentId}`))
        end

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("punishment_delete_expiration")

        local resolveReason = "Unresolved"

        if resolve == "reversed" then
            resolveReason = "Reversed this punishment entirely"
        end

        if modlogschannel then
            promise.yield(discord:create_message({
                channel_id = modlogschannel,
                data = {
                    embeds = {
                        {
                            title = "Punishment Expiration Removed",
                            description = string.format("Punishment ID: %s\nUser ID: %s\nReason: ``%s``", punishment.punishmentId, punishment.userId, punishment.reason),
                            fields = {
                                { name = "Moderator", value = if punishment.modId then "<@" .. punishment.modId .. ">" else "System", inline = true },
                                { name = "Created At", value = "<t:" .. punishment.created_at.timestamp_seconds .. ">", inline = true },
                                { name = "Old Expiry", value = if oldExpiresAt then "<t:" .. oldExpiresAt.timestamp_seconds .. ">" else "None", inline = true },
                                { name = "Reason", value = punishment.reason, inline = true },
                                { name = "Punishment Count", value = tostring(punishment.punishment), inline = true },
                                { name = "Punishment Resolved", value = resolveReason }
                            },
                        }
                    } :: {discord.EmbedObject},
                }
            }))
        end
    end

    local function deletePunishmentExpiration(userId: discord.Snowflake, punishmentId: string, resolve: ResolutionReason?)
        -- Get the punishment itself and update its internal expires_at
        local record = promise.yield(kv:getrecord(`{userId}/{punishmentId}`))
        if not record.exists then
            return
        end

        local cpunishment = _parsePunishmentData(punishmentId, userId, record)

        if not cpunishment then
            return
        end

        _deletePunishmentExpirationImpl(cpunishment, resolve)
    end

    local function getPunishmentFromScheduledExecId(scheduledExecId: string): (discord.Snowflake?, string?)
        -- Ensure it starts with builtins.punishments/
        local f, _ = scheduledExecId:find("builtins.punishments/")
        if f ~= 1 then
            return nil, nil
        end
        
        -- Extract the userId and punishmentId
        local userId, punishmentId = scheduledExecId:match("builtins.punishments/(%d+)/(%w+)")
        if not userId or not punishmentId then
            return nil, nil
        end

        return userId, punishmentId
    end

    local function _reversePunishment(punishment: Punishment, mod: string?, auditReason: string)
        if punishment.resolved then return end 
        
        -- Reverse the punishment
        local action = punishmentActions[punishment.punishment]
        if action and action.reverse then
            action.reverse(ctx, discord, punishment)
        end

        -- Reverse all expirations/resolve all older punishments
        local punishments = self.getPunishmentsOnUser(punishment.userId)
        for _, p in punishments do
            if p.punishment == punishment.punishment then
                -- Delete the punishment expiration with resolution of  "reversed"
                _deletePunishmentExpirationImpl(p, "reversed")
            end
        end
    end

    local function deletePunishment(userId: discord.Snowflake, punishmentId: string, mod: string?, auditReason: string)
        if not userId or not punishmentId or not auditReason then
            error("User ID, Punishment ID or Audit Reason is nil")
        end

        -- Fetch the punishment
        local record = promise.yield(kv:getrecord(`{userId}/{punishmentId}`))
        local cpunishment = _parsePunishmentData(punishmentId, userId, record)
        if not cpunishment then
            return
        end

        if storeTab.onPunishmentDelete then
            (storeTab.onPunishmentDelete :: any)(cpunishment, mod, auditReason)
        end

        -- Reverse the punishment
        _reversePunishment(cpunishment, mod, auditReason)

        -- Then remove from DB
        promise.yield(kv:delete(`{userId}/{punishmentId}`))

        -- Clear cache
        self.clearCachedUserPunishments(userId)

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("punishment_delete")

        if modlogschannel then
            promise.yield(discord:create_message({
                channel_id = modlogschannel,
                data = {
                    embeds = {
                        {
                            title = "Punishment Deleted",
                            description = string.format("Punishment ID: %s\nUser ID: %s\nReason: %s", cpunishment.punishmentId, cpunishment.userId, cpunishment.reason),
                            fields = {
                                { name = "Original Moderator", value = if cpunishment.modId then "<@" .. cpunishment.modId .. ">" else "System", inline = true },
                                { name = "Deleted By", value = if mod then "<@" .. mod .. ">" else "System", inline = true },
                                { name = "Created At", value = "<t:" .. cpunishment.created_at.timestamp_seconds .. ">", inline = true },
                                { name = "Expires On", value = if cpunishment.expires_at then "<t:" .. cpunishment.expires_at.timestamp_seconds .. ">" else "Never", inline = true },
                                { name = "Reason For Punishment", value = cpunishment.reason, inline = true },
                                { name = "Reason For Deletion", value = if auditReason then auditReason else "No reason provided", inline = true },
                                { name = "Punishment Count", value = tostring(cpunishment.punishment), inline = true },
                                { name = "Deleted At", value = "<t:" .. datetime.UTC:now().timestamp_seconds .. ">", inline = true },
                            },
                        }
                    } :: {discord.EmbedObject},
                }
            }))
        end
    end

    local function reversePunishmentClass(userId: discord.Snowflake, mod: string?, punishment: string, auditReason: string) 
        local action = punishmentActions[punishment]

        if not action or not action.reverse then
            error(punishment .. "s cannot be reversed")
        end

        -- Create a dummy punishment
        local reversePunishment: Punishment = {
            userId = userId,
            modId = mod,
            punishment = punishment,
            reason = auditReason,
            expires_at = nil,
            delete_message_seconds = nil,
            numStings = nil,
            created_at = datetime.UTC:now(),
            punishmentId = "DUMMY",
        }

        -- Reverse the punishment
        _reversePunishment(reversePunishment, mod, auditReason)

        -- Clear cache
        self.clearCachedUserPunishments(userId)   
        
        -- Send a modlog message
        local modlogschannel = builtinsettingsmanager.getModLogsChannel("punishment_reversed")

        if modlogschannel then
            promise.yield(discord:create_message({
                channel_id = modlogschannel,
                data = {
                    embeds = {
                        {
                            title = "Punishment Reversed",
                            description = string.format("User ID: %s\nPunishment Class: %s\nReason: %s", userId, punishment, auditReason),
                            fields = {
                                { name = "Moderator", value = if mod then "<@" .. mod .. ">" else "System", inline = true },
                                { name = "Reversed At", value = "<t:" .. datetime.UTC:now().timestamp_seconds .. ">", inline = true },
                            },
                        }
                    } :: {discord.EmbedObject},
                }
            }))
        end
    end

    local function getPunishmentsOnUser(userId: discord.Snowflake): {Punishment}
        local punishments = promise.yield(kv:find(`{userId}/%`))
        if not punishments or #punishments == 0 then
            return {}
        end

        local punishmentList: {Punishment} = {}
        for _, punishment in punishments do
            local punishmentParsed = _parsePunishmentData(punishment.key:split("/")[2], userId, punishment)
            if not punishmentParsed then
                continue
            end
            punishmentList[#punishmentList + 1] = punishmentParsed
        end

        self.updateCachedUserPunishments(userId, punishmentList)
        return punishmentList
    end

    local function getPunishment(userId: discord.Snowflake, punishmentId: string): Punishment?
        local punishment = promise.yield(kv:getrecord(`{userId}/{punishmentId}`))

        local parsedPunishment = _parsePunishmentData(punishmentId, userId, punishment)
        
        return parsedPunishment
    end

    local function createUserPunishment(punishment: CreatePunishment): Punishment
        local punishmentId = typesext.randstring(16)

        -- Create the punishment
        promise.yield(kv:set(`{punishment.userId}/{punishmentId}`, {
            reason = punishment.reason,
            modId = punishment.modId,
            expires_at = punishment.expires_at,
            punishment = punishment.punishment or error("Internal error: no punishment specified"),
            delete_message_seconds = punishment.delete_message_seconds,
            numStings = punishment.numStings
        }))

        local createdAt = datetime.UTC:now()

        if punishment.expires_at then
            -- Create the expiration task
            promise.yield(scheduledExec:add({
                id = `builtins.punishments/{punishment.userId}/{punishmentId}`,
                data = {
                    reason = punishment.reason,
                },
                run_at = tostring(punishment.expires_at), -- TODO: Support datetime in scheduledexec API
            }))
        end

        self.clearCachedUserPunishments(punishment.userId)

        local cpunishment = {
            punishmentId = punishmentId,
            userId = punishment.userId,
            modId = punishment.modId,
            reason = punishment.reason,
            created_at = createdAt,
            expires_at = punishment.expires_at,
            punishment = punishment.punishment or error("Internal error: no punishment specified"),
            delete_message_seconds = punishment.delete_message_seconds,
            numStings = punishment.numStings
        } :: Punishment

        if storeTab.onPunishmentCreate then
            (storeTab.onPunishmentCreate :: any)(cpunishment)
        end

        -- Apply punishment check
        local action = punishmentActions[cpunishment.punishment]

        if action and action.check then 
            action.check(ctx, ge, cpunishment)
        end

        --[[
    userId: discord.Snowflake,
    modId: discord.Snowflake?,
    stings: number?,
    reason: string,
    expires_at: datetime.DateTime?,
        ]]

        if punishment.numStings then 
            stingmanager.createUserSting({
                userId = cpunishment.userId,
                modId = cpunishment.modId,
                stings = cpunishment.numStings,
                reason = cpunishment.reason,
                expires_at = cpunishment.expires_at
            })
        end

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("punishment_create")

        if modlogschannel then
            promise.yield(discord:create_message({
                channel_id = modlogschannel,
                data = {
                    embeds = {
                        {
                            title = "Punishment Created",
                            description = string.format("Punishment ID: %s\nUser ID: %s\nReason: %s", cpunishment.punishmentId, cpunishment.userId, cpunishment.reason),
                            fields = {
                                { name = "Moderator", value = if cpunishment.modId then "<@" .. cpunishment.modId .. ">" else "System", inline = true },
                                { name = "Created At", value = "<t:" .. cpunishment.created_at.timestamp_seconds .. ">", inline = true },
                                { name = "Expires On", value = if cpunishment.expires_at then "<t:" .. cpunishment.expires_at.timestamp_seconds .. ">" else "Never", inline = true },
                                { name = "Reason", value = cpunishment.reason, inline = true },
                                { name = "Punishment Count", value = tostring(cpunishment.punishment), inline = true },
                            },
                        }
                    } :: {discord.EmbedObject},
                }
            }))
        end

        -- Apply the punishment
        if action and action.apply then
            action.apply(ctx, discord, cpunishment)
        end

        return cpunishment
    end

    local function getCachedUserPunishments(userId: string): {Punishment}
        if _cachedUserPunishments[userId] then 
            if not maxBurstCacheTime or _cachedUserPunishments[userId].createdAt - os.clock() < maxBurstCacheTime then 
                return _cachedUserPunishments[userId].punishments
            end
        end
    
        local punishments = self.getPunishmentsOnUser(userId)
        _cachedUserPunishments[userId] = {
            punishments = punishments,
            createdAt = os.clock(),
        }
        return punishments
    end  
    
    local function clearCachedUserPunishments(userId: string): nil
        if _cachedUserPunishments[userId] then
            _cachedUserPunishments[userId] = nil
        end
        return nil
    end

    local function updateCachedUserPunishments(userId: string, punishments: {Punishment}): nil
        _cachedUserPunishments[userId] = {
            punishments = punishments,
            createdAt = os.clock(),
        }
        return nil
    end

    local function punishmentCompactString(punishment: Punishment): string
        local expiresAt = if punishment.expires_at then "<t:" .. punishment.expires_at.timestamp_seconds .. ">" else "Never"
        local mod = if punishment.modId then "<@" .. punishment.modId .. ">" else "System"
        local reason = if #punishment.reason > 0 then punishment.reason else "No reason provided"
        if #reason > 128 then
            reason = reason:sub(1, 128) .. "..."
        end
        -- "Punishment by " .. if maxPunishment.modId then "<@" .. maxPunishment.modId .. ">" else "System" .. " with ID of ``" .. maxPunishment.punishmentId .. "``",
        return string.format("Punishment by %s with ID of ``%s``\nReason: %s\nCreated at: <t:%d>\nExpires at: %s\nPunishment: %s", mod, punishment.punishmentId, reason, punishment.created_at.timestamp_seconds, expiresAt, punishment.punishment)
    end

    local function getPunishmentActions(): {[string]: PunishmentAction}
        return punishmentActions
    end

    -- Save to self
    self.getPunishmentsOnUser = getPunishmentsOnUser
    self.getPunishmentExpiration = getPunishmentExpiration
    self.setPunishmentExpiration = setPunishmentExpiration
    self.createUserPunishment = createUserPunishment
    self.deletePunishmentExpiration = deletePunishmentExpiration
    self.deletePunishment = deletePunishment
    self.reversePunishmentClass = reversePunishmentClass
    self.getPunishmentFromScheduledExecId = getPunishmentFromScheduledExecId
    self.getPunishment = getPunishment
    self.getCachedUserPunishments = getCachedUserPunishments
    self.clearCachedUserPunishments = clearCachedUserPunishments
    self.updateCachedUserPunishments = updateCachedUserPunishments
    self.punishmentCompactString = punishmentCompactString
    self.getPunishmentActions = getPunishmentActions

    return self
end

return PunishmentManager