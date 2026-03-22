-- Alert.lua
-- All output (chat, sound, visual popup) lives here.
-- Single public entry point: TheGrudge.Alert:Trigger(entry, source)
--
-- "entry"  = grudge map entry { name, kill_count, last_killed_at, incidents }
-- "source" = string hint: "nameplate" | "combat_log" | "group" | "target" |
--                         "mouseover" | "chat" | "who" | "test"
--
-- Visual system notes:
--   • Pure Lua — no XML, no BLP, no TGA required.
--   • Animation driven by OnUpdate (same math as Cheese's APIAnimation.lua,
--     without the XML AnimationGroup overhead we don't need).
--   • Single frame created once on first alert, reused forever (Cheese pool pattern).
--   • Three animation phases: FADE_IN → HOLD (pulsing border) → FADE_OUT.

TheGrudge.Alert = {}

local Alert = TheGrudge.Alert


-- ─── Severity thresholds ─────────────────────────────────────────────────────
local SEVERITY = {
    { min = 1, max = 2,    label = "CAUTION", color = "ffff9900",
      r = 1.0, g = 0.60, b = 0.00 },
    { min = 3, max = 5,    label = "WARNING", color = "ffff4400",
      r = 1.0, g = 0.27, b = 0.00 },
    { min = 6, max = 99999, label = "DANGER",  color = "ffff0000",
      r = 1.0, g = 0.00, b = 0.00 },
}
Alert._SEVERITY = SEVERITY   -- exposed for SettingsUI preview buttons

local function GetSeverity(kills)
    for _, s in ipairs(SEVERITY) do
        if kills >= s.min and kills <= s.max then return s end
    end
    return SEVERITY[#SEVERITY]
end


-- ─── Source labels ───────────────────────────────────────────────────────────
local SOURCE_LABEL = {
    nameplate  = "entered render range",
    combat_log = "is in combat nearby",
    group      = "joined your group",
    target     = "is your current target",
    mouseover  = "is under your cursor",
    chat       = "spoke in a chat channel",
    who        = "is online on this realm",
    test       = "TEST ALERT",
}

local function GetSourceLabel(source)
    return SOURCE_LABEL[source] or ("detected via " .. tostring(source))
end


-- ─── Relative time ───────────────────────────────────────────────────────────
local function FormatRelativeTime(ts)
    if not ts or ts == 0 then return "unknown" end
    local delta = time() - ts
    if delta < 60     then return "just now"
    elseif delta < 3600  then return math.floor(delta / 60)   .. " min ago"
    elseif delta < 86400 then return math.floor(delta / 3600) .. " hr ago"
    else                      return math.floor(delta / 86400) .. " day(s) ago"
    end
end


-- ═══════════════════════════════════════════════════════════════════════════════
-- VISUAL POPUP
-- ═══════════════════════════════════════════════════════════════════════════════

local POPUP_W        = 390
local POPUP_H        = 136
local FADE_IN_TIME   = 0.20   -- seconds
local HOLD_TIME      = 5.0    -- seconds before auto-dismiss
local FADE_OUT_TIME  = 0.35   -- seconds
local PULSE_FREQ     = 2.8    -- border pulse speed (radians / second)
local BORDER_SZ      = 2      -- border edge thickness in pixels

local _frame = nil   -- single reusable popup frame


-- ─── BuildFrame ──────────────────────────────────────────────────────────────
-- Called once, lazily. Creates every sub-region.

local function BuildFrame()
    local f = CreateFrame("Frame", "TheGrudgePopup", UIParent)
    f:SetWidth(POPUP_W)
    f:SetHeight(POPUP_H)
    -- Restore saved position, or default to top-left inset on first run
    local saved = TheGrudgeSettings and TheGrudgeSettings.popupPos
    if saved then
        f:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -80)
    end
    f:SetFrameStrata("HIGH")
    f:SetAlpha(0)
    f:SetMovable(true)
    f:SetClampedToScreen(true)  -- prevent dragging off-screen
    f:EnableMouse(false)        -- click-through by default; Ctrl held unlocks drag
    f:Hide()

    -- Dark background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(0, 0, 0, 0.84)

    -- Left accent bar (4 px, coloured by severity)
    local accent = f:CreateTexture(nil, "BORDER")
    accent:SetWidth(4)
    accent:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, 0)
    accent:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.accent = accent

    -- Four border edges — stored in array for fast colour + alpha updates
    local function Edge(p1, p2, x1, y1, x2, y2)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p1, f, p1, x1, y1)
        t:SetPoint(p2, f, p2, x2, y2)
        return t
    end
    local B = BORDER_SZ
    f.edges = {
        Edge("TOPLEFT",    "TOPRIGHT",    0,  0,  0, -B),   -- top
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", 0,  B,  0,  0),   -- bottom
        Edge("TOPLEFT",    "BOTTOMLEFT",  0,  0,  B,  0),   -- left
        Edge("TOPRIGHT",   "BOTTOMRIGHT",-B,  0,  0,  0),   -- right
    }

    -- ── Text layers ──────────────────────────────────────────────────────────

    -- Severity label  e.g. "⚠  DANGER  ⚠"
    local sevText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sevText:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -9)
    f.sevText = sevText

    -- Player name (large)
    local nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -26)
    nameText:SetWidth(POPUP_W - 22)
    nameText:SetJustifyH("LEFT")
    f.nameText = nameText

    -- Source context  e.g. "is in combat nearby"
    local srcText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    srcText:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -48)
    srcText:SetTextColor(0.72, 0.72, 0.72)
    f.srcText = srcText

    -- Thin divider
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  f, "TOPLEFT",  14, -63)
    div:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -63)
    div:SetTexture(0.28, 0.28, 0.28, 1)

    -- Kill count + last seen
    local killText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    killText:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -74)
    killText:SetWidth(POPUP_W - 22)
    killText:SetJustifyH("LEFT")
    f.killText = killText

    -- Last incident
    local incText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    incText:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -96)
    incText:SetWidth(POPUP_W - 22)
    incText:SetJustifyH("LEFT")
    incText:SetTextColor(0.65, 0.65, 0.65)
    f.incText = incText

    -- ── Ctrl-drag to reposition ───────────────────────────────────────────────
    -- Holding Ctrl enables mouse so the frame can be grabbed and dragged.
    -- Releasing Ctrl (or the mouse button) locks it again.
    -- The frame remembers wherever it was dropped via ClearAllPoints/SetPoint
    -- so the position persists for the rest of the session.

    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsControlKeyDown() then
            -- If we're already fading out, snap back to fully visible hold
            if self.phase == "FADE_OUT" then
                self:SetAlpha(1)
                self.phase  = "HOLD"
                self.phaseT = 0
            end
            self:StartMoving()
            self.isDragging = true
        end
    end)

    f:SetScript("OnMouseUp", function(self, button)
        if self.isDragging then
            self:StopMovingOrSizing()
            self.isDragging = false
            -- Bake the new position as a TOPLEFT anchor so future Show() calls
            -- don't snap back to the default point.
            local point, _, relPoint, x, y = self:GetPoint(1)
            self:ClearAllPoints()
            self:SetPoint(point, UIParent, relPoint, x, y)
            -- Persist across sessions
            if not TheGrudgeSettings then TheGrudgeSettings = {} end
            TheGrudgeSettings.popupPos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    -- ── OnUpdate: Ctrl key tracking + animation phases ────────────────────────
    -- Ctrl held   → EnableMouse(true)  so the frame intercepts clicks for drag
    -- Ctrl absent → EnableMouse(false) so it stays fully click-through in combat
    --
    -- Animation mirrors Cheese's APIAnimation.lua alpha logic, driven inline
    -- (no XML AnimationGroup needed since we only have one frame).
    f:SetScript("OnUpdate", function(self, elapsed)
        -- Track Ctrl key to toggle mouse interactivity
        local ctrlDown = IsControlKeyDown()
        if ctrlDown ~= self._ctrlWas then
            self:EnableMouse(ctrlDown)
            self._ctrlWas = ctrlDown
        end

        if not self.phase then return end

        self.phaseT = (self.phaseT or 0) + elapsed
        self.totalT = (self.totalT or 0) + elapsed

        if self.phase == "FADE_IN" then
            local t = math.min(self.phaseT / FADE_IN_TIME, 1)
            self:SetAlpha(t)
            if t >= 1 then
                self.phase  = "HOLD"
                self.phaseT = 0
            end

        elseif self.phase == "HOLD" then
            -- Sin-wave border pulse (from Cheese's ScaleTemplate pulse concept)
            -- Mapped to [0.35, 1.0] so the border never fully disappears
            local pulse = 0.675 + 0.325 * math.sin(self.totalT * PULSE_FREQ)
            for _, edge in ipairs(self.edges) do
                edge:SetAlpha(pulse)
            end
            -- Pause the countdown while dragging OR while the mouse is still
            -- hovering over the player this alert was triggered for.
            local mouseoverName = UnitName("mouseover")
            local pinnedByMouse = mouseoverName
                and self.alertName
                and mouseoverName:lower() == self.alertName
            if not self.isDragging and not pinnedByMouse and self.phaseT >= HOLD_TIME then
                self.phase  = "FADE_OUT"
                self.phaseT = 0
            end

        elseif self.phase == "FADE_OUT" then
            -- If the player moves their mouse back onto the target while it's
            -- fading out, snap back to full opacity and resume hold.
            local mouseoverName = UnitName("mouseover")
            if mouseoverName and self.alertName
                and mouseoverName:lower() == self.alertName
            then
                self:SetAlpha(1)
                self.phase  = "HOLD"
                self.phaseT = 0
                return
            end
            local t = math.min(self.phaseT / FADE_OUT_TIME, 1)
            self:SetAlpha(1 - t)
            if t >= 1 then
                self:SetAlpha(0)
                self:Hide()
                self.phase = nil
            end
        end
    end)

    return f
end


-- ─── Alert:ShowVisual ────────────────────────────────────────────────────────

function Alert:ShowVisual(entry, sev, source)
    if not _frame then
        _frame = BuildFrame()
    end
    local f = _frame

    local r, g, b = sev.r, sev.g, sev.b

    -- Colour accent + border edges
    f.accent:SetTexture(r, g, b, 1)
    for _, edge in ipairs(f.edges) do
        edge:SetTexture(r, g, b, 1)
        edge:SetAlpha(1)
    end

    -- Severity label
    f.sevText:SetText("⚠  " .. sev.label .. "  ⚠")
    f.sevText:SetTextColor(r, g, b)

    -- Name
    f.nameText:SetText(entry.name)
    f.nameText:SetTextColor(r, g, b)

    -- Source
    f.srcText:SetText(GetSourceLabel(source))

    -- Kill count + relative time
    local kills    = entry.kill_count or 0
    local killWord = kills == 1 and "time" or "times"
    local lastSeen = FormatRelativeTime(entry.last_killed_at)
    f.killText:SetText(string.format(
        "|cff%sKilled you %d %s|r   ·   Last kill: %s",
        sev.color, kills, killWord, lastSeen
    ))

    -- Most recent incident
    if entry.incidents and #entry.incidents > 0 then
        local latest = entry.incidents[1]
        for _, inc in ipairs(entry.incidents) do
            if (inc.ts or 0) > (latest.ts or 0) then latest = inc end
        end
        local zone = latest.zone or "Unknown"
        if latest.subzone and latest.subzone ~= "" then
            zone = latest.subzone .. ", " .. zone
        end
        f.incText:SetText(string.format(
            "%s  ·  %s  ·  %s dmg",
            latest.spell or "Unknown",
            zone,
            tostring(latest.damage or 0)
        ))
    else
        f.incText:SetText("")
    end

    -- Reset and start animation
    f:SetAlpha(0)
    f.phase      = "FADE_IN"
    f.phaseT     = 0
    f.totalT     = 0
    f.alertName  = entry.name:lower()   -- used by OnUpdate to pin on mouseover
    f:Show()
end


-- ─── Alert:PlayAlertSound ────────────────────────────────────────────────────
-- Plays a severity-appropriate sound.
-- Custom MP3s in the extras/ folder are always attempted first via
-- PlaySoundFile. Silent placeholder files are shipped for each slot so the
-- call never errors — replacing a placeholder with real audio is all the user
-- needs to do to override that tier.
--
-- Slot mapping (mirrors README.txt):
--   extras/1.mp3 → CAUTION  (1-2 kills)
--   extras/2.mp3 → WARNING  (3-5 kills)
--   extras/3.mp3 → DANGER   (6+ kills)
--
-- Default built-in fallbacks (used only if PlaySoundFile somehow fails):
--   CAUTION → 569   (whisper notification — subtle)
--   WARNING → 8959  (igCreatureAggroSmall — punchy grunt)
--   DANGER  → 1483  (you are being attacked — urgent)

local SOUND_SLOTS = {
    CAUTION = { slot = 1, fallback = 569  },
    WARNING = { slot = 2, fallback = 8959 },
    DANGER  = { slot = 3, fallback = 1483 },
}

local EXTRAS_PATH = "Interface\\AddOns\\TheGrudge\\extras\\"

function Alert:PlayAlertSound(sev)
    -- Respect the sound enabled toggle
    if TheGrudgeSettings and TheGrudgeSettings.soundEnabled == false then return end

    local cfg = SOUND_SLOTS[sev.label]
    if not cfg then return end

    -- Try custom file first unless the user has disabled custom sounds
    local useCustom = not TheGrudgeSettings or TheGrudgeSettings.useCustomSounds ~= false
    if useCustom then
        local ok = PlaySoundFile(EXTRAS_PATH .. cfg.slot .. ".mp3")
        if ok then return end
    end
    -- Fall back to built-in game sound
    PlaySound(cfg.fallback)
end


-- ─── Alert:Trigger ───────────────────────────────────────────────────────────

function Alert:Trigger(entry, source)
    local kills    = entry.kill_count or 0
    local sev      = GetSeverity(kills)
    local killWord = kills == 1 and "time" or "times"
    local lastSeen = FormatRelativeTime(entry.last_killed_at)
    local srcStr   = GetSourceLabel(source)

    -- ── Chat output ──────────────────────────────────────────────────────────
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cffff4444[THE GRUDGE]|r |c%s⚠ %s ⚠|r  |cffffd700%s|r %s!",
        sev.color, sev.label, entry.name, srcStr
    ))
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cffaaaaaa   They have killed you |c%s%d|r %s.  Last kill: %s.|r",
        sev.color, kills, killWord, lastSeen
    ))

    if entry.incidents and #entry.incidents > 0 then
        local latest = entry.incidents[1]
        for _, inc in ipairs(entry.incidents) do
            if (inc.ts or 0) > (latest.ts or 0) then latest = inc end
        end
        local zone = latest.zone or "Unknown"
        if latest.subzone and latest.subzone ~= "" then
            zone = latest.subzone .. ", " .. zone
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cffaaaaaa   Last incident: |cffffd700%s|r in |cff88aaff%s|r for |c%s%d dmg|r.|r",
            latest.spell or "Unknown", zone, sev.color, latest.damage or 0
        ))
    end

    -- ── Sound ────────────────────────────────────────────────────────────────
    -- Custom MP3s in Interface/AddOns/TheGrudge/extras/ take priority.
    -- Silent placeholder files are shipped for each slot so PlaySoundFile
    -- always succeeds. Users replace them with their own audio to override.
    -- See extras/README.txt for the slot mapping.
    Alert:PlayAlertSound(sev)

    -- ── Visual popup ─────────────────────────────────────────────────────────
    Alert:ShowVisual(entry, sev, source)
end
