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

H.test("halloween: candy spots lie in the corridor (off the walls, away from the nests) or on the base's walkway", function()
	local rng = seeded(3)
	local half = Config.CORRIDOR_WIDTH / 2
	for _ = 1, 2000 do
		local p = Halloween.spot(false, rng)
		H.ok(p.X > Config.CORRIDOR_START_X and p.X < Config.END_X, "in the corridor")
		H.ok(math.abs(p.Z) <= half - 12 + 1e-9, "off the walls")
		H.ok(not Halloween.nearNest(p), "away from the bosses")
	end
	local x0, x1, w = Halloween.baseRange()
	H.ok(x0 < x1 and x1 < Config.CORRIDOR_START_X and w > 0, "a walkway")
	for _ = 1, 500 do
		local p = Halloween.spot(true, rng)
		H.ok(p.X >= x0 and p.X <= x1 and math.abs(p.Z) <= w, "on the walkway")
		H.ok(math.abs(p.Z) < Config.WALKWAY_WIDTH / 2, "not in a plot")
	end
	H.ok(Halloween.nearNest(Config.nestCenter(4)), "a nest is near itself")
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
