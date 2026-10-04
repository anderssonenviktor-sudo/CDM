local addonName, ns = ...
local Adapter = {}
ns.BlizzardAdapter = Adapter
local Util = ns.Util
local callbacks
local viewers, sources, status = {}, {}, {}
local viewerHooks = setmetatable({}, { __mode = "k" })
local frameStates = setmetatable({}, { __mode = "k" })
local nextSerial = 0

local function State(frame)
    local state = frameStates[frame]
    if not state then
        nextSerial = nextSerial + 1
        state = { generation = 0, serial = nextSerial }
        frameStates[frame] = state
    end
    return state
end

local function Reset(frame, active)
    local state = State(frame)
    state.generation = state.generation + 1
    state.active = active
    state.key, state.cooldownID = nil, nil
    callbacks.onReset(frame, state.viewerID)
    if state.viewerID then callbacks.onData(state.viewerID) end
end

-- Pure metadata boundary: display values never enter the source record.
function Adapter.MakeSource(viewerID, viewerCategory, cooldownID, layoutIndex, info)
    local id = Util.Number(cooldownID)
    if not id or id < 1 or id ~= math.floor(id) then return nil end
    if not Util.IsPublic(info) or type(info) ~= "table" then info = {} end
    if not Util.IsPublic(info.category) then return nil end
    local category = Util.Number(info.category) or Util.Number(viewerCategory)
    if not category or category < 0 or category ~= math.floor(category) then return nil end
    local source = {
        key = "blizzard:" .. viewerID .. ":" .. category .. ":" .. id,
        viewerID = viewerID, sourceCategory = category, viewerCategory = Util.Number(viewerCategory),
        cooldownID = id, blizzardOrder = Util.Number(layoutIndex) or math.huge,
        baseSpellID = Util.Number(info.spellID), overrideSpellID = Util.Number(info.overrideSpellID),
        linkedSpellID = Util.Number(info.linkedSpellID), linkedSpellIDs = {},
    }
    if Util.IsPublic(info.linkedSpellIDs) and type(info.linkedSpellIDs) == "table" then
        for _, spellID in ipairs(info.linkedSpellIDs) do
            local publicID = Util.Number(spellID)
            if publicID then source.linkedSpellIDs[#source.linkedSpellIDs + 1] = publicID end
        end
    end
    return source
end

local function HookFrame(frame, viewerID)
    local state = State(frame)
    state.viewerID = viewerID
    if state.hooked then return end
    state.hooked = true
    if frame.OnCooldownIDSet then
        hooksecurefunc(frame, "OnCooldownIDSet", function(self) Reset(self, true) end)
    end
    if frame.ResetCooldownData then
        hooksecurefunc(frame, "ResetCooldownData", function(self) Reset(self, false) end)
    end
    for _, method in ipairs({ "SetPoint", "SetSize", "SetScale" }) do
        hooksecurefunc(frame, method, function(self)
            local current = frameStates[self]
            if current.active then callbacks.onGeometry(current.viewerID, self) end
        end)
    end
    frame:HookScript("OnShow", function(self)
        local current = frameStates[self]
        if current.active then callbacks.onAppearance(self) end
    end)
    if frame.Icon then
        for _, method in ipairs({ "SetTexture", "SetAtlas", "SetTexCoord", "AddMaskTexture" }) do
            if frame.Icon[method] then
                hooksecurefunc(frame.Icon, method, function() callbacks.onAppearance(frame) end)
            end
        end
    end
    if frame.Cooldown and frame.Cooldown.SetCountdownFont then
        hooksecurefunc(frame.Cooldown, "SetCountdownFont", function() callbacks.onAppearance(frame) end)
    end
    local charge = frame.ChargeCount and frame.ChargeCount.Current
    if charge then
        hooksecurefunc(charge, "SetText", function(_, value) callbacks.onAppearance(frame, "charge", value) end)
    end
    local stacks = frame.Applications and frame.Applications.Applications
    if stacks then
        for _, method in ipairs({ "SetFont", "SetTextColor" }) do
            hooksecurefunc(stacks, method, function() callbacks.onAppearance(frame) end)
        end
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if Util.IsPublic(region) and region.GetAtlas then
            local atlas = region:GetAtlas()
            if Util.IsPublic(atlas) and atlas == "UI-HUD-CoolDownManager-IconOverlay" then
                hooksecurefunc(region, "SetAlpha", function() callbacks.onAppearance(frame) end)
            end
        end
    end
end

local function HookViewer(viewer, viewerID)
    if viewerHooks[viewer] then return end
    viewerHooks[viewer] = true
    if viewer.OnAcquireItemFrame then
        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, frame)
            HookFrame(frame, viewerID)
            Reset(frame, true)
        end)
    end
    for _, method in ipairs({ "RefreshLayout", "RefreshData" }) do
        if viewer[method] then
            hooksecurefunc(viewer, method, function() callbacks.onData(viewerID) end)
        end
    end
    for _, method in ipairs({ "Layout", "SetPoint", "SetSize", "SetScale" }) do
        if viewer[method] then
            hooksecurefunc(viewer, method, function() callbacks.onGeometry(viewerID) end)
        end
    end
    viewer:HookScript("OnShow", function() callbacks.onData(viewerID) end)
    viewer:HookScript("OnHide", function() callbacks.onData(viewerID) end)
end

function Adapter.Initialize(lifecycleCallbacks)
    callbacks = lifecycleCallbacks
end

function Adapter.Discover(viewerID)
    local description = ns.Constants.viewers[viewerID]
    local viewer = _G[description.frameName]
    local result = {}
    sources[viewerID], viewers[viewerID] = result, viewer
    local report = { count = 0, placeholders = 0, skipped = 0 }
    status[viewerID] = report
    if not viewer or not viewer.itemFramePool then return result, viewer end
    HookViewer(viewer, viewerID)
    local category = viewer.GetCategory and Util.Number(viewer:GetCategory())
    local ordered = viewer.GetCooldownIDs and viewer:GetCooldownIDs()
    local ranks = {}
    if Util.IsPublic(ordered) and type(ordered) == "table" then
        for index, value in ipairs(ordered) do
            local id = Util.Number(value)
            if id then ranks[id] = index end
        end
    end
    for frame in viewer.itemFramePool:EnumerateActive() do
        HookFrame(frame, viewerID)
        local state = State(frame)
        local id = frame.GetCooldownID and frame:GetCooldownID()
        local info = frame.GetCooldownInfo and frame:GetCooldownInfo()
        local publicID = Util.Number(id)
        local order = Util.Number(frame.layoutIndex) or (publicID and ranks[publicID])
        local source = Adapter.MakeSource(viewerID, category, id, order, info)
        if source then
            if state.key and state.key ~= source.key then Reset(frame, true) end
            state.active, state.key, state.cooldownID = true, source.key, source.cooldownID
            source.frame, source.generation, source.serial = frame, state.generation, state.serial
            result[#result + 1] = source
        else
            state.active, state.key, state.cooldownID = false, nil, nil
            callbacks.onReset(frame, viewerID)
            if Util.IsPublic(id) and id == nil then
                report.placeholders = report.placeholders + 1
            else
                report.skipped = report.skipped + 1
            end
        end
    end
    report.count = #result
    return result, viewer
end

function Adapter.GetSources(viewerID)
    return sources[viewerID] or {}, viewers[viewerID]
end

function Adapter.IsCurrent(source)
    local state = frameStates[source.frame]
    if not state or not state.active or state.generation ~= source.generation or state.key ~= source.key then
        return false
    end
    local id = source.frame.GetCooldownID and source.frame:GetCooldownID()
    return Util.IsPublic(id) and id == source.cooldownID
end

function Adapter.GetStatus(viewerID)
    local result = Util.Copy(status[viewerID] or { count = 0, placeholders = 0, skipped = 0 })
    local viewer = viewers[viewerID]
    local enabled = C_CVar and C_CVar.GetCVarBool("cooldownViewerEnabled")
    local available = C_CooldownViewer and C_CooldownViewer.IsCooldownViewerAvailable()
    local shown = viewer and viewer:IsShown()
    if Util.IsPublic(enabled) and enabled == false then result.state = "disabled"
    elseif Util.IsPublic(available) and available == false then result.state = "unavailable"
    elseif not viewer then result.state = "missing"
    elseif result.count == 0 and result.skipped > 0 then result.state = "secret"
    elseif result.count == 0 then result.state = "empty"
    elseif Util.IsPublic(shown) and shown == false then result.state = "hidden"
    else result.state = "active" end
    return result
end
