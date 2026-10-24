local Runtime = _G["CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L

local OUTLINE_OPTIONS = {
    { value = "",             label = L["None"] },
    { value = "OUTLINE",      label = L["Outline"] },
    { value = "THICKOUTLINE", label = L["Thick Outline"] },
    { value = "SLUG",         label = L["Slug"] },
}

local function OutlineLabel(value)
    return UI.GetOptionLabel(OUTLINE_OPTIONS, value, L["Outline"])
end

local function FontDropdown(rc, yOff, page)
    local lbl = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    lbl:SetText(L["Font"])
    lbl:SetPoint("TOPLEFT", 0, yOff)

    local dd = UI.CreateDropdown(rc)
    dd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
    dd:SetWidth(220)
    dd:SetDefaultText(CDM.db.textFont or CDM.defaults.textFont or "Expressway")
    UI.SetupMediaDropdown(dd, "font",
        function() return CDM.db.textFont end,
        function(name) CDM.db.textFont = name; API:Refresh("STYLE") end,
        function(name) dd:SetDefaultText(name) end)
    page.fontDropdown = dd
end

local function OutlineDropdown(rc, yOff, page)
    local lbl = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    lbl:SetText(L["Font Outline"])
    lbl:SetPoint("TOPLEFT", 0, yOff)

    local dd = UI.CreateDropdown(rc)
    dd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
    dd:SetWidth(220)
    dd:SetDefaultText(OutlineLabel(CDM.db.textFontOutline))
    UI.SetupValueDropdown(dd, OUTLINE_OPTIONS,
        function() return CDM.db.textFontOutline end,
        function(value, label)
            CDM.db.textFontOutline = value
            dd:SetDefaultText(label)
            API:Refresh("STYLE")
        end)
    page.outlineDropdown = dd
end

local stylingExpanded = { font = true }

local function BuildBorders(subPage, page)
    local content, scrollFrame = UI.CreateScrollableTab(subPage, "CDM_StylingScrollFrame", 520)
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
            local expanded = stylingExpanded[key] == true
            body:SetShown(expanded)
            arrow:SetRotation(expanded and 0 or math.pi / 2)
            section:SetHeight(expanded and (30 + contentHeight) or 24)
            UpdateScrollHeight()
        end
        header:SetScript("OnClick", function()
            stylingExpanded[key] = not stylingExpanded[key]
            UI.CloseAllDropdownMenus()
            UpdateSection()
        end)
        sections[#sections + 1] = section
        UpdateSection()
        return body
    end

    local font = CollapsibleSection("font", L["Global Font"], 120)
    FontDropdown(font, 0, page)
    OutlineDropdown(font, -55, page)

    local rc = CollapsibleSection("border", L["Border Settings"], 290)
    local yOff = 0

    local lblDropdown = rc:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    lblDropdown:SetText(L["Border Texture"])
    lblDropdown:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 25

    local ddBorder = UI.CreateDropdown(rc)
    ddBorder:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 40
    ddBorder:SetWidth(220)
    ddBorder:SetDefaultText(CDM.db.borderFile or L["Select Border..."])
    page.dropdown = ddBorder

    UI.SetupMediaDropdown(
        ddBorder,
        "border",
        function() return CDM.db.borderFile end,
        function(name)
            CDM.db.borderFile = name
            API:Refresh("STYLE")
        end,
        function(name)
            ddBorder:SetDefaultText(name)
        end
    )

    local colorPicker = UI.CreateColorSwatch(rc, L["Border Color"], "borderColor", "STYLE")
    colorPicker:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 45
    page.colorPicker = colorPicker

    page.controls.b0 = UI.CreateModernSlider(rc, L["Border Size"], 1, 50, CDM.db.borderSize, function(v) CDM.db.borderSize = v; API:Refresh("STYLE") end)
    page.controls.b0:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 60

    page.controls.b1 = UI.CreateModernSlider(rc, L["Border Offset X"], -50, 50, CDM.db.borderOffsetX, function(v) CDM.db.borderOffsetX = v; API:Refresh("STYLE") end)
    page.controls.b1:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 60

    page.controls.b2 = UI.CreateModernSlider(rc, L["Border Offset Y"], -50, 50, CDM.db.borderOffsetY, function(v) CDM.db.borderOffsetY = v; API:Refresh("STYLE") end)
    page.controls.b2:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 60

    local pressOverlay = CollapsibleSection("pressOverlay", L["Press Overlay"], 110)
    local keybindings = CollapsibleSection("keybindings", L["Keybindings"], 350)
    ns._CreateAssistPanel(pressOverlay, keybindings, page)
    subPage:HookScript("OnShow", UpdateScrollHeight)
end

local function CreateBorderTab(page)
    BuildBorders(page, page)
end

API:RegisterConfigTab("border", L["Styling"], CreateBorderTab, 4)
