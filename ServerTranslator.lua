-- ServerTranslator.lua
-- TheGrudge — WotLK 3.3.5 Combat Log Normaliser + Server Detection
--
-- Private servers (Warmane, ChromieCraft, etc.) sometimes deliver
-- COMBAT_LOG_EVENT_UNFILTERED args in non-standard order or with non-standard
-- types. This module:
--   1. Auto-detects the server by watching the realm name and chat messages.
--   2. Normalises the raw vararg from OnEvent into a consistent 11-field header
--      that the rest of the addon can rely on.
--   3. Provides NormaliseName() to clean source/dest names that may arrive as
--      GUIDs, numbers, or scrambled strings on some private server builds.
--
-- Usage (Detection.lua):
--   local ts, sub, hide, sGUID, sName, sFlags, sRF, dGUID, dName, dFlags, dRF, ... =
--       TheGrudge.ServerTranslator:Translate(...)
--   local cleanName = TheGrudge.ServerTranslator:NormaliseName(sName, sGUID)

TheGrudge.ServerTranslator = {}

local ST = TheGrudge.ServerTranslator

-- ─── Server fingerprints ─────────────────────────────────────────────────────
-- Patterns matched (case-insensitive) against realm name and chat messages.

local SERVER_PATTERNS = {
    Warmane      = { "warmane", "warmane%.com", "icecrown", "lordaeron",
                     "donate and be rewarded with coins" },
    Dalaran      = { "dalaran%-wow", "dalaran%-wow%.com" },
    ChromieCraft = { "chromiecraft", "chromiecraft%.com" },
    TurtleWoW    = { "turtle wow", "turtle%-wow%.org" },
    Firestorm    = { "firestorm", "firestorm%-servers%.com" },
}

-- ─── State ───────────────────────────────────────────────────────────────────
local _server     = nil   -- detected server name string, or nil
local _confidence = "unknown"

-- ─── Internal: attempt to match a string against all fingerprints ─────────────

local function MatchServer(str)
    if type(str) ~= "string" or str == "" then return nil end
    local lower = str:lower()
    for serverName, patterns in pairs(SERVER_PATTERNS) do
        for _, pat in ipairs(patterns) do
            if lower:match(pat) then
                return serverName
            end
        end
    end
    return nil
end

local function RecordServer(name, confidence)
    if _server then return end   -- first detection wins; don't overwrite
    _server     = name
    _confidence = confidence
    DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cffff4444[The Grudge]|r Server detected: |cffffd700%s|r (%s)", name, confidence)
    )
end

-- ─── Chat / realm listener ───────────────────────────────────────────────────

local _listenerFrame = CreateFrame("Frame")
_listenerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_listenerFrame:RegisterEvent("CHAT_MSG_SYSTEM")
_listenerFrame:RegisterEvent("CHAT_MSG_CHANNEL")

_listenerFrame:SetScript("OnEvent", function(self, event, msg)
    if _server then return end   -- already detected; stop checking

    if event == "PLAYER_ENTERING_WORLD" then
        -- Check realm name immediately on login
        local realm = GetRealmName()
        local found = MatchServer(realm)
        if found then
            RecordServer(found, "realm_name")
        end

    elseif msg then
        -- Watch system and channel messages for server ads
        local found = MatchServer(msg)
        if found then
            RecordServer(found, "chat_message")
        end
    end
end)


-- ─── ST:Translate ─────────────────────────────────────────────────────────────
-- Accepts the raw ... from OnEvent for COMBAT_LOG_EVENT_UNFILTERED and returns
-- a normalised 11-field header followed by any event-specific trailing args.
--
-- Retail/standard WotLK layout (13 header fields before event args):
--   timestamp, subevent, hideCaster,
--   srcGUID, srcName, srcFlags, srcRaidFlags,
--   dstGUID, dstName, dstFlags, dstRaidFlags
--
-- Some private server builds omit hideCaster and/or raidFlags, shifting every
-- subsequent position. We detect and correct this by inspecting field types.

function ST:Translate(...)
    local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 = ...

    -- a1 should be a number (timestamp). If it looks like a subevent string
    -- the server has omitted the timestamp and shifted everything left.
    -- In practice WotLK always sends timestamp, so we just ensure hideCaster
    -- and raidFlags are present.

    local timestamp  = a1
    local subevent   = a2
    -- a3 is hideCaster (boolean) on Retail/some builds, but some private servers
    -- skip it entirely making a3 the srcGUID. Detect by type:
    local hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags,
          dstGUID, dstName, dstFlags, dstRaidFlags

    if type(a3) == "boolean" or a3 == nil then
        -- Standard layout — hideCaster is present
        hideCaster  = a3 or false
        srcGUID     = a4
        srcName     = a5
        srcFlags    = a6
        srcRaidFlags = a7
        dstGUID     = a8
        dstName     = a9
        dstFlags    = a10
        dstRaidFlags = a11
    else
        -- Compressed layout — hideCaster is missing; a3 is srcGUID
        hideCaster  = false
        srcGUID     = a3
        srcName     = a4
        srcFlags    = a5
        srcRaidFlags = 0        -- not provided; insert default
        dstGUID     = a6
        dstName     = a7
        dstFlags    = a8
        dstRaidFlags = 0
    end

    -- Normalise flags to numbers (some builds send them as hex strings)
    srcFlags     = tonumber(srcFlags)  or 0
    srcRaidFlags = tonumber(srcRaidFlags) or 0
    dstFlags     = tonumber(dstFlags)  or 0
    dstRaidFlags = tonumber(dstRaidFlags) or 0

    -- Collect trailing event-specific args
    -- We need to figure out how many header fields were consumed so we can
    -- forward the rest. Use select() on the original vararg.
    local headerCount = (type(a3) == "boolean" or a3 == nil) and 11 or 10
    local extra = { select(headerCount + 1, ...) }

    return timestamp, subevent, hideCaster,
           srcGUID, srcName, srcFlags, srcRaidFlags,
           dstGUID, dstName, dstFlags, dstRaidFlags,
           unpack(extra)
end


-- ─── ST:NormaliseName ────────────────────────────────────────────────────────
-- Cleans a name/GUID pair from the combat log.
-- On Warmane and similar servers the name field can arrive as:
--   • A proper player name string            → return as-is
--   • A hex GUID string ("0xF130...")        → return nil (not a name)
--   • A number (creature ID)                 → return nil
--   • An empty string or "Unknown"           → return nil
-- Returns a clean name string, or nil if the value cannot be a player name.

function ST:NormaliseName(name, guid)
    -- Priority 1: name field looks like a real player name
    if type(name) == "string" and name ~= "" and name ~= "Unknown" then
        -- Must contain at least one letter, be ≤ 20 chars,
        -- and not look like a GUID or creature string
        if name:find("%a")
            and #name <= 20
            and not name:find("^0x")
            and not name:find("Creature")
            and not name:find("^%d+$")
        then
            return name
        end
    end

    -- Priority 2: on some Warmane builds the GUID field actually holds the name
    if type(guid) == "string" and guid ~= "" then
        if guid:find("%a")
            and #guid <= 20
            and not guid:find("^0x")
            and not guid:find(":")
            and not guid:find("%d%d%d%d")
        then
            return guid
        end
    end

    -- Can't recover a usable name
    return nil
end


-- ─── ST:GetServer / ST:SetServer ─────────────────────────────────────────────

function ST:GetServer()
    return _server or "WotLK"
end

function ST:GetConfidence()
    return _confidence
end

function ST:SetServer(name)
    if SERVER_PATTERNS[name] then
        _server     = name
        _confidence = "manual_override"
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff4444[The Grudge]|r Server manually set to |cffffd700%s|r.", name)
        )
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff4444[The Grudge]|r Unknown server name. Valid options: " ..
            "Warmane, Dalaran, ChromieCraft, TurtleWoW, Firestorm"
        )
    end
end
