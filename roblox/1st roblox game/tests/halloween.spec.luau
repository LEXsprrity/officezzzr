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

H.test("halloween: candy for a seed brought home grows with its zone; prices grow with the zone", function()
	for k = 1, #Config.ZONES do
		H.eq(Halloween.stealCandy(k), k)
		if k > 1 then
			H.ok(Halloween.price(k) > Halloween.price(k - 1), `zone {k} costs more`)
		end
	end
	-- a new player's first Haunted seed (the Meadow) after about 7 minutes and a few Meadow steals
	H.ok(Halloween.price(1) <= 7 * Halloween.CANDY_PER_MINUTE + 3 * Halloween.stealCandy(1), "the first one comes quickly")
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
	p.candy = Halloween.price(3) + 4
	local ok, msg, roll, pack = Shop.buyHaunted(p, 3, DURING, seeded(1))
	H.ok(ok, msg)
	H.eq(p.candy, 4)
	H.eq(roll.zone, 3)
	H.eq(roll.mutation, Halloween.MUTATION)
	H.eq(pack.id, "Haunted:Jungle")
	H.eq(SeedPacks.bagCount(p.seedBag), 1)
	local key = next(p.seedBag)
	local z, r, m = SeedPacks.parseBagKey(key)
	H.ok(z == 3 and r == roll.rarity and m == Halloween.MUTATION, "a plantable Haunted bag key")
end)

H.test("halloween: a Haunted seed is refused after the event, without candy, past the Speed, or with a full bag", function()
	local function fresh()
		local p = ProfileStore.defaultProfile()
		p.speed = Config.ZONES[2].req
		p.candy = 1000
		return p
	end
	local p = fresh()
	H.ok(not Shop.buyHaunted(p, 1, AFTER, seeded(1)), "over")
	H.ok(not Shop.buyHaunted(p, 3, DURING, seeded(1)), "zone 3 needs its Speed")
	for _, bad in { 0, 8, 1.5, "1", nil } do
		H.ok(not Shop.buyHaunted(p, bad, DURING, seeded(1)), `junk zone {bad}`)
	end
	H.eq(p.candy, 1000, "nothing spent")
	p.candy = Halloween.price(2) - 1
	H.ok(not Shop.buyHaunted(p, 2, DURING, seeded(1)), "not enough candy")
	H.eq(p.candy, Halloween.price(2) - 1)
	p = fresh()
	p.seedBag["1:1"] = Config.SEED_BAG_MAX
	H.ok(not Shop.buyHaunted(p, 1, DURING, seeded(1)), "bag full")
	H.eq(p.candy, 1000)
	H.ok(Shop.buyHaunted(fresh(), 1, DURING, seeded(1)), "a lower zone is fine")
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

H.test("halloween: the server pays candy per minute and per seed brought home, only during the event", function()
	local seeds = fs.readFile("src/server/SeedService.luau")
	H.ok(string.find(seeds, "Halloween.active(os.time())", 1, true) ~= nil, "consumeCarry checks the event")
	H.ok(string.find(seeds, "Halloween.stealCandy(carry.zone)", 1, true) ~= nil, "the zone's candy")
	local main = fs.readFile("src/server/Main.server.luau")
	H.ok(string.find(main, "Halloween.CANDY_PER_MINUTE", 1, true) ~= nil, "the minute loop")
	local shop = fs.readFile("src/server/ShopService.luau")
	H.ok(string.find(shop, "Shop.buyHaunted(s.profile", 1, true) ~= nil, "Candy: requests go through Shop.buyHaunted")
end)
