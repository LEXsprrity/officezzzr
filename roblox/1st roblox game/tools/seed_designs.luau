-- Our own seed designs (owner 2026-10-22: every seed rebranded by biome, ice seeds for the ice biome, sakura
-- seeds for the sakura biome; only the bought Sunpetal, Dawnfruit and Amberpine stay). Built from plain
-- Plastic parts in the same chunky style as those three: a seed with its zone's little sprout on top, about
-- 1.5 studs tall, front toward -Z, the ground at y 0. Never Neon (owner: no brightness around the seed).
-- tools/export_seeds.luau fits each into the pod / carried seed; tools/seed_sheet.luau renders them all.
local roblox = require("@lune/roblox")

local Instance, Vector3, CFrame, Color3 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3
local Enum = roblox.Enum
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi
local V = Vector3.new

local function rgb(r: number, g: number, b: number): any
	return Color3.fromRGB(r, g, b)
end

local function at(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): any
	return CFrame.new(x, y, z) * CFrame.fromEulerAnglesYXZ(rad(rx or 0), rad(ry or 0), rad(rz or 0))
end

local model: any

local function part(class: string, size: any, cf: any, color: any): any
	local p = Instance.new(class)
	p.Name = "Part"
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Plastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function block(size: any, cf: any, color: any): any
	return part("Part", size, cf, color)
end

local function wedge(size: any, cf: any, color: any): any -- (slope faces -Z and up; the high edge at +Z)
	return part("WedgePart", size, cf, color)
end

local function ball(d: number, pos: any, color: any): any
	local p = part("Part", V(d, d, d), CFrame.new(pos), color)
	p.Shape = Enum.PartType.Ball
	return p
end

-- An ellipsoid (a SpecialMesh sphere filling the part).
local function egg(size: any, cf: any, color: any): any
	local p = part("Part", size, cf, color)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- A cylinder `len` long, `d` across, its axis along the frame's Y.
local function cyl(len: number, d: number, cf: any, color: any): any
	local p = part("Part", V(len, d, d), cf * CFrame.Angles(0, 0, pi / 2), color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A frame at `pos` turned `yaw` degrees around Y and then tipped `tilt` degrees about X (positive lifts its -Z
-- end: a petal pushed out along -Z then points up and out).
local function around(pos: any, yaw: number, tilt: number): any
	return CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(0, rad(yaw), 0) * CFrame.Angles(rad(tilt), 0, 0)
end

-- A ring of `n` petals: ellipsoids `size` (long along Z) around `centre`, pushed `r` out and tipped `tilt`.
local function petals(n: number, centre: any, r: number, size: any, tilt: number, color: any, yaw0: number?)
	for i = 0, n - 1 do
		local yaw = (yaw0 or 0) + i * 360 / n
		local cf = around(centre, yaw, tilt) * CFrame.new(0, 0, -r)
		egg(size, cf, color)
	end
end

local designs = {}

----------------------------------------------------------------------------------------------------
-- 🌼 Meadow
----------------------------------------------------------------------------------------------------
-- A four-leaf clover on a brown seed, two little leaves at its foot.
function designs.Clover()
	local SEED, SEED_D = rgb(150, 98, 58), rgb(118, 74, 42)
	local LEAF, LEAF_D, LEAF_L = rgb(86, 186, 72), rgb(58, 146, 52), rgb(170, 230, 120)
	egg(V(0.9, 0.75, 0.9), at(0, 0.375, 0), SEED)
	block(V(0.5, 0.12, 0.5), at(0, 0.62, 0, 0, 45, 0), SEED_D)
	cyl(0.75, 0.13, at(0, 1.0, 0, 0, 0, 6), LEAF_D)
	local top = V(0.04, 1.4, 0)
	for i = 0, 3 do
		local yaw = 45 + i * 90
		for side = -1, 1, 2 do -- (two lobes make the heart)
			local cf = around(top, yaw, -14) * CFrame.new(side * 0.13, 0, -0.3)
			egg(V(0.36, 0.09, 0.42), cf * CFrame.fromEulerAnglesYXZ(0, rad(-side * 22), 0), LEAF)
		end
		egg(V(0.12, 0.1, 0.26), around(top + V(0, 0.03, 0), yaw, -14) * CFrame.new(0, 0, -0.2), LEAF_L)
	end
	ball(0.16, top + V(0, 0.03, 0), LEAF_D)
	for side = -1, 1, 2 do
		egg(V(0.42, 0.08, 0.2), at(side * 0.38, 0.72, 0.05, 0, 0, side * 25), LEAF)
		egg(V(0.2, 0.06, 0.06), at(side * 0.38, 0.75, 0.05, 0, 0, side * 25), LEAF_D) -- (its vein)
	end
	-- the seed's grooves and a shine
	for i = 0, 3 do
		local cf = around(V(0, 0.38, 0), i * 90 + 20, 0) * CFrame.new(0, 0, -0.44)
		block(V(0.05, 0.42, 0.04), cf, SEED_D)
	end
	egg(V(0.16, 0.12, 0.06), at(-0.2, 0.55, -0.36, -20, -25, 0), rgb(196, 140, 92))
	-- a ladybug on a leaf, dew drops, crumbs of soil
	local bug = (around(top, 225, -14) * CFrame.new(0, 0.07, -0.34)).Position
	ball(0.16, bug, rgb(230, 40, 40))
	ball(0.09, bug + V(0.06, 0.02, -0.06), rgb(25, 25, 25))
	block(V(0.015, 0.04, 0.15), CFrame.new(bug + V(0, 0.06, 0)) * CFrame.fromEulerAnglesYXZ(0, rad(45), 0), rgb(25, 25, 25))
	for _, d in { V(-0.05, 0.08, 0.04), V(0.04, 0.08, -0.03) } do
		ball(0.035, bug + d, rgb(25, 25, 25))
	end
	ball(0.07, (around(top, 135, -14) * CFrame.new(0.1, 0.06, -0.3)).Position, rgb(200, 240, 255))
	ball(0.05, (around(top, 315, -14) * CFrame.new(-0.1, 0.06, -0.36)).Position, rgb(200, 240, 255))
	for _, p in { V(0.4, 0.05, -0.3), V(-0.42, 0.04, -0.2), V(0.1, 0.04, -0.46) } do
		block(V(0.1, 0.08, 0.1), CFrame.new(p) * CFrame.fromEulerAnglesYXZ(0, rad(p.X * 90), 0), SEED_D)
	end
end

-- A daisy: white petals round a fat yellow middle, on a stem out of a seed in a tuft of grass.
function designs.Daisy()
	local SEED = rgb(168, 112, 66)
	local GRASS, GRASS_D = rgb(104, 200, 80), rgb(70, 160, 60)
	local WHITE, PINKTIP, YELLOW = rgb(255, 255, 250), rgb(255, 214, 230), rgb(255, 200, 40)
	egg(V(0.8, 0.7, 0.8), at(0, 0.35, 0), SEED)
	for i = 0, 6 do
		local yaw = i * 360 / 7
		local cf = around(V(0, 0.15, 0), yaw, -28) * CFrame.new(0, 0.28, -0.36)
		wedge(V(0.14, 0.42, 0.1), cf, if i % 2 == 0 then GRASS else GRASS_D)
	end
	cyl(0.85, 0.12, at(0, 1.05, 0.02, -8, 0, 0), GRASS_D)
	egg(V(0.36, 0.07, 0.2), at(0.22, 1.0, 0.02, 0, 0, 30), GRASS)
	egg(V(0.36, 0.07, 0.2), at(-0.22, 0.88, 0.04, 0, 0, -30), GRASS)
	local head = at(0, 1.55, -0.1, -40, 0, 0)
	for i = 0, 11 do
		local cf = head * CFrame.fromEulerAnglesYXZ(0, rad(i * 30), 0) * CFrame.Angles(rad(8), 0, 0) * CFrame.new(0, 0, -0.4)
		egg(V(0.2, 0.07, 0.56), cf, if i % 4 == 0 then PINKTIP else WHITE)
	end
	cyl(0.14, 0.44, head * CFrame.new(0, 0.04, 0), YELLOW)
	ball(0.3, (head * CFrame.new(0, 0.08, 0)).Position, rgb(255, 176, 30))
	for i = 0, 5 do -- (pollen dots on the middle)
		local a = i * pi / 3
		ball(0.06, (head * CFrame.new(cos(a) * 0.15, 0.13, sin(a) * 0.15)).Position, rgb(230, 140, 20))
	end
	-- a second, closed bud on its own stalk, and a bee
	cyl(0.5, 0.07, at(0.3, 0.95, 0.08, 0, 0, -18), GRASS_D)
	egg(V(0.16, 0.24, 0.16), at(0.39, 1.24, 0.08, 0, 0, -18), GRASS)
	egg(V(0.11, 0.14, 0.11), at(0.41, 1.36, 0.08, 0, 0, -18), WHITE)
	local bee = at(-0.46, 1.62, -0.16, 0, 30, 0)
	egg(V(0.14, 0.13, 0.2), bee, rgb(255, 205, 40))
	block(V(0.15, 0.135, 0.04), bee * CFrame.new(0, 0, 0.02), rgb(35, 30, 30))
	ball(0.1, (bee * CFrame.new(0, 0.01, -0.11)).Position, rgb(35, 30, 30))
	for side = -1, 1, 2 do
		egg(V(0.14, 0.03, 0.1), bee * CFrame.new(side * 0.09, 0.08, 0.02) * CFrame.Angles(0, 0, rad(side * 30)), rgb(225, 245, 255))
	end
	-- the seed's stripes
	for i = 0, 2 do
		local cf = around(V(0, 0.36, 0), i * 120 - 30, 0) * CFrame.new(0, 0, -0.39)
		block(V(0.05, 0.4, 0.04), cf, rgb(130, 82, 46))
	end
end

----------------------------------------------------------------------------------------------------
-- 🦂 Desert (and the bought Sunpetal)
----------------------------------------------------------------------------------------------------
-- A little cactus with two arms and a pink flower, out of a sandy seed.
function designs.Cactus()
	local SAND, SAND_D = rgb(232, 196, 130), rgb(196, 158, 96)
	local GREEN, GREEN_D, GREEN_L = rgb(70, 166, 84), rgb(46, 128, 62), rgb(120, 200, 110)
	local PINK, PINK_D, YELLOW = rgb(255, 110, 170), rgb(230, 70, 140), rgb(255, 220, 70)
	egg(V(1.0, 0.6, 1.0), at(0, 0.3, 0), SAND)
	block(V(0.18, 0.1, 0.18), at(0.3, 0.52, -0.18, 0, 30, 0), SAND_D)
	block(V(0.14, 0.08, 0.14), at(-0.32, 0.5, 0.2, 0, 10, 0), SAND_D)
	block(V(0.42, 1.0, 0.42), at(0, 0.98, 0), GREEN)
	ball(0.42, V(0, 1.48, 0), GREEN)
	for x = -1, 1, 2 do -- (ribs)
		block(V(0.05, 0.9, 0.44), at(x * 0.1, 0.98, 0), GREEN_D)
	end
	block(V(0.22, 0.18, 0.2), at(-0.3, 0.86, 0), GREEN)
	block(V(0.2, 0.42, 0.2), at(-0.42, 1.06, 0), GREEN)
	ball(0.2, V(-0.42, 1.27, 0), GREEN)
	block(V(0.22, 0.18, 0.2), at(0.3, 1.04, 0), GREEN)
	block(V(0.2, 0.3, 0.2), at(0.42, 1.18, 0), GREEN)
	ball(0.2, V(0.42, 1.33, 0), GREEN)
	for _, p in { V(0.12, 1.2, -0.22), V(-0.1, 0.8, -0.22), V(0.13, 0.68, -0.22), V(-0.12, 1.36, -0.2) } do
		block(V(0.04, 0.04, 0.08), CFrame.new(p), GREEN_L)
	end
	petals(5, V(0, 1.7, 0), 0.12, V(0.16, 0.08, 0.24), 30, PINK)
	petals(5, V(0, 1.74, 0), 0.07, V(0.11, 0.07, 0.16), 45, PINK_D, 36)
	ball(0.12, V(0, 1.76, 0), YELLOW)
	-- white spines all over the trunk and arms
	local SPINE = rgb(250, 248, 230)
	for i = 0, 11 do
		local yaw = i * 75
		local y = 0.6 + (i % 6) * 0.15
		local cf = around(V(0, y, 0), yaw, 0) * CFrame.new(0, 0, -0.24)
		block(V(0.025, 0.025, 0.1), cf, SPINE)
	end
	for _, p in { V(-0.42, 1.12, -0.11), V(-0.53, 1.0, 0), V(0.42, 1.24, -0.11), V(0.53, 1.14, 0), V(0, 1.6, -0.2) } do
		block(V(0.025, 0.025, 0.09), CFrame.lookAt(p, p * V(2, 1, 2) + V(0, 0, -0.1)), SPINE)
	end
	-- a baby cactus, pebbles and a bleached bone in the sand
	block(V(0.18, 0.26, 0.18), at(0.3, 0.62, 0.22), GREEN_D)
	ball(0.18, V(0.3, 0.75, 0.22), GREEN_D)
	ball(0.07, V(0.3, 0.86, 0.22), PINK)
	for _, p in { V(-0.36, 0.5, -0.24), V(0.42, 0.42, -0.1), V(-0.12, 0.5, -0.4) } do
		egg(V(0.12, 0.08, 0.1), CFrame.new(p), rgb(170, 140, 110))
	end
	block(V(0.3, 0.05, 0.05), at(-0.16, 0.6, 0.36, 0, 30, 0), rgb(245, 240, 225))
	for side = -1, 1, 2 do
		ball(0.08, (at(-0.16, 0.6, 0.36, 0, 30, 0) * CFrame.new(side * 0.15, 0, 0)).Position, rgb(245, 240, 225))
	end
end

----------------------------------------------------------------------------------------------------
-- 🦖 Jungle (and the bought Dawnfruit)
----------------------------------------------------------------------------------------------------
-- Two pitcher plants (lime cups with red rims and lids) and big leaves, out of a dark green seed.
function designs.Pitcher()
	local SEED = rgb(58, 104, 52)
	local CUP, CUP_D, RIM, SPOT = rgb(150, 210, 70), rgb(112, 176, 52), rgb(196, 40, 60), rgb(150, 30, 60)
	local LEAF, LEAF_D = rgb(52, 156, 72), rgb(36, 118, 56)
	egg(V(0.9, 0.62, 0.9), at(0, 0.31, 0), SEED)
	for i = 0, 3 do
		local cf = around(V(0, 0.45, 0), 45 + i * 90, -62) * CFrame.new(0, 0, -0.42)
		egg(V(0.34, 0.07, 0.62), cf, if i % 2 == 0 then LEAF else LEAF_D)
	end
	local function pitcher(x: number, z: number, h: number, lean: number)
		local base = at(x, 0.55, z, 0, 0, lean)
		cyl(h, 0.36, base * CFrame.new(0, h / 2, 0), CUP)
		egg(V(0.38, 0.3, 0.38), base * CFrame.new(0, 0.05, 0), CUP_D)
		cyl(0.08, 0.42, base * CFrame.new(0, h, 0), RIM)
		cyl(0.03, 0.3, base * CFrame.new(0, h + 0.03, 0), rgb(70, 20, 30))
		egg(V(0.34, 0.06, 0.3), base * CFrame.new(0, h + 0.2, 0.14) * CFrame.Angles(rad(-35), 0, 0), RIM)
		for i = 0, 5 do
			local a = i * 1.7
			block(V(0.07, 0.07, 0.03), base * CFrame.new(sin(a) * 0.18, 0.15 + i * h / 7, -cos(a) * 0.18) * CFrame.fromEulerAnglesYXZ(0, a, 0), SPOT)
		end
		cyl(h * 0.6, 0.04, base * CFrame.new(0, h * 0.45, -0.18), CUP_D) -- (its front wing)
		cyl(0.05, 0.38, base * CFrame.new(0, h * 0.82, 0), RIM) -- (a red band under the mouth)
	end
	pitcher(-0.17, 0.02, 0.85, 8)
	pitcher(0.22, -0.08, 0.55, -10)
	-- leaf midribs, a tendril with a baby pitcher, a fly on the big one's lid
	for i = 0, 3 do
		local cf = around(V(0, 0.46, 0), 45 + i * 90, -62) * CFrame.new(0, 0.03, -0.42)
		block(V(0.04, 0.03, 0.5), cf, rgb(120, 200, 110))
	end
	block(V(0.04, 0.3, 0.04), at(0.4, 0.62, 0.18, 0, 0, -40), LEAF_D)
	block(V(0.04, 0.2, 0.04), at(0.52, 0.8, 0.18, 0, 0, 10), LEAF_D)
	egg(V(0.14, 0.2, 0.14), at(0.52, 0.94, 0.18), CUP)
	cyl(0.03, 0.15, at(0.52, 1.04, 0.18), RIM)
	local fly = (at(-0.17, 0.55, 0.02, 0, 0, 8) * CFrame.new(0, 1.12, 0.1)).Position
	egg(V(0.12, 0.08, 0.16), CFrame.new(fly), rgb(30, 50, 40))
	for side = -1, 1, 2 do
		egg(V(0.12, 0.02, 0.07), CFrame.new(fly + V(side * 0.07, 0.04, 0.03)) * CFrame.Angles(0, 0, rad(side * 25)), rgb(220, 240, 250))
	end
	ball(0.05, fly + V(0.03, 0.02, -0.07), rgb(200, 30, 30))
end

----------------------------------------------------------------------------------------------------
-- 🌋 Lava Fields (and the bought Amberpine)
----------------------------------------------------------------------------------------------------
-- A cracked obsidian seed, lava in its cracks, a sprout of flame-shaped leaves.
function designs.Obsidian()
	local ROCK, ROCK_D = rgb(52, 40, 54), rgb(34, 26, 36)
	local LAVA, LAVA_L, FIRE_Y = rgb(255, 92, 16), rgb(255, 150, 30), rgb(255, 220, 70)
	local c = V(0, 0.46, 0)
	egg(V(1.0, 0.92, 1.0), CFrame.new(c), ROCK)
	egg(V(0.5, 0.4, 0.5), at(0.26, 0.62, 0.16, 0, 0, -30), ROCK_D) -- (lumps)
	egg(V(0.46, 0.36, 0.46), at(-0.3, 0.3, -0.1, 0, 0, 25), ROCK_D)
	-- glowing cracks running down the rock's front and sides
	for _, k in { { -10, 0.62, 0.34, 70 }, { 0, 0.4, 0.3, 100 }, { 50, 0.55, 0.26, 80 }, { -60, 0.36, 0.28, 110 }, { 110, 0.5, 0.24, 75 }, { -130, 0.5, 0.22, 95 } } do
		local yaw, y, len, roll = k[1], k[2], k[3], k[4]
		local dir = V(sin(rad(yaw)), 0, -cos(rad(yaw)))
		local onRock = c + dir * 0.49 + V(0, y - c.Y, 0) * 0.9 - dir * (y - c.Y) ^ 2 * 0.6
		block(V(0.07, len, 0.06), CFrame.lookAt(onRock, onRock + dir) * CFrame.Angles(0, 0, rad(roll - 90)), LAVA)
	end
	cyl(0.12, 0.5, at(0, 0.9, 0), LAVA) -- (the molten top)
	cyl(0.14, 0.34, at(0, 0.92, 0), LAVA_L)
	local function flame(yaw: number, tilt: number, h: number, w: number, color: any)
		local cf = around(V(0, 0.95, 0), yaw, -tilt) * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, pi / 2, 0)
		wedge(V(0.1, h, w / 2), cf * CFrame.new(0, 0, -w / 4), color)
		wedge(V(0.1, h, w / 2), cf * CFrame.new(0, 0, w / 4) * CFrame.Angles(0, pi, 0), color)
	end
	for i = 0, 4 do
		flame(i * 72, 30, 0.55, 0.26, LAVA)
	end
	for i = 0, 2 do
		flame(36 + i * 120, 16, 0.62, 0.22, LAVA_L)
	end
	flame(0, 0, 0.8, 0.26, FIRE_Y)
	flame(90, 0, 0.8, 0.26, FIRE_Y)
	-- branching cracks, embers flying up, little cooled rocks round the foot
	for _, k in { { 20, 0.3, 0.16, 40 }, { -35, 0.55, 0.14, 140 }, { 80, 0.3, 0.14, 60 }, { -95, 0.62, 0.16, 120 }, { 160, 0.4, 0.2, 90 } } do
		local yaw, y, len, roll = k[1], k[2], k[3], k[4]
		local dir = V(sin(rad(yaw)), 0, -cos(rad(yaw)))
		local onRock = c + dir * 0.5 + V(0, y - c.Y, 0) * 0.9 - dir * (y - c.Y) ^ 2 * 0.6
		block(V(0.05, len, 0.05), CFrame.lookAt(onRock, onRock + dir) * CFrame.Angles(0, 0, rad(roll - 90)), LAVA_L)
	end
	for _, e in { V(0.3, 1.5, -0.1), V(-0.26, 1.62, 0.08), V(0.12, 1.86, -0.04), V(-0.12, 1.38, -0.24), V(0.22, 1.28, 0.2) } do
		block(V(0.07, 0.07, 0.07), CFrame.new(e) * CFrame.fromEulerAnglesYXZ(rad(45), rad(45), 0), if e.Y > 1.6 then FIRE_Y else LAVA_L)
	end
	for _, p in { V(0.46, 0.08, -0.26), V(-0.48, 0.07, -0.18), V(0.1, 0.06, -0.52), V(-0.2, 0.07, 0.46) } do
		block(V(0.16, 0.12, 0.14), CFrame.new(p) * CFrame.fromEulerAnglesYXZ(rad(20), rad(p.X * 100), rad(15)), ROCK_D)
		block(V(0.06, 0.02, 0.06), CFrame.new(p + V(0, 0.065, 0)), LAVA)
	end
end

----------------------------------------------------------------------------------------------------
-- ❄️ Snow Peaks
----------------------------------------------------------------------------------------------------
-- A tiny snowy pine out of an icy blue seed with a snow cap.
function designs.FrostPine()
	local ICE, ICE_D, SNOW = rgb(170, 216, 245), rgb(120, 180, 225), rgb(250, 252, 255)
	local PINE, PINE_D, TRUNK = rgb(40, 120, 92), rgb(28, 92, 72), rgb(110, 76, 56)
	egg(V(0.86, 0.68, 0.86), at(0, 0.34, 0), ICE)
	egg(V(0.7, 0.2, 0.7), at(0, 0.62, 0), SNOW)
	for _, s in { { 0.32, 0.36, -0.2 }, { -0.36, 0.3, 0.1 } } do
		block(V(0.14, 0.14, 0.14), at(s[1], s[2], s[3], 30, 45, 0), ICE_D)
	end
	block(V(0.16, 0.3, 0.16), at(0, 0.78, 0), TRUNK)
	-- A skirt of 8 wedge branches sloping out and down from the trunk, `r` long and `h` tall, base at `y`.
	local function skirt(y: number, r: number, h: number, yaw: number, color: any)
		for k = 0, 7 do
			local cf = at(0, y + h / 2, 0, 0, yaw + k * 45, 0) * CFrame.new(0, 0, -r / 2)
			wedge(V(r * 0.62, h, r), cf, color)
		end
	end
	local tiers = { { 0.8, 0.5, 0.42 }, { 1.1, 0.4, 0.38 }, { 1.38, 0.3, 0.36 } }
	for i, t in tiers do
		local y, r, h = t[1], t[2], t[3]
		local yaw = if i % 2 == 0 then 22.5 else 0
		skirt(y, r, h, yaw, if i % 2 == 1 then PINE else PINE_D)
		skirt(y + h * 0.55, r * 0.5, h * 0.45, yaw, SNOW)
	end
	ball(0.16, V(0, 1.78, 0), SNOW)
	-- icicles hanging off the snow cap, frost on the seed, snowflakes in the air
	for i = 0, 7 do
		local cf = around(V(0, 0.6, 0), i * 45 + 10, 0) * CFrame.new(0, -0.06 - (i % 3) * 0.03, -0.35)
		wedge(V(0.06, 0.12 + (i % 3) * 0.05, 0.06), cf * CFrame.Angles(pi, 0, 0), rgb(220, 242, 255))
	end
	for i = 0, 4 do
		local cf = around(V(0, 0.28, 0), i * 72 + 36, 0) * CFrame.new(0, (i % 2) * 0.08, -0.43)
		block(V(0.1, 0.1, 0.03), cf * CFrame.Angles(0, 0, rad(45)), rgb(236, 248, 255))
	end
	for _, f in { V(0.44, 1.5, -0.2), V(-0.46, 1.24, -0.1), V(0.36, 0.98, 0.3), V(-0.3, 1.72, 0.1) } do
		local cf = CFrame.lookAt(f, f + V(0, 0, -1))
		for k = 0, 2 do
			block(V(0.02, 0.16, 0.02), cf * CFrame.Angles(0, 0, rad(k * 60)), SNOW)
		end
	end
	-- red berries peeking out of the branches
	for _, b in { V(0.22, 0.9, -0.3), V(-0.26, 1.18, -0.2), V(0.12, 1.42, -0.2) } do
		ball(0.08, b, rgb(220, 40, 50))
	end
end

-- A cluster of ice crystals out of a snow mound.
function designs.IceCrystal()
	local SNOW, SNOW_D = rgb(248, 251, 255), rgb(214, 228, 242)
	local C1, C2, C3 = rgb(140, 206, 255), rgb(96, 168, 240), rgb(206, 238, 255)
	egg(V(1.0, 0.5, 1.0), at(0, 0.25, 0), SNOW)
	egg(V(0.4, 0.2, 0.4), at(0.3, 0.42, 0.18), SNOW_D)
	local function shard(x: number, z: number, h: number, w: number, rx: number, rz: number, color: any)
		local base = at(x, 0.35, z, rx, 0, rz)
		local cf = base * CFrame.new(0, h / 2, 0) * CFrame.fromEulerAnglesYXZ(0, rad(45), 0)
		block(V(w, h, w), cf, color)
		local tip = base * CFrame.new(0, h, 0) * CFrame.fromEulerAnglesYXZ(0, rad(45), 0)
		wedge(V(w, w * 1.1, w / 2), tip * CFrame.new(0, w * 0.55, -w / 4), color)
		wedge(V(w, w * 1.1, w / 2), tip * CFrame.new(0, w * 0.55, w / 4) * CFrame.Angles(0, pi, 0), color)
		block(V(w * 0.25, h * 0.7, w * 1.02), cf * CFrame.new(-w * 0.2, 0, 0), C3) -- (a lighter facet)
	end
	shard(0, 0, 1.05, 0.34, 0, 0, C1)
	shard(-0.26, 0.06, 0.7, 0.26, 0, 26, C2)
	shard(0.26, -0.02, 0.6, 0.24, -8, -28, C1)
	shard(0.06, 0.26, 0.5, 0.22, 28, 6, C2)
	shard(-0.06, -0.26, 0.42, 0.2, -30, 0, C3)
	-- small shards poking out of the snow, snow lumps, sparkles
	shard(0.4, -0.22, 0.22, 0.12, -20, -40, C2)
	shard(-0.42, -0.16, 0.2, 0.11, -15, 40, C1)
	shard(-0.3, 0.34, 0.24, 0.12, 30, 20, C3)
	for _, p in { V(0.3, 0.36, -0.36), V(-0.18, 0.4, -0.42), V(0.46, 0.3, 0.2) } do
		egg(V(0.2, 0.12, 0.18), CFrame.new(p), SNOW_D)
	end
	for _, s in { V(0.24, 1.2, -0.2), V(-0.34, 0.98, -0.18), V(0.38, 0.7, -0.3) } do
		block(V(0.04, 0.16, 0.04), CFrame.new(s), rgb(255, 255, 255))
		block(V(0.16, 0.04, 0.04), CFrame.new(s), rgb(255, 255, 255))
	end
end

----------------------------------------------------------------------------------------------------
-- 👽 Deep Space
----------------------------------------------------------------------------------------------------
-- A ringed purple planet with a star sprouting from its top.
function designs.Planet()
	local PLANET, BAND_D = rgb(132, 78, 220), rgb(96, 52, 176)
	local RING, RING_D = rgb(255, 150, 230), rgb(200, 96, 190)
	local STEM, STAR = rgb(90, 200, 160), rgb(255, 222, 60)
	local c = V(0, 0.55, 0)
	ball(1.0, c, PLANET)
	egg(V(0.97, 0.16, 0.97), CFrame.new(c + V(0, -0.22, 0)), BAND_D)
	local tilt = CFrame.new(c) * CFrame.Angles(rad(-14), 0, rad(18))
	cyl(0.05, 1.75, tilt, RING_D)
	cyl(0.06, 1.5, tilt, RING)
	ball(0.16, (CFrame.new(c) * CFrame.new(-0.34, 0.06, -0.39)).Position, BAND_D) -- (a crater)
	cyl(0.4, 0.09, at(0.05, 1.18, 0, 0, 0, -8), STEM)
	egg(V(0.3, 0.06, 0.16), at(0.22, 1.12, 0, 0, 0, 30), STEM)
	local star = at(0.08, 1.48, -0.02, -10, 0, 0)
	for i = 0, 4 do
		local cf = star * CFrame.Angles(0, 0, rad(i * 72)) * CFrame.new(0, 0.12, 0)
		wedge(V(0.1, 0.24, 0.08), cf * CFrame.new(0.05, 0, 0) * CFrame.Angles(0, -pi / 2, 0), STAR)
		wedge(V(0.1, 0.24, 0.08), cf * CFrame.new(-0.05, 0, 0) * CFrame.Angles(0, pi / 2, 0), STAR)
	end
	cyl(0.1, 0.18, star * CFrame.Angles(pi / 2, 0, 0), STAR)
	-- more craters, a swirl band, a little moon, twinkles
	for _, k in { { 0.28, 0.2, -0.38, 0.12 }, { -0.1, -0.12, -0.48, 0.1 }, { 0.42, -0.1, -0.2, 0.09 } } do
		local p = c + V(k[1], k[2], k[3])
		egg(V(k[4], k[4], 0.04), CFrame.lookAt(p, c), BAND_D)
	end
	egg(V(0.99, 0.08, 0.99), CFrame.new(c + V(0, 0.16, 0)), rgb(176, 120, 250))
	ball(0.22, (tilt * CFrame.new(-0.86, 0.14, 0.2)).Position, rgb(220, 220, 235))
	ball(0.07, (tilt * CFrame.new(-0.82, 0.2, 0.12)).Position, rgb(170, 170, 190))
	for _, s in { V(0.6, 1.3, -0.1), V(-0.62, 1.08, 0.1), V(0.5, 0.2, -0.4) } do
		block(V(0.035, 0.14, 0.035), CFrame.new(s), STAR)
		block(V(0.14, 0.035, 0.035), CFrame.new(s), STAR)
	end
end

-- A green alien bulb with purple spots and two eyes on stalks.
function designs.Alien()
	local SKIN, SKIN_D, SPOT = rgb(110, 230, 140), rgb(70, 190, 110), rgb(160, 80, 230)
	local WHITE, PUPIL = rgb(255, 255, 255), rgb(30, 20, 50)
	egg(V(0.9, 1.0, 0.9), at(0, 0.5, 0), SKIN)
	egg(V(0.7, 0.2, 0.7), at(0, 0.08, 0), SKIN_D)
	for _, s in { { -0.28, 0.6, -0.3 }, { 0.3, 0.4, -0.3 }, { 0.38, 0.72, 0.1 }, { -0.4, 0.36, 0.08 }, { 0.05, 0.85, 0.32 } } do
		egg(V(0.16, 0.16, 0.06), CFrame.lookAt(V(s[1], s[2], s[3]), V(0, 0.5, 0)), SPOT)
	end
	egg(V(0.3, 0.07, 0.04), at(0, 0.42, -0.44, 0, 0, 0), PUPIL) -- (a smile)
	for side = -1, 1, 2 do
		local stalk = at(side * 0.16, 0.96, 0, 0, 0, -side * 22)
		cyl(0.5, 0.09, stalk * CFrame.new(0, 0.22, 0), SKIN_D)
		local eye = (stalk * CFrame.new(0, 0.5, 0)).Position
		ball(0.34, eye, WHITE)
		ball(0.16, eye + V(0, 0.01, -0.12), PUPIL)
	end
	for side = -1, 1, 2 do -- (stubby feet)
		egg(V(0.22, 0.12, 0.3), at(side * 0.24, 0.06, -0.24, 0, side * 15, 0), SKIN_D)
	end
	-- eye shines, blushing cheeks, little arms waving, a tooth, a glowing-green tummy patch
	for side = -1, 1, 2 do
		local stalk = at(side * 0.16, 0.96, 0, 0, 0, -side * 22)
		local eye = (stalk * CFrame.new(0, 0.5, 0)).Position
		ball(0.05, eye + V(0.03, 0.06, -0.17), WHITE)
		ball(0.05, (stalk * CFrame.new(0, 0.3, 0)).Position, SPOT) -- (a ring on the stalk)
		egg(V(0.12, 0.07, 0.03), CFrame.lookAt(V(side * 0.24, 0.5, -0.4), V(side * 0.24, 0.5, -1)), rgb(255, 140, 170))
		egg(V(0.12, 0.3, 0.12), at(side * 0.46, 0.5, -0.06, 0, 0, side * 50), SKIN)
		ball(0.11, V(side * 0.6, 0.62, -0.06), SKIN)
	end
	block(V(0.05, 0.05, 0.02), at(0.05, 0.4, -0.45), WHITE)
	egg(V(0.38, 0.4, 0.06), CFrame.lookAt(V(0, 0.26, -0.39), V(0, 0.4, -1)), rgb(170, 255, 190))
end

----------------------------------------------------------------------------------------------------
-- ⛩️ Spirit Garden
----------------------------------------------------------------------------------------------------
-- A crooked cherry branch with three pink blossoms, out of a red-brown seed.
function designs.Sakura()
	local SEED, BARK, BARK_D = rgb(150, 86, 76), rgb(96, 60, 54), rgb(70, 44, 42)
	local PINK, PINK_L, CORE = rgb(255, 160, 200), rgb(255, 210, 228), rgb(220, 70, 120)
	egg(V(0.8, 0.66, 0.8), at(0, 0.33, 0), SEED)
	block(V(0.16, 0.5, 0.16), at(0, 0.82, 0, 0, 0, 10), BARK)
	block(V(0.14, 0.42, 0.14), at(-0.1, 1.2, 0, 0, 0, 30), BARK)
	block(V(0.12, 0.38, 0.12), at(0.12, 1.12, 0.02, 0, 0, -48), BARK_D)
	block(V(0.1, 0.3, 0.1), at(-0.26, 1.48, 0, 0, 0, -10), BARK_D)
	local function blossom(pos: any, size: number, face: any)
		local cf = CFrame.lookAt(pos, pos + face) * CFrame.Angles(rad(-90), 0, 0)
		for i = 0, 4 do
			local p = cf * CFrame.fromEulerAnglesYXZ(0, rad(i * 72), 0) * CFrame.Angles(rad(12), 0, 0) * CFrame.new(0, 0, -0.14 * size)
			egg(V(0.22, 0.07, 0.26) * size, p, if i % 2 == 0 then PINK else PINK_L)
		end
		ball(0.11 * size, (cf * CFrame.new(0, 0.03, 0)).Position, CORE)
	end
	blossom(V(-0.28, 1.68, -0.04), 1.25, V(-0.3, 1, -0.6))
	blossom(V(0.3, 1.28, -0.04), 1.1, V(0.6, 0.6, -0.6))
	blossom(V(-0.26, 1.3, -0.12), 0.85, V(-0.7, 0.2, -0.8))
	ball(0.12, V(0.02, 1.42, -0.02), PINK_L) -- (a bud)
	egg(V(0.14, 0.05, 0.18), at(0.36, 0.82, -0.3, 20, 30, 10), PINK) -- (fallen petals)
	egg(V(0.14, 0.05, 0.18), at(-0.4, 0.68, -0.18, -15, 70, -20), PINK_L)
	-- two more blossoms, buds, young leaves, a tiny paper lantern hanging off a twig
	block(V(0.08, 0.3, 0.08), at(0.3, 1.46, 0.02, 0, 0, -20), BARK_D)
	blossom(V(0.36, 1.62, -0.02), 0.9, V(0.4, 1, -0.5))
	blossom(V(-0.02, 1.02, -0.16), 0.75, V(0, 0.2, -1))
	for _, b in { V(-0.36, 1.86, 0.02), V(0.48, 1.4, 0), V(-0.12, 1.66, 0.12) } do
		egg(V(0.09, 0.12, 0.09), CFrame.new(b), PINK)
	end
	for _, l in { { 0.2, 1.34, 0.12, 40 }, { -0.36, 1.5, 0.1, -50 } } do
		egg(V(0.16, 0.04, 0.09), at(l[1], l[2], l[3], 0, l[4], 20), rgb(130, 200, 110))
	end
	block(V(0.02, 0.16, 0.02), at(0.18, 1.06, -0.04), rgb(60, 40, 40))
	egg(V(0.16, 0.2, 0.16), at(0.18, 0.92, -0.04), rgb(240, 70, 70))
	cyl(0.03, 0.1, at(0.18, 1.02, -0.04), rgb(60, 40, 40))
	cyl(0.03, 0.1, at(0.18, 0.82, -0.04), rgb(60, 40, 40))
	-- the seed's pale stripes
	for i = 0, 2 do
		local cf = around(V(0, 0.34, 0), i * 120 - 20, 0) * CFrame.new(0, 0, -0.39)
		block(V(0.05, 0.38, 0.04), cf, rgb(176, 112, 100))
	end
end

-- A lotus on a lily pad: two rings of pink-white petals round a seed pod.
function designs.Lotus()
	local PAD, PAD_D = rgb(76, 170, 96), rgb(52, 132, 74)
	local PINK, PINK_L, WHITE = rgb(250, 120, 180), rgb(255, 176, 214), rgb(255, 236, 244)
	local POD, POD_D = rgb(214, 224, 90), rgb(168, 176, 56)
	cyl(0.12, 1.4, at(0, 0.06, 0), PAD)
	cyl(0.04, 1.2, at(0, 0.13, 0), PAD_D)
	wedge(V(0.3, 0.13, 0.5), at(0.42, 0.07, -0.42, 0, 45, 0), rgb(52, 120, 150)) -- (the pad's notch, water blue)
	egg(V(0.6, 0.3, 0.6), at(0, 0.24, 0), PINK)
	petals(8, V(0, 0.3, 0), 0.36, V(0.34, 0.12, 0.7), 30, PINK, 0)
	petals(8, V(0, 0.38, 0), 0.26, V(0.3, 0.11, 0.62), 55, PINK_L, 22.5)
	petals(6, V(0, 0.46, 0), 0.15, V(0.24, 0.1, 0.46), 72, WHITE, 10)
	cyl(0.2, 0.32, at(0, 0.56, 0), POD)
	for i = 0, 5 do
		local a = i * pi / 3
		cyl(0.03, 0.05, CFrame.new(cos(a) * 0.09, 0.66, sin(a) * 0.09), POD_D)
	end
	cyl(0.03, 0.05, CFrame.new(0, 0.66, 0), POD_D)
	-- pink tips on the outer petals, golden stamens, the pad's veins, dew, a baby pad and a dragonfly
	for i = 0, 7 do
		local cf = around(V(0, 0.3, 0), i * 45, 30) * CFrame.new(0, 0.02, -0.66)
		egg(V(0.14, 0.08, 0.14), cf, rgb(225, 70, 140))
	end
	for i = 0, 9 do
		local a = i * pi / 5
		cyl(0.12, 0.025, CFrame.new(cos(a) * 0.19, 0.6, sin(a) * 0.19) * CFrame.Angles(sin(a) * 0.4, 0, -cos(a) * 0.4), rgb(255, 210, 60))
	end
	for i = 0, 5 do
		local cf = at(0, 0.14, 0, 0, i * 60 + 15, 0) * CFrame.new(0, 0, -0.42)
		block(V(0.03, 0.02, 0.52), cf, rgb(108, 196, 120))
	end
	ball(0.07, V(-0.5, 0.17, -0.3), rgb(210, 240, 255))
	ball(0.05, V(0.46, 0.16, 0.34), rgb(210, 240, 255))
	cyl(0.06, 0.5, at(-0.6, 0.03, 0.42), PAD_D)
	local fly = at(0.5, 0.95, -0.2, 0, 35, -10)
	cyl(0.34, 0.05, fly * CFrame.Angles(pi / 2, 0, 0) * CFrame.new(0, 0.06, 0), rgb(60, 170, 220))
	ball(0.08, (fly * CFrame.new(0, 0, -0.12)).Position, rgb(40, 120, 190))
	for side = -1, 1, 2 do
		for k = 0, 1 do
			egg(V(0.24, 0.02, 0.07), fly * CFrame.new(side * 0.13, 0.03, -0.06 + k * 0.08) * CFrame.Angles(0, rad(side * (10 - k * 20)), 0), rgb(220, 245, 255))
		end
	end
end

local SeedDesigns = {}

-- The design called `name` as a fresh Model (parts in place, ground at y 0), or nil if there is none.
function SeedDesigns.build(name: string): any?
	local fn = designs[name]
	if not fn then
		return nil
	end
	model = Instance.new("Model")
	model.Name = name
	fn()
	local m = model
	model = nil
	return m
end

function SeedDesigns.names(): { string }
	local out = {}
	for name in designs do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

return SeedDesigns
