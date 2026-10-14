-- Colours the "👟 700M recommended" plank by each nest for this player: GREEN once their Speed reaches the
-- zone's recommended Speed, RED below it (Config.speedPlankColor). The planks are the parts WorldBuilder
-- tags Role = "SpeedPlank" with their ZoneIndex; the Speed comes from StatsUpdate (partial tables; the
-- server pushes it with every income tick). Display only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local StatsUpdate = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StatsUpdate") :: RemoteEvent

local speed = 0
local planks: { [Instance]: number } = {} -- plank -> its zone

local function paint(plank: Instance, k: number)
	local color = Config.speedPlankColor(speed, k)
	for _, d in plank:GetDescendants() do
		if d:IsA("TextLabel") then
			d.TextColor3 = color
		end
	end
end

local function consider(inst: Instance)
	if typeof(inst) ~= "Instance" or inst:GetAttribute("Role") ~= "SpeedPlank" then
		return
	end
	local k = inst:GetAttribute("ZoneIndex")
	if type(k) == "number" and Config.ZONES[k] then
		planks[inst] = k
		paint(inst, k)
		inst.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				planks[inst] = nil
			end
		end)
	end
end

StatsUpdate.OnClientEvent:Connect(function(partial: { [string]: any })
	if type(partial) ~= "table" or type(partial.speed) ~= "number" or partial.speed == speed then
		return
	end
	speed = partial.speed
	for plank, k in planks do
		paint(plank, k)
	end
end)

local all = workspace:GetDescendants()
for i = 1, #all do
	consider(all[i])
end
workspace.DescendantAdded:Connect(consider) -- a map the server regenerates
