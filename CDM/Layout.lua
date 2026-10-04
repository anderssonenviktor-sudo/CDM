local addonName, ns = ...
local Layout = {}
ns.Layout = Layout
local containers, plans = {}, {}
local placements = setmetatable({}, { __mode = "k" })
local applying = false
local isCurrent, defer, request

function Layout.Calculate(count, config)
    local result = { width = 0, height = 0, slots = {} }
    if count == 0 then return result end
    local horizontal = config.growth == "LEFT" or config.growth == "RIGHT"
    local primary = math.min(count, config.perRow)
    local secondary = math.ceil(count / config.perRow)
    local columns, rows = horizontal and secondary or primary, horizontal and primary or secondary
    result.width = columns * config.width + (columns - 1) * config.spacing
    result.height = rows * config.height + (rows - 1) * config.spacing
    for index = 1, count do
        local line = math.floor((index - 1) / config.perRow)
        local position = (index - 1) % config.perRow
        local lineCount = math.min(config.perRow, count - line * config.perRow)
        local offset = (primary - lineCount) * ((horizontal and config.height or config.width) + config.spacing)
        if config.alignment == "START" then offset = 0
        elseif config.alignment ~= "END" then offset = offset / 2 end
        local x, y
        if horizontal then
            x = line * (config.width + config.spacing)
            if config.growth == "LEFT" then x = result.width - config.width - x end
            y = -(offset + position * (config.height + config.spacing))
        else
            x = offset + position * (config.width + config.spacing)
            y = line * (config.height + config.spacing)
            if config.growth == "UP" then y = result.height - config.height - y end
            y = -y
        end
        result.slots[index] = { x = x, y = y }
    end
    return result
end

function Layout.Initialize(validate, deferCallback, requestCallback)
    isCurrent, defer, request = validate, deferCallback, requestCallback
end

function Layout.Invalidate(groupID)
    if not groupID then
        plans = {}
        placements = setmetatable({}, { __mode = "k" })
        return
    end
    local plan = plans[groupID]
    if plan then
        for _, source in ipairs(plan.members) do
            local record = placements[source.frame]
            if record and record.groupID == groupID then placements[source.frame] = nil end
        end
    end
    plans[groupID] = nil
end

function Layout.InvalidateViewer(viewerID)
    for id, plan in pairs(plans) do
        if plan.viewerID == viewerID then Layout.Invalidate(id) end
    end
end

local function Guarded(callback)
    applying = true
    local ok, message = pcall(callback)
    applying = false
    if not ok then error(message, 0) end
end

local function ApplyFrame(record)
    local frame = record.source.frame
    frame:SetScale(1)
    frame:SetSize(record.width, record.height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", record.container, "TOPLEFT", record.x, record.y)
end

local function ApplyViewer(plan)
    local viewer = plan.viewer
    if not viewer then return end
    viewer:SetScale(1)
    viewer:ClearAllPoints()
    viewer:SetPoint("TOPLEFT", plan.container, "TOPLEFT", 0, 0)
    viewer:SetPoint("BOTTOMRIGHT", plan.container, "BOTTOMRIGHT", 0, 0)
end

function Layout.Apply(config, members, viewer, sourceCount)
    if InCombatLockdown() then defer(config.id); return false end
    Layout.Invalidate(config.id)
    -- Leave Blizzard's ID-less Edit Mode placeholders under Blizzard control.
    local isDefault = config.id == ns.Constants.viewers[config.viewer].groupID
    if not viewer or (#members == 0 and (not isDefault or not sourceCount or sourceCount == 0)) then return true end
    local geometry = Layout.Calculate(#members, config)
    local container = containers[config.id]
    if not container then
        container = CreateFrame("Frame", "CDM_Anchor_" .. config.id:gsub("%-", "_"), UIParent)
        containers[config.id] = container
    end
    local plan = { container = container, viewer = isDefault and viewer or nil,
        viewerID = config.viewer, members = members }
    plans[config.id] = plan
    Guarded(function()
        container:ClearAllPoints()
        container:SetPoint(config.point, UIParent, config.relativePoint, config.x, config.y)
        container:SetSize(math.max(geometry.width, 1), math.max(geometry.height, 1))
        ApplyViewer(plan)
        for index, source in ipairs(members) do
            if isCurrent(source) then
                local slot = geometry.slots[index]
                local record = {
                    source = source, groupID = config.id, container = container,
                    width = config.width, height = config.height, x = slot.x, y = slot.y,
                }
                placements[source.frame] = record
                ApplyFrame(record)
            end
        end
    end)
    return true
end

function Layout.ReassertViewer(viewerID)
    for id, plan in pairs(plans) do
        if plan.viewerID == viewerID then Layout.Reassert(id) end
    end
end

function Layout.ReassertFrame(frame)
    if applying then return end
    local record = placements[frame]
    if not record then return end
    if InCombatLockdown() then defer(record.groupID); return end
    if not isCurrent(record.source) then
        Layout.Invalidate(record.groupID)
        request(record.groupID, "DATA")
        return
    end
    Guarded(function() ApplyFrame(record) end)
end

function Layout.Reassert(groupID)
    if applying then return end
    if InCombatLockdown() then defer(groupID); return end
    local plan = plans[groupID]
    if not plan then return end
    for _, source in ipairs(plan.members) do
        if not isCurrent(source) then
            Layout.Invalidate(groupID)
            request(groupID, "DATA")
            return
        end
    end
    Guarded(function()
        ApplyViewer(plan)
        for _, source in ipairs(plan.members) do
            local record = placements[source.frame]
            if record then ApplyFrame(record) end
        end
    end)
end
