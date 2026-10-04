local addonName, ns = ...
local API = _G.CDM_API
local AceGUI = LibStub("AceGUI-3.0")
local Skin = {}
ns.OptionsSkin = Skin
local Create
local prefix = "CDM_Options_"
local accent = { 1, 0.82, 0.05, 1 }
local background = { 0.035, 0.04, 0.05, 0.92 }
local panelBackground = { 20 / 255, 20 / 255, 20 / 255, 1 }
local fieldBackground = { 0.04, 0.04, 0.04, 1 }
local buttonBackground = { 0.04, 0.04, 0.04, 1 }
local border = { 0.3, 0.31, 0.34, 1 }
local state = setmetatable({}, { __mode = "k" })
local ownedTextures = setmetatable({}, { __mode = "k" })
local fonts = {}

local function Font(role)
    if fonts[role] then return fonts[role] end
    local source = role == "small" and GameFontHighlightSmall or GameFontNormal
    local path, size, flags = source:GetFont()
    local font = CreateFont(prefix .. role .. "Font")
    font:SetFont(path, size, flags)
    font:SetTextColor(1, 1, 1, 1)
    font:SetShadowColor(0, 0, 0, 1)
    font:SetShadowOffset(1, -1)
    fonts[role] = font
    return font
end

local function State(object)
    local data = state[object]
    if not data then data = {}; state[object] = data end
    return data
end

local function Texture(host, layer)
    local texture = host:CreateTexture(nil, layer or "BACKGROUND")
    ownedTextures[texture] = true
    return texture
end

local function StripArt(host, keep)
    if host.SetBackdrop then host:SetBackdrop(nil) end
    -- A previously installed external skin can have put art on a child frame.
    -- Hide that old surface; our fill and border are regions of the host itself.
    if host.NUIBackdrop then host.NUIBackdrop:Hide() end
    if host.NineSlice then
        for _, region in ipairs({ host.NineSlice:GetRegions() }) do
            if region:IsObjectType("Texture") then region:SetAlpha(0) end
        end
    end
    for _, region in ipairs({ host:GetRegions() }) do
        if region:IsObjectType("Texture") and region ~= keep and not ownedTextures[region] then
            region:SetAlpha(0)
        end
    end
end

local function StripChildArt(host)
    for _, child in ipairs({ host:GetChildren() }) do
        StripArt(child)
        StripChildArt(child)
    end
end

local function ChildLevels(host)
    for _, child in ipairs({ host:GetChildren() }) do
        child:SetFrameLevel(host:GetFrameLevel() + 1)
        ChildLevels(child)
    end
end

local function Surface(host, fill, insetLeft, insetTop, insetRight, insetBottom)
    local data = State(host)
    if not data.fill then
        data.fill = Texture(host)
        data.edges = {}
        for index = 1, 4 do data.edges[index] = Texture(host, "BORDER") end
    end
    local left, top, right, bottom = insetLeft or 0, insetTop or 0, insetRight or 0, insetBottom or 0
    local texture = data.fill
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", host, "TOPLEFT", left, -top)
    texture:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -right, bottom)
    texture:SetColorTexture(unpack(fill))
    local edges = data.edges
    for _, edge in ipairs(edges) do edge:ClearAllPoints(); edge:SetColorTexture(unpack(border)) end
    edges[1]:SetPoint("TOPLEFT", texture); edges[1]:SetPoint("TOPRIGHT", texture); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT", texture); edges[2]:SetPoint("BOTTOMRIGHT", texture); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT", texture); edges[3]:SetPoint("BOTTOMLEFT", texture); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT", texture); edges[4]:SetPoint("BOTTOMRIGHT", texture); edges[4]:SetWidth(1)
    return data
end

local function Tint(label, disabled, useAccent)
    if not label then return end
    if disabled then label:SetTextColor(0.62, 0.64, 0.68, 1)
    elseif useAccent then label:SetTextColor(unpack(accent))
    else label:SetTextColor(1, 1, 1, 1) end
end

-- External skins may retain label references in color-update callbacks. Give
-- our private widget fresh labels so those callbacks cannot recolor CDM text.
local function Label(widget, key, parent, role)
    local data = State(widget)
    data.labels = data.labels or {}
    local label = data.labels[key]
    if not label then
        local original = widget[key]
        if not original then return nil end
        label = parent:CreateFontString(nil, "OVERLAY")
        -- WoW requires a font before SetText, including empty copied text.
        label:SetFontObject(Font(role or "normal"))
        local value = original:GetText()
        if (not issecretvalue or not issecretvalue(value)) and (not canaccessvalue or canaccessvalue(value)) then
            label:SetText(value or "")
        end
        for index = 1, original:GetNumPoints() do label:SetPoint(original:GetPoint(index)) end
        label:SetJustifyH(original:GetJustifyH())
        local height = original:GetHeight()
        if height and height > 0 then label:SetHeight(height) end
        original:Hide()
        data.labels[key] = label
        widget[key] = label
    end
    label:SetFontObject(Font(role or "normal"))
    return label
end

local function ReplaceTexture(widget, key)
    local data = State(widget)
    data.textures = data.textures or {}
    if data.textures[key] then return data.textures[key] end
    local original = widget[key]
    local texture = Texture(widget.frame, original:GetDrawLayer())
    for index = 1, original:GetNumPoints() do texture:SetPoint(original:GetPoint(index)) end
    texture:SetSize(original:GetWidth(), original:GetHeight())
    if not original:IsShown() then texture:Hide() end
    original:SetAlpha(0)
    data.textures[key], widget[key] = texture, texture
    return texture
end

local function Button(control, symbol)
    StripArt(control)
    local data = Surface(control, buttonBackground)
    if not data.highlight then
        data.highlight = Texture(control, "HIGHLIGHT")
        data.highlight:SetAllPoints(data.fill)
        data.highlight:SetColorTexture(accent[1], accent[2], accent[3], 0.2)
        control:SetHighlightTexture(data.highlight)
    end
    if symbol then
        if not data.glyph then
            for _, region in ipairs({ control:GetRegions() }) do
                if region:IsObjectType("FontString") then region:Hide() end
            end
            data.glyph = control:CreateFontString(nil, "OVERLAY")
            data.glyph:SetPoint("CENTER")
        end
        data.glyph:SetFontObject(Font("normal"))
        data.glyph:SetText(symbol)
    else
        if not data.text then
            local original = control:GetFontString()
            data.text = control:CreateFontString(nil, "OVERLAY")
            data.text:SetFontObject(Font("small"))
            data.text:SetPoint("TOPLEFT", 8, -1)
            data.text:SetPoint("BOTTOMRIGHT", -8, 1)
            data.text:SetJustifyH("CENTER")
            data.text:SetJustifyV("MIDDLE")
            if original then data.text:SetText(original:GetText() or ""); original:Hide() end
            control:SetFontString(data.text)
        end
        data.text:SetFontObject(Font("small"))
        control:SetNormalFontObject(Font("small"))
        control:SetHighlightFontObject(Font("small"))
        control:SetDisabledFontObject(Font("small"))
        Tint(data.text, not control:IsEnabled())
    end
end

local function Arrow(control, up)
    if not control then return end
    StripArt(control)
    local data = Surface(control, fieldBackground)
    if not data.arrow then
        data.arrow = { Texture(control, "OVERLAY"), Texture(control, "OVERLAY") }
        for _, region in ipairs({ control:GetRegions() }) do
            if region:IsObjectType("FontString") then region:Hide() end
        end
        data.highlight = Texture(control, "HIGHLIGHT")
        data.highlight:SetAllPoints(data.fill)
        data.highlight:SetColorTexture(accent[1], accent[2], accent[3], 0.2)
        control:SetHighlightTexture(data.highlight)
    end
    for index, texture in ipairs(data.arrow) do
        texture:SetColorTexture(1, 1, 1, 1)
        texture:SetSize(7, 2)
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", control, "CENTER", index == 1 and -2 or 2, 0)
        texture:SetRotation((index == 1 and -1 or 1) * (up and -1 or 1) * math.pi / 4)
    end
end

local function Input(control)
    StripArt(control)
    Surface(control, fieldBackground)
    control:SetFontObject(Font("small"))
end

local function Slider(control, vertical, disabled)
    if not control then return end
    local thumb = control:GetThumbTexture()
    StripArt(control, thumb)
    -- An external scrollbar skin can draw a grip on a child of the slider.
    StripChildArt(control)
    if vertical then
        Surface(control, fieldBackground)
    else
        -- Keep a generous click target while drawing only a six-pixel track.
        control:SetHeight(18)
        control:SetHitRectInsets(0, 0, 0, 0)
        local data = Surface(control, fieldBackground, 0, 6, 0, 6)
        for _, edge in ipairs(data.edges) do edge:SetColorTexture(0.2, 0.2, 0.2, 1) end
        if thumb then
            if not data.progress then
                data.progress = Texture(control, "ARTWORK")
                data.progress:SetPoint("LEFT", data.fill, "LEFT")
                -- Native slider movement also moves this edge: no polling or
                -- replacement of AceGUI's value-change scripts is needed.
                data.progress:SetPoint("RIGHT", thumb, "CENTER")
                data.progress:SetHeight(4)
                data.thumbBorder = Texture(control, "OVERLAY")
                data.thumbBorder:SetDrawLayer("OVERLAY", -1)
                data.thumbBorder:SetPoint("TOPLEFT", thumb, "TOPLEFT", -1, 1)
                data.thumbBorder:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 1, -1)
                data.thumbBorder:SetColorTexture(0, 0, 0, 1)
            end
            if disabled then data.progress:SetColorTexture(0.35, 0.35, 0.35, 1)
            else data.progress:SetColorTexture(unpack(accent)) end
        end
    end
    if thumb then
        ownedTextures[thumb] = true
        thumb:SetAlpha(1)
        if vertical then
            thumb:SetColorTexture(0.55, 0.57, 0.6, 1)
            thumb:SetSize(8, 22)
        else
            thumb:SetDrawLayer("OVERLAY")
            local shade = disabled and 0.5 or 0.9
            thumb:SetColorTexture(shade, shade, shade, 1)
            thumb:SetSize(8, 12)
        end
    end
end

local function Scrollbar(control)
    if not control then return end
    Slider(control, true)
    local name = control:GetName()
    Arrow(control.ScrollUpButton or (name and _G[name .. "ScrollUpButton"]), true)
    Arrow(control.ScrollDownButton or (name and _G[name .. "ScrollDownButton"]), false)
end

local function LogoHeader(widget)
    local data = State(widget)
    if not data.logo then
        data.logo = Texture(widget.frame, "OVERLAY")
        data.logo:SetTexture("Interface\\AddOns\\CDM\\Media\\Textures\\cdmlogo.tga")
        -- The supplied 128x128 logo has transparent padding above and below.
        data.logo:SetTexCoord(0, 1, 40 / 128, 96 / 128)
        data.logo:SetSize(96, 42)
        data.logo:SetPoint("TOP", widget.frame, "TOP", 0, -6)
    end
    widget.titletext:Hide()
    -- Preserve the stock title's drag target over the visible logo.
    widget.titlebg:ClearAllPoints()
    widget.titlebg:SetPoint("TOP", widget.frame, "TOP", 0, -6)
    widget.titlebg:SetSize(96, 42)
    widget.content:SetPoint("TOPLEFT", widget.frame, "TOPLEFT", 17, -56)
    local height = math.max(0, widget.frame:GetHeight() - 96)
    widget.content:SetHeight(height)
    widget.content.height = height
end

local function Window(widget)
    StripArt(widget.frame)
    Surface(widget.frame, background)
    local title = Label(widget, "titletext", widget.frame)
    title:ClearAllPoints()
    title:SetPoint("TOP", widget.frame, "TOP", 0, -4)
    Tint(title, false, true)
    local status = Label(widget, "statustext", widget.frame, "small")
    if status then
        status:ClearAllPoints()
        status:SetPoint("BOTTOMLEFT", widget.frame, "BOTTOMLEFT", 22, 17)
        status:SetPoint("BOTTOMRIGHT", widget.frame, "BOTTOMRIGHT", -140, 17)
        Tint(status, false, true)
    end
    if widget.closebutton then Button(widget.closebutton, API.GetText("X")) end
    for _, key in ipairs({ "sizer_se", "sizer_s", "sizer_e" }) do
        if widget[key] then StripArt(widget[key]) end
    end
    for _, child in ipairs({ widget.frame:GetChildren() }) do
        if child:IsObjectType("Button") then
            if child ~= widget.closebutton and child:GetText() then Button(child)
            elseif child ~= widget.closebutton then StripArt(child) end
        end
    end
    if widget.type == prefix .. "Frame" then LogoHeader(widget) end
end

local function Dropdown(widget, centered)
    StripArt(widget.dropdown)
    local data = Surface(widget.dropdown, fieldBackground, 15, 2, 21, 0)
    widget.button:SetParent(widget.dropdown)
    Arrow(widget.button)
    widget.button:ClearAllPoints()
    widget.button:SetPoint("TOPRIGHT", data.fill, "TOPRIGHT", -2, -2)
    widget.button:SetPoint("BOTTOMRIGHT", data.fill, "BOTTOMRIGHT", -2, 2)
    widget.button:SetWidth(20)
    -- A region on the outer frame is drawn under the dropdown child surface.
    local text = Label(widget, "text", widget.dropdown, "small")
    text:ClearAllPoints()
    text:SetPoint("LEFT", data.fill, "LEFT", centered and 24 or 4, 0)
    text:SetPoint("RIGHT", data.fill, "RIGHT", -24, 0)
    text:SetJustifyH(centered and "CENTER" or "RIGHT")
    Tint(text, widget.disabled)
    local label = Label(widget, "label", widget.frame, "small")
    label:ClearAllPoints()
    label:SetPoint("BOTTOMLEFT", data.fill, "TOPLEFT", 0, 2)
    label:SetPoint("BOTTOMRIGHT", data.fill, "TOPRIGHT", 0, 2)
    label:SetJustifyH(centered and "CENTER" or "LEFT")
    Tint(label, widget.disabled, true)
end

local function Tab(tab)
    StripArt(tab)
    local data = Surface(tab, fieldBackground, 10, 3, 10, 0)
    if tab.selected then
        data.fill:SetColorTexture(accent[1], accent[2], accent[3], 0.2)
        for _, edge in ipairs(data.edges) do edge:SetColorTexture(unpack(accent)) end
    end
    local text = tab.Text or tab:GetFontString()
    text:SetParent(tab)
    text:SetFontObject(Font("small"))
    tab:SetNormalFontObject(Font("small"))
    tab:SetHighlightFontObject(Font("small"))
    tab:SetDisabledFontObject(Font("small"))
    text:ClearAllPoints()
    text:SetPoint("LEFT", tab, "LEFT", 10, 0)
    text:SetPoint("RIGHT", tab, "RIGHT", -10, 0)
    Tint(text, tab.disabled, not tab.selected)
    if not data.highlight then
        data.highlight = Texture(tab, "HIGHLIGHT")
        data.highlight:SetAllPoints(data.fill)
        data.highlight:SetColorTexture(accent[1], accent[2], accent[3], 0.15)
        tab:SetHighlightTexture(data.highlight)
    end
end

local styles = {}
styles.Frame, styles.Window, styles.CDMGroupPopup = Window, Window, Window
styles.Dropdown = function(widget) Dropdown(widget, false) end
styles.CDMCenteredDropdown = function(widget) Dropdown(widget, true) end
styles.Button = function(widget)
    Button(widget.frame)
    widget.text = State(widget.frame).text
    Tint(widget.text, widget.disabled)
end
styles.EditBox = function(widget)
    Input(widget.editbox)
    Button(widget.button)
    local label = Label(widget, "label", widget.frame, "small")
    label:ClearAllPoints()
    label:SetPoint("BOTTOMLEFT", widget.editbox, "TOPLEFT", 0, 2)
    label:SetPoint("BOTTOMRIGHT", widget.editbox, "TOPRIGHT", 0, 2)
    Tint(label, widget.disabled, true)
end
styles.Slider = function(widget)
    Slider(widget.slider, false, widget.disabled)
    Input(widget.editbox)
    widget.editbox:ClearAllPoints()
    widget.editbox:SetPoint("TOPRIGHT", widget.frame, "TOPRIGHT", -3, 0)
    widget.editbox:SetSize(56, 18)
    Tint(widget.editbox, widget.disabled, true)
    local label = Label(widget, "label", widget.frame)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", widget.frame, "TOPLEFT", 3, -2)
    label:SetPoint("TOPRIGHT", widget.editbox, "TOPLEFT", -8, -2)
    label:SetHeight(15)
    label:SetJustifyH("LEFT")
    Tint(label, widget.disabled, true)
    widget.slider:ClearAllPoints()
    widget.slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    widget.slider:SetPoint("TOPRIGHT", widget.frame, "TOPRIGHT", -3, -21)
    for _, key in ipairs({ "lowtext", "hightext" }) do
        local text = Label(widget, key, widget.slider, "small")
        text:ClearAllPoints()
        local side = key == "lowtext" and "LEFT" or "RIGHT"
        text:SetPoint("TOP" .. side, widget.slider, "BOTTOM" .. side, 0, -1)
        text:SetJustifyH(side)
        text:SetHeight(12)
        Tint(text, true)
    end
    widget:SetHeight(54)
end
styles.Heading = function(widget)
    local label = Label(widget, "label", widget.frame)
    label:ClearAllPoints(); label:SetPoint("TOP"); label:SetPoint("BOTTOM")
    Tint(label, false, true)
    for _, key in ipairs({ "left", "right" }) do
        local texture = ReplaceTexture(widget, key)
        texture:SetHeight(1); texture:SetColorTexture(unpack(border)); texture:SetTexCoord(0, 1, 0, 1)
    end
    widget.left:SetPoint("RIGHT", label, "LEFT", -5, 0)
    widget.right:SetPoint("LEFT", label, "RIGHT", 5, 0)
end
styles.Label = function(widget)
    local label = Label(widget, "label", widget.frame, "small")
    Tint(label)
end
styles.ColorPicker = function(widget)
    local swatch = widget.colorSwatch
    swatch:SetParent(widget.frame)
    swatch:SetDrawLayer("OVERLAY")
    swatch:ClearAllPoints(); swatch:SetPoint("LEFT", widget.frame, "LEFT", 2, 0)
    swatch:SetSize(20, 14); swatch:SetColorTexture(1, 1, 1, 1)
    swatch.background:SetParent(widget.frame)
    swatch.background:SetColorTexture(unpack(border))
    swatch.background:ClearAllPoints(); swatch.background:SetPoint("TOPLEFT", swatch, -1, 1)
    swatch.background:SetPoint("BOTTOMRIGHT", swatch, 1, -1)
    swatch.checkers:SetParent(widget.frame); swatch.checkers:SetAllPoints(swatch)
    local text = Label(widget, "text", widget.frame, "small")
    text:ClearAllPoints(); text:SetPoint("LEFT", swatch, "RIGHT", 4, 0); text:SetPoint("RIGHT")
    Tint(text, widget.disabled)
end
styles.ScrollFrame = function(widget) Scrollbar(widget.scrollbar) end
styles.TabGroup = function(widget)
    StripArt(widget.border)
    Surface(widget.border, panelBackground)
    Tint(Label(widget, "titletext", widget.frame), false, true)
    for _, tab in ipairs(widget.tabs) do Tab(tab) end
end
styles["Dropdown-Pullout"] = function(widget)
    StripArt(widget.frame)
    Surface(widget.frame, background)
    Slider(widget.slider, true)
end
styles["Dropdown-Item-Toggle"] = function(widget)
    local text = Label(widget, "text", widget.frame, "small")
    Tint(text, widget.disabled)
    local highlight = ReplaceTexture(widget, "highlight")
    highlight:SetColorTexture(accent[1], accent[2], accent[3], 0.2)
    highlight:SetBlendMode("BLEND")
end

local function After(widget, method, callback)
    local original = widget[method]
    if not original then return end
    widget[method] = function(self, ...)
        local result = original(self, ...)
        callback(self, ...)
        return result
    end
end

local function Register(baseType)
    local ownType = prefix .. baseType
    if AceGUI:GetWidgetVersion(ownType) then return ownType end
    local constructor = assert(AceGUI.WidgetRegistry[baseType], "Missing AceGUI widget: " .. baseType)
    AceGUI:RegisterWidgetType(ownType, function()
        local widget = constructor()
        widget.type = ownType
        local style = styles[baseType]
        if style then
            After(widget, "OnAcquire", style)
            After(widget, "SetDisabled", style)
            After(widget, "SetLabel", style)
        end
        if baseType == "TabGroup" then
            After(widget, "BuildTabs", style)
            After(widget, "SelectTab", style)
        end
        if baseType == "Dropdown" or baseType == "CDMCenteredDropdown" then
            local itemType = Register("Dropdown-Item-Toggle")
            local setList = widget.SetList
            widget.SetList = function(self, list, order) return setList(self, list, order, itemType) end
            -- The base acquisition creates a shared pullout. Replace it with
            -- one from CDM's private pool and preserve AceGUI's own callbacks.
            After(widget, "OnAcquire", function(self)
                local shared = self.pullout
                local pullout = Create("Dropdown-Pullout")
                pullout.userdata.obj = self
                for event, callback in pairs(shared.events) do pullout:SetCallback(event, callback) end
                pullout.frame:SetFrameLevel(self.frame:GetFrameLevel() + 1)
                ChildLevels(pullout.frame)
                self.pullout = pullout
                AceGUI:Release(shared)
            end)
        end
        if baseType == "Frame" or baseType == "Window" or baseType == "CDMGroupPopup" then
            After(widget, "SetTitle", Window)
            After(widget, "SetStatusText", Window)
        end
        if baseType == "Frame" then After(widget, "OnHeightSet", LogoHeader) end
        return widget
    end, 1)
    return ownType
end

Create = function(baseType)
    if baseType == "CDMSpellOrder" then return AceGUI:Create(baseType) end
    return AceGUI:Create(Register(baseType))
end
Skin.Create = Create
