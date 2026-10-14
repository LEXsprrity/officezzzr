-- 4. Lava Fields: dark basalt walls under a hot orange cap, a plum floor, and fire everywhere:
--   * the volcano altar (owner's reference): a stepped dark-stone altar against the left wall, a crater of
--     lava on top with real fire over it, the lava running down its steps in a jagged channel and pooling
--     on the floor in front
--   * a lava fall pouring down the right wall over a rocky ledge into a pool, steaming
--   * lava terraces on the right wall: three stepped stone shelves, each holding a pool that spills over
--     its front edge into the next, with a fire on top
--   * clusters of basalt columns, burning vents, dead trees, studded rocks and ragged lava pools between them
--   * embers rising and ash drifting down
-- Lava is the only thing that glows (Neon); every stone, tree and rock is studded plastic.
local Assets = require(script.Parent.Parent:WaitForChild("Assets"))
local Props = require(script.Parent.Parent:WaitForChild("Props"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local rgb, at, box, glowBox = Kit.rgb, Kit.at, Kit.box, Kit.glowBox
local GROUND = Kit.GROUND
local M = Enum.Material

local Lava = {}
Lava.floorLight = rgb(106, 68, 76)
Lava.wallLight = rgb(68, 52, 60)
Lava.cap = rgb(255, 132, 44)

local LAVA = rgb(255, 122, 30)
local LAVA_HOT = rgb(255, 208, 64)
local STONE = { rgb(58, 56, 66), rgb(70, 66, 78), rgb(50, 48, 58) }
local STONE_TOP = rgb(84, 78, 92)
local CHAR = rgb(52, 44, 48)
local CHAR_LIGHT = rgb(74, 62, 64)
local OBSIDIAN = rgb(42, 34, 56)

-- A ragged lava pool on the floor with brighter spots and a glow over it. `lift` (a few tenths) keeps
-- pools apart in height.
local function lavaPool(F: Instance, center: Vector3, w: number, d: number, rng: Random, lift: number, light: boolean?)
	local rows = Kit.pool(F, "LavaPool", Vector3.new(math.round(center.X), GROUND, math.round(center.Z)), w, d, rng, LAVA, M.Neon, lift)
	Kit.poolSpots(F, "LavaHot", rows, rng, LAVA_HOT, lift + 0.12, math.max(1, math.round(w * d / 70)))
	if light ~= false and #rows > 0 then
		local host = Props.deco(F, "LavaGlow", Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, 3, 0)), LAVA)
		host.Transparency = 1
		host.CastShadow = false
		Props.light(host, LAVA, math.min(40, 12 + w), 1.6)
	end
end

-- The stepped stone altar with its burning crater (the owner's reference), laid out in frame `f` (u along
-- the wall, v out from it, y up; built at the frame's scale): the lava zig-zags down its front.
local function altar(F: Instance, f: Kit.Frame)
	local s1, s2, s3 = STONE[1], STONE[2], STONE[3]
	local back = 0
	local function stone(u0: number, u1: number, y0: number, y1: number, v0: number, v1: number, color: Color3)
		if v0 < 0 then -- (the backs sunk into the wall, each a little deeper: no two faces on one plane)
			back += 1
			v0 -= back * 0.03
		end
		box(F, "AltarStone", f, u0, u1, y0, y1, v0, v1, color)
	end
	-- the base: one deep slab under everything and two long low steps in front
	stone(-18.4, 18.2, 0, 3.2, -0.6, 16.3, s3)
	stone(-17, -2.6, 0, 2.05, 13.6, 24.2, s1)
	stone(-6.2, 15.3, 0, 2.45, 15.8, 26.1, s2)
	stone(14.6, 20.4, 0, 1.55, 6.2, 17.4, s1) -- a low step out to the right
	-- the second tier: a block each side and a step in the middle the lava runs over
	stone(-15.3, -3.6, 0.4, 6.25, 1.8, 14.2, s2) -- (bottoms staggered too: they overlap inside the base)
	stone(3.1, 16.2, 0.5, 5.4, 2.7, 15.1, s1)
	stone(-5.1, 6.3, 0.6, 4.35, 5.8, 18.1, STONE_TOP)
	-- the third: the central tower, a step on its right, a tall pillar on its left
	stone(-8.2, 7.1, 3.0, 9.65, -0.6, 12.1, s2)
	stone(7.6, 14.1, 3.0, 8.15, 1.6, 10.2, s3)
	stone(-14.2, -8.6, 3.0, 10.85, 0.8, 9.1, s1)
	stone(-13.6, -9.3, 10.6, 12.35, 2.2, 7.4, STONE_TOP) -- the pillar's cap
	-- the crown: the crater block, a shoulder on its right, and the rim round the lava (open at the front)
	stone(-5.2, 4.1, 9.2, 13.6, -0.6, 8.05, s1)
	stone(4.4, 10.1, 7.9, 11.25, -0.4, 6.1, s2)
	stone(-5.6, -3.15, 13.2, 15.05, -0.6, 7.6, s3)
	stone(1.95, 4.45, 13.25, 14.65, -0.6, 7.2, s3)
	stone(-3.3, 2.1, 13.3, 15.6, -0.6, 1.55, s2)

	-- the lava: the crater's pool, then down the crown's face, across the tower's top, down its face, over the
	-- middle step, down onto the front step, jogging right and over its edge onto the floor. (Each fall down a
	-- face is a little narrower than the runs it joins, and no run ends flush with a step's front.)
	glowBox(F, "AltarLava", f, -3.15, 1.95, 13.4, 13.95, 1.55, 7.85, LAVA_HOT)
	glowBox(F, "AltarLava", f, -1.13, 0.93, 9.6, 13.9, 8.05, 8.4, LAVA)
	glowBox(F, "AltarLava", f, -1.25, 1.05, 9.5, 9.85, 8.1, 11.0, LAVA)
	glowBox(F, "AltarLava", f, -1.35, 4.35, 9.55, 9.9, 10.5, 12.0, LAVA)
	glowBox(F, "AltarLava", f, 2.67, 4.23, 4.3, 9.82, 12.1, 12.45, LAVA)
	glowBox(F, "AltarLava", f, 2.55, 4.35, 4.2, 4.6, 12.45, 18.0, LAVA_HOT)
	glowBox(F, "AltarLava", f, 2.67, 4.23, 2.4, 4.52, 18.1, 18.45, LAVA)
	glowBox(F, "AltarLava", f, 2.55, 7.25, 2.3, 2.7, 18.45, 21.1, LAVA)
	glowBox(F, "AltarLava", f, 5.45, 7.25, 2.3, 2.75, 21.1, 26.0, LAVA_HOT)
	glowBox(F, "AltarLava", f, 5.57, 7.13, -0.05, 2.68, 26.1, 26.45, LAVA)
	-- a glowing opening in the left block, and a trickle down the base on that side
	glowBox(F, "AltarLava", f, -12.4, -7.6, 2.6, 5.0, 14.2, 14.5, LAVA)
	glowBox(F, "AltarLava", f, -11.1, -9.7, -0.05, 2.55, 14.25, 14.45, LAVA)
	glowBox(F, "AltarLava", f, -11.2, -9.6, 1.6, 2.15, 14.45, 24.25, LAVA)

	-- the fire over the crater
	Kit.fire(F, Kit.p(f, -0.6, 13.9, 4.6), 2 * f.scale, 3)
end

-- A lava fall pouring from the top of the wall (frame `f` against it) over a rocky ledge into a pool.
local function lavaFall(F: Instance, f: Kit.Frame, rng: Random)
	-- the ledge: a stepped heap of dark rock against the wall
	local tops = Kit.mound(F, "FallRock", f, 38, 15, 12, 4, rng, STONE, 0.6)
	local ledge = 0
	for _, t in tops do
		if t.u0 < -3 and t.u1 > 3 then
			ledge = math.max(ledge, t.top)
		end
	end
	local depth = 0
	for _, t in tops do
		if t.u0 < -3 and t.u1 > 3 and t.top >= ledge - 1e-6 then
			depth = t.v1
		end
	end
	-- the fall: offset sheets down the wall, a jagged stream with a bright core
	glowBox(F, "LavaFall", f, -3.2, 2.9, 31.2, Kit.H + 0.6, 0.15, 1.3, LAVA)
	glowBox(F, "LavaFall", f, -2.3, 3.8, 15.4, 31.5, 0.3, 1.6, LAVA)
	glowBox(F, "LavaFall", f, -3.6, 2.6, ledge - 0.2, 15.7, 0.45, 1.9, LAVA)
	glowBox(F, "LavaFall", f, -1.9, 1.5, ledge + 2, 25, 1.0, 2.1, LAVA_HOT)
	glowBox(F, "LavaFall", f, -1.3, 2.1, 24.4, 44, 0.9, 1.95, LAVA_HOT)
	-- over the ledge's top and down its front
	glowBox(F, "LavaFall", f, -3.6, 2.6, ledge - 0.2, ledge + 0.32, 1.9, depth + 0.2, LAVA)
	glowBox(F, "LavaFall", f, -2.6, 1.9, -0.05, ledge + 0.34, depth + 0.2, depth + 0.6, LAVA)
	-- the pool it falls into
	lavaPool(F, Kit.p(f, -0.3, 0, depth + 7), 24, 12, rng, 0.2)
	-- steam and spatter where it lands
	local steam = Props.deco(F, "LavaSteam", Vector3.new(8, 2, 8), Kit.cf(f, -0.3, 1.5, depth + 3), LAVA)
	steam.Transparency = 1
	steam.CastShadow = false
	Props.emitOn(steam, {
		texture = Props.TEX.smoke, color = Kit.gradient(rgb(200, 190, 190), rgb(120, 110, 116)), rate = 3,
		lifetime = NumberRange.new(3, 5), speed = NumberRange.new(3, 6),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 13) }),
		transparency = Kit.fade(0.55, 0.85), spread = Vector2.new(25, 25), rotSpeed = NumberRange.new(-30, 30),
	})
	Props.emitOn(steam, {
		texture = Props.TEX.spark, color = Kit.gradient(LAVA_HOT, rgb(255, 80, 30)), rate = 6,
		lifetime = NumberRange.new(1.2, 2.2), speed = NumberRange.new(6, 11),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.12) }),
		acceleration = Vector3.new(0, -6, 0), spread = Vector2.new(35, 35), lightEmission = 1, lightInfluence = 0,
	})
end

-- Three stepped stone shelves against the wall, each holding a pool of lava that spills over its front
-- edge into the next one down, and onto the floor.
local function terraces(F: Instance, f: Kit.Frame)
	local s1, s2, s3 = STONE[1], STONE[2], STONE[3]
	-- the shelves (back to front, high to low) and chunky boulders on their ends
	box(F, "TerraceStone", f, -16.2, 15.4, 0, 3.15, -0.6, 21.2, s3)
	box(F, "TerraceStone", f, -13.4, 12.6, 0, 6.6, -0.65, 14.3, s1)
	box(F, "TerraceStone", f, -10.6, 10.2, 0, 10.35, -0.7, 8.1, s2)
	box(F, "TerraceStone", f, -7.2, 6.4, 0, 13.4, -0.75, 3.3, STONE_TOP)
	box(F, "TerraceStone", f, 10.8, 15.2, 0, 8.6, 7.4, 14.6, s2)
	box(F, "TerraceStone", f, -16.9, -12.6, 0, 4.4, 13.1, 21.6, s1)
	box(F, "TerraceStone", f, 8.6, 12.9, 0, 12.2, 1.5, 8.6, s1)
	box(F, "TerraceStone", f, -12.1, -9.4, 0, 8.9, 7.0, 10.9, s3)
	-- the pools on the shelves (inset from their edges) and the spills between them
	glowBox(F, "TerraceLava", f, -9.2, 8.2, 10.35, 10.65, 3.35, 7.4, LAVA)
	glowBox(F, "TerraceLava", f, -9.1, 10.4, 6.6, 6.9, 8.2, 13.6, LAVA)
	glowBox(F, "TerraceLava", f, -12.2, 14.6, 3.15, 3.45, 14.4, 20.5, LAVA)
	glowBox(F, "TerraceLava", f, -2.4, 0.9, 6.7, 10.68, 8.1, 8.45, LAVA_HOT) -- spill: top shelf to the middle one
	glowBox(F, "TerraceLava", f, 4.1, 6.9, 3.25, 6.93, 14.3, 14.65, LAVA_HOT) -- middle to the bottom one
	glowBox(F, "TerraceLava", f, -6.3, -3.5, -0.05, 3.48, 21.2, 21.55, LAVA_HOT) -- bottom one onto the floor
	-- a crack of lava in the top block, and fire over the highest pool
	glowBox(F, "TerraceLava", f, -2.2, 2.4, 10.6, 13.45, 3.3, 3.62, LAVA)
	Kit.fire(F, Kit.p(f, -1, 10.6, 5.2), 1.1 * f.scale, 1.5)
end

-- A cluster of square basalt columns of stepped heights, in frame `f`.
local function basalt(F: Instance, f: Kit.Frame, rng: Random)
	local cols = {
		{ -6, 2, 12 }, { -3.3, 2.6, 15.5 }, { -0.6, 2, 10.5 }, { 2.1, 2.7, 13.2 }, { 4.8, 2.2, 8.4 },
		{ -4.8, 5.2, 7.2 }, { -2.1, 5.5, 9.6 }, { 0.6, 5.0, 6.3 }, { 3.3, 5.4, 4.8 }, { -0.9, 8.1, 3.5 }, { 1.8, 8.0, 2.4 },
	}
	for i, q in cols do
		local h = q[3] + rng:NextNumber(-0.4, 0.4) + i * 0.01
		local u, v = q[1], q[2]
		box(F, "Basalt", f, u - 1.3, u + 1.3, 0, h, v - 1.25, v + 1.25, STONE[i % #STONE + 1])
		box(F, "Basalt", f, u - 1.05, u + 1.05, h - 0.1, h + 0.35, v - 1.0, v + 1.0, STONE_TOP)
	end
end

-- A lava vent: a squat stepped cone of rock, a pool of lava in its top and flames licking out of it.
local function vent(F: Instance, p: Vector3, s: number, rng: Random)
	local spin = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi / 2), 0)
	Props.block(F, "VentRock", Vector3.new(9, 2.2, 9) * s, spin * CFrame.new(0, 1.1 * s - 0.2, 0), STONE[3])
	Props.block(F, "VentRock", Vector3.new(11, 1.5, 6) * s, spin * CFrame.Angles(0, math.rad(45), 0) * CFrame.new(0, 0.75 * s - 0.1, 0), STONE[1])
	Props.block(F, "VentRock", Vector3.new(6.4, 2.4, 6.4) * s, spin * CFrame.Angles(0, math.rad(20), 0) * CFrame.new(0, 3.2 * s - 0.2, 0), STONE[2])
	Kit.glow(F, "VentLava", Vector3.new(4, 0.4, 4) * s, spin * CFrame.Angles(0, math.rad(20), 0) * CFrame.new(0, 4.4 * s - 0.15, 0), LAVA_HOT)
	Kit.fire(F, (spin * CFrame.new(0, 4.4 * s, 0)).Position, 0.9 * s, 0)
end

-- A dead tree, `scale` times a 15-stud one: a charred trunk in two kinked blocks, bare branches tipped
-- outward with a twig at each end.
local function deadTree(F: Instance, base: Vector3, rng: Random, scale: number)
	local spin = CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local h1, h2 = 8 * scale, 6.5 * scale
	local lower = spin * CFrame.Angles(0, 0, rng:NextNumber(-0.06, 0.06))
	Props.block(F, "DeadTree", Vector3.new(2.2 * scale, h1, 2.2 * scale), lower * CFrame.new(0, h1 / 2 - 0.3, 0), CHAR)
	local kink = lower * CFrame.new(0, h1 - 0.8, 0) * CFrame.Angles(0, 0, rng:NextNumber(0.12, 0.22))
	Props.block(F, "DeadTree", Vector3.new(1.6 * scale, h2, 1.6 * scale), kink * CFrame.new(0, h2 / 2, 0), CHAR_LIGHT)
	local top = kink * CFrame.new(0, h2 - 0.6, 0)
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local len = rng:NextNumber(4, 6.5) * scale
		local branch = top * CFrame.new(0, (-i * 1.1 + 1) * scale, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, -rng:NextNumber(0.7, 1.0))
		Props.block(F, "DeadBranch", Vector3.new(0.9 * scale, len, 0.9 * scale), branch * CFrame.new(0, len / 2, 0), if i % 2 == 0 then CHAR else CHAR_LIGHT)
		Props.block(F, "DeadBranch", Vector3.new(0.6 * scale, len * 0.45, 0.6 * scale),
			branch * CFrame.new(0, len - 0.4, 0) * CFrame.Angles(0, 0, 0.7) * CFrame.new(0, len * 0.2, 0), CHAR)
	end
end

function Lava.build(c: Kit.Ctx)
	local F = c.folder
	Kit.floor(c, Lava)
	Kit.walls(c, Lava)

	-- the volcano altar against the left wall, a quarter of the way in (far from the nest at the end)
	local altarFrame = Kit.wallFrame(at(c, 0.22), -1, 1.7)
	Assets.swap("Lava_Volcano", F, Kit.facing(altarFrame), function(into)
		altar(into, altarFrame)
	end, Vector3.new(1.1, 1.2, 1.1))
	local altarRng = Kit.rand(c, "altar")
	lavaPool(F, Kit.p(altarFrame, 6.5, 0, 30.5), 24, 10, altarRng, 0.2)
	lavaPool(F, Kit.p(altarFrame, -10.5, 0, 27.5), 10, 6, altarRng, 0.26, false)
	for i, q in { { -26, 6, 1.7 }, { 27, 10, 1.25 } } do
		local rng = Kit.rand(c, "altarTree" .. i)
		local p = Kit.p(altarFrame, q[1], 0, q[2])
		Assets.swap("Lava_DeadTree", F, Assets.spin(p), function(into)
			deadTree(into, p, rng, q[3])
		end)
	end

	-- the lava fall down the right wall near the entrance, the terraces further along that side
	lavaFall(F, Kit.wallFrame(at(c, 0.1), 1), Kit.rand(c, "fall"))
	local terraceFrame = Kit.wallFrame(at(c, 0.6), 1, 1.6)
	Assets.swap("Lava_Terraces", F, Kit.facing(terraceFrame), function(into)
		terraces(into, terraceFrame)
	end, Vector3.new(1.1, 1.2, 1.1))
	lavaPool(F, Kit.p(terraceFrame, -4.9, 0, 26.5), 20, 9, Kit.rand(c, "terracePool"), 0.24)

	-- basalt columns: a big cluster on the left halfway along, two smaller ones on the right
	for i, q in { { 0.5, -1, 1.6 }, { 0.33, 1, 1.15 }, { 0.86, 1, 1.35 } } do
		local frame = Kit.wallFrame(at(c, q[1]), q[2], q[3])
		local rng = Kit.rand(c, "basalt" .. i)
		Assets.swap("Lava_Basalt", F, Kit.facing(frame), function(into)
			basalt(into, frame, rng)
		end)
	end
	-- dead trees and rocks between the pieces
	for i, spot in { { 0.03, -1, 1.5 }, { 0.42, 1, 1.6 }, { 0.75, 1, 1.9 }, { 0.62, -1, 1.4 }, { 0.97, 1, 1.5 } } do
		local rng = Kit.rand(c, "deadtree" .. i)
		local p = Vector3.new(at(c, spot[1]) + rng:NextNumber(-5, 5), GROUND, spot[2] * rng:NextNumber(78, 86))
		Assets.swap("Lava_DeadTree", F, Assets.spin(p), function(into)
			deadTree(into, p, rng, spot[3])
		end)
	end
	for i, spot in { { 0.15, 1 }, { 0.36, -1 }, { 0.46, 1 }, { 0.58, -1 }, { 0.72, 1 }, { 0.92, 1 }, { 0.67, -1 }, { 0.08, -1 } } do
		local rng = Kit.rand(c, "rock" .. i)
		local p = Vector3.new(at(c, spot[1]) + rng:NextNumber(-8, 8), GROUND, spot[2] * rng:NextNumber(60, 74))
		local size = rng:NextNumber(6, 11)
		Assets.swap("Lava_Rock", F, Assets.spin(p), function(into)
			Kit.rock(into, "LavaRock", p, size, rng, if i % 2 == 0 then OBSIDIAN else STONE[1], STONE[2])
		end)
	end
	-- loose pools between the pieces, in the side bands (the middle stays clear), and two burning vents
	lavaPool(F, Vector3.new(at(c, 0.42), GROUND, 60), 16, 9, Kit.rand(c, "pool1"), 0.22)
	lavaPool(F, Vector3.new(at(c, 0.68), GROUND, -62), 14, 8, Kit.rand(c, "pool2"), 0.28)
	lavaPool(F, Vector3.new(at(c, 0.9), GROUND, 64), 12, 7, Kit.rand(c, "pool3"), 0.3)
	lavaPool(F, Vector3.new(at(c, 0.06), GROUND, -66), 12, 7, Kit.rand(c, "pool4"), 0.32, false)
	lavaPool(F, Vector3.new(at(c, 0.28), GROUND, 64), 10, 6, Kit.rand(c, "pool5"), 0.34, false)
	lavaPool(F, Vector3.new(at(c, 0.97), GROUND, 58), 12, 8, Kit.rand(c, "pool6"), 0.36, false)
	for i, q in { { 0.43, -74, 1.2 }, { 0.84, 72, 1.1 } } do
		local p = Vector3.new(at(c, q[1]), GROUND, q[2])
		local rng = Kit.rand(c, "vent" .. i)
		Assets.swap("Lava_Vent", F, Assets.spin(p), function(into)
			vent(into, p, q[3], rng)
		end)
	end

	Kit.ambience(c, 200, 3, 4, { -- embers rising off the ground
		texture = Props.TEX.spark, color = Kit.gradient(LAVA_HOT, rgb(255, 70, 20)), rate = 6,
		lifetime = NumberRange.new(3, 5), speed = NumberRange.new(2, 4),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.12) }),
		acceleration = Vector3.new(0.6, 1.5, 0), spread = Vector2.new(30, 30), lightEmission = 1, lightInfluence = 0,
	})
	Kit.ambience(c, 400, 34, 2, { -- falling ash
		color = rgb(150, 140, 150), rate = 5, lifetime = NumberRange.new(6, 9), speed = NumberRange.new(1, 3),
		size = NumberSequence.new(0.25), direction = Enum.NormalId.Bottom, acceleration = Vector3.new(1, -0.4, 0),
	})
end

return Lava
