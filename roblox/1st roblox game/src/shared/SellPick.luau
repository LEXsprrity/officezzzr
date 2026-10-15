--!strict
-- Pure: what the Sell window (the SELL stall, HUD) lists and what each of its buttons sells. Everything the
-- stall buys, from the client's stats: planted plants ("p<slot>"), plants in the Inventory ("i<id>") and
-- seed-bag seeds by label ("s<zone:rarity[:Mutation]>": seeds differ only by their hidden gene, so they
-- list and sell as one). A sale is the SellPlants remote's three arguments (plant slots, inventory ids,
-- { [label]: count }) and what it should pay; the server re-checks all of it (Selling).
-- The quick sells: one button per rarity, Common to Epic, and "Sell all" (every rarity but Legendary,
-- which is never quick-sold); mutated plants and seeds only with "include mutated" on.
local Config = require(script.Parent:WaitForChild("Config"))
local SeedPacks = require(script.Parent:WaitForChild("SeedPacks"))

local SellPick = {}

export type Item = {
	key: string,
	kind: "plant" | "inv" | "seed",
	slot: number?, -- plant
	id: number?, -- inv
	label: string?, -- seed: its bag label
	gene: number?, -- seed: one of its genes (the seed design it shows)
	zone: number,
	rarity: number,
	mutation: string?,
	count: number, -- seeds held (1 for a plant)
	sell: number, -- what one sells for now
	src: any, -- the plants view entry (plants and inventory)
}

export type Group = { id: string, label: string, rarity: number? } -- rarity nil: every one but Legendary
SellPick.GROUPS = {} :: { Group }
for r = 1, Config.LEGENDARY - 1 do
	local id = Config.RARITIES[r].id
	table.insert(SellPick.GROUPS, { id = id, label = `Sell {id}`, rarity = r })
end
table.insert(SellPick.GROUPS, { id = "All", label = "Sell all" })

function SellPick.group(id: string?): Group?
	for _, g in SellPick.GROUPS do
		if g.id == id then
			return g
		end
	end
	return nil
end

-- What one seed of (zone, rarity, mutation) sells for, with the player's money multiplier (plot level and
-- money passes, as the server's Sessions.moneyMult).
function SellPick.seedPrice(stats: { [string]: any }, zone: number, rarity: number, mutation: string?): number
	return Config.seedSellPrice(zone, rarity, mutation, Config.moneyMult(stats.plotLevel or 1, stats.passes))
end

-- Everything the stall can buy, plants first (the server's prices), then the seeds.
function SellPick.items(stats: { [string]: any }): { Item }
	local out: { Item } = {}
	for _, p in stats.plants or {} do
		table.insert(out, { key = `p{p.slot}`, kind = "plant", slot = p.slot, zone = p.zone, rarity = p.rarity, mutation = p.mutation, count = 1, sell = p.sell or 0, src = p })
	end
	for _, p in stats.inventory or {} do
		table.insert(out, { key = `i{p.id}`, kind = "inv", id = p.id, zone = p.zone, rarity = p.rarity, mutation = p.mutation, count = 1, sell = p.sell or 0, src = p })
	end
	local byLabel: { [string]: Item } = {}
	local labels: { string } = {}
	for key, count in stats.seedBag or {} do
		local zone, rarity, mutation, gene = SeedPacks.parseBagKey(key)
		if zone and rarity and type(count) == "number" and count > 0 then
			local label = SeedPacks.labelKey(key)
			local item = byLabel[label]
			if item then
				item.count += count
				if gene and (item.gene == nil or gene < item.gene) then
					item.gene = gene -- (a fixed one of its genes, so its picture never flickers)
				end
			else
				byLabel[label] = { key = `s{label}`, kind = "seed", label = label, gene = gene, zone = zone, rarity = rarity, mutation = mutation, count = count,
					sell = SellPick.seedPrice(stats, zone, rarity, mutation), src = nil }
				table.insert(labels, label)
			end
		end
	end
	table.sort(labels)
	for _, label in labels do
		table.insert(out, byLabel[label])
	end
	return out
end

-- Whether a quick sell takes this item.
function SellPick.matches(item: Item, group: Group, includeMutated: boolean): boolean
	if item.rarity >= Config.LEGENDARY or (item.mutation ~= nil and not includeMutated) then
		return false
	end
	return group.rarity == nil or item.rarity == group.rarity
end

-- A pending sale: one item (`key`; a seed's `count`, all of them when nil) or a quick sell (`group`).
export type Pick = { key: string?, count: number?, group: string?, mutated: boolean? }

export type Sale = { slots: { number }, ids: { number }, seeds: { [string]: number }, total: number, count: number }

-- What `pick` sells out of `items`: the SellPlants arguments, what it pays and how many things it sells.
function SellPick.sale(items: { Item }, pick: Pick): Sale
	local out: Sale = { slots = {}, ids = {}, seeds = {}, total = 0, count = 0 }
	local group = SellPick.group(pick.group)
	for _, item in items do
		local n = 0
		if pick.key ~= nil and item.key == pick.key then
			n = if item.kind == "seed" then math.clamp(pick.count or item.count, 0, item.count) else 1
		elseif group and SellPick.matches(item, group, pick.mutated == true) then
			n = item.count
		end
		if n > 0 then
			if item.kind == "plant" then
				table.insert(out.slots, item.slot :: number)
			elseif item.kind == "inv" then
				table.insert(out.ids, item.id :: number)
			else
				out.seeds[item.label :: string] = n
			end
			out.total += item.sell * n
			out.count += n
		end
	end
	return out
end

return SellPick
