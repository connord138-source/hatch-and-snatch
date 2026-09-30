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
	-- The server sends only the fields that changed; merge them into the current state
	stateUpdate.OnClientEvent:Connect(function(changes: { [string]: any }, cleared: { string }, full: boolean)
		local state = if full or ClientState.current == nil
			then {}
			else ClientState.current :: { [string]: any }
		for key, value in changes do
			state[key] = value
		end
		for _, key in cleared do
			state[key] = nil
		end
		ClientState.current = state
		ClientState.changed:fire(state)
	end)
end

-- Asks the server to do something (see Net.onRequest on the server).
function ClientState.request(name: string, ...: any)
	local remote = remotes:WaitForChild(name) :: RemoteEvent
	remote:FireServer(...)
end

return ClientState
