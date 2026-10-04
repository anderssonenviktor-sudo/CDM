local addonName, ns = ...
local API = _G.CDM_API
local AceGUI = LibStub("AceGUI-3.0")

-- Construct distinct widget types so appearance changes never reach the
-- shared pools for standard AceGUI dropdowns or windows.
local function CenteredDropdown()
    local widget = AceGUI.WidgetRegistry.Dropdown()
    widget.type = "CDMCenteredDropdown"
    widget.label:SetJustifyH("CENTER")
    widget.text:SetJustifyH("CENTER")
    widget.text:ClearAllPoints()
    widget.text:SetPoint("LEFT", widget.frame, "BOTTOMLEFT", 24, 13)
    widget.text:SetPoint("RIGHT", widget.frame, "BOTTOMRIGHT", -24, 13)
    return widget
end

local function PopupLayers(control, strata, level)
    control:SetFrameStrata(strata)
    control:SetFrameLevel(level)
    for _, child in ipairs({ control:GetChildren() }) do
        PopupLayers(child, strata, level + 1)
    end
end

local function GroupPopup()
    local widget = AceGUI.WidgetRegistry.Window()
    widget.type = "CDMGroupPopup"
    local acquire = widget.OnAcquire
    function widget:OnAcquire()
        acquire(self)
        self:SetTitle(API.GetText("New group"))
        self:SetWidth(300)
        self:SetHeight(240)
        self:EnableResize(false)
    end
    function widget:SetOwner(owner)
        local control = self.frame
        -- Keep the popup above its owner when the toplevel window is raised.
        control:SetParent(owner.frame)
        control:ClearAllPoints()
        control:SetPoint("CENTER", owner.frame, "CENTER")
        PopupLayers(control, owner.frame:GetFrameStrata(), owner.frame:GetFrameLevel() + 20)
    end
    return widget
end

AceGUI:RegisterWidgetType("CDMCenteredDropdown", CenteredDropdown, 1)
AceGUI:RegisterWidgetType("CDMGroupPopup", GroupPopup, 1)

AceGUI:RegisterLayout("CDMGroupHeader", function(content, children)
    local dropdown, button = children[1], children[2]
    if not dropdown then return end
    local width = content.width or content:GetWidth()
    dropdown:SetWidth(width / 3)
    local control = dropdown.frame
    control:ClearAllPoints()
    control:SetPoint("TOP", content, "TOP", 0, 0)
    control:Show()
    if button then
        button:SetWidth(100)
        local action = button.frame
        action:ClearAllPoints()
        action:SetPoint("TOPLEFT", control, "TOPRIGHT", 8, -16)
        action:Show()
    end
    content.obj:LayoutFinished(nil, 48)
end)
