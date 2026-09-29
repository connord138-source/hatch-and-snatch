--!strict
-- Placeholder HUD built from code: cash + rate, uncollected, Hatcher Level + XP,
-- Luck Wheel spins, incubator timers, carried-egg hint, moon event banner, toasts
-- and server announcements. Presentation only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local label = Ui.label
local panel = Ui.panel

local TOAST_COLORS: { [string]: Color3 } = {
	info = Color3.fromRGB(40, 44, 56),
	good = Color3.fromRGB(30, 110, 60),
	bad = Color3.fromRGB(140, 40, 40),
	rare = Color3.fromRGB(150, 90, 10),
}

local HudController = {}

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Toasts and announcements go on their own layer so they show over open menus
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "HatchOverlay"
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = 10
	overlay.Parent = gui.Parent

	-- Cash panel (top-left)
	local cashPanel = panel(gui, { Size = UDim2.fromOffset(250, 132), Position = UDim2.fromOffset(12, 12) })
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

	-- Hatcher Level + XP bar + Luck Wheel spins (bottom of the cash panel)
	local levelLabel = label(cashPanel, {
		Size = UDim2.new(0.62, -10, 0, 18),
		Position = UDim2.fromOffset(10, 92),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(150, 220, 255),
		Text = "Lv 1",
	})
	local spinsLabel = label(cashPanel, {
		Size = UDim2.new(0.38, -10, 0, 18),
		Position = UDim2.new(0.62, 0, 0, 92),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(255, 215, 90),
		Text = "",
	})
	local xpBar = Instance.new("Frame")
	xpBar.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
	xpBar.BorderSizePixel = 0
	xpBar.Position = UDim2.fromOffset(10, 114)
	xpBar.Size = UDim2.new(1, -20, 0, 8)
	xpBar.Parent = cashPanel
	local xpFill = Instance.new("Frame")
	xpFill.BackgroundColor3 = Color3.fromRGB(110, 200, 255)
	xpFill.BorderSizePixel = 0
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.Parent = xpBar

	-- Incubators (left, under the lock status; the top-right belongs to Roblox's player list)
	local maxIncubators = #Config.Progression.incubatorSlotCosts
	local incubatorPanel = panel(gui, {
		Size = UDim2.fromOffset(250, 70),
		Position = UDim2.fromOffset(12, 194),
	})
	label(
		incubatorPanel,
		{ Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 6), Text = "Incubators" }
	)
	local incubatorRows: { TextLabel } = {}
	for i = 1, maxIncubators do
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
		Size = UDim2.fromOffset(460, 58),
		Position = UDim2.new(0.5, -230, 0, 12),
		Visible = false,
	})
	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Thickness = 2
	bannerStroke.Parent = banner
	local bannerLabel = label(banner, { Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 3) })
	-- What the event does, so "Blood Moon" means something to new players
	local bannerInfo = label(banner, {
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 33),
		TextColor3 = Color3.fromRGB(230, 230, 230),
	})

	-- Base lock status (under the cash panel)
	local lockPanel = panel(gui, { Size = UDim2.fromOffset(250, 34), Position = UDim2.fromOffset(12, 152) })
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

	-- Carried-egg hint (while holding an egg bought off the belt)
	local eggBanner = panel(gui, {
		Size = UDim2.fromOffset(460, 40),
		Position = UDim2.new(0.5, -230, 0, 76),
		BackgroundColor3 = Color3.fromRGB(40, 90, 140),
		Visible = false,
	})
	local eggLabel = label(eggBanner, { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) })

	-- Toasts (bottom-center)
	local toastHolder = Instance.new("Frame")
	toastHolder.BackgroundTransparency = 1
	toastHolder.Size = UDim2.fromOffset(460, 200)
	toastHolder.Position = UDim2.new(0.5, -230, 1, -260)
	toastHolder.Parent = overlay
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
	local announceLabel = label(overlay, {
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

	local notify = remotes:WaitForChild("Notify") :: RemoteEvent
	local announceRemote = remotes:WaitForChild("Announce") :: RemoteEvent
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

		local current = ClientState.current
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
			local owned: number = current.incubatorSlots or 1
			incubatorPanel.Size = UDim2.fromOffset(250, 40 + owned * 30)
			for i, row in incubatorRows do
				row.Visible = i <= owned
				local egg = nil
				for _, candidate in current.incubators do
					if candidate.slot == i then
						egg = candidate
					end
				end
				local tier = Config.Progression.incubatorTiers[(current.incubatorTiers or {})[i] or 1]
				if egg then
					local biome = Config.Biomes[egg.biome]
					local remaining = egg.hatchAt - now
					row.Text = if remaining > 0
						then `{i}. {biome.displayName} — {Format.duration(remaining)}`
						else `{i}. {biome.displayName} — hatching!`
					row.TextColor3 = Color3.new(1, 1, 1)
				else
					row.Text = `{i}. {tier.name} — empty`
					row.TextColor3 = Color3.fromRGB(160, 160, 160)
				end
			end

			local progression = current.progression
			if progression then
				levelLabel.Text =
					`Hatcher Lv {progression.level}  ·  {progression.xpInto}/{progression.xpNeeded} XP`
				xpFill.Size = UDim2.fromScale(math.clamp(progression.xpInto / progression.xpNeeded, 0, 1), 1)
			end
			local charge: number = current.luckCharge or 1
			spinsLabel.Text = `🎡 {current.spins or 0}`
				.. (if charge > 1 then `  ·  next egg ×{charge}` else "")
			if current.heldEgg then
				eggBanner.Visible = true
				eggLabel.Text =
					`Carrying a {Config.Biomes[current.heldEgg].displayName} egg — place it in an incubator (E)`
			else
				eggBanner.Visible = false
			end
		end

		local eventName = Workspace:GetAttribute("MoonEventName")
		local endsAt = Workspace:GetAttribute("MoonEventEndsAt")
		if typeof(eventName) == "string" and typeof(endsAt) == "number" then
			banner.Visible = true
			bannerLabel.Text = `🌕 {eventName} — {Format.duration(endsAt - now)}`
			local info = Workspace:GetAttribute("MoonEventInfo")
			bannerInfo.Text = if typeof(info) == "string" then info else ""
			local color = Workspace:GetAttribute("MoonEventColor")
			bannerStroke.Color = if typeof(color) == "Color3" then color else Color3.new(1, 1, 1)
			bannerLabel.TextColor3 = bannerStroke.Color
		else
			banner.Visible = false
		end
	end)
end

return HudController
