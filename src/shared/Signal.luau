--!strict
-- Minimal synchronous signal for server-side service wiring. Listeners run in
-- connect order on the caller's thread (so "releasing" handlers finish before
-- the profile is saved). Unlike BindableEvent, tables are passed by reference.
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
		listener(...)
	end
end

return Signal
