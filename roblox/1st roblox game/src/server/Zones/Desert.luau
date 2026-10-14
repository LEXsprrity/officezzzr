-- 2. Desert: sand floor, darker sandstone walls under a light sand cap:
--   * a stepped sandstone pyramid against the left wall: a staircase up its front to a little temple,
--     a broken corner with its blocks tumbled on the sand, an obelisk each side
--   * an oasis on the right: a lily pond under leaning palms, rocks and reeds
--   * ruins: broken columns, a fallen one and a crumbling wall
--   * a giant blocky skull and ribs half buried in the sand
--   * cactus clusters, stepped dunes along the walls, tumbleweeds and loose bones
--   * drifting sand and heat sparkles
local Assets = require(script.Parent.Parent:WaitForChild("Assets"))
local Props = require(script.Parent.Parent:WaitForChild("Props"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local rgb, at, box = Kit.rgb, Kit.at, Kit.box
local block = Props.block
local GROUND = Kit.GROUND

local Desert = {}
Desert.floorLight = rgb(248, 224, 164)
Desert.wallLight = rgb(226, 184, 112)
Desert.cap = rgb(255, 224, 146)

local SANDSTONE = { rgb(222, 178, 112), rgb(236, 196, 130), rgb(212, 166, 100) }
local TRIM = rgb(196, 146, 88)
local DARK = rgb(70, 46, 34)
local CACTUS = rgb(104, 196, 70)
local CACTUS_LIGHT = rgb(140, 216, 92)
local BONE = rgb(250, 244, 226)
local BONE_SHADE = rgb(226, 214, 190)
local PALM = { rgb(150, 104, 62), rgb(172, 124, 76) }
local FROND = rgb(84, 184, 66)
local FROND_LIGHT = rgb(122, 210, 84)
local DUNE = { rgb(246, 222, 162), rgb(236, 206, 140), rgb(250, 232, 182) }

-- The stepped pyramid in frame `f`: five tiers against the wall, a staircase up the middle of its front to
-- a little temple with a dark doorway, the top right corner broken off and its blocks lying on the sand.
local function pyramid(F: Instance, f: Kit.Frame, rng: Random)
	for i = 0, 3 do
		local half = 16 - 3.1 * i
		local front = 24 - 4.3 * i
		local y0, y1 = 2.6 * i, 2.6 * (i + 1)
		local back = -0.6 - 0.05 * i
		local inner = 3.4 + 0.04 * i -- (each tier's edge by the stairs a little apart: no two faces on one plane)
		local broken = i >= 2 -- the top right corner is broken off
		local right = if i == 3 then half * 0.45 elseif broken then half * 0.8 else half
		local rFront = front - (if broken then 1.4 else 0)
		-- each tier in two blocks (left and right of the stairs), a hair apart in height
		box(F, "PyramidStep", f, -half, -inner, math.max(0, y0 - 0.4), y1 + 0.02 * i, back, front, SANDSTONE[i % 2 + 1])
		box(F, "PyramidStep", f, inner, right, math.max(0, y0 - 0.4), y1 + 0.02 * i + 0.11, back, rFront, SANDSTONE[(i + 1) % 2 + 1])
		-- a darker trim along each tier's front edge
		box(F, "PyramidTrim", f, -half - 0.2, -inner - 0.2, y1 - 0.5 + 0.02 * i, y1 + 0.32 + 0.02 * i, front - 0.8, front + 0.25, TRIM)
		box(F, "PyramidTrim", f, inner + 0.2, right + 0.2, y1 - 0.39 + 0.02 * i, y1 + 0.43 + 0.02 * i, rFront - 0.8, rFront + 0.25, TRIM)
	end
	-- the top tier, whole, and the staircase up the front to it: one step per 1.3 studs
	local top = 2.6 * 5
	box(F, "PyramidStep", f, -3.6, 3.6, 7.2, top + 0.08, -0.85, 6.8, SANDSTONE[1])
	for s = 0, 9 do
		local y1 = 1.3 * (s + 1)
		local v1 = 24.6 - 1.78 * s
		local w = 3.3 + 0.05 * (s % 2)
		box(F, "PyramidStair", f, -w, w, math.max(0, y1 - 1.6), y1, v1 - 2.25 - 0.4 * (s % 2), v1, SANDSTONE[3])
	end
	-- the temple on top: walls, a dark doorway, a stepped roof
	box(F, "PyramidTemple", f, -3.1, 3.1, top - 0.4, top + 4.6, 0.2, 5.6, SANDSTONE[2])
	box(F, "PyramidDoor", f, -1.3, 1.3, top, top + 3.1, 5.6, 5.9, DARK)
	box(F, "PyramidTemple", f, -4, 4, top + 4.6, top + 5.6, -0.4, 6.5, TRIM)
	box(F, "PyramidTemple", f, -2.4, 2.4, top + 5.6, top + 6.6, 1.2, 4.8, SANDSTONE[1])
	-- the broken corner's blocks, tumbled on the sand at the right
	for i = 1, 4 do
		local u = 13 + i * 2.2 + rng:NextNumber(-0.8, 0.8)
		local v = 16 + rng:NextNumber(-2, 5)
		local s = rng:NextNumber(1.8, 3)
		block(F, "PyramidRubble", Vector3.new(s * 1.3, s, s) * f.scale,
			Kit.cf(f, u, s * 0.45, v, rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.25, 0.25)), SANDSTONE[i % 3 + 1])
	end
	-- an obelisk each side of the front
	for _, u in { -20.5, 20.5 } do
		local v = 21
		box(F, "Obelisk", f, u - 2, u + 2, 0, 1.6, v - 2, v + 2, TRIM)
		box(F, "Obelisk", f, u - 1.25, u + 1.25, 1.2, 11.5, v - 1.25, v + 1.25, SANDSTONE[2])
		block(F, "Obelisk", Vector3.new(1.75, 1.75, 1.75) * f.scale, Kit.cf(f, u, 11.4, v) * CFrame.Angles(0, 0, math.rad(45)), rgb(255, 214, 90))
	end
end

-- A palm tree leaning toward `dir` (a unit vector on the ground): a curved trunk of offset blocks and a
-- crown of drooping fronds with coconuts.
local function palm(F: Instance, base: Vector3, dir: Vector3, h: number, rng: Random)
	local segs = 6
	local seg = h / segs
	local turn = math.atan2(dir.X, dir.Z)
	local pos = base
	local lean = 0
	for i = 1, segs do
		lean += 0.045 * i
		local step = Vector3.new(dir.X * math.sin(lean), math.cos(lean), dir.Z * math.sin(lean)) * seg
		local cf = CFrame.new(pos + step / 2) * CFrame.Angles(0, turn, 0) * CFrame.Angles(lean, 0, 0)
		block(F, "PalmTrunk", Vector3.new(1.9 - i * 0.08, seg + 0.35, 1.9 - i * 0.08), cf * CFrame.Angles(0, (i % 2) * 0.4, 0), PALM[i % 2 + 1])
		pos += step
	end
	local crown = CFrame.new(pos) * CFrame.Angles(0, turn, 0)
	block(F, "PalmCrown", Vector3.new(2.4, 1.3, 2.4), crown * CFrame.new(0, 0.2, 0), PALM[1])
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local frond = crown * CFrame.Angles(0, a, 0)
		block(F, "PalmFrond", Vector3.new(4.6, 0.45, 1.7), frond * CFrame.new(2.3, 0.7 + i * 0.03, 0) * CFrame.Angles(0, 0, -0.18), FROND)
		block(F, "PalmFrond", Vector3.new(4.2, 0.4, 1.4), frond * CFrame.new(6.0, -0.35 + i * 0.03, 0) * CFrame.Angles(0, 0, -0.62), FROND_LIGHT)
	end
	for i = 1, 3 do
		local a = i * 2.1
		block(F, "Coconut", Vector3.new(0.9, 0.9, 0.9), crown * CFrame.new(math.cos(a) * 1.1, -0.85, math.sin(a) * 1.1), rgb(110, 72, 44))
	end
end

-- A saguaro in blocks: trunk, one or two arms, a flower on top sometimes. `h` is its height.
local function saguaro(F: Instance, p: Vector3, h: number, rng: Random)
	local spin = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	block(F, "Cactus", Vector3.new(3, h, 3), spin * CFrame.new(0, h / 2, 0), CACTUS)
	block(F, "Cactus", Vector3.new(2.3, 0.7, 2.3), spin * CFrame.new(0, h + 0.3, 0), CACTUS_LIGHT)
	for _, dir in { -1, 1 } do
		if dir == 1 or rng:NextNumber() < 0.65 then
			local y = h * rng:NextNumber(0.35, 0.55)
			local up = rng:NextNumber(3, 5.5)
			block(F, "CactusArm", Vector3.new(3.2, 2, 2), spin * CFrame.new(dir * 2.6, y, 0), CACTUS)
			block(F, "CactusArm", Vector3.new(2, up, 1.8), spin * CFrame.new(dir * 3.7, y + up / 2 + 0.4, 0), CACTUS)
			block(F, "CactusArm", Vector3.new(1.5, 0.5, 1.5), spin * CFrame.new(dir * 3.7, y + up + 0.55, 0), CACTUS_LIGHT)
		end
	end
	if rng:NextNumber() < 0.6 then
		block(F, "CactusFlower", Vector3.new(1.4, 0.9, 1.4), spin * CFrame.new(0, h + 1.05, 0) * CFrame.Angles(0, math.rad(45), 0), rgb(255, 110, 170))
	end
end

-- A squat barrel cactus with a flower crown.
local function barrel(F: Instance, p: Vector3, s: number, rng: Random)
	local spin = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	block(F, "Barrel", Vector3.new(2.8 * s, 2.4 * s, 2.8 * s), spin * CFrame.new(0, 1.2 * s, 0), CACTUS)
	block(F, "Barrel", Vector3.new(2.1 * s, 0.6 * s, 2.1 * s), spin * CFrame.new(0, 2.5 * s, 0), CACTUS_LIGHT)
	block(F, "CactusFlower", Vector3.new(1 * s, 0.7 * s, 1 * s), spin * CFrame.new(0, 2.95 * s, 0) * CFrame.Angles(0, math.rad(45), 0),
		if rng:NextNumber() < 0.5 then rgb(255, 200, 60) else rgb(255, 120, 180))
end

-- Stepped dune: three sand layers, each smaller and offset, long along X.
local function dune(F: Instance, p: Vector3, len: number, dep: number, rng: Random)
	local x, z = p.X, p.Z
	for i = 0, 2 do
		local l = len * (1 - i * 0.3) * rng:NextNumber(0.9, 1)
		local d = dep * (1 - i * 0.3) * rng:NextNumber(0.85, 1)
		x += rng:NextNumber(-0.12, 0.12) * len
		local h = 1.4 + i * 0.07
		local y = i * 1.3
		block(F, "Dune", Vector3.new(l, h, d), CFrame.new(x, GROUND + y + h / 2 - 0.1, z + rng:NextNumber(-0.1, 0.1) * dep), DUNE[i + 1])
	end
end

-- A giant skull (looking along +X) and its spine and ribs, half buried in the sand.
local function skeleton(F: Instance, p: Vector3, rng: Random)
	local cf = CFrame.new(p)
	local s = 1.5
	local function b(name: string, size: Vector3, offset: CFrame, color: Color3)
		block(F, name, size * s, cf * CFrame.new(offset.Position * s) * offset.Rotation, color)
	end
	-- the skull
	b("Skull", Vector3.new(8, 6.6, 7.4), CFrame.new(0, 3.1, 0), BONE)
	b("Skull", Vector3.new(2.2, 1.4, 7.8), CFrame.new(3.2, 5.3, 0), BONE_SHADE) -- the brow
	b("SkullSnout", Vector3.new(4.4, 3, 5.2), CFrame.new(5.5, 1.9, 0), BONE)
	b("SkullJaw", Vector3.new(5.6, 1.3, 5.6), CFrame.new(4.8, 0.45, 0) * CFrame.Angles(0, 0, 0.08), BONE_SHADE)
	for _, z in { -1.9, 1.9 } do
		b("EyeSocket", Vector3.new(0.5, 2.1, 2.1), CFrame.new(4.1, 3.7, z), DARK)
	end
	b("EyeSocket", Vector3.new(0.4, 1.1, 1.3), CFrame.new(7.75, 2.3, 0), DARK) -- the nose
	for i = 1, 4 do
		b("Tooth", Vector3.new(0.7, 0.9, 0.6), CFrame.new(7.2, 0.5, -2.1 + i * 0.85), rgb(255, 255, 250))
	end
	-- the spine and ribs behind it
	for i = 1, 5 do
		b("Spine", Vector3.new(2.2, 1.5 + (i % 2) * 0.2, 2), CFrame.new(-4.2 - i * 2.6, 0.55, 0) * CFrame.Angles(0, 0, 0.05 * i), BONE_SHADE)
	end
	for i = 1, 4 do
		local x = -6.5 - i * 2.6
		local h = 6.2 - i * 0.6
		for _, side in { -1, 1 } do
			local rib = CFrame.new(x, 0, side * 1.2) * CFrame.Angles(side * 0.55, 0, 0)
			b("Rib", Vector3.new(0.9, h, 0.9), rib * CFrame.new(0, h / 2, 0), BONE)
			b("Rib", Vector3.new(0.85, 2.6, 0.85), rib * CFrame.new(0, h - 0.2, 0) * CFrame.Angles(-side * 1.1, 0, 0) * CFrame.new(0, 1.1, 0), BONE)
		end
	end
	return rng
end

-- Broken columns, a fallen one and a crumbling wall, in frame `f`.
local function ruins(F: Instance, f: Kit.Frame, rng: Random)
	local function column(u: number, v: number, drums: number, capital: boolean)
		box(F, "Column", f, u - 2, u + 2, 0, 1.3, v - 2, v + 2, SANDSTONE[3])
		local y = 1.3
		for i = 1, drums do
			local h = 3 + rng:NextNumber(-0.3, 0.3)
			local cf = Kit.cf(f, u + rng:NextNumber(-0.15, 0.15), y + h / 2, v, rng:NextNumber(-0.15, 0.15), 0, 0)
			block(F, "Column", Vector3.new(2.9, h, 2.9) * f.scale, cf, SANDSTONE[i % 2 + 1])
			y += h
		end
		if capital then
			box(F, "Column", f, u - 2.1, u + 2.1, y - 0.1, y + 1.1, v - 2.1, v + 2.1, TRIM)
		else -- a broken top: half a drum, tipped
			block(F, "Column", Vector3.new(2.9, 1.6, 1.6) * f.scale, Kit.cf(f, u, y + 0.5, v - 0.5, 0, 0.3, 0), SANDSTONE[1])
		end
	end
	column(-12, 7, 4, true)
	column(-3, 8.5, 2, false)
	column(6, 7.5, 3, false)
	-- a fallen column, its drums lying in a row
	for i = 1, 3 do
		local u = 6 + i * 3.4
		block(F, "Column", Vector3.new(3.1, 2.8, 2.8) * f.scale, Kit.cf(f, u, 1.25, 15 + i * 0.5, 0.08 * i, 0, 0), SANDSTONE[i % 2 + 1])
	end
	-- the crumbling wall: blocks of ragged heights, a drift of sand at its foot
	local u = -17
	for i = 1, 7 do
		local w = rng:NextNumber(2.4, 3.4)
		local h = 9 - math.abs(i - 3) * 1.6 + rng:NextNumber(-0.8, 0.8)
		box(F, "RuinWall", f, u, u + w, 0, h, 0.4 + (i % 2) * 0.15, 3.2 + (i % 2) * 0.15, SANDSTONE[i % 3 + 1])
		u += w
	end
	box(F, "Dune", f, -18, -2, 0, 1.15, 2.8, 5.6, DUNE[1])
end

local function tumbleweed(F: Instance, p: Vector3, rng: Random)
	local cf = CFrame.new(p + Vector3.new(0, 1.3, 0))
	for i = 1, 4 do
		block(F, "Tumbleweed", Vector3.new(2.8, 0.35, 0.35),
			cf * CFrame.Angles(rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi)), if i % 2 == 0 then rgb(176, 130, 80) else rgb(150, 106, 64))
	end
	block(F, "Tumbleweed", Vector3.new(1.6, 1.6, 1.6), cf * CFrame.Angles(0.6, 0.3, 0.9), rgb(186, 140, 88))
end

function Desert.build(c: Kit.Ctx)
	local F = c.folder
	Kit.floor(c, Desert)
	Kit.walls(c, Desert)

	-- Left wall: the Meadow's turtle reaches its first dozen studs and the nest has its last stretch, so
	-- the pyramid and the ruins share the middle. Right wall: cacti, a dune, the oasis, cacti, the skull.
	local pyrFrame = Kit.wallFrame(at(c, 0.26), -1, 1.65)
	local pyrRng = Kit.rand(c, "pyramid")
	Assets.swap("Desert_Pyramid", F, Kit.facing(pyrFrame), function(into)
		pyramid(into, pyrFrame, pyrRng)
	end)
	local ruinFrame = Kit.wallFrame(at(c, 0.55), -1, 1.3)
	local ruinRng = Kit.rand(c, "ruins")
	Assets.swap("Desert_Ruins", F, Kit.facing(ruinFrame), function(into)
		ruins(into, ruinFrame, ruinRng)
	end)

	-- the oasis on the right: a pond, palms leaning over it, rocks
	local ox = at(c, 0.42)
	Kit.pond(F, Vector3.new(ox, GROUND, 70), 28, 2)
	for i, q in { { -18, 86, 17, 0.3, -0.9 }, { 15, 88, 20, -0.6, -0.8 }, { -4, 52, 15, 0.2, 1 } } do
		local p = Vector3.new(ox + q[1], GROUND, q[2])
		local dir = Vector3.new(q[4], 0, q[5]).Unit
		local rng = Kit.rand(c, "palm" .. i)
		Assets.swap("Desert_Palm", F, Assets.facing(p, dir), function(into)
			palm(into, p, dir, q[3], rng)
		end)
	end
	for i, q in { { -20, 60, 3.4 }, { 21, 62, 4.2 }, { 6, 89, 3 } } do
		local p = Vector3.new(ox + q[1], GROUND, q[2])
		local rng = Kit.rand(c, "oasisRock" .. i)
		Assets.swap("Desert_Rock", F, Assets.spin(p), function(into)
			Kit.rock(into, "Rock", p, q[3], rng, rgb(196, 160, 110), rgb(214, 180, 128))
		end)
	end

	-- the skull on the right toward the end, looking down the corridor
	local skull = Vector3.new(at(c, 0.85), GROUND, 74)
	local skullRng = Kit.rand(c, "skull")
	Assets.swap("Desert_Skull", F, Assets.facing(skull, Vector3.xAxis), function(into)
		skeleton(into, skull, skullRng)
	end)
	for i, q in { { 0.93, 58 }, { 0.5, 54 }, { 0.36, -54 } } do
		local rng = Kit.rand(c, "bone" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-4, 4), GROUND + 0.45, q[2])
		local d = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * 1.7
		Assets.swap("Desert_Bone", F, Assets.facing(p - Vector3.new(0, 0.45, 0), d), function(into)
			local along = Props.lookAt(Vector3.zero, d)
			block(into, "Bone", Vector3.new(0.6, 0.6, 3.4), CFrame.new(p) * along.Rotation, BONE)
			for _, e in { -1, 1 } do
				block(into, "BoneEnd", Vector3.new(1.3, 0.8, 0.8), CFrame.new(p + d * e) * along.Rotation, BONE_SHADE)
			end
		end)
	end

	-- cactus clusters along the right wall
	for i, q in { { 0.08, 82 }, { 0.6, 84 }, { 0.97, 82 } } do
		local rng = Kit.rand(c, "cactus" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-3, 3), GROUND, q[2])
		Assets.swap("Desert_Cactus", F, Assets.spin(p), function(into)
			saguaro(into, p, rng:NextNumber(12, 18), rng)
			barrel(into, p + Vector3.new(rng:NextNumber(3.5, 5), 0, -math.sign(q[2]) * rng:NextNumber(3, 6)), rng:NextNumber(0.8, 1.1), rng)
			if rng:NextNumber() < 0.6 then
				saguaro(into, p + Vector3.new(-rng:NextNumber(4, 6), 0, -math.sign(q[2]) * rng:NextNumber(2, 4)), rng:NextNumber(5, 7), rng)
			end
		end)
	end

	-- stepped dunes against the walls
	for i, q in { { 0.225, 88, 28, 11 }, { 0.62, 91, 20, 8 }, { 0.11, -90, 16, 8 } } do
		local rng = Kit.rand(c, "dune" .. i)
		dune(F, Vector3.new(at(c, q[1]), GROUND, q[2]), q[3], q[4], rng)
	end
	for i, q in { { 0.15, 50 }, { 0.4, -46 }, { 0.79, 46 } } do
		local rng = Kit.rand(c, "tumbleweed" .. i)
		local p = Vector3.new(at(c, q[1]), GROUND, q[2])
		Assets.swap("Desert_Tumbleweed", F, Assets.spin(p), function(into)
			tumbleweed(into, p, rng)
		end)
	end

	Kit.ambience(c, 200, 3, 4, { -- drifting sand
		texture = Props.TEX.smoke, color = rgb(240, 214, 160), rate = 3, lifetime = NumberRange.new(5, 8),
		speed = NumberRange.new(1, 3), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) }),
		transparency = Kit.fade(0.8, 0.9), spread = Vector2.new(180, 30), acceleration = Vector3.new(5, 0, 0),
	})
	Kit.ambience(c, 200, 10, 14, { -- heat sparkles
		color = rgb(255, 236, 170), rate = 4, lifetime = NumberRange.new(2, 4), speed = NumberRange.new(0.2, 0.8),
		size = NumberSequence.new(0.3), spread = Vector2.new(180, 180), lightEmission = 0.8,
	})
end

return Desert
