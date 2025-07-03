--!strict
local datetime = require "@antiraid/datetime"
local discord = require "@discord-types/apiTypes"
local Primitives = require "@antiraid-core/primitives"
local typesext = require "@antiraid/typesext"
local builtinSettingsManager = require "./builtinsettingsmanager"
local stingmanager = require "./stingmanager"
local canModeratorAffectTarget = require "./modhierarchy".canModeratorAffectTarget
local kv = require"@antiraid-core/plugins/kv"

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
    resolved: ResolutionReason?,
}

export type CreatePunishment = {
    userId: discord.Snowflake,
    modId: discord.Snowflake?,
    punishment: string,
    reason: string,
    expires_at: datetime.DateTime?,
    delete_message_seconds: number?,
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
    --- Sets the expiration of a punishment. Repeated calls override previous expiration
    setPunishmentExpiration: (userId: discord.Snowflake, punishmentId: string, reason: string, expiresAt: datetime.DateTime) -> (),
    --- Deletes the expiration of a punishment
    deletePunishmentExpiration: (userId: discord.Snowflake, punishmentId: string, resolve: ResolutionReason?) -> (),
    --- Deletes a punishment. This will also reverse the punishment if possible and delete the expiration if it exists
    deletePunishment: (userId: discord.Snowflake, punishmentId: string, mod: string?, auditReason: string) -> (),
    --- Reverse a whole class of punishments, this will create a dummy punishment for reversal disabling expiration for all punishments within the bot
    reversePunishmentClass: (userId: discord.Snowflake, mod: string?, punishment: string, auditReason: string) -> (),
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
    check: (ctx: Primitives.TemplateContext, p: Punishment) -> (),
    needsReversal: boolean,
    apply: (ctx: Primitives.TemplateContext, p: Punishment) -> (),
    remove: ((ctx: Primitives.TemplateContext, p: Punishment) -> ())?,
}

local punishmentActions: {[string]: PunishmentAction} = {
    ban = {
        name = "Ban",
        description = "Bans the user from the server",
        check = function(ctx: Primitives.TemplateContext, p: Punishment) 
            if p.modId then
                local storeTab = ctx.store :: any
                canModeratorAffectTarget(
                    ctx, 
                    storeTab.userinfomanager.get(p.modId),
                    p.userId, 
                    "moderation.ban"
                )
            end
            return
        end,
        apply = function(ctx: Primitives.TemplateContext, p: Punishment) 
            ctx.Discord:create_guild_ban({
                delete_message_seconds = p.delete_message_seconds,
                reason = p.reason,
                user_id = p.userId,
            })
        end,
        needsReversal = true,
        remove = function(ctx: Primitives.TemplateContext, p: Punishment) 
            ctx.Discord:remove_guild_ban({
                user_id = p.userId,
                reason = "Reverting ban by " .. (if p.modId then "<@" .. p.modId .. ">" else "System") .. " with reason of ``" .. p.reason .. "``",
            })
        end
    },
    kick = {
        name = "Kick",
        description = "Kicks the user from the server",
        check = function(ctx: Primitives.TemplateContext, p: Punishment) 
            if p.delete_message_seconds then 
                error("Kick punishments cannot have a delete_message_seconds value")
            end

            if p.modId then
                local storeTab = ctx.store :: any
                canModeratorAffectTarget(
                    ctx, 
                    storeTab.userinfomanager.get(p.modId), 
                    p.userId, 
                    "moderation.kick"
                )
            end
        end,
        needsReversal = false,
        apply = function(ctx: Primitives.TemplateContext, p: Punishment) 
            ctx.Discord:remove_guild_member({
                reason = p.reason,
                user_id = p.userId,
            })
        end,
    },
    timeout = {
        name = "Timeout",
        description = "Times out the user for a specified duration",
        supportsExpiryAnyways = true,
        check = function(ctx: Primitives.TemplateContext, p: Punishment) 
            if not p.expires_at then 
                error("Timeout punishments must have a expires_at value")
            end

            if p.modId then
                local storeTab = ctx.store :: any
                canModeratorAffectTarget(
                    ctx, 
                    storeTab.userinfomanager.get(p.modId),
                    p.userId, 
                    "moderation.timeout"
                )
            end
        end,
        needsReversal = false,
        apply = function(ctx: Primitives.TemplateContext, p: Punishment) 
            ctx.Discord:modify_guild_member({
                reason = p.reason,
                user_id = p.userId,
                data = {
                    communication_disabled_until = tostring(p.expires_at),
                }
            })
        end,
        remove = function(ctx: Primitives.TemplateContext, p: Punishment) 
            ctx.Discord:modify_guild_member({
                user_id = p.userId,
                reason = "Reverting timeout by " .. (if p.modId then "<@" .. p.modId .. ">" else "System") .. " with reason of ``" .. p.reason .. "``",
                data = {
                    communication_disabled_until = {}
                }
            })
        end
    }
}

-- Cached user punishments should be captured by the PunishmentManager class to ensure require cache keeps the cache local reference the same across
-- all PunishmentManager instances
local _cachedUserPunishments: {[string]: {punishments: {Punishment}, createdAt: number }} = {}
local maxBurstCacheTime = 120 -- 2 minutes

local function PunishmentManager(ctx: Primitives.TemplateContext, stingmanager: stingmanager.StingManager): PunishmentManager
    local self = {}

    -- Create a new key-value executor with the builtins.punishments kv-scope
    local builtinsettingsmanager = builtinSettingsManager(ctx)
    local storeTab = ctx.store :: any

    local function _parsePunishmentData(punishmentId: string, userId: string, punishment: kv.KvRecord): Punishment?
        if not punishment.exists then return nil end
        local reason: string = punishment.value.reason
        local modId: discord.Snowflake? = punishment.value.modId
        local punishmentStr = punishment.value.punishment
        local created_at = punishment.created_at
        local expires_at = punishment.expires_at
        local delete_message_seconds = tonumber(punishment.value.delete_message_seconds)

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
        } :: Punishment
    end

    local function setPunishmentExpiration(userId: discord.Snowflake, punishmentId: string, reason: string, expiresAt: datetime.DateTime)
        -- Get the punishment itself and update its internal expires_at
        local record = ctx.KV:getrecord(punishmentId, {"builtins.punishments", userId})
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
        ctx.KV:setexpiry(punishmentId, {"builtins.punishments", userId}, expiresAt)

        -- Send a modlog message
        local modlogschannel = builtinsettingsmanager.getModLogsChannel("punishment_set_expiration")

        if modlogschannel then
            ctx.Discord:create_message({
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
            })
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

        ctx.KV:setexpiry(punishment.punishmentId, {"builtins.punishments", userId}, nil)

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("punishment_delete_expiration")

        local resolveReason = "Unresolved"

        if resolve == "reversed" then
            resolveReason = "Reversed this punishment"
        end

        if modlogschannel then
            ctx.Discord:create_message({
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
            })
        end
    end

    local function deletePunishmentExpiration(userId: discord.Snowflake, punishmentId: string, resolve: ResolutionReason?)
        -- Get the punishment itself and update its internal expires_at
        local record = ctx.KV:getrecord(punishmentId, {"builtins.punishments", userId})
        if not record.exists then
            return
        end

        local cpunishment = _parsePunishmentData(punishmentId, userId, record)

        if not cpunishment then
            return
        end

        _deletePunishmentExpirationImpl(cpunishment, resolve)
    end

    local function _reversePunishment(punishment: Punishment, mod: string?, auditReason: string)
        if punishment.resolved then return end 
        
        -- Reverse the punishment
        local action = punishmentActions[punishment.punishment]
        if action and action.remove then
            action.remove(ctx, punishment)
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
        local record = ctx.KV:getrecord(punishmentId, {"builtins.punishments", userId})
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
        ctx.KV:delete(punishmentId, {"builtins.punishments", userId})

        -- Clear cache
        self.clearCachedUserPunishments(userId)

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("punishment_delete")

        if modlogschannel then
            ctx.Discord:create_message({
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
            })
        end
    end

    local function reversePunishmentClass(userId: discord.Snowflake, mod: string?, punishment: string, auditReason: string) 
        local action = punishmentActions[punishment]

        if not action or not action.remove then
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
            ctx.Discord:create_message({
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
            })
        end
    end

    local function getPunishmentsOnUser(userId: discord.Snowflake): {Punishment}
        local punishments = ctx.KV:find("%%", {"builtins.punishments", userId})
        if not punishments or #punishments == 0 then
            return {}
        end

        local punishmentList: {Punishment} = {}
        for _, punishment in punishments do
            local punishmentParsed = _parsePunishmentData(punishment.key, userId, punishment)
            if not punishmentParsed then
                continue
            end
            punishmentList[#punishmentList + 1] = punishmentParsed
        end

        self.updateCachedUserPunishments(userId, punishmentList)
        return punishmentList
    end

    local function getPunishment(userId: discord.Snowflake, punishmentId: string): Punishment?
        local punishment = ctx.KV:getrecord(punishmentId, {"builtins.punishments", userId})

        local parsedPunishment = _parsePunishmentData(punishmentId, userId, punishment)
        
        return parsedPunishment
    end

    local function createUserPunishment(punishment: CreatePunishment): Punishment
        local punishmentId = typesext.randstring(16)

        local createdAt = datetime.UTC:now()
        local cpunishment = {
            punishmentId = punishmentId,
            userId = punishment.userId,
            modId = punishment.modId,
            reason = punishment.reason,
            created_at = createdAt,
            expires_at = punishment.expires_at,
            punishment = punishment.punishment or error("Internal error: no punishment specified"),
            delete_message_seconds = punishment.delete_message_seconds,
        } :: Punishment

        -- Apply punishment check
        local action = punishmentActions[cpunishment.punishment]

        if action and action.check then 
            action.check(ctx, cpunishment)
        end        

        -- Create the punishment
        ctx.KV:set(punishmentId, {
            reason = punishment.reason,
            modId = punishment.modId,
            punishment = punishment.punishment or error("Internal error: no punishment specified"),
            delete_message_seconds = punishment.delete_message_seconds,
        }, {"builtins.punishments", punishment.userId}, punishment.expires_at)

        self.clearCachedUserPunishments(punishment.userId)

        if storeTab.onPunishmentCreate then
            (storeTab.onPunishmentCreate :: any)(cpunishment)
        end

        local modlogschannel = builtinsettingsmanager.getModLogsChannel("punishment_create")

        if modlogschannel then
            ctx.Discord:create_message({
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
            })
        end

        -- Apply the punishment
        if action and action.apply then
            action.apply(ctx, cpunishment)
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

        if punishment.punishmentId == "DUMMY" then
            return string.format("Reversed punishment by %s for user %s\nReason: %s", mod, punishment.userId, reason)
        end

        return string.format("Punishment by %s with ID of ``%s``\nReason: %s\nCreated at: <t:%d>\nExpires at: %s\nPunishment: %s", mod, punishment.punishmentId, reason, punishment.created_at.timestamp_seconds, expiresAt, punishment.punishment)
    end

    local function getPunishmentActions(): {[string]: PunishmentAction}
        return punishmentActions
    end

    -- Save to self
    self.getPunishmentsOnUser = getPunishmentsOnUser
    self.setPunishmentExpiration = setPunishmentExpiration
    self.createUserPunishment = createUserPunishment
    self.deletePunishmentExpiration = deletePunishmentExpiration
    self.deletePunishment = deletePunishment
    self.reversePunishmentClass = reversePunishmentClass
    self.getPunishment = getPunishment
    self.getCachedUserPunishments = getCachedUserPunishments
    self.clearCachedUserPunishments = clearCachedUserPunishments
    self.updateCachedUserPunishments = updateCachedUserPunishments
    self.punishmentCompactString = punishmentCompactString
    self.getPunishmentActions = getPunishmentActions

    return self
end

return PunishmentManager