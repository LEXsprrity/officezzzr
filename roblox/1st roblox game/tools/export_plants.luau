-- Exports the owner's flower pack (models/plants/FlowersByLoxxsy.rbxm: Folder FlowersByLoxxsy > "Titanic"
-- (the big ones) + "Normal") into the game's plant-creatures: assets/Creature_<Seed>.rbxm for each zone, a
-- Folder with one sub-folder per rarity (Common ... Legendary) holding that zone's plant models for it.
-- CreatureModels.build picks one per plant (by its id), so a zone's plants of one rarity mix their looks.
--
-- Each model is copied as is (meshes, colours, materials, particles, beams, lights), with nothing that runs
-- or collides: scripts and welds dropped, every part anchored, CanCollide/CanTouch/CanQuery off. It is
-- scaled so it fits its rarity's footprint (Config.creatureFootprint: its reach from its centre line is at
-- most half of it) and height (Config.creatureHeight), with its bottom centre at the origin, and marked
-- KeepScale (already to size). Particles, beams and lights are scaled with it. Attributes: Source (the
-- pack's folder/model), SourceHeight (its height in the pack, studs) and Sword (the katana-shaped ones).
--
-- Rules (the owner's): small plants (most of "Normal", 3-12 studs) are Common/Uncommon/Rare; the big ones
-- (20+ studs: all of "Titanic" and the big ones in "Normal") are Legendary; the meme/VFX mid-size ones are
-- Epic; the swords are Legendary and only in the last zone (Spirit Garden). tests/plants.spec checks them.
-- Change the table below and run again from the game folder:
--   lune run tools/export_plants.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("../tests/harness")
local PlantGround = require("./plant_ground")

local Config = H.shared("Config")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local NumberSequence, NumberSequenceKeypoint, NumberRange = roblox.NumberSequence, roblox.NumberSequenceKeypoint, roblox.NumberRange

local SOURCE = "models/plants/FlowersByLoxxsy.rbxm"

-- The sword-shaped plants (katanas): Cryonix (ice) and Pyronis (fire, the same katana shape and size).
local SWORDS = { Cryonix = true, Pyronis = true }

-- Zone id -> rarity -> pack models (owner 2026-10-20): ranked by size and how strong their effects are, the big
-- ones (20+ studs in the pack) and the strongest effects Epic or Legendary, the plain ones Common to Rare, at least
-- two of every rarity in every zone; from the Snow Peaks on, at most 2 Commons, 2 Uncommons and 3 Rares, the rest
-- Epic or Legendary (owner 2026-10-20). The rarity odds and pay don't change.
-- Lighter models (fewer parts) for the common rarities: a plot holds up to 40 plants.
local PLANTS = {
	Meadow = {
		Common = { "Cornflower", "Tulip", "Iris", "Daisy", "Pansy" },
		Uncommon = { "Dandelion", "Lily", "Pinkbells", "Thistle" },
		Rare = { "Hellebore", "Rose", "Orchid", "Sunflower" },
		Epic = { "Ballerina", "Mafioso" },
		Legendary = { "Verdantis", "Rosaris", "Sunfloris" },
	},
	Desert = {
		Common = { "Nuzwat", "Succulent", "Cactus" },
		Uncommon = { "RadianceLily", "KittyTowerFlower", "ZebraFlower" },
		Rare = { "Sunpetal", "HaloOrchid", "DesertWildFlower" },
		Epic = { "MantisReaper", "SolarIris", "Sahur" },
		Legendary = { "Helios", "Aetheris" },
	},
	Jungle = {
		Common = { "ShimmeringLichen", "Beenspector", "ZombeeFlower" },
		Uncommon = { "OceanBloom", "BugEater", "UnicornPetunia" },
		Rare = { "Snapdragon", "MeanFlower", "SpiderLilly" },
		Epic = { "GlowBerry", "Bombardiro", "Patapim" },
		Legendary = { "Paradoxys", "Venomyx" },
	},
	Lava = {
		Common = { "EmberSpark", "Pomeflower" },
		Uncommon = { "DarkflareRose", "DragonFlower" },
		Rare = { "CrimsonWidow", "RedStar" },
		Epic = { "Draconyx", "StrawberryElephant", "FrostburnRose" },
		Legendary = { "Infernyx", "Coreflare" },
	},
	Snow = {
		Common = { "IcecapBloom", "Snowdrop" },
		Uncommon = { "FrostLily", "WinterRose" },
		Rare = { "HollyBloom", "PolarSpire", "Glacierheart" },
		Epic = { "Santa", "Reindeer", "CrystalDaisy", "Elf", "Gingerbread", "PoinsettiaBlossom", "Trallalero", "Snowpuff", "CrystalizedPetal", "Mistletoe" },
		Legendary = { "Aracnid", "Lunaris", "Frostwyrm" },
	},
	Space = {
		Common = { "Lobelia", "EclipseBloom" },
		Uncommon = { "NebulaRose", "BorealBell" },
		Rare = { "Voidbloom", "CyberFlower", "MeteorFlower" },
		Epic = { "TwilightAmarilis", "StarfallFlower", "Gleamblossom", "LaVaca", "SixSeven", "Starpetal" },
		Legendary = { "Stellaris", "Cybaris", "Jellythys" },
	},
	Spirit = {
		Common = { "Camellia", "MoonlaceOrchid" },
		Uncommon = { "Lightbloom", "Whitenight" },
		Rare = { "Crystalflower", "Bamboo", "IvoryIris" },
		Epic = { "BubbleLotus", "Assassino", "DualityFlower", "DualityRose", "Ghostflower", "Ghostleaf" },
		Legendary = { "Cryonix", "Pyronis", "Noctyra", "Velkrya" },
	},
}

-- How far a part reaches along unit vector u (like CreatureModels.extents: a part's box, every part).
local function reach(p: any, u: any): number
	local cf, half = p.CFrame, p.Size / 2
	return cf.Position:Dot(u) + math.abs(half.X * cf.RightVector:Dot(u)) + math.abs(half.Y * cf.UpVector:Dot(u))
		+ math.abs(half.Z * cf.LookVector:Dot(u))
end

local DIRS = {}
for i = 0, 31 do
	local a = i * math.pi / 16
	DIRS[i + 1] = Vector3.new(math.cos(a), 0, math.sin(a))
end

-- (bottom centre of the visible parts' box, reach from its vertical axis, height above its bottom)
local function measure(parts: { any }): (any, number, number)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in parts do
		if p.Transparency < 1 then
			lo = lo:Min(Vector3.new(-reach(p, -Vector3.xAxis), -reach(p, -Vector3.yAxis), -reach(p, -Vector3.zAxis)))
			hi = hi:Max(Vector3.new(reach(p, Vector3.xAxis), reach(p, Vector3.yAxis), reach(p, Vector3.zAxis)))
		end
	end
	local origin = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	local radius, top = 0, 0
	for _, p in parts do
		top = math.max(top, reach(p, Vector3.yAxis))
		for _, u in DIRS do
			radius = math.max(radius, reach(p, u) - origin:Dot(u))
		end
	end
	return origin, radius, top - origin.Y
end

local function scaleSequence(seq: any, s: number): any
	local points = {}
	for _, k in seq.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(k.Time, k.Value * s, k.Envelope * s))
	end
	return NumberSequence.new(points)
end

local function export(source: any, zone: number, rarity: number): (any, string)
	local model = source:Clone()
	for _, d in model:GetDescendants() do
		if d.Parent ~= nil and (d:IsA("LuaSourceContainer") or d:IsA("JointInstance") or d:IsA("WeldConstraint")
			or d:IsA("ClickDetector") or d:IsA("ProximityPrompt") or d:IsA("TouchTransmitter")) then
			d:Destroy()
		end
	end
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	assert(#parts > 0, `{source.Name} has no parts`)
	local origin, radius, height = measure(parts)
	local footprint, maxHeight = Config.creatureFootprint(rarity), Config.creatureHeight(zone, rarity)
	local s = math.min(maxHeight / height, (footprint / 2 - 0.01) / radius)

	-- Scale about the bottom centre and move it to the origin, keeping every rotation.
	for _, p in parts do
		p.Size *= s
		p.CFrame = CFrame.new((p.CFrame.Position - origin) * s) * p.CFrame.Rotation
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") then
			d.CFrame = CFrame.new(d.CFrame.Position * s) * d.CFrame.Rotation
		elseif d:IsA("Beam") then
			d.Width0 *= s
			d.Width1 *= s
			d.CurveSize0 *= s
			d.CurveSize1 *= s
		elseif d:IsA("ParticleEmitter") then
			d.Size = scaleSequence(d.Size, s)
			d.Speed = NumberRange.new(d.Speed.Min * s, d.Speed.Max * s)
			d.Acceleration *= s
		elseif d:IsA("Light") then
			d.Range = math.max(d.Range * s, 4)
		end
	end
	if not model.PrimaryPart then
		model.PrimaryPart = parts[1]
	end
	model:SetAttribute("KeepScale", true)
	model:SetAttribute("Source", `{source.Parent.Name}/{source.Name}`)
	model:SetAttribute("SourceHeight", math.floor(height * 10 + 0.5) / 10)
	if SWORDS[source.Name] then
		model:SetAttribute("Sword", true)
	end
	PlantGround.apply(model) -- stand on its base disc, not on a leaf poking below it
	return model, string.format("%-18s %3d parts  %5.1f -> %4.1f tall, reach %.2f (scale %.3f)", source.Name, #parts, height, height * s, radius * s, s)
end

local roots = roblox.deserializeModel(fs.readFile(SOURCE))
assert(#roots == 1 and roots[1].Name == "FlowersByLoxxsy", `{SOURCE}: expected one FlowersByLoxxsy folder`)
-- By name; "Normal" first (HollyBloom is in both folders)
local byName = {}
for _, folderName in { "Normal", "Titanic" } do
	local folder = roots[1]:FindFirstChild(folderName)
	assert(folder, `{SOURCE} has no {folderName} folder`)
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and not byName[m.Name] then
			byName[m.Name] = m
		end
	end
end

local used = {}
for zone, z in Config.ZONES do
	local plants = PLANTS[z.id]
	assert(plants, `no plants for zone {z.id}`)
	local slot = "Creature_" .. string.gsub(z.seed, "%s", "")
	local out = roblox.Instance.new("Folder")
	out.Name = slot
	print(`== {slot} ({z.name})`)
	for rarity, r in Config.RARITIES do
		local names = plants[r.id]
		assert(names and #names > 0, `{z.id} has no {r.id} plants`)
		local group = roblox.Instance.new("Folder")
		group.Name = r.id
		group.Parent = out
		for _, name in names do
			local source = byName[name]
			assert(source, `{SOURCE} has no model {name}`)
			assert(not used[name], `{name} is used twice ({used[name]} and {z.id} {r.id})`)
			used[name] = `{z.id} {r.id}`
			local model, line = export(source, zone, rarity)
			model.Parent = group
			print(`  {r.id:sub(1, 4)}  {line}`)
		end
	end
	fs.writeFile(`assets/{slot}.rbxm`, roblox.serializeModel({ out }))
end
local unused = {}
for name in byName do
	if not used[name] then
		table.insert(unused, name)
	end
end
table.sort(unused)
print("not used: " .. table.concat(unused, ", "))
