--!strict
-- Remotes. Server -> client: state snapshots, toasts and announcements.
-- Client -> server: menu requests (the Creatures menu, rebirth). Their arguments
-- are untrusted, so every handler validates them; requests are also rate limited
-- per player. World actions (buying eggs, stealing, collecting cash) still go
-- through ProximityPrompts / touch pads that the server checks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local function makeEvent(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local stateUpdate = makeEvent("StateUpdate")
local notify = makeEvent("Notify")
local announce = makeEvent("Announce")
local hatchReveal = makeEvent("HatchReveal") -- (reveal table, see Net.hatchReveal)
local teleport = makeEvent("Teleport") -- (cframe) move your own character there
local requests: { [string]: RemoteEvent } = {
	CreatureAction = makeEvent("CreatureAction"), -- (action: string, uid: string, target: string?)
	Rebirth = makeEvent("Rebirth"), -- ()
	UpgradeBase = makeEvent("UpgradeBase"), -- ()
	DesignPick = makeEvent("DesignPick"), -- (slot: string, optionId: string) Castle Designer: buy if needed, then use
	DesignPreset = makeEvent("DesignPreset"), -- (presetId: string) Castle Designer: buy what's missing, set every slot
	Security = makeEvent("Security"), -- () buy the next security upgrade
	BuyFloor = makeEvent("BuyFloor"), -- () buy the next floor
	ToggleBuild = makeEvent("ToggleBuild"), -- (itemId: string) switch a bought decor item on/off
	BuyVault = makeEvent("BuyVault"), -- () buy the next vault room
	RedeemCode = makeEvent("RedeemCode"), -- (code: string)
	ClaimGroup = makeEvent("ClaimGroup"), -- () after the Roblox group join prompt
	WatchAd = makeEvent("WatchAd"), -- () show a rewarded video ad
	ClaimDaily = makeEvent("ClaimDaily"), -- () today's login streak reward
	RerollQuest = makeEvent("RerollQuest"), -- (index: number) swap one daily quest
}

-- The owner's admin panel: (action, target, ...) → a line of text (Admin.luau
-- checks who's asking on every call)
local admin = Instance.new("RemoteFunction")
admin.Name = "Admin"
admin.Parent = folder

folder.Parent = ReplicatedStorage

local REQUEST_INTERVAL = 0.15 -- minimum seconds between one player's requests of one kind
local lastRequest: { [Player]: { [string]: number } } = {}
Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

export type NotifyKind = "info" | "good" | "bad" | "rare"

local Net = {}

-- Sends the fields of a player's state that changed (StateService); `cleared`
-- lists fields that are now nil, and `full` says to start from an empty state.
function Net.sendState(player: Player, changes: { [string]: any }, cleared: { string }, full: boolean)
	stateUpdate:FireClient(player, changes, cleared, full)
end

function Net.notify(player: Player, text: string, kind: NotifyKind?)
	notify:FireClient(player, text, kind or "info")
end

-- Big centered message for everyone (rare hatches, moon events).
function Net.announce(text: string, color: Color3?)
	announce:FireAllClients(text, color or Color3.fromRGB(255, 255, 255))
end

-- Plays the hatch reveal reel for the player who hatched it.
function Net.hatchReveal(player: Player, reveal: { [string]: any })
	hatchReveal:FireClient(player, reveal)
end

-- Handles one kind of client request. The handler gets the raw, untrusted arguments.
-- Moves a player's character, on the server and on their own client. The client
-- owns its character's physics, so a server-only move could be undone by the
-- player still walking in (the auto-lock push "didn't stick" 2 times in 4, PC
-- round 473db78).
function Net.teleport(player: Player, cframe: CFrame)
	local character = player.Character
	if character then
		character:PivotTo(cframe)
	end
	teleport:FireClient(player, cframe)
end

-- Answers the admin panel's calls (rate limited like the requests).
function Net.onAdmin(handler: (Player, any, any, ...any) -> string)
	admin.OnServerInvoke = function(player: Player, action: any, target: any, ...: any): string
		local now = os.clock()
		local last: { [string]: number } = lastRequest[player] or {}
		lastRequest[player] = last
		if now - (last.Admin or 0) < REQUEST_INTERVAL then
			return "Too fast"
		end
		last.Admin = now
		return handler(player, action, target, ...)
	end
end

function Net.onRequest(name: string, handler: (Player, ...any) -> ())
	requests[name].OnServerEvent:Connect(function(player: Player, ...: any)
		local now = os.clock()
		local last = lastRequest[player] or {}
		lastRequest[player] = last
		if now - (last[name] or 0) < REQUEST_INTERVAL then
			return
		end
		last[name] = now
		handler(player, ...)
	end)
end

return Net
