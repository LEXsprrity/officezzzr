--!strict
-- Pure planting rules shared by the server (PlotService checks every request) and the client (the green/red
-- preview, Planting.client): where on a plot a seed may go. Players plant anywhere on the brown dirt beds of
-- their own plot (parts tagged Role = "PlantBed"), not in fixed slots.
--
-- Positions are kept in the plot's own space: its origin is the "PlotOrigin" attachment (the floor's top
-- centre, looking into the plot from its entrance), x runs across the plot and z along it (+z toward the
-- entrance). Saved plants keep (x, z), so they land in the same place on any plot index, and follow a plot
-- that is moved or turned in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Planting = {}

-- A plant as far as placing goes: where it stands, its rarity (its size) and its id (`slot`).
export type Spot = { x: number, z: number, rarity: number, slot: number? }
export type Reason = "full" | "bed" | "close" | "far"

-- What the server toasts (and the client's hint says) when a spot is refused.
Planting.MESSAGES = {
	full = "Your plot is full! Sell or remove a plant, or upgrade your plot (board at your plot's entrance).",
	bed = "Plant on the brown dirt of your own plot!",
	close = "Too close to another plant: give it room to grow!",
	far = "Walk closer to plant there.",
} :: { [Reason]: string }

-- How far a creature of `rarity` reaches on the ground once full-grown (the biggest variance, like
-- CreatureModels.scaleFor at full weight, its rarity's size multiplier included): the spacing between plants
-- is budgeted on this.
function Planting.radius(rarity: number): number
	local grown = (Config.GROW_MAX_FACTOR * 1.2) ^ Config.CREATURE_GROWTH_EXPONENT * (1 + Config.CREATURE_RARITY_SCALE * (rarity - 1))
	local scale = math.clamp(grown, Config.CREATURE_MIN_SCALE, Config.CREATURE_MAX_SCALE) * Config.creatureSizeMult(rarity)
	return Config.creatureFootprint(rarity) * scale / 2
end

-- How far past its bed's fence gap a full-grown plant of `rarity` may reach: PLANT_FENCE_OVERHANG, more for a
-- bigger one (x its size multiplier: a Legendary 3.75 studs, still well short of the treadmill out front).
function Planting.fenceOverhang(rarity: number): number
	return Config.PLANT_FENCE_OVERHANG * Config.creatureSizeMult(rarity)
end

-- A plant's stem / core footprint: PLANT_CORE_SHARE of its full-grown reach (not its leaves' spread).
function Planting.coreRadius(rarity: number): number
	return Planting.radius(rarity) * Config.PLANT_CORE_SHARE
end

-- How far inside its bed a plant of `rarity` must stand: its core (at least PLANT_BED_MARGIN), or more for a
-- big one, so a full-grown plant reaches at most fenceOverhang past the bed's fence gap.
function Planting.bedMargin(rarity: number): number
	return math.max(Config.PLANT_BED_MARGIN, Planting.coreRadius(rarity), Planting.radius(rarity) - Config.BED_FENCE_GAP - Planting.fenceOverhang(rarity))
end

-- The closest two plants may stand (centre to centre): a tiny core, PLANT_SPACING_SHARE x (radiusA + radiusB),
-- at least PLANT_MIN_GAP. They may touch and their leaves overlap freely; only a spot that would all but hide
-- the other's centre is refused (owner 2026-10-15: "they must be able to touch and nearly stack").
function Planting.minDistance(rarityA: number, rarityB: number): number
	return math.max(Config.PLANT_MIN_GAP, Config.PLANT_SPACING_SHARE * (Planting.radius(rarityA) + Planting.radius(rarityB)))
end

-- Which way a plant faces: `yaw` degrees (turned by the player while placing it, Planting.client) from the
-- way plants have always faced, the plot's entrance. nil or 0: facing the entrance (plants saved before v11).
function Planting.facing(origin: CFrame, yaw: number?): CFrame
	return origin.Rotation * CFrame.Angles(0, math.pi + math.rad(yaw or 0), 0)
end

-- A yaw from the network or a save (untrusted): a finite number, wrapped into 0..360 (rounded to 0.01
-- degree), or nil.
function Planting.normalizeYaw(yaw: any): number?
	if type(yaw) ~= "number" or yaw ~= yaw or math.abs(yaw) > 1e6 then
		return nil
	end
	local y = math.round((yaw % 360) * 100) / 100
	return if y >= 360 then 0 else y
end

-- A world position in the plot's space, and back (on the origin's height).
function Planting.toLocal(origin: CFrame, pos: Vector3): (number, number)
	local rel = origin:PointToObjectSpace(pos)
	return rel.X, rel.Z
end

function Planting.toWorld(origin: CFrame, x: number, z: number): Vector3
	return origin:PointToWorldSpace(Vector3.new(x, 0, z))
end

-- The bed (a part, or anything with CFrame and Size) that `pos` is on, with at least `margin` (default
-- PLANT_BED_MARGIN) of dirt around it, or nil. `pos` may be on the bed's top or a little above or below it.
function Planting.bedAt(beds: { any }, pos: Vector3, margin: number?): any?
	local m = margin or Config.PLANT_BED_MARGIN
	for _, bed in beds do
		local cf: CFrame, size: Vector3 = bed.CFrame, bed.Size
		local rel = cf:PointToObjectSpace(pos)
		if math.abs(rel.X) <= size.X / 2 - m and math.abs(rel.Z) <= size.Z / 2 - m and math.abs(rel.Y) <= size.Y / 2 + 4 then
			return bed
		end
	end
	return nil
end

-- The point on `bed`'s top straight over (or under) `pos`: where a plant stands.
function Planting.surface(bed: any, pos: Vector3): Vector3
	local cf: CFrame, size: Vector3 = bed.CFrame, bed.Size
	local rel = cf:PointToObjectSpace(pos)
	return cf:PointToWorldSpace(Vector3.new(rel.X, size.Y / 2, rel.Z))
end

export type Query = {
	beds: { any }, -- the plot's dirt beds
	origin: CFrame, -- the plot's origin (PlotOrigin)
	plants: { Spot }, -- what is planted already
	pos: Vector3, -- where the new plant would go (world)
	rarity: number, -- the new plant's rarity (its size)
	root: Vector3?, -- where the planter stands; nil skips the reach check (auto-placing)
	limit: number?, -- the plot's slots; nil skips the count check
	ignore: number?, -- a plant id to leave out of the spacing check (the plant being re-placed)
}

-- May a plant go there? Returns true, or false and why: "full" (no slot left), "bed" (not on a bed),
-- "close" (too near another plant) or "far" (out of the planter's reach).
function Planting.check(q: Query): (boolean, Reason?)
	if q.limit and #q.plants >= q.limit then
		return false, "full"
	end
	if not Planting.bedAt(q.beds, q.pos, Planting.bedMargin(q.rarity)) then
		return false, "bed"
	end
	local x, z = Planting.toLocal(q.origin, q.pos)
	for _, p in q.plants do
		if q.ignore ~= nil and p.slot == q.ignore then
			continue
		end
		local dx, dz = p.x - x, p.z - z
		if math.sqrt(dx * dx + dz * dz) < Planting.minDistance(p.rarity, q.rarity) - 1e-6 then
			return false, "close"
		end
	end
	if q.root then
		local flat = Vector3.new(q.root.X - q.pos.X, 0, q.root.Z - q.pos.Z).Magnitude
		if flat > Config.PLANT_REACH then
			return false, "far"
		end
	end
	return true, nil
end

-- A new plant's id: the smallest positive whole number no plant has. Ids name plants in the remove prompt,
-- the Plants menu and the SELL stall, and seed each plant's weight variance.
function Planting.newId(plants: { Spot }): number
	local used: { [number]: boolean } = {}
	for _, p in plants do
		if p.slot then
			used[p.slot] = true
		end
	end
	local id = 1
	while used[id] do
		id += 1
	end
	return id
end

----------------------------------------------------------------------------------------------------
-- The default layout (WorldBuilder builds it; old saves and auto-placing use it)
----------------------------------------------------------------------------------------------------
-- The two beds in the plot's space: one each side of the grass path, from the path out to BED_FENCE_GAP
-- off the fence, front to back. Each is { center, size }; its top is level with the plot's ground (the origin), BED_HEIGHT deep.
function Planting.defaultBeds(): { { center: Vector3, size: Vector3 } }
	local inner = Config.PLOT_PATH_WIDTH / 2
	local outer = Config.PLOT_SIZE / 2 - Config.BED_FENCE_GAP
	local depth = Config.PLOT_SIZE - 2 * Config.BED_FENCE_GAP
	local list = {}
	for _, s in { -1, 1 } do
		table.insert(list, {
			center = Vector3.new(s * (inner + outer) / 2, -Config.BED_HEIGHT / 2, 0), -- its top level with the ground
			size = Vector3.new(outer - inner, Config.BED_HEIGHT, depth),
		})
	end
	return list
end

-- Saves up to format v5 had a fixed grid: 8 columns SLOT_SPACING apart across the plot's middle, rows from
-- 46 studs in from the entrance. An old slot keeps its spot, with each half of the grid pushed out onto its
-- bed (clear of the path), so an old plot keeps its arrangement.
local LEGACY_COLUMNS, LEGACY_ROWS, LEGACY_FIRST_ROW = 8, 5, 46
local LEGACY_MARGIN = 2 -- (the bed margin those spots were made with: kept, so an old save lands as it always did)

function Planting.legacySpot(slot: number): (number, number)
	local row = (slot - 1) // LEGACY_COLUMNS
	local col = (slot - 1) % LEGACY_COLUMNS
	local u = (col - (LEGACY_COLUMNS - 1) / 2) * Config.SLOT_SPACING
	local push = Config.PLOT_PATH_WIDTH / 2 + LEGACY_MARGIN + 1 - Config.SLOT_SPACING / 2
	return u + math.sign(u) * push, Config.PLOT_SIZE / 2 - (LEGACY_FIRST_ROW + row * Config.SLOT_SPACING)
end

-- Where auto-placing tries, in order: the old grid's spots (the back half of the beds), then the same
-- columns on toward the entrance. { x, z } pairs in the plot's space.
local candidateList: { { number } }? = nil
function Planting.candidates(): { { number } }
	if candidateList then
		return candidateList
	end
	local list = {}
	for slot = 1, LEGACY_COLUMNS * LEGACY_ROWS do
		local x, z = Planting.legacySpot(slot)
		table.insert(list, { x, z })
	end
	local front = Config.PLOT_SIZE / 2 - Config.BED_FENCE_GAP - Config.PLANT_BED_MARGIN
	local _, z = Planting.legacySpot(1)
	z += Config.SLOT_SPACING
	while z <= front do
		for col = 1, LEGACY_COLUMNS do
			local x = Planting.legacySpot(col)
			table.insert(list, { x, z })
		end
		z += Config.SLOT_SPACING
	end
	candidateList = list
	return list
end

-- A free spot for a plant of `rarity` on these beds (the first candidate that passes the check, without
-- the reach and count checks), as (x, z), or nil when none is left.
function Planting.autoPlace(beds: { any }, origin: CFrame, plants: { Spot }, rarity: number, ignore: number?): (number?, number?)
	for _, c in Planting.candidates() do
		local pos = Planting.toWorld(origin, c[1], c[2])
		if Planting.check({ beds = beds, origin = origin, plants = plants, pos = pos, rarity = rarity, ignore = ignore }) then
			return c[1], c[2]
		end
	end
	return nil, nil
end

-- Makes sure every plant stands on a bed, apart from the others (a save from another map, a bed moved in
-- Studio, an old save): plants are taken in id order, and one that doesn't fit where it is is moved to a
-- free spot (autoPlace). One with no free spot left keeps its place. Changes x/z in place; returns how many
-- plants moved.
function Planting.settle(beds: { any }, origin: CFrame, plants: { Spot }): number
	local order = table.clone(plants)
	table.sort(order, function(a, b)
		return (a.slot or 0) < (b.slot or 0)
	end)
	local placed: { Spot } = {}
	local moved = 0
	for _, p in order do
		local pos = Planting.toWorld(origin, p.x, p.z)
		if not Planting.check({ beds = beds, origin = origin, plants = placed, pos = pos, rarity = p.rarity }) then
			local x, z = Planting.autoPlace(beds, origin, placed, p.rarity)
			if x and z then
				p.x, p.z = x, z
				moved += 1
			end
		end
		table.insert(placed, p)
	end
	return moved
end

return Planting
