--!strict
-- Client bootstrap. The client is presentation only — the server never trusts
-- it for cash, hatching or steals.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CreatureAnimator = require(script.Controllers.CreatureAnimator)
local HudController = require(script.Controllers.HudController)
local PromptFilter = require(script.Controllers.PromptFilter)

HudController.start()
CreatureAnimator.start()
PromptFilter.start()

print(`[HatchAndSnatch] Client ready — {#Config.Creatures} creatures in config`)
