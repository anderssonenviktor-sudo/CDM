local Runtime = _G["CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local CDM_C = CDM and CDM.CONST or {}
local L = Runtime.L
local LSM = LibStub("LibSharedMedia-3.0")

ns.ConfigUI = ns.ConfigUI or {}
local UI = ns.ConfigUI

local GOLD = CDM_C.GOLD or { r = 1, g = 0.82, b = 0, a = 1 }
local WHITE = CDM_C.WHITE or { r = 1, g = 1, b = 1, a = 1 }

local colorSwatchesByKey = {}

local function CreateControlSurface(frame)
    local function Texture(layer)
        local texture = frame:CreateTexture(nil, layer)
        return texture
    end

    local background = Texture("BACKGROUND")
    background:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    local borders = {}
    local top = Texture("BORDER")
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    local bottom = Texture("BORDER")
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    local left = Texture("BORDER")
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)
    local right = Texture("BORDER")
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)
    borders[1], borders[2], borders[3], borders[4] = top, bottom, left, right
    return background, borders
end

local function SetControlBorder(borders, r, g, b, a)
    for _, border in ipairs(borders) do
        border:SetColorTexture(r, g, b, a or 1)
    end
end

local function CreateChevron(frame, point, relativeTo, relativePoint, x, y)
    local left = frame:CreateTexture(nil, "OVERLAY")
    local right = frame:CreateTexture(nil, "OVERLAY")
    left:SetSize(6, 1.5)
    right:SetSize(6, 1.5)
    left:SetPoint(point, relativeTo, relativePoint, x - 2, y)
    right:SetPoint(point, relativeTo, relativePoint, x + 2, y)
    left:SetRotation(-math.pi / 4)
    right:SetRotation(math.pi / 4)
    return left, right
end

function UI.StyleDivider(texture)
    texture:SetColorTexture(0.25, 0.25, 0.27, 0.6)
    texture:SetHeight(1)
end

local ConfigMenuStyle = CreateFromMixins(MenuStyle1Mixin)
local MENU_INSET = { left = 1, right = 1, top = 1, bottom = 1 }
local MENU_ROW_HEIGHT = 26
local MENU_CHILD_PADDING = { width = 0, height = 0 }

function ConfigMenuStyle:GetInset()
    return MENU_INSET
end

function ConfigMenuStyle:GetChildExtentPadding()
    -- Row initializers include their own text and arrow padding.
    return MENU_CHILD_PADDING
end

function ConfigMenuStyle:InitScrollLayout(childWidth, maxScrollExtent)
    MenuProxyMixin.InitScrollLayout(self, childWidth, maxScrollExtent)
    -- The native layout reserves an extra ten pixels beyond the scrollbar.
    self:SetFixedSize(
        childWidth + MENU_INSET.left + MENU_INSET.right + self.ScrollBar:GetWidth(),
        maxScrollExtent + MENU_INSET.top + MENU_INSET.bottom
    )
end

function ConfigMenuStyle:Generate()
    -- The backdrop is attached after Blizzard acquires and configures the popup.
end

local function StyleAcquiredMenu(menu)
    menu:SetAlpha(1)
    menu:SetIgnoreParentAlpha(true)

    -- AttachTemplate returns this surface to the menu pool when the popup closes.
    local background = menu:AttachTemplate("BackdropTemplate")
    background:SetAllPoints(menu)
    background:SetFrameLevel(menu:GetFrameLevel())
    background:SetAlpha(1)
    background:SetIgnoreParentAlpha(true)
    background:EnableMouse(false)
    background:SetBackdrop({
        bgFile = CDM_C.TEX_WHITE8X8,
        edgeFile = CDM_C.TEX_WHITE8X8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    background:SetBackdropColor(0.06, 0.06, 0.065, 1)
    background:SetBackdropBorderColor(0.28, 0.28, 0.31, 1)
    background:Show()

    UI.StyleScrollBar(menu, menu.ScrollBox)
end

local function StyleMenuElement(frame, description)
    local fontString = frame.fontString
    if not fontString then return end

    local selected = frame.leftTexture2 ~= nil
    local textLeft = frame.leftTexture1 and 28 or 10
    fontString:SetFontObject("CDM_Font12")
    fontString:ClearAllPoints()
    fontString:SetPoint("LEFT", textLeft, 0)
    fontString:SetHeight(MENU_ROW_HEIGHT)
    -- Refit after changing the font so long media names retain their full width.
    fontString:SetTextToFit(fontString:GetText())
    if selected then
        fontString:SetTextColor(GOLD.r, GOLD.g, GOLD.b, 1)
        local selection = frame:AttachTexture()
        selection:SetDrawLayer("BACKGROUND", -1)
        selection:SetPoint("TOPLEFT", 0, -1)
        selection:SetPoint("BOTTOMRIGHT", 0, 1)
        selection:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 0.09)
    end
    if frame.highlight then
        frame.highlight:ClearAllPoints()
        frame.highlight:SetPoint("TOPLEFT", 0, -1)
        frame.highlight:SetPoint("BOTTOMRIGHT", 0, 1)
        frame.highlight:SetColorTexture(1, 1, 1, 0.08)
        frame.highlight:SetBlendMode("BLEND")
    end
    if frame.leftTexture1 then
        frame.leftTexture1:ClearAllPoints()
        frame.leftTexture1:SetPoint("LEFT", 8, 0)
        frame.leftTexture1:SetSize(12, 12)
        if description:IsRadio() then
            -- Single-choice lists only need a mark beside the selected row.
            frame.leftTexture1:Hide()
        end
    end
    if frame.leftTexture2 then
        frame.leftTexture2:SetAtlas("common-dropdown-icon-checkmark-yellow")
        frame.leftTexture2:SetSize(14, 14)
        frame.leftTexture2:ClearAllPoints()
        frame.leftTexture2:SetPoint("LEFT", 7, 0)
    end
    if frame.arrow then
        frame.arrow:SetTexture("Interface\\AddOns\\CDM\\Media\\Textures\\collapse")
        frame.arrow:SetRotation(-math.pi / 2)
        frame.arrow:SetSize(10, 10)
        frame.arrow:ClearAllPoints()
        frame.arrow:SetPoint("RIGHT", -8, 0)
        frame.arrow:SetVertexColor(0.7, 0.7, 0.7, 1)
    end

    -- Explicit extents keep pooled full-row art out of content measurement.
    local textRight = frame.arrow and 28 or 10
    return textLeft + math.ceil(fontString:GetUnboundedStringWidth()) + textRight, MENU_ROW_HEIGHT
end

local function StyleMenuDescription(description)
    for _, element in description:EnumerateElementDescriptions() do
        element:AddInitializer(StyleMenuElement)
        StyleMenuDescription(element)
    end
end

function UI.CreateDropdown(parent, fontObject)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown.Background:Hide()
    dropdown.Arrow:Hide()
    dropdown.Text:SetFontObject(fontObject or "CDM_Font12")
    dropdown.Text:ClearAllPoints()
    dropdown.Text:SetPoint("LEFT", 10, 0)
    dropdown.Text:SetPoint("RIGHT", -28, 0)
    dropdown.Text:SetHeight(16)

    local background, borders = CreateControlSurface(dropdown)
    local left, right = CreateChevron(dropdown, "CENTER", dropdown, "RIGHT", -14, 0)

    local function UpdateStyle()
        local enabled = dropdown:IsEnabled()
        local active = enabled and (dropdown:IsOver() or dropdown:IsMenuOpen())
        background:SetColorTexture(0.045, 0.045, 0.05, enabled and 0.96 or 0.5)
        if active then
            SetControlBorder(borders, GOLD.r, GOLD.g, GOLD.b, 0.55)
        else
            SetControlBorder(borders, 0.25, 0.25, 0.28, enabled and 1 or 0.45)
        end
        local c = enabled and 0.75 or 0.35
        left:SetColorTexture(c, c, c, 1)
        right:SetColorTexture(c, c, c, 1)
    end

    -- Keep the intrinsic dropdown's selection, refresh and submenu behavior.
    dropdown.menuMixin = ConfigMenuStyle
    local setupMenu = dropdown.SetupMenu
    function dropdown:SetupMenu(generator)
        setupMenu(self, function(owner, rootDescription)
            rootDescription:AddMenuAcquiredCallback(StyleAcquiredMenu)
            generator(owner, rootDescription)
            StyleMenuDescription(rootDescription)
        end)
    end
    hooksecurefunc(dropdown, "OnButtonStateChanged", UpdateStyle)
    dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuOpen, UpdateStyle)
    dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuClose, UpdateStyle)
    dropdown:HookScript("OnHide", function(self) self:CloseMenu() end)
    UpdateStyle()
    return dropdown
end

function UI.PositionDropdownRow(dropdown, label, parent, x, y, width)
    dropdown:ClearAllPoints()
    CDM.Pixel.SetPoint(dropdown, "TOPLEFT", parent, "TOPLEFT", x, y)
    CDM.Pixel.SetSize(dropdown, width, 26)
    label:ClearAllPoints()
    label:SetPoint("LEFT", dropdown, "LEFT", -CDM.Pixel.Snap(x), 0)
end

local function StyleSliderWithSteppers(control)
    local slider = control.Slider
    slider.Left:Hide()
    slider.Middle:Hide()
    slider.Right:Hide()
    slider.Thumb:SetTexture(CDM_C.TEX_WHITE8X8)
    slider.Thumb:SetSize(8, 14)
    slider.Thumb:SetDrawLayer("OVERLAY")

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.22, 0.22, 0.24, 1)
    track:SetHeight(3)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(3)
    fill:SetPoint("LEFT", track, "LEFT")

    local function UpdateFill()
        local minValue, maxValue = slider:GetMinMaxValues()
        local ratio = maxValue > minValue and (slider:GetValue() - minValue) / (maxValue - minValue) or 0
        ratio = math.max(0, math.min(1, ratio))
        fill:SetWidth(math.max(1, track:GetWidth() * ratio))
        fill:SetShown(ratio > 0)
        local enabled = control:IsSliderEnabled()
        fill:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, enabled and 0.65 or 0.2)
        local c = enabled and 0.9 or 0.4
        slider.Thumb:SetVertexColor(c, c, c, 1)
    end

    -- Glyphs drawn as textures: font "-"/"+" sit off the track's vertical centre.
    local STEPPER_LEN, STEPPER_THICK = 8, 2
    for _, info in ipairs({ { control.Back, false }, { control.Forward, true } }) do
        local button, isPlus = info[1], info[2]
        for _, region in ipairs({ button:GetRegions() }) do region:Hide() end
        button:SetSize(16, 20)
        -- Reuse the template's anchor (re-anchoring to the slider could loop) and
        -- drop its y offset so the glyph centres on the track.
        local point, relativeTo, relativePoint, x = button:GetPoint(1)
        if point then
            button:ClearAllPoints()
            button:SetPoint(point, relativeTo, relativePoint, x, 0)
        end

        local bars = {}
        local horizontal = button:CreateTexture(nil, "OVERLAY")
        horizontal:SetSize(STEPPER_LEN, STEPPER_THICK)
        horizontal:SetPoint("CENTER")
        bars[1] = horizontal
        if isPlus then
            local vertical = button:CreateTexture(nil, "OVERLAY")
            vertical:SetSize(STEPPER_THICK, STEPPER_LEN)
            vertical:SetPoint("CENTER")
            bars[2] = vertical
        end

        local function SetGlyphColor(r, g, b)
            for _, bar in ipairs(bars) do bar:SetColorTexture(r, g, b, 1) end
        end
        SetGlyphColor(0.65, 0.65, 0.65)
        button:HookScript("OnEnter", function()
            if button:IsEnabled() then SetGlyphColor(GOLD.r, GOLD.g, GOLD.b) end
        end)
        button:HookScript("OnLeave", function() SetGlyphColor(0.65, 0.65, 0.65) end)
    end

    slider:HookScript("OnValueChanged", UpdateFill)
    slider:HookScript("OnSizeChanged", UpdateFill)
    slider:HookScript("OnShow", UpdateFill)
    hooksecurefunc(control, "SetEnabled", UpdateFill)
    UpdateFill()
end

-- Callers routinely SetScript OnEditFocusLost/OnEnter after creation, which
-- would drop hooked styling, so a child frame polls the state while visible.
local function StyleEditBox(editBox, surface)
    surface = surface or editBox
    local background, borders = CreateControlSurface(surface)
    local watcher = CreateFrame("Frame", nil, surface)
    local lastState

    local function UpdateStyle()
        local enabled = editBox:IsEnabled()
        local state = (not enabled and 1) or (editBox:HasFocus() and 2) or (surface:IsMouseOver() and 3) or 4
        if state == lastState then return end
        lastState = state
        background:SetColorTexture(0.025, 0.025, 0.03, enabled and 0.9 or 0.45)
        if state == 2 then
            SetControlBorder(borders, GOLD.r, GOLD.g, GOLD.b, 0.65)
        elseif state == 3 then
            SetControlBorder(borders, GOLD.r, GOLD.g, GOLD.b, 0.35)
        else
            SetControlBorder(borders, 0.25, 0.25, 0.28, enabled and 1 or 0.45)
        end
    end

    watcher:SetScript("OnUpdate", UpdateStyle)
    UpdateStyle()
end

-- Flat replacement for InputBoxTemplate. The frame bounds are the visible box;
-- the template's art extended 5px past the left edge.
function UI.CreateEditBox(parent, fontObject)
    local editBox = CreateFrame("EditBox", nil, parent)
    editBox:SetFontObject(fontObject or "CDM_Font14")
    editBox:SetTextInsets(6, 6, 0, 0)
    editBox:SetAutoFocus(false)
    -- Same defaults as InputBoxTemplate; callers may replace any of them.
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    editBox:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    StyleEditBox(editBox)
    return editBox
end

function UI.ApplyCrossIcon(button)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(24, 24)
    icon:SetTexture("Interface\\AddOns\\CDM\\Media\\Textures\\cross-small-white")
    icon:SetVertexColor(1, 0.267, 0.267, 1)
    return icon
end

function UI.CreateConfigWindow(parent, name)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = CDM_C.TEX_WHITE8X8,
        edgeFile = CDM_C.TEX_WHITE8X8,
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.035, 0.035, 0.04, 0.96)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)

    local closeButton = CreateFrame("Button", nil, frame)
    closeButton:SetSize(24, 24)
    closeButton:SetPoint("TOPRIGHT", -8, -8)
    closeButton:SetFrameLevel(frame:GetFrameLevel() + 20)

    UI.ApplyCrossIcon(closeButton)

    closeButton:SetScript("OnClick", function() frame:Hide() end)
    closeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Close"])
        GameTooltip:Show()
    end)
    closeButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    closeButton:SetScript("OnHide", function() GameTooltip:Hide() end)
    frame.CloseButton = closeButton
    return frame
end

function UI.CreateTextButton(parent, tint)
    local button = CreateFrame("Button", nil, parent)
    local text = button:CreateFontString(nil, "OVERLAY", "CDM_Font12")
    text:SetPoint("LEFT", 6, 0)
    text:SetPoint("RIGHT", -6, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    button:SetFontString(text)
    local background, borders = CreateControlSurface(button)
    local pressed, hovered = false, false

    local function UpdateStyle()
        if not button:IsEnabled() then
            background:SetColorTexture(0.035, 0.035, 0.04, 0.5)
            SetControlBorder(borders, 0.15, 0.15, 0.17, 1)
            text:SetTextColor(0.35, 0.35, 0.35, 1)
        elseif pressed then
            background:SetColorTexture(0.13, 0.12, 0.075, 0.95)
            SetControlBorder(borders, GOLD.r, GOLD.g, GOLD.b, 0.7)
            text:SetTextColor(1, 1, 1, 1)
        elseif hovered then
            background:SetColorTexture(0.095, 0.095, 0.105, 0.95)
            SetControlBorder(borders, GOLD.r, GOLD.g, GOLD.b, 0.45)
            text:SetTextColor(1, 1, 1, 1)
        else
            background:SetColorTexture(0.05, 0.05, 0.055, 0.95)
            SetControlBorder(borders, 0.25, 0.25, 0.28, 1)
            text:SetTextColor(0.85, 0.85, 0.85, 1)
        end
        if tint and button:IsEnabled() then
            local strength = pressed and 0.18 or hovered and 0.15 or 0.12
            background:SetColorTexture(math.max(0.035, tint.r * strength),
                math.max(0.035, tint.g * strength), math.max(0.035, tint.b * strength), 0.8)
            SetControlBorder(borders, tint.r, tint.g, tint.b, pressed and 0.8 or hovered and 0.65 or 0.45)
        end
    end

    button:HookScript("OnEnter", function() hovered = true; UpdateStyle() end)
    button:HookScript("OnLeave", function() hovered = false; pressed = false; UpdateStyle() end)
    button:HookScript("OnMouseDown", function() pressed = true; UpdateStyle() end)
    button:HookScript("OnMouseUp", function() pressed = false; UpdateStyle() end)
    button:HookScript("OnDisable", function() pressed = false; UpdateStyle() end)
    button:HookScript("OnEnable", UpdateStyle)
    button:HookScript("OnHide", function() hovered = false; pressed = false; UpdateStyle() end)
    UpdateStyle()
    return button
end

local function BroadcastSwatchColor(key, r, g, b, a)
    local swatches = colorSwatchesByKey[key]
    if not swatches then return end
    for swatchFrame in pairs(swatches) do
        swatchFrame:UpdateColor(r, g, b, a)
    end
end

local function TriggerConfigRefresh(scope)
    API:Refresh(scope)
end

function UI.CreateColorSwatch(parent, label, key, scope)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(250, 30)

    local text = frame:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)

    local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
    button:SetSize(20, 20)
    button:SetPoint("LEFT", text, "RIGHT", 8, 0)
    button:SetBackdrop({
        edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1,
        bgFile = CDM_C.TEX_WHITE8X8,
    })

    local color = CDM.db[key] or CDM.defaults[key] or CDM.defaults.borderColor
    button:SetBackdropColor(color.r, color.g, color.b, color.a)
    button:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    if not colorSwatchesByKey[key] then
        colorSwatchesByKey[key] = setmetatable({}, { __mode = "k" })
    end
    colorSwatchesByKey[key][frame] = true

    function frame:UpdateColor(r, g, b, a)
        button:SetBackdropColor(r, g, b, a)
        if frame.OnChange then
            frame.OnChange(r, g, b, a)
        end
    end

    local enabledFlag = true

    button:SetScript("OnClick", function()
        if not enabledFlag then return end
        local color = CDM.db[key] or CDM.defaults[key] or CDM.defaults.borderColor
        local function ApplyPickedColor()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            CDM.db[key] = { r = r, g = g, b = b, a = a }
            BroadcastSwatchColor(key, r, g, b, a)
            TriggerConfigRefresh(scope)
        end

        local info = {
            swatchFunc = ApplyPickedColor,
            opacityFunc = ApplyPickedColor,
            cancelFunc = function(prev)
                CDM.db[key] = prev
                BroadcastSwatchColor(key, prev.r, prev.g, prev.b, prev.a)
                TriggerConfigRefresh(scope)
            end,
            r = color.r, g = color.g, b = color.b, opacity = color.a,
            hasOpacity = true,
            previousValues = { r = color.r, g = color.g, b = color.b, a = color.a }
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    function frame:SetEnabled(enabled)
        enabledFlag = enabled and true or false
        button:EnableMouse(enabledFlag)
        local v = enabledFlag and 1 or 0.5
        text:SetTextColor(v, v, v, 1)
        frame:SetAlpha(enabledFlag and 1 or 0.5)
    end

    return frame
end

local function CreateSectionHeader(parent, text, anchorFrame, yOffset, fontObject, anchoredOffset, topOffset)
    local header = parent:CreateFontString(nil, "ARTWORK", fontObject)
    if anchorFrame then
        header:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, yOffset or anchoredOffset)
    else
        header:SetPoint("TOPLEFT", 0, yOffset or topOffset)
    end
    header:SetText(text)
    header:SetTextColor(GOLD.r, GOLD.g, GOLD.b, GOLD.a or 1)
    return header
end

function UI.CreateSimpleColorPicker(parent, initialColor, onChange, hasOpacity)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(20, 20)
    button:SetBackdrop({
        edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1,
        bgFile = CDM_C.TEX_WHITE8X8,
    })

    local color = initialColor
        and { r = initialColor.r, g = initialColor.g, b = initialColor.b, a = initialColor.a or 1 }
        or { r = 1, g = 1, b = 1, a = 1 }

    local function DrawSwatch()
        local drawA = hasOpacity and color.a or 1
        button:SetBackdropColor(color.r, color.g, color.b, drawA)
    end

    DrawSwatch()
    button:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    function button:UpdateColor(r, g, b, a)
        color.r, color.g, color.b = r, g, b
        if a ~= nil then color.a = a end
        DrawSwatch()
    end

    button:SetScript("OnClick", function()
        local prevR, prevG, prevB, prevA = color.r, color.g, color.b, color.a
        local info = {
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = hasOpacity and ColorPickerFrame:GetColorAlpha() or 1
                button:UpdateColor(r, g, b, a)
                if onChange then onChange(r, g, b, a) end
            end,
            opacityFunc = function()
                if not hasOpacity then return end
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                button:UpdateColor(r, g, b, a)
                if onChange then onChange(r, g, b, a) end
            end,
            cancelFunc = function()
                button:UpdateColor(prevR, prevG, prevB, prevA)
                if onChange then onChange(prevR, prevG, prevB, prevA) end
            end,
            r = color.r, g = color.g, b = color.b,
            hasOpacity = hasOpacity and true or false,
            opacity = color.a,
            previousValues = { r = prevR, g = prevG, b = prevB, opacity = prevA },
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    return button
end

-- The input overlaps the slider's hit rect, so it must sit above the slider's
-- frame level or clicks on the box land on the slider instead.
local function CreateSliderInput(panel)
    local eb = CreateFrame("EditBox", nil, panel)
    eb:SetSize(50, 18)
    eb:SetPoint("BOTTOM", panel.Slider, "TOP", 0, -8)
    eb:SetFrameLevel(panel.Slider.Slider:GetFrameLevel() + 2)
    eb:SetFontObject("CDM_Font14")
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(0, 0, 0, 0)
    eb:SetAutoFocus(false)
    StyleEditBox(eb)
    return eb
end

function UI.CreateModernSlider(parent, label, minVal, maxVal, currentVal, onValueChanged, labelWidth, sliderWidth)
    currentVal = tonumber(currentVal) or minVal
    local lw = labelWidth or 200
    local sw = sliderWidth or 240

    local function toInt(v)
        if v >= 0 then return math.floor(v) else return math.ceil(v) end
    end

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(lw + 4 + sw, 40)

    panel.Label = panel:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    panel.Label:SetPoint("LEFT", 0, 0)
    panel.Label:SetText(label)
    panel.Label:SetWidth(lw)
    panel.Label:SetJustifyH("LEFT")

    local initVal = toInt(currentVal)

    panel.Slider = CreateFrame("Slider", nil, panel, "MinimalSliderWithSteppersTemplate")
    panel.Slider:SetPoint("LEFT", panel.Label, "RIGHT", 4, 0)
    panel.Slider:SetWidth(sw)
    panel.Slider:Init(initVal, minVal, maxVal, (maxVal - minVal), {
        [MinimalSliderWithSteppersMixin.Label.Top] = nil,
        [MinimalSliderWithSteppersMixin.Label.Right] = nil
    })
    StyleSliderWithSteppers(panel.Slider)

    panel.Input = CreateSliderInput(panel)
    local suppressOnValueChanged = false

    local function SetSliderValue(value, suppressCallback)
        if suppressCallback then
            suppressOnValueChanged = true
        end
        panel.Slider:SetValue(value)
        if suppressCallback then
            suppressOnValueChanged = false
        end
    end

    panel.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        local numVal = tonumber(value)
        if not numVal then numVal = minVal end
        local val = toInt(numVal)
        if not panel.Input:HasFocus() then panel.Input:SetText(val) end
        if suppressOnValueChanged then
            return
        end
        onValueChanged(val)
    end)

    panel.Input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = math.max(minVal, math.min(maxVal, val))
            self:SetText(val)
            SetSliderValue(val, false)
        end
        self:ClearFocus()
    end)

    panel.Input:SetScript("OnEscapePressed", function(self)
        self:SetText(toInt(panel.Slider:GetValue()))
        self:ClearFocus()
    end)

    panel.Input:SetText(initVal)

    function panel:UpdateUIValue(value)
        local clamped = math.max(minVal, math.min(maxVal, toInt(value)))
        SetSliderValue(clamped, true)
        panel.Input:SetText(clamped)
    end

    return panel
end

function UI.CreateModernSliderPrecise(parent, label, minVal, maxVal, currentVal, step, decimals, onValueChanged)
    currentVal = tonumber(currentVal) or minVal
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(400, 40)

    local valueStep = tonumber(step) or 0.05
    if valueStep <= 0 then
        valueStep = 0.05
    end

    local valueDecimals = tonumber(decimals) or 2
    if valueDecimals < 0 then
        valueDecimals = 0
    end

    local factor = 10 ^ valueDecimals
    local function RoundNearest(value)
        if value >= 0 then
            return math.floor(value + 0.5)
        end
        return math.ceil(value - 0.5)
    end

    local minScaled = RoundNearest(minVal * factor)
    local maxScaled = RoundNearest(maxVal * factor)
    local stepScaled = math.max(1, RoundNearest(valueStep * factor))

    local function ClampAndQuantize(value)
        local numVal = tonumber(value)
        if not numVal then
            numVal = minVal
        end

        local scaled = RoundNearest(numVal * factor)
        scaled = math.max(minScaled, math.min(maxScaled, scaled))
        local stepsFromMin = (scaled - minScaled) / stepScaled
        local snappedSteps = RoundNearest(stepsFromMin)
        local quantizedScaled = minScaled + (snappedSteps * stepScaled)
        quantizedScaled = math.max(minScaled, math.min(maxScaled, quantizedScaled))
        return quantizedScaled / factor
    end

    local function ToScaled(value)
        return RoundNearest(ClampAndQuantize(value) * factor)
    end

    local function FormatValue(value)
        local asString = string.format("%." .. valueDecimals .. "f", value)
        asString = asString:gsub("(%..-)0+$", "%1")
        asString = asString:gsub("%.$", "")
        return asString
    end

    panel.Label = panel:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    panel.Label:SetPoint("LEFT", 0, 0)
    panel.Label:SetText(label)
    panel.Label:SetWidth(200)
    panel.Label:SetJustifyH("LEFT")

    panel.Slider = CreateFrame("Slider", nil, panel, "MinimalSliderWithSteppersTemplate")
    panel.Slider:SetPoint("LEFT", panel.Label, "RIGHT", 4, 0)
    panel.Slider:SetWidth(240)
    local numSteps = math.max(1, RoundNearest((maxScaled - minScaled) / stepScaled))
    panel.Slider:Init(ToScaled(currentVal), minScaled, maxScaled, numSteps, {
        [MinimalSliderWithSteppersMixin.Label.Top] = nil,
        [MinimalSliderWithSteppersMixin.Label.Right] = nil
    })
    StyleSliderWithSteppers(panel.Slider)

    panel.Input = CreateSliderInput(panel)
    local suppressOnValueChanged = false

    local function SetSliderValue(value, suppressCallback)
        if suppressCallback then
            suppressOnValueChanged = true
        end
        panel.Slider:SetValue(value)
        if suppressCallback then
            suppressOnValueChanged = false
        end
    end

    panel.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        local quantized = ClampAndQuantize((tonumber(value) or minScaled) / factor)
        if not panel.Input:HasFocus() then panel.Input:SetText(FormatValue(quantized)) end
        if suppressOnValueChanged then
            return
        end
        onValueChanged(quantized)
    end)

    panel.Input:SetScript("OnEnterPressed", function(self)
        local quantized = ClampAndQuantize(self:GetText())
        self:SetText(FormatValue(quantized))
        SetSliderValue(ToScaled(quantized), false)
        self:ClearFocus()
    end)

    panel.Input:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatValue(ClampAndQuantize((panel.Slider:GetValue() or minScaled) / factor)))
        self:ClearFocus()
    end)

    panel.Input:SetText(FormatValue(ClampAndQuantize(currentVal)))

    function panel:UpdateUIValue(value)
        local quantized = ClampAndQuantize(value)
        SetSliderValue(ToScaled(quantized), true)
        panel.Input:SetText(FormatValue(quantized))
    end

    return panel
end

function UI.RoundToInt(value)
    local num = tonumber(value)
    if not num then return 0 end
    return math.floor(num + 0.5)
end

function UI.CreateModernCheckbox(parent, label, initialValue, onChange)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(400, 26)

    local checkbox = CreateFrame("CheckButton", nil, frame)
    checkbox:SetSize(18, 18)
    checkbox:SetPoint("LEFT", 0, 0)

    local background, borders = CreateControlSurface(checkbox)

    local fill = checkbox:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMRIGHT", -4, 4)
    fill:SetColorTexture(1, 1, 1, 1)

    local fillFade = fill:CreateAnimationGroup()
    local fadeIn = fillFade:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.1)

    local text = frame:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    text:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    text:SetText(label)

    local hovered = false

    local function UpdateStyle()
        local enabled = checkbox:IsEnabled()
        local checked = checkbox:GetChecked()
        if not enabled then
            background:SetColorTexture(0.035, 0.035, 0.04, 0.5)
            SetControlBorder(borders, 0.15, 0.15, 0.17, 1)
        elseif checked then
            background:SetColorTexture(0.05, 0.05, 0.055, 0.95)
            SetControlBorder(borders, GOLD.r, GOLD.g, GOLD.b, hovered and 1 or 0.85)
        elseif hovered then
            background:SetColorTexture(0.095, 0.095, 0.105, 0.95)
            SetControlBorder(borders, GOLD.r, GOLD.g, GOLD.b, 0.6)
        else
            background:SetColorTexture(0.05, 0.05, 0.055, 0.95)
            SetControlBorder(borders, 0.25, 0.25, 0.28, 1)
        end

        fill:SetShown(checked and true or false)
        if hovered and enabled then
            fill:SetVertexColor(1, 0.9, 0.35, 1)
        else
            fill:SetVertexColor(GOLD.r, GOLD.g, GOLD.b, enabled and 1 or 0.4)
        end

        if not enabled then
            text:SetTextColor(0.4, 0.4, 0.4, 1)
        elseif checked or hovered then
            text:SetTextColor(1, 1, 1, 1)
        else
            text:SetTextColor(0.55, 0.55, 0.55, 1)
        end
    end

    -- Extend the click area over the label so the whole row toggles.
    local function UpdateHitRect()
        local labelWidth = math.ceil(text:GetStringWidth() or 0)
        checkbox:SetHitRectInsets(0, -(labelWidth + 8), -4, -4)
    end

    checkbox:SetChecked(initialValue or false)
    UpdateHitRect()

    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if onChange then
            onChange(checked)
        end
    end)

    -- PostClick (not OnClick) so the style survives callers replacing OnClick.
    checkbox:SetScript("PostClick", function(self)
        if self:GetChecked() then
            fillFade:Stop()
            fillFade:Play()
        end
        UpdateStyle()
    end)
    checkbox:SetScript("OnEnter", function() hovered = true; UpdateStyle() end)
    checkbox:SetScript("OnLeave", function() hovered = false; UpdateStyle() end)
    checkbox:HookScript("OnEnable", UpdateStyle)
    checkbox:HookScript("OnDisable", UpdateStyle)
    checkbox:HookScript("OnHide", function() hovered = false; UpdateStyle() end)
    hooksecurefunc(checkbox, "SetChecked", UpdateStyle)
    hooksecurefunc(text, "SetText", UpdateHitRect)
    UpdateStyle()

    frame.checkbox = checkbox
    frame.label = text

    function frame:SetChecked(checked)
        checkbox:SetChecked(checked)
    end

    function frame:GetChecked()
        return checkbox:GetChecked()
    end

    function frame:SetEnabled(enabled)
        if enabled then
            checkbox:Enable()
        else
            checkbox:Disable()
        end
    end

    return frame
end

function UI.CreateHeader(parent, text, anchorFrame, yOffset)
    return CreateSectionHeader(parent, text, anchorFrame, yOffset, "CDM_Font18", -15, -10)
end

function UI.CreateSubHeader(parent, text, anchorFrame, yOffset)
    return CreateSectionHeader(parent, text, anchorFrame, yOffset, "CDM_Font14", -12, -10)
end

UI.TextColors = UI.TextColors or {
    white = { r = WHITE.r, g = WHITE.g, b = WHITE.b, a = WHITE.a or 1 },
    muted = { r = 0.7, g = 0.7, b = 0.7, a = 1 },
    dim = { r = 0.6, g = 0.6, b = 0.6, a = 1 },
    subtle = { r = 0.8, g = 0.8, b = 0.8, a = 1 },
    faint = { r = 0.5, g = 0.5, b = 0.5, a = 1 },
    placeholder = { r = 0.55, g = 0.55, b = 0.55, a = 1 },
    inactive = { r = 0.82, g = 0.82, b = 0.82, a = 1 },
    success = { r = 0.5, g = 1, b = 0.5, a = 1 },
    error = { r = 1, g = 0.3, b = 0.3, a = 1 },
}

function UI.SetTextColor(fontString, color)
    if not fontString or not color then return end
    fontString:SetTextColor(color.r, color.g, color.b, color.a or 1)
end

function UI.SetTextMuted(fontString)
    UI.SetTextColor(fontString, UI.TextColors.muted)
end

function UI.SetTextSubtle(fontString)
    UI.SetTextColor(fontString, UI.TextColors.subtle)
end

function UI.SetTextFaint(fontString)
    UI.SetTextColor(fontString, UI.TextColors.faint)
end

function UI.SetTextInactive(fontString)
    UI.SetTextColor(fontString, UI.TextColors.inactive)
end

function UI.SetTextWhite(fontString)
    UI.SetTextColor(fontString, UI.TextColors.white)
end

function UI.SetTextSuccess(fontString)
    UI.SetTextColor(fontString, UI.TextColors.success)
end

function UI.SetTextError(fontString)
    UI.SetTextColor(fontString, UI.TextColors.error)
end

function UI.CloseAllDropdownMenus()
    if Menu and Menu.GetManager then
        Menu.GetManager():CloseMenus()
    end
end

function UI.AttachCloseMenusOnScroll(scrollFrame)
    if not scrollFrame or scrollFrame._cdmCloseMenusOnScrollHooked then
        return
    end

    scrollFrame._cdmCloseMenusOnScrollHooked = true
    scrollFrame:HookScript("OnVerticalScroll", function()
        UI.CloseAllDropdownMenus()
    end)
    scrollFrame:HookScript("OnHide", function()
        UI.CloseAllDropdownMenus()
    end)
end

function UI.StyleScrollBar(scrollFrame, scrollRegion)
    local bar = scrollFrame.ScrollBar
    if not bar or bar._cdmStyled then return end
    bar._cdmStyled = true

    local anchor = scrollRegion or scrollFrame
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
    bar:SetWidth(10)

    local function HideArrow(button)
        if not button then return end
        button:Hide()
        button:EnableMouse(false)
    end
    HideArrow(bar.Back or bar.ScrollUpButton)
    HideArrow(bar.Forward or bar.ScrollDownButton)

    local function HideArtwork(frame)
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:IsObjectType("Texture") then region:SetAlpha(0) end
        end
    end
    HideArtwork(bar)
    if bar.Background then
        bar.Background:Hide()
    end

    local track = bar.Track or bar
    if track ~= bar then
        HideArtwork(track)
        track:ClearAllPoints()
        track:SetAllPoints(bar)
    end
    local background = track:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOP", 0, 0)
    background:SetPoint("BOTTOM", 0, 0)
    background:SetWidth(6)
    background:SetColorTexture(0.10, 0.10, 0.12, 0.9)

    if bar.GetThumb then
        local thumb = bar:GetThumb()
        -- Keep Blizzard's atlas regions intact for its size and state callbacks.
        HideArtwork(thumb)
        thumb:SetWidth(10)
        local fill = thumb:CreateTexture(nil, "OVERLAY")
        fill:SetPoint("TOP", 0, 0)
        fill:SetPoint("BOTTOM", 0, 0)
        fill:SetWidth(6)
        fill:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 1)
        fill:SetAlpha(0.85)
        thumb:HookScript("OnEnter", function() fill:SetAlpha(1) end)
        thumb:HookScript("OnLeave", function() fill:SetAlpha(0.85) end)
        bar:SetHideIfUnscrollable(true)
    else
        local thumb = bar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 1)
            thumb:SetAlpha(0.85)
            thumb:SetSize(6, 40)
            bar:HookScript("OnEnter", function() thumb:SetAlpha(1) end)
            bar:HookScript("OnLeave", function() thumb:SetAlpha(0.85) end)
        end
        local function UpdateVisibility()
            bar:SetShown(scrollFrame:GetVerticalScrollRange() > 0)
        end
        scrollFrame:HookScript("OnScrollRangeChanged", UpdateVisibility)
        scrollFrame:HookScript("OnShow", UpdateVisibility)
        UpdateVisibility()
    end
end

function UI.CreateScrollableTab(page, frameName, contentHeight, contentWidth)
    local scrollFrame = CreateFrame("ScrollFrame", frameName, page, "ScrollFrameTemplate")
    UI.StyleScrollBar(scrollFrame)
    scrollFrame:SetPoint("TOPLEFT", 0, -20)
    scrollFrame:SetPoint("BOTTOMRIGHT", -10, 20)
    UI.AttachCloseMenusOnScroll(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(contentWidth or 460, contentHeight or 800)
    scrollFrame:SetScrollChild(scrollChild)

    local contentContainer = CreateFrame("Frame", nil, scrollChild)
    contentContainer:SetPoint("TOPLEFT", 35, -20)
    contentContainer:SetPoint("TOPRIGHT", -25, -20)
    contentContainer:SetHeight(contentHeight or 800)

    return contentContainer, scrollFrame
end

local SCROLL_BOTTOM_PAD = 20

function UI.MakeSubPageScroll(subPage, frameName)
    local sf = CreateFrame("ScrollFrame", frameName, subPage, "ScrollFrameTemplate")
    UI.StyleScrollBar(sf)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -10, 0)
    UI.AttachCloseMenusOnScroll(sf)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(540)
    sf:SetScrollChild(sc)

    local rc = CreateFrame("Frame", nil, sc)
    rc:SetPoint("TOPLEFT", 30, 0)
    rc:SetPoint("TOPRIGHT", -20, 0)
    return rc, sc
end

function UI.FinalizeScroll(sc, rc, yOff)
    local h = math.abs(yOff) + SCROLL_BOTTOM_PAD
    sc:SetHeight(h)
    rc:SetHeight(h)
end

function UI.CreateVerticalLayout(startY)
    local layout = { y = startY or 0 }
    function layout:Next(spacing)
        self.y = self.y - spacing
        return self.y
    end
    return layout
end

UI.PositionOptions = {
    "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT",
    "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
}

-- "Anchor To" choices, shared by the Options pages and Anchor Mode.
UI.AnchorTargets = {
    cooldownGroup = {
        { label = L["Screen"], value = "screen" },
        { label = L["Player Frame"], value = "playerFrame" },
        { label = L["Essential Viewer"], value = "essential" },
        { label = L["Utility Viewer"], value = "utility" },
        { label = L["Buff Viewer"], value = "buff" },
        { label = L["Cast Bar"], value = "castBar" },
        { label = L["Resource Bar"], value = "resources" },
    },
    buffGroup = {
        { label = L["Screen"], value = "screen" },
        { label = L["Player Frame"], value = "playerFrame" },
        { label = L["Essential Viewer"], value = "essential" },
        { label = L["Buff Viewer"], value = "buff" },
        { label = L["Cast Bar"], value = "castBar" },
        { label = L["Resource Bar"], value = "resources" },
    },
    buffBarGroup = {
        { label = L["Screen"], value = "screen" },
        { label = L["Player Frame"], value = "playerFrame" },
        { label = L["Essential Viewer"], value = "essential" },
        { label = L["Buff Viewer"], value = "buff" },
        { label = L["Buff Bar Viewer"], value = "buffBar" },
        { label = L["Cast Bar"], value = "castBar" },
        { label = L["Resource Bar"], value = "resources" },
    },
    buffViewer = {
        { label = L["Screen"], value = "screen" },
        { label = L["Player Frame"], value = "playerFrame" },
        { label = L["Essential Viewer"], value = "essential" },
        { label = L["Cast Bar"], value = "castBar" },
        { label = L["Resource Bar"], value = "resources" },
    },
}

function UI.GetCastBarAnchorTargets()
    local options = {
        { value = "screen", label = L["Screen"] },
        { value = "playerFrame", label = L["Player Frame"] },
        { value = "essential", label = L["Essential Viewer"] },
        { value = "utility", label = L["Utility Viewer"] },
    }
    if CDM.db.resourcesEnabled ~= false then
        options[#options + 1] = { value = "resources", label = L["Resources"] }
    end
    return options
end

UI.GlowTypeOptions = {
    { value = "pixel", label = L["Pixel Glow"] },
    { value = "autocast", label = L["Autocast Glow"] },
    { value = "button", label = L["Button Glow"] },
    { value = "proc", label = L["Proc Glow"] },
    { value = "gcd", label = L["GCD"] },
    { value = "shape", label = L["Shape Glow"] },
}

function UI.SetupValueDropdown(dropdown, options, getValue, setValue)
    dropdown:SetupMenu(function(_, rootDescription)
        local opts = type(options) == "function" and options() or options
        for _, opt in ipairs(opts) do
            rootDescription:CreateRadio(opt.label, function() return getValue() == opt.value end, function()
                setValue(opt.value, opt.label)
            end)
        end
    end)
end

function UI.CreateSpellGlowTypeOverride(parent, yOff, specID, spellID, registerDropdown)
    local label = parent:CreateFontString(nil, "OVERLAY", "CDM_Font14")
    label:SetText(L["Glow Type"])
    label:SetPoint("TOPLEFT", 0, yOff)

    local dropdown = UI.CreateDropdown(parent)
    if registerDropdown then dropdown = registerDropdown(dropdown) end
    dropdown:SetWidth(170)
    dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)

    local options = { { value = nil, label = L["Use Global Glow Type"] } }
    for _, option in ipairs(UI.GlowTypeOptions) do
        options[#options + 1] = option
    end
    local currentType = API:GetSpellGlowType(specID, spellID)
    dropdown:SetDefaultText(UI.GetOptionLabel(options, currentType, L["Use Global Glow Type"]))
    UI.SetupValueDropdown(dropdown, options,
        function() return API:GetSpellGlowType(specID, spellID) end,
        function(value, optionLabel)
            API:SetSpellGlowType(specID, spellID, value)
            dropdown:SetDefaultText(optionLabel)
        end)
    return yOff - 36
end

function UI.SetupPositionDropdown(dropdown, getValue, setValue, positions)
    local options = positions or UI.PositionOptions
    dropdown:SetupMenu(function(_, rootDescription)
        for _, pos in ipairs(options) do
            rootDescription:CreateRadio(pos, function() return getValue() == pos end, function()
                setValue(pos)
            end)
        end
    end)
end

local lsmListCache = {}

local function GetCachedMediaList(mediaType)
    if lsmListCache[mediaType] then return lsmListCache[mediaType] end
    local raw = LSM:List(mediaType) or {}
    local sorted = {}
    for i, name in ipairs(raw) do sorted[i] = name end
    table.sort(sorted)
    local deduped = {}
    local seenPaths = {}
    for _, name in ipairs(sorted) do
        local path = LSM:Fetch(mediaType, name)
        if not path or not seenPaths[path] then
            if path then seenPaths[path] = true end
            deduped[#deduped + 1] = name
        end
    end
    lsmListCache[mediaType] = deduped
    return deduped
end

function UI.SetupMediaDropdown(dropdown, mediaType, getValue, setValue, setText, maxVisibleRows)
    if maxVisibleRows then
        dropdown:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2))
    end
    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetScrollMode(maxVisibleRows and MENU_ROW_HEIGHT * maxVisibleRows or 500)
        local list = GetCachedMediaList(mediaType)
        for _, name in ipairs(list) do
            local entry = rootDescription:CreateRadio(name, function() return getValue() == name end, function()
                setValue(name)
                if setText then
                    setText(name)
                end
            end)
            if mediaType == "statusbar" then
                local path = LSM:Fetch(mediaType, name)
                entry:AddInitializer(function(frame)
                    local preview = frame:AttachTexture()
                    preview:SetDrawLayer("BACKGROUND", -2)
                    preview:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
                    preview:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                    if type(path) == "string" and C_Texture.GetAtlasInfo(path) then
                        preview:SetAtlas(path)
                    else
                        preview:SetTexture(path)
                    end
                    preview:SetVertexColor(1, 1, 1, 0.4)
                end)
            end
        end
    end)
end

do
    local function HideAndOrphan(...)
        for i = 1, select("#", ...) do
            local child = select(i, ...)
            child:Hide()
            child:SetParent(nil)
        end
    end
    function UI.ClearChildren(frame)
        HideAndOrphan(frame:GetChildren())
    end
end

function UI.CreateScrollableEditBox(parent, width, height, editWidth)
    local boxFrame = CreateFrame("Frame", nil, parent)
    boxFrame:SetSize(width, height)

    local scrollFrame = CreateFrame("ScrollFrame", nil, boxFrame, "UIPanelScrollFrameTemplate")
    UI.StyleScrollBar(scrollFrame)
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 8)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("CDM_Font14")
    editBox:SetWidth(editWidth or (width - 40))
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)
    StyleEditBox(editBox, boxFrame)

    local function FocusEditBox()
        editBox:SetFocus()
    end
    boxFrame:EnableMouse(true)
    boxFrame:SetScript("OnMouseDown", FocusEditBox)
    scrollFrame:SetScript("OnMouseDown", FocusEditBox)

    return boxFrame, editBox
end

function UI.SetupModuleToggle(parent, enableCheckbox)
    local overlayLevel = parent:GetFrameLevel() + 100
    local overlay = CreateFrame("Frame", nil, parent)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(overlayLevel)
    overlay:EnableMouse(true)
    overlay:Hide()

    enableCheckbox:SetFrameLevel(overlayLevel + 10)

    local function SetEnabled(en)
        local alpha = 0.35
        if en then
            alpha = 1
        end

        for _, child in ipairs({ parent:GetChildren() }) do
            if child ~= enableCheckbox and child ~= overlay then
                child:SetAlpha(alpha)
            end
        end
        for _, region in ipairs({ parent:GetRegions() }) do
            region:SetAlpha(alpha)
        end
        overlay:SetShown(not en)
    end

    return SetEnabled
end

function UI.CreateModalOverlay()
    local overlay = CreateFrame("Frame", nil, ns.ConfigFrame, "BackdropTemplate")
    overlay:SetPoint("TOPLEFT", ns.ConfigFrame, "TOPLEFT", 19, -66)
    overlay:SetPoint("BOTTOMRIGHT", ns.ConfigFrame, "BOTTOMRIGHT", -19, 41)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetFrameLevel(ns.ConfigFrame:GetFrameLevel() + 50)
    overlay:EnableMouse(true)
    overlay:Hide()

    local overlayBg = overlay:CreateTexture(nil, "BACKGROUND")
    overlayBg:SetAllPoints()
    overlayBg:SetColorTexture(0, 0, 0, 0.4)

    local window = UI.CreateConfigWindow(overlay)
    window:EnableMouse(true)
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(overlay:GetFrameLevel() + 5)
    window:SetPoint("CENTER", ns.ConfigFrame, "CENTER")
    window:SetScript("OnMouseDown", function() end)

    local closeButton = window.CloseButton
    if closeButton then
        closeButton:HookScript("OnClick", function() overlay:Hide() end)
    end

    overlay:SetScript("OnMouseDown", function() overlay:Hide() end)
    overlay:SetScript("OnShow", function() window:Show() end)
    window:HookScript("OnHide", function() overlay:Hide() end)

    overlay.window = window
    return overlay
end

-- Shared "Custom Icon" chooser. One text field plus a Spell, an Item and an
-- Icon button: the button the user presses declares how the typed ID should be
-- read, so the same number can mean a spell, an item, or a raw FileDataID.
-- Confirms with { kind = "spell"|"item"|"texture", id = <number> }, or nil when
-- cleared.
local customIconPopup

function UI.ShowCustomIconPopup(current, onConfirm)
    if not customIconPopup then
        local overlay = UI.CreateModalOverlay()
        local window = overlay.window
        window:SetSize(376, 210)

        local title = window:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        title:SetText(L["Custom Icon"])
        title:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -44)
        title:SetTextColor(GOLD.r, GOLD.g, GOLD.b, 1)

        local hint = window:CreateFontString(nil, "ARTWORK", "CDM_Font12")
        hint:SetText(L["Enter a spell ID, item ID or icon FileDataID, then choose which it is."])
        hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        hint:SetWidth(300)
        hint:SetJustifyH("LEFT")
        UI.SetTextFaint(hint)

        local editBox = UI.CreateEditBox(window)
        editBox:SetSize(120, 22)
        editBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -14)
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(10)

        local preview = window:CreateTexture(nil, "ARTWORK")
        preview:SetSize(28, 28)
        preview:SetPoint("LEFT", editBox, "RIGHT", 14, 0)
        preview:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local status = window:CreateFontString(nil, "ARTWORK", "CDM_Font12")
        status:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -10)
        status:SetWidth(300)
        status:SetJustifyH("LEFT")

        local spellBtn = UI.CreateTextButton(window)
        spellBtn:SetSize(80, 22)
        spellBtn:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 18, 18)
        spellBtn:SetText(L["Spell"])

        local itemBtn = UI.CreateTextButton(window)
        itemBtn:SetSize(80, 22)
        itemBtn:SetPoint("LEFT", spellBtn, "RIGHT", 8, 0)
        itemBtn:SetText(L["Item"])

        local textureBtn = UI.CreateTextButton(window)
        textureBtn:SetSize(80, 22)
        textureBtn:SetPoint("LEFT", itemBtn, "RIGHT", 8, 0)
        textureBtn:SetText(L["Icon ID"])

        local clearBtn = UI.CreateTextButton(window)
        clearBtn:SetSize(80, 22)
        clearBtn:SetPoint("LEFT", textureBtn, "RIGHT", 8, 0)
        clearBtn:SetText(L["Clear"])

        -- A FileDataID has no lookup that can confirm it exists, so unlike the
        -- spell and item cases this returns the ID itself and validity is judged
        -- by whether the texture object accepts it (see Commit).
        local function ResolveTexture(kind, id)
            if kind == "item" then
                local tex = C_Item.GetItemIconByID(id)
                if not tex then C_Item.RequestLoadItemDataByID(id) end
                return tex
            elseif kind == "texture" then
                return id
            end
            return C_Spell.GetSpellTexture(id)
        end

        local function Commit(kind)
            local id = tonumber(editBox:GetText())
            if not id or id <= 0 then
                status:SetText(L["Enter a valid ID"])
                UI.SetTextError(status)
                return
            end
            local tex = ResolveTexture(kind, id)
            if tex then
                -- SetTexture silently no-ops on a FileDataID that resolves to
                -- nothing, leaving the previous texture in place; clearing first
                -- makes GetTexture a truthful check on whether it took.
                preview:SetTexture(nil)
                preview:SetTexture(tex)
            end
            if not tex or not preview:GetTexture() then
                preview:SetTexture(nil)
                status:SetText(kind == "item" and L["No icon found for that item ID"]
                    or kind == "texture" and L["No icon found for that icon ID"]
                    or L["No icon found for that spell ID"])
                UI.SetTextError(status)
                return
            end
            if customIconPopup.onConfirm then
                customIconPopup.onConfirm({ kind = kind, id = id })
            end
            overlay:Hide()
        end

        spellBtn:SetScript("OnClick", function() Commit("spell") end)
        itemBtn:SetScript("OnClick", function() Commit("item") end)
        textureBtn:SetScript("OnClick", function() Commit("texture") end)
        clearBtn:SetScript("OnClick", function()
            if customIconPopup.onConfirm then customIconPopup.onConfirm(nil) end
            overlay:Hide()
        end)

        editBox:SetScript("OnEscapePressed", function() overlay:Hide() end)

        customIconPopup = overlay
        customIconPopup.editBox = editBox
        customIconPopup.status = status
        customIconPopup.preview = preview
        customIconPopup.clearBtn = clearBtn
        customIconPopup.ResolveTexture = ResolveTexture
    end

    local p = customIconPopup
    p.onConfirm = onConfirm
    p.status:SetText("")

    local hasCurrent = type(current) == "table" and tonumber(current.id)
    p.editBox:SetText(hasCurrent and tostring(current.id) or "")
    p.preview:SetTexture(hasCurrent and p.ResolveTexture(current.kind, current.id) or nil)
    p.clearBtn:SetEnabled(hasCurrent and true or false)

    p:Show()
    p.editBox:SetFocus()
end

function UI.CreateTimedStatus(fontString, duration)
    local timer
    duration = duration or 2
    return function(text)
        fontString:SetText(text)
        if timer then timer:Cancel() end
        if text ~= "" then
            timer = C_Timer.NewTimer(duration, function() fontString:SetText("") end)
        end
    end
end

function UI.AttachPlaceholder(editBox, text)
    local ph = editBox:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    ph:SetPoint("LEFT", editBox, "LEFT", 2, 0)
    ph:SetText(text)
    ph:SetTextColor(0.5, 0.5, 0.5, 0.7)
    editBox:HookScript("OnTextChanged", function(self)
        ph:SetShown(self:GetText() == "")
    end)
    return ph
end

function UI.GetOptionLabel(options, value, default)
    for _, opt in ipairs(options) do
        if opt.value == value then return opt.label end
    end
    return default or value
end

function UI.CreateSubTabBar(parent, tabs, initialTab, fixedTabWidth)
    local TAB_HEIGHT = 37
    local barFrame = CreateFrame("Frame", nil, parent)
    barFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 30, -2)
    barFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -2)
    barFrame:SetHeight(TAB_HEIGHT)

    local subPages = {}
    local tabButtons = {}
    local selectedTab = nil

    local function UpdateTabStyle(button, active)
        button.selected = active
        button.Underline:SetShown(active)
        if active then
            button.Background:SetColorTexture(1, 1, 1, 0.045)
            button.label:SetTextColor(1, 1, 1, 1)
        else
            button.Background:SetColorTexture(1, 1, 1, 0)
            button.label:SetTextColor(0.65, 0.65, 0.65, 1)
        end
    end

    local function SelectTab(id)
        if selectedTab == id then return end
        UI.CloseAllDropdownMenus()
        selectedTab = id
        for _, info in ipairs(tabs) do
            local btn = tabButtons[info.id]
            local pg = subPages[info.id]
            UpdateTabStyle(btn, info.id == id)
            if info.id == id then
                pg:Show()
            else
                pg:Hide()
            end
        end
    end

    local prevBtn
    for _, info in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, barFrame)
        btn:SetHeight(TAB_HEIGHT - 4)

        btn.Background = btn:CreateTexture(nil, "BACKGROUND")
        btn.Background:SetAllPoints()
        btn.Underline = btn:CreateTexture(nil, "ARTWORK")
        btn.Underline:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 0.8)
        btn.Underline:SetHeight(2)
        btn.Underline:SetPoint("BOTTOMLEFT", 8, 0)
        btn.Underline:SetPoint("BOTTOMRIGHT", -8, 0)

        local label = btn:CreateFontString(nil, "OVERLAY", "CDM_Font12")
        label:SetPoint("CENTER", 0, 1)
        label:SetText(info.label)
        btn.label = label

        local textWidth = label:GetStringWidth()
        btn:SetWidth(fixedTabWidth or math.max(textWidth + 28, 80))

        if prevBtn then
            btn:SetPoint("BOTTOMLEFT", prevBtn, "BOTTOMRIGHT", 4, 0)
        else
            btn:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
        end
        prevBtn = btn

        btn:SetScript("OnClick", function() SelectTab(info.id) end)
        btn:SetScript("OnEnter", function(self)
            if not self.selected then
                self.Background:SetColorTexture(1, 1, 1, 0.025)
                self.label:SetTextColor(0.9, 0.9, 0.9, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self) UpdateTabStyle(self, self.selected) end)
        tabButtons[info.id] = btn

        local pg = CreateFrame("Frame", nil, parent)
        pg:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", -30, 0)
        pg:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
        pg:Hide()
        pg.controls = {}
        subPages[info.id] = pg
    end

    SelectTab(initialTab or tabs[1].id)

    return {
        selectTab = SelectTab,
        subPages = subPages,
        barFrame = barFrame,
        tabButtons = tabButtons,
    }
end
