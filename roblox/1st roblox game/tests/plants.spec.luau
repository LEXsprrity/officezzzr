-- The game's plants: the owner's flower pack (models/plants/FlowersByLoxxsy.rbxm), exported by
-- tools/export_plants.luau into assets/Creature_<Seed>.rbxm, one folder per rarity. Every zone x rarity has
-- models that load and fit, the swords are only Spirit Garden Legendaries, the Legendaries are the pack's
-- big plants, and a plot of them stays within a part budget.
local H = require("./harness")
local loaded = require("./creature_loader")

local CreatureModels, Config = loaded.CreatureModels, loaded.Config

local SPIRIT = #Config.ZONES
local L = Config.LEGENDARY

local function slotOf(k: number): string
	return "Creature_" .. string.gsub(Config.ZONES[k].seed, "%s", "")
end

-- The exported models for zone k, rarity r (in the order CreatureModels picks them).
local function variants(k: number, r: number): { any }
	local file = H.assets:FindFirstChild(slotOf(k))
	local folder = file and file:FindFirstChild(Config.RARITIES[r].id)
	local out = {}
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				table.insert(out, m)
			end
		end
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

local function count(root: any, class: string, except: { [string]: boolean }?): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA(class) and not (except and except[d.Name]) then
			n += 1
		end
	end
	return n
end

local OUR_FX = { RaritySparkles = true, ZoneFX = true, MutationSparkles = true }

H.test("plants: every zone x rarity has plant models, and each one builds (picked per plant)", function()
	for k = 1, #Config.ZONES do
		H.ok(H.assets:FindFirstChild(slotOf(k)) ~= nil, `assets/{slotOf(k)}.rbxm`)
		for r = 1, #Config.RARITIES do
			local list = variants(k, r)
			local label = `{Config.ZONES[k].id} {Config.RARITIES[r].id}`
			H.ok(#list >= 1, label .. " has models")
			for i, source in list do
				H.eq(count(source, "LuaSourceContainer"), 0, `{label} {source.Name}: no scripts`)
				H.eq(source:GetAttribute("KeepScale"), true, `{label} {source.Name}: exported to size`)
				local model = CreatureModels.build(k, r, nil, i)
				H.eq(model:GetAttribute("Asset"), source.Name, `{label}: pick {i} is {source.Name}`)
				H.ok(model.PrimaryPart ~= nil and model.PrimaryPart:FindFirstChild("InfoAnchor") ~= nil
					and model.PrimaryPart:FindFirstChild("PromptAnchor") ~= nil, `{label} {source.Name}: body and anchors`)
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						H.ok(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, `{label} {source.Name}: {d.Name} anchored decoration`)
					end
				end
				-- the same plant id always gets the same model; ids wrap around the list
				H.eq(CreatureModels.build(k, r, nil, i + #list):GetAttribute("Asset"), source.Name, `{label}: pick wraps`)
				model:Destroy()
			end
		end
	end
end)

H.test("plants: each fits its rarity's footprint and height (so Planting's spacing holds)", function()
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			for i, source in variants(k, r) do
				local model = CreatureModels.build(k, r, nil, i)
				local radius, height = CreatureModels.extents(model)
				local label = `{Config.ZONES[k].id} {Config.RARITIES[r].id} {source.Name}`
				H.ok(radius <= Config.creatureFootprint(r) / 2 + 0.01, `{label}: reach {radius}`)
				-- (+ the Legendary halo over the top)
				H.ok(height <= Config.creatureHeight(k, r) + (if r == L then 1 else 0.01), `{label}: height {height}`)
				H.ok(height >= 1.5, `{label}: visible ({height})`)
				model:Destroy()
			end
		end
	end
end)

H.test("plants: each plant is named after its flower: CreatureModels.variantOf is the model build picks", function()
	local Format = H.shared("Format")
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			local list = variants(k, r)
			local names = CreatureModels.variants(k, r)
			local label = `{Config.ZONES[k].id} {Config.RARITIES[r].id}`
			H.eq(#names, #list, label .. ": the Index lists every model")
			for i, source in list do
				H.eq(names[i], source.Name, `{label}: catalog order`)
				H.eq(CreatureModels.variantOf(k, r, i), source.Name, `{label}: plant id {i}`)
				H.eq(CreatureModels.variantOf(k, r, i + #list), source.Name, `{label}: ids wrap like build`)
				H.ok(#`{k}:{r}:{source.Name}` < 40, `{label} {source.Name}: its Index key fits a save (< 40 chars)`)
			end
		end
	end
	H.eq(Format.plantName("Daisy"), "Daisy")
	H.eq(Format.plantName("DesertWildFlower"), "Desert Wild Flower")
	H.eq(Format.plantName("LaVaca"), "La Vaca")
	H.eq(Format.plantName("SixSeven"), "Six Seven")
end)

H.test("plants: the server names plants by flower everywhere and fills the Index per flower (saves stay compatible)", function()
	local fs = require("@lune/fs")
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, "line(\"Name\", PlotService.plantName(plant)", 1, true) ~= nil, "the billboard")
	H.ok(string.find(plot, "name = PlotService.plantName(plant), --", 1, true) ~= nil, "the plants view (Plants panel, Sell cards)")
	H.ok(string.find(plot, "`{plant.zone}:{plant.rarity}:{variant}`", 1, true) ~= nil, "an Index key per flower")
	H.ok(string.find(plot, "`{plant.zone}:{plant.rarity}`", 1, true) ~= nil, "the old zone:rarity key is still set")
	H.ok(string.find(plot, "discover(s.profile, plant) -- saves from before", 1, true) ~= nil, "old saves: planted flowers count")
	H.ok(string.find(plot, "Sessions.push(s.player, { catalog = catalog() })", 1, true) ~= nil, "the client gets the flower catalog")
end)

H.test("plants: a seed's flower is drawn when it is planted and kept in `variant` (old plants keep the id pick)", function()
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			local names = CreatureModels.variants(k, r)
			local label = `{Config.ZONES[k].id} {Config.RARITIES[r].id}`
			-- every flower can come up, from the whole roll range, never out of the list
			local seen = {}
			for i = 0, 99 do
				local v = CreatureModels.randomVariant(k, r, function()
					return i / 100
				end)
				H.ok(v ~= nil and table.find(names, v) ~= nil, `{label}: draws one of its models`)
				seen[v :: string] = true
			end
			H.ok(CreatureModels.randomVariant(k, r, function()
				return 0.999999
			end) == names[#names], `{label}: the top of the roll`)
			for i, name in names do
				H.ok(seen[name], `{label}: {name} can be drawn`)
				-- the plant grows into its saved flower, whatever its id
				H.eq(CreatureModels.pickOf(k, r, name, 7), i, `{label}: {name} is built`)
				H.eq(CreatureModels.flowerOf(k, r, name, 7), name, `{label}: and named`)
			end
			-- a plant from before v8 (no variant), or one whose model is gone: the old id-based pick
			H.eq(CreatureModels.pickOf(k, r, nil, 5), 5, `{label}: no variant`)
			H.eq(CreatureModels.pickOf(k, r, "NoSuchFlower", 5), 5, `{label}: an unknown variant`)
			H.eq(CreatureModels.flowerOf(k, r, nil, 5), CreatureModels.variantOf(k, r, 5), `{label}: the same flower as before`)
		end
	end
	local fs = require("@lune/fs")
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, "else PlantGhosts.seedPlant(zone, rarity, mutation, gene, slot, now, x, z, flowerRoll)", 1, true) ~= nil, "planting makes the seed's plant")
	local ghosts = fs.readFile("src/server/PlantGhosts.luau")
	H.ok(string.find(ghosts, "else CreatureModels.randomVariant(zone, rarity, roll)", 1, true) ~= nil, "a seed without a gene draws its flower then")
	H.ok(string.find(plot, "CreatureModels.build(plant.zone, plant.rarity, plant.mutation, CreatureModels.pickOf(plant.zone, plant.rarity, plant.variant, plant.slot))", 1, true) ~= nil,
		"the model is the saved flower")
	H.ok(string.find(plot, "CreatureModels.flowerOf(plant.zone, plant.rarity, plant.variant, plant.slot)", 1, true) ~= nil, "named and indexed by it")
	H.ok(string.find(plot, "pos = top,", 1, true) ~= nil, "the client gets where to reveal its name")
	local client = fs.readFile("src/client/Planting.client.luau")
	H.ok(string.find(client, "reveal(data.name, data.pos,", 1, true) ~= nil and string.find(client, "UiFx.relief(text", 1, true) ~= nil,
		"the name pops up over the new plant, in relief")
end)

H.test("plants: until it is planted a seed only says its rarity (\"Rare Seed\"), never its flower or zone seed", function()
	local SeedPacks = H.shared("SeedPacks")
	local SeedService = H.server("SeedService")
	for k, zone in Config.ZONES do
		for r, rarity in Config.RARITIES do
			local name = SeedPacks.seedName(k, r, nil)
			H.eq(name, `{rarity.id} Seed`)
			H.eq(SeedService.seedName(k, r, nil), name, "pods and carried seeds")
			H.ok(not string.find(name, zone.seed, 1, true), `{zone.id}: no zone seed name`)
			for _, flower in CreatureModels.variants(k, r) do
				H.ok(not string.find(name, flower, 1, true), `{zone.id}: no flower name`)
			end
		end
	end
	H.eq(SeedPacks.seedName(6, 3, "Gold"), "Gold Rare Seed")
end)

H.test("plants: the swords (katanas) are Legendary and only in the Spirit Garden", function()
	local swords = {}
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			for _, m in variants(k, r) do
				if m:GetAttribute("Sword") then
					H.ok(k == SPIRIT and r == L, `{m.Name} is a sword outside Spirit Legendary ({Config.ZONES[k].id} {Config.RARITIES[r].id})`)
					swords[m.Name] = true
				end
			end
		end
	end
	H.ok(swords.Cryonix and swords.Pyronis, "Cryonix and Pyronis are the Spirit Garden swords")
end)

H.test("plants: Legendaries are the pack's big plants (20+ studs), everything else is small", function()
	local seen = {}
	for k = 1, #Config.ZONES do
		local legendaries = #variants(k, L)
		H.ok(legendaries >= 2 and legendaries <= 4, `{Config.ZONES[k].id}: {legendaries} Legendaries`)
		for r = 1, #Config.RARITIES do
			for _, m in variants(k, r) do
				local source, tall = m:GetAttribute("Source"), m:GetAttribute("SourceHeight")
				H.ok(type(source) == "string" and type(tall) == "number", `{m.Name}: Source and SourceHeight`)
				H.ok(not seen[m.Name], `{m.Name} used once`)
				seen[m.Name] = true
				if r == L then
					H.ok(tall >= 20, `Legendary {m.Name} is big ({tall})`)
				else
					H.ok(tall < 20 and string.sub(source, 1, 8) ~= "Titanic/", `{Config.RARITIES[r].id} {m.Name} is small ({source}, {tall})`)
				end
			end
		end
	end
end)

H.test("plants: Legendaries tower over the zone's Commons and grow past 15 studs", function()
	for k = 1, #Config.ZONES do
		local tallestCommon = 0
		for i in variants(k, 1) do
			local _, h = CreatureModels.extents(CreatureModels.build(k, 1, nil, i))
			tallestCommon = math.max(tallestCommon, h)
		end
		for i, m in variants(k, L) do
			local _, h = CreatureModels.extents(CreatureModels.build(k, L, nil, i))
			H.ok(h > tallestCommon, `{m.Name} ({h}) over the {Config.ZONES[k].id} Commons ({tallestCommon})`)
			local grown = CreatureModels.scaleFor(k, L, Config.sproutWeight(k, L) * Config.GROW_MAX_FACTOR)
			H.ok(h * grown >= 15, `{m.Name} full-grown {h * grown} studs`)
		end
	end
end)

H.test("plants: Legendaries are 1.5x bigger at every stage (owner 2026-10-15); Epics and below unchanged", function()
	H.eq(Config.creatureSizeMult(L), 1.5, "Legendary size")
	for r = 1, L - 1 do
		H.eq(Config.creatureSizeMult(r), 1, `rarity {r} unchanged`)
	end
	for k = 1, #Config.ZONES do
		for r = 1, L do
			for step = 0, 4 do
				local w = Config.plantWeight(k, r, Config.GROW_TIME * step / 4, 1)
				local ratio = w / Config.sproutWeight(k, r)
				local base = math.clamp(ratio ^ Config.CREATURE_GROWTH_EXPONENT * (1 + Config.CREATURE_RARITY_SCALE * (r - 1)),
					Config.CREATURE_MIN_SCALE, Config.CREATURE_MAX_SCALE)
				H.near(CreatureModels.scaleFor(k, r, w), base * (if r == L then 1.5 else 1), 1e-9, `zone {k} rarity {r} step {step}`)
			end
		end
		-- the zone's tallest Legendary, full-grown: ~36 (Meadow) .. ~43+ (Spirit Garden) studs
		local tallest = 0
		for i in variants(k, L) do
			local _, h = CreatureModels.extents(CreatureModels.build(k, L, nil, i))
			tallest = math.max(tallest, h)
		end
		local grown = CreatureModels.scaleFor(k, L, Config.sproutWeight(k, L) * Config.GROW_MAX_FACTOR)
		H.ok(tallest * grown >= 33 and tallest * grown <= 50, `{Config.ZONES[k].id} tallest Legendary full-grown {tallest * grown} studs`)
	end
end)

H.test("plants: they keep their own effects and still get rarity and mutation flair", function()
	local cryonix
	for i, m in variants(SPIRIT, L) do
		if m.Name == "Cryonix" then
			cryonix = CreatureModels.build(SPIRIT, L, "Gold", i)
		end
	end
	H.ok(cryonix ~= nil, "Cryonix builds")
	H.ok(count(cryonix, "ParticleEmitter", OUR_FX) > 0 and count(cryonix, "Beam") > 0, "Cryonix keeps its particles and beams")
	local foil = 0
	for _, d in cryonix:GetDescendants() do
		if d:IsA("BasePart") and d.Material.Name == "Foil" then
			foil += 1
		end
	end
	H.ok(foil > 0, "the Gold mutation applies")
	H.eq(cryonix:GetAttribute("Mutation"), "Gold")
	local ring
	for _, d in cryonix:GetDescendants() do
		if d.Name == "AuraRing" then
			ring = d
		end
	end
	H.eq(ring, nil, "no aura ring on the ground under the plant")
	local halo = 0
	for _, d in cryonix:GetDescendants() do
		if d.Name == "HaloOrb" then
			halo += 1
		end
	end
	H.eq(halo, 6, "the Legendary halo")
end)

-- Parts and particle emitters per plant model, by rarity: a plot holds up to SLOTS_MAX + PASS_EXTRA_SLOTS
-- plants and a server up to 8 plots, so the common rarities use the lighter models.
local MAX_PARTS = { 25, 30, 45, 50, 75 }
local MAX_EMITTERS = { 4, 8, 25, 30, 40 }

H.test("plants: a plot full of them stays within the part budget", function()
	local plants = Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS
	for k = 1, #Config.ZONES do
		local weights = Config.rarityWeights(k, 1)
		local average = 0
		for r = 1, #Config.RARITIES do
			local list = variants(k, r)
			local sum = 0
			for _, m in list do
				local parts, emitters = count(m, "BasePart"), count(m, "ParticleEmitter")
				H.ok(parts <= MAX_PARTS[r], `{Config.RARITIES[r].id} {m.Name}: {parts} parts`)
				H.ok(emitters <= MAX_EMITTERS[r], `{Config.RARITIES[r].id} {m.Name}: {emitters} particle emitters`)
				sum += parts
			end
			average += weights[r] * sum / math.max(#list, 1)
		end
		print(string.format("        %-7s ~%.1f parts per plant, ~%d per full plot (%d plants)", Config.ZONES[k].id, average, math.floor(average * plants), plants))
		H.ok(average <= 22, `{Config.ZONES[k].id}: {average} parts per plant on average`)
	end
end)

H.test("plants: each stands on its base, not floating on a leaf that pokes below it (owner: Aetheris floated)", function()
	local function bottomOf(p: any): number
		local c, s = p.CFrame, p.Size
		return c.Position.Y - (math.abs(c.RightVector.Y) * s.X / 2 + math.abs(c.UpVector.Y) * s.Y / 2 + math.abs(c.LookVector.Y) * s.Z / 2)
	end
	local checked = 0
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			for i, source in variants(k, r) do
				if not source:GetAttribute("Sword") then
					local model = CreatureModels.build(k, r, nil, i)
					local base = model:FindFirstChild("PrimaryPart")
					if base and base:IsA("BasePart") and base.Transparency >= 1 then
						local y = bottomOf(base) -- (build pivots the plant at the origin, on the soil)
						H.ok(y < 0.1 and y > -1, `{Config.ZONES[k].id} {source.Name}: its base {y} studs off the ground`) -- (a little sunk in the soil is fine)
						checked += 1
					end
					model:Destroy()
				end
			end
		end
	end
	H.ok(checked > 50, `checked {checked} plants`)
end)

return nil
