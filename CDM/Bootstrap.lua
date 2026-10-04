local addonName, ns = ...
local Settings, Adapter = ns.Settings, ns.BlizzardAdapter
local Model, Layout, Style, Updates = ns.Model, ns.Layout, ns.Style, ns.Updates
local started = false
local appliedSpec, specScheduled, specVersion = 0, false, 0
local events = CreateFrame("Frame", "CDM_EventFrame")

local function BroadData()
    Layout.Invalidate()
    Model.Clear()
    Style.ClearBindings()
    Updates.MarkAll("DATA")
end

local function ViewerData(viewerID)
    Layout.InvalidateViewer(viewerID)
    Model.ClearViewer(viewerID)
    Style.ClearBindings(viewerID)
    for _, id in ipairs(Settings.GetGroupIDs(viewerID)) do Updates.Mark(id, "DATA") end
end

local function Specialization()
    local index = GetSpecialization()
    if not ns.Util.Number(index) then return 0 end
    return ns.Util.Number(GetSpecializationInfo(index)) or 0
end

local function TransitionSpec()
    appliedSpec = Specialization()
    Settings.SetSpec(appliedSpec)
    BroadData()
    ns.PublicAPI.Notify("spec")
end

local function ScheduleSpec()
    specVersion = specVersion + 1
    if specScheduled then return end
    specScheduled = true
    C_Timer.After(0, function()
        specScheduled = false
        local version = specVersion
        TransitionSpec()
        -- Like Ayije's versioned settling checks, this catches APIs becoming
        -- ready after the specialization event. It is bounded, not polling.
        C_Timer.After(0.25, function()
            if version == specVersion and Specialization() ~= appliedSpec then TransitionSpec() end
        end)
    end)
end

local function SettingsChanged(kind, groupID, reason, viewerID)
    if reason == "DATA" and viewerID then ViewerData(viewerID)
    elseif reason == "DATA" then BroadData()
    elseif groupID then
        Layout.Invalidate(groupID)
        Updates.Mark(groupID, reason)
    else Updates.MarkAll(reason) end
    ns.PublicAPI.Notify(kind)
end

local function Process(groupID, reasons, context)
    local config = Settings.GetEffective(groupID)
    if not config then return end
    local members = Model.GetMembers(groupID)
    local _, viewer = Adapter.GetSources(config.viewer)
    if reasons.DATA then
        local sources = context[config.viewer]
        if not sources then
            sources, viewer = Adapter.Discover(config.viewer)
            context[config.viewer] = sources
        end
        members = Model.Resolve(config, sources, Settings.GetAssignments())
    end
    local sources = Adapter.GetSources(config.viewer)
    if reasons.DATA or reasons.LAYOUT then Layout.Apply(config, members, viewer, #sources) end
    if reasons.DATA or reasons.LAYOUT or reasons.STYLE then
        for _, source in ipairs(members) do Style.Apply(source, config) end
    end
end

local function Start()
    if started then return end
    Updates.Initialize(Process, Settings.GetGroupIDs, function() ns.PublicAPI.Notify("status") end)
    Layout.Initialize(Adapter.IsCurrent, Updates.Defer, Updates.Mark)
    Style.Initialize(Adapter.IsCurrent, Updates.Defer)
    Adapter.Initialize({
        onData = function(viewerID)
            Layout.InvalidateViewer(viewerID)
            for _, id in ipairs(Settings.GetGroupIDs(viewerID)) do Updates.Mark(id, "DATA") end
        end,
        onReset = function(frame, viewerID)
            Style.ResetFrame(frame)
            Layout.InvalidateViewer(viewerID)
        end,
        onGeometry = function(viewerID, frame)
            if frame then Layout.ReassertFrame(frame)
            else
                Layout.ReassertViewer(viewerID)
            end
        end,
        onAppearance = Style.Reassert,
    })
    local ok, message = Settings.Initialize(SettingsChanged)
    started = true
    if not ok then print(ns.L["CDM:"] .. " " .. ns.L[message]) end
    local media = LibStub("LibSharedMedia-3.0")
    media.RegisterCallback(events, "LibSharedMedia_Registered", function(_, mediaType, key)
        if not ns.Util.IsPublic(mediaType) or mediaType ~= "font" or not ns.Util.IsPublic(key) then return end
        for _, groupID in ipairs(Settings.GetGroupIDs()) do
            local config = Settings.GetEffective(groupID)
            if config and config.style.font == key then
                Style.InvalidateFont(groupID)
                Updates.Mark(groupID, "STYLE")
            end
        end
        ns.PublicAPI.Notify("media")
    end)
    TransitionSpec()
end

events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == addonName then Start()
        elseif started and arg == "Blizzard_CooldownViewer" then BroadData() end
        return
    end
    if not started then return end
    if event == "PLAYER_REGEN_ENABLED" then
        Updates.Resume()
        ns.PublicAPI.ResumeOptions()
        ns.PublicAPI.Notify("combat")
    elseif event == "PLAYER_REGEN_DISABLED" then ns.PublicAPI.Notify("combat")
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg == "player" then ScheduleSpec() end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then ScheduleSpec()
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
        if specScheduled or Specialization() ~= appliedSpec then ScheduleSpec() else BroadData() end
    elseif event == "CVAR_UPDATE" then
        if ns.Util.IsPublic(arg) and arg == "cooldownViewerEnabled" then BroadData() end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then Updates.MarkAll("LAYOUT")
    else BroadData() end
end)

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "CVAR_UPDATE", "UI_SCALE_CHANGED",
    "DISPLAY_SIZE_CHANGED", "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED",
    "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED",
}) do events:RegisterEvent(event) end

SLASH_CDM_SLICE1 = "/cedm"
SlashCmdList.CDM_SLICE = function() CDM_API.OpenOptions() end
