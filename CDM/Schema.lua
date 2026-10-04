local addonName, ns = ...
local Util = ns.Util
local Schema = { version = 2, maxGroups = 64 }
ns.Schema = Schema

local presentation = {
    font = "Friz Quadrata TT", cooldownTextSize = 16, chargeTextSize = 13,
    crop = 0.08, borderSize = 1, borderColor = { 0, 0, 0, 1 },
    cooldownColor = { 1, 1, 1, 1 }, chargeColor = { 1, 1, 1, 1 },
    stackTextSize = 13, stackColor = { 1, 1, 1, 1 },
}
local groups = {
    ["essential-main"] = {
        viewer = "essential", point = "CENTER", relativePoint = "CENTER",
        x = 0, y = -180, width = 44, height = 44, spacing = 4, perRow = 8,
    },
    ["utility-main"] = {
        viewer = "utility", point = "CENTER", relativePoint = "CENTER",
        x = 0, y = -245, width = 36, height = 36, spacing = 4, perRow = 8,
    },
    ["buff-main"] = {
        viewer = "buff", point = "CENTER", relativePoint = "CENTER",
        x = 0, y = -310, width = 40, height = 40, spacing = 4, perRow = 8,
    },
}
local points = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local groupRanges = {
    x = { -4000, 4000 }, y = { -4000, 4000 }, width = { 16, 128 },
    height = { 16, 128 }, spacing = { 0, 32 }, perRow = { 1, 40, true },
}
local styleRanges = {
    crop = { 0, 0.3 }, borderSize = { 0, 8 }, cooldownTextSize = { 8, 40 },
    chargeTextSize = { 8, 40 },
    stackTextSize = { 8, 40 },
}

local function InRange(value, range)
    local number = Util.Number(value)
    return number and number >= range[1] and number <= range[2]
        and (not range[3] or number == math.floor(number))
end

local function IsTable(value)
    return Util.IsPublic(value) and type(value) == "table"
end

function Schema.ValidateViewer(viewer)
    return Util.IsPublic(viewer) and type(viewer) == "string"
        and ns.Constants.viewers[viewer] ~= nil
end

function Schema.ValidateName(value)
    return Util.IsPublic(value) and type(value) == "string" and #value <= 80
        and value:find("%S") ~= nil and not value:find("%c")
end

function Schema.CustomGroupSerial(id)
    if not Util.IsPublic(id) or type(id) ~= "string" then return nil end
    local serial = tonumber(id:match("^group%-([1-9]%d*)$"))
    if serial and serial <= 999999999 then return serial end
end

function Schema.ParseSourceKey(key)
    if not Util.IsPublic(key) or type(key) ~= "string" or #key > 80 then return nil end
    local viewer, category, id = key:match("^blizzard:([%a]+):(%d+):(%d+)$")
    category, id = tonumber(category), tonumber(id)
    if Schema.ValidateViewer(viewer) and category and category <= 1000
        and id and id > 0 and id <= 2147483647
        and key == "blizzard:" .. viewer .. ":" .. category .. ":" .. id then
        return viewer, category, id
    end
end

function Schema.ValidateStyleValue(key, value)
    if not Util.IsPublic(key) or type(key) ~= "string" then return false end
    local range = styleRanges[key]
    if range then return not not InRange(value, range) end
    if key == "font" then
        return Util.IsPublic(value) and type(value) == "string"
            and #value > 0 and #value <= 100 and not value:find("%c")
    end
    if key == "borderColor" or key == "cooldownColor" or key == "chargeColor" or key == "stackColor" then
        if not IsTable(value) then return false end
        for index = 1, 4 do
            if not InRange(value[index], { 0, 1 }) then return false end
        end
        return true
    end
    return false
end

function Schema.ValidateGroupValue(key, value)
    if not Util.IsPublic(key) or type(key) ~= "string" then return false end
    if groupRanges[key] then return not not InRange(value, groupRanges[key]) end
    if key == "name" then return not not Schema.ValidateName(value) end
    if key == "growth" then
        return Util.IsPublic(value) and (value == "DOWN" or value == "UP" or value == "LEFT" or value == "RIGHT")
    end
    if key == "alignment" then
        return Util.IsPublic(value) and (value == "START" or value == "CENTER" or value == "END")
    end
    if key == "point" or key == "relativePoint" then
        return Util.IsPublic(value) and type(value) == "string" and points[value] == true
    end
    return false
end

local CleanStyle
local function CleanGroup(raw, viewer)
    raw = IsTable(raw) and raw or {}
    local default = groups[ns.Constants.viewers[viewer].groupID]
    local result = { viewer = viewer, style = CleanStyle(raw.style, false) }
    for key, value in pairs(default) do
        if key ~= "viewer" then
            result[key] = Schema.ValidateGroupValue(key, raw[key]) and raw[key] or value
        end
    end
    for key, value in pairs({ growth = "DOWN", alignment = "CENTER" }) do
        result[key] = Schema.ValidateGroupValue(key, raw[key]) and raw[key] or value
    end
    if Schema.ValidateName(raw.name) then result.name = raw.name:match("^%s*(.-)%s*$") end
    return result
end

function Schema.NewGroup(viewer, name)
    return CleanGroup({ name = name }, viewer)
end

function Schema.GetGroupIDs(configs)
    local result, ranks = {}, {}
    for index, viewer in ipairs(ns.Constants.viewerIDs) do ranks[viewer] = index end
    for id in pairs(configs) do result[#result + 1] = id end
    table.sort(result, function(a, b)
        if a == b then return false end
        local av, bv = configs[a].viewer, configs[b].viewer
        if av ~= bv then return ranks[av] < ranks[bv] end
        local default = ns.Constants.viewers[av].groupID
        if a == default then return true end
        if b == default then return false end
        return Schema.CustomGroupSerial(a) < Schema.CustomGroupSerial(b)
    end)
    return result
end

CleanStyle = function(raw, useDefaults)
    local result = {}
    raw = IsTable(raw) and raw or {}
    for key, default in pairs(presentation) do
        if Schema.ValidateStyleValue(key, raw[key]) then
            -- Copy only recognized color components; reject arbitrary payloads.
            local value = raw[key]
            if type(default) == "table" then
                result[key] = { value[1], value[2], value[3], value[4] }
            else
                result[key] = value
            end
        elseif useDefaults then
            result[key] = Util.Copy(default)
        end
    end
    return result
end

local function CleanSpec(raw)
    raw = IsTable(raw) and raw or {}
    local rawGroups = IsTable(raw.groups) and raw.groups or {}
    local result = { groups = {}, assignments = {}, nextGroupID = 1 }
    for id, default in pairs(groups) do
        result.groups[id] = CleanGroup(rawGroups[id], default.viewer)
    end
    local custom, highest = {}, 0
    for id, group in pairs(rawGroups) do
        local serial = Schema.CustomGroupSerial(id)
        if serial and IsTable(group) and Schema.ValidateViewer(group.viewer) then
            custom[#custom + 1] = id
            highest = math.max(highest, serial)
        end
    end
    table.sort(custom, function(a, b) return Schema.CustomGroupSerial(a) < Schema.CustomGroupSerial(b) end)
    for index = 1, math.min(#custom, Schema.maxGroups - #ns.Constants.groupIDs) do
        local id = custom[index]
        result.groups[id] = CleanGroup(rawGroups[id], rawGroups[id].viewer)
    end
    local serial = InRange(raw.nextGroupID, { 1, 1000000000, true }) and raw.nextGroupID or 1
    result.nextGroupID = math.max(serial, highest + 1)
    if IsTable(raw.assignments) then
        for sourceKey, assignment in pairs(raw.assignments) do
            if Util.IsPublic(sourceKey) and type(sourceKey) == "string"
                and IsTable(assignment) and Util.IsPublic(assignment.groupID)
                and type(assignment.groupID) == "string" then
                local group = result.groups[assignment.groupID]
                local viewer = Schema.ParseSourceKey(sourceKey)
                if group and viewer == group.viewer
                    and InRange(assignment.order, { 1, 10000, true }) then
                    result.assignments[sourceKey] = {
                        groupID = assignment.groupID, order = assignment.order,
                    }
                end
            end
        end
    end
    return result
end

-- Version zero belongs only to this new addon. No external profile imports.
local migrations = {
    [1] = function(profile)
        if not IsTable(profile.presentation) then profile.presentation = {} end
        if not IsTable(profile.specs) then profile.specs = {} end
    end,
    [2] = function(profile)
        -- CleanSpec adds native buffs and normalizes custom groups while
        -- retaining version-one layouts, styles and valid assignments.
        if not IsTable(profile.specs) then profile.specs = {} end
    end,
}

function Schema.Upgrade(profile)
    if not IsTable(profile) then return false, "Invalid profile data." end
    local version = Util.Number(rawget(profile, "schemaVersion")) or 0
    if version > Schema.version then return false, "This profile needs a newer CDM version." end
    if version < 0 or version ~= math.floor(version) then version = 0 end
    for nextVersion = version + 1, Schema.version do
        migrations[nextVersion](profile)
        profile.schemaVersion = nextVersion
    end
    profile.presentation = CleanStyle(profile.presentation, true)
    local cleanSpecs = {}
    if IsTable(profile.specs) then
        for specID, spec in pairs(profile.specs) do
            if InRange(specID, { 0, 10000, true }) then cleanSpecs[specID] = CleanSpec(spec) end
        end
    end
    profile.specs = cleanSpecs
    profile.schemaVersion = Schema.version
    return true
end

function Schema.NewSpec()
    return CleanSpec({})
end

function Schema.DefaultPresentation()
    return Util.Copy(presentation)
end

function Schema.Resolve(profile, specID)
    if not profile.specs[specID] then profile.specs[specID] = Schema.NewSpec() end
    local spec = profile.specs[specID]
    local effective = {}
    for id, group in pairs(spec.groups) do
        local config = Util.Copy(group)
        config.id = id
        config.isDefault = id == ns.Constants.viewers[group.viewer].groupID
        config.styleOverrides = Util.Copy(group.style)
        config.style = Util.Copy(profile.presentation)
        for key, value in pairs(group.style) do config.style[key] = Util.Copy(value) end
        effective[id] = config
    end
    return effective, spec.assignments
end
