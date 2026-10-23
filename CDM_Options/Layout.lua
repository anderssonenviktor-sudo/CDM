local Runtime = _G["CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L

local generalExpanded = {}

local function CreateLayoutTab(page, tabId)
    local tabBar = UI.CreateSubTabBar(page, {
        { id = "cooldowns", label = L["Cooldowns"] },
        { id = "general", label = L["General"] },
        { id = "text", label = L["Text"] },
    }, "cooldowns", 100)

    local subPages = tabBar.subPages

    if ns._CreateCooldownGroupsPanel then
        ns._CreateCooldownGroupsPanel(subPages.cooldowns, page)
    end

    ns._CreateCooldownTextPanel(subPages.text, page)

    local generalPage = subPages.general

    local divider = generalPage:CreateTexture(nil, "ARTWORK")
    UI.StyleDivider(divider)
    divider:SetPoint("TOP", generalPage, "TOP", 0, 0)

    local content, scrollFrame = UI.CreateScrollableTab(generalPage, "CDM_LayoutGeneralScrollFrame", 520)
    local scrollChild = scrollFrame:GetScrollChild()

    local sections = {}

    local function UpdateScrollHeight()
        local height = 40
        for i, section in ipairs(sections) do
            height = height + section:GetHeight()
            if i > 1 then height = height + 14 end
        end
        content:SetHeight(height - 20)
        scrollChild:SetHeight(height)
    end

    local function CollapsibleSection(key, label, contentHeight)
        local section = CreateFrame("Frame", nil, content)
        section:SetWidth(520)
        local previous = sections[#sections]
        if previous then
            section:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -14)
        else
            section:SetPoint("TOPLEFT")
        end

        local header = CreateFrame("Button", nil, section)
        header:SetPoint("TOPLEFT")
        header:SetSize(520, 24)
        local arrow = header:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture("Interface\\AddOns\\CDM\\Media\\Textures\\collapse")
        arrow:SetPoint("LEFT")
        arrow:SetSize(14, 14)
        arrow:SetVertexColor(1, 0.82, 0, 1)
        local title = UI.CreateHeader(header, label)
        title:ClearAllPoints()
        title:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
        local highlight = header:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.82, 0, 0.08)

        local body = CreateFrame("Frame", nil, section)
        body:SetPoint("TOPLEFT", 0, -30)
        body:SetSize(520, contentHeight)
        local function UpdateSection()
            local expanded = generalExpanded[key] == true
            body:SetShown(expanded)
            arrow:SetRotation(expanded and 0 or math.pi / 2)
            section:SetHeight(expanded and (30 + contentHeight) or 24)
            UpdateScrollHeight()
        end
        function section:SetContentHeight(height)
            contentHeight = height
            body:SetHeight(height)
            UpdateSection()
        end
        header:SetScript("OnClick", function()
            generalExpanded[key] = not generalExpanded[key]
            UI.CloseAllDropdownMenus()
            UpdateSection()
        end)
        sections[#sections + 1] = section
        UpdateSection()
        return section, body
    end

    local _, swipe = CollapsibleSection("swipe", L["Cooldown Swipe"], 108)

    generalPage.hideGCDSwipeCheckbox = UI.CreateModernCheckbox(
        swipe,
        L["Hide GCD Swipe"],
        CDM.db.hideGCDSwipe,
        function(checked)
            CDM.db.hideGCDSwipe = checked
            API:Refresh("STYLE")
        end
    )
    generalPage.hideGCDSwipeCheckbox:SetPoint("TOPLEFT")

    local swipeColorLabel = swipe:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    swipeColorLabel:SetText(L["Swipe Color"])
    swipeColorLabel:SetPoint("TOPLEFT", generalPage.hideGCDSwipeCheckbox, "BOTTOMLEFT", 0, -14)

    local swipeInit = CDM.db.swipeColor or { r = 0, g = 0, b = 0, a = 0.6 }
    local swipeColorPicker = UI.CreateSimpleColorPicker(swipe, swipeInit, function(r, g, b)
        CDM.db.swipeColor = { r = r, g = g, b = b, a = CDM.db.swipeColor and CDM.db.swipeColor.a or 0.6 }
        API:Refresh("STYLE")
    end)
    swipeColorPicker:SetPoint("LEFT", swipeColorLabel, "RIGHT", 6, 0)

    local swipeAlphaSlider = UI.CreateModernSlider(swipe, L["Swipe Opacity"], 0, 100,
        math.floor((swipeInit.a or 0.6) * 100),
        function(v)
            local sc = CDM.db.swipeColor or { r = 0, g = 0, b = 0, a = 0.6 }
            CDM.db.swipeColor = { r = sc.r, g = sc.g, b = sc.b, a = v / 100 }
            API:Refresh("STYLE")
        end)
    swipeAlphaSlider:SetPoint("TOPLEFT", swipeColorLabel, "BOTTOMLEFT", 0, -10)

    local _, layout = CollapsibleSection("layout", L["Layout Settings"], 40)

    generalPage.controls.l1 = UI.CreateModernSlider(layout, L["Icon Spacing"], -1, 30, CDM.db.spacing, function(v) CDM.db.spacing = v; API:Refresh("LAYOUT") end)
    generalPage.controls.l1:SetPoint("TOPLEFT")

    local _, essential = CollapsibleSection("essential", L["Essential"], 240)

    local maxRowEssSlider = UI.CreateModernSlider(essential, L["Max Icons Per Row"], 1, 20, CDM.db.maxRowEss, function(v)
        CDM.db.maxRowEss = v; API:Refresh("LAYOUT")
    end)
    maxRowEssSlider:SetPoint("TOPLEFT")

    local row1Width = ns.CreateIconSizeSlider(essential, L["Row 1 Width"], "sizeEssRow1", "w")
    row1Width:SetPoint("TOPLEFT", maxRowEssSlider, "BOTTOMLEFT", 0, -10)
    local row1Height = ns.CreateIconSizeSlider(essential, L["Row 1 Height"], "sizeEssRow1", "h")
    row1Height:SetPoint("TOPLEFT", row1Width, "BOTTOMLEFT", 0, -10)
    local row2Width = ns.CreateIconSizeSlider(essential, L["Row 2 Width"], "sizeEssRow2", "w")
    row2Width:SetPoint("TOPLEFT", row1Height, "BOTTOMLEFT", 0, -10)
    local row2Height = ns.CreateIconSizeSlider(essential, L["Row 2 Height"], "sizeEssRow2", "h")
    row2Height:SetPoint("TOPLEFT", row2Width, "BOTTOMLEFT", 0, -10)

    local utilitySection, utility = CollapsibleSection("utility", L["Utility"], 135)

    local utilityWidth = ns.CreateIconSizeSlider(utility, L["Width"], "sizeUtility", "w")
    utilityWidth:SetPoint("TOPLEFT")
    local utilityHeight = ns.CreateIconSizeSlider(utility, L["Height"], "sizeUtility", "h")
    utilityHeight:SetPoint("TOPLEFT", utilityWidth, "BOTTOMLEFT", 0, -10)

    local wrapCheckbox, utilWrapSlider, unlockCheckbox, xOffsetSlider, verticalCheckbox

    local function UpdateUnlockControls()
        local wrapOn = CDM.db.utilityWrap == true
        local unlockOn = CDM.db.utilityUnlock == true
        utilWrapSlider:SetShown(wrapOn)
        unlockCheckbox:SetShown(wrapOn)
        xOffsetSlider:SetShown(wrapOn and unlockOn)
        verticalCheckbox:SetShown(wrapOn and unlockOn)
        utilitySection:SetContentHeight(wrapOn and (unlockOn and 315 or 225) or 135)
    end

    wrapCheckbox = UI.CreateModernCheckbox(
        utility,
        L["Wrap Utility Bar"],
        CDM.db.utilityWrap,
        function(checked)
            CDM.db.utilityWrap = checked
            UpdateUnlockControls()
            API:Refresh("LAYOUT")
        end
    )
    wrapCheckbox:SetPoint("TOPLEFT", utilityHeight, "BOTTOMLEFT", 0, -15)

    utilWrapSlider = UI.CreateModernSlider(utility, L["Utility Max Icons Per Row"], 1, 20, CDM.db.maxRowUtil, function(v)
        CDM.db.maxRowUtil = v; API:Refresh("LAYOUT")
    end)
    utilWrapSlider:SetPoint("TOPLEFT", wrapCheckbox, "BOTTOMLEFT", 0, -10)

    unlockCheckbox = UI.CreateModernCheckbox(
        utility,
        L["Unlock Utility Bar"],
        CDM.db.utilityUnlock,
        function(checked)
            CDM.db.utilityUnlock = checked
            UpdateUnlockControls()
            API:Refresh("LAYOUT")
        end
    )
    unlockCheckbox:SetPoint("TOPLEFT", utilWrapSlider, "BOTTOMLEFT", 0, -10)

    xOffsetSlider = UI.CreateModernSlider(utility, L["Utility X Offset"], -600, 600, CDM.db.utilityXOffset, function(v)
        CDM.db.utilityXOffset = v; API:Refresh("LAYOUT")
    end)
    xOffsetSlider:SetPoint("TOPLEFT", unlockCheckbox, "BOTTOMLEFT", 0, -10)

    verticalCheckbox = UI.CreateModernCheckbox(
        utility,
        L["Display Vertical"],
        CDM.db.utilityVertical,
        function(checked)
            CDM.db.utilityVertical = checked
            UpdateUnlockControls()
            API:Refresh("LAYOUT")
        end
    )
    verticalCheckbox:SetPoint("TOPLEFT", xOffsetSlider, "BOTTOMLEFT", 0, -10)

    UpdateUnlockControls()
    generalPage:HookScript("OnShow", UpdateScrollHeight)
end

API:RegisterConfigTab("layout", L["Cooldowns"], CreateLayoutTab, 2)
