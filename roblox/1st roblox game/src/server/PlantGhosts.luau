-- The planting preview's 3D ghosts (Planting.client), and what a seed grows into. The plant models live in
-- ServerStorage, which clients can't read, so the server puts light silhouettes into
-- ReplicatedStorage.PlantGhosts: one per flower ("Ghost_<zone>_<rarity>_<n>", the n-th of the zone's plant
-- models of that rarity, CreatureModels.variants; 1 for the built-in creature), each at plant scale 1, plain
-- parts only: no lights, particles, labels, decals or textures, nothing that collides or casts a shadow.
-- They are built the first time a seed or plant needs one (ensure), so only the flowers in play replicate.
-- The client tints it (green where the seed may go, red where not) and scales it to the size the server
-- says.
-- A seed's gene (Config.rollGene) decides its flower and its weight variance, so the ghost shows exactly
-- the plant it grows into, at the size it has right when planted (seedLook), while every label still says
-- only "Common Seed" (owner: the silhouette may show, the name is revealed when it is planted).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SeedPacks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SeedPacks"))
local Palettes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palettes"))
local CreatureModels = require(script.Parent:WaitForChild("CreatureModels"))

local PlantGhosts = {}

PlantGhosts.FOLDER = "PlantGhosts"

function PlantGhosts.name(zone: number, rarity: number, index: number): string
	return `Ghost_{zone}_{rarity}_{index}`
end

-- How many flowers a seed of (zone, rarity) may grow into (1: the built-in creature).
function PlantGhosts.count(zone: number, rarity: number): number
	return math.max(#CreatureModels.variants(zone, rarity), 1)
end

-- Which of them a seed of this mutation with this gene grows into (its ghost's n): CreatureModels.seedVariant
-- (a Haunted seed: one of the Haunted set's).
function PlantGhosts.indexOf(zone: number, rarity: number, gene: number, mutation: string?): number
	local flower = CreatureModels.seedVariant(zone, rarity, mutation, gene)
	local index = if flower then table.find(CreatureModels.variants(zone, rarity), flower) else nil
	return index or (math.floor(gene) - 1) % PlantGhosts.count(zone, rarity) + 1
end

-- How big a plant of (zone, rarity) with this weight variance is right when it is planted (its sprout
-- weight), in CreatureModels.applyScale units.
function PlantGhosts.sproutScale(zone: number, rarity: number, variance: number): number
	return CreatureModels.scaleFor(zone, rarity, Config.plantWeight(zone, rarity, 0, variance))
end

-- What the planting preview shows for a seed of this mutation with this gene: (ghost n, scale).
function PlantGhosts.seedLook(zone: number, rarity: number, gene: number, mutation: string?): (number, number)
	return PlantGhosts.indexOf(zone, rarity, gene, mutation), PlantGhosts.sproutScale(zone, rarity, Config.geneVariance(gene))
end

-- ...and for a plant (an inventory plant planted again): its own flower at its own size at `now`.
function PlantGhosts.plantLook(plant: any, now: number): (number, number)
	local flower = CreatureModels.flowerOf(plant.zone, plant.rarity, plant.variant, plant.slot)
	local index = if flower then table.find(CreatureModels.variants(plant.zone, plant.rarity), flower) else nil
	local weight = Config.plantWeight(plant.zone, plant.rarity, now - plant.plantedAt, Config.varianceOf(plant))
	return index or 1, CreatureModels.scaleFor(plant.zone, plant.rarity, weight)
end

-- The planting preview for the seed under `key` in `bag` (untrusted key): (the key it is under now, zone,
-- rarity, mutation, ghost n, scale), or nil when there is no such seed. A seed from before genes gets one
-- here (moved to its new key), so what the ghost shows is what it grows into.
function PlantGhosts.bagPreview(bag: { [string]: number }, key: any, roll: () -> number): (string?, number?, number?, string?, number?, number?)
	local zone, rarity, mutation, gene = SeedPacks.parseBagKey(key)
	if not zone or not rarity or (bag[key] or 0) <= 0 then
		return nil, nil, nil, nil, nil, nil
	end
	if not gene then
		gene = Config.rollGene(roll)
		SeedPacks.takeFromBag(bag, key)
		key = SeedPacks.addToBag(bag, zone, rarity, mutation, gene)
	end
	local ghost, scale = PlantGhosts.seedLook(zone, rarity, gene :: number, mutation)
	return key, zone, rarity, mutation, ghost, scale
end

-- The plant a seed grows into, planted at (x, z) under id `slot` at `now`: with a gene, the flower, palette
-- (Shared/Palettes) and variance it decides (what its ghost showed); without one (a seed from before genes) a
-- flower drawn now with `roll`, Natural, and the variance from its planting time and id.
function PlantGhosts.seedPlant(zone: number, rarity: number, mutation: string?, gene: number?, slot: number, now: number,
	x: number, z: number, roll: () -> number): any
	return {
		slot = slot, zone = zone, rarity = rarity, mutation = mutation, plantedAt = now, x = x, z = z,
		variant = if gene then CreatureModels.seedVariant(zone, rarity, mutation, gene) else CreatureModels.randomVariant(zone, rarity, roll, mutation),
		variance = if gene then Config.geneVariance(gene) else nil,
		palette = Palettes.ofSeed(gene, mutation), -- its colours (nil: Natural; always for a seed from before genes)
	}
end

-- One ghost: the flower's parts and meshes only, at plant scale 1, pivoted on the soil at the origin.
function PlantGhosts.build(zone: number, rarity: number, index: number): Model
	local model = CreatureModels.build(zone, rarity, nil, index)
	CreatureModels.applyScale(model, 1)
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
	model.Name = PlantGhosts.name(zone, rarity, index)
	return model
end

local folder: Folder? = nil

-- Puts an empty ReplicatedStorage.PlantGhosts in place (once, at start). Returns the folder.
function PlantGhosts.publish(parent: Instance?): Folder
	local into = parent or ReplicatedStorage
	local old = into:FindFirstChild(PlantGhosts.FOLDER)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = PlantGhosts.FOLDER
	f.Parent = into
	folder = f
	return f
end

-- The ghost of flower `index` of (zone, rarity), built into the folder the first time it is needed (before
-- the server tells a client about the seed, so it replicates first). nil if it can't be built (warned).
function PlantGhosts.ensure(zone: number, rarity: number, index: number): Model?
	local f = if folder and folder.Parent then folder else PlantGhosts.publish()
	local name = PlantGhosts.name(zone, rarity, index)
	local have = f:FindFirstChild(name)
	if have then
		return have :: Model
	end
	local ok, ghost = pcall(PlantGhosts.build, zone, rarity, index)
	if not ok then
		warn("[PlantGhosts]", zone, rarity, index, ghost)
		return nil
	end
	ghost.Parent = f
	return ghost
end

return PlantGhosts
