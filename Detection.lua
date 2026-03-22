-- Detection.lua
-- Seven detection layers run in parallel:
--   1. COMBAT_LOG_EVENT_UNFILTERED  — fires on any nearby combat action
--   2. OnUpdate nameplate sweep     — polls visible nameplates every N seconds
--   3. GROUP_ROSTER_UPDATE          — catches party/raid members immediately
--   4. PLAYER_TARGET_CHANGED        — fires when you click or tab-target someone
--   5. UPDATE_MOUSEOVER_UNIT        — fires when you hover over a unit frame/nameplate
--   6. Chat channel scanning        — SAY, YELL, GENERAL, TRADE, etc.
--   7. Periodic /who query          — checks if any grudge target is online on the realm
--   8. PLAYER_ENTERING_WORLD        — immediate /who burst on every zone transition
--
-- All names funnel through Detection:CheckName() which enforces the alert cooldown.

TheGrudge.Detection = {}

local Detection      = TheGrudge.Detection

-- ─── Tunables ────────────────────────────────────────────────────────────────
local SCAN_INTERVAL  = 3.0    -- seconds between nameplate sweeps
local ALERT_COOLDOWN = 30     -- seconds before the same target can alert again
local WHO_INTERVAL   = 120    -- seconds between automatic /who sweeps (2 min)
local WHO_BATCH_SIZE = 1      -- WoW only returns one /who result set at a time;
                               -- we cycle through targets one per interval
local WHO_ZONE_DELAY = 3.0    -- seconds after zoning before the burst /who fires
                               -- (gives the server time to settle after a load screen)

-- ─── State ───────────────────────────────────────────────────────────────────
local _lastScan      = 0
local _lastWho       = 0
local _whoIndex      = 1       -- cycles through grudge targets for /who queries
local _whoNames      = {}      -- flat ordered list rebuilt on each sweep start
local _alerted       = {}      -- [lowername] → expiry timestamp
local _zonePending   = false   -- true while waiting for WHO_ZONE_DELAY after zoning
local _zoneTimer     = 0       -- counts up to WHO_ZONE_DELAY

local scanFrame = CreateFrame("Frame")


-- ─── Detection:Start ─────────────────────────────────────────────────────────

function Detection:Start()
    -- ── Event registrations ──────────────────────────────────────────────────
    scanFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    scanFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    scanFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    scanFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    scanFrame:RegisterEvent("PLAYER_ENTERING_WORLD")   -- zone/BG/dungeon transitions

    -- Chat channels we want to monitor for grudge-target names
    scanFrame:RegisterEvent("CHAT_MSG_SAY")
    scanFrame:RegisterEvent("CHAT_MSG_YELL")
    scanFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    scanFrame:RegisterEvent("CHAT_MSG_WHISPER")        -- they whispered you
    scanFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM") -- you whispered them
    scanFrame:RegisterEvent("CHAT_MSG_EMOTE")
    scanFrame:RegisterEvent("CHAT_MSG_TEXT_EMOTE")

    -- /who result callback
    scanFrame:RegisterEvent("WHO_LIST_UPDATE")

    -- ── OnUpdate: nameplate sweep + /who timer + zone-trigger delay ─────────────
    scanFrame:SetScript("OnUpdate", function(self, elapsed)
        _lastScan = _lastScan + elapsed
        if _lastScan >= SCAN_INTERVAL then
            _lastScan = 0
            Detection:ScanNameplates()
        end

        -- Zone-triggered burst: fires WHO_ZONE_DELAY seconds after PLAYER_ENTERING_WORLD
        if _zonePending then
            _zoneTimer = _zoneTimer + elapsed
            if _zoneTimer >= WHO_ZONE_DELAY then
                _zonePending = false
                _zoneTimer   = 0
                _lastWho     = 0          -- reset the periodic timer so we don't
                                          -- double-fire a few seconds later
                Detection:WhoSweepAll()
            end
        end

        _lastWho = _lastWho + elapsed
        if _lastWho >= WHO_INTERVAL then
            _lastWho = 0
            Detection:WhoSweep()
        end
    end)

    -- ── OnEvent dispatcher ───────────────────────────────────────────────────
    scanFrame:SetScript("OnEvent", function(self, event, ...)
        if not TheGrudge.enabled then return end

        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            Detection:OnCombatLogEvent(...)

        elseif event == "GROUP_ROSTER_UPDATE" then
            Detection:ScanGroup()

        elseif event == "PLAYER_TARGET_CHANGED" then
            Detection:CheckUnit("target", "target")

        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            Detection:CheckUnit("mouseover", "mouseover")

        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Arm the delayed burst sweep. We wait WHO_ZONE_DELAY seconds because
            -- PLAYER_ENTERING_WORLD fires while the loading screen is still up on
            -- some 3.3.5a builds; delaying ensures the server is ready for /who.
            _zonePending = true
            _zoneTimer   = 0

        elseif event == "WHO_LIST_UPDATE" then
            Detection:OnWhoResult()

        elseif event == "CHAT_MSG_SAY"
            or event == "CHAT_MSG_YELL"
            or event == "CHAT_MSG_CHANNEL"
            or event == "CHAT_MSG_WHISPER"
            or event == "CHAT_MSG_WHISPER_INFORM"
            or event == "CHAT_MSG_EMOTE"
            or event == "CHAT_MSG_TEXT_EMOTE"
        then
            -- arg2 for chat events is the sender name (may include realm: "Name-Realm")
            local _, senderFull = ...
            if senderFull then
                -- Strip the "-RealmName" suffix so cross-realm names still match
                local senderName = senderFull:match("^([^%-]+)")
                Detection:CheckName(senderName, "chat")
            end
        end
    end)

    -- Do an immediate group scan in case we logged in mid-group
    Detection:ScanGroup()
end


-- ─── Detection:CheckName ─────────────────────────────────────────────────────
-- Single choke-point for all detections. Every candidate name flows here.

function Detection:CheckName(name, source)
    if type(name) ~= "string" or name == "" then return end
    if not TheGrudge.enabled then return end

    local entry = TheGrudge:IsOnGrudgeList(name)
    if not entry then return end

    local now    = time()
    local expiry = _alerted[name:lower()]
    if expiry and now < expiry then return end

    _alerted[name:lower()] = now + ALERT_COOLDOWN
    TheGrudge.Alert:Trigger(entry, source)
end


-- ─── Detection:CheckUnit ─────────────────────────────────────────────────────
-- Checks a unit token (e.g. "target", "mouseover") if it is a player.

function Detection:CheckUnit(unit, source)
    if not UnitExists(unit) then return end
    if not UnitIsPlayer(unit) then return end
    -- Hostile or neutral players only — skip friendly/same-faction
    -- (Remove the reaction check below if you want to alert on faction-mates too)
    local reaction = UnitReaction(unit, "player")
    -- reaction 1-4 = hostile/unfriendly/neutral/neutral, 5-8 = friendly
    -- We alert on anyone reaction <= 4 OR if they're on the grudge list regardless
    -- For grudge we want to catch them regardless of current reaction, so just pass the name.
    local name = UnitName(unit)
    self:CheckName(name, source)
end


-- ─── Detection:ScanNameplates ────────────────────────────────────────────────
-- Iterates all visible nameplate unit tokens. WotLK 3.3.5 uses legacy approach.

function Detection:ScanNameplates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local name = UnitName(unit)
            self:CheckName(name, "nameplate")
        else
            break  -- nameplate slots are contiguous; safe to stop here
        end
    end
end


-- ─── Detection:ScanGroup ─────────────────────────────────────────────────────
-- Checks all current party/raid members against the grudge list.

function Detection:ScanGroup()
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            self:CheckName(UnitName(unit), "group")
        end
    end

    for i = 1, 40 do
        local unit = "raid" .. i
        if UnitExists(unit) then
            self:CheckName(UnitName(unit), "group")
        end
    end
end


-- ─── Detection:WhoSweep ──────────────────────────────────────────────────────
-- Issues a /who query for one grudge target per call, cycling through the list.
-- WoW rate-limits /who — one query returns results via WHO_LIST_UPDATE.
-- Exposed publicly so the slash command can trigger it manually.

function Detection:WhoSweep()
    -- Rebuild the flat list each sweep so it stays current
    _whoNames = {}
    for _, entry in pairs(TheGrudge.grudgeMap) do
        _whoNames[#_whoNames + 1] = entry.name
    end

    if #_whoNames == 0 then return end

    -- Cycle through targets so we don't hammer the same name every time
    if _whoIndex > #_whoNames then
        _whoIndex = 1
    end

    local target = _whoNames[_whoIndex]
    _whoIndex = _whoIndex + 1

    if target then
        -- SendWho() fires WHO_LIST_UPDATE without printing to the default chat frame.
        -- The chat filter below handles any echo that leaks through on old 3.3.5a builds.
        SendWho(target)
    end
end


-- ─── Detection:WhoSweepAll ───────────────────────────────────────────────────
-- Queries every grudge target in rapid succession. Called on zone transitions
-- so we get a full picture of who's online in the new zone immediately.
-- Because WoW serialises /who requests server-side this is safe to burst —
-- extra queries are queued, not dropped.

function Detection:WhoSweepAll()
    local count = 0
    for _, entry in pairs(TheGrudge.grudgeMap) do
        SendWho(entry.name)
        count = count + 1
    end
    -- Reset the cyclic index so the next periodic sweep starts fresh
    _whoIndex = 1
end


-- ─── Detection:OnWhoResult ───────────────────────────────────────────────────
-- Parses the /who result set and checks every returned name.

function Detection:OnWhoResult()
    local count = GetNumWhoResults()
    for i = 1, count do
        local name = GetWhoInfo(i)  -- returns name, guildName, level, race, class, zone, classFileName
        if name then
            self:CheckName(name, "who")
        end
    end
end


-- ─── /who chat filter ────────────────────────────────────────────────────────
-- On some 3.3.5a private server builds, SendWho() still echoes "No players
-- found." or individual results to CHAT_MSG_SYSTEM. We install a lightweight
-- chat filter that silences exactly those messages while our /who is active.
--
-- The filter is intentionally narrow: it only suppresses the two standard
-- /who system strings. Everything else passes through untouched.
--
-- Because ChatFrame_AddMessageEventFilter is additive (all filters run in
-- order, first true return wins), this is safe to leave registered permanently.

local WHO_SUPPRESS_PATTERNS = {
    "^No players found%.",           -- empty result
    "^Players found: ",              -- result header on some builds
}

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(self, event, msg)
    if not msg then return false end
    for _, pat in ipairs(WHO_SUPPRESS_PATTERNS) do
        if msg:find(pat) then
            return true   -- returning true suppresses the message
        end
    end
    return false
end)


-- ─── Detection:OnCombatLogEvent ──────────────────────────────────────────────
-- Fired for every combat log event within range (~60 yds from you or the raid).
-- Raw args from OnEvent are piped through ServerTranslator:Translate() first,
-- which normalises the header layout and coerces flags to numbers regardless
-- of which private server build is running.
-- We check both source and dest to catch grudge targets being attacked by others.

function Detection:OnCombatLogEvent(...)
    local ST = TheGrudge.ServerTranslator

    -- Normalise the raw vararg — handles missing hideCaster, string flags, etc.
    local timestamp, subevent, hideCaster,
          srcGUID, srcName, srcFlags, srcRaidFlags,
          dstGUID, dstName, dstFlags, dstRaidFlags = ST:Translate(...)

    local PLAYER_FLAG = 0x00000004  -- COMBATLOG_OBJECT_TYPE_PLAYER

    -- Source: clean the name through NormaliseName, then check if it's a player
    if bit.band(srcFlags, PLAYER_FLAG) ~= 0 then
        local cleanName = ST:NormaliseName(srcName, srcGUID)
        if cleanName then
            self:CheckName(cleanName, "combat_log")
        end
    end

    -- Destination: same treatment — catches grudge targets being hit by others
    if bit.band(dstFlags, PLAYER_FLAG) ~= 0 then
        local cleanName = ST:NormaliseName(dstName, dstGUID)
        if cleanName then
            self:CheckName(cleanName, "combat_log")
        end
    end
end