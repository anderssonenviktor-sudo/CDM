local Runtime = _G["CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L


local function CreateAssistPanel(pressOverlay, keybindings, page)

    local setPOControlsEnabled
    page.controls.pressOverlayEnabled = UI.CreateModernCheckbox(
        pressOverlay,
        L["Enable Press Overlay"],
        CDM.db.pressOverlayEnabled or false,
        function(checked)
            CDM.db.pressOverlayEnabled = checked
            if setPOControlsEnabled then setPOControlsEnabled(checked) end
            API:Refresh("STYLE")
        end
    )
    page.controls.pressOverlayEnabled:SetPoint("TOPLEFT")

    page.controls.pressOverlayTint = UI.CreateModernCheckbox(
        pressOverlay,
        L["Color Tint"],
        CDM.db.pressOverlayTint or false,
        function(checked)
            CDM.db.pressOverlayTint = checked
            if checked then
                CDM.db.pressOverlayHighlight = false
                CDM.db.pressOverlayBorder = false
            end
            API:Refresh("STYLE")
        end
    )
    page.controls.pressOverlayTint:SetPoint("TOPLEFT", page.controls.pressOverlayEnabled, "BOTTOMLEFT", 0, -10)

    page.pressOverlayTintColorPicker = UI.CreateColorSwatch(pressOverlay, L["Tint Color"], "pressOverlayTintColor", "STYLE")
    page.pressOverlayTintColorPicker:SetPoint("TOPLEFT", page.controls.pressOverlayTint, "BOTTOMLEFT", 0, -10)

    local poControls = {
        page.controls.pressOverlayTint, page.pressOverlayTintColorPicker,
    }

    local poOverlay = CreateFrame("Frame", nil, pressOverlay)
    poOverlay:SetPoint("TOPLEFT", page.controls.pressOverlayTint, "TOPLEFT")
    poOverlay:SetPoint("BOTTOMRIGHT", page.pressOverlayTintColorPicker, "BOTTOMRIGHT")
    local poMaxLevel = 0
    for _, ctrl in ipairs(poControls) do
        local lvl = ctrl:GetFrameLevel()
        if lvl > poMaxLevel then poMaxLevel = lvl end
    end
    poOverlay:SetFrameLevel(poMaxLevel + 10)
    poOverlay:EnableMouse(true)
    poOverlay:Hide()

    setPOControlsEnabled = function(en)
        local alpha = en and 1 or 0.35
        for _, ctrl in ipairs(poControls) do
            ctrl:SetAlpha(alpha)
        end
        poOverlay:SetShown(not en)
    end
    setPOControlsEnabled(CDM.db.pressOverlayEnabled or false)
    
    local setKBControlsEnabled
    page.controls.assistEnabled = UI.CreateModernCheckbox(
        keybindings,
        L["Enable Keybind Text"],
        CDM.db.assistEnabled or false,
        function(checked)
            CDM.db.assistEnabled = checked
            if setKBControlsEnabled then setKBControlsEnabled(checked) end
            API:Refresh("STYLE")
        end
    )
    page.controls.assistEnabled:SetPoint("TOPLEFT")

    page.controls.assistFontSize = UI.CreateModernSlider(
        keybindings, L["Font Size"], 1, 30, CDM.db.assistFontSize or 15,
        function(v)
            CDM.db.assistFontSize = v
            API:Refresh("STYLE")
        end
    )
    page.controls.assistFontSize:SetPoint("TOPLEFT", page.controls.assistEnabled, "BOTTOMLEFT", 0, -15)

    page.assistColorPicker = UI.CreateColorSwatch(keybindings, L["Color"], "assistColor", "STYLE")
    page.assistColorPicker:SetPoint("TOPLEFT", page.controls.assistFontSize, "BOTTOMLEFT", 0, -15)

    local lblPos = keybindings:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    lblPos:SetText(L["Position"])
    lblPos:SetPoint("TOPLEFT", page.assistColorPicker, "BOTTOMLEFT", 0, -15)

    local ddPos = UI.CreateDropdown(keybindings)
    ddPos:SetPoint("TOPLEFT", lblPos, "BOTTOMLEFT", 0, -10)
    ddPos:SetWidth(180)
    ddPos:SetDefaultText(CDM.db.assistPosition or "TOPRIGHT")
    page.assistPosDropdown = ddPos

    UI.SetupPositionDropdown(
        ddPos,
        function() return CDM.db.assistPosition end,
        function(pos)
            CDM.db.assistPosition = pos
            ddPos:SetDefaultText(pos)
            API:Refresh("STYLE")
        end
    )

    page.controls.assistOffsetX = UI.CreateModernSlider(
        keybindings, L["X Offset"], -20, 20, CDM.db.assistOffsetX or 0,
        function(v)
            CDM.db.assistOffsetX = v
            API:Refresh("STYLE")
        end
    )
    page.controls.assistOffsetX:SetPoint("TOPLEFT", ddPos, "BOTTOMLEFT", 0, -15)

    page.controls.assistOffsetY = UI.CreateModernSlider(
        keybindings, L["Y Offset"], -20, 20, CDM.db.assistOffsetY or 0,
        function(v)
            CDM.db.assistOffsetY = v
            API:Refresh("STYLE")
        end
    )
    page.controls.assistOffsetY:SetPoint("TOPLEFT", page.controls.assistOffsetX, "BOTTOMLEFT", 0, -15)

    local kbControls = {
        page.controls.assistFontSize, page.assistColorPicker,
        ddPos, page.controls.assistOffsetX, page.controls.assistOffsetY,
    }
    local kbRegions = { lblPos }

    local kbOverlay = CreateFrame("Frame", nil, keybindings)
    kbOverlay:SetPoint("TOPLEFT", page.controls.assistFontSize, "TOPLEFT")
    kbOverlay:SetPoint("BOTTOMRIGHT", page.controls.assistOffsetY, "BOTTOMRIGHT")
    local maxLevel = 0
    for _, ctrl in ipairs(kbControls) do
        local lvl = ctrl:GetFrameLevel()
        if lvl > maxLevel then maxLevel = lvl end
    end
    kbOverlay:SetFrameLevel(maxLevel + 10)
    kbOverlay:EnableMouse(true)
    kbOverlay:Hide()

    setKBControlsEnabled = function(en)
        local alpha = en and 1 or 0.35
        for _, ctrl in ipairs(kbControls) do
            ctrl:SetAlpha(alpha)
        end
        for _, region in ipairs(kbRegions) do
            region:SetAlpha(alpha)
        end
        kbOverlay:SetShown(not en)
    end
    setKBControlsEnabled(CDM.db.assistEnabled or false)
end

ns._CreateAssistPanel = CreateAssistPanel
