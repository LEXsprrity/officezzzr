-- Mutations (owner 2026-10-19): Gold, Rainbow and the packs' Celestial 2.5x more common; the new Diamond
-- between Gold and Rainbow everywhere a mutation shows; Gold and Diamond as whole makeovers like Haunted
-- (Shared/Mutations: goldify, diamondify), the same on the server's plant and the HUD's 3D picture.
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local H = require("./harness")

local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")
local Palettes = H.shared("Palettes")
local Halloween = H.shared("Halloween")
local Mutations = H.shared("Mutations")
local CreatureModels = H.server("CreatureModels")
local FlowerPreviews = H.server("FlowerPreviews")
local PlantGhosts = H.server("PlantGhosts")
local ProfileStore = H.server("ProfileStore")
local Selling = H.server("Selling")
local Seedling = H.server("Seedling")
H.stubServer("Net", { StatsUpdate = { FireClient = function() end }, LootEvent = { FireClient = function() end }, toast = function() end })
local PlotService = H.server("PlotService")

local Color3, ColorSequence = roblox.Color3, roblox.ColorSequence
local NOW = 1.8e9
local L = Config.LEGENDARY
local MAKEOVERS = { "Gold", "Diamond" }

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

local function area(p: any): number
	local s = p.Size
	return if p.Transparency >= 0.95 then 0 else s.X * s.Y + s.Y * s.Z + s.X * s.Z
end

-- The plant's own parts' looks (colour, material, transparency; not our Flair), sorted.
local function ownLooks(model: any): string
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d:GetAttribute(Halloween.FLAIR) then
			table.insert(out, `{d.Color:ToHex()}/{d.Material.Name}/{string.format("%.3f", d.Transparency)}`)
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function hsv(c: any): (number, number, number)
	local h, s, v = c:ToHSV()
	return h * 360, s, v
end

local function pickOf(k: number, r: number, name: string): number
	return table.find(CreatureModels.variants(k, r), name) :: number
end

----------------------------------------------------------------------------------------------------
-- Chances
----------------------------------------------------------------------------------------------------
H.test("mutations: Gold 5%, Diamond 2%, Rainbow 1.25%, Celestial 0.625% (owner 2026-10-19: half of the 2.5x), in roll order", function()
	local ids = {}
	for _, m in Config.MUTATIONS do
		table.insert(ids, m.id)
	end
	H.eq(table.concat(ids, ","), "Gold,Diamond,Rainbow,Night,Celestial,Haunted", "the roll (and Index) order")
	local gold, diamond, rainbow = Config.mutationById("Gold"), Config.mutationById("Diamond"), Config.mutationById("Rainbow")
	H.near(gold.chance, 0.05, 1e-12, "Gold: 5%")
	H.near(diamond.chance, 0.02, 1e-12, "Diamond: 2%")
	H.near(rainbow.chance, 0.0125, 1e-12, "Rainbow: 1.25%")
	H.near(Config.PACK_EXCLUSIVE_CHANCE, 0.00625, 1e-12, "Celestial: 0.625% of pack seeds")
	for _, c in { { gold.chance, 0.04 }, { rainbow.chance, 0.01 }, { Config.PACK_EXCLUSIVE_CHANCE, 0.005 } } do
		H.ok(c[1] >= c[2] and c[1] <= 1.5 * c[2], "a little over the old chance (1x-1.5x)")
	end
	-- the ladder: the rarer, the better it pays; Diamond between Gold and Rainbow
	H.ok(gold.chance > diamond.chance and diamond.chance > rainbow.chance, "Gold > Diamond > Rainbow in chance")
	H.ok(gold.income < diamond.income and diamond.income < rainbow.income, "Gold < Diamond < Rainbow in pay")
	H.ok(rainbow.income < Config.mutationById("Celestial").income, "Celestial still pays the most")
	H.eq(diamond.income, 4)
	H.ok(not diamond.nightOnly and not diamond.exclusive, "Diamond rolls from pods, day and night")
	-- still mostly plain seeds
	local any = 0
	for _, m in Config.MUTATIONS do
		any += m.chance
	end
	H.ok(any < 0.35, `a night pod: {any * 100}% mutated at most`)
end)

H.test("mutations: a large seeded roll of pods and packs matches the new chances", function()
	local rng = H.Random.new(20261019)
	local function roll()
		return rng:NextNumber()
	end
	local N = 200000
	for _, night in { false, true } do
		local hits: { [string]: number } = {}
		for _ = 1, N do
			local _, m = Config.rollSeed(3, 1, night, roll)
			if m then
				hits[m] = (hits[m] or 0) + 1
			end
		end
		for _, m in Config.MUTATIONS do
			local want = if m.nightOnly and not night then 0 else m.chance * N
			local got = hits[m.id] or 0
			if want == 0 then
				H.eq(got, 0, `{m.id} never rolls here`)
			else
				H.ok(math.abs(got - want) <= 0.06 * want, `{m.id} ({if night then "night" else "day"}): {got} of ~{want}`)
			end
		end
	end
	local pack = SeedPacks.zonePack(6)
	local hits: { [string]: number } = {}
	for _ = 1, N do
		local _, m = SeedPacks.roll(pack, roll)
		if m then
			hits[m] = (hits[m] or 0) + 1
		end
	end
	for _, o in SeedPacks.odds(pack).mutations do
		local want = o.pct / 100 * N
		H.ok(math.abs((hits[o.id] or 0) - want) <= 0.08 * want, `pack {o.id}: {hits[o.id] or 0} of ~{want}`)
	end
end)

----------------------------------------------------------------------------------------------------
-- Diamond everywhere
----------------------------------------------------------------------------------------------------
H.test("diamond: names, odds, the reel, the bud, Sell, the Index and the cards' word colour", function()
	local diamond = Config.mutationById("Diamond")
	H.ok(diamond ~= nil, "a mutation")
	-- names
	H.eq(SeedPacks.seedName(6, 3, "Diamond"), "Diamond Rare Seed")
	local plant = { slot = 1, zone = 1, rarity = 1, plantedAt = NOW, x = 0, z = 0, variant = "Daisy", palette = "Azure", mutation = "Diamond" }
	H.eq(PlotService.plantName(plant), "Diamond Daisy", "the makeover replaces the palette's word")
	H.eq(Config.legendaryAnnouncement("Alex", 7, "Diamond"), "🌟 Alex got a LEGENDARY Diamond Seed!")
	-- the pack odds (and so the Shop's odds line and the reel, which roll from them)
	for _, offer in SeedPacks.offers() do
		local odds = SeedPacks.odds(offer.pack)
		local found = nil
		for _, m in odds.mutations do
			if m.id == "Diamond" then
				found = m.pct
			end
		end
		H.near(found or 0, diamond.chance * Config.PACK_MUTATION_MULT * 100, 1e-9, `{offer.pack.name}: Diamond 8%`)
	end
	local pack = SeedPacks.zonePack(6)
	local odds = SeedPacks.odds(pack)
	local before = odds.mutations[1].pct + odds.mutations[2].pct -- (Celestial, Gold)
	local steps = { 0.5, (before + 0.01) / 100 }
	local _, m = SeedPacks.roll(pack, function()
		return table.remove(steps, 1) :: number
	end)
	H.eq(m, "Diamond", "a pack can land on Diamond")
	H.ok(SeedPacks.better({ rarity = 2, mutation = "Diamond" }, { rarity = 2, mutation = "Gold" }), "x10 best: Diamond beats Gold")
	H.ok(SeedPacks.better({ rarity = 2, mutation = "Rainbow" }, { rarity = 2, mutation = "Diamond" }), "...and Rainbow beats Diamond")
	-- the seed bag key, its label and the Sell list
	local key = SeedPacks.bagKey(4, 2, "Diamond", 123)
	local z, r, mut, gene = SeedPacks.parseBagKey(key)
	H.ok(z == 4 and r == 2 and mut == "Diamond" and gene == 123, "a Diamond bag key round-trips")
	H.ok(Selling.MAX_SEED_LABELS >= #Config.ZONES * #Config.RARITIES * 7, "room for every label")
	-- the bud and the pod's colour
	local bud = Seedling.build(2, 3, "Diamond"):FindFirstChild("Bud") :: any
	H.eq(bud.Color, diamond.color, "the seedling's bud in Diamond's colour")
	-- income and the stall
	H.near(Config.plantIncome(1, 1, Config.sproutWeight(1, 1), "Diamond"), Config.plantIncome(1, 1, Config.sproutWeight(1, 1)) * 4, 1e-9)
	local p = { slot = 1, zone = 3, rarity = 2, mutation = "Diamond", plantedAt = NOW - 600, x = 0, z = 0, variance = 1 }
	local plain = { slot = 2, zone = 3, rarity = 2, plantedAt = NOW - 600, x = 0, z = 0, variance = 1 }
	H.near(Selling.price(p, NOW, 1), 4 * Selling.price(plain, NOW, 1), 1e-6, "sells for 4x")
	H.near(Config.seedSellPrice(3, 2, "Diamond"), 4 * Config.seedSellPrice(3, 2), 1e-6, "a Diamond seed too")
	-- the Index
	local keys = PlotService.indexKeys(p)
	H.ok(table.find(keys, "3:Diamond") ~= nil, "found in the Index")
	-- a colour of its own (the word on the cards and pills)
	for _, other in Config.MUTATIONS do
		if other.id ~= "Diamond" then
			H.ok(other.color ~= diamond.color, `not {other.id}'s colour`)
		end
	end
	local h, s, v = hsv(diamond.color)
	H.ok(h >= 170 and h <= 210 and v > 0.9 and s < 0.4, "icy pale cyan")
end)

H.test("diamond: saves and loads (plants, inventory, seed bag, Index); old mutation ids load unchanged", function()
	local p = ProfileStore.defaultProfile()
	table.insert(p.plants, { slot = 1, zone = 5, rarity = 4, mutation = "Diamond", plantedAt = 100, x = 1, z = 2, variant = "CrystalDaisy" })
	for i, id in { "Gold", "Rainbow", "Night", "Celestial", "Haunted" } do
		table.insert(p.plants, { slot = i + 1, zone = 2, rarity = 2, mutation = id, plantedAt = 100, x = i, z = 4 })
	end
	table.insert(p.inventory, { id = 1, zone = 2, rarity = 3, mutation = "Diamond", age = 50, variance = 1 })
	p.seedBag[SeedPacks.bagKey(6, 5, "Diamond", 4242)] = 2
	p.seedBag["2:3:Gold"] = 1 -- (a key from before genes)
	p.index["5:Diamond"] = true
	local back = ProfileStore.deserialize(serde.decode("json", serde.encode("json", ProfileStore.serialize(p))))
	H.eq(back.plants[1].mutation, "Diamond")
	H.eq(back.plants[1].variant, "CrystalDaisy")
	for i, id in { "Gold", "Rainbow", "Night", "Celestial", "Haunted" } do
		H.eq(back.plants[i + 1].mutation, id, `{id} loads unchanged`)
	end
	H.eq(back.inventory[1].mutation, "Diamond")
	H.eq(back.seedBag[SeedPacks.bagKey(6, 5, "Diamond", 4242)], 2)
	H.eq(back.seedBag["2:3:Gold"], 1)
	H.eq(back.index["5:Diamond"], true)
	-- an unknown mutation id is still dropped
	local junk = ProfileStore.deserialize({ v = ProfileStore.VERSION, plants = { { s = 1, z = 1, r = 1, m = "Platinum", t = 100, px = 0, pz = 0 } } })
	H.eq(junk.plants[1] and junk.plants[1].mutation, nil, "not a mutation")
end)

----------------------------------------------------------------------------------------------------
-- The makeovers
----------------------------------------------------------------------------------------------------
H.test("makeover: goldify and diamondify are deterministic and don't depend on the parts' order", function()
	for _, c in { { 7, L, "Pyronis" }, { 1, 4, "Ballerina" }, { 4, 2, "DarkflareRose" }, { 5, 3, "CrystalDaisy" } } do
		local raw = rawModel(c[1], c[2], c[3])
		H.ok(raw ~= nil, c[3])
		for _, id in MAKEOVERS do
			local a, b = raw:Clone(), raw:Clone()
			Mutations.makeover(a, id)
			Mutations.makeover(b, id)
			H.eq(ownLooks(a), ownLooks(b), `{c[3]} {id}: the same twice`)
			-- the same parts in reverse order, flat in one model
			local shuffled = raw:Clone()
			local flat = roblox.Instance.new("Model")
			local parts = {}
			for _, d in shuffled:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			for i = #parts, 1, -1 do
				parts[i].Parent = flat
			end
			Mutations.makeover(flat, id)
			H.eq(ownLooks(flat), ownLooks(a), `{c[3]} {id}: whatever the order`)
			H.ok(ownLooks(a) ~= ownLooks(raw), `{c[3]} {id}: made over`)
		end
	end
	H.eq(Mutations.makeover(roblox.Instance.new("Model"), "Night"), false, "Night only tints")
	H.eq(Mutations.makeover(roblox.Instance.new("Model"), nil), false)
	H.ok(Mutations.repaints("Gold") and Mutations.repaints("Diamond") and Mutations.repaints(Halloween.MUTATION))
	for _, id in Mutations.REPAINTS do
		H.ok(Config.mutationById(id) ~= nil, id)
		H.ok(Palettes.OVERRIDDEN[id], `{id} replaces the palette`)
	end
end)

H.test("makeover: our Flair (halo, jack-o'-lantern) keeps its colours; the plant's own effects turn", function()
	for _, id in MAKEOVERS do
		local model = rawModel(7, L, "Pyronis"):Clone()
		local flair = roblox.Instance.new("Part")
		flair.Color = Color3.fromRGB(255, 190, 30)
		flair.Material = roblox.Enum.Material.Neon
		flair:SetAttribute(Halloween.FLAIR, true)
		flair.Parent = model
		local fx = roblox.Instance.new("ParticleEmitter")
		fx:SetAttribute(Halloween.FLAIR, true)
		fx.Color = ColorSequence.new(Color3.fromRGB(1, 2, 3))
		fx.Parent = flair
		local own = roblox.Instance.new("ParticleEmitter")
		own.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		Mutations.makeover(model, id)
		H.eq(flair.Color, Color3.fromRGB(255, 190, 30), `{id}: the Flair part as it was`)
		H.eq(flair.Material, roblox.Enum.Material.Neon)
		H.eq(fx.Color.Keypoints[1].Value, Color3.fromRGB(1, 2, 3), `{id}: the Flair's effect as it was`)
		H.eq(own.Texture, Mutations.SPARKLE_TEXTURE, `{id}: the plant's own particles sparkle`)
		H.eq(own.Color, Mutations.LOOKS[id].sparkles)
	end
	-- the built plant: the Legendary halo keeps the rarity's colour
	for _, id in MAKEOVERS do
		local plant = CreatureModels.build(7, L, id, 1)
		local orbs = 0
		for _, d in plant:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "HaloOrb" then
				orbs += 1
				H.eq(d.Color, Config.RARITIES[L].color, `{id}: the halo stays Legendary gold`)
			end
		end
		H.ok(orbs > 0, "a halo")
		H.eq(plant:GetAttribute("Mutation"), id)
	end
end)

H.test("makeover: every plant model reads as gold or as diamond (colour shares, glow, materials, visible)", function()
	local GOLDEN = Mutations.LOOKS.Gold
	local ICE = Mutations.LOOKS.Diamond
	for _, c in allModels() do
		local raw = rawModel(c[1], c[2], c[3])
		local tag = `{c[3]}`
		for _, id in MAKEOVERS do
			local look = Mutations.LOOKS[id]
			local m = raw:Clone()
			Mutations.makeover(m, id)
			local total, themed, glass, visibleBefore, visibleAfter = 0, 0, 0, 0, 0
			local rawParts, parts = {}, {}
			for _, d in raw:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(rawParts, d)
				end
			end
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				elseif d:IsA("ParticleEmitter") then
					H.eq(d.Color, look.sparkles, `{tag} {id}: sparkles`)
				end
			end
			for i, p in parts do
				local a = area(p)
				total += a
				visibleBefore += area(rawParts[i])
				visibleAfter += a
				if p.Material == roblox.Enum.Material.Neon then
					H.eq(p.Color, look.glow, `{tag} {id}: Neon glows`)
					themed += a
					continue
				end
				local h, s, v = hsv(p.Color)
				if id == "Gold" then
					if h >= 25 and h <= 55 and s >= 0.25 then
						themed += a
					end
				elseif (h >= 180 and h <= 215) or (s < 0.12 and v > 0.9) then
					themed += a
				end
				if p.Material == look.brightMaterial and look.brightTransparency > 0 then
					glass += a
					H.ok(p.Transparency <= math.max(rawParts[i].Transparency, look.brightTransparency) + 1e-6, `{tag} {id}: no more see-through than that`)
				end
			end
			H.ok(total > 0, tag)
			H.ok(themed >= 0.95 * total, `{tag} {id}: {math.floor(themed / total * 100)}% on the theme`)
			H.ok(visibleAfter >= 0.999 * visibleBefore, `{tag} {id}: nothing turns invisible`)
			-- its contrast kept: its own brightness range (Mutations.range) at least 40% of what it was
			local lo0, hi0 = Mutations.range(rawParts)
			local lo1, hi1 = Mutations.range(parts)
			if hi0 - lo0 >= Mutations.MIN_RANGE then -- (a one-colour plant has none to keep)
				H.ok(hi1 - lo1 >= 0.4 * (hi0 - lo0), `{tag} {id}: contrast {hi1 - lo1} (was {hi0 - lo0})`)
			end
			if id == "Diamond" then
				H.ok(glass < 0.9 * total or total == 0, `{tag}: not all glass`)
			end
		end
	end
	-- the materials read as the theme
	H.eq(GOLDEN.material, roblox.Enum.Material.Foil)
	H.eq(GOLDEN.darkMaterial, roblox.Enum.Material.Metal)
	H.eq(ICE.brightMaterial, roblox.Enum.Material.Glass)
	H.ok(ICE.brightTransparency > 0 and ICE.brightTransparency <= 0.3, "crystal, never invisible")
end)

H.test("makeover: across the garden, gold has deep amber and pale gold, diamond icy cyan and white crystal", function()
	for _, id in MAKEOVERS do
		local shares = { dark = 0, mid = 0, bright = 0 }
		local look = Mutations.LOOKS[id]
		local darkUnder, brightOver = Mutations.brightness(Mutations.ramp(look, 0.25)), Mutations.brightness(Mutations.ramp(look, 0.75))
		local total = 0
		for _, c in allModels() do
			local m = rawModel(c[1], c[2], c[3]):Clone()
			Mutations.makeover(m, id)
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Material ~= roblox.Enum.Material.Neon then
					local a = area(d)
					local b = Mutations.brightness(d.Color)
					total += a
					shares[if b < darkUnder then "dark" elseif b > brightOver then "bright" else "mid"] += a
				end
			end
		end
		for k, v in shares do
			H.ok(v >= 0.05 * total, `{id}: {k} {math.floor(v / total * 100)}% of the surface`)
		end
		print(`        {id}: dark {math.floor(shares.dark / total * 100)}%, middle {math.floor(shares.mid / total * 100)}%, bright {math.floor(shares.bright / total * 100)}% of the garden`)
		H.ok(shares.mid >= 0.4 * total, `{id}: mostly the rich middle ({math.floor(shares.mid / total * 100)}%)`)
		H.ok(shares.dark <= 0.3 * total, `{id}: not a dark plant`)
	end
end)

H.test("makeover: the HUD's 3D pictures (FlowerView) show Gold and Diamond plants as the server builds them", function()
	local FlowerView = H.shared("FlowerView")
	local rs = H.services.ReplicatedStorage
	local before = rs.__children.FlowerPreviews
	local root = roblox.Instance.new("Folder")
	root.Name = FlowerPreviews.FOLDER
	local checks = { { 7, L, "Pyronis" }, { 1, 4, "Ballerina" }, { 5, 3, "CrystalDaisy" }, { 3, 1, "BugEater" } }
	for _, c in checks do
		local k, r, name = c[1], c[2], c[3]
		local zf = root:FindFirstChild(tostring(k)) or roblox.Instance.new("Folder")
		zf.Name = tostring(k)
		zf.Parent = root
		local rf = roblox.Instance.new("Folder")
		rf.Name = tostring(r)
		rf.Parent = zf
		FlowerPreviews.build(k, r, pickOf(k, r, name), name).Parent = rf
	end
	rs.__children.FlowerPreviews = root
	local ok, err = pcall(function()
		for _, c in checks do
			local k, r, name = c[1], c[2], c[3]
			local plain = FlowerView.flower(k, r, name)
			for _, id in MAKEOVERS do
				local picture = FlowerView.flower(k, r, name, id)
				H.ok(picture ~= nil and picture ~= plain, `{name} {id}: a copy`)
				H.eq(FlowerView.flower(k, r, name, id), picture, "made once")
				H.eq(FlowerView.flower(k, r, name, id, "Violet"), picture, "the makeover wins over the palette")
				local server = CreatureModels.build(k, r, id, pickOf(k, r, name), "Violet")
				H.eq(ownLooks(picture), ownLooks(server), `{name} {id}: the picture is the planted plant`)
				-- the planting ghost too: a seed of the mutation keeps no palette
				H.eq(PlantGhosts.seedPlant(k, r, id, 77, 1, NOW, 0, 0, math.random).palette, nil)
			end
			H.ok(ownLooks(FlowerView.flower(k, r, name, "Gold")) ~= ownLooks(FlowerView.flower(k, r, name, "Diamond")), `{name}: two looks`)
			H.ok(ownLooks(plain) == ownLooks(FlowerPreviews.build(k, r, pickOf(k, r, name), name)), "the preview itself stays plain")
		end
	end)
	rs.__children.FlowerPreviews = before
	H.ok(ok, err)
end)

H.test("makeover: a built-in creature (no plant models) is still tinted by roles, in its mutation's colours", function()
	-- the zones' FALLBACK (no assets): build with a zone whose models are missing is covered in creatures.spec;
	-- here the role tint for Diamond: icy, Ice, a little shine
	local m = CreatureModels.build(2, 1, "Diamond", 1)
	H.eq(m:GetAttribute("Mutation"), "Diamond")
	local sparkles = nil
	for _, d in m:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == "MutationSparkles" then
			sparkles = d
		end
	end
	H.ok(sparkles ~= nil and sparkles.Color == Mutations.LOOKS.Diamond.sparkles, "white-cyan glints")
end)

return nil
