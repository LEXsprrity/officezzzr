-- The "👟 2M recommended" plank by each nest, for this player: its text comes from Config.ZONES[ZoneIndex].req
-- (Format.speedPlank), so a map built or hand-edited with older numbers still reads right, and its colour
-- is GREEN once their Speed reaches that recommended Speed, RED below it (Config.speedPlankColor). The planks
-- are the parts WorldBuilder tags Role = "SpeedPlank" with their ZoneIndex, with a "Speed" and a
-- "Recommended" TextLabel; the Speed comes from StatsUpdate (partial tables; the server pushes it with every
-- income tick). Display only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local StatsUpdate = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StatsUpdate") :: RemoteEvent

local speed = 0
local planks: { [Instance]: number } = {} -- plank -> its zone

local function paint(plank: Instance, k: number)
	local color = Config.speedPlankColor(speed, k)
	local top, bottom = Format.speedPlank(Config.ZONES[k].req)
	for _, d in plank:GetDescendants() do
		if d:IsA("TextLabel") then
			d.TextColor3 = color
			if d.Name == "Speed" then
				d.Text = top
			elseif d.Name == "Recommended" then
				d.Text = bottom
			end
		end
	end
end

-- The plank a label (or the plank itself) belongs to, with its zone.
local function plankOf(inst: Instance): (Instance?, number?)
	local node: Instance? = inst
	while node and node ~= workspace do
		if node:GetAttribute("Role") == "SpeedPlank" then
			local k = node:GetAttribute("ZoneIndex")
			return node, if type(k) == "number" and Config.ZONES[k] then k else nil
		end
		node = node.Parent
	end
	return nil, nil
end

local function consider(inst: Instance)
	if typeof(inst) ~= "Instance" then
		return
	end
	if inst:IsA("TextLabel") then -- a label that arrives after its plank
		local plank, k = plankOf(inst)
		if plank and k and planks[plank] then
			paint(plank, k)
		end
		return
	end
	if inst:GetAttribute("Role") ~= "SpeedPlank" then
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
