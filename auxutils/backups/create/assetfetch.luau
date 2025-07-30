local Primitives = require"@antiraid-core/primitives"
local apitypes = require"@discord-types/apiTypes"
local blob = require"@antiraid-core/blob"

export type Asset = "icon" | "banner" | "splash"
local ASSETS = {
    "icon",
    "banner",
    "splash",
}

local function fetchAsset(ctx: Primitives.TemplateContext, g: apitypes.GuildObject, icon: Asset): blob.Blob 
    local url = nil
    if icon == "icon" then
        url = `https://cdn.discordapp.com/icons/{g.id}/{g.icon}.jpg?size=512`
    elseif icon == "banner" then
        url = `https://cdn.discordapp.com/banners/{g.id}/{g.banner}.jpg?size=512`
    elseif icon == "splash" then
        url = `https://cdn.discordapp.com/splashes/{g.id}/{g.splash}.jpg?size=512`
    else
        error(`Unknown asset type: {icon}`)
    end

    local resp = ctx.HTTPClient.new_request("GET", url):send()
    if resp.status ~= 200 then
        error(`Failed to fetch {icon} for guild {g.id}: with status code {resp.status}`)
    end

    return resp:blob()
end

local function fetchAssets(ctx: Primitives.TemplateContext, g: apitypes.GuildObject, assets: {Asset}): {[Asset]: blob.Blob}
    local fetchedAssets = {}
    for _, asset in assets do
        fetchedAssets[asset] = fetchAsset(ctx, g, asset)
    end
    return fetchedAssets
end

local function fetchAllAssets(ctx: Primitives.TemplateContext, g: apitypes.GuildObject): {[Asset]: blob.Blob}
    return fetchAssets(ctx, g, ASSETS)
end

return {
    fetchAsset = fetchAsset,
    fetchAssets = fetchAssets,
    fetchAllAssets = fetchAllAssets,
    ASSETS = ASSETS,
}