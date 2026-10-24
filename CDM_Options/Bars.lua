local Runtime = _G["CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local L = Runtime.L
local CDM_C = CDM and CDM.CONST or {}
local UI = ns.ConfigUI
local Shared = ns.GroupEditorShared or {}
local M = CDM.BUFFBAR
local GetSpellTexture = C_Spell.GetSpellTexture
local GetSpellName = C_Spell.GetSpellName

local DestroyFrame = Shared.DestroyFrame

local PAGE_INSET = 12
local TOOLBAR_TOP = -12
local BROWSER_MAX_H = 172
local GROUP_TITLE_H = 22
local GROUP_GAP = 10
local ICON_SIZE = 32
local ICON_GAP = 2
local STRIP_PAD = 5

-- Two columns must fit a tab page minus the scroll bar (~635px usable).
local COL_GAP = 20
local COL_W = 300
local SLIDER_LABEL_W = 116
local SLIDER_W = 170

local function SaveAndRefresh()
    if CDM.InvalidateBuffBarEntries then CDM.InvalidateBuffBarEntries() end
    API:Refresh("BUFF_DATA", "STYLE", "LAYOUT")
end

local function CreateSlider(parent, label, minVal, maxVal, currentVal, onChange)
    return UI.CreateModernSlider(parent, label, minVal, maxVal, currentVal,
        onChange, SLIDER_LABEL_W, SLIDER_W)
end

StaticPopupDialogs["CDM_CONFIRM_DELETE_BARGROUP"] = {
    text = "",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local fn = StaticPopupDialogs["CDM_CONFIRM_DELETE_BARGROUP"]._pendingDelete
        StaticPopupDialogs["CDM_CONFIRM_DELETE_BARGROUP"]._pendingDelete = nil
        if fn then fn() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local BAR_TYPE_OPTIONS = {
    { value = M.TYPE_TIMER, label = L["Timer Bar"] },
    { value = M.TYPE_STACK, label = L["Stack Bar"] },
}

local ICON_POS_OPTIONS = {
    { value = "LEFT", label = L["Left"] },
    { value = "RIGHT", label = L["Right"] },
    { value = "HIDDEN", label = L["Hidden"] },
}

local GROW_OPTIONS = {
    { value = "DOWN", label = L["Down"] },
    { value = "UP", label = L["Up"] },
}

local function CreateBarsTab(page)
    local si = GetSpecialization()
    local currentSpecID = si and GetSpecializationInfo(si) or nil
    local currentDB = CDM.db

    -- Selection is either a group (by index) or a bar (by table identity --
    -- indices shift when bars move between groups).
    local selectedGroupIndex = nil
    local selectedBar = nil
    local selectedBarGroupIndex = nil
    local browserGroupIndex = nil
    -- Which sub-tab the bar settings panel is showing. Persisted across the
    -- rebuilds that a setting change triggers, so toggling a checkbox does not
    -- bounce the user back to the first tab.
    local barSettingsTab = "appearance"

    local RefreshAll
    local ShowBarSettings
    local ShowGroupSettings
    local ShowAddBarPopup
    local ShowBarMenu
    local renameActiveGroupIndex = nil
    local renameActiveEditBox = nil

    -- Writes a pending rename back and tears the box down. Safe to call at any
    -- time, including from inside the box's own handlers -- it clears the
    -- state before touching the widget, so re-entry is a no-op.
    local function CommitPendingRename(apply)
        local box, index = renameActiveEditBox, renameActiveGroupIndex
        -- No box yet means a rename was just requested and BuildBrowser has not
        -- created its widget: leave renameActiveGroupIndex alone so the next
        -- pass can open it.
        if not box then
            if apply == false then renameActiveGroupIndex = nil end
            return
        end
        renameActiveEditBox = nil
        renameActiveGroupIndex = nil

        box:SetScript("OnEditFocusLost", nil)
        box:SetScript("OnEnterPressed", nil)
        box:SetScript("OnEscapePressed", nil)
        box:ClearFocus()
        box:Hide()
        box:GetParent().title:Show()

        if apply == false or not index then return end
        local groups = M.GetGroups(currentSpecID)
        local gd = groups and groups[index]
        local newName = box:GetText():match("^%s*(.-)%s*$")
        if gd and newName and newName ~= "" and newName ~= gd.name then
            gd.name = newName
            box:GetParent().title:SetText(newName)
            SaveAndRefresh()
        end
    end

    local function EnsureGroups()
        local groups = M.EnsureGroups(currentSpecID)
        if groups and #groups == 0 then
            groups[1] = M.CreateGroup(groups, L["BAR1"])
            return groups, true
        end
        return groups
    end
    local function GetGroups() return M.GetGroups(currentSpecID) end

    local function RefreshBrowserIfNeeded()
        if RefreshAll then RefreshAll() end
    end

    -- Drag/drop keeps the bar table as its payload,
    -- so identity survives the move and per-bar settings travel with it.
    local RegisterDropTarget, ClearDropTargets, StartDrag, EndDrag, CancelDrag
    do
        local dragState = { active = false, bar = nil, dragFrame = nil }
        local dropTargets = {}
        local dragFrameCache

        local function HideHighlights()
            for _, target in ipairs(dropTargets) do
                if target.frame.highlight then target.frame.highlight:Hide() end
            end
        end

        local function GetOrCreateDragFrame(bar)
            if not dragFrameCache then
                dragFrameCache = CreateFrame("Frame", nil, UIParent)
                dragFrameCache:SetSize(28, 28)
                dragFrameCache:SetFrameStrata("TOOLTIP")
                local icon = dragFrameCache:CreateTexture(nil, "ARTWORK")
                icon:SetAllPoints()
                dragFrameCache.icon = icon
                dragFrameCache:SetAlpha(0.8)
            end
            local tex = bar.spellID and GetSpellTexture(bar.spellID)
            if tex then
                dragFrameCache.icon:SetTexture(tex)
            else
                dragFrameCache.icon:SetColorTexture(0.3, 0.3, 0.3)
            end
            CDM_C.ApplyIconTexCoord(dragFrameCache.icon, CDM_C.GetEffectiveZoomAmount())
            return dragFrameCache
        end

        RegisterDropTarget = function(frame, groupIndex, viewport)
            dropTargets[#dropTargets + 1] = { frame = frame, groupIndex = groupIndex, viewport = viewport }
        end
        ClearDropTargets = function() table.wipe(dropTargets) end

        local function IsOverTarget(target)
            return target.frame:IsVisible() and target.frame:IsMouseOver()
                and (not target.viewport or target.viewport:IsMouseOver())
        end

        StartDrag = function(bar)
            if dragState.active then return end
            dragState.active = true
            dragState.bar = bar
            local df = GetOrCreateDragFrame(bar)
            dragState.dragFrame = df
            df:Show()
            local cachedScale = UIParent:GetEffectiveScale()
            df:SetScript("OnUpdate", function()
                local x, y = GetCursorPosition()
                df:ClearAllPoints()
                df:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / cachedScale, y / cachedScale)
                for _, target in ipairs(dropTargets) do
                    if target.frame.highlight then
                        target.frame.highlight:SetShown(IsOverTarget(target))
                    end
                end
            end)
        end

        EndDrag = function()
            if not dragState.active then return end
            local bar = dragState.bar
            if dragState.dragFrame then
                dragState.dragFrame:SetScript("OnUpdate", nil)
                dragState.dragFrame:Hide()
                dragState.dragFrame = nil
            end

            local targetGroupIndex, hit = nil, false
            for _, target in ipairs(dropTargets) do
                if IsOverTarget(target) then
                    targetGroupIndex = target.groupIndex
                    hit = true
                    break
                end
            end
            HideHighlights()
            dragState.active = false
            dragState.bar = nil

            if not hit or not bar then return end
            CommitPendingRename(true)
            if M.MoveBar(bar, targetGroupIndex, currentSpecID) then
                selectedBar, selectedBarGroupIndex = bar, targetGroupIndex
                selectedGroupIndex = nil
                browserGroupIndex = targetGroupIndex
                SaveAndRefresh()
                RefreshBrowserIfNeeded()
                ShowBarSettings(bar, targetGroupIndex)
            end
        end

        CancelDrag = function()
            if not dragState.active then return end
            if dragState.dragFrame then
                dragState.dragFrame:SetScript("OnUpdate", nil)
                dragState.dragFrame:Hide()
                dragState.dragFrame = nil
            end
            HideHighlights()
            dragState.active = false
            dragState.bar = nil
        end
    end

    -- Toolbar

    local buttonRow = CreateFrame("Frame", nil, page)
    buttonRow:SetPoint("TOPLEFT", PAGE_INSET, TOOLBAR_TOP)
    buttonRow:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAGE_INSET, TOOLBAR_TOP)
    buttonRow:SetHeight(24)

    local browserFrame = CreateFrame("Frame", nil, page)
    browserFrame:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", 0, -8)
    browserFrame:SetPoint("TOPRIGHT", buttonRow, "BOTTOMRIGHT", 0, -8)
    browserFrame:SetHeight(ICON_SIZE + GROUP_TITLE_H + STRIP_PAD * 2)

    local groupScroll = CreateFrame("ScrollFrame", nil, browserFrame, "ScrollFrameTemplate")
    UI.StyleScrollBar(groupScroll)
    UI.AttachCloseMenusOnScroll(groupScroll)
    groupScroll:SetPoint("TOPLEFT")
    groupScroll:SetPoint("BOTTOMRIGHT", -14, 0)
    local groupList = CreateFrame("Frame", nil, groupScroll)
    groupList:SetSize(640, 1)
    groupScroll:SetScrollChild(groupList)

    local selectionHeader = CreateFrame("Frame", nil, page)
    selectionHeader:SetPoint("TOPLEFT", browserFrame, "BOTTOMLEFT", 0, -10)
    selectionHeader:SetPoint("TOPRIGHT", browserFrame, "BOTTOMRIGHT", 0, -10)
    selectionHeader:SetHeight(80)
    selectionHeader:Hide()

    local selectionTitle = selectionHeader:CreateFontString(nil, "OVERLAY", "CDM_Font18")
    selectionTitle:SetPoint("TOPLEFT", 0, -2)
    selectionTitle:SetPoint("TOPRIGHT", -310, -2)
    selectionTitle:SetJustifyH("LEFT")
    selectionTitle:SetWordWrap(false)
    selectionTitle:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)

    local selectionContext = selectionHeader:CreateFontString(nil, "OVERLAY", "CDM_Font12")
    selectionContext:SetPoint("TOPLEFT", 0, -26)
    selectionContext:SetPoint("TOPRIGHT", -310, -26)
    selectionContext:SetJustifyH("LEFT")
    selectionContext:SetWordWrap(false)
    UI.SetTextMuted(selectionContext)

    local headerControls
    local editingBar, editingScroll
    local headerDivider = page:CreateTexture(nil, "ARTWORK")
    UI.StyleDivider(headerDivider)
    headerDivider:SetPoint("TOPLEFT", browserFrame, "BOTTOMLEFT", 0, -6)
    headerDivider:SetPoint("TOPRIGHT", browserFrame, "BOTTOMRIGHT", 0, -6)

    -- Settings area fills everything under the strip.
    local settingsPanel = CreateFrame("Frame", nil, page)
    settingsPanel:SetPoint("TOPLEFT", browserFrame, "BOTTOMLEFT", 0, -10)
    settingsPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAGE_INSET, 16)

    local settingsPlaceholder = settingsPanel:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    settingsPlaceholder:SetPoint("TOP", 0, -30)
    settingsPlaceholder:SetText(L["Select a group to edit placement, or a bar to edit its appearance."])
    UI.SetTextMuted(settingsPlaceholder)

    local panelManager = Shared.CreateRightPanelManager(settingsPanel, settingsPlaceholder, DestroyFrame)
    local RegisterPanelDropdown = panelManager.RegisterDropdown
    local preview = ns.CreateBuffBarPreview(selectionHeader, true)
    preview:SetPoint("TOPRIGHT", -4, 0)

    local function LayoutSettingsPanel()
        settingsPanel:ClearAllPoints()
        settingsPanel:SetPoint("TOPLEFT", browserFrame, "BOTTOMLEFT", 0,
            selectionHeader:IsShown() and -96 or -16)
        settingsPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAGE_INSET, 16)
    end

    browserFrame:HookScript("OnSizeChanged", LayoutSettingsPanel)

    local function ResetPreview()
        editingBar, editingScroll = nil, nil
        preview:SetBar(nil)
        preview:Hide()
        selectionHeader:Hide()
        DestroyFrame(headerControls)
        headerControls = nil
        LayoutSettingsPanel()
    end

    local function CreatePanelContent(height, reuseContent)
        if not reuseContent then ResetPreview() end
        return panelManager.CreateScrollContent(height, reuseContent)
    end

    local function ClearPanel()
        ResetPreview()
        panelManager.Clear()
    end

    local function MakeDropdown(parent)
        return RegisterPanelDropdown(
            UI.CreateDropdown(parent))
    end

    -- Keep sections in fixed columns as threshold rows are added or removed.
    local function NewColumns(rc)
        local cols = {
            { x = 0, y = 0 },
            { x = COL_W + COL_GAP, y = 0 },
        }
        local sections = {}

        return {
            Section = function(column, build)
                sections[#sections + 1] = { column = column, build = build }
            end,
            Flush = function()
                for _, s in ipairs(sections) do
                    local col = cols[s.column]
                    s.build(col)
                    col.y = col.y - 12   -- breathing room between sections
                end
                wipe(sections)
            end,
            Get = function(i) return cols[i] end,
            -- Start both columns below a full-width heading.
            SetTop = function(y)
                cols[1].y, cols[2].y = y, y
            end,
            MaxDepth = function()
                return math.max(-cols[1].y, -cols[2].y)
            end,
            Header = function(col, text)
                local h = rc:CreateFontString(nil, "ARTWORK", "CDM_Font18")
                h:SetPoint("TOPLEFT", col.x, col.y)
                h:SetWidth(COL_W)
                h:SetJustifyH("LEFT")
                h:SetWordWrap(false)
                h:SetText(text)
                h:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
                col.y = col.y - 30
            end,
            Label = function(col, text, muted, small)
                local fs = rc:CreateFontString(nil, "OVERLAY",
                    small and "CDM_Font12" or "CDM_Font14")
                fs:SetPoint("TOPLEFT", col.x, col.y)
                fs:SetWidth(COL_W)
                fs:SetJustifyH("LEFT")
                fs:SetText(text)
                if muted then UI.SetTextMuted(fs) end
                col.y = col.y - math.max(small and 20 or 22, math.ceil(fs:GetStringHeight()) + 6)
                return fs
            end,
            Slider = function(col, label, minV, maxV, cur, onChange)
                local s = CreateSlider(rc, label, minV, maxV, cur, onChange)
                s:SetPoint("TOPLEFT", col.x, col.y)
                col.y = col.y - 46
                return s
            end,
            Check = function(col, label, checked, onChange)
                local c = UI.CreateModernCheckbox(rc, label, checked, onChange)
                c:SetPoint("TOPLEFT", col.x, col.y)
                col.y = col.y - 32
                return c
            end,
            Dropdown = function(col, options, getV, setV, defaultText, width)
                local dd = MakeDropdown(rc)
                dd:SetWidth(width or 200)
                dd:SetPoint("TOPLEFT", col.x, col.y)
                dd:SetDefaultText(defaultText)
                UI.SetupValueDropdown(dd, options, getV, function(val)
                    setV(val)
                    dd:SetDefaultText(UI.GetOptionLabel(options, val, val))
                end)
                col.y = col.y - 36
                return dd
            end,
            PositionDropdown = function(col, getV, setV, defaultText, width)
                local dd = MakeDropdown(rc)
                dd:SetWidth(width or 200)
                dd:SetPoint("TOPLEFT", col.x, col.y)
                dd:SetDefaultText(defaultText)
                UI.SetupPositionDropdown(dd, getV, setV)
                col.y = col.y - 36
                return dd
            end,
            ColorRow = function(col, label, initial, onChange)
                local fs = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
                fs:SetPoint("TOPLEFT", col.x, col.y)
                fs:SetWidth(170)
                fs:SetJustifyH("LEFT")
                fs:SetText(label)
                local picker = UI.CreateSimpleColorPicker(rc, initial, onChange, true)
                picker:SetPoint("TOPLEFT", col.x + 180, col.y + 2)
                col.y = col.y - 28
                return picker
            end,
            Gap = function(col, amount)
                col.y = col.y - (amount or 10)
            end,
        }
    end

    -- Group settings: placement only. Bars carry their own visuals.
    ShowGroupSettings = function(groupIndex)
        local groups = GetGroups()
        local gd = groups and groups[groupIndex]
        if not gd then ClearPanel(); return end

        local _, rc = CreatePanelContent(400)
        local C = NewColumns(rc)

        local left = C.Get(1)
        C.Header(left, (gd.name or (L["BAR"] .. groupIndex)) .. "  " .. L["(Group)"])
        C.Label(left, L["Groups control placement. Each bar keeps its own appearance."], true, true)
        C.Gap(left, 6)

        C.Label(left, L["Grow Direction"])
        C.Dropdown(left, GROW_OPTIONS,
            function() return gd.grow or "DOWN" end,
            function(val) gd.grow = val; SaveAndRefresh() end,
            UI.GetOptionLabel(GROW_OPTIONS, gd.grow or "DOWN", L["Down"]))

        C.Gap(left, 12)
        C.Slider(left, L["Spacing"], -1, 50, gd.spacing or 1, function(v)
            gd.spacing = UI.RoundToInt(v); SaveAndRefresh()
        end)

        -- Anchor lives in the right column so both stay short.
        local right = C.Get(2)
        C.Header(right, L["Anchor"])

        local anchorTargets = {
            { label = L["Screen"], value = "screen" },
            { label = L["Player Frame"], value = "playerFrame" },
            { label = L["Essential Viewer"], value = "essential" },
            { label = L["Buff Viewer"], value = "buff" },
            { label = L["Buff Bar Viewer"], value = "buffBar" },
        }

        C.Label(right, L["Anchor To"])
        local anchorLabel, anchorDropdown, relLabel, relDropdown
        local xSlider, ySlider
        local UpdateAnchorVisibility

        C.Dropdown(right, anchorTargets,
            function() return gd.anchorTarget or "screen" end,
            function(val)
                local prev = gd.anchorTarget or "screen"
                gd.anchorTarget = val
                gd.anchorPoint = gd.anchorPoint or "CENTER"
                gd.anchorRelativeTo = gd.anchorRelativeTo or "CENTER"
                if val ~= prev then
                    gd.offsetX, gd.offsetY = 0, 0
                    xSlider:UpdateUIValue(0)
                    ySlider:UpdateUIValue(0)
                end
                SaveAndRefresh()
                UpdateAnchorVisibility()
            end,
            UI.GetOptionLabel(anchorTargets, gd.anchorTarget or "screen", L["Screen"]))

        local yAfterTarget = right.y

        anchorLabel = C.Label(right, L["Anchor Point"])
        anchorDropdown = C.PositionDropdown(right,
            function() return gd.anchorPoint or "CENTER" end,
            function(val) gd.anchorPoint = val; SaveAndRefresh() end,
            gd.anchorPoint or "CENTER")

        relLabel = C.Label(right, L["Relative Point"])
        relDropdown = C.PositionDropdown(right,
            function() return gd.anchorRelativeTo or "CENTER" end,
            function(val) gd.anchorRelativeTo = val; SaveAndRefresh() end,
            gd.anchorRelativeTo or "CENTER")

        local yAfterConditional = right.y

        C.Gap(right, 12)
        xSlider = C.Slider(right, L["X Offset"], -840, 840, gd.offsetX or 0, function(v)
            gd.offsetX = UI.RoundToInt(v); SaveAndRefresh()
        end)
        ySlider = C.Slider(right, L["Y Offset"], -470, 470, gd.offsetY or 0, function(v)
            gd.offsetY = UI.RoundToInt(v); SaveAndRefresh()
        end)

        UpdateAnchorVisibility = function()
            local isScreen = (gd.anchorTarget or "screen") == "screen"
            anchorLabel:SetShown(not isScreen)
            anchorDropdown:SetShown(not isScreen)
            relLabel:SetShown(not isScreen)
            relDropdown:SetShown(not isScreen)
            if not isScreen then
                anchorDropdown:SetDefaultText(gd.anchorPoint or "CENTER")
                relDropdown:SetDefaultText(gd.anchorRelativeTo or "CENTER")
            end
            -- Collapse the gap the hidden dropdowns leave behind.
            local sliderY = (isScreen and yAfterTarget or yAfterConditional) - 12
            xSlider:ClearAllPoints()
            xSlider:SetPoint("TOPLEFT", right.x, sliderY)
            ySlider:ClearAllPoints()
            ySlider:SetPoint("TOPLEFT", right.x, sliderY - 46)
            rc:SetHeight(math.max(C.MaxDepth(), math.abs(sliderY - 92)) + 24)
        end
        UpdateAnchorVisibility()
        if ns.RegisterAnchorPositionUpdater then
            ns.RegisterAnchorPositionUpdater("buff_bar_group_" .. groupIndex, function(x, y)
                if selectedGroupIndex ~= groupIndex or not page:IsShown() then return end
                xSlider:UpdateUIValue(x)
                ySlider:UpdateUIValue(y)
            end)
        end
    end

    -- Per-bar settings, spread across two columns.
    ShowBarSettings = function(bar, groupIndex, scrollOffset)
        if not bar then ClearPanel(); return end
        M.NormalizeBar(bar)

        local reuseContent = editingBar == bar
        if reuseContent and scrollOffset == nil then scrollOffset = editingScroll:GetVerticalScroll() end
        local scrollFrame, rc = CreatePanelContent(400, reuseContent)
        local contentHeightFloor = reuseContent and rc:GetHeight() or 0
        editingBar, editingScroll = bar, scrollFrame
        DestroyFrame(headerControls)
        headerControls = nil
        selectionTitle:SetText(bar.name or (bar.spellID and GetSpellName(bar.spellID)) or L["Unknown"])
        local group = groupIndex and GetGroups()[groupIndex]
        selectionContext:SetText(group and group.name or L["BAR1"])
        selectionHeader:Show()
        preview:SetBar(bar)
        preview:Show()
        if not reuseContent then LayoutSettingsPanel() end

        local function Save()
            SaveAndRefresh()
            preview:Refresh()
        end
        local function Write(key, value) bar[key] = value; Save() end
        local function WriteColor(key, r, g, b, a)
            bar[key] = { r = r, g = g, b = b, a = a or 1 }
            Save()
        end

        headerControls = CreateFrame("Frame", nil, selectionHeader)
        headerControls:SetAllPoints()
        local typeDropdown = MakeDropdown(headerControls)
        typeDropdown:SetWidth(170)
        typeDropdown:SetPoint("TOPLEFT", 0, -46)
        typeDropdown:SetDefaultText(UI.GetOptionLabel(BAR_TYPE_OPTIONS, bar.barType, L["Timer Bar"]))
        UI.SetupValueDropdown(typeDropdown, BAR_TYPE_OPTIONS,
            function() return bar.barType end,
            function(val)
                bar.barType = val
                M.NormalizeBar(bar)
                Save()
                RefreshBrowserIfNeeded()
                ShowBarSettings(bar, groupIndex)
            end)

        local isStack = bar.barType == M.TYPE_STACK

        -- Tab strip: the shared Blizzard-atlas tabs, same as the Cooldowns and
        -- Text pages, followed by the thin horizontal divider they all use.
        local tabHost = CreateFrame("Frame", nil, rc)
        tabHost:SetPoint("TOPLEFT", 0, 0)
        tabHost:SetPoint("TOPRIGHT", rc, "TOPRIGHT", 0, 0)
        tabHost:SetHeight(240)

        local tabDefs = {
            { id = "appearance", label = L["Appearance"] },
            { id = "text", label = L["Text"] },
        }
        if isStack then
            tabDefs[#tabDefs + 1] = { id = "custom", label = L["Stack Settings"] }
        elseif barSettingsTab == "custom" then
            barSettingsTab = "appearance"
            scrollOffset = 0
            contentHeightFloor = 0
        end
        local subTabs = UI.CreateSubTabBar(tabHost, tabDefs, barSettingsTab)

        local tabPages = subTabs.subPages

        local divider = tabHost:CreateTexture(nil, "ARTWORK")
        UI.StyleDivider(divider)
        divider:SetPoint("TOPLEFT", subTabs.barFrame, "BOTTOMLEFT", -30, 0)
        divider:SetPoint("TOPRIGHT", subTabs.barFrame, "BOTTOMRIGHT", 30, 0)
        local dividerH = divider:GetHeight()

        -- CreateSubTabBar anchors its pages to BOTTOMRIGHT of the host, which
        -- would stretch them; re-anchor to a fixed top so each page sizes to
        -- its own content instead.
        local pagesTop = -(37 + dividerH + 8)
        for _, pg in pairs(tabPages) do
            pg:ClearAllPoints()
            pg:SetPoint("TOPLEFT", tabHost, "TOPLEFT", 0, pagesTop)
            pg:SetPoint("TOPRIGHT", tabHost, "TOPRIGHT", 0, pagesTop)
            pg:SetHeight(1)
        end

        local pageHeights = {}
        local ResizeToTab

        -- The helper's own SelectTab handles the atlas swap; wrap it so
        -- switching also closes any open dropdown (its anchor button is about
        -- to be hidden) and resizes the scroll child to the new tab.
        local function SelectTab(id)
            if id == barSettingsTab then return end
            panelManager.CloseDropdownMenus()
            subTabs.selectTab(id)
            barSettingsTab = id
            contentHeightFloor = 0
            scrollFrame:SetVerticalScroll(0)
            if ResizeToTab then ResizeToTab(id) end
        end

        for _, def in ipairs({ "appearance", "text", "custom" }) do
            local btn = subTabs.tabButtons[def]
            if btn then
                btn:SetScript("OnClick", function() SelectTab(def) end)
            end
        end

        -- Each tab lays its sections out in two columns of its own.
        local function BuildPage(id, build)
            local pg = tabPages[id]
            if not pg then return end
            local C = NewColumns(pg)
            build(C)
            C.Flush()
            local h = C.MaxDepth() + 16
            pg:SetHeight(h)
            pageHeights[id] = h
        end

        BuildPage("appearance", function(C)
            local left = C.Get(1)
            C.Header(left, L["Size & Icon"])
            C.Slider(left, L["Bar Width"], 0, 600, bar.width or 0, function(v)
                local value = UI.RoundToInt(v)
                if value > 0 and value < 60 then value = 60 end
                Write("width", value)
            end)
            C.Label(left, L["0 = automatic width"], true, true)
            C.Slider(left, L["Bar Height"], 4, 40, bar.height or 20, function(v)
                Write("height", UI.RoundToInt(v))
            end)
            C.Label(left, L["Icon Position"])
            C.Dropdown(left, ICON_POS_OPTIONS,
                function() return bar.iconPosition or "LEFT" end,
                function(val)
                    bar.iconPosition = val
                    Save()
                    ShowBarSettings(bar, groupIndex, scrollFrame:GetVerticalScroll())
                end,
                UI.GetOptionLabel(ICON_POS_OPTIONS, bar.iconPosition or "LEFT", L["Left"]))
            if bar.iconPosition ~= "HIDDEN" then
                C.Gap(left, 12)
                C.Slider(left, L["Icon-Bar Gap"], -1, 20, bar.iconGap or 1, function(v)
                    Write("iconGap", UI.RoundToInt(v))
                end)
            end

            local right = C.Get(2)
            C.Header(right, L["Texture & Colors"])
            C.Label(right, L["Bar Texture"])
            local dd = MakeDropdown(tabPages.appearance)
            dd:SetWidth(200)
            dd:SetPoint("TOPLEFT", right.x, right.y)
            dd:SetDefaultText(bar.texture or "Solid")
            UI.SetupMediaDropdown(dd, "statusbar",
                function() return bar.texture or "Solid" end,
                function(name) bar.texture = name; Save() end,
                function(name) dd:SetDefaultText(name or "Solid") end)
            right.y = right.y - 40
            C.ColorRow(right, L["Bar Color"], bar.barColor,
                function(r, g, b, a) WriteColor("barColor", r, g, b, a) end)
            C.ColorRow(right, L["Background Color"], bar.bgColor,
                function(r, g, b, a) WriteColor("bgColor", r, g, b, a) end)
            C.Gap(right, 6)
            C.Check(right, L["Hide Border"], bar.hideBorder == true,
                function(checked) Write("hideBorder", checked) end)
            C.Check(right, L["Show Spark"], bar.showSpark == true,
                function(checked) Write("showSpark", checked) end)
        end)

        BuildPage("text", function(C)
            local left = C.Get(1)
            C.Header(left, L["Stack Count"])
            local shownStack = bar.showApplications ~= false
            C.Check(left, L["Show Stack Count"], shownStack, function(checked)
                bar.showApplications = checked
                Save()
                ShowBarSettings(bar, groupIndex, scrollFrame:GetVerticalScroll())
            end)
            if shownStack then
                C.Slider(left, L["Font Size"], 6, 32, bar.applicationsFontSize or 15,
                    function(v) Write("applicationsFontSize", UI.RoundToInt(v)) end)
                C.ColorRow(left, L["Color"], bar.applicationsColor,
                    function(r, g, b, a) WriteColor("applicationsColor", r, g, b, a) end)
                C.Label(left, L["Position"])
                C.PositionDropdown(left,
                    function() return bar.applicationsPosition or "CENTER" end,
                    function(val) bar.applicationsPosition = val; Save() end,
                    bar.applicationsPosition or "CENTER")
                C.Gap(left, 12)
                C.Slider(left, L["X Offset"], -50, 50, bar.applicationsOffsetX or 0,
                    function(v) Write("applicationsOffsetX", UI.RoundToInt(v)) end)
                C.Slider(left, L["Y Offset"], -20, 20, bar.applicationsOffsetY or 0,
                    function(v) Write("applicationsOffsetY", UI.RoundToInt(v)) end)
            end

            if not isStack then
                local right = C.Get(2)
                C.Header(right, L["Duration"])
                C.Check(right, L["Show Duration Text"], bar.showDuration ~= false, function(checked)
                    bar.showDuration = checked
                    Save()
                    ShowBarSettings(bar, groupIndex, scrollFrame:GetVerticalScroll())
                end)
                if bar.showDuration ~= false then
                    C.Slider(right, L["Font Size"], 6, 32, bar.durationFontSize or 15,
                        function(v) Write("durationFontSize", UI.RoundToInt(v)) end)
                    C.ColorRow(right, L["Color"], bar.durationColor,
                        function(r, g, b, a) WriteColor("durationColor", r, g, b, a) end)
                    C.Label(right, L["Position"])
                    C.PositionDropdown(right,
                        function() return bar.durationPosition or "RIGHT" end,
                        function(val) bar.durationPosition = val; Save() end,
                        bar.durationPosition or "RIGHT")
                    C.Gap(right, 12)
                    C.Slider(right, L["X Offset"], -50, 50, bar.durationOffsetX or -2,
                        function(v) Write("durationOffsetX", UI.RoundToInt(v)) end)
                    C.Slider(right, L["Y Offset"], -20, 20, bar.durationOffsetY or 0,
                        function(v) Write("durationOffsetY", UI.RoundToInt(v)) end)
                    C.Gap(right, 8)
                    local decimals = bar.timerDecimals ~= false
                    C.Check(right, L["Show Decimals"], decimals, function(checked)
                        bar.timerDecimals = checked
                        Save()
                        ShowBarSettings(bar, groupIndex, scrollFrame:GetVerticalScroll())
                    end)
                    if decimals then
                        C.Slider(right, L["Decimal Threshold"], 3, 120, bar.decimalThreshold or 5,
                            function(v) Write("decimalThreshold", UI.RoundToInt(v)) end)
                    end
                end
            end
        end)

        -- ---- Custom: behaviour unique to this bar type ----
        BuildPage("custom", function(C)
            if isStack then
                C.Section(1, function(col)
                    C.Header(col, L["Stack Fill"])
                    C.Slider(col, L["Max Stacks"], 1, 100, bar.maxStacks or 1,
                        function(v) Write("maxStacks", UI.RoundToInt(v)) end)
                    C.Check(col, L["Always Show Bar"], bar.alwaysShow ~= false,
                        function(checked) Write("alwaysShow", checked) end)
                    C.Label(col, L["Keep an empty bar visible when the buff is not active."], true, true)
                end)

                bar.colorThresholds = bar.colorThresholds or {}
                local thresholds = bar.colorThresholds

                C.Section(2, function(col)
                    C.Header(col, L["Threshold Colors"])
                    C.Label(col, L["The bar recolors once it reaches this many stacks."], true, true)

                    local pg = tabPages.custom
                    for ti = 1, #thresholds do
                        local t = thresholds[ti]
                        if type(t) == "table" then
                            local atLabel = pg:CreateFontString(nil, "OVERLAY", "CDM_Font14")
                            atLabel:SetText(L["At"])
                            atLabel:SetPoint("TOPLEFT", col.x, col.y - 4)

                            local stacksInput = CreateFrame("EditBox", nil, pg, "InputBoxTemplate")
                            stacksInput:SetSize(44, 20)
                            stacksInput:SetPoint("LEFT", atLabel, "RIGHT", 8, 0)
                            stacksInput:SetAutoFocus(false)
                            stacksInput:SetNumeric(true)
                            stacksInput:SetMaxLetters(3)
                            stacksInput:SetText(tostring(t.stacks or 1))
                            stacksInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                            stacksInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                            stacksInput:SetScript("OnEditFocusLost", function(self)
                                local n = tonumber(self:GetText())
                                if n and n > 0 then
                                    t.stacks = math.floor(n)
                                else
                                    self:SetText(tostring(t.stacks or 1))
                                end
                                Save()
                            end)

                            local suffix = pg:CreateFontString(nil, "OVERLAY", "CDM_Font14")
                            suffix:SetText(L["stacks"])
                            suffix:SetPoint("LEFT", stacksInput, "RIGHT", 6, 0)

                            if type(t.color) ~= "table" then
                                t.color = { r = 1, g = 0.6, b = 0, a = 1 }
                            end
                            local picker = UI.CreateSimpleColorPicker(pg, t.color, function(r, g, b, a)
                                t.color = { r = r, g = g, b = b, a = a or 1 }
                                Save()
                            end, true)
                            picker:SetPoint("LEFT", suffix, "RIGHT", 10, 0)

                            local delBtn = UI.CreateTextButton(pg)
                            delBtn:SetSize(22, 20)
                            delBtn:SetPoint("LEFT", picker, "RIGHT", 10, 0)
                            delBtn:SetText("X")
                            local capturedIndex = ti
                            delBtn:SetScript("OnClick", function()
                                table.remove(thresholds, capturedIndex)
                                Save()
                                ShowBarSettings(bar, groupIndex, scrollFrame:GetVerticalScroll())
                            end)

                            col.y = col.y - 28
                        end
                    end

                    local addBtn = UI.CreateTextButton(pg)
                    addBtn:SetSize(120, 22)
                    addBtn:SetPoint("TOPLEFT", col.x, col.y)
                    addBtn:SetText(L["Add Threshold"])
                    addBtn:SetScript("OnClick", function()
                        local maxStacks = bar.maxStacks or 1
                        local suggested = #thresholds == 0
                            and math.max(1, math.floor(maxStacks / 2))
                            or math.min(maxStacks, (thresholds[#thresholds].stacks or 1) + 1)
                        thresholds[#thresholds + 1] = {
                            stacks = suggested,
                            color = { r = 1, g = 0.6, b = 0, a = 1 },
                        }
                        Save()
                        ShowBarSettings(bar, groupIndex, scrollFrame:GetVerticalScroll())
                    end)
                    col.y = col.y - 32
                end)

                C.Section(1, function(col)
                    local pg = tabPages.custom
                    C.Header(col, L["Tick Marks"])
                    local tickLabel = pg:CreateFontString(nil, "OVERLAY", "CDM_Font14")
                    tickLabel:SetText(L["At stacks:"])
                    tickLabel:SetPoint("TOPLEFT", col.x, col.y - 4)

                    local tickInput = CreateFrame("EditBox", nil, pg, "InputBoxTemplate")
                    tickInput:SetSize(110, 20)
                    tickInput:SetPoint("LEFT", tickLabel, "RIGHT", 8, 0)
                    tickInput:SetAutoFocus(false)
                    tickInput:SetMaxLetters(60)
                    tickInput:SetText(bar.tickValues or "")
                    tickInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                    tickInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                    tickInput:SetScript("OnEditFocusLost", function(self)
                        bar.tickValues = self:GetText()
                        Save()
                    end)
                    col.y = col.y - 26

                    C.Label(col, L["comma separated, e.g. 5,10,15"], true, true)
                    C.Slider(col, L["Tick Width"], 0, 6, bar.tickWidth or 1,
                        function(v) Write("tickWidth", UI.RoundToInt(v)) end)
                    C.ColorRow(col, L["Tick Color"], bar.tickColor,
                        function(r, g, b, a) WriteColor("tickColor", r, g, b, a) end)
                end)
            end
        end)

        ResizeToTab = function(id)
            local h = (pageHeights[id] or 0)
            tabHost:SetHeight(math.abs(pagesTop) + h)
            -- Keep enough canvas below the current viewport when controls collapse.
            rc:SetHeight(math.max(contentHeightFloor, math.abs(pagesTop) + h + 16))
        end

        -- The helper already selected `barSettingsTab` at construction and its
        -- own SelectTab early-returns on an unchanged id, so calling the
        -- wrapper here would no-op and never size the scroll child. Size it
        -- directly instead; the wrapper only matters for later tab clicks.
        local wanted = barSettingsTab
        if not tabPages[wanted] then
            wanted = "appearance"
            SelectTab(wanted)
        else
            ResizeToTab(wanted)
        end
        if scrollOffset then
            scrollFrame:SetVerticalScroll(math.min(scrollOffset, math.max(0, rc:GetHeight() - scrollFrame:GetHeight())))
        end
    end

    local addBarPopup
    local addBarPopupContent

    ShowAddBarPopup = function(targetGroupIndex)
        CommitPendingRename(true)
        panelManager.CloseDropdownMenus()
        local targetGroups = EnsureGroups()
        if not targetGroups then return end
        targetGroupIndex = targetGroupIndex or 1
        if not addBarPopup then
            addBarPopup = UI.CreateModalOverlay()
        end
        addBarPopup:Hide()
        DestroyFrame(addBarPopupContent)
        local rc = CreateFrame("Frame", nil, addBarPopup.window)
        rc:SetPoint("TOPLEFT", 22, -38)
        rc:SetWidth(300)
        addBarPopupContent = rc

        local popupDB = CDM.db
        local popupSpecID = currentSpecID
        local groups = GetGroups()
        local targetGroup = groups and groups[targetGroupIndex]
        if not targetGroup then return end

        local header = rc:CreateFontString(nil, "ARTWORK", "CDM_Font18")
        header:SetPoint("TOPLEFT")
        header:SetWidth(300)
        header:SetJustifyH("LEFT")
        header:SetWordWrap(false)
        header:SetText(L["Add Bar to:"] .. " " .. (targetGroup.name or L["Group"]))
        header:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)

        local listLabel = rc:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        listLabel:SetText(L["Tracked buffs"])
        listLabel:SetPoint("TOPLEFT", 0, -32)
        UI.SetTextWhite(listLabel)

        local tracked = CDM.GetBuffBarTrackedSpells and CDM.GetBuffBarTrackedSpells() or {}
        local listHeight = math.max(1, #tracked) * 28
        local list = CreateFrame("Frame", nil, rc)
        list:SetPoint("TOPLEFT", 0, -58)
        list:SetSize(300, listHeight)

        if #tracked == 0 then
            local msg = list:CreateFontString(nil, "OVERLAY", "CDM_Font14")
            msg:SetPoint("TOPLEFT", 0, -4)
            msg:SetText(L["(No tracked buffs found)"])
            UI.SetTextMuted(msg)
        end

        for i, entry in ipairs(tracked) do
            local added = M.IsSpellConfigured(entry.spellID, currentSpecID)
            local row = CreateFrame("Button", nil, list)
            row:SetSize(300, 28)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
            row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)

            local rowIcon = row:CreateTexture(nil, "ARTWORK")
            rowIcon:SetSize(22, 22)
            rowIcon:SetPoint("LEFT", 0, 0)
            rowIcon:SetTexture(entry.icon or 134400)
            CDM_C.ApplyIconTexCoord(rowIcon, CDM_C.GetEffectiveZoomAmount())

            local label = row:CreateFontString(nil, "OVERLAY", "CDM_Font14")
            label:SetPoint("LEFT", rowIcon, "RIGHT", 6, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            if added then
                label:SetText(entry.name .. " |cff888888(" .. L["added"] .. ")|r")
                UI.SetTextFaint(label)
            else
                label:SetText(entry.name)
            end

            local sid, sname = entry.spellID, entry.name
            row:SetScript("OnClick", function()
                local currentGroups = GetGroups()
                if not page:IsShown() or popupDB ~= CDM.db or popupSpecID ~= currentSpecID
                    or not currentGroups or currentGroups[targetGroupIndex] ~= targetGroup then
                    addBarPopup:Hide()
                    return
                end
                targetGroup.bars = targetGroup.bars or {}
                local destination = targetGroup.bars

                local newBar = M.CreateBar(sid, sname, M.TYPE_TIMER)
                destination[#destination + 1] = newBar
                selectedBar = newBar
                selectedBarGroupIndex = targetGroupIndex
                selectedGroupIndex = nil
                addBarPopup:Hide()
                SaveAndRefresh()
                RefreshBrowserIfNeeded()
                ShowBarSettings(newBar, targetGroupIndex)
            end)
        end

        rc:SetHeight(58 + listHeight)
        addBarPopup.window:SetSize(344, rc:GetHeight() + 58)
        addBarPopup:Show()
    end

    local function RefreshSelection()
        if selectedBar then
            ShowBarSettings(selectedBar, selectedBarGroupIndex)
        elseif selectedGroupIndex then
            ShowGroupSettings(selectedGroupIndex)
        else
            ClearPanel()
        end
    end

    local function SelectGroup(index)
        CommitPendingRename(true)
        browserGroupIndex = index
        selectedGroupIndex = index
        selectedBar, selectedBarGroupIndex = nil, nil
        RefreshAll()
        RefreshSelection()
    end

    local function RenameGroup(index)
        if not index then return end
        if browserGroupIndex ~= index then SelectGroup(index) end
        CommitPendingRename(true)
        renameActiveGroupIndex = index
        RefreshAll()
    end

    local function DuplicateGroup(index)
        local groups = EnsureGroups()
        local gd = groups and groups[index]
        if not gd then return end
        CommitPendingRename(true)
        local clone = M.CreateGroup(groups,
            Shared.GetUniqueGroupName(groups, gd.name or L["Group"]))
        for _, key in ipairs({ "grow", "spacing", "anchorTarget", "anchorPoint", "anchorRelativeTo", "offsetX", "offsetY" }) do
            clone[key] = gd[key]
        end
        for _, bar in ipairs(gd.bars or {}) do clone.bars[#clone.bars + 1] = M.CloneBar(bar) end
        groups[#groups + 1] = clone
        SaveAndRefresh()
        SelectGroup(#groups)
    end

    local function DeleteGroup(index)
        local groups = GetGroups()
        local gd = groups and groups[index]
        if not gd then return end
        local sourceDB, sourceSpec = CDM.db, currentSpecID
        local function Delete()
            if not page:IsShown() or CDM.db ~= sourceDB or currentSpecID ~= sourceSpec
                or GetGroups()[index] ~= gd then return end
            CommitPendingRename(renameActiveGroupIndex ~= index)
            table.remove(groups, index)
            local destination = EnsureGroups()[1]
            destination.bars = destination.bars or {}
            for _, bar in ipairs(gd.bars or {}) do destination.bars[#destination.bars + 1] = bar end
            if selectedGroupIndex == index then
                selectedGroupIndex = 1
            elseif selectedGroupIndex and selectedGroupIndex > index then
                selectedGroupIndex = selectedGroupIndex - 1
            end
            if selectedBarGroupIndex == index then
                selectedBarGroupIndex = 1
            elseif selectedBarGroupIndex and selectedBarGroupIndex > index then
                selectedBarGroupIndex = selectedBarGroupIndex - 1
            end
            if browserGroupIndex == index then
                browserGroupIndex = 1
            elseif browserGroupIndex and browserGroupIndex > index then
                browserGroupIndex = browserGroupIndex - 1
            end
            SaveAndRefresh()
            RefreshAll()
            RefreshSelection()
        end
        local count = #(gd.bars or {})
        if count > 0 then
            local dialog = StaticPopupDialogs["CDM_CONFIRM_DELETE_BARGROUP"]
            local destination = groups[index == 1 and 2 or 1]
            dialog.text = string.format(L["Delete group? Its %d bar(s) move to %s."],
                count, destination and destination.name or L["BAR1"])
            dialog._pendingDelete = Delete
            StaticPopup_Show("CDM_CONFIRM_DELETE_BARGROUP")
        else
            Delete()
        end
    end

    local function ShowGroupMenu(owner, index)
        if not index then return end
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateButton(L["Rename"], function() RenameGroup(index) end)
            root:CreateButton(L["Add Bar"], function() ShowAddBarPopup(index) end)
            root:CreateButton(L["Duplicate"], function() DuplicateGroup(index) end)
            root:CreateDivider()
            root:CreateButton(L["Delete Group"], function() DeleteGroup(index) end)
        end)
    end

    ShowBarMenu = function(owner, bar)
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateButton(L["Remove Bar"], function()
                M.RemoveBar(bar, currentSpecID)
                if selectedBar == bar then
                    selectedBar, selectedBarGroupIndex = nil, nil
                    selectedGroupIndex = browserGroupIndex
                end
                SaveAndRefresh()
                RefreshAll()
                RefreshSelection()
            end)
        end)
    end

    local addGroupBtn = UI.CreateTextButton(buttonRow)
    addGroupBtn:SetSize(100, 22)
    addGroupBtn:SetPoint("LEFT", 0, 0)
    addGroupBtn:SetText(L["Add Group"])
    addGroupBtn:SetScript("OnClick", function()
        CommitPendingRename(true)
        local groups = EnsureGroups()
        if not groups then return end
        local names = {}
        for _, group in ipairs(groups) do
            if group.name then names[group.name] = true end
        end
        local number = 1
        while names[L["BAR"] .. number] do number = number + 1 end
        groups[#groups + 1] = M.CreateGroup(groups, L["BAR"] .. number)
        SaveAndRefresh()
        SelectGroup(#groups)
    end)

    local groupRows = {}
    local function AcquireGroupRow(index)
        local row = groupRows[index]
        if not row then
            row = CreateFrame("Frame", nil, groupList)
            row.titleButton = CreateFrame("Button", nil, row)
            row.titleButton:SetPoint("TOPLEFT")
            row.titleButton:SetPoint("TOPRIGHT")
            row.titleButton:SetHeight(GROUP_TITLE_H)
            row.titleButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row.title = row.titleButton:CreateFontString(nil, "OVERLAY", "CDM_Font14")
            row.title:SetPoint("LEFT", 2, 0)
            row.title:SetPoint("RIGHT", -4, 0)
            row.title:SetJustifyH("LEFT")
            row.title:SetWordWrap(false)

            row.strip = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.strip:SetPoint("TOPLEFT", 0, -GROUP_TITLE_H)
            row.strip:SetBackdrop({ bgFile = CDM_C.TEX_WHITE8X8, edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1 })
            row.strip:SetBackdropColor(0.035, 0.035, 0.035, 0.65)
            row.strip:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)
            row.selection = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.selection:SetAllPoints()
            row.selection:SetBackdrop({ edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1 })
            row.selection:SetBackdropBorderColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 0.8)
            row.selection:SetFrameLevel(row:GetFrameLevel() + 6)
            row.selection:Hide()
            row.highlight = row.strip:CreateTexture(nil, "OVERLAY")
            row.highlight:SetAllPoints()
            row.highlight:SetColorTexture(1, 0.82, 0, 0.14)
            row.highlight:Hide()
            row.selectButton = CreateFrame("Button", nil, row.strip)
            row.selectButton:SetAllPoints()
            row.selectButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            row.deleteButton = UI.CreateTextButton(row.strip, { r = 1, g = 0.267, b = 0.267 })
            row.deleteButton:SetSize(ICON_SIZE, ICON_SIZE)
            row.deleteButton:SetPoint("TOPLEFT", STRIP_PAD, -STRIP_PAD)
            row.deleteButton:SetFrameLevel(row.selectButton:GetFrameLevel() + 2)
            local cross = UI.ApplyCrossIcon(row.deleteButton)
            cross:SetSize(18, 18)
            row.addButton = UI.CreateTextButton(row.strip, CDM_C.GOLD)
            row.addButton:SetSize(ICON_SIZE, ICON_SIZE)
            row.addButton:SetFrameLevel(row.selectButton:GetFrameLevel() + 2)
            local plusH = row.addButton:CreateTexture(nil, "ARTWORK", nil, 2)
            plusH:SetSize(10, 2)
            plusH:SetPoint("CENTER")
            plusH:SetColorTexture(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
            local plusV = row.addButton:CreateTexture(nil, "ARTWORK", nil, 2)
            plusV:SetSize(2, 10)
            plusV:SetPoint("CENTER")
            plusV:SetColorTexture(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
            row.icons = {}
            groupRows[index] = row
        end
        row.highlight:Hide()
        row.title:Show()
        if row.renameBox and row.renameBox ~= renameActiveEditBox then row.renameBox:Hide() end
        row:Show()
        return row
    end

    local function AcquireBarIcon(row, index)
        local button = row.icons[index]
        if not button then
            button = CreateFrame("Button", nil, row.strip, "BackdropTemplate")
            button:SetBackdrop({ edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1 })
            button:SetFrameLevel(row.selectButton:GetFrameLevel() + 2)
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            button:RegisterForDrag("LeftButton")
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetPoint("TOPLEFT", 1, -1)
            button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            local hover = button:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.15)
            button.badge = button:CreateFontString(nil, "OVERLAY", "CDM_Font12")
            button.badge:SetPoint("BOTTOMRIGHT", -2, 2)
            row.icons[index] = button
        end
        button:Show()
        return button
    end

    local function RevealGroup(row)
        local offset, height = groupScroll:GetVerticalScroll(), browserFrame:GetHeight()
        if row.offset < offset then
            groupScroll:SetVerticalScroll(row.offset)
        elseif row.offset + row:GetHeight() > offset + height then
            groupScroll:SetVerticalScroll(math.max(0, row.offset + math.min(height, row:GetHeight()) - height))
        end
    end

    local function BuildBrowser()
        ClearDropTargets()
        local groups = GetGroups()
        local availableWidth = math.max(ICON_SIZE * 3 + STRIP_PAD * 2 + ICON_GAP * 2,
            groupScroll:GetWidth() > 0 and groupScroll:GetWidth() - 4 or 640)
        groupList:SetWidth(availableWidth)
        for index = #groups + 1, #groupRows do groupRows[index]:Hide() end
        local x, offset, rowHeight, selectedIconTop = 0, 0, 0, nil
        for groupIndex, group in ipairs(groups) do
            local row = AcquireGroupRow(groupIndex)
            local bars = group.bars or {}
            local columns = math.max(1, math.floor((availableWidth - STRIP_PAD * 2 - ICON_SIZE * 2 - ICON_GAP * 2) / (ICON_SIZE + ICON_GAP)))
            columns = math.min(columns, math.max(1, #bars))
            local lines = math.max(1, math.ceil(#bars / columns))
            local stripWidth = STRIP_PAD * 2 + (columns + 2) * ICON_SIZE + (columns + 1) * ICON_GAP
            local stripHeight = STRIP_PAD * 2 + lines * ICON_SIZE + (lines - 1) * ICON_GAP
            if x > 0 and x + stripWidth > availableWidth then
                x = 0
                offset = offset + rowHeight + GROUP_GAP
                rowHeight = 0
            end
            row.offset = offset
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", x, -offset)
            row:SetSize(stripWidth, GROUP_TITLE_H + stripHeight)
            row.strip:SetSize(stripWidth, stripHeight)
            row.addButton:ClearAllPoints()
            row.addButton:SetPoint("TOPRIGHT", -STRIP_PAD, -STRIP_PAD)
            local active = selectedGroupIndex == groupIndex
            row.selection:SetShown(active)
            row.title:SetText(group.name or (L["BAR"] .. groupIndex))
            if active then UI.SetTextWhite(row.title) else UI.SetTextSubtle(row.title) end
            RegisterDropTarget(row.strip, groupIndex, groupScroll)
            row.strip.highlight = row.highlight
            local function Select(_, button)
                if button == "RightButton" then ShowGroupMenu(row.titleButton, groupIndex) else SelectGroup(groupIndex) end
            end
            row.titleButton:SetScript("OnClick", Select)
            row.selectButton:SetScript("OnClick", Select)
            row.deleteButton:SetScript("OnClick", function() DeleteGroup(groupIndex) end)
            row.deleteButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L["Delete Group"])
                GameTooltip:Show()
            end)
            row.deleteButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.addButton:SetScript("OnClick", function() ShowAddBarPopup(groupIndex) end)
            row.addButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L["Add Bar to:"] .. " " .. (group.name or L["Group"]))
                GameTooltip:Show()
            end)
            row.addButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
            if renameActiveGroupIndex == groupIndex then
                row.title:Hide()
                local box = row.renameBox
                if not box then
                    box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
                    box:SetPoint("TOPLEFT", 4, -1)
                    box:SetPoint("TOPRIGHT", -4, -1)
                    box:SetHeight(GROUP_TITLE_H - 2)
                    box:SetFontObject("CDM_Font14")
                    box:SetFrameLevel(row.titleButton:GetFrameLevel() + 2)
                    box:SetAutoFocus(false)
                    box:SetMaxLetters(40)
                    row.renameBox = box
                end
                local sameBox = renameActiveEditBox == box
                if not sameBox then box:SetText(group.name or L["Group"]) end
                box:SetScript("OnEditFocusLost", function()
                    CommitPendingRename(true)
                    RefreshAll()
                    RefreshSelection()
                end)
                box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
                box:SetScript("OnEscapePressed", function() CommitPendingRename(false); RefreshAll() end)
                renameActiveEditBox = box
                box:Show()
                if not sameBox then box:SetFocus(); box:HighlightText() end
            end
            for index = #bars + 1, #row.icons do row.icons[index]:Hide() end
            for index, bar in ipairs(bars) do
                M.NormalizeBar(bar)
                local button = AcquireBarIcon(row, index)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", STRIP_PAD + ICON_SIZE + ICON_GAP + ((index - 1) % columns) * (ICON_SIZE + ICON_GAP),
                    -STRIP_PAD - math.floor((index - 1) / columns) * (ICON_SIZE + ICON_GAP))
                button:SetSize(ICON_SIZE, ICON_SIZE)
                button.icon:SetTexture((bar.spellID and GetSpellTexture(bar.spellID)) or 134400)
                CDM_C.ApplyIconTexCoord(button.icon, CDM_C.GetEffectiveZoomAmount())
                local selected = selectedBar == bar
                if selected then
                    selectedIconTop = offset + GROUP_TITLE_H + STRIP_PAD
                        + math.floor((index - 1) / columns) * (ICON_SIZE + ICON_GAP)
                end
                button:SetBackdropBorderColor(selected and 1 or 0.08, selected and 0.82 or 0.08, selected and 0 or 0.08, 1)
                button.badge:SetText(bar.barType == M.TYPE_STACK and "|cff88bbffS|r" or "")
                button:SetScript("OnClick", function(_, mouseButton)
                    if mouseButton == "RightButton" then ShowBarMenu(button, bar); return end
                    CommitPendingRename(true)
                    selectedBar, selectedBarGroupIndex = bar, groupIndex
                    selectedGroupIndex, browserGroupIndex = nil, groupIndex
                    RefreshAll()
                    ShowBarSettings(bar, groupIndex)
                end)
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if bar.spellID then GameTooltip:SetSpellByID(bar.spellID) else GameTooltip:SetText(bar.name or L["Unknown"]) end
                    GameTooltip:AddLine(bar.barType == M.TYPE_STACK and L["Stack Bar"] or L["Timer Bar"], 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function() GameTooltip:Hide() end)
                button:SetScript("OnDragStart", function() GameTooltip:Hide(); StartDrag(bar) end)
                button:SetScript("OnDragStop", function() EndDrag() end)
            end
            x = x + stripWidth + GROUP_GAP
            rowHeight = math.max(rowHeight, row:GetHeight())
        end
        local height = math.max(1, offset + rowHeight)
        groupList:SetHeight(height)
        browserFrame:SetHeight(math.min(BROWSER_MAX_H, height))
        local active = groupRows[renameActiveGroupIndex or browserGroupIndex or 1]
        if selectedIconTop and not renameActiveGroupIndex then
            local scroll, viewHeight = groupScroll:GetVerticalScroll(), browserFrame:GetHeight()
            if selectedIconTop < scroll then
                groupScroll:SetVerticalScroll(selectedIconTop)
            elseif selectedIconTop + ICON_SIZE > scroll + viewHeight then
                groupScroll:SetVerticalScroll(selectedIconTop + ICON_SIZE - viewHeight)
            end
        elseif active then
            RevealGroup(active)
        end
    end

    RefreshAll = function()
        local groups, created = EnsureGroups()
        if not groups then ClearPanel(); return end
        if created then SaveAndRefresh() end
        if selectedBar then
            local found = false
            for index, group in ipairs(groups) do
                for _, bar in ipairs(group.bars or {}) do
                    if bar == selectedBar then
                        selectedBarGroupIndex, browserGroupIndex = index, index
                        found = true
                    end
                end
            end
            if not found then
                selectedBar, selectedBarGroupIndex = nil, nil
                ClearPanel()
            end
        elseif selectedGroupIndex then
            browserGroupIndex = selectedGroupIndex
        end
        if not browserGroupIndex or not groups[browserGroupIndex] then
            browserGroupIndex = 1
            if not selectedBar then selectedGroupIndex = 1 end
        end
        BuildBrowser()
        if preview:IsShown() then preview:Refresh() end
    end

    local lastBrowserWidth
    groupScroll:HookScript("OnSizeChanged", function(_, width)
        if width == lastBrowserWidth then return end
        lastBrowserWidth = width
        RefreshAll()
    end)

    page:SetScript("OnMouseUp", function() EndDrag() end)

    page:HookScript("OnHide", function()
        CommitPendingRename(true)
        if addBarPopup then addBarPopup:Hide() end
        StaticPopup_Hide("CDM_CONFIRM_DELETE_BARGROUP")
        StaticPopupDialogs["CDM_CONFIRM_DELETE_BARGROUP"]._pendingDelete = nil
        GameTooltip:Hide()
        panelManager.CloseDropdownMenus()
        CancelDrag()
    end)

    page:HookScript("OnShow", function()
        local spec = GetSpecialization()
        local newSpecID = spec and GetSpecializationInfo(spec) or nil
        if newSpecID ~= currentSpecID or CDM.db ~= currentDB then
            CommitPendingRename(false)
            currentSpecID = newSpecID
            currentDB = CDM.db
            selectedGroupIndex = nil
            selectedBar = nil
            selectedBarGroupIndex = nil
            browserGroupIndex = nil
            groupScroll:SetVerticalScroll(0)
            ClearPanel()
        end
        RefreshAll()
        RefreshSelection()
    end)
end

API:RegisterConfigTab("bars", L["Bars"], CreateBarsTab, 8)
