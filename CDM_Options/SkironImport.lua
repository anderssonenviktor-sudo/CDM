local CDM = _G["CDM"]
if not CDM then return end
local ns = CDM._OptionsNS
local L = CDM.L

-- Conversion stays in the on-demand Options addon. Only a pasted export is
-- inspected; no foreign SavedVariables or Skiron frames are accessed. A named
-- NUF_Player target can supply a read-only snapshot of its current bounds.
local Importer = {}
ns.SkironImport = Importer

local POINTS = {
    CENTER = { 0, 0 }, TOP = { 0, 0.5 }, BOTTOM = { 0, -0.5 },
    LEFT = { -0.5, 0 }, RIGHT = { 0.5, 0 },
    TOPLEFT = { -0.5, 0.5 }, TOPRIGHT = { 0.5, 0.5 },
    BOTTOMLEFT = { -0.5, -0.5 }, BOTTOMRIGHT = { 0.5, -0.5 },
}
local GLOWS = { Pixel = "pixel", Proc = "proc", Autocast = "autocast", Button = "button" }
local OUTLINES = { NONE = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true, ["MONOCHROME,OUTLINE"] = true }
local FRAME_TARGETS = {
    PlayerFrame = "playerFrame", ElvUF_Player = "playerFrame", SUFUnitplayer = "playerFrame",
    UUF_Player = "playerFrame", EllesmereUIUnitFrames_Player = "playerFrame", MSUF_player = "playerFrame",
    EQOLUFPlayerFrame = "playerFrame", oUF_Player = "playerFrame",
    EssentialCooldownViewer = "essential", UtilityCooldownViewer = "utility", BuffIconCooldownViewer = "buff",
}

local function Number(value, low, high)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    if low and value < low or high and value > high then return nil end
    return value
end

local function ID(value)
    value = tonumber(value)
    return Number(value, 1, 2147483647) and value == math.floor(value) and value or nil
end

local function AnchorID(reference)
    if type(reference) ~= "string" then return nil end
    local kind, value = reference:match("^ANCHOR:([%a]+):(%d+)$")
    if kind then
        value = ID(value)
        if not value or value > 99 then return nil end
        kind = kind:upper()
        if kind == "I" then return value end
        if kind == "G" then return 100 + value end
        if kind == "BB" then return 200 + value end
        return nil
    end
    value = ID(reference:match("^ANCHOR:(%d+)$") or reference:match("^SCM_GroupAnchor_(%d+)$"))
    if value and value < 300 and value ~= 100 and value ~= 200 then return value end
end

local function Color(value)
    if type(value) ~= "table" then return nil end
    local r = value.r or value[1]
    local g = value.g or value[2]
    local b = value.b or value[3]
    local a = value.a or value[4] or 1
    if Number(r, 0, 1) and Number(g, 0, 1) and Number(b, 0, 1) and Number(a, 0, 1) then
        return { r = r, g = g, b = b, a = a }
    end
end

local function Path(base, key)
    return base .. "." .. tostring(key):gsub("[|%c]", "?")
end

local function Get(t, key)
    if type(t) ~= "table" then return nil end
    local value = t[key]
    if value == nil and type(key) == "number" then value = t[tostring(key)] end
    return value
end

local function NumericKeys(t)
    local result, seen = {}, {}
    if type(t) == "table" then
        for key in pairs(t) do
            local id = ID(key)
            if id and not seen[id] then
                result[#result + 1], seen[id] = id, true
            end
        end
    end
    table.sort(result)
    return result
end

local function Context()
    local ctx = { data = {}, used = {}, aliases = {}, warnings = {}, warningSet = {}, groupCount = 0, specIDs = {}, records = {} }
    function ctx:Use(path) self.used[self.aliases[path] or path] = true end
    function ctx:Warn(message)
        if not self.warningSet[message] then
            self.warningSet[message] = true
            self.warnings[#self.warnings + 1] = message
        end
    end
    function ctx:Map(source, key, base, dest, target, kind, low, high)
        local value = Get(source, key)
        if value == nil then return nil end
        local mapped
        if kind == "number" then mapped = Number(value, low, high)
        elseif kind == "color" then mapped = Color(value)
        elseif kind == "point" then mapped = POINTS[value] and value
        elseif kind == "outline" then mapped = OUTLINES[value] and value
        elseif kind == "boolean" and type(value) == "boolean" then mapped = value
        elseif kind == "invert" and type(value) == "boolean" then mapped = not value
        elseif kind == "string" and type(value) == "string" and #value > 0 and #value < 256 then mapped = value
        end
        if mapped ~= nil then
            dest[target] = mapped
            self:Use(Path(base, key))
        end
        return mapped
    end
    return ctx
end

local function MapFields(ctx, source, base, dest, fields)
    for _, field in ipairs(fields) do
        ctx:Map(source, field[1], base, dest, field[2], field[3], field[4], field[5])
    end
end

local function ConvertGlow(ctx, source, base)
    local style = Get(source, "glowType")
    if Get(source, "useCustomGlow") == true and GLOWS[style] then
        ctx:Use(Path(base, "useCustomGlow"))
        ctx:Use(Path(base, "glowType"))
        ctx.data.glowType = GLOWS[style]
        local settings = Get(Get(source, "glowTypeOptions"), style)
        local path = Path(Path(base, "glowTypeOptions"), style)
        if ctx:Map(settings, "glowColor", path, ctx.data, "glowColor", "color") then
            ctx.data.glowColorMode = "custom"
        end
        local fields = {
            Pixel = {
                { "numLines", "glowPixelLines", "number", 1, 64 },
                { "frequency", "glowPixelFrequency", "number", -10, 10 },
                { "length", "glowPixelLength", "number", 0, 100 },
                { "thickness", "glowPixelThickness", "number", 0.1, 20 },
                { "xOffset", "glowPixelXOffset", "number", -100, 100 },
                { "yOffset", "glowPixelYOffset", "number", -100, 100 },
                { "border", "glowPixelBorder", "boolean" },
            },
            Autocast = {
                { "numParticles", "glowAutocastParticles", "number", 1, 64 },
                { "frequency", "glowAutocastFrequency", "number", -10, 10 },
                { "scale", "glowAutocastScale", "number", 0.1, 10 },
            },
            Button = { { "frequency", "glowButtonFrequency", "number", -10, 10 } },
        }
        MapFields(ctx, settings, path, ctx.data, fields[style] or {})
    end
end

local function ConvertGeneral(ctx, source, base)
    MapFields(ctx, source, base, ctx.data, {
        { "borderSize", "borderSize", "number", 0, 16 },
        { "borderColor", "borderColor", "color" },
        { "iconZoom", "zoomAmount", "number", 0, 0.45 },
        { "pressOverlay", "pressOverlayEnabled", "boolean" },
        { "disableGCD", "hideGCDSwipe", "boolean" },
        { "normalSwipeColor", "swipeColor", "color" },
        { "cooldownFont", "textFont", "string" },
        { "cooldownFontOutline", "textFontOutline", "outline" },
        { "cooldownFontColor", "cooldownColor", "color" },
        { "chargeFontSize", "chargeFontSize", "number", 1, 100 },
        { "chargeColour", "chargeColor", "color" },
        { "applicationsColour", "countColor", "color" },
        { "chargeRelativePoint", "chargePosition", "point" },
        { "chargeXOffset", "chargeOffsetX", "number", -100, 100 },
        { "chargeYOffset", "chargeOffsetY", "number", -100, 100 },
        { "pandemicBorderColor", "pandemicBorderColor", "color" },
    })
    if ctx.data.zoomAmount ~= nil then ctx.data.zoomIcons = ctx.data.zoomAmount > 0 end
    if ctx.data.chargeFontSize then ctx.data.countFontSize = ctx.data.chargeFontSize end
    if ctx.data.cooldownColor then ctx.data.buffCooldownColor = CDM:DeepCopy(ctx.data.cooldownColor) end
    if Get(source, "chargePoint") and Get(source, "chargePoint") ~= Get(source, "chargeRelativePoint") then
        ctx:Warn(L["Text anchor alignment differs between SkironCDM and CDM; review charge and stack text positions."])
    end
    local hidePandemic = Get(source, "pandemicGlowOption")
    if hidePandemic == "disablePandemicGlow" or hidePandemic == "keepPandemicGlow" then
        ctx.data.hidePandemicIndicator = hidePandemic == "disablePandemicGlow"
        ctx:Use(Path(base, "pandemicGlowOption"))
    end
    if Get(source, "pandemicReplaceWithBorder") == true then
        ctx.data.pandemicCustomizationEnabled, ctx.data.pandemicBorderEnabled = true, true
        ctx:Use(Path(base, "pandemicReplaceWithBorder"))
    end
    ConvertGlow(ctx, source, base)
    MapFields(ctx, Get(source, "buffBarOptions"), Path(base, "buffBarOptions"), ctx.data, {
        { "barTexture", "buffBarTexture", "string" },
        { "backgroundColor", "buffBarBackgroundColor", "color" },
        { "foregroundColor", "buffBarColor", "color" },
        { "fontSize", "buffBarNameFontSize", "number", 1, 100 },
        { "hideSpellName", "buffBarShowName", "invert" },
        { "hideDuration", "buffBarShowDuration", "invert" },
        { "nameXOffset", "buffBarNameOffsetX", "number", -100, 100 },
        { "nameYOffset", "buffBarNameOffsetY", "number", -100, 100 },
        { "nameColor", "buffBarNameColor", "color" },
        { "durationXOffset", "buffBarDurationOffsetX", "number", -100, 100 },
        { "durationYOffset", "buffBarDurationOffsetY", "number", -100, 100 },
        { "durationColor", "buffBarDurationColor", "color" },
    })
    if ctx.data.buffBarNameFontSize then ctx.data.buffBarDurationFontSize = ctx.data.buffBarNameFontSize end
end

local function ConvertCastBar(ctx, source, base)
    MapFields(ctx, source, base, ctx.data, {
        { "enable", "castBarEnabled", "boolean" },
        { "width", "castBarWidth", "number", 1, 2000 },
        { "height", "castBarHeight", "number", 1, 200 },
        { "texture", "castBarTexture", "string" },
        { "fontSize", "castBarFontSize", "number", 1, 100 },
        { "useClassColor", "castBarUseClassColor", "boolean" },
        { "fgColor", "castBarCastColor", "color" },
        { "bgColor", "castBarBackgroundColor", "color" },
    })
    if Get(source, "matchParentWidth") == true then
        ctx:Use(Path(base, "matchParentWidth"))
    elseif Get(source, "matchParentWidth") == false then
        ctx:Use(Path(base, "matchParentWidth"))
    end
    if ctx.data.castBarCastColor then ctx.data.castBarChannelColor = CDM:DeepCopy(ctx.data.castBarCastColor) end
    if Get(source, "texture") then ctx.data.castBarUseAtlasTextures = false end
    if Get(Get(source, "icon"), "enable") ~= nil then ctx.data.castBarIconGap = 0 end
    for _, entry in ipairs({ { "spellName", "LEFT", "castBarNameOffsetX", "castBarNameOffsetY" },
        { "castDuration", "RIGHT", "castBarTimerOffsetX", "castBarTimerOffsetY" } }) do
        local anchor = Get(Get(source, entry[1]), "anchors")
        if type(anchor) == "table" and anchor[1] == entry[2] and anchor[2] == entry[2]
            and Number(anchor[3], -100, 100) and Number(anchor[4], -100, 100) then
            ctx.data[entry[3]], ctx.data[entry[4]] = anchor[3], anchor[4]
            ctx:Use(Path(Path(base, entry[1]), "anchors"))
        end
    end
    for _, entry in ipairs({
        { "icon", "enable", "castBarShowIcon", "boolean" },
        { "icon", "position", "castBarIconPosition", "string" },
        { "spark", "enable", "castBarShowSpark", "boolean" },
        { "spellName", "enable", "castBarShowSpellName", "boolean" },
        { "castDuration", "enable", "castBarShowTimer", "boolean" },
    }) do
        local child = Get(source, entry[1])
        if entry[3] ~= "castBarIconPosition" or Get(child, entry[2]) == "LEFT" or Get(child, entry[2]) == "RIGHT" then
            ctx:Map(child, entry[2], Path(base, entry[1]), ctx.data, entry[3], entry[4])
        end
    end
    local anchor = Get(source, "anchors")
    if type(anchor) == "table" then
        local targets = {
            UIParent = "screen", EssentialCooldownViewer = "essential",
            SCM_PrimaryResourceBar = "resources", SCM_SecondaryResourceBar = "resources",
            ["SCM_SecondaryResourceBar,SCM_PrimaryResourceBar,ANCHOR:1"] = "resources",
        }
        if targets[anchor[2]] and POINTS[anchor[1]] and POINTS[anchor[3]]
            and Number(anchor[4], -10000, 10000) and Number(anchor[5], -10000, 10000) then
            ctx.data.castBarAnchor = targets[anchor[2]]
            ctx.data.castBarAnchorPoint, ctx.data.castBarTargetPoint = anchor[1], anchor[3]
            ctx.data.castBarOffsetX, ctx.data.castBarOffsetY = anchor[4], anchor[5]
            ctx:Use(Path(base, "anchors"))
        end
    end
    if next(source or {}) then ctx:Warn(L["CDM uses its own cast-bar font and border behavior; review the imported cast bar."]) end
end

local PRIMARY_BARS = { Mana = true, Rage = true, Energy = true, Focus = true, RunicPower = true, LunarPower = true, Maelstrom = true, Insanity = true, Fury = true }
local POWER_TOKENS = {
    Mana = "MANA", Rage = "RAGE", Energy = "ENERGY", Focus = "FOCUS", RunicPower = "RUNIC_POWER",
    LunarPower = "LUNAR_POWER", Maelstrom = "MAELSTROM", Insanity = "INSANITY", Fury = "FURY",
    HolyPower = "HOLY_POWER", ComboPoints = "COMBO_POINTS", Runes = "RUNES", SoulShards = "SOUL_SHARDS",
    ArcaneCharges = "ARCANE_CHARGES", Essence = "ESSENCE", Chi = "CHI", Stagger = "STAGGER",
    MaelstromWeapon = "MAELSTROM_WEAPON", SoulFragments = "SOUL_FRAGMENTS_VENGEANCE",
    DevourerSoulFragments = "SOUL_FRAGMENTS", FireBlast = "SPELL_CHARGES_FIRE_BLAST", TipOfTheSpear = "TIP_OF_THE_SPEAR",
}
local function ConvertResourceStyle(ctx, source, base, section, bar, dest)
    local config = Get(source, section)
    MapFields(ctx, config, Path(base, section), dest, {
        { "height", "height", "number", 1, 200 },
        { "width", "width", "number", 1, 2000 },
        { "texture", "barTexture", "string" },
        { "backgroundTexture", "bgTexture", "string" },
        { "backgroundColor", "bgColor", "color" },
        { "showBorder", "hideBorder", "invert" },
        { "fontSize", "tagFontSize", "number", 1, 100 },
        { "textXOffset", "tagOffsetX", "number", -100, 100 },
        { "textYOffset", "tagOffsetY", "number", -100, 100 },
        { "showValues", "tagEnabled", "boolean" },
        { "useSmoothPowerUpdates", "smoothBars", "boolean" },
    })
    local token = POWER_TOKENS[bar]
    local override = token and Get(Get(source, "powerTypeColorOverrides"), token)
    if override then
        ctx:Map(override, "color", Path(Path(base, "powerTypeColorOverrides"), token), dest, "color", "color")
    end
    if Get(config, "enabled") == false then
        dest.loadMode = "never"
        ctx:Use(Path(Path(base, section), "enabled"))
    end
end

local function ConvertResources(ctx, source, base)
    ctx:Map(source, "enabled", base, ctx.data, "resourcesEnabled", "boolean")
    local settings = {}
    for class, bars in pairs(CDM.CLASS_BARS or {}) do
        for _, bar in ipairs(bars) do
            local section = PRIMARY_BARS[bar] and "primaryBar" or "secondaryBar"
            local dest = {}
            ConvertResourceStyle(ctx, source, base, section, bar, dest)
            if next(dest) then
                settings[class] = settings[class] or {}
                settings[class][bar] = dest
            end
        end
    end
    if next(settings) then
        ctx.data.resourceBarSettings = settings
        ctx:Warn(L["Resource bars use CDM's existing resource types. Unsupported custom resources and visibility rules are listed as skipped."])
    end
end

local function DefaultAnchor(index)
    local size = index == 1 and 47 or index == 2 and 41 or 40
    return {
        anchor = index == 1 and { "CENTER", "UIParent", "CENTER", 0, -285 }
            or { "TOP", "ANCHOR:" .. (index - 1), "BOTTOM", 0, 1 },
        rowConfig = { { iconWidth = size, iconHeight = size, limit = 8 } },
    }
end

local function LayoutNumber(ctx, source, key, base, fallback, low, high)
    local value = Number(Get(source, key), low, high)
    if value then ctx:Use(Path(base, key)) end
    return value or fallback
end

local function MakeRows(ctx, model)
    local anchor = model.config
    local rowConfig = Get(anchor, "rowConfig")
    local rowKeys = NumericKeys(rowConfig)
    local spacing = LayoutNumber(ctx, anchor, "spacing", model.path, 0, -16, 100)
    model.spacing = spacing
    local sourceGrow = Get(anchor, "grow")
    model.grow = sourceGrow or "CENTERED"
    if model.grow == "RIGHT" or model.grow == "LEFT" or model.grow == "CENTERED" or model.grow == "CENTER" then
        if sourceGrow == model.grow then ctx:Use(Path(model.path, "grow")) end
    else
        model.grow = "CENTERED"
    end
    model.up = Get(anchor, "secondaryGrow") == "UP"
    if model.up or Get(anchor, "secondaryGrow") == "DOWN" then ctx:Use(Path(model.path, "secondaryGrow")) end
    model.rows, model.width, model.height = {}, 0, 0
    local start, rowIndex = 1, 1
    repeat
        local key = rowKeys[math.min(rowIndex, #rowKeys)] or 1
        local row = Get(rowConfig, key) or {}
        local path = Path(Path(model.path, "rowConfig"), key)
        local size = Number(Get(row, "size"), 1, 1024)
        local width = LayoutNumber(ctx, row, "iconWidth", path, size or 47, 1, 1024)
        local height = LayoutNumber(ctx, row, "iconHeight", path, size or 47, 1, 1024)
        if size then ctx:Use(Path(path, "size")) end
        local limit = math.floor(LayoutNumber(ctx, row, "limit", path, 8, 1, 1000))
        local count = math.min(limit, #model.entries - start + 1)
        local layout = { config = row, path = path, start = start, count = count, width = width, height = height, y = model.height }
        layout.totalWidth = math.max(1, count) * width + math.max(0, count - 1) * spacing
        model.rows[#model.rows + 1] = layout
        model.width = math.max(model.width, layout.totalWidth)
        model.height = model.height + height + spacing
        start, rowIndex = start + math.max(1, count), rowIndex + 1
    until start > #model.entries
    model.height = model.height - spacing
    model.firstWidth, model.firstHeight = model.rows[1].width, model.rows[1].height
end

-- Resolve anchor geometry using only the exported layouts. Supported player
-- and viewer targets stay attached through CDM's existing anchoring helpers.
local ResolveReference
local function ResolvePosition(ctx, models, index, visiting)
    local model = models[index]
    if not model then return nil end
    if model.x then return model end
    if visiting[index] then return nil end
    visiting[index] = true
    if model.prepare then model.prepare(ctx, models, visiting, model) end
    local anchor = Get(model.config, "anchor")
    local point, relative, target, x, y = "CENTER", "CENTER", "UIParent", 0, 0
    if type(anchor) == "table" then point, target, relative, x, y = unpack(anchor)
    elseif anchor ~= nil then point = nil end
    local tx, ty
    model.anchorTarget, model.anchorRelativeTo = "screen", "CENTER"
    if POINTS[point] and POINTS[relative] and Number(x, -10000, 10000) and Number(y, -10000, 10000) then
        local reference = model.reference or ResolveReference(ctx, models, target, relative, visiting)
        if reference then
            tx, ty = reference.x, reference.y
            model.anchorTarget, model.anchorRelativeTo = reference.anchorTarget, reference.anchorRelativeTo
            if reference.link then
                ctx:Warn(L["Skiron anchor links use offsets based on configured icons; review positions after importing."])
            end
        end
    end
    visiting[index] = nil
    if not tx then
        model.x, model.y = 0, -100 - (type(index) == "number" and ((index - 1) % 100) * 60 or 0)
        model.invalid = true
        ctx:Warn(L["Unsupported or cyclic Skiron anchors use fallback screen positions; review group positions after importing."])
        if type(target) == "string" then
            ctx:Warn(string.format(L["Anchor target '%s' could not be converted; the group uses a fallback screen position."], target:gsub("[|%c]", "?")))
        end
        return model
    end
    local pivot = point
    local shiftX = 0
    if not model.rect and model.grow == "RIGHT" then
        if point == "TOP" or point == "TOPRIGHT" then pivot = "TOPLEFT"
        elseif point == "BOTTOM" or point == "BOTTOMRIGHT" then pivot = "BOTTOMLEFT"
        elseif point == "RIGHT" then pivot = "LEFT" end
        if point == "TOPRIGHT" then shiftX = -model.firstWidth
        elseif point == "TOP" or point == "BOTTOM" or point == "CENTER" then shiftX = -model.firstWidth / 2 end
    elseif not model.rect and model.grow == "LEFT" then
        if point == "TOP" or point == "TOPLEFT" then pivot = "TOPRIGHT"
        elseif point == "BOTTOM" or point == "BOTTOMLEFT" then pivot = "BOTTOMRIGHT"
        elseif point == "LEFT" then pivot = "RIGHT" end
        if point == "TOPLEFT" then shiftX = model.firstWidth
        elseif point == "TOP" or point == "BOTTOM" or point == "CENTER" then shiftX = model.firstWidth / 2 end
    end
    local fraction = POINTS[pivot]
    local extraHeight = model.rect and 0 or math.max(0, model.height - model.firstHeight)
    local shiftY = model.up and (fraction[2] > 0 and extraHeight or fraction[2] == 0 and extraHeight / 2 or 0)
        or (fraction[2] < 0 and -extraHeight or fraction[2] == 0 and -extraHeight / 2 or 0)
    model.x, model.y = tx + x + shiftX - fraction[1] * model.width, ty + y + shiftY - fraction[2] * model.height
    if model.path then ctx:Use(Path(model.path, "anchor")) end
    return model
end

local function ReadFrameSize(frame)
    if not frame or type(frame.GetWidth) ~= "function" or type(frame.GetHeight) ~= "function" then return nil end
    local ok, w, h = pcall(function()
        local width, height = frame:GetWidth(), frame:GetHeight()
        if CDM.IsSafeNumber(width) and CDM.IsSafeNumber(height) then return width, height end
    end)
    if ok then return Number(w, 1, 10000), Number(h, 1, 10000) end
end

local function SnapshotNorskenPlayer(ctx, models)
    -- The export names this external frame. Read its bounds only; never load
    -- another addon's DB or access Skiron-owned live frames.
    local frame = _G.NUF_Player
    local width, height = ReadFrameSize(frame)
    if not width or not height then return nil end
    local ok, x, y, scale = pcall(function()
        local cx, cy = frame:GetCenter()
        local ratio = (frame.GetEffectiveScale and frame:GetEffectiveScale() or 1)
            / (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
        if CDM.IsSafeNumber(cx) and CDM.IsSafeNumber(cy) and CDM.IsSafeNumber(ratio) then return cx, cy, ratio end
    end)
    if not ok or not Number(x) or not Number(y) or not Number(scale, 0.01, 100) then return nil end
    local model = {
        x = x * scale - UIParent:GetWidth() / 2, y = y * scale - UIParent:GetHeight() / 2,
        width = width * scale, height = height * scale, anchorTarget = "screen", anchorRelativeTo = "CENTER",
    }
    models.NUF_Player = model
    ctx:Warn(L["NUF_Player anchors use its current screen position. Re-import after moving or resizing that player frame."])
    return model
end

ResolveReference = function(ctx, models, target, point, visiting)
    if type(target) ~= "string" or not POINTS[point] then return nil end
    local isList = target:find(",", 1, true) ~= nil
    for name in target:gmatch("[^,]+") do
        name = name:match("^%s*(.-)%s*$")
        if name == "UIParent" then
            return { x = POINTS[point][1] * UIParent:GetWidth(), y = POINTS[point][2] * UIParent:GetHeight(),
                width = UIParent:GetWidth(), height = UIParent:GetHeight(), anchorTarget = "screen", anchorRelativeTo = "CENTER" }
        end
        local id = AnchorID(name) or (models[name] and name)
        local parent = id and ResolvePosition(ctx, models, id, visiting)
        if not parent and name == "NUF_Player" then parent = SnapshotNorskenPlayer(ctx, models) end
        if name == "NUF_Player" and not isList and _G.NUF_Player == nil then
            -- Skiron's UpdateAnchor substitutes UIParent when this stored
            -- frame name is absent, retaining the exported point and offsets.
            ctx:Warn(string.format(L["Anchor target '%s' is unavailable; Skiron's screen fallback was preserved."], name))
            return ResolveReference(ctx, models, "UIParent", point, visiting)
        end
        if parent and not parent.invalid and (not isList or parent.shown ~= false or AnchorID(name)) then
            return { x = parent.x + POINTS[point][1] * parent.width, y = parent.y + POINTS[point][2] * parent.height,
                width = parent.width, height = parent.height, anchorTarget = parent.anchorTarget,
                anchorRelativeTo = parent.anchorRelativeTo, link = true, name = name }
        end
        if FRAME_TARGETS[name] then
            if FRAME_TARGETS[name] == "playerFrame" then ctx:Warn(L["Player-frame anchors use CDM's selected player frame."]) end
            local width, height = ReadFrameSize(_G[name])
            return { x = 0, y = 0, width = width, height = height, anchorTarget = FRAME_TARGETS[name], anchorRelativeTo = point, name = name }
        end
    end
end

local function EffectiveSettings(ctx, root, rootPath, override, overridePath)
    if type(override) ~= "table" or override.active ~= true then return { data = root, path = rootPath } end
    local data = type(root) == "table" and CDM:DeepCopy(root) or {}
    local function Merge(dest, source, sourcePath, outPath)
        for key, value in pairs(source) do
            local targetPath = Path(outPath, key)
            ctx.aliases[targetPath] = Path(sourcePath, key)
            if type(value) == "table" then
                if type(dest[key]) ~= "table" then dest[key] = {} end
                Merge(dest[key], value, Path(sourcePath, key), targetPath)
            else
                dest[key] = value
            end
        end
    end
    if type(root) == "table" then Merge(data, root, rootPath, overridePath) end
    Merge(data, override, overridePath, overridePath)
    ctx:Use(Path(overridePath, "active"))
    return { data = data, path = overridePath, overridden = true }
end

local SECONDARY_RESOURCES = { DEATHKNIGHT = "Runes", PALADIN = "HolyPower", ROGUE = "ComboPoints", WARLOCK = "SoulShards", EVOKER = "Essence" }
local SPEC_SECONDARY_RESOURCES = { [62] = "ArcaneCharges", [63] = "FireBlast", [64] = "unsupportedIcicles", [255] = "TipOfTheSpear",
    [257] = "unsupportedSerenity", [263] = "MaelstromWeapon", [268] = "Stagger", [269] = "Chi", [581] = "SoulFragments", [1480] = "DevourerSoulFragments" }
local PRIMARY_BY_CLASS = { PALADIN = "Mana", MAGE = "Mana", WARLOCK = "Mana", PRIEST = "Mana", SHAMAN = "Mana", EVOKER = "Mana",
    MONK = "Mana", DRUID = "Mana", WARRIOR = "Rage", HUNTER = "Focus", ROGUE = "Energy", DEATHKNIGHT = "RunicPower", DEMONHUNTER = "Fury" }
local SPEC_PRIMARY_RESOURCES = { [258] = "Insanity", [262] = "Maelstrom", [268] = "Energy", [269] = "Energy", [102] = "LunarPower", [103] = "Energy", [104] = "Rage" }
local function ResourceKeys(ctx, specID, source, overridden)
    local class = ctx.specClasses[specID] or select(2, UnitClass("player"))
    local primary = SPEC_PRIMARY_RESOURCES[specID] or PRIMARY_BY_CLASS[class]
    if specID == ctx.currentSpecID and UnitPowerType then
        local _, token = UnitPowerType("player")
        for key, value in pairs(POWER_TOKENS) do if value == token and PRIMARY_BARS[key] then primary = key; break end end
    end
    local secondary = SPEC_SECONDARY_RESOURCES[specID] or SECONDARY_RESOURCES[class]
    if class == "DRUID" and primary == "Energy" then secondary = "ComboPoints"
    elseif class == "PRIEST" and primary == "Insanity" or class == "SHAMAN" and primary == "Maelstrom" then secondary = "Mana" end
    local primaryConfig, secondaryConfig = Get(source, "primaryBar"), Get(source, "secondaryBar")
    if overridden and Get(primaryConfig, "forceMana") == true then primary = "Mana" end
    if overridden and Get(secondaryConfig, "forceMana") == true and primary ~= "Mana" then secondary = "Mana" end
    local role = GetSpecializationInfoByID and select(5, GetSpecializationInfoByID(specID)) or "DAMAGER"
    local function Shown(key, config)
        if not key or Get(source, "enabled") == false or Get(config, "enabled") == false then return false end
        return key ~= "Mana" or specID == 62 or Get(Get(config, "hideManaRoles"), role) ~= true
    end
    return class, primary, secondary, Shown(primary, primaryConfig), Shown(secondary, secondaryConfig)
end

local function AddBarModels(ctx, models, specID, source, base)
    local resources = EffectiveSettings(ctx, ctx.rootResources, "resourceBarSettings.resourceBar", Get(source, "resourceBarConfig"), Path(base, "resourceBarConfig"))
    local cast = EffectiveSettings(ctx, ctx.rootCast, "castBarSettings", Get(source, "castBarConfig"), Path(base, "castBarConfig"))
    local record = { specID = specID, models = models, resources = resources, cast = cast }
    if type(resources.data) == "table" then
        local data = resources.data
        local class, primary, secondary, primaryShown, secondaryShown = ResourceKeys(ctx, specID, data, resources.overridden)
        record.class, record.primary, record.secondary = class, primary, secondary
        local p, s = Get(data, "primaryBar"), Get(data, "secondaryBar")
        local both = primaryShown and secondaryShown
        local ph = Number(Get(p, both and "heightAlternative" or "height"), 1, 200) or Number(Get(p, "height"), 1, 200) or 20
        local sh = Number(Get(s, both and "heightAlternative" or "height"), 1, 200) or Number(Get(s, "height"), 1, 200) or 20
        local spacing = Number(Get(data, "spacing"), -16, 100) or -1
        local up = Get(data, "growDirection") ~= "DOWN"
        local container = { rect = true, shown = primaryShown or secondaryShown, width = 1,
            height = both and (ph + sh + spacing) or primaryShown and ph or secondaryShown and sh or 0,
            config = { anchor = { Get(data, "point") or "BOTTOM", Get(data, "anchorFrame") or "ANCHOR:1", Get(data, "relativePoint") or "TOP",
                Number(Get(data, "xOffset"), -10000, 10000) or 0, Number(Get(data, "yOffset"), -10000, 10000) or 0 } },
        }
        container.prepare = function(c, ms, visiting, model)
            model.reference = ResolveReference(c, ms, model.config.anchor[2], model.config.anchor[3], visiting)
            local minimum = Number(Get(data, "minWidth"), 1, 2000) or 200
            local function Width(config)
                local w = Number(Get(config, "width"), 1, 2000) or 200
                if Get(config, "matchAnchorWidth") ~= false and model.reference and model.reference.width then w = model.reference.width end
                return math.max(minimum, w)
            end
            model.primaryWidth, model.secondaryWidth = Width(p), Width(s)
        end
        models.SCM_ResourceBarContainer = container
        local function Bar(primaryBar)
            local model = { rect = true, width = 200, height = primaryBar and ph or sh }
            if primaryBar then model.shown = primaryShown else model.shown = secondaryShown end
            local parent = not primaryBar and primaryShown and "SCM_PrimaryResourceBar" or "SCM_ResourceBarContainer"
            local point = up and "BOTTOM" or "TOP"
            local relative = parent == "SCM_PrimaryResourceBar" and (up and "TOP" or "BOTTOM") or point
            model.config = { anchor = { point, parent, relative, 0, parent == "SCM_PrimaryResourceBar" and (up and spacing or -spacing) or 0 } }
            model.prepare = function(c, ms, visiting, m)
                local owner = ResolvePosition(c, ms, "SCM_ResourceBarContainer", visiting)
                m.width = owner and (primaryBar and owner.primaryWidth or owner.secondaryWidth) or 200
            end
            return model
        end
        models.SCM_PrimaryResourceBar, models.SCM_SecondaryResourceBar = Bar(true), Bar(false)
    end
    if type(cast.data) == "table" then
        local data = cast.data
        local anchors = Get(data, "anchors")
        if type(anchors) ~= "table" then anchors = { "BOTTOM", "SCM_SecondaryResourceBar,SCM_PrimaryResourceBar,ANCHOR:1", "TOP", 0, 0 } end
        local model = { rect = true, shown = Get(data, "enable") ~= false, width = Number(Get(data, "width"), 1, 2000) or 270,
            height = Number(Get(data, "height"), 1, 200) or 24, config = { anchor = anchors } }
        model.prepare = function(c, ms, visiting, m)
            m.reference = ResolveReference(c, ms, anchors[2], anchors[3], visiting)
            if Get(data, "matchParentWidth") == true and m.reference and Number(m.reference.width, 1, 2000) then m.width = m.reference.width end
        end
        models.SCM_CastBar = model
    end
    ctx.records[#ctx.records + 1] = record
    return record
end

local function ConvertBarGeometry(ctx, record)
    local models = record.models
    if type(record.resources.data) == "table" then
        ConvertResources(ctx, record.resources.data, record.resources.path)
        local keys = { { record.primary, "SCM_PrimaryResourceBar", "primaryBar" }, { record.secondary, "SCM_SecondaryResourceBar", "secondaryBar" } }
        for _, entry in ipairs(keys) do
            local key, modelName, section = unpack(entry)
            local model = models[modelName]
            if key and CDM.RESOURCE_BAR_DEFAULTS[key] and model then
                local class = key == "Mana" and "General" or record.class
                local settings = ctx.data.resourceBarSettings or {}
                ctx.data.resourceBarSettings = settings
                settings[class] = settings[class] or {}
                settings[class][key] = settings[class][key] or {}
                local dest = settings[class][key]
                ConvertResourceStyle(ctx, record.resources.data, record.resources.path, section, key, dest)
                dest.loadMode = model.shown and "always" or "never"
                local stacked = section == "secondaryBar" and record.primary
                    and models.SCM_PrimaryResourceBar and models.SCM_PrimaryResourceBar.shown
                dest.anchorTo = stacked and record.primary or "essential"
                dest.anchorPoint, dest.anchorTargetPoint = "BOTTOM", "TOP"
                dest.offsetX, dest.offsetY = 0, 1
                if stacked then dest.barSpacing = 1 end
                local barConfig = Get(record.resources.data, section)
                if Get(barConfig, "matchAnchorWidth") ~= false then
                    dest.width = 0 -- CDM matches the Essential row when width is zero.
                else
                    local minimum = Number(Get(record.resources.data, "minWidth"), 1, 2000) or 200
                    dest.width = math.max(minimum, Number(Get(barConfig, "width"), 1, 2000) or 200)
                    ctx:Use(Path(record.resources.path, "minWidth"))
                end
                dest.height = model.height
                ctx:Use(Path(Path(record.resources.path, section), "matchAnchorWidth"))
                ctx:Use(Path(Path(record.resources.path, section), "heightAlternative"))
                ctx:Use(Path(Path(record.resources.path, section), "enabled"))
                ctx:Use(Path(Path(record.resources.path, section), "hideManaRoles"))
            end
        end
        for _, key in ipairs(CDM.CLASS_BARS[record.class] or {}) do
            if key ~= record.primary and key ~= record.secondary then
                local settings = ctx.data.resourceBarSettings
                settings[record.class] = settings[record.class] or {}
                settings[record.class][key] = settings[record.class][key] or {}
                settings[record.class][key].loadMode = "never"
            end
        end
    end
    if type(record.cast.data) == "table" then
        ConvertCastBar(ctx, record.cast.data, record.cast.path)
        local model = ResolvePosition(ctx, models, "SCM_CastBar", {})
        if model and not model.invalid then
            ctx.data.castBarWidth, ctx.data.castBarHeight = model.width, model.height
            if model.anchorTarget == "screen" or model.anchorTarget == "playerFrame" or model.anchorTarget == "essential" or model.anchorTarget == "utility" then
                ctx.data.castBarAnchor, ctx.data.castBarAnchorPoint = model.anchorTarget, "CENTER"
                ctx.data.castBarTargetPoint = model.anchorRelativeTo
                ctx.data.castBarOffsetX, ctx.data.castBarOffsetY = model.x, model.y
                ctx:Use(Path(record.cast.path, "anchors"))
            end
        end
    end
    ctx.barSpecID = record.specID
    ctx:Warn(L["Bar positions and matched widths use exported icon counts. Re-import after changing that layout."])
end

local function AddModels(ctx, models, anchors, base, offset, general)
    for _, index in ipairs(NumericKeys(anchors)) do
        local config = Get(anchors, index)
        local path = Path(base, index)
        if index <= 99 and type(config) == "table" then
            local shared = Get(config, "useGlobalProfileConfig")
            if offset ~= 100 and shared == true then
                local key = offset == 200 and "buffBarsAnchorConfig" or "anchorConfig"
                local inherited = Get(Get(general, key), index)
                if type(inherited) == "table" then
                    ctx:Use(Path(path, "useGlobalProfileConfig"))
                    config, path = inherited, Path(Path("globalSettings", key), index)
                else
                    ctx:Warn(L["This export uses shared layouts but does not include them. Include Global Settings when exporting from SkironCDM."])
                end
            elseif shared == false then
                ctx:Use(Path(path, "useGlobalProfileConfig"))
            end
            models[offset + index] = { config = config, path = path, entries = {} }
        end
    end
end

local function BuiltInTarget(model)
    local name = Get(model.config, "anchorName")
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$"):lower()
    if name == "essential" or name == "utility" then return name end
    if name == "buff" or name == "buffs" then return "buff" end
end

local function GroupName(ctx, model, index, rowIndex)
    local name = Get(model.config, "anchorName")
    if type(name) == "string" and name ~= "" and #name < 256 then
        ctx:Use(Path(model.path, "anchorName"))
        if #model.rows == 1 then return name end
        return string.format(L["%s (Row %d)"], name, rowIndex)
    end
    return string.format(L["Skiron Anchor %d, Row %d"], index, rowIndex)
end

local function FontSize(value, width, height)
    if not Number(value, 0.01, 100) then return nil end
    return value > 1 and value or math.max(1, math.floor(math.min(width, height) * value + 0.5))
end

local function ConvertSpec(ctx, specID, source, base, general)
    local version = Get(source, "profileVersion")
    if version ~= nil and (not Number(version, 0, 2) or version ~= math.floor(version)) then return false, "invalid_profile_version" end
    ctx:Use(Path(base, "profileVersion"))
    local models = {}
    local anchors = Get(source, "anchorConfig")
    AddModels(ctx, models, anchors, Path(base, "anchorConfig"), 0, general)
    AddModels(ctx, models, Get(source, "buffBarsAnchorConfig"), Path(base, "buffBarsAnchorConfig"), 200, general)
    AddModels(ctx, models, Get(ctx.globalAnchors, "globalAnchorConfig"), "globalAnchors.globalAnchorConfig", 100, general)
    for index = 1, 3 do
        if not models[index] then models[index] = { config = DefaultAnchor(index), path = Path(Path(base, "anchorConfig"), index), entries = {} } end
    end
    local spellConfig = Get(source, "spellConfig")
    local categories = Enum.CooldownViewerCategory
    local tracking = { version = 1, specID = specID, entries = {} }
    local trackedIDs = {}
    if type(spellConfig) == "table" then
        local total = 0
        for configKey, config in pairs(spellConfig) do
            total = total + 1
            if total > 4096 then return false, "invalid_profile_data" end
            local spellPath = Path(Path(base, "spellConfig"), configKey)
            local spellID = ID(Get(config, "spellID"))
            local sources, groupConfigs = Get(config, "source"), Get(config, "anchorGroup")
            if spellID and type(sources) == "table" and type(groupConfigs) == "table" then
                local choices = {}
                for category, groupIndex in pairs(sources) do
                    category, groupIndex = tonumber(category), ID(groupIndex)
                    local sourceKind = category == categories.TrackedBuff and "buff"
                        or category == categories.Essential and "essential"
                        or category == categories.Utility and "utility"
                    local group = groupIndex and Get(groupConfigs, groupIndex)
                    local model = groupIndex and models[groupIndex]
                    if sourceKind and model and type(group) == "table" then
                        local target = BuiltInTarget(model)
                        choices[#choices + 1] = {
                            kind = target or (sourceKind == "buff" and "buffGroups" or "cooldownGroups"),
                            family = sourceKind == "buff" and "buff" or "cooldown",
                            index = groupIndex, category = category, config = group,
                            targetCategory = target == "essential" and categories.Essential
                                or target == "utility" and categories.Utility
                                or target == "buff" and categories.TrackedBuff or category,
                        }
                    end
                end
                table.sort(choices, function(a, b)
                    if a.index ~= b.index then return a.index < b.index end
                    return a.category < b.category
                end)
                -- Only anchors named for built-in rows stay ungrouped. Other
                -- named anchors retain their own CDM groups.
                local usedKinds = {}
                for _, choice in ipairs(choices) do
                    if not usedKinds[choice.family] then
                        usedKinds[choice.family] = choice.index
                        local groupPath = Path(Path(spellPath, "anchorGroup"), choice.index)
                        models[choice.index].entries[#models[choice.index].entries + 1] = {
                            id = spellID, kind = choice.kind,
                            order = Number(Get(choice.config, "order"), -100000, 100000) or 999,
                            config = choice.config, path = groupPath,
                        }
                        local cooldownID = ID(Get(config, "cooldownID"))
                        local trackingID = cooldownID or -spellID
                        if not trackedIDs[trackingID] then
                            tracking.entries[#tracking.entries + 1] = {
                                cooldownID = cooldownID, spellID = spellID, category = choice.targetCategory,
                            }
                            trackedIDs[trackingID] = true
                        end
                        if BuiltInTarget(models[choice.index]) then
                            ctx:Use(Path(models[choice.index].path, "anchorName"))
                        end
                        ctx:Use(Path(spellPath, "spellID"))
                        ctx:Use(Path(spellPath, "cooldownID"))
                        ctx:Use(Path(Path(spellPath, "source"), choice.category))
                        if Number(Get(choice.config, "order"), -100000, 100000) then ctx:Use(Path(groupPath, "order")) end
                    elseif usedKinds[choice.family] == choice.index then
                        ctx:Use(Path(Path(spellPath, "source"), choice.category))
                    else
                        ctx:Warn(L["Duplicate Skiron spell assignments use the first compatible group in each viewer."])
                    end
                end
            end
        end
    end
    local slots = Get(Get(source, "customConfig"), "slotConfig")
    if type(slots) == "table" and CDM.CONST.GetTrinketSentinelForSlot then
        for key, config in pairs(slots) do
            local slot, index = ID(Get(config, "slotID")), ID(Get(config, "anchorGroup"))
            if (slot == 13 or slot == 14) and models[index]
                and Get(config, "useLoadClass") ~= true and Get(config, "useLoadRole") ~= true and Get(config, "useLoadRace") ~= true then
                models[index].entries[#models[index].entries + 1] = {
                    id = CDM.CONST.GetTrinketSentinelForSlot(slot),
                    kind = BuiltInTarget(models[index]) == "essential" and "essential" or "cooldownGroups",
                    order = Number(Get(config, "order"), -100000, 100000) or 999,
                }
                ctx.data.cooldownTrinkets = ctx.data.cooldownTrinkets or {}
                ctx.data.cooldownTrinkets[specID] = ctx.data.cooldownTrinkets[specID] or {}
                ctx.data.cooldownTrinkets[specID][slot] = true
                local path = Path(Path(Path(base, "customConfig"), "slotConfig"), key)
                for _, field in ipairs({ "slotID", "anchorGroup", "order", "id", "iconType", "spellID", "useLoadClass", "useLoadRole", "useLoadRace",
                    "loadClasses", "loadRoles", "loadRaces" }) do ctx:Use(Path(path, field)) end
            end
        end
    end
    for _, model in pairs(models) do
        table.sort(model.entries, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            if a.id ~= b.id then return a.id < b.id end
            return a.kind < b.kind
        end)
        MakeRows(ctx, model)
    end
    AddBarModels(ctx, models, specID, source, base)
    local grouped = { cooldownGroups = {}, buffGroups = {} }
    for _, index in ipairs(NumericKeys(models)) do
        local model = models[index]
        for rowIndex, row in ipairs(model.rows) do
            for _, kind in ipairs({ "cooldownGroups", "buffGroups" }) do
                local spells, mixed, firstSlot, lastSlot = {}, false
                for position = row.start, row.start + row.count - 1 do
                    local entry = model.entries[position]
                    if entry.kind == kind then
                        if not grouped[kind][entry.id] then
                            spells[#spells + 1] = entry.id
                            grouped[kind][entry.id] = true
                            firstSlot, lastSlot = firstSlot or (position - row.start), position - row.start
                        else
                            ctx:Warn(L["Duplicate Skiron spell assignments use the first compatible group in each viewer."])
                        end
                    elseif entry.kind == "cooldownGroups" or entry.kind == "buffGroups" then
                        mixed = true
                    end
                end
                if #spells > 0 then
                    local resolved = ResolvePosition(ctx, models, index, {})
                    ctx.data[kind] = ctx.data[kind] or {}
                    ctx.data[kind][specID] = ctx.data[kind][specID] or {}
                    local step = row.width + model.spacing
                    local firstX = resolved.x - row.totalWidth / 2 + row.width / 2
                    local direction = 1
                    if model.grow == "RIGHT" then firstX = resolved.x - model.width / 2 + row.width / 2
                    elseif model.grow == "LEFT" then firstX, direction = resolved.x + model.width / 2 - row.width / 2, -1 end
                    local firstCenter = firstX + direction * firstSlot * step
                    local lastCenter = firstX + direction * lastSlot * step
                    local group = {
                        name = GroupName(ctx, model, index, rowIndex),
                        spells = spells, iconWidth = row.width, iconHeight = row.height,
                        spacing = model.spacing, grow = "CENTER_H", anchorTarget = model.anchorTarget,
                        anchorPoint = "CENTER", anchorRelativeTo = model.anchorRelativeTo,
                        offsetX = (firstCenter + lastCenter) / 2,
                        offsetY = model.y + (model.up and (-model.height / 2 + row.y + row.height / 2)
                            or (model.height / 2 - row.y - row.height / 2)),
                    }
                    if model.grow == "RIGHT" then group.grow, group.offsetX = "RIGHT", firstCenter - row.width / 2
                    elseif model.grow == "LEFT" then group.grow, group.offsetX = "LEFT", firstCenter + row.width / 2 end
                    if kind == "buffGroups" and group.anchorTarget == "utility" then
                        group.anchorTarget, group.anchorRelativeTo = "screen", "CENTER"
                        group.offsetX, group.offsetY = 0, -100 - ((index - 1) % 100) * 60
                        ctx:Warn(L["CDM buff groups cannot anchor to the utility viewer; a fallback screen position was used."])
                    end
                    local fontValue = Get(row.config, "cooldownFontSize")
                    local fontPath = Path(row.path, "cooldownFontSize")
                    if fontValue == nil then fontValue, fontPath = Get(general, "cooldownFontSize"), "globalSettings.cooldownFontSize" end
                    group.cooldownFontSize = FontSize(fontValue, row.width, row.height)
                    if group.cooldownFontSize then ctx:Use(fontPath) end
                    local buff = kind == "buffGroups"
                    MapFields(ctx, row.config, row.path, group, {
                        { buff and "applicationsFontSize" or "chargeFontSize", buff and "countFontSize" or "chargeFontSize", "number", 1, 100 },
                        { buff and "applicationsColour" or "chargeColour", buff and "countColor" or "chargeColor", "color" },
                        { buff and "applicationsRelativePoint" or "chargeRelativePoint", buff and "countPosition" or "chargePosition", "point" },
                        { buff and "applicationsXOffset" or "chargeXOffset", buff and "countOffsetX" or "chargeOffsetX", "number", -100, 100 },
                        { buff and "applicationsYOffset" or "chargeYOffset", buff and "countOffsetY" or "chargeOffsetY", "number", -100, 100 },
                    })
                    if mixed then ctx:Warn(L["Mixed cooldown and buff rows became separate CDM groups; review their spacing."]) end
                    local groups = ctx.data[kind][specID]
                    groups[#groups + 1] = group
                    ctx.groupCount = ctx.groupCount + 1
                end
            end
        end
    end
    local ordered = { essential = {}, utility = {} }
    local seen = {}
    local layout = {}
    for _, index in ipairs(NumericKeys(models)) do
        local model = models[index]
        for _, entry in ipairs(model.entries) do
            if (entry.kind == "essential" or entry.kind == "utility") and not seen[entry.id] then
                ordered[entry.kind][#ordered[entry.kind] + 1] = entry.id
                seen[entry.id] = true
            end
            if not layout[entry.kind] and model.rows[1] then
                layout[entry.kind] = model
            end
        end
    end
    if #ordered.essential + #ordered.utility > 0 then
        local order = ordered.essential
        for _, spellID in ipairs(ordered.utility) do order[#order + 1] = spellID end
        ctx.data.ungroupedCooldownOrder = ctx.data.ungroupedCooldownOrder or {}
        ctx.data.ungroupedCooldownOrder[specID] = order
    end
    -- Viewer sizes are profile-wide. Use the active spec's exported rows when
    -- a class export contains different layouts for multiple specializations.
    if specID == ctx.currentSpecID or not ctx.layoutSpecID then
        local function Size(model, rowIndex, key)
            local row = model and model.rows[rowIndex]
            if row then
                ctx.data[key] = {
                    w = math.max(20, math.min(100, row.width)),
                    h = math.max(20, math.min(100, row.height)),
                }
            end
        end
        Size(layout.essential, 1, "sizeEssRow1")
        Size(layout.essential, 2, "sizeEssRow2")
        Size(layout.utility, 1, "sizeUtility")
        Size(layout.buff, 1, "sizeBuff")
        if layout.essential then
            ctx.data.maxRowEss = math.min(20, math.floor(Number(Get(layout.essential.rows[1].config, "limit"), 1, 1000) or 8))
        end
        if layout.utility then
            ctx.data.maxRowUtil = math.min(20, math.floor(Number(Get(layout.utility.rows[1].config, "limit"), 1, 1000) or 8))
        end
        local spacingModel = layout.essential or layout.utility or layout.buff
        if spacingModel then ctx.data.spacing = math.max(-1, math.min(30, spacingModel.spacing)) end
        ctx.layoutSpecID = specID
    end
    ctx.trackingBySpec = ctx.trackingBySpec or {}
    ctx.trackingBySpec[specID] = tracking
    ctx.specIDs[#ctx.specIDs + 1] = specID
    return true
end

local function CollectSkipped(data, ctx)
    local result, visited, nodes = {}, {}, 0
    local function Walk(value, path, depth)
        if ctx.used[path] then return end
        nodes = nodes + 1
        if type(value) ~= "table" or depth > 16 or nodes > 50000 or visited[value] then
            result[#result + 1] = path
            return
        end
        visited[value] = true
        for key, child in pairs(value) do Walk(child, Path(path, key), depth + 1) end
        visited[value] = nil
    end
    for key, value in pairs(data) do Walk(value, tostring(key), 0) end
    table.sort(result)
    return result
end

function Importer:Matches(profileString)
    return type(profileString) == "string" and profileString:gsub("[%s%z]", ""):find("^!SCM") ~= nil
end

function Importer:Convert(profileString)
    if type(profileString) ~= "string" then return nil, "invalid_profile_data" end
    local normalized = profileString:gsub("[%s%z]", "")
    local version, exportType, encoded = normalized:match("^!SCM:(%d+):(%d+)!(.+)$")
    if not version then return nil, "invalid_profile_data" end
    if tonumber(version) ~= 1 then return nil, "invalid_profile_version" end
    exportType = tonumber(exportType)
    local classList, classSpecs = ns.GroupEditorShared.GetClassCatalog()
    local specClasses = {}
    for _, class in ipairs(classList) do
        for _, spec in ipairs(classSpecs[class.classTag] or {}) do specClasses[spec.specID] = class.classTag end
    end
    if exportType > 4 and not specClasses[exportType] then return nil, "invalid_profile_data" end
    local payload, decodeErr = CDM.ProfileIO:DecodePayload(encoded)
    if not payload then return nil, decodeErr end
    if exportType ~= 2 and exportType ~= 3 then
        for _, section in ipairs({ "profileData", "globalSettings", "castBarSettings", "resourceBarSettings", "globalAnchors" }) do
            if payload[section] ~= nil and type(payload[section]) ~= "table" then return nil, "invalid_profile_data" end
        end
    end
    local ctx = Context()
    ctx.specClasses, ctx.currentSpecID = specClasses, CDM:GetCurrentSpecID()
    local sections = payload.profileData ~= nil or payload.globalSettings ~= nil or payload.castBarSettings ~= nil
        or payload.resourceBarSettings ~= nil or payload.globalAnchors ~= nil
    local general = exportType == 2 and payload or sections and payload.globalSettings or nil
    ctx.globalAnchors = sections and payload.globalAnchors or nil
    if general ~= nil and type(general) ~= "table" then return nil, "invalid_profile_data" end
    if exportType == 2 then
        -- Use the same paths as sectioned exports when collecting the report.
        payload = { globalSettings = payload }
    end
    if general then ConvertGeneral(ctx, general, "globalSettings") end
    local castBar = sections and payload.castBarSettings or nil
    if castBar ~= nil and type(castBar) ~= "table" then return nil, "invalid_profile_data" end
    ctx.rootCast = castBar
    if castBar then ConvertCastBar(ctx, castBar, "castBarSettings") end
    local resources = sections and payload.resourceBarSettings or nil
    if resources ~= nil and type(resources) ~= "table" then return nil, "invalid_profile_data" end
    if resources and resources.resourceBar ~= nil then
        if type(resources.resourceBar) ~= "table" then return nil, "invalid_profile_data" end
        ctx.rootResources = resources.resourceBar
        ConvertResources(ctx, resources.resourceBar, "resourceBarSettings.resourceBar")
    end
    if exportType ~= 2 and exportType ~= 3 then
        local data = sections and payload.profileData or payload
        local base = sections and "profileData" or "profile"
        if data ~= nil and type(data) ~= "table" then return nil, "invalid_profile_data" end
        data = data or {}
        local function Spec(specID, config, path)
            if type(config) ~= "table" then return true end
            return ConvertSpec(ctx, specID, config, path, general)
        end
        if exportType == 0 or exportType == 4 then
            for _, class in ipairs(classList) do
                local configs = Get(data, class.classTag)
                for _, specID in ipairs(NumericKeys(configs)) do
                    if specClasses[specID] == class.classTag then
                        local ok, err = Spec(specID, Get(configs, specID), Path(Path(base, class.classTag), specID))
                        if not ok then return nil, err end
                    end
                end
            end
        elseif exportType == 1 then
            for _, specID in ipairs(NumericKeys(data)) do
                if specClasses[specID] then
                    local ok, err = Spec(specID, Get(data, specID), Path(base, specID))
                    if not ok then return nil, err end
                end
            end
        else
            local ok, err = Spec(exportType, data, base)
            if not ok then return nil, err end
        end
        -- Bare legacy exports need matching report paths, too.
        if not sections then payload = { profile = data } end
    end
    local selected
    for _, record in ipairs(ctx.records) do
        if record.specID == ctx.currentSpecID then selected = record; break end
        if not selected then selected = record end
    end
    if selected and (selected.resources.data or selected.cast.data) then
        ConvertBarGeometry(ctx, selected)
        if #ctx.records > 1 then
            ctx:Warn(string.format(L["Resource and cast-bar settings use specialization %d. Import separately for other specializations with different bar layouts."], selected.specID))
        end
    end
    if not next(ctx.data) then return nil, "no_compatible_settings" end
    ctx:Warn(L["Only supported exported settings were converted. Skiron custom timers, effect rules, visibility conditions and dynamic layout behavior are not imported."])
    ctx.skipped = CollectSkipped(payload, ctx)
    ctx.skippedCount = #ctx.skipped
    table.sort(ctx.specIDs)
    local tracking = ctx.trackingBySpec and (ctx.trackingBySpec[ctx.currentSpecID] or ctx.trackingBySpec[ctx.specIDs[1]])
    return {
        profile_export_version = 1, addon = "CDM", profileName = L["SkironCDM Imported"], data = ctx.data,
        blizzardTracking = tracking and #tracking.entries > 0 and tracking or nil,
    }, nil, ctx
end
