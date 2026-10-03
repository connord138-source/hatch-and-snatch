--!strict
-- The owner's in-game admin panel (owner, 2026-10-03: "an access panel for my
-- account as admin in game that I can spawn certain items in with, change cash
-- amount, etc."). Admins are the experience's owner (the user who owns it, or
-- the owner rank of the group that does), anyone in ADMIN_USER_IDS, and every
-- player in Studio. They get an Admin attribute, which shows the panel's button
-- on their client (AdminController); the client can fake that attribute, so the
-- server checks who is asking on every request and ignores everyone else.
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AdminActions = require(script.Parent.AdminActions)
local Net = require(script.Parent.Net)

-- Extra admins by Roblox UserId (the owner needs no entry)
local ADMIN_USER_IDS: { number } = {}

local admins: { [Player]: boolean } = {}

local Admin = {}

local function checkAdmin(player: Player): boolean
	if RunService:IsStudio() or table.find(ADMIN_USER_IDS, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	-- A group-owned experience: the group's owner
	local ok, info = pcall(GroupService.GetGroupInfoAsync, GroupService, game.CreatorId)
	return ok and typeof(info) == "table" and info.Owner ~= nil and info.Owner.Id == player.UserId
end

function Admin.isAdmin(player: Player): boolean
	return admins[player] == true
end

-- Who a request applies to: the admin ("me"), every player ("all"), or the
-- player with that UserId.
local function targetsOf(player: Player, target: any): { Player }?
	if target == nil or target == "me" then
		return { player }
	elseif target == "all" then
		return Players:GetPlayers()
	elseif typeof(target) == "number" then
		local other = Players:GetPlayerByUserId(target)
		return if other then { other } else nil
	end
	return nil
end

local function run(player: Player, action: any, target: any, ...: any): string
	local targets = targetsOf(player, target)
	if targets == nil then
		return "That player has left"
	end
	if action == "addCash" then
		return AdminActions.addCash(targets, ...)
	elseif action == "setCash" then
		return AdminActions.setCash(targets, ...)
	elseif action == "essence" then
		return AdminActions.essence(targets, ...)
	elseif action == "xp" then
		return AdminActions.xp(targets, ...)
	elseif action == "spins" then
		return AdminActions.spins(targets, ...)
	elseif action == "rebirths" then
		return AdminActions.rebirths(targets, ...)
	elseif action == "grant" then
		return AdminActions.grant(targets, ...)
	elseif action == "egg" then
		return AdminActions.egg(targets, ...)
	elseif action == "hatchAll" then
		return AdminActions.hatchAll(targets)
	elseif action == "growAll" then
		return AdminActions.growAll(targets)
	elseif action == "storeAll" then
		return AdminActions.storeAll(targets)
	elseif action == "reveal" then
		return AdminActions.reveal({ player }, ...)
	elseif action == "maxBase" then
		return AdminActions.maxBase(targets)
	elseif action == "allDesigns" then
		return AdminActions.allDesigns(targets)
	elseif action == "pass" then
		return AdminActions.pass(targets, ...)
	elseif action == "product" then
		return AdminActions.product(targets, ...)
	elseif action == "moonEvent" then
		return AdminActions.moonEvent(...)
	elseif action == "zoneEvent" then
		return AdminActions.zoneEvent(...)
	elseif action == "clock" then
		return AdminActions.clock(...)
	elseif action == "restartGuide" then
		return AdminActions.restartGuide(targets)
	elseif action == "resetCodes" then
		return AdminActions.resetCodes(targets)
	elseif action == "nextDay" then
		return AdminActions.nextDay(targets)
	elseif action == "goToBase" then
		return AdminActions.goToBase(player, targets[1])
	end
	return "Unknown action"
end

function Admin.start()
	local function joined(player: Player)
		if checkAdmin(player) then
			admins[player] = true
			player:SetAttribute("Admin", true)
		end
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		task.spawn(joined, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		admins[player] = nil
	end)

	Net.onAdmin(function(player: Player, action: any, target: any, ...: any): string
		if not admins[player] then
			return "Not an admin"
		end
		local ok, result = pcall(run, player, action, target, ...)
		local text = if ok then result else "Failed: " .. tostring(result)
		print(`[Admin] {player.Name}: {action} ({tostring(target or "me")}) → {text}`)
		return text
	end)
end

return Admin
