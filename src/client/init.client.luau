--!strict
-- Client bootstrap. The client is presentation only — the server never trusts
-- it for cash, hatching or steals.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ClientState = require(script.ClientState)
local CreatureAnimator = require(script.Controllers.CreatureAnimator)
local HudController = require(script.Controllers.HudController)
local IncubatorController = require(script.Controllers.IncubatorController)
local MenuController = require(script.Controllers.MenuController)
local PromptFilter = require(script.Controllers.PromptFilter)
local RevealController = require(script.Controllers.RevealController)

ClientState.start()
HudController.start()
MenuController.start()
CreatureAnimator.start()
PromptFilter.start()
IncubatorController.start()
RevealController.start()

print(`[HatchAndSnatch] Client ready — {#Config.Creatures} creatures in config`)
