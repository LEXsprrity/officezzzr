-- Pure: the SELL stall in the shop plaza. What a plant sells for, and the check + apply of a SellPlants
-- request (a list of the player's plant slots). PlotService does the instance work around it (the
-- distance to the stall, the creature models, the client updates).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))

local Selling = {}

-- One request can't name more slots than a plot can ever have.
Selling.MAX_SLOTS = Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS

-- What the stall pays for `plant` right now: SELL_STALL_SECONDS of its base income (the same formula as
-- PlotService.plantStats, no day/night, like the R-key refund) x `moneyMult` (plot level, 2x Money).
function Selling.price(plant: ProfileStore.Plant, now: number, moneyMult: number): number
	local variance = Config.plantVariance(plant.plantedAt, plant.slot)
	local weight = Config.plantWeight(plant.zone, plant.rarity, now - plant.plantedAt, variance)
	return Config.plantIncome(plant.zone, plant.rarity, weight, plant.mutation) * Config.SELL_STALL_SECONDS * moneyMult
end

-- Checks a request from the client (untrusted): `slots` must be a plain list of at most MAX_SLOTS whole
-- numbers, and `distance` (studs from the player to the nearest SELL stall, nil when there is none) at
-- most SELL_STALL_DISTANCE. Returns the slots the player has a plant in, each once and in request order
-- (a slot named twice is sold once; a slot with no plant, e.g. sold a moment ago, is skipped), or nil
-- and why: "far", "bad" or "none".
function Selling.check(profile: ProfileStore.Profile, slots: any, distance: number?): ({ number }?, string?)
	if type(distance) ~= "number" or distance ~= distance or distance > Config.SELL_STALL_DISTANCE then
		return nil, "far"
	end
	if type(slots) ~= "table" then
		return nil, "bad"
	end
	local count = 0
	for key, slot in slots do
		count += 1
		if count > Selling.MAX_SLOTS or type(key) ~= "number" or type(slot) ~= "number" or slot ~= math.floor(slot) then
			return nil, "bad"
		end
	end
	if count ~= #slots then
		return nil, "bad" -- holes or extra keys: not a plain list
	end
	local planted: { [number]: boolean } = {}
	for _, plant in profile.plants do
		planted[plant.slot] = true
	end
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, slot in slots do
		if planted[slot] and not seen[slot] then
			seen[slot] = true
			table.insert(out, slot)
		end
	end
	if #out == 0 then
		return nil, "none"
	end
	return out
end

export type Sale = { slots: { number }, total: number }

-- Checks the request (Selling.check) and sells: removes those plants from the profile and pays their
-- price. Returns what was sold, or nil and why (nothing changes then).
function Selling.sell(profile: ProfileStore.Profile, slots: any, distance: number?, now: number, moneyMult: number): (Sale?, string?)
	local ok, why = Selling.check(profile, slots, distance)
	if not ok then
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
	profile.money += total
	return { slots = ok, total = total }
end

return Selling
