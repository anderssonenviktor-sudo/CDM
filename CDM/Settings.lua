local addonName, ns = ...
local Settings = {}
ns.Settings = Settings
local db, onChanged
local currentSpec = 0
local effective, assignments = {}, {}
local groupIDs, viewerGroups = {}, {}
local failure
local defaults = { profile = { presentation = ns.Schema.DefaultPresentation(), specs = {} } }

local function ValidDatabase(raw)
    if not ns.Util.IsPublic(raw) then return false end
    if raw == nil then return true end
    if type(raw) ~= "table" then return false end
    for _, key in ipairs({ "profiles", "profileKeys" }) do
        if not ns.Util.IsPublic(raw[key]) or (raw[key] ~= nil and type(raw[key]) ~= "table") then return false end
    end
    for name, profile in pairs(raw.profiles or {}) do
        if not ns.Util.IsPublic(name) or not ns.Util.IsPublic(profile)
            or type(name) ~= "string" or type(profile) ~= "table" then return false end
    end
    for character, profileName in pairs(raw.profileKeys or {}) do
        if not ns.Util.IsPublic(character) or not ns.Util.IsPublic(profileName)
            or type(character) ~= "string" or type(profileName) ~= "string" then return false end
    end
    return true
end

local function Resolve()
    if failure then return end
    effective, assignments = ns.Schema.Resolve(db.profile, currentSpec)
    groupIDs = ns.Schema.GetGroupIDs(effective)
    viewerGroups = {}
    for _, viewer in ipairs(ns.Constants.viewerIDs) do viewerGroups[viewer] = {} end
    for _, id in ipairs(groupIDs) do
        local ids = viewerGroups[effective[id].viewer]
        ids[#ids + 1] = id
    end
end

local function ProfileChanged()
    local ok, message = ns.Schema.Upgrade(db.profile)
    failure = not ok and message or nil
    if failure then effective, assignments, groupIDs, viewerGroups = {}, {}, {}, {}
    else db:RegisterDefaults(defaults); Resolve() end
    onChanged("profile", nil, "DATA")
end

function Settings.Initialize(callback)
    onChanged = callback
    db, effective, assignments, failure = nil, {}, {}, nil
    groupIDs, viewerGroups = {}, {}
    if not ValidDatabase(CDM_DB) then
        failure = "Invalid SavedVariables data. CDM has stopped."
        return false, failure
    end
    -- Validate raw profiles before AceDB installs its defaults metatables.
    db = LibStub("AceDB-3.0"):New("CDM_DB", nil, true)
    local ok, message = ns.Schema.Upgrade(db.profile)
    failure = not ok and message or nil
    db.RegisterCallback(Settings, "OnProfileChanged", ProfileChanged)
    db.RegisterCallback(Settings, "OnProfileCopied", ProfileChanged)
    db.RegisterCallback(Settings, "OnProfileReset", ProfileChanged)
    if failure then return false, failure end
    db:RegisterDefaults(defaults)
    Resolve()
    return true
end

function Settings.SetSpec(specID)
    local value = ns.Util.Number(specID)
    if not value or value < 0 or value > 10000 or value ~= math.floor(value) then value = 0 end
    currentSpec = value
    Resolve()
end

function Settings.GetEffective(groupID)
    return effective[groupID]
end

function Settings.GetAssignments()
    return assignments
end

function Settings.GetGroupIDs(viewer)
    if viewer then return viewerGroups[viewer] or {} end
    return groupIDs
end

local function EditableGroup(groupID)
    if failure or not db then return nil, failure or "CDM is not ready." end
    if not ns.Util.IsPublic(groupID) or type(groupID) ~= "string" or not effective[groupID] then
        return nil, "Unknown group."
    end
    return db.profile.specs[currentSpec].groups[groupID]
end

function Settings.CreateGroup(viewer, name)
    if failure or not db then return false, failure or "CDM is not ready." end
    if not ns.Schema.ValidateViewer(viewer) then return false, "Unknown viewer." end
    if not ns.Schema.ValidateName(name) then return false, "Invalid group name." end
    local spec = db.profile.specs[currentSpec]
    if #groupIDs >= ns.Schema.maxGroups or spec.nextGroupID > 999999999 then
        return false, "The group limit has been reached."
    end
    local id = "group-" .. spec.nextGroupID
    spec.nextGroupID = spec.nextGroupID + 1
    spec.groups[id] = ns.Schema.NewGroup(viewer, name)
    Resolve()
    onChanged("groups", id, "DATA", viewer)
    return true, id
end

function Settings.DeleteGroup(groupID)
    local group, message = EditableGroup(groupID)
    if not group then return false, message end
    if effective[groupID].isDefault then return false, "Default groups cannot be deleted." end
    local viewer = group.viewer
    local spec = db.profile.specs[currentSpec]
    for key, assignment in pairs(spec.assignments) do
        if assignment.groupID == groupID then spec.assignments[key] = nil end
    end
    spec.groups[groupID] = nil
    Resolve()
    onChanged("groups", groupID, "DATA", viewer)
    return true
end

function Settings.SetEntryOrder(groupID, keys)
    local group, message = EditableGroup(groupID)
    if not group then return false, message end
    if not ns.Util.IsPublic(keys) or type(keys) ~= "table" or #keys > 10000 then
        return false, "Invalid entry order."
    end
    local seen, count, length = {}, 0, #keys
    for index, key in pairs(keys) do
        local number = ns.Util.Number(index)
        if not number or number < 1 or number > length or number ~= math.floor(number) then
            return false, "Invalid entry order."
        end
        if ns.Schema.ParseSourceKey(key) ~= group.viewer then return false, "Entries must stay in their original viewer." end
        if seen[key] then return false, "Invalid entry order." end
        seen[key] = true
        count = count + 1
    end
    if count ~= length then return false, "Invalid entry order." end
    local stored = db.profile.specs[currentSpec].assignments
    for index, key in ipairs(keys) do stored[key] = { groupID = groupID, order = index } end
    Resolve()
    onChanged("assignment", groupID, "DATA", group.viewer)
    return true
end

function Settings.SetGroupStyleValue(groupID, key, value)
    local group, message = EditableGroup(groupID)
    if not group then return false, message end
    if not ns.Schema.ValidateStyleValue(key, value) then return false, "Invalid appearance value." end
    group.style[key] = type(value) == "table" and { value[1], value[2], value[3], value[4] } or value
    Resolve()
    onChanged("group-style", groupID, "STYLE")
    return true
end

function Settings.ResetGroupStyle(groupID)
    local group, message = EditableGroup(groupID)
    if not group then return false, message end
    group.style = {}
    Resolve()
    onChanged("group-style", groupID, "STYLE")
    return true
end

function Settings.GetSnapshot()
    local profiles = db and db:GetProfiles() or {}
    table.sort(profiles)
    local result = {
        specID = currentSpec, profile = db and db:GetCurrentProfile() or "",
        profiles = profiles, error = failure,
        presentation = db and not failure and ns.Util.Copy(db.profile.presentation) or {},
        groups = {},
    }
    for _, id in ipairs(groupIDs) do
        if effective[id] then result.groups[#result.groups + 1] = ns.Util.Copy(effective[id]) end
    end
    return result
end

function Settings.SetGroupValue(groupID, key, value)
    local group, message = EditableGroup(groupID)
    if not group then return false, message end
    if not ns.Schema.ValidateGroupValue(key, value) then return false, "Invalid layout value." end
    if key == "name" then value = value:match("^%s*(.-)%s*$") end
    group[key] = value
    Resolve()
    onChanged("group", groupID, key == "name" and "STYLE" or "LAYOUT")
    return true
end

function Settings.SetPresentationValue(key, value)
    if failure or not db then return false, failure or "CDM is not ready." end
    if not ns.Schema.ValidateStyleValue(key, value) then return false, "Invalid appearance value." end
    if type(value) == "table" then value = { value[1], value[2], value[3], value[4] } end
    db.profile.presentation[key] = value
    Resolve()
    onChanged("presentation", nil, "STYLE")
    return true
end

function Settings.SelectProfile(name)
    if not db then return false, failure or "CDM is not ready." end
    if not ns.Util.IsPublic(name) or type(name) ~= "string" then return false, "Invalid profile name." end
    name = name:match("^%s*(.-)%s*$")
    if #name == 0 or #name > 50 or name:find("%c") then return false, "Invalid profile name." end
    -- Do not activate a future-schema profile and then normalize it away.
    local stored = db.sv.profiles[name]
    if type(stored) == "table" then
        local version = ns.Util.Number(rawget(stored, "schemaVersion"))
        if version and version > ns.Schema.version then return false, "This profile needs a newer CDM version." end
    end
    db:SetProfile(name)
    return not failure, failure
end
