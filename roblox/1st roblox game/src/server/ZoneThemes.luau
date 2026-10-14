-- Per-zone art for the corridor: themed floor and walls, a few props and particle ambience. WorldBuilder
-- calls ZoneThemes.build for each zone and uses ZoneThemes.theme for the nest colours. There are no gates,
-- arches or zone signs (owner playtest): one zone flows into the next by its floor and wall colours.
--
-- Art direction (owner playtest, docs/references): a game for kids, so clean and cartoony, never realistic.
--   * flat bright colours in plastic: a big studded floor with a big lighter checker over it, tall flat
--     walls with a lighter checker on their inner face and a simple cap along the top
--   * every zone keeps its own theme (colours, cap, props), in the same clean language
--   * few, well-placed props, fewest in the early zones; no realistic materials (Assets.REALISTIC)
--
-- Layout rules that keep the corridor playable:
--   * only the floor and the two walls (and the Spirit Garden's back wall) collide;
--     every prop is a non-colliding "ghost" (see Props)
--   * props stand along the walls (|z| >= ~50 of the 96); the middle only gets flat floor overlays, so
--     the run and the guards' chase line stay visually clear
--   * part counts are budgeted (tests/world.spec.luau keeps the whole corridor under 6k parts)
--   * each distinctive prop is an asset slot ("Desert_Cactus", ...; see Assets.swap): its random draws
--     happen inside the build function, so a drop-in model never shifts the rest of the layout
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Props = require(script.Parent:WaitForChild("Props"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local ZoneThemes = {}

local GROUND = Config.GROUND_Y
local W = Config.CORRIDOR_WIDTH
local HALF_W = W / 2
local H = Config.WALL_HEIGHT
local M = Enum.Material

local box, deco, ball, cylinder, rod, blob, flat, disc, studs =
	Props.box, Props.deco, Props.ball, Props.cylinder, Props.rod, Props.blob, Props.flat, Props.disc, Props.studs
local swap, spin = Assets.swap, Assets.spin

local FLOOR_TILE = W / 6 -- the floor checker: six big tiles across
ZoneThemes.EDGE_WIDTH = 5 -- the soft border strip at each zone's entrance...
ZoneThemes.EDGE_LIGHTEN = 0.2 -- ...this much lighter than the zone's floor
local WALL_ROWS = 3 -- the wall checker: three rows up the inner face

type Ctx = {
	folder: Folder,
	k: number,
	x0: number,
	x1: number,
	len: number,
	nestX: number,
	rng: Random,
}

export type Theme = {
	floorLight: Color3, -- the checker over the floor (Config zone .floor is the floor itself)
	wallLight: Color3, -- the checker on the walls (Config zone .wall)
	cap: Color3, -- the strip along the top of both walls
	nestStone: Color3,
	build: (ctx: Ctx) -> (),
}

----------------------------------------------------------------------------------------------------
-- Shared building blocks
----------------------------------------------------------------------------------------------------
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function theme(c: Ctx): Theme
	return ZoneThemes.theme(c.k)
end

-- x at fraction `f` of the zone (0 = its entrance, 1 = its end).
local function at(c: Ctx, f: number): number
	return c.x0 + c.len * f
end

-- The studded floor: a big checker of the zone's colour and its lighter tone, every tile level with the
-- ground and side by side (Props.checker; owner playtest: no steps, no z-fighting), on a slab sunk under it.
local function floor(c: Ctx)
	local zone = Config.ZONES[c.k]
	studs(box(c.folder, "Floor", Vector3.new(c.len, 4, W), CFrame.new(c.x0 + c.len / 2, GROUND - Props.TILE_THICKNESS - 2, 0), zone.floor))
	-- A soft border where the zone begins: a strip a shade lighter than its floor, flat and studded like
	-- the rest (no glow), level with it. That and the new colours are the only thing marking a zone change.
	local edge = { c.x0, c.x0 + ZoneThemes.EDGE_WIDTH, -HALF_W, HALF_W }
	Props.tile(c.folder, "ZoneEdge", edge, GROUND, zone.floor:Lerp(Color3.new(1, 1, 1), ZoneThemes.EDGE_LIGHTEN))
	Props.checker(c.folder, "FloorTile", { c.x0, c.x1, -HALF_W, HALF_W }, FLOOR_TILE, FLOOR_TILE, GROUND, theme(c).floorLight, zone.floor, { edge })
end

-- A flat wall from x0 to x1 on side `s` (its inner face at z = s * HALF_W): studded plastic in the zone's
-- colour, a checker of the lighter tone on the inner face and the cap along the top.
local function wallRun(c: Ctx, x0: number, x1: number, s: number)
	local zone, t = Config.ZONES[c.k], theme(c)
	local len, mid = x1 - x0, (x0 + x1) / 2
	studs(box(c.folder, "Wall", Vector3.new(len, H, 4), CFrame.new(mid, GROUND + H / 2, s * (HALF_W + 2)), zone.wall), { "FrontSurface", "BackSurface" })
	local rh = H / WALL_ROWS
	local n = math.max(1, math.round(len / rh))
	local w = len / n
	for i = 0, n - 1 do
		for r = 0, WALL_ROWS - 1 do
			if (i + r) % 2 == 0 then
				local tile = studs(deco(c.folder, "WallTile", Vector3.new(w, rh, 0.1),
					CFrame.new(x0 + (i + 0.5) * w, GROUND + (r + 0.5) * rh, s * (HALF_W - 0.05)), t.wallLight), { "FrontSurface", "BackSurface" })
				tile.CastShadow = false
			end
		end
	end
	studs(deco(c.folder, "WallCap", Vector3.new(len, 2, 7), CFrame.new(mid, GROUND + H + 1, s * (HALF_W + 1.5)), t.cap))
end

local function walls(c: Ctx)
	for _, s in { -1, 1 } do
		wallRun(c, c.x0, c.x1, s)
	end
end

-- Invisible slabs over the corridor that emit particles, one per `spacing` studs.
local function ambience(c: Ctx, spacing: number, y: number, height: number, spec: Props.EmitterSpec)
	local n = math.max(1, math.floor(c.len / spacing))
	local w = c.len / n
	for i = 0, n - 1 do
		Props.emitter(c.folder, "Ambience", Vector3.new(w, height, W - 8), Vector3.new(c.x0 + (i + 0.5) * w, GROUND + y, 0), spec)
	end
end

local function fade(a: number, b: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, a),
		NumberSequenceKeypoint.new(0.8, b),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function gradient(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) })
end

-- A cartoon pond (owner's reference): flat studded water in a checker of two blues, in a soft, slightly
-- irregular shape (rows of cells, narrower toward the ends), round lily pads with a wedge cut out (the
-- first one has a pink and yellow flower) and a clump of tall green reeds at one end. `d` is its width
-- along X; it is about 3/4 as deep along Z. No rim, no glass, no glow.
-- The pond is SUNKEN (owner playtest: raised slabs showed their sides): the floor and its checker are cut
-- around each row of water (cutFloor), a solid bed fills the dip under it, and the water sits POND_SINK
-- below the floor, so the grass bank shows a small step down all round. Lily pads float on the water.
local WATER = rgb(64, 156, 222)
local WATER_LIGHT = rgb(100, 186, 238)
local LILY = rgb(74, 172, 72)
local REED = rgb(66, 168, 58)
local POND_CELL = 5 -- the checker's cell, about
ZoneThemes.POND_SINK = 0.4 -- the water's surface, this far below the floor
local POND_WATER = 0.3 -- the water tiles' thickness (both blues level, side by side)
local CUT = { Floor = true, FloorTile = true, ZoneEdge = true } -- what a pond cuts its hole into

-- Cuts the rectangle (x0..x1, z0..z1) out of every floor part in F (the floor, its checker and the zone
-- edge): each part it overlaps is resized to the biggest piece left and cloned for the rest, so the zone's
-- first "Floor" stays a full-width strip. `parts` is the running list of cuttable parts.
local function cutFloor(parts: { BasePart }, x0: number, x1: number, z0: number, z1: number)
	local eps = 1e-3
	for i = 1, #parts do
		local part = parts[i]
		local pos, size = part.CFrame.Position, part.Size
		local px0, px1, pz0, pz1 = pos.X - size.X / 2, pos.X + size.X / 2, pos.Z - size.Z / 2, pos.Z + size.Z / 2
		if part.Parent and x0 < px1 - eps and x1 > px0 + eps and z0 < pz1 - eps and z1 > pz0 + eps then
			local mx0, mx1 = math.max(px0, x0), math.min(px1, x1)
			local pieces = {}
			for _, r in { { px0, x0, pz0, pz1 }, { x1, px1, pz0, pz1 }, { mx0, mx1, pz0, z0 }, { mx0, mx1, z1, pz1 } } do
				if r[2] - r[1] > eps and r[4] - r[3] > eps then
					table.insert(pieces, r)
				end
			end
			table.sort(pieces, function(a, b)
				return (a[2] - a[1]) * (a[4] - a[3]) > (b[2] - b[1]) * (b[4] - b[3])
			end)
			for j, r in pieces do
				local piece = if j == 1 then part else part:Clone()
				piece.Size = Vector3.new(r[2] - r[1], size.Y, r[4] - r[3])
				piece.CFrame = CFrame.new((r[1] + r[2]) / 2, pos.Y, (r[3] + r[4]) / 2)
				if j > 1 then
					piece.Parent = part.Parent
					table.insert(parts, piece)
				end
			end
			if #pieces == 0 then -- wholly inside the hole
				part.Parent = nil
			end
		end
	end
end

local function pond(F: Instance, p: Vector3, d: number, pads: number?)
	local floorParts = {}
	for _, child in F:GetChildren() do
		if child:IsA("BasePart") and CUT[child.Name] then
			table.insert(floorParts, child)
		end
	end
	local bedTop = p.Y - ZoneThemes.POND_SINK - POND_WATER
	local surface = p.Y - ZoneThemes.POND_SINK -- the water's top
	local n = math.max(3, math.round(d / POND_CELL)) -- cells across X
	local cell = d / n
	local rows = math.max(3, math.round(n * 0.75))
	for r = 0, rows - 1 do
		local v = ((r + 0.5) / rows) * 2 - 1 -- -1 .. 1 across Z
		local half = math.sqrt(1 - 0.8 * v * v) * n / 2
		local shift = math.round(math.sin(r * 2.1 + d) * 0.6) -- a little unevenness, the same every build
		local a = math.clamp(math.round(n / 2 - half) + shift, 0, n - 1)
		local b = math.clamp(math.round(n / 2 + half) - 1 + shift, a, n - 1)
		local z = p.Z + (r - (rows - 1) / 2) * cell
		local x0, x1 = p.X + (a - n / 2) * cell, p.X + (b + 1 - n / 2) * cell
		cutFloor(floorParts, x0, x1, z - cell / 2, z + cell / 2)
		-- the water's checker: both blues side by side, all level (the darker cells are "Pond")
		for col = a, b do
			local light = (col + r) % 2 == 0
			studs(flat(F, if light then "PondTile" else "Pond", cell, cell, Vector3.new(p.X + (col + 0.5 - n / 2) * cell, bedTop, z),
				if light then WATER_LIGHT else WATER, nil, nil, POND_WATER))
		end
	end
	local depth = rows * cell
	-- the solid bed under the water (the dip's floor), so nobody falls through the hole
	studs(box(F, "Floor", Vector3.new(d, bedTop - (GROUND - 4), depth), CFrame.new(p.X, (bedTop + GROUND - 4) / 2, p.Z),
		if floorParts[1] then floorParts[1].Color else WATER))
	for i = 1, pads or 0 do
		local a = i * 2.4
		local size = if i == 1 then math.min(7, d * 0.24) else math.min(4.5, d * 0.16)
		local center = Vector3.new(p.X + math.cos(a) * d * 0.22, surface + 0.02 + i * 0.03, p.Z + math.sin(a) * depth * 0.2) -- floating on the water (each a little higher: overlapping pads mustn't z-fight)
		studs(disc(F, "LilyPad", size, center, LILY, M.Plastic, 0.2))
		-- the wedge cut: a water-coloured diamond with one corner at the pad's centre (a 90-degree notch)
		local cut = size * 0.38
		local dir = a + math.pi * 0.75
		local yaw = math.pi / 4 - dir
		deco(F, "LilyCut", Vector3.new(cut, 0.22, cut),
			CFrame.new(center + Vector3.new(math.cos(dir), 0, math.sin(dir)) * (cut / math.sqrt(2)) + Vector3.new(0, 0.11, 0)) * CFrame.Angles(0, yaw, 0),
			WATER).CastShadow = false
		if i == 1 then -- a pink flower with a yellow heart on the big pad
			local top = center + Vector3.new(0, 0.35, 0)
			for k, turn in { 0, math.pi / 2 } do
				deco(F, "LilyPetal", Vector3.new(size * 0.34, 0.3, size * 0.12), CFrame.new(top + Vector3.new(0, (k - 1) * 0.03, 0)) * CFrame.Angles(0, turn + 0.4, 0), rgb(255, 140, 200)).CastShadow = false
			end
			deco(F, "LilyHeart", Vector3.new(size * 0.12, 0.4, size * 0.12), CFrame.new(top + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0.4, 0), rgb(255, 222, 70)).CastShadow = false
		end
	end
	-- tall reeds just past the pond's +X end, on the wall side
	local side = if p.Z < 0 then -1 else 1
	local base = p + Vector3.new(d / 2 + 1, 0, side * depth * 0.15)
	for j, h in { 7, 9.5, 5.5 } do
		local at = base + Vector3.new((j - 2) * 1.1, 0, (j % 2) * 1.2 - 0.6)
		studs(deco(F, "Reed", Vector3.new(0.7, h, 0.7), CFrame.new(at + Vector3.new(0, h / 2, 0)) * CFrame.Angles(math.rad((j - 2) * 5), 0, math.rad((j - 2) * -4)), REED),
			{ "FrontSurface", "BackSurface", "LeftSurface", "RightSurface", "TopSurface" })
	end
end

-- A waterfall pouring down the wall on side `s` into a pond (the Spirit Garden's accents).
local function waterfall(F: Instance, x: number, s: number, width: number)
	local z = s * (HALF_W - 0.6)
	local fall = deco(F, "Waterfall", Vector3.new(width, H - 2, 1), CFrame.new(x, GROUND + (H - 2) / 2, z), rgb(160, 225, 255))
	fall.Transparency = 0.2
	fall.CastShadow = false
	local core = deco(F, "WaterfallCore", Vector3.new(width * 0.4, H - 2, 0.6), CFrame.new(x, GROUND + (H - 2) / 2, z - s * 0.5), rgb(235, 250, 255), M.SmoothPlastic)
	core.Transparency = 0.35
	core.CastShadow = false
	pond(F, Vector3.new(x, GROUND, s * (HALF_W - 14)), 28, 2)
	Props.emitter(F, "WaterfallMist", Vector3.new(width, 2, 4), Vector3.new(x, GROUND + 2, s * (HALF_W - 4)), {
		texture = Props.TEX.smoke, color = rgb(235, 248, 255), rate = 6, lifetime = NumberRange.new(1.5, 2.5),
		speed = NumberRange.new(2, 4), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) }),
		transparency = fade(0.4, 0.7), spread = Vector2.new(40, 40),
	})
end

local BRIGHT = {
	rgb(255, 90, 120), rgb(255, 215, 60), rgb(170, 110, 255), rgb(255, 150, 60), rgb(90, 190, 255), rgb(255, 255, 255), rgb(255, 120, 210),
}

----------------------------------------------------------------------------------------------------
-- 1. Meadow: the first stretch, kept nearly empty: green lawn, a pond, a few trees, bushes and a flower bed
----------------------------------------------------------------------------------------------------
local function buildMeadow(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	walls(c)
	for i, spot in { { 0.3, 1 }, { 0.62, -1 } } do
		Props.roundTree(F, Vector3.new(at(c, spot[1]), GROUND, spot[2] * 78), rng, Color3.fromHSV(0.27 + i * 0.03, 0.75, 0.85), rng:NextNumber(12, 15))
	end
	for _, spot in { { 0.4, 1 }, { 0.78, -1 }, { 0.82, 1 } } do
		Props.bush(F, Vector3.new(at(c, spot[1]), GROUND, spot[2] * 84), rng:NextNumber(5, 7), rgb(80, 196, 64))
	end
	pond(F, Vector3.new(at(c, 0.45), GROUND, -68), 26, 3)
	for _, spot in { { 0.55, 1 } } do -- a little flower bed across from the pond
		for j = 1, 4 do
			local p = Vector3.new(at(c, spot[1]) + rng:NextNumber(-8, 8), GROUND, spot[2] * rng:NextNumber(66, 80))
			Props.flower(F, p, BRIGHT[rng:NextInteger(1, #BRIGHT)], rng:NextNumber(1.6, 2.6), "Meadow_Flower")
		end
	end
	local p = Vector3.new(at(c, 0.68), GROUND, -82)
	swap("Meadow_Mushroom", F, spin(p), function(into)
		cylinder(into, "MushroomStem", 3, 1.4, p + Vector3.new(0, 1.5, 0), rgb(250, 240, 220))
		blob(into, "MushroomCap", Vector3.new(4.5, 2.4, 4.5), CFrame.new(p + Vector3.new(0, 3, 0)), rgb(235, 60, 60))
	end)

	ambience(c, 200, 4, 6, { -- butterflies
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 140, 200)), ColorSequenceKeypoint.new(0.5, rgb(255, 230, 90)), ColorSequenceKeypoint.new(1, rgb(140, 200, 255)),
		}),
		rate = 5, lifetime = NumberRange.new(4, 6), speed = NumberRange.new(1, 2.5), size = NumberSequence.new(0.7),
		spread = Vector2.new(180, 180), rotSpeed = NumberRange.new(-120, 120), lightEmission = 0.3,
	})
	ambience(c, 200, 12, 10, { -- drifting pollen
		color = rgb(255, 245, 160), rate = 8, lifetime = NumberRange.new(5, 8), speed = NumberRange.new(0.3, 1),
		size = NumberSequence.new(0.25), spread = Vector2.new(180, 180), lightEmission = 1,
	})
end

----------------------------------------------------------------------------------------------------
-- 2. Desert: sand floor, a stepped pyramid, a few saguaros, an oasis and one big skeleton
----------------------------------------------------------------------------------------------------
local CACTUS = rgb(110, 200, 70)

local function saguaro(F: Instance, p: Vector3, rng: Random)
	local h = rng:NextNumber(9, 14)
	studs(deco(F, "Cactus", Vector3.new(3, h, 3), CFrame.new(p + Vector3.new(0, h / 2, 0)), CACTUS))
	for _, dir in { -1, 1 } do
		if dir == 1 or rng:NextNumber() < 0.6 then
			local y = h * rng:NextNumber(0.4, 0.6)
			local up = rng:NextNumber(3, 5)
			studs(deco(F, "CactusArm", Vector3.new(3, 2, 2), CFrame.new(p + Vector3.new(dir * 2.5, y, 0)), CACTUS))
			studs(deco(F, "CactusArm", Vector3.new(2, up, 2), CFrame.new(p + Vector3.new(dir * 3.5, y + up / 2, 0)), CACTUS))
		end
	end
	if rng:NextNumber() < 0.5 then
		ball(F, "CactusFlower", 1.6, p + Vector3.new(0, h + 0.6, 0), rgb(255, 110, 170))
	end
end

local BONE = rgb(250, 244, 226)

local function skeleton(F: Instance, p: Vector3, rng: Random)
	local len = rng:NextNumber(16, 22)
	local a, b = p + Vector3.new(-len / 2, 1, 0), p + Vector3.new(len / 2, 1, 0)
	rod(F, "Spine", a, b, 1.2, BONE)
	blob(F, "Skull", Vector3.new(6, 4.5, 5), CFrame.new(b + Vector3.new(3, 1, 0)), BONE)
	for _, z in { -1.3, 1.3 } do
		ball(F, "EyeSocket", 1.3, b + Vector3.new(4.2, 1.8, z), rgb(40, 30, 30))
	end
	for i = 1, 4 do
		local x = a.X + len * (0.25 + i * 0.12)
		for _, dz in { -1, 1 } do
			local base = Vector3.new(x, a.Y, p.Z)
			rod(F, "Rib", base, base + Vector3.new(0, 5, dz * 4), 0.7, BONE)
		end
	end
end

-- A stepped sandstone pyramid in flat plastic (the reference's little pyramid). `p` is its ground centre.
local function pyramid(F: Instance, p: Vector3, size: number)
	swap("Desert_Pyramid", F, Assets.facing(p, -Vector3.xAxis), function(into)
		local steps = 4
		local stepH = size * 0.14
		for j = 0, steps - 1 do
			local w = size * (1 - j / steps)
			studs(deco(into, "PyramidStep", Vector3.new(w, stepH, w), CFrame.new(p + Vector3.new(0, (j + 0.5) * stepH, 0)),
				if j % 2 == 0 then rgb(222, 178, 112) else rgb(236, 196, 130)))
		end
	end)
end

local function buildDesert(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	walls(c)
	pyramid(F, Vector3.new(at(c, 0.3), GROUND, -66), 34)
	for _, spot in { { 0.15, 80 }, { 0.42, 74 }, { 0.5, -82 }, { 0.7, 84 }, { 0.78, -76 } } do
		local p = Vector3.new(at(c, spot[1]) + rng:NextNumber(-10, 10), GROUND, spot[2])
		swap("Desert_Cactus", F, spin(p), function(into)
			saguaro(into, p, rng)
		end)
	end
	local skull = Vector3.new(at(c, 0.6), GROUND, 70)
	swap("Desert_Skull", F, Assets.facing(skull, Vector3.xAxis), function(into) -- the skull looks along +X
		skeleton(into, skull, rng)
	end)
	local oasis = Vector3.new(at(c, 0.62), GROUND, -66)
	pond(F, oasis, 24, 0)
	for _, dz in { -4, 4 } do -- a few loose bones near the skeleton
		local p = skull + Vector3.new(rng:NextNumber(14, 24), 0.4, dz)
		local d = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * 1.6
		swap("Desert_Bone", F, Assets.facing(p - Vector3.new(0, 0.4, 0), d), function(into)
			rod(into, "Bone", p - d, p + d, 0.5, BONE)
			ball(into, "BoneEnd", 0.9, p - d, BONE)
			ball(into, "BoneEnd", 0.9, p + d, BONE)
		end)
	end

	ambience(c, 450, 3, 4, { -- drifting sand
		texture = Props.TEX.smoke, color = rgb(240, 214, 160), rate = 3, lifetime = NumberRange.new(5, 8),
		speed = NumberRange.new(1, 3), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) }),
		transparency = fade(0.8, 0.9), spread = Vector2.new(180, 30), acceleration = Vector3.new(5, 0, 0),
	})
	ambience(c, 225, 10, 14, { -- heat sparkles
		color = rgb(255, 236, 170), rate = 4, lifetime = NumberRange.new(2, 4), speed = NumberRange.new(0.2, 0.8),
		size = NumberSequence.new(0.3), spread = Vector2.new(180, 180), lightEmission = 0.8,
	})
end

----------------------------------------------------------------------------------------------------
-- 3. Jungle: deep green, big trees along the walls, ferns, a lily pond, vines, fireflies
----------------------------------------------------------------------------------------------------
local LEAF = rgb(60, 176, 64)
local LEAF_LIGHT = rgb(96, 206, 80)
local TRUNK = rgb(122, 84, 52)

local function buildJungle(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	walls(c)
	for i = 1, 6 do -- vines down both walls, a few per side
		for _, s in { -1, 1 } do
			local x = at(c, (i - 0.5) / 6) + s * 20
			local top = Vector3.new(x, GROUND + H, s * (HALF_W - 0.6))
			local tip = top - Vector3.new(0, rng:NextNumber(14, 26), 0)
			rod(F, "Vine", top, tip, 0.8, rgb(52, 150, 52))
			blob(F, "VineLeaf", Vector3.new(3.4, 2.4, 0.6), CFrame.new(tip), LEAF_LIGHT)
		end
	end
	for i = 1, 6 do -- big trees along the walls, alternating sides; canopies reach in a little
		local s = if i % 2 == 0 then 1 else -1
		local base = Vector3.new(at(c, (i - 0.5) / 6) + rng:NextNumber(-12, 12), GROUND, s * rng:NextNumber(80, 86))
		swap("Jungle_Tree", F, Assets.facing(base, Vector3.new(0, 0, -s)), function(into) -- front toward the path
			local h = rng:NextNumber(24, 32)
			studs(deco(into, "Trunk", Vector3.new(4, h, 4), CFrame.new(base + Vector3.new(0, h / 2, 0)), TRUNK))
			local top = base + Vector3.new(0, h, 0)
			blob(into, "Canopy", Vector3.new(26, 10, 24), CFrame.new(top + Vector3.new(0, 1, -s * 5)), LEAF)
			blob(into, "Canopy", Vector3.new(16, 8, 14), CFrame.new(top + Vector3.new(rng:NextNumber(-5, 5), 6, -s * 2)), LEAF_LIGHT)
		end)
	end
	for i = 1, 6 do -- ferns: big leaves fanned out
		local s = if i % 2 == 0 then -1 else 1
		local p = Vector3.new(at(c, (i - 0.3) / 6) + rng:NextNumber(-10, 10), GROUND, s * rng:NextNumber(64, 76))
		swap("Jungle_Fern", F, spin(p), function(into)
			for j = 1, 4 do
				local a = j / 4 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
				blob(into, "Fern", Vector3.new(7, 0.6, 2.6),
					CFrame.new(p + Vector3.new(math.cos(a) * 3, 1.6, math.sin(a) * 3)) * CFrame.Angles(0, -a, math.rad(25)), LEAF_LIGHT)
			end
		end)
	end
	for _, spot in { { 0.2, -1 }, { 0.72, 1 } } do
		local p = Vector3.new(at(c, spot[1]), GROUND + 1.4, spot[2] * 70)
		swap("Jungle_Log", F, Assets.facing(p - Vector3.new(0, 1.4, 0), Vector3.new(1, 0, -6)), function(into) -- model X along the log
			rod(into, "Log", p - Vector3.new(6, 0, 1), p + Vector3.new(6, 0, 1), 2.8, TRUNK)
		end)
	end
	for _ = 1, 5 do
		Props.flower(F, Vector3.new(at(c, rng:NextNumber(0.1, 0.9)), GROUND, (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(60, 72)),
			({ rgb(255, 70, 70), rgb(255, 150, 40), rgb(255, 90, 200) })[rng:NextInteger(1, 3)], rng:NextNumber(2, 3.5))
	end
	pond(F, Vector3.new(at(c, 0.45), GROUND, 64), 30, 4)

	ambience(c, 300, 7, 10, { -- fireflies
		color = rgb(210, 255, 120), rate = 6, lifetime = NumberRange.new(3, 5), speed = NumberRange.new(0.3, 1.2),
		size = NumberSequence.new(0.35), spread = Vector2.new(180, 180), lightEmission = 1,
	})
	ambience(c, 300, 36, 2, { -- falling leaves
		color = gradient(rgb(90, 200, 70), rgb(160, 220, 60)), rate = 3, lifetime = NumberRange.new(6, 9),
		speed = NumberRange.new(2, 4), size = NumberSequence.new(0.6), direction = Enum.NormalId.Bottom,
		acceleration = Vector3.new(0.8, -0.5, 0), rotSpeed = NumberRange.new(-90, 90),
	})
end

----------------------------------------------------------------------------------------------------
-- 4. Lava Fields: cartoon volcano land: lava rivers along the walls, three volcanoes, rocks
----------------------------------------------------------------------------------------------------
local LAVA = rgb(255, 120, 30)
local LAVA_HOT = rgb(255, 210, 70)
local LAVA_ROCK = rgb(70, 46, 54)

local function embers(host: BasePart)
	Props.emitOn(host, {
		texture = Props.TEX.spark, color = gradient(LAVA_HOT, rgb(255, 60, 20)), rate = 4,
		lifetime = NumberRange.new(1.5, 3), speed = NumberRange.new(3, 6), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		acceleration = Vector3.new(0, 2, 0), spread = Vector2.new(25, 25), lightEmission = 1,
	})
end

local function smoke(host: BasePart, rate: number)
	Props.emitOn(host, {
		texture = Props.TEX.smoke, color = gradient(rgb(120, 110, 120), rgb(70, 64, 76)), rate = rate,
		lifetime = NumberRange.new(4, 7), speed = NumberRange.new(3, 6), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12) }),
		transparency = fade(0.5, 0.8), spread = Vector2.new(15, 15), rotSpeed = NumberRange.new(-30, 30),
	})
end

local function buildLava(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	walls(c)

	-- Lava rivers along both walls (walkable: they're flat overlays)
	local seg = 100
	local n = math.floor(c.len / seg)
	for _, s in { -1, 1 } do
		for i = 0, n - 1 do
			local x = c.x0 + (i + 0.5) * c.len / n
			local z = s * 80
			-- (end to end: the pieces mustn't overlap on the same plane, or they z-fight)
			flat(F, "RiverBank", c.len / n, 14, Vector3.new(x, GROUND, z), rgb(56, 36, 44), M.SmoothPlastic, nil, 0.2)
			local river = flat(F, "LavaRiver", c.len / n, 9, Vector3.new(x, GROUND, z), LAVA, M.SmoothPlastic, nil, 0.3)
			if i % 3 == 0 then
				embers(river)
			end
		end
	end
	for _ = 1, 10 do -- a few lava cracks (flat plastic, no glow)
		flat(F, "Crack", rng:NextNumber(8, 16), 0.6, Vector3.new(at(c, rng:NextNumber(0.05, 0.95)), GROUND, rng:NextNumber(-50, 50)),
			if rng:NextNumber() < 0.3 then LAVA_HOT else LAVA, M.SmoothPlastic, rng:NextNumber(0, math.pi), 0.15)
	end

	for i = 1, 3 do -- volcanoes against the walls (a drop-in volcano gets the crater's smoke and embers)
		local p = Vector3.new(at(c, (i - 0.5) / 3) + rng:NextNumber(-30, 30), GROUND, (if i % 2 == 0 then 1 else -1) * 66)
		swap("Lava_Volcano", F, Assets.facing(p, Vector3.new(0, 0, -math.sign(p.Z))), function(into)
			cylinder(into, "Volcano", 6, 26, p + Vector3.new(0, 3, 0), rgb(96, 62, 66))
			cylinder(into, "Volcano", 6, 18, p + Vector3.new(0, 9, 0), rgb(110, 72, 74))
			cylinder(into, "Volcano", 5, 11, p + Vector3.new(0, 14.5, 0), rgb(124, 82, 80))
			local crater = disc(into, "Crater", 8, p + Vector3.new(0, 17, 0), LAVA_HOT, M.Neon, 0.3)
			Props.light(crater, LAVA, 24, 2)
			smoke(crater, 3)
			embers(crater)
		end, Vector3.new(1.2, 1.5, 1.2))
	end
	for _ = 1, 5 do
		local p = Vector3.new(at(c, rng:NextNumber(0.08, 0.92)), GROUND, (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(56, 66))
		local size = Vector3.new(rng:NextNumber(5, 9), rng:NextNumber(3, 6), rng:NextNumber(5, 8))
		local yaw = rng:NextNumber(0, 6)
		swap("Lava_Rock", F, CFrame.new(p) * CFrame.Angles(0, yaw, 0), function(into)
			Props.rock(into, p, size, LAVA_ROCK, M.SmoothPlastic, yaw, false)
			ball(into, "Magma", size.Y * 0.5, p + Vector3.new(0, size.Y * 0.45, 0), LAVA, M.Neon)
		end)
	end
	for _ = 1, 5 do -- crystal spikes
		local p = Vector3.new(at(c, rng:NextNumber(0.08, 0.92)), GROUND, (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(86, 90))
		local h = rng:NextNumber(7, 14)
		swap("Lava_Obsidian", F, spin(p), function(into)
			deco(into, "Obsidian", Vector3.new(2, h, 2), CFrame.new(p + Vector3.new(0, h / 2 - 1, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 3), rng:NextNumber(-0.2, 0.2)),
				rgb(60, 36, 80))
		end, Vector3.new(3, 1, 3))
	end

	ambience(c, 350, 34, 2, { -- falling ash
		color = rgb(150, 140, 150), rate = 5, lifetime = NumberRange.new(6, 9), speed = NumberRange.new(1, 3),
		size = NumberSequence.new(0.25), direction = Enum.NormalId.Bottom, acceleration = Vector3.new(1, -0.4, 0),
	})
end

----------------------------------------------------------------------------------------------------
-- 5. Snow Peaks: white floor, ice-blue walls under a snow cap, pines, snowmen, ice crystals, snowfall
----------------------------------------------------------------------------------------------------
local ICE = rgb(170, 220, 250)
local SNOW = rgb(252, 253, 255)

local function pine(F: Instance, p: Vector3, scale: number)
	swap("Snow_Pine", F, spin(p), function(into)
		studs(deco(into, "PineTrunk", Vector3.new(2, 4 * scale, 2) * Vector3.new(scale, 1, scale), CFrame.new(p + Vector3.new(0, 2 * scale, 0)), TRUNK))
		for i = 0, 2 do
			local w = (12 - i * 3) * scale
			studs(deco(into, "PineTier", Vector3.new(w, 3.5 * scale, w), CFrame.new(p + Vector3.new(0, (5 + i * 3.4) * scale, 0)) * CFrame.Angles(0, if i % 2 == 0 then 0 else math.rad(45), 0),
				rgb(40, 150, 90)))
		end
		studs(deco(into, "PineSnow", Vector3.new(3.6, 2, 3.6) * scale, CFrame.new(p + Vector3.new(0, 13 * scale, 0)), SNOW))
	end)
end

-- Looks toward -X, at the players coming from the base.
local function snowman(F: Instance, p: Vector3)
	swap("Snow_Snowman", F, Assets.facing(p, -Vector3.xAxis), function(into)
		ball(into, "Snowman", 6, p + Vector3.new(0, 2.6, 0), SNOW)
		ball(into, "Snowman", 4.4, p + Vector3.new(0, 6.6, 0), SNOW)
		ball(into, "Snowman", 3.2, p + Vector3.new(0, 9.6, 0), SNOW)
		for _, z in { -0.6, 0.6 } do
			ball(into, "Coal", 0.5, p + Vector3.new(-1.45, 10, z), rgb(30, 30, 35))
		end
		rod(into, "Carrot", p + Vector3.new(-1.3, 9.6, 0), p + Vector3.new(-3.2, 9.4, 0), 0.5, rgb(255, 140, 40))
		cylinder(into, "Hat", 2, 2.2, p + Vector3.new(0, 11.8, 0), rgb(30, 30, 40))
		disc(into, "HatBrim", 3.2, p + Vector3.new(0, 10.8, 0), rgb(30, 30, 40))
		rod(into, "Scarf", p + Vector3.new(0, 8.4, -2), p + Vector3.new(0, 8.4, 2), 1, rgb(230, 50, 60))
	end)
end

local function buildSnow(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	walls(c)
	for _ = 1, 6 do
		flat(F, "IcePatch", rng:NextNumber(16, 30), rng:NextNumber(10, 18), Vector3.new(at(c, rng:NextNumber(0.08, 0.92)), GROUND, rng:NextNumber(-60, 60)),
			ICE, M.SmoothPlastic, rng:NextNumber(0, math.pi), 0.2)
	end
	local icicles = math.max(4, math.round(c.len / 50)) -- one per 50 studs on each wall
	for i = 1, icicles do -- icicles under the snow cap
		for _, s in { -1, 1 } do
			local len = rng:NextNumber(4, 8)
			deco(F, "Icicle", Vector3.new(1.2, len, 1.2), CFrame.new(at(c, (i - 0.5) / icicles), GROUND + H - len / 2, s * (HALF_W - 0.8)) * CFrame.Angles(0, math.rad(45), 0), ICE).CastShadow = false
		end
	end
	local pines = math.max(2, math.round(c.len / 100)) -- one per 100 studs on each side
	for i = 1, pines do
		for _, s in { -1, 1 } do
			pine(F, Vector3.new(at(c, (i - 0.5) / pines) + rng:NextNumber(-12, 12) + s * 25, GROUND, s * rng:NextNumber(78, 86)), rng:NextNumber(1, 1.5))
		end
	end
	for i = 1, 3 do
		snowman(F, Vector3.new(at(c, (i - 0.5) / 3) + rng:NextNumber(-40, 40), GROUND, (if i % 2 == 0 then 1 else -1) * rng:NextNumber(58, 66)))
	end
	for _ = 1, 4 do -- ice crystal clusters
		local p = Vector3.new(at(c, rng:NextNumber(0.08, 0.92)), GROUND, (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(66, 74))
		swap("Snow_Crystal", F, spin(p), function(into)
			for j = 1, 3 do
				local h = rng:NextNumber(4, 10)
				deco(into, "IceCrystal", Vector3.new(1.8, h, 1.8), CFrame.new(p + Vector3.new(rng:NextNumber(-1.5, 1.5), h / 2 - 0.5, rng:NextNumber(-1.5, 1.5)))
					* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 3), rng:NextNumber(-0.35, 0.35)),
					if j == 1 then rgb(150, 235, 255) else ICE, if j == 1 then M.Neon else M.Glass)
			end
		end)
	end

	ambience(c, 200, 48, 2, { -- snowfall
		color = rgb(255, 255, 255), rate = 16, lifetime = NumberRange.new(8, 11), speed = NumberRange.new(3, 5),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.3) }),
		direction = Enum.NormalId.Bottom, acceleration = Vector3.new(1, -0.5, 0), spread = Vector2.new(15, 15),
		rotSpeed = NumberRange.new(-60, 60), lightEmission = 0.3,
	})
end

----------------------------------------------------------------------------------------------------
-- 6. Deep Space: purple floor with a few stars, planets in the sky, crystals, a UFO
----------------------------------------------------------------------------------------------------
local SPACE_CYAN = rgb(70, 225, 255)
local SPACE_PINK = rgb(255, 80, 220)
local STAR_COLORS = { rgb(255, 255, 255), SPACE_CYAN, rgb(255, 150, 240), rgb(255, 240, 140) }

local function buildSpace(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	walls(c)
	for _ = 1, 30 do
		local size = rng:NextNumber(0.8, 1.6)
		flat(F, "FloorStar", size, size, Vector3.new(at(c, rng:NextNumber(0.03, 0.97)), GROUND, rng:NextNumber(-88, 88)), STAR_COLORS[rng:NextInteger(1, #STAR_COLORS)], M.SmoothPlastic, math.rad(45), 0.15)
	end

	-- Planets hang in the sky over the corridor (a drop-in planet's pivot is the bottom of the sphere)
	local planetColors = { rgb(255, 150, 60), rgb(80, 220, 200), rgb(255, 110, 180), rgb(150, 110, 255), rgb(255, 220, 90) }
	for i = 1, 5 do
		local size = rng:NextNumber(24, 44)
		local p = Vector3.new(at(c, (i - 0.5) / 5), GROUND + rng:NextNumber(80, 120), rng:NextNumber(-90, 90))
		local color = planetColors[i]
		swap("Space_Planet", F, spin(p - Vector3.new(0, size / 2, 0)), function(into)
			ball(into, "Planet", size, p, color)
			if i % 2 == 1 then
				local ring = deco(into, "PlanetRing", Vector3.new(0.6, size * 1.9, size * 1.9), CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(90) + rng:NextNumber(-0.5, 0.5)),
					color:Lerp(Color3.new(1, 1, 1), 0.5), M.Neon)
				ring.Shape = Enum.PartType.Cylinder
				ring.Transparency = 0.35
			end
		end, Vector3.new(1, 1, 1))
	end
	for _ = 1, 8 do -- crystal clusters
		local p = Vector3.new(at(c, rng:NextNumber(0.06, 0.94)), GROUND, (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(70, 86))
		local color = if rng:NextNumber() < 0.5 then rgb(190, 120, 255) else SPACE_CYAN
		swap("Space_Crystal", F, spin(p), function(into)
			local first: BasePart? = nil
			for j = 1, 3 do
				local h = rng:NextNumber(5, 14)
				local cr = deco(into, "Crystal", Vector3.new(rng:NextNumber(1.5, 3), h, rng:NextNumber(1.5, 3)),
					CFrame.new(p + Vector3.new(rng:NextNumber(-2, 2), h / 2 - 1, rng:NextNumber(-2, 2))) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)),
					color, if j == 1 then M.Neon else M.Glass)
				first = first or cr
			end
			if first and rng:NextNumber() < 0.35 then
				Props.light(first, color, 16, 1.5)
			end
		end)
	end
	for _ = 1, 6 do -- asteroids floating along the walls (a drop-in one's pivot is its bottom)
		local size = rng:NextNumber(4, 9)
		local pos = Vector3.new(at(c, rng:NextNumber(0.06, 0.94)), GROUND + rng:NextNumber(22, 44), (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(64, 84))
		local rot = CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0)
		swap("Space_Asteroid", F, spin(pos - Vector3.new(0, size * 0.45, 0)), function(into)
			blob(into, "Asteroid", Vector3.new(size, size * 0.8, size * 0.9), CFrame.new(pos) * rot, rgb(150, 140, 180))
		end, Vector3.new(1.2, 1.2, 1.2))
	end
	for _ = 1, 6 do -- alien mushrooms
		local p = Vector3.new(at(c, rng:NextNumber(0.06, 0.94)), GROUND, (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(60, 76))
		local h = rng:NextNumber(3, 7)
		swap("Space_Mushroom", F, spin(p), function(into)
			cylinder(into, "AlienStem", h, 1, p + Vector3.new(0, h / 2, 0), rgb(200, 240, 230))
			blob(into, "AlienCap", Vector3.new(4.5, 1.8, 4.5), CFrame.new(p + Vector3.new(0, h, 0)), if rng:NextNumber() < 0.5 then rgb(120, 255, 150) else SPACE_PINK, M.Neon)
		end)
	end
	-- A UFO parked over the first stretch (a drop-in UFO keeps the tractor beam under it)
	local u = Vector3.new(c.x0 + 260, GROUND + 40, -50)
	swap("Space_UFO", F, Assets.facing(u - Vector3.new(0, 2, 0), -Vector3.xAxis), function(into)
		blob(into, "UFO", Vector3.new(24, 4, 24), CFrame.new(u), rgb(200, 205, 220))
		blob(into, "UFODome", Vector3.new(10, 7, 10), CFrame.new(u + Vector3.new(0, 2.5, 0)), rgb(120, 230, 255), M.Glass).Transparency = 0.3
		disc(into, "UFORing", 20, u - Vector3.new(0, 1.8, 0), rgb(120, 255, 150), M.Neon, 0.3)
	end, Vector3.new(1.2, 2, 1.2))
	local beam = cylinder(F, "UFOBeam", 38, 12, u - Vector3.new(0, 21, 0), rgb(120, 255, 150), M.Neon)
	beam.Transparency = 0.85
	beam.CastShadow = false

	ambience(c, 450, 22, 30, { -- twinkles
		color = gradient(rgb(255, 255, 255), SPACE_CYAN), rate = 10, lifetime = NumberRange.new(2, 4),
		speed = NumberRange.new(0, 0.4), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		spread = Vector2.new(180, 180), lightEmission = 1,
	})
end

----------------------------------------------------------------------------------------------------
-- 7. Spirit Garden, the last stage (the corridor ends at its back wall): green lawn, lavender checker
--    walls under a stylised tiled roof, red torii, waterfalls into ponds, cherry trees and stone lanterns
----------------------------------------------------------------------------------------------------
local TORII_RED = rgb(212, 40, 46)
local ROOF = rgb(44, 50, 82)
local ROOF_RIDGE = rgb(64, 72, 112)
local BLOSSOM = { rgb(255, 176, 206), rgb(255, 200, 222), rgb(250, 150, 190) }

-- A red torii across the corridor.
local function torii(F: Instance, x: number, height: number)
	swap("Spirit_Torii", F, Assets.facing(Vector3.new(x, GROUND, 0), -Vector3.xAxis), function(into)
		for _, s in { -1, 1 } do
			local z = s * (HALF_W - 12)
			cylinder(into, "ToriiPillar", height, 5, Vector3.new(x, GROUND + height / 2, z), TORII_RED)
			cylinder(into, "ToriiFoot", 3, 7, Vector3.new(x, GROUND + 1.5, z), ROOF)
		end
		studs(deco(into, "ToriiBeam", Vector3.new(5, 3, W - 10), CFrame.new(x, GROUND + height, 0), TORII_RED))
		studs(deco(into, "ToriiCap", Vector3.new(6, 2, W + 2), CFrame.new(x, GROUND + height + 2.5, 0), ROOF))
		studs(deco(into, "ToriiBeam", Vector3.new(4, 2, W - 20), CFrame.new(x, GROUND + height - 7, 0), TORII_RED))
	end, Vector3.new(1, 1.5, 0))
end

-- A stone lantern; a lit one's light carries over to a drop-in model that has none of its own.
local function stoneLantern(F: Instance, p: Vector3, lit: boolean)
	swap("Spirit_Lantern", F, Assets.facing(p, Vector3.new(0, 0, -math.sign(p.Z))), function(into) -- front toward the path
		local stone = rgb(150, 150, 200)
		studs(deco(into, "LanternBase", Vector3.new(3, 1, 3), CFrame.new(p + Vector3.new(0, 0.5, 0)), stone))
		studs(deco(into, "LanternPost", Vector3.new(1.4, 3.4, 1.4), CFrame.new(p + Vector3.new(0, 2.7, 0)), stone))
		local light = deco(into, "LanternLight", Vector3.new(2.2, 2, 2.2), CFrame.new(p + Vector3.new(0, 5.4, 0)), rgb(255, 214, 130), M.Neon)
		studs(deco(into, "LanternRoof", Vector3.new(4.4, 1.2, 4.4), CFrame.new(p + Vector3.new(0, 7, 0)), ROOF))
		if lit then
			Props.light(light, rgb(255, 200, 120), 16, 1.2)
		end
	end)
end

-- A cherry tree leaning over the path (side `s`).
local function cherryTree(F: Instance, p: Vector3, s: number, rng: Random)
	swap("Spirit_CherryTree", F, Assets.facing(p, Vector3.new(0, 0, -s)), function(into) -- front toward the path
		local top = p + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(12, 16), -s * 3)
		rod(into, "Trunk", p, top, 2.2, rgb(110, 70, 58))
		local branch = top + Vector3.new(rng:NextNumber(3, 6), rng:NextNumber(1, 3), -s * 4)
		rod(into, "Branch", top, branch, 1.2, rgb(110, 70, 58))
		blob(into, "Blossom", Vector3.new(16, 9, 14), CFrame.new(top + Vector3.new(0, 2, 0)), BLOSSOM[rng:NextInteger(1, #BLOSSOM)])
		blob(into, "Blossom", Vector3.new(11, 7, 10), CFrame.new(branch + Vector3.new(0, 1.5, 0)), BLOSSOM[rng:NextInteger(1, #BLOSSOM)])
	end)
end

-- The stylised tiled roof along the top of a wall run (x0..x1, side `s`): a dark slab sloping down toward
-- the corridor, ridges of tiles across it and a red trim along its lower edge.
local function roof(c: Ctx, x0: number, x1: number, s: number)
	local F, len = c.folder, x1 - x0
	local tilt = CFrame.Angles(-s * math.rad(20), 0, 0)
	local cf = CFrame.new((x0 + x1) / 2, GROUND + H + 3, s * (HALF_W + 1)) * tilt
	deco(F, "Roof", Vector3.new(len + 4, 1.6, 13), cf, ROOF)
	local n = math.max(1, math.round(len / 7))
	for i = 0, n - 1 do
		local x = x0 + (i + 0.5) * len / n - (x0 + x1) / 2
		deco(F, "RoofTile", Vector3.new(2.4, 1.2, 13.4), cf * CFrame.new(x, 1, 0) * CFrame.Angles(0, 0, math.rad(45)), ROOF_RIDGE).CastShadow = false
	end
	deco(F, "RoofTrim", Vector3.new(len + 4, 1.4, 1), cf * CFrame.new(0, -0.6, -s * 6.4), TORII_RED)
end

local function buildSpirit(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	walls(c)
	for _, s in { -1, 1 } do
		roof(c, c.x0, c.x1, s)
	end
	-- The corridor ends here: a back wall in the same style closes it (no finish line, no sign).
	local endX = c.x1
	local zone, t = Config.ZONES[c.k], theme(c)
	studs(box(F, "Wall", Vector3.new(4, H, W + 8), CFrame.new(endX + 2, GROUND + H / 2, 0), zone.wall), { "LeftSurface", "RightSurface" })
	local rh = H / WALL_ROWS
	local n = math.round(W / rh)
	for i = 0, n - 1 do
		for r = 0, WALL_ROWS - 1 do
			if (i + r) % 2 == 0 then
				studs(deco(F, "WallTile", Vector3.new(0.1, rh, W / n), CFrame.new(endX - 0.05, GROUND + (r + 0.5) * rh, -HALF_W + (i + 0.5) * W / n), t.wallLight),
					{ "LeftSurface", "RightSurface" }).CastShadow = false
			end
		end
	end
	studs(deco(F, "WallCap", Vector3.new(7, 2, W + 8), CFrame.new(endX + 1.5, GROUND + H + 1, 0), t.cap))
	deco(F, "Roof", Vector3.new(13, 1.6, W + 12), CFrame.new(endX + 1, GROUND + H + 3, 0) * CFrame.Angles(0, 0, math.rad(20)), ROOF)
	deco(F, "RoofTrim", Vector3.new(1, 1.4, W + 12), CFrame.new(endX - 5, GROUND + H + 0.9, 0), TORII_RED)
	-- ...with a big waterfall pouring down its middle into a pond.
	local fall = deco(F, "Waterfall", Vector3.new(1, H - 2, 24), CFrame.new(endX - 0.6, GROUND + (H - 2) / 2, 0), rgb(160, 225, 255))
	fall.Transparency = 0.2
	fall.CastShadow = false
	local core = deco(F, "WaterfallCore", Vector3.new(0.6, H - 2, 10), CFrame.new(endX - 1.1, GROUND + (H - 2) / 2, 0), rgb(235, 250, 255), M.SmoothPlastic)
	core.Transparency = 0.35
	core.CastShadow = false
	pond(F, Vector3.new(endX - 18, GROUND, 0), 32, 4)
	Props.emitter(F, "WaterfallMist", Vector3.new(4, 2, 24), Vector3.new(endX - 4, GROUND + 2, 0), {
		texture = Props.TEX.smoke, color = rgb(235, 248, 255), rate = 8, lifetime = NumberRange.new(1.5, 2.5),
		speed = NumberRange.new(2, 4), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) }),
		transparency = fade(0.4, 0.7), spread = Vector2.new(40, 40),
	})

	for _, f in { 0.25, 0.6 } do
		torii(F, at(c, f), 34)
	end
	for _, spot in { { 0.12, -1 }, { 0.45, 1 } } do -- waterfalls into ponds, one each side (and the big one at the end)
		waterfall(F, at(c, spot[1]), spot[2], 12)
	end
	for i, f in { 0.08, 0.35, 0.66 } do
		for _, s in { -1, 1 } do
			stoneLantern(F, Vector3.new(at(c, f), GROUND, s * 58), i == 2)
		end
	end
	for _, spot in { { 0.05, 1 }, { 0.22, -1 }, { 0.3, 1 }, { 0.55, -1 }, { 0.6, 1 }, { 0.88, -1 }, { 0.9, 1 } } do
		local s = spot[2]
		cherryTree(F, Vector3.new(at(c, spot[1]) + rng:NextNumber(-8, 8), GROUND, s * rng:NextNumber(80, 86)), s, rng)
	end
	for x = c.x0 + 24, c.x1 - 24, 30 do -- stepping stones down the middle
		flat(F, "SteppingStone", 12, 16, Vector3.new(x, GROUND, rng:NextNumber(-2, 2)), rgb(196, 196, 226), M.SmoothPlastic, rng:NextNumber(-0.12, 0.12), 0.25)
	end

	ambience(c, 275, 40, 2, { -- falling cherry petals
		texture = Props.TEX.smoke, color = gradient(rgb(255, 170, 205), rgb(255, 215, 230)), rate = 8,
		lifetime = NumberRange.new(8, 11), speed = NumberRange.new(2, 3), size = NumberSequence.new(0.5),
		transparency = fade(0.05, 0.2), direction = Enum.NormalId.Bottom, acceleration = Vector3.new(1.5, -0.8, 0),
		spread = Vector2.new(30, 30), rotSpeed = NumberRange.new(-120, 120),
	})
end

----------------------------------------------------------------------------------------------------
-- Theme table
----------------------------------------------------------------------------------------------------
local THEMES: { [string]: Theme } = {
	Meadow = {
		floorLight = rgb(124, 212, 64), wallLight = rgb(212, 144, 94), cap = rgb(90, 214, 64),
		nestStone = rgb(190, 190, 205),
		build = buildMeadow,
	},
	Desert = {
		floorLight = rgb(248, 224, 164), wallLight = rgb(238, 196, 112), cap = rgb(250, 222, 150),
		nestStone = rgb(226, 160, 96),
		build = buildDesert,
	},
	Jungle = {
		floorLight = rgb(72, 184, 82), wallLight = rgb(86, 156, 84), cap = rgb(96, 206, 80),
		nestStone = rgb(120, 160, 110),
		build = buildJungle,
	},
	Lava = {
		floorLight = rgb(106, 68, 76), wallLight = rgb(88, 58, 66), cap = rgb(255, 120, 40),
		nestStone = rgb(70, 46, 54),
		build = buildLava,
	},
	Snow = {
		floorLight = rgb(214, 232, 252), wallLight = rgb(180, 222, 252), cap = SNOW,
		nestStone = ICE,
		build = buildSnow,
	},
	Space = {
		floorLight = rgb(78, 60, 156), wallLight = rgb(60, 48, 124), cap = rgb(36, 28, 84),
		nestStone = rgb(160, 120, 255),
		build = buildSpace,
	},
	Spirit = {
		floorLight = rgb(128, 214, 110), wallLight = rgb(156, 156, 224), cap = ROOF,
		nestStone = rgb(170, 170, 214),
		build = buildSpirit,
	},
}

function ZoneThemes.theme(k: number): Theme
	return THEMES[Config.ZONES[k].id]
end

function ZoneThemes.build(folder: Folder, k: number, rng: Random)
	local x0 = Config.zoneStartX(k)
	local len = Config.ZONES[k].length
	local ctx: Ctx = { folder = folder, k = k, x0 = x0, x1 = x0 + len, len = len, nestX = Config.nestX(k), rng = rng }
	ZoneThemes.theme(k).build(ctx)
end

return ZoneThemes
