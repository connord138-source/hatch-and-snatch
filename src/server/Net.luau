--!strict
-- Server-side remotes. All are server -> client for now: every player action
-- (buying eggs, collecting cash) goes through ProximityPrompts / touch pads that
-- the server validates, so there is no client -> server remote to exploit yet.
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

folder.Parent = ReplicatedStorage

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

return Net
