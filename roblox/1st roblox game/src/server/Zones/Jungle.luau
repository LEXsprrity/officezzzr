-- 3. Jungle: deep green walls under a lime cap, vines hanging down them:
--   * a mossy rock cliff against the left wall with a waterfall pouring from a notch into a lily pond
--   * ruins on the right: a giant stone head half covered in moss, a stepped altar and broken columns
--   * giant trees with roots, layered canopies and hanging vines
--   * bamboo clumps, giant leaf plants, bushes, a fallen log with mushrooms, big tropical flowers
--   * fireflies and falling leaves
local Assets = require(script.Parent.Parent:WaitForChild("Assets"))
local Props = require(script.Parent.Parent:WaitForChild("Props"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local rgb, at, box = Kit.rgb, Kit.at, Kit.box
local block = Props.block
local GROUND, HALF_W, H = Kit.GROUND, Kit.HALF_W, Kit.H

local Jungle = {}
Jungle.floorLight = rgb(72, 184, 82)
Jungle.wallLight = rgb(72, 126, 68)
Jungle.cap = rgb(124, 222, 74)

local LEAF = rgb(52, 160, 60)
local LEAF_DARK = rgb(40, 132, 52)
local LEAF_LIGHT = rgb(98, 204, 76)
local TRUNK = rgb(122, 84, 52)
local TRUNK_DARK = rgb(98, 66, 42)
local VINE = rgb(52, 150, 52)
local STONE = { rgb(128, 142, 128), rgb(112, 126, 114), rgb(144, 156, 140) }
local MOSS = rgb(88, 176, 70)
local DARK = rgb(40, 44, 40)

-- A giant jungle tree: flared roots, a trunk of three stacked blocks, two branches, a canopy in layers and
-- vines hanging from it. `s` scales it (1: about 36 studds tall); it leans its canopy toward `lean`.
local function bigTree(F: Instance, base: Vector3, s: number, lean: Vector3, rng: Random)
	local spin = CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, math.pi / 2), 0)
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + 0.4
		block(F, "Root", Vector3.new(2.2, 3.6, 5) * s, spin * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.2 * s, 2.6 * s) * CFrame.Angles(-0.5, 0, 0), TRUNK_DARK)
	end
	local h1, h2, h3 = 12 * s, 10 * s, 8 * s
	block(F, "Trunk", Vector3.new(4.6, h1, 4.6) * Vector3.new(s, 1, s), spin * CFrame.new(0, h1 / 2, 0), TRUNK)
	local mid = spin * CFrame.new(lean.X * 0.8, h1 - 0.4, lean.Z * 0.8)
	block(F, "Trunk", Vector3.new(3.9 * s, h2, 3.9 * s), mid * CFrame.new(0, h2 / 2, 0), TRUNK_DARK)
	local up = mid * CFrame.new(lean.X * 0.8, h2 - 0.4, lean.Z * 0.8)
	block(F, "Trunk", Vector3.new(3.2 * s, h3, 3.2 * s), up * CFrame.new(0, h3 / 2, 0), TRUNK)
	local top = up * CFrame.new(lean.X * 0.6, h3, lean.Z * 0.6)
	for i, a in { 0.6, 3.6 } do
		local len = 8 * s
		local branch = up * CFrame.new(0, h3 * 0.5, 0) * CFrame.Angles(0, a + i * 0.3, 0) * CFrame.Angles(0, 0, -0.9)
		block(F, "Branch", Vector3.new(1.6 * s, len, 1.6 * s), branch * CFrame.new(0, len / 2, 0), TRUNK_DARK)
		block(F, "Canopy", Vector3.new(10, 3.6, 10) * s, branch * CFrame.new(0, len, 0) * CFrame.Angles(0, 0, 0.9) * CFrame.new(0, 0.6 * s + i * 0.05, 0), if i == 1 then LEAF_LIGHT else LEAF)
	end
	-- the canopy: a big leafy mass of overlapping blocks, a fringe hanging under it
	block(F, "Canopy", Vector3.new(22, 6, 18) * s, top * CFrame.new(0, 1 * s, 0), LEAF)
	block(F, "Canopy", Vector3.new(16, 7, 22) * s, top * CFrame.new(1.2 * s, 2.2 * s, -0.8 * s), LEAF_DARK)
	block(F, "Canopy", Vector3.new(14, 5, 14) * s, top * CFrame.new(-1 * s, 5.5 * s, 0.6 * s), LEAF_LIGHT)
	block(F, "Canopy", Vector3.new(8, 3.4, 8) * s, top * CFrame.new(0.6 * s, 8.2 * s, -0.4 * s), LEAF)
	block(F, "Canopy", Vector3.new(18, 2.4, 14) * s, top * CFrame.new(0.4 * s, -2.4 * s, 0.3 * s), LEAF_DARK)
	-- vines hanging off the canopy's edges
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local len = rng:NextNumber(7, 13) * s
		local at = top * CFrame.new(math.cos(a) * 9 * s, -1.4 * s - len / 2, math.sin(a) * 7 * s)
		block(F, "TreeVine", Vector3.new(0.6, len, 0.6), at, VINE)
		block(F, "TreeVine", Vector3.new(1.8, 1.2, 0.5), at * CFrame.new(0, -len / 2, 0) * CFrame.Angles(0, a, 0), LEAF_LIGHT)
	end
end

-- A giant leaf plant: big flat leaves fanned out and tipped up, around a short stalk.
local function leafPlant(F: Instance, p: Vector3, s: number, rng: Random)
	local spin = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	block(F, "LeafPlant", Vector3.new(1.2, 2.2, 1.2) * s, spin * CFrame.new(0, 1.1 * s, 0), LEAF_DARK)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local tip = rng:NextNumber(0.25, 0.45)
		block(F, "LeafPlant", Vector3.new(7, 0.45, 2.6) * s,
			spin * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.6 * s + i * 0.04, 0) * CFrame.Angles(0, 0, tip) * CFrame.new(3.4 * s, 0, 0),
			if i % 2 == 0 then LEAF_LIGHT else LEAF)
	end
end

-- A big tropical flower: a stalk and five chunky petals round a yellow heart.
local function bigFlower(F: Instance, p: Vector3, color: Color3, rng: Random)
	local spin = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	local h = rng:NextNumber(3, 4.5)
	block(F, "BigFlower", Vector3.new(0.5, h, 0.5), spin * CFrame.new(0, h / 2, 0), VINE)
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		block(F, "BigFlower", Vector3.new(1.8, 0.4, 1.1), spin * CFrame.Angles(0, a, 0) * CFrame.new(1.05, h + 0.1 + i * 0.02, 0) * CFrame.Angles(0, 0, 0.3), color)
	end
	block(F, "BigFlower", Vector3.new(0.9, 0.7, 0.9), spin * CFrame.new(0, h + 0.4, 0), rgb(255, 222, 70))
end

-- The cliff in frame `f`: rock towers either side of a notch the waterfall pours from, ledges stepping
-- down in front, moss on every top.
local function cliff(F: Instance, f: Kit.Frame)
	local s1, s2, s3 = STONE[1], STONE[2], STONE[3]
	local rocks = {
		{ -21, -5.2, 0, 24.3, -0.6, 6.4, s1 }, { -5.4, 5.6, 0, 21.1, -0.7, 5.9, s2 }, { 5.3, 20.6, 0, 27.4, -0.6, 6.8, s3 },
		{ -19.2, -6.1, 0, 15.2, 5.6, 11.3, s2 }, { 6.4, 18.3, 0, 12.4, 5.5, 12.2, s1 },
		{ -17.1, -7.2, 0, 6.3, 10.6, 15.4, s3 }, { 7.3, 16.2, 0, 5.2, 11.6, 16.3, s2 }, { -23.6, -18.4, 0, 9.1, 1.2, 9.4, s3 },
		{ 19.4, 24.2, 0, 14.3, 0.8, 8.2, s2 },
	}
	for i, r in rocks do
		box(F, "CliffRock", f, r[1], r[2], r[3], r[4], r[5], r[6], r[7])
		-- moss on its top, a little inset, hanging over the front a bit
		box(F, "Moss", f, r[1] + 0.6, r[2] - 0.5, r[4] - 0.3, r[4] + 0.55 + i * 0.01, r[5] + 0.4, r[6] + 0.35, MOSS)
	end
	Kit.waterfall(F, f, 0, 5.9, 7.5, 21.1)
end

-- The ruins in frame `f`: a giant stone head, a stepped altar with a doorway, broken columns.
local function ruins(F: Instance, f: Kit.Frame, rng: Random)
	local s1, s2, s3 = STONE[1], STONE[2], STONE[3]
	-- the stepped altar
	box(F, "Ruin", f, -6, 22, 0, 2.6, -0.6, 18.4, s2)
	box(F, "Ruin", f, -3.6, 19.4, 0, 5.3, -0.7, 13.6, s1)
	box(F, "Ruin", f, -0.8, 16.2, 0, 8.1, -0.8, 9.2, s3)
	box(F, "Ruin", f, 2.2, 13.1, 8.1, 13.6, 0.2, 7.3, s1)
	box(F, "RuinDoor", f, 5.8, 9.4, 8.1, 11.6, 7.3, 7.6, DARK)
	box(F, "Ruin", f, 1.4, 13.9, 13.6, 14.8, -0.4, 8.1, s3)
	for i, r in { { -6, 22, 2.6, -0.6, 18.4 }, { -3.6, 19.4, 5.3, -0.7, 13.6 }, { -0.8, 16.2, 8.1, -0.8, 9.2 }, { 1.4, 13.9, 14.8, -0.4, 8.1 } } do
		local m0 = r[1] + 1 + rng:NextNumber(0, 3)
		box(F, "Moss", f, m0, m0 + rng:NextNumber(4, 8), r[3] - 0.25, r[3] + 0.45 + i * 0.01, r[4] + 0.6, r[5] - rng:NextNumber(0.4, 2), MOSS)
	end
	-- the giant head, looking out at the corridor
	local hu, hv = -14, 14
	box(F, "StoneHead", f, hu - 5.5, hu + 5.5, 0, 12.4, hv - 5, hv + 4.6, s1)
	box(F, "StoneHead", f, hu - 6, hu + 6, 9.8, 13.6, hv - 5.4, hv + 5.2, s3) -- the brow and headdress
	box(F, "StoneHead", f, hu - 1.2, hu + 1.2, 4.6, 8.4, hv + 4.6, hv + 6.0, s2) -- the nose
	box(F, "StoneHead", f, hu - 3.4, hu + 3.4, 1.6, 2.9, hv + 4.6, hv + 5.1, DARK) -- the mouth
	for _, e in { -1, 1 } do
		box(F, "StoneHead", f, hu + e * 3 - 1.4, hu + e * 3 + 1.4, 7.4, 9.1, hv + 4.6, hv + 4.95, rgb(250, 250, 240))
		box(F, "StoneHead", f, hu + e * 3 - 0.6, hu + e * 3 + 0.4, 7.5, 8.8, hv + 4.95, hv + 5.2, DARK)
		box(F, "StoneHead", f, hu + e * 6.1 - 0.9, hu + e * 6.1 + 0.9, 3.6, 9.4, hv - 2.2, hv + 2.4, s2) -- the ears
	end
	box(F, "Moss", f, hu - 4.8, hu + 3.6, 13.3, 14.2, hv - 4.6, hv + 2.8, MOSS)
	box(F, "Moss", f, hu + 2.4, hu + 6.3, 11.6, 13.9, hv - 5.6, hv - 2.4, MOSS)
	-- broken columns with vines
	for i, q in { { 24.5, 9, 13.5 }, { 27.5, 15.5, 8.2 }, { 21.5, 21.5, 5.6 } } do
		local u, v, h = q[1], q[2], q[3]
		box(F, "Column", f, u - 1.9, u + 1.9, 0, 1.2, v - 1.9, v + 1.9, s2)
		box(F, "Column", f, u - 1.4, u + 1.4, 1.0, h, v - 1.4, v + 1.4, if i % 2 == 0 then s1 else s3)
		box(F, "Moss", f, u - 1.15, u + 1.6, h - 0.2, h + 0.45, v - 1.6, v + 1.1, MOSS)
		box(F, "TreeVine", f, u + 1.4, u + 1.8, h * 0.3, h - 0.1, v - 0.5, v + 0.3, VINE)
	end
end

-- A fallen log with a moss top, a stump end and two little mushrooms.
local function log(F: Instance, p: Vector3, rng: Random)
	local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0)
	block(F, "Log", Vector3.new(16, 3.4, 3.4), cf * CFrame.new(0, 1.5, 0), TRUNK)
	block(F, "Log", Vector3.new(0.6, 3, 3), cf * CFrame.new(8.2, 1.5, 0), rgb(206, 160, 104))
	block(F, "Moss", Vector3.new(9, 0.6, 2.6), cf * CFrame.new(-2, 3.35, 0.2), MOSS)
	for i, q in { { 3, 2.4 }, { 5.2, 1.6 } } do
		local m = cf * CFrame.new(q[1], 3.2, 1.2 - i * 0.3)
		block(F, "LogMushroom", Vector3.new(0.5, q[2], 0.5), m * CFrame.new(0, q[2] / 2, 0), rgb(250, 238, 214))
		block(F, "LogMushroom", Vector3.new(1.9, 0.6, 1.9) * (q[2] / 2.4), m * CFrame.new(0, q[2], 0), rgb(255, 140, 50))
	end
end

-- Vines down a wall (side `s`): a few hanging from its top along the zone, each with leaves.
local function wallVines(c: Kit.Ctx, rng: Random)
	for i = 1, 7 do
		for _, s in { -1, 1 } do
			local x = at(c, (i - 0.5) / 7) + s * 18 + rng:NextNumber(-6, 6)
			local len = rng:NextNumber(14, 28)
			local z = s * (HALF_W - 0.5)
			Props.block(c.folder, "Vine", Vector3.new(0.8, len, 0.8), CFrame.new(x, GROUND + H - len / 2 + 0.6, z), VINE)
			for j = 1, 2 do
				local y = GROUND + H - len * j / 2.15
				Props.block(c.folder, "VineLeaf", Vector3.new(2.4, 1.3, 0.5), CFrame.new(x + (j % 2) * 1.2 - 0.6, y, z - s * 0.5) * CFrame.Angles(0, 0, (j % 2 - 0.5) * 0.8),
					if j == 2 then LEAF_LIGHT else LEAF)
			end
		end
	end
end

function Jungle.build(c: Kit.Ctx)
	local F = c.folder
	Kit.floor(c, Jungle)
	Kit.walls(c, Jungle)
	wallVines(c, Kit.rand(c, "vines"))

	-- the waterfall cliff on the left near the entrance, its pond in front
	local cliffFrame = Kit.wallFrame(at(c, 0.17), -1, 1.4)
	Assets.swap("Jungle_Waterfall", F, Kit.facing(cliffFrame), function(into)
		cliff(into, cliffFrame)
	end)
	local pondAt = Kit.p(cliffFrame, 0, 0, 17)
	Kit.pond(F, Vector3.new(math.round(pondAt.X), GROUND, math.round(pondAt.Z)), 26, 4)

	-- the ruins on the right, halfway along
	local ruinFrame = Kit.wallFrame(at(c, 0.5), 1, 1.6)
	local ruinRng = Kit.rand(c, "ruins")
	Assets.swap("Jungle_Ruins", F, Kit.facing(ruinFrame), function(into)
		ruins(into, ruinFrame, ruinRng)
	end)

	-- giant trees along both walls, their canopies leaning in
	for i, q in { { 0.05, -1, 1.0 }, { 0.36, -1, 1.15 }, { 0.56, -1, 1.05 }, { 0.1, 1, 1.1 }, { 0.3, 1, 0.95 }, { 0.7, 1, 1.2 }, { 0.9, 1, 1.0 } } do
		local rng = Kit.rand(c, "tree" .. i)
		local s = q[2]
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-5, 5), GROUND, s * rng:NextNumber(80, 84))
		Assets.swap("Jungle_Tree", F, Assets.facing(p, Vector3.new(0, 0, -s)), function(into)
			bigTree(into, p, q[3], Vector3.new(0, 0, -s * 1.2), rng)
		end)
	end
	-- bamboo, leaf plants, flowers and a fallen log in between
	for i, q in { { 0.22, 1, 5 }, { 0.47, -1, 4 }, { 0.8, 1, 5 }, { 0.65, -1, 4 } } do
		local rng = Kit.rand(c, "bamboo" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-4, 4), GROUND, q[2] * rng:NextNumber(84, 88))
		Assets.swap("Jungle_Bamboo", F, Assets.spin(p), function(into)
			Kit.bamboo(into, "Bamboo", p, rng, q[3], rng:NextNumber(18, 26))
		end)
	end
	for i, q in { { 0.08, 1 }, { 0.27, -1 }, { 0.42, -1 }, { 0.63, 1 }, { 0.84, 1 }, { 0.95, 1 }, { 0.17, 1 } } do
		local rng = Kit.rand(c, "leaf" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-6, 6), GROUND, q[2] * rng:NextNumber(66, 76))
		Assets.swap("Jungle_Fern", F, Assets.spin(p), function(into)
			leafPlant(into, p, rng:NextNumber(1.6, 2.1), rng)
		end)
	end
	for i, q in { { 0.04, 1, 7 }, { 0.26, 1, 6 }, { 0.77, 1, 7.5 }, { 0.3, -1, 6.5 }, { 0.6, -1, 7 }, { 0.68, -1, 6 } } do
		local rng = Kit.rand(c, "bush" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-3, 3), GROUND, q[2] * rng:NextNumber(84, 88))
		Assets.swap("Jungle_Bush", F, Assets.spin(p), function(into)
			Kit.bush(into, p, q[3], rng, LEAF_DARK, LEAF, rgb(255, 120, 60))
		end)
	end
	for i, q in { { 0.12, -1 }, { 0.33, 1 }, { 0.52, -1 }, { 0.86, 1 }, { 0.62, 1 } } do
		local rng = Kit.rand(c, "flower" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-4, 4), GROUND, q[2] * rng:NextNumber(60, 66))
		bigFlower(F, p, ({ rgb(255, 70, 70), rgb(255, 150, 40), rgb(255, 90, 200) })[i % 3 + 1], rng)
	end
	local logRng = Kit.rand(c, "log")
	local logAt = Vector3.new(at(c, 0.72), GROUND, -76)
	Assets.swap("Jungle_Log", F, Assets.facing(logAt, Vector3.new(0, 0, 1)), function(into)
		log(into, logAt, logRng)
	end)

	Kit.ambience(c, 200, 7, 10, { -- fireflies
		color = rgb(210, 255, 120), rate = 4, lifetime = NumberRange.new(3, 5), speed = NumberRange.new(0.3, 1.2),
		size = NumberSequence.new(0.35), spread = Vector2.new(180, 180), lightEmission = 1, lightInfluence = 0,
	})
	Kit.ambience(c, 400, 36, 2, { -- falling leaves
		color = Kit.gradient(rgb(90, 200, 70), rgb(160, 220, 60)), rate = 4, lifetime = NumberRange.new(6, 9),
		speed = NumberRange.new(2, 4), size = NumberSequence.new(0.6), direction = Enum.NormalId.Bottom,
		acceleration = Vector3.new(0.8, -0.5, 0), rotSpeed = NumberRange.new(-90, 90),
	})
end

return Jungle
