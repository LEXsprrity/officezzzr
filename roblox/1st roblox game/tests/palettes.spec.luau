-- Colour variants (Shared/Palettes): a seed's gene picks a palette as well as its flower; the plant keeps it.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Config = H.shared("Config")
local Palettes = H.shared("Palettes")
local Halloween = H.shared("Halloween")
local CreatureModels = H.server("CreatureModels")
local PlantGhosts = H.server("PlantGhosts")
local FlowerPreviews = H.server("FlowerPreviews")
local ProfileStore = H.server("ProfileStore")
local Inventory = H.server("Inventory")
local Selling = H.server("Selling")
H.stubServer("Net", { StatsUpdate = { FireClient = function() end }, LootEvent = { FireClient = function() end }, toast = function() end })
local PlotService = H.server("PlotService")

local SPIRIT, EPIC = #Config.ZONES, 4
local NOW = 1.8e9

local function rawModel(k: number, r: number, name: string): any
	local file = H.assets:FindFirstChild("Creature_" .. string.gsub(Config.ZONES[k].seed, "%s", ""))
	local folder = file and file:FindFirstChild(Config.RARITIES[r].id)
	return folder and folder:FindFirstChild(name)
end

-- Every plant model: { zone, rarity, name }.
local function allModels(): { { any } }
	local out = {}
	for k in Config.ZONES do
		for r in Config.RARITIES do
			for _, name in CreatureModels.variants(k, r) do
				table.insert(out, { k, r, name })
			end
		end
	end
	return out
end

local function partsOf(model: any): { any }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- The plant's own parts' colours (not our halo or pumpkin), sorted.
local function ownColors(model: any): string
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d:GetAttribute(Halloween.FLAIR) then
			table.insert(out, d.Color:ToHex())
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function area(p: any): number
	local s = p.Size
	return if p.Transparency >= 0.95 then 0 else s.X * s.Y + s.Y * s.Z + s.X * s.Z
end

local function hueGap(a: number, b: number): number
	local d = math.abs(a - b) % 1
	return math.min(d, 1 - d)
end

local function pickOf(k: number, r: number, name: string): number
	return table.find(CreatureModels.variants(k, r), name) :: number
end

-- A gene whose seed (zone, rarity, mutation) grows into `flower` in `palette` (nil: Natural).
local function geneFor(k: number, r: number, flower: string, palette: string?, mutation: string?): number
	for gene = 1, Config.SEED_GENES do
		if CreatureModels.seedVariant(k, r, mutation, gene) == flower and Palettes.ofSeed(gene, mutation) == palette then
			return gene
		end
	end
	error(`no gene for {flower} {palette}`)
end

H.test("palettes: Natural and four palettes, Natural the most common (44%), the rest 14% each, from the gene", function()
	H.ok(#Palettes.LIST >= 2 and #Palettes.LIST <= 4, "3 to 5 looks with Natural")
	local sum = Palettes.NATURAL_WEIGHT
	for _, p in Palettes.LIST do
		sum += p.weight
		H.ok(Config.mutationById(p.id) == nil, `{p.id}: not a mutation's name`)
		H.ok(Palettes.byId(p.id) == p)
	end
	H.eq(sum, 100)
	H.ok(Palettes.NATURAL_WEIGHT >= 40 and Palettes.NATURAL_WEIGHT <= 50, "40-50% Natural")
	local counts: { [string]: number } = {}
	for gene = 1, Config.SEED_GENES do
		local id = Palettes.of(gene) or Palettes.NATURAL
		counts[id] = (counts[id] or 0) + 1
		H.eq(Palettes.of(gene), id ~= Palettes.NATURAL and id or nil, "the same gene, the same palette")
	end
	H.near(counts[Palettes.NATURAL] / Config.SEED_GENES, Palettes.NATURAL_WEIGHT / 100, 0.005, "Natural")
	for _, p in Palettes.LIST do
		H.near(counts[p.id] / Config.SEED_GENES, p.weight / 100, 0.005, p.id)
	end
	H.eq(Palettes.of(0.5 + 41), Palettes.of(41), "a gene is a whole number")
end)

H.test("palettes: independent of the flower pick ((gene-1) % n + 1) and of the weight variance: every flower in every palette", function()
	local STEP = 17 -- (a sample of the genes, spread over all of them: 17 shares no factor with any n up to 16)
	for n = 2, 16 do
		local seen: { [number]: { [string]: number } } = {}
		local per: { [number]: number } = {}
		for gene = 1, Config.SEED_GENES, STEP do
			local pick = (gene - 1) % n + 1
			local id = Palettes.of(gene) or Palettes.NATURAL
			seen[pick] = seen[pick] or {}
			seen[pick][id] = (seen[pick][id] or 0) + 1
			per[pick] = (per[pick] or 0) + 1
		end
		for pick = 1, n do
			H.near(seen[pick][Palettes.NATURAL] / per[pick], Palettes.NATURAL_WEIGHT / 100, 0.03, `n={n}, flower {pick}: Natural`)
			for _, p in Palettes.LIST do
				H.near((seen[pick][p.id] or 0) / per[pick], p.weight / 100, 0.03, `n={n}, flower {pick}: {p.id}`)
			end
		end
	end
	-- the weight variance: big and small plants come in every palette alike
	local small, big = { total = 0, natural = 0 }, { total = 0, natural = 0 }
	for gene = 1, Config.SEED_GENES, STEP do
		local bucket = if Config.geneVariance(gene) < 1 then small else big
		bucket.total += 1
		bucket.natural += if Palettes.of(gene) then 0 else 1
	end
	H.near(small.natural / small.total, big.natural / big.total, 0.02, "the same share of Natural, small or big")
	-- neighbouring genes don't follow each other
	local same = 0
	for gene = 1, 20000 do
		same += if Palettes.of(gene) == Palettes.of(gene + 1) then 1 else 0
	end
	H.near(same / 20000, 0.44 ^ 2 + 4 * 0.14 ^ 2, 0.03, "neighbours as alike as any two genes")
end)

H.test("palettes: the seed's gene gives its palette on the server plant, the planted plant, the ghost and the 3D pictures", function()
	local rs = H.services.ReplicatedStorage
	local before = rs.__children.FlowerPreviews
	local root = roblox.Instance.new("Folder")
	root.Name = FlowerPreviews.FOLDER
	local zf = roblox.Instance.new("Folder")
	zf.Name = tostring(SPIRIT)
	zf.Parent = root
	local rf = roblox.Instance.new("Folder")
	rf.Name = tostring(EPIC)
	rf.Parent = zf
	local names = CreatureModels.variants(SPIRIT, EPIC)
	for i, name in names do
		FlowerPreviews.build(SPIRIT, EPIC, i, name).Parent = rf
	end
	rs.__children.FlowerPreviews = root
	local FlowerView = H.shared("FlowerView")
	local ok, err = pcall(function()
		local looks = { Palettes.NATURAL }
		for _, p in Palettes.LIST do
			table.insert(looks, p.id)
		end
		for _, name in names do
			for _, look in looks do
				local id = if look ~= Palettes.NATURAL then look else nil
				local gene = geneFor(SPIRIT, EPIC, name, id)
				-- planted: the flower and palette its gene decided, what its ghost showed
				local plant = PlantGhosts.seedPlant(SPIRIT, EPIC, nil, gene, 1, NOW, 0, 0, function()
					return 0.5
				end)
				H.eq(plant.variant, name, "its flower")
				H.eq(plant.palette, id, `{name}: its palette`)
				H.eq(names[(PlantGhosts.seedLook(SPIRIT, EPIC, gene, nil))], name, "the ghost shows that flower")
				-- the server's plant and the HUD's picture of it: the same colours
				local server = CreatureModels.build(SPIRIT, EPIC, nil, pickOf(SPIRIT, EPIC, name), plant.palette)
				local picture = FlowerView.flower(SPIRIT, EPIC, name, nil, plant.palette)
				H.eq(ownColors(picture), ownColors(server), `{name} {id}: the picture is the planted plant`)
				local plain = FlowerView.flower(SPIRIT, EPIC, name)
				if id then
					H.ok(picture ~= plain and ownColors(picture) ~= ownColors(plain), `{name} {id}: recoloured`)
					H.eq(FlowerView.flower(SPIRIT, EPIC, name, nil, id), picture, "made once")
					H.ok(ownColors(plain) == ownColors(FlowerPreviews.build(SPIRIT, EPIC, pickOf(SPIRIT, EPIC, name), name)), "the preview itself stays Natural")
				else
					H.eq(picture, plain, "Natural: the preview itself")
				end
			end
		end
		H.eq(FlowerView.flower(SPIRIT, EPIC, names[1], "Haunted", "Azure"), FlowerView.flower(SPIRIT, EPIC, names[1], "Haunted"), "Haunted wins")
		for _, mut in { "Gold", "Diamond" } do
			H.eq(FlowerView.flower(SPIRIT, EPIC, names[1], mut, "Azure"), FlowerView.flower(SPIRIT, EPIC, names[1], mut), `{mut} wins`)
		end
	end)
	rs.__children.FlowerPreviews = before
	H.ok(ok, err)
end)

H.test("palettes: old plants (no palette) stay Natural and never change; the palette is saved and kept in the inventory", function()
	-- a v12 save: no palette, the model's own colours
	local data = ProfileStore.serialize(ProfileStore.defaultProfile())
	data.v = 12
	data.plants = { { s = 1, z = SPIRIT, r = EPIC, t = NOW - 100, px = 0, pz = 0, vr = "DualityRose", va = 1 } }
	data.inv = { { i = 1, z = SPIRIT, r = EPIC, vr = "Assassino", a = 10, va = 1 } }
	local old = ProfileStore.deserialize(data)
	H.eq(old.plants[1].palette, nil, "an old plant: Natural")
	H.eq(old.inventory[1].palette, nil, "an old inventory plant: Natural")
	local raw = rawModel(SPIRIT, EPIC, "DualityRose")
	local built = CreatureModels.build(SPIRIT, EPIC, nil, pickOf(SPIRIT, EPIC, "DualityRose"), old.plants[1].palette)
	H.eq(ownColors(built), ownColors(raw), "its own colours, as before palettes")
	H.eq(PlotService.plantName(old.plants[1]), "Duality Rose", "no palette in its name")
	-- junk is never trusted
	data.plants[1].pa = "Plaid"
	data.inv[1].pa = 7
	local junk = ProfileStore.deserialize(data)
	H.eq(junk.plants[1].palette, nil)
	H.eq(junk.inventory[1].palette, nil)
	-- a new plant's palette round-trips, and survives the inventory
	local p = ProfileStore.defaultProfile()
	table.insert(p.plants, { slot = 3, zone = SPIRIT, rarity = EPIC, plantedAt = NOW - 50, x = 0, z = 0, variant = "DualityRose", variance = 1, palette = "Azure" })
	local back = ProfileStore.deserialize(ProfileStore.serialize(p))
	H.eq(ProfileStore.serialize(p).v, ProfileStore.VERSION)
	H.eq(back.plants[1].palette, "Azure", "saved")
	local entry = Inventory.take(back, 3, NOW, 1)
	H.ok(entry ~= nil)
	H.eq(entry.palette, "Azure", "into the inventory")
	H.eq(ProfileStore.deserialize(ProfileStore.serialize(back)).inventory[1].palette, "Azure", "saved there")
	H.eq(Inventory.toPlant(entry, 4, NOW, 0, 0).palette, "Azure", "planted again")
	-- a seed from before genes grows Natural
	H.eq(PlantGhosts.seedPlant(SPIRIT, EPIC, nil, nil, 1, NOW, 0, 0, function()
		return 0.3
	end).palette, nil)
end)

H.test("palettes: Haunted, Gold and Diamond win (their makeover) and Rainbow repaints; Night and Celestial tint over the palette", function()
	local name = "DualityRose"
	local pick = pickOf(SPIRIT, EPIC, name)
	for gene = 1, 2000 do
		H.eq(Palettes.ofSeed(gene, Halloween.MUTATION), nil, "a Haunted seed has no palette")
		H.eq(Palettes.ofSeed(gene, "Rainbow"), nil, "nor a Rainbow one")
		H.eq(Palettes.ofSeed(gene, "Gold"), nil, "nor a Gold one")
		H.eq(Palettes.ofSeed(gene, "Diamond"), nil, "nor a Diamond one")
		H.eq(Palettes.ofSeed(gene, "Night"), Palettes.of(gene), "a Night seed has its gene's")
	end
	H.eq(PlantGhosts.seedPlant(SPIRIT, EPIC, Halloween.MUTATION, 77, 1, NOW, 0, 0, math.random).palette, nil)
	for _, p in Palettes.LIST do
		local haunted = CreatureModels.build(SPIRIT, EPIC, Halloween.MUTATION, pick, p.id)
		H.eq(ownColors(haunted), ownColors(CreatureModels.build(SPIRIT, EPIC, Halloween.MUTATION, pick)), `Haunted {p.id}: the Haunted look`)
		H.eq(Palettes.prefix(p.id, Halloween.MUTATION), "", "named Haunted only")
		H.eq(Palettes.shown(p.id, "Rainbow"), nil)
		for _, mut in { "Gold", "Diamond" } do
			local made = CreatureModels.build(SPIRIT, EPIC, mut, pick, p.id)
			H.eq(ownColors(made), ownColors(CreatureModels.build(SPIRIT, EPIC, mut, pick)), `{mut} {p.id}: the {mut} look`)
			H.eq(Palettes.prefix(p.id, mut), "", `named {mut} only`)
		end
	end
	-- the tints go over a palette and it still shows through: a palette's plant stays at least half as far
	-- (in colour, part by part) from the Natural one under the same mutation as without it
	local function apart(a: any, b: any): number
		local pa, pb = partsOf(a), partsOf(b)
		local total, gap = 0, 0
		for i, d in pa do
			if not d:GetAttribute(Halloween.FLAIR) then
				local x, y, w = d.Color, pb[i].Color, area(d)
				total += w
				gap += (math.abs(x.R - y.R) + math.abs(x.G - y.G) + math.abs(x.B - y.B)) * w
			end
		end
		return gap / total
	end
	for _, name in CreatureModels.variants(SPIRIT, EPIC) do
		local at = pickOf(SPIRIT, EPIC, name)
		local plain = CreatureModels.build(SPIRIT, EPIC, nil, at)
		for _, mut in { "Night", "Celestial" } do
			local natural = CreatureModels.build(SPIRIT, EPIC, mut, at)
			for _, p in Palettes.LIST do
				local tinted = CreatureModels.build(SPIRIT, EPIC, mut, at, p.id)
				local without = apart(CreatureModels.build(SPIRIT, EPIC, nil, at, p.id), plain)
				H.ok(apart(tinted, natural) >= 0.5 * without, `{mut} {name} {p.id}: the palette shows through`)
				H.eq(tinted:GetAttribute("Mutation"), mut)
			end
		end
	end
end)

H.test("palettes: named before the flower, after the mutation (\"Night Azure Duality Rose\"), and found in the Index", function()
	local plant = { slot = 1, zone = SPIRIT, rarity = EPIC, plantedAt = NOW, x = 0, z = 0, variant = "DualityRose", palette = "Azure" }
	H.eq(PlotService.plantName(plant), "Azure Duality Rose")
	plant.mutation = "Night"
	H.eq(PlotService.plantName(plant), "Night Azure Duality Rose")
	plant.mutation = Halloween.MUTATION
	H.eq(PlotService.plantName(plant), "Haunted Duality Rose", "Haunted: no palette")
	plant.mutation = "Diamond"
	H.eq(PlotService.plantName(plant), "Diamond Duality Rose", "Diamond: no palette")
	plant.mutation = "Gold"
	H.eq(PlotService.plantName(plant), "Gold Duality Rose", "Gold: no palette")
	plant.mutation = nil
	plant.palette = nil
	H.eq(PlotService.plantName(plant), "Duality Rose", "Natural: no word")
	plant.palette = "Crimson"
	local keys = PlotService.indexKeys(plant)
	H.ok(table.find(keys, `{SPIRIT}:{EPIC}:DualityRose`) ~= nil, "the flower, as before")
	H.ok(table.find(keys, `{SPIRIT}:{EPIC}:DualityRose:Crimson`) ~= nil, "and its palette")
	plant.palette = nil
	H.eq(#PlotService.indexKeys(plant), 2, "Natural: the flower only")
	-- every palette key fits a save (ProfileStore keeps keys under 40 characters)
	for _, m in allModels() do
		for _, p in Palettes.LIST do
			H.ok(#`{m[1]}:{m[2]}:{m[3]}:{p.id}` < 40, `{m[3]} {p.id}: its Index key fits`)
		end
	end
	-- the HUD: the plants' pictures in their palette, the Index's palette studs
	local HUD = fs.readFile("src/client/HUD.client.luau")
	local _, n = string.gsub(HUD, "FlowerView%.flower%(p%.zone, p%.rarity, p%.flower, p%.mutation, p%.palette%)", "")
	H.eq(n, 3, "Plants, Inventory and Sell cards")
	H.ok(string.find(HUD, "local lit = stats.index[`{c.key}:{p.id}`] == true", 1, true) ~= nil, "the Index cell's palette studs")
	local plot = fs.readFile("src/server/PlotService.luau")
	local _, sent = string.gsub(plot, "palette = Palettes%.shown%(plant%.palette, plant%.mutation%),", "")
	H.eq(sent, 2, "the plants and the inventory tell the HUD their palette")
end)

H.test("palettes: purely cosmetic: income, weight and price are the same in every palette", function()
	local base = { slot = 1, zone = SPIRIT, rarity = EPIC, plantedAt = NOW - 600, x = 0, z = 0, variant = "DualityRose", variance = 1.1 }
	local w0, i0 = PlotService.plantStats(base, NOW, 1)
	local s0 = Selling.price(base, NOW, 1)
	for _, p in Palettes.LIST do
		local plant = table.clone(base)
		plant.palette = p.id
		local w, i = PlotService.plantStats(plant, NOW, 1)
		H.eq(w, w0, `{p.id}: weight`)
		H.eq(i, i0, `{p.id}: income`)
		H.eq(Selling.price(plant, NOW, 1), s0, `{p.id}: price`)
	end
end)

H.test("palettes: every plant in every palette keeps its contrast (hues turned, never its brightness or saturation)", function()
	H.ok(#allModels() > 100, "every plant model")
	for _, m in allModels() do
		local k, r, name = m[1], m[2], m[3]
		local raw = rawModel(k, r, name)
		local before = partsOf(raw)
		local total, leafy = 0, 0
		for _, d in before do
			local a = area(d)
			total += a
			local h, s, v = d.Color:ToHSV()
			if s >= Palettes.CHROMA and v >= Palettes.DARK and Palettes.fromFoliage(h) == 0 then
				leafy += a
			end
		end
		for _, p in Palettes.LIST do
			local label = `{Config.ZONES[k].id} {name} {p.id}`
			local copy = raw:Clone()
			local after = partsOf(copy)
			local plan = Palettes.plan(after, p.id)
			H.ok(plan ~= nil, `{label}: something turns`)
			Palettes.apply(copy, p.id)
			local changed, blossom, intoLeaves, onHue = 0, 0, 0, 0
			for i, d in after do
				local h0, s0, v0 = before[i].Color:ToHSV()
				local h1, s1, v1 = d.Color:ToHSV()
				H.near(v1, v0, 0.01, `{label}: brightness kept`)
				if s0 >= Palettes.CHROMA then
					H.near(s1, s0, 0.01, `{label}: saturation kept`)
				else
					H.ok(s1 >= s0 - 0.01, `{label}: a white or grey only washed`)
				end
				H.eq(d.Material, before[i].Material, `{label}: Neon stays Neon`)
				if d.Color:ToHex() ~= before[i].Color:ToHex() then
					local a = area(d)
					changed += a
					if s0 >= Palettes.CHROMA and v0 >= 0.05 then
						-- every turned colour by the same angle: the plant's own contrasts between them stay
						H.near(hueGap(h1, h0), math.abs((plan :: any).shift), 0.02, `{label}: one turn for all`)
					end
					if (plan :: any).blossom then
						blossom += a
						intoLeaves += if Palettes.fromFoliage(h1) == 0 then a else 0
					end
					onHue += if hueGap(h1, p.hue) <= 1 / Palettes.BINS + Palettes.MIN_SHIFT then a else 0
				end
			end
			H.ok(changed >= 0.1 * total, `{label}: the palette shows ({math.floor(changed / total * 100)}% of it turned)`)
			H.ok(onHue >= 0.25 * changed, `{label}: it reads {p.id} ({math.floor(onHue / changed * 100)}% on its hue)`)
			if leafy >= 0.15 * total and blossom > 0 then
				H.ok(intoLeaves <= 0.5 * blossom, `{label}: the blossom stays apart from the leaves ({math.floor(intoLeaves / blossom * 100)}% green)`)
			end
		end
	end
	-- by colour, whatever the parts' order (the HUD's picture is a copy)
	for _, c in { { SPIRIT, EPIC, "DualityFlower" }, { 1, 1, "Daisy" }, { 5, 3, "CrystalDaisy" } } do
		local parts = partsOf(rawModel(c[1], c[2], c[3]))
		local reversed = {}
		for i = #parts, 1, -1 do
			table.insert(reversed, parts[i])
		end
		for _, p in Palettes.LIST do
			local a, b = Palettes.plan(parts, p.id) :: any, Palettes.plan(reversed, p.id) :: any
			H.eq(a.shift, b.shift, `{c[3]} {p.id}: either way`)
			H.eq(a.blossom, b.blossom)
		end
	end
	-- the plant's own glow and sparkles turn with it; our halo and pumpkin don't
	local plant = CreatureModels.build(SPIRIT, Config.LEGENDARY, Halloween.MUTATION, 1)
	local flair = {}
	for _, d in plant:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute(Halloween.FLAIR) then
			flair[d] = d.Color:ToHex()
		end
	end
	Palettes.apply(plant, "Azure")
	for d, hex in flair do
		H.eq(d.Color:ToHex(), hex, "our flair keeps its colours")
	end
	H.eq(Palettes.FLAIR, Halloween.FLAIR)
	local glowing = 0
	for _, m in allModels() do
		local raw = rawModel(m[1], m[2], m[3])
		local copy = raw:Clone()
		local plan = Palettes.plan(partsOf(copy), "Violet") :: any
		Palettes.apply(copy, "Violet")
		local mine, theirs = raw:GetDescendants(), copy:GetDescendants()
		for i, d in mine do
			if d:IsA("ParticleEmitter") or d:IsA("Beam") then
				glowing += 1
				for j, key in theirs[i].Color.Keypoints do
					H.eq(key.Value:ToHex(), Palettes.recolor(d.Color.Keypoints[j].Value, plan):ToHex(), `{m[3]}: its {d.Name} turns too`)
				end
			end
		end
	end
	H.ok(glowing > 0, "some plants have their own particles or beams")
end)
