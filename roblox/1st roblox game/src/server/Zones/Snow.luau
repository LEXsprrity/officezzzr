-- 5. Snow Peaks: a white floor, pale blue-grey ice walls under a snow cap with icicles:
--   * stepped ice cliffs against both walls: ice blocks in terraces with snow on every top, icicles under
--     the ledges and a frozen waterfall down the bigger one
--   * a frozen pond with an ice-fishing hole, a snowman beside it
--   * an igloo
--   * snowy pines in groups, glowing ice crystals, snow drifts
--   * snowfall
local Assets = require(script.Parent.Parent:WaitForChild("Assets"))
local Props = require(script.Parent.Parent:WaitForChild("Props"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local rgb, at, box = Kit.rgb, Kit.at, Kit.box
local block = Props.block
local GROUND, HALF_W, H = Kit.GROUND, Kit.HALF_W, Kit.H

local Snow = {}
Snow.floorLight = rgb(214, 232, 252)
Snow.wallLight = rgb(168, 200, 226)
Snow.cap = rgb(252, 253, 255)

local SNOW = rgb(252, 253, 255)
local ICE = { rgb(170, 214, 240), rgb(196, 228, 250), rgb(150, 198, 232) }
local ICE_GLOW = rgb(150, 235, 255)
local PINE = rgb(40, 150, 90)
local PINE_DARK = rgb(30, 124, 78)
local TRUNK = rgb(122, 84, 52)

-- A stepped ice cliff in frame `f`, `w` wide and up to `h` tall: a row of tall ice columns along the wall
-- (tallest in the middle, a jagged skyline), a lower row stepping out in front of it and a few low blocks in
-- front of that, snow on every top and icicles under the front edges. With `notch` (a u), a frozen waterfall
-- runs down the face there into a frozen pool, and the rows in front leave it clear.
local function iceCliff(F: Instance, f: Kit.Frame, w: number, h: number, rng: Random, notch: number?)
	local half = w / 2
	local tops: { Kit.Top } = {}
	local function piece(u0: number, u1: number, top: number, v0: number, v1: number, color: Color3)
		box(F, "IceCliff", f, u0, u1, 0, top, v0, v1, color)
		table.insert(tops, { u0 = u0, u1 = u1, v0 = v0, v1 = v1, top = top })
	end
	local function clear(u0: number, u1: number): boolean
		return notch == nil or u1 < notch - 4 or u0 > notch + 4
	end
	-- the back row against the wall
	local u, i = -half, 0
	while u < half - 1 do
		i += 1
		local bw = math.min(rng:NextNumber(4.5, 8), half - u)
		local k = 1 - math.abs(u + bw / 2) / half
		piece(u, u + bw, h * (0.42 + 0.58 * k) * rng:NextNumber(0.85, 1.05), -0.6 - i * 0.013, rng:NextNumber(6, 9.5), ICE[i % 3 + 1])
		u += bw
	end
	-- the middle row, lower, stepping out
	u, i = -half + rng:NextNumber(1, 3), 0
	while u < half - 4 do
		i += 1
		local bw = math.min(rng:NextNumber(5, 9), half - 1 - u)
		if clear(u, u + bw) and rng:NextNumber() < 0.85 then
			local k = 1 - math.abs(u + bw / 2) / half
			piece(u, u + bw, h * (0.18 + 0.3 * k) * rng:NextNumber(0.8, 1.1), 1.5 + i * 0.011, rng:NextNumber(11, 15), ICE[(i + 1) % 3 + 1])
		end
		u += bw + rng:NextNumber(0, 1.5)
	end
	-- a few low blocks in front
	for j = 1, 4 do
		local bu = rng:NextNumber(-half + 3, half - 6)
		local bw = rng:NextNumber(3, 6)
		if clear(bu, bu + bw) then
			piece(bu, bu + bw, rng:NextNumber(2, 5), 10 + j * 0.017, rng:NextNumber(16, 20), ICE[j % 3 + 1])
		end
	end
	for n, t in tops do
		-- snow on every top, inset a little and spilling over the front
		box(F, "CliffSnow", f, t.u0 + 0.35, t.u1 - 0.35, t.top - 0.3, t.top + 0.7 + n * 0.007, t.v0 + 0.3, t.v1 + 0.35, SNOW)
		-- icicles under the front edge
		local count = math.max(1, math.floor((t.u1 - t.u0) / 3))
		for j = 1, count do
			if rng:NextNumber() < 0.6 then
				local iu = t.u0 + (j - 0.5) * (t.u1 - t.u0) / count + rng:NextNumber(-0.4, 0.4)
				local len = rng:NextNumber(1.4, 3.2)
				block(F, "Icicle", Vector3.new(0.7, len, 0.7) * f.scale, Kit.cf(f, iu, t.top - 0.3 - len / 2, t.v1 + 0.2) * CFrame.Angles(0, math.rad(45), 0), ICE[2])
			end
		end
	end
	if notch then -- the frozen fall down the back column there, into a frozen pool
		local col: Kit.Top? = nil
		for _, t in tops do
			if t.u0 <= notch - 2.6 and t.u1 >= notch + 2.6 and t.v0 < 0 then
				col = t
			end
		end
		if col then
			box(F, "FrozenFall", f, notch - 2.6, notch + 2.5, 0, col.top + 0.2, col.v1, col.v1 + 0.9, rgb(214, 244, 255))
			box(F, "FrozenFall", f, notch - 1.6, notch + 1.7, 0, col.top + 0.1, col.v1 + 0.9, col.v1 + 1.4, SNOW)
			local foot = Kit.p(f, notch, 0, col.v1 + 6)
			Kit.pool(F, "FrozenPool", Vector3.new(math.round(foot.X), GROUND, math.round(foot.Z)), 12 * f.scale, 8 * f.scale, rng,
				rgb(200, 236, 255), Enum.Material.Plastic, 0.22)
		end
	end
end

-- A snowy pine: a trunk and three square tiers turned alternately, each with snow on top, a snow tip.
local function pine(F: Instance, p: Vector3, s: number, rng: Random)
	local spin = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi / 2), 0)
	block(F, "PineTrunk", Vector3.new(2 * s, 4 * s, 2 * s), spin * CFrame.new(0, 2 * s, 0), TRUNK)
	for i = 0, 2 do
		local w = (12 - i * 3.2) * s
		local th = 3.6 * s
		local y = (5 + i * 3.4) * s
		local turn = CFrame.Angles(0, if i % 2 == 0 then 0 else math.rad(45), 0)
		block(F, "PineTier", Vector3.new(w, th, w), spin * CFrame.new(0, y, 0) * turn, if i % 2 == 0 then PINE else PINE_DARK)
		block(F, "PineSnow", Vector3.new(w * 0.72, 0.7 * s, w * 0.72), spin * CFrame.new(0, y + th / 2 + 0.25 * s, 0) * turn, SNOW)
	end
	block(F, "PineSnow", Vector3.new(2.6 * s, 2 * s, 2.6 * s), spin * CFrame.new(0, 13.6 * s, 0) * CFrame.Angles(0, math.rad(22), 0), SNOW)
end

-- A snowman of three stacked snow blocks, looking toward -X (the players coming from the base): coal eyes
-- and buttons, a carrot nose, a top hat, a red scarf and stick arms.
local function snowman(F: Instance, p: Vector3, s: number)
	local cf = Assets.facing(p, -Vector3.xAxis)
	local function b(name: string, size: Vector3, offset: CFrame, color: Color3)
		block(F, name, size * s, cf * CFrame.new(offset.Position * s) * offset.Rotation, color)
	end
	b("Snowman", Vector3.new(6, 5, 6), CFrame.new(0, 2.5, 0), SNOW)
	b("Snowman", Vector3.new(4.4, 4, 4.4), CFrame.new(0, 6.7, 0), SNOW)
	b("Snowman", Vector3.new(3.4, 3.2, 3.4), CFrame.new(0, 10.1, 0), SNOW)
	for _, x in { -0.75, 0.75 } do
		b("Coal", Vector3.new(0.55, 0.55, 0.3), CFrame.new(x, 10.7, -1.8), rgb(30, 30, 35))
	end
	for i = 1, 3 do
		b("Coal", Vector3.new(0.6, 0.6, 0.3), CFrame.new(0, 5.6 + i * 0.95, -2.3), rgb(30, 30, 35))
	end
	b("Carrot", Vector3.new(0.6, 0.6, 2), CFrame.new(0, 10.05, -2.6), rgb(255, 140, 40))
	b("Hat", Vector3.new(4, 0.5, 4), CFrame.new(0, 11.95, 0), rgb(30, 30, 40))
	b("Hat", Vector3.new(2.6, 2.4, 2.6), CFrame.new(0, 13.35, 0), rgb(30, 30, 40))
	b("Hat", Vector3.new(2.7, 0.5, 2.7), CFrame.new(0, 12.5, 0), rgb(220, 40, 50))
	b("Scarf", Vector3.new(4.6, 0.9, 4.6), CFrame.new(0, 8.75, 0), rgb(230, 50, 60))
	b("Scarf", Vector3.new(0.9, 2.6, 0.5), CFrame.new(1.3, 7.6, -2.4) * CFrame.Angles(0, 0, 0.15), rgb(230, 50, 60))
	for _, side in { -1, 1 } do
		b("Stick", Vector3.new(4.2, 0.45, 0.45), CFrame.new(side * 3.6, 7.9, 0) * CFrame.Angles(0, 0, side * 0.45), rgb(110, 76, 50))
	end
end

-- An igloo in frame `f`: a dome of stacked snow-block rings shrinking upward, and an entrance tunnel.
local function igloo(F: Instance, f: Kit.Frame)
	local rings = { { 9, 0, 3.2 }, { 8.2, 2.8, 5.8 }, { 6.6, 5.4, 8.1 }, { 4.4, 7.7, 9.8 } }
	for i, r in rings do
		local half, y0, y1 = r[1], r[2], r[3]
		box(F, "Igloo", f, -half, half, y0, y1 + i * 0.01, 10 - half * 0.82, 10 + half * 0.82, if i % 2 == 0 then ICE[2] else SNOW)
		box(F, "Igloo", f, -half * 0.82, half * 0.82, y0 + 0.2, y1 + 0.13 + i * 0.01, 10 - half, 10 + half, if i % 2 == 0 then SNOW else ICE[2])
	end
	box(F, "Igloo", f, -2.6, 2.6, 0, 4.6, 16.5, 21.8, SNOW)
	box(F, "IglooDoor", f, -1.5, 1.5, 0, 3.4, 21.8, 22.1, rgb(60, 90, 130))
end

function Snow.build(c: Kit.Ctx)
	local F = c.folder
	Kit.floor(c, Snow)
	Kit.walls(c, Snow)

	-- icicles under the snow cap, one per 45 studs on each wall
	local icicles = math.max(4, math.round(c.len / 45))
	local ic = Kit.rand(c, "icicles")
	for i = 1, icicles do
		for _, s in { -1, 1 } do
			local len = ic:NextNumber(4, 8)
			block(F, "Icicle", Vector3.new(1.2, len, 1.2), CFrame.new(at(c, (i - 0.5) / icicles) + ic:NextNumber(-6, 6), GROUND + H - len / 2, s * (HALF_W - 0.8)) * CFrame.Angles(0, math.rad(45), 0), ICE[2])
		end
	end

	-- the big ice cliff on the left near the entrance, a frozen waterfall down it; a lower one on the right
	local cliffFrame = Kit.wallFrame(at(c, 0.17), -1, 1.5)
	local cliffRng = Kit.rand(c, "cliff1")
	Assets.swap("Snow_Cliff", F, Kit.facing(cliffFrame), function(into)
		iceCliff(into, cliffFrame, 44, 26, cliffRng, 1)
	end)
	local cliff2 = Kit.wallFrame(at(c, 0.6), 1, 1.35)
	local cliff2Rng = Kit.rand(c, "cliff2")
	Assets.swap("Snow_Cliff", F, Kit.facing(cliff2), function(into)
		iceCliff(into, cliff2, 36, 20, cliff2Rng)
	end)

	-- the frozen pond on the right with its fishing hole and a snowman watching it
	local px = at(c, 0.3)
	Kit.pond(F, Vector3.new(px, GROUND, 66), 30, 0, Kit.ICE_POND)
	block(F, "FishingHole", Vector3.new(3.4, 0.16, 3.4), CFrame.new(px + 4, GROUND - Kit.POND_SINK + 0.06, 64), rgb(40, 80, 140)).CastShadow = false
	block(F, "FishingRod", Vector3.new(0.3, 0.3, 6), CFrame.new(px + 6.2, GROUND + 1.2, 61.5) * CFrame.Angles(math.rad(-25), math.rad(30), 0), rgb(130, 90, 56))
	local snowmanAt = Vector3.new(px + 22, GROUND, 58)
	Assets.swap("Snow_Snowman", F, Assets.facing(snowmanAt, -Vector3.xAxis), function(into)
		snowman(into, snowmanAt, 1)
	end)
	local snowman2 = Vector3.new(at(c, 0.74), GROUND, -62)
	Assets.swap("Snow_Snowman", F, Assets.facing(snowman2, -Vector3.xAxis), function(into)
		snowman(into, snowman2, 0.85)
	end)

	-- the igloo on the right, near the end
	local iglooFrame = Kit.wallFrame(at(c, 0.86), 1, 1.3)
	Assets.swap("Snow_Igloo", F, Kit.facing(iglooFrame), function(into)
		igloo(into, iglooFrame)
	end)

	-- pines in little groups along both walls
	for i, q in { { 0.04, -1, 1.6 }, { 0.36, -1, 1.9 }, { 0.42, -1, 1.4 }, { 0.62, -1, 1.7 }, { 0.08, 1, 1.8 }, { 0.14, 1, 1.3 },
		{ 0.46, 1, 1.85 }, { 0.75, 1, 1.6 }, { 0.98, 1, 1.8 } } do
		local rng = Kit.rand(c, "pine" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-4, 4), GROUND, q[2] * rng:NextNumber(80, 87))
		Assets.swap("Snow_Pine", F, Assets.spin(p), function(into)
			pine(into, p, q[3], rng)
		end)
	end
	-- glowing ice crystals
	for i, q in { { 0.3, -1 }, { 0.52, 1 }, { 0.7, -1 }, { 0.93, 1 } } do
		local rng = Kit.rand(c, "crystal" .. i)
		local p = Vector3.new(at(c, q[1]) + rng:NextNumber(-4, 4), GROUND, q[2] * rng:NextNumber(68, 76))
		Assets.swap("Snow_Crystal", F, Assets.spin(p), function(into)
			Kit.crystals(into, "IceCrystal", p, rng, ICE_GLOW, ICE[3], 5, rng:NextNumber(8, 12), 2)
		end)
	end
	-- snow drifts against the walls
	for i, q in { { 0.25, -1, 26 }, { 0.5, 1, 22 }, { 0.8, -1, 18 } } do
		local rng = Kit.rand(c, "drift" .. i)
		local x, z = at(c, q[1]), q[2] * 90
		for j = 0, 2 do
			local l = q[3] * (1 - j * 0.3)
			block(F, "SnowDrift", Vector3.new(l, 1.3 + j * 0.06, 9 - j * 2.4), CFrame.new(x + rng:NextNumber(-2, 2), GROUND + j * 1.2 + 0.55, z - q[2] * j * 0.6), if j == 1 then rgb(236, 244, 255) else SNOW)
		end
	end

	Kit.ambience(c, 200, 48, 2, { -- snowfall
		color = rgb(255, 255, 255), rate = 16, lifetime = NumberRange.new(8, 11), speed = NumberRange.new(3, 5),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.3) }),
		direction = Enum.NormalId.Bottom, acceleration = Vector3.new(1, -0.5, 0), spread = Vector2.new(15, 15),
		rotSpeed = NumberRange.new(-60, 60), lightEmission = 0.3,
	})
end

return Snow
