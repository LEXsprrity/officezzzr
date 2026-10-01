--!strict
-- Seed packs ("eggs with odds"): the visible odds table, rolls, the server-wide featured rotation,
-- the developer products that sell packs (Robux only) and the seed-bag key format. Pure and shared,
-- so the Shop UI shows exactly the odds the server rolls with, and the featured countdown needs no
-- remote.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SeedPacks = {}

export type Pack = {
	id: string, -- reveal id: "Pack:<zoneId>" or "Pack:Featured:<slot>"
	zone: number,
	featured: boolean,
	slot: number?, -- featured rotation slot
	name: string,
	luck: number,
	mutationMult: number,
	exclusive: string?, -- featured-only mutation id
	exclusiveChance: number,
}

export type Odds = {
	rarities: { number }, -- percent per Config.RARITIES index; sums to 100
	mutations: { { id: string, pct: number } }, -- percent each, in roll order
	noMutation: number, -- percent; mutations + noMutation sum to 100
}

function SeedPacks.zonePack(k: number): Pack
	local zone = Config.ZONES[k]
	return {
		id = "Pack:" .. zone.id,
		zone = k,
		featured = false,
		slot = nil,
		name = `{zone.seed} Pack`,
		luck = Config.PACK_LUCK,
		mutationMult = Config.PACK_MUTATION_MULT,
		exclusive = nil,
		exclusiveChance = 0,
	}
end

----------------------------------------------------------------------------------------------------
-- Featured rotation: slot = floor(os.time / period). Zones come in shuffled cycles of #ZONES slots
-- (each zone once per cycle, never the same zone twice in a row), from a fixed-seed PRNG, so every
-- server computes the same pack without talking to each other.
----------------------------------------------------------------------------------------------------
function SeedPacks.featuredSlot(now: number): number
	return math.floor(now / Config.FEATURED_ROTATION_SECONDS)
end

function SeedPacks.slotEndsAt(slot: number): number
	return (slot + 1) * Config.FEATURED_ROTATION_SECONDS
end

local function cycleOrder(cycle: number): { number }
	-- MINSTD (Park-Miller): products stay below 2^53, so it's exact on every platform.
	local state = (cycle * 7919 + Config.FEATURED_SEED) % 2147483646 + 1
	local function nextInt(n: number): number
		state = (state * 48271) % 2147483647
		return state % n
	end
	for _ = 1, 3 do
		nextInt(2)
	end
	local order = {}
	for k = 1, #Config.ZONES do
		order[k] = k
	end
	for i = #order, 2, -1 do
		local j = nextInt(i) + 1
		order[i], order[j] = order[j], order[i]
	end
	return order
end

function SeedPacks.featuredZone(slot: number): number
	local n = #Config.ZONES
	local cycle = slot // n
	local i = slot % n + 1
	local order = cycleOrder(cycle)
	-- The last zone of the previous cycle must not open this one.
	if order[1] == cycleOrder(cycle - 1)[n] then
		order[1], order[2] = order[2], order[1]
	end
	return order[i]
end

function SeedPacks.featuredPackForSlot(slot: number): Pack
	local k = SeedPacks.featuredZone(slot)
	local zone = Config.ZONES[k]
	return {
		id = `Pack:Featured:{slot}`,
		zone = k,
		featured = true,
		slot = slot,
		name = `Featured {zone.seed} Pack`,
		luck = Config.FEATURED_LUCK,
		mutationMult = Config.FEATURED_MUTATION_MULT,
		exclusive = Config.FEATURED_EXCLUSIVE,
		exclusiveChance = Config.FEATURED_EXCLUSIVE_CHANCE,
	}
end

function SeedPacks.featuredPack(now: number): Pack
	return SeedPacks.featuredPackForSlot(SeedPacks.featuredSlot(now))
end

-- Any pack by id, without checking that a featured slot is current (for displaying results).
function SeedPacks.lookup(id: string): Pack?
	local slot = tonumber(string.match(id, "^Pack:Featured:(%d+)$"))
	if slot then
		return SeedPacks.featuredPackForSlot(slot)
	end
	local zoneId = string.match(id, "^Pack:(%a+)$")
	for k, zone in Config.ZONES do
		if zone.id == zoneId then
			return SeedPacks.zonePack(k)
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Developer products (Robux): Config.DEVELOPER_PRODUCTS[name] = { id, label, robux, packs, zone? }
----------------------------------------------------------------------------------------------------
-- The product with this (non-zero) developer product id, as (name, product).
function SeedPacks.productById(productId: number): (string?, Config.DevProduct?)
	if productId == 0 then
		return nil, nil
	end
	for name, product in Config.DEVELOPER_PRODUCTS do
		if product.id == productId then
			return name, product
		end
	end
	return nil, nil
end

-- The product that sells zone k's pack, as (name, product).
function SeedPacks.zoneProduct(k: number): (string?, Config.DevProduct?)
	for name, product in Config.DEVELOPER_PRODUCTS do
		if product.zone == k then
			return name, product
		end
	end
	return nil, nil
end

-- Featured-pack products, smallest bundle first.
function SeedPacks.featuredProducts(): { { name: string, product: Config.DevProduct } }
	local list = {}
	for name, product in Config.DEVELOPER_PRODUCTS do
		if product.zone == nil then
			table.insert(list, { name = name, product = product })
		end
	end
	table.sort(list, function(a, b)
		return a.product.packs < b.product.packs
	end)
	return list
end

-- The pack a product opens: its zone pack, or the featured pack of `featuredSlot`.
function SeedPacks.packForProduct(product: Config.DevProduct, featuredSlot: number): Pack
	if product.zone then
		return SeedPacks.zonePack(product.zone)
	end
	return SeedPacks.featuredPackForSlot(featuredSlot)
end

-- Which featured slot a receipt opens. The player gets the pack they were shown when they clicked
-- Buy (`promptedSlot`, recorded by the server at `promptedAt`), even if it rotated while the Robux
-- dialog was open, as long as the receipt arrives within FEATURED_PROMPT_GRACE seconds. Otherwise
-- (receipt replayed on a later join, or on another server) it's the current featured pack.
function SeedPacks.receiptSlot(promptedSlot: number?, promptedAt: number?, now: number): number
	local current = SeedPacks.featuredSlot(now)
	if promptedSlot and promptedAt and now - promptedAt >= 0 and now - promptedAt <= Config.FEATURED_PROMPT_GRACE
		and promptedSlot <= current and promptedSlot >= current - 1 then
		return promptedSlot
	end
	return current
end

----------------------------------------------------------------------------------------------------
-- Odds and rolls
----------------------------------------------------------------------------------------------------
function SeedPacks.odds(pack: Pack): Odds
	local weights = Config.rarityWeights(pack.zone, pack.luck)
	local total = 0
	for _, w in weights do
		total += w
	end
	local rarities = {}
	for i, w in weights do
		rarities[i] = w / total * 100
	end
	local mutations = {}
	local sum = 0
	if pack.exclusive and pack.exclusiveChance > 0 then
		table.insert(mutations, { id = pack.exclusive, pct = pack.exclusiveChance * 100 })
		sum += pack.exclusiveChance * 100
	end
	for _, mut in Config.MUTATIONS do
		if not mut.nightOnly and not mut.exclusive and mut.chance > 0 then
			local pct = mut.chance * pack.mutationMult * 100
			table.insert(mutations, { id = mut.id, pct = pct })
			sum += pct
		end
	end
	return { rarities = rarities, mutations = mutations, noMutation = 100 - sum }
end

-- Rolls (rarity index, mutation id?) with an injectable rng: rng() -> [0, 1).
function SeedPacks.roll(pack: Pack, rng: () -> number): (number, string?)
	local odds = SeedPacks.odds(pack)
	local pick = rng() * 100
	local rarity = #odds.rarities
	for i, pct in odds.rarities do
		pick -= pct
		if pick < 0 then
			rarity = i
			break
		end
	end
	local m = rng() * 100
	for _, mut in odds.mutations do
		if m < mut.pct then
			return rarity, mut.id
		end
		m -= mut.pct
	end
	return rarity, nil
end

-- "58.3%", "4%", "0.5%", "0.04%"
function SeedPacks.percent(pct: number): string
	local s = if pct >= 10 then string.format("%.1f", pct) elseif pct >= 1 then string.format("%.2f", pct) else string.format("%.2g", pct)
	if string.find(s, ".", 1, true) and not string.find(s, "e", 1, true) then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s .. "%"
end

----------------------------------------------------------------------------------------------------
-- Seed bag: { [key] = count } with key "zone:rarity" or "zone:rarity:Mutation"
----------------------------------------------------------------------------------------------------
function SeedPacks.bagKey(zone: number, rarity: number, mutation: string?): string
	return if mutation then `{zone}:{rarity}:{mutation}` else `{zone}:{rarity}`
end

-- Validates a key from a client or a save. Returns nil for anything malformed.
function SeedPacks.parseBagKey(key: any): (number?, number?, string?)
	if type(key) ~= "string" or #key > 32 then
		return nil, nil, nil
	end
	local z, r, m = string.match(key, "^(%d+):(%d+):?(%a*)$")
	local zone, rarity = tonumber(z), tonumber(r)
	if not zone or not rarity or not Config.ZONES[zone] or not Config.RARITIES[rarity] then
		return nil, nil, nil
	end
	local mutation: string? = if m == "" then nil else m
	if mutation and not Config.mutationById(mutation) then
		return nil, nil, nil
	end
	if SeedPacks.bagKey(zone, rarity, mutation) ~= key then -- canonical form only ("01:1" is not a key)
		return nil, nil, nil
	end
	return zone, rarity, mutation
end

function SeedPacks.bagCount(bag: { [string]: number }): number
	local n = 0
	for _, count in bag do
		n += count
	end
	return n
end

function SeedPacks.addToBag(bag: { [string]: number }, zone: number, rarity: number, mutation: string?)
	local key = SeedPacks.bagKey(zone, rarity, mutation)
	bag[key] = (bag[key] or 0) + 1
end

function SeedPacks.takeFromBag(bag: { [string]: number }, key: string): boolean
	local n = bag[key] or 0
	if n <= 0 then
		return false
	end
	if n > 1 then
		bag[key] = n - 1
	else
		bag[key] = nil :: any
	end
	return true
end

function SeedPacks.seedName(zone: number, rarity: number, mutation: string?): string
	local prefix = if mutation then mutation .. " " else ""
	return `{prefix}{Config.RARITIES[rarity].id} {Config.ZONES[zone].seed}`
end

return SeedPacks
