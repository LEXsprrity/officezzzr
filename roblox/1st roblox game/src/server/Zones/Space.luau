-- 6. Deep Space: a purple floor, deep purple walls under a bright lilac cap, the sky full of planets:
--   * a UFO hovering over the right side, beaming up a cow
--   * big glowing crystal formations on rocky bases
--   * glowing craters in the floor: a ring of moon rock round a pool of glowing goo
--   * a little rocket on its launch tower
--   * floating asteroids (some with crystals), blocky ringed planets in the sky
--   * alien plants with glowing bulbs, moon rocks, twinkling stars
-- Crystals, goo, bulbs and lights glow (Neon); rock, metal and the rest are studded plastic.
local Assets = require(script.Parent.Parent:WaitForChild("Assets"))
local Props = require(script.Parent.Parent:WaitForChild("Props"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local rgb, at, box = Kit.rgb, Kit.at, Kit.box
local block, glow = Props.block, Kit.glow
local GROUND = Kit.GROUND
local M = Enum.Material

local Space = {}
Space.floorLight = rgb(78, 60, 156)
Space.wallLight = rgb(52, 40, 112)
Space.cap = rgb(190, 140, 255)

local CYAN = rgb(70, 225, 255)
local PINK = rgb(255, 80, 220)
local GOO = rgb(120, 255, 150)
local MOON = { rgb(150, 140, 180), rgb(124, 114, 160), rgb(170, 162, 200) }
local METAL = rgb(206, 210, 224)
local METAL_DARK = rgb(150, 156, 176)

-- A UFO: a wide disc of two crossed blocks, a rim with lights, a cyan dome; a cow floating under it in a
-- beam of rising sparkles.
local function ufo(F: Instance, u: Vector3)
	local cf = CFrame.new(u)
	block(F, "UFO", Vector3.new(24, 2.2, 15), cf, METAL)
	block(F, "UFO", Vector3.new(15, 2.6, 24), cf * CFrame.new(0, 0.25, 0), METAL_DARK)
	block(F, "UFO", Vector3.new(19, 1.4, 19), cf * CFrame.new(0, -1.4, 0) * CFrame.Angles(0, math.rad(45), 0), METAL_DARK)
	block(F, "UFODome", Vector3.new(9, 3.4, 9), cf * CFrame.new(0, 2.8, 0), rgb(130, 230, 255))
	block(F, "UFODome", Vector3.new(5.6, 1.8, 5.6), cf * CFrame.new(0, 5.1, 0) * CFrame.Angles(0, math.rad(45), 0), rgb(180, 245, 255))
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		glow(F, "UFOLight", Vector3.new(1.4, 0.9, 1.4), cf * CFrame.new(math.cos(a) * 10.4, -0.9, math.sin(a) * 10.4), if i % 2 == 0 then rgb(255, 230, 90) else GOO)
	end
	local beam = Props.deco(F, "UFOBeam", Vector3.new(9, 30, 9), cf * CFrame.new(0, -17, 0), GOO)
	beam.Transparency = 1
	beam.CastShadow = false
	Props.emitOn(beam, {
		color = Kit.gradient(GOO, rgb(200, 255, 220)), rate = 14, lifetime = NumberRange.new(2.5, 3.5), speed = NumberRange.new(6, 9),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.2) }),
		spread = Vector2.new(5, 5), lightEmission = 1, lightInfluence = 0,
	})
	Props.light(beam, GOO, 24, 1.2)
	-- the cow, mid-air
	local cow = cf * CFrame.new(0.5, -15, 0) * CFrame.Angles(0.25, 0.6, 0.15)
	block(F, "Cow", Vector3.new(5, 3, 3), cow, rgb(250, 250, 250))
	block(F, "Cow", Vector3.new(2, 2, 2.2), cow * CFrame.new(3.2, 0.8, 0), rgb(250, 250, 250))
	block(F, "Cow", Vector3.new(1, 0.8, 1.4), cow * CFrame.new(4.4, 0.4, 0), rgb(255, 170, 190))
	block(F, "Cow", Vector3.new(1.6, 1.2, 0.3), cow * CFrame.new(-0.6, 0.3, 1.55), rgb(40, 40, 46))
	block(F, "Cow", Vector3.new(1.2, 1.4, 0.3), cow * CFrame.new(1.2, -0.2, -1.55), rgb(40, 40, 46))
	for _, q in { { -1.8, -1 }, { -1.8, 1 }, { 1.8, -1 }, { 1.8, 1 } } do
		block(F, "Cow", Vector3.new(0.7, 1.8, 0.7), cow * CFrame.new(q[1], -2.2, q[2]), rgb(250, 250, 250))
	end
end

-- A glowing crater: a ring of moon-rock blocks round a pool of glowing goo.
local function crater(F: Instance, p: Vector3, r: number, rng: Random, color: Color3)
	local n = 9
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local h = rng:NextNumber(1.2, 2.6)
		local len = 2 * math.pi * r / n * 1.15
		block(F, "CraterRim", Vector3.new(len, h, rng:NextNumber(2.6, 3.4)),
			CFrame.new(p + Vector3.new(math.cos(a) * r, h / 2 - 0.2, math.sin(a) * r)) * CFrame.Angles(0, -a + math.pi / 2, rng:NextNumber(-0.08, 0.08)),
			MOON[i % #MOON + 1])
	end
	local rows = Kit.pool(F, "CraterGoo", Vector3.new(math.round(p.X), GROUND, math.round(p.Z)), r * 1.7, r * 1.7, rng, color, M.Neon, 0.22)
	Kit.poolSpots(F, "GooHot", rows, rng, color:Lerp(Color3.new(1, 1, 1), 0.5), 0.34, 3)
	local light = Props.deco(F, "CraterGlow", Vector3.new(1, 1, 1), CFrame.new(p + Vector3.new(0, 3, 0)), color)
	light.Transparency = 1
	light.CastShadow = false
	Props.light(light, color, r * 2.5, 1.4)
end

-- A blocky planet `s` across: a core cube with a band through it along each axis (a chunky voxel ball, its
-- equator band lighter), and maybe a flat ring of eight blocks round it.
local function planet(F: Instance, p: Vector3, s: number, color: Color3, ring: boolean, tilt: number)
	local cf = CFrame.new(p) * CFrame.Angles(0, tilt * 2, tilt)
	local light, dark = color:Lerp(Color3.new(1, 1, 1), 0.3), color:Lerp(Color3.new(0, 0, 0), 0.1)
	block(F, "Planet", Vector3.new(0.84, 0.84, 0.84) * s, cf, color)
	block(F, "Planet", Vector3.new(1, 0.6, 0.64) * s, cf, light)
	block(F, "Planet", Vector3.new(0.56, 1, 0.6) * s, cf, dark)
	block(F, "Planet", Vector3.new(0.62, 0.58, 1) * s, cf, light)
	-- three slabs turned 45 degrees round each axis round off its outline from every side
	local r = math.rad(45)
	block(F, "Planet", Vector3.new(0.78, 0.66, 0.78) * s, cf * CFrame.Angles(0, r, 0), color)
	block(F, "Planet", Vector3.new(0.7, 0.8, 0.8) * s, cf * CFrame.Angles(r, 0, 0), dark)
	block(F, "Planet", Vector3.new(0.82, 0.82, 0.68) * s, cf * CFrame.Angles(0, 0, r), color)
	if ring then
		local r, t = s * 0.82, s * 0.13
		local len = 2 * r * math.tan(math.pi / 8) * 1.12
		for i = 0, 7 do -- (neighbours overlap at the corners, so every other one sits a little higher)
			local side = CFrame.Angles(0, i * math.pi / 4, 0) * CFrame.new(0, (i % 2) * t * 0.3, r)
			block(F, "PlanetRing", Vector3.new(len, t * 0.45, t), cf * side, color:Lerp(Color3.new(1, 1, 1), 0.55))
		end
	end
end

-- A floating asteroid: a few tipped blocks, sometimes with a crystal growing on it.
local function asteroid(F: Instance, p: Vector3, s: number, rng: Random)
	for i = 1, 3 do
		local size = s * (if i == 1 then 1 else rng:NextNumber(0.5, 0.7))
		local off = if i == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.5, 0.5)) * s
		block(F, "Asteroid", Vector3.new(size, size * 0.8, size * 0.9),
			CFrame.new(p + off) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), rng:NextNumber(0, 3)), MOON[i])
	end
	if rng:NextNumber() < 0.5 then
		glow(F, "AsteroidCrystal", Vector3.new(0.9, s * 0.8, 0.9) * Vector3.new(s / 4, 1, s / 4),
			CFrame.new(p + Vector3.new(0, s * 0.55, 0)) * CFrame.Angles(0.3, 0.7, 0.2), if rng:NextNumber() < 0.5 then CYAN else PINK)
	end
end

-- An alien plant: tall stalks topped with glowing bulbs, round a leafy base.
local function alienPlant(F: Instance, p: Vector3, rng: Random, bulb: Color3, lit: boolean)
	local stalk = rgb(90, 200, 170)
	block(F, "AlienPlant", Vector3.new(3, 1.4, 3), CFrame.new(p + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), rgb(70, 160, 150))
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local h = rng:NextNumber(4, 8)
		local lean = rng:NextNumber(0.1, 0.25)
		local base = CFrame.new(p + Vector3.new(math.cos(a), 0, math.sin(a)) * 0.6) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -lean)
		block(F, "AlienPlant", Vector3.new(0.5, h, 0.5), base * CFrame.new(0, h / 2, 0), stalk)
		local b = glow(F, "AlienBulb", Vector3.new(1.5, 1.7, 1.5), base * CFrame.new(0, h + 0.6, 0) * CFrame.Angles(0, math.rad(45), 0), bulb)
		if i == 1 and lit then
			Props.light(b, bulb, 12, 1)
		end
	end
end

-- A little rocket on a launch tower, in frame `f`.
local function rocket(F: Instance, f: Kit.Frame)
	local red, white = rgb(235, 60, 60), rgb(245, 246, 250)
	-- the pad and the tower
	box(F, "LaunchPad", f, -7, 7, 0, 1.2, 2, 16, METAL_DARK)
	box(F, "LaunchTower", f, -6.4, -4.4, 1, 26, 3, 5, rgb(255, 196, 60))
	for i = 1, 4 do
		box(F, "LaunchTower", f, -4.6, -1.6, 4 + i * 5, 4.8 + i * 5 + i * 0.01, 3.4, 4.6, rgb(255, 196, 60))
	end
	-- the rocket: body, stripes, window, nose in steps, fins and a flame
	box(F, "Rocket", f, -1.6, 2.6, 1.2, 19, 5.9, 10.1, white)
	box(F, "Rocket", f, -1.8, 2.8, 6, 7.4, 5.7, 10.3, red)
	box(F, "Rocket", f, -1.8, 2.8, 13.2, 14.6, 5.7, 10.3, red)
	box(F, "Rocket", f, -0.4, 1.4, 15.4, 17.2, 10.1, 10.4, CYAN)
	box(F, "Rocket", f, -1.1, 2.1, 19, 21.4, 6.4, 9.6, red)
	box(F, "Rocket", f, -0.4, 1.4, 21.4, 23.2, 7.1, 8.9, red)
	for _, q in { { -3.4, -1.6, 5.9, 10.1 }, { 2.6, 4.4, 5.9, 10.1 } } do
		box(F, "Rocket", f, q[1], q[2], 1.2, 6.2, q[3] + 1, q[4] - 1, red)
	end
	box(F, "Rocket", f, -1.0, 2.0, 1.2, 4.2, 4.4, 5.9, red)
	box(F, "Rocket", f, -1.0, 2.0, 1.2, 4.3, 10.1, 11.6, red)
end

function Space.build(c: Kit.Ctx)
	local F = c.folder
	Kit.floor(c, Space)
	Kit.walls(c, Space)

	-- stars dotted on the floor
	local dots = Kit.rand(c, "stars")
	for _ = 1, 24 do
		local size = dots:NextNumber(0.9, 1.7)
		local p = Vector3.new(at(c, dots:NextNumber(0.03, 0.97)), GROUND, dots:NextNumber(-88, 88))
		local star = Props.flat(F, "FloorStar", size, size, p, ({ rgb(255, 255, 255), CYAN, rgb(255, 150, 240), rgb(255, 240, 140) })[dots:NextInteger(1, 4)],
			M.SmoothPlastic, math.rad(45) + dots:NextNumber(-0.2, 0.2), 0.15 + dots:NextNumber(0, 0.1))
		star.CastShadow = false
	end

	-- the UFO over the right side, near the entrance
	local u = Vector3.new(at(c, 0.2), GROUND + 34, 58)
	Assets.swap("Space_UFO", F, Assets.facing(u - Vector3.new(0, 2, 0), -Vector3.xAxis), function(into)
		ufo(into, u)
	end, Vector3.new(1.2, 2, 1.2))

	-- glowing craters on both sides
	for i, q in { { 0.12, -60, 8, GOO }, { 0.46, 62, 9, CYAN }, { 0.66, -64, 7, PINK }, { 0.84, 58, 6, GOO } } do
		local rng = Kit.rand(c, "crater" .. i)
		local p = Vector3.new(at(c, q[1]), GROUND, q[2])
		Assets.swap("Space_Crater", F, Assets.spin(p), function(into)
			crater(into, p, q[3], rng, q[4])
		end)
	end

	-- crystal formations against the walls
	for i, q in { { 0.04, -1, 20, PINK }, { 0.33, -1, 24, CYAN }, { 0.56, 1, 21, PINK }, { 0.8, 1, 18, CYAN }, { 0.5, -1, 16, rgb(190, 120, 255) } } do
		local rng = Kit.rand(c, "crystal" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-3, 3), GROUND, q[2] * rng:NextNumber(80, 86))
		Assets.swap("Space_Crystal", F, Assets.spin(p), function(into)
			Kit.crystals(into, "Crystal", p, rng, q[4], MOON[2], 6, q[3], 2)
		end)
	end

	-- the rocket on the right, near the end
	local rocketFrame = Kit.wallFrame(at(c, 0.92), 1, 1.5)
	Assets.swap("Space_Rocket", F, Kit.facing(rocketFrame), function(into)
		rocket(into, rocketFrame)
	end)

	-- planets over the corridor (a drop-in planet's pivot is the bottom of the sphere)
	for i, q in { { 0.1, 92, -40, 30, rgb(255, 150, 60), true }, { 0.38, 118, 50, 40, rgb(80, 220, 200), false },
		{ 0.62, 100, -70, 24, rgb(255, 110, 180), true }, { 0.86, 126, 30, 34, rgb(150, 110, 255), true } } do
		local p = Vector3.new(at(c, q[1]), GROUND + q[2], q[3])
		Assets.swap("Space_Planet", F, Assets.spin(p - Vector3.new(0, q[4] / 2, 0)), function(into)
			planet(into, p, q[4], q[5], q[6], i * 0.3)
		end, Vector3.new(1, 1, 1))
	end
	-- asteroids floating along the walls
	for i, q in { { 0.08, 1, 30 }, { 0.27, -1, 40 }, { 0.42, 1, 24 }, { 0.58, -1, 34 }, { 0.72, 1, 44 }, { 0.82, 1, 36 } } do
		local rng = Kit.rand(c, "asteroid" .. i)
		local s = rng:NextNumber(5, 9)
		local pos = Vector3.new(at(c, q[1]), GROUND + q[3], q[2] * rng:NextNumber(64, 82))
		Assets.swap("Space_Asteroid", F, Assets.spin(pos - Vector3.new(0, s * 0.45, 0)), function(into)
			asteroid(into, pos, s, rng)
		end, Vector3.new(1.2, 1.2, 1.2))
	end
	-- alien plants and moon rocks
	for i, q in { { 0.16, 1, GOO }, { 0.3, 1, PINK }, { 0.42, -1, CYAN }, { 0.62, 1, rgb(255, 230, 90) }, { 0.74, -1, GOO }, { 0.97, -1, PINK } } do
		local rng = Kit.rand(c, "plant" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-4, 4), GROUND, q[2] * rng:NextNumber(66, 76))
		Assets.swap("Space_Mushroom", F, Assets.spin(p), function(into)
			alienPlant(into, p, rng, q[3], i % 2 == 1)
		end)
	end
	for i, q in { { 0.24, -1 }, { 0.53, 1 }, { 0.7, 1 }, { 0.86, -1 }, { 0.36, 1 } } do
		local rng = Kit.rand(c, "rock" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-5, 5), GROUND, q[2] * rng:NextNumber(58, 70))
		local size = rng:NextNumber(4, 8)
		Assets.swap("Space_Rock", F, Assets.spin(p), function(into)
			Kit.rock(into, "MoonRock", p, size, rng, MOON[1], MOON[3])
		end)
	end

	Kit.ambience(c, 200, 22, 30, { -- twinkles
		color = Kit.gradient(rgb(255, 255, 255), CYAN), rate = 5, lifetime = NumberRange.new(2, 4),
		speed = NumberRange.new(0, 0.4), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		spread = Vector2.new(180, 180), lightEmission = 1, lightInfluence = 0,
	})
end

return Space
