local Runtime = _G["CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local L = Runtime.L
local CDM_C = CDM and CDM.CONST or {}
local UI = ns.ConfigUI
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local ConfigFrame = nil
local categories = {}
local buttons = {}
local currentTab = nil
local ADDON_NAME = "CDM"
local versionText = nil
local footerRefreshRegistered = false
local lastFooterFont = nil
local combatCloseRegistered = false
local hidingForAnchorMode = false
local SCROLL_FRAME_NAMES = {
    resources = "CDM_ResourcesScrollFrame",
    bars = "CDM_BarsScrollFrame",
    castbar = "CDM_CastBarScrollFrame",
    buffgroups = "CDM_BuffGroupsLeftScroll",
}

local function GetAddonVersionText()
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")

    if not version or version == "" then
        return nil
    end

    return "v" .. tostring(version)
end

local function ApplyFooterTextStyle(fontString)
    if not fontString then return end

    local db = CDM.db or {}
    local defaults = CDM.defaults or {}
    local fontName = db.textFont or defaults.textFont or "Expressway"
    local fontOutline = nil
    local fontPath = (LSM and LSM:Fetch("font", fontName)) or CDM_C.FONT_PATH
    local fontSize = (CDM.Pixel and CDM.Pixel.FontSize(18)) or 18

    fontString:SetFontObject("CDM_GameFontHighlightSmall")
    local setOk = fontString:SetFont(fontPath, fontSize, fontOutline)
    if not setOk then
        fontString:SetFont(CDM_C.FONT_PATH, fontSize, fontOutline)
    end
end

local function ApplyAllFooterTextStyles()
    local currentFont = CDM.db and CDM.db.textFont
    if currentFont == lastFooterFont then return end
    lastFooterFont = currentFont
    ApplyFooterTextStyle(versionText)
end

local function PrintConfigCombatBlocked(actionLabel)
    print("|cffff0000" .. string.format(L["Cannot %s while in combat"], actionLabel or L["open CDM config"]) .. "|r")
end

local function HideConfigPopups()
    if not StaticPopup_Hide then
        return
    end

    StaticPopup_Hide("CDM_COPY_URL")
    StaticPopup_Hide("CDM_CONFIRM_RESET_PROFILE")
    StaticPopup_Hide("CDM_CONFIRM_COPY_PROFILE")
    StaticPopup_Hide("CDM_CONFIRM_DELETE_PROFILE")
    StaticPopup_Hide("CDM_CONFIRM_IMPORT_ALL_AYIJE_PROFILES")
    StaticPopup_Hide("CDM_CONFIRM_DELETE_GROUP")
    StaticPopup_Hide("CDM_CONFIRM_DELETE_CD_GROUP")
end

local function HideConfigUiForCombat()
    local frame = ConfigFrame or ns.ConfigFrame
    if frame and frame.IsShown and frame:IsShown() then
        if UI and UI.CloseAllDropdownMenus then
            UI.CloseAllDropdownMenus()
        end
        frame:Hide()
    end
    HideConfigPopups()
end

local function RegisterCombatConfigAutoClose()
    if combatCloseRegistered then return end
    combatCloseRegistered = true

    CDM:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        HideConfigUiForCombat()
    end)
end

RegisterCombatConfigAutoClose()

local function SetCategoryButtonState(button, isActive)
    button.Selection:SetShown(isActive)
    if isActive then
        button.Background:SetColorTexture(1, 1, 1, 0.055)
        button.Background:Show()
        UI.SetTextWhite(button.Text)
        return
    end

    button.Background:Hide()
    UI.SetTextInactive(button.Text)
end

-- Tab pages are created empty and populated the first time they are selected.
-- Building all of them up front costs ~120 CreateFrame calls plus the widgets
-- each builder makes, all to show one page and hide the rest.
local function EnsureCategoryBuilt(id)
    local page = categories[id]
    if not page or page.acdmBuilt then return end

    local tabDef = ns.ConfigTabs and ns.ConfigTabs[id]
    if not tabDef or not tabDef.createFunc then return end

    page.acdmBuilt = true
    tabDef.createFunc(page, id)
end

local function SelectCategory(id)
    if UI and UI.CloseAllDropdownMenus then
        UI.CloseAllDropdownMenus()
    end
    -- The Cooldowns editor reuses the Buff per-spell override renderer for
    -- tracked Buff icons placed in cooldown rows.
    if id == "layout" then
        EnsureCategoryBuilt("buffgroups")
    end
    -- Must precede the SetShown pass below: builders install OnShow handlers
    -- that have to be attached before the page is shown.
    EnsureCategoryBuilt(id)
    currentTab = id
    for categoryId, frame in pairs(categories) do frame:SetShown(categoryId == id) end
    for buttonId, btn in pairs(buttons) do
        SetCategoryButtonState(btn, buttonId == id)
    end

    local scrollFrameName = SCROLL_FRAME_NAMES[id]
    if scrollFrameName then
        local scrollFrame = _G[scrollFrameName]
        if scrollFrame then
            scrollFrame:SetVerticalScroll(0)
        end
    end

end

ns.ConfigSelectCategory = SelectCategory

local function CreateCategoryPage(id, name, Content)
    local page = CreateFrame("Frame", nil, Content)
    page:SetAllPoints()
    page:Hide()
    page.controls = {}
    categories[id] = page
    return page
end

ns.ConfigCreatePage = CreateCategoryPage

local categoryHeaders = {
    { tabs = {"layout", "buffgroups", "bars", "glow", "castbar", "resources", "border"} },
    { divider = true, tabs = {"profiles"} },
}

local function CreateConfigFrame()
    if ConfigFrame then return end

    ConfigFrame = UI.CreateConfigWindow(UIParent, "CDMConfigFrame")
    ConfigFrame:SetSize(920, 720)
    ConfigFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    ConfigFrame:SetFrameStrata("HIGH")
    ConfigFrame:Hide()
    if not tContains(UISpecialFrames, "CDMConfigFrame") then
        tinsert(UISpecialFrames, "CDMConfigFrame")
    end
    ConfigFrame:EnableKeyboard(true)
    ConfigFrame:SetPropagateKeyboardInput(true)
    ConfigFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    ConfigFrame:HookScript("OnHide", function()
        if UI and UI.CloseAllDropdownMenus then
            UI.CloseAllDropdownMenus()
        end
        HideConfigPopups()
        if CDM.SetConfigWindowActive then
            CDM:SetConfigWindowActive(false)
        end
    end)
    ConfigFrame:HookScript("OnShow", function()
        ConfigFrame:SetPropagateKeyboardInput(true)
        if CDM.SetConfigWindowActive then
            CDM:SetConfigWindowActive(true)
        end
    end)

    local titleContainer = CreateFrame("Frame", nil, ConfigFrame)
    titleContainer:SetPoint("TOPLEFT", ConfigFrame, "TOPLEFT", 0, 0)
    titleContainer:SetPoint("TOPRIGHT", ConfigFrame, "TOPRIGHT", 0, 0)
    titleContainer:SetHeight(52)
    titleContainer:SetFrameLevel(ConfigFrame:GetFrameLevel() + 10)

    local titleLogo = titleContainer:CreateTexture(nil, "OVERLAY")
    titleLogo:SetSize(112, 112)
    -- The logo artwork sits slightly below the center of its transparent canvas.
    titleLogo:SetPoint("CENTER", titleContainer, "CENTER", 0, 3)
    titleLogo:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\cdmlightning2.tga")

    local function CreateHeaderIconButton(textureName, iconSize, yOffset)
        local button = CreateFrame("Button", nil, titleContainer)
        button:SetSize(44, 44)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        -- Center the visible artwork, accounting for its transparent padding.
        icon:SetPoint("CENTER", 0, yOffset or 0)
        icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\" .. textureName .. ".tga")
        icon:SetVertexColor(1, 0.82, 0, 1)
        icon:SetAlpha(0.82)
        button:HookScript("OnEnter", function() icon:SetAlpha(1) end)
        button:HookScript("OnLeave", function() icon:SetAlpha(button:IsEnabled() and 0.82 or 0.35) end)
        local function UpdateEnabledState()
            icon:SetAlpha(button:IsEnabled() and 0.82 or 0.35)
        end
        hooksecurefunc(button, "Enable", UpdateEnabledState)
        hooksecurefunc(button, "Disable", UpdateEnabledState)
        hooksecurefunc(button, "SetEnabled", UpdateEnabledState)
        return button
    end

    local cdmBtn = CreateHeaderIconButton("wrench", 50, 1)
    cdmBtn:SetPoint("LEFT", titleContainer, "LEFT", 16, 0)
    cdmBtn:SetScript("OnClick", function()
        if not CooldownViewerSettings then return end
        if CooldownViewerSettings:IsVisible() then
            securecall("HideUIPanel", CooldownViewerSettings)
        else
            securecall("ShowUIPanel", CooldownViewerSettings)
        end
    end)

    local editModeBtn = CreateHeaderIconButton("eye2", 64, 1)
    editModeBtn:SetPoint("LEFT", cdmBtn, "RIGHT", 4, 0)
    editModeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Edit Mode Settings"])
        GameTooltip:Show()
    end)
    editModeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local editModeOverlay
    editModeBtn:SetScript("OnClick", function()
        if not ns.CreateEditModeOverlay then return end
        if not editModeOverlay then
            editModeOverlay = ns.CreateEditModeOverlay()
        end
        editModeOverlay:Show()
    end)

    local anchorBtn = CreateHeaderIconButton("anchor2", 38)
    anchorBtn:SetPoint("LEFT", editModeBtn, "RIGHT", 2, 0)
    anchorBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Unlock Anchors"])
        GameTooltip:Show()
    end)
    anchorBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    anchorBtn:SetScript("OnClick", function()
        if not (ns.ToggleAnchorMode and ns.IsAnchorModeActive) then return end
        if InCombatLockdown() then return end
        hidingForAnchorMode = true
        ConfigFrame:Hide()
        hidingForAnchorMode = false
        ns.ToggleAnchorMode(anchorBtn)
        if not ns.IsAnchorModeActive() then ConfigFrame:Show() end
    end)

    ConfigFrame:HookScript("OnHide", function()
        if not hidingForAnchorMode and ns.CloseAnchorMode then
            ns.CloseAnchorMode(false)
        end
    end)

    ConfigFrame:SetMovable(true)
    ConfigFrame:EnableMouse(true)
    ConfigFrame:RegisterForDrag("LeftButton")
    ConfigFrame:SetScript("OnDragStart", ConfigFrame.StartMoving)
    ConfigFrame:SetScript("OnDragStop", ConfigFrame.StopMovingOrSizing)

    local panelBgHolder = CreateFrame("Frame", nil, ConfigFrame, "BackdropTemplate")
    panelBgHolder:SetPoint("TOPLEFT", titleContainer, "BOTTOMLEFT", 8, 0)
    panelBgHolder:SetPoint("BOTTOMRIGHT", ConfigFrame, "BOTTOMRIGHT", -8, 25)
    panelBgHolder:SetBackdrop({
        bgFile = CDM_C.TEX_WHITE8X8,
        edgeFile = CDM_C.TEX_WHITE8X8,
        edgeSize = 1,
    })
    panelBgHolder:SetBackdropColor(0.065, 0.065, 0.065, 0.4)
    panelBgHolder:SetBackdropBorderColor(0.25, 0.25, 0.27, 1)

    versionText = ConfigFrame:CreateFontString(nil, "OVERLAY")
    versionText:SetPoint("BOTTOMRIGHT", ConfigFrame, "BOTTOMRIGHT", -16, 6)
    ApplyFooterTextStyle(versionText)
    versionText:SetText(GetAddonVersionText() or "")
    if UI and UI.SetTextFaint then
        UI.SetTextFaint(versionText)
    else
        versionText:SetTextColor(0.5, 0.5, 0.5, 1)
    end

    local Sidebar = CreateFrame("Frame", nil, ConfigFrame)
    Sidebar:SetPoint("TOPLEFT", panelBgHolder, "TOPLEFT", 1, 0)
    Sidebar:SetPoint("BOTTOMLEFT", panelBgHolder, "BOTTOMLEFT", 1, 0)
    Sidebar:SetWidth(180)

    local sidebarDivider = panelBgHolder:CreateTexture(nil, "BORDER")
    sidebarDivider:SetColorTexture(0.22, 0.22, 0.24, 0.45)
    sidebarDivider:SetWidth(1)
    sidebarDivider:SetPoint("TOPLEFT", Sidebar, "TOPRIGHT", 16, -12)
    sidebarDivider:SetPoint("BOTTOMLEFT", Sidebar, "BOTTOMRIGHT", 16, 12)

    local Content = CreateFrame("Frame", nil, ConfigFrame)
    Content:SetPoint("TOPLEFT", Sidebar, "TOPRIGHT", 35, 0)
    Content:SetPoint("BOTTOMRIGHT", panelBgHolder, "BOTTOMRIGHT", -13, 0)

    ns.ConfigContent = Content
    ns.ConfigFrame = ConfigFrame
    ns.ConfigSidebar = Sidebar

    local sortedTabs = {}
    for id, tabDef in pairs(ns.ConfigTabs or {}) do
        table.insert(sortedTabs, tabDef)
    end
    table.sort(sortedTabs, function(a, b) return a.navOrder < b.navOrder end)

    -- Pages only; each tab's contents are built lazily by EnsureCategoryBuilt.
    for _, tabDef in ipairs(sortedTabs) do
        CreateCategoryPage(tabDef.id, tabDef.label, Content)
    end

    local function AddNav(id, label, y, indent)
        indent = indent or 0
        local btn = CreateFrame("Button", nil, Sidebar)
        btn:SetSize(175 - indent, 32)
        btn:SetPoint("TOPLEFT", indent, y)

        btn.Background = btn:CreateTexture(nil, "BACKGROUND")
        btn.Background:SetAllPoints()

        btn.Selection = btn:CreateTexture(nil, "ARTWORK")
        btn.Selection:SetColorTexture(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 0.85)
        btn.Selection:SetWidth(2)
        btn.Selection:SetPoint("TOPLEFT", 4, -7)
        btn.Selection:SetPoint("BOTTOMLEFT", 4, 7)

        btn.Text = btn:CreateFontString(nil, "OVERLAY", "CDM_Font14")
        btn.Text:SetPoint("LEFT", btn, "LEFT", 14, 0)
        btn.Text:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
        btn.Text:SetJustifyH("LEFT")
        btn.Text:SetWordWrap(false)
        btn.Text:SetText(label)
        SetCategoryButtonState(btn, false)

        btn:SetScript("OnEnter", function(self)
            if currentTab ~= id then
                self.Background:SetColorTexture(1, 1, 1, 0.035)
                self.Background:Show()
                UI.SetTextWhite(self.Text)
            end
        end)

        btn:SetScript("OnLeave", function(self)
            SetCategoryButtonState(self, currentTab == id)
        end)

        btn:SetScript("OnClick", function() SelectCategory(id) end)
        buttons[id] = btn
    end

    local yOffset = -12
    local tabIndent = 8

    for _, category in ipairs(categoryHeaders) do
        if category.divider then
            local divider = Sidebar:CreateTexture(nil, "ARTWORK")
            divider:SetColorTexture(0.3, 0.3, 0.32, 0.4)
            divider:SetSize(147, 1)
            divider:SetPoint("TOPLEFT", 22, yOffset - 10)
            yOffset = yOffset - 30
        end

        for _, tabId in ipairs(category.tabs) do
            local tabDef = ns.ConfigTabs and ns.ConfigTabs[tabId]
            if tabDef then
                AddNav(tabDef.id, tabDef.label, yOffset, tabIndent)
                yOffset = yOffset - 38
            end
        end

    end

    -- open on the sidebar's first entry (navOrder only governs page build order)
    local firstNavTab = categoryHeaders[1] and categoryHeaders[1].tabs[1]
    if firstNavTab and ns.ConfigTabs and ns.ConfigTabs[firstNavTab] then
        SelectCategory(firstNavTab)
    elseif sortedTabs[1] then
        SelectCategory(sortedTabs[1].id)
    end

    if not footerRefreshRegistered then
        API:RegisterRefreshCallback("configFooterTextStyle", function()
            ApplyAllFooterTextStyles()
        end, 95, { "STYLE" })
        footerRefreshRegistered = true
    end
end

function API:ShowConfig(targetTab)
    if InCombatLockdown() then
        PrintConfigCombatBlocked(L["open CDM config"])
        return
    end

    if not ConfigFrame then CreateConfigFrame() end
    ConfigFrame:Show()

    -- Jumping to a tab does not need the full teardown/rebuild that
    -- RebuildConfigFrame does; that is only for discarding stale state.
    if targetTab == "importexport" then
        SelectCategory("profiles")
        if ns.SelectProfilesSubTab then ns.SelectProfilesSubTab("importexport") end
    elseif targetTab and ns.ConfigTabs and ns.ConfigTabs[targetTab] then
        SelectCategory(targetTab)
    end
end

function API:RebuildConfigFrame(targetTab)
    if InCombatLockdown() then
        PrintConfigCombatBlocked(L["rebuild CDM config"])
        return
    end

    if ConfigFrame then
        API:UnregisterPositionSliderUpdater("essential")
        API:UnregisterPositionSliderUpdater("buff")
        API:UnregisterPositionSliderUpdater("buffBar")

        API:UnregisterRefreshCallback("configFooterTextStyle")
        footerRefreshRegistered = false
        if ns.CancelImportStatusTimer then
            ns.CancelImportStatusTimer()
        end

        ConfigFrame:Hide()
        ConfigFrame:SetParent(nil)  -- orphan for GC
        ConfigFrame = nil
        categories = {}
        buttons = {}
        currentTab = nil
        versionText = nil
        ns.ConfigFrame = nil
        ns.ConfigContent = nil
        ns.ConfigSidebar = nil
        ns.SelectProfilesSubTab = nil
    end
    CreateConfigFrame()
    ConfigFrame:Show()

    local tabToSelect = targetTab == "importexport" and "profiles" or (targetTab or "profiles")
    if not (ns.ConfigTabs and ns.ConfigTabs[tabToSelect]) then
        tabToSelect = "profiles"
    end
    if ns.ConfigTabs and ns.ConfigTabs[tabToSelect] then
        SelectCategory(tabToSelect)
        if targetTab == "importexport" and ns.SelectProfilesSubTab then
            ns.SelectProfilesSubTab("importexport")
        end
    end
end
