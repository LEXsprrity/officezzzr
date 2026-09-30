--!strict
-- Seed packs ("eggs with odds"): prices, the visible odds table, rolls, the server-wide featured
-- rotation and the seed-bag key format. Pure and shared, so the Shop UI shows exactly the odds the
-- server rolls with, and the featured countdown needs no remote.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SeedPacks = {}

export type Pack = {
	id: string, -- RequestBuy item id: "Pack:<zoneId>" or "Pack:Featured:<slot>"
	zone: number,
	featured: boolean,
	slot: number?, -- featured rotation slot
	name: string,
	price: number,
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

-- Two significant figures, so prices read like "$40K" / "$1.2K".
function SeedPacks.roundPrice(x: number): number
	if x <= 0 then
		return 0
	end
	local step = 10 ^ math.max(0, math.floor(math.log10(x)) - 1)
	return math.floor(x / step + 0.5) * step
end

-- Priced like the rest of the economy: PACK_INCOME_SECONDS of a Common zone-k plant's income.
function SeedPacks.basePrice(k: number): number
	return SeedPacks.roundPrice(Config.seedIncome(k) * Config.PACK_INCOME_SECONDS)
end

function SeedPacks.zonePack(k: number): Pack
	local zone = Config.ZONES[k]
	return {
		id = "Pack:" .. zone.id,
		zone = k,
		featured = false,
		slot = nil,
		name = `{zone.seed} Pack`,
		price = SeedPacks.basePrice(k),
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
		price = SeedPacks.roundPrice(SeedPacks.basePrice(k) * Config.FEATURED_PRICE_MULT),
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

-- A pack the player may buy right now. Featured ids carry their slot, so a click from a stale menu
-- (the pack rotated while it was open) is refused instead of buying a different pack.
function SeedPacks.fromId(id: string, now: number): (Pack?, string?)
	local pack = SeedPacks.lookup(id)
	if not pack then
		return nil, "Unknown pack"
	end
	if pack.featured and pack.slot ~= SeedPacks.featuredSlot(now) then
		return nil, "The featured pack just rotated! Check out the new one."
	end
	return pack, nil
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
