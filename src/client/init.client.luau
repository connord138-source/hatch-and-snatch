--!strict
-- Client bootstrap. The client is presentation only — the server never trusts
-- it for cash, hatching or steals.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ads = require(script.Ads)
local BeltController = require(script.Controllers.BeltController)
local ClientState = require(script.ClientState)
local CreatureAnimator = require(script.Controllers.CreatureAnimator)
local DayNightController = require(script.Controllers.DayNightController)
local GuideController = require(script.Controllers.GuideController)
local HudController = require(script.Controllers.HudController)
local IncubatorController = require(script.Controllers.IncubatorController)
local LuckWheelController = require(script.Controllers.LuckWheelController)
local MenuController = require(script.Controllers.MenuController)
local OddsController = require(script.Controllers.OddsController)
local PromptFilter = require(script.Controllers.PromptFilter)
local RainbowController = require(script.Controllers.RainbowController)
local CastleFxController = require(script.Controllers.CastleFxController)
local RevealController = require(script.Controllers.RevealController)
local TeleportController = require(script.Controllers.TeleportController)
local ZoneGateController = require(script.Controllers.ZoneGateController)
local ZoneMoodController = require(script.Controllers.ZoneMoodController)

ClientState.start()
HudController.start()
MenuController.start()
CreatureAnimator.start()
PromptFilter.start()
RainbowController.start()
CastleFxController.start()
DayNightController.start()
IncubatorController.start()
task.spawn(LuckWheelController.start) -- waits for the world to replicate
RevealController.start()
task.spawn(TeleportController.start) -- waits for the remotes
OddsController.start() -- the egg odds panel (paid random items: odds before buying)
task.spawn(ZoneGateController.start) -- waits for the world to replicate
task.spawn(ZoneMoodController.start) -- waits for the world to replicate
task.spawn(GuideController.start) -- waits for the world to replicate
task.spawn(BeltController.start) -- waits for the belt folder
task.spawn(Ads.start) -- checks every minute whether a rewarded ad can play

print(`[HatchAndSnatch] Client ready — {#Config.Creatures} creatures in config`)
