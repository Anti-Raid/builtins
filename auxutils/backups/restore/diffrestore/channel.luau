local apitypes = require"@discord-types/apiTypes"
local resttypes = require"@discord-types/restTypes"

export type ChannelChange = {
    type: "CreateChannel",
    --- The channel object to create
    channel: resttypes.CreateGuildChannelRequest
} | {
    type: "DeleteChannel",
    --- The ID of the channel to delete
    channelid: string
} | {
    type: "ModifyChannel",
    --- The ID of the channel to modify
    channelid: string,
    --- The channel object with the modified properties. 
    ---
    --- Use "MoveChannel" if you only need to move the channel to a different category.
    channel: resttypes.ModifyChannelRequest
} | {
    type: "MoveChannel",
    --- The ID of the channel to move
    channelid: string,
    --- The ID of the new parent category. If null, the channel will not have a category attached to it anymore
    newparentid: string?
}

local function diff(old: {apitypes.ChannelObject}, new: {apitypes.ChannelObject}): {ChannelChange}
    error("not implemented yet")
end

return {
    diff = diff
}