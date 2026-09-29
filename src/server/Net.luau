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
local requests: { [string]: RemoteEvent } = {
	CreatureAction = makeEvent("CreatureAction"), -- (action: string, uid: string)
	Rebirth = makeEvent("Rebirth"), -- ()
	UpgradeBase = makeEvent("UpgradeBase"), -- ()
	Theme = makeEvent("Theme"), -- (themeId: string) buy if needed, then apply
	Security = makeEvent("Security"), -- () buy the next security upgrade
}

folder.Parent = ReplicatedStorage

local REQUEST_INTERVAL = 0.15 -- minimum seconds between one player's requests
local lastRequest: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

export type NotifyKind = "info" | "good" | "bad" | "rare"

local Net = {}

function Net.sendState(player: Player, snapshot: { [string]: any })
	stateUpdate:FireClient(player, snapshot)
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
function Net.onRequest(name: string, handler: (Player, ...any) -> ())
	requests[name].OnServerEvent:Connect(function(player: Player, ...: any)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < REQUEST_INTERVAL then
			return
		end
		lastRequest[player] = now
		handler(player, ...)
	end)
end

return Net
