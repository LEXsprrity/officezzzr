-- Seeds (owner requests): a seed's gene decides its flower and size from the moment it exists, so the
-- planting ghost shows exactly what grows (the flower, at the size it has when planted) while every label
-- still says only "Common Seed" until it is planted; pods always show their name tag; seeds have no glow
-- and can be swapped for a model in assets/Seed; a stolen seed goes to the bag as soon as you are home,
-- and the hotbar's slot 2 plants from the bag.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")
local Enum = roblox.Enum

local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")
local ProfileStore = H.server("ProfileStore")
local Inventory = H.server("Inventory")
local CreatureModels = H.server("CreatureModels")
local PlantGhosts = H.server("PlantGhosts")

local Vector3 = H.Vector3
local NOW = 1_800_000_000

-- Lune has no Model:ScaleTo: record the scale instead (what CreatureModels.applyScale would set).
local function withoutScaleTo(fn: () -> ())
	local applyScale = CreatureModels.applyScale
	CreatureModels.applyScale = function(model: any, scale: number)
		model:SetAttribute("Scale", scale)
	end
	local ok, err = pcall(fn)
	CreatureModels.applyScale = applyScale
	if not ok then
		error(err, 0)
	end
end

-- Genes spread over the whole range, and some edge ones.
local GENES = { 1, 2, 3, 7, 16, 97, 1000, 65537, 360360, Config.SEED_GENES - 1, Config.SEED_GENES }

-- Every flower name the game has (to check labels never say one).
local function allFlowers(): { string }
	local names = {}
	for k in Config.ZONES do
		for r in Config.RARITIES do
			for _, name in CreatureModels.variants(k, r) do
				table.insert(names, name)
			end
		end
	end
	return names
end

-- The plant a seed grows into must be the one its ghost showed: the same flower model, and right when it is
-- planted the same size.
local function checkSame(zone: number, rarity: number, gene: number?, ghost: number, scale: number, plant: any, label: string)
	local names = CreatureModels.variants(zone, rarity)
	if #names > 0 then
		H.eq(plant.variant, names[ghost], `{label}: the ghost's flower is the planted flower`)
	end
	H.eq(CreatureModels.pickOf(zone, rarity, plant.variant, plant.slot), if #names > 0 then ghost else plant.slot, `{label}: the planted model is the ghost's`)
	local weight = Config.plantWeight(zone, rarity, NOW - plant.plantedAt, Config.varianceOf(plant))
	H.near(CreatureModels.scaleFor(zone, rarity, weight), scale, 1e-9, `{label}: the ghost's size is the size when planted`)
	H.ok(gene == nil or plant.variance == Config.geneVariance(gene), `{label}: its weight follows its gene`)
end

----------------------------------------------------------------------------------------------------
-- Genes
----------------------------------------------------------------------------------------------------
H.test("seeds: a gene is a whole number in range, every flower is as likely, and its variance is a plant's", function()
	H.eq(Config.rollGene(function()
		return 0
	end), 1)
	H.eq(Config.rollGene(function()
		return 0.9999999999
	end), Config.SEED_GENES)
	for n = 1, 16 do
		H.eq(Config.SEED_GENES % n, 0, `{n} flowers share the genes evenly`)
	end
	for _, gene in GENES do
		local v = Config.geneVariance(gene)
		H.ok(v >= 0.8 and v < 1.2, `gene {gene}: variance {v} in the plants' range`)
	end
end)

H.test("seeds: a pod's seed grows into exactly what its ghost shows (flower and size when planted)", function()
	for zone in Config.ZONES do
		for rarity in Config.RARITIES do
			local seen = {}
			for _, gene in GENES do
				local ghost, scale = PlantGhosts.seedLook(zone, rarity, gene)
				H.ok(ghost >= 1 and ghost <= PlantGhosts.count(zone, rarity), "a ghost that exists")
				local plant = PlantGhosts.seedPlant(zone, rarity, nil, gene, 9, NOW, 1, 2, function()
					error("a seed with a gene never re-rolls its flower")
				end)
				checkSame(zone, rarity, gene, ghost, scale, plant, `{zone}x{rarity} gene {gene}`)
				H.ok(scale < CreatureModels.scaleFor(zone, rarity, Config.plantWeight(zone, rarity, Config.GROW_TIME, plant.variance)) + 1e-9,
					"a sprout, not full-grown")
				seen[ghost] = true
			end
			for i = 1, PlantGhosts.count(zone, rarity) do
				H.ok(seen[i] or PlantGhosts.indexOf(zone, rarity, i) == i, `{zone}x{rarity}: flower {i} can come up`)
			end
		end
	end
	-- a seed from before genes still plants (its flower drawn then)
	local plant = PlantGhosts.seedPlant(1, 1, nil, nil, 3, NOW, 0, 0, function()
		return 0
	end)
	H.eq(plant.variant, CreatureModels.variants(1, 1)[1])
	H.eq(plant.variance, nil, "and the variance from its planting time and id, as before")
end)

H.test("seeds: an inventory plant's ghost is its own flower at its own size", function()
	local profile = ProfileStore.defaultProfile()
	for i, name in CreatureModels.variants(5, 3) do
		table.insert(profile.plants, { slot = i, zone = 5, rarity = 3, plantedAt = NOW - 300 * i, x = 0, z = 0, variant = name })
	end
	for i in CreatureModels.variants(5, 3) do
		local entry = Inventory.take(profile, i, NOW)
		H.ok(entry ~= nil)
		local later = NOW + 5000 -- (growth stops in the inventory)
		local ghost, scale = PlantGhosts.plantLook(Inventory.asPlant(entry, later), later)
		local plant = Inventory.toPlant(entry, 50 + i, later, 1, 1)
		local names = CreatureModels.variants(5, 3)
		H.eq(names[ghost], plant.variant, "its flower")
		local weight = Config.plantWeight(5, 3, later - plant.plantedAt, Config.varianceOf(plant))
		H.near(CreatureModels.scaleFor(5, 3, weight), scale, 1e-9, "its size")
	end
end)

----------------------------------------------------------------------------------------------------
-- The seed bag
----------------------------------------------------------------------------------------------------
H.test("seeds: bag keys carry the gene, old keys still load, and junk genes are refused", function()
	local key = SeedPacks.bagKey(7, 5, "Celestial", Config.SEED_GENES)
	H.eq(key, `7:5:Celestial#{Config.SEED_GENES}`)
	H.ok(#key <= 32, "fits the key limit")
	local z, r, m, g = SeedPacks.parseBagKey(key)
	H.ok(z == 7 and r == 5 and m == "Celestial" and g == Config.SEED_GENES, "round trip")
	z, r, m, g = SeedPacks.parseBagKey("2:3#15")
	H.ok(z == 2 and r == 3 and m == nil and g == 15, "no mutation")
	z, r, m, g = SeedPacks.parseBagKey("2:3:Gold")
	H.ok(z == 2 and r == 3 and m == "Gold" and g == nil, "an old key: no gene")
	for _, bad in { "2:3#0", "2:3#07", "2:3#", `2:3#{Config.SEED_GENES + 1}`, "2:3#-4", "2:3#1.5", "2:3#1#2", "2:3:Gold#x" } do
		H.eq((SeedPacks.parseBagKey(bad)), nil, "rejects " .. bad)
	end
	H.eq(SeedPacks.labelKey(key), "7:5:Celestial")
	H.eq(SeedPacks.labelKey("2:3"), "2:3")
	local bag = {}
	H.eq(SeedPacks.addToBag(bag, 2, 3, nil, 15), "2:3#15", "addToBag says the key")
	H.eq(SeedPacks.addToBag(bag, 2, 3, nil, 15), "2:3#15")
	H.eq(bag["2:3#15"], 2, "the same seed stacks")
end)

H.test("seeds: save v10 keeps the bag's genes; a v9 bag loads as it was", function()
	H.ok(ProfileStore.VERSION >= 10)
	local p = ProfileStore.defaultProfile()
	p.seedBag["3:2:Gold#4242"] = 1
	p.seedBag["1:1#9"] = 2
	local back = ProfileStore.deserialize(ProfileStore.serialize(p))
	H.eq(back.seedBag["3:2:Gold#4242"], 1)
	H.eq(back.seedBag["1:1#9"], 2)
	local v9 = ProfileStore.deserialize({ v = 9, bag = { ["3:2:Gold"] = 2, ["1:1"] = 1, ["1:1#bad"] = 4 } })
	H.eq(v9.seedBag["3:2:Gold"], 2, "old keys load unchanged")
	H.eq(v9.seedBag["1:1"], 1)
	H.eq(v9.seedBag["1:1#bad"], nil, "junk is dropped")
	H.eq(ProfileStore.serialize(v9).v, ProfileStore.VERSION, "saved back in the current version")
end)

H.test("seeds: a bag seed's ghost is what it grows into, and an old seed gets its gene at its Plant button", function()
	local bag = { ["4:2#123"] = 1, ["6:4:Gold"] = 2 }
	local key, zone, rarity, mutation, ghost, scale = PlantGhosts.bagPreview(bag, "4:2#123", function()
		error("a seed with a gene is never re-rolled")
	end)
	H.ok(key == "4:2#123" and zone == 4 and rarity == 2 and mutation == nil)
	local plant = PlantGhosts.seedPlant(4, 2, nil, select(4, SeedPacks.parseBagKey(key)), 1, NOW, 0, 0, math.random)
	checkSame(4, 2, 123, ghost :: number, scale :: number, plant, "bag seed")
	-- an old key: one seed moves to a key with a gene, and that is the one shown and planted
	key, zone, rarity, mutation, ghost, scale = PlantGhosts.bagPreview(bag, "6:4:Gold", function()
		return 0.5
	end)
	local gene = select(4, SeedPacks.parseBagKey(key))
	H.ok(gene ~= nil, "it got a gene")
	H.ok(zone == 6 and rarity == 4 and mutation == "Gold", "the same seed")
	H.eq(bag["6:4:Gold"], 1, "one seed left the old key")
	H.eq(bag[key :: string], 1, "...for its new one")
	plant = PlantGhosts.seedPlant(6, 4, "Gold", gene, 2, NOW, 0, 0, math.random)
	checkSame(6, 4, gene, ghost :: number, scale :: number, plant, "old bag seed")
	-- no such seed
	H.eq((PlantGhosts.bagPreview(bag, "1:1#5", math.random)), nil)
	H.eq((PlantGhosts.bagPreview(bag, "inv:3", math.random)), nil)
	H.eq((PlantGhosts.bagPreview(bag, 5, math.random)), nil)
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, "PlantGhosts.bagPreview(s.profile.seedBag, key, flowerRoll)", 1, true) ~= nil, "the Plant button uses it")
	H.ok(string.find(plot, "zone, rarity, mutation, gene = SeedPacks.parseBagKey(bagKey)", 1, true) ~= nil, "planting from the bag uses the key's gene")
	H.ok(string.find(plot, "s.carry.zone, s.carry.rarity, s.carry.mutation, s.carry.gene", 1, true) ~= nil, "planting the carried seed uses its gene")
	H.ok(string.find(plot, "PlantGhosts.plantLook(plant, now)", 1, true) ~= nil, "an inventory plant shows its own look")
end)

H.test("seeds: a pack's seed has a gene", function()
	local Shop = H.server("Shop")
	local p = ProfileStore.defaultProfile()
	local product
	for name, entry in Config.DEVELOPER_PRODUCTS do
		if entry.kind == "Pack" then
			product = name
			break
		end
	end
	local _, _, grant = Shop.processReceipt(p, product, "gene-1", 0, function()
		return 0.37
	end, function()
		return true
	end)
	H.ok(grant and grant.roll, "granted")
	local key = next(p.seedBag)
	H.ok(select(4, SeedPacks.parseBagKey(key)) ~= nil, `{key} has a gene`)
	H.ok(not string.find(grant.roll.name, "#", 1, true), "the reveal never shows it")
end)

----------------------------------------------------------------------------------------------------
-- Ghosts
----------------------------------------------------------------------------------------------------
H.test("planting ghosts: one silhouette per flower, built when first needed, plain parts only", function()
	local folder = roblox.Instance.new("Folder")
	PlantGhosts.publish(folder)
	local ghosts = folder:FindFirstChild(PlantGhosts.FOLDER)
	H.ok(ghosts ~= nil and #ghosts:GetChildren() == 0, "an empty folder at start (nothing replicates until a seed needs it)")
	local parts, models = 0, 0
	withoutScaleTo(function()
		for zone in Config.ZONES do
			for rarity in Config.RARITIES do
				for i = 1, PlantGhosts.count(zone, rarity) do
					local ghost = PlantGhosts.ensure(zone, rarity, i)
					H.ok(ghost and ghost:IsA("Model") and ghost.Parent == ghosts, `{zone}x{rarity}#{i}: a ghost`)
					H.eq(ghost.Name, PlantGhosts.name(zone, rarity, i))
					H.eq(PlantGhosts.ensure(zone, rarity, i), ghost, "built once")
					H.eq(ghost:GetAttribute("Scale"), 1, "at plant scale 1 (the client scales it)")
					models += 1
					for _, d in ghost:GetDescendants() do
						if d:IsA("BasePart") then
							parts += 1
							H.ok(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch and not d.CastShadow, `{d:GetFullName()}: inert`)
						else
							H.ok(d:IsA("Model") or d:IsA("SpecialMesh") or d:IsA("Attachment") or d:IsA("WeldConstraint") or d:IsA("Weld")
								or d:IsA("Motor6D") or d:IsA("Bone"), `{d:GetFullName()}: no {d.ClassName} on a ghost`)
						end
					end
				end
			end
		end
	end)
	print(`        planting ghosts: {models} flowers, {parts} parts if every one is in play`)
	H.ok(parts / models < 60, "each ghost is light")
	local client = fs.readFile("src/client/Planting.client.luau")
	H.ok(string.find(client, "folder:FindFirstChild(`Ghost_{zone}_{rarity}_{ghost}`)", 1, true) ~= nil, "the client clones the seed's own flower")
	H.ok(string.find(client, "model:ScaleTo(model:GetScale() * math.clamp(scale, 0.1, 4))", 1, true) ~= nil, "at the size the server says")
	H.ok(not string.find(client, "\"Disc\"", 1, true), "no flat disc")
	local main = fs.readFile("src/server/Main.server.luau")
	H.ok(string.find(main, "task.spawn(PlantGhosts.publish)", 1, true) ~= nil, "published at start")
end)

----------------------------------------------------------------------------------------------------
-- Pods: name tags in every path, no glow, the carry, the bag on arrival
----------------------------------------------------------------------------------------------------
local Net = H.stubServer("Net", { StatsUpdate = { FireClient = function() end }, LootEvent = { FireClient = function() end }, toast = function() end })
Net.announce = Net.announce or function() end
local Sessions = H.server("Sessions")
local SeedService = H.server("SeedService")
local Assets = H.server("Assets")
local SpeedLogic = H.server("SpeedLogic")

-- Puts the thief's root at `at`, where the server's movement check has seen it (SpeedService.trustedRoot):
-- they walked there.
local function arrive(s: any, at: Vector3)
	s.player.Character:FindFirstChild("HumanoidRootPart").CFrame = roblox.CFrame.new(at)
	SpeedLogic.teleported(s.tracker, at)
	s.tracker.at = os.clock()
end

local function nestInfos(): { any }
	local infos = {}
	for k in Config.ZONES do
		local model = roblox.Instance.new("Model")
		model.Name = "Nest_" .. k
		model.Parent = H.workspace
		local pods = {}
		for i = 1, Config.PODS_PER_NEST do
			pods[i] = roblox.CFrame.new(Config.nestCenter(k) + Config.podOffset(k, i))
		end
		infos[k] = { zone = k, model = model, center = Config.nestCenter(k), podCFrames = pods, guardHome = Config.nestCenter(k) }
	end
	return infos
end

local function thief(at: Vector3): (any, any)
	local char = roblox.Instance.new("Model")
	char.Name = "Thief"
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = roblox.CFrame.new(at)
	root.Parent = char
	local torso = roblox.Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.CFrame = roblox.CFrame.new(at)
	torso.Parent = char
	local hum = roblox.Instance.new("Humanoid")
	hum.Health = 100
	hum.Parent = char
	local player = { Name = "Thief", UserId = math.random(1, 1e9), DisplayName = "Thief", Character = char, Parent = nil }
	local s = Sessions.create(player :: any, ProfileStore.defaultProfile(), false)
	arrive(s, at)
	return player, s
end

-- Every pod shown has its seed's look (no Neon, no light), its prompt and an enabled, non-empty name tag
-- that draws over everything; every pod hidden has none.
local function checkPods(label: string)
	for k in Config.ZONES do
		for i, pod in SeedService.pods(k) do
			local where = `{label}: zone {k} pod {i}`
			local shown = pod.part.Transparency < 1 or pod.part:FindFirstChild("SeedModel") ~= nil
			H.eq(shown, pod.available, `{where}: seen exactly when it can be stolen`)
			H.eq(pod.gui.Enabled, pod.available, `{where}: its name tag with it`)
			H.eq(pod.prompt.Enabled, pod.available, `{where}: its prompt with it`)
			if pod.available then
				H.ok(pod.label.Text ~= "" and pod.label.Text == SeedService.seedName(k, pod.rarity, pod.mutation), `{where}: says "{pod.label.Text}"`)
				H.ok(pod.gui.AlwaysOnTop, `{where}: never hidden behind the boss or another pod`)
				H.ok(pod.label.Parent:FindFirstChild("Shadow") ~= nil and pod.label.Parent.Shadow.Text == pod.label.Text, `{where}: relief text`)
				H.eq(pod.label.Text, pod.prompt.ObjectText, `{where}: the tag says what the prompt says`)
				-- exactly one tag on the pod (its seed model brings none), hanging on the pod's own spot, just
				-- over the top of this pod's own seed
				local guis = {}
				for _, d in pod.part:GetDescendants() do
					if d:IsA("BillboardGui") then
						table.insert(guis, d)
					end
				end
				H.ok(#guis == 1 and guis[1] == pod.gui and pod.gui.Enabled, `{where}: one enabled tag ({#guis})`)
				local spot = pod.gui.Adornee
				H.ok(spot ~= nil and spot:IsA("Attachment") and spot.Parent == pod.part, `{where}: hung on its own pod`)
				local model = pod.part:FindFirstChild("SeedModel")
				H.ok(model ~= nil, `{where}: shows its Seed_ model`)
				local _, hi = Assets.bounds(model, pod.part.CFrame)
				local top = hi.Y
				local over = spot.CFrame.Position.Y - top
				H.ok(math.abs(spot.CFrame.Position.X) < 1e-4 and math.abs(spot.CFrame.Position.Z) < 1e-4 and pod.gui.StudsOffsetWorldSpace.Magnitude < 1e-4,
					`{where}: straight over its seed`)
				H.ok(over >= SeedService.LABEL_GAP - 1e-4 and over <= SeedService.LABEL_GAP + SeedService.LABEL_STAGGER + 1e-4,
					`{where}: just over its seed's top ({over} studs)`)
			end
			H.ok(pod.part.Material ~= Enum.Material.Neon and pod.part:FindFirstChildWhichIsA("Light") == nil, `{where}: no glow`)
			if pod.available then
				H.eq(pod.part:GetAttribute("Design"), SeedService.designOf(k, pod.gene), `{where}: its gene's design`)
				for _, d in pod.part:GetDescendants() do
					H.ok(not d:IsA("Light") and not d:IsA("ParticleEmitter") and not (d:IsA("BasePart") and d.Material == Enum.Material.Neon),
						`{where}: no glow on {d:GetFullName()}`)
				end
			end
		end
	end
end

H.test("pods: every visible pod has its name tag, from the start and after every path", function()
	SeedService.buildPods(nestInfos())
	checkPods("at start")
	-- Owner playtest: 3 "Common Seed" tags floated together far up while the pod in front (its prompt
	-- "Epic Seed") had none: the tags hung 3-4.65 studs over the pods' centres, at about the camera's height,
	-- so they drew near the horizon over the far scenery. Now each hangs low, over its own seed, and no two
	-- pods' tags are in the same spot. (With the owner's seed models: assets/Seed_<Zone>.)
	for k in Config.ZONES do
		H.ok(SeedService.designCount(k) > 0, `zone {k} uses its Seed_ models`)
		local pods = SeedService.pods(k)
		for i, pod in pods do
			local at = (pod.part.CFrame * pod.gui.Adornee.CFrame).Position
			H.ok(at.Y - pod.part.CFrame.Position.Y <= pod.part.Size.Y / 2 + SeedService.LABEL_GAP + SeedService.LABEL_STAGGER + 1e-4,
				`zone {k} pod {i}: its tag is low, just over the seed`)
			for j = i + 1, #pods do
				local other = (pods[j].part.CFrame * pods[j].gui.Adornee.CFrame).Position
				H.ok((other - at).Magnitude > 1, `zone {k}: pods {i} and {j} have their tags apart`)
				local d = pods[j].part.CFrame.Position - pod.part.CFrame.Position
				if Vector3.new(d.X, 0, d.Z).Magnitude < 4 then
					H.ok(math.abs(other.Y - at.Y) >= SeedService.LABEL_STAGGER - 1e-4, `zone {k}: pods {i} and {j} are close: their tags at different heights`)
				end
			end
		end
	end

	local function stealFrom(zone: number, i: number): (any, any, any)
		local pod = SeedService.pods(zone)[i]
		local player, s = thief(pod.part.CFrame.Position + Vector3.new(2, 0, 0))
		local gene, rarity = pod.gene, pod.rarity
		local design = pod.part:GetAttribute("Design")
		SeedService.steal(player, zone, i)
		H.ok(s.carry ~= nil, "stolen")
		H.eq(s.carry.gene, gene, "the carry keeps the pod's gene")
		local seed = s.carry.model and s.carry.model:FindFirstChild("Seed")
		H.ok(seed ~= nil and seed:FindFirstChild("SeedModel") ~= nil, "the seed on the thief's back")
		H.eq(seed:GetAttribute("Design"), design, "the carried seed looks like its pod's")
		for _, d in seed:FindFirstChild("SeedModel"):GetDescendants() do
			if d:IsA("BasePart") then
				H.ok(not d.Anchored and d.Massless and not d.CanCollide and not d.CanQuery, `{d.Name}: welded, massless, never in the way`)
				H.ok(d:FindFirstChildWhichIsA("WeldConstraint") ~= nil, `{d.Name}: welded to the seed`)
			end
		end
		local ghost, scale = PlantGhosts.seedLook(zone, rarity, gene)
		H.ok(s.carry.ghost == ghost and s.carry.scale == scale, "and what its ghost shows")
		H.ok(not pod.available, "the pod is hidden")
		checkPods("stolen")
		return player, s, pod
	end

	-- stolen -> returned (caught, died, left): back with the same seed
	local player, s, pod = stealFrom(2, 1)
	local gene = s.carry.gene
	SeedService.returnCarry(player)
	H.ok(pod.available and pod.gene == gene, "back in its pod, gene and all")
	checkPods("returned")
	Sessions.remove(player)

	-- stolen -> planted -> regrown
	player, s, pod = stealFrom(3, 2)
	local carry = SeedService.consumeCarry(player)
	H.ok(carry ~= nil and not pod.available)
	local plant = PlantGhosts.seedPlant(carry.zone, carry.rarity, carry.mutation, carry.gene, 1, NOW, 0, 0, math.random)
	checkSame(carry.zone, carry.rarity, carry.gene, carry.ghost, carry.scale, plant, "carried seed")
	checkPods("planted")
	H.runDelayed()
	H.ok(pod.available, "regrown")
	checkPods("regrown after planting")
	Sessions.remove(player)

	-- stolen -> stored on arrival -> regrown
	player, s, pod = stealFrom(4, 3)
	carry = s.carry
	arrive(s, Vector3.new(Config.CORRIDOR_START_X - 1, 3, 0))
	H.ok(SeedService.storeCarried(player), "stored on arrival")
	local key = SeedPacks.bagKey(carry.zone, carry.rarity, carry.mutation, carry.gene)
	H.eq(s.profile.seedBag[key], 1, "in the bag with its gene")
	local _, _, _, _, ghost, scale = PlantGhosts.bagPreview(s.profile.seedBag, key, math.random)
	H.ok(ghost == carry.ghost and scale == carry.scale, "the bag shows the same ghost as the carry did")
	checkPods("stored")
	H.runDelayed()
	checkPods("regrown after storing")
	Sessions.remove(player)

	-- a stale regrow (the seed came back first) never touches a shown pod
	player, s, pod = stealFrom(5, 4)
	SeedService.consumeCarry(player)
	pod.regrowToken += 1 -- (as returnCarry would)
	H.runDelayed()
	H.ok(not pod.available, "a stale regrow does nothing")
	Sessions.remove(player)
end)

-- Runs only the queued task.delay callbacks of exactly `seconds` (the others stay queued).
local function runTimers(seconds: number): number
	local keep, run = {}, {}
	for _, d in H.delayed do
		table.insert(if d.seconds == seconds then run else keep, d)
	end
	H.delayed = keep
	for _, d in run do
		d.fn(table.unpack(d.args, 1, d.args.n))
	end
	return #run
end

H.test("pods: an untouched pod re-rolls after POD_REFRESH (each on its own clock); a stolen one doesn't", function()
	H.ok(Config.POD_REFRESH == 180, "3 minutes")
	H.delayed = {}
	SeedService.buildPods(nestInfos())
	local pods = SeedService.pods(1)
	H.eq(runTimers(Config.POD_REFRESH), #Config.ZONES * Config.PODS_PER_NEST, "one clock per pod, started when its seed appeared")
	-- (every pod re-rolled once: its seed is new and its next clock is running)
	checkPods("refreshed")
	for i, pod in pods do
		H.eq(pod.part:GetAttribute("Roll"), 2, `pod {i}: re-rolled once (the client pops it)`)
		H.eq(pod.label.Text, pod.prompt.ObjectText, `pod {i}: tag and prompt changed together`)
	end
	-- a fresh roll really is fresh: over a few refreshes the genes change
	local genes = {}
	for _ = 1, 4 do
		for _, pod in pods do
			genes[pod.gene] = true
		end
		runTimers(Config.POD_REFRESH)
	end
	local n = 0
	for _ in genes do
		n += 1
	end
	H.ok(n > Config.PODS_PER_NEST, "new seeds (genes) after refreshes")

	-- stolen: its clock stops; nothing changes while it is carried
	local pod = pods[2]
	local player, s = thief(pod.part.CFrame.Position + Vector3.new(2, 0, 0))
	SeedService.steal(player, 1, 2)
	H.ok(s.carry ~= nil and not pod.available, "stolen")
	local roll = pod.part:GetAttribute("Roll")
	runTimers(Config.POD_REFRESH)
	H.ok(not pod.available and pod.part:GetAttribute("Roll") == roll, "a stolen pod doesn't re-roll")
	-- back (caught): the same seed, its clock starts again
	local gene = s.carry.gene
	SeedService.returnCarry(player)
	H.ok(pod.available and pod.gene == gene, "back with its seed")
	H.eq(pod.label.Text, pod.prompt.ObjectText)
	runTimers(Config.POD_REFRESH)
	H.ok(pod.available and pod.part:GetAttribute("Roll") == roll + 2, "then re-rolls on its own clock")
	Sessions.remove(player)

	-- planted: only the regrow runs (no stale refresh flips it early), then its clock starts
	player, s = thief(pod.part.CFrame.Position + Vector3.new(2, 0, 0))
	SeedService.steal(player, 1, 2)
	SeedService.consumeCarry(player)
	runTimers(Config.POD_REFRESH)
	H.ok(not pod.available, "an old refresh clock never regrows a planted pod early")
	H.ok(runTimers(Config.POD_REGROW) == 1, "its regrow")
	H.ok(pod.available, "regrown")
	H.eq(pod.label.Text, pod.prompt.ObjectText)
	Sessions.remove(player)
	H.delayed = {}
end)

H.test("2x Luck: the pickup says when the thief's luck raised the seed (the client shows Lucky! Rare > Epic)", function()
	local source = fs.readFile("src/server/SeedService.luau")
	H.ok(string.find(source, "shown = pod.rarity", 1, true) ~= nil, "the Pickup event carries what the pod showed")
	local effects = fs.readFile("src/client/Effects.client.luau")
	H.ok(string.find(effects, "data.shown", 1, true) ~= nil and string.find(effects, "Lucky!", 1, true) ~= nil,
		"Effects.client shows Lucky! when the seed came out rarer than its pod said")
	-- the draw is fixed per (seed gene, thief)
	H.eq(SeedService.luckRoll(77, 4242), SeedService.luckRoll(77, 4242))
end)

-- The bought seeds each zone uses (tools/export_seeds.luau's list): "Apple Seed", ...
local function exportedTools(): { { string } }
	local source = fs.readFile("tools/export_seeds.luau")
	local zones = {}
	for list in string.gmatch(source, "tools = (%b{})") do
		local names = {}
		for name in string.gmatch(list, "\"([^\"]+)\"") do
			table.insert(names, name)
		end
		table.insert(zones, names)
	end
	return zones
end

H.test("seed designs: every zone has 2 of the owner's seeds, with no scripts or glow, and no design is used by two zones", function()
	local Assets = H.server("Assets")
	local tools = exportedTools()
	H.eq(#tools, #Config.ZONES, "a pair for every zone")
	local usedBy: { [string]: number } = {}
	for k, names in tools do
		H.eq(#names, 2, `{Config.ZONES[k].id}: 2 designs`)
		for _, name in names do
			H.ok(usedBy[name] == nil, `{name} is used by zones {usedBy[name]} and {k}`)
			usedBy[name] = k
		end
	end
	local fingerprints: { [string]: string } = {}
	for k, zone in Config.ZONES do
		local slot = Assets.seedSlot(k)
		H.eq(slot, "Seed_" .. zone.id)
		H.ok(table.find(Assets.SLOTS, slot) ~= nil, `{slot} is an asset slot`)
		local folder = H.assets:FindFirstChild(slot)
		H.ok(folder ~= nil and folder:IsA("Folder"), `assets/{slot}.rbxm is there`)
		H.eq(SeedService.designCount(k), 2, `{zone.id}: 2 designs load`)
		for _, design in folder:GetChildren() do
			H.ok(design:IsA("Model") and string.match(design.Name, "^Design%d$") ~= nil, `{slot}/{design.Name}: a design, never a fruit's name`)
			local parts = {}
			for _, d in design:GetDescendants() do
				H.ok(not d:IsA("LuaSourceContainer"), `{d:GetFullName()}: no scripts`)
				H.ok(not d:IsA("Light") and not d:IsA("ParticleEmitter") and not d:IsA("Tool"), `{d:GetFullName()}: no {d.ClassName}`)
				for name in usedBy do
					H.ok(not string.find(d.Name, (string.gsub(name, " Seed$", "")), 1, true), `{d:GetFullName()} is named after a fruit`)
				end
				if d:IsA("BasePart") then
					H.ok(d.Material ~= Enum.Material.Neon and d.Transparency < 1, `{d:GetFullName()}: visible, not Neon`)
					H.ok(d.Anchored and not d.CanCollide and not d.CanQuery, `{d:GetFullName()}: anchored, never in the way`)
					table.insert(parts, string.format("%s %.2f %.2f %.2f %s", d.ClassName, d.Size.X, d.Size.Y, d.Size.Z, d.Color:ToHex()))
				end
			end
			H.ok(#parts > 0, `{slot}/{design.Name}: has parts`)
			table.sort(parts)
			local print = table.concat(parts, ";")
			H.ok(fingerprints[print] == nil, `{slot}/{design.Name} is the same model as {fingerprints[print]}`)
			fingerprints[print] = `{slot}/{design.Name}`
		end
	end
	local n = 0
	for _ in fingerprints do
		n += 1
	end
	H.eq(n, 2 * #Config.ZONES, "14 different designs")
	H.ok(fs.isFile("models/seeds/PlantsByLoxsy.rbxm"), "the bought file is kept in the repo")
end)

H.test("seed designs: the gene picks one of the zone's 2, whatever the rarity; the ball when a zone has none", function()
	for k in Config.ZONES do
		local seen, ones = {}, 0
		for gene = 1, 400 do
			local design = SeedService.designOf(k, gene)
			H.ok(design == 1 or design == 2, "one of the 2")
			seen[design] = true
			ones += if design == 1 then 1 else 0
		end
		H.ok(seen[1] and seen[2], `zone {k}: both designs come up`)
		H.ok(ones > 120 and ones < 280, `zone {k}: about evenly ({ones}/400)`)
	end
	-- independent of the flower: every (flower, design) pair comes up
	local pairs = {}
	for gene = 1, 600 do
		pairs[`{PlantGhosts.indexOf(1, 1, gene)}:{SeedService.designOf(1, gene)}`] = true
	end
	for i = 1, PlantGhosts.count(1, 1) do
		H.ok(pairs[`{i}:1`] and pairs[`{i}:2`], `flower {i} with either design`)
	end
	-- the same gene looks the same as a Common and as a Legendary
	local a, b = roblox.Instance.new("Part"), roblox.Instance.new("Part")
	for _, p in { a, b } do
		p.Size = Vector3.one * 3
		p.Anchored = true
	end
	for gene = 1, 20 do
		SeedService.seedLook(a, 4, 1, nil, gene)
		SeedService.seedLook(b, 4, 5, "Gold", gene)
		H.eq(a:GetAttribute("Design"), b:GetAttribute("Design"), `gene {gene}: rarity never changes the design`)
		H.eq(a.Transparency, 1, "the ball hides behind the design")
	end
	local count = 0
	for _, c in a:GetChildren() do
		count += if c.Name == "SeedModel" then 1 else 0
	end
	H.eq(count, 1, "re-dressing replaces the design")
	H.eq(SeedService.designOf(4, nil), 1, "a seed from before genes: the first design")
	-- the hotbar's icons: every design, published for the client
	local looks = SeedService.publishLooks(roblox.Instance.new("Folder"))
	for k in Config.ZONES do
		local zoneLooks = looks:FindFirstChild(tostring(k))
		H.ok(zoneLooks and zoneLooks:FindFirstChild("1") and zoneLooks:FindFirstChild("2"), `zone {k}'s designs for the hotbar`)
	end
	-- no file for the zone: a plain ball in the seed colour, no glow
	H.withoutAssets("Seed_", function()
		local part = roblox.Instance.new("Part")
		part.Size = Vector3.one * 3
		part.Anchored = true
		local light = roblox.Instance.new("PointLight")
		light.Parent = part
		part.Material = Enum.Material.Neon
		H.eq(SeedService.seedLook(part, 2, 3, nil, 77), nil, "no model: the ball")
		H.eq(part.Color, Config.ZONES[2].seedColor)
		H.eq(part.Material, Enum.Material.SmoothPlastic, "not Neon")
		H.eq(part:FindFirstChildWhichIsA("Light"), nil, "no light")
		H.eq(part.Transparency, 0)
		SeedService.seedLook(part, 2, 3, "Gold", 77)
		H.eq(part.Color, Config.mutationById("Gold").color, "a mutation's colour")
	end)
	local source = fs.readFile("src/server/SeedService.luau")
	H.ok(not string.find(source, "Instance.new(\"PointLight\")", 1, true), "no PointLight is made")
	H.ok(not string.find(source, "Material = Enum.Material.Neon", 1, true), "nothing is made Neon")
end)

----------------------------------------------------------------------------------------------------
-- Labels never name the flower before it is planted
----------------------------------------------------------------------------------------------------
H.test("seeds: no label says the flower before it is planted", function()
	local flowers = allFlowers()
	local Format = H.shared("Format")
	for k in Config.ZONES do
		for r in Config.RARITIES do
			for _, mut in { nil, "Gold" } :: { string? } do
				local name = SeedPacks.seedName(k, r, mut)
				for _, flower in flowers do
					H.ok(not string.find(name, flower, 1, true) and not string.find(name, Format.plantName(flower), 1, true), `"{name}" names {flower}`)
				end
				H.ok(not string.find(name, "#", 1, true), "never the gene")
			end
		end
	end
	-- what the client is told about a seed: its look (a ghost number and a size), never its flower
	local sessions = fs.readFile("src/server/Sessions.luau")
	H.ok(string.find(sessions, "{ zone = c.zone, rarity = c.rarity, mutation = c.mutation, ghost = c.ghost, scale = c.scale }", 1, true) ~= nil,
		"the carry view")
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, "key = seedKey, zone = zone, rarity = rarity, name = SeedService.seedName(zone, rarity, mutation), ghost = ghost, scale = scale", 1, true) ~= nil,
		"a bag seed's preview is called by its seed name")
	local hud = fs.readFile("src/client/HUD.client.luau")
	H.ok(string.find(hud, "byLabel[SeedPacks.labelKey(key)]", 1, true) ~= nil, "the Inventory lists seeds by label, not by gene")
	H.ok(string.find(fs.readFile("src/client/Planting.client.luau"), "reveal(data.name, data.pos,", 1, true) ~= nil, "named when planted (the reveal)")
end)

----------------------------------------------------------------------------------------------------
-- The hotbar's seed slot
----------------------------------------------------------------------------------------------------
H.test("hotbar: slot 2 is the seed bag; 2 or a tap plants the latest seed, 2 again or Q puts it back", function()
	local hud = fs.readFile("src/client/HUD.client.luau")
	H.ok(string.find(hud, "Name = \"Hotbar\"", 1, true) ~= nil, "the HUD's hotbar can be found")
	H.ok(string.find(hud, "SortOrder = Enum.SortOrder.LayoutOrder", 1, true) ~= nil and string.find(hud, "batSlot.LayoutOrder = 1", 1, true) ~= nil,
		"the Bat stays slot 1")
	H.ok(string.find(hud, "if input.KeyCode == Enum.KeyCode.One then", 1, true) ~= nil, "1 is the Bat")
	local client = fs.readFile("src/client/Planting.client.luau")
	for _, needle in {
		"seedSlot.Name = \"SeedSlot\"",
		"seedSlot.LayoutOrder = 2",
		"hud:WaitForChild(\"Hotbar\", 30)", -- in the HUD's hotbar
		"elseif input.KeyCode == Enum.KeyCode.Two then", -- 2
		"seedSlot.Activated:Connect(useSeedSlot)", -- a tap
		"RequestUseItem:FireServer(\"Seed:\" .. recent[#recent])", -- the same planting flow as the Inventory's Plant button
		"stopBag() -- 2 again: put it back",
		"elseif input.KeyCode == Enum.KeyCode.Q and bag then", -- Q
		"Icons.set(slotLabel, \"Seeds\"",
		"UiFx.relief(slotCount, 2, 2)", -- relief text
	} do
		H.ok(string.find(client, needle, 1, true) ~= nil, needle)
	end
	H.ok(string.find(client, "local BAG_FULL = \"Seed bag full: plant or sell to make room for your seed!\"", 1, true) ~= nil,
		"a seed stuck on your back in the base says why")
	local shop = fs.readFile("src/server/ShopService.luau")
	H.ok(string.find(shop, "PlotService.plantFromBag", 1, true) ~= nil, "\"Seed:<key>\" opens the planting preview")
end)

return nil
