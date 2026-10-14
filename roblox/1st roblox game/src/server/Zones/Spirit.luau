-- 7. Spirit Garden, the last stage (the corridor ends at its back wall): green lawn, lavender checker walls
-- under a stylised tiled roof, and a calm Japanese garden (no torii: the owner removed the gates):
--   * cherry trees in bloom, petals falling from them
--   * stone lanterns with a warm light, in pairs along the path
--   * two little shrines: a stone base, red posts, a stepped roof, an offering box
--   * waterfalls down the side walls into ponds (the owner liked these), one of them a koi pond
--   * bamboo groves, rocks, stepping stones down the middle
--   * the end: a bright, pale back wall with a big waterfall into a pond, lanterns along it, so the end of
--     the corridor reads from the spawn, by day and by night
local Assets = require(script.Parent.Parent:WaitForChild("Assets"))
local Props = require(script.Parent.Parent:WaitForChild("Props"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local rgb, at, box = Kit.rgb, Kit.at, Kit.box
local block = Props.block
local GROUND, W, HALF_W, H = Kit.GROUND, Kit.W, Kit.HALF_W, Kit.H
local M = Enum.Material

local Spirit = {}
Spirit.floorLight = rgb(128, 214, 110)
Spirit.wallLight = rgb(156, 156, 224)

local ROOF = rgb(96, 112, 184)
local ROOF_RIDGE = rgb(128, 144, 208)
local RED = rgb(218, 46, 52)
local STONE = rgb(176, 176, 196)
local STONE_DARK = rgb(140, 140, 162)
local WOOD = rgb(110, 70, 58)
local WOOD_DARK = rgb(84, 52, 44)
local LAMP = rgb(255, 214, 130)
local BLOSSOM = { rgb(255, 176, 206), rgb(255, 200, 222), rgb(250, 150, 190) }
local BACK = rgb(206, 204, 246) -- the back wall: pale, so the end of the corridor shows from the spawn
local BACK_LIGHT = rgb(238, 236, 255)
Spirit.cap = ROOF

-- A stone lantern: a base, a post, the glowing light box under a wide stepped roof. Lit ones carry a light
-- (and pass it on to a drop-in model that has none of its own).
local function stoneLantern(F: Instance, p: Vector3, s: number, lit: boolean)
	local cf = CFrame.new(p)
	local function b(name: string, size: Vector3, y: number, color: Color3, turn: number?)
		return block(F, name, size * s, cf * CFrame.new(0, y * s, 0) * CFrame.Angles(0, turn or 0, 0), color)
	end
	b("LanternBase", Vector3.new(3.4, 1, 3.4), 0.5, STONE_DARK)
	b("LanternBase", Vector3.new(2.4, 0.6, 2.4), 1.25, STONE)
	b("LanternPost", Vector3.new(1.4, 3.6, 1.4), 3.2, STONE)
	b("LanternBase", Vector3.new(3, 0.6, 3), 5.25, STONE_DARK)
	local light = Kit.glow(F, "LanternLight", Vector3.new(2.1, 1.9, 2.1) * s, cf * CFrame.new(0, 6.45 * s, 0), LAMP)
	b("LanternRoof", Vector3.new(4.6, 0.9, 4.6), 7.8, STONE, math.rad(45))
	b("LanternRoof", Vector3.new(2.6, 0.9, 2.6), 8.65, STONE_DARK)
	b("LanternRoof", Vector3.new(0.9, 0.9, 0.9), 9.4, STONE)
	if lit then
		Props.light(light, rgb(255, 200, 120), 18, 1.4)
	end
end

-- A cherry tree leaning over the path (side `s`): a dark trunk with a bend, two branches and a cloud of
-- blossom in layered pink blocks.
local function cherryTree(F: Instance, p: Vector3, s: number, rng: Random, scale: number)
	local spin = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0)
	local h1, h2 = 8 * scale, 7 * scale
	block(F, "Trunk", Vector3.new(2.6 * scale, h1, 2.6 * scale), spin * CFrame.new(0, h1 / 2, 0), WOOD)
	local bend = spin * CFrame.new(0, h1 - 0.6, 0) * CFrame.Angles(s * 0.28, 0, rng:NextNumber(-0.15, 0.15))
	block(F, "Trunk", Vector3.new(2 * scale, h2, 2 * scale), bend * CFrame.new(0, h2 / 2, 0), WOOD_DARK)
	local top = bend * CFrame.new(0, h2 - 0.4, 0)
	for i, a in { 1.1, -1.4 } do
		local len = 6 * scale
		local branch = top * CFrame.Angles(0, a + rng:NextNumber(-0.3, 0.3), 0) * CFrame.Angles(0, 0, -0.95)
		block(F, "Branch", Vector3.new(1.1 * scale, len, 1.1 * scale), branch * CFrame.new(0, len / 2, 0), WOOD)
		block(F, "Blossom", Vector3.new(8.5, 4, 8.5) * scale, branch * CFrame.new(0, len, 0) * CFrame.Angles(0, 0, 0.95) * CFrame.new(0, 0.8 + i * 0.07, 0), BLOSSOM[i + 1])
	end
	block(F, "Blossom", Vector3.new(15, 5, 12) * scale, top * CFrame.new(0, 1.8 * scale, 0), BLOSSOM[1])
	block(F, "Blossom", Vector3.new(11, 5.4, 15) * scale, top * CFrame.new(0.8 * scale, 2.6 * scale, -0.6 * scale), BLOSSOM[2])
	block(F, "Blossom", Vector3.new(9, 3.6, 9) * scale, top * CFrame.new(-0.6 * scale, 5.6 * scale, 0.4 * scale), BLOSSOM[3])
	block(F, "Blossom", Vector3.new(12.6, 2, 10) * scale, top * CFrame.new(0.3 * scale, 0.1 - scale, 0.2 * scale), BLOSSOM[3]) -- (its top under the trunk's)
end

-- A little shrine in frame `f`: a two-step stone base, red posts, dark wooden walls with a gold-trimmed
-- door, a stepped slate roof with a red ridge, an offering box and a bell rope.
local function shrine(F: Instance, f: Kit.Frame)
	box(F, "ShrineBase", f, -7, 7, 0, 1.2, 0.5, 13.5, STONE_DARK)
	box(F, "ShrineBase", f, -5.6, 5.6, 1, 2.4, 1.2, 11.2, STONE)
	box(F, "ShrineStep", f, -2.2, 2.2, 0, 1.75, 13.5, 15.2, STONE)
	for _, q in { { -4.6, 2.2 }, { 4.6, 2.2 }, { -4.6, 10.2 }, { 4.6, 10.2 } } do
		box(F, "ShrinePost", f, q[1] - 0.55, q[1] + 0.55, 2.4, 9.4, q[2] - 0.55, q[2] + 0.55, RED)
	end
	box(F, "ShrineWall", f, -4.0, 4.0, 2.45, 8.9, 2.1, 9.4, WOOD_DARK)
	box(F, "ShrineDoor", f, -2.1, 2.1, 2.4, 7.2, 9.4, 9.7, WOOD)
	box(F, "ShrineDoor", f, -2.3, 2.3, 7.2, 7.7, 9.35, 9.8, rgb(255, 200, 70))
	box(F, "ShrineRoof", f, -6.6, 6.6, 9.4, 10.6, -0.4, 13.2, ROOF)
	box(F, "ShrineRoof", f, -5.2, 5.2, 10.6, 11.9, 1.0, 11.8, ROOF_RIDGE)
	box(F, "ShrineRoof", f, -3.4, 3.4, 11.9, 12.9, 2.6, 10.2, ROOF)
	box(F, "ShrineRoof", f, -3.9, 3.9, 12.9, 13.6, 5.7, 7.1, RED)
	box(F, "ShrineRoof", f, -6.8, 6.8, 9.2, 9.75, 12.85, 13.45, RED)
	box(F, "Offering", f, -1.6, 1.6, 2.4, 4.2, 11.4, 13.1, WOOD)
	box(F, "Offering", f, -1.7, 1.7, 4.2, 4.55, 11.3, 13.2, rgb(255, 200, 70))
	box(F, "BellRope", f, -0.25, 0.25, 6.4, 9.3, 10.6, 11.1, RED)
	box(F, "Bell", f, -0.7, 0.7, 8.6, 9.35, 10.15, 11.55, rgb(255, 200, 70))
end

-- Koi on the pond's water: an orange or white fish with a tail and a patch.
local function koi(F: Instance, p: Vector3, yaw: number, color: Color3, patch: Color3)
	local cf = CFrame.new(p) * CFrame.Angles(0, yaw, 0)
	block(F, "Koi", Vector3.new(2.6, 0.3, 1.1), cf, color)
	block(F, "Koi", Vector3.new(1, 0.28, 1.3), cf * CFrame.new(-1.7, 0.02, 0) * CFrame.Angles(0, math.rad(45), 0), color)
	block(F, "Koi", Vector3.new(0.9, 0.32, 0.8), cf * CFrame.new(0.4, 0.06, 0), patch)
end

-- The tiled roof along the top of a wall run (x0..x1, side `s`): a slate slab sloping down toward the
-- corridor, ridges of tiles across it and a red trim along its lower edge.
local function roof(c: Kit.Ctx, x0: number, x1: number, s: number)
	local F, len = c.folder, x1 - x0
	local tilt = CFrame.Angles(-s * math.rad(20), 0, 0)
	local cf = CFrame.new((x0 + x1) / 2, GROUND + H + 3, s * (HALF_W + 1)) * tilt
	Props.studs(Props.deco(F, "Roof", Vector3.new(len + 4, 1.6, 13), cf, ROOF))
	local n = math.max(1, math.round(len / 7))
	for i = 0, n - 1 do
		local x = x0 + (i + 0.5) * len / n - (x0 + x1) / 2
		Props.deco(F, "RoofTile", Vector3.new(2.4, 1.2, 13.4), cf * CFrame.new(x, 1, 0) * CFrame.Angles(0, 0, math.rad(45)), ROOF_RIDGE).CastShadow = false
	end
	Props.deco(F, "RoofTrim", Vector3.new(len + 3.8, 1.4, 1), cf * CFrame.new(0, -0.6, -s * 6.4), RED)
end

-- The back wall that ends the corridor: solid, pale (so it shows down the whole corridor), a light checker
-- on its face, the roof along its top, a big waterfall into a pond and lanterns along it.
local function backWall(c: Kit.Ctx)
	local F = c.folder
	local endX = c.x1
	Props.studs(Props.box(F, "Wall", Vector3.new(4, H, W + 8), CFrame.new(endX + 2, GROUND + H / 2, 0), BACK), { "LeftSurface", "RightSurface" })
	local rows = 3
	local rh = H / rows
	local n = math.round(W / rh)
	for i = 0, n - 1 do
		for r = 0, rows - 1 do
			if (i + r) % 2 == 0 then
				-- (the end tiles stop short of the side walls' own checker)
				local z0 = -HALF_W + i * W / n + (if i == 0 then 0.15 else 0)
				local z1 = -HALF_W + (i + 1) * W / n - (if i == n - 1 then 0.15 else 0)
				Props.studs(Props.deco(F, "WallTile", Vector3.new(0.1, rh, z1 - z0), CFrame.new(endX - 0.05, GROUND + (r + 0.5) * rh, (z0 + z1) / 2), BACK_LIGHT),
					{ "LeftSurface", "RightSurface" }).CastShadow = false
			end
		end
	end
	Props.studs(Props.deco(F, "WallCap", Vector3.new(7, 2, W + 8), CFrame.new(endX + 1.5, GROUND + H + 1.05, 0), Spirit.cap))
	Props.studs(Props.deco(F, "Roof", Vector3.new(13, 1.6, W + 12), CFrame.new(endX + 1, GROUND + H + 3, 0) * CFrame.Angles(0, 0, math.rad(20)), ROOF))
	Props.deco(F, "RoofTrim", Vector3.new(1, 1.4, W + 11.6), CFrame.new(endX - 5, GROUND + H + 0.9, 0), RED)
	-- the big waterfall down its middle into a pond
	local f = Kit.frame(Vector3.new(endX, GROUND, 0), -Vector3.xAxis)
	Kit.waterfall(F, f, 0, 0, 26, H - 2.5)
	Kit.pond(F, Vector3.new(endX - 20, GROUND, 0), 34, 4)
	-- lanterns on the wall either side of the fall, and two tall stone lanterns by the pond
	for i, z in { -76, -52, -28, 28, 52, 76 } do
		local p = Vector3.new(endX, GROUND + 30 + (i % 2) * 4, z)
		block(F, "WallLantern", Vector3.new(2.4, 1, 3.4), CFrame.new(p + Vector3.new(-1.35, -2.2, 0)), STONE_DARK)
		local light = Kit.glow(F, "WallLanternLight", Vector3.new(2, 3, 2.6), CFrame.new(p + Vector3.new(-1.2, -0.2, 0)), LAMP)
		block(F, "WallLantern", Vector3.new(3, 1, 4), CFrame.new(p + Vector3.new(-1.6, 1.8, 0)), ROOF)
		if i % 2 == 1 then
			Props.light(light, rgb(255, 200, 120), 26, 1.6)
		end
	end
	for _, z in { -26, 26 } do
		stoneLantern(F, Vector3.new(endX - 12, GROUND, z), 1.5, true)
	end
end

function Spirit.build(c: Kit.Ctx)
	local F = c.folder
	Kit.floor(c, Spirit)
	Kit.walls(c, Spirit)
	for _, s in { -1, 1 } do
		roof(c, c.x0, c.x1, s)
	end
	backWall(c)

	-- waterfalls down the side walls into ponds (the right one is the koi pond)
	for i, q in { { 0.12, -1 }, { 0.45, 1 } } do
		local x, s = at(c, q[1]), q[2]
		local f = Kit.wallFrame(x, s)
		Kit.waterfall(F, f, 0, 0, 12, H - 2.5)
		local pondAt = Vector3.new(x, GROUND, s * (HALF_W - 15))
		Kit.pond(F, pondAt, if i == 2 then 32 else 28, 2)
		if i == 2 then
			local rng = Kit.rand(c, "koi")
			for j = 1, 5 do
				local a = j / 5 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
				local p = pondAt + Vector3.new(math.cos(a) * rng:NextNumber(4, 9), -Kit.POND_SINK + 0.16 + j * 0.01, math.sin(a) * rng:NextNumber(3, 6))
				koi(F, p, a + math.pi / 2, if j % 2 == 0 then rgb(255, 250, 245) else rgb(255, 130, 40), if j % 2 == 0 then rgb(240, 70, 50) else rgb(255, 250, 245))
			end
		end
	end

	-- the shrines
	for i, q in { { 0.29, -1 }, { 0.6, 1 } } do
		local f = Kit.wallFrame(at(c, q[1]), q[2], 1.5)
		Assets.swap("Spirit_Shrine", F, Kit.facing(f), function(into)
			shrine(into, f)
		end)
		if i == 1 then
			for _, u in { -11, 11 } do
				local p = Kit.p(f, u, 0, 14)
				Assets.swap("Spirit_Lantern", F, Assets.facing(p, f.out), function(into)
					stoneLantern(into, p, 1, true)
				end)
			end
		end
	end
	-- stone lanterns in pairs along the path
	for i, f in { 0.08, 0.38, 0.7 } do
		for _, s in { -1, 1 } do
			local p = Vector3.new(at(c, f), GROUND, s * 56)
			Assets.swap("Spirit_Lantern", F, Assets.facing(p, Vector3.new(0, 0, -s)), function(into) -- front toward the path
				stoneLantern(into, p, 1, i ~= 2)
			end)
		end
	end
	-- cherry trees along both walls, leaning over the path
	for i, q in { { 0.06, 1, 1.0 }, { 0.21, -1, 1.15 }, { 0.3, 1, 1.05 }, { 0.5, -1, 1.2 }, { 0.69, -1, 1.0 }, { 0.73, 1, 1.15 }, { 0.93, 1, 1.0 } } do
		local s = q[2]
		local rng = Kit.rand(c, "cherry" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-5, 5), GROUND, s * rng:NextNumber(80, 85))
		Assets.swap("Spirit_CherryTree", F, Assets.facing(p, Vector3.new(0, 0, -s)), function(into) -- front toward the path
			cherryTree(into, p, s, rng, q[3])
		end)
		if i % 2 == 1 then -- petals falling from it
			Props.emitter(F, "Petals", Vector3.new(14, 2, 12), p + Vector3.new(0, 18 * q[3], -s * 5), {
				texture = Props.TEX.smoke, color = Kit.gradient(rgb(255, 170, 205), rgb(255, 215, 230)), rate = 3,
				lifetime = NumberRange.new(5, 7), speed = NumberRange.new(1, 2), size = NumberSequence.new(0.45),
				transparency = Kit.fade(0.05, 0.2), direction = Enum.NormalId.Bottom, acceleration = Vector3.new(1, -0.6, 0),
				spread = Vector2.new(40, 40), rotSpeed = NumberRange.new(-120, 120),
			})
		end
	end
	-- bamboo groves and rocks
	for i, q in { { 0.175, 1 }, { 0.41, -1 }, { 0.83, 1 }, { 0.58, -1 } } do
		local rng = Kit.rand(c, "bamboo" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-3, 3), GROUND, q[2] * rng:NextNumber(84, 88))
		Assets.swap("Spirit_Bamboo", F, Assets.spin(p), function(into)
			Kit.bamboo(into, "Bamboo", p, rng, 5, rng:NextNumber(20, 28))
		end)
	end
	for i, q in { { 0.18, -1 }, { 0.34, 1 }, { 0.55, 1 }, { 0.64, -1 }, { 0.86, 1 } } do
		local rng = Kit.rand(c, "rock" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-4, 4), GROUND, q[2] * rng:NextNumber(62, 72))
		local size = rng:NextNumber(3.5, 6)
		Assets.swap("Spirit_Rock", F, Assets.spin(p), function(into)
			Kit.rock(into, "Rock", p, size, rng, STONE, STONE_DARK)
		end)
	end
	-- stepping stones down the middle
	local stones = Kit.rand(c, "stones")
	for x = c.x0 + 24, c.x1 - 40, 30 do
		Props.flat(F, "SteppingStone", 12, 16, Vector3.new(x, GROUND, stones:NextNumber(-2, 2)), rgb(196, 196, 226), M.SmoothPlastic, stones:NextNumber(-0.12, 0.12), 0.25)
	end

	Kit.ambience(c, 400, 40, 2, { -- falling cherry petals
		texture = Props.TEX.smoke, color = Kit.gradient(rgb(255, 170, 205), rgb(255, 215, 230)), rate = 8,
		lifetime = NumberRange.new(8, 11), speed = NumberRange.new(2, 3), size = NumberSequence.new(0.5),
		transparency = Kit.fade(0.05, 0.2), direction = Enum.NormalId.Bottom, acceleration = Vector3.new(1.5, -0.8, 0),
		spread = Vector2.new(30, 30), rotSpeed = NumberRange.new(-120, 120),
	})
end

return Spirit
