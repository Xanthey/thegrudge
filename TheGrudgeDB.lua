-- TheGrudgeDB.lua
-- Written and managed by WhoDASH / SyncDAT.
-- Lives in Interface/AddOns/TheGrudge/ — NOT in WTF/SavedVariables.
-- WoW loads this as a plain read-only Lua file and never writes to it.
--
-- To test: replace PLAYERNAME with any player near you, then /reload.

TheGrudgeData = {
	["version"] = 1,
	["exported_at"] = 1772393425,
	["exported_by"] = "WhoDASH",
	["characters"] = {
		["Icecrown:Amarigold"] = {
			["name"] = "Amarigold",
			["faction"] = "Alliance",
			["class"] = "MAGE",
			["realm"] = "Icecrown",
			["grudge_list"] = {
				{
					["name"] = "Zilly",
					["kill_count"] = 1,
					["added_at"] = 1771727343,
					["last_killed_at"] = 1771384615,
					["incidents"] = {
						{
							["ts"] = 1771384615,
							["zone"] = "Tanaris",
							["subzone"] = "Gadgetzan",
							["spell"] = "Shield of Righteousness",
							["damage"] = 963,
						},
					},
				},
				{
					["name"] = "Packdesix",
					["kill_count"] = 4,
					["added_at"] = 1771727338,
					["last_killed_at"] = 1771642729,
					["incidents"] = {
						{
							["ts"] = 1771642729,
							["zone"] = "Warsong Gulch",
							["subzone"] = "",
							["spell"] = "Melee",
							["damage"] = 3839,
						},
						{
							["ts"] = 1771642207,
							["zone"] = "Silverwing Hold",
							["subzone"] = "",
							["spell"] = "Execute",
							["damage"] = 3216,
						},
						{
							["ts"] = 1771642018,
							["zone"] = "Warsong Gulch",
							["subzone"] = "",
							["spell"] = "Whirlwind",
							["damage"] = 5429,
						},
						{
							["ts"] = 1771641415,
							["zone"] = "Warsong Gulch",
							["subzone"] = "Silverwing Hold",
							["spell"] = "Whirlwind",
							["damage"] = 5234,
						},
					},
				},
				-- ================================================================
				-- TEST ENTRY — replace PLAYERNAME with someone near you, /reload
				-- ================================================================
				{
					["name"] = "Andalouse",
					["kill_count"] = 3,
					["added_at"] = 1772393425,
					["last_killed_at"] = 1772393425,
					["incidents"] = {
						{
							["ts"] = 1772393425,
							["zone"] = "Test Zone",
							["subzone"] = "",
							["spell"] = "Test Spell",
							["damage"] = 9999,
						},
					},
				},
			},
		},
	},
}
