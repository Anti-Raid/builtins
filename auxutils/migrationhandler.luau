local Primitives = require "@antiraid-core/primitives"
local isDevMode = require"../devs".isInDevMode

local scopePrefix = if isDevMode then "builtins-dev" else "builtins"

local cacheExpiryTime = 60 -- Cache expiry time

export type Migration = {
    id: string, -- Unique ID of the migration
    data: any, -- Additional data associated with the migration
}

export type MigrationHandler = {
    --- Returns a list of applied migration IDs
    getservermigrations: () -> {[string]: Migration}, 
    --- Returns a cached list of applied migration IDs
    getservermigrationscached: () -> {[string]: Migration},
    --- Adds a migration ID to the list of applied migrations
    addmigration: (migration_id: string, data: any) -> (),
}

--- # What are migrations?
---
--- Migrations are a way to manage feature changes or other updates (such as a first-time setup wizard in the future)
--- that need to be applied once per server. Each migration has a unique ID, and once applied, the ID is stored
--- in a list of applied migrations.
local function MigrationHandler(ctx: Primitives.TemplateContext): MigrationHandler
    local self = {}

    type CachedMigrations = {
        migrations: {[string]: Migration},
        made: number
    }

    local cachedMigrations: CachedMigrations = {
        migrations = table.freeze({}) :: {[string]: Migration},
        made = -math.huge
    }
    
    local function getservermigrations(): {[string]: Migration}
        local data = ctx.KV:find("%%", {scopePrefix .. ".migrations"})

        local migrations = {}
        for _, item in data do
            assert(item.exists, "Expected migration item to exist")
            migrations[item.key] = {
                id = item.key,
                data = item.value :: any,
            }
        end

        migrations = table.freeze(migrations) :: {[string]: Migration}

        cachedMigrations = {
            migrations = migrations,
            made = os.clock(),
        }

        return migrations
    end

    local function getservermigrationscached(): {[string]: Migration}
        if os.clock() - cachedMigrations.made > cacheExpiryTime then
            return getservermigrations()
        end

        return cachedMigrations.migrations
    end

    local function addmigration(migration_id: string, data: any): ()
        assert(type(migration_id) == "string", "migration_id must be a string")

        ctx.KV:set(
            migration_id,
            data,
            {scope = scopePrefix .. ".migrations"}
        )

        -- Invalidate cache
        cachedMigrations.made = -math.huge
    end

    self.getservermigrations = getservermigrations
    self.getservermigrationscached = getservermigrationscached
    self.addmigration = addmigration

    return self
end

return MigrationHandler