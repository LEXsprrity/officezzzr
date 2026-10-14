-- Pure: the SELL stall in the shop plaza. What a plant sells for, and the check + apply of a SellPlants
-- request (a list of the player's plant slots). PlotService does the instance work around it (the
-- distance to the stall, the creature models, the client updates).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))

local Selling = {}

-- One request can't name more slots than a plot can ever have.
Selling.MAX_SLOTS = Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS

-- What the stall pays for `plant` right now: SELL_STALL_SECONDS of its base income (the same formula as
-- PlotService.plantStats, no day/night) x `moneyMult` (plot level, 2x Money). A plant in the inventory sells
-- for the same as it would on the plot (Inventory.asPlant: its growth stopped where it left).
function Selling.price(plant: ProfileStore.Plant, now: number, moneyMult: number): number
	local variance = Config.varianceOf(plant)
	local weight = Config.plantWeight(plant.zone, plant.rarity, now - plant.plantedAt, variance)
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

export type Sale = { slots: { number }, ids: { number }, total: number }

-- Checks the request (Selling.check) and sells: removes those plants from the plot and the inventory and
-- pays their price. Returns what was sold, or nil and why (nothing changes then).
function Selling.sell(profile: ProfileStore.Profile, slots: any, distance: number?, now: number, moneyMult: number, ids: any?): (Sale?, string?)
	local ok, okIds, why = Selling.check(profile, slots, distance, ids)
	if not ok or not okIds then
		return nil, why
	end
	local selling: { [number]: boolean } = {}
	for _, slot in ok do
		selling[slot] = true
	end
	local total = 0
	local kept: { ProfileStore.Plant } = {}
	for _, plant in profile.plants do
		if selling[plant.slot] then
			total += Selling.price(plant, now, moneyMult)
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
	profile.money += total
	return { slots = ok, ids = okIds, total = total }
end

return Selling
