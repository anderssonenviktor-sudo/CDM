local addonName, ns = ...
local API = { version = 1 }
local listeners = {}
local optionsOpener
local openPending = false
local L = ns.L

local function EntryName(source)
    local spellID = source.overrideSpellID or source.baseSpellID or source.linkedSpellID
    local name = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if ns.Util.IsPublic(name) and type(name) == "string" then
        return string.format(L["%s (entry %d)"], name, source.cooldownID)
    end
    return string.format(L["Cooldown entry %d"], source.cooldownID)
end

local function EntryIcon(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellTexture then return nil end
    local icon = C_Spell.GetSpellTexture(spellID)
    local value = ns.Util.Number(icon)
    if value and value > 0 then return value end
end

local function EntrySnapshot(viewerID)
    local result = {}
    local sources = ns.BlizzardAdapter.GetSources(viewerID)
    local assignments = ns.Settings.GetAssignments()
    for _, groupID in ipairs(ns.Settings.GetGroupIDs(viewerID)) do
        local group = ns.Settings.GetEffective(groupID)
        for index, source in ipairs(ns.Model.Order(group, sources, assignments)) do
            local spellID = source.overrideSpellID or source.baseSpellID or source.linkedSpellID
            result[#result + 1] = { key = source.key, viewer = viewerID, groupID = groupID,
                name = EntryName(source), order = index, cooldownID = source.cooldownID,
                spellID = spellID, icon = EntryIcon(spellID) }
        end
    end
    return result
end

local function KnownEntry(key)
    local viewer = ns.Schema.ParseSourceKey(key)
    if not viewer then return nil end
    for _, source in ipairs(ns.BlizzardAdapter.GetSources(viewer)) do
        if source.key == key and ns.BlizzardAdapter.IsCurrent(source) then return source end
    end
end

-- Insert in the current group order in one Settings transaction. nil means
-- append; stable keys avoid replaying an index from an old options snapshot.
function API.ReorderEntry(groupID, key, beforeKey)
    if not ns.Util.IsPublic(groupID) or type(groupID) ~= "string" then return false, "Unknown group." end
    if not ns.Util.IsPublic(beforeKey) or (beforeKey ~= nil and type(beforeKey) ~= "string") then
        return false, "Invalid entry order."
    end
    local source = KnownEntry(key)
    if not source then return false, "This tracked entry is currently unavailable." end
    local group = ns.Settings.GetEffective(groupID)
    if not group or group.viewer ~= source.viewerID then return false, "Unknown group." end
    local keys, selected, destination = {}, false, beforeKey == nil
    for _, member in ipairs(ns.Model.Order(group, ns.BlizzardAdapter.GetSources(group.viewer), ns.Settings.GetAssignments())) do
        if not ns.BlizzardAdapter.IsCurrent(member) then return false, "This tracked entry is currently unavailable." end
        if member.key == key then selected = true end
        if member.key == beforeKey then destination = true end
        keys[#keys + 1] = member.key
    end
    if not selected or not destination then return false, "This tracked entry is currently unavailable." end
    if key == beforeKey then return true end
    local reordered = {}
    for _, memberKey in ipairs(keys) do
        if memberKey == beforeKey then reordered[#reordered + 1] = key end
        if memberKey ~= key then reordered[#reordered + 1] = memberKey end
    end
    if beforeKey == nil then reordered[#reordered + 1] = key end
    local changed = false
    for index, memberKey in ipairs(keys) do if reordered[index] ~= memberKey then changed = true; break end end
    if not changed then return true end
    return ns.Settings.SetEntryOrder(groupID, reordered)
end

function API.GetText(key)
    if not ns.Util.IsPublic(key) or type(key) ~= "string" then return "" end
    return L[key]
end

function API.GetSnapshot()
    local snapshot = ns.Settings.GetSnapshot()
    snapshot.apiVersion = API.version
    snapshot.combat = not not InCombatLockdown()
    snapshot.updates = ns.Updates.GetSnapshot()
    snapshot.entries = {}
    for _, viewerID in ipairs(ns.Constants.viewerIDs) do snapshot.entries[viewerID] = EntrySnapshot(viewerID) end
    for _, group in ipairs(snapshot.groups) do
        group.status = ns.BlizzardAdapter.GetStatus(group.viewer)
        group.entryCount = 0
        for _, entry in ipairs(snapshot.entries[group.viewer]) do
            if entry.groupID == group.id then group.entryCount = group.entryCount + 1 end
        end
    end
    return snapshot
end

function API.GetFonts()
    local result = {}
    for _, name in ipairs(LibStub("LibSharedMedia-3.0"):List("font")) do result[name] = name end
    return result
end

function API.SetGroupValue(groupID, key, value)
    return ns.Settings.SetGroupValue(groupID, key, value)
end

function API.SetPresentationValue(key, value)
    return ns.Settings.SetPresentationValue(key, value)
end

function API.CreateGroup(viewer, name)
    return ns.Settings.CreateGroup(viewer, name)
end

function API.DeleteGroup(groupID)
    return ns.Settings.DeleteGroup(groupID)
end

function API.SetGroupStyleValue(groupID, key, value)
    return ns.Settings.SetGroupStyleValue(groupID, key, value)
end

function API.ResetGroupStyle(groupID)
    return ns.Settings.ResetGroupStyle(groupID)
end

function API.AssignEntry(key, groupID)
    local source = KnownEntry(key)
    if not source then return false, "This tracked entry is currently unavailable." end
    if not ns.Util.IsPublic(groupID) or type(groupID) ~= "string" then return false, "Unknown group." end
    local group = ns.Settings.GetEffective(groupID)
    if not group then return false, "Unknown group." end
    if group.viewer ~= source.viewerID then return false, "Entries must stay in their original viewer." end
    local keys = {}
    local sources = ns.BlizzardAdapter.GetSources(group.viewer)
    for _, member in ipairs(ns.Model.Order(group, sources, ns.Settings.GetAssignments())) do
        if member.key ~= key then keys[#keys + 1] = member.key end
    end
    keys[#keys + 1] = key
    return ns.Settings.SetEntryOrder(groupID, keys)
end

function API.MoveEntry(key, direction)
    if not ns.Util.IsPublic(direction) or (direction ~= -1 and direction ~= 1) then return false, "Invalid entry order." end
    local source = KnownEntry(key)
    if not source then return false, "This tracked entry is currently unavailable." end
    local assignment = ns.Settings.GetAssignments()[key]
    local groupID = assignment and assignment.groupID or ns.Constants.viewers[source.viewerID].groupID
    local group = ns.Settings.GetEffective(groupID)
    if not group then return false, "CDM is not ready." end
    local keys, selected = {}, nil
    for index, member in ipairs(ns.Model.Order(group, ns.BlizzardAdapter.GetSources(group.viewer), ns.Settings.GetAssignments())) do
        keys[index] = member.key
        if member.key == key then selected = index end
    end
    local destination = selected and selected + direction
    if not destination or destination < 1 or destination > #keys then return false, "This entry is already at the end." end
    keys[selected], keys[destination] = keys[destination], keys[selected]
    return ns.Settings.SetEntryOrder(groupID, keys)
end

function API.SelectProfile(name)
    return ns.Settings.SelectProfile(name)
end

function API.RegisterListener(owner, callback)
    if not ns.Util.IsPublic(owner) or type(owner) ~= "table" or type(callback) ~= "function" then return false end
    listeners[owner] = callback
    return true
end

function API.UnregisterListener(owner)
    if ns.Util.IsPublic(owner) and owner ~= nil then listeners[owner] = nil end
end

function API.RegisterOptionsPanel(version, callback)
    if not ns.Util.IsPublic(version) or version ~= API.version or type(callback) ~= "function" or optionsOpener then return false end
    optionsOpener = callback
    return true
end

function API.OpenOptions()
    if InCombatLockdown() then
        openPending = true
        print(L["CDM: Options will open after combat."])
        return false
    end
    openPending = false
    if not optionsOpener then
        local ok = C_AddOns.LoadAddOn("CDM_Options")
        if not ok or not optionsOpener then
            print(L["CDM: Could not load CDM_Options. Make sure both addon folders are present and enabled."])
            return false
        end
    end
    optionsOpener()
    return true
end

ns.PublicAPI = {
    Notify = function(kind)
        local callbacks = {}
        for _, callback in pairs(listeners) do callbacks[#callbacks + 1] = callback end
        for _, callback in ipairs(callbacks) do
            local ok, message = pcall(callback, kind)
            if not ok then geterrorhandler()(message) end
        end
    end,
    ResumeOptions = function()
        if openPending then API.OpenOptions() end
    end,
}
_G.CDM_API = API
