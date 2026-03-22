-- SettingsUI.lua
-- TheGrudge settings window.
-- Opens with /grudge ui  or  /grudge settings
-- Style mirrors WhoDAT's WhoCHAT palette: dark near-black background,
-- opaque border matte, blue accent on interactive elements.

TheGrudge.UI = {}

local UI = TheGrudge.UI

-- ─── Palette (WhoCHAT-matched from WhoDAT ui_main.lua) ───────────────────────
local PAL = {
    bg     = { 0.06, 0.07, 0.10, 0.96 },
    border = { 0.00, 0.00, 0.00, 1.00 },
    accent = { 0.16, 0.32, 0.80, 0.90 },
    nav    = { 0.08, 0.09, 0.12, 1.00 },
    muted  = { 0.45, 0.48, 0.55, 1.00 },
    text   = { 0.90, 0.90, 0.90, 1.00 },
    dim    = { 0.55, 0.55, 0.58, 1.00 },
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────
local function Solid(tex, r, g, b, a)
    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    tex:SetVertexColor(r, g, b, a or 1)
end

-- Attach the WhoCHAT chrome (dark bg + thick opaque border matte) to any frame
local function Chrome(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT",     f, "TOPLEFT",      1, -1)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1,  1)
    Solid(bg, PAL.bg[1], PAL.bg[2], PAL.bg[3], PAL.bg[4])

    -- Border frame sits above content so it draws over child frames
    local bframe = CreateFrame("Frame", nil, f)
    bframe:SetAllPoints(f)
    bframe:SetFrameLevel(f:GetFrameLevel() + 10)

    local function Edge(bframe, p1, x1, y1, p2, x2, y2, isH)
        local t = bframe:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p1, f, p1, x1, y1)
        t:SetPoint(p2, f, p2, x2, y2)
        Solid(t, PAL.border[1], PAL.border[2], PAL.border[3], PAL.border[4])
        if isH then t:SetHeight(6) else t:SetWidth(6) end
    end
    Edge(bframe, "TOPLEFT",     0,  0, "TOPRIGHT",    0,  0, true)
    Edge(bframe, "BOTTOMLEFT",  0,  0, "BOTTOMRIGHT", 0,  0, true)
    Edge(bframe, "TOPLEFT",     0,  0, "BOTTOMLEFT",  0,  0, false)
    Edge(bframe, "TOPRIGHT",    0,  0, "BOTTOMRIGHT", 0,  0, false)
end

-- Tint a standard button to match the palette
local function TintBtn(btn)
    local nt = btn:GetNormalTexture()
    local pt = btn:GetPushedTexture()
    local ht = btn:GetHighlightTexture()
    if nt then Solid(nt, PAL.nav[1],    PAL.nav[2],    PAL.nav[3],    0.70) end
    if pt then Solid(pt, PAL.accent[1], PAL.accent[2], PAL.accent[3], 0.50) end
    if ht then
        ht:SetBlendMode("ADD")
        Solid(ht, PAL.accent[1], PAL.accent[2], PAL.accent[3], 0.22)
    end
end

-- Section header label
local function SectionLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(PAL.accent[1], PAL.accent[2], PAL.accent[3])
    return fs
end

-- Dim caption label
local function Caption(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(PAL.dim[1], PAL.dim[2], PAL.dim[3])
    if width then fs:SetWidth(width) end
    return fs
end

-- Thin horizontal divider
local function Divider(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetPoint("TOPLEFT",  parent, "TOPLEFT",  16, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, y)
    Solid(t, PAL.nav[1], PAL.nav[2], PAL.nav[3], 0.8)
    return t
end

-- Standard action button
local function MakeButton(parent, label, w, h)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w or 140, h or 22)
    btn:SetText(label)
    TintBtn(btn)
    return btn
end

-- Checkbox with inline label
local function MakeCheckbox(parent, label, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb:SetSize(20, 20)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(label)
    fs:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
    cb._label = fs
    return cb
end

-- ─── Settings defaults ────────────────────────────────────────────────────────
local function EnsureSettings()
    if not TheGrudgeSettings then TheGrudgeSettings = {} end
    local s = TheGrudgeSettings
    if s.soundEnabled  == nil then s.soundEnabled  = true end
    if s.useCustomSounds == nil then s.useCustomSounds = false end
    return s
end


-- ─── UI:Build ────────────────────────────────────────────────────────────────
local _win = nil

local WIN_W = 420
local WIN_H = 390

function UI:Build()
    if _win then return _win end

    local s = EnsureSettings()

    -- ── Root window ──────────────────────────────────────────────────────────
    local f = CreateFrame("Frame", "TheGrudgeSettingsWindow", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        local pt, _, rp, x, y = self:GetPoint(1)
        self:ClearAllPoints()
        self:SetPoint(pt, UIParent, rp, x, y)
        EnsureSettings()
        TheGrudgeSettings.uiPos = { point = pt, relPoint = rp, x = x, y = y }
    end)
    f:Hide()
    Chrome(f)

    -- Restore saved position if any
    local pos = s.uiPos
    if pos then
        f:ClearAllPoints()
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end

    -- ── Title bar ────────────────────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0,  0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0,  0)
    titleBar:SetHeight(28)
    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints(titleBar)
    Solid(titleBg, PAL.nav[1], PAL.nav[2], PAL.nav[3], PAL.nav[4])

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 14, 0)
    titleText:SetText("|cffff4444The Grudge|r  —  Settings")
    titleText:SetTextColor(1, 1, 1)

    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)
    closeBtn:SetSize(24, 24)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- ── Content area ─────────────────────────────────────────────────────────
    -- All controls placed relative to content frame for clarity
    local c = CreateFrame("Frame", nil, f)
    c:SetPoint("TOPLEFT",     f, "TOPLEFT",     14, -36)
    c:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14,  14)

    local y = -4   -- running y cursor (negative = downward)
    local function Y(step) y = y - (step or 10) end

    -- ── SECTION: Detection Toast ──────────────────────────────────────────────
    SectionLabel(c, "Detection Toast", 0, y)
    Y(22)
    Caption(c, "Hold Ctrl and drag the toast to reposition it.", 2, y)
    Y(18)

    local testRow = { }
    local testLabels = {
        { label = "Test Caution",  sev = "CAUTION", kills = 1 },
        { label = "Test Warning",  sev = "WARNING", kills = 3 },
        { label = "Test Danger",   sev = "DANGER",  kills = 6 },
    }
    local btnX = 0
    for _, td in ipairs(testLabels) do
        local btn = MakeButton(c, td.label, 118, 22)
        btn:SetPoint("TOPLEFT", c, "TOPLEFT", btnX, y)
        btn:SetScript("OnClick", function()
            -- Build a synthetic entry matching the severity requested
            local fakeEntry = {
                name          = "TestPlayer",
                kill_count    = td.kills,
                last_killed_at = time() - 3600,
                incidents     = {
                    { ts = time() - 3600, zone = "Warsong Gulch",
                      subzone = "", spell = "Execute", damage = 4200 }
                },
            }
            TheGrudge.Alert:Trigger(fakeEntry, "test")
        end)
        testRow[#testRow+1] = btn
        btnX = btnX + 126
    end
    Y(30)

    local resetPosBtn = MakeButton(c, "Reset Toast Position", 180, 22)
    resetPosBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
    resetPosBtn:SetScript("OnClick", function()
        -- Wipe saved position and snap back to default
        EnsureSettings()
        TheGrudgeSettings.popupPos = nil
        local popup = _G["TheGrudgePopup"]
        if popup then
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -80)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r Toast position reset to default.")
    end)
    Y(36)

    Divider(c, y)
    Y(12)

    -- ── SECTION: Sound ────────────────────────────────────────────────────────
    SectionLabel(c, "Alert Sounds", 0, y)
    Y(26)

    local cbSound = MakeCheckbox(c, "Enable alert sounds", 0, y)
    cbSound:SetChecked(EnsureSettings().soundEnabled)
    cbSound:SetScript("OnClick", function(self)
        EnsureSettings()
        TheGrudgeSettings.soundEnabled = self:GetChecked() and true or false
    end)
    Y(30)

    local cbCustom = MakeCheckbox(c, "Use custom sound files from extras/ folder", 0, y)
    cbCustom:SetChecked(EnsureSettings().useCustomSounds)
    cbCustom:SetScript("OnClick", function(self)
        EnsureSettings()
        TheGrudgeSettings.useCustomSounds = self:GetChecked() and true or false
    end)
    Y(24)
    Caption(c, "Place 1.mp3 / 2.mp3 / 3.mp3 in Interface/AddOns/TheGrudge/extras/", 22, y, WIN_W - 60)
    Y(36)

    -- Sound slot rows
    local SLOT_INFO = {
        { label = "CAUTION  (1–2 kills)", slot = 1, sev = "CAUTION", kills = 1 },
        { label = "WARNING  (3–5 kills)", slot = 2, sev = "WARNING", kills = 3 },
        { label = "DANGER   (6+ kills)",  slot = 3, sev = "DANGER",  kills = 6 },
    }
    local sevColors = { CAUTION = {1,0.6,0}, WARNING = {1,0.27,0}, DANGER = {1,0,0} }

    for _, si in ipairs(SLOT_INFO) do
        local col = sevColors[si.sev]
        local rowLabel = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rowLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y)
        rowLabel:SetText(si.label)
        rowLabel:SetTextColor(col[1], col[2], col[3])
        rowLabel:SetWidth(160)

        local fileTag = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fileTag:SetPoint("LEFT", rowLabel, "RIGHT", 8, 0)
        fileTag:SetText("extras/" .. si.slot .. ".mp3")
        fileTag:SetTextColor(PAL.dim[1], PAL.dim[2], PAL.dim[3])

        local previewBtn = MakeButton(c, "Preview", 82, 20)
        previewBtn:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, y)
        previewBtn:SetScript("OnClick", function()
            local sevTable
            for _, sv in ipairs(TheGrudge.Alert._SEVERITY or {}) do
                if sv.label == si.sev then sevTable = sv; break end
            end
            -- Build a minimal sev table if needed
            if not sevTable then
                local r, g, b = col[1], col[2], col[3]
                sevTable = { label = si.sev, r = r, g = g, b = b,
                             color = (si.sev == "CAUTION" and "ffff9900")
                                  or (si.sev == "WARNING" and "ffff4400")
                                  or "ffff0000" }
            end
            TheGrudge.Alert:PlayAlertSound(sevTable)
        end)
        Y(26)
    end

    Divider(c, y)
    Y(12)

    -- ── SECTION: Grudge List ──────────────────────────────────────────────────
    SectionLabel(c, "Grudge List", 0, y)
    Y(26)

    local countFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countFS:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y)
    local n = TheGrudge:GrudgeCount()
    countFS:SetText(string.format("%d player(s) on your grudge list.", n))
    countFS:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
    f.countFS = countFS   -- stored so UI:Show() can refresh it
    Y(30)

    -- Channel label
    local chanLabel = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chanLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 4, y)
    chanLabel:SetText("Output channel:")
    chanLabel:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])

    -- All possible channels; availability checked at send time
    local CHANNELS = {
        { label = "Local Defense", type = "LOCAL_DEFENSE" },
        { label = "Say",           type = "SAY"     },
        { label = "Yell",          type = "YELL"    },
        { label = "Party",         type = "PARTY"   },
        { label = "Raid",          type = "RAID"    },
        { label = "Guild",         type = "GUILD"   },
    }

    -- Track selected channel index in settings
    EnsureSettings()
    if not TheGrudgeSettings.printChannel then
        TheGrudgeSettings.printChannel = "SAY"
    end

    -- Find initial index
    local function GetChannelIndex()
        for i, ch in ipairs(CHANNELS) do
            if ch.type == TheGrudgeSettings.printChannel then return i end
        end
        return 1
    end

    -- Dropdown using WoW's native UIDropDownMenu
    local dropdown = CreateFrame("Frame", "TheGrudgeChanDropdown", c, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", c, "TOPLEFT", 100, y + 6)
    UIDropDownMenu_SetWidth(dropdown, 140)
    UIDropDownMenu_SetText(dropdown, CHANNELS[GetChannelIndex()].label)

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for i, ch in ipairs(CHANNELS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = ch.label
            info.value   = ch.type
            info.checked = (ch.type == TheGrudgeSettings.printChannel)
            info.func    = function()
                TheGrudgeSettings.printChannel = ch.type
                UIDropDownMenu_SetText(dropdown, ch.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    Y(34)

    -- Send button — validates channel availability before sending
    local sendBtn = MakeButton(c, "Send List", 100, 22)
    sendBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
    sendBtn:SetScript("OnClick", function()
        local chanType = TheGrudgeSettings.printChannel or "SAY"

        -- Availability guards
        if chanType == "PARTY" and not UnitInParty("player") then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r You are not in a party.")
            return
        end
        if chanType == "RAID" and not UnitInRaid("player") then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r You are not in a raid.")
            return
        end
        if chanType == "GUILD" and not IsInGuild() then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r You are not in a guild.")
            return
        end

        -- Build and send one message per grudge entry
        -- Plain text only for chat — no colour codes (they don't render in chat channels)
        local count = TheGrudge:GrudgeCount()
        if count == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r Your grudge list is empty.")
            return
        end

        SendChatMessage(string.format("[The Grudge] %d player(s) on watch list:", count), chanType)
        for _, entry in pairs(TheGrudge.grudgeMap) do
            SendChatMessage(string.format(
                "  %s — killed me %d time(s)", entry.name, entry.kill_count), chanType)
        end
    end)
    Y(36)

    -- ── Version footer ────────────────────────────────────────────────────────
    local verFS = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    verFS:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 4)
    verFS:SetText("TheGrudge v" .. (TheGrudge.version or "?") .. "  ·  Synced by WhoDASH")
    verFS:SetTextColor(PAL.muted[1], PAL.muted[2], PAL.muted[3])

    _win = f
    return f
end


-- ─── UI:Toggle / Show / Hide ─────────────────────────────────────────────────

function UI:Show()
    local f = self:Build()
    -- Refresh grudge count each time the window opens
    if f.countFS then
        local n = TheGrudge:GrudgeCount()
        f.countFS:SetText(string.format("%d player(s) on your grudge list.", n))
    end
    f:Show()
end

function UI:Hide()
    if _win then _win:Hide() end
end

function UI:Toggle()
    if _win and _win:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end