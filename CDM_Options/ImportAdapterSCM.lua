local Runtime = _G["CDM"]
if not Runtime then return end
local CDM = Runtime
local ns = CDM._OptionsNS
local L = CDM.L
local CDM_C = CDM.CONST
local LSM = LibStub("LibSharedMedia-3.0")
local Adapters = ns.ImportAdapters

local math_floor = math.floor
local math_ceil = math.ceil
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local table_sort = table.sort
local IsSafeNumber = CDM.IsSafeNumber

-- SkironCooldownManager (SCM) v1.6.4 exports. Format notes and the field
-- mapping are in docs/scm_mapping.md; the import converts the active spec only.
local SCM_DATA_VERSION = 1
local EXPORT_ALL, EXPORT_CLASS, EXPORT_GLOBAL_SETTINGS, EXPORT_GLOBAL_ANCHORS, EXPORT_EVERYTHING = 0, 1, 2, 3, 4
-- SCM group numbers: 1-99 per spec, 101+ account-wide, 201+ buff bars (Modules/utils.lua:5-9).
local GLOBAL_GROUP_FIRST = 101
local BUFF_BAR_GROUP_FIRST = 201
local SCM_DEFAULT_GLOW_COLOR = { r = 0.95, g = 0.95, b = 0.32, a = 1 }
local WHITE = { r = 1, g = 1, b = 1, a = 1 }

local VALID_POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local GLOW_TYPES = { Pixel = "pixel", Autocast = "autocast", Button = "button", Proc = "proc" }

local COOLDOWN_GROUP_TARGETS = {
    screen = true, playerFrame = true, essential = true, utility = true, buff = true, castBar = true, resources = true,
}
local BUFF_GROUP_TARGETS = {
    screen = true, playerFrame = true, essential = true, buff = true, castBar = true, resources = true,
}

local CATEGORY = Enum and Enum.CooldownViewerCategory or {}
local function CategorySet(...)
    local set = {}
    for i = 1, select("#", ...) do
        local value = CATEGORY[select(i, ...)]
        if value ~= nil then set[value] = true end
    end
    return set
end
local ESSENTIAL_CATS = CategorySet("Essential", "SpecAgnosticEssential", "EquipSlotEssential")
local UTILITY_CATS = CategorySet("Utility")
local BUFF_CATS = CategorySet("TrackedBuff", "SpecAgnosticTracked", "EquipSlotTracked")
local BAR_CATS = CategorySet("TrackedBar")

-- SCM power tokens that have one clear ACDM bar.
local POWER_TOKEN_BARS = {
    MANA = "Mana", RAGE = "Rage", ENERGY = "Energy", FOCUS = "Focus", RUNIC_POWER = "RunicPower",
    RUNES = "Runes", HOLY_POWER = "HolyPower", COMBO_POINTS = "ComboPoints", SOUL_SHARDS = "SoulShards",
    LUNAR_POWER = "LunarPower", MAELSTROM = "Maelstrom", MAELSTROM_WEAPON = "MaelstromWeapon",
    CHI = "Chi", INSANITY = "Insanity", ARCANE_CHARGES = "ArcaneCharges", FURY = "Fury",
    ESSENCE = "Essence", SOUL_FRAGMENTS_VENGEANCE = "SoulFragments", STAGGER = "Stagger",
    TIP_OF_THE_SPEAR = "TipOfTheSpear",
}
-- ACDM-only trackers that SCM's secondary bar never represents.
local ACDM_ONLY_BARS = { IgnorePain = true, Ironfur = true, FireBlast = true, Flurry = true, Prescience = true }

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Num(value)
    if type(value) == "number" and value == value then return value end
    return nil
end

local function Round(value)
    return math_floor(value + 0.5)
end

-- CBOR keeps number keys as numbers, but SCM also accepts string spec keys.
local function Lookup(t, key)
    if type(t) ~= "table" or key == nil then return nil end
    local value = t[key]
    if value == nil then value = t[tostring(key)] end
    if value == nil and type(key) == "string" then
        local n = tonumber(key)
        if n then value = t[n] end
    end
    return value
end

local function NumericKeys(t)
    local keys = {}
    if type(t) ~= "table" then return keys end
    for key in pairs(t) do
        local n = tonumber(key)
        if n then keys[#keys + 1] = n end
    end
    table_sort(keys)
    return keys
end

-- SCM stores colours both as {r, g, b, a} and as {1, 2, 3, 4} arrays.
local function Color(c)
    if type(c) ~= "table" then return nil end
    local r, g, b, a = Num(c.r or c[1]), Num(c.g or c[2]), Num(c.b or c[3]), Num(c.a or c[4])
    if not (r and g and b) then return nil end
    return { r = r, g = g, b = b, a = a or 1 }
end

local function SameColor(a, b)
    if not a or not b then return false end
    return math_abs(a.r - b.r) < 0.005 and math_abs(a.g - b.g) < 0.005
        and math_abs(a.b - b.b) < 0.005 and math_abs((a.a or 1) - (b.a or 1)) < 0.005
end

local function Point(value)
    if type(value) == "string" and VALID_POINTS[value] then return value end
    return nil
end

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName and IsSafeNumber(spellID) then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then return name end
    end
    return string.format(L["Spell %s"], tostring(spellID))
end

local function SpecName(specID)
    local _, name = GetSpecializationInfoByID(specID)
    return name or tostring(specID)
end

-- SCM font sizes <= 1 are a fraction of the icon size (Modules/skinning.lua:114-120).
local function FontSize(value, w, h)
    value = Num(value)
    if not value or value <= 0 then return nil end
    if value <= 1 then
        if not (w and h) then return nil end
        return math_max(1, Round(math_min(w, h) * value))
    end
    return Round(value)
end

local function RowSize(row)
    if type(row) ~= "table" then return nil end
    local w = Num(row.iconWidth) or Num(row.size)
    local h = Num(row.iconHeight) or Num(row.size)
    if w and h then return Round(w), Round(h) end
    return nil
end

local function Media(kind, name, fallback, report, label)
    if type(name) ~= "string" or name == "" then return nil end
    if LSM:IsValid(kind, name) then return name end
    report:Approx(L["%s \"%s\" is not installed; using %s."], label, name, fallback)
    return fallback
end

local function Outline(value, report)
    if type(value) ~= "string" then return nil end
    local upper = value:upper()
    if upper == "" or upper == "NONE" then return "" end
    local hasSlug = upper:find("SLUG", 1, true) ~= nil
    local result
    if upper:find("THICKOUTLINE", 1, true) then
        result = "THICKOUTLINE"
    elseif upper:find("OUTLINE", 1, true) then
        result = "OUTLINE"
    elseif hasSlug then
        result = "SLUG"
    end
    if not result then
        report:Skip(L["Font outline \"%s\""], value)
    elseif hasSlug and result ~= "SLUG" then
        report:Approx(L["Font outline \"%s\" became \"%s\"."], value, result)
    end
    return result
end

---------------------------------------------------------------------------
-- Screen geometry. ACDM viewers pin a fixed edge to UIParent, so SCM's
-- point/relativePoint pair is turned into offsets from the screen centre.
---------------------------------------------------------------------------

local function PointOffset(point, w, h)
    local x, y = 0, 0
    if point:find("LEFT", 1, true) then x = -w / 2 elseif point:find("RIGHT", 1, true) then x = w / 2 end
    if point:find("TOP", 1, true) then y = h / 2 elseif point:find("BOTTOM", 1, true) then y = -h / 2 end
    return x, y
end

-- Centre of a W x H box whose `point` sits at UIParent's `relPoint` + (x, y).
local function ScreenBoxCenter(ctx, point, relPoint, x, y, w, h)
    local rx, ry = PointOffset(relPoint, ctx.screenW, ctx.screenH)
    local ox, oy = PointOffset(point, w, h)
    return rx + x - ox, ry + y - oy
end

local function GroupExtent(count, limit, iconW, iconH, spacing)
    count = math_max(count, 1)
    local cols = (limit and limit > 0 and limit < count) and limit or count
    local rows = math_ceil(count / cols)
    return cols * iconW + (cols - 1) * spacing, rows * iconH + (rows - 1) * spacing
end

---------------------------------------------------------------------------
-- Anchor strings: frame name, "ANCHOR:n" / "ANCHOR:I|G|BB:n", or a comma
-- list where SCM uses the first visible entry (Modules/utils.lua:221-300).
---------------------------------------------------------------------------

local function ParseAnchorItem(item)
    item = strtrim(item)
    if item == "" then return nil end
    if item == "UIParent" then return { target = "screen" } end

    local kind, id = item:match("^ANCHOR:(%a+):(%d+)$")
    if kind then
        id = tonumber(id)
        kind = kind:upper()
        if kind == "I" then return { group = id } end
        if kind == "BB" then return { target = "buffBar", name = item } end
        return { unsupported = item }
    end
    local n = tonumber(item:match("^ANCHOR:(%d+)$"))
    if n then
        if n >= BUFF_BAR_GROUP_FIRST then return { target = "buffBar", name = item } end
        if n >= GLOBAL_GROUP_FIRST then return { unsupported = item } end
        return { group = n }
    end
    if item == "SCM_CastBar" then return { target = "castBar" } end
    if item:match("^SCM_%a*ResourceBar$") then return { target = "resources" } end
    if item == "PlayerFrame" or item:match("[_%.]Player$") or item:lower():match("unitplayer$") then
        return { target = "playerFrame" }
    end
    return { unsupported = item }
end

local function ParseAnchor(relativeTo)
    if type(relativeTo) ~= "string" or relativeTo == "" then return { target = "screen" } end
    local firstUnsupported
    for item in relativeTo:gmatch("[^,]+") do
        local ref = ParseAnchorItem(item)
        if ref and not ref.unsupported then return ref end
        firstUnsupported = firstUnsupported or ref
    end
    return firstUnsupported or { target = "screen" }
end

local function ReadAnchor(layout)
    local a = type(layout) == "table" and type(layout.anchor) == "table" and layout.anchor or {}
    local point = Point(a[1]) or "CENTER"
    return point, a[2], Point(a[3]) or point, Num(a[4]) or 0, Num(a[5]) or 0
end

---------------------------------------------------------------------------
-- Source data
---------------------------------------------------------------------------

local function SplitHeader(text)
    local compact = text:gsub("[%s%z]", "")
    local version, exportType, body = compact:match("^!SCM:(%d+):(%d+)!(.+)$")
    if not version then return nil end
    return tonumber(version), tonumber(exportType), body
end

-- Returns the active spec's config, plus every spec the string contains.
local function FindSpecConfig(payload, exportType, specID, class)
    local bySpec
    if exportType == EXPORT_ALL or exportType == EXPORT_EVERYTHING then
        bySpec = Lookup(payload.profileData, class)
    elseif exportType == EXPORT_CLASS then
        bySpec = payload.profileData
    else
        bySpec = { [exportType] = payload.profileData }
    end
    if type(bySpec) ~= "table" then return nil, {}, {} end
    return Lookup(bySpec, specID), NumericKeys(bySpec), bySpec
end

local function IsEmptySpec(spec)
    if type(spec) ~= "table" then return true end
    if type(spec.spellConfig) == "table" and next(spec.spellConfig) then return false end
    local custom = spec.customConfig
    if type(custom) == "table" then
        for _, entries in pairs(custom) do
            if type(entries) == "table" and next(entries) then return false end
        end
    end
    return true
end

-- A spec layout flagged useGlobalProfileConfig uses the profile-wide one
-- instead (Modules/utils.lua:343-370).
local function ResolveLayout(specLayouts, profileLayouts, index)
    local layout = Lookup(specLayouts, index)
    if type(layout) ~= "table" then return nil end
    local profileLayout = Lookup(profileLayouts, index)
    if layout.useGlobalProfileConfig and type(profileLayout) == "table" then return profileLayout end
    return layout
end

local function FirstRow(layout)
    local rows = type(layout) == "table" and layout.rowConfig
    return type(rows) == "table" and rows[1] or nil
end

---------------------------------------------------------------------------
-- Members: Blizzard entries (keyed by cooldownID) and SCM custom icons
---------------------------------------------------------------------------

local function ResolveNativeIdentity(member)
    local getInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if getInfo then
        local ok, info = pcall(getInfo, member.cooldownID)
        if ok and type(info) == "table" then
            member.baseSpellID = IsSafeNumber(info.spellID) and info.spellID or nil
            member.identity = CDM_C.ResolveViewerEntryIdentity(info, member.category)
        end
    end
    -- SCM stores the current override spell; ACDM's matching passes accept it too.
    member.identity = member.identity or member.scmSpellID
    return member.identity ~= nil
end

local function MemberKind(member)
    local kind = member.kind
    if kind == "native" then
        if ESSENTIAL_CATS[member.category] or UTILITY_CATS[member.category] then return "cooldown" end
        if BUFF_CATS[member.category] then return "buff" end
        if BAR_CATS[member.category] then return "bar" end
        return nil
    end
    if kind == "slot" or kind == "customSpell" then return "cooldown" end
    if kind == "timer" or kind == "bloodlust" then return "buff" end
    return nil
end

local function SourceCategory(source)
    if type(source) ~= "table" then return nil end
    local keys = NumericKeys(source)
    return keys[1]
end

local function CollectNativeMembers(spec, groups, tracking, report)
    local duplicated, accountWide = 0, 0
    for key, entry in pairs(type(spec.spellConfig) == "table" and spec.spellConfig or {}) do
        if type(entry) == "table" then
            local cooldownID = Num(entry.cooldownID) or tonumber(tostring(key):match("^cooldown:(%d+)$"))
            local category = SourceCategory(entry.source)
            if cooldownID and category ~= nil then
                local member = {
                    kind = "native", cooldownID = cooldownID, category = category,
                    scmSpellID = IsSafeNumber(entry.spellID) and entry.spellID or nil,
                    settings = entry.anchorGroup,
                }
                ResolveNativeIdentity(member)
                -- Matches CaptureBlizzardTracking: equipment slots carry no spellID.
                local isEquipSlot = CATEGORY.EquipSlotEssential ~= nil and category == CATEGORY.EquipSlotEssential
                tracking[#tracking + 1] = {
                    cooldownID = cooldownID,
                    spellID = not isEquipSlot and (member.baseSpellID or member.scmSpellID) or nil,
                    category = category,
                }

                local placed = false
                for _, g in ipairs(NumericKeys(entry.anchorGroup)) do
                    local groupSettings = Lookup(entry.anchorGroup, g)
                    if g >= BUFF_BAR_GROUP_FIRST then
                        -- Tracked bars stay in Blizzard's buff bar viewer.
                    elseif g >= GLOBAL_GROUP_FIRST then
                        accountWide = accountWide + 1
                    elseif not placed then
                        member.order = type(groupSettings) == "table" and Num(groupSettings.order) or 999
                        member.groupSettings = groupSettings
                        groups[g] = groups[g] or { index = g, members = {} }
                        table.insert(groups[g].members, member)
                        placed = true
                    else
                        duplicated = duplicated + 1
                    end
                end
            end
        end
    end
    if duplicated > 0 then
        report:Approx(L["Spells in more than one SCM group kept only their lowest-numbered group (%d)."], duplicated)
    end
    if accountWide > 0 then
        report:Skip(L["Spells in SCM account-wide groups (%d)"], accountWide)
    end
end

local CUSTOM_KINDS = {
    { key = "slotConfig", kind = "slot" },
    { key = "spellConfig", kind = "customSpell" },
    { key = "timerConfig", kind = "timer" },
    { key = "bloodlustConfig", kind = "bloodlust" },
    { key = "itemConfig", kind = "item" },
}

local function CollectCustomMembers(spec, groups, class, report)
    local custom = type(spec.customConfig) == "table" and spec.customConfig or {}
    local items, otherClass, loadRules = 0, 0, 0
    for _, def in ipairs(CUSTOM_KINDS) do
        for _, entry in pairs(type(custom[def.key]) == "table" and custom[def.key] or {}) do
            if type(entry) == "table" then
                local g = Num(entry.anchorGroup)
                local classes = entry.loadClasses
                if entry.useLoadClass and type(classes) == "table" and classes[class] ~= true then
                    otherClass = otherClass + 1
                elseif def.kind == "item" then
                    items = items + 1
                elseif g and g >= GLOBAL_GROUP_FIRST then
                    report:Skip(L["Custom icon %s in an SCM account-wide group"], SpellName(entry.spellID))
                elseif g and g >= 1 then
                    if entry.useLoadRace or entry.useLoadRole or entry.useSpellKnown then
                        loadRules = loadRules + 1
                    end
                    local member = {
                        kind = def.kind, order = Num(entry.order) or 999,
                        spellID = IsSafeNumber(entry.spellID) and entry.spellID or nil,
                        slotID = Num(entry.slotID), duration = Num(entry.duration),
                    }
                    groups[g] = groups[g] or { index = g, members = {} }
                    table.insert(groups[g].members, member)
                end
            end
        end
    end
    if items > 0 then report:Skip(L["Custom item icons such as potions and healthstones (%d)"], items) end
    if otherClass > 0 then report:Skip(L["Custom icons limited to other classes (%d)"], otherClass) end
    if loadRules > 0 then
        report:Approx(L["Custom icons with race or role load conditions now always load (%d)."], loadRules)
    end
end

local function SortMembers(members)
    table_sort(members, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return (a.cooldownID or a.spellID or 0) < (b.cooldownID or b.spellID or 0)
    end)
end

local function ClassifyGroup(group)
    local cooldown, buff, native = 0, 0, 0
    local allEssential, allUtility = true, true
    for _, member in ipairs(group.members) do
        local kind = MemberKind(member)
        member.memberKind = kind
        if kind == "cooldown" then
            cooldown = cooldown + 1
            if member.kind == "native" then
                native = native + 1
                if not ESSENTIAL_CATS[member.category] then allEssential = false end
                if not UTILITY_CATS[member.category] then allUtility = false end
            else
                allUtility = false
            end
        elseif kind == "buff" then
            buff = buff + 1
        end
    end
    if cooldown == 0 and buff == 0 then
        group.kind = nil
    elseif cooldown >= buff then
        group.kind = "cooldown"
    else
        group.kind = "buff"
    end
    group.allEssential = group.kind == "cooldown" and allEssential
    group.allUtility = group.kind == "cooldown" and native > 0 and allUtility
    group.mixed = cooldown > 0 and buff > 0
end

---------------------------------------------------------------------------
-- Conversion
---------------------------------------------------------------------------

local function NewContext(specID, class, report)
    local _, _, _, _, role = GetSpecializationInfoByID(specID)
    return {
        specID = specID, class = class, role = role, report = report,
        screenW = UIParent:GetWidth(), screenH = UIParent:GetHeight(),
        groupMap = {},
    }
end

local function GroupLabel(layout, index)
    local name = type(layout) == "table" and layout.anchorName
    if type(name) == "string" and name ~= "" then return name end
    return string.format(L["SCM group %d"], index)
end

local function ConvertGrow(grow, label, report)
    if grow == nil or grow == "CENTERED" or grow == "CENTER" then return "CENTER_H" end
    if grow == "FIXED" then
        report:Approx(L["%s: fixed-slot layout became centred."], label)
        return "CENTER_H"
    end
    if grow == "LEFT" or grow == "RIGHT" or grow == "UP" or grow == "DOWN" then return grow end
    report:Approx(L["%s: grow direction \"%s\" became centred."], label, tostring(grow))
    return "CENTER_H"
end

-- Text settings for one SCM row, falling back to the profile options.
local function RowText(options, row, w, h)
    row = type(row) == "table" and row or {}
    local chargePoint = Point(row.chargePoint) or Point(options.chargePoint)
    local chargeRelative = Point(row.chargeRelativePoint) or Point(options.chargeRelativePoint)
    return {
        cooldownFontSize = FontSize(row.cooldownFontSize, w, h) or FontSize(options.cooldownFontSize, w, h),
        chargeFontSize = FontSize(row.chargeFontSize, w, h) or FontSize(options.chargeFontSize, w, h),
        chargeColor = Color(row.chargeColour) or Color(options.chargeColour),
        chargePosition = chargePoint,
        chargePointMismatch = chargePoint and chargeRelative and chargeRelative ~= chargePoint,
        chargeOffsetX = Num(row.chargeXOffset) or Num(options.chargeXOffset),
        chargeOffsetY = Num(row.chargeYOffset) or Num(options.chargeYOffset),
        countFontSize = FontSize(row.applicationsFontSize, w, h) or FontSize(options.applicationsFontSize, w, h),
        countPosition = Point(row.applicationsPoint) or Point(options.applicationsPoint),
        countOffsetX = Num(row.applicationsXOffset) or Num(options.applicationsXOffset),
        countOffsetY = Num(row.applicationsYOffset) or Num(options.applicationsYOffset),
    }
end

local function NoteChargeMismatch(text, label, ctx)
    if text.chargePointMismatch and not ctx.chargeMismatchNoted then
        ctx.chargeMismatchNoted = true
        ctx.report:Approx(L["%s: charge text uses one anchor point instead of SCM's point pair."], label)
    end
end

local function NoteExtraRows(layout, label, report)
    local rows = type(layout) == "table" and layout.rowConfig
    if type(rows) == "table" and #rows > 1 then
        report:Approx(L["%s: every row uses row 1's size and text settings."], label)
    end
end

-- Places a group container on screen so the icons land where SCM drew them.
local function SetScreenAnchor(group, ctx, point, relPoint, x, y, count, limit)
    local w, h, spacing = group.iconWidth, group.iconHeight, group.spacing or 1
    local W, H = GroupExtent(count, limit, w, h, spacing)
    local cx, cy = ScreenBoxCenter(ctx, point, relPoint, x, y, W, H)
    -- The container is icon sized; where it sits depends on the grow mode
    -- (CooldownGroups.lua PositionCooldownGroupFrames / Layout.lua DeriveSelfPoint).
    if group.grow == "RIGHT" then
        cx, cy = cx - W / 2, cy + H / 2 - h / 2
    elseif group.grow == "LEFT" then
        cx, cy = cx + W / 2, cy + H / 2 - h / 2
    elseif group.grow == "DOWN" then
        cx, cy = cx - W / 2 + w / 2, cy + H / 2
    elseif group.grow == "UP" then
        cx, cy = cx - W / 2 + w / 2, cy - H / 2
    end
    group.anchorTarget = "screen"
    group.anchorPoint = "CENTER"
    group.anchorRelativeTo = "CENTER"
    group.offsetX = Round(cx)
    group.offsetY = Round(cy)
end

local function SetGroupAnchor(group, layout, label, ctx, allowed, count, limit)
    local report = ctx.report
    local point, relativeTo, relPoint, x, y = ReadAnchor(layout)
    local ref = ParseAnchor(relativeTo)

    local target = ref.target
    if ref.group then
        local mapped = ctx.groupMap[ref.group]
        if mapped and mapped.viewer then
            target = mapped.viewer
        elseif mapped and mapped.acdmGroup and mapped.acdmGroup.anchorTarget then
            -- ACDM groups cannot anchor to each other: reuse the parent's anchor.
            local parent = mapped.acdmGroup
            group.anchorTarget = parent.anchorTarget
            group.anchorPoint = parent.anchorPoint
            group.anchorRelativeTo = parent.anchorRelativeTo
            group.offsetX = Round((parent.offsetX or 0) + x)
            group.offsetY = Round((parent.offsetY or 0) + y)
            report:Approx(L["%s was anchored to %s; it now shares that group's anchor with the offsets added."],
                label, mapped.label)
            return
        elseif mapped then
            -- The parent is converted later in group order, so its anchor is unknown here.
            report:Approx(L["%s was anchored to \"%s\"; it is placed on the screen."], label, mapped.label)
            SetScreenAnchor(group, ctx, "CENTER", "CENTER", x, y, count, limit)
            return
        else
            report:Approx(L["%s was anchored to an SCM group that was not imported; it is placed on the screen."], label)
            SetScreenAnchor(group, ctx, "CENTER", "CENTER", x, y, count, limit)
            return
        end
    end

    if ref.unsupported then
        report:Approx(L["%s was anchored to \"%s\"; it is placed on the screen."], label, ref.unsupported)
        SetScreenAnchor(group, ctx, point, relPoint, x, y, count, limit)
        return
    end
    if target == "screen" then
        SetScreenAnchor(group, ctx, point, relPoint, x, y, count, limit)
        return
    end
    if not allowed[target] then
        report:Approx(L["%s cannot anchor to \"%s\" in CDM; it is placed on the screen."], label, target)
        SetScreenAnchor(group, ctx, "CENTER", "CENTER", 0, 0, count, limit)
        return
    end
    group.anchorTarget = target
    group.anchorPoint = point
    group.anchorRelativeTo = relPoint
    group.offsetX = Round(x)
    group.offsetY = Round(y)
end

local function GroupIdentities(group, ctx, data)
    local spells = {}
    local specID = ctx.specID
    for _, member in ipairs(group.members) do
        if member.memberKind == group.kind then
            if member.kind == "native" then
                if member.identity then spells[#spells + 1] = member.identity end
            elseif member.kind == "slot" and (member.slotID == 13 or member.slotID == 14) then
                data.cooldownTrinkets[specID] = data.cooldownTrinkets[specID] or {}
                data.cooldownTrinkets[specID][member.slotID] = true
                spells[#spells + 1] = CDM_C.GetTrinketSentinelForSlot(member.slotID)
            elseif member.kind == "customSpell" and member.spellID then
                local list = data.customCooldownEntries[specID] or {}
                data.customCooldownEntries[specID] = list
                list[#list + 1] = { id = member.spellID }
                spells[#spells + 1] = member.spellID
            elseif (member.kind == "timer" and member.spellID and member.duration) or member.kind == "bloodlust" then
                local spellID = member.kind == "bloodlust" and 2825 or member.spellID
                local entry = { duration = member.kind == "bloodlust" and 40 or member.duration }
                if member.kind == "bloodlust" then entry.triggerType = "bloodlust" end
                local info = C_Spell.GetSpellInfo(spellID)
                if info then
                    entry.name = info.name
                    entry.icon = info.iconID
                    data.customBuffRegistry[spellID] = entry
                    spells[#spells + 1] = spellID
                end
            end
        end
    end
    return spells
end

local function NewCooldownGroup(name, layout, options)
    local row = FirstRow(layout)
    local defaults = CDM.defaults
    local w, h = RowSize(row)
    w = w or defaults.sizeEssRow1.w
    h = h or defaults.sizeEssRow1.h
    local text = RowText(options, row, w, h)
    return {
        name = name, spells = {},
        spacing = Num(layout and layout.spacing) or 1,
        iconWidth = w, iconHeight = h,
        maxPerRow = Num(row and row.limit),
        cooldownFontSize = text.cooldownFontSize or defaults.cooldownFontSize,
        cooldownColor = Color(options.cooldownFontColor) or { r = 1, g = 1, b = 1, a = 1 },
        chargeFontSize = text.chargeFontSize or defaults.chargeFontSize,
        chargeColor = text.chargeColor or { r = 1, g = 1, b = 1, a = 1 },
        chargePosition = text.chargePosition or "BOTTOMRIGHT",
        chargeOffsetX = text.chargeOffsetX or 0,
        chargeOffsetY = text.chargeOffsetY or 0,
    }, text
end

local function NewBuffGroup(name, layout, options)
    local row = FirstRow(layout)
    local defaults = CDM.defaults
    local w, h = RowSize(row)
    w = w or defaults.sizeBuff.w
    h = h or defaults.sizeBuff.h
    local text = RowText(options, row, w, h)
    return {
        name = name, spells = {},
        spacing = Num(layout and layout.spacing) or 1,
        iconWidth = w, iconHeight = h,
        maxPerRow = Num(row and row.limit),
        cooldownFontSize = text.cooldownFontSize or defaults.buffCooldownFontSize,
        cooldownColor = Color(options.cooldownFontColor) or { r = 1, g = 1, b = 1, a = 1 },
        countFontSize = text.countFontSize or defaults.countFontSize,
        countColor = Color(options.applicationsColour) or { r = 1, g = 1, b = 1, a = 1 },
        countPosition = text.countPosition or "BOTTOMRIGHT",
        countOffsetX = text.countOffsetX or 0,
        countOffsetY = text.countOffsetY or 0,
    }
end

-- Chooses which SCM groups become the Essential, Utility and Buff viewers.
local function AssignViewers(groupList, ctx)
    local essential, utility, buff
    for _, group in ipairs(groupList) do
        local layout = group.layout
        local _, relativeTo = ReadAnchor(layout)
        local ref = ParseAnchor(relativeTo)
        if not essential and group.kind == "cooldown" and group.allEssential and ref.target == "screen" then
            essential = group
        elseif not buff and group.kind == "buff" and ref.target == "screen" then
            buff = group
        end
    end
    if essential then
        for _, group in ipairs(groupList) do
            if group ~= essential and group.kind == "cooldown" and group.allUtility then
                local _, relativeTo = ReadAnchor(group.layout)
                local ref = ParseAnchor(relativeTo)
                if ref.group == essential.index then
                    utility = group
                    break
                end
            end
        end
    end
    if essential then ctx.groupMap[essential.index] = { viewer = "essential", label = essential.label } end
    if utility then ctx.groupMap[utility.index] = { viewer = "utility", label = utility.label } end
    if buff then ctx.groupMap[buff.index] = { viewer = "buff", label = buff.label } end
    return essential, utility, buff
end

local function MemberCount(group)
    local count = 0
    for _, member in ipairs(group.members) do
        if member.memberKind == group.kind then count = count + 1 end
    end
    return count
end

local function ConvertEssentialViewer(group, options, ctx, data, order)
    local report = ctx.report
    local layout = group.layout
    local rows = type(layout.rowConfig) == "table" and layout.rowConfig or {}
    local defaults = CDM.defaults
    local w1, h1 = RowSize(rows[1])
    w1, h1 = w1 or defaults.sizeEssRow1.w, h1 or defaults.sizeEssRow1.h
    local w2, h2 = RowSize(rows[2])
    w2, h2 = w2 or w1, h2 or h1
    local spacing = Num(layout.spacing) or 1
    local limit = Num(rows[1] and rows[1].limit)
    local text1 = RowText(options, rows[1], w1, h1)
    local text2 = RowText(options, rows[2] or rows[1], w2, h2)

    data.sizeEssRow1 = { w = w1, h = h1 }
    data.sizeEssRow2 = { w = w2, h = h2 }
    data.spacing = spacing
    data.maxRowEss = limit
    data.cooldownFontSize = text1.cooldownFontSize
    data.chargeFontSize = text1.chargeFontSize
    data.chargeColor = text1.chargeColor
    data.chargePosition = text1.chargePosition
    data.chargeOffsetX = text1.chargeOffsetX
    data.chargeOffsetY = text1.chargeOffsetY
    data.essRow2CooldownFontSize = text2.cooldownFontSize
    data.essRow2ChargeFontSize = text2.chargeFontSize
    data.essRow2ChargeColor = text2.chargeColor
    data.essRow2ChargePosition = text2.chargePosition
    data.essRow2ChargeOffsetX = text2.chargeOffsetX
    data.essRow2ChargeOffsetY = text2.chargeOffsetY
    NoteChargeMismatch(text1, group.label, ctx)
    if #rows > 2 then
        report:Approx(L["%s: rows 3 and later use row 2's size."], group.label)
    end
    if layout.grow ~= nil and layout.grow ~= "CENTERED" and layout.grow ~= "CENTER" then
        report:Approx(L["%s: the Essential viewer is always centred."], group.label)
    end

    -- ACDM pins the Essential viewer's top centre (Layout.lua AnchorMainLayoutContainer).
    local point, _, relPoint, x, y = ReadAnchor(layout)
    local count = MemberCount(group)
    local rowCount = (limit and limit > 0) and math_ceil(math_max(count, 1) / limit) or 1
    local W = select(1, GroupExtent(count, limit, w1, h1, spacing))
    local H = h1 + (rowCount > 1 and (rowCount - 1) * (h2 + spacing) or 0)
    local cx, cy = ScreenBoxCenter(ctx, point, relPoint, x, y, W, H)
    data.editModePositions[CDM_C.VIEWERS.ESSENTIAL] = { Default = { point = "CENTER", x = Round(cx), y = Round(cy + H / 2) } }
    ctx.essentialHeight = H

    for _, identity in ipairs(GroupIdentities(group, ctx, data)) do order[#order + 1] = identity end
end

local function ConvertUtilityViewer(group, essential, options, ctx, data, order)
    local report = ctx.report
    local layout = group.layout
    local row = FirstRow(layout)
    local defaults = CDM.defaults
    local w, h = RowSize(row)
    w, h = w or defaults.sizeUtility.w, h or defaults.sizeUtility.h
    local limit = Num(row and row.limit)
    local text = RowText(options, row, w, h)

    data.sizeUtility = { w = w, h = h }
    if limit and limit > 0 then
        data.maxRowUtil = limit
        data.utilityWrap = true
    end
    data.utilityCooldownFontSize = text.cooldownFontSize
    data.utilityChargeFontSize = text.chargeFontSize
    data.utilityChargeColor = text.chargeColor
    data.utilityChargePosition = text.chargePosition
    data.utilityChargeOffsetX = text.chargeOffsetX
    data.utilityChargeOffsetY = text.chargeOffsetY
    NoteExtraRows(layout, group.label, report)
    local spacing = Num(layout.spacing)
    if spacing and data.spacing and spacing ~= data.spacing then
        report:Approx(L["%s: CDM uses one icon spacing for Essential and Utility (%d)."], group.label, data.spacing)
    end

    -- ACDM puts Utility's top centre under Essential's bottom centre, minus spacing.
    local point, _, relPoint, x, y = ReadAnchor(layout)
    local count = MemberCount(group)
    local W, H = GroupExtent(count, limit, w, h, Num(layout.spacing) or 1)
    local essW = essential and select(1, GroupExtent(MemberCount(essential), data.maxRowEss,
        data.sizeEssRow1.w, data.sizeEssRow1.h, data.spacing or 1)) or W
    local essH = ctx.essentialHeight or 0
    local rx, ry = PointOffset(relPoint, essW, essH)
    local px, py = rx + x, ry + y + essH / 2 -- relative to Essential's bottom centre
    local ox, oy = PointOffset(point, W, H)
    data.utilityAnchor = "essential"
    data.utilityXOffset = Round(px - ox)
    data.utilityYOffset = Round(py - oy + H / 2 + (data.spacing or 1))
    if point ~= "TOP" or relPoint ~= "BOTTOM" then
        report:Approx(L["%s: position under the Essential viewer is approximate."], group.label)
    end

    for _, identity in ipairs(GroupIdentities(group, ctx, data)) do order[#order + 1] = identity end
end

local function ConvertBuffViewer(group, options, ctx, data)
    local report = ctx.report
    local layout = group.layout
    local row = FirstRow(layout)
    local defaults = CDM.defaults
    local w, h = RowSize(row)
    w, h = w or defaults.sizeBuff.w, h or defaults.sizeBuff.h
    local text = RowText(options, row, w, h)

    data.sizeBuff = { w = w, h = h }
    data.buffCooldownFontSize = text.cooldownFontSize
    data.countFontSize = text.countFontSize
    data.countPositionMain = text.countPosition
    data.countOffsetXMain = text.countOffsetX
    data.countOffsetYMain = text.countOffsetY
    NoteExtraRows(layout, group.label, report)
    if Num(row and row.limit) then
        report:Approx(L["%s: the Buff viewer has no per-row limit."], group.label)
    end

    -- ACDM pins the Buff viewer's bottom centre.
    local point, _, relPoint, x, y = ReadAnchor(layout)
    local W, H = GroupExtent(MemberCount(group), Num(row and row.limit), w, h, Num(layout.spacing) or 1)
    local cx, cy = ScreenBoxCenter(ctx, point, relPoint, x, y, W, H)
    data.editModePositions[CDM_C.VIEWERS.BUFF] = { Default = { point = "CENTER", x = Round(cx), y = Round(cy - H / 2) } }

    local natives, customOrder = 0, {}
    for _, member in ipairs(group.members) do
        if member.memberKind == "buff" then
            if member.kind == "native" then
                natives = natives + 1
            else
                customOrder[#customOrder + 1] = { member = member, afterNative = natives }
            end
        end
    end
    local ids = GroupIdentities(group, ctx, data)
    local registered = {}
    for _, spellID in ipairs(ids) do registered[spellID] = true end
    local list = {}
    for _, entry in ipairs(customOrder) do
        local spellID = entry.member.kind == "bloodlust" and 2825 or entry.member.spellID
        if spellID and registered[spellID] then
            list[#list + 1] = { spellID = spellID, afterNative = entry.afterNative }
        end
    end
    if #list > 0 then data.ungroupedCustomBuffOrder[ctx.specID] = list end
    if natives > 1 then
        report:Approx(L["%s: Blizzard buffs in the Buff viewer keep Blizzard's order."], group.label)
    end
end

local function ConvertGroups(spec, options, ctx, data)
    local report = ctx.report
    local groups = {}
    local tracking = {}
    CollectNativeMembers(spec, groups, tracking, report)
    CollectCustomMembers(spec, groups, ctx.class, report)

    local groupList = {}
    local strayCooldowns, strayBuffs = 0, 0
    for _, g in ipairs(NumericKeys(groups)) do
        local group = groups[g]
        group.layout = ResolveLayout(spec.anchorConfig, options.anchorConfig, g) or {}
        group.label = GroupLabel(group.layout, g)
        SortMembers(group.members)
        ClassifyGroup(group)
        if group.kind then
            groupList[#groupList + 1] = group
            if group.mixed then
                for _, member in ipairs(group.members) do
                    if member.memberKind ~= group.kind and member.memberKind ~= "bar" then
                        if member.memberKind == "cooldown" then strayCooldowns = strayCooldowns + 1
                        else strayBuffs = strayBuffs + 1 end
                    end
                end
            end
        end
    end
    if strayCooldowns + strayBuffs > 0 then
        report:Approx(L["Icons that shared a group with the other type (cooldowns with buffs) were left out of it (%d)."],
            strayCooldowns + strayBuffs)
    end

    local essential, utility, buffViewer = AssignViewers(groupList, ctx)
    local order = {}
    if essential then ConvertEssentialViewer(essential, options, ctx, data, order) end
    if utility then ConvertUtilityViewer(utility, essential, options, ctx, data, order) end
    if buffViewer then ConvertBuffViewer(buffViewer, options, ctx, data) end
    if #order > 0 then data.ungroupedCooldownOrder[ctx.specID] = order end

    local cooldownGroups, buffGroups = {}, {}
    for _, group in ipairs(groupList) do
        if not ctx.groupMap[group.index] then
            local layout = group.layout
            local row = FirstRow(layout)
            local count = MemberCount(group)
            local acdmGroup
            if group.kind == "cooldown" then
                local text
                acdmGroup, text = NewCooldownGroup(group.label, layout, options)
                NoteChargeMismatch(text, group.label, ctx)
                cooldownGroups[#cooldownGroups + 1] = acdmGroup
                ctx.groupMap[group.index] = { acdmGroup = acdmGroup, label = group.label }
            else
                acdmGroup = NewBuffGroup(group.label, layout, options)
                buffGroups[#buffGroups + 1] = acdmGroup
                ctx.groupMap[group.index] = { acdmGroup = acdmGroup, label = group.label }
            end
            acdmGroup.grow = ConvertGrow(layout.grow, group.label, report)
            NoteExtraRows(layout, group.label, report)
            SetGroupAnchor(acdmGroup, layout, group.label, ctx,
                group.kind == "cooldown" and COOLDOWN_GROUP_TARGETS or BUFF_GROUP_TARGETS,
                count, Num(row and row.limit))
            acdmGroup.spells = GroupIdentities(group, ctx, data)
        end
    end
    if #cooldownGroups > 0 then data.cooldownGroups[ctx.specID] = cooldownGroups end
    if #buffGroups > 0 then data.buffGroups[ctx.specID] = buffGroups end

    return tracking, #groupList
end

local function ConvertIconStyle(options, data, report)
    local zoom = Num(options.iconZoom)
    if zoom then
        data.zoomAmount = zoom
        data.zoomIcons = zoom > 0
    end
    -- SCM always draws a solid border.
    data.borderFile = "1 Pixel"
    data.borderSize = Num(options.borderSize)
    data.borderColor = Color(options.borderColor)
    data.swipeColor = Color(options.normalSwipeColor)
    if type(options.pressOverlay) == "boolean" then data.pressOverlayEnabled = options.pressOverlay end

    local font = Media("font", options.cooldownFont, "Expressway", report, L["Font"])
    data.textFont = font
    local outline = options.cooldownFontOutline
    if outline ~= nil then data.textFontOutline = Outline(outline, report) end
    data.cooldownColor = Color(options.cooldownFontColor)
    data.buffCooldownColor = Color(options.cooldownFontColor)
    data.countColor = Color(options.applicationsColour)
    if options.chargeFont and options.cooldownFont and options.chargeFont ~= options.cooldownFont then
        report:Approx(L["CDM uses one font for all text; the cooldown font was used."])
    end
    if type(options.cooldownBreakpoints) == "table" and #options.cooldownBreakpoints > 0 then
        report:Skip(L["Custom cooldown time formats"])
    end
    if options.disableGCD then
        report:Skip(L["Hide GCD swipe"])
    end
    if options.hideWhileMounted or options.hideOutOfCombat or options.hideWhileDead
        or options.hideWhileInVehicle or options.hideWhileResting or options.useCustomVisibilityCondition then
        report:Skip(L["Icon visibility conditions (mounted, out of combat, dead, vehicle, resting, macro)"])
    end
end

local function ConvertGlow(options, data, report)
    if options.useCustomGlow then
        local glowType = GLOW_TYPES[options.glowType]
        if glowType then
            data.glowType = glowType
            local typeOptions = type(options.glowTypeOptions) == "table" and options.glowTypeOptions[options.glowType]
            local color = typeOptions and Color(typeOptions.glowColor)
            local isDefault = SameColor(color, SCM_DEFAULT_GLOW_COLOR) or (glowType == "proc" and SameColor(color, WHITE))
            if color and not isDefault then
                data.glowColorMode = "custom"
                data.glowColor = color
            end
        else
            report:Skip(L["Glow type \"%s\""], tostring(options.glowType))
        end
    end
    local all = type(options.glowTypeOptions) == "table" and options.glowTypeOptions or {}
    local pixel, autocast, button = all.Pixel, all.Autocast, all.Button
    if type(pixel) == "table" then
        data.glowPixelLines = Num(pixel.numLines)
        data.glowPixelFrequency = Num(pixel.frequency)
        data.glowPixelLength = Num(pixel.length)
        data.glowPixelThickness = Num(pixel.thickness)
        data.glowPixelXOffset = Num(pixel.xOffset)
        data.glowPixelYOffset = Num(pixel.yOffset)
        if type(pixel.border) == "boolean" then data.glowPixelBorder = pixel.border end
    end
    if type(autocast) == "table" then
        data.glowAutocastParticles = Num(autocast.numParticles)
        data.glowAutocastFrequency = Num(autocast.frequency)
        data.glowAutocastScale = Num(autocast.scale)
    end
    if type(button) == "table" then
        data.glowButtonFrequency = Num(button.frequency)
    end

    local pandemic = options.pandemicGlowOption or "keepPandemicGlow"
    if pandemic == "keepPandemicGlow" then
        data.hidePandemicIndicator = false
    elseif pandemic == "disablePandemicGlow" then
        data.hidePandemicIndicator = true
    elseif pandemic == "replacePandemicGlow" then
        data.hidePandemicIndicator = true
        data.pandemicCustomizationEnabled = true
        data.pandemicBorderEnabled = options.pandemicReplaceWithBorder == true
        data.pandemicBorderColor = Color(options.pandemicBorderColor)
        if options.pandemicReplaceWithBorder and Num(options.pandemicBorderSize) and options.pandemicBorderSize ~= 1 then
            report:Skip(L["Pandemic border thickness"])
        end
        if options.pandemicReplaceWithCustomGlow then
            local glow = CDM:DeepCopy(CDM.defaults.pandemicGlow)
            glow.enabled = true
            glow.style = GLOW_TYPES[options.pandemicGlowType] or glow.style
            local typeOptions = type(options.pandemicCustomGlowTypeOptions) == "table"
                and options.pandemicCustomGlowTypeOptions[options.pandemicGlowType]
            local color = typeOptions and Color(typeOptions.glowColor)
            if color and not SameColor(color, SCM_DEFAULT_GLOW_COLOR) then
                glow.colorMode = "custom"
                glow.r, glow.g, glow.b, glow.alpha = color.r, color.g, color.b, color.a
            end
            data.pandemicGlow = glow
        end
    end
end

-- Per-spell rules SCM keeps on each group entry that CDM cannot express yet.
local function ReportEffectRules(spec, report)
    local glows = 0
    for _, entry in pairs(type(spec.spellConfig) == "table" and spec.spellConfig or {}) do
        if type(entry) == "table" and type(entry.anchorGroup) == "table" then
            for _, settings in pairs(entry.anchorGroup) do
                local rules = type(settings) == "table" and type(settings.effectRules) == "table" and settings.effectRules
                local glow = rules and type(rules.glow) == "table" and rules.glow.rules
                if type(glow) == "table" and #glow > 0 then glows = glows + 1 end
            end
        end
    end
    if glows > 0 then report:Skip(L["Per-spell glow rules (%d)"], glows) end
end

local function ConvertBuffBars(spec, options, ctx, data)
    local report = ctx.report
    local layout = ResolveLayout(spec.buffBarsAnchorConfig, options.buffBarsAnchorConfig, 1)
    if layout then
        local row = FirstRow(layout)
        local w, h = RowSize(row)
        if w and h then
            data.buffBarWidth = w
            data.buffBarHeight = h
        end
        if Num(layout.spacing) then data.buffBarSpacing = layout.spacing end
        local point, relativeTo, relPoint, x, y = ReadAnchor(layout)
        local ref = ParseAnchor(relativeTo)
        if ref.target == "screen" then
            -- ACDM pins the buff bar viewer's top centre when it grows down.
            local cx, cy = ScreenBoxCenter(ctx, point, relPoint, x, y, w or 200, h or 20)
            data.editModePositions[CDM_C.VIEWERS.BUFF_BAR] = {
                Default = { point = "CENTER", x = Round(cx), y = Round(cy + (h or 20) / 2) },
            }
        else
            report:Approx(L["Buff bars were anchored to \"%s\"; they keep CDM's default position."], tostring(relativeTo))
        end
        local extra = 0
        for _, index in ipairs(NumericKeys(spec.buffBarsAnchorConfig)) do
            if index > 1 then extra = extra + 1 end
        end
        if extra > 0 then report:Skip(L["Extra SCM buff bar groups (%d)"], extra) end
    end

    local bar = type(options.buffBarOptions) == "table" and options.buffBarOptions or nil
    if bar then
        data.buffBarTexture = Media("statusbar", bar.barTexture, "Solid", report, L["Buff bar texture"])
        data.buffBarColor = Color(bar.foregroundColor)
        data.buffBarBackgroundColor = Color(bar.backgroundColor)
        if type(bar.hideSpellName) == "boolean" then data.buffBarShowName = not bar.hideSpellName end
        if type(bar.hideDuration) == "boolean" then data.buffBarShowDuration = not bar.hideDuration end
        data.buffBarNameColor = Color(bar.nameColor)
        data.buffBarNameOffsetX = Num(bar.nameXOffset)
        data.buffBarNameOffsetY = Num(bar.nameYOffset)
        data.buffBarDurationColor = Color(bar.durationColor)
        data.buffBarDurationOffsetX = Num(bar.durationXOffset)
        data.buffBarDurationOffsetY = Num(bar.durationYOffset)
        local size = FontSize(bar.fontSize)
        data.buffBarNameFontSize = size
        data.buffBarDurationFontSize = size
        if Num(bar.borderSize) and bar.borderSize ~= (data.borderSize or 1) then
            report:Approx(L["Buff bars use CDM's icon border settings."])
        end
    end

    local content = Num(options.buffBarContent)
    local enum = Enum and Enum.CooldownViewerBarContent
    if content and enum then
        -- SCM labels NameOnly "Bar Only".
        if content == enum.NameOnly then
            data.buffBarIconPosition = "HIDDEN"
        elseif enum.IconOnly and content == enum.IconOnly then
            report:Skip(L["Buff bars showing only the icon"])
        end
    end
end

local function CastBarTarget(relativeTo, ctx)
    local ref = ParseAnchor(relativeTo)
    if ref.target == "resources" or ref.target == "playerFrame" or ref.target == "screen" then return ref.target end
    if ref.group then
        local mapped = ctx.groupMap[ref.group]
        if mapped and (mapped.viewer == "essential" or mapped.viewer == "utility") then return mapped.viewer end
    end
    return nil
end

local function ConvertCastBar(cast, ctx, data)
    if type(cast) ~= "table" then return end
    local report = ctx.report
    if type(cast.enable) == "boolean" then data.castBarEnabled = cast.enable end
    data.castBarHeight = Num(cast.height)
    data.castBarFontSize = Num(cast.fontSize)
    data.castBarTexture = Media("statusbar", cast.texture, "Solid", report, L["Cast bar texture"])
    data.castBarBackgroundColor = Color(cast.bgColor)
    local fg = Color(cast.fgColor)
    data.castBarCastColor = fg
    data.castBarChannelColor = fg
    data.castBarUninterruptibleColor = Color(cast.interruptColor)
    if type(cast.useClassColor) == "boolean" then data.castBarUseClassColor = cast.useClassColor end

    local stages = type(cast.empoweredStageColors) == "table" and cast.empoweredStageColors or {}
    for i = 1, 4 do
        local color = Color(stages[i])
        if color then
            color.a = 1
            data["castBarEmpowerStage" .. i .. "Color"] = color
        end
    end
    if #stages > 0 then
        report:Approx(L["Cast bar empower colours are solid in CDM (SCM tints them); stage 5 was dropped."])
    end

    local a = type(cast.anchors) == "table" and cast.anchors or {}
    local target = CastBarTarget(a[2], ctx)
    if target then
        data.castBarAnchor = target
        data.castBarAnchorPoint = Point(a[1])
        data.castBarTargetPoint = Point(a[3])
        data.castBarOffsetX = Num(a[4])
        data.castBarOffsetY = Num(a[5])
    else
        report:Approx(L["Cast bar was anchored to \"%s\"; it keeps CDM's default anchor."], tostring(a[2]))
    end
    if cast.matchParentWidth then
        data.castBarWidth = 0
        data.castBarAutoWidthSource = target == "utility" and "utility" or "essential"
    else
        data.castBarWidth = Num(cast.width)
    end

    local icon = type(cast.icon) == "table" and cast.icon or {}
    if type(icon.enable) == "boolean" then data.castBarShowIcon = icon.enable end
    if icon.position == "LEFT" or icon.position == "RIGHT" then data.castBarIconPosition = icon.position end
    local spark = type(cast.spark) == "table" and cast.spark or {}
    if type(spark.enable) == "boolean" then data.castBarShowSpark = spark.enable end
    local name = type(cast.spellName) == "table" and cast.spellName or {}
    if type(name.enable) == "boolean" then data.castBarShowSpellName = name.enable end
    if type(name.anchors) == "table" then
        data.castBarNameOffsetX = Num(name.anchors[3])
        data.castBarNameOffsetY = Num(name.anchors[4])
    end
    local timer = type(cast.castDuration) == "table" and cast.castDuration or {}
    if type(timer.enable) == "boolean" then data.castBarShowTimer = timer.enable end
    if type(timer.anchors) == "table" then
        data.castBarTimerOffsetX = Num(timer.anchors[3])
        data.castBarTimerOffsetY = Num(timer.anchors[4])
    end
    if type(cast.ticks) == "table" and cast.ticks.enable then report:Skip(L["Cast bar channel ticks"]) end
end

local function BarClass(barKey, class)
    return barKey == "Mana" and "General" or class
end

local function BarSettings(data, class, barKey)
    local classKey = BarClass(barKey, class)
    data.resourceBarSettings[classKey] = data.resourceBarSettings[classKey] or {}
    local settings = data.resourceBarSettings[classKey][barKey] or {}
    data.resourceBarSettings[classKey][barKey] = settings
    return settings
end

local function ApplyBarOptions(settings, opts, report)
    settings.height = Num(opts.height)
    if opts.matchAnchorWidth then
        settings.width = 0
    else
        settings.width = Num(opts.width)
    end
    settings.barTexture = Media("statusbar", opts.texture, "Solid", report, L["Resource bar texture"])
    if opts.useBackgroundTexture ~= false then
        settings.bgTexture = Media("statusbar", opts.backgroundTexture, "Solid", report, L["Resource bar texture"])
    end
    settings.bgColor = Color(opts.backgroundColor)
    if type(opts.showBorder) == "boolean" then settings.hideBorder = not opts.showBorder end
    settings.borderThickness = Num(opts.backdropSize)
    settings.borderColor = Color(opts.backdropColor)
    if type(opts.showValues) == "boolean" then settings.tagEnabled = opts.showValues end
    settings.tagFontSize = Num(opts.fontSize)
    settings.tagOffsetX = Num(opts.textXOffset)
    settings.tagOffsetY = Num(opts.textYOffset)
    if type(opts.useSmoothPowerUpdates) == "boolean" then settings.smoothBars = opts.useSmoothPowerUpdates end
end

local function DefaultLoad(barKey)
    local defaults = CDM.RESOURCE_BAR_DEFAULTS and CDM.RESOURCE_BAR_DEFAULTS[barKey]
    if defaults and type(defaults.load) == "table" then return CDM:DeepCopy(defaults.load) end
    return {}
end

local function ConvertResources(section, ctx, data)
    local rb = type(section) == "table" and section.resourceBar
    if type(rb) ~= "table" then return end
    local report, specID, class = ctx.report, ctx.specID, ctx.class
    if type(rb.enabled) == "boolean" then data.resourcesEnabled = rb.enabled end

    -- SCM's primary bar shows UnitPowerType; the secondary shows the spec's
    -- class resource (Modules/resourcebar.lua:1334-1476).
    local primaryPT = UnitPowerType("player")
    if class == "DRUID" and CDM.GetDruidPrimaryPowerType then primaryPT = CDM.GetDruidPrimaryPowerType(specID) end
    local primaryKey = CDM.POWER_TYPE_TO_BAR_KEY and CDM.POWER_TYPE_TO_BAR_KEY[primaryPT]
    local secondaryKey
    local powers = CDM.SPEC_POWER_MAP and CDM.SPEC_POWER_MAP[specID]
    if powers ~= nil and type(powers) ~= "table" then powers = { powers } end
    for _, pt in ipairs(powers or {}) do
        local key = CDM.POWER_TYPE_TO_BAR_KEY[pt] or pt
        if key ~= primaryKey and not ACDM_ONLY_BARS[key] then
            secondaryKey = key
            break
        end
    end

    local stack = {}
    local function AddBar(barKey, opts, isPrimary)
        if not barKey or type(opts) ~= "table" then return end
        local settings = BarSettings(data, class, barKey)
        ApplyBarOptions(settings, opts, report)
        local load = DefaultLoad(barKey)
        local shown = opts.enabled ~= false
        if barKey == "Mana" and isPrimary then
            local roles = type(opts.hideManaRoles) == "table" and opts.hideManaRoles or {}
            if roles[ctx.role] and not opts.forceMana then shown = false end
            load.spec = type(load.spec) == "table" and load.spec or {}
            load.spec[specID] = shown or nil
            settings.loadMode = "conditional"
        elseif not shown then
            settings.loadMode = "never"
        end
        if shown then
            if rb.hideOutOfCombat then load.combat = true end
            if rb.hideWhileMounted then load.hideMounted = true end
            if rb.hideOutOfCombat or rb.hideWhileMounted then settings.loadMode = "conditional" end
            stack[#stack + 1] = barKey
        end
        if settings.loadMode == "conditional" then settings.load = load end
        if opts.showTicks then ctx.resourceTicks = true end
    end
    AddBar(primaryKey, rb.primaryBar, true)
    AddBar(secondaryKey, rb.secondaryBar, false)
    if ctx.resourceTicks then report:Skip(L["Resource bar ticks"]) end

    -- The first visible bar anchors like SCM's bar stack; the rest stack on it.
    local up = rb.growDirection ~= "DOWN"
    for i, barKey in ipairs(stack) do
        local settings = BarSettings(data, class, barKey)
        if i == 1 then
            local ref = ParseAnchor(rb.anchorFrame)
            local mapped = ref.group and ctx.groupMap[ref.group]
            local point = Point(rb.point) or "BOTTOM"
            local relPoint = Point(rb.relativePoint) or "TOP"
            local x, y = Num(rb.xOffset) or 0, Num(rb.yOffset) or 0
            settings.anchorPoint = point
            settings.anchorTargetPoint = relPoint
            if ref.target == "playerFrame" then
                settings.anchorTo = "playerFrame"
            elseif mapped and mapped.viewer == "essential" then
                settings.anchorTo = "essential"
            elseif ref.target == "screen" then
                -- ACDM's screen anchor pins the bar's bottom centre.
                local width = settings.width and settings.width > 0 and settings.width or 200
                local height = settings.height or 16
                local cx, cy = ScreenBoxCenter(ctx, point, relPoint, x, y, width, height)
                settings.anchorTo = "screen"
                x, y = cx, cy - height / 2
            else
                settings.anchorTo = "essential"
                report:Approx(L["Resource bars were anchored to \"%s\"; they now anchor to the Essential viewer."],
                    tostring(rb.anchorFrame))
            end
            settings.offsetX = Round(x)
            settings.offsetY = Round(y)
        else
            settings.anchorTo = stack[i - 1]
            settings.anchorPoint = up and "BOTTOM" or "TOP"
            settings.anchorTargetPoint = up and "TOP" or "BOTTOM"
            settings.barSpacing = Num(rb.spacing)
        end
    end

    local overrides = type(rb.powerTypeColorOverrides) == "table" and rb.powerTypeColorOverrides or {}
    for token, override in pairs(overrides) do
        local barKey = POWER_TOKEN_BARS[token]
        if barKey and type(override) == "table" and override.enabled then
            BarSettings(data, class, barKey).color = Color(override.color)
        end
    end
    if class == "DEATHKNIGHT" then
        BarSettings(data, class, "Runes").rechargingColor = Color(rb.runeRechargeColor)
    elseif class == "MONK" and type(rb.staggerColors) == "table" then
        local stagger = BarSettings(data, class, "Stagger")
        stagger.lightColor = Color(rb.staggerColors.light)
        stagger.moderateColor = Color(rb.staggerColors.moderate)
        stagger.heavyColor = Color(rb.staggerColors.heavy)
    elseif class == "ROGUE" or class == "DRUID" then
        BarSettings(data, class, "ComboPoints").overflowingColor = Color(rb.comboPointsOverflowColor)
    end
    if rb.hideWhileDead or rb.hideWhileInVehicle or rb.hideWhileResting or rb.useCustomVisibilityCondition then
        report:Skip(L["Resource bar visibility conditions (dead, vehicle, resting, macro)"])
    end
end

-- Removes nil-equivalent empty tables so the profile stays sparse.
local function PruneEmpty(data)
    for key, value in pairs(data) do
        if type(value) == "table" and next(value) == nil then data[key] = nil end
    end
end

local function Convert(text)
    local dataVersion, exportType, body = SplitHeader(text)
    if not dataVersion then return nil, L["Invalid profile data"] end
    if dataVersion ~= SCM_DATA_VERSION then
        return nil, string.format(L["Unsupported SCM export version %d."], dataVersion)
    end
    if exportType == EXPORT_GLOBAL_SETTINGS or exportType == EXPORT_GLOBAL_ANCHORS then
        return nil, L["This SCM string only holds global settings or anchors. Export a profile, class or spec from SCM instead."]
    end

    local payload, decodeErr = Adapters.DecodeBody(body)
    if not payload then return nil, decodeErr end

    local specID = CDM:GetCurrentSpecID()
    local class = UnitClassBase("player")
    if not specID or not class then return nil, L["Your specialization is not available yet. Try again in a moment."] end

    local spec, available, bySpec = FindSpecConfig(payload, exportType, specID, class)
    if type(spec) ~= "table" then
        if #available == 0 then
            return nil, L["This SCM string has no settings for your class."]
        end
        local names = {}
        for _, id in ipairs(available) do names[#names + 1] = SpecName(id) end
        return nil, string.format(L["This SCM string has no settings for %s. It contains: %s."],
            SpecName(specID), table.concat(names, ", "))
    end
    if IsEmptySpec(spec) then
        return nil, string.format(L["SCM has no tracked spells for %s."], SpecName(specID))
    end

    local report = Adapters.NewReport()
    local ctx = NewContext(specID, class, report)
    local options = type(payload.globalSettings) == "table" and payload.globalSettings or {}
    local data = {
        editModePositions = {}, cooldownGroups = {}, buffGroups = {}, ungroupedCooldownOrder = {},
        ungroupedCustomBuffOrder = {}, customBuffRegistry = {}, customCooldownEntries = {},
        cooldownTrinkets = {}, resourceBarSettings = {},
    }

    local others = {}
    for _, id in ipairs(available) do
        if id ~= specID and not IsEmptySpec(Lookup(bySpec, id)) then
            others[#others + 1] = SpecName(id)
        end
    end
    if #others > 0 then report:Skip(L["Other specializations in this string: %s"], table.concat(others, ", ")) end

    local tracking, groupCount = ConvertGroups(spec, options, ctx, data)
    ConvertIconStyle(options, data, report)
    ConvertGlow(options, data, report)
    ReportEffectRules(spec, report)
    ConvertBuffBars(spec, options, ctx, data)
    ConvertCastBar(payload.castBarSettings, ctx, data)
    ConvertResources(payload.resourceBarSettings, ctx, data)

    local globalAnchors = payload.globalAnchors
    if type(globalAnchors) == "table" and type(globalAnchors.globalCustomConfig) == "table" then
        for _, entries in pairs(globalAnchors.globalCustomConfig) do
            if type(entries) == "table" and next(entries) then
                report:Skip(L["SCM account-wide groups and their icons"])
                break
            end
        end
    end
    if type(options.debuffs) == "table" and next(options.debuffs) then
        report:Skip(L["SCM's damage-over-time aura list"])
    end
    if groupCount == 0 then report:Skip(L["No SCM groups had icons for this specialization."]) end
    PruneEmpty(data)

    return {
        profileName = string.format(L["SCM - %s"], SpecName(specID)),
        profileData = data,
        blizzardTracking = #tracking > 0 and { version = 1, specID = specID, entries = tracking } or nil,
        report = report,
    }
end

Adapters.Register({
    id = "SCM",
    label = "SkironCooldownManager",
    Detect = function(text) return text:find("^%s*!SCM:") ~= nil end,
    Convert = Convert,
})
