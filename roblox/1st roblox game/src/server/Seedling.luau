-- The seedling a fresh seed stands as while it sprouts (Config.sproutTime): a little stepped mound of dirt
-- with the seed itself sitting on it (owner 2026-10-22: the seed on the plot until the flower grows), the
-- same design its pod and the carried seed showed (assets/Seed_<ZoneId>, `design`: Plant.seedDesign). Without
-- the seed file: a sprout on the mound, two leaves and a bud in the seed's rarity colour (its mutation's, if
-- it has one). All in the map's studded plastic (Props.block). PlotService puts it where the plant stands and
-- swaps it for the flower when the sprouting ends. Like a plant model, its PrimaryPart ("Body", the mound)
-- holds an "InfoAnchor" attachment at the top for the hover info, and its pivot is on the ground.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Props = require(script.Parent:WaitForChild("Props"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local Seedling = {}

Seedling.DIRT = Color3.fromRGB(122, 82, 50)
Seedling.DIRT_TOP = Color3.fromRGB(146, 100, 62)
Seedling.STEM = Color3.fromRGB(70, 175, 60)
Seedling.LEAF = Color3.fromRGB(110, 215, 80)
Seedling.SIZE_PER_RARITY = 0.08 -- a rarer seed's seedling is a little bigger
Seedling.SEED_SIZE = 2.6 -- studs the seed is fitted into on the mound (a pod's is 3)

-- Which of zone `zone`'s seed designs a seed with this gene looks like (SeedService.designOf's pick).
function Seedling.designOf(zone: number, gene: number?): number
	return Config.geneDesign(gene, #Assets.variantNames(Assets.seedSlot(zone)))
end

function Seedling.build(zone: number, rarity: number, mutation: string?, design: number?): Model
	local model = Instance.new("Model")
	local s = 1 + Seedling.SIZE_PER_RARITY * (rarity - 1)
	local function block(name: string, size: Vector3, cf: CFrame, color: Color3): Part
		return Props.block(model, name, size * s, CFrame.new(cf.Position * s) * cf.Rotation, color)
	end
	-- The mound: a wide low step and a smaller one on top
	local body = block("Body", Vector3.new(2.6, 0.5, 2.6), CFrame.new(0, 0.25, 0), Seedling.DIRT)
	block("DirtTop", Vector3.new(1.6, 0.3, 1.6), CFrame.new(0.1, 0.65, -0.05), Seedling.DIRT_TOP)
	local anchorY = 2.4 * s -- (the InfoAnchor, in the mound's space: just over the bud or the seed)
	local slot = Assets.seedSlot(zone)
	local seed = Assets.get(slot) and Assets.place(slot, nil, CFrame.new(0, 0.8 * s, 0), Vector3.one * Seedling.SEED_SIZE * s, nil, design or 1)
	if seed then
		seed.Name = "SeedModel"
		seed:SetAttribute("Design", design or 1)
		for _, d in seed:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		anchorY = (0.8 + Seedling.SEED_SIZE - 0.25) * s -- (at most SEED_SIZE tall)
		seed.Parent = model
	else
		-- The sprout: a stem, two leaves tipped up, and the bud
		block("Stem", Vector3.new(0.3, 1.3, 0.3), CFrame.new(0, 1.45, 0), Seedling.STEM)
		block("LeafL", Vector3.new(0.9, 0.2, 0.5), CFrame.new(-0.5, 1.55, 0) * CFrame.Angles(0, 0, math.rad(-25)), Seedling.LEAF)
		block("LeafR", Vector3.new(0.9, 0.2, 0.5), CFrame.new(0.5, 1.85, 0) * CFrame.Angles(0, 0, math.rad(25)), Seedling.LEAF)
		local mut = Config.mutationById(mutation)
		local bud = (if mut then mut.color else Config.RARITIES[rarity].color) :: Color3
		block("Bud", Vector3.new(0.55, 0.55, 0.55), CFrame.new(0, 2.35, 0), bud)
	end
	model.PrimaryPart = body
	body.PivotOffset = CFrame.new(0, -0.25 * s, 0) -- the pivot on the ground, under the mound
	local anchor = Instance.new("Attachment")
	anchor.Name = "InfoAnchor"
	anchor.Position = Vector3.new(0, anchorY, 0)
	anchor.Parent = body
	model:SetAttribute("Zone", zone)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Mutation", mutation)
	return model
end

return Seedling
