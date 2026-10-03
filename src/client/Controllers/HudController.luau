--!strict
-- Placeholder HUD built from code: cash + rate, uncollected, Hatcher Level + XP,
-- Luck Wheel spins, incubator timers, Server Luck, ad boost, carried-egg hint, moon event banner, toasts
-- and server announcements. Presentation only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Ads = require(script.Parent.Parent.Ads)
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

local TOAST_SECONDS = 4

local ESSENCE_ORDER = { "Mossvale", "CoralCoast", "MagmaRift", "FrostShelf", "StormPeaks", "Moonfall" }

local HudController = {}

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")
	Ui.autoScale(gui)

	-- Toasts and announcements go on their own layer so they show over open menus
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "HatchOverlay"
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = 10
	overlay.Parent = gui.Parent
	Ui.autoScale(overlay)

	-- Cash panel (top-left)
	local cashPanel = panel(gui, { Size = UDim2.fromOffset(250, 152), Position = UDim2.fromOffset(12, 12) })
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
	-- Biome Essence from harvest nodes and releases (only the kinds you have)
	local essenceLabel = label(cashPanel, {
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.fromOffset(10, 128),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(215, 185, 255),
		Text = "✨ no Essence yet — harvest in the biome zones",
	})

	-- Incubators (left, under the lock status; the top-right belongs to Roblox's player list)
	local maxIncubators = #Config.Progression.incubatorSlotCosts
	local incubatorPanel = panel(gui, {
		Size = UDim2.fromOffset(250, 70),
		Position = UDim2.fromOffset(12, 214),
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

	-- Server Luck (under the incubators while a Server Luck purchase is running)
	local luckPanel = panel(gui, {
		Size = UDim2.fromOffset(250, 30),
		Position = UDim2.fromOffset(12, 284),
		Visible = false,
	})
	local luckLabel = label(luckPanel, {
		Size = UDim2.new(1, -20, 1, -8),
		Position = UDim2.fromOffset(10, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(140, 255, 160),
	})

	-- Rewarded ad (under Server Luck): a Watch button while Roblox has an ad to show,
	-- and the ×2 cash timer while the boost runs
	local adTuning = Config.Monetization.tuning.adBoost
	local adButton = Ui.button(gui, {
		Size = UDim2.fromOffset(250, 34),
		Position = UDim2.fromOffset(12, 284),
		BackgroundColor3 = Ui.colors.good,
		Visible = false,
	})
	adButton.Activated:Connect(Ads.watch)
	local columnBottom = 284 -- where the left column continues below the incubators

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
	local lockPanel = panel(gui, { Size = UDim2.fromOffset(250, 34), Position = UDim2.fromOffset(12, 172) })
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

	-- One toast per message: the same one again (E pressed over and over on a
	-- locked egg stacked copies, playtest 2026-10-03) pulses the toast already up
	-- and keeps it there longer
	local toasts: { [string]: { frame: Frame, expires: number } } = {}
	local function toast(text: string, kind: string)
		local key = `{kind}|{text}`
		local shown = toasts[key]
		if shown then
			shown.expires = os.clock() + TOAST_SECONDS
			shown.frame.BackgroundTransparency = 0
			TweenService:Create(shown.frame, TweenInfo.new(0.3), { BackgroundTransparency = 0.25 }):Play()
			return
		end
		local toastFrame = panel(toastHolder, {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = TOAST_COLORS[kind] or TOAST_COLORS.info,
		})
		label(
			toastFrame,
			{ Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), Text = Ui.hint(text) }
		)
		local entry = { frame = toastFrame, expires = os.clock() + TOAST_SECONDS }
		toasts[key] = entry
		task.spawn(function()
			while os.clock() < entry.expires do
				task.wait(entry.expires - os.clock())
			end
			toasts[key] = nil
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
			columnBottom = 214 + 40 + owned * 30 + 8
			luckPanel.Position = UDim2.fromOffset(12, columnBottom)
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
			local essenceParts: { string } = {}
			local essence: { [string]: number } = current.essence or {}
			for _, biomeId in ESSENCE_ORDER do
				if (essence[biomeId] or 0) > 0 then
					table.insert(
						essenceParts,
						`{Config.Zones.byBiome[biomeId].essence:match("^%S+")} {essence[biomeId]}`
					)
				end
			end
			if #essenceParts > 0 then
				essenceLabel.Text = `✨ {table.concat(essenceParts, " · ")}`
			end
			if current.heldEgg then
				eggBanner.Visible = true
				eggLabel.Text = Ui.hint(
					`Carrying a {Config.Biomes[current.heldEgg].displayName} egg — place it in an incubator (E)`
				)
			else
				eggBanner.Visible = false
			end
		end

		local serverLuck = Workspace:GetAttribute("ServerLuck")
		local serverLuckUntil = Workspace:GetAttribute("ServerLuckUntil")
		if
			typeof(serverLuck) == "number"
			and serverLuck > 1
			and typeof(serverLuckUntil) == "number"
			and serverLuckUntil > now
		then
			luckPanel.Visible = true
			luckLabel.Text = `🍀 Server Luck ×{serverLuck} — {Format.duration(serverLuckUntil - now)}`
		else
			luckPanel.Visible = false
		end

		local boostEnds: number = if current and current.boosts then current.boosts.cash or 0 else 0
		local boosted = boostEnds > os.time()
		adButton.Visible = Ads.available or boosted
		adButton.Position = UDim2.fromOffset(12, columnBottom + (if luckPanel.Visible then 38 else 0))
		adButton.AutoButtonColor = Ads.available
		adButton.BackgroundColor3 = if Ads.available then Ui.colors.good else Ui.colors.disabled
		adButton.Text = if boosted and Ads.available
			then `📺 ×{adTuning.multiplier} cash {Format.duration(boostEnds - os.time())} · watch for +{adTuning.minutes} min`
			elseif boosted then `📺 ×{adTuning.multiplier} cash: {Format.duration(
				boostEnds - os.time()
			)} left`
			else `📺 Watch an ad: ×{adTuning.multiplier} cash for {adTuning.minutes} min`

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
