--!strict
-- Client bootstrap. The client is presentation only — the server never trusts
-- it for cash, hatching or steals.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ads = require(script.Ads)
local ClientState = require(script.ClientState)
local CreatureAnimator = require(script.Controllers.CreatureAnimator)
local HudController = require(script.Controllers.HudController)
local IncubatorController = require(script.Controllers.IncubatorController)
local LuckWheelController = require(script.Controllers.LuckWheelController)
local MenuController = require(script.Controllers.MenuController)
local PromptFilter = require(script.Controllers.PromptFilter)
local RevealController = require(script.Controllers.RevealController)
local ZoneGateController = require(script.Controllers.ZoneGateController)
local ZoneMoodController = require(script.Controllers.ZoneMoodController)

ClientState.start()
HudController.start()
MenuController.start()
CreatureAnimator.start()
PromptFilter.start()
IncubatorController.start()
task.spawn(LuckWheelController.start) -- waits for the world to replicate
RevealController.start()
task.spawn(ZoneGateController.start) -- waits for the world to replicate
task.spawn(ZoneMoodController.start) -- waits for the world to replicate
task.spawn(Ads.start) -- checks every minute whether a rewarded ad can play

print(`[HatchAndSnatch] Client ready — {#Config.Creatures} creatures in config`)
