-- Per-zone art for the corridor: each zone's studded floor and walls, its set pieces and its particle
-- ambience. WorldBuilder calls ZoneThemes.build for each zone; each zone keeps its nest's corner clear
-- (nestKeepOut). There are no gates, arches or zone signs (owner playtest): one zone flows into the next by
-- its floor and wall colours.
--
-- Each zone lives in its own module, Zones/<Zone> (its colours and build), on the shared kit Zones/Kit.
--
-- Art direction (owner playtest, docs/references): a game for kids, clean and cartoony, never realistic.
--   * the classic studded plastic everywhere: the floor (a big checker), the tall walls (a checker on their
--     inner face, a cap in the zone's accent colour along the top) and every prop (Props.block)
--   * each zone's walls a darker shade of its ground, and distinct from every other zone's
--   * rich zones: 3-6 strong set pieces each (a stepped volcano altar with fire and lava, a pyramid, a
--     waterfall...) and small details scattered between them, every shape built from many offset blocks at
--     different heights, never one plain box or cylinder
--   * Neon only where something glows: lava, glowing crystals, lamps; never as strips or rings on the floor
--
-- Layout rules that keep the corridor playable:
--   * only the floor and the two walls (and the Spirit Garden's back wall) collide;
--     every prop is a non-colliding "ghost" (see Props)
--   * set pieces stand along the walls; the middle of the corridor only gets flat things on the floor (lava
--     pools, stepping stones), so the run and the guards' chase line stay clear
--   * no prop in a nest's corner (nestKeepOut), where the boss sleeps by its pods and the Speed plank
--   * part and emitter counts are budgeted (tests/world.spec.luau and tests/zones.spec.luau)
--   * each distinctive prop is an asset slot ("Desert_Cactus", ...; see Assets.swap): its random draws
--     happen inside the build function, so a drop-in model never shifts the rest of the layout
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Assets = require(script.Parent:WaitForChild("Assets"))
local Zones = script.Parent:WaitForChild("Zones")
local Kit = require(Zones:WaitForChild("Kit"))

local ZoneThemes = {}

ZoneThemes.EDGE_WIDTH = Kit.EDGE_WIDTH
ZoneThemes.EDGE_LIGHTEN = Kit.EDGE_LIGHTEN
ZoneThemes.POND_SINK = Kit.POND_SINK

export type Theme = Kit.Theme

local THEMES: { [string]: Theme } = {}
for _, zone in Config.ZONES do
	THEMES[zone.id] = require(Zones:WaitForChild(zone.id)) :: any
end

function ZoneThemes.theme(k: number): Theme
	return THEMES[Config.ZONES[k].id]
end

-- The nest's corner (Config.nestCenter), as world bounds x0, x1, z0, z1: the boss sleeping against the left
-- wall (GUARD_HOME_OFFSET along, its body reaching ~24 studs either way), its pods by its right flank and
-- the Speed plank by its nose. No prop stands in it (pruneNest), so nothing pokes through the boss and
-- nothing lies under the pods; the floor, the walls and what runs along them (caps, vines, icicles, the
-- sky's planets) stay.
function ZoneThemes.nestKeepOut(k: number): (number, number, number, number)
	local c = Config.nestCenter(k)
	if Config.nestSide(k) > 0 then -- (a nest against the right wall, Config.NEST_RIGHT: mirrored)
		return c.X - 28, c.X + Config.GUARD_HOME_OFFSET + 24, c.Z - 36, Kit.HALF_W
	end
	return c.X - 28, c.X + Config.GUARD_HOME_OFFSET + 24, -Kit.HALF_W, c.Z + 36
end

local KEEP = {
	Floor = true, FloorTile = true, ZoneEdge = true, Wall = true, WallTile = true, WallCap = true,
	Roof = true, RoofTile = true, RoofTrim = true, Ambience = true, Icicle = true, Vine = true, VineLeaf = true,
}

-- Removes the zone's props that reach into its nest's corner. It runs after the theme has built, so no
-- random draw moves and the rest of the zone keeps its layout. (The zones place their set pieces clear of
-- it; tests/zones.spec checks they all still stand.)
local function pruneNest(c: Kit.Ctx)
	local x0, x1, z0, z1 = ZoneThemes.nestKeepOut(c.k)
	for _, child in c.folder:GetChildren() do
		if KEEP[child.Name] or not (child:IsA("BasePart") or child:IsA("Model")) then
			continue
		end
		local lo, hi = Assets.bounds(child)
		if lo and hi and lo.Y < Kit.GROUND + Kit.H and lo.X < x1 and hi.X > x0 and lo.Z < z1 and hi.Z > z0 then
			child:Destroy()
		end
	end
end

-- A zone whose nest is against the right wall (Config.NEST_RIGHT): its theme lays it out around a left nest,
-- so the whole zone is mirrored across the corridor's middle (z -> -z, each part's orientation mirrored by
-- M R M, a proper rotation): props, floor (ponds are cut into it) and walls alike, so it is the same zone
-- seen in a mirror.
local MIRROR = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.yAxis, -Vector3.zAxis)
local function mirrorZone(c: Kit.Ctx)
	for _, d in c.folder:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			d.CFrame = CFrame.new(p.X, p.Y, -p.Z) * (MIRROR * (d.CFrame - p) * MIRROR)
		end
	end
end

-- Builds zone k into `folder`. Every zone (and every piece in it, Kit.rand) draws from its own seeded
-- Random, so the map bakes the same every time and changing one zone never moves another's props.
function ZoneThemes.build(folder: Folder, k: number)
	local zone = Config.ZONES[k]
	local x0 = Config.zoneStartX(k)
	local ctx: Kit.Ctx = {
		folder = folder, k = k, id = zone.id, x0 = x0, x1 = x0 + zone.length, len = zone.length, nestX = Config.nestX(k),
		rng = Random.new(20260930 + k * 7919),
	}
	ZoneThemes.theme(k).build(ctx)
	if Config.nestSide(k) > 0 then
		mirrorZone(ctx)
	end
	pruneNest(ctx)
end

return ZoneThemes
