--!strict
-- Placeholder HUD built from code: cash + rate, uncollected, incubator timers,
-- moon event banner, toasts and server announcements. Presentation only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local TOAST_COLORS: { [string]: Color3 } = {
	info = Color3.fromRGB(40, 44, 56),
	good = Color3.fromRGB(30, 110, 60),
	bad = Color3.fromRGB(140, 40, 40),
	rare = Color3.fromRGB(150, 90, 10),
}

local HudController = {}

local state: { [string]: any }? = nil

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	l.TextScaled = true
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function panel(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	f.BackgroundTransparency = 0.25
	for key, value in props do
		(f :: any)[key] = value
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = f
	f.Parent = parent
	return f
end

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Cash panel (top-left)
	local cashPanel = panel(gui, { Size = UDim2.fromOffset(250, 96), Position = UDim2.fromOffset(12, 12) })
	local cashLabel = label(cashPanel, {
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(120, 255, 140),
		Text = "$0",
	})
	local rateLabel = label(cashPanel, {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 46),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "+$0/s",
	})
	local uncollectedLabel = label(cashPanel, {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 68),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		Text = "",
	})

	-- Incubators (top-right)
	local incubatorPanel = panel(gui, {
		Size = UDim2.fromOffset(230, 40 + Config.Economy.tunables.incubatorSlots * 30),
		Position = UDim2.new(1, -242, 0, 12),
	})
	label(
		incubatorPanel,
		{ Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 6), Text = "Incubators" }
	)
	local incubatorRows: { TextLabel } = {}
	for i = 1, Config.Economy.tunables.incubatorSlots do
		incubatorRows[i] = label(incubatorPanel, {
			Size = UDim2.new(1, -20, 0, 24),
			Position = UDim2.fromOffset(10, 6 + i * 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			Text = `{i}. empty`,
		})
	end

	-- Moon event banner (top-center)
	local banner = panel(gui, {
		Size = UDim2.fromOffset(320, 40),
		Position = UDim2.new(0.5, -160, 0, 12),
		Visible = false,
	})
	local bannerLabel = label(banner, { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) })

	-- Base lock status (under the cash panel)
	local lockPanel = panel(gui, { Size = UDim2.fromOffset(250, 34), Position = UDim2.fromOffset(12, 116) })
	local lockStatus = label(lockPanel, {
		Size = UDim2.new(1, -20, 1, -8),
		Position = UDim2.fromOffset(10, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Base: unlocked",
	})

	-- Carry banner (center, while holding a stolen creature)
	local carryBanner = panel(gui, {
		Size = UDim2.fromOffset(420, 44),
		Position = UDim2.new(0.5, -210, 0, 60),
		BackgroundColor3 = Color3.fromRGB(150, 30, 30),
		Visible = false,
	})
	local carryLabel =
		label(carryBanner, { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) })

	-- Toasts (bottom-center)
	local toastHolder = Instance.new("Frame")
	toastHolder.BackgroundTransparency = 1
	toastHolder.Size = UDim2.fromOffset(460, 200)
	toastHolder.Position = UDim2.new(0.5, -230, 1, -260)
	toastHolder.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 6)
	layout.Parent = toastHolder

	local function toast(text: string, kind: string)
		local toastFrame = panel(toastHolder, {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = TOAST_COLORS[kind] or TOAST_COLORS.info,
		})
		label(toastFrame, { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), Text = text })
		task.delay(4, function()
			toastFrame:Destroy()
		end)
	end

	-- Announcements (center)
	local announceLabel = label(gui, {
		Size = UDim2.new(0.8, 0, 0, 60),
		Position = UDim2.new(0.1, 0, 0.3, 0),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local function announce(text: string, color: Color3)
		announceLabel.Text = text
		announceLabel.TextColor3 = color
		announceLabel.TextTransparency = 0
		announceLabel.TextStrokeTransparency = 0.3
		task.delay(3, function()
			if announceLabel.Text == text then
				TweenService
					:Create(
						announceLabel,
						TweenInfo.new(1),
						{ TextTransparency = 1, TextStrokeTransparency = 1 }
					)
					:Play()
			end
		end)
	end

	local stateUpdate = remotes:WaitForChild("StateUpdate") :: RemoteEvent
	local notify = remotes:WaitForChild("Notify") :: RemoteEvent
	local announceRemote = remotes:WaitForChild("Announce") :: RemoteEvent
	stateUpdate.OnClientEvent:Connect(function(newState)
		state = newState
	end)
	notify.OnClientEvent:Connect(toast)
	announceRemote.OnClientEvent:Connect(announce)

	-- Per-frame refresh (cheap: a handful of labels)
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		local now = Workspace:GetServerTimeNow()

		local current = state
		if current then
			cashLabel.Text = Format.cash(current.cash)
			rateLabel.Text = `+{Format.cash(current.rate)}/s`
			uncollectedLabel.Text = if current.uncollected >= 1
				then `{Format.cash(current.uncollected)} waiting — step on your green pad`
				else ""
			if now < current.lockedUntil then
				lockStatus.Text = `Base: LOCKED {Format.duration(current.lockedUntil - now)}`
				lockStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
			elseif now < current.lockCooldownUntil then
				lockStatus.Text = `Lock recharging {Format.duration(current.lockCooldownUntil - now)}`
				lockStatus.TextColor3 = Color3.fromRGB(200, 200, 200)
			elseif now < current.protectedUntil then
				lockStatus.Text = `New-player shield {Format.duration(current.protectedUntil - now)}`
				lockStatus.TextColor3 = Color3.fromRGB(150, 200, 255)
			else
				lockStatus.Text = "Base: unlocked — lock it at the red button"
				lockStatus.TextColor3 = Color3.fromRGB(255, 220, 120)
			end
			if current.carrying then
				carryBanner.Visible = true
				carryLabel.Text = `Carrying {current.carrying} — run back to your base!`
			else
				carryBanner.Visible = false
			end
			for i, row in incubatorRows do
				local egg = current.incubators[i]
				if egg then
					local biome = Config.Biomes[egg.biome]
					local remaining = egg.hatchAt - now
					row.Text = if remaining > 0
						then `{i}. {biome.displayName} — {Format.duration(remaining)}`
						else `{i}. {biome.displayName} — hatching!`
					row.TextColor3 = Color3.new(1, 1, 1)
				else
					row.Text = `{i}. empty`
					row.TextColor3 = Color3.fromRGB(160, 160, 160)
				end
			end
		end

		local eventName = Workspace:GetAttribute("MoonEventName")
		local endsAt = Workspace:GetAttribute("MoonEventEndsAt")
		if typeof(eventName) == "string" and typeof(endsAt) == "number" then
			banner.Visible = true
			bannerLabel.Text = `🌕 {eventName} — {Format.duration(endsAt - now)}`
		else
			banner.Visible = false
		end
	end)
end

return HudController
