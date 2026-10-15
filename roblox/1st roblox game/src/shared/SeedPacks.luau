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
	luck: number, -- tilts Common..Epic
	legendaryChance: number, -- 0..1, fixed (never tilted by luck)
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
		legendaryChance = Config.PACK_LEGENDARY_CHANCE,
		mutationMult = Config.PACK_MUTATION_MULT,
		exclusive = Config.PACK_EXCLUSIVE,
		exclusiveChance = Config.PACK_EXCLUSIVE_CHANCE,
	}
end

----------------------------------------------------------------------------------------------------
-- Developer products (Robux): the Config.DEVELOPER_PRODUCTS of kind "Pack" ({ id, label, robux, zone })
----------------------------------------------------------------------------------------------------
-- The pack a "Pack" product opens.
function SeedPacks.packForProduct(product: Config.DevProduct): Pack
	return SeedPacks.zonePack(product.zone :: number)
end

-- A sold pack by its reveal id ("Pack:Space"), or nil.
function SeedPacks.lookup(id: string): Pack?
	for _, entry in Config.products("Pack") do
		local pack = SeedPacks.packForProduct(entry.product)
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
	local weights = Config.rarityWeights(pack.zone, pack.luck, pack.legendaryChance)
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

-- What the Shop's pack card shows as its rewards: one tile per rarity, Common first, with that rarity's
-- exact chance (odds) and the zone's flower of that rarity (`catalog[zone][rarity][1]`, the server's
-- StatsUpdate catalog; nil while it hasn't arrived or a rarity has no plant model: FlowerView's fallback).
-- The Legendary tile is the featured one (big, in a rainbow frame).
export type Tile = { rarity: number, id: string, pct: number, flower: string?, featured: boolean }
function SeedPacks.showcase(pack: Pack, catalog: any): { Tile }
	local odds = SeedPacks.odds(pack)
	local flowers = type(catalog) == "table" and catalog[pack.zone] or nil
	local tiles = {}
	for i, rarity in Config.RARITIES do
		local list = type(flowers) == "table" and flowers[i] or nil
		local flower = type(list) == "table" and list[1] or nil
		table.insert(tiles, {
			rarity = i, id = rarity.id, pct = odds.rarities[i], flower = if type(flower) == "string" then flower else nil,
			featured = i == Config.LEGENDARY,
		})
	end
	return tiles
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
-- Seed bag: { [key] = count } with key "zone:rarity[:Mutation][#gene]". The gene (Config.rollGene, save
-- v10) is the seed's hidden flower and size, so seeds with a gene rarely stack. A key without one (from
-- before v10) is still a seed: PlotService gives it a gene when its Plant button is pressed (so its ghost
-- matches too), or draws its flower when it is planted. The gene is never shown: labels come from
-- seedName, and the Inventory lists seeds by label (labelKey).
----------------------------------------------------------------------------------------------------
function SeedPacks.bagKey(zone: number, rarity: number, mutation: string?, gene: number?): string
	local key = if mutation then `{zone}:{rarity}:{mutation}` else `{zone}:{rarity}`
	return if gene then `{key}#{gene}` else key
end

-- Validates a key from a client or a save. Returns nil for anything malformed; the gene is nil for a key
-- from before v10.
function SeedPacks.parseBagKey(key: any): (number?, number?, string?, number?)
	if type(key) ~= "string" or #key > 32 then
		return nil, nil, nil, nil
	end
	local z, r, m, g = string.match(key, "^(%d+):(%d+):?(%a*)#?(%d*)$")
	local zone, rarity = tonumber(z), tonumber(r)
	if not zone or not rarity or not Config.ZONES[zone] or not Config.RARITIES[rarity] then
		return nil, nil, nil, nil
	end
	local mutation: string? = if m == "" then nil else m
	if mutation and not Config.mutationById(mutation) then
		return nil, nil, nil, nil
	end
	local gene = if g == "" then nil else tonumber(g)
	if gene and (gene < 1 or gene > Config.SEED_GENES) then
		return nil, nil, nil, nil
	end
	if SeedPacks.bagKey(zone, rarity, mutation, gene) ~= key then -- canonical form only ("01:1", "1:1#07" are not keys)
		return nil, nil, nil, nil
	end
	return zone, rarity, mutation, gene
end

-- The key without its gene, "zone:rarity[:Mutation]": seeds with the same label list as one.
function SeedPacks.labelKey(key: string): string
	return (string.gsub(key, "#%d*$", ""))
end

function SeedPacks.bagCount(bag: { [string]: number }): number
	local n = 0
	for _, count in bag do
		n += count
	end
	return n
end

-- Returns the key it went under.
function SeedPacks.addToBag(bag: { [string]: number }, zone: number, rarity: number, mutation: string?, gene: number?): string
	local key = SeedPacks.bagKey(zone, rarity, mutation, gene)
	bag[key] = (bag[key] or 0) + 1
	return key
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

-- What a seed is called until it is planted: "Rare Seed", "Gold Epic Seed". Its flower is a surprise (owner
-- request): its gene decides it, but no label says so until it is planted, and from then on the plant goes
-- by the flower's name. No zone seed name either ("Rare Starpetal" on every pod read repetitive). `zone` is kept
-- so every caller still says which seed it means.
function SeedPacks.seedName(_zone: number, rarity: number, mutation: string?): string
	local prefix = if mutation then mutation .. " " else ""
	return `{prefix}{Config.RARITIES[rarity].id} Seed`
end

return SeedPacks
