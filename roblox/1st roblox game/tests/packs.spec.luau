-- Seed packs: two premium late-game packs, Robux only. Products, odds, rolls, the Celestial rules,
-- the prompt gates (no Speed gate), idempotent receipt grants, the bag caps and the bag's save format.
local serde = require("@lune/serde")
local H = require("./harness")

local Config = H.shared("Config")
local Format = H.shared("Format")
local SeedPacks = H.shared("SeedPacks")
local Shop = H.server("Shop")
local ProfileStore = H.server("ProfileStore")

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

local ALL_IDS = { PackSpace = 106, PackSpirit = 107 }
local SPACE, SPIRIT = 6, 7

local function packs(): { any }
	return { SeedPacks.zonePack(SPACE), SeedPacks.zonePack(SPIRIT) }
end

----------------------------------------------------------------------------------------------------
-- Robux only: no money path exists
----------------------------------------------------------------------------------------------------
H.test("robux only: packs have no money price and there is no money purchase path", function()
	H.eq(Shop.buyPack, nil, "Shop.buyPack is gone")
	H.eq(SeedPacks.fromId, nil, "the money-buy lookup is gone")
	H.eq(Config.PACK_INCOME_SECONDS, nil)
	local view = { money = 1e15, speed = 1e15, speedMultTier = 1, treadmillTier = 1, slots = 10 }
	for _, pack in packs() do
		H.eq((pack :: any).price, nil, pack.id .. " has no money price")
		H.eq((Config.priceOf(pack.id, view)), nil, "not a money shop item")
	end
	local p = ProfileStore.defaultProfile()
	p.money, p.speed = 1e15, 1e15
	for _, id in { "Pack:Space", "Pack:Spirit", "Product:PackSpace" } do
		H.eq((Shop.buy(p, id)), false, id)
	end
	H.eq(p.money, 1e15, "a rich player is never charged")
	H.eq(SeedPacks.bagCount(p.seedBag), 0)
end)

H.test("removed: the featured pack, its bundles and the zone 1-5 packs are gone", function()
	for _, key in { "FEATURED_ROTATION_SECONDS", "FEATURED_SEED", "FEATURED_LUCK", "FEATURED_MUTATION_MULT", "FEATURED_EXCLUSIVE",
		"FEATURED_EXCLUSIVE_CHANCE", "FEATURED_PROMPT_GRACE" } do
		H.eq((Config :: any)[key], nil, "Config." .. key)
	end
	for _, fn in { "featuredSlot", "slotEndsAt", "featuredZone", "featuredPack", "featuredPackForSlot", "featuredProducts", "receiptSlot", "zoneProduct" } do
		H.eq((SeedPacks :: any)[fn], nil, "SeedPacks." .. fn)
	end
	for _, name in { "PackMeadow", "PackDesert", "PackJungle", "PackLava", "PackSnow", "PackBundle1", "PackBundle3", "PackBundle10" } do
		H.eq(Config.DEVELOPER_PRODUCTS[name], nil, name)
	end
	for _, id in { "Pack:Meadow", "Pack:Desert", "Pack:Jungle", "Pack:Lava", "Pack:Snow", "Pack:Featured:5" } do
		H.eq(SeedPacks.lookup(id), nil, id .. " is not a pack any more")
	end
end)

----------------------------------------------------------------------------------------------------
-- Developer products
----------------------------------------------------------------------------------------------------
H.test("products: exactly two, Deep Space and Spirit Garden, id = 0 stubs with premium placeholders", function()
	local names = {}
	for name, product in Config.DEVELOPER_PRODUCTS do
		table.insert(names, name)
		H.eq(product.id, 0, name .. " ships as a stub")
		H.eq((product :: any).packs, nil, name .. ": one pack per product, no bundles")
	end
	H.eq(#names, 2, "two products")
	local P = Config.DEVELOPER_PRODUCTS
	H.eq(P.PackSpace.zone, SPACE)
	H.eq(P.PackSpace.label, "Starpetal Pack")
	H.eq(P.PackSpace.robux, 2000)
	H.eq(P.PackSpirit.zone, SPIRIT)
	H.eq(P.PackSpirit.label, "Lotus Wyrm Pack")
	H.eq(P.PackSpirit.robux, 3000)
	for name, product in P do
		H.eq(product.label, SeedPacks.packForProduct(product).name, name .. " label matches the pack")
	end
	local list = SeedPacks.products()
	H.eq(#list, 2)
	H.eq(list[1].name, "PackSpace", "Shop order: by zone")
	H.eq(list[2].name, "PackSpirit")
	H.eq(Format.robux(P.PackSpace.robux), "R$ 2,000")
	H.eq(Format.robux(P.PackSpirit.robux), "R$ 3,000")
end)

H.test("products: lookup by developer product id", function()
	H.eq((SeedPacks.productById(0)), nil, "0 is never a product, even with stubs")
	H.eq((SeedPacks.productById(106)), nil, "stubs match nothing")
	withIds(ALL_IDS, function()
		for name, id in ALL_IDS do
			local found, product = SeedPacks.productById(id)
			H.eq(found, name)
			H.eq(product, Config.DEVELOPER_PRODUCTS[name])
		end
		H.eq((SeedPacks.productById(999)), nil, "unknown id")
		H.eq((SeedPacks.productById(0)), nil)
	end)
	H.eq((SeedPacks.productById(106)), nil, "ids restored")
end)

H.test("products: each opens its zone's pack, and reveal ids look up the same pack", function()
	local P = Config.DEVELOPER_PRODUCTS
	local space = SeedPacks.packForProduct(P.PackSpace)
	H.eq(space.id, "Pack:Space")
	H.eq(space.zone, SPACE)
	H.eq(space.name, "Starpetal Pack")
	local spirit = SeedPacks.packForProduct(P.PackSpirit)
	H.eq(spirit.id, "Pack:Spirit")
	H.eq(spirit.zone, SPIRIT)
	for _, pack in { space, spirit } do
		local same, why = H.deepEq(SeedPacks.lookup(pack.id), pack)
		H.ok(same, why)
		H.eq(pack.exclusive, "Celestial")
	end
	H.eq(SeedPacks.lookup("nope"), nil)
end)

----------------------------------------------------------------------------------------------------
-- Odds
----------------------------------------------------------------------------------------------------
H.test("odds: rarity odds sum to 100% and mutations + none sum to 100% for both packs", function()
	for _, pack in packs() do
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

H.test("odds: packs show Celestial 0.5%, Gold and Rainbow, never Night; Spirit is luckier than Space", function()
	H.eq(Config.PACK_EXCLUSIVE, "Celestial")
	H.eq(Config.PACK_EXCLUSIVE_CHANCE, 0.005)
	for _, pack in packs() do
		local odds = SeedPacks.odds(pack)
		local ids = {}
		for _, m in odds.mutations do
			table.insert(ids, m.id)
		end
		H.eq(table.concat(ids, ","), "Celestial,Gold,Rainbow", pack.id)
		H.near(odds.mutations[1].pct, 0.5, 1e-12, "Celestial 0.5%")
		H.near(odds.mutations[2].pct, 4, 1e-12, "Gold 4%")
		H.near(odds.mutations[3].pct, 1, 1e-12, "Rainbow 1%")
		H.eq(SeedPacks.percent(odds.mutations[1].pct), "0.5%")
	end
	local space, spirit = SeedPacks.odds(packs()[1]), SeedPacks.odds(packs()[2])
	H.ok(spirit.rarities[#Config.RARITIES] > space.rarities[#Config.RARITIES], "deeper zone, rarer seeds")
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
-- Rolls and the Celestial rules
----------------------------------------------------------------------------------------------------
H.test("roll: seeded RNG is reproducible and edge values stay in range", function()
	local pack = SeedPacks.zonePack(SPACE)
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
	H.eq(m, "Celestial", "rng 0 -> the first mutation, Celestial")
	r, m = SeedPacks.roll(pack, function()
		return 0.999999999
	end)
	H.eq(r, #Config.RARITIES, "rng ~1 -> Legendary")
	H.eq(m, nil, "rng ~1 -> no mutation")
end)

H.test("roll: 200k seeded rolls match the displayed odds, Celestial included", function()
	for _, pack in packs() do
		local odds = SeedPacks.odds(pack)
		local rng = seeded(2026 + pack.zone)
		local N = 200000
		local rarityHits, mutHits = {}, {}
		for _ = 1, N do
			local r, m = SeedPacks.roll(pack, rng)
			rarityHits[r] = (rarityHits[r] or 0) + 1
			if m then
				mutHits[m] = (mutHits[m] or 0) + 1
			end
		end
		for i, pct in odds.rarities do
			local got = (rarityHits[i] or 0) / N * 100
			H.near(got, pct, math.max(0.1, pct * 0.05), `{pack.id} rarity {i}`)
		end
		for _, m in odds.mutations do
			local got = (mutHits[m.id] or 0) / N * 100
			H.near(got, m.pct, math.max(0.08, m.pct * 0.2), `{pack.id} {m.id}`)
		end
		H.ok((mutHits.Celestial or 0) > 0, pack.id .. ": Celestial does drop")
		H.eq(mutHits.Night, nil, pack.id .. ": Night never rolls from packs")
	end
end)

H.test("celestial: still a mutation (x12, exclusive) and pods can never roll it, day or night, any zone", function()
	local cel = Config.mutationById("Celestial")
	H.ok(cel ~= nil, "Celestial still exists")
	H.eq(cel.exclusive, true)
	H.eq(cel.chance, 0, "pods roll mutations by chance; 0 means never")
	H.eq(cel.income, 12)
	local rng = seeded(7)
	for k = 1, #Config.ZONES do
		for _, night in { false, true } do
			for _ = 1, 10000 do
				local _, m = Config.rollSeed(k, if night then Config.NIGHT_LUCK else 1, night, rng)
				H.ok(m ~= "Celestial", "a pod rolled Celestial")
			end
		end
		-- even the luckiest edge of the pod roll can't land on it
		local _, edge = Config.rollSeed(k, Config.NIGHT_LUCK, true, function()
			return 0
		end)
		H.ok(edge ~= "Celestial", "rng 0 pod roll")
	end
end)

----------------------------------------------------------------------------------------------------
-- The Robux prompt (soft-gated) vs the receipt (always granted)
----------------------------------------------------------------------------------------------------
H.test("prompt: unknown products are refused and id = 0 stubs say coming soon", function()
	local p = ProfileStore.defaultProfile()
	local product, why = Shop.canPrompt(p, "Nope")
	H.eq(product, nil)
	H.ok(why ~= nil)
	for name in Config.DEVELOPER_PRODUCTS do
		product, why = Shop.canPrompt(p, name)
		H.eq(product, nil, name .. ": no prompt without a real id")
		H.ok(why and string.find(why, "coming soon"), why)
	end
	-- removed products are unknown, even with an id-shaped name
	for _, old in { "PackMeadow", "PackBundle1" } do
		product, why = Shop.canPrompt(p, old)
		H.eq(product, nil, old)
		H.eq(why, "Unknown pack")
	end
end)

H.test("prompt: no Speed gate, both packs open to a brand-new player", function()
	withIds(ALL_IDS, function()
		local p = ProfileStore.defaultProfile()
		H.eq(p.speed, 0)
		for name, product in Config.DEVELOPER_PRODUCTS do
			local got, why = Shop.canPrompt(p, name)
			H.eq(got, product, name .. " open at 0 Speed")
			H.eq(why, nil)
		end
	end)
end)

H.test("prompt: no new prompts once the bag holds SEED_BAG_MAX seeds (soft cap)", function()
	withIds(ALL_IDS, function()
		local p = ProfileStore.defaultProfile()
		p.seedBag["1:1"] = Config.SEED_BAG_MAX - 1
		H.ok((Shop.canPrompt(p, "PackSpace")))
		p.seedBag["1:1"] = Config.SEED_BAG_MAX
		local product, why = Shop.canPrompt(p, "PackSpace")
		H.eq(product, nil)
		H.ok(why and string.find(why, "full"), why)
		H.eq((Shop.canPrompt(p, "PackSpirit")), nil)
	end)
end)

H.test("prompt: checking a prompt never changes the profile", function()
	withIds(ALL_IDS, function()
		local p = ProfileStore.defaultProfile()
		p.money = 12345
		local before = serde.encode("json", ProfileStore.serialize(p))
		Shop.canPrompt(p, "PackSpirit")
		Shop.canPrompt(p, "PackSpace")
		Shop.canPrompt(p, "Nope")
		H.eq(serde.encode("json", ProfileStore.serialize(p)), before)
	end)
end)

----------------------------------------------------------------------------------------------------
-- Receipts: grants
----------------------------------------------------------------------------------------------------
H.test("grant: each pack puts one seed of its zone (6 or 7) in the bag and charges no money", function()
	for name, zone in { PackSpace = SPACE, PackSpirit = SPIRIT } do
		local p = ProfileStore.defaultProfile() -- 0 Speed: no gate on the grant either
		p.money = 500
		local confirm, status, grant = Shop.processReceipt(p, name, "z-" .. name, 0, seeded(zone), yes)
		H.eq(confirm, true)
		H.eq(status, "granted")
		H.eq(grant.pack.zone, zone)
		H.eq(grant.roll.zone, zone)
		H.eq(grant.roll.name, SeedPacks.seedName(zone, grant.roll.rarity, grant.roll.mutation))
		H.eq(grant.compensation, 0)
		H.eq(SeedPacks.bagCount(p.seedBag), 1)
		H.eq(p.money, 500, "Robux packs never touch money")
		H.eq((SeedPacks.parseBagKey(next(p.seedBag))), zone)
		H.eq(p.receipts[1], "z-" .. name)
	end
end)

H.test("grant: a pack can give Celestial, and the bag/save keep it", function()
	local p = ProfileStore.defaultProfile()
	local _, _, grant = Shop.processReceipt(p, "PackSpirit", "cel-1", 0, function()
		return 0 -- lowest roll: Common + the first mutation, Celestial
	end, yes)
	H.eq(grant.roll.mutation, "Celestial")
	H.eq(grant.roll.name, "Celestial Common Lotus Wyrm")
	local key = SeedPacks.bagKey(SPIRIT, 1, "Celestial")
	H.eq(p.seedBag[key], 1)
	H.eq(select(3, SeedPacks.parseBagKey(key)), "Celestial", "a Celestial bag key is valid (plantable)")
end)

----------------------------------------------------------------------------------------------------
-- Receipts: idempotency
----------------------------------------------------------------------------------------------------
H.test("receipts: a PurchaseId is granted exactly once across retries, then just confirmed", function()
	local p = ProfileStore.defaultProfile()
	local saves = 0
	local function save()
		saves += 1
		return true
	end
	local confirm, status, grant = Shop.processReceipt(p, "PackSpace", "purchase-1", 0, seeded(5), save)
	H.eq(confirm, true)
	H.eq(status, "granted")
	H.ok(grant.roll ~= nil)
	for _ = 1, 3 do
		confirm, status, grant = Shop.processReceipt(p, "PackSpace", "purchase-1", 0, seeded(5), save)
		H.eq(confirm, true, "duplicate is confirmed")
		H.eq(status, "duplicate")
		H.eq(grant, nil)
	end
	H.eq(SeedPacks.bagCount(p.seedBag), 1, "no double grant")
	H.eq(saves, 4, "saved before each confirm")
	-- a new purchase of the same product is a new grant
	Shop.processReceipt(p, "PackSpace", "purchase-1b", 0, seeded(5), save)
	H.eq(SeedPacks.bagCount(p.seedBag), 2)
end)

H.test("receipts: a failed save is not confirmed and the retries don't grant twice", function()
	local p = ProfileStore.defaultProfile()
	local function no()
		return false
	end
	local confirm, status = Shop.processReceipt(p, "PackSpirit", "purchase-2", 0, seeded(6), no)
	H.eq(confirm, false, "NotProcessedYet when the save failed")
	H.eq(status, "granted")
	confirm, status = Shop.processReceipt(p, "PackSpirit", "purchase-2", 0, seeded(6), no)
	H.eq(confirm, false, "still failing: still not confirmed")
	H.eq(status, "duplicate")
	confirm, status = Shop.processReceipt(p, "PackSpirit", "purchase-2", 0, seeded(6), yes)
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
	local p = ProfileStore.defaultProfile()
	H.ok((Shop.processReceipt(p, "PackSpirit", "purchase-3", 0, seeded(8), function()
		return store:save(77, p)
	end)))
	H.eq(SeedPacks.bagCount(p.seedBag), 1)
	-- server hop: Roblox redelivers the receipt on another server
	local loaded = ProfileStore.new(ds, 1, 0):load(77)
	local confirm, status = Shop.processReceipt(loaded, "PackSpirit", "purchase-3", 0, seeded(8), function()
		return store:save(77, loaded)
	end)
	H.eq(confirm, true)
	H.eq(status, "duplicate")
	H.eq(SeedPacks.bagCount(loaded.seedBag), 1)
end)

H.test("receipts: a server that dies before saving loses nothing; the next server grants exactly once", function()
	local ds = jsonStore()
	local store = ProfileStore.new(ds, 1, 0)
	H.ok(store:save(78, ProfileStore.defaultProfile()))
	-- server A: grants in memory, the save fails (DataStore down), then the server dies
	local a = store:load(78)
	ds.failTimes = 100
	local confirm = Shop.processReceipt(a, "PackSpace", "purchase-4", 0, seeded(9), function()
		return store:save(78, a)
	end)
	H.eq(confirm, false, "not confirmed, so Roblox will redeliver")
	ds.failTimes = 0
	-- server B: the saved profile has neither the seed nor the id, so it grants once
	local b = store:load(78)
	H.eq(SeedPacks.bagCount(b.seedBag), 0)
	local status
	confirm, status = Shop.processReceipt(b, "PackSpace", "purchase-4", 0, seeded(9), function()
		return store:save(78, b)
	end)
	H.eq(confirm, true)
	H.eq(status, "granted")
	confirm, status = Shop.processReceipt(b, "PackSpace", "purchase-4", 0, seeded(9), function()
		return store:save(78, b)
	end)
	H.eq(status, "duplicate")
	local final = store:load(78)
	H.eq(SeedPacks.bagCount(final.seedBag), 1)
	H.eq((SeedPacks.parseBagKey(next(final.seedBag))), SPACE)
end)

H.test("receipts: unknown products and missing sessions are never confirmed", function()
	local p = ProfileStore.defaultProfile()
	H.eq((Shop.processReceipt(p, "Nope", "x", 0, seeded(1), yes)), false)
	H.eq((Shop.processReceipt(p, "PackBundle1", "x", 0, seeded(1), yes)), false, "a removed product")
	H.eq((Shop.processReceipt(p, nil, "x", 0, seeded(1), yes)), false)
	H.eq((Shop.processReceipt(nil, "PackSpace", "x", 0, seeded(1), yes)), false)
	H.eq(#p.receipts, 0)
	H.eq(SeedPacks.bagCount(p.seedBag), 0)
end)

----------------------------------------------------------------------------------------------------
-- Receipts: the bag caps
----------------------------------------------------------------------------------------------------
H.test("bag: paid grants go past the soft max up to the hard max", function()
	local p = ProfileStore.defaultProfile()
	local money = p.money
	p.seedBag["1:1"] = Config.SEED_BAG_MAX + 10
	local _, _, grant = Shop.processReceipt(p, "PackSpace", "soft-1", 0, seeded(10), yes)
	H.ok(grant.roll ~= nil)
	H.eq(grant.compensation, 0)
	H.eq(SeedPacks.bagCount(p.seedBag), Config.SEED_BAG_MAX + 11)
	H.eq(p.money, money, "no compensation below the hard max")
end)

H.test("bag: at the hard max a pack pays income-based money instead (never lost), once", function()
	local income = 1e12 -- $/s, more than any Common plant earns, so the player's income decides
	local p = ProfileStore.defaultProfile()
	local money = p.money
	p.seedBag["1:1"] = Config.SEED_BAG_HARD_MAX - 1
	local _, _, g1 = Shop.processReceipt(p, "PackSpace", "hard-1", income, seeded(11), yes)
	H.ok(g1.roll ~= nil, "the last seed still fits")
	H.eq(SeedPacks.bagCount(p.seedBag), Config.SEED_BAG_HARD_MAX)
	H.eq(p.money, money)
	for name, zone in { PackSpace = SPACE, PackSpirit = SPIRIT } do
		local before = p.money
		local per = Shop.fullBagCompensation(SeedPacks.zonePack(zone), income)
		H.eq(per, math.floor(income * Config.PACK_FULL_BAG_INCOME_SECONDS))
		local confirm, status, grant = Shop.processReceipt(p, name, "hard-" .. name, income, seeded(12), yes)
		H.eq(confirm, true)
		H.eq(status, "granted")
		H.eq(grant.roll, nil, "no seed fits")
		H.eq(grant.compensation, per)
		H.eq(p.money, before + per)
		-- its retry doesn't pay twice
		local _, again = Shop.processReceipt(p, name, "hard-" .. name, income, seeded(12), yes)
		H.eq(again, "duplicate")
		H.eq(p.money, before + per)
	end
	H.eq(SeedPacks.bagCount(p.seedBag), Config.SEED_BAG_HARD_MAX)
end)

H.test("bag: compensation is never zero, even for a player with no income yet", function()
	for _, pack in packs() do
		local c = Shop.fullBagCompensation(pack, 0)
		H.ok(c > 0, pack.id)
		H.eq(c, math.floor(Config.seedIncome(pack.zone) * Config.PACK_FULL_BAG_INCOME_SECONDS))
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
	p.seedBag = { ["1:1"] = 3, ["7:5:Celestial"] = 1, ["6:2:Gold"] = 2 }
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

H.test("data: receipt history keeps the newest RECEIPT_HISTORY ids as grants add more", function()
	local p = ProfileStore.defaultProfile()
	p.seedBag = {}
	for i = 1, Config.RECEIPT_HISTORY + 5 do
		Shop.grantProduct(p, "PackSpace", "h" .. i, 0, seeded(i))
		p.seedBag = {} -- plant them all, so the bag never fills
	end
	H.eq(#p.receipts, Config.RECEIPT_HISTORY)
	H.eq(p.receipts[1], "h6")
	H.eq((Shop.grantProduct(p, "PackSpace", "h" .. (Config.RECEIPT_HISTORY + 5), 0, seeded(1))), "duplicate")
end)
