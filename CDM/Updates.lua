local addonName, ns = ...
local Updates = {}
ns.Updates = Updates
local pending, deferred, counts = {}, {}, {}
local scheduled, processing = false, false
local process, getGroupIDs, completed

local Flush
local function Schedule()
    if scheduled or processing then return end
    scheduled = true
    C_Timer.After(0, Flush)
end

Flush = function()
    scheduled = false
    if processing then return end
    local batch = pending
    pending = {}
    processing = true
    local context = {}
    local worked = false
    for _, groupID in ipairs(getGroupIDs and getGroupIDs() or ns.Constants.groupIDs) do
        local reasons = batch[groupID]
        if reasons then
            worked = true
            local count = counts[groupID] or { DATA = 0, LAYOUT = 0, STYLE = 0 }
            counts[groupID] = count
            for reason in pairs(reasons) do count[reason] = count[reason] + 1 end
            local ok, message = pcall(process, groupID, reasons, context)
            if not ok then geterrorhandler()(message) end
        end
    end
    processing = false
    if worked and completed then
        local ok, message = pcall(completed)
        if not ok then geterrorhandler()(message) end
    end
    if next(pending) then Schedule() end
end

function Updates.Initialize(callback, groupsCallback, completedCallback)
    process, getGroupIDs, completed = callback, groupsCallback, completedCallback
end

function Updates.Mark(groupID, reason)
    if reason ~= "DATA" and reason ~= "LAYOUT" and reason ~= "STYLE" then return end
    if not pending[groupID] then pending[groupID] = {} end
    pending[groupID][reason] = true
    Schedule()
end

function Updates.MarkAll(reason)
    for _, groupID in ipairs(getGroupIDs and getGroupIDs() or ns.Constants.groupIDs) do Updates.Mark(groupID, reason) end
end

function Updates.Defer(groupID)
    deferred[groupID] = true
end

function Updates.Resume()
    local dirty = deferred
    deferred = {}
    for groupID in pairs(dirty) do Updates.Mark(groupID, "DATA") end
end

function Updates.GetSnapshot()
    return { pending = ns.Util.Copy(pending), deferred = ns.Util.Copy(deferred), passes = ns.Util.Copy(counts) }
end
