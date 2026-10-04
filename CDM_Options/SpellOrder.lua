local addonName, ns = ...
local API = _G.CDM_API
local AceGUI = LibStub("AceGUI-3.0")
local typeName = "CDMSpellOrder"
local size, gap, padding = 32, 4, 4
local stride = size + gap

-- These are options-owned buttons, never Blizzard viewer frames. Entries
-- contain only detached, sanitized public metadata from CDM_API.
local function Constructor()
    local panel = CreateFrame("Frame", nil, UIParent)
    local widget = { type = typeName, frame = panel }
    local entries, buttons = {}, {}
    local columns, startX = 1, padding
    local dragged
    local tooltipOwner
    local marker = panel:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(0, 1, 0.8, 1)
    marker:SetSize(2, size)
    marker:Hide()
    local ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(size, size)
    ghost:EnableMouse(false)
    ghost:SetAlpha(0.85)
    local ghostIcon = ghost:CreateTexture(nil, "ARTWORK")
    ghostIcon:SetAllPoints()
    ghostIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ghost:Hide()

    local function HideTooltip()
        if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then GameTooltip:Hide() end
        tooltipOwner = nil
    end

    local function CancelDrag()
        if dragged then buttons[dragged].icon:SetAlpha(1) end
        dragged = nil
        panel:SetScript("OnUpdate", nil)
        marker:Hide()
        ghost:Hide()
        HideTooltip()
    end

    local function DropSlot()
        if not panel:IsMouseOver() then return nil end
        local left, top = panel:GetLeft(), panel:GetTop()
        if not left or not top then return nil end
        local cursorX, cursorY = GetCursorPosition()
        local scale = panel:GetEffectiveScale()
        local x, y = cursorX / scale - left, top - cursorY / scale
        local row = math.floor((y - padding) / stride)
        local rows = math.ceil(#entries / columns)
        if row < 0 or row >= rows then return nil end
        local count = math.min(columns, #entries - row * columns)
        local column = math.max(0, math.min(count, math.floor((x - startX + size / 2) / stride)))
        return row * columns + column + 1, row, column
    end

    local function UpdateDrag()
        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
        local slot, row, column = DropSlot()
        if slot then
            marker:ClearAllPoints()
            marker:SetPoint("TOPLEFT", panel, "TOPLEFT", startX + column * stride - gap / 2, -padding - row * stride)
            marker:Show()
        else marker:Hide() end
    end

    local function FinishDrag()
        if not dragged then return end
        local slot = DropSlot()
        local key = entries[dragged].key
        local beforeKey = slot and entries[slot] and entries[slot].key or nil
        local unchanged = slot and (slot == dragged or slot == dragged + 1)
        CancelDrag()
        if slot and not unchanged then widget:Fire("OnReorder", key, beforeKey) end
    end

    local function AddButton(index)
        local button = CreateFrame("Button", nil, panel)
        button:SetSize(size, size)
        button:RegisterForDrag("LeftButton")
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0, 0, 0, 1)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.2)
        buttons[index] = { button = button, icon = icon }
        button:SetScript("OnEnter", function()
            if dragged or not entries[index] then return end
            tooltipOwner = button
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(entries[index].name)
            GameTooltip:AddLine(API.GetText("Drag to reorder."), 0, 1, 0.8)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", HideTooltip)
        button:SetScript("OnDragStart", function()
            if #entries < 2 or not entries[index] then return end
            CancelDrag()
            dragged = index
            icon:SetAlpha(0.35)
            ghostIcon:SetTexture(entries[index].icon or 134400)
            ghost:Show()
            panel:SetScript("OnUpdate", UpdateDrag)
            UpdateDrag()
        end)
        button:SetScript("OnDragStop", FinishDrag)
        button:SetScript("OnMouseUp", function(_, mouseButton)
            if mouseButton == "LeftButton" then FinishDrag()
            elseif mouseButton == "RightButton" then CancelDrag() end
        end)
    end

    local function Arrange(width)
        CancelDrag()
        width = math.max(size + padding * 2, width or panel:GetWidth())
        columns = math.max(1, math.min(math.max(1, #entries), math.floor((width - padding * 2 + gap) / stride)))
        startX = (width - (columns * stride - gap)) / 2
        for index, entry in ipairs(entries) do
            if not buttons[index] then AddButton(index) end
            local item = buttons[index]
            item.icon:SetTexture(entry.icon or 134400)
            item.icon:SetAlpha(1)
            item.button:ClearAllPoints()
            item.button:SetPoint("TOPLEFT", panel, "TOPLEFT", startX + ((index - 1) % columns) * stride,
                -padding - math.floor((index - 1) / columns) * stride)
            item.button:Show()
        end
        for index = #entries + 1, #buttons do buttons[index].button:Hide() end
        local height = padding * 2 + math.max(1, math.ceil(#entries / columns)) * stride - gap
        if panel:GetHeight() ~= height then widget:SetHeight(height) end
    end

    function widget:OnAcquire()
        self:SetWidth(300)
        self:SetHeight(size + padding * 2)
    end

    function widget:SetEntries(values)
        entries = values
        Arrange()
    end

    function widget:OnWidthSet(width) Arrange(width) end
    function widget:CancelDrag() CancelDrag() end

    function widget:OnRelease()
        CancelDrag()
        entries = {}
        for _, item in ipairs(buttons) do item.button:Hide(); item.icon:SetTexture(nil) end
    end

    panel:SetScript("OnHide", CancelDrag)
    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(typeName, Constructor, 2)
