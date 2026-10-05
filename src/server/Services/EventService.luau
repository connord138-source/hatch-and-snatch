--!strict
-- Hourly server-wide Moon events (every 2 minutes in Studio). The Moon Egg's
-- color is the alarm; clients read the workspace attributes for the banner.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Types = require(ReplicatedStorage.Shared.Config.Types)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local WorldService = require(script.Parent.WorldService)

local MOON_COLORS: { [string]: Color3 } = {
	BloodMoon = Color3.fromRGB(200, 30, 40),
	GoldMoon = Color3.fromRGB(255, 200, 60),
	VoidMoon = Color3.fromRGB(110, 40, 170),
	PrismMoon = Color3.fromRGB(120, 255, 230),
}
local IDLE_MOON = Color3.fromRGB(235, 230, 210)

local active: Types.MoonEvent? = nil
local rng = Random.new()

local EventService = {}

function EventService.active(): Types.MoonEvent?
	return active
end

function EventService.activeId(): string?
	return if active then active.id else nil
end

function EventService.finishMultiplier(): number
	return if active then active.finishChanceMultiplier else 1
end

function EventService.earningsMultiplier(): number
	return if active then active.earningsMultiplier else 1
end

function EventService.spawnsJunkEgg(): boolean
	return active ~= nil and active.spawnsJunkEgg
end

local function pickEvent(): Types.MoonEvent
	local total = 0
	for _, event in Config.MoonEvents do
		total += event.weight
	end
	local roll = rng:NextNumber() * total
	for _, event in Config.MoonEvents do
		roll -= event.weight
		if roll <= 0 then
			return event
		end
	end
	return Config.MoonEvents[1]
end

local function setMoon(color: Color3)
	local moon = WorldService.moon
	if moon then
		moon.Color = color
	end
end

-- Starts an event now. Exposed so Studio testing / admin tools can force one.
function EventService.run(event: Types.MoonEvent)
	active = event
	local endsAt = Timing.now() + event.durationSeconds
	Workspace:SetAttribute("MoonEvent", event.id)
	Workspace:SetAttribute("MoonEventName", event.displayName)
	Workspace:SetAttribute("MoonEventEndsAt", endsAt)
	Workspace:SetAttribute("MoonEventInfo", event.description)
	local color = MOON_COLORS[event.id] or IDLE_MOON
	Workspace:SetAttribute("MoonEventColor", color)
	setMoon(color)
	WorldService.setMoonTint(color)
	Net.announce(`{event.displayName} is rising!`, color)
	task.wait(event.durationSeconds)
	if active == event then
		active = nil
		Workspace:SetAttribute("MoonEvent", nil)
		Workspace:SetAttribute("MoonEventName", nil)
		Workspace:SetAttribute("MoonEventEndsAt", nil)
		Workspace:SetAttribute("MoonEventInfo", nil)
		Workspace:SetAttribute("MoonEventColor", nil)
		setMoon(IDLE_MOON)
		WorldService.setMoonTint(nil)
	end
end

function EventService.start()
	local interval = if Timing.isStudio()
		then Config.Debug.studioMoonEventIntervalSeconds
		else Config.Economy.tunables.moonEventIntervalSeconds
	task.spawn(function()
		while true do
			Workspace:SetAttribute("MoonEventNextAt", Timing.now() + interval)
			task.wait(interval)
			Workspace:SetAttribute("MoonEventNextAt", nil)
			Guard.run("EventService.run", function()
				EventService.run(pickEvent())
			end)
		end
	end)
	-- The board at the South Event Grounds: what's up now, or when the next moon rises
	task.spawn(function()
		while true do
			local board = WorldService.eventBoard
			if board then
				local now = Timing.now()
				local endsAt = Workspace:GetAttribute("MoonEventEndsAt")
				local nextAt = Workspace:GetAttribute("MoonEventNextAt")
				if active and typeof(endsAt) == "number" then
					board.Text =
						`🌙 {active.displayName}\n{Format.duration(math.max(0, endsAt - now))} left`
				elseif typeof(nextAt) == "number" then
					board.Text = `🌙 Next moon event\nin {Format.duration(math.max(0, nextAt - now))}`
				else
					board.Text = "🌙 Moon Events"
				end
			end
			task.wait(1)
		end
	end)
end

return EventService
