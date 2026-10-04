local addonName, ns = ...
local Model = {}
ns.Model = Model
local members = {}
local owners = {}

local function ComesBefore(a, b)
    if a.order ~= b.order then return a.order < b.order end
    if a.source.blizzardOrder ~= b.source.blizzardOrder then
        return a.source.blizzardOrder < b.source.blizzardOrder
    end
    if a.source.cooldownID ~= b.source.cooldownID then
        return a.source.cooldownID < b.source.cooldownID
    end
    if a.source.sourceCategory ~= b.source.sourceCategory then
        return a.source.sourceCategory < b.source.sourceCategory
    end
    return a.source.serial < b.source.serial
end

function Model.Order(group, sources, assignments)
    local ordered = {}
    for _, source in ipairs(sources) do
        if source.viewerID == group.viewer then
            local assignment = assignments[source.key]
            local destination = assignment and assignment.groupID
                or ns.Constants.viewers[source.viewerID].groupID
            if destination == group.id then
                ordered[#ordered + 1] = {
                    source = source, order = assignment and assignment.order or source.blizzardOrder,
                }
            end
        end
    end
    table.sort(ordered, ComesBefore)
    local result = {}
    for _, item in ipairs(ordered) do result[#result + 1] = item.source end
    return result
end

function Model.Resolve(group, sources, assignments)
    local result = Model.Order(group, sources, assignments)
    members[group.id], owners[group.id] = result, group.viewer
    return result
end

function Model.GetMembers(groupID)
    return members[groupID] or {}
end

function Model.Clear(groupID)
    if groupID then members[groupID], owners[groupID] = nil, nil
    else members, owners = {}, {} end
end

function Model.ClearViewer(viewerID)
    for id, owner in pairs(owners) do
        if owner == viewerID then members[id], owners[id] = nil, nil end
    end
end
