-- 1. Meadow: the first stretch, a bright garden. Green lawn, earth-brown walls under a grass cap:
--   * the lily pond the owner liked (checker water, notched lily pads with a flower, reeds) near the entrance
--   * two raised flower beds, the big one behind a white picket fence with a watering can
--   * a cluster of big red spotted mushrooms
--   * round block trees, bushes, rocks and little flowers along the walls
--   * butterflies and pollen in the air
-- The nest (the Giant Turtle) has the left wall's far half, so the left side keeps the pond, a tree and bushes.
local Assets = require(script.Parent.Parent:WaitForChild("Assets"))
local Props = require(script.Parent.Parent:WaitForChild("Props"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local rgb, at, box = Kit.rgb, Kit.at, Kit.box
local block = Props.block
local GROUND = Kit.GROUND

local Meadow = {}
Meadow.floorLight = rgb(124, 212, 64)
Meadow.wallLight = rgb(212, 144, 94)
Meadow.cap = rgb(96, 220, 64)

local LEAF = rgb(70, 178, 58)
local LEAF_LIGHT = rgb(110, 206, 74)
local TRUNK = rgb(150, 98, 58)
local STEM = rgb(70, 170, 60)
local PICKET = rgb(250, 250, 244)
local RAIL = rgb(222, 224, 226)
local WOOD = rgb(176, 116, 70)
local SOIL = rgb(118, 78, 56)
local STONE = rgb(160, 162, 172)
local STONE_LIGHT = rgb(186, 188, 196)
local CREAM = rgb(250, 238, 214)
local BRIGHT = {
	rgb(255, 90, 120), rgb(255, 215, 60), rgb(170, 110, 255), rgb(255, 150, 60), rgb(90, 190, 255), rgb(255, 255, 255), rgb(255, 120, 210),
}

-- A little block flower: a stem, a leaf, two crossed petals and a yellow heart.
local function flower(F: Instance, p: Vector3, petal: Color3, h: number, rng: Random)
	local spin = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	block(F, "FlowerStem", Vector3.new(0.35, h, 0.35), spin * CFrame.new(0, h / 2, 0), STEM)
	block(F, "FlowerLeaf", Vector3.new(1.1, 0.22, 0.5), spin * CFrame.new(0.55, h * 0.45, 0) * CFrame.Angles(0, 0, 0.35), STEM)
	block(F, "FlowerPetal", Vector3.new(1.9, 0.42, 0.72), spin * CFrame.new(0, h + 0.1, 0), petal)
	block(F, "FlowerPetal", Vector3.new(0.72, 0.5, 1.9), spin * CFrame.new(0, h + 0.17, 0), petal)
	block(F, "FlowerHeart", Vector3.new(0.82, 0.62, 0.82), spin * CFrame.new(0, h + 0.27, 0), rgb(255, 222, 70))
end

-- A raised wooden flower bed full of flowers (frame `f`: u along, v out), `len` x `dep` studs.
local function flowerBed(F: Instance, f: Kit.Frame, len: number, dep: number, rng: Random)
	local l2 = len / 2
	box(F, "BedBorder", f, -l2, l2, 0, 1.45, 0, 1, WOOD)
	box(F, "BedBorder", f, -l2, l2, 0, 1.45, dep - 1, dep, WOOD)
	box(F, "BedBorder", f, -l2, -l2 + 1, 0, 1.75, 1, dep - 1, WOOD)
	box(F, "BedBorder", f, l2 - 1, l2, 0, 1.75, 1, dep - 1, WOOD)
	box(F, "BedSoil", f, -l2 + 1, l2 - 1, 0, 1.05, 1, dep - 1, SOIL)
	local n = math.floor(len / 3)
	for i = 1, n do
		for row = 0, 1 do
			if (i + row) % 2 == 0 or rng:NextNumber() < 0.4 then
				local u = -l2 + 1 + (i - 0.5) * (len - 2) / n + rng:NextNumber(-0.4, 0.4)
				local v = 1 + (dep - 2) * (if row == 0 then 0.3 else 0.72)
				flower(F, Kit.p(f, u, 1.05, v), BRIGHT[rng:NextInteger(1, #BRIGHT)], rng:NextNumber(1.6, 2.8), rng)
			end
		end
	end
end

-- A white picket fence along the frame's u from u0 to u1 (pointed pickets on two rails), at v.
local function picketFence(F: Instance, f: Kit.Frame, u0: number, u1: number, v: number, rng: Random)
	local n = math.max(2, math.floor((u1 - u0) / 1.7))
	for i = 0, n - 1 do
		local u = u0 + (i + 0.5) * (u1 - u0) / n
		local h = 3.4 + rng:NextNumber(-0.15, 0.15)
		local lean = if rng:NextNumber() < 0.15 then rng:NextNumber(-0.12, 0.12) else 0
		local base = Kit.cf(f, u, 0, v, 0, 0, lean)
		block(F, "Picket", Vector3.new(0.9, h, 0.45), base * CFrame.new(0, h / 2, 0), PICKET)
		block(F, "PicketTip", Vector3.new(0.64, 0.64, 0.42), base * CFrame.new(0, h, 0) * CFrame.Angles(0, 0, math.rad(45)), PICKET)
	end
	for _, y in { 1.0, 2.5 } do
		box(F, "PicketRail", f, u0 - 0.3, u1 + 0.3, y - 0.25, y + 0.25, v - 0.6, v - 0.23, RAIL)
	end
end

-- A teal watering can: body, spout with its rose, and a handle on top.
local function wateringCan(F: Instance, p: Vector3, yaw: number)
	local cf = CFrame.new(p) * CFrame.Angles(0, yaw, 0)
	local teal = rgb(60, 196, 200)
	block(F, "Can", Vector3.new(2.2, 1.9, 1.5), cf * CFrame.new(0, 0.95, 0), teal)
	block(F, "Can", Vector3.new(0.45, 0.45, 2.6), cf * CFrame.new(1.4, 1.4, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(-35), 0, 0), teal)
	block(F, "Can", Vector3.new(0.8, 0.8, 0.5), cf * CFrame.new(2.55, 2.15, 0) * CFrame.Angles(0, 0, math.rad(-35)), rgb(240, 200, 60))
	block(F, "Can", Vector3.new(1.7, 0.35, 0.35), cf * CFrame.new(-0.1, 2.3, 0), rgb(240, 200, 60))
end

-- A big red mushroom with white spots: a cream stem, a stepped cap and spots on it. `s` is its height.
local function mushroom(F: Instance, p: Vector3, s: number, rng: Random, cap: Color3)
	local spin = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	local w = s * 0.32
	block(F, "MushroomStem", Vector3.new(w, s * 0.62, w), spin * CFrame.new(0, s * 0.31, 0), CREAM)
	block(F, "MushroomCap", Vector3.new(w * 2.9, s * 0.2, w * 2.9), spin * CFrame.new(0, s * 0.66, 0), cap)
	block(F, "MushroomCap", Vector3.new(w * 2.2, s * 0.17, w * 2.2), spin * CFrame.new(0, s * 0.82, 0), cap)
	block(F, "MushroomCap", Vector3.new(w * 1.25, s * 0.13, w * 1.25), spin * CFrame.new(0, s * 0.95, 0), cap)
	for i = 1, 3 do
		local a = i * 2.1 + rng:NextNumber(-0.3, 0.3)
		local r = w * (if i == 3 then 0.3 else 0.85)
		local y = if i == 3 then s * 1.02 + 0.02 else s * 0.9 + i * 0.03
		block(F, "MushroomSpot", Vector3.new(w * 0.5, s * 0.06 + 0.1, w * 0.5), spin * CFrame.new(math.cos(a) * r, y, math.sin(a) * r), rgb(255, 255, 255))
	end
end

function Meadow.build(c: Kit.Ctx)
	local F = c.folder
	Kit.floor(c, Meadow)
	Kit.walls(c, Meadow)

	-- the lily pond on the left near the entrance (the nest has the rest of the left wall)
	Kit.pond(F, Vector3.new(at(c, 0.2), GROUND, -68), 26, 3)
	local left = Kit.rand(c, "left")
	Assets.swap("Meadow_Tree", F, Assets.spin(Vector3.new(at(c, 0.05), GROUND, -86)), function(into)
		Kit.roundTree(into, Vector3.new(at(c, 0.05), GROUND, -86), left, 13, 10, LEAF, LEAF_LIGHT, TRUNK)
	end)
	for i, q in { { 0.04, -60, 4.2 }, { 0.33, -86, 5.2 } } do
		local p = Vector3.new(at(c, q[1]), GROUND, q[2])
		Assets.swap("Meadow_Bush", F, Assets.spin(p), function(into)
			Kit.bush(into, p, q[3], Kit.rand(c, "leftBush" .. i), LEAF, LEAF_LIGHT, rgb(240, 60, 80))
		end)
	end

	-- the flower bed and its picket fence on the right
	local bedFrame = Kit.wallFrame(at(c, 0.34), 1)
	local bedRng = Kit.rand(c, "bed")
	Assets.swap("Meadow_FlowerBed", F, Kit.facing(bedFrame, 0, 18), function(into)
		flowerBed(into, Kit.frame(Kit.p(bedFrame, 0, 0, 14), bedFrame.out), 22, 9, bedRng)
		picketFence(into, bedFrame, -15.5, 15.5, 9.5, bedRng)
	end)
	wateringCan(F, Kit.p(bedFrame, 13.5, 0, 26.5), math.rad(200))
	-- a second, smaller bed further along, without a fence
	local bed2 = Kit.wallFrame(at(c, 0.76), 1)
	local bed2Rng = Kit.rand(c, "bed2")
	Assets.swap("Meadow_FlowerBed", F, Kit.facing(bed2, 0, 28), function(into)
		flowerBed(into, Kit.frame(Kit.p(bed2, 0, 0, 24), bed2.out), 13, 7, bed2Rng)
	end)

	-- the mushroom cluster further along the right
	local mush = Kit.rand(c, "mushrooms")
	local mx = at(c, 0.6)
	Assets.swap("Meadow_Mushroom", F, Assets.spin(Vector3.new(mx, GROUND, 78)), function(into)
		mushroom(into, Vector3.new(mx, GROUND, 80), 11, mush, rgb(235, 52, 52))
		mushroom(into, Vector3.new(mx - 8, GROUND, 75), 7.5, mush, rgb(240, 70, 60))
		mushroom(into, Vector3.new(mx + 5, GROUND, 71.5), 5.2, mush, rgb(255, 120, 40))
		mushroom(into, Vector3.new(mx - 3, GROUND, 68.5), 3.2, mush, rgb(235, 52, 52))
	end)

	-- round trees, bushes and rocks along the right wall
	for i, q in { { 0.08, 84, 14, 11 }, { 0.84, 82, 15.5, 12 } } do
		local p = Vector3.new(at(c, q[1]), GROUND, q[2])
		local rng = Kit.rand(c, "tree" .. i)
		Assets.swap("Meadow_Tree", F, Assets.spin(p), function(into)
			Kit.roundTree(into, p, rng, q[3], q[4], if i == 1 then LEAF else rgb(84, 190, 62), LEAF_LIGHT, TRUNK)
		end)
	end
	for i, q in { { 0.16, 74, 4.5 }, { 0.75, 88, 5.5 }, { 0.96, 72, 4.2 }, { 0.5, 88, 3.8 } } do
		local p = Vector3.new(at(c, q[1]), GROUND, q[2])
		Assets.swap("Meadow_Bush", F, Assets.spin(p), function(into)
			Kit.bush(into, p, q[3], Kit.rand(c, "bush" .. i), LEAF, LEAF_LIGHT, rgb(240, 60, 80))
		end)
	end
	for i, q in { { 0.7, 66, 3.2 }, { 0.93, 86, 4.4 } } do
		local rng = Kit.rand(c, "rock" .. i)
		local p = Vector3.new(at(c, q[1]), GROUND, q[2])
		Assets.swap("Meadow_Rock", F, Assets.spin(p), function(into)
			Kit.rock(into, "Rock", p, q[3], rng, STONE, STONE_LIGHT)
		end)
	end
	-- little flowers dotted along the walls
	local dots = Kit.rand(c, "flowers")
	for _, q in { { 0.22, 64 }, { 0.47, 66 }, { 0.66, 90 }, { 0.9, 62 }, { 0.12, 90 }, { 0.55, 62 }, { 0.02, -72 }, { 0.36, -64 } } do
		local p = Vector3.new(at(c, q[1]) + dots:NextNumber(-3, 3), GROUND, q[2] + dots:NextNumber(-2, 2))
		local color = BRIGHT[dots:NextInteger(1, #BRIGHT)]
		local h = dots:NextNumber(1.6, 2.6)
		local rng = Kit.rand(c, "flower" .. q[1])
		Assets.swap("Meadow_Flower", F, Assets.spin(p), function(into)
			flower(into, p, color, h, rng)
		end)
	end

	Kit.ambience(c, 200, 4, 6, { -- butterflies
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 140, 200)), ColorSequenceKeypoint.new(0.5, rgb(255, 230, 90)), ColorSequenceKeypoint.new(1, rgb(140, 200, 255)),
		}),
		rate = 5, lifetime = NumberRange.new(4, 6), speed = NumberRange.new(1, 2.5), size = NumberSequence.new(0.7),
		spread = Vector2.new(180, 180), rotSpeed = NumberRange.new(-120, 120), lightEmission = 0.3,
	})
	Kit.ambience(c, 200, 12, 10, { -- drifting pollen
		color = rgb(255, 245, 160), rate = 8, lifetime = NumberRange.new(5, 8), speed = NumberRange.new(0.3, 1),
		size = NumberSequence.new(0.25), spread = Vector2.new(180, 180), lightEmission = 1,
	})
end

return Meadow
