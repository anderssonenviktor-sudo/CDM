local AddonName = "CDM"
local CDM = _G[AddonName]
local CDM_C = CDM.CONST
local Pixel = CDM.Pixel

local GetTime = GetTime
local IsSpellKnownOrInSpellBook = C_SpellBook.IsSpellKnownOrInSpellBook
local UnitChannelInfo = UnitChannelInfo
local type = type

-- Port of the Mass Disintegrate detection in DisintegrateTicks by Xephyris and
-- Vollmer (MIT License). The cast bar can't tell a Mass Disintegrate from a
-- plain Disintegrate. With the talent, each completed empower (or one made
-- instant by Tip the Scales) grants a stack, and the next Disintegrate within
-- 15 seconds consumes it.

local DISINTEGRATE = 356995
local MASS_DISINTEGRATE = 436335
local DEVASTATION_SPEC_ID = 1467
local STACK_DURATION = 15
-- Casting Hover during a channel fires a second start for the same channel.
local SAME_CHANNEL_WINDOW = 0.5
local DEFAULT_TEXT = "DON'T CLIP"

local EMPOWERS = {
    [357208] = true, -- Fire Breath
    [382266] = true, -- Fire Breath (Font of Magic)
    [359073] = true, -- Eternity Surge
    [382411] = true, -- Eternity Surge (Font of Magic)
}

local stacks = 0
local lastGainedStack = 0
local tipTheScalesActive = false
local lastStart = 0

local function CfgVal(key, default)
    return CDM_C.GetConfigValue(key, default)
end

local function IsEnabled()
    return CfgVal("castBarMassDisintegrateWarning", false) == true
end

local function KnowsMassDisintegrate()
    return IsSpellKnownOrInSpellBook(MASS_DISINTEGRATE)
end

local function GainStack()
    stacks = stacks + 1
    lastGainedStack = GetTime()
end

local function GetWarning()
    local frame = CDM.castBarFrame
    return frame and frame.massDisintegrateWarning
end

local MassDisintegrate = {}
CDM.MassDisintegrate = MassDisintegrate

function MassDisintegrate.Attach(frame)
    local warning = frame.topOverlay:CreateFontString(nil, "OVERLAY")
    warning:SetIgnoreParentScale(true)
    warning:Hide()
    frame.massDisintegrateWarning = warning
end

function MassDisintegrate.Refresh(frame)
    local warning = frame.massDisintegrateWarning
    if not warning then return end
    local text = CfgVal("castBarClipWarningText", DEFAULT_TEXT)
    if type(text) ~= "string" or text == "" then text = DEFAULT_TEXT end
    warning:SetFont(CDM_C.GetBaseFontPath(), Pixel.FontSize(CfgVal("castBarClipWarningFontSize", 18)),
        CDM_C.GetBaseFontOutline())
    warning:SetText(text)
    warning:ClearAllPoints()
    Pixel.SetPoint(warning, "BOTTOM", frame, "TOP",
        CfgVal("castBarClipWarningOffsetX", 0), CfgVal("castBarClipWarningOffsetY", 10))
    if not IsEnabled() then warning:Hide() end
end

function MassDisintegrate.Hide(frame)
    if frame.massDisintegrateWarning then frame.massDisintegrateWarning:Hide() end
end

-- The preview shows the warning so it can be placed without casting.
function MassDisintegrate.ShowPreview(frame)
    local warning = frame.massDisintegrateWarning
    if warning then
        warning:SetShown(IsEnabled() and CDM.GetCurrentSpecID and CDM:GetCurrentSpecID() == DEVASTATION_SPEC_ID)
    end
end

local function OnEvent(_, event, ...)
    if event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        local _, _, _, complete = ...
        if not complete or not KnowsMassDisintegrate() then return end
        GainStack()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if tipTheScalesActive and EMPOWERS[spellID] and KnowsMassDisintegrate() then
            tipTheScalesActive = false
            GainStack()
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- Ignores other channels such as Fishing or quest casts.
        if select(3, ...) ~= DISINTEGRATE then return end
        local _, _, _, startTimeMS = UnitChannelInfo("player")
        if not startTimeMS then return end
        local startTime = startTimeMS / 1000
        if startTime - lastStart < SAME_CHANNEL_WINDOW then return end
        lastStart = startTime

        local isMass = false
        if stacks > 0 then
            if GetTime() - lastGainedStack > STACK_DURATION then
                stacks = 0
            else
                stacks = stacks - 1
                isMass = true
            end
        end
        local warning = GetWarning()
        if warning then warning:SetShown(isMass and IsEnabled()) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if select(3, ...) ~= DISINTEGRATE then return end
        local warning = GetWarning()
        if warning then warning:Hide() end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        if EMPOWERS[...] then tipTheScalesActive = true end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if EMPOWERS[...] then tipTheScalesActive = false end
    elseif event == "PLAYER_DEAD" then
        stacks = 0
    end
end

-- Evokers only. Its own frame, like the cast bar, so the player-only unit
-- events don't fire for every unit through CDM's shared dispatcher.
if select(2, UnitClass("player")) == "EVOKER" then
    local eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
    for _, event in ipairs({
        "UNIT_SPELLCAST_EMPOWER_STOP",
        "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_STOP",
    }) do
        eventFrame:RegisterUnitEvent(event, "player")
    end
    CDM:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", OnEvent)
    CDM:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", OnEvent)
    CDM:RegisterEvent("PLAYER_DEAD", OnEvent)
end
