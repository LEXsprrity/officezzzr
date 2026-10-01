--!strict
-- Seed packs ("eggs with odds"): the two premium packs, their visible odds table, rolls, the
-- developer products that sell them (Robux only) and the seed-bag key format. Pure and shared, so the
-- Shop UI shows exactly the odds the server rolls with.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SeedPacks = {}

export type Pack = {
	id: string, -- reveal id: "Pack:<zoneId>"
	zone: number,
	name: string,
	luck: number,
	mutationMult: number,
	exclusive: string?, -- pack-only mutation id (never from pods)
	exclusiveChance: number,
}

export type Odds = {
	rarities: { number }, -- percent per Config.RARITIES index; sums to 100
	mutations: { { id: string, pct: number } }, -- percent each, in roll order
	noMutation: number, -- percent; mutations + noMutation sum to 100
}

-- The pack that rolls zone k's seed.
function SeedPacks.zonePack(k: number): Pack
	local zone = Config.ZONES[k]
	return {
		id = "Pack:" .. zone.id,
		zone = k,
		name = `{zone.seed} Pack`,
		luck = Config.PACK_LUCK,
		mutationMult = Config.PACK_MUTATION_MULT,
		exclusive = Config.PACK_EXCLUSIVE,
		exclusiveChance = Config.PACK_EXCLUSIVE_CHANCE,
	}
end

----------------------------------------------------------------------------------------------------
-- Developer products (Robux): Config.DEVELOPER_PRODUCTS[name] = { id, label, robux, zone }
----------------------------------------------------------------------------------------------------
-- Every product, by zone (the Shop's card order).
function SeedPacks.products(): { { name: string, product: Config.DevProduct } }
	local list = {}
	for name, product in Config.DEVELOPER_PRODUCTS do
		table.insert(list, { name = name, product = product })
	end
	table.sort(list, function(a, b)
		return a.product.zone < b.product.zone
	end)
	return list
end

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

-- The pack a product opens.
function SeedPacks.packForProduct(product: Config.DevProduct): Pack
	return SeedPacks.zonePack(product.zone)
end

-- A sold pack by its reveal id ("Pack:Space"), or nil.
function SeedPacks.lookup(id: string): Pack?
	for _, product in Config.DEVELOPER_PRODUCTS do
		local pack = SeedPacks.packForProduct(product)
		if pack.id == id then
			return pack
		end
	end
	return nil
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
