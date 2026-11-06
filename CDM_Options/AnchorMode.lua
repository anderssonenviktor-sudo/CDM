local AddonName = "CDM"
local CDM = _G[AddonName]
if not CDM then return end

local ns = CDM._OptionsNS
local UI = ns.ConfigUI
local L = CDM.L
local VIEWERS = CDM.CONST.VIEWERS

local GetCursorPosition = GetCursorPosition
local GetCurrentKeyBoardFocus = GetCurrentKeyBoardFocus
local GetPhysicalScreenSize = GetPhysicalScreenSize
local InCombatLockdown = InCombatLockdown
local securecall = securecall
local IsShiftKeyDown = IsShiftKeyDown
local math_abs = math.abs
local math_ceil = math.ceil
local math_floor = math.floor
local math_rad = math.rad
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber

local configWindowActive = false

function CDM:SetConfigWindowActive(active)
    active = active and true or false
    if configWindowActive ~= active then
        configWindowActive = active
        self:Refresh("LAYOUT")
    end
end

function CDM:SetAnchorModeActive(active)
    self.anchorModeActive = active and true or false
    self:Refresh("BUFF_DATA")
    self:UpdateContainerDragOverlays()
end

local AnchorMode = {
    active = false,
    entries = {},
    overlays = {},
    selectedEntry = nil,
}

local configPositionUpdaters = {}

function ns.RegisterAnchorPositionUpdater(key, callback)
    if type(key) ~= "string" or type(callback) ~= "function" then return end
    configPositionUpdaters[key] = callback
end

local function NotifyConfigPosition(entry, x, y)
    local callback = entry and configPositionUpdaters[entry.key]
    if callback then callback(x, y) end
end

local GRID_SIZE = 64
local GRID_LINE_WIDTH = 1
local GRID_COLOR = { 0, 0, 0, 0.4 }
local GRID_CENTER_ALPHA = 0.55
local SNAP_RANGE = 10
local OVERLAY_COLOR = { 0.08, 0.08, 0.08, 0.72 }
local GOLD = { 1, 0.82, 0, 1 }
local gridCenterX, gridCenterY = 0, 0
local ARROW_TEXTURE = "Interface\\AddOns\\CDM\\Media\\Textures\\collapse"

local grid = CreateFrame("Frame", "CDM_AnchorGrid", UIParent)
grid:SetAllPoints(UIParent)
grid:SetFrameStrata("BACKGROUND")
grid.lines = {}
grid:Hide()

local overlayHost = CreateFrame("Frame", "CDM_AnchorOverlays", UIParent)
overlayHost:SetAllPoints(UIParent)
overlayHost:SetFrameStrata("TOOLTIP")
overlayHost:Hide()

local function BuildGrid()
    local width, height = UIParent:GetSize()
    local physicalWidth, physicalHeight = GetPhysicalScreenSize()
    if not physicalWidth or physicalWidth == 0 or not physicalHeight or physicalHeight == 0 then return end

    local pixel = width / physicalWidth
    local step = math_floor(physicalWidth / GRID_SIZE + 0.5) * pixel
    local lineWidth = GRID_LINE_WIDTH * pixel
    gridCenterX = math_floor(physicalWidth * 0.5 + 0.5) * pixel
    gridCenterY = math_floor(physicalHeight * 0.5 + 0.5) * pixel
    local index = 0

    local function AddLine(isCenter)
        index = index + 1
        local line = grid.lines[index]
        if not line then
            line = grid:CreateTexture(nil, "BACKGROUND")
            grid.lines[index] = line
        end
        if isCenter then
            line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], GRID_CENTER_ALPHA)
            line:SetDrawLayer("BACKGROUND", 1)
        else
            line:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
            line:SetDrawLayer("BACKGROUND", 0)
        end
        line:ClearAllPoints()
        line:Show()
        return line
    end

    local function PlaceVertical(x, isCenter)
        local line = AddLine(isCenter)
        local thickness = isCenter and lineWidth * 2 or lineWidth
        local left = isCenter and x - lineWidth or x
        line:SetPoint("TOPLEFT", grid, "TOPLEFT", left, 0)
        line:SetPoint("BOTTOMRIGHT", grid, "BOTTOMLEFT", left + thickness, 0)
    end

    local function PlaceHorizontal(y, isCenter)
        local line = AddLine(isCenter)
        local thickness = isCenter and lineWidth * 2 or lineWidth
        local top = isCenter and y - lineWidth or y
        line:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -top)
        line:SetPoint("BOTTOMRIGHT", grid, "TOPRIGHT", 0, -(top + thickness))
    end

    for i = -math_ceil(gridCenterX / step), math_ceil((width - gridCenterX) / step) do
        PlaceVertical(gridCenterX + i * step, i == 0)
    end

    for i = -math_ceil(gridCenterY / step), math_ceil((height - gridCenterY) / step) do
        PlaceHorizontal(gridCenterY + i * step, i == 0)
    end

    for i = index + 1, #grid.lines do
        grid.lines[i]:Hide()
    end
end

local function RefreshActiveGrid()
    if AnchorMode.active then
        BuildGrid()
    end
end

CDM:RegisterEvent("UI_SCALE_CHANGED", RefreshActiveGrid)
CDM:RegisterEvent("DISPLAY_SIZE_CHANGED", RefreshActiveGrid)

local function PrintMessage(message)
    if CDM.Print then
        CDM:Print(message)
    else
        print("CDM: " .. message)
    end
end

local function EnsureViewerPosition(viewerName, defaults)
    local positions = CDM.db.editModePositions
    if not positions then
        positions = {}
        CDM.db.editModePositions = positions
    end
    local viewerPositions = positions[viewerName]
    if not viewerPositions then
        viewerPositions = {}
        positions[viewerName] = viewerPositions
    end
    if not viewerPositions.Default then
        viewerPositions.Default = {
            point = defaults.point,
            x = defaults.x,
            y = defaults.y,
        }
    end
    return viewerPositions.Default
end
ns.EnsureViewerPosition = EnsureViewerPosition

local GetFrameBounds
local buffBarFrameScratch = {}

local function GetConfiguredBuffBarFrames(groupIndex)
    for i = #buffBarFrameScratch, 1, -1 do
        buffBarFrameScratch[i] = nil
    end
    if not (CDM.GetBuffBarEntries and CDM.BuffBarTimers_GetBar) then
        return buffBarFrameScratch
    end
    local entries = CDM.GetBuffBarEntries()
    for i, entry in ipairs(entries) do
        if entry.groupIndex == groupIndex then
            local frame = CDM.BuffBarTimers_GetBar(i)
            if frame then
                buffBarFrameScratch[#buffBarFrameScratch + 1] = frame
            end
        end
    end
    return buffBarFrameScratch
end

local function AddEntry(key, label, frame, getOffsets, setOffsets, apply, getBounds, hasActiveFrames)
    if not frame then return end
    local entry = {
        key = key,
        label = label,
        frame = frame,
        getOffsets = getOffsets,
        setOffsets = setOffsets,
        apply = apply,
        getBounds = getBounds,
        hasActiveFrames = hasActiveFrames,
    }
    AnchorMode.entries[#AnchorMode.entries + 1] = entry
    return entry
end

local function AddViewerEntries()
    local containers = CDM.anchorContainers
    if not containers then return end

    local essential = containers[VIEWERS.ESSENTIAL]
    local essentialFrames = CDM.ungroupedAnchorFrames and CDM.ungroupedAnchorFrames[VIEWERS.ESSENTIAL]
    AddEntry("essential", L["Essential Cooldowns"], essential,
        function()
            local p = EnsureViewerPosition(VIEWERS.ESSENTIAL, { point = "CENTER", x = 0, y = -201 })
            return p.x or 0, p.y or -201
        end,
        function(x, y)
            local p = EnsureViewerPosition(VIEWERS.ESSENTIAL, { point = "CENTER", x = 0, y = -201 })
            p.x, p.y = x, y
        end,
        function()
            CDM:UpdateEssentialContainerPosition()
            if CDM.UpdateResources then CDM:UpdateResources() end
            if CDM.UpdatePlayerCastBar then CDM:UpdatePlayerCastBar() end
            local p = EnsureViewerPosition(VIEWERS.ESSENTIAL, { point = "CENTER", x = 0, y = -201 })
            CDM:NotifyPositionSliderUpdate("essential", p.x, p.y, true)
        end,
        function() return GetFrameBounds(essentialFrames) end,
        function() return GetFrameBounds(essentialFrames) ~= nil end)

    local utility = containers[VIEWERS.UTILITY]
    local utilityFrames = CDM.ungroupedAnchorFrames and CDM.ungroupedAnchorFrames[VIEWERS.UTILITY]
    AddEntry("utility", L["Utility Cooldowns"], utility,
        function() return CDM.db.utilityXOffset or 0, CDM.db.utilityYOffset or 0 end,
        function(x, y) CDM.db.utilityXOffset, CDM.db.utilityYOffset = x, y end,
        function() CDM:UpdateUtilityContainerPosition() end,
        function() return GetFrameBounds(utilityFrames) end,
        function() return GetFrameBounds(utilityFrames) ~= nil end)

    if not CDM.db.moveBuffsDown then
        local buff = containers[VIEWERS.BUFF]
        local buffFrames = CDM.ungroupedAnchorFrames and CDM.ungroupedAnchorFrames[VIEWERS.BUFF]
        -- Screen placement lives in editModePositions; other anchors have their own offsets.
        local function IsScreenAnchored()
            return (CDM.db.buffAnchorTarget or "screen") == "screen"
        end
        AddEntry("buff", L["Buff Icons"], buff,
            function()
                if not IsScreenAnchored() then
                    return CDM.db.buffAnchorOffsetX or 0, CDM.db.buffAnchorOffsetY or 0
                end
                local p = EnsureViewerPosition(VIEWERS.BUFF, { point = "CENTER", x = 0, y = -149 })
                return p.x or 0, p.y or -149
            end,
            function(x, y)
                if not IsScreenAnchored() then
                    CDM.db.buffAnchorOffsetX, CDM.db.buffAnchorOffsetY = x, y
                    return
                end
                local p = EnsureViewerPosition(VIEWERS.BUFF, { point = "CENTER", x = 0, y = -149 })
                p.x, p.y = x, y
            end,
            function()
                CDM:UpdateBuffContainerPosition()
                if IsScreenAnchored() then
                    local p = EnsureViewerPosition(VIEWERS.BUFF, { point = "CENTER", x = 0, y = -149 })
                    CDM:NotifyPositionSliderUpdate("buff", p.x, p.y, true)
                end
            end,
            function() return GetFrameBounds(buffFrames) end,
            function() return GetFrameBounds(buffFrames) ~= nil end)
    end

    local buffBar = containers[VIEWERS.BUFF_BAR]
    AddEntry("buff_bar", L["Buff Bars"], buffBar,
        function()
            local p = EnsureViewerPosition(VIEWERS.BUFF_BAR, { point = "CENTER", x = 0, y = -324 })
            return p.x or 0, p.y or -324
        end,
        function(x, y)
            local p = EnsureViewerPosition(VIEWERS.BUFF_BAR, { point = "CENTER", x = 0, y = -324 })
            p.x, p.y = x, y
        end,
        function()
            CDM:UpdateBuffBarContainerPosition()
            local p = EnsureViewerPosition(VIEWERS.BUFF_BAR, { point = "CENTER", x = 0, y = -324 })
            CDM:NotifyPositionSliderUpdate("buffBar", p.x, p.y, true)
        end,
        function() return GetFrameBounds(GetConfiguredBuffBarFrames(nil)) end,
        function()
            local bars = CDM.BUFFBAR and CDM.BUFFBAR.GetUngrouped and CDM.BUFFBAR.GetUngrouped()
            return type(bars) == "table" and #bars > 0
        end)
end

local function AddResourceEntries()
    if CDM.db.resourcesEnabled == false or not CDM.resourceBars then return end
    for powerType, bar in pairs(CDM.resourceBars) do
        local anchorTo = bar and bar.barKey and CDM:GetBarSetting(bar.barKey, "anchorTo")
        local independentlyAnchored = not anchorTo or anchorTo == "screen"
            or anchorTo == "playerFrame" or anchorTo == "essential"
        if bar and bar.barKey and bar:IsShown() and independentlyAnchored then
            local barKey = bar.barKey
            local capturedBarKey = barKey
            AddEntry("resource_" .. barKey, L[barKey], bar,
                function()
                    return CDM:GetBarSetting(capturedBarKey, "offsetX") or 0,
                        CDM:GetBarSetting(capturedBarKey, "offsetY") or 0
                end,
                function(x, y)
                    CDM:SetBarSetting(capturedBarKey, "offsetX", x)
                    CDM:SetBarSetting(capturedBarKey, "offsetY", y)
                end,
                function() CDM:UpdateResources() end)
        end
    end
end

local function AddCastBarEntry()
    local frame = CDM.castBarFrame
    if CDM.db.castBarEnabled == false or not frame then return end
    local anchorFrame = CDM.castBarContainer or frame
    AddEntry("cast_bar", L["Player Cast Bar"], anchorFrame,
        function() return CDM.db.castBarOffsetX or 0, CDM.db.castBarOffsetY or 0 end,
        function(x, y) CDM.db.castBarOffsetX, CDM.db.castBarOffsetY = x, y end,
        function() CDM:UpdatePlayerCastBar() end)
end

GetFrameBounds = function(frames, extraFrames)
    local left, right, top, bottom
    local parentScale = UIParent:GetEffectiveScale()
    local function Include(frame)
        if not (frame and frame:IsShown()) then return end
        local frameLeft, frameRight = frame:GetLeft(), frame:GetRight()
        local frameTop, frameBottom = frame:GetTop(), frame:GetBottom()
        if not (frameLeft and frameRight and frameTop and frameBottom) then return end
        local scaleRatio = frame:GetEffectiveScale() / parentScale
        frameLeft, frameRight = frameLeft * scaleRatio, frameRight * scaleRatio
        frameTop, frameBottom = frameTop * scaleRatio, frameBottom * scaleRatio
        left = left and math.min(left, frameLeft) or frameLeft
        right = right and math.max(right, frameRight) or frameRight
        top = top and math.max(top, frameTop) or frameTop
        bottom = bottom and math.min(bottom, frameBottom) or frameBottom
    end
    if frames then
        for _, frame in pairs(frames) do Include(frame) end
    end
    if extraFrames then
        for _, frame in pairs(extraFrames) do Include(frame) end
    end
    return left, right, top, bottom
end

local function AddGroupEntries(prefix, labelPrefix, containers, sets, apply, frameRegistry, includePlaceholders)
    local groups = sets and sets.groups
    if not containers or not groups then return end
    for index, group in ipairs(groups) do
        local frame = containers[index]
        if frame then
            local capturedGroup = group
            local capturedIndex = index
            local label = capturedGroup.name or (labelPrefix .. " " .. index)
            AddEntry(prefix .. index, label, frame,
                function() return capturedGroup.offsetX or 0, capturedGroup.offsetY or 0 end,
                function(x, y) capturedGroup.offsetX, capturedGroup.offsetY = x, y end,
                apply,
                function()
                    local extraFrames
                    if includePlaceholders and CDM.BuffGroupPlaceholders.GetGroupFrames then
                        extraFrames = CDM.BuffGroupPlaceholders.GetGroupFrames(capturedIndex)
                    end
                    return GetFrameBounds(frameRegistry and frameRegistry[capturedIndex], extraFrames)
                end,
                function()
                    return GetFrameBounds(frameRegistry and frameRegistry[capturedIndex]) ~= nil
                end)
        end
    end
end

local function AddBuffBarGroupEntries()
    local groups = CDM.buffBarGroupSets and CDM.buffBarGroupSets.groups
    local containers = CDM.buffBarGroupContainers
    if not containers or not groups then return end
    for index, group in ipairs(groups) do
        local frame = containers[index]
        if frame then
            local capturedGroup = group
            local capturedIndex = index
            AddEntry("buff_bar_group_" .. index,
                capturedGroup.name or (L["Buff Bar Group"] .. " " .. index), frame,
                function() return capturedGroup.offsetX or 0, capturedGroup.offsetY or 0 end,
                function(x, y) capturedGroup.offsetX, capturedGroup.offsetY = x, y end,
                function() CDM:Refresh("BUFF_DATA") end,
                function() return GetFrameBounds(GetConfiguredBuffBarFrames(capturedIndex)) end,
                function()
                    return type(capturedGroup.bars) == "table" and #capturedGroup.bars > 0
                end)
        end
    end
end

local function GetAutoBarWidth(entry)
    if entry.key == "cast_bar" and CDM.db.castBarAutoWidthSource == "utility"
        and CDM:GetUtilityVisibleCount() > 0 then
        return CDM:GetUtilityContentWidth()
    end
    local width = CDM.CalculateEssentialRow1Width and CDM.CalculateEssentialRow1Width() or 200
    return width > 0 and width or 200
end

local function ConfigureEntrySize(entry)
    local key = entry.key
    local sizeKeys
    if key == "essential" then
        sizeKeys = { "sizeEssRow1" }
        local count = 0
        local frames = CDM.ungroupedAnchorFrames and CDM.ungroupedAnchorFrames[VIEWERS.ESSENTIAL]
        for _ in pairs(frames or {}) do count = count + 1 end
        if count > (CDM.db.maxRowEss or 9) then
            sizeKeys[2] = "sizeEssRow2"
        end
    elseif key == "utility" then
        sizeKeys = { "sizeUtility" }
    elseif key == "buff" then
        sizeKeys = { "sizeBuff" }
    end

    local items, widthKey, heightKey, defaultWidth, defaultHeight
    local groupIndex = tonumber(key:match("^cooldown_group_(%d+)$"))
    local buffIndex = tonumber(key:match("^buff_group_(%d+)$"))
    local barIndex = tonumber(key:match("^buff_bar_group_(%d+)$"))
    local resourceKey = key:match("^resource_(.+)$")
    if sizeKeys then
        entry.sizeLimits = { width = { 20, 100 }, height = { 20, 100 } }
        entry.refreshSize = function() CDM:Refresh("LAYOUT") end
        entry.readSize = function(axis)
            local field = axis == "width" and "w" or "h"
            local value = CDM.db[sizeKeys[1]][field]
            for i = 2, #sizeKeys do
                if CDM.db[sizeKeys[i]][field] ~= value then return nil end
            end
            return value
        end
        entry.writeSize = function(axis, value)
            local field = axis == "width" and "w" or "h"
            for _, sizeKey in ipairs(sizeKeys) do
                -- Defaults may be inherited; replace the size instead of mutating it.
                local current = CDM.db[sizeKey]
                local updated = { w = current.w, h = current.h }
                updated[field] = value
                CDM.db[sizeKey] = updated
            end
        end
        return
    elseif groupIndex or buffIndex then
        local sets = groupIndex and CDM.CooldownGroupSets or CDM.BuffGroupSets
        items = { sets.groups[groupIndex or buffIndex] }
        widthKey, heightKey = "iconWidth", "iconHeight"
        defaultWidth, defaultHeight = 30, 30
        entry.sizeLimits = { width = { 16, 100 }, height = { 16, 100 } }
        entry.refreshSize = function() CDM:Refresh(groupIndex and "CD_DATA" or "BUFF_DATA") end
    elseif key == "buff_bar" or barIndex then
        if barIndex then
            items = CDM.buffBarGroupSets.groups[barIndex].bars
        else
            items = CDM.BUFFBAR.GetUngrouped()
        end
        if not items or #items == 0 then return end
        widthKey, heightKey = "width", "height"
        defaultWidth, defaultHeight = 0, 20
        entry.sizeLimits = { width = { 60, 600 }, height = { 4, 40 } }
        entry.autoWidth = true
        entry.refreshSize = function()
            CDM.InvalidateBuffBarEntries()
            CDM:Refresh("BUFF_DATA", "STYLE", "LAYOUT")
        end
    elseif key == "cast_bar" then
        items = { CDM.db }
        widthKey, heightKey = "castBarWidth", "castBarHeight"
        defaultWidth, defaultHeight = 300, 20
        entry.sizeLimits = { width = { 60, 1000 }, height = { 8, 50 } }
        entry.autoWidth = true
        entry.refreshSize = function() CDM:Refresh("STYLE") end
    elseif resourceKey then
        entry.sizeLimits = { width = { 60, 600 }, height = { 4, 40 } }
        entry.autoWidth = true
        entry.readSize = function(axis)
            local value = CDM:GetBarSetting(resourceKey, axis) or (axis == "width" and 0 or 16)
            return axis == "width" and value == 0 and GetAutoBarWidth(entry) or value
        end
        entry.writeSize = function(axis, value) CDM:SetBarSetting(resourceKey, axis, value) end
        entry.refreshSize = function() CDM:Refresh("RESOURCES", "LAYOUT") end
        return
    else
        return
    end

    entry.readSize = function(axis)
        local field = axis == "width" and widthKey or heightKey
        local fallback = axis == "width" and defaultWidth or defaultHeight
        local value
        for i, item in ipairs(items) do
            local current = item[field] or fallback
            if axis == "width" and entry.autoWidth and current == 0 then
                current = GetAutoBarWidth(entry)
            end
            if i > 1 and current ~= value then return nil end
            value = current
        end
        return value
    end
    entry.writeSize = function(axis, value)
        local field = axis == "width" and widthKey or heightKey
        for _, item in ipairs(items) do item[field] = value end
    end
end

-- Groups reset their offsets on a new target, as the group editors do.
local function GroupAnchor(group, options, refresh)
    return {
        options = options,
        get = function() return group.anchorTarget or "screen" end,
        set = function(value)
            group.anchorTarget = value
            group.anchorPoint = group.anchorPoint or "CENTER"
            group.anchorRelativeTo = group.anchorRelativeTo or "CENTER"
            group.offsetX, group.offsetY = 0, 0
            refresh()
        end,
    }
end

local function ConfigureEntryAnchor(entry)
    local key = entry.key
    local groupIndex = tonumber(key:match("^cooldown_group_(%d+)$"))
    local buffIndex = tonumber(key:match("^buff_group_(%d+)$"))
    local barIndex = tonumber(key:match("^buff_bar_group_(%d+)$"))
    local resourceKey = key:match("^resource_(.+)$")
    if groupIndex then
        entry.anchor = GroupAnchor(CDM.CooldownGroupSets.groups[groupIndex], UI.AnchorTargets.cooldownGroup,
            function() CDM:Refresh("CD_DATA") end)
    elseif buffIndex then
        entry.anchor = GroupAnchor(CDM.BuffGroupSets.groups[buffIndex], UI.AnchorTargets.buffGroup,
            function() CDM:Refresh("BUFF_DATA") end)
    elseif barIndex then
        entry.anchor = GroupAnchor(CDM.buffBarGroupSets.groups[barIndex], UI.AnchorTargets.buffBarGroup,
            function()
                CDM.InvalidateBuffBarEntries()
                CDM:Refresh("BUFF_DATA", "STYLE", "LAYOUT")
            end)
    elseif key == "buff" then
        entry.anchor = {
            options = UI.AnchorTargets.buffViewer,
            get = function() return CDM.db.buffAnchorTarget or "screen" end,
            set = function(value)
                -- Screen placement keeps its Edit Mode position.
                if value ~= "screen" then
                    CDM.db.buffAnchorOffsetX, CDM.db.buffAnchorOffsetY = 0, 0
                end
                CDM.db.buffAnchorTarget = value
                CDM.db.moveBuffsDown = false
                CDM:Refresh("LAYOUT")
            end,
        }
    elseif key == "cast_bar" then
        entry.anchor = {
            options = UI.GetCastBarAnchorTargets,
            get = function() return CDM.db.castBarAnchor or "resources" end,
            set = function(value)
                CDM.db.castBarAnchor = value
                CDM:Refresh("STYLE")
            end,
        }
    elseif resourceKey and ns.GetResourceAnchorTargets then
        local classKey = ns.GetResourceBarClassKey(resourceKey)
        entry.anchor = {
            options = function() return ns.GetResourceAnchorTargets(classKey, resourceKey) end,
            get = function() return CDM:GetBarSettingForClass(classKey, resourceKey, "anchorTo") or "screen" end,
            set = function(value)
                CDM:SetBarSettingForClass(classKey, resourceKey, "anchorTo", value)
                CDM:Refresh("RESOURCES", "LAYOUT")
            end,
        }
    end
end

local function GetAnchorOptions(anchor)
    local options = anchor.options
    return type(options) == "function" and options() or options
end

local function BuildEntries()
    for i = #AnchorMode.entries, 1, -1 do
        AnchorMode.entries[i] = nil
    end

    AddViewerEntries()
    AddResourceEntries()
    AddCastBarEntry()
    AddGroupEntries("cooldown_group_", L["Cooldown Group"], CDM.cooldownGroupContainers, CDM.CooldownGroupSets,
        function() CDM:UpdateAllCooldownGroupContainers() end, CDM.cooldownGroupFrames)
    AddGroupEntries("buff_group_", L["Buff Group"], CDM.buffGroupContainers, CDM.BuffGroupSets,
        function() CDM:UpdateAllBuffGroupContainers() end, CDM.buffGroupFrames, true)
    AddBuffBarGroupEntries()
    for _, entry in ipairs(AnchorMode.entries) do
        ConfigureEntrySize(entry)
        ConfigureEntryAnchor(entry)
    end
end

local dragging
local pendingCombatRefresh = false
local UpdateNudgePanel
local dragFrame = CreateFrame("Frame")
dragFrame:Hide()

local function UpdateOverlayBounds(overlay)
    local entry = overlay and overlay.entry
    if not entry then return end
    if entry.hasActiveFrames and not entry.hasActiveFrames() then
        overlay:Hide()
        return
    end
    overlay:Show()
    overlay:ClearAllPoints()
    if entry.getBounds then
        local left, right, top, bottom = entry.getBounds()
        if left and right and top and bottom then
            overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
            overlay:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
            return
        end
    end
    overlay:SetAllPoints(entry.frame)
end

local anchorRefreshFrame = CreateFrame("Frame")
local anchorRefreshElapsed = 0
anchorRefreshFrame:Hide()
anchorRefreshFrame:SetScript("OnUpdate", function(_, elapsed)
    anchorRefreshElapsed = anchorRefreshElapsed + elapsed
    if anchorRefreshElapsed < 0.1 then return end
    anchorRefreshElapsed = 0
    for _, overlay in ipairs(AnchorMode.overlays) do
        UpdateOverlayBounds(overlay)
    end
end)

local function UpdateDrag()
    if not dragging then return end
    local frame = dragging.entry.frame
    local scale = frame:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    local dx = math_floor(cursorX - dragging.cursorX + 0.5)
    local dy = math_floor(cursorY - dragging.cursorY + 0.5)

    if not IsShiftKeyDown() then
        local centerX = dragging.centerX + dx * dragging.scaleRatio
        local centerY = dragging.centerY + dy * dragging.scaleRatio
        if math_abs(centerX - gridCenterX) < SNAP_RANGE then
            dx = dx + math_floor((gridCenterX - centerX) / dragging.scaleRatio + 0.5)
        end
        if math_abs(centerY - gridCenterY) < SNAP_RANGE then
            dy = dy + math_floor((gridCenterY - centerY) / dragging.scaleRatio + 0.5)
        end
    end

    dragging.dx, dragging.dy = dx, dy
    frame:ClearAllPoints()
    frame:SetPoint(dragging.point, dragging.relativeTo, dragging.relativePoint,
        dragging.originX + dx, dragging.originY + dy)
    UpdateOverlayBounds(dragging.overlay)
end

dragFrame:SetScript("OnUpdate", UpdateDrag)

local function StartDrag(overlay)
    if not AnchorMode.active or InCombatLockdown() then return end
    local entry = overlay.entry
    local frame = entry.frame
    if frame:GetNumPoints() ~= 1 then return end

    local point, relativeTo, relativePoint, originX, originY = frame:GetPoint(1)
    local scale = frame:GetEffectiveScale()
    local scaleRatio = scale / UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local offsetX, offsetY = entry.getOffsets()
    local left, bottom, width, height = frame:GetRect()
    dragging = {
        entry = entry,
        overlay = overlay,
        point = point,
        relativeTo = relativeTo or UIParent,
        relativePoint = relativePoint,
        originX = originX or 0,
        originY = originY or 0,
        cursorX = cursorX / scale,
        cursorY = cursorY / scale,
        centerX = left and (left + width / 2) * scaleRatio or 0,
        centerY = bottom and (bottom + height / 2) * scaleRatio or 0,
        scaleRatio = scaleRatio,
        offsetX = offsetX,
        offsetY = offsetY,
        dx = 0,
        dy = 0,
    }
    dragFrame:Show()
end

local function ApplyEntryOffsets(entry, x, y, runApply)
    if not entry then return end
    x = math_floor((tonumber(x) or 0) + 0.5)
    y = math_floor((tonumber(y) or 0) + 0.5)
    entry.setOffsets(x, y)
    if runApply then
        entry.apply()
    else
        pendingCombatRefresh = true
    end
    NotifyConfigPosition(entry, x, y)
    for _, overlay in ipairs(AnchorMode.overlays) do
        if overlay.entry == entry then
            UpdateOverlayBounds(overlay)
            break
        end
    end
    if UpdateNudgePanel then UpdateNudgePanel() end
end

local function CommitDrag(runApply)
    if not dragging then return end
    dragFrame:Hide()
    local drag = dragging
    dragging = nil
    ApplyEntryOffsets(drag.entry, drag.offsetX + drag.dx, drag.offsetY + drag.dy, runApply)
    UpdateOverlayBounds(drag.overlay)
end

local function StopDrag()
    CommitDrag(not InCombatLockdown())
end

local nudgePanel
local anchorBanner
local RebuildEntries
local PANEL_BG = { 0.035, 0.035, 0.04, 0.96 }

local function CreateAnchorBanner()
    if anchorBanner then return anchorBanner end

    local banner = CreateFrame("Frame", "CDM_AnchorModeBanner", UIParent, "BackdropTemplate")
    banner:SetSize(230, 30)
    banner:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    banner:SetFrameStrata("TOOLTIP")
    -- Leave room above the toolbar for its panel and interactive children.
    banner:SetFrameLevel(100)
    banner:SetClampedToScreen(true)
    banner:SetMovable(true)
    banner:EnableMouse(true)
    banner:RegisterForDrag("LeftButton")
    banner:SetScript("OnDragStart", banner.StartMoving)
    banner:SetScript("OnDragStop", banner.StopMovingOrSizing)
    banner:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    banner:SetBackdropColor(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], PANEL_BG[4])
    banner:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)

    local label = banner:CreateFontString(nil, "OVERLAY", "CDM_Font12")
    label:SetPoint("LEFT", 14, 0)
    label:SetText(L["Anchor Mode"])
    label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)

    local exitButton = CreateFrame("Button", nil, banner)
    exitButton:SetSize(100, 28)
    exitButton:SetPoint("RIGHT", -5, 0)
    local exitText = exitButton:CreateFontString(nil, "OVERLAY", "CDM_Font12")
    exitText:SetPoint("CENTER")
    exitText:SetText(L["Exit Anchor"])
    exitText:SetTextColor(1, 0.3, 0.2, 1)
    exitButton:SetScript("OnEnter", function() exitText:SetTextColor(1, 0.65, 0.5, 1) end)
    exitButton:SetScript("OnLeave", function() exitText:SetTextColor(1, 0.3, 0.2, 1) end)
    exitButton:SetScript("OnClick", function() AnchorMode:Exit(true) end)

    banner:Hide()
    anchorBanner = banner
    return banner
end

local function RefreshOverlaySelection()
    for _, overlay in ipairs(AnchorMode.overlays) do
        local selected = AnchorMode.selectedEntry == overlay.entry
        if selected or overlay.isHovered then
            overlay:SetBackdropBorderColor(1, 1, 1, 1)
        else
            overlay:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
        end
    end
end

local function SelectEntry(entry)
    if nudgePanel then
        for _, box in ipairs(nudgePanel.boxes) do box:ClearFocus() end
    end
    if nudgePanel then nudgePanel.anchorDropdown:CloseMenu() end
    AnchorMode.selectedEntry = entry
    RefreshOverlaySelection()
    if UpdateNudgePanel then UpdateNudgePanel() end
end

local function ApplyEntrySize(entry, axis, value)
    if not (entry and entry.writeSize) or InCombatLockdown() then return end
    local limits = entry.sizeLimits[axis]
    value = math_floor(value + 0.5)
    if not (axis == "width" and entry.autoWidth and value == 0) then
        value = math.max(limits[1], math.min(limits[2], value))
    end
    entry.writeSize(axis, value)
    entry.refreshSize()
    UpdateNudgePanel()
    -- Auto widths resolve after the refreshed layout runs.
    C_Timer.After(0, function()
        if AnchorMode.active then UpdateNudgePanel() end
    end)
end

local function StepSelectedSize(box, direction)
    local entry = AnchorMode.selectedEntry
    if not (entry and entry.readSize) then return end
    local current = entry.readSize(box.axis)
    if not current then return end
    ApplyEntrySize(entry, box.axis, current + direction * (IsShiftKeyDown() and 10 or 1))
end

local function SetEntryAnchor(entry, value)
    local anchor = entry and entry.anchor
    if not anchor or InCombatLockdown() or anchor.get() == value then return end
    anchor.set(value)
    AnchorMode.anchorChanged = true
    -- A new target can move offsets or add and remove entries.
    RebuildEntries(entry.key)
end

local function NudgeSelected(dx, dy)
    local entry = AnchorMode.selectedEntry
    if not entry or InCombatLockdown() then return end
    local x, y = entry.getOffsets()
    local step = IsShiftKeyDown() and 10 or 1
    ApplyEntryOffsets(entry, (x or 0) + dx * step, (y or 0) + dy * step, true)
end

local keyboardHandler = CreateFrame("Frame", "CDM_AnchorKeyboardHandler", UIParent)
keyboardHandler:SetFrameStrata("TOOLTIP")
keyboardHandler:SetFrameLevel(90)
keyboardHandler:EnableMouse(false)
keyboardHandler:EnableKeyboard(true)
keyboardHandler:SetPropagateKeyboardInput(true)
keyboardHandler:Hide()

local KEYBOARD_NUDGES = {
    LEFT = { -1, 0 },
    UP = { 0, 1 },
    DOWN = { 0, -1 },
    RIGHT = { 1, 0 },
}

keyboardHandler:SetScript("OnKeyDown", function(self, key)
    if GetCurrentKeyBoardFocus() then
        self:SetPropagateKeyboardInput(true)
        return
    end
    if key == "ESCAPE" then
        AnchorMode:Exit(true)
        self:SetPropagateKeyboardInput(false)
        return
    end
    local delta = KEYBOARD_NUDGES[key]
    if delta and AnchorMode.selectedEntry then
        self:SetPropagateKeyboardInput(false)
        NudgeSelected(delta[1], delta[2])
        return
    end

    self:SetPropagateKeyboardInput(true)
end)

local function CreateNudgePanel()
    if nudgePanel then return nudgePanel end

    local banner = CreateAnchorBanner()
    local panelHeight = 182
    local panel = CreateFrame("Frame", "CDM_AnchorNudgeTool", banner, "BackdropTemplate")
    panel:SetSize(230, panelHeight)
    -- Overlap the banner by a pixel so the two borders read as one frame.
    panel:SetPoint("TOP", banner, "BOTTOM", 0, 1)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetFrameLevel(banner:GetFrameLevel() + 1)
    banner:SetClampRectInsets(0, 0, 0, -(panelHeight - 1))
    panel:EnableMouse(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], PANEL_BG[4])
    panel:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)

    local selected = panel:CreateFontString(nil, "OVERLAY", "CDM_Font12")
    selected:SetPoint("TOP", 0, -7)
    selected:SetWidth(210)
    selected:SetWordWrap(false)
    selected:SetFontObject("CDM_Font18")
    selected:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    panel.selected = selected

    local function CreateValueBox(labelText, y)
        local label = panel:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        label:SetPoint("TOPLEFT", 14, y)
        label:SetText(labelText)

        local box = UI.CreateEditBox(panel)
        box:SetFrameLevel(panel:GetFrameLevel() + 1)
        box:SetSize(70, 22)
        -- Leaves room on both sides for the steppers.
        box:SetPoint("TOPRIGHT", -30, y + 4)
        box:SetJustifyH("CENTER")
        return box
    end

    -- The left stepper lowers the value and the right one raises it.
    local function CreateStepper(box, direction, rotation, onClick)
        local button = CreateFrame("Button", nil, panel)
        button:SetFrameLevel(panel:GetFrameLevel() + 1)
        button:SetSize(18, 22)
        if direction < 0 then
            button:SetPoint("RIGHT", box, "LEFT", -2, 0)
        else
            button:SetPoint("LEFT", box, "RIGHT", 2, 0)
        end
        local icon = button:CreateTexture(nil, "OVERLAY")
        icon:SetSize(16, 16)
        icon:SetPoint("CENTER")
        icon:SetTexture(ARROW_TEXTURE)
        icon:SetRotation(math_rad(rotation))
        icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        button:SetScript("OnEnter", function() icon:SetVertexColor(1, 1, 1, 1) end)
        button:SetScript("OnLeave", function() icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
        button:SetScript("OnClick", function()
            -- Commit any typed value first so the step starts from it.
            box:ClearFocus()
            onClick(direction)
        end)
        return button
    end

    panel.xBox = CreateValueBox(L["X Offset"], -36)
    panel.yBox = CreateValueBox(L["Y Offset"], -64)
    panel.widthBox = CreateValueBox(L["Width"], -92)
    panel.heightBox = CreateValueBox(L["Height"], -120)
    panel.widthBox.axis = "width"
    panel.heightBox.axis = "height"
    panel.sizeBoxes = { panel.widthBox, panel.heightBox }
    panel.boxes = { panel.xBox, panel.yBox, panel.widthBox, panel.heightBox }

    panel.offsetSteppers = {
        CreateStepper(panel.xBox, -1, -90, function(d) NudgeSelected(d, 0) end),
        CreateStepper(panel.xBox, 1, 90, function(d) NudgeSelected(d, 0) end),
        CreateStepper(panel.yBox, -1, 0, function(d) NudgeSelected(0, d) end),
        CreateStepper(panel.yBox, 1, 180, function(d) NudgeSelected(0, d) end),
    }
    panel.sizeSteppers = {}
    for _, box in ipairs(panel.sizeBoxes) do
        for _, direction in ipairs({ -1, 1 }) do
            panel.sizeSteppers[#panel.sizeSteppers + 1] = CreateStepper(box, direction,
                direction < 0 and -90 or 90, function(d) StepSelectedSize(box, d) end)
        end
    end

    local anchorDropdown = UI.CreateDropdown(panel)
    anchorDropdown:SetPoint("TOPLEFT", 14, -146)
    anchorDropdown:SetPoint("TOPRIGHT", -10, -146)
    anchorDropdown:SetHeight(24)
    anchorDropdown:SetupMenu(function(_, rootDescription)
        -- Menus open below the TOOLTIP strata this panel uses.
        rootDescription:AddMenuAcquiredCallback(function(menu)
            menu:SetFrameStrata("TOOLTIP")
            menu:SetFrameLevel(panel:GetFrameLevel() + 50)
        end)
        local entry = AnchorMode.selectedEntry
        local anchor = entry and entry.anchor
        if not anchor then return end
        for _, option in ipairs(GetAnchorOptions(anchor)) do
            local value = option.value
            rootDescription:CreateRadio(option.label,
                function() return anchor.get() == value end,
                function() SetEntryAnchor(entry, value) end)
        end
    end)
    panel.anchorDropdown = anchorDropdown

    local function CommitBox(box)
        if panel.updating or panel.committing or not box.dirty then return end
        box.dirty = false
        local entry = AnchorMode.selectedEntry
        local value = tonumber(box:GetText())
        if entry and value and value == value and math_abs(value) < math.huge and not InCombatLockdown() then
            if box.axis then
                ApplyEntrySize(entry, box.axis, value)
            else
                local x, y = entry.getOffsets()
                if box == panel.xBox then x = value else y = value end
                ApplyEntryOffsets(entry, x, y, true)
            end
        end
        UpdateNudgePanel()
    end

    local function OnEnterPressed(self)
        CommitBox(self)
        panel.committing = true
        self:ClearFocus()
        panel.committing = false
        UpdateNudgePanel()
    end

    local function OnEscapePressed(self)
        self.dirty = false
        self:ClearFocus()
        UpdateNudgePanel()
    end

    for _, box in ipairs(panel.boxes) do
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput and not panel.updating then self.dirty = true end
        end)
        box:SetScript("OnEnterPressed", OnEnterPressed)
        box:SetScript("OnEscapePressed", OnEscapePressed)
        box:SetScript("OnEditFocusLost", CommitBox)
    end
    panel.widthBox:SetScript("OnEnter", function(self)
        local entry = AnchorMode.selectedEntry
        if not entry or not entry.autoWidth then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Width (0 = Auto)"])
        GameTooltip:AddLine(L["Automatic width shows its current size. Enter 0 to restore automatic width."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.widthBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel:Hide()
    nudgePanel = panel
    return panel
end

UpdateNudgePanel = function()
    local panel = nudgePanel
    if not panel then return end
    local entry = AnchorMode.selectedEntry
    panel.updating = true
    local function UpdateBox(box, value, enabled)
        -- Committing one field can refresh the panel after another gains focus.
        if box:HasFocus() then return end
        box:SetText(value)
        if enabled then box:Enable() else box:Disable() end
    end
    for _, box in ipairs(panel.sizeBoxes) do
        if entry and entry.readSize then
            local value = entry.readSize(box.axis)
            UpdateBox(box, value and math_floor(value + 0.5) or L["Mixed"], true)
        else
            UpdateBox(box, "--", false)
        end
    end
    local function SetSteppersEnabled(steppers, enabled)
        for _, stepper in ipairs(steppers) do
            stepper:SetEnabled(enabled)
            stepper:SetAlpha(enabled and 1 or 0.35)
        end
    end
    SetSteppersEnabled(panel.sizeSteppers, entry and entry.readSize and true or false)
    SetSteppersEnabled(panel.offsetSteppers, entry and true or false)

    local anchor = entry and entry.anchor
    local dropdown = panel.anchorDropdown
    if anchor then
        local value = anchor.get()
        dropdown:SetDefaultText(UI.GetOptionLabel(GetAnchorOptions(anchor), value, value))
    else
        dropdown:SetDefaultText("--")
    end
    dropdown:SetEnabled(anchor and true or false)
    -- Regenerate so the shown selection follows the newly selected entry.
    dropdown:GenerateMenu()
    if entry then
        local x, y = entry.getOffsets()
        panel.selected:SetText(entry.label)
        UpdateBox(panel.xBox, math_floor((x or 0) + 0.5), true)
        UpdateBox(panel.yBox, math_floor((y or 0) + 0.5), true)
    else
        panel.selected:SetText(L["Select Anchor"])
        UpdateBox(panel.xBox, "--", false)
        UpdateBox(panel.yBox, "--", false)
    end
    panel.updating = false
end

local function CreateOverlay(entry)
    local overlay = CreateFrame("Frame", nil, overlayHost, "BackdropTemplate")
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    overlay:SetBackdropColor(OVERLAY_COLOR[1], OVERLAY_COLOR[2], OVERLAY_COLOR[3], OVERLAY_COLOR[4])
    overlay:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
    overlay.entry = entry
    overlay.isHovered = false
    UpdateOverlayBounds(overlay)
    overlay:SetFrameLevel(overlayHost:GetFrameLevel() + 1)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    local label = overlay:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    label:SetPoint("CENTER")
    label:SetText(entry.label)
    label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    label:SetShadowOffset(1, -1)

    overlay:SetScript("OnDragStart", StartDrag)
    overlay:SetScript("OnDragStop", StopDrag)
    overlay:SetScript("OnEnter", function(self)
        self.isHovered = true
        self:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    overlay:SetScript("OnLeave", function(self)
        self.isHovered = false
        if AnchorMode.selectedEntry == self.entry then
            self:SetBackdropBorderColor(1, 1, 1, 1)
        else
            self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
        end
    end)
    overlay:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then SelectEntry(self.entry) end
    end)
    return overlay
end

local function ClearOverlays()
    for _, overlay in ipairs(AnchorMode.overlays) do
        overlay:Hide()
        overlay:SetParent(nil)
    end
    for i = #AnchorMode.overlays, 1, -1 do
        AnchorMode.overlays[i] = nil
    end
end

local function PopulateEntries(selectKey)
    BuildEntries()
    for _, entry in ipairs(AnchorMode.entries) do
        AnchorMode.overlays[#AnchorMode.overlays + 1] = CreateOverlay(entry)
        if selectKey and entry.key == selectKey then
            AnchorMode.selectedEntry = entry
        end
    end
    RefreshOverlaySelection()
    UpdateNudgePanel()
end

RebuildEntries = function(selectKey)
    if AnchorMode.entryTimer then AnchorMode.entryTimer:Cancel() end
    ClearOverlays()
    AnchorMode.selectedEntry = nil
    UpdateNudgePanel()
    -- Measure bounds after the refreshed layout has been applied.
    AnchorMode.entryTimer = C_Timer.NewTimer(0, function()
        AnchorMode.entryTimer = nil
        if not AnchorMode.active or InCombatLockdown() then return end
        PopulateEntries(selectKey)
    end)
end

function AnchorMode:Enter(button)
    if self.active then return end
    if InCombatLockdown() then
        PrintMessage(L["Cannot unlock anchors during combat."])
        return
    end

    self.active = true
    self.button = button
    if CDM.SetAnchorModeActive then
        CDM:SetAnchorModeActive(true)
    end
    local settings = _G.CooldownViewerSettings
    if settings and not settings:IsShown() then
        self.openedSettings = settings
        securecall("ShowUIPanel", settings)
    end
    -- Blizzard populates inactive buff previews when its settings open. Wait
    -- for those frames and CDM's layout before capturing anchor bounds.
    self.entryTimer = C_Timer.NewTimer(0, function()
        self.entryTimer = nil
        if not self.active or InCombatLockdown() then return end
        CDM:Refresh("LAYOUT")
        self.entryTimer = C_Timer.NewTimer(0, function()
            self.entryTimer = nil
            if not self.active or InCombatLockdown() then return end
            PopulateEntries()
        end)
    end)
    BuildGrid()
    self.selectedEntry = nil
    self.anchorChanged = false
    local panel = CreateNudgePanel()
    CreateAnchorBanner():Show()
    UpdateNudgePanel()
    panel:Show()
    keyboardHandler:SetPropagateKeyboardInput(true)
    keyboardHandler:Show()
    grid:Show()
    overlayHost:Show()
    anchorRefreshElapsed = 0
    anchorRefreshFrame:Show()
    if button then button:LockHighlight() end
end

function AnchorMode:Exit(reopenConfig)
    if not self.active then return end
    if nudgePanel then
        for _, box in ipairs(nudgePanel.boxes) do box:ClearFocus() end
    end
    self.active = false
    if self.entryTimer then
        self.entryTimer:Cancel()
        self.entryTimer = nil
    end
    if dragging then
        CommitDrag(not InCombatLockdown())
    else
        dragFrame:Hide()
    end
    grid:Hide()
    overlayHost:Hide()
    anchorRefreshFrame:Hide()
    keyboardHandler:Hide()
    keyboardHandler:SetPropagateKeyboardInput(true)
    if nudgePanel then nudgePanel:Hide() end
    if anchorBanner then anchorBanner:Hide() end
    self.selectedEntry = nil
    ClearOverlays()
    if CDM.SetAnchorModeActive then
        CDM:SetAnchorModeActive(false)
    end
    if self.button then self.button:UnlockHighlight() end
    self.button = nil
    if self.openedSettings and not InCombatLockdown() then
        securecall("HideUIPanel", self.openedSettings)
        self.openedSettings = nil
    end
    if reopenConfig and not InCombatLockdown() and CDM.API and CDM.API.ShowConfig then
        if self.anchorChanged and CDM.API.RebuildConfigFrame then
            -- Open pages still show the old anchor controls.
            CDM.API:RebuildConfigFrame(ns.GetCurrentConfigTab and ns.GetCurrentConfigTab())
        else
            CDM.API:ShowConfig()
        end
    end
    self.anchorChanged = false
end

function ns.ToggleAnchorMode(button)
    if AnchorMode.active then
        AnchorMode:Exit(true)
    else
        AnchorMode:Enter(button)
    end
end

function ns.IsAnchorModeActive()
    return AnchorMode.active
end

function ns.CloseAnchorMode(reopenConfig)
    AnchorMode:Exit(reopenConfig)
end

CDM:RegisterCombatStateHandler(function(isInCombat)
    if isInCombat then
        if AnchorMode.active then
            PrintMessage(L["Anchors closed because combat started."])
            AnchorMode:Exit(false)
        end
    else
        if AnchorMode.openedSettings then
            securecall("HideUIPanel", AnchorMode.openedSettings)
            AnchorMode.openedSettings = nil
        end
        if pendingCombatRefresh then
            pendingCombatRefresh = false
            CDM:Refresh("LAYOUT")
            CDM:Refresh("RESOURCES")
            CDM:Refresh("BUFF_DATA")
        end
    end
end)
