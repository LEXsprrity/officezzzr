-- The flowers' 3D pictures for the HUD (Index cells, Plants and Inventory cards, Sell cards; the client's
-- Shared/FlowerView puts them in ViewportFrames). The plant models live in ServerStorage, which clients
-- can't read, so at start the server copies every flower into ReplicatedStorage.FlowerPreviews as
-- <zone>/<rarity>/<model name> ("1/2/Daisy"; FALLBACK for a zone or rarity without plant models, the
-- built-in creature): its own colours and materials at build size, pivoted on the soil at the origin, and
-- plain looks only: no lights, particles, sounds, labels or scripts, nothing that collides, is queried,
-- touched or casts a shadow. Each carries ViewRadius / ViewHeight (CreatureModels.extents) so the client
-- fits its camera without measuring.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CreatureModels = require(script.Parent:WaitForChild("CreatureModels"))

local FlowerPreviews = {}

FlowerPreviews.FOLDER = "FlowerPreviews"
FlowerPreviews.FALLBACK = "Creature" -- (the client's FlowerView.FALLBACK)

-- What a preview may keep: the model, its parts and what shapes or paints them.
local KEEP = { "Model", "BasePart", "SpecialMesh", "BlockMesh", "CylinderMesh", "Decal", "SurfaceAppearance" }
local function keeps(d: Instance): boolean
	for _, class in KEEP do
		if d:IsA(class) then
			return true
		end
	end
	return false
end

-- One preview: flower `index` of (zone, rarity) (CreatureModels.build's pick), named `name`.
function FlowerPreviews.build(zone: number, rarity: number, index: number, name: string): Model
	local model = CreatureModels.build(zone, rarity, nil, index)
	for _, d in model:GetDescendants() do
		if not keeps(d) then
			d:Destroy()
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	local radius, height = CreatureModels.extents(model)
	model:SetAttribute("ViewRadius", radius)
	model:SetAttribute("ViewHeight", height)
	model:SetAttribute("Zone", zone)
	model:SetAttribute("Rarity", rarity)
	model.Name = name
	return model
end

-- Builds ReplicatedStorage.FlowerPreviews with every zone x rarity x flower (replacing an old one) and
-- parents it in one go. Returns the folder. A flower that can't be built is skipped (warned).
function FlowerPreviews.publish(parent: Instance?): Folder
	local into = parent or ReplicatedStorage
	local folder = Instance.new("Folder")
	folder.Name = FlowerPreviews.FOLDER
	for k in Config.ZONES do
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = tostring(k)
		zoneFolder.Parent = folder
		for r in Config.RARITIES do
			local rarityFolder = Instance.new("Folder")
			rarityFolder.Name = tostring(r)
			rarityFolder.Parent = zoneFolder
			local names = CreatureModels.variants(k, r)
			for i = 1, math.max(#names, 1) do
				local ok, model = pcall(FlowerPreviews.build, k, r, i, names[i] or FlowerPreviews.FALLBACK)
				if ok then
					model.Parent = rarityFolder
				else
					warn("[FlowerPreviews]", k, r, i, model)
				end
			end
		end
	end
	local old = into:FindFirstChild(FlowerPreviews.FOLDER)
	if old then
		old:Destroy()
	end
	folder.Parent = into
	return folder
end

return FlowerPreviews
