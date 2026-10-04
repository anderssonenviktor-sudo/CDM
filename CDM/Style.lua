local addonName, ns = ...
local Style = {}
ns.Style = Style
local states = setmetatable({}, { __mode = "k" })
local fonts = {}
local applying = false
local isCurrent, defer
local LSM = LibStub("LibSharedMedia-3.0")
local maskAtlas = "UI-HUD-CoolDownManager-Mask"
local overlayAtlas = "UI-HUD-CoolDownManager-IconOverlay"

function Style.Initialize(validate, deferCallback)
    isCurrent, defer = validate, deferCallback
    for viewerID, description in pairs(ns.Constants.viewers) do
        local name = "CDM_Font_" .. viewerID
        fonts[description.groupID] = { name = name, object = CreateFont(name) }
    end
end

function Style.InvalidateFont(groupID)
    if fonts[groupID] then fonts[groupID].style = nil end
end

local function Crop(width, height, padding)
    local span = 1 - 2 * padding
    local aspect = width / height
    local x = span * math.min(1, aspect)
    local y = span * math.min(1, 1 / aspect)
    return (1 - x) / 2, (1 + x) / 2, (1 - y) / 2, (1 + y) / 2
end
Style.CalculateCrop = Crop

local function RemoveKnownMask(frame, state)
    local icon = frame.Icon
    if not icon or not icon.GetNumMaskTextures then return end
    -- Only Blizzard's known rounded mask; preserve other addons' masks.
    local count = ns.Util.Number(icon:GetNumMaskTextures())
    if not count then return end
    for index = count, 1, -1 do
        local mask = icon:GetMaskTexture(index)
        if ns.Util.IsPublic(mask) and mask then
            local atlas = mask:GetAtlas()
            if ns.Util.IsPublic(atlas) and atlas == maskAtlas then
                icon:RemoveMaskTexture(mask)
                state.masks[mask] = true
            end
        end
    end
end

local function HideKnownOverlay(frame, state)
    for _, region in ipairs({ frame:GetRegions() }) do
        if ns.Util.IsPublic(region) and region.GetAtlas then
            local atlas = region:GetAtlas()
            if ns.Util.IsPublic(atlas) and atlas == overlayAtlas then
                if not state.overlays[region] then
                    local alpha = region:GetAlpha()
                    state.overlays[region] = ns.Util.Number(alpha) or 1
                end
                region:SetAlpha(0)
            end
        end
    end
end

local function BorderGeometry(frame, state, size)
    if not state.border then
        state.border = {}
        for index = 1, 4 do state.border[index] = frame:CreateTexture(nil, "OVERLAY", nil, 7) end
    end
    local top, bottom, left, right = unpack(state.border)
    for _, texture in ipairs(state.border) do texture:ClearAllPoints() end
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(math.max(size, 0.01))
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(math.max(size, 0.01))
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(math.max(size, 0.01))
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(math.max(size, 0.01))
end

local function Appearance(frame, state, config)
    local style = config.style
    local font = fonts[config.id]
    if font.style ~= style then
        font.path = LSM:Fetch("font", style.font, true) or STANDARD_TEXT_FONT
        font.object:SetFont(font.path, style.cooldownTextSize, "OUTLINE")
        font.object:SetTextColor(unpack(style.cooldownColor))
        font.style = style
    end
    if frame.Icon then
        frame.Icon:SetTexCoord(Crop(config.width, config.height, style.crop))
    end
    -- Texture masks/alpha are appearance changes, not protected frame geometry.
    RemoveKnownMask(frame, state)
    HideKnownOverlay(frame, state)
    if frame.Cooldown then
        frame.Cooldown:SetCountdownFont(font.name)
        frame.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        frame.Cooldown:SetDrawBling(false)
    end
    local charge = frame.ChargeCount and frame.ChargeCount.Current
    if charge then
        charge:SetFont(font.path, style.chargeTextSize, "OUTLINE")
        charge:SetTextColor(unpack(style.chargeColor))
    end
    local stacks = frame.Applications and frame.Applications.Applications
    if stacks then
        stacks:SetFont(font.path, style.stackTextSize, "OUTLINE")
        stacks:SetTextColor(unpack(style.stackColor))
    end
    if state.border then
        for _, texture in ipairs(state.border) do
            texture:SetColorTexture(unpack(style.borderColor))
            texture:SetAlpha(style.borderSize > 0 and 1 or 0)
        end
    end
end

local function Guarded(callback)
    applying = true
    local ok, message = pcall(callback)
    applying = false
    if not ok then error(message, 0) end
end

function Style.Apply(source, config)
    if not isCurrent(source) then return end
    if not fonts[config.id] then
        if InCombatLockdown() then defer(config.id); return end
        local name = "CDM_Font_" .. config.id:gsub("%-", "_")
        fonts[config.id] = { name = name, object = CreateFont(name) }
    end
    local frame = source.frame
    local state = states[frame]
    if not state then
        state = { masks = {}, overlays = {} }
        states[frame] = state
    end
    state.source, state.config = source, config
    Guarded(function()
        if not InCombatLockdown() then
            if frame.Icon then
                frame.Icon:ClearAllPoints()
                frame.Icon:SetAllPoints(frame)
                if frame.Icon.SetSnapToPixelGrid then frame.Icon:SetSnapToPixelGrid(false) end
                if frame.Icon.SetTexelSnappingBias then frame.Icon:SetTexelSnappingBias(0) end
            end
            if frame.Cooldown then
                frame.Cooldown:ClearAllPoints()
                frame.Cooldown:SetAllPoints(frame)
            end
            local charge = frame.ChargeCount and frame.ChargeCount.Current
            if charge then
                charge:ClearAllPoints()
                charge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
                charge:SetIgnoreParentScale(true)
            end
            local stacks = frame.Applications and frame.Applications.Applications
            if stacks then
                stacks:ClearAllPoints()
                stacks:SetPoint("TOP", frame, "TOP", 0, -2)
                stacks:SetIgnoreParentScale(true)
            end
            BorderGeometry(frame, state, config.style.borderSize)
        else
            defer(config.id)
        end
        Appearance(frame, state, config)
    end)
end

function Style.ResetFrame(frame)
    local state = states[frame]
    if not state then return end
    state.source, state.config = nil, nil
    if state.border then
        for _, texture in ipairs(state.border) do texture:SetAlpha(0) end
    end
    -- Skin removal also makes ID-less Edit Mode placeholders look native.
    for mask in pairs(state.masks) do frame.Icon:AddMaskTexture(mask) end
    state.masks = {}
    for region, alpha in pairs(state.overlays) do region:SetAlpha(alpha) end
    state.overlays = {}
end

function Style.ClearBindings(viewerID)
    for frame, state in pairs(states) do
        if not viewerID or (state.config and state.config.viewer == viewerID) then Style.ResetFrame(frame) end
    end
end

function Style.Reassert(frame, reason, displayValue)
    if applying then return end
    local state = states[frame]
    if not state or not state.source or not isCurrent(state.source) then return end
    Guarded(function()
        if reason == "charge" then
            -- The type is public even when the number is secret. Do not test
            -- the count: Blizzard's formatter accepts the secret directly.
            if type(displayValue) == "number" and C_StringUtil and C_StringUtil.TruncateWhenZero then
                frame.ChargeCount.Current:SetText(C_StringUtil.TruncateWhenZero(displayValue))
            end
        else
            Appearance(frame, state, state.config)
        end
    end)
end
