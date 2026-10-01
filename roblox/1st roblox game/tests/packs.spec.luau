-- Seed packs: Robux only. Odds, rolls, featured rotation, developer products, the Speed gate on the
-- prompt (never on the receipt), idempotent receipt grants, the bag caps and the seed bag's save format.
local serde = require("@lune/serde")
local H = require("./harness")

local Config = H.shared("Config")
local Format = H.shared("Format")
local SeedPacks = H.shared("SeedPacks")
local Shop = H.server("Shop")
local ProfileStore = H.server("ProfileStore")

local T = 1790000000 -- a fixed os.time()

local function seeded(seed: number): () -> number
	local r = H.Random.new(seed)
	return function()
		return r:NextNumber()
	end
end

local function yes(): boolean
	return true
end

-- Runs fn with some developer product ids set (as if pasted from the Creator Dashboard), then puts
-- the stubs back, even if fn fails.
local function withIds(ids: { [string]: number }, fn: () -> ())
	local old = {}
	for name, id in ids do
		old[name] = Config.DEVELOPER_PRODUCTS[name].id
		Config.DEVELOPER_PRODUCTS[name].id = id
	end
	local ok, err = pcall(fn)
	for name, id in old do
		Config.DEVELOPER_PRODUCTS[name].id = id
	end
	if not ok then
		error(err, 0)
	end
end

local ALL_IDS = {
	PackMeadow = 101, PackDesert = 102, PackJungle = 103, PackLava = 104, PackSnow = 105, PackSpace = 106, PackSpirit = 107,
	PackBundle1 = 201, PackBundle3 = 203, PackBundle10 = 210,
}

----------------------------------------------------------------------------------------------------
-- Robux only: no money path exists
----------------------------------------------------------------------------------------------------
H.test("robux only: packs have no money price and there is no money purchase path", function()
	H.eq(Shop.buyPack, nil, "Shop.buyPack is gone")
	H.eq(SeedPacks.fromId, nil, "the money-buy lookup is gone")
	H.eq(SeedPacks.basePrice, nil)
	H.eq(SeedPacks.roundPrice, nil)
	H.eq(Config.PACK_INCOME_SECONDS, nil)
	H.eq(Config.PACK_COOLDOWN, nil)
	H.eq(Config.FEATURED_PRICE_MULT, nil)
	local view = { money = 1e15, speed = 1e15, speedMultTier = 1, treadmillTier = 1, slots = 10 }
	for k, zone in Config.ZONES do
		local pack = SeedPacks.zonePack(k)
		H.eq(pack.id, "Pack:" .. zone.id)
		H.eq(pack.zone, k)
		H.eq((pack :: any).price, nil, zone.id .. " has no money price")
		H.eq((Config.priceOf(pack.id, view)), nil, "not a money shop item")
	end
	H.eq((SeedPacks.featuredPackForSlot(5) :: any).price, nil)
	-- the old money ids are not shop items either: a rich player is never charged
	local p = ProfileStore.defaultProfile()
	p.money, p.speed = 1e15, 1e15
	for _, id in { "Pack:Meadow", `Pack:Featured:{SeedPacks.featuredSlot(T)}` } do
		H.eq((Shop.buy(p, id, 0)), false, id)
	end
	H.eq(p.money, 1e15)
	H.eq(SeedPacks.bagCount(p.seedBag), 0)
end)

----------------------------------------------------------------------------------------------------
-- Developer products
----------------------------------------------------------------------------------------------------
H.test("products: one per zone pack plus 1/3/10 featured bundles, id = 0 stubs with Robux placeholders", function()
	local perZone = {}
	local featured = {}
	for name, product in Config.DEVELOPER_PRODUCTS do
		H.eq(product.id, 0, name .. " ships as a stub")
		H.ok(type(product.label) == "string" and #product.label > 0, name)
		H.ok(type(product.robux) == "number" and product.robux > 0 and product.robux == math.floor(product.robux), name .. " placeholder R$")
		if product.zone then
			H.eq(product.packs, 1, name)
			H.ok(Config.ZONES[product.zone] ~= nil, name .. " zone")
			H.eq(perZone[product.zone], nil, "two products for zone " .. product.zone)
			perZone[product.zone] = product
		else
			featured[product.packs] = product.robux
		end
	end
	for k = 1, #Config.ZONES do
		H.ok(perZone[k], "zone " .. k .. " has a product")
		H.eq(perZone[k].label, SeedPacks.zonePack(k).name, "label matches the pack")
		if k > 1 then
			H.ok(perZone[k].robux > perZone[k - 1].robux, "zone placeholders rise by zone")
		end
	end
	H.eq(perZone[1].robux, 25, "zone packs start at 25 R$")
	H.eq(featured[1], 80)
	H.eq(featured[3], 200)
	H.eq(featured[10], 600)
	local list = SeedPacks.featuredProducts()
	H.eq(#list, 3)
	H.eq(list[1].product.packs, 1, "smallest bundle first")
	H.eq(list[3].product.packs, 10)
end)

H.test("products: lookup by developer product id", function()
	H.eq((SeedPacks.productById(0)), nil, "0 is never a product, even with stubs")
	H.eq((SeedPacks.productById(101)), nil, "stubs match nothing")
	withIds(ALL_IDS, function()
		for name, id in ALL_IDS do
			local found, product = SeedPacks.productById(id)
			H.eq(found, name)
			H.eq(product, Config.DEVELOPER_PRODUCTS[name])
		end
		H.eq((SeedPacks.productById(999)), nil, "unknown id")
		H.eq((SeedPacks.productById(0)), nil)
		H.eq((SeedPacks.zoneProduct(3)), "PackJungle")
		H.eq((SeedPacks.zoneProduct(99)), nil)
	end)
	H.eq((SeedPacks.productById(101)), nil, "ids restored")
end)

H.test("products: a product opens its zone pack, or the featured pack of the given slot", function()
	local P = Config.DEVELOPER_PRODUCTS
	local zone = SeedPacks.packForProduct(P.PackLava, 0)
	H.eq(zone.id, "Pack:Lava")
	H.eq(zone.featured, false)
	local slot = SeedPacks.featuredSlot(T)
	local f = SeedPacks.packForProduct(P.PackBundle3, slot)
	H.eq(f.id, `Pack:Featured:{slot}`)
	H.eq(f.zone, SeedPacks.featuredZone(slot))
	H.ok(f.featured and f.exclusive == Config.FEATURED_EXCLUSIVE)
end)

H.test("format: Robux labels", function()
	H.eq(Format.robux(80), "R$ 80")
	H.eq(Format.robux(1200), "R$ 1,200")
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

H.test("featured: a receipt opens the pack shown at the click, within the grace period", function()
	local P = Config.FEATURED_ROTATION_SECONDS
	local slot = SeedPacks.featuredSlot(T)
	local edge = SeedPacks.slotEndsAt(slot)
	-- clicked just before the rotation, paid just after: still the pack they saw
	H.eq(SeedPacks.receiptSlot(slot, edge - 5, edge + 20), slot)
	-- no prompt in this session (replayed on rejoin or on another server): the current pack
	H.eq(SeedPacks.receiptSlot(nil, nil, edge + 20), slot + 1)
	-- too long ago, or a slot that isn't current/previous: the current pack
	H.eq(SeedPacks.receiptSlot(slot, edge - 5, edge - 5 + Config.FEATURED_PROMPT_GRACE + 1), slot + 1)
	H.eq(SeedPacks.receiptSlot(slot - 1, edge - P - 5, edge + 20), slot + 1)
	H.eq(SeedPacks.receiptSlot(slot + 5, edge - 5, edge + 20), slot + 1, "a future slot is never trusted")
	H.eq(SeedPacks.receiptSlot(slot, edge + 100, edge + 20), slot + 1, "a prompt time in the future is ignored")
end)

----------------------------------------------------------------------------------------------------
-- The Robux prompt (gated) vs the receipt (always granted)
----------------------------------------------------------------------------------------------------
H.test("prompt: unknown products are refused and id = 0 stubs say coming soon", function()
	local p = ProfileStore.defaultProfile()
	p.speed = 1e15
	local product, why = Shop.canPrompt(p, "Nope", T, nil)
	H.eq(product, nil)
	H.ok(why ~= nil)
	product, why = Shop.canPrompt(p, "PackMeadow", T, nil)
	H.eq(product, nil, "no prompt without a real id")
	H.ok(why and string.find(why, "coming soon"), why)
	product, why = Shop.canPrompt(p, "PackBundle10", T, SeedPacks.featuredSlot(T))
	H.eq(product, nil)
	H.ok(why and string.find(why, "coming soon"), why)
end)

H.test("prompt: zone packs are locked until the zone's Speed; the featured pack has no gate", function()
	withIds(ALL_IDS, function()
		local p = ProfileStore.defaultProfile() -- 0 Speed
		local product, why = Shop.canPrompt(p, "PackMeadow", T, nil)
		H.eq(product, Config.DEVELOPER_PRODUCTS.PackMeadow, "Meadow is open at 0 Speed")
		H.eq(why, nil)
		product, why = Shop.canPrompt(p, "PackDesert", T, nil)
		H.eq(product, nil, "Desert pack refused below 10K Speed")
		H.ok(why and string.find(why, "Speed"), why)
		p.speed = Config.ZONES[2].req
		H.ok((Shop.canPrompt(p, "PackDesert", T, nil)), "open at exactly the recommended Speed")
		H.eq((Shop.canPrompt(p, "PackSpirit", T, nil)), nil)
		p.speed = 0
		for _, entry in SeedPacks.featuredProducts() do
			H.ok((Shop.canPrompt(p, entry.name, T, SeedPacks.featuredSlot(T))), entry.name .. " open at 0 Speed")
		end
	end)
end)

H.test("prompt: a featured click from a stale menu is refused", function()
	withIds(ALL_IDS, function()
		local p = ProfileStore.defaultProfile()
		local slot = SeedPacks.featuredSlot(T)
		local product, why = Shop.canPrompt(p, "PackBundle1", T, slot - 1)
		H.eq(product, nil)
		H.ok(why and string.find(why, "rotated"), why)
		H.ok((Shop.canPrompt(p, "PackBundle1", T, slot)))
	end)
end)

H.test("prompt: no new prompts once the bag holds SEED_BAG_MAX seeds", function()
	withIds(ALL_IDS, function()
		local p = ProfileStore.defaultProfile()
		p.seedBag["1:1"] = Config.SEED_BAG_MAX - 1
		H.ok((Shop.canPrompt(p, "PackMeadow", T, nil)))
		p.seedBag["1:1"] = Config.SEED_BAG_MAX
		local product, why = Shop.canPrompt(p, "PackMeadow", T, nil)
		H.eq(product, nil)
		H.ok(why and string.find(why, "full"), why)
		H.eq((Shop.canPrompt(p, "PackBundle1", T, nil)), nil)
	end)
end)

H.test("prompt: checking a prompt never changes the profile", function()
	withIds(ALL_IDS, function()
		local p = ProfileStore.defaultProfile()
		p.money = 12345
		local before = serde.encode("json", ProfileStore.serialize(p))
		Shop.canPrompt(p, "PackSpirit", T, nil)
		Shop.canPrompt(p, "PackBundle1", T, 1)
		Shop.canPrompt(p, "PackMeadow", T, nil)
		H.eq(serde.encode("json", ProfileStore.serialize(p)), before)
	end)
end)

----------------------------------------------------------------------------------------------------
-- Receipts: grants
----------------------------------------------------------------------------------------------------
H.test("grant: a zone pack puts one seed of its zone in the bag and charges no money", function()
	local p = ProfileStore.defaultProfile()
	p.speed = 1e15
	p.money = 500
	local confirm, status, grant = Shop.processReceipt(p, "PackJungle", "z-1", SeedPacks.featuredSlot(T), 0, seeded(1), yes)
	H.eq(confirm, true)
	H.eq(status, "granted")
	H.eq(grant.pack.id, "Pack:Jungle")
	H.eq(#grant.rolls, 1)
	H.eq(grant.rolls[1].zone, 3)
	H.eq(grant.compensated, 0)
	H.eq(SeedPacks.bagCount(p.seedBag), 1)
	H.eq(p.money, 500, "Robux packs never touch money")
	H.eq((SeedPacks.parseBagKey(next(p.seedBag))), 3)
end)

H.test("grant: featured bundles open N packs of the given featured slot", function()
	local slot = SeedPacks.featuredSlot(T)
	local fz = SeedPacks.featuredZone(slot)
	for name, n in { PackBundle1 = 1, PackBundle3 = 3, PackBundle10 = 10 } do
		local p = ProfileStore.defaultProfile()
		local confirm, status, grant = Shop.processReceipt(p, name, "f-" .. name, slot, 0, seeded(n), yes)
		H.eq(confirm, true)
		H.eq(status, "granted")
		H.eq(grant.pack.id, `Pack:Featured:{slot}`)
		H.eq(#grant.rolls, n, name)
		for _, r in grant.rolls do
			H.eq(r.zone, fz)
		end
		H.eq(SeedPacks.bagCount(p.seedBag), n)
	end
end)

H.test("grant: a featured pack can give the exclusive", function()
	local p = ProfileStore.defaultProfile()
	local slot = SeedPacks.featuredSlot(T)
	local _, _, grant = Shop.processReceipt(p, "PackBundle1", "x-1", slot, 0, function()
		return 0 -- lowest roll: Common + the first mutation, which is the exclusive
	end, yes)
	H.eq(grant.rolls[1].mutation, Config.FEATURED_EXCLUSIVE)
	H.eq(p.seedBag[SeedPacks.bagKey(SeedPacks.featuredZone(slot), 1, Config.FEATURED_EXCLUSIVE)], 1)
end)

H.test("grant: a locked zone pack's prompt is refused, but a receipt that arrives is still granted", function()
	withIds(ALL_IDS, function()
		local p = ProfileStore.defaultProfile() -- 0 Speed: the Spirit Garden is far away
		H.eq((Shop.canPrompt(p, "PackSpirit", T, nil)), nil, "prompt refused")
		-- ...but the player paid (an old prompt, a pending receipt, a changed config): grant it.
		local confirm, status, grant = Shop.processReceipt(p, "PackSpirit", "locked-1", SeedPacks.featuredSlot(T), 0, seeded(4), yes)
		H.eq(confirm, true)
		H.eq(status, "granted")
		H.eq(#grant.rolls, 1)
		H.eq(grant.rolls[1].zone, 7)
		H.eq(SeedPacks.bagCount(p.seedBag), 1)
	end)
end)

----------------------------------------------------------------------------------------------------
-- Receipts: idempotency
----------------------------------------------------------------------------------------------------
H.test("receipts: a PurchaseId is granted exactly once across retries, then just confirmed", function()
	local p = ProfileStore.defaultProfile()
	local slot = SeedPacks.featuredSlot(T)
	local saves = 0
	local function save()
		saves += 1
		return true
	end
	local confirm, status, grant = Shop.processReceipt(p, "PackBundle3", "purchase-1", slot, 0, seeded(5), save)
	H.eq(confirm, true)
	H.eq(status, "granted")
	H.eq(#grant.rolls, 3)
	for _ = 1, 3 do
		confirm, status, grant = Shop.processReceipt(p, "PackBundle3", "purchase-1", slot, 0, seeded(5), save)
		H.eq(confirm, true, "duplicate is confirmed")
		H.eq(status, "duplicate")
		H.eq(grant, nil)
	end
	H.eq(SeedPacks.bagCount(p.seedBag), 3, "no double grant")
	H.eq(saves, 4, "saved before each confirm")
	-- a new purchase of the same product is a new grant
	Shop.processReceipt(p, "PackBundle3", "purchase-1b", slot, 0, seeded(5), save)
	H.eq(SeedPacks.bagCount(p.seedBag), 6)
end)

H.test("receipts: a failed save is not confirmed and the retries don't grant twice", function()
	local p = ProfileStore.defaultProfile()
	local slot = SeedPacks.featuredSlot(T)
	local function no()
		return false
	end
	local confirm, status = Shop.processReceipt(p, "PackMeadow", "purchase-2", slot, 0, seeded(6), no)
	H.eq(confirm, false, "NotProcessedYet when the save failed")
	H.eq(status, "granted")
	confirm, status = Shop.processReceipt(p, "PackMeadow", "purchase-2", slot, 0, seeded(6), no)
	H.eq(confirm, false, "still failing: still not confirmed")
	H.eq(status, "duplicate")
	confirm, status = Shop.processReceipt(p, "PackMeadow", "purchase-2", slot, 0, seeded(6), yes)
	H.eq(confirm, true)
	H.eq(status, "duplicate")
	H.eq(SeedPacks.bagCount(p.seedBag), 1)
end)

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

H.test("receipts: the receipt id survives a save/load, so another server won't regrant", function()
	local ds = jsonStore()
	local store = ProfileStore.new(ds, 1, 0)
	local slot = SeedPacks.featuredSlot(T)
	local p = ProfileStore.defaultProfile()
	H.ok((Shop.processReceipt(p, "PackBundle10", "purchase-3", slot, 0, seeded(8), function()
		return store:save(77, p)
	end)))
	H.eq(SeedPacks.bagCount(p.seedBag), 10)
	-- server hop: Roblox redelivers the receipt on another server, hours later (another featured slot)
	local loaded = ProfileStore.new(ds, 1, 0):load(77)
	local confirm, status = Shop.processReceipt(loaded, "PackBundle10", "purchase-3", slot + 3, 0, seeded(8), function()
		return store:save(77, loaded)
	end)
	H.eq(confirm, true)
	H.eq(status, "duplicate")
	H.eq(SeedPacks.bagCount(loaded.seedBag), 10)
end)

H.test("receipts: a server that dies before saving loses nothing; the next server grants exactly once", function()
	local ds = jsonStore()
	local store = ProfileStore.new(ds, 1, 0)
	local slot = SeedPacks.featuredSlot(T)
	H.ok(store:save(78, ProfileStore.defaultProfile()))
	-- server A: grants in memory, the save fails (DataStore down), then the server dies
	local a = store:load(78)
	ds.failTimes = 100
	local confirm = Shop.processReceipt(a, "PackBundle3", "purchase-4", slot, 0, seeded(9), function()
		return store:save(78, a)
	end)
	H.eq(confirm, false, "not confirmed, so Roblox will redeliver")
	ds.failTimes = 0
	-- server B: the saved profile has neither the seeds nor the id, so it grants once
	local b = store:load(78)
	H.eq(SeedPacks.bagCount(b.seedBag), 0)
	local status
	confirm, status = Shop.processReceipt(b, "PackBundle3", "purchase-4", slot, 0, seeded(9), function()
		return store:save(78, b)
	end)
	H.eq(confirm, true)
	H.eq(status, "granted")
	confirm, status = Shop.processReceipt(b, "PackBundle3", "purchase-4", slot, 0, seeded(9), function()
		return store:save(78, b)
	end)
	H.eq(status, "duplicate")
	H.eq(SeedPacks.bagCount(store:load(78).seedBag), 3)
end)

H.test("receipts: unknown products and missing sessions are never confirmed", function()
	local p = ProfileStore.defaultProfile()
	H.eq((Shop.processReceipt(p, "Nope", "x", 0, 0, seeded(1), yes)), false)
	H.eq((Shop.processReceipt(p, nil, "x", 0, 0, seeded(1), yes)), false)
	H.eq((Shop.processReceipt(nil, "PackBundle1", "x", 0, 0, seeded(1), yes)), false)
	H.eq(#p.receipts, 0)
	H.eq(SeedPacks.bagCount(p.seedBag), 0)
end)

----------------------------------------------------------------------------------------------------
-- Receipts: the bag caps
----------------------------------------------------------------------------------------------------
H.test("bag: paid grants go past the soft max up to the hard max", function()
	local p = ProfileStore.defaultProfile()
	local money = p.money
	p.seedBag["1:1"] = Config.SEED_BAG_MAX - 1
	local _, _, grant = Shop.processReceipt(p, "PackBundle10", "soft-1", SeedPacks.featuredSlot(T), 0, seeded(10), yes)
	H.eq(#grant.rolls, 10)
	H.eq(grant.compensated, 0)
	H.eq(SeedPacks.bagCount(p.seedBag), Config.SEED_BAG_MAX + 9)
	H.eq(p.money, money, "no compensation below the hard max")
end)

H.test("bag: past the hard max a pack pays income-based money instead (never lost)", function()
	local slot = SeedPacks.featuredSlot(T)
	local pack = SeedPacks.featuredPackForSlot(slot)
	local income = 1e12 -- $/s, more than any Common plant earns, so the player's income decides
	local per = Shop.fullBagCompensation(pack, income)
	H.eq(per, math.floor(income * Config.PACK_FULL_BAG_INCOME_SECONDS))
	local p = ProfileStore.defaultProfile()
	local money = p.money
	p.seedBag["1:1"] = Config.SEED_BAG_HARD_MAX - 2
	local confirm, status, grant = Shop.processReceipt(p, "PackBundle10", "hard-1", slot, income, seeded(11), yes)
	H.eq(confirm, true)
	H.eq(status, "granted")
	H.eq(#grant.rolls, 2, "two seeds still fit")
	H.eq(grant.compensated, 8)
	H.eq(grant.compensation, per * 8)
	H.eq(SeedPacks.bagCount(p.seedBag), Config.SEED_BAG_HARD_MAX)
	H.eq(p.money, money + per * 8, "8 packs paid out")
	-- truly full: a zone pack pays too, and its retry doesn't pay twice
	local _, _, g2 = Shop.processReceipt(p, "PackSpirit", "hard-2", slot, income, seeded(12), yes)
	H.eq(#g2.rolls, 0)
	H.eq(g2.compensated, 1)
	local _, status2 = Shop.processReceipt(p, "PackSpirit", "hard-2", slot, income, seeded(12), yes)
	H.eq(status2, "duplicate")
	H.eq(p.money, money + per * 8 + Shop.fullBagCompensation(SeedPacks.zonePack(7), income))
	H.eq(SeedPacks.bagCount(p.seedBag), Config.SEED_BAG_HARD_MAX)
end)

H.test("bag: compensation is never zero, even for a player with no income yet", function()
	for k = 1, #Config.ZONES do
		local pack = SeedPacks.zonePack(k)
		local c = Shop.fullBagCompensation(pack, 0)
		H.ok(c > 0, "zone " .. k)
		H.eq(c, math.floor(Config.seedIncome(k) * Config.PACK_FULL_BAG_INCOME_SECONDS))
		H.ok(Shop.fullBagCompensation(pack, 1e18) > c, "scales with the player's income")
	end
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
