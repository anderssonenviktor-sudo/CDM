local Runtime = _G["CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L

local castBarExpanded = { dimensions = true }

local function CreateCastBarTab(page, tabId)
    local scrollChild, scrollFrame = UI.CreateScrollableTab(page, "CDM_CastBarScrollFrame", 700, 650)
    local scrollContent = scrollFrame:GetScrollChild()

    local sections = {}

    local function UpdateScrollHeight()
        local height = 20 + 26 + 20 + 20
        for i, section in ipairs(sections) do
            height = height + section:GetHeight()
            if i > 1 then height = height + 14 end
        end
        scrollContent:SetHeight(height)
        scrollChild:SetHeight(height - 20)
    end

    local function CollapsibleSection(key, label, contentHeight)
        local section = CreateFrame("Frame", nil, scrollChild)
        section:SetWidth(580)
        local previous = sections[#sections]
        if previous then
            section:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -14)
        else
            section:SetPoint("TOPLEFT", page.controls.castBarEnabled, "BOTTOMLEFT", 34, -20)
        end

        local header = CreateFrame("Button", nil, section)
        header:SetPoint("TOPLEFT")
        header:SetSize(580, 24)
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

        local content = CreateFrame("Frame", nil, section)
        content:SetPoint("TOPLEFT", 0, -30)
        content:SetSize(580, contentHeight)
        function section:SetContentHeight(value)
            contentHeight = value
            content:SetHeight(value)
            section:SetHeight(castBarExpanded[key] and (30 + value) or 24)
            UpdateScrollHeight()
        end
        local function UpdateSection()
            local expanded = castBarExpanded[key] == true
            content:SetShown(expanded)
            arrow:SetRotation(expanded and 0 or math.pi / 2)
            section:SetHeight(expanded and (30 + contentHeight) or 24)
            UpdateScrollHeight()
        end
        header:SetScript("OnClick", function()
            castBarExpanded[key] = not castBarExpanded[key]
            UI.CloseAllDropdownMenus()
            UpdateSection()
        end)
        sections[#sections + 1] = section
        UpdateSection()
        return section, content
    end

    local enabled = CDM.db.castBarEnabled ~= false
    page.controls.castBarEnabled = UI.CreateModernCheckbox(
        scrollChild,
        L["Enable Cast Bar"],
        enabled,
        function(checked)
            CDM.db.castBarEnabled = checked
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarEnabled:SetPoint("TOPLEFT", -34, 0)
    page.controls.castBarEnabled:SetWidth(170)

    local previewEnabled = CDM.db.castBarPreviewEnabled == true
    page.controls.castBarPreviewEnabled = UI.CreateModernCheckbox(
        scrollChild,
        L["Show Preview"] or "Show Preview",
        previewEnabled,
        function(checked)
            CDM.db.castBarPreviewEnabled = checked
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarPreviewEnabled:SetPoint("LEFT", page.controls.castBarEnabled, "RIGHT", 0, 0)
    page.controls.castBarPreviewEnabled:SetWidth(160)

    local blizzHidden = CDM.db.hideBlizzardCastBar ~= false
    page.controls.hideBlizzardCastBar = UI.CreateModernCheckbox(
        scrollChild,
        L["Hide Blizzard Cast Bar"],
        blizzHidden,
        function(checked)
            CDM.db.hideBlizzardCastBar = checked
            if checked and API.DisableBlizzardPlayerCastBar then
                API:DisableBlizzardPlayerCastBar()
            end
        end
    )
    page.controls.hideBlizzardCastBar:SetPoint("LEFT", page.controls.castBarPreviewEnabled, "RIGHT", 0, 0)
    page.controls.hideBlizzardCastBar:SetWidth(230)

    local dimensionsSection, dimensions = CollapsibleSection("dimensions", L["Dimensions"], 135)

    page.controls.castBarWidthSlider = UI.CreateModernSlider(
        dimensions,
        L["Width (0 = Auto)"],
        0, 1000,
        CDM.db.castBarWidth or 300,
        function(v)
            local value = UI.RoundToInt(v)
            if value > 0 and value < 60 then
                value = 60
                page.controls.castBarWidthSlider.Slider:SetValue(60)
            end
            CDM.db.castBarWidth = value
            page.UpdateAutoWidthLayout()
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarWidthSlider:SetPoint("TOPLEFT")

    local autoSourceChecked = (CDM.db.castBarAutoWidthSource == "utility")
    page.controls.castBarAutoWidthSource = UI.CreateModernCheckbox(
        dimensions,
        L["Match Utility Width"],
        autoSourceChecked,
        function(checked)
            CDM.db.castBarAutoWidthSource = checked and "utility" or "essential"
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarAutoWidthSource:SetPoint("TOPLEFT", page.controls.castBarWidthSlider, "BOTTOMLEFT", 0, -5)
    page.controls.castBarHeightSlider = UI.CreateModernSlider(
        dimensions,
        L["Height"],
        8, 50,
        CDM.db.castBarHeight or 20,
        function(v)
            CDM.db.castBarHeight = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )
    function page.UpdateAutoWidthLayout()
        local isAuto = (CDM.db.castBarWidth or 300) == 0
        page.controls.castBarAutoWidthSource:SetShown(isAuto)
        page.controls.castBarHeightSlider:ClearAllPoints()
        if isAuto then
            page.controls.castBarHeightSlider:SetPoint("TOPLEFT", page.controls.castBarAutoWidthSource, "BOTTOMLEFT", 0, -10)
        else
            page.controls.castBarHeightSlider:SetPoint("TOPLEFT", page.controls.castBarWidthSlider, "BOTTOMLEFT", 0, -10)
        end
        dimensionsSection:SetContentHeight(isAuto and 135 or 100)
    end
    page.UpdateAutoWidthLayout()
    page:HookScript("OnShow", function()
        page.controls.castBarWidthSlider:UpdateUIValue(CDM.db.castBarWidth or 300)
        page.controls.castBarHeightSlider:UpdateUIValue(CDM.db.castBarHeight or 20)
        page.UpdateAutoWidthLayout()
    end)

    local ICON_SECTION_HEIGHT = 290
    local iconSection, iconContent = CollapsibleSection("icon", L["Icon/Ticks"], ICON_SECTION_HEIGHT)

    local showIcon = CDM.db.castBarShowIcon or false
    page.controls.castBarShowIcon = UI.CreateModernCheckbox(
        iconContent,
        L["Show Spell Icon"],
        showIcon,
        function(checked)
            CDM.db.castBarShowIcon = checked
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarShowIcon:SetPoint("TOPLEFT")

    local iconPosLabel = iconContent:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    iconPosLabel:SetText(L["Icon Position:"])
    iconPosLabel:SetPoint("TOPLEFT", page.controls.castBarShowIcon, "BOTTOMLEFT", 0, -10)

    local ddIconPos = UI.CreateDropdown(iconContent)
    ddIconPos:SetPoint("TOPLEFT", iconPosLabel, "BOTTOMLEFT", 0, -5)
    ddIconPos:SetWidth(150)
    ddIconPos:SetDefaultText(CDM.db.castBarIconPosition or "LEFT")
    page.controls.castBarIconPositionDropdown = ddIconPos

    local iconPosOptions = {
        { value = "LEFT", label = L["Left"] },
        { value = "RIGHT", label = L["Right"] },
    }

    UI.SetupValueDropdown(
        ddIconPos,
        iconPosOptions,
        function() return CDM.db.castBarIconPosition or "LEFT" end,
        function(value)
            CDM.db.castBarIconPosition = value
            ddIconPos:SetDefaultText(value)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarIconGapSlider = UI.CreateModernSlider(
        iconContent,
        L["Icon-Bar Gap"],
        -1, 20,
        CDM.db.castBarIconGap or 1,
        function(v)
            CDM.db.castBarIconGap = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarIconGapSlider:SetPoint("TOPLEFT", ddIconPos, "BOTTOMLEFT", 0, -10)

    page.controls.castBarShowTicks = UI.CreateModernCheckbox(
        iconContent,
        L["Show Channel Ticks"],
        CDM.db.castBarShowTicks ~= false,
        function(checked)
            CDM.db.castBarShowTicks = checked
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarShowTicks:SetPoint("TOPLEFT", page.controls.castBarIconGapSlider, "BOTTOMLEFT", 0, -10)

    -- Each color sits on its toggle's row, in one column.
    page.controls.castBarTickColor = UI.CreateColorSwatch(iconContent, "", "castBarTickColor", "STYLE")
    page.controls.castBarTickColor:SetPoint("LEFT", page.controls.castBarShowTicks, "LEFT", 190, 0)

    -- Last-tick highlight is Arcane only (Arcane Missiles clip point).
    local ARCANE_SPEC_ID = 62
    local lastTickRow = page.controls.castBarShowTicks
    if CDM.GetCurrentSpecID and CDM:GetCurrentSpecID() == ARCANE_SPEC_ID then
        page.controls.castBarHighlightLastTick = UI.CreateModernCheckbox(
            iconContent,
            L["Highlight Last Tick"],
            CDM.db.castBarHighlightLastTick == true,
            function(checked)
                CDM.db.castBarHighlightLastTick = checked
                API:Refresh("STYLE")
            end
        )
        page.controls.castBarHighlightLastTick:SetPoint("TOPLEFT", lastTickRow, "BOTTOMLEFT", 0, -10)

        page.controls.castBarLastTickColor = UI.CreateColorSwatch(iconContent, "", "castBarLastTickColor", "STYLE")
        page.controls.castBarLastTickColor:SetPoint("LEFT", page.controls.castBarHighlightLastTick, "LEFT", 190, 0)

        lastTickRow = page.controls.castBarHighlightLastTick
    else
        ICON_SECTION_HEIGHT = ICON_SECTION_HEIGHT - 36
        iconSection:SetContentHeight(ICON_SECTION_HEIGHT)
    end

    page.controls.castBarTickWidthSlider = UI.CreateModernSlider(
        iconContent,
        L["Tick Width"],
        1, 6,
        CDM.db.castBarTickWidth or 2,
        function(v)
            CDM.db.castBarTickWidth = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )

    -- Devastation only: the spec that can talent into Mass Disintegrate.
    local DEVASTATION_SPEC_ID = 1467
    if CDM.GetCurrentSpecID and CDM:GetCurrentSpecID() == DEVASTATION_SPEC_ID then
        local MASS_SETTINGS_HEIGHT = 190
        local massSettings = CreateFrame("Frame", nil, iconContent)
        massSettings:SetSize(500, MASS_SETTINGS_HEIGHT)

        local function UpdateMassLayout()
            local warningOn = CDM.db.castBarMassDisintegrateWarning == true
            massSettings:SetShown(warningOn)
            local slider = page.controls.castBarTickWidthSlider
            slider:ClearAllPoints()
            if warningOn then
                slider:SetPoint("TOPLEFT", massSettings, "BOTTOMLEFT", -20, -20)
            else
                slider:SetPoint("TOPLEFT", page.controls.castBarMassDisintegrateWarning, "BOTTOMLEFT", 0, -20)
            end
            iconSection:SetContentHeight(ICON_SECTION_HEIGHT + 36 + (warningOn and MASS_SETTINGS_HEIGHT + 10 or 0))
        end

        page.controls.castBarMassDisintegrateWarning = UI.CreateModernCheckbox(
            iconContent,
            L["Mass Disintegrate Clip Warning"],
            CDM.db.castBarMassDisintegrateWarning == true,
            function(checked)
                CDM.db.castBarMassDisintegrateWarning = checked
                UpdateMassLayout()
                API:Refresh("STYLE")
            end
        )
        page.controls.castBarMassDisintegrateWarning:SetPoint(
            "TOPLEFT", lastTickRow, "BOTTOMLEFT", 0, -10)
        massSettings:SetPoint("TOPLEFT", page.controls.castBarMassDisintegrateWarning, "BOTTOMLEFT", 20, -10)

        local textLabel = massSettings:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        textLabel:SetText(L["Warning Text"])
        textLabel:SetPoint("TOPLEFT", 0, -4)

        local textBox = UI.CreateEditBox(massSettings)
        textBox:SetSize(180, 22)
        textBox:SetPoint("LEFT", textLabel, "RIGHT", 12, 0)
        textBox:SetMaxLetters(40)
        textBox:SetText(CDM.db.castBarClipWarningText or "")
        textBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        textBox:SetScript("OnEscapePressed", function(self)
            self:SetText(CDM.db.castBarClipWarningText or "")
            self:ClearFocus()
        end)
        textBox:SetScript("OnEditFocusLost", function(self)
            self:HighlightText(0, 0)
            local text = strtrim(self:GetText() or "")
            -- An empty box restores the default text.
            CDM.db.castBarClipWarningText = text ~= "" and text or nil
            self:SetText(CDM.db.castBarClipWarningText or "")
            API:Refresh("STYLE")
        end)
        page.controls.castBarClipWarningText = textBox

        page.controls.castBarClipWarningFontSize = UI.CreateModernSlider(
            massSettings,
            L["Font Size"],
            8, 40,
            CDM.db.castBarClipWarningFontSize or 18,
            function(v)
                CDM.db.castBarClipWarningFontSize = UI.RoundToInt(v)
                API:Refresh("STYLE")
            end
        )
        page.controls.castBarClipWarningFontSize:SetPoint("TOPLEFT", textLabel, "BOTTOMLEFT", 0, -25)

        page.controls.castBarClipWarningOffsetX = UI.CreateModernSlider(
            massSettings,
            L["X Offset"],
            -300, 300,
            CDM.db.castBarClipWarningOffsetX or 0,
            function(v)
                CDM.db.castBarClipWarningOffsetX = UI.RoundToInt(v)
                API:Refresh("STYLE")
            end
        )
        page.controls.castBarClipWarningOffsetX:SetPoint(
            "TOPLEFT", page.controls.castBarClipWarningFontSize, "BOTTOMLEFT", 0, -10)

        page.controls.castBarClipWarningOffsetY = UI.CreateModernSlider(
            massSettings,
            L["Y Offset"],
            -300, 300,
            CDM.db.castBarClipWarningOffsetY or 10,
            function(v)
                CDM.db.castBarClipWarningOffsetY = UI.RoundToInt(v)
                API:Refresh("STYLE")
            end
        )
        page.controls.castBarClipWarningOffsetY:SetPoint(
            "TOPLEFT", page.controls.castBarClipWarningOffsetX, "BOTTOMLEFT", 0, -10)

        UpdateMassLayout()
    else
        page.controls.castBarTickWidthSlider:SetPoint(
            "TOPLEFT", lastTickRow, "BOTTOMLEFT", 0, -20)
    end

    local textureSection, textureContent = CollapsibleSection("texture", L["Bar Texture"], 75)

    local useAtlas = CDM.db.castBarUseAtlasTextures ~= false
    page.controls.castBarUseAtlas = UI.CreateModernCheckbox(
        textureContent,
        L["Use Blizzard Atlas Textures"],
        useAtlas,
        function(checked)
            CDM.db.castBarUseAtlasTextures = checked
            local showLSM = not checked
            if page.castBarLSMGroup then
                page.castBarLSMGroup:SetShown(showLSM)
            end
            textureSection:SetContentHeight(showLSM and 400 or 75)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarUseAtlas:SetPoint("TOPLEFT")

    local showSpark = CDM.db.castBarShowSpark
    if showSpark == nil then showSpark = true end
    page.controls.castBarShowSpark = UI.CreateModernCheckbox(
        textureContent,
        L["Show Spark"],
        showSpark,
        function(checked)
            CDM.db.castBarShowSpark = checked
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarShowSpark:SetPoint("TOPLEFT", page.controls.castBarUseAtlas, "BOTTOMLEFT", 0, -10)

    local lsmGroup = CreateFrame("Frame", nil, textureContent)
    lsmGroup:SetSize(600, 310)
    lsmGroup:SetPoint("TOPLEFT", page.controls.castBarShowSpark, "BOTTOMLEFT", 0, -10)
    page.castBarLSMGroup = lsmGroup

    lsmGroup:SetShown(not useAtlas)
    textureSection:SetContentHeight(useAtlas and 75 or 400)

    local lsmLayout = UI.CreateVerticalLayout(0)
    local function LsmNextY(spacing) return lsmLayout:Next(spacing) end

    local textureLabel = lsmGroup:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    textureLabel:SetText(L["Bar Texture:"])
    textureLabel:SetPoint("TOPLEFT", 0, LsmNextY(0))

    local ddTexture = UI.CreateDropdown(lsmGroup)
    ddTexture:SetPoint("TOPLEFT", 0, LsmNextY(20))
    ddTexture:SetWidth(220)
    ddTexture:SetDefaultText(CDM.db.castBarTexture or "Blizzard")
    page.controls.castBarTextureDropdown = ddTexture

    UI.SetupMediaDropdown(
        ddTexture,
        "statusbar",
        function() return CDM.db.castBarTexture or "Blizzard" end,
        function(name)
            CDM.db.castBarTexture = name
            API:Refresh("STYLE")
        end,
        function(name)
            ddTexture:SetDefaultText(name or "Blizzard")
        end
    )

    local bgTextureLabel = lsmGroup:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    bgTextureLabel:SetText(L["Background Texture:"])
    bgTextureLabel:SetPoint("TOPLEFT", 0, LsmNextY(50))

    local ddBgTexture = UI.CreateDropdown(lsmGroup)
    ddBgTexture:SetPoint("TOPLEFT", 0, LsmNextY(20))
    ddBgTexture:SetWidth(220)
    ddBgTexture:SetDefaultText(CDM.db.castBarBackgroundTexture or "Blizzard")
    page.controls.castBarBgTextureDropdown = ddBgTexture

    UI.SetupMediaDropdown(
        ddBgTexture,
        "statusbar",
        function() return CDM.db.castBarBackgroundTexture or "Blizzard" end,
        function(name)
            CDM.db.castBarBackgroundTexture = name
            API:Refresh("STYLE")
        end,
        function(name)
            ddBgTexture:SetDefaultText(name or "Blizzard")
        end
    )

    page.controls.castBarBackgroundColor = UI.CreateColorSwatch(lsmGroup, L["Background Color"], "castBarBackgroundColor", "STYLE")
    page.controls.castBarBackgroundColor:SetPoint("TOPLEFT", 0, LsmNextY(50))

    page.controls.castBarCastColor = UI.CreateColorSwatch(lsmGroup, L["Cast Color"], "castBarCastColor", "STYLE")
    page.controls.castBarCastColor:SetPoint("TOPLEFT", 0, LsmNextY(40))

    local useClassColor = CDM.db.castBarUseClassColor == true
    page.controls.castBarUseClassColor = UI.CreateModernCheckbox(
        lsmGroup,
        L["Class Color"],
        useClassColor,
        function(checked)
            CDM.db.castBarUseClassColor = checked
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarUseClassColor:SetPoint("LEFT", page.controls.castBarCastColor, "RIGHT", 20, 0)

    page.controls.castBarChannelColor = UI.CreateColorSwatch(lsmGroup, L["Channel Color"], "castBarChannelColor", "STYLE")
    page.controls.castBarChannelColor:SetPoint("TOPLEFT", 0, LsmNextY(40))

    page.controls.castBarUninterruptibleColor = UI.CreateColorSwatch(lsmGroup, L["Uninterruptible Color"], "castBarUninterruptibleColor", "STYLE")
    page.controls.castBarUninterruptibleColor:SetPoint("TOPLEFT", 0, LsmNextY(40))

    local _, positionContent = CollapsibleSection("position", L["Position"], 320)

    local POINT_OPTIONS = {
        { value = "TOPLEFT",     label = L["Top Left"] or "Top Left" },
        { value = "TOP",         label = L["Top"] or "Top" },
        { value = "TOPRIGHT",    label = L["Top Right"] or "Top Right" },
        { value = "LEFT",        label = L["Left"] or "Left" },
        { value = "CENTER",      label = L["Center"] or "Center" },
        { value = "RIGHT",       label = L["Right"] or "Right" },
        { value = "BOTTOMLEFT",  label = L["Bottom Left"] or "Bottom Left" },
        { value = "BOTTOM",      label = L["Bottom"] or "Bottom" },
        { value = "BOTTOMRIGHT", label = L["Bottom Right"] or "Bottom Right" },
    }

    local BuildAnchorOptions = UI.GetCastBarAnchorTargets

    local anchorLabel = positionContent:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    anchorLabel:SetText(L["Anchor To:"] or "Anchor To:")
    anchorLabel:SetPoint("TOPLEFT")

    local ddAnchor = UI.CreateDropdown(positionContent)
    ddAnchor:SetPoint("TOPLEFT", anchorLabel, "BOTTOMLEFT", 0, -5)
    ddAnchor:SetWidth(200)
    page.controls.castBarAnchor = ddAnchor

    local function GetAnchorLabel(value)
        for _, opt in ipairs(BuildAnchorOptions()) do
            if opt.value == value then return opt.label end
        end
        return value or ""
    end

    local currentAnchor = CDM.db.castBarAnchor or "resources"
    ddAnchor:SetDefaultText(GetAnchorLabel(currentAnchor))

    UI.SetupValueDropdown(
        ddAnchor,
        BuildAnchorOptions,
        function() return CDM.db.castBarAnchor or "resources" end,
        function(value)
            CDM.db.castBarAnchor = value
            ddAnchor:SetDefaultText(GetAnchorLabel(value))
            API:Refresh("STYLE")
        end
    )

    local anchorPointLabel = positionContent:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    anchorPointLabel:SetText(L["Anchor Point:"] or "Anchor Point:")
    anchorPointLabel:SetPoint("TOPLEFT", ddAnchor, "BOTTOMLEFT", 0, -10)

    local ddAnchorPoint = UI.CreateDropdown(positionContent)
    ddAnchorPoint:SetPoint("TOPLEFT", anchorPointLabel, "BOTTOMLEFT", 0, -5)
    ddAnchorPoint:SetWidth(200)
    page.controls.castBarAnchorPoint = ddAnchorPoint

    local function GetPointLabel(value)
        for _, opt in ipairs(POINT_OPTIONS) do
            if opt.value == value then return opt.label end
        end
        return value or ""
    end

    ddAnchorPoint:SetDefaultText(GetPointLabel(CDM.db.castBarAnchorPoint or "BOTTOM"))
    UI.SetupValueDropdown(
        ddAnchorPoint,
        POINT_OPTIONS,
        function() return CDM.db.castBarAnchorPoint or "BOTTOM" end,
        function(value)
            CDM.db.castBarAnchorPoint = value
            ddAnchorPoint:SetDefaultText(GetPointLabel(value))
            API:Refresh("STYLE")
        end
    )

    local targetPointLabel = positionContent:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    targetPointLabel:SetText(L["Target Point:"] or "Target Point:")
    targetPointLabel:SetPoint("TOPLEFT", ddAnchorPoint, "BOTTOMLEFT", 0, -10)

    local ddTargetPoint = UI.CreateDropdown(positionContent)
    ddTargetPoint:SetPoint("TOPLEFT", targetPointLabel, "BOTTOMLEFT", 0, -5)
    ddTargetPoint:SetWidth(200)
    page.controls.castBarTargetPoint = ddTargetPoint

    ddTargetPoint:SetDefaultText(GetPointLabel(CDM.db.castBarTargetPoint or "TOP"))
    UI.SetupValueDropdown(
        ddTargetPoint,
        POINT_OPTIONS,
        function() return CDM.db.castBarTargetPoint or "TOP" end,
        function(value)
            CDM.db.castBarTargetPoint = value
            ddTargetPoint:SetDefaultText(GetPointLabel(value))
            API:Refresh("STYLE")
        end
    )

    page.controls.castBarOffsetXSlider = UI.CreateModernSlider(
        positionContent,
        L["X Offset"],
        -800, 800,
        CDM.db.castBarOffsetX or 0,
        function(v)
            CDM.db.castBarOffsetX = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarOffsetXSlider:SetPoint("TOPLEFT", ddTargetPoint, "BOTTOMLEFT", 0, -15)

    page.controls.castBarOffsetYSlider = UI.CreateModernSlider(
        positionContent,
        L["Y Offset"],
        -600, 600,
        CDM.db.castBarOffsetY or -166,
        function(v)
            CDM.db.castBarOffsetY = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarOffsetYSlider:SetPoint("TOPLEFT", page.controls.castBarOffsetXSlider, "BOTTOMLEFT", 0, -10)

    if ns.RegisterAnchorPositionUpdater then
        ns.RegisterAnchorPositionUpdater("cast_bar", function(x, y)
            if not page:IsShown() then return end
            page.controls.castBarOffsetXSlider:UpdateUIValue(x)
            page.controls.castBarOffsetYSlider:UpdateUIValue(y)
        end)
    end

    local _, textContent = CollapsibleSection("text", L["Text"], 410)

    page.controls.castBarFontSizeSlider = UI.CreateModernSlider(
        textContent,
        L["Font Size"],
        8, 24,
        CDM.db.castBarFontSize or 15,
        function(v)
            CDM.db.castBarFontSize = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarFontSizeSlider:SetPoint("TOPLEFT")

    local showName = CDM.db.castBarShowSpellName
    if showName == nil then showName = true end
    page.controls.castBarShowSpellName = UI.CreateModernCheckbox(
        textContent,
        L["Show Spell Name"],
        showName,
        function(checked)
            CDM.db.castBarShowSpellName = checked
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarShowSpellName:SetPoint("TOPLEFT", page.controls.castBarFontSizeSlider, "BOTTOMLEFT", 0, -10)

    page.controls.castBarNameMaxCharsSlider = UI.CreateModernSlider(
        textContent,
        L["Max Name Length (0 = Full)"],
        0, 30,
        CDM.db.castBarNameMaxChars or 0,
        function(v)
            CDM.db.castBarNameMaxChars = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarNameMaxCharsSlider:SetPoint("TOPLEFT", page.controls.castBarShowSpellName, "BOTTOMLEFT", 0, -10)

    page.controls.castBarNameOffsetX = UI.CreateModernSlider(
        textContent,
        L["Name X Offset"],
        -50, 50,
        CDM.db.castBarNameOffsetX or 4,
        function(v)
            CDM.db.castBarNameOffsetX = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarNameOffsetX:SetPoint("TOPLEFT", page.controls.castBarNameMaxCharsSlider, "BOTTOMLEFT", 0, -10)

    page.controls.castBarNameOffsetY = UI.CreateModernSlider(
        textContent,
        L["Name Y Offset"],
        -20, 20,
        CDM.db.castBarNameOffsetY or 0,
        function(v)
            CDM.db.castBarNameOffsetY = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarNameOffsetY:SetPoint("TOPLEFT", page.controls.castBarNameOffsetX, "BOTTOMLEFT", 0, -10)

    local showTimer = CDM.db.castBarShowTimer
    if showTimer == nil then showTimer = true end
    page.controls.castBarShowTimer = UI.CreateModernCheckbox(
        textContent,
        L["Show Timer"],
        showTimer,
        function(checked)
            CDM.db.castBarShowTimer = checked
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarShowTimer:SetPoint("TOPLEFT", page.controls.castBarNameOffsetY, "BOTTOMLEFT", 0, -10)

    page.controls.castBarShowTotalDuration = UI.CreateModernCheckbox(
        textContent,
        L["Show Total Duration (e.g. 0.5/1.5)"],
        CDM.db.castBarShowTotalDuration == true,
        function(checked)
            CDM.db.castBarShowTotalDuration = checked
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarShowTotalDuration:SetPoint("TOPLEFT", page.controls.castBarShowTimer, "BOTTOMLEFT", 0, -10)

    page.controls.castBarTimerOffsetX = UI.CreateModernSlider(
        textContent,
        L["Timer X Offset"],
        -50, 50,
        CDM.db.castBarTimerOffsetX or -4,
        function(v)
            CDM.db.castBarTimerOffsetX = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarTimerOffsetX:SetPoint("TOPLEFT", page.controls.castBarShowTotalDuration, "BOTTOMLEFT", 0, -10)

    page.controls.castBarTimerOffsetY = UI.CreateModernSlider(
        textContent,
        L["Timer Y Offset"],
        -20, 20,
        CDM.db.castBarTimerOffsetY or 0,
        function(v)
            CDM.db.castBarTimerOffsetY = UI.RoundToInt(v)
            API:Refresh("STYLE")
        end
    )
    page.controls.castBarTimerOffsetY:SetPoint("TOPLEFT", page.controls.castBarTimerOffsetX, "BOTTOMLEFT", 0, -10)

    local _, playerClass = UnitClass("player")
    local specID = CDM.GetCurrentSpecID and CDM:GetCurrentSpecID()
    local hasEmpoweredCasts = (playerClass == "EVOKER") or (specID == 250) or (specID == 269)
    if hasEmpoweredCasts then
        local empowerSection, empowerContent = CollapsibleSection("empower", L["Empowered Stages"], 205)

        page.controls.castBarEmpowerWindUpColor = UI.CreateColorSwatch(empowerContent, L["Wind Up Color"], "castBarEmpowerWindUpColor", "STYLE")
        page.controls.castBarEmpowerWindUpColor:SetPoint("TOPLEFT")

        page.controls.castBarEmpowerStage1Color = UI.CreateColorSwatch(empowerContent, L["Stage 1 Color"], "castBarEmpowerStage1Color", "STYLE")
        page.controls.castBarEmpowerStage1Color:SetPoint("TOPLEFT", page.controls.castBarEmpowerWindUpColor, "BOTTOMLEFT", 0, -10)

        page.controls.castBarEmpowerStage2Color = UI.CreateColorSwatch(empowerContent, L["Stage 2 Color"], "castBarEmpowerStage2Color", "STYLE")
        page.controls.castBarEmpowerStage2Color:SetPoint("TOPLEFT", page.controls.castBarEmpowerStage1Color, "BOTTOMLEFT", 0, -10)

        -- Font of Magic talent: Preservation 375783, Devastation 411212, Augmentation 408083
        local hasFontOfMagic = IsPlayerSpell(375783) or IsPlayerSpell(411212) or IsPlayerSpell(408083)
        local lastAnchor = page.controls.castBarEmpowerStage2Color

        if hasFontOfMagic then
            page.controls.castBarEmpowerStage3Color = UI.CreateColorSwatch(empowerContent, L["Stage 3 Color"], "castBarEmpowerStage3Color", "STYLE")
            page.controls.castBarEmpowerStage3Color:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -10)
            lastAnchor = page.controls.castBarEmpowerStage3Color
        end

        page.controls.castBarEmpowerStage4Color = UI.CreateColorSwatch(empowerContent, L["Hold At Max Color"], "castBarEmpowerStage4Color", "STYLE")
        page.controls.castBarEmpowerStage4Color:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -10)
        empowerSection:SetContentHeight(hasFontOfMagic and 190 or 150)
    end
end

API:RegisterConfigTab("castbar", L["Castbar"], CreateCastBarTab, 11.2)
