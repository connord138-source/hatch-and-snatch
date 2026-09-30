--!strict
-- Minimal synchronous signal for server-side service wiring. Listeners run in
-- connect order on the caller's thread (so "releasing" handlers finish before
-- the profile is saved). Unlike BindableEvent, tables are passed by reference.
-- A listener that errors is reported and skipped, so the rest still run (a join
-- or leave must never stop halfway).
local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { listeners: { (...any) -> () } }, Signal))

function Signal.new(): Signal
	return setmetatable({ listeners = {} }, Signal)
end

function Signal.connect(self: Signal, listener: (...any) -> ())
	table.insert(self.listeners, listener)
end

function Signal.fire(self: Signal, ...: any)
	for _, listener in self.listeners do
		local args = table.pack(...)
		local ok, problem = xpcall(function(): any
			listener(table.unpack(args, 1, args.n))
			return nil
		end, debug.traceback)
		if not ok then
			warn(`[Signal] a listener failed: {problem}`)
		end
	end
end

return Signal
