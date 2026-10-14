-- The planting preview's 3D ghosts (Planting.client): the plant models live in ServerStorage, which clients
-- can't read, so at start the server puts one light silhouette per zone x rarity into
-- ReplicatedStorage.PlantGhosts ("Ghost_<zone>_<rarity>"). A seed's flower is a surprise until it is
-- planted, so each ghost is the zone's first model of that rarity (pick 1), at its full-grown size (the
-- average variance), plain parts only: no lights, particles, labels, decals or textures, nothing that
-- collides or casts a shadow. The client tints it (green where the seed may go, red where not).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CreatureModels = require(script.Parent:WaitForChild("CreatureModels"))

local PlantGhosts = {}

PlantGhosts.FOLDER = "PlantGhosts"

function PlantGhosts.name(zone: number, rarity: number): string
	return `Ghost_{zone}_{rarity}`
end

-- How big a full-grown plant of (zone, rarity) is, in CreatureModels.applyScale units.
function PlantGhosts.fullScale(zone: number, rarity: number): number
	return CreatureModels.scaleFor(zone, rarity, Config.plantWeight(zone, rarity, Config.GROW_TIME, 1))
end

-- One ghost: the plant's parts and meshes only, pivoted on the soil at the origin.
function PlantGhosts.build(zone: number, rarity: number): Model
	local model = CreatureModels.build(zone, rarity, nil, 1)
	CreatureModels.applyScale(model, PlantGhosts.fullScale(zone, rarity))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Material = Enum.Material.SmoothPlastic
			d.Color = Color3.new(1, 1, 1)
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
		elseif not (d:IsA("Model") or d:IsA("SpecialMesh") or d:IsA("Attachment") or d:IsA("WeldConstraint") or d:IsA("Weld")
			or d:IsA("Motor6D") or d:IsA("Bone")) then
			d:Destroy()
		end
	end
	for _, d in model:GetDescendants() do -- (a SpecialMesh's texture would tint it)
		if d:IsA("SpecialMesh") then
			d.TextureId = ""
		end
	end
	model:SetAttribute("Zone", zone)
	model:SetAttribute("Rarity", rarity)
	model.Name = PlantGhosts.name(zone, rarity)
	return model
end

-- Builds every ghost into ReplicatedStorage.PlantGhosts (once, at start). Returns the folder.
function PlantGhosts.publish(parent: Instance?): Folder
	local into = parent or ReplicatedStorage
	local old = into:FindFirstChild(PlantGhosts.FOLDER)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = PlantGhosts.FOLDER
	for zone in Config.ZONES do
		for rarity in Config.RARITIES do
			local ok, ghost = pcall(PlantGhosts.build, zone, rarity)
			if ok then
				ghost.Parent = folder
			else
				warn("[PlantGhosts]", zone, rarity, ghost)
			end
		end
	end
	folder.Parent = into
	return folder
end

return PlantGhosts
