local addonName, ns = ...

ns.L = setmetatable({}, { __index = function(_, key) return key end })
ns.Constants = {
    groupIDs = { "essential-main", "utility-main", "buff-main" },
    viewerIDs = { "essential", "utility", "buff" },
    viewers = {
        essential = { frameName = "EssentialCooldownViewer", groupID = "essential-main" },
        utility = { frameName = "UtilityCooldownViewer", groupID = "utility-main" },
        buff = { frameName = "BuffIconCooldownViewer", groupID = "buff-main" },
    },
}

local Util = {}
ns.Util = Util

function Util.IsPublic(value)
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end

function Util.Number(value)
    if not Util.IsPublic(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

-- Only configuration/sanitized snapshots use this; never pass a live frame.
function Util.Copy(value)
    if not Util.IsPublic(value) then return nil end
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        if Util.IsPublic(key) then result[key] = Util.Copy(item) end
    end
    return result
end
