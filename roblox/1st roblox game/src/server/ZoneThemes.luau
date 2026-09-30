-- Per-zone art for the corridor: themed floor and walls, props and particle ambience. WorldBuilder
-- calls ZoneThemes.build for each zone and uses ZoneThemes.theme for the arch and nest colours.
--
-- Layout rules that keep the corridor playable:
--   * only the floor and the two walls collide; every prop is a non-colliding "ghost" (see Props)
--   * tall props stand along the walls (|z| >= ~18); the middle only gets flat floor overlays,
--     so the run and the guards' chase line stay visually clear
--   * part counts are budgeted (tests/world.spec.luau keeps the whole corridor under 6k parts)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Props = require(script.Parent:WaitForChild("Props"))

local ZoneThemes = {}

local GROUND = Config.GROUND_Y
local HALF_W = Config.CORRIDOR_WIDTH / 2
local H = Config.WALL_HEIGHT
local M = Enum.Material

local box, deco, ball, cylinder, rod, blob, flat, disc = Props.box, Props.deco, Props.ball, Props.cylinder, Props.rod, Props.blob, Props.flat, Props.disc

type Ctx = {
	folder: Folder,
	k: number,
	x0: number,
	x1: number,
	len: number,
	nestX: number,
	rng: Random,
	helpers: { [string]: any },
}

export type Theme = {
	arch: Color3,
	archMaterial: Enum.Material,
	accent: Color3,
	sign: Color3,
	signText: Color3,
	mound: Color3,
	nestStone: Color3,
	nestStoneMaterial: Enum.Material,
	leaf: Color3,
	build: (ctx: Ctx) -> (),
	ornament: (folder: Instance, x: number) -> (),
}

----------------------------------------------------------------------------------------------------
-- Shared building blocks
----------------------------------------------------------------------------------------------------
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function side(rng: Random): number
	return if rng:NextNumber() < 0.5 then -1 else 1
end

-- Random x inside the zone, away from its ends (the arch) by `margin`.
local function randX(c: Ctx, margin: number?): number
	local m = margin or 20
	return c.x0 + c.rng:NextNumber(m, c.len - m)
end

-- Evenly spaced x positions with jitter.
local function every(c: Ctx, spacing: number, jitter: number, fn: (x: number, i: number) -> ())
	local n = math.floor((c.len - 40) / spacing)
	for i = 0, n do
		local x = c.x0 + 20 + i * spacing + c.rng:NextNumber(-jitter, jitter)
		if x > c.x0 + 12 and x < c.x1 - 12 then
			fn(x, i)
		end
	end
end

local function floor(c: Ctx)
	local zone = Config.ZONES[c.k]
	box(c.folder, "Floor", Vector3.new(c.len, 4, Config.CORRIDOR_WIDTH), CFrame.new(c.x0 + c.len / 2, GROUND - 2, 0), zone.floor, (M :: any)[zone.material])
end

-- Both side walls (Config zone colour): a solid body plus an optional non-colliding cap.
local function walls(c: Ctx, material: Enum.Material, cap: Color3?, capMaterial: Enum.Material?, capSize: Vector2?)
	local mid = c.x0 + c.len / 2
	for _, s in { -1, 1 } do
		box(c.folder, "Wall", Vector3.new(c.len, H, 4), CFrame.new(mid, GROUND + H / 2, s * (HALF_W + 2)), Config.ZONES[c.k].wall, material)
		if cap then
			local size = capSize or Vector2.new(6, 2)
			deco(c.folder, "WallCap", Vector3.new(c.len, size.Y, size.X), CFrame.new(mid, GROUND + H + size.Y / 2, s * (HALF_W + 2)), cap, capMaterial or material)
		end
	end
end

-- A horizontal band on the inner face of both walls.
local function band(c: Ctx, y: number, height: number, color: Color3, material: Enum.Material?)
	for _, s in { -1, 1 } do
		local p = deco(c.folder, "WallBand", Vector3.new(c.len, height, 0.5), CFrame.new(c.x0 + c.len / 2, GROUND + y, s * (HALF_W - 0.2)), color, material)
		p.CastShadow = false
	end
end

-- Invisible slabs over the corridor that emit particles, one per `spacing` studs.
local function ambience(c: Ctx, spacing: number, y: number, height: number, spec: Props.EmitterSpec)
	local n = math.max(1, math.floor(c.len / spacing))
	local w = c.len / n
	for i = 0, n - 1 do
		Props.emitter(c.folder, "Ambience", Vector3.new(w, height, Config.CORRIDOR_WIDTH - 8), Vector3.new(c.x0 + (i + 0.5) * w, GROUND + y, 0), spec)
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

local function sparkleGradient(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) })
end

local BRIGHT = {
	rgb(255, 90, 120), rgb(255, 215, 60), rgb(170, 110, 255), rgb(255, 150, 60), rgb(90, 190, 255), rgb(255, 255, 255), rgb(255, 120, 210),
}

----------------------------------------------------------------------------------------------------
-- 1. Meadow: bright lawn, a pebble path, hedges, flowers, trees, mushrooms, butterflies
----------------------------------------------------------------------------------------------------
local function buildMeadow(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	for x = c.x0 + 20, c.x1 - 20, 40 do
		flat(F, "LawnStripe", 20, Config.CORRIDOR_WIDTH, Vector3.new(x, GROUND, 0), rgb(132, 230, 92), M.Grass, nil, 0.06)
	end
	flat(F, "Path", c.len - 8, 12, Vector3.new(c.x0 + c.len / 2, GROUND, 0), rgb(240, 222, 170), M.Pebble, nil, 0.15)

	-- Hedge walls with bumpy tops
	walls(c, M.LeafyGrass)
	for x = c.x0 + 8, c.x1 - 8, 15 do
		for _, s in { -1, 1 } do
			blob(F, "HedgeTop", Vector3.new(16, 8, 7), CFrame.new(x + rng:NextNumber(-2, 2), GROUND + H, s * (HALF_W + 2)), rgb(76, 176, 70), M.LeafyGrass)
		end
	end

	for _ = 1, 70 do
		local x = randX(c)
		local z = side(rng) * rng:NextNumber(12, 30)
		Props.flower(F, Vector3.new(x, GROUND, z), BRIGHT[rng:NextInteger(1, #BRIGHT)], rng:NextNumber(1.2, 2.4))
	end
	for _ = 1, 14 do
		Props.bush(F, Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(26, 30)), rng:NextNumber(4, 7), rgb(70, 180, 60))
	end
	every(c, 75, 10, function(x, i)
		local s = if i % 2 == 0 then 1 else -1
		Props.roundTree(F, Vector3.new(x, GROUND, s * rng:NextNumber(26, 28)), rng, Color3.fromHSV(rng:NextNumber(0.25, 0.33), 0.75, 0.82), rng:NextNumber(10, 16))
	end)
	for _ = 1, 10 do -- toadstools
		local p = Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(18, 28))
		local h = rng:NextNumber(1.5, 3)
		cylinder(F, "MushroomStem", h, 0.9, p + Vector3.new(0, h / 2, 0), rgb(250, 240, 220))
		blob(F, "MushroomCap", Vector3.new(3, 1.6, 3), CFrame.new(p + Vector3.new(0, h, 0)), rgb(235, 60, 60))
	end
	for _ = 1, 6 do
		Props.rock(F, Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(20, 29)), Vector3.new(rng:NextNumber(3, 6), rng:NextNumber(2, 4), rng:NextNumber(3, 5)), rgb(160, 160, 170), M.Slate, rng:NextNumber(0, 6))
	end

	-- Butterflies near the flowers, and slow drifting pollen
	ambience(c, 150, 4, 6, {
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 140, 200)), ColorSequenceKeypoint.new(0.5, rgb(255, 230, 90)), ColorSequenceKeypoint.new(1, rgb(140, 200, 255)),
		}),
		rate = 4, lifetime = NumberRange.new(4, 6), speed = NumberRange.new(1, 2.5), size = NumberSequence.new(0.7),
		spread = Vector2.new(180, 180), rotSpeed = NumberRange.new(-120, 120), lightEmission = 0.3,
	})
	ambience(c, 300, 12, 10, {
		color = rgb(255, 245, 160), rate = 8, lifetime = NumberRange.new(5, 8), speed = NumberRange.new(0.3, 1),
		size = NumberSequence.new(0.25), spread = Vector2.new(180, 180), lightEmission = 1,
	})
end

local function meadowOrnament(folder: Instance, x: number)
	for i = -3, 3 do
		blob(folder, "Garland", Vector3.new(2.6, 2.6, 2.6), CFrame.new(x - 4, GROUND + H + 5, i * 9), BRIGHT[(i + 4) % #BRIGHT + 1])
	end
end

----------------------------------------------------------------------------------------------------
-- 2. Desert: sand, ripples, dunes, saguaros, skeletons, mesas, drifting dust
----------------------------------------------------------------------------------------------------
local function saguaro(F: Instance, p: Vector3, rng: Random)
	local green = rgb(70, 172, 82)
	local h = rng:NextNumber(7, 13)
	cylinder(F, "Cactus", h, 2.6, p + Vector3.new(0, h / 2, 0), green, M.Grass)
	ball(F, "CactusTop", 2.6, p + Vector3.new(0, h, 0), green, M.Grass)
	for _, dir in { -1, 1 } do
		if dir == 1 or rng:NextNumber() < 0.6 then
			local y = h * rng:NextNumber(0.4, 0.65)
			local elbow = p + Vector3.new(dir * 2.6, y, 0)
			rod(F, "CactusArm", p + Vector3.new(0, y, 0), elbow, 1.6, green, M.Grass)
			local up = rng:NextNumber(2.5, 4.5)
			cylinder(F, "CactusArm", up, 1.6, elbow + Vector3.new(0, up / 2, 0), green, M.Grass)
			ball(F, "CactusTop", 1.6, elbow + Vector3.new(0, up, 0), green, M.Grass)
		end
	end
	if rng:NextNumber() < 0.5 then
		ball(F, "CactusFlower", 1.4, p + Vector3.new(0, h + 1.2, 0), rgb(255, 110, 170))
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
	for i = 1, 5 do
		local x = a.X + len * (0.25 + i * 0.1)
		for _, dz in { -1, 1 } do
			local base = Vector3.new(x, a.Y, p.Z)
			rod(F, "Rib", base, base + Vector3.new(0, 5, dz * 4), 0.7, BONE)
		end
	end
end

local function buildDesert(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	for _ = 1, 24 do
		flat(F, "Ripple", rng:NextNumber(18, 40), 1.2, Vector3.new(randX(c), GROUND, rng:NextNumber(-24, 24)), rgb(222, 180, 102), M.Sand, rng:NextNumber(-0.25, 0.25), 0.08)
	end

	walls(c, M.Sandstone, rgb(246, 206, 140), M.Sandstone, Vector2.new(6, 3))
	band(c, 6, 5, rgb(204, 128, 74), M.Sandstone)
	band(c, 16, 3, rgb(246, 200, 132), M.Sandstone)
	band(c, 30, 6, rgb(190, 112, 64), M.Sandstone)

	every(c, 70, 12, function(x)
		local s = side(rng)
		blob(F, "Dune", Vector3.new(rng:NextNumber(40, 70), rng:NextNumber(8, 14), rng:NextNumber(18, 26)),
			CFrame.new(x, GROUND - 1, s * rng:NextNumber(27, 30)), rgb(244, 212, 138), M.Sand)
	end)
	for _ = 1, 16 do
		saguaro(F, Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(19, 27)), rng)
	end
	for i = 1, 3 do
		skeleton(F, Vector3.new(c.x0 + c.len * (i / 4) + rng:NextNumber(-40, 40), GROUND, (if i % 2 == 0 then 1 else -1) * 22), rng)
	end
	for _ = 1, 10 do -- loose bones
		local p = Vector3.new(randX(c), GROUND + 0.4, side(rng) * rng:NextNumber(6, 26))
		local d = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * 1.6
		rod(F, "Bone", p - d, p + d, 0.5, BONE)
		ball(F, "BoneEnd", 0.9, p - d, BONE)
		ball(F, "BoneEnd", 0.9, p + d, BONE)
	end
	for _ = 1, 8 do -- mesas
		local p = Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(26, 29))
		local w = rng:NextNumber(10, 16)
		local y = 0
		for j = 1, 3 do
			local h = rng:NextNumber(3, 6)
			deco(F, "Mesa", Vector3.new(w, h, w * 0.6), CFrame.new(p + Vector3.new(0, y + h / 2, 0)) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
				if j % 2 == 0 then rgb(214, 128, 76) else rgb(196, 106, 62), M.Sandstone)
			y += h
			w *= 0.72
		end
	end

	ambience(c, 200, 3, 4, {
		texture = Props.TEX.smoke, color = rgb(232, 204, 150), rate = 3, lifetime = NumberRange.new(5, 8),
		speed = NumberRange.new(1, 3), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) }),
		transparency = fade(0.75, 0.85), spread = Vector2.new(180, 30), acceleration = Vector3.new(5, 0, 0),
	})
end

local function desertOrnament(folder: Instance, x: number)
	local p = Vector3.new(x - 4.5, GROUND + H + 6, 0)
	blob(folder, "Skull", Vector3.new(3, 5, 6), CFrame.new(p), BONE)
	for _, z in { -1, 1 } do
		ball(folder, "EyeSocket", 1.4, p + Vector3.new(-1.3, 0.8, z * 1.3), rgb(40, 30, 30))
		rod(folder, "Horn", p + Vector3.new(0, 1.5, z * 2.5), p + Vector3.new(-1, 4.5, z * 6), 1, BONE)
	end
end

----------------------------------------------------------------------------------------------------
-- 3. Jungle: dense trees with canopies over the path, vines, ferns, a dirt trail, fireflies
----------------------------------------------------------------------------------------------------
local function buildJungle(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	local i = 0
	for x = c.x0 + 24, c.x1 - 24, 40 do
		i += 1
		flat(F, "Trail", 46, 12, Vector3.new(x, GROUND, math.sin(i * 0.7) * 7), rgb(136, 96, 58), M.Ground, math.cos(i * 0.7) * 0.15, 0.12)
	end

	walls(c, M.Cobblestone, rgb(60, 146, 56), M.LeafyGrass, Vector2.new(7, 3))
	every(c, 24, 6, function(x)
		for _, s in { -1, 1 } do
			if rng:NextNumber() < 0.65 then
				local top = Vector3.new(x + rng:NextNumber(-4, 4), GROUND + H, s * (HALF_W - 0.4))
				local tip = top - Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(10, 30), 0)
				rod(F, "Vine", top, tip, 0.5, rgb(52, 136, 52), M.Grass)
				blob(F, "VineLeaf", Vector3.new(2.4, 1.6, 0.5), CFrame.new(tip), rgb(70, 180, 70), M.Grass)
			end
		end
	end)

	-- Dense trees along both walls; their canopies reach over the path
	every(c, 40, 8, function(x)
		for _, s in { -1, 1 } do
			local base = Vector3.new(x + rng:NextNumber(-6, 6), GROUND, s * rng:NextNumber(26, 29))
			local h = rng:NextNumber(22, 34)
			cylinder(F, "Trunk", h, 3.4, base + Vector3.new(0, h / 2, 0), rgb(104, 72, 46), M.Wood)
			local top = base + Vector3.new(0, h, 0)
			blob(F, "Canopy", Vector3.new(24, 8, 22), CFrame.new(top + Vector3.new(0, 1, -s * 6)), rgb(40, 150, 55), M.LeafyGrass)
			blob(F, "Canopy", Vector3.new(16, 7, 14), CFrame.new(top + Vector3.new(rng:NextNumber(-5, 5), 5, -s * 2)), rgb(62, 176, 60), M.LeafyGrass)
			rod(F, "Vine", top + Vector3.new(2, 0, -s * 10), top + Vector3.new(2, -rng:NextNumber(8, 16), -s * 11), 0.4, rgb(52, 136, 52), M.Grass)
		end
	end)

	for _ = 1, 28 do -- ferns: big leaves fanned out
		local p = Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(18, 25))
		local green = Color3.fromHSV(rng:NextNumber(0.27, 0.36), 0.75, rng:NextNumber(0.55, 0.75))
		for j = 1, 4 do
			local a = j / 4 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			blob(F, "Fern", Vector3.new(7, 0.5, 2.6),
				CFrame.new(p + Vector3.new(math.cos(a) * 3, 1.6, math.sin(a) * 3)) * CFrame.Angles(0, -a, math.rad(25)), green, M.Grass)
		end
	end
	for _ = 1, 12 do
		Props.flower(F, Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(16, 24)), ({ rgb(255, 70, 70), rgb(255, 150, 40), rgb(255, 90, 200) })[rng:NextInteger(1, 3)], rng:NextNumber(2, 3.5))
	end
	for _ = 1, 5 do
		local p = Vector3.new(randX(c), GROUND + 1.4, side(rng) * rng:NextNumber(22, 26))
		rod(F, "Log", p - Vector3.new(6, 0, 1), p + Vector3.new(6, 0, 1), 2.8, rgb(110, 76, 48), M.Wood)
	end

	ambience(c, 230, 7, 10, { -- fireflies
		color = rgb(210, 255, 120), rate = 6, lifetime = NumberRange.new(3, 5), speed = NumberRange.new(0.3, 1.2),
		size = NumberSequence.new(0.35), spread = Vector2.new(180, 180), lightEmission = 1,
	})
	ambience(c, 280, 36, 2, { -- falling leaves
		color = sparkleGradient(rgb(90, 200, 70), rgb(160, 220, 60)), rate = 3, lifetime = NumberRange.new(6, 9),
		speed = NumberRange.new(2, 4), size = NumberSequence.new(0.6), direction = Enum.NormalId.Bottom,
		acceleration = Vector3.new(0.8, -0.5, 0), rotSpeed = NumberRange.new(-90, 90),
	})
end

local function jungleOrnament(folder: Instance, x: number)
	for _, z in { -30, -27.5, 27.5, 30 } do -- beside the sign, not over it
		local top = Vector3.new(x - 4, GROUND + H + 3.5, z)
		rod(folder, "Vine", top, top - Vector3.new(0, 9, 0), 0.5, rgb(52, 136, 52), M.Grass)
		blob(folder, "VineLeaf", Vector3.new(0.5, 2, 3), CFrame.new(top - Vector3.new(0, 9, 0)), rgb(70, 180, 70), M.Grass)
	end
end

----------------------------------------------------------------------------------------------------
-- 4. Lava Fields: basalt, lava rivers along the walls, glowing cracks, volcanoes, embers + smoke
----------------------------------------------------------------------------------------------------
local LAVA = rgb(255, 112, 24)
local LAVA_HOT = rgb(255, 200, 60)

local function embers(host: BasePart)
	Props.emitOn(host, {
		texture = Props.TEX.spark, color = sparkleGradient(LAVA_HOT, rgb(255, 60, 20)), rate = 4,
		lifetime = NumberRange.new(1.5, 3), speed = NumberRange.new(3, 6), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		acceleration = Vector3.new(0, 2, 0), spread = Vector2.new(25, 25), lightEmission = 1,
	})
end

local function smoke(host: BasePart, rate: number)
	Props.emitOn(host, {
		texture = Props.TEX.smoke, color = sparkleGradient(rgb(90, 80, 80), rgb(40, 36, 40)), rate = rate,
		lifetime = NumberRange.new(4, 7), speed = NumberRange.new(3, 6), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12) }),
		transparency = fade(0.5, 0.8), spread = Vector2.new(15, 15), rotSpeed = NumberRange.new(-30, 30),
	})
end

local function buildLava(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)

	-- Lava rivers along both walls (walkable: they're flat overlays)
	local seg = 80
	local n = math.floor(c.len / seg)
	for _, s in { -1, 1 } do
		for i = 0, n - 1 do
			local x = c.x0 + (i + 0.5) * seg
			local z = s * (23 + math.sin(i * 1.3 + s) * 2.5)
			local yaw = math.cos(i * 1.3 + s) * 0.06
			flat(F, "RiverCrust", seg + 4, 10, Vector3.new(x, GROUND, z), rgb(110, 40, 22), M.Slate, yaw, 0.1)
			local river = flat(F, "LavaRiver", seg + 2, 7, Vector3.new(x, GROUND, z), LAVA, M.Neon, yaw, 0.18)
			if i % 2 == 0 then
				Props.light(river, LAVA, 18, 1.6)
			end
			if i % 3 == 0 then
				embers(river)
			end
		end
	end
	for _ = 1, 6 do -- streams crossing the floor
		flat(F, "LavaStream", 64, 3, Vector3.new(randX(c, 120), GROUND, 0), LAVA, M.Neon, rng:NextNumber(0.35, 0.8) * side(rng), 0.14)
	end
	for _ = 1, 50 do -- glowing cracks
		flat(F, "Crack", rng:NextNumber(6, 16), 0.35, Vector3.new(randX(c), GROUND, rng:NextNumber(-17, 17)),
			if rng:NextNumber() < 0.3 then LAVA_HOT else LAVA, M.Neon, rng:NextNumber(0, math.pi), 0.1)
	end

	walls(c, M.Basalt, rgb(40, 30, 32), M.Basalt, Vector2.new(6, 2))
	every(c, 45, 8, function(x) -- glowing veins in the walls
		for _, s in { -1, 1 } do
			local z = s * (HALF_W - 0.2)
			local a = Vector3.new(x, GROUND + rng:NextNumber(2, 8), z)
			local b = a + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(10, 18), 0)
			local d = b + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(8, 14), 0)
			rod(F, "Vein", a, b, 0.7, LAVA, M.Neon)
			rod(F, "Vein", b, d, 0.5, LAVA, M.Neon)
		end
	end)

	for i = 1, 6 do -- volcanoes against the walls
		local p = Vector3.new(c.x0 + c.len * (i - 0.5) / 6 + rng:NextNumber(-40, 40), GROUND, (if i % 2 == 0 then 1 else -1) * 27)
		cylinder(F, "Volcano", 5, 20, p + Vector3.new(0, 2.5, 0), rgb(70, 46, 44), M.Basalt)
		cylinder(F, "Volcano", 5, 14, p + Vector3.new(0, 7.5, 0), rgb(84, 52, 48), M.Basalt)
		cylinder(F, "Volcano", 4, 9, p + Vector3.new(0, 12, 0), rgb(96, 58, 50), M.Basalt)
		local crater = disc(F, "Crater", 7, p + Vector3.new(0, 14, 0), LAVA_HOT, M.Neon, 0.3)
		Props.light(crater, LAVA, 24, 2)
		smoke(crater, 3)
		embers(crater)
	end
	for _ = 1, 18 do
		local p = Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(14, 20))
		local size = Vector3.new(rng:NextNumber(4, 9), rng:NextNumber(3, 6), rng:NextNumber(4, 8))
		Props.rock(F, p, size, rgb(44, 34, 38), M.Basalt, rng:NextNumber(0, 6))
		if rng:NextNumber() < 0.5 then
			ball(F, "Magma", size.Y * 0.5, p + Vector3.new(0, size.Y * 0.45, 0), LAVA, M.Neon)
		end
	end
	for _ = 1, 16 do -- obsidian spikes
		local p = Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(26, 30))
		local h = rng:NextNumber(6, 14)
		deco(F, "Obsidian", Vector3.new(1.6, h, 1.6), CFrame.new(p + Vector3.new(0, h / 2 - 1, 0)) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 3), rng:NextNumber(-0.25, 0.25)),
			rgb(26, 20, 32), M.Glass)
	end

	ambience(c, 400, 34, 2, { -- falling ash
		color = rgb(120, 110, 110), rate = 5, lifetime = NumberRange.new(6, 9), speed = NumberRange.new(1, 3),
		size = NumberSequence.new(0.25), direction = Enum.NormalId.Bottom, acceleration = Vector3.new(1, -0.4, 0),
	})
end

local function lavaOrnament(folder: Instance, x: number)
	for _, s in { -1, 1 } do
		local top = Vector3.new(x - 3.2, GROUND + H + 8, s * (HALF_W - 1))
		rod(folder, "LavaDrip", top, top - Vector3.new(0, 16, 0), 0.8, LAVA, M.Neon)
		local flame = Props.emitter(folder, "Flame", Vector3.new(3, 1, 3), Vector3.new(x, GROUND + H + 16, s * (HALF_W - 1)), {
			texture = Props.TEX.fire, color = sparkleGradient(LAVA_HOT, rgb(255, 60, 20)), rate = 18, lifetime = NumberRange.new(0.6, 1.1),
			speed = NumberRange.new(4, 7), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0.5) }),
			spread = Vector2.new(10, 10), lightEmission = 1,
		})
		flame.Name = "Flame"
	end
end

----------------------------------------------------------------------------------------------------
-- 5. Snow Peaks: snow, ice patches, ice walls with snow caps + icicles, pines, snowmen, snowfall
----------------------------------------------------------------------------------------------------
local ICE = rgb(170, 216, 250)

local function pine(F: Instance, p: Vector3, scale: number)
	local green = rgb(38, 118, 82)
	cylinder(F, "PineTrunk", 4 * scale, 1.6 * scale, p + Vector3.new(0, 2 * scale, 0), rgb(110, 76, 50), M.Wood)
	for i = 0, 2 do
		local w = (12 - i * 3) * scale
		deco(F, "PineTier", Vector3.new(w, 3.5 * scale, w), CFrame.new(p + Vector3.new(0, (5 + i * 3.4) * scale, 0)) * CFrame.Angles(0, if i % 2 == 0 then 0 else math.rad(45), 0), green, M.Grass)
	end
	blob(F, "PineSnow", Vector3.new(6, 2.4, 6) * scale, CFrame.new(p + Vector3.new(0, 13 * scale, 0)), rgb(250, 252, 255), M.Snow)
end

local function snowman(F: Instance, p: Vector3)
	local white = rgb(248, 250, 255)
	ball(F, "Snowman", 6, p + Vector3.new(0, 2.6, 0), white, M.Snow)
	ball(F, "Snowman", 4.4, p + Vector3.new(0, 6.6, 0), white, M.Snow)
	ball(F, "Snowman", 3.2, p + Vector3.new(0, 9.6, 0), white, M.Snow)
	for _, z in { -0.6, 0.6 } do
		ball(F, "Coal", 0.5, p + Vector3.new(-1.45, 10, z), rgb(30, 30, 35))
	end
	rod(F, "Carrot", p + Vector3.new(-1.3, 9.6, 0), p + Vector3.new(-3.2, 9.4, 0), 0.5, rgb(255, 140, 40))
	cylinder(F, "Hat", 2, 2.2, p + Vector3.new(0, 11.8, 0), rgb(30, 30, 40))
	disc(F, "HatBrim", 3.2, p + Vector3.new(0, 10.8, 0), rgb(30, 30, 40))
end

local function buildSnow(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	for _ = 1, 18 do
		flat(F, "IcePatch", rng:NextNumber(10, 24), rng:NextNumber(6, 14), Vector3.new(randX(c), GROUND, rng:NextNumber(-20, 20)), ICE, M.Glacier, rng:NextNumber(0, math.pi), 0.1)
	end

	walls(c, M.Ice, rgb(250, 252, 255), M.Snow, Vector2.new(8, 4))
	every(c, 24, 8, function(x) -- icicles under the snow cap
		for _, s in { -1, 1 } do
			local len = rng:NextNumber(3, 7)
			deco(F, "Icicle", Vector3.new(0.9, len, 0.9), CFrame.new(x, GROUND + H - len / 2, s * (HALF_W - 0.6)) * CFrame.Angles(0, math.rad(45), 0), ICE, M.Ice).CastShadow = false
		end
	end)
	every(c, 90, 20, function(x) -- drifts along the wall foot
		blob(F, "Drift", Vector3.new(rng:NextNumber(20, 36), rng:NextNumber(5, 8), 10), CFrame.new(x, GROUND, side(rng) * 30), rgb(250, 252, 255), M.Snow)
	end)

	every(c, 50, 10, function(x)
		for _, s in { -1, 1 } do
			pine(F, Vector3.new(x + rng:NextNumber(-8, 8), GROUND, s * rng:NextNumber(24, 28)), rng:NextNumber(0.9, 1.5))
		end
	end)
	for i = 1, 4 do
		snowman(F, Vector3.new(c.x0 + c.len * (i - 0.5) / 4 + rng:NextNumber(-60, 60), GROUND, (if i % 2 == 0 then 1 else -1) * rng:NextNumber(18, 22)))
	end
	for _ = 1, 12 do -- ice crystal clusters
		local p = Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(20, 28))
		for j = 1, 3 do
			local h = rng:NextNumber(3, 9)
			deco(F, "IceCrystal", Vector3.new(1.4, h, 1.4), CFrame.new(p + Vector3.new(rng:NextNumber(-1.5, 1.5), h / 2 - 0.5, rng:NextNumber(-1.5, 1.5)))
				* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 3), rng:NextNumber(-0.35, 0.35)),
				if j == 1 then rgb(150, 235, 255) else ICE, if j == 1 then M.Neon else M.Ice)
		end
	end

	ambience(c, 150, 48, 2, { -- snowfall
		color = rgb(255, 255, 255), rate = 14, lifetime = NumberRange.new(8, 11), speed = NumberRange.new(3, 5),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.3) }),
		direction = Enum.NormalId.Bottom, acceleration = Vector3.new(1, -0.5, 0), spread = Vector2.new(15, 15),
		rotSpeed = NumberRange.new(-60, 60), lightEmission = 0.3,
	})
end

local function snowOrnament(folder: Instance, x: number)
	blob(folder, "SnowCap", Vector3.new(9, 4, Config.CORRIDOR_WIDTH + 12), CFrame.new(x, GROUND + H + 9, 0), rgb(250, 252, 255), M.Snow)
	for _, z in { -35, -32, -29, 29, 32, 35 } do -- icicles beside the sign, not over it
		local len = 3 + (math.abs(z) % 3)
		deco(folder, "Icicle", Vector3.new(0.9, len, 0.9), CFrame.new(x - 4.2, GROUND + H + 3.5 - len / 2, z) * CFrame.Angles(0, math.rad(45), 0), ICE, M.Ice)
	end
end

----------------------------------------------------------------------------------------------------
-- 6. Deep Space: dark floor with neon stars and grid, planets, crystals, asteroids, a UFO
----------------------------------------------------------------------------------------------------
local SPACE_CYAN = rgb(70, 225, 255)
local SPACE_PINK = rgb(255, 80, 220)
local STAR_COLORS = { rgb(255, 255, 255), SPACE_CYAN, rgb(255, 150, 240), rgb(255, 240, 140) }

local function buildSpace(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	for x = c.x0 + 30, c.x1 - 30, 60 do
		flat(F, "GridLine", 0.6, Config.CORRIDOR_WIDTH, Vector3.new(x, GROUND, 0), SPACE_CYAN, M.Neon, nil, 0.06)
	end
	for _, s in { -1, 1 } do
		flat(F, "GridLine", c.len, 0.6, Vector3.new(c.x0 + c.len / 2, GROUND, s * 20), SPACE_CYAN, M.Neon, nil, 0.06)
	end
	for _ = 1, 90 do
		local size = rng:NextNumber(0.5, 1.1)
		flat(F, "FloorStar", size, size, Vector3.new(randX(c, 8), GROUND, rng:NextNumber(-30, 30)), STAR_COLORS[rng:NextInteger(1, #STAR_COLORS)], M.Neon, math.rad(45), 0.08)
	end

	walls(c, M.Metal, rgb(24, 20, 50), M.Metal, Vector2.new(6, 2))
	band(c, 14, 1.2, SPACE_PINK, M.Neon)
	band(c, H - 1.5, 0.8, SPACE_CYAN, M.Neon)
	every(c, 60, 0, function(x)
		for _, s in { -1, 1 } do
			deco(F, "PanelSeam", Vector3.new(0.4, H - 4, 0.3), CFrame.new(x, GROUND + H / 2, s * (HALF_W - 0.1)), rgb(120, 100, 220), M.Neon).CastShadow = false
		end
	end)

	-- Planets hang in the sky over the corridor
	local planetColors = { rgb(255, 150, 60), rgb(80, 220, 200), rgb(255, 110, 180), rgb(150, 110, 255), rgb(255, 220, 90), rgb(110, 170, 255) }
	for i = 1, 8 do
		local size = rng:NextNumber(18, 42)
		local p = Vector3.new(c.x0 + c.len * (i - 0.5) / 8, GROUND + rng:NextNumber(70, 110), rng:NextNumber(-40, 40))
		local color = planetColors[(i - 1) % #planetColors + 1]
		ball(F, "Planet", size, p, color)
		if i % 2 == 1 then
			local ring = deco(F, "PlanetRing", Vector3.new(0.6, size * 1.9, size * 1.9), CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(90) + rng:NextNumber(-0.5, 0.5)),
				color:Lerp(Color3.new(1, 1, 1), 0.5), M.Neon)
			ring.Shape = Enum.PartType.Cylinder
			ring.Transparency = 0.35
		end
	end
	for _ = 1, 22 do -- crystal clusters
		local p = Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(22, 29))
		local color = if rng:NextNumber() < 0.5 then rgb(190, 120, 255) else SPACE_CYAN
		local first: BasePart? = nil
		for j = 1, 3 do
			local h = rng:NextNumber(5, 14)
			local cr = deco(F, "Crystal", Vector3.new(rng:NextNumber(1.5, 3), h, rng:NextNumber(1.5, 3)),
				CFrame.new(p + Vector3.new(rng:NextNumber(-2, 2), h / 2 - 1, rng:NextNumber(-2, 2))) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)),
				color, if j == 1 then M.Neon else M.Glass)
			first = first or cr
		end
		if first and rng:NextNumber() < 0.35 then
			Props.light(first, color, 16, 1.5)
		end
	end
	for _ = 1, 14 do
		local size = rng:NextNumber(3, 8)
		blob(F, "Asteroid", Vector3.new(size, size * 0.8, size * 0.9), CFrame.new(randX(c), GROUND + rng:NextNumber(18, 38), side(rng) * rng:NextNumber(18, 28))
			* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), rgb(110, 104, 132), M.Slate)
	end
	for _ = 1, 10 do -- alien mushrooms
		local p = Vector3.new(randX(c), GROUND, side(rng) * rng:NextNumber(18, 26))
		local h = rng:NextNumber(3, 7)
		cylinder(F, "AlienStem", h, 0.8, p + Vector3.new(0, h / 2, 0), rgb(200, 240, 230))
		blob(F, "AlienCap", Vector3.new(4, 1.6, 4), CFrame.new(p + Vector3.new(0, h, 0)), if rng:NextNumber() < 0.5 then rgb(120, 255, 150) else SPACE_PINK, M.Neon)
	end
	-- A UFO parked over the first stretch
	local u = Vector3.new(c.x0 + 260, GROUND + 36, 0)
	blob(F, "UFO", Vector3.new(24, 4, 24), CFrame.new(u), rgb(180, 185, 200), M.Metal)
	blob(F, "UFODome", Vector3.new(10, 7, 10), CFrame.new(u + Vector3.new(0, 2.5, 0)), rgb(120, 230, 255), M.Glass).Transparency = 0.3
	disc(F, "UFORing", 20, u - Vector3.new(0, 1.8, 0), rgb(120, 255, 150), M.Neon, 0.3)
	local beam = cylinder(F, "UFOBeam", 34, 12, u - Vector3.new(0, 19, 0), rgb(120, 255, 150), M.Neon)
	beam.Transparency = 0.85
	beam.CastShadow = false

	ambience(c, 350, 22, 30, { -- twinkles
		color = sparkleGradient(rgb(255, 255, 255), SPACE_CYAN), rate = 10, lifetime = NumberRange.new(2, 4),
		speed = NumberRange.new(0, 0.4), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		spread = Vector2.new(180, 180), lightEmission = 1,
	})
end

local function spaceOrnament(folder: Instance, x: number)
	for _, s in { -1, 1 } do
		local ring = deco(folder, "OrbitRing", Vector3.new(0.4, 14, 14), CFrame.new(x, GROUND + H + 12, s * (HALF_W - 1)) * CFrame.Angles(0, 0, math.rad(70)), SPACE_CYAN, M.Neon)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 0.3
		rod(folder, "Antenna", Vector3.new(x, GROUND + H + 8, s * 12), Vector3.new(x, GROUND + H + 16, s * 12), 0.4, rgb(180, 185, 200), M.Metal)
		ball(folder, "AntennaTip", 1.2, Vector3.new(x, GROUND + H + 16.5, s * 12), SPACE_PINK, M.Neon)
	end
end

----------------------------------------------------------------------------------------------------
-- 7. Spirit Garden: raked gravel, stepping stones, plaster walls with red posts, torii gates,
--    stone lanterns, cherry trees, koi ponds, paper lanterns and falling petals
----------------------------------------------------------------------------------------------------
local TORII_RED = rgb(212, 40, 46)
local BLOSSOM = { rgb(255, 176, 206), rgb(255, 200, 222), rgb(250, 150, 190) }

local function stoneLantern(F: Instance, p: Vector3, lit: boolean)
	local stone = rgb(170, 166, 160)
	deco(F, "LanternBase", Vector3.new(2.6, 1, 2.6), CFrame.new(p + Vector3.new(0, 0.5, 0)), stone, M.Slate)
	cylinder(F, "LanternPost", 3.4, 1.1, p + Vector3.new(0, 2.7, 0), stone, M.Slate)
	local light = deco(F, "LanternLight", Vector3.new(2, 1.8, 2), CFrame.new(p + Vector3.new(0, 5.3, 0)), rgb(255, 214, 130), M.Neon)
	blob(F, "LanternRoof", Vector3.new(4, 1.4, 4), CFrame.new(p + Vector3.new(0, 6.6, 0)), rgb(92, 90, 96), M.Slate)
	if lit then
		Props.light(light, rgb(255, 200, 120), 16, 1.2)
	end
end

local function cherryTree(F: Instance, p: Vector3, s: number, rng: Random)
	local top = p + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(11, 15), -s * 3)
	rod(F, "Trunk", p, top, 1.8, rgb(96, 58, 48), M.Wood)
	local branch = top + Vector3.new(rng:NextNumber(3, 6), rng:NextNumber(1, 3), -s * 4)
	rod(F, "Branch", top, branch, 1, rgb(96, 58, 48), M.Wood)
	blob(F, "Blossom", Vector3.new(16, 9, 14), CFrame.new(top + Vector3.new(0, 2, 0)), BLOSSOM[rng:NextInteger(1, #BLOSSOM)], M.Grass)
	blob(F, "Blossom", Vector3.new(11, 7, 10), CFrame.new(branch + Vector3.new(0, 1.5, 0)), BLOSSOM[rng:NextInteger(1, #BLOSSOM)], M.Grass)
end

local function buildSpirit(c: Ctx)
	local rng, F = c.rng, c.folder
	floor(c)
	for _, s in { -1, 1 } do
		flat(F, "Moss", c.len, 9, Vector3.new(c.x0 + c.len / 2, GROUND, s * 27.5), rgb(122, 184, 96), M.Grass, nil, 0.12)
	end
	for x = c.x0 + 14, c.x1 - 14, 22 do
		flat(F, "SteppingStone", 12, 16, Vector3.new(x, GROUND, rng:NextNumber(-1.5, 1.5)), rgb(168, 162, 160), M.Slate, rng:NextNumber(-0.12, 0.12), 0.25)
	end
	for _ = 1, 50 do
		flat(F, "Petal", 0.9, 0.6, Vector3.new(randX(c), GROUND, rng:NextNumber(-26, 26)), BLOSSOM[rng:NextInteger(1, #BLOSSOM)], M.SmoothPlastic, rng:NextNumber(0, math.pi), 0.06)
	end

	-- White plaster walls with red timber posts and a tiled roof
	walls(c, M.SmoothPlastic, rgb(60, 58, 74), M.Slate, Vector2.new(9, 2.5))
	band(c, 1.5, 3, TORII_RED)
	band(c, H - 3, 3, TORII_RED)
	band(c, H - 5.2, 0.6, rgb(255, 200, 80), M.Foil)
	every(c, 40, 0, function(x)
		for _, s in { -1, 1 } do
			deco(F, "WallPost", Vector3.new(1.8, H, 1.2), CFrame.new(x, GROUND + H / 2, s * (HALF_W - 0.4)), TORII_RED)
		end
	end)

	for i = 1, 5 do
		c.helpers.torii(F, c.x0 + i * c.len / 6, TORII_RED, 26)
	end
	every(c, 120, 0, function(x, i)
		for _, s in { -1, 1 } do
			stoneLantern(F, Vector3.new(x + 60 * (if s > 0 then 0 else 1), GROUND, s * 15), i % 2 == 0)
		end
	end)
	every(c, 100, 15, function(x)
		for _, s in { -1, 1 } do
			cherryTree(F, Vector3.new(x + rng:NextNumber(-10, 10), GROUND, s * rng:NextNumber(25, 28)), s, rng)
		end
	end)
	for i = 1, 8 do -- strings of paper lanterns across the path
		local x = c.x0 + (i - 0.5) * c.len / 8 + 60
		rod(F, "LanternRope", Vector3.new(x, GROUND + 32, -HALF_W), Vector3.new(x, GROUND + 32, HALF_W), 0.2, rgb(40, 30, 30))
		for z = -20, 20, 10 do
			local lantern = blob(F, "PaperLantern", Vector3.new(2.4, 3, 2.4), CFrame.new(x, GROUND + 30, z), if z == 0 then rgb(255, 200, 90) else rgb(240, 60, 60), M.Neon)
			lantern.CastShadow = false
		end
	end
	for i = 1, 2 do -- koi ponds
		local p = Vector3.new(c.x0 + c.len * (i == 1 and 0.3 or 0.62), GROUND, (if i == 1 then 1 else -1) * 22)
		local pond = disc(F, "Pond", 14, p, rgb(100, 180, 225), M.Glass, 0.3)
		pond.Transparency = 0.2
		for j = 1, 7 do
			local a = j / 7 * math.pi * 2
			Props.rock(F, p + Vector3.new(math.cos(a) * 7.5, 0, math.sin(a) * 7.5), Vector3.new(2.4, 1.6, 2), rgb(150, 146, 144), M.Slate, a)
		end
		for j = 1, 2 do
			blob(F, "Koi", Vector3.new(2, 0.5, 0.8), CFrame.new(p + Vector3.new(j * 2 - 3, 0.4, j - 1.5)) * CFrame.Angles(0, j, 0), if j == 1 then rgb(255, 130, 40) else rgb(255, 250, 245))
		end
	end

	ambience(c, 160, 40, 2, { -- falling cherry petals
		texture = Props.TEX.smoke, color = sparkleGradient(rgb(255, 170, 205), rgb(255, 215, 230)), rate = 8,
		lifetime = NumberRange.new(8, 11), speed = NumberRange.new(2, 3), size = NumberSequence.new(0.5),
		transparency = fade(0.05, 0.2), direction = Enum.NormalId.Bottom, acceleration = Vector3.new(1.5, -0.8, 0),
		spread = Vector2.new(30, 30), rotSpeed = NumberRange.new(-120, 120),
	})
end

local function spiritOrnament(folder: Instance, x: number)
	for _, s in { -1, 1 } do
		local lantern = blob(folder, "PaperLantern", Vector3.new(3, 4, 3), CFrame.new(x - 5, GROUND + H - 1, s * 27.5), rgb(240, 60, 60), M.Neon)
		lantern.CastShadow = false
		ball(folder, "GoldFinial", 2, Vector3.new(x - 5, GROUND + H + 1.5, s * 27.5), rgb(255, 205, 80), M.Foil)
	end
end

----------------------------------------------------------------------------------------------------
-- Theme table
----------------------------------------------------------------------------------------------------
local THEMES: { [string]: Theme } = {
	Meadow = {
		arch = rgb(255, 250, 240), archMaterial = M.WoodPlanks, accent = rgb(255, 222, 60),
		sign = rgb(64, 168, 70), signText = rgb(255, 210, 235),
		mound = rgb(122, 82, 50), nestStone = rgb(170, 170, 180), nestStoneMaterial = M.Slate, leaf = rgb(90, 210, 80),
		build = buildMeadow, ornament = meadowOrnament,
	},
	Desert = {
		arch = rgb(214, 140, 80), archMaterial = M.Sandstone, accent = rgb(255, 170, 60),
		sign = rgb(170, 90, 50), signText = rgb(255, 225, 190),
		mound = rgb(196, 146, 88), nestStone = rgb(214, 150, 92), nestStoneMaterial = M.Sandstone, leaf = rgb(80, 175, 80),
		build = buildDesert, ornament = desertOrnament,
	},
	Jungle = {
		arch = rgb(110, 84, 56), archMaterial = M.Wood, accent = rgb(140, 255, 90),
		sign = rgb(40, 110, 50), signText = rgb(200, 255, 170),
		mound = rgb(112, 76, 46), nestStone = rgb(100, 130, 90), nestStoneMaterial = M.Cobblestone, leaf = rgb(40, 175, 70),
		build = buildJungle, ornament = jungleOrnament,
	},
	Lava = {
		arch = rgb(56, 40, 42), archMaterial = M.Basalt, accent = LAVA,
		sign = rgb(90, 24, 16), signText = rgb(255, 180, 120),
		mound = rgb(52, 36, 36), nestStone = rgb(40, 30, 32), nestStoneMaterial = M.Basalt, leaf = rgb(230, 90, 30),
		build = buildLava, ornament = lavaOrnament,
	},
	Snow = {
		arch = rgb(186, 222, 250), archMaterial = M.Ice, accent = rgb(140, 230, 255),
		sign = rgb(60, 110, 170), signText = rgb(210, 240, 255),
		mound = rgb(222, 236, 250), nestStone = ICE, nestStoneMaterial = M.Ice, leaf = rgb(60, 150, 110),
		build = buildSnow, ornament = snowOrnament,
	},
	Space = {
		arch = rgb(60, 50, 120), archMaterial = M.Metal, accent = SPACE_CYAN,
		sign = rgb(34, 24, 80), signText = rgb(200, 170, 255),
		mound = rgb(62, 50, 112), nestStone = rgb(160, 120, 255), nestStoneMaterial = M.Glass, leaf = rgb(120, 255, 180),
		build = buildSpace, ornament = spaceOrnament,
	},
	Spirit = {
		arch = TORII_RED, archMaterial = M.SmoothPlastic, accent = rgb(255, 205, 80),
		sign = rgb(120, 20, 30), signText = rgb(255, 200, 220),
		mound = rgb(120, 90, 70), nestStone = rgb(190, 185, 180), nestStoneMaterial = M.Slate, leaf = rgb(255, 170, 200),
		build = buildSpirit, ornament = spiritOrnament,
	},
}

function ZoneThemes.theme(k: number): Theme
	return THEMES[Config.ZONES[k].id]
end

function ZoneThemes.build(folder: Folder, k: number, rng: Random, helpers: { [string]: any })
	local x0 = Config.zoneStartX(k)
	local len = Config.ZONES[k].length
	local ctx: Ctx = { folder = folder, k = k, x0 = x0, x1 = x0 + len, len = len, nestX = Config.nestX(k), rng = rng, helpers = helpers }
	ZoneThemes.theme(k).build(ctx)
end

function ZoneThemes.archOrnament(folder: Instance, k: number, x: number)
	ZoneThemes.theme(k).ornament(folder, x)
end

return ZoneThemes
