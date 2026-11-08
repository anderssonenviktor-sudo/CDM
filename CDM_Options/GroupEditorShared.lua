local Runtime = _G["CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM_C = Runtime and Runtime.CONST or {}
local UI = ns.ConfigUI
local L = Runtime.L

ns.GroupEditorShared = ns.GroupEditorShared or {}
local Shared = ns.GroupEditorShared

local EMPTY_KEYS = {}
local CLASS_LIST = {}
local CLASS_SPECS = {}

for i = 1, GetNumClasses() do
    local className, classTag, classID = GetClassInfo(i)
    if classTag then
        local color = RAID_CLASS_COLORS[classTag]
        CLASS_LIST[#CLASS_LIST + 1] = {
            classTag = classTag,
            className = className,
            classID = classID,
            r = color and color.r or 1,
            g = color and color.g or 1,
            b = color and color.b or 1,
        }
        local specs = {}
        for j = 1, GetNumSpecializationsForClassID(classID) do
            local specID, specName = GetSpecializationInfoForClassID(classID, j)
            if specID then
                specs[#specs + 1] = { specID = specID, specName = specName }
            end
        end
        CLASS_SPECS[classTag] = specs
    end
end

table.sort(CLASS_LIST, function(a, b) return a.className < b.className end)

function Shared.GetClassCatalog()
    return CLASS_LIST, CLASS_SPECS
end

Shared.GROW_OPTIONS = {
    { label = "Right", value = "RIGHT" },
    { label = "Left", value = "LEFT" },
    { label = "Up", value = "UP" },
    { label = "Down", value = "DOWN" },
    { label = "Center Horizontal", value = "CENTER_H" },
    { label = "Center Vertical", value = "CENTER_V" },
}

function Shared.GetGrowLabel(growValue)
    return UI.GetOptionLabel(Shared.GROW_OPTIONS, growValue, growValue or "RIGHT")
end

function Shared.IsUsableSpellID(spellID)
    return API.IsSafeNumber(spellID) and spellID > 0 and spellID == math.floor(spellID)
end

function Shared.GetDisplaySpellID(spellID)
    if C_Spell.GetSpellTexture(spellID) then return spellID end
    local base = API.NormalizeToBase and API.NormalizeToBase(spellID)
    if base and base ~= spellID then return base end
    return spellID
end

function Shared.GetUniqueGroupName(groups, baseName)
    if not groups then return baseName end
    local nameSet = {}
    for _, group in ipairs(groups) do
        if group.name then
            nameSet[group.name] = true
        end
    end
    if not nameSet[baseName] then return baseName end
    for i = 1, 99 do
        local candidate = baseName .. " (" .. i .. ")"
        if not nameSet[candidate] then
            return candidate
        end
    end
    return baseName .. " (" .. time() .. ")"
end

local function AreEquivalentSpellIDs(leftSpellID, rightSpellID)
    if not Shared.IsUsableSpellID(leftSpellID) or not Shared.IsUsableSpellID(rightSpellID) then
        return false
    end
    return leftSpellID == rightSpellID
end

function Shared.MarkEquivalentSpellIDs(targetSet, spellID)
    if type(targetSet) ~= "table" or not Shared.IsUsableSpellID(spellID) then return end
    targetSet[spellID] = true
end

function Shared.HasEquivalentSpellID(targetSet, spellID)
    if type(targetSet) ~= "table" or not Shared.IsUsableSpellID(spellID) then
        return false
    end
    return targetSet[spellID] or false
end

function Shared.RemoveSpellFromGroupList(spellList, spellID)
    if type(spellList) ~= "table" or not Shared.IsUsableSpellID(spellID) then
        return nil
    end
    for i = #spellList, 1, -1 do
        if AreEquivalentSpellIDs(spellList[i], spellID) then
            return table.remove(spellList, i)
        end
    end
    return nil
end

function Shared.AddSpellToGroupList(spellList, spellID)
    if type(spellList) ~= "table" or not Shared.IsUsableSpellID(spellID) then
        return nil
    end
    Shared.RemoveSpellFromGroupList(spellList, spellID)
    spellList[#spellList + 1] = spellID
    return spellID
end

function Shared.InsertSpellInGroupList(spellList, spellID, insertIndex)
    if type(spellList) ~= "table" or not Shared.IsUsableSpellID(spellID) then
        return nil
    end
    local previousIndex
    for i = #spellList, 1, -1 do
        if AreEquivalentSpellIDs(spellList[i], spellID) then
            previousIndex = i
            table.remove(spellList, i)
            break
        end
    end
    insertIndex = tonumber(insertIndex) or (#spellList + 1)
    if previousIndex and previousIndex < insertIndex then
        insertIndex = insertIndex - 1
    end
    insertIndex = math.max(1, math.min(insertIndex, #spellList + 1))
    table.insert(spellList, insertIndex, spellID)
    return spellID
end

local function GetOverrideStorageKey(spellID, normalizeToBase)
    if API.GetBuffOverrideStorageKey then
        return API:GetBuffOverrideStorageKey(spellID)
    end
    if not Shared.IsUsableSpellID(spellID) then
        return nil
    end
    local baseID = normalizeToBase and normalizeToBase(spellID)
    return Shared.IsUsableSpellID(baseID) and baseID or spellID
end

function Shared.EnsureResolvedOverrideEntry(overrideMap, spellID, normalizeToBase)
    if type(overrideMap) ~= "table" or not Shared.IsUsableSpellID(spellID) then
        return nil
    end
    if API.EnsureBuffOverrideEntry then
        return API:EnsureBuffOverrideEntry(overrideMap, spellID)
    end
    local storageKey = GetOverrideStorageKey(spellID, normalizeToBase)
    if not Shared.IsUsableSpellID(storageKey) then
        return nil
    end
    if type(overrideMap[storageKey]) ~= "table" then
        overrideMap[storageKey] = {}
    end
    return overrideMap[storageKey]
end

function Shared.GetMergedOverrideEntry(overrideMap, spellID)
    if API.GetMergedBuffOverrideEntry then
        return API:GetMergedBuffOverrideEntry(overrideMap, spellID)
    end
    return nil
end

function Shared.ExtractMergedOverrideEntry(overrideMap, spellID)
    if API.ExtractMergedBuffOverrideEntry then
        return API:ExtractMergedBuffOverrideEntry(overrideMap, spellID)
    end
    return nil
end

function Shared.StoreMergedOverrideEntry(overrideMap, spellID, incoming, normalizeToBase)
    if type(overrideMap) ~= "table" or type(incoming) ~= "table" or not Shared.IsUsableSpellID(spellID) then
        return
    end
    if API.StoreMergedBuffOverrideEntry then
        API:StoreMergedBuffOverrideEntry(overrideMap, spellID, incoming)
        return
    end
    local storageKey = GetOverrideStorageKey(spellID, normalizeToBase)
    if Shared.IsUsableSpellID(storageKey) then
        overrideMap[storageKey] = incoming
    end
end

function Shared.CreateRightPanelManager(rightPanel, placeholder, destroyFrame)
    local rightContentFrame = nil
    local rightScrollFrame = nil
    local rightPanelDropdowns = {}

    local function CloseDropdownMenus()
        if UI and UI.CloseAllDropdownMenus then
            UI.CloseAllDropdownMenus()
        end
        for _, dropdown in ipairs(rightPanelDropdowns) do
            if dropdown and dropdown.CloseMenu then
                dropdown:CloseMenu()
            end
        end
    end

    local function Reset(showPlaceholder)
        CloseDropdownMenus()
        table.wipe(rightPanelDropdowns)
        if rightContentFrame then
            destroyFrame(rightContentFrame)
            rightContentFrame = nil
        end
        if rightScrollFrame then
            destroyFrame(rightScrollFrame)
            rightScrollFrame = nil
        end
        placeholder:SetShown(showPlaceholder)
    end

    return {
        RegisterDropdown = function(dropdown)
            if dropdown then
                rightPanelDropdowns[#rightPanelDropdowns + 1] = dropdown
            end
            return dropdown
        end,
        CreateScrollContent = function(minHeight, reuseContent)
            -- Opt-in callers build inside child frames and keep the scroll geometry intact.
            if reuseContent and rightScrollFrame and rightContentFrame then
                CloseDropdownMenus()
                table.wipe(rightPanelDropdowns)
                UI.ClearChildren(rightContentFrame)
                return rightScrollFrame, rightContentFrame
            end
            Reset(false)

            local sf = CreateFrame("ScrollFrame", nil, rightPanel, "ScrollFrameTemplate")
            UI.StyleScrollBar(sf)
            sf:SetAllPoints()
            sf:Show()
            sf:HookScript("OnVerticalScroll", CloseDropdownMenus)
            sf:HookScript("OnHide", CloseDropdownMenus)
            rightScrollFrame = sf

            local rc = CreateFrame("Frame", nil, sf)
            rc:SetWidth(sf:GetWidth() > 0 and sf:GetWidth() - 20 or 400)
            rc:SetHeight(minHeight or 400)
            sf:SetScrollChild(rc)
            -- Tabs can be built before their anchored width is available.
            local function UpdateContentWidth()
                local width = sf:GetWidth()
                if width > 20 then
                    rc:SetWidth(width - 20)
                end
            end
            sf:HookScript("OnSizeChanged", UpdateContentWidth)
            sf:HookScript("OnShow", UpdateContentWidth)
            UpdateContentWidth()
            rc:Show()
            rightContentFrame = rc
            return sf, rc
        end,
        Clear = function()
            Reset(true)
        end,
        CloseDropdownMenus = CloseDropdownMenus,
    }
end

function Shared.CreateDragDropController(config)
    local dragState = {
        active = false,
        spellID = nil,
        sourceGroup = nil,
        dragFrame = nil,
    }
    local dropTargets = {}
    local dragFrameCache = nil
    local insertMarker = nil

    local function HideInsertMarker()
        if insertMarker then insertMarker:Hide() end
    end

    local function HideHighlights()
        for _, target in ipairs(dropTargets) do
            if target.frame.highlight then
                target.frame.highlight:Hide()
            end
        end
        HideInsertMarker()
    end

    local function GetOrCreateInsertMarker()
        if insertMarker then return insertMarker end
        insertMarker = CreateFrame("Frame", nil, UIParent)
        insertMarker:SetHeight(2)
        insertMarker:SetFrameStrata("TOOLTIP")
        local line = insertMarker:CreateTexture(nil, "OVERLAY")
        line:SetAllPoints()
        line:SetColorTexture(1, 0.82, 0, 1)
        insertMarker.line = line
        local left = insertMarker:CreateTexture(nil, "OVERLAY")
        left:SetSize(6, 6)
        left:SetPoint("CENTER", insertMarker, "LEFT")
        left:SetColorTexture(1, 0.82, 0, 1)
        insertMarker.firstCap = left
        local right = insertMarker:CreateTexture(nil, "OVERLAY")
        right:SetSize(6, 6)
        right:SetPoint("CENTER", insertMarker, "RIGHT")
        right:SetColorTexture(1, 0.82, 0, 1)
        insertMarker.secondCap = right
        return insertMarker
    end

    local function FindHoveredTarget()
        local fallback
        local insertionFallback
        local hasHorizontalTargets = false
        for _, target in ipairs(dropTargets) do
            local isValid = not target.canDrop
                or target.canDrop(dragState.spellID, dragState.sourceGroup)
            if isValid and target.frame:IsMouseOver() then
                if (target.splitInsertion or target.horizontalInsertion) and target.insertIndex then
                    local cursorX, cursorY = GetCursorPosition()
                    local centerX, centerY = target.frame:GetCenter()
                    local before
                    if target.horizontalInsertion then
                        before = (cursorX / UIParent:GetEffectiveScale()) < (centerX or 0)
                    else
                        before = (cursorY / UIParent:GetEffectiveScale()) >= (centerY or 0)
                    end
                    target.resolvedInsertIndex = target.insertIndex + (before and 0 or 1)
                    target.markerAfter = not before
                    return target
                end
                if target.showInsertion and target.insertIndex then
                    insertionFallback = insertionFallback or target
                end
                fallback = fallback or target
            end
            if isValid and target.horizontalInsertion then
                hasHorizontalTargets = true
            end
        end

        -- Icon spacing is part of the horizontal drop lane. Resolve gaps to the
        -- nearest icon instead of treating them as an append-to-end drop.
        if fallback and hasHorizontalTargets then
            local cursorX, cursorY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cursorX, cursorY = cursorX / scale, cursorY / scale
            local nearest, nearestDistance
            for _, target in ipairs(dropTargets) do
                local isValid = not target.canDrop
                    or target.canDrop(dragState.spellID, dragState.sourceGroup)
                if isValid and target.highlightFrame == fallback.frame then
                    local centerX, centerY = target.frame:GetCenter()
                    local height = target.frame:GetHeight() or 0
                    if centerX and centerY and math.abs(cursorY - centerY) <= (height / 2 + 8) then
                        local distance = math.abs(cursorX - centerX)
                        if not nearestDistance or distance < nearestDistance then
                            nearest, nearestDistance = target, distance
                        end
                    end
                end
            end
            if nearest then
                local centerX = nearest.frame:GetCenter()
                local before = cursorX < (centerX or 0)
                nearest.resolvedInsertIndex = nearest.insertIndex + (before and 0 or 1)
                nearest.markerAfter = not before
                return nearest
            end
        end
        return insertionFallback or fallback
    end

    local function UpdateTargetVisuals(target)
        local highlightFrame = target and (target.highlightFrame or target.frame)
        for _, candidate in ipairs(dropTargets) do
            if candidate.frame.highlight then
                candidate.frame.highlight:SetShown(candidate.frame == highlightFrame)
            end
        end

        local label = target and target.label
        if type(label) == "function" then
            label = label(dragState.sourceGroup, dragState.spellID)
        end
        if dragFrameCache and dragFrameCache.destination then
            dragFrameCache.destination:SetText(label or "")
            dragFrameCache.destination:SetShown(label ~= nil)
        end

        if not target or not target.showInsertion then
            HideInsertMarker()
            return
        end

        local marker = GetOrCreateInsertMarker()
        marker:ClearAllPoints()
        marker.firstCap:ClearAllPoints()
        marker.secondCap:ClearAllPoints()
        if target.horizontalInsertion then
            marker:ClearAllPoints()
            marker:SetWidth(2)
            local point = target.markerAfter and "RIGHT" or "LEFT"
            marker:SetPoint("TOP", target.frame, "TOP" .. point, 0, 0)
            marker:SetPoint("BOTTOM", target.frame, "BOTTOM" .. point, 0, 0)
            marker.firstCap:SetPoint("CENTER", marker, "TOP")
            marker.secondCap:SetPoint("CENTER", marker, "BOTTOM")
        else
            marker:SetHeight(2)
            local point = target.markerAfter and "BOTTOM" or "TOP"
            marker:SetPoint("TOPLEFT", target.frame, point .. "LEFT", 0, 1)
            marker:SetPoint("TOPRIGHT", target.frame, point .. "RIGHT", 0, 1)
            marker.firstCap:SetPoint("CENTER", marker, "LEFT")
            marker.secondCap:SetPoint("CENTER", marker, "RIGHT")
        end
        marker:Show()
    end

    local function GetOrCreateDragFrame(spellID)
        if not dragFrameCache then
            dragFrameCache = CreateFrame("Frame", nil, UIParent)
            dragFrameCache:SetSize(28, 28)
            dragFrameCache:SetFrameStrata("TOOLTIP")
            local icon = dragFrameCache:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            dragFrameCache.icon = icon
            local destination = dragFrameCache:CreateFontString(nil, "OVERLAY", "CDM_Font12")
            destination:SetPoint("TOPLEFT", dragFrameCache, "BOTTOMRIGHT", 6, -3)
            destination:SetJustifyH("LEFT")
            destination:SetTextColor(1, 0.82, 0)
            destination:SetShadowColor(0, 0, 0, 1)
            destination:SetShadowOffset(1, -1)
            dragFrameCache.destination = destination
            dragFrameCache:SetAlpha(0.8)
        end
        local tex
        local trinketSlot = CDM_C.GetTrinketSlotFromSentinel and CDM_C.GetTrinketSlotFromSentinel(spellID)
            or CDM_C.GetNativeTrinketSlotFromSentinel and CDM_C.GetNativeTrinketSlotFromSentinel(spellID)
        if trinketSlot then
            local itemID = GetInventoryItemID("player", trinketSlot)
            tex = itemID and C_Item.GetItemIconByID(itemID)
        else
            tex = C_Spell.GetSpellTexture(Shared.GetDisplaySpellID(spellID))
        end
        if tex then
            dragFrameCache.icon:SetTexture(tex)
        else
            dragFrameCache.icon:SetColorTexture(0.3, 0.3, 0.3)
        end
        CDM_C.ApplyIconTexCoord(dragFrameCache.icon, CDM_C.GetEffectiveZoomAmount())
        return dragFrameCache
    end

    return {
        RegisterDropTarget = function(frame, groupIndex, options)
            options = options or {}
            dropTargets[#dropTargets + 1] = {
                frame = frame,
                groupIndex = groupIndex,
                label = options.label,
                insertIndex = options.insertIndex,
                showInsertion = options.showInsertion,
                splitInsertion = options.splitInsertion,
                horizontalInsertion = options.horizontalInsertion,
                highlightFrame = options.highlightFrame,
                canDrop = options.canDrop,
            }
        end,
        ClearDropTargets = function()
            table.wipe(dropTargets)
        end,
        StartDrag = function(spellID, sourceGroup, sourceFrame)
            if dragState.active then return end
            dragState.active = true
            dragState.spellID = spellID
            dragState.sourceGroup = sourceGroup
            dragState.sourceFrame = sourceFrame
            if sourceFrame then
                dragState.sourceAlpha = sourceFrame:GetAlpha()
                sourceFrame:SetAlpha(0.35)
            end

            local df = GetOrCreateDragFrame(spellID)
            dragState.dragFrame = df
            df:Show()
            local cachedScale = UIParent:GetEffectiveScale()
            df:SetScript("OnUpdate", function()
                local x, y = GetCursorPosition()
                df:ClearAllPoints()
                df:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / cachedScale, y / cachedScale)
                UpdateTargetVisuals(FindHoveredTarget())
            end)
        end,
        EndDrag = function()
            if not dragState.active then return end

            local spellID = dragState.spellID
            local sourceGroup = dragState.sourceGroup

            if dragState.dragFrame then
                dragState.dragFrame:SetScript("OnUpdate", nil)
                dragState.dragFrame:Hide()
                dragState.dragFrame = nil
            end

            local target = FindHoveredTarget()
            local targetGroupIndex = target and target.groupIndex or nil
            local targetInsertIndex = target and (target.resolvedInsertIndex or target.insertIndex) or nil
            local hitDropTarget = target ~= nil

            HideHighlights()

            dragState.active = false
            dragState.spellID = nil
            dragState.sourceGroup = nil
            if dragState.sourceFrame then
                dragState.sourceFrame:SetAlpha(dragState.sourceAlpha or 1)
            end
            dragState.sourceFrame = nil
            dragState.sourceAlpha = nil

            if config and config.onDrop then
                config.onDrop(spellID, sourceGroup, targetGroupIndex, hitDropTarget, targetInsertIndex)
            end
        end,
        CancelDrag = function()
            if not dragState.active then return end
            if dragState.dragFrame then
                dragState.dragFrame:SetScript("OnUpdate", nil)
                dragState.dragFrame:Hide()
                dragState.dragFrame = nil
            end
            HideHighlights()
            if dragState.sourceFrame then
                dragState.sourceFrame:SetAlpha(dragState.sourceAlpha or 1)
            end
            dragState.active = false
            dragState.spellID = nil
            dragState.sourceGroup = nil
            dragState.sourceFrame = nil
            dragState.sourceAlpha = nil
        end,
    }
end

local HEADER_SCROLL_LEFT_PAD = 54
local GROUP_ROW_W = 226
local HEADER_GROUP_H = 28
local HEADER_DELETE_BTN_SIZE = 20
local HEADER_PREVIEW_MAX = 5
local HEADER_PREVIEW_SIZE = 16
local HEADER_PREVIEW_GAP = 2
local HEADER_CHEVRON_W = 24
-- Spell rows sit inside the card's 1px border so their selection fill can
-- span the full card width.
local SPELL_ROW_INSET = 1
local SPELL_ROW_PAD = 8
local SPELL_ROW_H = 32
local SPELL_ICON_SIZE = 28
local SELECTED_ACCENT_W = 2

-- Same surface and border values as UI.CreateTextButton, so the group list
-- matches the rest of the options window.
local CARD_BORDER_COLOR = { 0.25, 0.25, 0.28, 1 }
local HEADER_BG_COLOR = { 0.05, 0.05, 0.055, 0.95 }
local HEADER_BG_HOVER_COLOR = { 0.095, 0.095, 0.105, 0.95 }
local BODY_BG_COLOR = { 0.03, 0.03, 0.035, 0.9 }
local SELECTED_ACCENT_COLOR = { 1, 0.82, 0, 0.8 }
local SELECTED_ROW_BG_COLOR = { 1, 0.82, 0, 0.08 }
local DELETE_IDLE_COLOR = { 0.5, 0.5, 0.5, 1 }
local DELETE_HOVER_COLOR = { 1, 0.267, 0.267, 1 }

local function CreateEdges(frame, layer, sides)
    local edges = {}
    for _, side in ipairs(sides) do
        local tex = frame:CreateTexture(nil, layer)
        tex:SetColorTexture(unpack(CARD_BORDER_COLOR))
        if side == "TOP" or side == "BOTTOM" then
            tex:SetPoint(side .. "LEFT", 0, 0)
            tex:SetPoint(side .. "RIGHT", 0, 0)
            tex:SetHeight(1)
        else
            tex:SetPoint("TOP" .. side, 0, 0)
            tex:SetPoint("BOTTOM" .. side, 0, 0)
            tex:SetWidth(1)
        end
        edges[#edges + 1] = tex
    end
    return edges
end

local function CreateSelectedAccent(frame, inset)
    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", inset, -inset)
    accent:SetPoint("BOTTOMLEFT", inset, inset)
    accent:SetWidth(SELECTED_ACCENT_W)
    accent:SetColorTexture(unpack(SELECTED_ACCENT_COLOR))
    accent:Hide()
    return accent
end

-- Two rotated bars, matching the chevron drawn by UI.CreateDropdown.
local function CreateHeaderChevron(frame)
    local first = frame:CreateTexture(nil, "OVERLAY")
    local second = frame:CreateTexture(nil, "OVERLAY")
    first:SetSize(6, 1.5)
    second:SetSize(6, 1.5)
    local chevron = { first, second }
    function chevron.SetExpanded(expanded)
        first:ClearAllPoints()
        second:ClearAllPoints()
        if expanded then
            first:SetPoint("CENTER", frame, "CENTER", -2, 0)
            second:SetPoint("CENTER", frame, "CENTER", 2, 0)
            first:SetRotation(-math.pi / 4)
            second:SetRotation(math.pi / 4)
        else
            first:SetPoint("CENTER", frame, "CENTER", 0, 2)
            second:SetPoint("CENTER", frame, "CENTER", 0, -2)
            first:SetRotation(-math.pi / 4)
            second:SetRotation(math.pi / 4)
        end
    end
    function chevron.SetBrightness(value)
        first:SetColorTexture(value, value, value, 1)
        second:SetColorTexture(value, value, value, 1)
    end
    return chevron
end

Shared.GROUP_ROW_W = GROUP_ROW_W
Shared.GROUP_HEADER_H = HEADER_GROUP_H
Shared.GROUP_GAP = 8
Shared.SPELL_ROW_H = SPELL_ROW_H
Shared.SPELL_ROW_INSET = SPELL_ROW_INSET

-- Grey cross that turns red on hover, so destructive buttons stay out of the
-- way until the cursor is on them.
function Shared.StyleQuietDeleteButton(button, iconSize, tooltipText)
    local icon = UI.ApplyCrossIcon(button)
    icon:SetSize(iconSize, iconSize)
    icon:SetVertexColor(unpack(DELETE_IDLE_COLOR))
    button:SetScript("OnEnter", function(self)
        icon:SetVertexColor(unpack(DELETE_HOVER_COLOR))
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipText)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        icon:SetVertexColor(unpack(DELETE_IDLE_COLOR))
        if tooltipText then GameTooltip:Hide() end
    end)
    return icon
end

function Shared.CreateExpandableHeader(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(GROUP_ROW_W, HEADER_GROUP_H)

    -- `bg` spans the whole header; the rename box anchors its left edge to it.
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(HEADER_BG_COLOR))
    CreateEdges(row, "BORDER", { "TOP", "BOTTOM", "LEFT", "RIGHT" })
    local selectedAccent = CreateSelectedAccent(row, 1)

    local nameText = row:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)

    local expandBtn = CreateFrame("Button", nil, row)
    expandBtn:SetPoint("TOPRIGHT", 0, 0)
    expandBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    expandBtn:SetWidth(HEADER_CHEVRON_W)
    expandBtn:SetFrameLevel(row:GetFrameLevel() + 1)
    local chevron = CreateHeaderChevron(expandBtn)

    local selectBtn = CreateFrame("Button", nil, row)
    selectBtn:SetPoint("TOPLEFT", 0, 0)
    selectBtn:SetPoint("BOTTOMRIGHT", expandBtn, "BOTTOMLEFT", 0, 0)
    selectBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local deleteBtn = CreateFrame("Button", nil, row)
    deleteBtn:SetSize(HEADER_DELETE_BTN_SIZE, HEADER_DELETE_BTN_SIZE)
    deleteBtn:SetPoint("RIGHT", expandBtn, "LEFT", 0, 0)
    deleteBtn:SetFrameLevel(row:GetFrameLevel() + 2)
    Shared.StyleQuietDeleteButton(deleteBtn, 18, L["Delete Group"])

    local function UpdateHover()
        local hovered = row:IsMouseOver()
        bg:SetColorTexture(unpack(hovered and HEADER_BG_HOVER_COLOR or HEADER_BG_COLOR))
        chevron.SetBrightness(hovered and 1 or 0.75)
    end
    for _, child in ipairs({ selectBtn, expandBtn, deleteBtn }) do
        child:HookScript("OnEnter", UpdateHover)
        child:HookScript("OnLeave", UpdateHover)
    end
    row:HookScript("OnShow", UpdateHover)
    chevron.SetBrightness(0.75)

    local previews = {}
    for i = 1, HEADER_PREVIEW_MAX do
        local tex = row:CreateTexture(nil, "ARTWORK")
        tex:SetSize(HEADER_PREVIEW_SIZE, HEADER_PREVIEW_SIZE)
        if i == 1 then
            tex:SetPoint("RIGHT", deleteBtn, "LEFT", -4, 0)
        else
            tex:SetPoint("RIGHT", previews[i - 1], "LEFT", -HEADER_PREVIEW_GAP, 0)
        end
        tex:Hide()
        previews[i] = tex
    end

    return {
        row = row,
        bgLeft = bg,
        nameText = nameText,
        deleteBtn = deleteBtn,
        selectBtn = selectBtn,
        expandBtn = expandBtn,
        chevron = chevron,
        previews = previews,
        selectedAccent = selectedAccent,
    }
end

-- previewTextures is only drawn while collapsed, so a closed group can still be
-- recognised by its first few icons.
function Shared.ConfigureExpandableHeader(header, yOff, isExpanded, displayName, isSelected, previewTextures)
    if not header then return end

    header.row:SetSize(GROUP_ROW_W, HEADER_GROUP_H)
    header.row:ClearAllPoints()
    header.row:SetPoint("TOPLEFT", HEADER_SCROLL_LEFT_PAD, yOff)
    header.chevron.SetExpanded(isExpanded)

    local shownPreviews = 0
    for i, tex in ipairs(header.previews) do
        local texture = not isExpanded and previewTextures and previewTextures[i]
        if texture then
            tex:SetTexture(texture)
            CDM_C.ApplyIconTexCoord(tex, CDM_C.GetEffectiveZoomAmount())
            tex:Show()
            shownPreviews = i
        else
            tex:SetTexture(nil)
            tex:Hide()
        end
    end

    header.nameText:ClearAllPoints()
    header.nameText:SetPoint("LEFT", header.bgLeft, "LEFT", 10, 0)
    local rightAnchor = shownPreviews > 0 and header.previews[shownPreviews] or header.deleteBtn
    header.nameText:SetPoint("RIGHT", rightAnchor, "LEFT", -6, 0)
    header.nameText:Show()
    header.nameText:SetText(displayName)
    if isSelected then
        UI.SetTextWhite(header.nameText)
    else
        UI.SetTextMuted(header.nameText)
    end

    header.selectedAccent:SetShown(isSelected and true or false)
    header.deleteBtn:Show()
    header.selectBtn:Show()
    header.expandBtn:Show()
end

function Shared.SetSpellRowSelected(widget, isSelected)
    widget.selectedBg:SetShown(isSelected and true or false)
    widget.selectedAccent:SetShown(isSelected and true or false)
end

function Shared.SetupRenameEditBox(headerRow, bgLeft, rightAnchor, nameText, currentName, onCommit, onCancel)
    nameText:Hide()
    local editBox = UI.CreateEditBox(headerRow)
    editBox:SetPoint("LEFT", bgLeft, "LEFT", 4, 0)
    editBox:SetPoint("RIGHT", rightAnchor, "LEFT", -4, 0)
    editBox:SetHeight(18)
    editBox:SetTextInsets(4, 4, 0, 0)
    editBox:SetText(currentName)
    editBox:SetAutoFocus(true)
    editBox:HighlightText()
    editBox:SetFrameLevel(headerRow:GetFrameLevel() + 3)

    local committed = false
    local function DoCommit(self)
        if committed then return end
        committed = true
        local newName = self:GetText()
        self:SetScript("OnEditFocusLost", nil)
        self:Hide()
        if newName and newName ~= "" then
            onCommit(newName)
        else
            onCancel()
        end
    end
    editBox:SetScript("OnEnterPressed", DoCommit)
    editBox:SetScript("OnEscapePressed", function(self)
        if committed then return end
        committed = true
        self:SetScript("OnEditFocusLost", nil)
        self:Hide()
        onCancel()
    end)
    editBox:SetScript("OnEditFocusLost", DoCommit)
    return editBox
end

function Shared.BuildGroupContextMenu(rootDescription, labels, onRename, onDuplicate, onCopyToSpec)
    rootDescription:CreateButton(labels.rename, onRename)
    rootDescription:CreateButton(labels.duplicate, onDuplicate)
    local copyMenu = rootDescription:CreateButton(labels.copyTo)
    for _, classInfo in ipairs(CLASS_LIST) do
        local color = RAID_CLASS_COLORS[classInfo.classTag]
        local coloredName = color and color:WrapTextInColorCode(classInfo.className) or classInfo.className
        local classMenu = copyMenu:CreateButton(coloredName)
        local specs = CLASS_SPECS[classInfo.classTag]
        if specs then
            for _, specInfo in ipairs(specs) do
                classMenu:CreateButton(specInfo.specName, function()
                    onCopyToSpec(specInfo.specID)
                end)
            end
        end
    end
end

function Shared.GetConfiguredBorderColor()
    if Runtime.GetConfiguredBorderColor then
        return Runtime.GetConfiguredBorderColor()
    end
    return 0, 0, 0, 1
end

function Shared.ApplyConfiguredBorderColor(borderFrame)
    if not (borderFrame and borderFrame.SetBackdropBorderColor) then return end
    local r, g, b, a = Shared.GetConfiguredBorderColor()
    borderFrame:SetBackdropBorderColor(r, g, b, a)
end

function Shared.RenderSpellPicker(config)
    local _, rc = config.createRightScrollContent(config.minHeight or 400)

    local header = rc:CreateFontString(nil, "ARTWORK", "CDM_Font18")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetText(config.headerText)
    header:SetTextColor(config.headerColor.r, config.headerColor.g, config.headerColor.b, 1)

    if config.isCacheMissing then
        local msg = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        msg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -20)
        msg:SetText(config.cacheMissingText)
        UI.SetTextMuted(msg)
    elseif #(config.spells or EMPTY_KEYS) == 0 then
        local msg = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        msg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -20)
        msg:SetText(config.emptyText)
        UI.SetTextMuted(msg)
    else
        local yOff = -34
        for _, entry in ipairs(config.spells) do
            local row = CreateFrame("Button", nil, rc)
            row:SetSize(300, 30)
            row:SetPoint("TOPLEFT", 0, yOff)

            local iconTex = row:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(24, 24)
            iconTex:SetPoint("LEFT", 0, 0)
            if entry.icon then
                iconTex:SetTexture(entry.icon)
            end

            local label = row:CreateFontString(nil, "OVERLAY", "CDM_Font14")
            label:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
            label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            label:SetJustifyH("LEFT")
            if config.currentSpecID == config.playerSpecID and entry.isKnown == false then
                label:SetTextColor(0.5, 0.5, 0.5, 1)
            end
            label:SetText(entry.name)

            local sid = entry.spellID
            local cdID = entry.cdID
            row:SetScript("OnClick", function()
                config.onSelect(sid, cdID)
            end)

            yOff = yOff - 30
        end

        rc:SetHeight(math.abs(yOff) + 10)
    end

    local doneBtn = UI.CreateTextButton(rc)
    doneBtn:SetSize(80, 22)
    doneBtn:SetPoint("TOPRIGHT", rc, "TOPRIGHT", 0, 0)
    doneBtn:SetText(config.doneText or "Back")
    doneBtn:SetScript("OnClick", config.onDone)

    return rc
end

Shared.LEFT_INSET = 35
Shared.LEFT_WIDTH = 240
Shared.SCROLL_LEFT_PAD = 54
Shared.RIGHT_X = 35 + 240 + 40
Shared.SLIDER_LABEL_W = 120
Shared.SLIDER_W = 200

-- Lines through the Add Group row out to the sidebar divider and panel border,
-- plus one down between the group list and the settings panel.
-- The Add Group button sits at LEFT_INSET, and buttonRow stops rowRightInset short of the page edge.
function Shared.CreateGroupEditorLines(page, buttonRow, addGroupBtn, rowRightInset)
    local edges = ns.ConfigContentEdges or { left = 0, right = 0 }

    local leftLine = buttonRow:CreateTexture(nil, "ARTWORK")
    UI.StyleBorderLine(leftLine)
    leftLine:SetPoint("LEFT", addGroupBtn, "LEFT", -(Shared.LEFT_INSET + edges.left), 0)
    leftLine:SetPoint("RIGHT", addGroupBtn, "LEFT", 0, 0)

    local rightLine = buttonRow:CreateTexture(nil, "ARTWORK")
    UI.StyleBorderLine(rightLine)
    rightLine:SetPoint("LEFT", addGroupBtn, "RIGHT", 0, 0)
    rightLine:SetPoint("RIGHT", buttonRow, "RIGHT", rowRightInset + edges.right, 0)

    -- Centered in the gap, which also keeps it clear of the list's scrollbar.
    local columnX = (Shared.LEFT_INSET + GROUP_ROW_W + Shared.RIGHT_X) / 2
    local columnLine = buttonRow:CreateTexture(nil, "ARTWORK")
    UI.StyleBorderLine(columnLine, true)
    columnLine:SetPoint("TOPLEFT", addGroupBtn, "LEFT", columnX - Shared.LEFT_INSET, 0)
    columnLine:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", columnX, 0)
end

function Shared.DestroyFrame(frame)
    if not frame then return end
    frame:Hide()
    frame:SetParent(nil)
end

function Shared.CreateSlider(parent, label, minVal, maxVal, currentVal, onChange)
    return UI.CreateModernSlider(parent, label, minVal, maxVal, currentVal, onChange, Shared.SLIDER_LABEL_W, Shared.SLIDER_W)
end

function Shared.SaveVisualRefresh(scope)
    API:Refresh(scope)
end

function Shared.BuildStackThresholdWidgets(rc, yOff, cfg)
    local ov = cfg.existingOv or {}
    local function write(key, value)
        local entry = cfg.ensureOv()
        if entry then entry[key] = value end
        cfg.save()
    end
    local function writeColor(key, r, g, b)
        write(key, { r = r, g = g, b = b })
    end

    local enabled = ov.stackTextThresholdEnabled == true
    local checkbox = UI.CreateModernCheckbox(rc, L["Charge color"], enabled, function(checked)
        write("stackTextThresholdEnabled", checked or nil)
        if cfg.onToggle then cfg.onToggle() end
    end)
    checkbox:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 30
    if enabled then
        local threshold = ov.stackTextThreshold or 2
        local label = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        label:SetPoint("TOPLEFT", 0, yOff)
        label:SetText(L["Condition:"] .. " " .. L[">="])
        local input = UI.CreateEditBox(rc)
        input:SetSize(60, 22)
        input:SetPoint("LEFT", label, "RIGHT", 12, 0)
        input:SetNumeric(true)
        input:SetMaxLetters(7)
        input:SetText(tostring(threshold))
        input:SetScript("OnEditFocusLost", function(self)
            local value = math.max(1, math.floor(tonumber(self:GetText()) or threshold))
            self:SetText(tostring(value))
            if value == threshold then return end
            threshold = value
            write("stackTextThreshold", value)
        end)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self)
            self:SetText(tostring(threshold))
            self:ClearFocus()
        end)
        yOff = yOff - 30
        local colorLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        colorLabel:SetPoint("TOPLEFT", 0, yOff)
        colorLabel:SetText(L["Threshold Color"])
        local picker = UI.CreateSimpleColorPicker(rc,
            ov.stackTextThresholdColor or { r = 1, g = 0, b = 0 },
            function(r, g, b) writeColor("stackTextThresholdColor", r, g, b) end, false)
        picker:SetPoint("LEFT", colorLabel, "RIGHT", 6, 0)
        yOff = yOff - 30
    end
    return yOff
end

function Shared.BuildTextOverrideWidgets(rc, yOff, cfg)
    local CreateSlider = Shared.CreateSlider
    local existingOv = cfg.existingOv
    local ensureOv = cfg.ensureOv
    local save = cfg.save
    local f = cfg.fields
    local d = cfg.defaults

    if cfg.showHeader then
        yOff = yOff - 10
        local ovHeader = rc:CreateFontString(nil, "ARTWORK", "CDM_Font18")
        ovHeader:SetPoint("TOPLEFT", 0, yOff)
        ovHeader:SetText(L["Text Overrides"])
        ovHeader:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
        yOff = yOff - 34
    end

    local useTextOv = existingOv and existingOv.textOverride
    local textOvCheckbox = UI.CreateModernCheckbox(rc,
        L["Override Text Settings"],
        useTextOv or false,
        function(checked)
            local ov = ensureOv()
            if not ov then return end
            ov.textOverride = checked or nil
            save()
            if cfg.onToggle then cfg.onToggle(checked) end
        end
    )
    textOvCheckbox:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 36

    if useTextOv then
        local ov = existingOv or {}
        local function write(key, value)
            local o = ensureOv()
            if o then
                o[key] = value
                -- The dropdown reads the merged snapshot, not the saved entry.
                ov[key] = value
            end
            save()
        end
        local function writeColor(key, r, g, b, a)
            local o = ensureOv()
            if o then o[key] = cfg.colorAlpha and { r = r, g = g, b = b, a = a or 1 } or { r = r, g = g, b = b } end
            save()
        end

        local cdFS = CreateSlider(rc, L["Cooldown Size"], 6, 32,
            ov[f.cdSize] or d[f.cdSize], function(v) write(f.cdSize, v) end)
        cdFS:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 50

        local cdColorLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        cdColorLabel:SetText(L["Cooldown Color"])
        cdColorLabel:SetPoint("TOPLEFT", 0, yOff)
        local cdColorPicker = UI.CreateSimpleColorPicker(rc,
            ov[f.cdColor] or d[f.cdColor] or { r = 1, g = 1, b = 1 },
            function(r, g, b, a) writeColor(f.cdColor, r, g, b, a) end,
            cfg.colorAlpha and true or false)
        cdColorPicker:SetPoint("LEFT", cdColorLabel, "RIGHT", 6, 0)
        yOff = yOff - 30

        local chargeFS = CreateSlider(rc, L["Charge Size"], 6, 32,
            ov[f.chargeSize] or d[f.chargeSize], function(v) write(f.chargeSize, v) end)
        chargeFS:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 50

        local chargeColorLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        chargeColorLabel:SetText(L["Charge Color"])
        chargeColorLabel:SetPoint("TOPLEFT", 0, yOff)
        local chargeColorPicker = UI.CreateSimpleColorPicker(rc,
            ov[f.chargeColor] or d[f.chargeColor] or { r = 1, g = 1, b = 1 },
            function(r, g, b, a) writeColor(f.chargeColor, r, g, b, a) end,
            cfg.colorAlpha and true or false)
        chargeColorPicker:SetPoint("LEFT", chargeColorLabel, "RIGHT", 6, 0)
        yOff = yOff - 30

        local posLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        posLabel:SetText(L["Position"])
        posLabel:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 22
        local posDropdown = cfg.createDropdown(rc)
        posDropdown:SetWidth(180)
        posDropdown:SetPoint("TOPLEFT", 0, yOff)
        posDropdown:SetDefaultText(ov[f.chargePos] or d[f.chargePos] or "BOTTOMRIGHT")
        UI.SetupPositionDropdown(posDropdown,
            function() return ov[f.chargePos] or d[f.chargePos] or "BOTTOMRIGHT" end,
            function(val) write(f.chargePos, val) end
        )
        yOff = yOff - 40

        local xSlider = CreateSlider(rc, L["X Offset"], -20, 20,
            ov[f.chargeX] or d[f.chargeX] or 0, function(v) write(f.chargeX, v) end)
        xSlider:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 50

        local ySlider = CreateSlider(rc, L["Y Offset"], -20, 20,
            ov[f.chargeY] or d[f.chargeY] or 0, function(v) write(f.chargeY, v) end)
        ySlider:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 50
    end

    return yOff
end

function Shared.CreateQueueLeftPanelRefresh(containerFrame, getRefreshAllFn)
    local queued = false
    return function(delay)
        if queued then return end
        queued = true
        C_Timer.After(delay or 0.1, function()
            queued = false
            if containerFrame:IsShown() and getRefreshAllFn() then
                getRefreshAllFn()()
            end
        end)
    end
end

local function ResolveWidgetRoot(widget)
    if type(widget) ~= "table" then
        return widget
    end
    return widget.root or widget.row or widget.frame
end

function Shared.CreateWidgetPool(factory, reset)
    local active = {}
    local inactive = {}

    local function ReleaseInternal(widget)
        if not widget then return end
        if reset then
            reset(widget)
        end
        local root = ResolveWidgetRoot(widget)
        if root then
            root:Hide()
            root:ClearAllPoints()
        end
        inactive[#inactive + 1] = widget
    end

    return {
        Acquire = function(_, parent)
            local widget = table.remove(inactive)
            if not widget then
                widget = factory(parent)
            end

            local root = ResolveWidgetRoot(widget)
            if root and root:GetParent() ~= parent then
                root:SetParent(parent)
            end
            if root then
                root:Show()
            end

            active[#active + 1] = widget
            return widget
        end,
        ReleaseAll = function(_)
            for i = #active, 1, -1 do
                local widget = active[i]
                active[i] = nil
                ReleaseInternal(widget)
            end
        end,
    }
end

function Shared.CreateViewerSettingsCallbacks(queueFn)
    local owners = {}
    local evRegistry = EventRegistry

    local function Register()
        if not (evRegistry and evRegistry.RegisterCallback) then return end
        if owners[1] then return end
        local o1, o2, o3, o4 = {}, {}, {}, {}
        owners[1], owners[2], owners[3], owners[4] = o1, o2, o3, o4
        evRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function() queueFn(0.2) end, o1)
        evRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function() queueFn(0.2) end, o2)
        evRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function() queueFn(0.2) end, o3)
        evRegistry:RegisterCallback("CooldownViewerSettings.OnPendingChanges", function() queueFn(0.3) end, o4)
    end

    local function Unregister()
        if not (evRegistry and evRegistry.UnregisterCallback) then return end
        if not owners[1] then return end
        evRegistry:UnregisterCallback("CooldownViewerSettings.OnShow", owners[1])
        evRegistry:UnregisterCallback("CooldownViewerSettings.OnHide", owners[2])
        evRegistry:UnregisterCallback("CooldownViewerSettings.OnDataChanged", owners[3])
        evRegistry:UnregisterCallback("CooldownViewerSettings.OnPendingChanges", owners[4])
        table.wipe(owners)
    end

    return Register, Unregister
end

function Shared.CreateGroupEditorPools(parent, config)
    local CDM = Runtime
    local iconSize = SPELL_ICON_SIZE
    local rowHeight = SPELL_ROW_H
    local highlightAlpha = config and config.highlightAlpha or 0.2
    local resetBorder = config and config.resetBorder

    local headerPool = Shared.CreateWidgetPool(function(p)
        local header = Shared.CreateExpandableHeader(p)
        header.root = header.row
        return header
    end, function(header)
        header.nameText:Show()
        header.selectBtn:SetScript("OnClick", nil)
        header.deleteBtn:SetScript("OnClick", nil)
        header.expandBtn:SetScript("OnClick", nil)
    end)

    local groupContainerPool = Shared.CreateWidgetPool(function(p)
        local gc = CreateFrame("Frame", nil, p)
        gc:SetSize(GROUP_ROW_W, 10)
        local bg = gc:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(unpack(BODY_BG_COLOR))
        -- No top edge: the header's bottom border closes the card.
        CreateEdges(gc, "BORDER", { "BOTTOM", "LEFT", "RIGHT" })
        local hl = CreateFrame("Frame", nil, gc, "BackdropTemplate")
        hl:SetAllPoints()
        hl:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        hl:SetBackdropBorderColor(1, 0.82, 0, math.max(0.65, highlightAlpha))
        hl:SetFrameLevel(gc:GetFrameLevel() + 3)
        hl:Hide()
        gc.highlight = hl
        return { root = gc, highlight = hl }
    end, function(widget)
        widget.highlight:Hide()
    end)

    local emptyRowPool = Shared.CreateWidgetPool(function(p)
        local f = CreateFrame("Frame", nil, p)
        f:SetSize(GROUP_ROW_W, rowHeight)
        local t = f:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        t:SetPoint("LEFT", SPELL_ROW_INSET + SPELL_ROW_PAD, 0)
        return { root = f, text = t }
    end, function(widget)
        widget.text:SetText("")
    end)

    local spellRowPool = Shared.CreateWidgetPool(function(p)
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(GROUP_ROW_W - SPELL_ROW_INSET * 2, rowHeight)

        local hoverBg = row:CreateTexture(nil, "BACKGROUND")
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(1, 1, 1, 0.04)
        hoverBg:Hide()
        local selectedBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        selectedBg:SetAllPoints()
        selectedBg:SetColorTexture(unpack(SELECTED_ROW_BG_COLOR))
        selectedBg:Hide()
        local selectedAccent = CreateSelectedAccent(row, 0)

        local iconContainer = CreateFrame("Frame", nil, row)
        iconContainer:SetSize(iconSize, iconSize)
        iconContainer:SetPoint("LEFT", SPELL_ROW_PAD, 0)
        local iconTex = iconContainer:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        CDM_C.ApplyIconTexCoord(iconTex, CDM_C.GetEffectiveZoomAmount())

        if CDM.BORDER and CDM.BORDER.CreateBorder then
            CDM.BORDER:CreateBorder(iconContainer)
            if CDM.BORDER.activeBorders then
                CDM.BORDER.activeBorders[iconContainer] = nil
            end
        end

        local removeBtn = CreateFrame("Button", nil, row)
        removeBtn:SetSize(16, 16)
        removeBtn:SetPoint("RIGHT", -6, 0)
        removeBtn:SetFrameLevel(row:GetFrameLevel() + 2)
        local removeBtnIcon = Shared.StyleQuietDeleteButton(removeBtn, 20, L["Remove from group"])

        local nameText = row:CreateFontString(nil, "OVERLAY", "CDM_Font12")
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)

        local clickBtn = CreateFrame("Button", nil, row)
        clickBtn:SetAllPoints()
        clickBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        clickBtn:RegisterForDrag("LeftButton")

        local function UpdateHover()
            hoverBg:SetShown(row:IsMouseOver())
        end
        for _, child in ipairs({ clickBtn, removeBtn }) do
            child:HookScript("OnEnter", UpdateHover)
            child:HookScript("OnLeave", UpdateHover)
        end
        row:HookScript("OnShow", UpdateHover)

        return {
            root = row,
            selectedBg = selectedBg,
            selectedAccent = selectedAccent,
            iconContainer = iconContainer,
            iconTex = iconTex,
            removeBtn = removeBtn,
            removeBtnIcon = removeBtnIcon,
            nameText = nameText,
            clickBtn = clickBtn,
        }
    end, function(widget)
        Shared.SetSpellRowSelected(widget, false)
        widget.removeBtn:Hide()
        widget.removeBtn:SetScript("OnClick", nil)
        widget.clickBtn:SetScript("OnClick", nil)
        widget.clickBtn:SetScript("OnDragStart", nil)
        widget.clickBtn:SetScript("OnDragStop", nil)
        widget.nameText:SetText("")
        widget.iconTex:SetTexture(nil)
        widget.iconTex:SetDesaturated(false)
        widget.iconTex:SetAlpha(1)
        if widget.iconContainer.border then
            widget.iconContainer.border:SetAlpha(1)
            if resetBorder then
                resetBorder(widget.iconContainer.border)
            end
        end
    end)

    return headerPool, groupContainerPool, emptyRowPool, spellRowPool
end

function Shared.AcquireEmptyRow(pool, parent, text)
    local widget = pool:Acquire(parent)
    widget.root:SetPoint("TOPLEFT", 0, 0)
    widget.text:SetText(text)
    UI.SetTextFaint(widget.text)
    return widget
end

function Shared.CreateGroupEditorHelpers(config)
    local CDM = Runtime
    local dbKey = config.dbKey
    local ungroupedDbKey = config.ungroupedDbKey
    local getCurrentSpecID = config.getCurrentSpecID
    local setCurrentSpecID = config.setCurrentSpecID
    local setPlayerSpecID = config.setPlayerSpecID
    local normalizeToBase = config.normalizeToBase
    local extraCloneFields = config.extraCloneFields

    local function RefreshCurrentSpecID()
        local si = GetSpecialization()
        local newPlayerSpec = si and GetSpecializationInfo(si) or nil
        setPlayerSpecID(newPlayerSpec)
        setCurrentSpecID(newPlayerSpec)
    end

    local function EnsureGroups()
        local specID = getCurrentSpecID()
        if not specID then return nil end
        if not CDM.db[dbKey] then CDM.db[dbKey] = {} end
        if not CDM.db[dbKey][specID] then CDM.db[dbKey][specID] = {} end
        return CDM.db[dbKey][specID]
    end

    local function GetSpecGroups()
        local specID = getCurrentSpecID()
        if not specID then return nil end
        local tbl = CDM.db[dbKey]
        return tbl and tbl[specID]
    end

    local function EnsureUngroupedOverrides()
        local specID = getCurrentSpecID()
        if not specID then return nil end
        if not CDM.db[ungroupedDbKey] then CDM.db[ungroupedDbKey] = {} end
        if not CDM.db[ungroupedDbKey][specID] then CDM.db[ungroupedDbKey][specID] = {} end
        return CDM.db[ungroupedDbKey][specID]
    end

    local function GetUngroupedOverride(spellID)
        local specID = getCurrentSpecID()
        if not specID then return nil end
        local specOv = CDM.db[ungroupedDbKey] and CDM.db[ungroupedDbKey][specID]
        return Shared.GetMergedOverrideEntry(specOv, spellID)
    end

    local function HelpersEnsureResolvedOverrideEntry(overrideMap, spellID)
        return Shared.EnsureResolvedOverrideEntry(overrideMap, spellID, normalizeToBase)
    end

    local function HelpersExtractMergedOverrideEntry(overrideMap, spellID)
        return Shared.ExtractMergedOverrideEntry(overrideMap, spellID)
    end

    local function HelpersStoreMergedOverrideEntry(overrideMap, spellID, incoming)
        Shared.StoreMergedOverrideEntry(overrideMap, spellID, incoming, normalizeToBase)
    end

    local function HelpersEnsureSpellOverride(groupIndex, spellID)
        local groups = GetSpecGroups()
        if not groups or not groups[groupIndex] then return nil end
        local gd = groups[groupIndex]
        if not gd.spellOverrides then gd.spellOverrides = {} end
        return HelpersEnsureResolvedOverrideEntry(gd.spellOverrides, spellID)
    end

    local function HelpersEnsureUngroupedOverrideEntry(spellID)
        local specOv = EnsureUngroupedOverrides()
        if not specOv then return nil end
        return HelpersEnsureResolvedOverrideEntry(specOv, spellID)
    end

    local function HelpersCreateLayoutOnlyGroupClone(groups, groupData)
        local clone = {
            name = Shared.GetUniqueGroupName(groups, groupData.name or "Group"),
            spells = {},
            grow = groupData.grow,
            spacing = groupData.spacing,
            iconWidth = groupData.iconWidth,
            iconHeight = groupData.iconHeight,
            cooldownFontSize = groupData.cooldownFontSize,
            anchorTarget = groupData.anchorTarget,
            anchorPoint = groupData.anchorPoint,
            anchorRelativeTo = groupData.anchorRelativeTo,
            offsetX = groupData.offsetX,
            offsetY = groupData.offsetY,
        }
        if groupData.cooldownColor then
            clone.cooldownColor = { r = groupData.cooldownColor.r, g = groupData.cooldownColor.g, b = groupData.cooldownColor.b, a = groupData.cooldownColor.a }
        end
        if extraCloneFields then
            for _, key in ipairs(extraCloneFields) do
                local val = groupData[key]
                if type(val) == "table" and val.r ~= nil then
                    clone[key] = { r = val.r, g = val.g, b = val.b, a = val.a }
                else
                    clone[key] = val
                end
            end
        end
        return clone
    end

    local function HelpersCopyGroupSettingsToSpec(groupData, targetSpecID)
        if not CDM.db[dbKey] then CDM.db[dbKey] = {} end
        if not CDM.db[dbKey][targetSpecID] then CDM.db[dbKey][targetSpecID] = {} end
        local targetGroups = CDM.db[dbKey][targetSpecID]
        targetGroups[#targetGroups + 1] = HelpersCreateLayoutOnlyGroupClone(targetGroups, groupData)
    end

    local function HelpersDuplicateGroup(groupData, specGroups)
        specGroups[#specGroups + 1] = HelpersCreateLayoutOnlyGroupClone(specGroups, groupData)
        return #specGroups
    end

    return {
        RefreshCurrentSpecID = RefreshCurrentSpecID,
        EnsureGroups = EnsureGroups,
        GetSpecGroups = GetSpecGroups,
        EnsureUngroupedOverrides = EnsureUngroupedOverrides,
        GetUngroupedOverride = GetUngroupedOverride,
        EnsureResolvedOverrideEntry = HelpersEnsureResolvedOverrideEntry,
        ExtractMergedOverrideEntry = HelpersExtractMergedOverrideEntry,
        StoreMergedOverrideEntry = HelpersStoreMergedOverrideEntry,
        EnsureSpellOverride = HelpersEnsureSpellOverride,
        EnsureUngroupedOverrideEntry = HelpersEnsureUngroupedOverrideEntry,
        CreateLayoutOnlyGroupClone = HelpersCreateLayoutOnlyGroupClone,
        CopyGroupSettingsToSpec = HelpersCopyGroupSettingsToSpec,
        DuplicateGroup = HelpersDuplicateGroup,
    }
end

function Shared.RenderGroupSettingsPanel(config)
    local rc = config.rc
    local gd = config.gd
    local groupIndex = config.groupIndex
    local registerDropdown = config.registerDropdown
    local save = config.saveAndRefresh
    local slider = config.createSlider
    local L = config.L
    local tf = config.textFields
    local yOff = 0

    local nameHeader = rc:CreateFontString(nil, "ARTWORK", "CDM_Font18")
    nameHeader:SetPoint("TOPLEFT", 0, yOff)
    nameHeader:SetText(gd.name or ("Group " .. groupIndex))
    nameHeader:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
    yOff = yOff - 34

    local growLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    growLabel:SetText(L["Grow Direction"])
    growLabel:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 22

    local growDropdown = registerDropdown(UI.CreateDropdown(rc))
    growDropdown:SetWidth(180)
    growDropdown:SetPoint("TOPLEFT", 0, yOff)
    growDropdown:SetDefaultText(Shared.GetGrowLabel(gd.grow or "RIGHT"))
    UI.SetupValueDropdown(growDropdown, Shared.GROW_OPTIONS,
        function() return gd.grow or "RIGHT" end,
        function(val) gd.grow = val; save() end
    )
    yOff = yOff - 40

    if config.preSpacingSection then
        yOff = config.preSpacingSection(rc, yOff)
    end

    local spacingSlider = slider(rc, L["Spacing"], -1, 50, gd.spacing or 4, function(v)
        gd.spacing = v; save()
    end)
    spacingSlider:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local widthSlider = slider(rc, L["Icon Width"], 16, 100, gd.iconWidth or 30, function(v)
        gd.iconWidth = v; save()
    end)
    widthSlider:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local heightSlider = slider(rc, L["Icon Height"], 16, 100, gd.iconHeight or 30, function(v)
        gd.iconHeight = v; save()
    end)
    heightSlider:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    if config.postSizeSection then
        yOff = config.postSizeSection(rc, yOff)
    end

    yOff = yOff - 10
    local textHeader = rc:CreateFontString(nil, "ARTWORK", "CDM_Font18")
    textHeader:SetPoint("TOPLEFT", 0, yOff)
    textHeader:SetText(L["Text"])
    textHeader:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
    yOff = yOff - 34

    local cdFSSlider = slider(rc, L["Cooldown Size"], 6, 32, gd.cooldownFontSize or 12, function(v)
        gd.cooldownFontSize = v; save()
    end)
    cdFSSlider:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local cdColorLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    cdColorLabel:SetText(L["Color"])
    cdColorLabel:SetPoint("TOPLEFT", 0, yOff)
    local cdColorInit = gd.cooldownColor or { r = 1, g = 1, b = 1 }
    local cdColorPicker = UI.CreateSimpleColorPicker(rc, cdColorInit, function(r, g, b, a)
        if not gd.cooldownColor then gd.cooldownColor = { r = 1, g = 1, b = 1, a = 1 } end
        gd.cooldownColor.r, gd.cooldownColor.g, gd.cooldownColor.b = r, g, b
        gd.cooldownColor.a = a or 1
        save()
    end, true)
    cdColorPicker:SetPoint("LEFT", cdColorLabel, "RIGHT", 6, 0)
    yOff = yOff - 30

    local secFSSlider = slider(rc, L["Charge Size"], 6, 32, gd[tf.sizeKey] or tf.sizeDefault, function(v)
        gd[tf.sizeKey] = v; save()
    end)
    secFSSlider:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local secColorLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    secColorLabel:SetText(L["Color"])
    secColorLabel:SetPoint("TOPLEFT", 0, yOff)
    local secColorInit = gd[tf.colorKey] or { r = 1, g = 1, b = 1 }
    local secColorPicker = UI.CreateSimpleColorPicker(rc, secColorInit, function(r, g, b, a)
        if not gd[tf.colorKey] then gd[tf.colorKey] = { r = 1, g = 1, b = 1, a = 1 } end
        gd[tf.colorKey].r, gd[tf.colorKey].g, gd[tf.colorKey].b = r, g, b
        gd[tf.colorKey].a = a or 1
        save()
    end, true)
    secColorPicker:SetPoint("LEFT", secColorLabel, "RIGHT", 6, 0)
    yOff = yOff - 30

    local secPosLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    secPosLabel:SetText(L["Position"])
    secPosLabel:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 22

    local secPosDropdown = registerDropdown(UI.CreateDropdown(rc))
    secPosDropdown:SetWidth(180)
    secPosDropdown:SetPoint("TOPLEFT", 0, yOff)
    secPosDropdown:SetDefaultText(gd[tf.posKey] or tf.posDefault)
    UI.SetupPositionDropdown(secPosDropdown,
        function() return gd[tf.posKey] or tf.posDefault end,
        function(val) gd[tf.posKey] = val; save() end
    )
    yOff = yOff - 40

    local secXSlider = slider(rc, L["X Offset"], -20, 20, gd[tf.xKey] or 0, function(v)
        gd[tf.xKey] = v; save()
    end)
    secXSlider:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local secYSlider = slider(rc, L["Y Offset"], -20, 20, gd[tf.yKey] or 0, function(v)
        gd[tf.yKey] = v; save()
    end)
    secYSlider:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    yOff = yOff - 10
    local anchorHeader = rc:CreateFontString(nil, "ARTWORK", "CDM_Font18")
    anchorHeader:SetPoint("TOPLEFT", 0, yOff)
    anchorHeader:SetText(L["Anchor"])
    anchorHeader:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
    yOff = yOff - 34

    local anchorTargetLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    anchorTargetLabel:SetText(L["Anchor To"])
    anchorTargetLabel:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 22

    local UpdateAnchorVisibility
    local xSlider, ySlider
    local anchorTargetDropdown = registerDropdown(UI.CreateDropdown(rc))
    anchorTargetDropdown:SetWidth(180)
    anchorTargetDropdown:SetPoint("TOPLEFT", 0, yOff)
    local currentTarget = gd.anchorTarget or "screen"
    local anchorTargets = config.anchorTargets
    local targetLabelMap = {}
    for _, entry in ipairs(anchorTargets) do
        targetLabelMap[entry.value] = entry.label
    end
    anchorTargetDropdown:SetDefaultText(targetLabelMap[currentTarget] or targetLabelMap.screen or "Screen")
    UI.SetupValueDropdown(anchorTargetDropdown, anchorTargets,
        function() return gd.anchorTarget or "screen" end,
        function(val)
            local prev = gd.anchorTarget or "screen"
            gd.anchorTarget = val
            gd.anchorPoint = gd.anchorPoint or "CENTER"
            gd.anchorRelativeTo = gd.anchorRelativeTo or "CENTER"
            if val ~= prev then
                gd.offsetX = 0
                gd.offsetY = 0
                xSlider:UpdateUIValue(0)
                ySlider:UpdateUIValue(0)
            end
            save()
            UpdateAnchorVisibility()
        end
    )
    yOff = yOff - 40
    local yAfterTarget = yOff

    local anchorLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    anchorLabel:SetText(L["Anchor Point"])
    anchorLabel:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 22

    local anchorDropdown = registerDropdown(UI.CreateDropdown(rc))
    anchorDropdown:SetWidth(180)
    anchorDropdown:SetPoint("TOPLEFT", 0, yOff)
    anchorDropdown:SetDefaultText(gd.anchorPoint or "CENTER")
    UI.SetupPositionDropdown(anchorDropdown,
        function() return gd.anchorPoint or "CENTER" end,
        function(val) gd.anchorPoint = val; save() end
    )
    yOff = yOff - 40

    local relLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    relLabel:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 22

    local relDropdown = registerDropdown(UI.CreateDropdown(rc))
    relDropdown:SetWidth(180)
    relDropdown:SetPoint("TOPLEFT", 0, yOff)
    relDropdown:SetDefaultText(gd.anchorRelativeTo or "CENTER")
    UI.SetupPositionDropdown(relDropdown,
        function() return gd.anchorRelativeTo or "CENTER" end,
        function(val) gd.anchorRelativeTo = val; save() end
    )
    yOff = yOff - 40
    local yAfterConditional = yOff

    xSlider = slider(rc, L["X Offset"], -840, 840, gd.offsetX or 0, function(v)
        gd.offsetX = v; save()
    end)
    xSlider:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    ySlider = slider(rc, L["Y Offset"], -470, 470, gd.offsetY or 0, function(v)
        gd.offsetY = v; save()
    end)
    ySlider:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local anchorRelLabels = config.anchorRelLabels or {}
    UpdateAnchorVisibility = function()
        local isScreen = (gd.anchorTarget or "screen") == "screen"
        anchorLabel:SetShown(not isScreen)
        anchorDropdown:SetShown(not isScreen)
        relLabel:SetShown(not isScreen)
        relDropdown:SetShown(not isScreen)
        if not isScreen then
            local target = gd.anchorTarget
            relLabel:SetText(anchorRelLabels[target] or (L["Essential Viewer Point"]))
            anchorDropdown:SetDefaultText(gd.anchorPoint or "CENTER")
            relDropdown:SetDefaultText(gd.anchorRelativeTo or "CENTER")
        end
        local sliderY = isScreen and yAfterTarget or yAfterConditional
        xSlider:ClearAllPoints(); xSlider:SetPoint("TOPLEFT", 0, sliderY)
        ySlider:ClearAllPoints(); ySlider:SetPoint("TOPLEFT", 0, sliderY - 50)
        rc:SetHeight(math.abs(sliderY - 100) + 20)
    end
    UpdateAnchorVisibility()
    return xSlider, ySlider
end
