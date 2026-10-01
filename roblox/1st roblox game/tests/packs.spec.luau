-- Seed packs: pricing, odds, rolls, featured rotation, the seed bag's save format and Robux receipts.
local serde = require("@lune/serde")
local H = require("./harness")

local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")
local Shop = H.server("Shop")
local ProfileStore = H.server("ProfileStore")

local function seeded(seed: number): () -> number
	local r = H.Random.new(seed)
	return function()
		return r:NextNumber()
	end
end

local function richPlayer()
	local p = ProfileStore.defaultProfile()
	p.money = 1e12
	p.speed = 1e10 -- every zone unlocked
	return p
end

----------------------------------------------------------------------------------------------------
-- Pricing
----------------------------------------------------------------------------------------------------
H.test("packs: one pack per zone, priced like the economy and rising by zone", function()
	local want = { 800, 40e3, 400e3, 4e6, 40e6, 400e6, 4e9 }
	for k, zone in Config.ZONES do
		local pack = SeedPacks.zonePack(k)
		H.eq(pack.id, "Pack:" .. zone.id)
		H.eq(pack.zone, k)
		H.eq(pack.price, want[k], zone.id .. " price")
		H.near(pack.price, Config.seedIncome(k) * Config.PACK_INCOME_SECONDS, pack.price * 0.05, "follows seedIncome")
		if k > 1 then
			H.ok(pack.price > SeedPacks.zonePack(k - 1).price, "prices rise with the zone")
		end
	end
end)

H.test("packs: featured pack costs FEATURED_PRICE_MULT x its zone pack (rounded)", function()
	for slot = 1000, 1020 do
		local f = SeedPacks.featuredPackForSlot(slot)
		local base = SeedPacks.zonePack(f.zone).price
		H.near(f.price, base * Config.FEATURED_PRICE_MULT, base * 0.06, "featured price")
		H.ok(f.featured and f.exclusive == Config.FEATURED_EXCLUSIVE, "has the exclusive")
	end
end)

H.test("packs: roundPrice keeps two significant figures", function()
	H.eq(SeedPacks.roundPrice(799.9999999), 800)
	H.eq(SeedPacks.roundPrice(1234), 1200)
	H.eq(SeedPacks.roundPrice(45), 45)
	H.eq(SeedPacks.roundPrice(0), 0)
end)

----------------------------------------------------------------------------------------------------
-- Odds
----------------------------------------------------------------------------------------------------
local function allPacks(): { any }
	local packs = {}
	for k = 1, #Config.ZONES do
		table.insert(packs, SeedPacks.zonePack(k))
	end
	for slot = 0, #Config.ZONES * 2 do
		table.insert(packs, SeedPacks.featuredPackForSlot(slot))
	end
	return packs
end

H.test("odds: rarity odds sum to 100% and mutations + none sum to 100% for every pack", function()
	for _, pack in allPacks() do
		local odds = SeedPacks.odds(pack)
		H.eq(#odds.rarities, #Config.RARITIES)
		local sum = 0
		for _, pct in odds.rarities do
			H.ok(pct > 0, "every rarity is possible")
			sum += pct
		end
		H.near(sum, 100, 1e-9, pack.id .. " rarities")
		local mutSum = odds.noMutation
		for _, m in odds.mutations do
			mutSum += m.pct
		end
		H.near(mutSum, 100, 1e-9, pack.id .. " mutations")
		H.ok(odds.noMutation > 50, "most seeds have no mutation")
	end
end)

H.test("odds: zone packs never show Night or the exclusive; featured packs are luckier and add it", function()
	for k = 1, #Config.ZONES do
		local zone = SeedPacks.odds(SeedPacks.zonePack(k))
		for _, m in zone.mutations do
			H.ok(m.id ~= "Night" and m.id ~= Config.FEATURED_EXCLUSIVE, "zone pack mutation " .. m.id)
		end
		local f = SeedPacks.featuredPackForSlot(0)
		f.zone = k -- same zone, featured rules
		local feat = SeedPacks.odds(f)
		H.ok(feat.rarities[#Config.RARITIES] > zone.rarities[#Config.RARITIES], "featured is luckier")
		H.eq(feat.mutations[1].id, Config.FEATURED_EXCLUSIVE)
		H.near(feat.mutations[1].pct, Config.FEATURED_EXCLUSIVE_CHANCE * 100, 1e-12, "exclusive chance")
	end
end)

H.test("odds: percent labels read well", function()
	H.eq(SeedPacks.percent(58.333), "58.3%")
	H.eq(SeedPacks.percent(40), "40%")
	H.eq(SeedPacks.percent(4), "4%")
	H.eq(SeedPacks.percent(2.5), "2.5%")
	H.eq(SeedPacks.percent(0.5), "0.5%")
	H.eq(SeedPacks.percent(0.0123), "0.012%")
end)

----------------------------------------------------------------------------------------------------
-- Rolls
----------------------------------------------------------------------------------------------------
H.test("roll: seeded RNG is reproducible and edge values stay in range", function()
	local pack = SeedPacks.zonePack(3)
	local a, b = seeded(42), seeded(42)
	for _ = 1, 200 do
		local r1, m1 = SeedPacks.roll(pack, a)
		local r2, m2 = SeedPacks.roll(pack, b)
		H.eq(r1, r2)
		H.eq(m1, m2)
	end
	local r, m = SeedPacks.roll(pack, function()
		return 0
	end)
	H.eq(r, 1, "rng 0 -> Common")
	H.eq(m, Config.MUTATIONS[1].id, "rng 0 -> first mutation")
	r, m = SeedPacks.roll(pack, function()
		return 0.999999999
	end)
	H.eq(r, #Config.RARITIES, "rng ~1 -> Legendary")
	H.eq(m, nil, "rng ~1 -> no mutation")
end)

H.test("roll: 200k seeded rolls match the displayed odds", function()
	local f = SeedPacks.featuredPackForSlot(12345)
	local odds = SeedPacks.odds(f)
	local rng = seeded(2026)
	local N = 200000
	local rarityHits, mutHits = {}, {}
	for _ = 1, N do
		local r, m = SeedPacks.roll(f, rng)
		rarityHits[r] = (rarityHits[r] or 0) + 1
		if m then
			mutHits[m] = (mutHits[m] or 0) + 1
		end
	end
	for i, pct in odds.rarities do
		local got = (rarityHits[i] or 0) / N * 100
		H.near(got, pct, math.max(0.1, pct * 0.05), `rarity {i}`)
	end
	for _, m in odds.mutations do
		local got = (mutHits[m.id] or 0) / N * 100
		H.near(got, m.pct, math.max(0.08, m.pct * 0.2), m.id)
	end
	H.ok((mutHits[Config.FEATURED_EXCLUSIVE] or 0) > 0, "the exclusive does drop")
end)

H.test("roll: pods never roll the featured exclusive", function()
	local rng = seeded(7)
	for _ = 1, 50000 do
		local _, m = Config.rollSeed(7, Config.NIGHT_LUCK, true, rng)
		H.ok(m ~= Config.FEATURED_EXCLUSIVE, "pod rolled the exclusive")
	end
end)

----------------------------------------------------------------------------------------------------
-- Featured rotation
----------------------------------------------------------------------------------------------------
H.test("featured: deterministic from the clock, changes exactly at the slot boundary", function()
	local P = Config.FEATURED_ROTATION_SECONDS
	local t = 1790000000
	local slot = SeedPacks.featuredSlot(t)
	H.eq(SeedPacks.featuredPack(t).id, SeedPacks.featuredPack(t).id, "same answer twice (any server)")
	H.ok(SeedPacks.slotEndsAt(slot) > t and SeedPacks.slotEndsAt(slot) - t <= P, "ends within one period")
	local edge = SeedPacks.slotEndsAt(slot)
	H.eq(SeedPacks.featuredSlot(edge - 0.001), slot)
	H.eq(SeedPacks.featuredSlot(edge), slot + 1)
end)

H.test("featured: every zone once per cycle, never the same zone twice in a row", function()
	local n = #Config.ZONES
	local prev = SeedPacks.featuredZone(-1)
	for slot = 0, 20000 do
		local z = SeedPacks.featuredZone(slot)
		H.ok(z >= 1 and z <= n, "zone in range")
		H.ok(z ~= prev, `slot {slot} repeats zone {z}`)
		prev = z
	end
	for cycle = 100, 110 do
		local seen = {}
		for i = 0, n - 1 do
			seen[SeedPacks.featuredZone(cycle * n + i)] = true
		end
		for k = 1, n do
			H.ok(seen[k], `cycle {cycle} misses zone {k}`)
		end
	end
end)

H.test("featured: buying with a stale slot id is refused", function()
	local t = 1790000000
	local current = SeedPacks.featuredPack(t)
	H.ok(SeedPacks.fromId(current.id, t) ~= nil, "current slot ok")
	local stale = `Pack:Featured:{current.slot - 1}`
	local pack, why = SeedPacks.fromId(stale, t)
	H.eq(pack, nil)
	H.ok(why and string.find(why, "rotated"), "explains the rotation")
	H.eq((SeedPacks.fromId("Pack:Nope", t)), nil)
	H.eq((SeedPacks.fromId("Pack:Featured:abc", t)), nil)
end)

----------------------------------------------------------------------------------------------------
-- Buying
----------------------------------------------------------------------------------------------------
H.test("buy: charges, rolls into the bag, and enforces unlock, money and bag size", function()
	local t = 1790000000
	local p = ProfileStore.defaultProfile()
	p.money = 10e3
	local ok, msg = Shop.buyPack(p, "Pack:Desert", t, seeded(1))
	H.eq(ok, false, "Desert locked at 0 Speed")
	H.ok(string.find(msg, "Speed"), msg)

	ok, msg = Shop.buyPack(p, "Pack:Meadow", t, seeded(1))
	H.ok(ok, msg)
	H.eq(p.money, 10e3 - 800)
	H.eq(SeedPacks.bagCount(p.seedBag), 1)

	p.money = 100
	ok = Shop.buyPack(p, "Pack:Meadow", t, seeded(1))
	H.eq(ok, false, "not enough money")
	H.eq(SeedPacks.bagCount(p.seedBag), 1)

	p = richPlayer()
	for _ = 1, Config.SEED_BAG_MAX do
		H.ok((Shop.buyPack(p, "Pack:Spirit", t, seeded(3))))
	end
	local money = p.money
	ok, msg = Shop.buyPack(p, "Pack:Spirit", t, seeded(3))
	H.eq(ok, false)
	H.ok(string.find(msg, "full"), msg)
	H.eq(p.money, money, "no charge when refused")
end)

H.test("buy: the featured pack is open to everyone and can give the exclusive", function()
	local t = 1790000000
	local p = ProfileStore.defaultProfile()
	local f = SeedPacks.featuredPack(t)
	p.money = f.price
	local ok, _, roll = Shop.buyPack(p, f.id, t, function()
		return 0 -- lowest roll: Common + the first mutation, which is the exclusive
	end)
	H.ok(ok, "featured bought at 0 Speed")
	H.eq(roll.mutation, Config.FEATURED_EXCLUSIVE)
	H.eq(p.seedBag[SeedPacks.bagKey(f.zone, 1, Config.FEATURED_EXCLUSIVE)], 1)
end)

H.test("bag: keys are validated and take/add keep counts right", function()
	for _, bad in { "0:1", "8:1", "1:6", "1:0", "1:1:Hacked", "01:1", "1:1:", "abc", "1", "" } do
		H.eq((SeedPacks.parseBagKey(bad)), nil, "rejects " .. bad)
	end
	H.eq((SeedPacks.parseBagKey(5)), nil, "rejects non-strings")
	local z, r, m = SeedPacks.parseBagKey("7:5:Celestial")
	H.eq(z, 7)
	H.eq(r, 5)
	H.eq(m, "Celestial")
	local bag = {}
	SeedPacks.addToBag(bag, 2, 3, nil)
	SeedPacks.addToBag(bag, 2, 3, nil)
	H.eq(bag["2:3"], 2)
	H.ok(SeedPacks.takeFromBag(bag, "2:3"))
	H.ok(SeedPacks.takeFromBag(bag, "2:3"))
	H.eq(bag["2:3"], nil, "empty stacks are removed")
	H.eq(SeedPacks.takeFromBag(bag, "2:3"), false)
end)

----------------------------------------------------------------------------------------------------
-- Persistence / migration
----------------------------------------------------------------------------------------------------
local function jsonStore(failTimes: number?)
	local store = { data = {} :: { [string]: string }, failTimes = failTimes or 0 }
	function store.UpdateAsync(self, key: string, transform: (any) -> any)
		if self.failTimes > 0 then
			self.failTimes -= 1
			error("mock DataStore failure")
		end
		local old = if self.data[key] then serde.decode("json", self.data[key]) else nil
		local new = transform(old)
		if new ~= nil then
			self.data[key] = serde.encode("json", new)
		end
		return new
	end
	return store
end

H.test("data: seed bag and receipts round-trip through a JSON DataStore", function()
	local p = ProfileStore.defaultProfile()
	p.seedBag = { ["1:1"] = 3, ["7:5:Celestial"] = 1, ["4:2:Gold"] = 2 }
	p.receipts = { "a1", "b2" }
	local ds = jsonStore()
	H.ok(ProfileStore.new(ds, 1, 0):save(9, p))
	local back, ok = ProfileStore.new(ds, 1, 0):load(9)
	H.ok(ok)
	local same, why = H.deepEq(back.seedBag, p.seedBag)
	H.ok(same, why)
	same, why = H.deepEq(back.receipts, p.receipts)
	H.ok(same, why)
end)

H.test("data: v1 saves (no bag, no receipts) load with empty defaults", function()
	local v1 = { v = 1, money = 50, speed = 10, speedMultTier = 1, treadmillTier = 1, slots = 10, plants = {}, index = {}, items = {}, potions = {}, reachedEnd = false, lastSeen = 5 }
	local p = ProfileStore.deserialize(serde.decode("json", serde.encode("json", v1)))
	H.eq(p.money, 50)
	H.eq(next(p.seedBag), nil)
	H.eq(#p.receipts, 0)
	-- an empty bag serializes as a JSON array; it must still load as an empty bag
	local blob = serde.decode("json", serde.encode("json", ProfileStore.serialize(ProfileStore.defaultProfile())))
	H.eq(next(ProfileStore.deserialize(blob).seedBag), nil)
end)

H.test("data: bad bag entries are dropped, the bag is clamped, receipts are trimmed", function()
	local receipts = {}
	for i = 1, Config.RECEIPT_HISTORY + 20 do
		receipts[i] = "r" .. i
	end
	local p = ProfileStore.deserialize({
		bag = { ["1:1"] = Config.SEED_BAG_HARD_MAX + 50, ["9:1"] = 2, ["1:2:Hacked"] = 1, ["2:2"] = -3, ["3:3"] = "x" },
		receipts = receipts,
	})
	H.eq(SeedPacks.bagCount(p.seedBag), Config.SEED_BAG_HARD_MAX)
	H.eq(p.seedBag["9:1"], nil)
	H.eq(p.seedBag["2:2"], nil)
	H.eq(#p.receipts, Config.RECEIPT_HISTORY)
	H.eq(p.receipts[#p.receipts], "r" .. (Config.RECEIPT_HISTORY + 20), "keeps the newest")
end)

----------------------------------------------------------------------------------------------------
-- Robux receipts
----------------------------------------------------------------------------------------------------
H.test("receipts: a PurchaseId is granted exactly once, then just confirmed", function()
	local t = 1790000000
	local p = ProfileStore.defaultProfile()
	local saves = 0
	local function save()
		saves += 1
		return true
	end
	local confirm, status, rolls = Shop.processReceipt(p, "PackBundle3", "purchase-1", t, seeded(5), save)
	H.eq(confirm, true)
	H.eq(status, "granted")
	H.eq(#rolls, 3)
	H.eq(SeedPacks.bagCount(p.seedBag), 3)
	confirm, status = Shop.processReceipt(p, "PackBundle3", "purchase-1", t, seeded(5), save)
	H.eq(confirm, true, "duplicate is confirmed")
	H.eq(status, "duplicate")
	H.eq(SeedPacks.bagCount(p.seedBag), 3, "no double grant")
	H.eq(saves, 2, "saved before each confirm")
end)

H.test("receipts: a failed save is not confirmed and the retry doesn't grant twice", function()
	local t = 1790000000
	local p = ProfileStore.defaultProfile()
	local confirm, status = Shop.processReceipt(p, "PackBundle1", "purchase-2", t, seeded(6), function()
		return false
	end)
	H.eq(confirm, false, "NotProcessedYet when the save failed")
	H.eq(status, "granted")
	confirm, status = Shop.processReceipt(p, "PackBundle1", "purchase-2", t, seeded(6), function()
		return true
	end)
	H.eq(confirm, true)
	H.eq(status, "duplicate")
	H.eq(SeedPacks.bagCount(p.seedBag), 1)
end)

H.test("receipts: the receipt id survives a save/load, so another server won't regrant", function()
	local t = 1790000000
	local ds = jsonStore()
	local store = ProfileStore.new(ds, 1, 0)
	local p = ProfileStore.defaultProfile()
	H.ok((Shop.processReceipt(p, "PackBundle10", "purchase-3", t, seeded(8), function()
		return store:save(77, p)
	end)))
	H.eq(SeedPacks.bagCount(p.seedBag), 10)
	local loaded = store:load(77)
	local confirm, status = Shop.processReceipt(loaded, "PackBundle10", "purchase-3", t, seeded(8), function()
		return store:save(77, loaded)
	end)
	H.eq(confirm, true)
	H.eq(status, "duplicate")
	H.eq(SeedPacks.bagCount(loaded.seedBag), 10)
end)

H.test("receipts: unknown products and missing sessions are never confirmed", function()
	local p = ProfileStore.defaultProfile()
	local yes = function()
		return true
	end
	H.eq((Shop.processReceipt(p, "Nope", "x", 0, seeded(1), yes)), false)
	H.eq((Shop.processReceipt(p, nil, "x", 0, seeded(1), yes)), false)
	H.eq((Shop.processReceipt(nil, "PackBundle1", "x", 0, seeded(1), yes)), false)
	H.eq(#p.receipts, 0)
end)

H.test("receipts: Robux grants go past the money cap but refund past the hard cap", function()
	local t = 1790000000
	local p = ProfileStore.defaultProfile()
	p.seedBag["1:1"] = Config.SEED_BAG_HARD_MAX - 2
	local _, _, rolls, pack = Shop.processReceipt(p, "PackBundle10", "purchase-4", t, seeded(9), function()
		return true
	end)
	H.eq(#rolls, 2)
	H.eq(SeedPacks.bagCount(p.seedBag), Config.SEED_BAG_HARD_MAX)
	H.eq(p.money, pack.price * 8, "8 packs refunded")
end)

H.test("config: developer products are stubs with ids, labels and 1/3/10 packs", function()
	local sizes = {}
	for name, product in Config.DEVELOPER_PRODUCTS do
		H.eq(type(product.id), "number", name)
		H.ok(type(product.label) == "string" and #product.label > 0, name)
		sizes[product.packs] = true
	end
	H.ok(sizes[1] and sizes[3] and sizes[10], "1/3/10 bundles")
end)
