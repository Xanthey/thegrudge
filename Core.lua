-- Core.lua
-- Handles ADDON_LOADED, PLAYER_LOGIN, SavedVariables bootstrapping,
-- and slash command registration.

local ADDON_NAME = "TheGrudge"
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            TheGrudge:OnLoad()
        end
    elseif event == "PLAYER_LOGIN" then
        TheGrudge:OnLogin()
    end
end)


-- ─── TheGrudge:OnLoad ────────────────────────────────────────────────────────

function TheGrudge:OnLoad()
    -- TheGrudgeData is defined in TheGrudgeData.lua, which is written and managed
    -- exclusively by WhoDASH / SyncDAT. This addon never writes to it.
    -- If it's missing the file simply hasn't been synced yet.
    if not TheGrudgeData then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff4444[The Grudge]|r |cffff8800Warning:|r TheGrudgeData.lua not found or empty. " ..
            "Sync your grudge list from WhoDASH and |cffffffff/reload|r."
        )
        -- Leave grudgeMap empty — detection will just never fire until a sync arrives.
    else
        self:BuildGrudgeMap()

        local count = self:GrudgeCount()
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff4444[The Grudge]|r Loaded — |cffffd700%d|r target(s) on your list.", count)
        )
    end

    -- Always register slash commands so /grudge works even with no DB
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff4444[The Grudge]|r Type |cffffffff/grudge|r for commands."
    )
    self:RegisterSlashCommands()
end


-- ─── TheGrudge:OnLogin ───────────────────────────────────────────────────────

function TheGrudge:OnLogin()
    TheGrudge.Detection:Start()
end


-- ─── TheGrudge:BuildGrudgeMap ────────────────────────────────────────────────
-- Flattens ALL characters' grudge lists from TheGrudgeData into a single lookup
-- table keyed by lowercase player name.
--
-- Merging rule when the same player appears across multiple characters:
--   • kill_count     → summed
--   • last_killed_at → highest (most recent)
--   • incidents      → concatenated
--   • name           → first casing wins (cosmetic only)

function TheGrudge:BuildGrudgeMap()
    self.grudgeMap = {}

    if not TheGrudgeData or not TheGrudgeData.characters then return end

    for charKey, charData in pairs(TheGrudgeData.characters) do
        local grudgeList = charData.grudge_list
        if grudgeList then
            for _, entry in ipairs(grudgeList) do
                local key      = entry.name:lower()
                local existing = self.grudgeMap[key]

                if not existing then
                    -- Deep-copy incidents so we don't mutate the DB table
                    local incidents = {}
                    if entry.incidents then
                        for _, inc in ipairs(entry.incidents) do
                            incidents[#incidents + 1] = inc
                        end
                    end
                    self.grudgeMap[key] = {
                        name           = entry.name,
                        kill_count     = entry.kill_count     or 0,
                        last_killed_at = entry.last_killed_at or 0,
                        added_at       = entry.added_at       or 0,
                        incidents      = incidents,
                    }
                else
                    existing.kill_count     = existing.kill_count + (entry.kill_count or 0)
                    existing.last_killed_at = math.max(existing.last_killed_at, entry.last_killed_at or 0)
                    -- Merge incidents from additional characters
                    if entry.incidents then
                        for _, inc in ipairs(entry.incidents) do
                            existing.incidents[#existing.incidents + 1] = inc
                        end
                    end
                end
            end
        end
    end
end


-- ─── TheGrudge:GrudgeCount ───────────────────────────────────────────────────

function TheGrudge:GrudgeCount()
    local n = 0
    for _ in pairs(self.grudgeMap) do n = n + 1 end
    return n
end


-- ─── TheGrudge:IsOnGrudgeList ────────────────────────────────────────────────
-- Returns the grudge entry for a player name, or nil if not found.
-- Guards against non-string input (combat log can occasionally pass numbers).

function TheGrudge:IsOnGrudgeList(playerName)
    if type(playerName) ~= "string" or playerName == "" then return nil end
    return self.grudgeMap[playerName:lower()]
end


-- ─── TheGrudge:RegisterSlashCommands ────────────────────────────────────────

function TheGrudge:RegisterSlashCommands()
    SLASH_THEGRUDGE1 = "/grudge"
    SLASH_THEGRUDGE2 = "/tg"

    SlashCmdList["THEGRUDGE"] = function(msg)
        local cmd = msg and msg:lower():match("^%s*(%S*)") or ""

        if cmd == "" or cmd == "help" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r Commands:")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge list|r         — Print all grudge targets")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge status|r       — Show enabled/disabled state")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge on|r           — Enable detection")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge off|r          — Disable detection")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge reload|r       — Rebuild grudge map from DB")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge ui|r           — Open settings window")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge who|r          — Run /who sweep for all targets")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge server|r       — Show detected server")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge server <n>|r   — Override (Warmane, Dalaran...)")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge debug [n]|r    — Diagnostic dump (optional name lookup)")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/grudge test <n>|r     — Simulate an alert for <n>")

        elseif cmd == "list" then
            local count = TheGrudge:GrudgeCount()
            if count == 0 then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r Your grudge list is empty.")
            else
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffff4444[The Grudge]|r %d target(s):", count)
                )
                for key, entry in pairs(TheGrudge.grudgeMap) do
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format(
                            "  |cffffd700%s|r — killed you |cffff4444%d|r time(s)",
                            entry.name, entry.kill_count
                        )
                    )
                end
            end

        elseif cmd == "status" then
            local state = TheGrudge.enabled and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r Detection is " .. state)

        elseif cmd == "on" then
            TheGrudge.enabled = true
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r Detection |cff00ff00ENABLED|r.")

        elseif cmd == "off" then
            TheGrudge.enabled = false
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r Detection |cffff0000DISABLED|r.")

        elseif cmd == "reload" then
            TheGrudge:BuildGrudgeMap()
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format(
                    "|cffff4444[The Grudge]|r Grudge map rebuilt — |cffffd700%d|r target(s).",
                    TheGrudge:GrudgeCount()
                )
            )

        elseif cmd == "ui" or cmd == "settings" then
            TheGrudge.UI:Toggle()

        elseif cmd == "who" then
            TheGrudge.Detection:WhoSweep()

        elseif cmd == "server" then
            local arg = msg:match("^%s*%S+%s+(.-)%s*$")
            local ST  = TheGrudge.ServerTranslator
            if arg and arg ~= "" then
                ST:SetServer(arg)
            else
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format(
                        "|cffff4444[The Grudge]|r Server: |cffffd700%s|r (confidence: %s)",
                        ST:GetServer(), ST:GetConfidence()
                    )
                )
            end

        elseif cmd == "test" then
            local targetName = msg:match("^%s*%S+%s+(.-)%s*$")
            if not targetName or targetName == "" then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[The Grudge]|r Usage: /grudge test <playername>")
            else
                local entry = TheGrudge:IsOnGrudgeList(targetName)
                if entry then
                    TheGrudge.Alert:Trigger(entry, "test")
                else
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format(
                            "|cffff4444[The Grudge]|r |cffffd700%s|r is not on your grudge list.",
                            targetName
                        )
                    )
                end
            end

        elseif cmd == "debug" then
            -- ── Step 1: DB loaded? ───────────────────────────────────────────
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[TG Debug]|r === TheGrudge Debug ===")
            if not TheGrudgeData then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[TG Debug]|r FAIL: TheGrudgeData is nil — DB file not loaded.")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[TG Debug]|r OK: TheGrudgeData loaded, version=" .. tostring(TheGrudgeData.version))
            end

            -- ── Step 2: Grudge map ───────────────────────────────────────────
            local mapCount = TheGrudge:GrudgeCount()
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[TG Debug]|r GrudgeMap entries: " .. mapCount)
            for k, v in pairs(TheGrudge.grudgeMap) do
                DEFAULT_CHAT_FRAME:AddMessage("  key='" .. k .. "'  name='" .. v.name .. "'  kills=" .. v.kill_count)
            end

            -- ── Step 3: Current target ───────────────────────────────────────
            if UnitExists("target") then
                local tName = UnitName("target") or "nil"
                local tIsPlayer = UnitIsPlayer("target")
                DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[TG Debug]|r Target: '" .. tName .. "'  isPlayer=" .. tostring(tIsPlayer))
                local entry = TheGrudge:IsOnGrudgeList(tName)
                DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[TG Debug]|r Target on grudge list: " .. tostring(entry ~= nil))
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[TG Debug]|r No current target.")
            end

            -- ── Step 4: Manual name lookup ───────────────────────────────────
            local testName = msg:match("^%s*%S+%s+(.-)%s*$")
            if testName and testName ~= "" then
                local entry = TheGrudge:IsOnGrudgeList(testName)
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffff4444[TG Debug]|r Lookup '%s' → %s", testName, entry and "FOUND" or "NOT FOUND")
                )
                -- Also show what the lowercase key would be
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffff4444[TG Debug]|r Lookup key: '" .. testName:lower() .. "'"
                )
            end

            -- ── Step 5: Enabled state ────────────────────────────────────────
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[TG Debug]|r Enabled: " .. tostring(TheGrudge.enabled))
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[TG Debug]|r Server: " .. TheGrudge.ServerTranslator:GetServer())
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[TG Debug]|r Usage: /grudge debug [playername]")

        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffff4444[The Grudge]|r Unknown command. Type |cffffffff/grudge help|r."
            )
        end
    end
end
