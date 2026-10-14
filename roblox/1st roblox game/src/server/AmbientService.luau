-- Day/night lighting (the phase itself is derived from the clock in Config, so the client's timer
-- needs no remote). The base's only leaderboard is RewardService's "MOST MONEY/s" board.
--
-- Lighting blends between the bright, vivid DAY look and the clear blue NIGHT look in LightingLook by
-- Config.nightBlend, so night never collapses into grey and dusk/dawn fade instead of snapping.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(script.Parent:WaitForChild("Net"))
local LightingLook = require(script.Parent:WaitForChild("LightingLook"))

local AmbientService = {}

-- The place file ships these under Lighting (default.project.json); create any that are missing.
local function ensureEffects(): { [string]: Instance }
	local out = {}
	for className in LightingLook.EFFECTS do
		local inst = Lighting:FindFirstChildOfClass(className :: any)
		if not inst then
			inst = Instance.new(className :: any)
			inst.Parent = Lighting
		end
		out[className] = inst :: Instance
	end
	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.StarCount = 3000
		sky.MoonAngularSize = 14
		sky.Parent = Lighting
	end
	return out
end

function AmbientService.applyLighting(now: number, effects: { [string]: Instance })
	LightingLook.apply(Lighting, effects, now)
end

function AmbientService.start()
	local effects = ensureEffects()
	local wasNight: boolean? = nil
	task.spawn(function()
		while true do
			local t = workspace:GetServerTimeNow()
			local night = Config.dayPhase(t)
			AmbientService.applyLighting(t, effects)
			if wasNight ~= nil and night ~= wasNight then
				for _, player in Players:GetPlayers() do
					Net.LootEvent:FireClient(player, "DayNight", { night = night })
				end
			end
			wasNight = night
			task.wait(1)
		end
	end)
end

return AmbientService
