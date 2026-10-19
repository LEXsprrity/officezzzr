-- The Halloween event (Shared/Halloween): candy, the Haunted seed sold for it, the Haunted mutation, the save.
local fs = require("@lune/fs")
local H = require("./harness")

local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")
local Halloween = H.shared("Halloween")
local Shop = H.server("Shop")
local ProfileStore = H.server("ProfileStore")

local DURING = Halloween.START + 3600
local AFTER = Halloween.END

local function seeded(seed: number): () -> number
	local r = H.Random.new(seed)
	return function()
		return r:NextNumber()
	end
end

H.test("halloween: runs from START to END (two weeks, through Nov 1)", function()
	H.ok(not Halloween.active(Halloween.START - 1), "not before")
	H.ok(Halloween.active(DURING), "during")
	H.ok(not Halloween.active(AFTER), "over at END")
	H.ok(Halloween.END - Halloween.START >= 13 * 86400, "about two weeks")
	H.eq(Halloween.timeLeft(Halloween.END - 3 * 86400), "3 days left")
	H.eq(Halloween.timeLeft(Halloween.END - 5 * 3600), "5 h left")
	H.eq(Halloween.timeLeft(Halloween.END - 90), "2 min left")
end)

H.test("halloween: 50 candy for one pull, 500 for ten (owner 2026-10-19), nothing else", function()
	H.eq(Halloween.price(1), 50)
	H.eq(Halloween.price(10), 500)
	for _, bad in { 0, 2, 5, 11, -1, 1.5 } do
		H.eq(Halloween.price(bad), nil, tostring(bad))
	end
end)

H.test("halloween: candy spots lie only in the corridor (off the walls, away from the nests), never in the base", function()
	local rng = seeded(3)
	local half = Config.CORRIDOR_WIDTH / 2
	for _ = 1, 3000 do
		local p = Halloween.spot(rng)
		H.ok(p.X > Config.CORRIDOR_START_X and p.X < Config.END_X, "in the corridor, not the base")
		H.ok(math.abs(p.Z) <= half - 12 + 1e-9, "off the walls")
		H.ok(not Halloween.nearNest(p), "away from the bosses")
	end
	H.ok(Halloween.nearNest(Config.nestCenter(4)), "a nest is near itself")
end)

H.test("halloween: at most 25 candy appear per 5 minutes (owner 2026-10-19), up to 25 on the map", function()
	H.ok(300 / Halloween.CANDY_EVERY <= 25 + 1e-9, `one every {Halloween.CANDY_EVERY} s`)
	H.ok(Halloween.CANDY_START <= Halloween.CANDY_ON_MAP and Halloween.CANDY_ON_MAP <= 25, "a cap")
	local candy = fs.readFile("src/server/CandyService.luau")
	H.ok(not string.find(candy, "CANDY_RESPAWN", 1, true), "a piece picked up doesn't come straight back")
	H.ok(string.find(candy, "#pieces < Halloween.CANDY_ON_MAP", 1, true) ~= nil, "the cap holds")
end)

H.test("halloween: the candy service picks up by walking over (trusted position), and the old candy sources are gone", function()
	local candy = fs.readFile("src/server/CandyService.luau")
	H.ok(string.find(candy, "SpeedService.trustedRoot(s.player)", 1, true) ~= nil, "a trusted position, no teleports")
	H.ok(string.find(candy, "Halloween.CANDY_RADIUS", 1, true) ~= nil, "within the radius")
	H.ok(not string.find(candy, "ProximityPrompt", 1, true) and not string.find(candy, "ClickDetector", 1, true), "no click")
	H.ok(string.find(candy, "Assets.place(\"Candy\"", 1, true) ~= nil, "the owner's candy model when it is in assets/")
	H.ok(not string.find(fs.readFile("src/server/SeedService.luau"), "Halloween", 1, true), "no candy for stealing")
	H.ok(not string.find(fs.readFile("src/server/Main.server.luau"), "CANDY_PER_MINUTE", 1, true), "no candy per minute")
	H.ok(string.find(fs.readFile("src/server/Main.server.luau"), "CandyService", 1, true) ~= nil, "started")
end)

H.test("halloween: the Haunted seed is of the deepest zone the player's Speed reaches", function()
	H.eq(Halloween.bestZone(0), 1)
	for k, zone in Config.ZONES do
		H.eq(Halloween.bestZone(zone.req), k, zone.id)
		if k > 1 then
			H.eq(Halloween.bestZone(zone.req - 1), k - 1, zone.id .. " just below")
		end
	end
end)

H.test("halloween: Haunted is an exclusive x5 mutation that pods never roll", function()
	local m = Config.mutationById(Halloween.MUTATION)
	H.ok(m ~= nil and m.exclusive == true and m.chance == 0, "exclusive")
	H.eq(m.income, 5)
	local rng = seeded(7)
	for _ = 1, 20000 do
		local _, mut = Config.rollSeed(3, 1.5, true, rng)
		H.ok(mut ~= Halloween.MUTATION, "a pod rolled Haunted")
	end
	-- the premium packs don't give it either
	for _, offer in SeedPacks.offers() do
		for _, mut in SeedPacks.odds(offer.pack).mutations do
			H.ok(mut.id ~= Halloween.MUTATION, offer.pack.id)
		end
	end
end)

H.test("halloween: the Haunted seed is always Haunted, with the zone's odds and twice its Legendary chance", function()
	for k, zone in Config.ZONES do
		local pack = SeedPacks.hauntedPack(k)
		H.eq(pack.id, "Haunted:" .. zone.id)
		H.eq(SeedPacks.lookup(pack.id).zone, k, "the reveal finds it")
		local odds = SeedPacks.odds(pack)
		local sum = 0
		for _, pct in odds.rarities do
			sum += pct
		end
		H.near(sum, 100, 1e-9, "rarities")
		H.near(odds.rarities[Config.LEGENDARY], Config.LEGENDARY_CHANCE[k] * Halloween.LEGENDARY_MULT * 100, 1e-9, "Legendary")
		H.eq(#odds.mutations, 1, "only Haunted")
		H.eq(odds.mutations[1].pct, 100)
		local rng = seeded(k)
		for _ = 1, 500 do
			local _, mut = SeedPacks.roll(pack, rng)
			H.eq(mut, Halloween.MUTATION)
		end
	end
	H.eq(SeedPacks.lookup("Haunted:Nowhere"), nil)
end)

H.test("halloween: buying a Haunted seed spends candy and puts a Haunted seed of that zone in the bag", function()
	local p = ProfileStore.defaultProfile()
	p.speed = Config.ZONES[3].req
	p.candy = 54
	local ok, msg, rolls, pack = Shop.buyHaunted(p, 3, 1, DURING, seeded(1))
	H.ok(ok, msg)
	H.eq(p.candy, 4)
	H.eq(#rolls, 1)
	local roll = rolls[1]
	H.eq(roll.zone, 3)
	H.eq(roll.mutation, Halloween.MUTATION)
	H.eq(pack.id, "Haunted:Jungle")
	H.eq(SeedPacks.bagCount(p.seedBag), 1)
	local key = next(p.seedBag)
	local z, r, m = SeedPacks.parseBagKey(key)
	H.ok(z == 3 and r == roll.rarity and m == Halloween.MUTATION, "a plantable Haunted bag key")
	-- ten for 500
	p.candy = 500
	ok, msg, rolls = Shop.buyHaunted(p, 2, 10, DURING, seeded(2))
	H.ok(ok, msg)
	H.eq(p.candy, 0)
	H.eq(#rolls, 10)
	H.eq(SeedPacks.bagCount(p.seedBag), 11)
end)

H.test("halloween: a Haunted seed is refused after the event, without candy, past the Speed, or with a full bag", function()
	local function fresh()
		local p = ProfileStore.defaultProfile()
		p.speed = Config.ZONES[2].req
		p.candy = 1000
		return p
	end
	local p = fresh()
	H.ok(not Shop.buyHaunted(p, 1, 1, AFTER, seeded(1)), "over")
	H.ok(not Shop.buyHaunted(p, 3, 1, DURING, seeded(1)), "zone 3 needs its Speed")
	for _, bad in { 0, 8, 1.5, "1", nil } do
		H.ok(not Shop.buyHaunted(p, bad, 1, DURING, seeded(1)), `junk zone {bad}`)
	end
	for _, bad in { 0, 2, 100, "10", nil } do
		H.ok(not Shop.buyHaunted(p, 1, bad, DURING, seeded(1)), `junk count {bad}`)
	end
	H.eq(p.candy, 1000, "nothing spent")
	p.candy = 49
	H.ok(not Shop.buyHaunted(p, 2, 1, DURING, seeded(1)), "not enough candy")
	p.candy = 499
	H.ok(not Shop.buyHaunted(p, 2, 10, DURING, seeded(1)), "not enough for ten")
	H.eq(p.candy, 499)
	p = fresh()
	p.seedBag["1:1"] = Config.SEED_BAG_MAX
	H.ok(not Shop.buyHaunted(p, 1, 1, DURING, seeded(1)), "bag full")
	p.seedBag["1:1"] = Config.SEED_BAG_MAX - 5
	H.ok(not Shop.buyHaunted(p, 1, 10, DURING, seeded(1)), "ten need ten free spaces")
	H.eq(p.candy, 1000)
	H.ok(Shop.buyHaunted(p, 1, 1, DURING, seeded(1)), "one still fits")
	H.ok(Shop.buyHaunted(fresh(), 1, 1, DURING, seeded(1)), "a lower zone is fine")
end)

H.test("halloween: candy is saved, and old or broken saves load with none", function()
	local p = ProfileStore.defaultProfile()
	H.eq(p.candy, 0)
	p.candy = 123
	H.eq(ProfileStore.deserialize(ProfileStore.serialize(p)).candy, 123)
	local old = ProfileStore.serialize(ProfileStore.defaultProfile())
	old.candy = nil
	H.eq(ProfileStore.deserialize(old).candy, 0, "a save from before the event")
	for _, junk in { -5, 0 / 0, "lots", 1e12 } do
		old.candy = junk
		local c = ProfileStore.deserialize(old).candy
		H.ok(c >= 0 and c <= 1e9 and c == math.floor(c), `junk {junk} -> {c}`)
	end
end)

H.test("halloween: Candy: requests go through Shop.buyHaunted", function()
	local shop = fs.readFile("src/server/ShopService.luau")
	H.ok(string.find(shop, "Shop.buyHaunted(s.profile", 1, true) ~= nil, "the server checks it all")
	H.ok(string.find(shop, "^Candy:(%d):(%d+)$", 1, true) ~= nil, "zone and count")
end)

----------------------------------------------------------------------------------------------------
-- The Haunted set (Halloween.SET): what a Haunted seed grows into, and the Haunted look
----------------------------------------------------------------------------------------------------
local roblox = require("@lune/roblox")
local CreatureModels = H.server("CreatureModels")
local PlantGhosts = H.server("PlantGhosts")
local FlowerPreviews = H.server("FlowerPreviews")
local HAUNTED = Halloween.MUTATION
local L = Config.LEGENDARY

local function rawModel(k: number, r: number, name: string): any
	local file = H.assets:FindFirstChild("Creature_" .. string.gsub(Config.ZONES[k].seed, "%s", ""))
	local folder = file and file:FindFirstChild(Config.RARITIES[r].id)
	return folder and folder:FindFirstChild(name)
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
	return s.X * s.Y + s.Y * s.Z + s.X * s.Z
end

H.test("haunted set: 7 Legendaries (one a zone, the Pyronis), 10 Epics, 10 Rares, 10 Uncommons, 10 Commons", function()
	local want = { 10, 10, 10, 10, 7 }
	local counts = { 0, 0, 0, 0, 0 }
	local seen = {}
	for k in Config.ZONES do
		H.ok(Halloween.SET[k] ~= nil, `{Config.ZONES[k].id} has a set`)
		for r, rarity in Config.RARITIES do
			local names = Halloween.setFlowers(k, r)
			H.ok(#names >= 1, `{Config.ZONES[k].id} {rarity.id}: at least one Haunted plant`)
			counts[r] += #names
			for _, name in names do
				H.ok(not seen[`{k}:{name}`], `{name} listed once`)
				seen[`{k}:{name}`] = true
			end
		end
		H.eq(#Halloween.setFlowers(k, L), 1, `one Legendary in {Config.ZONES[k].id}`)
		for key in Halloween.SET[k] do
			local known = false
			for _, rarity in Config.RARITIES do
				known = known or rarity.id == key
			end
			H.ok(known, `{key}: a rarity`)
		end
	end
	for r, n in want do
		H.eq(counts[r], n, Config.RARITIES[r].id)
	end
	H.eq(Halloween.setFlowers(#Config.ZONES, L)[1], "Pyronis", "the thumbnail's Pyronis")
	H.eq(#Halloween.setFlowers(#Config.ZONES + 1, 1), 0, "no such zone")
	H.eq(#Halloween.setFlowers(1, #Config.RARITIES + 1), 0, "no such rarity")
end)

H.test("haunted set: every name is one of its zone and rarity's plant models (assets/Creature_<Seed>)", function()
	for k in Config.ZONES do
		for r in Config.RARITIES do
			local models = CreatureModels.variants(k, r)
			for _, name in Halloween.setFlowers(k, r) do
				H.ok(table.find(models, name) ~= nil, `{Config.ZONES[k].id} {Config.RARITIES[r].id}: {name} is a model`)
				H.ok(rawModel(k, r, name) ~= nil, `{name} in the asset file`)
			end
			-- all of them are the seed's choices, in the set's order
			H.eq(table.concat(CreatureModels.seedVariants(k, r, HAUNTED), ","), table.concat(Halloween.setFlowers(k, r), ","), `{k}/{r} in gene order`)
		end
	end
end)

H.test("haunted set: a Haunted seed grows only into the set's plants, its gene picking (server, ghost and reveal agree)", function()
	for k in Config.ZONES do
		for r in Config.RARITIES do
			local set = Halloween.setFlowers(k, r)
			local models = CreatureModels.variants(k, r)
			local seen = {}
			for gene = 1, 60 do
				local flower = CreatureModels.seedVariant(k, r, HAUNTED, gene)
				H.ok(flower ~= nil and table.find(set, flower) ~= nil, `{k}/{r} gene {gene}: {flower} is in the set`)
				seen[flower :: string] = true
				H.eq(Halloween.flowerOf(k, r, gene), flower, "the reveal shows the same plant")
				local ghost = PlantGhosts.indexOf(k, r, gene, HAUNTED)
				H.eq(models[ghost], flower, "the planting ghost is that plant")
				local plant = PlantGhosts.seedPlant(k, r, HAUNTED, gene, 1, 0, 0, 0, seeded(gene))
				H.eq(plant.variant, flower, "and it grows into it")
				H.eq(CreatureModels.flowerOf(k, r, plant.variant, plant.slot), flower, "named and indexed by it")
			end
			for _, name in set do
				H.ok(seen[name], `{k}/{r}: {name} can come up`)
			end
			-- a Haunted seed from before genes draws among the set too
			for i = 0, 19 do
				local v = CreatureModels.randomVariant(k, r, function()
					return i / 20
				end, HAUNTED)
				H.ok(table.find(set, v) ~= nil, `{k}/{r}: a gene-less Haunted seed draws {v} from the set`)
			end
		end
	end
end)

H.test("haunted set: every other seed is unchanged (all the models, the same gene pick as before)", function()
	for k in Config.ZONES do
		for r in Config.RARITIES do
			local models = CreatureModels.variants(k, r)
			for _, mut in { false, "Gold", "Rainbow", "Celestial" } do
				local m = if mut then mut else nil
				H.eq(#CreatureModels.seedVariants(k, r, m), #models, `{k}/{r} {m}: every model`)
				for gene = 1, 30 do
					H.eq(CreatureModels.seedVariant(k, r, m, gene), CreatureModels.variantOf(k, r, gene), `{k}/{r} {m} gene {gene}`)
					H.eq(PlantGhosts.indexOf(k, r, gene, m), (gene - 1) % #models + 1, "the same ghost")
				end
			end
		end
	end
end)

H.test("haunted set: a bought Haunted seed plants as a set plant; old Haunted plants and gene-less seeds still load", function()
	local p = ProfileStore.defaultProfile()
	p.speed = Config.ZONES[7].req
	p.candy = 500
	local ok, msg, rolls = Shop.buyHaunted(p, 7, 10, DURING, seeded(11))
	H.ok(ok, msg)
	for _, roll in rolls do
		local key = SeedPacks.bagKey(roll.zone, roll.rarity, roll.mutation, roll.gene)
		H.ok((p.seedBag[key] or 0) > 0, "in the bag under its gene")
		local newKey, zone, rarity, mutation, ghost = PlantGhosts.bagPreview(p.seedBag, key, seeded(1))
		H.eq(newKey, key, "a seed with a gene keeps its key")
		local plant = PlantGhosts.seedPlant(zone, rarity, mutation, roll.gene, 1, 0, 0, 0, seeded(2))
		H.ok(table.find(Halloween.setFlowers(7, rarity), plant.variant) ~= nil, `{plant.variant}: a Haunted set plant`)
		H.eq(CreatureModels.variants(zone, rarity)[ghost], plant.variant, "what its ghost showed")
		H.eq(Halloween.flowerOf(zone, rarity, roll.gene), plant.variant, "what the reveal showed")
	end
	-- a Haunted plant planted before the set keeps its flower (by name), and its save loads as it was
	local old = ProfileStore.defaultProfile()
	table.insert(old.plants, { slot = 1, zone = 1, rarity = 2, mutation = HAUNTED, plantedAt = 0, x = 0, z = 0, variant = "Rose" })
	local loaded = ProfileStore.deserialize(ProfileStore.serialize(old))
	H.eq(loaded.plants[1].variant, "Rose")
	H.eq(loaded.plants[1].mutation, HAUNTED)
	H.eq(CreatureModels.flowerOf(1, 2, "Rose", 1), "Rose", "still a Rose")
	-- a Haunted bag seed from before genes gets one, and a set plant
	local bag = { ["3:4:Haunted"] = 1 }
	local key, zone, rarity, mutation, ghost = PlantGhosts.bagPreview(bag, "3:4:Haunted", seeded(5))
	H.ok(key ~= nil and zone == 3 and rarity == 4 and mutation == HAUNTED, "plantable")
	local _, _, _, gene = SeedPacks.parseBagKey(key)
	H.ok(gene ~= nil, "it got a gene")
	H.ok(table.find(Halloween.setFlowers(3, 4), CreatureModels.variants(3, 4)[ghost]) ~= nil, "its ghost is a set plant")
end)

H.test("haunted look: the Pyronis gets exactly the thumbnail's recipe (green glow, orange brights, purple, wisps)", function()
	local raw = rawModel(#Config.ZONES, L, "Pyronis")
	-- the thumbnail's recipe, by hand
	local expected = raw:Clone()
	for _, d in expected:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Material == roblox.Enum.Material.Neon then
				d.Color = roblox.Color3.fromRGB(140, 255, 60)
			elseif d.Color.R > 0.7 then
				d.Color = d.Color:Lerp(roblox.Color3.fromRGB(255, 125, 20), 0.7)
			else
				d.Color = d.Color:Lerp(roblox.Color3.fromRGB(95, 35, 150), 0.75)
			end
		end
	end
	local mine = raw:Clone()
	Halloween.hauntify(mine)
	H.eq(ownColors(mine), ownColors(expected), "Halloween.hauntify = the thumbnail")
	for _, d in mine:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Beam") then
			H.eq(d.Color, Halloween.WISPS, `{d.Name}: orange to purple wisps`)
		end
	end
	H.eq(Halloween.WISPS.Keypoints[1].Value, roblox.Color3.fromRGB(255, 125, 20))
	H.eq(Halloween.WISPS.Keypoints[3].Value, roblox.Color3.fromRGB(95, 35, 150))
	-- ...and the game's Haunted Pyronis is it, with its jack-o'-lantern
	local pick = table.find(CreatureModels.variants(#Config.ZONES, L), "Pyronis")
	local plant = CreatureModels.build(#Config.ZONES, L, HAUNTED, pick)
	H.eq(ownColors(plant), ownColors(expected), "the planted Haunted Pyronis")
	local pumpkin, emitters = 0, 0
	for _, d in plant:GetDescendants() do
		if d.Name == "Pumpkin" then
			pumpkin += 1
			H.ok(d:GetAttribute(Halloween.FLAIR) == true, "the pumpkin stays orange")
		elseif d:IsA("ParticleEmitter") and d.Name ~= "RaritySparkles" and d.Name ~= "MutationSparkles" then
			emitters += 1
			H.eq(d.Color, Halloween.WISPS, `{d.Name}: wisps`)
		end
	end
	H.eq(pumpkin, 1, "a jack-o'-lantern at its feet")
	H.ok(emitters > 1, "its own particles and the zone's")
	H.eq(plant:GetAttribute("Mutation"), HAUNTED)
	-- a plain one keeps its own colours
	H.eq(ownColors(CreatureModels.build(#Config.ZONES, L, nil, pick)), ownColors(raw), "not Haunted: its own colours")
end)

H.test("haunted look: no set plant turns to mush (some orange, some purple, never all one colour)", function()
	local green, orange, purple = Halloween.GREEN:ToHex(), Halloween.ORANGE, Halloween.PURPLE
	for k in Config.ZONES do
		for r in Config.RARITIES do
			for _, name in Halloween.setFlowers(k, r) do
				local m = rawModel(k, r, name):Clone()
				Halloween.hauntify(m)
				local total, warm, cool = 0, 0, 0
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						local a = area(d)
						total += a
						if d.Color:ToHex() ~= green then
							-- orange-ish (0.7 of the way to orange) or purple-ish (0.75 to purple): whichever is nearer
							local c = d.Color
							local toOrange = math.abs(c.R - orange.R) + math.abs(c.G - orange.G) + math.abs(c.B - orange.B)
							local toPurple = math.abs(c.R - purple.R) + math.abs(c.G - purple.G) + math.abs(c.B - purple.B)
							if toOrange < toPurple then
								warm += a
							else
								cool += a
							end
						end
					end
				end
				local label = `{Config.ZONES[k].id} {name}`
				H.ok(warm >= (Halloween.ORANGE_SHARE - 0.02) * total, `{label}: {math.floor(warm / total * 100)}% orange`)
				H.ok(cool >= 0.1 * total, `{label}: {math.floor(cool / total * 100)}% purple`)
			end
		end
	end
	-- which colours turn orange never depends on the parts' order (the client's preview is a copy)
	local function partsOf(model: any, reversed: boolean): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, if reversed then 1 else #out + 1, d)
			end
		end
		return out
	end
	for _, c in { { 1, 4, "Ballerina" }, { 4, 2, "DarkflareRose" }, { 6, 3, "StarfallFlower" } } do
		local m = rawModel(c[1], c[2], c[3])
		local x, y = Halloween.orangeColors(partsOf(m, false)), Halloween.orangeColors(partsOf(m, true))
		local nx = 0
		for hex in x do
			nx += 1
			H.ok(y[hex], `{c[3]}: {hex} either way`)
		end
		for hex in y do
			H.ok(x[hex], `{c[3]}: {hex} either way`)
		end
		H.ok(nx > 0, `{c[3]}: some colours turn orange`)
	end
end)

H.test("haunted look: the HUD's 3D pictures (FlowerView) show a Haunted plant as the server builds it", function()
	local FlowerView = H.shared("FlowerView")
	local rs = H.services.ReplicatedStorage
	local before = rs.__children.FlowerPreviews
	local root = roblox.Instance.new("Folder")
	root.Name = FlowerPreviews.FOLDER
	local checks = { { 7, L, "Pyronis" }, { 1, 4, "Ballerina" }, { 4, 2, "DarkflareRose" } }
	for _, c in checks do
		local k, r, name = c[1], c[2], c[3]
		local zf = root:FindFirstChild(tostring(k)) or roblox.Instance.new("Folder")
		zf.Name = tostring(k)
		zf.Parent = root
		local rf = roblox.Instance.new("Folder")
		rf.Name = tostring(r)
		rf.Parent = zf
		FlowerPreviews.build(k, r, table.find(CreatureModels.variants(k, r), name), name).Parent = rf
	end
	rs.__children.FlowerPreviews = root
	local ok, err = pcall(function()
		for _, c in checks do
			local k, r, name = c[1], c[2], c[3]
			local plain = FlowerView.flower(k, r, name)
			local spooky = FlowerView.flower(k, r, name, HAUNTED)
			H.ok(plain ~= nil and spooky ~= nil and spooky ~= plain, `{name}: a Haunted copy`)
			H.eq(spooky.Name, name)
			H.eq(FlowerView.flower(k, r, name, HAUNTED), spooky, "made once")
			H.ok(ownColors(plain) ~= ownColors(spooky), "the preview itself stays plain")
			local server = CreatureModels.build(k, r, HAUNTED, table.find(CreatureModels.variants(k, r), name))
			H.eq(ownColors(spooky), ownColors(server), `{name}: the same colours as the planted one`)
			H.eq(FlowerView.flower(k, r, name, "Gold"), plain, "other mutations: the plain picture")
		end
	end)
	rs.__children.FlowerPreviews = before
	H.ok(ok, err)
end)

H.test("haunted reveal: the HALLOWEEN card shows the set's Haunted plants; the reel, the result and the x10 grid show them in 3D", function()
	local pack = SeedPacks.hauntedPack(3)
	local tiles = SeedPacks.showcase(pack, nil)
	H.eq(#tiles, #Config.RARITIES)
	for _, tile in tiles do
		local set = Halloween.setFlowers(3, tile.rarity)
		H.eq(tile.flower, set[1], `{tile.id}: the set's plant`)
		H.eq(tile.mutation, HAUNTED, "in its Haunted look")
		H.eq(#(tile.flowers :: any), #set, "all of them in turn")
	end
	for _, offer in SeedPacks.offers() do -- the Robux packs are unchanged
		for _, tile in SeedPacks.showcase(offer.pack, nil) do
			H.ok(tile.mutation == nil and tile.flowers == nil, offer.pack.id)
		end
	end
	local HUD = string.gsub(fs.readFile("src/client/HUD.client.luau"), "\r", "")
	H.ok(string.find(HUD, "FlowerView.flower(zone, tile.rarity, flowers[i], tile.mutation)", 1, true) ~= nil, "the card's tiles take turns through the set")
	H.ok(string.find(HUD, "local name = flower or (if gene then Halloween.flowerOf(zone, rarity, gene) else nil)", 1, true) ~= nil,
		"the reveal picks the seed's plant like the server")
	H.ok(string.find(HUD, "local plantModel = look and hauntedPlant(look.zone, rarity, mutation, look.gene, look.flower)", 1, true) ~= nil,
		"reel and x10 grid cards: the Haunted plant")
	H.ok(string.find(HUD, "local plant = hauntedPlant(best.zone, best.rarity, best.mutation, tonumber(best.gene))", 1, true) ~= nil, "the single result: its plant")
	H.ok(string.find(HUD, "if mutation == Halloween.MUTATION and i >= REEL_TARGET - HAUNTED_REEL_3D then", 1, true) ~= nil, "the reel's cards")
	-- Haunted plants on the Plants, Inventory and Sell cards wear the look too
	local _, n = string.gsub(HUD, "FlowerView%.flower%(p%.zone, p%.rarity, p%.flower, p%.mutation, p%.palette%)", "")
	H.eq(n, 3, "Plants, Inventory and Sell cards")
end)
