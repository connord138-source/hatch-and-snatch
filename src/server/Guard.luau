--!strict
-- Keeps the server's loops alive through errors (release audit, 2026-10-05). The
-- growth, income, hatching and state loops each ran unprotected: one runtime error
-- (one bad record, one missing config entry) killed that loop for the whole server
-- until it restarted. Guard.run protects one step (one player's share of a tick),
-- and Guard.loop runs a protected step forever. Errors are warned, at most once a
-- minute per label, so a repeating one can't flood the console.
local Guard = {}

local lastWarned: { [string]: number } = {}

-- Runs fn(...) protected; true if it finished without an error.
function Guard.run(label: string, fn: (...any) -> (), ...: any): boolean
	local args = table.pack(...)
	-- xpcall + traceback: the trace of where it failed, not of this line
	local ok, problem = xpcall(function(): any
		fn(table.unpack(args, 1, args.n))
		return nil
	end, debug.traceback)
	if not ok then
		local now = os.clock()
		if now - (lastWarned[label] or -math.huge) >= 60 then
			lastWarned[label] = now
			warn(`[{label}] {problem}`)
		end
	end
	return ok
end

-- Runs `step` every `seconds`, forever, each pass protected.
function Guard.loop(label: string, seconds: number, step: () -> ())
	task.spawn(function()
		while true do
			task.wait(seconds)
			Guard.run(label, step)
		end
	end)
end

return Guard
