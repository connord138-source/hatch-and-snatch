--!strict
-- Studio-only test hook, for looking at things you'd otherwise wait hours for.
-- During Play, switch the Command Bar to the Server view and run e.g.:
--
--   game.ServerStorage.StudioDebug:Invoke("grant", "Tidalotl", "Galaxy", "Adult", "Albino")
--       -- gives every player that creature (finish, stage and mutation optional;
--       -- "Normal" for no finish)
--   game.ServerStorage.StudioDebug:Invoke("event", "BloodMoon")
--       -- starts a moon event now
--   game.ServerStorage.StudioDebug:Invoke("essence", "MagmaRift", 50)
--       -- gives every player that biome's Essence (shrine testing)
--   game.ServerStorage.StudioDebug:Invoke("zone", "MagmaRift")
--       -- runs that zone's set-piece event now (bloom, clam, eruption, boulder, strike, meteor)
--   game.ServerStorage.StudioDebug:Invoke("pass", "VIP")
--       -- gives every player that game pass (DoubleCash, VIP, AutoCollect, ExtraNursery, LongerLock, OfflinePlus)
--   game.ServerStorage.StudioDebug:Invoke("product", "ServerLuck")
--       -- runs a developer product's effect for every player (ServerLuck, GrowthElixir, SkipHatch, CashSmall, CashLarge)
--   game.ServerStorage.StudioDebug:Invoke("product", "AdBoost")
--       -- the rewarded-ad reward (×2 cash for 15 min) without an ad
--   game.ServerStorage.StudioDebug:Invoke("perk", "premium")
--       -- toggles pretend Roblox Premium ("premium"), group membership ("group") or a
--       -- region that restricts paid random items ("restricted") for every player
--   game.ServerStorage.StudioDebug:Invoke("codes")
--       -- forgets which codes every player redeemed (Config.Codes), to test them again
--   game.ServerStorage.StudioDebug:Invoke("cash", 1e12)
--       -- gives every player that much cash (late-game upgrades cost billions)
--   game.ServerStorage.StudioDebug:Invoke("guide")
--       -- restarts the first-session guide for every player (from "buy an egg")
--   game.ServerStorage.StudioDebug:Invoke("daily")
--       -- pretends a day passed: the login reward and new daily quests come back
--   game.ServerStorage.StudioDebug:Invoke("reveal", "Capybaron", "Galaxy", "Iridescent")
--       -- plays the hatch reveal for that species (finish and mutation optional)
--       -- without granting anything (store screenshots)
--   game.ServerStorage.StudioDebug:Invoke("build")
--       -- maxes every player's base: level 5, both floors, all 4 vaults, security,
--       -- the 4 hiding spots and every decor and security item
--   game.ServerStorage.StudioDebug:Invoke("designs")
--       -- gives every player every Castle Designer option (Rainbow needs a rebirth)
--   game.ServerStorage.StudioDebug:Invoke("store")
--       -- moves every creature on a pedestal to storage (free pedestals for grants)
--
-- It is a BindableFunction, so only server code and the Studio Command Bar can
-- reach it (never clients), and it is only created in Studio. The actions
-- themselves live in AdminActions, shared with the owner's in-game admin panel.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local AdminActions = require(script.Parent.AdminActions)
local DataService = require(script.Parent.Services.DataService)
local MonetizationService = require(script.Parent.Services.MonetizationService)

local StudioDebug = {}

-- Every player in the test session
local function everyone(): { Player }
	local list: { Player } = {}
	for player in DataService.loadedPlayers() do
		table.insert(list, player)
	end
	return list
end

-- Pretend Roblox Premium, group membership or a restricted region (Studio only)
local function perk(name: any): string
	if name ~= "premium" and name ~= "group" and name ~= "restricted" then
		return "perk is premium, group or restricted"
	end
	local on = false
	for player in DataService.loadedPlayers() do
		on = not (
			if name == "premium"
				then MonetizationService.isPremium(player)
				elseif name == "group" then MonetizationService.inGroup(player)
				else MonetizationService.paidRandomRestricted(player)
		)
		MonetizationService.setDebugPerk(player, name, on)
	end
	return `{name} {if on then "on" else "off"}`
end

function StudioDebug.start()
	if not RunService:IsStudio() then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "StudioDebug"
	hook.OnInvoke = function(action: any, ...: any): string
		local all = everyone()
		if action == "grant" then
			return AdminActions.grant(all, ...)
		elseif action == "event" then
			return AdminActions.moonEvent(...)
		elseif action == "essence" then
			return AdminActions.essence(all, ...)
		elseif action == "store" then
			return AdminActions.storeAll(all)
		elseif action == "zone" then
			return AdminActions.zoneEvent(...)
		elseif action == "pass" then
			return AdminActions.pass(all, ...)
		elseif action == "product" then
			return AdminActions.product(all, ...)
		elseif action == "perk" then
			return perk(...)
		elseif action == "codes" then
			return AdminActions.resetCodes(all)
		elseif action == "cash" then
			return AdminActions.addCash(all, ...)
		elseif action == "guide" then
			return AdminActions.restartGuide(all)
		elseif action == "reveal" then
			return AdminActions.reveal(all, ...)
		elseif action == "build" then
			return AdminActions.maxBase(all)
		elseif action == "designs" then
			return AdminActions.allDesigns(all)
		elseif action == "daily" then
			return AdminActions.nextDay(all)
		end
		return "actions: grant(species, finish?, stage?), event(id), essence(biome, amount?), zone(biome), pass(key), product(key), perk(premium|group|restricted), codes(), cash(amount), guide(), daily(), store(), build(), designs(), reveal(species, finish?)"
	end
	hook.Parent = ServerStorage
end

return StudioDebug
