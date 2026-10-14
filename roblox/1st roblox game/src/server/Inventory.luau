-- Pure: the plant inventory (profile.inventory, at most Config.INVENTORY_MAX). The Plants panel's Remove
-- takes a plant off the plot into it, as it was: its flower, mutation and growth (its age stops there and
-- its variance is kept, so its weight stays). From there it is planted again (PlotService.plantAt, the same
-- placement as a seed) or sold at the SELL stall (Selling.sell, the stall's price). Every request is
-- untrusted: ids and slots are checked against the player's own profile. PlotService does the instance
-- work around it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))
local SeedPacks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SeedPacks"))

local Inventory = {}

local function whole(v: any): boolean
	return type(v) == "number" and v == math.floor(v) and math.abs(v) <= 1e9
end

-- The entry with this id (untrusted), and where it is in the list.
function Inventory.find(profile: ProfileStore.Profile, id: any): (ProfileStore.InvPlant?, number?)
	if not whole(id) then
		return nil, nil
	end
	for i, entry in profile.inventory do
		if entry.id == id then
			return entry, i
		end
	end
	return nil, nil
end

function Inventory.isFull(profile: ProfileStore.Profile): boolean
	return #profile.inventory >= Config.INVENTORY_MAX
end

-- Takes the player's plant in `slot` (untrusted) off the plot into the inventory: no money (owner request:
-- Remove never sells). Returns the new entry, or nil and why: "bad" (not a slot number), "none" (no plant
-- of theirs there) or "full"; nothing changes then. `growMult`: the owner's Fast Grow (1 when nil), so it keeps
-- the growth it had.
function Inventory.take(profile: ProfileStore.Profile, slot: any, now: number, growMult: number?): (ProfileStore.InvPlant?, string?)
	if not whole(slot) then
		return nil, "bad"
	end
	for i, plant in profile.plants do
		if plant.slot == slot then
			if Inventory.isFull(profile) then
				return nil, "full"
			end
			local id = 1
			for _, entry in profile.inventory do
				id = math.max(id, entry.id + 1)
			end
			local entry: ProfileStore.InvPlant = {
				id = id, zone = plant.zone, rarity = plant.rarity, mutation = plant.mutation,
				variant = plant.variant, age = math.clamp(Config.plantAge(plant.plantedAt, now, growMult), 0, Config.GROW_TIME),
				variance = Config.varianceOf(plant),
			}
			table.remove(profile.plants, i)
			table.insert(profile.inventory, entry)
			return entry
		end
	end
	return nil, "none"
end

-- The plant an entry grows back into, planted at (x, z) under id `slot` at `now`: the same flower,
-- mutation and variance, its growth going on from where it stopped (at the owner's `growMult`, Fast Grow: its
-- plantedAt is set back by its age in real seconds at that rate; 1 when nil).
function Inventory.toPlant(entry: ProfileStore.InvPlant, slot: number, now: number, x: number, z: number, growMult: number?): ProfileStore.Plant
	return {
		slot = slot, zone = entry.zone, rarity = entry.rarity, mutation = entry.mutation, plantedAt = now - entry.age / (growMult or 1),
		x = x, z = z, variant = entry.variant, variance = entry.variance,
	}
end

-- Removes the entry with this id (untrusted). Returns it, or nil.
function Inventory.remove(profile: ProfileStore.Profile, id: any): ProfileStore.InvPlant?
	local entry, i = Inventory.find(profile, id)
	if entry and i then
		table.remove(profile.inventory, i)
	end
	return entry
end

-- Its weight, as it was when it left the plot.
function Inventory.weight(entry: ProfileStore.InvPlant): number
	return Config.plantWeight(entry.zone, entry.rarity, entry.age, entry.variance)
end

-- The plant it stands for at `now` (for prices: Selling.price), never put in the profile.
function Inventory.asPlant(entry: ProfileStore.InvPlant, now: number): ProfileStore.Plant
	return Inventory.toPlant(entry, 0, now, 0, 0)
end

-- A stolen seed carried home (`home`: in the base, out of the corridor) always goes into the seed bag by
-- itself, free plot slots or not (owner request), so it never stays on the thief's back: "store".
-- Otherwise why not: "away" (still in the corridor) or "bagFull" (SEED_BAG_MAX: it stays carried, and the
-- Inventory and the planting hint say so).
export type CarryHome = "store" | "away" | "bagFull"
function Inventory.carryHome(profile: ProfileStore.Profile, home: boolean): CarryHome
	if not home then
		return "away"
	elseif SeedPacks.bagCount(profile.seedBag) >= Config.SEED_BAG_MAX then
		return "bagFull"
	end
	return "store"
end

-- Whether a player standing at `pos` is home: in the base, out of the corridor (where the guards stop).
function Inventory.isHome(pos: Vector3): boolean
	return pos.X < Config.CORRIDOR_START_X
end

-- Whether a player at `pos` is out past the corridor's side walls or its back wall (with OFF_COURSE_MARGIN
-- studs for the walls' thickness). The walls are WALL_HEIGHT tall, so only flying or clipping gets there,
-- and no guard can follow (they chase inside the walls): a seed carried there goes back to its pod.
Inventory.OFF_COURSE_MARGIN = 8
function Inventory.offCourse(pos: Vector3): boolean
	if pos.X < Config.CORRIDOR_START_X then
		return false -- the base
	end
	return math.abs(pos.Z) > Config.CORRIDOR_WIDTH / 2 + Inventory.OFF_COURSE_MARGIN or pos.X > Config.END_X + Inventory.OFF_COURSE_MARGIN
end

return Inventory
