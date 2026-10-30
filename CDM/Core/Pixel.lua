local AddonName = "CDM"
local CDM = _G[AddonName]
local CDM_C = CDM.CONST

local math_floor = math.floor
local math_ceil = math.ceil
local type = type
local canaccessvalue = canaccessvalue

local Pixel = {}
CDM.Pixel = Pixel

local cachedPixelSize = 1
local cachedPhysH = 0
local cachedScale = 1

function Pixel.Update()
    local physH = select(2, GetPhysicalScreenSize())
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if physH and physH > 0 and scale and scale > 0 then
        if physH == cachedPhysH and scale == cachedScale then
            return
        end
        cachedPhysH = physH
        cachedScale = scale
        cachedPixelSize = 768 / (physH * scale)
    end
end

function Pixel.GetSize()
    return cachedPixelSize
end

function Pixel.Snap(value)
    if not value or value == 0 then return 0 end
    local px = value / cachedPixelSize
    if px >= 0 then
        return math_floor(px + 0.5) * cachedPixelSize
    else
        return math_ceil(px - 0.5) * cachedPixelSize
    end
end

function Pixel.HalfFloor(value)
    if not value or value == 0 then return 0 end
    local px = math_floor(value / cachedPixelSize + 0.5)
    return math_floor(px / 2) * cachedPixelSize
end

function Pixel.SnapEven(value)
    if not value or value == 0 then return 0 end
    local px = value / cachedPixelSize
    if px >= 0 then
        px = math_floor(px + 0.5)
    else
        px = math_ceil(px - 0.5)
    end
    if px % 2 ~= 0 then px = px + 1 end
    return px * cachedPixelSize
end

function Pixel.SetPoint(frame, point, relativeTo, relativePoint, x, y)
    if not frame then return end
    frame:SetPoint(
        point,
        relativeTo,
        relativePoint,
        Pixel.Snap(x or 0),
        Pixel.Snap(y or 0)
    )
end

function Pixel.SetSize(frame, w, h)
    if not frame then return end
    frame:SetSize(Pixel.Snap(w), Pixel.Snap(h))
end

-- 0 = left/bottom, 1 = right/top.
local POINT_FRACTION = {
    TOPLEFT     = { 0, 1 },   TOP    = { 0.5, 1 },   TOPRIGHT    = { 1, 1 },
    LEFT        = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT       = { 1, 0.5 },
    BOTTOMLEFT  = { 0, 0 },   BOTTOM = { 0.5, 0 },   BOTTOMRIGHT = { 1, 0 },
}

local function SafeNum(v)
    if type(v) == "number" and (not canaccessvalue or canaccessvalue(v)) then
        return v
    end
end

-- Snaps the resulting edge, not the offset. Pixel.SetPoint is useless when the
-- anchor frame itself sits on a half pixel (e.g. a Blizzard frame centred on an
-- odd width), since the fractional origin is inherited. Set the frame's size
-- first. Falls back to Pixel.SetPoint when geometry is secret or not laid out.
function Pixel.SetGridPoint(frame, point, relativeTo, relativePoint, x, y)
    if not frame then return end
    if type(relativeTo) == "string" then relativeTo = _G[relativeTo] end
    relativeTo = relativeTo or frame:GetParent()
    relativePoint = relativePoint or point
    x, y = x or 0, y or 0

    local objF, relF = POINT_FRACTION[point], POINT_FRACTION[relativePoint]
    local relLeft = objF and relF and relativeTo and SafeNum(relativeTo:GetLeft())
    local relBottom = relLeft and SafeNum(relativeTo:GetBottom())
    local relW = relBottom and SafeNum(relativeTo:GetWidth())
    local relH = relW and SafeNum(relativeTo:GetHeight())
    local objW = relH and SafeNum(frame:GetWidth())
    local objH = objW and SafeNum(frame:GetHeight())
    local objScale = objH and SafeNum(frame:GetEffectiveScale())
    local relScale = objScale and SafeNum(relativeTo:GetEffectiveScale())
    if not relScale or objScale <= 0 or cachedPhysH <= 0 then
        Pixel.SetPoint(frame, point, relativeTo, relativePoint, x, y)
        return
    end

    -- Work in the frame's own units so differing effective scales stay correct.
    local ratio = relScale / objScale
    local px = 768 / (cachedPhysH * objScale)
    local left = (relLeft + relF[1] * relW) * ratio - objF[1] * objW + x
    local bottom = (relBottom + relF[2] * relH) * ratio - objF[2] * objH + y
    local dx = math_floor(left / px + 0.5) * px - left
    local dy = math_floor(bottom / px + 0.5) * px - bottom
    frame:SetPoint(point, relativeTo, relativePoint, x + dx, y + dy)
end

function Pixel.FontSize(desiredPx)
    return desiredPx * cachedScale
end

function Pixel.DisableTextureSnap(tex)
    if not tex then return end
    if not tex.SetSnapToPixelGrid and tex.GetStatusBarTexture then
        tex = tex:GetStatusBarTexture()
        if not tex then return end
    end
    if tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
    end
    if tex.SetTexelSnappingBias then
        tex:SetTexelSnappingBias(0)
    end
end

function Pixel.CreateSolidTexture(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "OVERLAY", nil, sublevel or 0)
    tex:SetTexture(CDM_C.TEX_WHITE8X8)
    if tex.SetHorizTile then tex:SetHorizTile(false) end
    if tex.SetVertTile then tex:SetVertTile(false) end
    Pixel.DisableTextureSnap(tex)
    return tex
end

function Pixel.IsOneBorderMode()
    local borderFile = CDM_C.GetConfigValue("borderFile", "CDM_Thin")
    if borderFile == "None" then
        return false
    end
    if borderFile == "1 Pixel" then
        return true
    end
    local borderSize = CDM_C.GetConfigValue("borderSize", 16)
    return math.max(0, math_floor(borderSize / cachedPixelSize + 0.5)) <= 1
end

if UIParent then
    Pixel.Update()
end
