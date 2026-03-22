-- TheGrudge.lua
-- Entry point. Creates the addon namespace table that all other files share.

TheGrudge = {}
TheGrudge.version = "0.2.0"

-- Populated from TheGrudgeData (exported SavedVariables) on ADDON_LOADED
TheGrudge.grudgeMap = {}   -- keyed by lowercase player name → entry data
TheGrudge.enabled   = true
