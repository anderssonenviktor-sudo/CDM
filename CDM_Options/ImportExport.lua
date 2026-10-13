local AddonName = "CDM"
local Runtime = _G[AddonName]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L
local ProfileIO = CDM.ProfileIO

local ConfigKeys = ns.ConfigKeys or {}
local exportCategories = ConfigKeys.categories or {}
local exportCategoryOrder = ConfigKeys.order or {}
local METADATA_KEYS = { version = true, addon = true, timestamp = true, profileName = true }
local IMPORT_STATUS_SUCCESS_DURATION = 3

local LEGACY_MIGRATION_KEYS = {
    "sizeBuffSecondary", "sizeBuffTertiary",
    "buffSecondaryOffsetX", "buffSecondaryOffsetY",
    "buffTertiaryOffsetX", "buffTertiaryOffsetY",
    "buffSecondaryHorizontal", "buffTertiaryHorizontal",
    "countPositionSec", "countOffsetXSec", "countOffsetYSec",
    "countPositionTert", "countOffsetXTert", "countOffsetYTert",
    "resourcesBarHeight", "resourcesBar2Height", "resourcesBarWidth",
    "resourcesBarTexture", "resourcesBarBackgroundTexture",
    "resourcesBackgroundColor", "resourcesBarSpacing",
    "resourcesOffsetX", "resourcesOffsetY",
    "resourcesBar1TagFontSize", "resourcesBar1TagAnchor",
    "resourcesBar1TagOffsetX", "resourcesBar1TagOffsetY", "resourcesBar1TagColor",
    "resourcesBar2TagFontSize", "resourcesBar2TagAnchor",
    "resourcesBar2TagOffsetX", "resourcesBar2TagOffsetY", "resourcesBar2TagColor",
    "resourcesManaColor", "resourcesRageColor", "resourcesEnergyColor",
    "resourcesFocusColor", "resourcesComboPointsColor",
    "resourcesComboPointsChargedColor", "resourcesComboPointsChargedEmptyColor",
    "resourcesFeralOverflowingColor", "resourcesFeralOverflowingEmptyColor",
    "resourcesRunesReadyColor", "resourcesRunesRechargingColor",
    "resourcesRunicPowerColor", "resourcesLunarPowerColor",
    "resourcesIronfurColor", "resourcesIgnorePainColor", "resourcesIgnorePainHideIcon",
    "resourcesMaelstromColor", "resourcesInsanityColor", "resourcesFuryColor",
    "resourcesEssenceColor", "resourcesEssenceRechargingColor",
    "resourcesSoulShardsColor", "resourcesSoulShardsRechargingColor",
    "resourcesHolyPowerColor", "resourcesArcaneChargesColor", "resourcesChiColor",
    "resourcesStaggerLightColor", "resourcesStaggerModerateColor",
    "resourcesStaggerHeavyColor", "resourcesSoulFragmentsColor",
    "resourcesDevourerSoulFragmentsColor", "resourcesTipOfTheSpearColor",
    "resourcesManaPercentage", "resourcesManaSettings",
    "resourcesPrimaryResourceSettings", "resourcesSecondaryResourceSettings",
    "resourcesTagSettings", "resourcesSmoothBars", "resourcesMoveBuffsDown",
    "resourcesUnifiedBorder",
}
local importExportLastStatus = nil
local importExportStatusTimer = nil
local activeStatusFontString = nil

local function CancelImportStatusTimer()
    if importExportStatusTimer then
        importExportStatusTimer:Cancel()
        importExportStatusTimer = nil
    end
end

ns.CancelImportStatusTimer = CancelImportStatusTimer

local function ClearImportStatus(fontString)
    CancelImportStatusTimer()
    importExportLastStatus = nil
    if fontString then
        fontString:SetText("")
        UI.SetTextMuted(fontString)
    end
end

local function ApplyImportStatus(fontString)
    local status = importExportLastStatus
    CancelImportStatusTimer()
    if not fontString then
        return
    end

    if not status or not status.message then
        fontString:SetText("")
        UI.SetTextMuted(fontString)
        return
    end

    if status.expiresAt and status.expiresAt <= GetTime() then
        ClearImportStatus(fontString)
        return
    end

    fontString:SetText(status.message)
    if status.success then
        UI.SetTextSuccess(fontString)
    else
        UI.SetTextError(fontString)
    end

    if status.expiresAt then
        importExportStatusTimer = C_Timer.NewTimer(math.max(0, status.expiresAt - GetTime()), function()
            importExportStatusTimer = nil
            importExportLastStatus = nil
            if fontString then
                fontString:SetText("")
                UI.SetTextMuted(fontString)
            end
        end)
    end
end

local function SetImportStatus(fontString, success, message)
    importExportLastStatus = {
        success = success,
        message = message,
        expiresAt = success and (GetTime() + IMPORT_STATUS_SUCCESS_DURATION) or nil,
    }
    ApplyImportStatus(activeStatusFontString or fontString)
end

local function MapImportErrorCode(errCode)
    if errCode == "invalid_base64" then
        return L["Invalid Base64 encoding"]
    end
    if errCode == "decompression_failed" then
        return L["Decompression failed"]
    end
    if errCode == "combat_blocked" then
        return L["Cannot open config while in combat"]
    end
    if errCode == "invalid_profile_version" then
        return L["Invalid profile version"]
    end
    if errCode == "missing_profile_metadata" then
        return L["Missing profile metadata"]
    end
    if errCode == "wrong_addon" then
        return L["Profile is for a different addon"]
    end
    if errCode == "empty" then
        return L["No import string provided"]
    end
    if errCode == "apply_failed" then
        return L["Failed to import profile"]
    end
    if errCode == "no_compatible_settings" then
        return L["No compatible SkironCDM settings found. Export a class or specialization profile, or include global settings."]
    end
    if errCode == "invalid_blizzard_tracking" then
        return L["Invalid Blizzard cooldown tracking data"]
    end
    return L["Invalid profile data"]
end

local TRACKED_CATEGORIES = {}
if Enum and Enum.CooldownViewerCategory then
    local category = Enum.CooldownViewerCategory
    for _, name in ipairs({ "Essential", "Utility", "TrackedBuff", "TrackedBar",
        "SpecAgnosticEssential", "SpecAgnosticTracked", "EquipSlotEssential", "EquipSlotTracked" }) do
        if category[name] then TRACKED_CATEGORIES[category[name]] = true end
    end
end

local function IsTrackedCategory(category)
    return category ~= nil and not (issecretvalue and issecretvalue(category))
        and TRACKED_CATEGORIES[category] == true
end

local function SafeID(value)
    if value == nil or issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" or value ~= value or value < 1 or value > 2147483647
        or value ~= math.floor(value) then return nil end
    return value
end

local function GetBlizzardProvider()
    local settings = _G.CooldownViewerSettings
    if not settings or not settings.GetDataProvider then return nil end
    local ok, provider = pcall(settings.GetDataProvider, settings)
    if not ok then return nil end
    if not provider or not provider.GetOrderedCooldownIDs or not provider.GetCooldownInfoForID then return nil end
    return settings, provider
end

local function ReadProviderEntries(provider)
    local ok, ids = pcall(provider.GetOrderedCooldownIDs, provider)
    if not ok or type(ids) ~= "table" then return nil end
    local result = {}
    for _, cooldownID in ipairs(ids) do
        if SafeID(cooldownID) then
            local infoOK, info = pcall(provider.GetCooldownInfoForID, provider, cooldownID)
            if not infoOK then return nil end
            if type(info) == "table" then result[#result + 1] = { id = cooldownID, info = info } end
        end
    end
    return result
end

local function CaptureBlizzardTracking()
    -- Blizzard owns these choices. Store a snapshot in the export envelope,
    -- not in CDM's sparse profile or SavedVariables.
    local specID = SafeID(CDM:GetCurrentSpecID())
    local _, provider = GetBlizzardProvider()
    if not specID or not provider then return nil end
    local providerEntries = ReadProviderEntries(provider)
    if not providerEntries then return nil end
    local entries = {}
    for _, entry in ipairs(providerEntries) do
        local category = entry.info.category
        if IsTrackedCategory(category) then
            entries[#entries + 1] = {
                cooldownID = entry.id,
                spellID = category ~= Enum.CooldownViewerCategory.EquipSlotEssential
                    and SafeID(entry.info.spellID) or nil,
                category = category,
            }
        end
    end
    return { version = 1, specID = specID, entries = entries }
end

local function ValidateBlizzardTracking(value)
    if value == nil then return nil end
    if type(value) ~= "table" or value.version ~= 1 or not SafeID(value.specID)
        or type(value.entries) ~= "table" then return nil, "invalid_blizzard_tracking" end
    local entryCount = 0
    for key in pairs(value.entries) do
        if type(key) ~= "number" or key < 1 or key > 4096 or key ~= math.floor(key) then
            return nil, "invalid_blizzard_tracking"
        end
        entryCount = entryCount + 1
    end
    if entryCount ~= #value.entries then return nil, "invalid_blizzard_tracking" end
    local result, seen = { version = 1, specID = value.specID, entries = {} }, {}
    for _, entry in ipairs(value.entries) do
        if type(entry) ~= "table" or not TRACKED_CATEGORIES[entry.category]
            or entry.cooldownID ~= nil and not SafeID(entry.cooldownID)
            or entry.spellID ~= nil and not SafeID(entry.spellID)
            or entry.cooldownID == nil and entry.spellID == nil then
            return nil, "invalid_blizzard_tracking"
        end
        local identity = entry.cooldownID or -entry.spellID
        if not seen[identity] then
            result.entries[#result.entries + 1] = {
                cooldownID = entry.cooldownID, spellID = entry.spellID, category = entry.category,
            }
            seen[identity] = true
        end
    end
    return result
end

local function InferGroupTracking(profileData)
    local specID = SafeID(CDM:GetCurrentSpecID())
    if not specID or type(profileData) ~= "table" then return nil end
    local categories = Enum and Enum.CooldownViewerCategory
    if not categories then return nil end
    local result, seen = { version = 1, specID = specID, entries = {} }, {}
    for _, definition in ipairs({ { "cooldownGroups", categories.Essential }, { "buffGroups", categories.TrackedBuff } }) do
        local bySpec = profileData[definition[1]]
        local groups = type(bySpec) == "table" and (bySpec[specID] or bySpec[tostring(specID)])
        if type(groups) == "table" then
            for _, group in ipairs(groups) do
                if type(group) == "table" and type(group.spells) == "table" then
                    for _, spellID in ipairs(group.spells) do
                        if SafeID(spellID) and spellID < CDM.CONST.TRINKET_SENTINEL_BASE and not seen[spellID] then
                            result.entries[#result.entries + 1] = { spellID = spellID, category = definition[2] }
                            seen[spellID] = true
                        end
                    end
                end
            end
        end
    end
    return #result.entries > 0 and result or nil
end

local function FindMissingBlizzardTracking(tracking, alignCategories)
    if not tracking then return {}, 0 end
    if tracking.specID ~= CDM:GetCurrentSpecID() then return nil, "spec_mismatch" end
    local settings, provider = GetBlizzardProvider()
    if not provider then return nil, "unavailable" end
    local providerEntries = ReadProviderEntries(provider)
    if not providerEntries then return nil, "unavailable" end
    local byID, bySpell = {}, {}
    for _, entry in ipairs(providerEntries) do
        byID[entry.id] = entry.info
        local spellID = SafeID(entry.info.spellID)
        local active = IsTrackedCategory(entry.info.category)
        if spellID and (not bySpell[spellID] or active) then bySpell[spellID] = entry.id end
        if type(entry.info.linkedSpellIDs) == "table" then
            for _, linkedID in ipairs(entry.info.linkedSpellIDs) do
                linkedID = SafeID(linkedID)
                if linkedID and (not bySpell[linkedID] or active) then bySpell[linkedID] = entry.id end
            end
        end
    end
    local missing, unresolved, seen = {}, 0, {}
    for _, wanted in ipairs(tracking.entries) do
        local cooldownID = wanted.cooldownID
        local info = cooldownID and byID[cooldownID]
        if wanted.spellID and (not info or SafeID(info.spellID) ~= wanted.spellID) then
            cooldownID = bySpell[wanted.spellID]
            info = cooldownID and byID[cooldownID]
        end
        if not alignCategories and wanted.spellID and bySpell[wanted.spellID]
            and IsTrackedCategory(byID[bySpell[wanted.spellID]].category) then
            cooldownID = bySpell[wanted.spellID]
            info = byID[cooldownID]
        end
        if info and not seen[cooldownID] then
            seen[cooldownID] = true
            local current = info.category
            if current ~= nil and not (issecretvalue and issecretvalue(current))
                and (not IsTrackedCategory(current) or alignCategories and current ~= wanted.category) then
                local targetCategory = wanted.category
                if not alignCategories and not wanted.cooldownID and C_CooldownViewer
                    and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                    local ok, native = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                    if ok and type(native) == "table" and IsTrackedCategory(native.category) then
                        targetCategory = native.category
                    end
                end
                missing[#missing + 1] = {
                    cooldownID = cooldownID, spellID = SafeID(info.spellID) or wanted.spellID,
                    category = targetCategory,
                }
            end
        elseif not info then unresolved = unresolved + 1 end
    end
    return missing, unresolved, settings, provider
end

function API:GetMissingBlizzardTracking(prepared)
    return FindMissingBlizzardTracking(prepared and prepared.blizzardTracking,
        prepared and prepared.sourceAddon == "SkironCooldownManager")
end

function API:AddMissingBlizzardTracking(prepared)
    if InCombatLockdown() then return false, L["Cannot open config while in combat"] end
    local missing, unresolved, settings, provider = self:GetMissingBlizzardTracking(prepared)
    if not missing then
        if unresolved == "spec_mismatch" then return false, L["Blizzard tracking belongs to another specialization."] end
        return false, L["Blizzard cooldown settings are unavailable."]
    end
    local successStatus = Enum and Enum.CooldownLayoutStatus and Enum.CooldownLayoutStatus.Success
    if not settings or not provider or not provider.SetCooldownToCategory or successStatus == nil then
        return false, L["Blizzard cooldown settings are unavailable."]
    end
    local added, failed = 0, unresolved
    for _, entry in ipairs(missing) do
        local ok, status = pcall(provider.SetCooldownToCategory, provider, entry.cooldownID, entry.category)
        if ok and status == successStatus then added = added + 1 else failed = failed + 1 end
    end
    if added > 0 then
        local ok = pcall(settings.SaveCurrentLayout, settings)
        if not ok then return false, L["Blizzard cooldown tracking changed but could not be saved."] end
        if settings.RefreshLayout then pcall(settings.RefreshLayout, settings) end
        CDM:Refresh("CD_DATA")
        CDM:Refresh("BUFF_DATA")
    end
    if prepared.sourceAddon == "SkironCooldownManager" then
        return true, string.format(L["Placed %d spells in Blizzard viewer rows (%d unavailable)."], added, failed)
    end
    return true, string.format(L["Added %d spells to Blizzard tracking (%d unavailable)."], added, failed)
end

local function GetCategoryOrder()
    if exportCategoryOrder and #exportCategoryOrder > 0 then
        return exportCategoryOrder
    end

    local ordered = {}
    for categoryId in pairs(exportCategories) do
        ordered[#ordered + 1] = categoryId
    end
    table.sort(ordered)
    return ordered
end

function API:ExportProfile(categories)
    if not ProfileIO or not ProfileIO.ExportSegmentedProfile then
        return nil
    end
    local tracking = CaptureBlizzardTracking()
    if not tracking then
        print("|cffff0000[CDM Export]|r " .. L["Blizzard tracking is unavailable; the profile export will omit it."])
    end

    local exportString, errCode, errValue = ProfileIO:ExportSegmentedProfile(
        CDM.db,
        categories,
        exportCategories,
        CDM.activeProfileName,
        tracking
    )

    if exportString then
        return exportString
    end

    if errCode == "serialization_failed" then
        print("|cffff0000[CDM Export]|r " .. string.format(L["Serialization failed: %s"], tostring(errValue)))
    elseif errCode == "compression_failed" then
        print("|cffff0000[CDM Export]|r " .. string.format(L["Compression failed: %s"], tostring(errValue)))
    elseif errCode == "base64_failed" then
        print("|cffff0000[CDM Export]|r " .. string.format(L["Base64 encoding failed: %s"], tostring(errValue)))
    elseif errCode == "no_categories_selected" then
        print("|cffff0000[CDM Export]|r " .. L["Select at least one category to export."])
    end
    return nil
end

local function BuildPreparedImport(payload, conversionReport, existingProfiles)
    -- Ayije is the source of this fork and shares its profile schema. Accept
    -- its exact export identity only during an explicit import; retain the
    -- shared validator for metadata, setting types and all other addon names.
    local sourceAddon = conversionReport and "SkironCooldownManager" or payload.addon
    local importAddon = sourceAddon == "Ayije_CDM" and "Ayije_CDM" or AddonName
    local prepared, buildErr = ProfileIO:BuildImportProfile(
        payload,
        importAddon,
        CDM.defaults,
        exportCategories,
        METADATA_KEYS,
        LEGACY_MIGRATION_KEYS,
        existingProfiles or (CDM_RebornDB and CDM_RebornDB.profiles)
    )
    if not prepared then
        local code = buildErr and buildErr.code
        if code == "missing_profile_metadata" then
            return nil, MapImportErrorCode(code)
        end
        if code == "wrong_addon" then
            return nil, string.format(L["Profile is for a different addon: %s"], tostring(buildErr.addon))
        end
        return nil, MapImportErrorCode(code)
    end

    if sourceAddon == "Ayije_CDM" then
        local borders = { Ayije_Thin = "CDM_Thin", Ayije_Empty = "CDM_Empty" }
        local border = prepared.profileData.borderFile
        if type(border) == "string" and borders[border] then
            prepared.profileData.borderFile = borders[border]
        end
    end
    prepared.sourceAddon = sourceAddon
    prepared.conversionReport = conversionReport
    local tracking, trackingErr = ValidateBlizzardTracking(payload.blizzardTracking)
    if trackingErr then return nil, MapImportErrorCode(trackingErr) end
    prepared.blizzardTracking = tracking or InferGroupTracking(prepared.profileData)
    return prepared
end

local function PrepareProfileCollection(payload)
    if payload.addon ~= AddonName and payload.addon ~= "Ayije_CDM" then
        return nil, L["Profile is for a different addon"]
    end
    if payload.profile_collection_version ~= 1 then return nil, L["Invalid profile version"] end
    local version = payload.schemaVersion
    if version == nil then version = 0 end
    if type(version) ~= "number" or version < 0 or version > API:GetProfileSchemaVersion() or version ~= math.floor(version) then
        return nil, L["Invalid profile version"]
    end
    if type(payload.profiles) ~= "table" or not next(payload.profiles) then return nil, L["Invalid profile data"] end
    local prepared = {
        isCollection = true, sourceAddon = payload.addon, profileCount = 0, assignmentCount = 0,
        importedCount = 0, skippedCount = 0, nameMap = {},
        collection = { profiles = {}, profileKeys = {}, specProfiles = {}, schemaVersion = version },
    }
    local reserved, names = {}, {}
    for name in pairs(CDM_RebornDB and CDM_RebornDB.profiles or {}) do reserved[name] = true end
    for name, profile in pairs(payload.profiles) do
        if type(name) ~= "string" or name == "" or type(profile) ~= "table" then return nil, L["Invalid profile data"] end
        names[#names + 1] = name
        if #names > 1000 then return nil, L["Invalid profile data"] end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local profile, err = BuildPreparedImport({
            profile_export_version = 1, addon = payload.addon, profileName = name, data = payload.profiles[name],
        }, nil, reserved)
        if not profile then return nil, err end
        reserved[profile.profileName] = true
        prepared.nameMap[name] = profile.profileName
        prepared.collection.profiles[profile.profileName] = profile.profileData
        prepared.profileCount = prepared.profileCount + 1
        prepared.importedCount = prepared.importedCount + profile.importedCount
        prepared.skippedCount = prepared.skippedCount + profile.skippedCount
    end
    if payload.profileKeys ~= nil and type(payload.profileKeys) ~= "table"
        or payload.specProfiles ~= nil and type(payload.specProfiles) ~= "table" then return nil, L["Invalid profile data"] end
    for character, sourceName in pairs(payload.profileKeys or {}) do
        if type(character) ~= "string" or type(sourceName) ~= "string" then return nil, L["Invalid profile data"] end
        local name = prepared.nameMap[sourceName]
        if name then
            prepared.collection.profileKeys[character] = name
            prepared.assignmentCount = prepared.assignmentCount + 1
        else prepared.skippedCount = prepared.skippedCount + 1 end
    end
    for character, data in pairs(payload.specProfiles or {}) do
        if type(character) ~= "string" or type(data) ~= "table" or data.enabled ~= nil and type(data.enabled) ~= "boolean" then
            return nil, L["Invalid profile data"]
        end
        local dest = { enabled = data.enabled }
        for index = 1, 4 do
            local sourceName = data[index]
            if sourceName == nil then sourceName = data[tostring(index)] end
            if sourceName ~= nil then
                if type(sourceName) ~= "string" then return nil, L["Invalid profile data"] end
                local name = prepared.nameMap[sourceName]
                if name then dest[index] = name; prepared.assignmentCount = prepared.assignmentCount + 1
                else prepared.skippedCount = prepared.skippedCount + 1 end
            end
        end
        prepared.collection.specProfiles[character] = dest
    end
    if payload.defaultProfile ~= nil then
        if type(payload.defaultProfile) ~= "string" then return nil, L["Invalid profile data"] end
        prepared.collection.defaultProfile = prepared.nameMap[payload.defaultProfile]
        if not prepared.collection.defaultProfile then prepared.skippedCount = prepared.skippedCount + 1 end
    end
    local tracking, trackingErr = ValidateBlizzardTracking(payload.blizzardTracking)
    if trackingErr then return nil, MapImportErrorCode(trackingErr) end
    prepared.blizzardTracking = tracking
    return prepared
end

function API:PrepareProfileImport(encodedString)
    if type(encodedString) ~= "string" or encodedString == "" then return nil, L["No import string provided"] end
    if not ProfileIO then return nil, L["Invalid profile data"] end
    local payload, decodeErr, conversionReport
    if ns.SkironImport and ns.SkironImport:Matches(encodedString) then
        payload, decodeErr, conversionReport = ns.SkironImport:Convert(encodedString)
    else payload, decodeErr = ProfileIO:DecodePayload(encodedString) end
    if not payload then return nil, MapImportErrorCode(decodeErr) end
    if payload.profile_collection_version ~= nil or payload.profiles ~= nil then return PrepareProfileCollection(payload) end
    return BuildPreparedImport(payload, conversionReport)
end

local function ApplyPreparedImport(prepared)
    local ok, importErr
    if prepared.isCollection then ok, importErr = API:ImportProfileCollectionData(prepared.collection)
    else ok, importErr = API:ImportProfileData(prepared.profileName, prepared.profileData) end
    if not ok then
        local mapped = MapImportErrorCode(importErr)
        return false, mapped or importErr or L["Failed to import profile"]
    end

    if API.MarkSpecDataDirty then
        API:MarkSpecDataDirty()
    end
    if prepared.isCollection and not prepared.blizzardTracking then
        local active = prepared.collection.profiles[CDM.activeProfileName]
        if active then prepared.blizzardTracking = InferGroupTracking(active) end
    end

    local msg
    if prepared.isCollection then
        msg = string.format(L["Imported %d profiles and %d character/spec assignments."], prepared.profileCount, prepared.assignmentCount)
    else msg = string.format(L["Imported %d settings as '%s'"], prepared.importedCount, prepared.profileName) end
    if prepared.skippedCount and prepared.skippedCount > 0 then
        msg = msg .. string.format(" (%d skipped)", prepared.skippedCount)
    end
    return true, msg, prepared
end

function API:ImportProfile(encodedString)
    local prepared, prepareErr = API:PrepareProfileImport(encodedString)
    if not prepared then return false, prepareErr end
    return ApplyPreparedImport(prepared)
end

local function CollectionPayload(database, addon)
    if type(database) ~= "table" or type(database.profiles) ~= "table" then return nil end
    local global = type(database.global) == "table" and database.global or {}
    local version = global.schemaVersion
    if version == nil then version = 0 end
    return {
        profile_collection_version = 1, addon = addon, schemaVersion = version,
        profiles = database.profiles, profileKeys = database.profileKeys, specProfiles = database.specProfiles,
        defaultProfile = global.defaultProfile,
    }
end

function API:ExportAllProfiles()
    local payload = CollectionPayload(CDM_RebornDB, AddonName)
    if not payload then return nil, L["Invalid profile data"] end
    payload.blizzardTracking = CaptureBlizzardTracking()
    if not payload.blizzardTracking then
        print("|cffff0000[CDM Export]|r " .. L["Blizzard tracking is unavailable; the profile export will omit it."])
    end
    local encoded, err = ProfileIO:EncodePayload(CDM:DeepCopy(payload))
    if not encoded then return nil, MapImportErrorCode(err) end
    return encoded
end

function API:ImportAllAyijeProfiles()
    -- The source DB is read only inside this explicitly invoked action.
    local source = rawget(_G, "Ayije_CDMDB")
    local payload = CollectionPayload(source, "Ayije_CDM")
    if not payload then return false, L["Enable AyijeCDM alongside CDM and reload once to make its saved profiles available."] end
    local prepared, err = PrepareProfileCollection(payload)
    if not prepared then return false, err end
    return ApplyPreparedImport(prepared)
end

local externalImportNotice
local function ShowExternalImportNotice()
    if not externalImportNotice or externalImportNotice:GetParent() ~= ns.ConfigFrame then
        local popup = UI.CreateModalOverlay()
        local window = popup.window
        window:SetSize(360, 180)
        local title = UI.CreateHeader(window, L["Profile Imported"])
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", 18, -44)
        local message = window:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        message:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
        message:SetWidth(324)
        message:SetJustifyH("LEFT")
        message:SetWordWrap(true)
        message:SetText(L["Some anchors may need adjustment after importing this profile."])
        UI.SetTextMuted(message)
        local close = UI.CreateTextButton(window)
        close:SetSize(90, 26)
        close:SetPoint("BOTTOMRIGHT", -18, 18)
        close:SetText(L["Close"])
        close:SetScript("OnClick", function() popup:Hide() end)
        externalImportNotice = popup
    end
    externalImportNotice:Show()
end

local trackingNotice
local function ShowBlizzardTrackingNotice(prepared, statusFont, importMessage)
    local missing, unresolved = API:GetMissingBlizzardTracking(prepared)
    if not missing then
        local detail = unresolved == "spec_mismatch"
            and L["Blizzard tracking belongs to another specialization. Import while using that specialization to add its spells."]
            or L["Blizzard cooldown settings are unavailable."]
        SetImportStatus(statusFont, true, importMessage .. " " .. detail)
        return false
    end
    if #missing == 0 then
        if unresolved > 0 then
            SetImportStatus(statusFont, true, importMessage .. " "
                .. string.format(L["%d exported spells are unavailable in Blizzard's cooldown settings."], unresolved))
        end
        return false
    end

    if not trackingNotice or trackingNotice.popup:GetParent() ~= ns.ConfigFrame then
        local popup = UI.CreateModalOverlay()
        local window = popup.window
        window:SetSize(450, 270)
        local title = UI.CreateHeader(window, L["Missing Blizzard tracked spells"])
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", 18, -42)
        local message = window:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        message:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
        message:SetWidth(414)
        message:SetJustifyH("LEFT")
        message:SetWordWrap(true)
        UI.SetTextMuted(message)
        local list = window:CreateFontString(nil, "ARTWORK", "CDM_Font14")
        list:SetPoint("TOPLEFT", message, "BOTTOMLEFT", 0, -12)
        list:SetWidth(414)
        list:SetJustifyH("LEFT")
        list:SetWordWrap(true)
        UI.SetTextMuted(list)
        local add = UI.CreateTextButton(window)
        add:SetSize(155, 26)
        add:SetPoint("BOTTOMLEFT", 18, 18)
        add:SetText(L["Add missing spells"])
        local keep = UI.CreateTextButton(window)
        keep:SetSize(155, 26)
        keep:SetPoint("LEFT", add, "RIGHT", 8, 0)
        keep:SetText(L["Keep current tracking"])
        keep:SetScript("OnClick", function() popup:Hide() end)
        trackingNotice = { popup = popup, title = title, message = message, list = list, add = add }
    end

    local names = {}
    for index = 1, math.min(6, #missing) do
        local spellID = missing[index].spellID
        local name
        if spellID and C_Spell and C_Spell.GetSpellName then
            local ok, value = pcall(C_Spell.GetSpellName, spellID)
            if ok and not (issecretvalue and issecretvalue(value)) and type(value) == "string" then name = value end
        end
        names[#names + 1] = name or string.format(L["Cooldown %d"], missing[index].cooldownID)
    end
    if #missing > #names then names[#names + 1] = string.format(L["and %d more"], #missing - #names) end
    local isSkiron = prepared.sourceAddon == "SkironCooldownManager"
    local message = isSkiron
        and string.format(L["This Skiron import has %d spells missing from, or assigned to a different Blizzard viewer row. Place them in their exported Essential, Utility, or Buff rows?"], #missing)
        or string.format(
            L["This import includes %d entries that are not tracked in Blizzard's cooldown settings. Add them now? Existing tracked entries will stay enabled."],
            #missing
        )
    if prepared.sourceAddon == "Ayije_CDM" or prepared.sourceAddon == "SkironCooldownManager" then
        message = message .. " " .. L["Some anchors may need adjustment after importing this profile."]
    end
    trackingNotice.message:SetText(message)
    trackingNotice.list:SetText(table.concat(names, ", "))
    trackingNotice.title:SetText(isSkiron and L["Skiron viewer rows"] or L["Missing Blizzard tracked spells"])
    trackingNotice.add:SetText(isSkiron and L["Place in viewer rows"] or L["Add missing spells"])
    trackingNotice.add:SetScript("OnClick", function()
        local ok, detail = API:AddMissingBlizzardTracking(prepared)
        SetImportStatus(statusFont, ok, ok and (importMessage .. " " .. detail) or detail)
        trackingNotice.popup:Hide()
    end)
    trackingNotice.popup:Show()
    return true
end

local function CreateImportExportTab(page, tabId)
    local exportHeader = UI.CreateHeader(page, L["Export Profile"])
    exportHeader:SetPoint("TOPLEFT", 35, -40)

    local exportDesc = page:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    exportDesc:SetPoint("TOPLEFT", exportHeader, "BOTTOMLEFT", 0, -15)
    exportDesc:SetText(L["Select categories to export. Blizzard tracking for this spec is included."])
    UI.SetTextMuted(exportDesc)

    local checkboxes = {}
    local sortedCategories = GetCategoryOrder()
    local categoryCount = 0
    local columnWidth = 155
    local labelWidth = 115
    local rowHeight = 36

    for i, categoryId in ipairs(sortedCategories) do
        local categoryDef = exportCategories[categoryId]
        if categoryDef then
            categoryCount = categoryCount + 1
            local checkbox = UI.CreateModernCheckbox(
                page,
                categoryDef.label,
                true,
                nil
            )

            local col = (categoryCount - 1) % 3
            local row = math.floor((categoryCount - 1) / 3)
            checkbox:SetPoint("TOPLEFT", exportDesc, "BOTTOMLEFT", col * columnWidth, -12 - (row * rowHeight))
            checkbox:SetSize(columnWidth - 10, rowHeight)
            if checkbox.label then
                checkbox.label:SetWidth(labelWidth)
                checkbox.label:SetJustifyH("LEFT")
                checkbox.label:SetWordWrap(true)
            end

            checkboxes[categoryId] = checkbox
        end
    end

    local exportBtn = UI.CreateTextButton(page)
    exportBtn:SetSize(120, 26)
    local rowCount = math.max(1, math.ceil(categoryCount / 3))
    local exportBtnYOffset = -12 - (rowCount * rowHeight) - 8
    exportBtn:SetPoint("TOPLEFT", exportDesc, "BOTTOMLEFT", 0, exportBtnYOffset)
    exportBtn:SetText(L["Export"])

    local exportBoxLabel = page:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    exportBoxLabel:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -16)
    exportBoxLabel:SetText(L["Export String (Ctrl+C to copy):"])
    UI.SetTextMuted(exportBoxLabel)

    local exportBoxFrame, exportEditBox = UI.CreateScrollableEditBox(page, 420, 80, 380)
    exportBoxFrame:SetPoint("TOPLEFT", exportBoxLabel, "BOTTOMLEFT", 0, -4)

    exportBtn:SetScript("OnClick", function()
        local selectedCategories = {}
        for categoryId, checkbox in pairs(checkboxes) do
            if checkbox:GetChecked() then
                selectedCategories[categoryId] = true
            end
        end

        local exportString = API:ExportProfile(selectedCategories)
        if exportString then
            exportEditBox:SetText(exportString)
            exportEditBox:HighlightText()
            exportEditBox:SetFocus()
            print("|cff00ff00[CDM]|r " .. L["Profile exported! Copy the string above."])
        else
            exportEditBox:SetText("")
            print("|cffff0000[CDM]|r " .. L["Export failed."])
        end
    end)

    local exportAllBtn = UI.CreateTextButton(page)
    exportAllBtn:SetSize(150, 26)
    exportAllBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    exportAllBtn:SetText(L["Export all profiles"])
    exportAllBtn:SetScript("OnClick", function()
        local exported, err = API:ExportAllProfiles()
        exportEditBox:SetText(exported or "")
        if exported then
            exportEditBox:HighlightText()
            exportEditBox:SetFocus()
        else print("|cffff0000[CDM]|r " .. (err or L["Export failed."])) end
    end)

    local importHeader = UI.CreateHeader(page, L["Import Profile"], exportBoxFrame, -15)

    local importDesc = page:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    importDesc:SetPoint("TOPLEFT", importHeader, "BOTTOMLEFT", 0, -15)
    importDesc:SetText(L["Paste an export string below and click Import."])
    UI.SetTextMuted(importDesc)

    local supportedLabel = page:CreateFontString(nil, "ARTWORK", "CDM_Font12")
    supportedLabel:SetPoint("TOPLEFT", importDesc, "BOTTOMLEFT", 0, -4)
    supportedLabel:SetText(L["Supports CDM, AyijeCDM and SkironCDM export strings."])
    UI.SetTextMuted(supportedLabel)

    local importBoxFrame, importEditBox = UI.CreateScrollableEditBox(page, 420, 80, 380)
    importBoxFrame:SetPoint("TOPLEFT", supportedLabel, "BOTTOMLEFT", 0, -8)

    local importBtn = UI.CreateTextButton(page)
    importBtn:SetSize(120, 26)
    importBtn:SetPoint("TOPLEFT", importBoxFrame, "BOTTOMLEFT", 0, -6)
    importBtn:SetText(L["Import"])

    local importStatus = page:CreateFontString(nil, "ARTWORK", "CDM_Font14")
    importStatus:SetPoint("LEFT", importBtn, "RIGHT", 12, 0)
    importStatus:SetText("")
    UI.SetTextMuted(importStatus)
    activeStatusFontString = importStatus
    ApplyImportStatus(importStatus)

    local function ImportString(importString)
        local success, message, prepared = API:ImportProfile(importString)
        SetImportStatus(importStatus, success, message)
        if success then
            local showingTracking = ShowBlizzardTrackingNotice(prepared, importStatus, message)
            if not showingTracking and (prepared.sourceAddon == "Ayije_CDM" or prepared.sourceAddon == "SkironCooldownManager") then
                ShowExternalImportNotice()
            end
        end
    end
    importBtn:SetScript("OnClick", function()
        ImportString(importEditBox:GetText())
    end)

    local clearBtn = UI.CreateTextButton(page)
    clearBtn:SetSize(80, 26)
    clearBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    clearBtn:SetText(L["Clear"])
    clearBtn:SetScript("OnClick", function()
        importEditBox:SetText("")
        ClearImportStatus(importStatus)
    end)

    local ayijeBtn = UI.CreateTextButton(page)
    ayijeBtn:SetSize(190, 26)
    ayijeBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
    ayijeBtn:SetText(L["Import all Ayije profiles"])
    ayijeBtn:SetScript("OnClick", function()
        local success, message, prepared = API:ImportAllAyijeProfiles()
        SetImportStatus(importStatus, success, message)
        if success and not ShowBlizzardTrackingNotice(prepared, importStatus, message) then ShowExternalImportNotice() end
    end)

    local collectionHint = page:CreateFontString(nil, "ARTWORK", "CDM_Font12")
    collectionHint:SetPoint("TOPLEFT", importStatus, "BOTTOMLEFT", 0, -8)
    collectionHint:SetWidth(600)
    collectionHint:SetJustifyH("LEFT")
    collectionHint:SetWordWrap(true)
    collectionHint:SetText(L["All-profile transfers include character/spec assignments. Existing profiles are kept; imported names receive a suffix if needed."])
    UI.SetTextMuted(collectionHint)

    importStatus:ClearAllPoints()
    importStatus:SetPoint("TOPLEFT", importBtn, "BOTTOMLEFT", 0, -6)
    importStatus:SetWidth(600)
    importStatus:SetJustifyH("LEFT")
    importStatus:SetWordWrap(true)
end

API:RegisterConfigTab("importexport", L["Import/Export"], CreateImportExportTab, 12)
