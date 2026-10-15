-- Pure: the SELL stall in the shop plaza. What a plant or a seed sells for, and the check + apply of a
-- SellPlants request (the player's plant slots, inventory ids and seed-bag seeds). PlotService does the
-- instance work around it (the distance to the stall, the creature models, the client updates).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local SeedPacks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SeedPacks"))

local Selling = {}

-- One request can't name more slots than a plot can ever have.
Selling.MAX_SLOTS = Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS

-- One request can't name more kinds of seed than there are labels (zone x rarity x mutation or none).
Selling.MAX_SEED_LABELS = #Config.ZONES * #Config.RARITIES * (#Config.MUTATIONS + 1)

-- What the stall pays for `plant` right now: SELL_STALL_SECONDS (10) of its base income, i.e. 10x its $/s (the same formula as
-- PlotService.plantStats, no day/night) x `moneyMult` (plot level, 2x Money). A plant in the inventory sells
-- for the same as it would on the plot (Inventory.asPlant: its growth stopped where it left). `growMult`: the
-- owner's Fast Grow for a planted plant (1 when nil; never for an inventory plant, whose age is stored).
function Selling.price(plant: ProfileStore.Plant, now: number, moneyMult: number, growMult: number?): number
	local variance = Config.varianceOf(plant)
	local weight = Config.plantWeight(plant.zone, plant.rarity, Config.plantAge(plant.plantedAt, now, growMult), variance)
	return Config.plantIncome(plant.zone, plant.rarity, weight, plant.mutation) * Config.SELL_STALL_SECONDS * moneyMult
end

-- A plain list of at most `max` whole numbers (nil counts as empty), or nil.
local function numberList(list: any, max: number): { number }?
	if list == nil then
		return {}
	end
	if type(list) ~= "table" then
		return nil
	end
	local count = 0
	for key, n in list do
		count += 1
		if count > max or type(key) ~= "number" or type(n) ~= "number" or n ~= math.floor(n) then
			return nil
		end
	end
	if count ~= #list then
		return nil -- holes or extra keys: not a plain list
	end
	return list
end

-- The members of `list` that `has` says are there, each once and in request order.
local function present(list: { number }, has: { [number]: boolean }): { number }
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, n in list do
		if has[n] and not seen[n] then
			seen[n] = true
			table.insert(out, n)
		end
	end
	return out
end

-- Checks a request from the client (untrusted): `slots` (planted plants) and `ids` (inventory plants, may be
-- nil) must be plain lists of whole numbers (at most MAX_SLOTS and INVENTORY_MAX), and `distance` (studs
-- from the player to the nearest SELL stall, nil when there is none) at most SELL_STALL_DISTANCE. Returns
-- the slots the player has a plant in and the ids they have in their inventory, each once and in request
-- order (one named twice is sold once; one that is gone, e.g. sold a moment ago, is skipped), or nil and
-- why: "far", "bad" or "none".
function Selling.check(profile: ProfileStore.Profile, slots: any, distance: number?, ids: any?): ({ number }?, { number }?, string?)
	if type(distance) ~= "number" or distance ~= distance or distance > Config.SELL_STALL_DISTANCE then
		return nil, nil, "far"
	end
	local slotList = numberList(slots, Selling.MAX_SLOTS)
	local idList = numberList(ids, Config.INVENTORY_MAX)
	if not slotList or not idList or slots == nil then
		return nil, nil, "bad"
	end
	local planted: { [number]: boolean } = {}
	for _, plant in profile.plants do
		planted[plant.slot] = true
	end
	local stored: { [number]: boolean } = {}
	for _, entry in profile.inventory do
		stored[entry.id] = true
	end
	local outSlots, outIds = present(slotList, planted), present(idList, stored)
	if #outSlots == 0 and #outIds == 0 then
		return nil, nil, "none"
	end
	return outSlots, outIds
end

-- How many seeds the bag holds under a label ("zone:rarity[:Mutation]", SeedPacks.labelKey), whatever
-- their hidden genes.
function Selling.seedsHeld(bag: { [string]: number }, label: string): number
	local n = 0
	for key, count in bag do
		if SeedPacks.labelKey(key) == label then
			n += count
		end
	end
	return n
end

export type SeedSale = { label: string, zone: number, rarity: number, mutation: string?, count: number }

-- Checks the seeds part of a request (untrusted): nil (none), or a map { [label]: count } of at most
-- MAX_SEED_LABELS labels (gene-less bag keys, SeedPacks.labelKey), each a whole count from 1 to
-- SEED_BAG_HARD_MAX. Returns what can be sold, label by label in a fixed order, each count cut down to
-- what the bag holds (a label the player has none of is skipped: nobody sells more than they have), or
-- nil and "bad".
function Selling.seedsWanted(profile: ProfileStore.Profile, seeds: any): ({ SeedSale }?, string?)
	if seeds == nil then
		return {}, nil
	end
	if type(seeds) ~= "table" then
		return nil, "bad"
	end
	local out: { SeedSale } = {}
	local n = 0
	for label, count in seeds do
		n += 1
		if n > Selling.MAX_SEED_LABELS or type(label) ~= "string" or type(count) ~= "number" or count ~= math.floor(count) or count < 1
			or count > Config.SEED_BAG_HARD_MAX then
			return nil, "bad"
		end
		local zone, rarity, mutation, gene = SeedPacks.parseBagKey(label)
		if not zone or not rarity or gene ~= nil then
			return nil, "bad"
		end
		local take = math.min(count, Selling.seedsHeld(profile.seedBag, label))
		if take > 0 then
			table.insert(out, { label = label, zone = zone, rarity = rarity, mutation = mutation, count = take })
		end
	end
	table.sort(out, function(a, b)
		return a.label < b.label
	end)
	return out, nil
end

-- Takes `count` seeds of a label out of the bag (keys in a fixed order). Returns how many it took.
local function takeSeeds(bag: { [string]: number }, label: string, count: number): number
	local keys = {}
	for key in bag do
		if SeedPacks.labelKey(key) == label then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local taken = 0
	for _, key in keys do
		while taken < count and SeedPacks.takeFromBag(bag, key) do
			taken += 1
		end
	end
	return taken
end

export type Sale = { slots: { number }, ids: { number }, seeds: { SeedSale }, seedCount: number, total: number }

-- Checks the request (Selling.check, Selling.seedsWanted) and sells: removes those plants from the plot and
-- the inventory and those seeds from the bag, and pays their price (`growMult`: the owner's Fast Grow, for
-- the planted ones; a seed: Config.seedSellPrice). Returns what was sold, or nil and why (nothing changes
-- then). Nothing in here yields: the check and the change happen together.
function Selling.sell(profile: ProfileStore.Profile, slots: any, distance: number?, now: number, moneyMult: number, ids: any?,
	growMult: number?, seeds: any?): (Sale?, string?)
	local ok, okIds, why = Selling.check(profile, slots, distance, ids)
	if why == "far" or why == "bad" then
		return nil, why
	end
	local seedList, bad = Selling.seedsWanted(profile, seeds)
	if not seedList then
		return nil, bad
	end
	if not ok or not okIds then
		if #seedList == 0 then
			return nil, why
		end
		ok, okIds = {}, {} -- seeds only
	end
	local selling: { [number]: boolean } = {}
	for _, slot in ok do
		selling[slot] = true
	end
	local total = 0
	local kept: { ProfileStore.Plant } = {}
	for _, plant in profile.plants do
		if selling[plant.slot] then
			total += Selling.price(plant, now, moneyMult, growMult)
			selling[plant.slot] = nil -- a (corrupt) profile with two plants in one slot only sells the first
		else
			table.insert(kept, plant)
		end
	end
	table.clear(profile.plants)
	table.move(kept, 1, #kept, 1, profile.plants)
	for _, id in okIds do
		local entry = Inventory.remove(profile, id)
		if entry then
			total += Selling.price(Inventory.asPlant(entry, now), now, moneyMult)
		end
	end
	local seedCount = 0
	for _, sale in seedList do
		sale.count = takeSeeds(profile.seedBag, sale.label, sale.count)
		seedCount += sale.count
		total += sale.count * Config.seedSellPrice(sale.zone, sale.rarity, sale.mutation, moneyMult)
	end
	profile.money += total
	return { slots = ok, ids = okIds, seeds = seedList, seedCount = seedCount, total = total }
end

return Selling
