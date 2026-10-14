-- The plant inventory (owner requests): Remove takes a plant off the plot into it, as it was (never money);
-- from there it is planted again (same flower, mutation and weight) or sold at the SELL stall; a seed
-- brought home while the plot is full goes to the seed bag by itself. The planting preview's 3D ghosts.
-- Inventory and Selling are pure; SeedService.storeCarried runs with a stand-in player.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")
local ProfileStore = H.server("ProfileStore")
local Inventory = H.server("Inventory")
local Selling = H.server("Selling")

local Vector3 = H.Vector3
local NOW = 1_800_000_000
local NEAR = 5 -- studs from the SELL stall

local function plant(slot: number, zone: number, rarity: number, age: number, mutation: string?, variant: string?): ProfileStore.Plant
	return { slot = slot, zone = zone, rarity = rarity, mutation = mutation, plantedAt = NOW - age, x = 1, z = 2, variant = variant }
end

local function weightOf(p: ProfileStore.Plant, now: number): number
	return Config.plantWeight(p.zone, p.rarity, now - p.plantedAt, Config.varianceOf(p))
end

H.test("inventory: Remove takes your plant off the plot into the inventory as it was, for no money", function()
	local profile = ProfileStore.defaultProfile()
	profile.money = 1000
	profile.plants = { plant(1, 2, 3, 600, nil, "SolarIris"), plant(2, 6, 4, 5000, "Gold", "LaVaca") }
	local gold = profile.plants[2]
	local before = weightOf(gold, NOW)
	local entry = Inventory.take(profile, 2, NOW)
	H.ok(entry ~= nil, "taken")
	H.eq(profile.money, 1000, "no money (Remove never sells)")
	H.eq(#profile.plants, 1, "off the plot")
	H.eq(profile.plants[1].slot, 1)
	H.eq(#profile.inventory, 1, "in the inventory")
	local e = entry :: ProfileStore.InvPlant
	H.eq(e.zone, 6)
	H.eq(e.rarity, 4)
	H.eq(e.mutation, "Gold", "its mutation")
	H.eq(e.variant, "LaVaca", "its flower")
	H.eq(e.age, Config.GROW_TIME, "its growth (full-grown: capped)")
	H.near(Inventory.weight(e), before, before * 1e-9, "its weight")
	-- its growth stops while it waits
	H.near(Inventory.weight(e), Inventory.weight(Inventory.find(profile, e.id) :: any), 1e-9)
	-- refused: not yours, not a slot; nothing changes
	for _, bad in { 5, "1", 1.5, 0 / 0, math.huge, {}, true } :: { any } do
		local got, why = Inventory.take(profile, bad, NOW)
		H.eq(got, nil, `slot {tostring(bad)}`)
		H.ok(why == "none" or why == "bad", `slot {tostring(bad)}: {why}`)
	end
	H.eq(#profile.plants, 1)
	H.eq(#profile.inventory, 1)
	-- a young plant keeps its age
	local young = Inventory.take(profile, 1, NOW) :: ProfileStore.InvPlant
	H.eq(young.age, 600)
	H.ok(young.id ~= e.id, "ids stay unique")
end)

H.test("inventory: at most INVENTORY_MAX plants; a full inventory refuses Remove and keeps the plant planted", function()
	H.eq(Config.INVENTORY_MAX, 50)
	local profile = ProfileStore.defaultProfile()
	for i = 1, Config.INVENTORY_MAX + 1 do
		table.insert(profile.plants, plant(i, 1, 1, 60))
	end
	for i = 1, Config.INVENTORY_MAX do
		H.ok(Inventory.take(profile, i, NOW) ~= nil, `plant {i}`)
	end
	H.ok(Inventory.isFull(profile))
	local got, why = Inventory.take(profile, Config.INVENTORY_MAX + 1, NOW)
	H.eq(got, nil)
	H.eq(why, "full")
	H.eq(#profile.plants, 1, "still planted")
	H.eq(#profile.inventory, Config.INVENTORY_MAX)
end)

H.test("inventory: planted again, a plant keeps its flower, mutation and weight, and grows on", function()
	local profile = ProfileStore.defaultProfile()
	local original = plant(7, 4, 2, 300, "Rainbow", "RedStar")
	profile.plants = { original }
	local before = weightOf(original, NOW)
	local entry = Inventory.take(profile, 7, NOW) :: ProfileStore.InvPlant
	local later = NOW + 3600 -- an hour in the inventory: no growth
	local back = Inventory.toPlant(entry, 12, later, 3, -4)
	H.eq(back.slot, 12, "under a new id")
	H.eq(back.variant, "RedStar")
	H.eq(back.mutation, "Rainbow")
	H.eq(back.x, 3)
	H.eq(back.z, -4)
	H.near(weightOf(back, later), before, before * 1e-9, "the same weight as when it left")
	H.ok(weightOf(back, later + 60) > weightOf(back, later), "and it grows on from there")
	H.eq(Inventory.remove(profile, entry.id), entry)
	H.eq(#profile.inventory, 0)
	H.eq(Inventory.remove(profile, entry.id), nil, "gone: once")
	-- the planted plant keeps its variance through a save
	local p = ProfileStore.defaultProfile()
	p.plants = { back }
	local loaded = ProfileStore.deserialize(ProfileStore.serialize(p)).plants[1]
	H.near(weightOf(loaded, later), before, before * 1e-9, "saved and loaded")
end)

H.test("inventory: the SELL stall sells inventory plants at the stall price, with the planted ones", function()
	local profile = ProfileStore.defaultProfile()
	profile.money = 0
	profile.plants = { plant(1, 3, 2, 900), plant(2, 5, 1, 100, "Gold"), plant(3, 1, 1, 10) }
	local priceOnPlot = Selling.price(profile.plants[2], NOW, 2)
	local entry = Inventory.take(profile, 2, NOW) :: ProfileStore.InvPlant
	H.near(Selling.price(Inventory.asPlant(entry, NOW + 999), NOW + 999, 2), priceOnPlot, priceOnPlot * 1e-9, "the same price as on the plot")
	-- refused: too far, junk ids; nothing changes
	H.eq(select(2, Selling.sell(profile, {}, 99, NOW, 2, { entry.id })), "far")
	for _, bad in { "x", { 1.5 }, { "1" }, { [2] = 1 }, table.create(Config.INVENTORY_MAX + 1, 1) } :: { any } do
		H.eq(select(2, Selling.sell(profile, {}, NEAR, NOW, 2, bad)), "bad", `ids {tostring(bad)}`)
	end
	H.eq(select(2, Selling.sell(profile, {}, NEAR, NOW, 2, { 999 })), "none", "not in your inventory")
	H.eq(profile.money, 0)
	H.eq(#profile.inventory, 1)
	-- a plant and an inventory plant together
	local expect = Selling.price(profile.plants[1], NOW, 2) + priceOnPlot
	local sale = Selling.sell(profile, { 1 }, NEAR, NOW, 2, { entry.id, entry.id }) :: Selling.Sale
	H.ok(sale ~= nil, "sold")
	H.eq(#sale.slots, 1)
	H.eq(#sale.ids, 1, "an id named twice is sold once")
	H.near(sale.total, expect, expect * 1e-9)
	H.near(profile.money, expect, expect * 1e-9)
	H.eq(#profile.inventory, 0)
	H.eq(#profile.plants, 1, "the other plant stays")
	-- the old request (slots only) still works
	H.ok(Selling.sell(profile, { 3 }, NEAR, NOW, 1) ~= nil)
end)

H.test("inventory: saved and loaded (v9); older saves start with an empty inventory; junk is dropped", function()
	H.ok(ProfileStore.VERSION >= 9)
	local p = ProfileStore.defaultProfile()
	p.plants = { plant(1, 6, 3, 400, "Gold", "Starpetal"), plant(2, 2, 1, 50) }
	local a = Inventory.take(p, 1, NOW) :: ProfileStore.InvPlant
	local data = ProfileStore.serialize(p)
	H.eq(data.v, ProfileStore.VERSION)
	local back = ProfileStore.deserialize(data)
	H.eq(#back.inventory, 1)
	H.ok(H.deepEq(back.inventory[1], a), "every field round-trips")
	H.eq(#back.plants, 1)
	-- a v8 save: no inventory, plants without their own variance
	local v8 = { v = 8, plants = { { s = 3, z = 7, r = 4, t = NOW - 50, px = 2, pz = -3, vr = "Noctyra" } } }
	local old = ProfileStore.deserialize(v8)
	H.eq(#old.inventory, 0, "an empty inventory")
	H.eq(old.plants[1].variance, nil, "the variance from its planting time and id, as before")
	H.eq(old.plants[1].variant, "Noctyra")
	-- junk
	local junk = { v = 9, inv = {
		{ i = 1, z = 1, r = 1, a = 10, va = 1 },
		{ i = 1, z = 2, r = 2, a = 10, va = 1 }, -- the same id again
		{ i = 2, z = 0, r = 1, a = 10, va = 1 }, -- no such zone
		{ i = 3, z = 1, r = 1, a = 10, va = 7 }, -- a variance out of range
		{ i = 4, z = 1, r = 1, a = -5, va = 0.9, m = "Fake", vr = "<b>" },
		"nope",
	} }
	local j = ProfileStore.deserialize(junk)
	H.eq(#j.inventory, 2)
	H.eq(j.inventory[2].age, 0, "age clamped")
	H.eq(j.inventory[2].mutation, nil, "an unknown mutation dropped")
	H.eq(j.inventory[2].variant, nil, "a bad flower name dropped")
	local many = { v = 9, inv = {} }
	for i = 1, Config.INVENTORY_MAX + 10 do
		table.insert(many.inv, { i = i, z = 1, r = 1, a = 0, va = 1 })
	end
	H.eq(#ProfileStore.deserialize(many).inventory, Config.INVENTORY_MAX, "at most INVENTORY_MAX")
end)

H.test("inventory: a seed brought home to a full plot goes to the seed bag (pure rule)", function()
	local profile = ProfileStore.defaultProfile()
	for i = 1, 5 do
		table.insert(profile.plants, plant(i, 1, 1, 60))
	end
	H.eq(Inventory.carryHome(profile, 5, false), "away", "still in the corridor")
	H.eq(Inventory.carryHome(profile, 6, true), "room", "a free slot: plant it as usual")
	H.eq(Inventory.carryHome(profile, 5, true), "store", "full plot, at home: into the bag")
	for i = 1, Config.SEED_BAG_MAX do
		SeedPacks.addToBag(profile.seedBag, 1, 1 + i % 3, nil)
	end
	H.eq(Inventory.carryHome(profile, 5, true), "bagFull", "the bag is full too: it stays carried")
	H.ok(Inventory.isHome(Vector3.new(Config.CORRIDOR_START_X - 1, 3, 0)) and not Inventory.isHome(Vector3.new(Config.CORRIDOR_START_X + 1, 3, 0)),
		"home is the base, out of the corridor")
end)

H.test("inventory: SeedService.storeCarried puts a carried seed in the bag at home with a full plot, and clears the carry", function()
	H.stubServer("Net", { StatsUpdate = { FireClient = function() end }, LootEvent = { FireClient = function() end }, toast = function() end })
	local Sessions = H.server("Sessions")
	local SeedService = H.server("SeedService")
	local function setup(plants: number, x: number): (any, any)
		local root = { Position = Vector3.new(x, 3, 0) }
		local char = {
			FindFirstChild = function(_, name: string)
				return if name == "HumanoidRootPart" then root else nil
			end,
		}
		local player = { Name = "Thief", UserId = math.random(1, 1e9), DisplayName = "Thief", Character = char, Parent = nil }
		local profile = ProfileStore.defaultProfile()
		local s = Sessions.create(player :: any, profile, false)
		for i = 1, plants do
			table.insert(profile.plants, plant(i, 1, 1, 60))
		end
		s.carry = { zone = 3, rarity = 2, mutation = "Gold", pod = 1, model = nil }
		return player, s
	end
	-- full plot, at home: in the bag, carry cleared
	local player, s = setup(Config.SLOTS_START, Config.CORRIDOR_START_X - 20)
	H.eq(Sessions.maxSlots(s), Config.SLOTS_START)
	H.ok(SeedService.storeCarried(player), "stored")
	H.eq(s.carry, nil, "no longer carried")
	H.eq(s.profile.seedBag[SeedPacks.bagKey(3, 2, "Gold")], 1, "in the bag, mutation and all")
	H.ok(not SeedService.storeCarried(player), "nothing more to store")
	Sessions.remove(player)
	-- a free slot: it stays carried for the normal planting
	player, s = setup(Config.SLOTS_START - 1, Config.CORRIDOR_START_X - 20)
	H.ok(not SeedService.storeCarried(player))
	H.ok(s.carry ~= nil, "still carried: plant it")
	H.eq(SeedPacks.bagCount(s.profile.seedBag), 0)
	Sessions.remove(player)
	-- still in the corridor
	player, s = setup(Config.SLOTS_START, Config.CORRIDOR_START_X + 50)
	H.ok(not SeedService.storeCarried(player))
	H.ok(s.carry ~= nil, "not home yet")
	Sessions.remove(player)
	-- the payout loop checks it for every plot owner
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, "pcall(SeedService.storeCarried, owner :: Player)", 1, true) ~= nil, "wired in the payout loop")
end)

H.test("inventory: the server wiring (Remove, plant from the inventory, sell ids) and the HUD's Plants / Inventory tabs", function()
	local plot = fs.readFile("src/server/PlotService.luau")
	for _, needle in {
		"Inventory.take(s.profile, slot, now)", -- Remove: into the inventory
		"local invId = inventoryId(bagKey)", -- PlantSeed with "inv:<id>"
		"Inventory.remove(s.profile, invId)",
		"plantSeed(player, s, state, x, z, zone, rarity, mutation, entry)", -- planted again as it was
		"Selling.sell(s.profile, slots, distance, now, Sessions.moneyMult(s), ids)",
		"inventory = inventory, slots = Sessions.maxSlots(s)", -- the view
	} do
		H.ok(string.find(plot, needle, 1, true) ~= nil, needle)
	end
	H.ok(not string.find(plot, "Selling.remove", 1, true) and not string.find(plot, "\"Sold\"", 1, true), "Remove pays nothing")
	H.eq(Config.SELL_SECONDS, nil, "no refund constant left")
	local shop = fs.readFile("src/server/ShopService.luau")
	H.ok(string.find(shop, "PlotService.sellPlants(player, slots, ids)", 1, true) ~= nil, "SellPlants(slots, ids)")
	local hud = fs.readFile("src/client/HUD.client.luau")
	H.ok(not string.find(hud, "renderSeeds", 1, true) and not string.find(hud, "{ \"Seeds\", \"🌱\" }", 1, true), "no Seeds menu")
	H.ok(string.find(hud, "for _, name in { \"Plants\", \"Inventory\" } do", 1, true) ~= nil, "Plants / Inventory tabs")
	H.ok(string.find(hud, "RequestUseItem:FireServer(\"Seed:\" .. key)", 1, true) ~= nil, "a Plant button per seed and inventory plant")
	H.ok(string.find(hud, "SellPlants:FireServer(slots, ids)", 1, true) ~= nil, "the Sell window sells inventory plants too")
	H.ok(string.find(hud, "\"Plot and seed bag full: plant or sell to make room for your seed!\"", 1, true) ~= nil, "a full bag is said in the panel")
	H.ok(string.find(hud, "UiFx.relief(label, 3, 3)", 1, true) ~= nil, "in relief text")
end)

H.test("planting ghosts: one silhouette per zone x rarity at full-grown size, plain parts only", function()
	local PlantGhosts = H.server("PlantGhosts")
	local CreatureModels = H.server("CreatureModels")
	local folder = roblox.Instance.new("Folder")
	local applyScale = CreatureModels.applyScale
	CreatureModels.applyScale = function(model: any, scale: number) -- (Lune has no Model:ScaleTo: just record it)
		model:SetAttribute("Scale", scale)
	end
	PlantGhosts.publish(folder)
	CreatureModels.applyScale = applyScale

	local ghosts = folder:FindFirstChild(PlantGhosts.FOLDER)
	H.ok(ghosts ~= nil, "the folder")
	local parts = 0
	for zone in Config.ZONES do
		for rarity in Config.RARITIES do
			local ghost = ghosts:FindFirstChild(PlantGhosts.name(zone, rarity))
			H.ok(ghost and ghost:IsA("Model"), `{zone}x{rarity}: a ghost`)
			H.near(ghost:GetAttribute("Scale"), PlantGhosts.fullScale(zone, rarity), 1e-6, `{zone}x{rarity}: full-grown`)
			H.ok(PlantGhosts.fullScale(zone, rarity) >= CreatureModels.scaleFor(zone, rarity, Config.sproutWeight(zone, rarity)), "bigger than a sprout")
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
	print(`        planting ghosts: {#ghosts:GetChildren()} models, {parts} parts`)
	H.ok(parts < 1500, "cheap to replicate")
	local client = fs.readFile("src/client/Planting.client.luau")
	H.ok(string.find(client, "ReplicatedStorage:FindFirstChild(\"PlantGhosts\")", 1, true) ~= nil, "the client clones them")
	H.ok(not string.find(client, "\"Disc\"", 1, true), "no flat disc")
	local main = fs.readFile("src/server/Main.server.luau")
	H.ok(string.find(main, "task.spawn(PlantGhosts.publish)", 1, true) ~= nil, "published at start")
end)

return nil
