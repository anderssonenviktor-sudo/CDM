local AddonName = "CDM"
local CDM = _G[AddonName]
local CDM_C = CDM.CONST
local Pixel = CDM.Pixel

local GetInventoryItemID = GetInventoryItemID
local IsSpellKnown = C_SpellBook.IsSpellKnown
local ipairs = ipairs
local math_abs = math.abs
local math_floor = math.floor
local math_fmod = math.fmod
local pairs = pairs
local pcall = pcall
local type = type

-- Interior tick marks for channeled spells. Each entry uses one cadence:
--   ticks = N     : N evenly spaced hits ending at the channel end; marks at i/N.
--   interval = s  : one hit every s seconds, so haste lengthens the channel and
--                   adds hits; marks at i/floor(duration / s).
--   pulses = P    : hits at the channel start, at its end and evenly between,
--                   so P hits span P - 1 intervals. Recasting before the old
--                   channel ends keeps the old rhythm (see BuildPulseFractions).
-- talents = { [spellID] = extra } adds hits while the player knows the spell.
-- setBonuses = { [spellID] = { pieces = n, extra = m } } adds hits while n
-- equipped items grant that set bonus for the current spec.
-- The last interior mark is the final point to clip or chain the channel.
local TICK_DATA = {
    -- Evoker: Azure Celerity adds an interval without lengthening the channel.
    [356995] = { pulses = 4, talents = { [1219723] = 1 } },         -- Disintegrate
    -- Mage
    [5143]   = {                                                    -- Arcane Missiles
        pulses = 5,
        talents = { [236628] = 2 },                                 -- Amplification
        setBonuses = { [1296581] = { pieces = 2, extra = 1 } },
    },
    [12051]  = { ticks = 6 },                                       -- Evocation
    [205021] = { ticks = 5 },                                       -- Ray of Frost
    -- Priest: Penance hits on cast, so two ticks make three bolts; Castigation adds one.
    [15407]  = { ticks = 6 },                                       -- Mind Flay
    [48045]  = { ticks = 6 },                                       -- Mind Sear
    [64843]  = { ticks = 4 },                                       -- Divine Hymn
    [47757]  = { ticks = 2, talents = { [193134] = 1 } },           -- Penance (heal)
    [47758]  = { ticks = 2, talents = { [193134] = 1 } },           -- Penance (damage)
    [373129] = { ticks = 2, talents = { [193134] = 1 } },           -- Dark Reprimand (damage)
    [400171] = { ticks = 2, talents = { [193134] = 1 } },           -- Dark Reprimand (heal)
}

local MAX_MARKS = 20
local SAME_CAST_WINDOW = 0.5
local PREVIEW_FRACTIONS = { 0.2, 0.4, 0.6, 0.8 }
local DEFAULT_TICK_COLOR = { r = 1, g = 1, b = 1, a = 1 }
local DEFAULT_LAST_TICK_COLOR = { r = 1, g = 0, b = 0, a = 0.95 }
local ARCANE_SPEC_ID = 62

local function CfgVal(key, default)
    return CDM_C.GetConfigValue(key, default)
end

local setBonusCache = {}

local function WipeSetBonusCache()
    for id in pairs(setBonusCache) do setBonusCache[id] = nil end
end
CDM:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", WipeSetBonusCache)
CDM:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", WipeSetBonusCache)

local function IsSetBonusActive(bonusSpellID, pieces)
    local cached = setBonusCache[bonusSpellID]
    if cached ~= nil then return cached end
    local active = false
    local getBonuses = C_Item and C_Item.GetSetBonusesForSpecializationByItemID
    local specID = CDM.GetCurrentSpecID and CDM:GetCurrentSpecID()
    if getBonuses and specID then
        local count = 0
        for slot = 1, 19 do
            local itemID = GetInventoryItemID("player", slot)
            if itemID then
                local ok, bonusIDs = pcall(getBonuses, specID, itemID)
                if ok and type(bonusIDs) == "table" then
                    for _, id in ipairs(bonusIDs) do
                        if id == bonusSpellID then
                            count = count + 1
                            break
                        end
                    end
                end
            end
        end
        active = count >= pieces
    end
    setBonusCache[bonusSpellID] = active
    return active
end

local function GetExtraHits(data)
    local extra = 0
    if data.talents then
        for spellID, amount in pairs(data.talents) do
            if IsSpellKnown(spellID) then extra = extra + amount end
        end
    end
    if data.setBonuses then
        for spellID, info in pairs(data.setBonuses) do
            if IsSetBonusActive(spellID, info.pieces) then extra = extra + info.extra end
        end
    end
    return extra
end

local function GetState(frame)
    local state = frame.cdmTicks
    if not state then
        state = { textures = {}, fractions = {}, count = 0 }
        frame.cdmTicks = state
    end
    return state
end

local function SetEvenFractions(state, segments)
    local count = 0
    for i = 1, segments - 1 do
        if count >= MAX_MARKS then break end
        count = count + 1
        state.fractions[count] = i / segments
    end
    state.count = count
end

-- A recast during a running channel of the same spell fires immediately, then
-- keeps the old channel's rhythm: its first mark lands where the old channel's
-- next hit was due, and the reported duration grows by that carry. The carry is
-- measured once per cast; channel updates for the same cast reuse it.
local function BuildPulseFractions(state, spellID, intervals, startTime, endTime, castID)
    local duration = endTime - startTime
    local sameCast
    if castID and state.castID then
        sameCast = castID == state.castID
    else
        sameCast = state.castStart and math_abs(startTime - state.castStart) < SAME_CAST_WINDOW
    end
    if not sameCast then
        local carry = 0
        local prevEnd, prevInterval = state.prevEnd, state.prevInterval
        if state.prevSpell == spellID and prevEnd and prevInterval and prevInterval > 0
            and startTime < prevEnd - 0.01 then
            carry = math_fmod(prevEnd - startTime, prevInterval)
            -- Grid-aligned recasts, and recasts just after a hit, lay out like a fresh cast.
            if carry < 0.01 or carry > prevInterval - 0.05 then carry = 0 end
        end
        state.carry = carry
        state.castID = castID
        state.castStart = startTime
    end

    local carry = state.carry or 0
    local count = 0
    local chained = false
    if carry > 0 and duration > 0 then
        local interval = (duration - carry) / intervals
        if interval > 0.01 then
            local t = carry
            while t < duration - interval * 0.05 and count < MAX_MARKS do
                count = count + 1
                state.fractions[count] = t / duration
                t = t + interval
            end
            chained = count > 0
        end
    end
    if chained then
        state.count = count
    else
        SetEvenFractions(state, intervals)
    end

    if duration > 0 then
        state.prevSpell = spellID
        state.prevEnd = endTime
        state.prevInterval = (chained and (duration - carry) or duration) / intervals
    end
end

local function HideTextures(state, from)
    local textures = state.textures
    for i = from or 1, #textures do
        textures[i]:Hide()
    end
end

local function Layout(frame)
    local state = frame.cdmTicks
    if not state then return end
    local count = state.count
    local showTicks = CfgVal("castBarShowTicks", true) == true
    -- Arcane only; a saved value from that spec stays off on other specs.
    local highlightLast = CfgVal("castBarHighlightLastTick", false) == true
        and CDM:GetCurrentSpecID() == ARCANE_SPEC_ID
    local bar = frame.castBar
    local width, height = bar:GetWidth(), bar:GetHeight()
    if count == 0 or not (showTicks or highlightLast) or not width or width <= 0 or not height or height <= 0 then
        HideTextures(state)
        return
    end

    local px = Pixel.GetSize()
    local baseWidth = math_floor(CfgVal("castBarTickWidth", 2) + 0.5)
    if baseWidth < 1 then baseWidth = 1 end
    local tickColor = CfgVal("castBarTickColor", DEFAULT_TICK_COLOR)
    local lastColor = CfgVal("castBarLastTickColor", DEFAULT_LAST_TICK_COLOR)

    for i = 1, count do
        local tick = state.textures[i]
        if not tick then
            tick = Pixel.CreateSolidTexture(bar, "OVERLAY", 3)
            state.textures[i] = tick
        end
        local isLast = i == count
        if not showTicks and not isLast then
            tick:Hide()
        else
            local highlighted = isLast and highlightLast
            local widthPx = highlighted and baseWidth + 1 or baseWidth
            -- Channels drain right to left, so time fraction f sits at (1 - f).
            -- Odd widths center on a pixel and even widths on a pixel edge,
            -- which keeps both edges on the physical grid.
            local offset = width * (1 - state.fractions[i]) / px
            if widthPx % 2 == 0 then
                offset = math_floor(offset + 0.5)
            else
                offset = math_floor(offset) + 0.5
            end
            local color = highlighted and lastColor or tickColor
            tick:SetVertexColor(color.r, color.g, color.b, color.a or 1)
            tick:SetSize(widthPx * px, height)
            tick:ClearAllPoints()
            tick:SetPoint("CENTER", bar, "LEFT", offset * px, 0)
            tick:Show()
        end
    end
    HideTextures(state, count + 1)
end

local Ticks = {}
CDM.CastBarTicks = Ticks

function Ticks.Attach(frame)
    GetState(frame)
    frame.castBar:HookScript("OnSizeChanged", function()
        Layout(frame)
    end)
end

-- Lays out marks for the player's current channel, or hides them when the
-- spell has no tick data.
function Ticks.Update(frame, spellID, startTime, endTime, castID)
    local state = GetState(frame)
    local data = CDM.IsSafeNumber(spellID) and TICK_DATA[spellID]
    if not data or not CDM.IsSafeNumber(startTime) or not CDM.IsSafeNumber(endTime) then
        state.count = 0
        HideTextures(state)
        return
    end

    if not CDM.IsSafeNumber(castID) then castID = nil end
    local duration = endTime - startTime
    if data.pulses then
        local intervals = data.pulses + GetExtraHits(data) - 1
        if intervals >= 1 then
            BuildPulseFractions(state, spellID, intervals, startTime, endTime, castID)
        else
            state.count = 0
        end
    elseif data.interval then
        SetEvenFractions(state, duration > 0 and math_floor(duration / data.interval) or 0)
    else
        SetEvenFractions(state, data.ticks + GetExtraHits(data))
    end
    Layout(frame)
end

function Ticks.ShowPreview(frame)
    local state = GetState(frame)
    for i, fraction in ipairs(PREVIEW_FRACTIONS) do
        state.fractions[i] = fraction
    end
    state.count = #PREVIEW_FRACTIONS
    Layout(frame)
end

-- Keeps the chain state, so a recast can still pick up the outgoing rhythm.
function Ticks.Hide(frame)
    local state = frame.cdmTicks
    if not state then return end
    state.count = 0
    HideTextures(state)
end

function Ticks.Reset(frame)
    local state = frame.cdmTicks
    if not state then return end
    Ticks.Hide(frame)
    state.castID, state.castStart, state.carry = nil, nil, nil
    state.prevSpell, state.prevEnd, state.prevInterval = nil, nil, nil
end

-- Re-applies colors and widths after a settings change.
function Ticks.Refresh(frame)
    Layout(frame)
end
