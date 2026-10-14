-- Day/night lighting (the phase itself is derived from the clock in Config, so the client's timer
-- needs no remote). The base's only leaderboard is RewardService's "MOST MONEY/s" board.
--
-- Each phase has one fixed look (LightingLook: the sun still all day, the moon still all night). It
-- switches at the flip, which Client/DayNight hides behind a short fade to black; clients switch their own
-- (local) Lighting at the same server time, so this write only keeps late joiners and the server in step.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LightingLook = require(Shared:WaitForChild("LightingLook"))
local Net = require(script.Parent:WaitForChild("Net"))

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

function AmbientService.applyLighting(night: boolean, effects: { [string]: Instance })
	LightingLook.applyPhase(Lighting, effects, night)
end

function AmbientService.start()
	local effects = ensureEffects()
	local wasNight: boolean? = nil
	task.spawn(function()
		while true do
			local night, left = Config.dayPhase(workspace:GetServerTimeNow())
			if night ~= wasNight then -- only on a flip: the look never changes inside a phase
				AmbientService.applyLighting(night, effects)
				if wasNight ~= nil then
					for _, player in Players:GetPlayers() do
						Net.LootEvent:FireClient(player, "DayNight", { night = night })
					end
				end
				wasNight = night
			end
			task.wait(math.clamp(left + 0.05, 0.1, 1)) -- wake right after the next flip
		end
	end)
end

return AmbientService
