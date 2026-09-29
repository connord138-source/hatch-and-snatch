--!strict
-- This player's own state as last sent by the server (StateService), shared by
-- every client controller, plus the way to send menu requests back. The server
-- validates every request; nothing here is trusted.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local ClientState = {
	current = nil :: { [string]: any }?,
	-- (state) — fired after every snapshot from the server
	changed = Signal.new(),
}

function ClientState.start()
	local stateUpdate = remotes:WaitForChild("StateUpdate") :: RemoteEvent
	stateUpdate.OnClientEvent:Connect(function(snapshot: { [string]: any })
		ClientState.current = snapshot
		ClientState.changed:fire(snapshot)
	end)
end

-- Asks the server to do something (see Net.onRequest on the server).
function ClientState.request(name: string, ...: any)
	local remote = remotes:WaitForChild(name) :: RemoteEvent
	remote:FireServer(...)
end

return ClientState
