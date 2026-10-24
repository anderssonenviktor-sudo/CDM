local Runtime = _G["CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L
local Shared = ns.GroupEditorShared or {}

local function OnResourcesSpecChanged()
    if not ns.ConfigFrame or not ns.ConfigFrame:IsShown() then return end
    C_Timer.After(0.3, function()
        if not ns.ConfigFrame or not ns.ConfigFrame:IsShown() then return end
        API:RebuildConfigFrame("resources")
    end)
end
API:RegisterSpecStateHandler(OnResourcesSpecChanged)

local CLASS_DISPLAY_NAMES = {
    WARRIOR = L["Warrior"], PALADIN = L["Paladin"], HUNTER = L["Hunter"],
    ROGUE = L["Rogue"], PRIEST = L["Priest"], DEATHKNIGHT = L["Death Knight"],
    SHAMAN = L["Shaman"], MAGE = L["Mage"], WARLOCK = L["Warlock"],
    MONK = L["Monk"], DRUID = L["Druid"], DEMONHUNTER = L["Demon Hunter"],
    EVOKER = L["Evoker"],
}

local BAR_DISPLAY_NAMES = ns.BAR_DISPLAY_NAMES

local IsBarActiveForSpec = ns.IsBarActiveForSpec

local SECONDARY_COLOR_FIELDS = {
    Runes = { { key = "rechargingColor", label = L["Recharging"] } },
    Essence = {
        { key = "rechargingColor", label = L["Recharging"] },
        { key = "nearlyCapColor", label = L["Nearly Capped"] },
        { key = "capColor", label = L["Capped"] },
    },
    SoulShards = { { key = "rechargingColor", label = L["Partial Fill"] } },
    Flurry = { { key = "rechargingColor", label = L["Recharging"] } },
    FireBlast = { { key = "rechargingColor", label = L["Recharging"] } },
    Prescience = { { key = "rechargingColor", label = L["Recharging"] } },
    ComboPoints = {
        ROGUE = {
            { key = "chargedColor", label = L["Charged"] },
            { key = "chargedEmptyColor", label = L["Charged Empty"] },
        },
        DRUID = {
            { key = "overflowingColor", label = L["Overflowing"] },
            { key = "overflowingEmptyColor", label = L["Overflowing Empty"] },
        },
    },
}

-- Bars that show a per-pip recharge countdown instead of a value tag. These
-- also skip the Conditions tab, which doesn't apply to them.
local USES_RECHARGE_TEXT = {
    Flurry = true, FireBlast = true, Prescience = true,
}

local LEFT_INSET = Shared.LEFT_INSET or 35
local SLIDER_LABEL_W = 180
local SLIDER_W = 280
local CONTROL_X = SLIDER_LABEL_W + 4

local function CreateBarColorPicker(parent, label, classKey, barKey, settingKey)
    local color = CDM:GetBarSettingForClass(classKey, barKey, settingKey) or { r = 1, g = 1, b = 1 }

    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(250, 22)

    local nameText = row:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    nameText:SetPoint("LEFT", 0, 0)
    nameText:SetText(label)

    local picker = UI.CreateSimpleColorPicker(row, color, function(r, g, b, a)
        CDM:SetBarSettingForClass(classKey, barKey, settingKey, { r = r, g = g, b = b, a = a or 1 })
        API:Refresh("RESOURCES")
    end, true)
    picker:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)

    row.picker = picker
    row.nameText = nameText
    return row
end

local function ReadTicksConfig(classKey, barKey)
    local stored = CDM:GetBarSettingForClass(classKey, barKey, "ticks")
    local color = stored and stored.color
    local cfg = {
        enabled   = stored and stored.enabled or false,
        color     = {
            r = color and color.r or 1,
            g = color and color.g or 1,
            b = color and color.b or 1,
            a = color and color.a or 1,
        },
        thickness = stored and stored.thickness or 2,
        values    = {},
    }
    if stored and stored.values then
        for i, v in ipairs(stored.values) do
            if i > CDM.CONST.MAX_TICKS_PER_BAR then break end
            cfg.values[i] = v
        end
    end
    return cfg
end

local function WriteTicksConfig(classKey, barKey, cfg)
    CDM:SetBarSettingForClass(classKey, barKey, "ticks", cfg)
    API:Refresh("RESOURCES")
end

local function BuildTicksSection(rc, classKey, barKey, startYOff)
    if not CDM.CONST.BAR_KEYS_SUPPORTING_TICKS[barKey] then return startYOff end

    local container = CreateFrame("Frame", nil, rc)
    container:SetPoint("TOPLEFT", 0, startYOff)
    container:SetPoint("RIGHT", rc, "RIGHT", 0, 0)
    container:SetHeight(1)

    local sectionHeight = 0

    local function Rebuild()
        UI.ClearChildren(container)
        local cfg = ReadTicksConfig(classKey, barKey)
        local y = 0

        local header = UI.CreateHeader(container, L["Ticks"])
        header:SetPoint("TOPLEFT", 0, y)
        y = y - 25

        local enableCB = UI.CreateModernCheckbox(container, L["Show Tick"],
            cfg.enabled,
            function(checked)
                cfg.enabled = checked and true or false
                WriteTicksConfig(classKey, barKey, cfg)
            end)
        enableCB:SetPoint("TOPLEFT", 0, y)

        local colorRow = CreateFrame("Frame", nil, container)
        colorRow:SetSize(180, 22)
        colorRow:SetPoint("TOPLEFT", 160, y)

        local colorLabel = colorRow:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        colorLabel:SetPoint("LEFT", 0, 0)
        colorLabel:SetText(L["Tick Color"])

        local colorPicker = UI.CreateSimpleColorPicker(colorRow, cfg.color, function(r, g, b, a)
            cfg.color = { r = r, g = g, b = b, a = a or 1 }
            WriteTicksConfig(classKey, barKey, cfg)
        end, true)
        colorPicker:SetPoint("LEFT", colorLabel, "RIGHT", 8, 0)

        y = y - 32

        local thickSlider = UI.CreateModernSlider(container, L["Thickness"], 1, 5,
            cfg.thickness or 2,
            function(v)
                cfg.thickness = UI.RoundToInt(v)
                WriteTicksConfig(classKey, barKey, cfg)
            end, SLIDER_LABEL_W, SLIDER_W)
        thickSlider:SetPoint("TOPLEFT", 0, y)
        y = y - 60

        local placeLabel = container:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        placeLabel:SetText(L["Tick Placement"])
        placeLabel:SetPoint("TOPLEFT", 0, y)
        y = y - 22

        for i = 1, #cfg.values do
            local row = CreateFrame("Frame", nil, container)
            row:SetSize(160, 24)
            row:SetPoint("TOPLEFT", 0, y)

            local valBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            valBox:SetSize(80, 22)
            valBox:SetPoint("LEFT", 6, 0)
            valBox:SetAutoFocus(false)
            valBox:SetNumeric(false)
            valBox:SetText(tostring(cfg.values[i]))
            valBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            valBox:SetScript("OnEscapePressed", function(self)
                self:SetText(tostring(cfg.values[i] or 0))
                self:ClearFocus()
            end)
            valBox:SetScript("OnEditFocusLost", function(self)
                local num = tonumber(self:GetText())
                if num and num >= 0 and num ~= cfg.values[i] then
                    cfg.values[i] = num
                    WriteTicksConfig(classKey, barKey, cfg)
                end
            end)

            local delBtn = UI.CreateTextButton(row)
            delBtn:SetSize(20, 20)
            delBtn:SetText("X")
            delBtn:SetPoint("LEFT", valBox, "RIGHT", 6, 0)
            delBtn:SetScript("OnClick", function()
                table.remove(cfg.values, i)
                WriteTicksConfig(classKey, barKey, cfg)
                Rebuild()
            end)

            y = y - 26
        end

        if #cfg.values < CDM.CONST.MAX_TICKS_PER_BAR then
            local addBtn = UI.CreateTextButton(container)
            addBtn:SetSize(60, 22)
            addBtn:SetText(L["Add"])
            addBtn:SetPoint("TOPLEFT", 0, y)
            addBtn:SetScript("OnClick", function()
                cfg.values[#cfg.values + 1] = 0
                WriteTicksConfig(classKey, barKey, cfg)
                Rebuild()
            end)
            y = y - 26
        end

        local prevHeight = sectionHeight
        sectionHeight = math.abs(y)
        container:SetHeight(sectionHeight)
        if prevHeight > 0 and sectionHeight ~= prevHeight then
            rc:SetHeight((rc:GetHeight() or 0) + (sectionHeight - prevHeight))
        end
    end

    Rebuild()
    return startYOff - sectionHeight
end


local function CreateResourcesTab(page, tabId)
    local _, playerClass = UnitClass("player")
    local currentSpecID = API:GetCurrentSpecID()

    local selectedClassKey = nil
    local selectedBarKey = nil
    page.controls = page.controls or {}
    local enabled = CDM.db.resourcesEnabled ~= false
    page.controls.resourcesEnabled = UI.CreateModernCheckbox(
        page, L["Enable Resources"], enabled,
        function(checked)
            CDM.db.resourcesEnabled = checked
            API:Refresh("RESOURCES", "LAYOUT")
        end
    )
    page.controls.resourcesEnabled:SetPoint("TOPLEFT", LEFT_INSET + 285, -20)
    page.controls.resourcesEnabled:SetWidth(170)

    local resourceLabel = page:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    resourceLabel:SetText(L["Resource"])
    resourceLabel:SetPoint("TOPLEFT", LEFT_INSET, -27)

    local resourceDropdown = UI.CreateDropdown(page, "CDM_Font14")
    resourceDropdown:SetPoint("LEFT", resourceLabel, "LEFT", 70, 0)
    resourceDropdown:SetSize(200, 30)
    resourceDropdown:SetDefaultText(L["Select a resource bar to configure"])

    local rightArea = CreateFrame("Frame", nil, page)
    rightArea:SetPoint("TOPLEFT", LEFT_INSET, -65)
    rightArea:SetPoint("BOTTOMRIGHT", -10, 20)

    local tabInfo = {
        { id = "appearance", label = L["Appearance"] },
        { id = "layout", label = L["Layout"] },
        { id = "text", label = L["Text"] },
        { id = "conditions", label = L["Conditions"] },
        { id = "load", label = L["Load"] },
    }
    local subTabs = UI.CreateSubTabBar(rightArea, tabInfo, "appearance")
    subTabs.barFrame:ClearAllPoints()
    subTabs.barFrame:SetPoint("TOPLEFT", 0, -2)
    subTabs.barFrame:SetPoint("TOPRIGHT", -20, -2)

    local divider = rightArea:CreateTexture(nil, "ARTWORK")
    UI.StyleDivider(divider)
    divider:SetPoint("TOPLEFT", subTabs.barFrame, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", subTabs.barFrame, "BOTTOMRIGHT")

    local managers = {}
    for _, info in ipairs(tabInfo) do
        local pg = subTabs.subPages[info.id]
        pg:ClearAllPoints()
        pg:SetPoint("TOPLEFT", subTabs.barFrame, "BOTTOMLEFT", 0, -15)
        pg:SetPoint("BOTTOMRIGHT", rightArea, "BOTTOMRIGHT")
        local placeholder = pg:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        placeholder:SetPoint("CENTER")
        placeholder:SetText(L["Select a resource bar to configure"])
        UI.SetTextMuted(placeholder)
        managers[info.id] = Shared.CreateRightPanelManager(pg, placeholder, Shared.DestroyFrame)
    end
    local condPage = subTabs.subPages.conditions
    local condManager = managers.conditions
    local loadPage = subTabs.subPages.load
    local loadManager = managers.load

    local currentSubTab = "appearance"
    local origSelectTab = subTabs.selectTab
    subTabs.selectTab = function(id)
        currentSubTab = id
        origSelectTab(id)
    end
    -- The helper's click handlers capture its original selector.
    for _, info in ipairs(tabInfo) do
        subTabs.tabButtons[info.id]:SetScript("OnClick", function() subTabs.selectTab(info.id) end)
    end

    local ShowBarSettings

    local function BuildAppearance(rc, rightManager, classKey, barKey)
        local yOff = -6
        local colorHeader = UI.CreateHeader(rc, L["Colors"])
        colorHeader:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 25

        if barKey ~= "Stagger" then
            local colorPicker = CreateBarColorPicker(rc, L["Bar Color"], classKey, barKey, "color")
            colorPicker:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 28
        end

        local bgColorPicker = CreateBarColorPicker(rc, L["Background"], classKey, barKey, "bgColor")
        bgColorPicker:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 28

        if barKey == "Stagger" then
            local baseColorPicker = CreateBarColorPicker(rc, L["Base Color"], classKey, barKey, "lightColor")
            baseColorPicker:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 28

            local ceilingSlider = UI.CreateModernSlider(rc, L["Bar Ceiling (% HP)"], 50, 500,
                CDM:GetBarSettingForClass(classKey, barKey, "ceilingPercent") or 100,
                function(v)
                    CDM:SetBarSettingForClass(classKey, barKey, "ceilingPercent", UI.RoundToInt(v))
                    API:Refresh("RESOURCES")
                end, SLIDER_LABEL_W, SLIDER_W)
            ceilingSlider:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 60

            for idx, tier in ipairs(CDM.CONST.STAGGER_TIERS) do
                local tierLabel = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
                tierLabel:SetPoint("TOPLEFT", 0, yOff)
                tierLabel:SetText(string.format(L["Tier %d"], idx))
                yOff = yOff - 22

                local enabledCB = UI.CreateModernCheckbox(rc, L["Enabled"],
                    CDM:GetBarSettingForClass(classKey, barKey, tier.enabled) and true or false,
                    function(checked)
                        CDM:SetBarSettingForClass(classKey, barKey, tier.enabled, checked)
                        API:Refresh("RESOURCES")
                    end)
                enabledCB:SetPoint("TOPLEFT", 0, yOff)

                local tierColorPicker = CreateBarColorPicker(rc, L["Color"], classKey, barKey, tier.color)
                tierColorPicker:SetPoint("TOPLEFT", 130, yOff)
                yOff = yOff - 28

                local thresholdSlider = UI.CreateModernSlider(rc, L["Threshold (% HP)"], 0, 500,
                    CDM:GetBarSettingForClass(classKey, barKey, tier.threshold) or 0,
                    function(v)
                        CDM:SetBarSettingForClass(classKey, barKey, tier.threshold, UI.RoundToInt(v))
                        API:Refresh("RESOURCES")
                    end, SLIDER_LABEL_W, SLIDER_W)
                thresholdSlider:SetPoint("TOPLEFT", 0, yOff)
                yOff = yOff - 60
            end
        else
            local secondaries = SECONDARY_COLOR_FIELDS[barKey]
            if secondaries and not secondaries[1] then
                secondaries = secondaries[classKey]
            end
            if secondaries then
                for _, field in ipairs(secondaries) do
                    local sp = CreateBarColorPicker(rc, field.label, classKey, barKey, field.key)
                    sp:SetPoint("TOPLEFT", 0, yOff)
                    yOff = yOff - 28
                end
            end
        end
        yOff = yOff - 10

        local borderHeader = UI.CreateHeader(rc, L["Border"])
        borderHeader:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 25

        local hideBorderCB = UI.CreateModernCheckbox(rc, L["Hide Border"],
            CDM:GetBarSettingForClass(classKey, barKey, "hideBorder") == true,
            function(checked)
                CDM:SetBarSettingForClass(classKey, barKey, "hideBorder", checked)
                API:Refresh("RESOURCES")
            end)
        hideBorderCB:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 35

        local thicknessSlider = UI.CreateModernSlider(rc, L["Border Thickness"], 1, 10,
            CDM:GetBarSettingForClass(classKey, barKey, "borderThickness") or 1,
            function(v)
                CDM:SetBarSettingForClass(classKey, barKey, "borderThickness", UI.RoundToInt(v))
                API:Refresh("RESOURCES")
            end, SLIDER_LABEL_W, SLIDER_W)
        thicknessSlider:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 60

        local borderColorPicker = CreateBarColorPicker(rc, L["Border Color"], classKey, barKey, "borderColor")
        borderColorPicker:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 40

        local textureHeader = UI.CreateHeader(rc, L["Textures"])
        textureHeader:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 25

        local barTextureLabel = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        barTextureLabel:SetText(L["Bar Texture:"])
        barTextureLabel:SetPoint("TOPLEFT", 0, yOff)

        local ddBarTexture = UI.CreateDropdown(rc)
        UI.PositionDropdownRow(ddBarTexture, barTextureLabel, rc, CONTROL_X, yOff, SLIDER_W)
        ddBarTexture:SetDefaultText(CDM:GetBarSettingForClass(classKey, barKey, "barTexture") or "Solid")
        if rightManager and rightManager.RegisterDropdown then rightManager.RegisterDropdown(ddBarTexture) end
        UI.SetupMediaDropdown(ddBarTexture, "statusbar",
            function() return CDM:GetBarSettingForClass(classKey, barKey, "barTexture") end,
            function(name) CDM:SetBarSettingForClass(classKey, barKey, "barTexture", name); API:Refresh("RESOURCES") end,
            function(name) ddBarTexture:SetDefaultText(name) end, 5)
        yOff = yOff - 50

        local bgTextureLabel = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        bgTextureLabel:SetText(L["Background Texture:"])
        bgTextureLabel:SetPoint("TOPLEFT", 0, yOff)

        local ddBgTexture = UI.CreateDropdown(rc)
        UI.PositionDropdownRow(ddBgTexture, bgTextureLabel, rc, CONTROL_X, yOff, SLIDER_W)
        ddBgTexture:SetDefaultText(CDM:GetBarSettingForClass(classKey, barKey, "bgTexture") or "Solid")
        if rightManager and rightManager.RegisterDropdown then rightManager.RegisterDropdown(ddBgTexture) end
        UI.SetupMediaDropdown(ddBgTexture, "statusbar",
            function() return CDM:GetBarSettingForClass(classKey, barKey, "bgTexture") end,
            function(name) CDM:SetBarSettingForClass(classKey, barKey, "bgTexture", name); API:Refresh("RESOURCES") end,
            function(name) ddBgTexture:SetDefaultText(name) end, 5)
        yOff = yOff - 60

        local SMOOTH_ELIGIBLE = {Mana=1,Rage=1,Energy=1,Focus=1,RunicPower=1,LunarPower=1,Maelstrom=1,Insanity=1,Fury=1}
        if SMOOTH_ELIGIBLE[barKey] then
            local smoothCB = UI.CreateModernCheckbox(rc, L["Smooth Fill"],
                CDM:GetBarSettingForClass(classKey, barKey, "smoothBars") ~= false,
                function(checked)
                    CDM:SetBarSettingForClass(classKey, barKey, "smoothBars", checked)
                    API:Refresh("RESOURCES")
                end)
            smoothCB:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 35
        end

        if barKey == "IgnorePain" then
            local hideIconCB = UI.CreateModernCheckbox(rc, L["Hide Icon"],
                CDM:GetBarSettingForClass(classKey, barKey, "hideIcon") == true,
                function(checked)
                    CDM:SetBarSettingForClass(classKey, barKey, "hideIcon", checked)
                    API:Refresh("RESOURCES", "LAYOUT")
                end)
            hideIconCB:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 35
        end

        if barKey == "HolyPower" then
            local paladinHeader = UI.CreateHeader(rc, L["Paladin"])
            paladinHeader:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 25

            local divinePurposeColorCB = UI.CreateModernCheckbox(rc, L["Change color on Divine Purpose"],
                CDM:GetBarSettingForClass(classKey, barKey, "divinePurposeColorEnabled") == true,
                function(checked)
                    CDM:SetBarSettingForClass(classKey, barKey, "divinePurposeColorEnabled", checked)
                    API:Refresh("RESOURCES")
                end)
            divinePurposeColorCB:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 35

            local divinePurposeColorPicker = CreateBarColorPicker(rc, L["Divine Purpose Color"], classKey, barKey, "divinePurposeColor")
            divinePurposeColorPicker:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 28
        end

        if barKey == "Essence" then
            local essenceHeader = UI.CreateHeader(rc, L["Evoker"])
            essenceHeader:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 25

            local dynColorsCB = UI.CreateModernCheckbox(rc, L["Capped / nearly capped colors"],
                CDM:GetBarSettingForClass(classKey, barKey, "dynamicColors") ~= false,
                function(checked)
                    CDM:SetBarSettingForClass(classKey, barKey, "dynamicColors", checked)
                    API:Refresh("RESOURCES")
                end)
            dynColorsCB:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 35

            local burstGlowCB = UI.CreateModernCheckbox(rc, L["Glow on Essence Burst"],
                CDM:GetBarSettingForClass(classKey, barKey, "essenceBurstGlow") ~= false,
                function(checked)
                    CDM:SetBarSettingForClass(classKey, barKey, "essenceBurstGlow", checked)
                    API:Refresh("RESOURCES")
                end)
            burstGlowCB:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 35

            local burstColorCB = UI.CreateModernCheckbox(rc, L["Change color on Essence Burst"],
                CDM:GetBarSettingForClass(classKey, barKey, "essenceBurstColorEnabled") == true,
                function(checked)
                    CDM:SetBarSettingForClass(classKey, barKey, "essenceBurstColorEnabled", checked)
                    API:Refresh("RESOURCES")
                end)
            burstColorCB:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 35

            local burstColorPicker = CreateBarColorPicker(rc, L["Essence Burst Color"], classKey, barKey, "essenceBurstColor")
            burstColorPicker:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 28
        end

        if USES_RECHARGE_TEXT[barKey] then
            local chargeTickSlider = UI.CreateModernSlider(rc, L["Tick Width"], 1, 10,
                CDM:GetBarSettingForClass(classKey, barKey, "chargeTickWidth") or 1,
                function(v)
                    CDM:SetBarSettingForClass(classKey, barKey, "chargeTickWidth", UI.RoundToInt(v))
                    API:Refresh("RESOURCES")
                end, SLIDER_LABEL_W, SLIDER_W)
            chargeTickSlider:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 60

        end

        yOff = BuildTicksSection(rc, classKey, barKey, yOff)

        rc:SetHeight(math.abs(yOff) + 20)
    end

    local function BuildLayout(rc, rightManager, classKey, barKey)
        local yOff = -6
        local sizeHeader = UI.CreateHeader(rc, L["Size"])
        sizeHeader:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 40

        local heightSlider = UI.CreateModernSlider(rc, L["Height"], 4, 40,
            CDM:GetBarSettingForClass(classKey, barKey, "height") or 16,
            function(v)
                CDM:SetBarSettingForClass(classKey, barKey, "height", UI.RoundToInt(v))
                API:Refresh("RESOURCES", "LAYOUT")
            end, SLIDER_LABEL_W, SLIDER_W)
        heightSlider:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 60

        local widthSlider = UI.CreateModernSlider(rc, L["Width (0 = Auto)"], 0, 600,
            CDM:GetBarSettingForClass(classKey, barKey, "width") or 0,
            function(v)
                local value = UI.RoundToInt(v)
                if value > 0 and value < 60 then value = 60 end
                CDM:SetBarSettingForClass(classKey, barKey, "width", value)
                API:Refresh("RESOURCES")
            end, SLIDER_LABEL_W, SLIDER_W)
        widthSlider:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 60

        heightSlider:HookScript("OnShow", function(self)
            self:UpdateUIValue(CDM:GetBarSettingForClass(classKey, barKey, "height") or 16)
        end)
        widthSlider:HookScript("OnShow", function(self)
            self:UpdateUIValue(CDM:GetBarSettingForClass(classKey, barKey, "width") or 0)
        end)

        if barKey == "ArcaneCharges" or barKey == "Essence" or barKey == "FireBlast"
            or barKey == "Flurry" or barKey == "Prescience" then
            local spacingSlider = UI.CreateModernSlider(rc, L["Spacing (-1 = No Spacing)"], -1, 40,
                CDM:GetBarSettingForClass(classKey, barKey, "pipSpacing") or -1,
                function(v)
                    CDM:SetBarSettingForClass(classKey, barKey, "pipSpacing", UI.RoundToInt(v))
                    API:Refresh("RESOURCES")
                end, SLIDER_LABEL_W, SLIDER_W)
            spacingSlider:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 60
        end

        local posHeader = UI.CreateHeader(rc, L["Position"])
        posHeader:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 25

        local anchorToLabel = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        anchorToLabel:SetText(L["Anchor To:"])
        anchorToLabel:SetPoint("TOPLEFT", 0, yOff)

        local generalBarSet = {}
        local generalBars = CDM.CLASS_BARS and CDM.CLASS_BARS["General"]
        if generalBars then
            for _, k in ipairs(generalBars) do generalBarSet[k] = true end
        end

        local function WouldCreateCycle(candidateKey)
            local visited = { [barKey] = true }
            local current = candidateKey
            while current do
                if visited[current] then return true end
                visited[current] = true
                local ck = generalBarSet[current] and "General" or classKey
                current = CDM:GetBarSettingForClass(ck, current, "anchorTo")
                if not current or current == "screen" or current == "essential"
                   or current == "playerFrame" then
                    return false
                end
            end
            return false
        end

        local anchorToOptions = {
            { value = "screen", label = L["Screen"] },
            { value = "playerFrame", label = L["Player Frame"] },
            { value = "essential", label = L["Essential Viewer"] },
        }
        local compatClassKey = classKey
        if classKey == "General" then
            local _, pc = UnitClass("player")
            compatClassKey = pc or classKey
        end

        local classBars = CDM.CLASS_BARS and CDM.CLASS_BARS[classKey]
        if classBars then
            for _, otherKey in ipairs(classBars) do
                if otherKey ~= barKey
                   and CDM.AreBarKeysSpecCompatible(compatClassKey, barKey, otherKey)
                   and not WouldCreateCycle(otherKey) then
                    anchorToOptions[#anchorToOptions + 1] = {
                        value = otherKey,
                        label = BAR_DISPLAY_NAMES[otherKey] or otherKey,
                    }
                end
            end
        end
        if classKey ~= "General" and generalBars then
            for _, otherKey in ipairs(generalBars) do
                if otherKey ~= barKey
                   and CDM.AreBarKeysSpecCompatible(compatClassKey, barKey, otherKey)
                   and not WouldCreateCycle(otherKey) then
                    anchorToOptions[#anchorToOptions + 1] = {
                        value = otherKey,
                        label = BAR_DISPLAY_NAMES[otherKey] or otherKey,
                    }
                end
            end
        end

        local currentAnchorTo = CDM:GetBarSettingForClass(classKey, barKey, "anchorTo") or "screen"

        local ddAnchorTo = UI.CreateDropdown(rc)
        UI.PositionDropdownRow(ddAnchorTo, anchorToLabel, rc, CONTROL_X, yOff, SLIDER_W)
        ddAnchorTo:SetDefaultText(UI.GetOptionLabel(anchorToOptions, currentAnchorTo, currentAnchorTo))
        if rightManager and rightManager.RegisterDropdown then rightManager.RegisterDropdown(ddAnchorTo) end
        UI.SetupValueDropdown(ddAnchorTo, anchorToOptions,
            function() return CDM:GetBarSettingForClass(classKey, barKey, "anchorTo") or "screen" end,
            function(value)
                CDM:SetBarSettingForClass(classKey, barKey, "anchorTo", value)
                API:Refresh("RESOURCES", "LAYOUT")
                ShowBarSettings(classKey, barKey)
            end)
        yOff = yOff - 60

        local isBarAnchor = currentAnchorTo ~= "screen" and currentAnchorTo ~= "playerFrame" and currentAnchorTo ~= "essential"

        if currentAnchorTo == "screen" then
            local offsetXSlider = UI.CreateModernSlider(rc, L["X Offset"], -600, 600,
                CDM:GetBarSettingForClass(classKey, barKey, "offsetX") or 0,
                function(v)
                    CDM:SetBarSettingForClass(classKey, barKey, "offsetX", UI.RoundToInt(v))
                    API:Refresh("RESOURCES")
                end, SLIDER_LABEL_W, SLIDER_W)
            offsetXSlider:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 60

            local offsetYSlider = UI.CreateModernSlider(rc, L["Y Offset"], -600, 600,
                CDM:GetBarSettingForClass(classKey, barKey, "offsetY") or -200,
                function(v)
                    CDM:SetBarSettingForClass(classKey, barKey, "offsetY", UI.RoundToInt(v))
                    API:Refresh("RESOURCES")
                end, SLIDER_LABEL_W, SLIDER_W)
            offsetYSlider:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 60

            if ns.RegisterAnchorPositionUpdater then
                ns.RegisterAnchorPositionUpdater("resource_" .. barKey, function(x, y)
                    if selectedClassKey ~= classKey or selectedBarKey ~= barKey or not page:IsShown() then return end
                    offsetXSlider:UpdateUIValue(x)
                    offsetYSlider:UpdateUIValue(y)
                end)
            end

        elseif isBarAnchor then
            local spacingSlider = UI.CreateModernSlider(rc, L["Bar Spacing"], -50, 50,
                CDM:GetBarSettingForClass(classKey, barKey, "barSpacing") or 1,
                function(v)
                    CDM:SetBarSettingForClass(classKey, barKey, "barSpacing", UI.RoundToInt(v))
                    API:Refresh("RESOURCES")
                end, SLIDER_LABEL_W, SLIDER_W)
            spacingSlider:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 60

            local stackDirLabel = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
            stackDirLabel:SetText(L["Stack Direction:"])
            stackDirLabel:SetPoint("TOPLEFT", 0, yOff)

            local stackOptions = {
                { value = "below", label = L["Below"] },
                { value = "above", label = L["Above"] },
                { value = "right", label = L["Right of"] },
                { value = "left", label = L["Left of"] },
            }
            local aP = CDM:GetBarSettingForClass(classKey, barKey, "anchorPoint") or "TOP"
            local tP = CDM:GetBarSettingForClass(classKey, barKey, "anchorTargetPoint") or "BOTTOM"
            local currentDir = "below"
            if aP == "BOTTOM" and tP == "TOP" then currentDir = "above"
            elseif aP == "LEFT" and tP == "RIGHT" then currentDir = "right"
            elseif aP == "RIGHT" and tP == "LEFT" then currentDir = "left"
            end

            local ddStackDir = UI.CreateDropdown(rc)
            UI.PositionDropdownRow(ddStackDir, stackDirLabel, rc, CONTROL_X, yOff, SLIDER_W)
            for _, opt in ipairs(stackOptions) do
                if opt.value == currentDir then ddStackDir:SetDefaultText(opt.label) break end
            end
            if rightManager and rightManager.RegisterDropdown then rightManager.RegisterDropdown(ddStackDir) end
            UI.SetupValueDropdown(ddStackDir, stackOptions,
                function() return currentDir end,
                function(value)
                    local newAP, newTP
                    if value == "below" then newAP, newTP = "TOP", "BOTTOM"
                    elseif value == "above" then newAP, newTP = "BOTTOM", "TOP"
                    elseif value == "right" then newAP, newTP = "LEFT", "RIGHT"
                    elseif value == "left" then newAP, newTP = "RIGHT", "LEFT"
                    end
                    CDM:SetBarSettingForClass(classKey, barKey, "anchorPoint", newAP)
                    CDM:SetBarSettingForClass(classKey, barKey, "anchorTargetPoint", newTP)
                    API:Refresh("RESOURCES")
                    ShowBarSettings(classKey, barKey)
                end)
            yOff = yOff - 60

        else
            local anchorPts = {
                { value = "TOPLEFT", label = "TOPLEFT" }, { value = "TOP", label = "TOP" },
                { value = "TOPRIGHT", label = "TOPRIGHT" }, { value = "LEFT", label = "LEFT" },
                { value = "CENTER", label = "CENTER" }, { value = "RIGHT", label = "RIGHT" },
                { value = "BOTTOMLEFT", label = "BOTTOMLEFT" }, { value = "BOTTOM", label = "BOTTOM" },
                { value = "BOTTOMRIGHT", label = "BOTTOMRIGHT" },
            }

            local apLabel = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
            apLabel:SetText(L["Bar Anchor Point:"])
            apLabel:SetPoint("TOPLEFT", 0, yOff)

            local ddAP = UI.CreateDropdown(rc)
            UI.PositionDropdownRow(ddAP, apLabel, rc, CONTROL_X, yOff, SLIDER_W)
            ddAP:SetDefaultText(CDM:GetBarSettingForClass(classKey, barKey, "anchorPoint") or "BOTTOM")
            if rightManager and rightManager.RegisterDropdown then rightManager.RegisterDropdown(ddAP) end
            UI.SetupValueDropdown(ddAP, anchorPts,
                function() return CDM:GetBarSettingForClass(classKey, barKey, "anchorPoint") or "BOTTOM" end,
                function(value)
                    CDM:SetBarSettingForClass(classKey, barKey, "anchorPoint", value)
                    ddAP:SetDefaultText(value)
                    API:Refresh("RESOURCES")
                end)
            yOff = yOff - 60

            local rpLabel = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
            rpLabel:SetText(L["Target Point:"])
            rpLabel:SetPoint("TOPLEFT", 0, yOff)

            local ddTP = UI.CreateDropdown(rc)
            UI.PositionDropdownRow(ddTP, rpLabel, rc, CONTROL_X, yOff, SLIDER_W)
            ddTP:SetDefaultText(CDM:GetBarSettingForClass(classKey, barKey, "anchorTargetPoint") or "TOP")
            if rightManager and rightManager.RegisterDropdown then rightManager.RegisterDropdown(ddTP) end
            UI.SetupValueDropdown(ddTP, anchorPts,
                function() return CDM:GetBarSettingForClass(classKey, barKey, "anchorTargetPoint") or "TOP" end,
                function(value)
                    CDM:SetBarSettingForClass(classKey, barKey, "anchorTargetPoint", value)
                    ddTP:SetDefaultText(value)
                    API:Refresh("RESOURCES")
                end)
            yOff = yOff - 60

            local offsetXSlider = UI.CreateModernSlider(rc, L["X Offset"], -600, 600,
                CDM:GetBarSettingForClass(classKey, barKey, "offsetX") or 0,
                function(v)
                    CDM:SetBarSettingForClass(classKey, barKey, "offsetX", UI.RoundToInt(v))
                    API:Refresh("RESOURCES")
                end, SLIDER_LABEL_W, SLIDER_W)
            offsetXSlider:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 60

            local offsetYSlider = UI.CreateModernSlider(rc, L["Y Offset"], -600, 600,
                CDM:GetBarSettingForClass(classKey, barKey, "offsetY") or 0,
                function(v)
                    CDM:SetBarSettingForClass(classKey, barKey, "offsetY", UI.RoundToInt(v))
                    API:Refresh("RESOURCES")
                end, SLIDER_LABEL_W, SLIDER_W)
            offsetYSlider:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 60

            if ns.RegisterAnchorPositionUpdater then
                ns.RegisterAnchorPositionUpdater("resource_" .. barKey, function(x, y)
                    if selectedClassKey ~= classKey or selectedBarKey ~= barKey or not page:IsShown() then return end
                    offsetXSlider:UpdateUIValue(x)
                    offsetYSlider:UpdateUIValue(y)
                end)
            end
        end

        rc:SetHeight(math.abs(yOff) + 20)
    end

    local function BuildText(rc, rightManager, classKey, barKey)
        local yOff = -6
        -- Charge bars draw a recharge countdown on the recharging pip instead of
        -- a value tag, so they get their own text settings block.
        if USES_RECHARGE_TEXT[barKey] then
            local rechargeHeader = UI.CreateHeader(rc, L["Cooldown Text"])
            rechargeHeader:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 30

            local rechargeCB = UI.CreateModernCheckbox(rc, L["Enable Cooldown Text"],
                CDM:GetBarSettingForClass(classKey, barKey, "rechargeTextEnabled") ~= false,
                function(checked)
                    CDM:SetBarSettingForClass(classKey, barKey, "rechargeTextEnabled", checked)
                    API:Refresh("RESOURCES")
                    ShowBarSettings(classKey, barKey)
                end)
            rechargeCB:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 35

            if CDM:GetBarSettingForClass(classKey, barKey, "rechargeTextEnabled") == false then
                rc:SetHeight(math.abs(yOff) + 20)
                return
            end

            local rechargeFontSlider = UI.CreateModernSlider(rc, L["Font Size"], 6, 32,
                CDM:GetBarSettingForClass(classKey, barKey, "rechargeTextFontSize") or 10,
                function(v)
                    CDM:SetBarSettingForClass(classKey, barKey, "rechargeTextFontSize", UI.RoundToInt(v))
                    API:Refresh("RESOURCES")
                end, SLIDER_LABEL_W, SLIDER_W)
            rechargeFontSlider:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 60

            local rechargeColorPicker = CreateBarColorPicker(rc, L["Text Color"], classKey, barKey, "rechargeTextColor")
            rechargeColorPicker:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 50

            rc:SetHeight(math.abs(yOff) + 20)
            return
        end

        local tagHeader = UI.CreateHeader(rc, L["Tag (Value Text)"])
        tagHeader:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 30

        local tagEnabledCB = UI.CreateModernCheckbox(rc, L["Enable Tag"],
            CDM:GetBarSettingForClass(classKey, barKey, "tagEnabled") ~= false,
            function(checked)
                CDM:SetBarSettingForClass(classKey, barKey, "tagEnabled", checked)
                API:Refresh("RESOURCES")
                ShowBarSettings(classKey, barKey)
            end)
        tagEnabledCB:SetPoint("TOPLEFT", 0, yOff)

        if CDM:GetBarSettingForClass(classKey, barKey, "tagEnabled") == false then
            rc:SetHeight(math.abs(yOff) + 55)
            return
        end

        if barKey == "TipOfTheSpear" then
            local tosTimeCB = UI.CreateModernCheckbox(rc, L["Show aura time"],
                CDM:GetBarSettingForClass(classKey, barKey, "tagShowAuraTime") == true,
                function(checked)
                    CDM:SetBarSettingForClass(classKey, barKey, "tagShowAuraTime", checked)
                    API:Refresh("RESOURCES")
                end)
            tosTimeCB:SetPoint("LEFT", tagEnabledCB, "LEFT", 150, 0)
        end

        yOff = yOff - 35

        local tagFontSlider = UI.CreateModernSlider(rc, L["Font Size"], 8, 32,
            CDM:GetBarSettingForClass(classKey, barKey, "tagFontSize") or 15,
            function(v)
                CDM:SetBarSettingForClass(classKey, barKey, "tagFontSize", UI.RoundToInt(v))
                API:Refresh("RESOURCES")
            end, SLIDER_LABEL_W, SLIDER_W)
        tagFontSlider:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 60

        local tagAnchorOptions = {
            { value = "LEFT", label = L["Left"] },
            { value = "CENTER", label = L["Center"] },
            { value = "RIGHT", label = L["Right"] },
        }
        local tagAnchorLabel = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        tagAnchorLabel:SetText(L["Tag Anchor:"])
        tagAnchorLabel:SetPoint("TOPLEFT", 0, yOff)

        local ddTagAnchor = UI.CreateDropdown(rc)
        UI.PositionDropdownRow(ddTagAnchor, tagAnchorLabel, rc, CONTROL_X, yOff, SLIDER_W)
        ddTagAnchor:SetDefaultText(CDM:GetBarSettingForClass(classKey, barKey, "tagAnchor") or "CENTER")
        if rightManager and rightManager.RegisterDropdown then rightManager.RegisterDropdown(ddTagAnchor) end
        UI.SetupValueDropdown(ddTagAnchor, tagAnchorOptions,
            function() return CDM:GetBarSettingForClass(classKey, barKey, "tagAnchor") end,
            function(value)
                CDM:SetBarSettingForClass(classKey, barKey, "tagAnchor", value)
                ddTagAnchor:SetDefaultText(value)
                API:Refresh("RESOURCES")
            end)
        yOff = yOff - 60

        local tagColorPicker = CreateBarColorPicker(rc, L["Tag Color"], classKey, barKey, "tagColor")
        tagColorPicker:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 28

        local tagXSlider = UI.CreateModernSlider(rc, L["Tag X Offset"], -200, 200,
            CDM:GetBarSettingForClass(classKey, barKey, "tagOffsetX") or 0,
            function(v)
                CDM:SetBarSettingForClass(classKey, barKey, "tagOffsetX", UI.RoundToInt(v))
                API:Refresh("RESOURCES")
            end, SLIDER_LABEL_W, SLIDER_W)
        tagXSlider:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 60

        local tagYSlider = UI.CreateModernSlider(rc, L["Tag Y Offset"], -50, 50,
            CDM:GetBarSettingForClass(classKey, barKey, "tagOffsetY") or 0,
            function(v)
                CDM:SetBarSettingForClass(classKey, barKey, "tagOffsetY", UI.RoundToInt(v))
                API:Refresh("RESOURCES")
            end, SLIDER_LABEL_W, SLIDER_W)
        tagYSlider:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 40

        if barKey == "Mana" then
            local pctCB = UI.CreateModernCheckbox(rc, L["Display as %"],
                CDM:GetBarSettingForClass(classKey, barKey, "displayAsPercent") == true,
                function(checked)
                    CDM:SetBarSettingForClass(classKey, barKey, "displayAsPercent", checked)
                    API:Refresh("RESOURCES")
                end)
            pctCB:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 35
        end

        rc:SetHeight(math.abs(yOff) + 20)
    end

    ShowBarSettings = function(classKey, barKey)
        resourceDropdown:OverrideText(BAR_DISPLAY_NAMES[barKey] or barKey)
        local builders = { appearance = BuildAppearance, layout = BuildLayout, text = BuildText }
        for _, info in ipairs(tabInfo) do
            local build = builders[info.id]
            if build then
                local manager = managers[info.id]
                local _, rc = manager.CreateScrollContent(400)
                build(rc, manager, classKey, barKey)
            end
        end
    end

    local function SelectBar(classKey, barKey)
        selectedClassKey = classKey
        selectedBarKey = barKey
        ShowBarSettings(classKey, barKey)
        local condUI = ns.ResourceConditionsUI
        if condUI and condUI.ShowBarConditions then
            condUI.ShowBarConditions(condPage, condManager, classKey, barKey)
        end
        local loadUI = ns.ResourceLoadUI
        if loadUI and loadUI.ShowBarLoad then
            loadUI.ShowBarLoad(loadPage, loadManager, classKey, barKey)
        end
        local condBtn = subTabs.tabButtons and subTabs.tabButtons["conditions"]
        if condBtn then
            if barKey == "Stagger" or barKey == "Ironfur" or barKey == "IgnorePain"
                or USES_RECHARGE_TEXT[barKey] then
                condBtn:Hide()
                if currentSubTab == "conditions" then subTabs.selectTab("appearance") end
            else
                condBtn:Show()
            end
        end
        local previous
        for _, info in ipairs(tabInfo) do
            local button = subTabs.tabButtons[info.id]
            button:ClearAllPoints()
            if button:IsShown() then
                if previous then
                    button:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", 4, 0)
                else
                    button:SetPoint("BOTTOMLEFT", subTabs.barFrame, "BOTTOMLEFT")
                end
                previous = button
            end
        end
    end

    resourceDropdown:SetupMenu(function(_, rootDescription)
        local classBars = CDM.CLASS_BARS
        if not classBars then return end
        for _, classKey in ipairs({ "General", playerClass }) do
            local bars = classBars[classKey]
            if bars and #bars > 0 then
                rootDescription:CreateTitle(classKey == "General" and L["Shared"] or CLASS_DISPLAY_NAMES[classKey])
                for _, barKey in ipairs(bars) do
                    rootDescription:CreateRadio(BAR_DISPLAY_NAMES[barKey] or barKey,
                        function() return selectedClassKey == classKey and selectedBarKey == barKey end,
                        function()
                            -- Rebuilding panels closes menus; let the selection finish first.
                            C_Timer.After(0, function()
                                if not page:IsShown() then return end
                                SelectBar(classKey, barKey)
                            end)
                        end)
                end
            end
        end
    end)

    local bars = CDM.CLASS_BARS and CDM.CLASS_BARS[playerClass]
    local initialBar = bars and bars[1]
    if bars then
        for _, barKey in ipairs(bars) do
            if IsBarActiveForSpec(barKey, currentSpecID) then
                initialBar = barKey
                break
            end
        end
    end
    if initialBar then
        SelectBar(playerClass, initialBar)
    elseif CDM.CLASS_BARS and CDM.CLASS_BARS.General and CDM.CLASS_BARS.General[1] then
        SelectBar("General", CDM.CLASS_BARS.General[1])
    end
end

API:RegisterConfigTab("resources", L["Resources"], CreateResourcesTab, 10)
