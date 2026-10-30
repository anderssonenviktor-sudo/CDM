local AddonName = "CDM"
local CDM = _G[AddonName]
local Pixel = CDM.Pixel
local Snap = Pixel.Snap

local GetFrameData = CDM.GetFrameData
local IsSafeNumber = CDM.IsSafeNumber
local InCombatLockdown = InCombatLockdown
CDM.GroupContainerUtils = {}

function CDM.GroupContainerUtils.AssignGroupSortKeys(frames, spellOrder, frameDataKey)
    for _, frame in ipairs(frames) do
        local fd = GetFrameData(frame)
        local fID = fd[frameDataKey]
        local ord = fID and spellOrder[fID] or nil
        if not ord then
            local fInfo = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
            if fInfo and fInfo.linkedSpellIDs then
                for _, lid in ipairs(fInfo.linkedSpellIDs) do
                    if IsSafeNumber(lid) then
                        ord = spellOrder[lid]
                        if ord then break end
                    end
                end
            end
        end
        fd.cdmSortKey = ord or 999
    end
end

-- Targets owned by CDM's cast bar and resource modules rather than a viewer.
local EXTERNAL_TARGETS = { castBar = true, resources = true }

local TARGET_ANCHORED = {
    essential = true, utility = true, buff = true, buffBar = true,
    playerFrame = true, castBar = true, resources = true,
}

-- True when the group's visibility follows its anchor target, so the caller
-- must not force-show a container that UpdateContainerPosition hid.
function CDM.GroupContainerUtils.IsTargetAnchored(anchorTarget)
    return TARGET_ANCHORED[anchorTarget] == true
end

-- Returns frame, followHidden. The cast bar container and resource bars keep
-- their points while hidden (cast bar disabled, bar load conditions), so groups
-- stay anchored to them instead of disappearing or jumping. The fallback to the
-- Essential viewer mirrors the cast bar's own "resources" anchor fallback.
function CDM.GroupContainerUtils.ResolveExternalAnchorTarget(anchorTarget)
    if not EXTERNAL_TARGETS[anchorTarget] then return nil end
    if anchorTarget == "castBar" then
        if CDM.castBarContainer then return CDM.castBarContainer, true end
    elseif not (CDM.db and CDM.db.resourcesEnabled == false) and CDM.ResolveResourcesAnchor then
        local bar = CDM.ResolveResourcesAnchor(true)
        if bar then return bar, true end
    end
    local containers = CDM.anchorContainers
    return containers and containers[CDM.CONST.VIEWERS.ESSENTIAL], false
end

function CDM.GroupContainerUtils.AnchorToTarget(container, targetContainer, anchorPoint, relativePoint, offsetX, offsetY, followHidden)
    if not targetContainer or (not followHidden and not targetContainer:IsShown()) then
        container:ClearAllPoints()
        container:Hide()
        return false
    end
    container:ClearAllPoints()
    Pixel.SetGridPoint(container, anchorPoint, targetContainer, relativePoint, offsetX, offsetY)
    if not container:IsShown() then
        container:Show()
    end
    return true
end

local descriptors = {}

function CDM.GroupContainerUtils.CreateDescriptor(opts)
    local desc = {}
    descriptors[#descriptors + 1] = desc
    desc.containers = opts.containers
    desc.registered = {}

    local namePrefix = opts.namePrefix
    local callbackPrefix = opts.callbackPrefix
    local getSets = opts.getSets

    function desc:GetOrCreateContainer(groupIndex)
        if self.containers[groupIndex] then
            return self.containers[groupIndex]
        end

        local container = CreateFrame("Frame", namePrefix .. groupIndex, UIParent)
        container:SetSize(1, 1)
        container:SetClampedToScreen(false)
        container:Show()

        self.containers[groupIndex] = container
        return container
    end

    function desc:UpdateContainerPosition(groupIndex, groupData, getAnchorTarget)
        local container = self.containers[groupIndex]
        if not container or not groupData then return end

        local anchorTarget = groupData.anchorTarget or "screen"
        local anchorPoint = groupData.anchorPoint or "CENTER"
        local relativePoint = groupData.anchorRelativeTo or "CENTER"
        local offsetX = groupData.offsetX or 0
        local offsetY = groupData.offsetY or 0

        local iconW = groupData.iconWidth or 30
        local iconH = groupData.iconHeight or 30
        Pixel.SetSize(container, iconW, iconH)

        if anchorTarget == "playerFrame" then
            CDM.AnchorToPlayerFrame(
                container,
                relativePoint,
                offsetX, offsetY,
                callbackPrefix .. groupIndex,
                false,
                anchorPoint
            )
        else
            CDM.InvalidateTrackerAnchorCache(container)
            local targetContainer, followHidden
            if EXTERNAL_TARGETS[anchorTarget] then
                targetContainer, followHidden = CDM.GroupContainerUtils.ResolveExternalAnchorTarget(anchorTarget)
            else
                targetContainer = getAnchorTarget(anchorTarget)
            end
            if targetContainer then
                CDM.GroupContainerUtils.AnchorToTarget(container, targetContainer, anchorPoint, relativePoint, offsetX, offsetY, followHidden)
            elseif anchorTarget == "screen" then
                container:ClearAllPoints()
                Pixel.SetPoint(container, "CENTER", UIParent, "CENTER", offsetX, offsetY)
                if not container:IsShown() then
                    container:Show()
                end
            else
                if container:IsShown() then
                    container:Hide()
                end
            end
        end
    end

    function desc:SyncCallbacks(getAnchorTarget)
        local sets = getSets()
        local groups = sets and sets.groups
        local needed = {}

        if groups then
            for idx, gd in ipairs(groups) do
                if (gd.anchorTarget or "screen") == "playerFrame" then
                    needed[idx] = true
                end
            end
        end

        for idx in pairs(needed) do
            if not self.registered[idx] then
                local capturedIdx = idx
                CDM.RegisterTrackerPositionCallback(callbackPrefix .. capturedIdx, function()
                    local s = getSets()
                    local g = s and s.groups and s.groups[capturedIdx]
                    if g and (g.anchorTarget or "screen") == "playerFrame" then
                        CDM.InvalidateTrackerAnchorCache(self.containers[capturedIdx])
                        self:UpdateContainerPosition(capturedIdx, g, getAnchorTarget)
                    end
                end)
                self.registered[idx] = true
            end
        end

        local toRemove
        for idx in pairs(self.registered) do
            if not needed[idx] then
                if not toRemove then toRemove = {} end
                toRemove[#toRemove + 1] = idx
            end
        end
        if toRemove then
            for _, idx in ipairs(toRemove) do
                CDM.UnregisterTrackerPositionCallback(callbackPrefix .. idx)
                self.registered[idx] = nil
            end
        end
    end

    desc.getSets = getSets
    return desc
end

local function NoAnchorTarget() return nil end
local externalRefreshPending = false

local function FlushPendingExternalRefresh(isInCombat)
    if isInCombat or not externalRefreshPending then return end
    externalRefreshPending = false
    CDM:RefreshExternalGroupAnchors()
end

-- Re-resolves groups anchored to the cast bar or resource bars. Their target
-- frame can change without a group refresh (cast bar toggled, a different
-- resource bar on top), so the cast bar and resource modules call this.
function CDM:RefreshExternalGroupAnchors()
    local buffTarget = self.db and self.db.buffAnchorTarget
    if EXTERNAL_TARGETS[buffTarget] and self.UpdateBuffContainerPosition then
        self:UpdateBuffContainerPosition()
    end
    local inCombat = InCombatLockdown()
    for _, desc in ipairs(descriptors) do
        local sets = desc.getSets()
        local groups = sets and sets.groups
        if groups then
            for idx, gd in ipairs(groups) do
                local container = desc.containers[idx]
                if container and EXTERNAL_TARGETS[gd.anchorTarget] then
                    -- A container becomes protected once a protected viewer
                    -- frame anchors to it; moving it then waits for combat end.
                    if inCombat and container:IsProtected() then
                        if not externalRefreshPending then
                            externalRefreshPending = true
                            -- InternalCallbacks loads after this file.
                            CDM:RegisterCombatStateHandler(FlushPendingExternalRefresh)
                        end
                    else
                        desc:UpdateContainerPosition(idx, gd, NoAnchorTarget)
                    end
                end
            end
        end
    end
end

-- A RESOURCES-only refresh rebuilds the bars without updating the cast bar.
CDM:RegisterRefreshCallback("externalGroupAnchors", function()
    CDM:RefreshExternalGroupAnchors()
end, 56, { "RESOURCES" })
