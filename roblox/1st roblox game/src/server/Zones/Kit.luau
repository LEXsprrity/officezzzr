-- Shared building blocks for the corridor's zones (ZoneThemes, Zones/<Zone>): the zone's studded floor and
-- walls, its particle ambience, the sunken lily pond and waterfalls, and the organic studded shapes the set
-- pieces are made of: stepped mounds, rock clusters, ragged "pixel" pools, round block trees, crystals,
-- bamboo and real fire.
--
-- Look (owner playtest): everything is the classic studded plastic of the floor and walls (Props.block:
-- studs on every visible face). Neon only where something glows: lava, glowing crystals, lamps. Shapes
-- are built from many offset blocks at different heights (stepped, irregular), never one big box or
-- cylinder.
--
-- Rules every helper keeps:
--   * no z-fighting: two blocks that overlap never share a face plane (heights and sizes are staggered;
--     tests/zones.spec checks every face of the corridor)
--   * props sit ON the ground (a block may sink into it a little, never float just above it); the only
--     flat things on the floor are pools a few tenths above it, never level with it
--   * deterministic: each piece draws from its own seeded Random (Kit.rand), so the map bakes the same every
--     time and changing one piece never reshuffles the others
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Props = require(script.Parent.Parent:WaitForChild("Props"))
local Assets = require(script.Parent.Parent:WaitForChild("Assets"))

local Kit = {}

Kit.GROUND = Config.GROUND_Y
Kit.W = Config.CORRIDOR_WIDTH
Kit.HALF_W = Config.CORRIDOR_WIDTH / 2
Kit.H = Config.WALL_HEIGHT
local GROUND, W, HALF_W, H = Kit.GROUND, Kit.W, Kit.HALF_W, Kit.H
local M = Enum.Material

export type Ctx = {
	folder: Folder,
	k: number,
	id: string,
	x0: number,
	x1: number,
	len: number,
	nestX: number,
	rng: Random,
}

export type Theme = {
	floorLight: Color3, -- the checker over the floor (Config zone .floor is the floor itself)
	wallLight: Color3, -- the checker on the walls (Config zone .wall)
	cap: Color3, -- the strip along the top of both walls, in the zone's accent colour
	build: (ctx: Ctx) -> (),
}

function Kit.rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local rgb = Kit.rgb

-- x at fraction `f` of the zone (0 = its entrance, 1 = its end).
function Kit.at(c: Ctx, f: number): number
	return c.x0 + c.len * f
end

-- A Random of its own for one piece of zone `c` (a hash of the zone and the tag): the same every build.
function Kit.rand(c: Ctx, tag: string): Random
	local s = c.id .. "/" .. tag
	local h = 7
	for i = 1, #s do
		h = (h * 131 + string.byte(s, i)) % 2147483629
	end
	return Random.new(h + 1)
end

----------------------------------------------------------------------------------------------------
-- Blocks
----------------------------------------------------------------------------------------------------
Kit.block = Props.block -- studded, non-colliding: what every prop is made of

-- A glowing block (lava, a lamp's light, a crystal's core): Neon, no studs, no shadow.
function Kit.glow(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Props.deco(parent, name, size, cf, color, M.Neon)
	p.CastShadow = false
	return p
end

-- A local frame standing on the ground at `origin`, its `out` axis pointing away from a wall (or wherever
-- the piece faces), `along` to its side and y up: set pieces are laid out in it, so the same piece stands
-- against either wall. Blocks built in it are turned with it (their X along, Z out).
-- `scale` multiplies everything laid out in it (a piece designed once, built bigger or smaller).
export type Frame = { origin: Vector3, along: Vector3, out: Vector3, rot: CFrame, scale: number }

function Kit.frame(origin: Vector3, out: Vector3, scale: number?): Frame
	local along = Vector3.yAxis:Cross(out)
	return { origin = origin, along = along, out = out, rot = CFrame.fromMatrix(Vector3.zero, along, Vector3.yAxis), scale = scale or 1 }
end

-- A frame against side `s` of the corridor (s = -1: the left wall, +1: the right one) at x, facing the middle.
function Kit.wallFrame(x: number, s: number, scale: number?): Frame
	return Kit.frame(Vector3.new(x, GROUND, s * HALF_W), Vector3.new(0, 0, -s), scale)
end

function Kit.p(f: Frame, u: number, y: number, v: number): Vector3
	local k = f.scale
	return f.origin + f.along * (u * k) + Vector3.yAxis * (y * k) + f.out * (v * k)
end

function Kit.cf(f: Frame, u: number, y: number, v: number, yaw: number?, tilt: number?, roll: number?): CFrame
	return CFrame.new(Kit.p(f, u, y, v)) * f.rot * CFrame.Angles(tilt or 0, yaw or 0, roll or 0)
end

-- The front of a piece built in `f`, for Assets.swap (its -Z faces the frame's `out`).
function Kit.facing(f: Frame, u: number?, v: number?): CFrame
	return Assets.facing(Kit.p(f, u or 0, 0, v or 0), f.out)
end

-- A studded block filling the frame's box u0..u1 (along), y0..y1 (up), v0..v1 (out).
function Kit.box(parent: Instance, name: string, f: Frame, u0: number, u1: number, y0: number, y1: number, v0: number, v1: number, color: Color3): Part
	return Props.block(parent, name, Vector3.new(u1 - u0, y1 - y0, v1 - v0) * f.scale, Kit.cf(f, (u0 + u1) / 2, (y0 + y1) / 2, (v0 + v1) / 2), color)
end

-- A glowing block over the frame's box.
function Kit.glowBox(parent: Instance, name: string, f: Frame, u0: number, u1: number, y0: number, y1: number, v0: number, v1: number, color: Color3): Part
	return Kit.glow(parent, name, Vector3.new(u1 - u0, y1 - y0, v1 - v0) * f.scale, Kit.cf(f, (u0 + u1) / 2, (y0 + y1) / 2, (v0 + v1) / 2), color)
end

----------------------------------------------------------------------------------------------------
-- Organic shapes
----------------------------------------------------------------------------------------------------
-- A chunky rock: 2-4 studded blocks yawed and tipped a little, the biggest in the middle, sunk a bit into
-- the floor so it sits firmly on it. `size` is its rough width. Returns its top height above the ground.
function Kit.rock(parent: Instance, name: string, base: Vector3, size: number, rng: Random, color: Color3, color2: Color3?): number
	local n = rng:NextInteger(2, 4)
	local top = 0
	for i = 1, n do
		local s = size * (if i == 1 then 1 else rng:NextNumber(0.45, 0.72))
		local h = s * rng:NextNumber(0.5, 0.85) * (if i == 1 then 1 else 0.8)
		local a = rng:NextNumber(0, math.pi * 2)
		local r = if i == 1 then 0 else size * rng:NextNumber(0.35, 0.55)
		local sink = h * 0.15
		local cf = CFrame.new(base + Vector3.new(math.cos(a) * r, h / 2 - sink, math.sin(a) * r))
			* CFrame.Angles(rng:NextNumber(-0.16, 0.16), rng:NextNumber(0, math.pi), rng:NextNumber(-0.16, 0.16))
		Props.block(parent, name, Vector3.new(s, h, s * rng:NextNumber(0.7, 1)), cf, if i % 2 == 0 and color2 then color2 else color)
		top = math.max(top, h - sink)
	end
	return top
end

-- A stepped mound in the frame: `tiers` levels, each a few overlapping offset blocks (none at the same height
-- as another), the footprint (`w` along x `d` out) shrinking toward the top, `h` tall. The back stays on
-- the frame's origin line (against a wall); each tier leans a little to one side. Returns, per tier, its
-- blocks' top heights and footprints (u0, u1, v0, v1, top) so lava, snow or moss can be laid on them.
export type Top = { u0: number, u1: number, v0: number, v1: number, top: number }

function Kit.mound(parent: Instance, name: string, f: Frame, w: number, d: number, h: number, tiers: number, rng: Random,
	colors: { Color3 }, shrink: number?): { Top }
	local tops: { Top } = {}
	local step = h / tiers
	local k = shrink or 0.72
	for i = 0, tiers - 1 do
		local t = i / math.max(1, tiers - 1)
		local tw = w * (1 - t * k)
		local td = d * (1 - t * k)
		local per = if i == tiers - 1 then 1 else 2 + (i % 2)
		for j = 1, per do
			local bw = tw * rng:NextNumber(0.55, 0.85)
			local bd = td * rng:NextNumber(0.6, 0.95)
			local u = rng:NextNumber(-1, 1) * (tw - bw) / 2
			local v0 = rng:NextNumber(-0.6, -0.2) + rng:NextNumber(0, 0.12) * (td - bd) -- (sunk into the wall behind)
			local top = (i + 1) * step + (j - 1) * 0.45 + rng:NextNumber(0.05, 0.3) -- staggered: no two tops level
			local y0 = math.max(0, i * step - 0.6 - j * 0.07)
			Kit.box(parent, name, f, u - bw / 2, u + bw / 2, y0, top, v0, v0 + bd, colors[(i + j) % #colors + 1])
			table.insert(tops, { u0 = u - bw / 2, u1 = u + bw / 2, v0 = v0, v1 = v0 + bd, top = top })
		end
	end
	return tops
end

-- A ragged flat pool lying on the floor (lava, glowing goo): rows `cell` deep along X, wider in the middle
-- and stepped at the ends like pixel art, side by side and level, so no two pieces overlap on one plane.
-- `w` x `d` is its extent (X, Z); its top is `lift` above the ground (a few tenths: on the floor, never level
-- with it). Returns its rows as world rects { x0, x1, z0, z1 }.
function Kit.pool(parent: Instance, name: string, center: Vector3, w: number, d: number, rng: Random, color: Color3,
	material: Enum.Material, lift: number, cell: number?): { { number } }
	local c = cell or 2
	local rows = math.max(2, math.round(d / c))
	local out = {}
	local thick = math.min(0.2, lift)
	local shift = 0
	for r = 0, rows - 1 do
		local v = ((r + 0.5) / rows) * 2 - 1
		local half = math.sqrt(math.max(0.08, 1 - v * v)) * w / 2 * rng:NextNumber(0.72, 1.05)
		shift = math.clamp(shift + rng:NextNumber(-0.6, 0.6) * c, -w * 0.18, w * 0.18)
		local x0 = center.X + math.round((-half + shift) / c) * c
		local x1 = center.X + math.round((half + shift) / c) * c
		if x1 - x0 >= c - 1e-6 then
			local z = center.Z + (r - (rows - 1) / 2) * c
			local p = Props.deco(parent, name, Vector3.new(x1 - x0, thick, c), CFrame.new((x0 + x1) / 2, GROUND + lift - thick / 2, z), color, material)
			p.CastShadow = false
			if material ~= M.Neon then
				Props.studs(p)
			end
			table.insert(out, { x0, x1, z - c / 2, z + c / 2 })
		end
	end
	return out
end

-- Brighter patches on a pool's rows (`rows` from Kit.pool): a few cell-snapped bits laid on it, `lift` above
-- the ground (higher than the pool's own top), never two in one row (they'd overlap on one plane).
function Kit.poolSpots(parent: Instance, name: string, rows: { { number } }, rng: Random, color: Color3, lift: number, count: number, cell: number?)
	local c = cell or 2
	local used = {}
	for _ = 1, count do
		local k = rng:NextInteger(1, #rows)
		local r = rows[k]
		local cells = math.floor((r[2] - r[1]) / c + 1e-6)
		if cells >= 2 and not used[k] then
			used[k] = true
			local n = rng:NextInteger(1, math.max(1, cells - 1))
			local a = rng:NextInteger(0, cells - n)
			local x0 = r[1] + a * c
			local x1 = x0 + n * c
			local inset = 0.3 -- inside the row, so its edges never meet the pool's sides
			local p = Kit.glow(parent, name, Vector3.new(x1 - x0 - inset * 2, 0.1, r[4] - r[3] - inset * 2),
				CFrame.new((x0 + x1) / 2, GROUND + lift - 0.05, (r[3] + r[4]) / 2), color)
			p.CastShadow = false
		end
	end
end

-- Real fire on top of something: an invisible host at `pos` (the flames' base) with big flames, embers
-- and smoke, and a warm light. `scale` 1 is a campfire; 2 is a volcano's.
function Kit.fire(parent: Instance, pos: Vector3, scale: number, smokeRate: number?): Part
	local host = Props.deco(parent, "Fire", Vector3.new(2.6, 1, 2.6) * scale, CFrame.new(pos + Vector3.new(0, 0.5 * scale, 0)), rgb(255, 150, 60))
	host.Transparency = 1
	host.CastShadow = false
	Props.emitOn(host, { -- flames
		texture = Props.TEX.fire,
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 236, 120)),
			ColorSequenceKeypoint.new(0.35, rgb(255, 160, 40)),
			ColorSequenceKeypoint.new(1, rgb(230, 60, 20)),
		}),
		rate = 22 + 6 * scale,
		lifetime = NumberRange.new(0.7, 1.25),
		speed = NumberRange.new(4 * math.sqrt(scale), 7 * math.sqrt(scale)),
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2.6 * scale),
			NumberSequenceKeypoint.new(0.45, 4 * scale),
			NumberSequenceKeypoint.new(1, 0.8 * scale),
		}),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(0.12, 0.12),
			NumberSequenceKeypoint.new(0.7, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		acceleration = Vector3.new(0, 5 * scale, 0),
		spread = Vector2.new(12, 12),
		rotSpeed = NumberRange.new(-50, 50),
		lightEmission = 1,
		lightInfluence = 0,
	})
	Props.emitOn(host, { -- embers
		texture = Props.TEX.spark,
		color = ColorSequence.new(rgb(255, 220, 90), rgb(255, 90, 30)),
		rate = 5 + 3 * scale,
		lifetime = NumberRange.new(1.6, 2.8),
		speed = NumberRange.new(6 * math.sqrt(scale), 10 * math.sqrt(scale)),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.15) }),
		acceleration = Vector3.new(0.8, 2, 0),
		spread = Vector2.new(28, 28),
		lightEmission = 1,
		lightInfluence = 0,
	})
	if (smokeRate or 1) > 0 then
		Props.emitOn(host, { -- smoke
			texture = Props.TEX.smoke,
			color = ColorSequence.new(rgb(110, 100, 104), rgb(70, 64, 70)),
			rate = smokeRate or 2.5,
			lifetime = NumberRange.new(4, 6),
			speed = NumberRange.new(5 * math.sqrt(scale), 8 * math.sqrt(scale)),
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3 * scale), NumberSequenceKeypoint.new(1, 10 * scale) }),
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.62),
				NumberSequenceKeypoint.new(1, 1),
			}),
			spread = Vector2.new(10, 10),
			rotSpeed = NumberRange.new(-25, 25),
		})
	end
	Props.light(host, rgb(255, 150, 60), math.min(60, 20 + 10 * scale), 2.4)
	return host
end

-- A cluster of crystals on a little studded rock: `n` tall faceted blocks tipped outward, the first one(s)
-- glowing (Neon, with a light), the rest the same colour in studded plastic. `h` is the tallest one.
function Kit.crystals(parent: Instance, name: string, base: Vector3, rng: Random, color: Color3, rock: Color3, n: number, h: number, glowing: number?)
	Kit.rock(parent, name .. "Rock", base, h * 0.42, rng, rock)
	local light = color:Lerp(Color3.new(1, 1, 1), 0.35)
	for i = 1, n do
		local ch = h * (if i == 1 then 1 else rng:NextNumber(0.45, 0.8))
		local cw = math.max(1, ch * rng:NextNumber(0.16, 0.24))
		local a = (i / n) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local r = if i == 1 then 0 else h * 0.16
		local tip = if i == 1 then rng:NextNumber(-0.08, 0.08) else 0.28 + rng:NextNumber(0, 0.18)
		local cf = CFrame.new(base + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
			* CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -tip) * CFrame.new(0, ch / 2 - 0.4, 0) * CFrame.Angles(0, math.rad(45), 0)
		local glow = i <= (glowing or 1)
		if glow then
			local core = Kit.glow(parent, name, Vector3.new(cw, ch, cw), cf, color)
			if i == 1 then
				Props.light(core, color, 14, 1.2)
			end
		else
			Props.block(parent, name, Vector3.new(cw, ch, cw), cf, light)
		end
	end
end

-- A clump of bamboo: `n` tall green canes with lighter nodes and a few leaves at the top.
function Kit.bamboo(parent: Instance, name: string, base: Vector3, rng: Random, n: number, h: number, cane: Color3?, node: Color3?, leaf: Color3?)
	local caneColor, nodeColor, leafColor = cane or rgb(92, 178, 62), node or rgb(146, 214, 92), leaf or rgb(74, 160, 58)
	for i = 1, n do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = if i == 1 then 0 else rng:NextNumber(1.2, 2.6)
		local ch = h * rng:NextNumber(0.6, 1)
		local tilt = rng:NextNumber(-0.06, 0.06)
		local root = base + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local frame = CFrame.new(root) * CFrame.Angles(tilt, rng:NextNumber(0, math.pi), rng:NextNumber(-0.06, 0.06))
		Props.block(parent, name, Vector3.new(0.9, ch, 0.9), frame * CFrame.new(0, ch / 2 - 0.3, 0), caneColor)
		local nodes = math.clamp(math.floor(ch / 9), 1, 2)
		for j = 1, nodes do
			Props.block(parent, name .. "Node", Vector3.new(1.15, 0.35, 1.15), frame * CFrame.new(0, ch * j / (nodes + 1) + i * 0.07, 0), nodeColor)
		end
		for j = 1, 2 do
			local side = if j == 1 then 1 else -1
			Props.block(parent, name .. "Leaf", Vector3.new(3, 0.25, 0.8),
				frame * CFrame.new(side * 1.3, ch - 0.6 - j * 0.7, 0) * CFrame.Angles(0, 0, side * -0.35), leafColor)
		end
	end
end

-- A round bush `s` across: three overlapping green blocks, sometimes with berries.
function Kit.bush(parent: Instance, p: Vector3, s: number, rng: Random, leaf: Color3, leafLight: Color3, berries: Color3?)
	local spin = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	Props.block(parent, "Bush", Vector3.new(s * 1.3, s * 0.62, s), spin * CFrame.new(0, s * 0.31, 0), leaf)
	Props.block(parent, "Bush", Vector3.new(s * 0.8, s * 0.82, s * 0.75), spin * CFrame.new(s * 0.12, s * 0.41 + 0.05, -s * 0.06), leafLight)
	Props.block(parent, "Bush", Vector3.new(s * 0.62, s * 0.5, s * 1.18), spin * CFrame.new(-s * 0.3, s * 0.25 + 0.1, 0.1), leaf)
	if berries and rng:NextNumber() < 0.5 then
		for i = 1, 3 do
			Props.block(parent, "Berry", Vector3.new(0.5, 0.5, 0.5), spin * CFrame.new(s * (i - 2) * 0.28, s * 0.62 + 0.08 * i, s * 0.45), berries)
		end
	end
end

-- A round tree in blocks: a trunk of two stacked blocks and a canopy built like a chunky ball (a core with a
-- wider band each way, a cap on top and a smaller one underneath), in two greens. `s` is the canopy's size.
function Kit.roundTree(parent: Instance, base: Vector3, rng: Random, s: number, trunkH: number, leaf: Color3, leafLight: Color3, trunk: Color3)
	local spin = CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, math.pi / 2), 0)
	Props.block(parent, "Trunk", Vector3.new(2.6, trunkH * 0.45, 2.6), spin * CFrame.new(0, trunkH * 0.225, 0), trunk)
	Props.block(parent, "Trunk", Vector3.new(2, trunkH * 0.65, 2), spin * CFrame.new(0.15, trunkH * 0.45 + trunkH * 0.325 - 0.3, 0.1), trunk)
	local cy = trunkH + s * 0.32
	Props.block(parent, "Canopy", Vector3.new(s, s * 0.78, s), spin * CFrame.new(0, cy, 0), leaf)
	Props.block(parent, "Canopy", Vector3.new(s * 1.24, s * 0.5, s * 0.72), spin * CFrame.new(0, cy - s * 0.04, 0), leafLight)
	Props.block(parent, "Canopy", Vector3.new(s * 0.72, s * 0.44, s * 1.24), spin * CFrame.new(0, cy + s * 0.03, 0), leaf)
	Props.block(parent, "Canopy", Vector3.new(s * 0.62, s * 0.3, s * 0.62), spin * CFrame.new(s * 0.06, cy + s * 0.39 + s * 0.15 - 0.2, -s * 0.04), leafLight)
	Props.block(parent, "Canopy", Vector3.new(s * 0.7, s * 0.22, s * 0.7), spin * CFrame.new(0, cy - s * 0.39 - s * 0.11 + 0.25, 0), leaf)
end

----------------------------------------------------------------------------------------------------
-- The zone's floor, walls and ambience
----------------------------------------------------------------------------------------------------
local FLOOR_TILE = W / 6 -- the floor checker: six big tiles across
Kit.EDGE_WIDTH = 5 -- the soft border strip at each zone's entrance...
Kit.EDGE_LIGHTEN = 0.2 -- ...this much lighter than the zone's floor
local WALL_ROWS = 3 -- the wall checker: three rows up the inner face

-- The studded floor: a big checker of the zone's colour and its lighter tone, every tile level with the
-- ground and side by side (Props.checker; owner playtest: no steps, no z-fighting), on a slab sunk under it.
function Kit.floor(c: Ctx, t: Theme)
	local zone = Config.ZONES[c.k]
	Props.studs(Props.box(c.folder, "Floor", Vector3.new(c.len, 4, W), CFrame.new(c.x0 + c.len / 2, GROUND - Props.TILE_THICKNESS - 2, 0), zone.floor))
	-- A soft border where the zone begins: a strip a shade lighter than its floor, flat and studded like
	-- the rest (no glow), level with it. That and the new colours are the only thing marking a zone change.
	local edge = { c.x0, c.x0 + Kit.EDGE_WIDTH, -HALF_W, HALF_W }
	Props.tile(c.folder, "ZoneEdge", edge, GROUND, zone.floor:Lerp(Color3.new(1, 1, 1), Kit.EDGE_LIGHTEN))
	Props.checker(c.folder, "FloorTile", { c.x0, c.x1, -HALF_W, HALF_W }, FLOOR_TILE, FLOOR_TILE, GROUND, t.floorLight, zone.floor, { edge })
end

-- A flat wall from x0 to x1 on side `s` (its inner face at z = s * HALF_W): studded plastic in the zone's
-- colour, a checker of the lighter tone on the inner face and the cap along the top.
function Kit.wallRun(c: Ctx, t: Theme, x0: number, x1: number, s: number)
	local zone = Config.ZONES[c.k]
	local len, mid = x1 - x0, (x0 + x1) / 2
	Props.studs(Props.box(c.folder, "Wall", Vector3.new(len, H, 4), CFrame.new(mid, GROUND + H / 2, s * (HALF_W + 2)), zone.wall), { "FrontSurface", "BackSurface" })
	local rh = H / WALL_ROWS
	local n = math.max(1, math.round(len / rh))
	local w = len / n
	for i = 0, n - 1 do
		for r = 0, WALL_ROWS - 1 do
			if (i + r) % 2 == 0 then
				local tile = Props.studs(Props.deco(c.folder, "WallTile", Vector3.new(w, rh, 0.1),
					CFrame.new(x0 + (i + 0.5) * w, GROUND + (r + 0.5) * rh, s * (HALF_W - 0.05)), t.wallLight), { "FrontSurface", "BackSurface" })
				tile.CastShadow = false
			end
		end
	end
	Props.studs(Props.deco(c.folder, "WallCap", Vector3.new(len, 2, 7), CFrame.new(mid, GROUND + H + 1, s * (HALF_W + 1.5)), t.cap))
end

function Kit.walls(c: Ctx, t: Theme)
	for _, s in { -1, 1 } do
		Kit.wallRun(c, t, c.x0, c.x1, s)
	end
end

-- Invisible slabs over the corridor that emit particles, one per `spacing` studs.
function Kit.ambience(c: Ctx, spacing: number, y: number, height: number, spec: Props.EmitterSpec)
	local n = math.max(1, math.floor(c.len / spacing))
	local w = c.len / n
	for i = 0, n - 1 do
		Props.emitter(c.folder, "Ambience", Vector3.new(w, height, W - 8), Vector3.new(c.x0 + (i + 0.5) * w, GROUND + y, 0), spec)
	end
end

function Kit.fade(a: number, b: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, a),
		NumberSequenceKeypoint.new(0.8, b),
		NumberSequenceKeypoint.new(1, 1),
	})
end

function Kit.gradient(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) })
end

----------------------------------------------------------------------------------------------------
-- The lily pond and waterfalls
----------------------------------------------------------------------------------------------------
-- A cartoon pond (owner's reference): flat studded water in a checker of two blues, in a soft, slightly
-- irregular shape (rows of cells, narrower toward the ends), round lily pads with a wedge cut out (the
-- first one has a pink and yellow flower) and a clump of tall green reeds at one end. `d` is its width
-- along X; it is about 3/4 as deep along Z. No rim, no glass, no glow.
-- The pond is SUNKEN (owner playtest: raised slabs showed their sides): the floor and its checker are cut
-- around each row of water (cutFloor), a solid bed fills the dip under it, and the water sits POND_SINK
-- below the floor, so the bank shows a small step down all round. Lily pads float on the water.
-- `style` changes the water (a frozen pond: its own names and colours, no pads or reeds).
Kit.WATER = rgb(64, 156, 222)
Kit.WATER_LIGHT = rgb(100, 186, 238)
Kit.FOAM = rgb(236, 248, 255)
local LILY = rgb(74, 172, 72)
local REED = rgb(66, 168, 58)
local POND_CELL = 5 -- the checker's cell, about
Kit.POND_SINK = 0.4 -- the water's surface, this far below the floor
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

export type PondStyle = { dark: string, light: string, water: Color3, waterLight: Color3, reeds: boolean }
Kit.ICE_POND = { dark = "Ice", light = "IceTile", water = rgb(170, 222, 250), waterLight = rgb(214, 240, 255), reeds = false } :: PondStyle

-- Returns the pond's extent (x0, x1, z0, z1).
function Kit.pond(F: Instance, p: Vector3, d: number, pads: number?, style: PondStyle?): (number, number, number, number)
	local st = style or { dark = "Pond", light = "PondTile", water = Kit.WATER, waterLight = Kit.WATER_LIGHT, reeds = true }
	local floorParts = {}
	for _, child in F:GetChildren() do
		if child:IsA("BasePart") and CUT[child.Name] then
			table.insert(floorParts, child)
		end
	end
	local bedTop = p.Y - Kit.POND_SINK - POND_WATER
	local surface = p.Y - Kit.POND_SINK -- the water's top
	local n = math.max(3, math.round(d / POND_CELL)) -- cells across X
	local cell = d / n
	local rows = math.max(3, math.round(n * 0.75))
	local ex0, ex1 = math.huge, -math.huge
	for r = 0, rows - 1 do
		local v = ((r + 0.5) / rows) * 2 - 1 -- -1 .. 1 across Z
		local half = math.sqrt(1 - 0.8 * v * v) * n / 2
		local shift = math.round(math.sin(r * 2.1 + d) * 0.6) -- a little unevenness, the same every build
		local a = math.clamp(math.round(n / 2 - half) + shift, 0, n - 1)
		local b = math.clamp(math.round(n / 2 + half) - 1 + shift, a, n - 1)
		local z = p.Z + (r - (rows - 1) / 2) * cell
		local x0, x1 = p.X + (a - n / 2) * cell, p.X + (b + 1 - n / 2) * cell
		ex0, ex1 = math.min(ex0, x0), math.max(ex1, x1)
		cutFloor(floorParts, x0, x1, z - cell / 2, z + cell / 2)
		-- the water's checker: both blues side by side, all level (the darker cells are "Pond")
		for col = a, b do
			local light = (col + r) % 2 == 0
			Props.studs(Props.flat(F, if light then st.light else st.dark, cell, cell, Vector3.new(p.X + (col + 0.5 - n / 2) * cell, bedTop, z),
				if light then st.waterLight else st.water, nil, nil, POND_WATER))
		end
	end
	local depth = rows * cell
	-- the solid bed under the water (the dip's floor), so nobody falls through the hole
	Props.studs(Props.box(F, "Floor", Vector3.new(d, bedTop - (GROUND - 4), depth), CFrame.new(p.X, (bedTop + GROUND - 4) / 2, p.Z),
		if floorParts[1] then floorParts[1].Color else st.water))
	for i = 1, pads or 0 do
		local a = i * 2.4
		local size = if i == 1 then math.min(7, d * 0.24) else math.min(4.5, d * 0.16)
		local center = Vector3.new(p.X + math.cos(a) * d * 0.22, surface + 0.02 + i * 0.03, p.Z + math.sin(a) * depth * 0.2) -- floating on the water (each a little higher: overlapping pads mustn't z-fight)
		Props.studs(Props.disc(F, "LilyPad", size, center, LILY, M.Plastic, 0.2))
		-- the wedge cut: a water-coloured diamond with one corner at the pad's centre (a 90-degree notch)
		local cut = size * 0.38
		local dir = a + math.pi * 0.75
		local yaw = math.pi / 4 - dir
		Props.deco(F, "LilyCut", Vector3.new(cut, 0.22, cut),
			CFrame.new(center + Vector3.new(math.cos(dir), 0, math.sin(dir)) * (cut / math.sqrt(2)) + Vector3.new(0, 0.11, 0)) * CFrame.Angles(0, yaw, 0),
			st.water).CastShadow = false
		if i == 1 then -- a pink flower with a yellow heart on the big pad
			local top = center + Vector3.new(0, 0.35, 0)
			for k, turn in { 0, math.pi / 2 } do
				Props.deco(F, "LilyPetal", Vector3.new(size * 0.34, 0.3, size * 0.12), CFrame.new(top + Vector3.new(0, (k - 1) * 0.03, 0)) * CFrame.Angles(0, turn + 0.4, 0), rgb(255, 140, 200)).CastShadow = false
			end
			Props.deco(F, "LilyHeart", Vector3.new(size * 0.13, 0.4, size * 0.13), CFrame.new(top + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0.4, 0), rgb(255, 222, 70)).CastShadow = false
		end
	end
	if st.reeds then -- tall reeds just past the pond's +X end, on the wall side
		local side = if p.Z < 0 then -1 else 1
		local base = p + Vector3.new(d / 2 + 1, 0, side * depth * 0.15)
		for j, h in { 7, 9.5, 5.5 } do
			local at = base + Vector3.new((j - 2) * 1.1, 0, (j % 2) * 1.2 - 0.6)
			Props.studs(Props.deco(F, "Reed", Vector3.new(0.7, h, 0.7), CFrame.new(at + Vector3.new(0, h / 2, 0)) * CFrame.Angles(math.rad((j - 2) * 5), 0, math.rad((j - 2) * -4)), REED),
				{ "FrontSurface", "BackSurface", "LeftSurface", "RightSurface", "TopSurface" })
		end
	end
	return ex0, ex1, p.Z - depth / 2, p.Z + depth / 2
end

-- Water pouring down from `top` (a ledge, or the wall's top) in the frame: a studded stream of two blues
-- with a white core, a little foam where it lands and spray and mist moving down it. `width` across, the
-- stream's back against v = `v` (a wall's or a cliff's face).
function Kit.waterfall(parent: Instance, f: Frame, u: number, v: number, width: number, top: number)
	local w2 = width / 2
	Kit.box(parent, "Waterfall", f, u - w2, u + w2, 0, top, v + 0.15, v + 0.8, Kit.WATER_LIGHT)
	Kit.box(parent, "Waterfall", f, u - w2 * 0.62, u + w2 * 0.62 - 0.37, 0, top - 0.3, v + 0.8, v + 1.3, Kit.WATER)
	Kit.box(parent, "WaterfallCore", f, u - w2 * 0.22 + 0.13, u + w2 * 0.3, 0, top - 0.7, v + 1.3, v + 1.6, Kit.FOAM)
	-- the lip where it pours over
	Kit.box(parent, "Waterfall", f, u - w2 - 0.2, u + w2 + 0.2, top - 0.9, top + 0.45, v + 0.05, v + 1.9, Kit.WATER_LIGHT)
	-- foam where it lands (chunky white blocks on the water)
	local foam = { { -0.55, 1.1, 1.3 }, { 0.1, 1.6, 1.7 }, { 0.6, 0.9, 1.2 } }
	for i, q in foam do
		local fu = u + q[1] * w2
		Kit.box(parent, "Foam", f, fu - q[3] * w2 * 0.45, fu + q[3] * w2 * 0.45, -0.3, q[2] - 0.3 + i * 0.05, v + 1.3 + i * 0.07, v + 1.3 + q[3] * 2.6, Kit.FOAM)
	end
	local spray = Props.deco(parent, "WaterfallSpray", Vector3.new(width, top * 0.9, 1) * f.scale, Kit.cf(f, u, top * 0.5, v + 1.8), Kit.FOAM)
	spray.Transparency = 1
	spray.CastShadow = false
	Props.emitOn(spray, {
		color = rgb(240, 250, 255), rate = 6 + width * 0.6, lifetime = NumberRange.new(0.8, 1.4), speed = NumberRange.new(6, 10),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.25) }),
		direction = Enum.NormalId.Bottom, spread = Vector2.new(4, 4), lightEmission = 0.3,
	})
	local mist = Props.deco(parent, "WaterfallMist", Vector3.new(width * f.scale, 2, 4), Kit.cf(f, u, 2 / f.scale, v + 3), Kit.FOAM)
	mist.Transparency = 1
	mist.CastShadow = false
	Props.emitOn(mist, {
		texture = Props.TEX.smoke, color = rgb(235, 248, 255), rate = 5, lifetime = NumberRange.new(1.5, 2.5),
		speed = NumberRange.new(2, 4), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) }),
		transparency = Kit.fade(0.45, 0.75), spread = Vector2.new(40, 40),
	})
end

return Kit
