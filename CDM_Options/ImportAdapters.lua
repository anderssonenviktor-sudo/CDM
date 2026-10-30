local Runtime = _G["CDM"]
if not Runtime then return end
local ns = Runtime._OptionsNS
local L = Runtime.L

-- Converters for other cooldown-manager addons' export strings. Each adapter
-- is { id, label, Detect(text) -> bool, Convert(text) -> result | nil, err }.
-- A result is { profileName, profileData, blizzardTracking, report }. The
-- caller still runs it through the normal profile import validation.
local Adapters = { list = {} }
ns.ImportAdapters = Adapters

function Adapters.Register(adapter)
    Adapters.list[#Adapters.list + 1] = adapter
end

function Adapters.Find(text)
    if type(text) ~= "string" then return nil end
    for _, adapter in ipairs(Adapters.list) do
        if adapter.Detect(text) then return adapter end
    end
    return nil
end

-- Base64 -> Deflate -> CBOR, the C_EncodingUtil pipeline CDM itself uses.
function Adapters.DecodeBody(body)
    local okDecode, compressed = pcall(C_EncodingUtil.DecodeBase64, body)
    if not okDecode or not compressed then return nil, L["Invalid Base64 encoding"] end
    local okInflate, raw = pcall(C_EncodingUtil.DecompressString, compressed)
    if not okInflate or not raw then return nil, L["Decompression failed"] end
    local okCBOR, payload = pcall(C_EncodingUtil.DeserializeCBOR, raw)
    if not okCBOR or type(payload) ~= "table" then return nil, L["Invalid profile data"] end
    return payload
end

local ReportMixin = {}

local function AddLine(report, list, message, ...)
    local line = select("#", ...) > 0 and message:format(...) or message
    if report.seen[line] then return end
    report.seen[line] = true
    list[#list + 1] = line
end

function ReportMixin:Approx(message, ...)
    AddLine(self, self.approximated, message, ...)
end

function ReportMixin:Skip(message, ...)
    AddLine(self, self.skipped, message, ...)
end

function ReportMixin:IsEmpty()
    return #self.approximated == 0 and #self.skipped == 0
end

function ReportMixin:ToText()
    local lines = {}
    if #self.approximated > 0 then
        lines[#lines + 1] = L["Approximated:"]
        for _, line in ipairs(self.approximated) do lines[#lines + 1] = "- " .. line end
    end
    if #self.skipped > 0 then
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = L["Not imported:"]
        for _, line in ipairs(self.skipped) do lines[#lines + 1] = "- " .. line end
    end
    return table.concat(lines, "\n")
end

function Adapters.NewReport()
    local report = { approximated = {}, skipped = {}, seen = {} }
    for key, fn in pairs(ReportMixin) do report[key] = fn end
    return report
end
