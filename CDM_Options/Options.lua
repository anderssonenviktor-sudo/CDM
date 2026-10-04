local addonName, ns = ...
local API = _G.CDM_API
local AceGUI = LibStub("AceGUI-3.0")
local Create = ns.OptionsSkin.Create
local L = setmetatable({}, { __index = function(_, key) return API.GetText(key) end })
local window, tabs, spellOrder
local groupPopup
local entriesSignature
local selectedGroup = "essential-main"
local selectedTab = "layout"
local selectedEntry
local appearanceScope = "profile"
local windowGeneration = 0
local editing, queued = false, false
local listener = {}
local Build
local names = { essential = L["Essential"], utility = L["Utility"], buff = L["Buff icons"] }
local states = {
    disabled = L["Blizzard Cooldown Manager is disabled. Enable it in Blizzard's settings."],
    unavailable = L["Blizzard Cooldown Manager is unavailable for this character."],
    missing = L["Waiting for Blizzard's cooldown viewer to load."],
    empty = L["No tracked entries. Choose spells in Blizzard's Cooldown Manager settings."],
    hidden = L["Blizzard currently hides this viewer. Check its Edit Mode visibility setting."],
    secret = L["Entry identities are currently restricted. Blizzard keeps control until they are available."],
}

local function Label(parent, text)
    local widget = Create("Label")
    widget:SetText(text)
    widget:SetFullWidth(true)
    parent:AddChild(widget)
    return widget
end

local function Heading(parent, text)
    local widget = Create("Heading")
    widget:SetText(text)
    widget:SetFullWidth(true)
    parent:AddChild(widget)
end

local function Command(callback)
    editing = true
    local ok, message = callback()
    editing = false
    if not ok then print(L["CDM:"] .. " " .. L[message or "Setting could not be changed."]) end
    return ok, message
end

local function Dropdown(parent, label, choices, order, value, callback)
    local widget = Create("Dropdown")
    widget:SetLabel(label)
    widget:SetList(choices, order)
    widget:SetValue(value)
    widget:SetFullWidth(true)
    widget:SetCallback("OnValueChanged", function(_, _, newValue) callback(newValue) end)
    parent:AddChild(widget)
    return widget
end

local function Button(parent, text, callback, disabled)
    local widget = Create("Button")
    widget:SetText(text)
    widget:SetDisabled(not not disabled)
    widget:SetRelativeWidth(0.5)
    widget:SetCallback("OnClick", callback)
    parent:AddChild(widget)
    return widget
end

local function GroupName(group)
    return group.name or names[group.viewer]
end

local function EntrySignature(snapshot)
    local values = { snapshot.profile, tostring(snapshot.specID), snapshot.error or "" }
    for _, group in ipairs(snapshot.groups) do
        values[#values + 1] = group.id .. ":" .. group.status.state
    end
    for _, viewer in ipairs({ "essential", "utility", "buff" }) do
        for _, entry in ipairs(snapshot.entries and snapshot.entries[viewer] or {}) do
            values[#values + 1] = entry.key .. ":" .. entry.groupID .. ":" .. entry.order .. ":" .. entry.name
                .. ":" .. tostring(entry.spellID) .. ":" .. tostring(entry.icon)
        end
    end
    return table.concat(values, "\n")
end

local function CloseGroupPopup()
    if not groupPopup then return end
    local popup = groupPopup
    groupPopup = nil
    AceGUI:Release(popup)
end

local function OpenGroupPopup(snapshot, viewer)
    if groupPopup then groupPopup:Show(); return end
    local profile, specID = snapshot.profile, snapshot.specID
    local draftViewer = viewer or "essential"
    groupPopup = Create("CDMGroupPopup")
    local popup = groupPopup
    popup:PauseLayout()
    popup:SetOwner(window)
    popup:SetLayout("Flow")
    popup:SetCallback("OnClose", CloseGroupPopup)
    local source = Create("Dropdown")
    source:SetLabel(L["Source viewer"])
    source:SetList(names, { "essential", "utility", "buff" })
    source:SetValue(draftViewer)
    source:SetWidth(200)
    source:SetCallback("OnValueChanged", function(_, _, value) draftViewer = value end)
    popup:AddChild(source)
    local name = Create("EditBox")
    name:SetLabel(L["New group name"])
    name:SetFullWidth(true)
    name:SetMaxLetters(80)
    name:DisableButton(true)
    popup:AddChild(name)
    local function Create()
        if groupPopup ~= popup then return end
        local current = API.GetSnapshot()
        if current.profile ~= profile or current.specID ~= specID then CloseGroupPopup(); return end
        local ok, id = Command(function() return API.CreateGroup(draftViewer, name:GetText()) end)
        if ok then
            CloseGroupPopup()
            selectedGroup, selectedEntry = id, nil
            Build()
        end
    end
    name:SetCallback("OnEnterPressed", Create)
    Button(popup, L["OK"], Create)
    Button(popup, L["Cancel"], function() if groupPopup == popup then CloseGroupPopup() end end)
    popup:ResumeLayout()
    popup:DoLayout()
    name:SetFocus()
end

local function GroupPicker(parent, snapshot)
    local choices, order, config = {}, {}, nil
    for _, group in ipairs(snapshot.groups) do
        choices[group.id] = string.format(L["%s - %s"], names[group.viewer], GroupName(group))
        order[#order + 1] = group.id
        if group.id == selectedGroup then config = group end
    end
    local header = Create("SimpleGroup")
    header:PauseLayout()
    header:SetLayout("CDMGroupHeader")
    header:SetAutoAdjustHeight(false)
    header:SetFullWidth(true)
    header:SetHeight(48)
    local dropdown = Create("CDMCenteredDropdown")
    dropdown:SetLabel(L["Group"])
    dropdown:SetList(choices, order)
    dropdown:SetValue(selectedGroup)
    dropdown:SetCallback("OnValueChanged", function(_, _, value)
        CloseGroupPopup()
        selectedGroup, selectedEntry = value, nil
        Build()
    end)
    header:AddChild(dropdown)
    Button(header, L["New group"], function() OpenGroupPopup(snapshot, config and config.viewer) end, not config)
    parent:AddChild(header)
    header:ResumeLayout()
    return config
end

local function Slider(parent, label, value, low, high, step, callback)
    local widget = Create("Slider")
    widget:SetLabel(label)
    widget:SetSliderValues(low, high, step)
    widget:SetValue(value)
    widget:SetRelativeWidth(0.5)
    widget:SetCallback("OnValueChanged", function(_, _, newValue)
        Command(function() return callback(newValue) end)
    end)
    parent:AddChild(widget)
end

local function SpellStrip(parent, snapshot, config)
    local entries = {}
    for _, entry in ipairs(snapshot.entries and snapshot.entries[config.viewer] or {}) do
        if entry.groupID == config.id then entries[#entries + 1] = entry end
    end
    if #entries == 0 then
        Label(parent, states[config.status.state] or L["This group has no assigned entries."])
        return
    end
    local signature = EntrySignature(snapshot)
    spellOrder = Create("CDMSpellOrder")
    spellOrder:SetFullWidth(true)
    spellOrder:SetEntries(entries)
    spellOrder:SetCallback("OnReorder", function(_, _, key, beforeKey)
        -- A drag may overlap a spec/profile or Blizzard metadata transition.
        -- Cancel it instead of saving an order from that old page.
        if EntrySignature(API.GetSnapshot()) ~= signature then Build(); return end
        Command(function() return API.ReorderEntry(config.id, key, beforeKey) end)
        Build()
    end)
    parent:AddChild(spellOrder)
end

local function LayoutPage(parent, snapshot)
    local config = GroupPicker(parent, snapshot)
    if not config then return end
    local groupID = config.id
    SpellStrip(parent, snapshot, config)
    Heading(parent, L["Position and icon layout"])
    for _, definition in ipairs({
        { "x", L["Horizontal offset"], -4000, 4000, 1 },
        { "y", L["Vertical offset"], -4000, 4000, 1 },
        { "width", L["Icon width"], 16, 128, 1 },
        { "height", L["Icon height"], 16, 128, 1 },
        { "spacing", L["Spacing"], 0, 32, 1 },
        { "perRow", (config.growth == "LEFT" or config.growth == "RIGHT") and L["Icons per column"] or L["Icons per row"], 1, 40, 1 },
    }) do
        local key = definition[1]
        Slider(parent, definition[2], config[key], definition[3], definition[4], definition[5], function(value)
            return API.SetGroupValue(groupID, key, value)
        end)
    end
    Dropdown(parent, L["Growth direction"], { DOWN = L["Down"], UP = L["Up"], LEFT = L["Left"], RIGHT = L["Right"] },
        { "DOWN", "UP", "LEFT", "RIGHT" }, config.growth, function(value)
            Command(function() return API.SetGroupValue(groupID, "growth", value) end)
            Build()
        end)
    Dropdown(parent, L["Align the final row or column"], { START = L["Start"], CENTER = L["Center"], END = L["End"] },
        { "START", "CENTER", "END" }, config.alignment, function(value)
            Command(function() return API.SetGroupValue(groupID, "alignment", value) end)
        end)
    Heading(parent, L["Manage groups"])
    local rename = Create("EditBox")
    rename:SetLabel(L["Group name (press Enter to save)"])
    rename:SetText(GroupName(config))
    rename:SetFullWidth(true)
    rename:SetCallback("OnEnterPressed", function(_, _, value)
        Command(function() return API.SetGroupValue(groupID, "name", value) end)
        Build()
    end)
    parent:AddChild(rename)
    Button(parent, L["Delete group"], function()
        if Command(function() return API.DeleteGroup(groupID) end) then
            selectedGroup, selectedEntry = nil, nil
            Build()
        end
    end, config.isDefault)
    Label(parent, L["Default groups are retained. Deleting a custom group returns its entries to the viewer's default group."])
end

local function EntriesPage(parent, snapshot)
    local config = GroupPicker(parent, snapshot)
    if not config then return end
    Label(parent, L["These are Blizzard's existing tracked entries. Assignments are saved separately for each specialization."])
    local entries = snapshot.entries and snapshot.entries[config.viewer] or {}
    local choices, order, groupChoices, groupOrder, selected, count = {}, {}, {}, {}, nil, 0
    for _, group in ipairs(snapshot.groups) do
        if group.viewer == config.viewer then
            groupChoices[group.id] = GroupName(group)
            groupOrder[#groupOrder + 1] = group.id
        end
    end
    for _, entry in ipairs(entries) do
        choices[entry.key] = string.format(L["%s - %s"], entry.name, groupChoices[entry.groupID])
        order[#order + 1] = entry.key
        if entry.groupID == config.id then count = count + 1 end
        if entry.key == selectedEntry then selected = entry end
    end
    if not selected then
        for _, entry in ipairs(entries) do
            if not selected or entry.groupID == config.id then selected = entry end
            if entry.groupID == config.id then break end
        end
    end
    selectedEntry = selected and selected.key or nil
    if not selected then
        Label(parent, L["No public tracked entries are available in this viewer. Choose entries in Blizzard's Cooldown Manager settings, then return here."])
        return
    end
    Dropdown(parent, L["Tracked entry"], choices, order, selectedEntry, function(value) selectedEntry = value; Build() end)
    local key = selected.key
    Dropdown(parent, L["Assigned group"], groupChoices, groupOrder, selected.groupID, function(value)
        if Command(function() return API.AssignEntry(key, value) end) then selectedGroup = value; Build() end
    end)
    Button(parent, L["Move earlier"], function() Command(function() return API.MoveEntry(key, -1) end); Build() end,
        selected.groupID ~= config.id or selected.order == 1)
    Button(parent, L["Move later"], function() Command(function() return API.MoveEntry(key, 1) end); Build() end,
        selected.groupID ~= config.id or selected.order == count)
    Heading(parent, L["Current group order"])
    local lines = {}
    for _, entry in ipairs(entries) do
        if entry.groupID == config.id then lines[#lines + 1] = string.format(L["%d. %s"], entry.order, entry.name) end
    end
    Label(parent, #lines > 0 and table.concat(lines, "\n") or L["This group has no assigned entries."])
    if config.viewer == "buff" then
        Label(parent, L["Buff slots follow tracked entry order. Blizzard hides inactive buffs; the remaining slots do not move based on aura activity."])
    end
end

local function AppearancePage(parent, snapshot)
    Dropdown(parent, L["Appearance scope"], { profile = L["Profile defaults"], group = L["Selected group"] },
        { "profile", "group" }, appearanceScope, function(value) appearanceScope = value; Build() end)
    local style = snapshot.presentation
    local config
    if appearanceScope == "group" then
        config = GroupPicker(parent, snapshot)
        if not config then return end
        style = config.style
        Label(parent, L["Changes override this group's profile defaults for the current specialization."])
        Button(parent, L["Use profile appearance"], function() Command(function() return API.ResetGroupStyle(config.id) end); Build() end)
    else
        Label(parent, L["Appearance defaults apply to all groups across this profile's specializations."])
    end
    local function SetValue(key, value)
        if config then return API.SetGroupStyleValue(config.id, key, value) end
        return API.SetPresentationValue(key, value)
    end
    if not style.font then return end
    local font = Create("Dropdown")
    font:SetLabel(L["Font"])
    font:SetList(API.GetFonts())
    font:SetValue(style.font)
    font:SetFullWidth(true)
    font:SetCallback("OnValueChanged", function(_, _, value)
        Command(function() return SetValue("font", value) end)
    end)
    parent:AddChild(font)
    for _, definition in ipairs({
        { "crop", L["Texture crop"], 0, 0.3, 0.01 },
        { "borderSize", L["Border thickness"], 0, 8, 1 },
        { "cooldownTextSize", L["Cooldown text size"], 8, 40, 1 },
        { "chargeTextSize", L["Charge text size"], 8, 40, 1 },
        { "stackTextSize", L["Buff stack text size"], 8, 40, 1 },
    }) do
        local key = definition[1]
        Slider(parent, definition[2], style[key], definition[3], definition[4], definition[5], function(value)
            return SetValue(key, value)
        end)
    end
    for _, definition in ipairs({
        { "borderColor", L["Border color"] }, { "cooldownColor", L["Cooldown text color"] },
        { "chargeColor", L["Charge text color"] },
        { "stackColor", L["Buff stack text color"] },
    }) do
        local key = definition[1]
        local color = Create("ColorPicker")
        color:SetLabel(definition[2])
        color:SetHasAlpha(true)
        color:SetColor(unpack(style[key]))
        color:SetRelativeWidth(0.5)
        color:SetCallback("OnValueConfirmed", function(_, _, r, g, b, a)
            Command(function() return SetValue(key, { r, g, b, a }) end)
        end)
        parent:AddChild(color)
    end
    Label(parent, L["Cooldown numbers follow Blizzard's Show Timer setting. Charge values and cooldown timing remain controlled by Blizzard."])
end

local function ProfilesPage(parent, snapshot)
    Label(parent, string.format(L["Current profile: %s. Specialization ID: %d."], snapshot.profile, snapshot.specID))
    local dropdown = Create("Dropdown")
    local profiles = {}
    for _, name in ipairs(snapshot.profiles) do profiles[name] = name end
    dropdown:SetLabel(L["Choose profile"])
    dropdown:SetList(profiles)
    dropdown:SetValue(snapshot.profile)
    dropdown:SetFullWidth(true)
    dropdown:SetCallback("OnValueChanged", function(_, _, value)
        Command(function() return API.SelectProfile(value) end)
        Build()
    end)
    parent:AddChild(dropdown)
    local name = Create("EditBox")
    name:SetLabel(L["Create or switch to a named profile"])
    name:SetFullWidth(true)
    name:SetCallback("OnEnterPressed", function(_, _, value)
        Command(function() return API.SelectProfile(value) end)
        Build()
    end)
    parent:AddChild(name)
    Label(parent, L["New profiles start with CDM defaults. Existing layouts are kept in their original profiles."])
end

Build = function()
    if not window then return end
    local snapshot = API.GetSnapshot()
    entriesSignature = EntrySignature(snapshot)
    local found = false
    for _, group in ipairs(snapshot.groups) do if group.id == selectedGroup then found = true; break end end
    if not found then selectedGroup = snapshot.groups[1] and snapshot.groups[1].id or nil; selectedEntry = nil end
    tabs:PauseLayout()
    tabs:ReleaseChildren()
    spellOrder = nil
    local scroll = Create("ScrollFrame")
    scroll:PauseLayout()
    scroll:SetLayout("Flow")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    tabs:AddChild(scroll)
    if snapshot.error then Label(scroll, L[snapshot.error]) end
    if selectedTab == "appearance" then AppearancePage(scroll, snapshot)
    elseif selectedTab == "entries" then EntriesPage(scroll, snapshot)
    elseif selectedTab == "profiles" then ProfilesPage(scroll, snapshot)
    else LayoutPage(scroll, snapshot) end
    tabs:ResumeLayout()
    tabs:DoLayout()
    scroll:ResumeLayout()
    scroll:DoLayout()
end

local function QueueBuild()
    if not queued then
        queued = true
        local generation = windowGeneration
        C_Timer.After(0, function()
            if generation ~= windowGeneration then return end
            queued = false
            if window then Build() end
        end)
    end
end

local function Changed(kind)
    if not window then return end
    if kind == "profile" or kind == "spec" then CloseGroupPopup() end
    if kind == "status" or kind == "combat" or editing then
        local snapshot = API.GetSnapshot()
        if not editing and (selectedTab == "entries" or selectedTab == "layout")
            and EntrySignature(snapshot) ~= entriesSignature then
            if spellOrder then spellOrder:CancelDrag() end
            QueueBuild()
        end
    else
        if spellOrder then spellOrder:CancelDrag() end
        QueueBuild()
    end
end

function ns.Open()
    if window then window:Show(); Build(); return end
    window = Create("Frame")
    windowGeneration = windowGeneration + 1
    window:PauseLayout()
    window:SetTitle(L["CDM"])
    window:SetStatusText(L["Cooldown and buff groups"])
    window:SetWidth(620)
    window:SetHeight(620)
    window:EnableResize(false)
    window:SetLayout("List")
    window:SetCallback("OnClose", function(widget)
        API.UnregisterListener(listener)
        CloseGroupPopup()
        window, tabs, spellOrder = nil, nil, nil
        entriesSignature = nil
        queued = false
        windowGeneration = windowGeneration + 1
        AceGUI:Release(widget)
    end)
    tabs = Create("TabGroup")
    tabs:PauseLayout()
    -- Fill uses the tab content's height; auto-sizing the same container from
    -- that child feeds its border insets back into another size/layout pass.
    tabs:SetAutoAdjustHeight(false)
    tabs:SetTabs({
        { value = "layout", text = L["Groups & layout"] },
        { value = "entries", text = L["Entries"] },
        { value = "appearance", text = L["Appearance"] },
        { value = "profiles", text = L["Profiles"] },
    })
    tabs:SetLayout("Fill")
    tabs:SetFullWidth(true)
    tabs:SetHeight(430)
    tabs:SetCallback("OnGroupSelected", function(_, _, value)
        CloseGroupPopup()
        selectedTab = value
        Build()
    end)
    window:AddChild(tabs)
    API.RegisterListener(listener, Changed)
    tabs:SelectTab(selectedTab)
    window:ResumeLayout()
    window:DoLayout()
end

API.RegisterOptionsPanel(1, ns.Open)
