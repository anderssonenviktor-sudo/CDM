local Runtime = _G["CDM"]
if not Runtime then return end
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L
local CDM_C = CDM.CONST

-- Enum may be unavailable on clients without the Cooldown Viewer; bail so the
-- rest of the Options embeds still load. ConfigFrame nil-checks ns.CreateEditModeOverlay.
local SI = Enum.EditModeCooldownViewerSystemIndices
if not SI then return end

local VIEWER_ORDER = { SI.Essential, SI.Utility, SI.BuffIcon, SI.BuffBar }
local VIEWER_LABELS = {
    [SI.Essential] = "Essential",
    [SI.Utility]   = "Utility",
    [SI.BuffIcon]  = "Buff Icons",
    [SI.BuffBar]   = "Buff Bars",
}

local COLOR_OK    = { 0.20, 0.75, 0.30 }
local COLOR_ERROR = { 0.992, 0.071, 0 }
local COLOR_MUTED = { 0.55, 0.55, 0.55 }

---------------------------------------------------------------------------
-- Blizzard Edit Mode settings CDM expects on the four cooldown viewers
---------------------------------------------------------------------------

local function HasEditModeApis()
    return C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
        and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
        and Enum.EditModeCooldownViewerSetting
        and Enum.CooldownViewerVisibleSetting
        and Enum.CooldownViewerBarContent
        and Enum.EditModeLayoutType
end

local POLICIES
local function GetPolicies()
    if POLICIES then return POLICIES end
    local S = Enum.EditModeCooldownViewerSetting
    local ALL = { SI.Essential, SI.Utility, SI.BuffIcon, SI.BuffBar }
    local BUFFS = { SI.BuffIcon, SI.BuffBar }
    POLICIES = {
        { labelKey = "Always Visible", viewers = ALL, setting = S.VisibleSetting, value = Enum.CooldownViewerVisibleSetting.Always },
        { labelKey = "Show Timer", viewers = ALL, setting = S.ShowTimer, value = 1 },
        { labelKey = "Hide Buffs When Inactive", viewers = BUFFS, setting = S.HideWhenInactive, value = 1 },
        { labelKey = "Full Opacity", viewers = ALL, setting = S.Opacity, value = 100 },
        { labelKey = "Bar Content: Icon & Name", viewers = { SI.BuffBar }, setting = S.BarContent, value = Enum.CooldownViewerBarContent.IconAndName },
        { labelKey = "Hide Tooltips", viewers = ALL, setting = S.ShowTooltips, value = 0 },
    }
    for _, policy in ipairs(POLICIES) do
        policy.viewerSet = {}
        for _, idx in ipairs(policy.viewers) do
            policy.viewerSet[idx] = true
        end
    end
    return POLICIES
end

-- C_EditMode.GetLayouts() omits presets, but activeLayout indexes the preset
-- list followed by the saved layouts, so presets have to be prepended.
local function GetLayoutInfo()
    local layoutInfo = C_EditMode.GetLayouts()
    if type(layoutInfo) ~= "table" or type(layoutInfo.layouts) ~= "table" then
        return nil
    end
    if type(layoutInfo.activeLayout) == "number"
        and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
        if type(presets) == "table" then
            tAppendAll(presets, layoutInfo.layouts)
            layoutInfo.layouts = presets
        end
    end
    return layoutInfo
end

local function GetActiveLayout(layoutInfo)
    if not layoutInfo or type(layoutInfo.activeLayout) ~= "number" then return nil end
    local layout = layoutInfo.layouts[layoutInfo.activeLayout]
    if type(layout) ~= "table" or type(layout.systems) ~= "table" then return nil end
    return layout
end

local function ForEachViewerSystem(layout, fn)
    local cooldownSystem = Enum.EditModeSystem.CooldownViewer
    for _, systemInfo in ipairs(layout.systems) do
        if systemInfo.system == cooldownSystem and type(systemInfo.settings) == "table" then
            fn(systemInfo)
        end
    end
end

local function FindSetting(settings, settingEnum)
    for _, info in ipairs(settings) do
        if info.setting == settingEnum then
            return info
        end
    end
end

-- Returns nil when Edit Mode data is unavailable, otherwise
-- { isPreset = bool, wrong = { { label, viewers = { idx, ... } }, ... } }.
local function ScanLayout()
    if not HasEditModeApis() then return nil end
    local layout = GetActiveLayout(GetLayoutInfo())
    if not layout then return nil end

    local wrongByPolicy = {}
    local seenAny = false
    ForEachViewerSystem(layout, function(systemInfo)
        seenAny = true
        for i, policy in ipairs(GetPolicies()) do
            if policy.viewerSet[systemInfo.systemIndex] then
                local info = FindSetting(systemInfo.settings, policy.setting)
                if not info or info.value ~= policy.value then
                    local set = wrongByPolicy[i] or {}
                    set[systemInfo.systemIndex] = true
                    wrongByPolicy[i] = set
                end
            end
        end
    end)
    if not seenAny then return nil end

    local wrong = {}
    for i, policy in ipairs(GetPolicies()) do
        local set = wrongByPolicy[i]
        if set then
            local viewers = {}
            for _, idx in ipairs(VIEWER_ORDER) do
                if set[idx] then viewers[#viewers + 1] = idx end
            end
            wrong[#wrong + 1] = { label = policy.labelKey, viewers = viewers }
        end
    end

    return {
        isPreset = layout.layoutType == Enum.EditModeLayoutType.Preset,
        wrong = wrong,
    }
end

local function FixLayout()
    if InCombatLockdown() then return "in_combat" end
    if not HasEditModeApis() then return "not_ready" end
    local layoutInfo = GetLayoutInfo()
    local layout = GetActiveLayout(layoutInfo)
    if not layout then return "not_ready" end
    if layout.layoutType == Enum.EditModeLayoutType.Preset then return "preset" end

    local changed = false
    ForEachViewerSystem(layout, function(systemInfo)
        for _, policy in ipairs(GetPolicies()) do
            if policy.viewerSet[systemInfo.systemIndex] then
                local info = FindSetting(systemInfo.settings, policy.setting)
                if not info then
                    systemInfo.settings[#systemInfo.settings + 1] = { setting = policy.setting, value = policy.value }
                    changed = true
                elseif info.value ~= policy.value then
                    info.value = policy.value
                    changed = true
                end
            end
        end
    end)
    if not changed then return "noop" end

    -- Only save. Showing/hiding EditModeManagerFrame to apply live runs Blizzard's
    -- layout update under CDM taint and poisons the viewers' secure aura maps,
    -- so the new layout is picked up by a reload instead.
    C_EditMode.SaveLayouts(layoutInfo)
    return "saved"
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local WINDOW_WIDTH = 420
local PADDING_X = 18
local CONTENT_TOP = 58
local ROW_HEIGHT = 24
local NOTE_HEIGHT = 32
local BUTTON_WIDTH = 120
local BUTTON_HEIGHT = 24
local BOTTOM_PADDING = 18

local function CreateEditModeOverlay()
    local overlay = UI.CreateModalOverlay()
    local window = overlay.window
    local contentWidth = WINDOW_WIDTH - PADDING_X * 2

    local title = window:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    title:SetText(L["Edit Mode Settings"])
    title:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING_X, -30)
    title:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)

    local rows = {}
    local function GetRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, window)
        row:SetSize(contentWidth, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING_X, -(CONTENT_TOP + (i - 1) * ROW_HEIGHT))
        row.label = row:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        row.label:SetPoint("LEFT")
        row.label:SetTextColor(COLOR_ERROR[1], COLOR_ERROR[2], COLOR_ERROR[3], 1)
        row.viewers = row:CreateFontString(nil, "ARTWORK", "CDM_Font12")
        row.viewers:SetPoint("RIGHT")
        row.viewers:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
        row.viewers:SetJustifyH("RIGHT")
        row.viewers:SetWordWrap(false)
        row.viewers:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3], 1)
        rows[i] = row
        return row
    end

    -- Shown instead of rows when nothing is wrong, and below rows for warnings.
    local note = window:CreateFontString(nil, "ARTWORK", "CDM_Font12")
    note:SetWidth(contentWidth)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)

    local fixBtn = UI.CreateTextButton(window)
    fixBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    fixBtn:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PADDING_X, BOTTOM_PADDING)
    fixBtn:SetText(L["Fix Settings"])

    local function SetNote(text, color, y)
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING_X, -y)
        note:SetText(text)
        note:SetTextColor(color[1], color[2], color[3], 1)
        note:SetShown(text ~= nil)
    end

    local pendingReload = false

    local function Refresh(warning)
        for _, row in ipairs(rows) do row:Hide() end

        local scan = ScanLayout()
        local wrong = scan and scan.wrong or {}
        local y = CONTENT_TOP
        fixBtn:SetText(L["Fix Settings"])

        if pendingReload then
            SetNote(L["Settings saved. Reload your UI to apply them."], COLOR_OK, y)
            fixBtn:SetText(L["Reload UI"])
            fixBtn:Show()
            fixBtn:Enable()
            y = y + ROW_HEIGHT + 12 + BUTTON_HEIGHT
        elseif not scan then
            SetNote(L["Edit Mode data is not available yet."], COLOR_MUTED, y)
            fixBtn:Hide()
            y = y + ROW_HEIGHT
        elseif #wrong == 0 then
            SetNote(L["All settings are correct"], COLOR_OK, y)
            fixBtn:Hide()
            y = y + ROW_HEIGHT
        else
            for i, entry in ipairs(wrong) do
                local row = GetRow(i)
                row.label:SetText(L[entry.label])
                local names = {}
                for _, idx in ipairs(entry.viewers) do
                    names[#names + 1] = L[VIEWER_LABELS[idx]]
                end
                row.viewers:SetText(table.concat(names, ", "))
                row:Show()
            end
            y = y + #wrong * ROW_HEIGHT

            if scan.isPreset then
                warning = L["Active layout is a preset. Switch to or create a custom layout to save changes."]
            end
            if warning then
                SetNote(warning, COLOR_MUTED, y + 6)
                y = y + NOTE_HEIGHT
            else
                note:Hide()
            end
            fixBtn:Show()
            fixBtn:SetEnabled(not scan.isPreset)
            y = y + 12 + BUTTON_HEIGHT
        end

        window:SetSize(WINDOW_WIDTH, y + BOTTOM_PADDING)
    end

    fixBtn:SetScript("OnClick", function()
        if pendingReload then
            ReloadUI()
            return
        end
        local result = FixLayout()
        if result == "in_combat" then
            Refresh(L["Cannot change Edit Mode settings in combat."])
            return
        end
        if result == "saved" then
            pendingReload = true
        end
        Refresh()
    end)

    overlay:HookScript("OnShow", function() Refresh() end)
    CDM:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
        if overlay:IsShown() then Refresh() end
    end)

    return overlay
end

ns.CreateEditModeOverlay = CreateEditModeOverlay
