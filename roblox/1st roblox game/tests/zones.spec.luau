-- The corridor's zones (ZoneThemes, Zones/*): every zone's set pieces stand (clear of its nest), everything
-- is the classic studded plastic of the floor and walls, Neon only where something glows (lava, crystals,
-- lamps), no two faces anywhere z-fight, the walls are a darker shade of each zone's ground and unlike any
-- other zone's, the end of the corridor shows from the spawn, and parts, emitters and lights stay in budget.
local H = require("./harness")
local roblox = require("@lune/roblox")

local Config = H.shared("Config")
local WorldBuilder = H.server("WorldBuilder")
local ZoneThemes = H.server("ZoneThemes")
local Assets = H.server("Assets")
local Enum = roblox.Enum

local GROUND = Config.GROUND_Y

-- The map these tests look at, built when the first one runs (the specs before them build and load maps of
-- their own, each replacing Workspace.World).
local built: any = nil
local function corridor(): any
	if not built or not built.Parent then
		WorldBuilder.build()
		built = H.workspace:FindFirstChild("World")
	end
	return built.Corridor
end

local function zoneFolder(k: number): any
	return corridor():FindFirstChild(string.format("%d_%s", k, Config.ZONES[k].id))
end

local function parts(root: any): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- What a zone is built of besides its props: the floor and its tiles, the walls, their checker and cap,
-- the Spirit Garden's roof, the pond water, the nest and the Speed plank.
local STRUCTURE = { Floor = true, FloorTile = true, ZoneEdge = true, Wall = true, WallTile = true, WallCap = true,
	Roof = true, RoofTile = true, RoofTrim = true, Pond = true, PondTile = true, Ice = true, IceTile = true }
local function isProp(p: any, id: string): boolean
	return not STRUCTURE[p.Name] and p.Transparency < 1 and not p:FindFirstAncestor("Nest_" .. id) and not p:FindFirstAncestor("SpeedSign")
end

----------------------------------------------------------------------------------------------------
-- Set pieces
----------------------------------------------------------------------------------------------------
-- Each zone's set pieces (by asset slot, how many at least), all clear of the nest's corner (pruneNest
-- would remove one that reached into it, so each has to be found standing).
local SET_PIECES = {
	Meadow = { Meadow_Tree = 3, Meadow_FlowerBed = 1, Meadow_Mushroom = 1, Meadow_Bush = 4, Meadow_Flower = 6 },
	Desert = { Desert_Pyramid = 1, Desert_Ruins = 1, Desert_Palm = 3, Desert_Skull = 1, Desert_Cactus = 3, Desert_Tumbleweed = 3 },
	Jungle = { Jungle_Waterfall = 1, Jungle_Ruins = 1, Jungle_Tree = 6, Jungle_Bamboo = 4, Jungle_Fern = 6, Jungle_Log = 1 },
	Lava = { Lava_Volcano = 1, Lava_Terraces = 1, Lava_Basalt = 3, Lava_DeadTree = 6, Lava_Rock = 6 },
	Snow = { Snow_Cliff = 2, Snow_Igloo = 1, Snow_Snowman = 2, Snow_Pine = 8, Snow_Crystal = 4 },
	Space = { Space_UFO = 1, Space_Crater = 3, Space_Rocket = 1, Space_Crystal = 5, Space_Planet = 4, Space_Asteroid = 6 },
	Spirit = { Spirit_Shrine = 2, Spirit_CherryTree = 7, Spirit_Lantern = 8, Spirit_Bamboo = 4 },
}

H.test("zones: every zone has its set pieces, all standing clear of its nest", function()
	for k, zone in Config.ZONES do
		local folder = zoneFolder(k)
		local found = {}
		for _, d in folder:GetDescendants() do
			local slot = d:IsA("Model") and d:GetAttribute("AssetSlot")
			if slot then
				found[slot] = (found[slot] or 0) + 1
			end
		end
		for slot, n in SET_PIECES[zone.id] do
			H.ok((found[slot] or 0) >= n, `{zone.id}: {found[slot] or 0} {slot}, want {n} (one pruned from the nest's corner?)`)
		end
		-- and nothing of the zone's own stands in the nest's corner (the walls, the floor and what hangs on
		-- the walls aside)
		local x0, x1, z0, z1 = ZoneThemes.nestKeepOut(k)
		local right = Config.nestSide(k) > 0 -- (the Meadow's nest is on the right: Config.NEST_RIGHT)
		for _, child in folder:GetChildren() do
			if (child:IsA("Model") or child:IsA("BasePart")) and child.Name ~= "Nest_" .. zone.id and child.Name ~= "SpeedSign" and not STRUCTURE[child.Name]
				and child.Name ~= "Ambience" and child.Name ~= "Vine" and child.Name ~= "VineLeaf" and child.Name ~= "Icicle" then
				local lo, hi = Assets.bounds(child)
				if lo and hi and lo.Y < GROUND + Config.WALL_HEIGHT then
					H.ok(not (lo.X < x1 and hi.X > x0 and (if right then hi.Z > z0 else lo.Z < z1)), `{zone.id}: {child.Name} reaches into the nest's corner`)
				end
			end
		end
	end
end)

H.test("zones: the Lava Fields' altar has real fire (flames, embers, smoke and a light) and lava running down it", function()
	local lava = zoneFolder(4)
	local altar = nil
	for _, d in lava:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("AssetSlot") == "Lava_Volcano" then
			altar = d
		end
	end
	H.ok(altar ~= nil, "the altar")
	local textures, light, stone, flow = {}, false, 0, 0
	for _, d in altar:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			textures[d.Texture] = true
		elseif d:IsA("PointLight") then
			light = true
		elseif d:IsA("BasePart") and d.Transparency < 1 then
			if d.Material == Enum.Material.Neon then
				flow += 1
			else
				stone += 1
			end
		end
	end
	H.ok(textures["rbxasset://textures/particles/fire_main.dds"] and textures["rbxasset://textures/particles/fire_sparks_main.dds"]
		and textures["rbxasset://textures/particles/smoke_main.dds"], "flames, embers and smoke")
	H.ok(light, "the fire lights it up")
	H.ok(stone >= 15, `a stepped altar of many blocks ({stone})`)
	H.ok(flow >= 8, `a jagged channel of lava down its steps ({flow} pieces)`)
	-- the lava pools on the floor are ragged (several rows), never one strip
	local pools = 0
	for _, d in lava:GetChildren() do
		if d.Name == "LavaPool" then
			pools += 1
		end
	end
	H.ok(pools >= 20, `lava pooling on the floor in rows ({pools})`)
end)

----------------------------------------------------------------------------------------------------
-- Materials
----------------------------------------------------------------------------------------------------
-- Glowing things: lava, glowing goo, crystals, lamps and lights. Nothing else is Neon.
local GLOWS = {
	LavaPool = true, LavaHot = true, AltarLava = true, TerraceLava = true, LavaFall = true, VentLava = true,
	CraterGoo = true, GooHot = true, Crystal = true, IceCrystal = true, AsteroidCrystal = true, AlienBulb = true, UFOLight = true,
	LanternLight = true, WallLanternLight = true,
}
-- Small flat bits that stay smooth: the pond's pads and flowers, stepping stones and floor stars.
local SMOOTH = { LilyPad = true, LilyCut = true, LilyPetal = true, LilyHeart = true, SteppingStone = true, FloorStar = true,
	RoofTile = true, RoofTrim = true }

H.test("zones: every prop is studded plastic like the floor and walls; Neon only on lava, crystals and lamps", function()
	for k, zone in Config.ZONES do
		local studded, total = 0, 0
		for _, p in parts(zoneFolder(k)) do
			if not isProp(p, zone.id) then
				continue
			end
			if p.Material == Enum.Material.Neon then
				H.ok(GLOWS[p.Name], `{zone.id}: {p:GetFullName()} glows, but isn't lava, a crystal or a lamp`)
			elseif not SMOOTH[p.Name] and p:IsA("Part") and p.Shape == Enum.PartType.Block and not p:FindFirstChildWhichIsA("SpecialMesh") then
				total += 1
				local ok = p.Material == Enum.Material.Plastic and p.TopSurface == Enum.SurfaceType.Studs
				if ok then
					studded += 1
				else
					error(`{zone.id}: {p:GetFullName()} isn't studded plastic ({p.Material}, top {p.TopSurface})`)
				end
				-- studs on the sides too (Props.block), unless it's a thin overlay
				if math.min(p.Size.X, p.Size.Z) > 0.5 and p.Size.Y > 0.5 then
					H.ok(p.FrontSurface == Enum.SurfaceType.Studs and p.LeftSurface == Enum.SurfaceType.Studs, `{zone.id}: {p:GetFullName()} studded on its sides`)
				end
			end
		end
		H.ok(total > 50 and studded == total, `{zone.id}: {studded}/{total} props studded`)
	end
end)

----------------------------------------------------------------------------------------------------
-- No z-fighting, at any height, on any face
----------------------------------------------------------------------------------------------------
type Face = { part: any, nx: number, ny: number, nz: number, d: number, poly: { { number } }, e1: any, e2: any }

local function cross2(o: { number }, a: { number }, b: { number }): number
	return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
end
local function area(poly: { { number } }): number
	local s = 0
	for i = 1, #poly do
		local a, b = poly[i], poly[i % #poly + 1]
		s += a[1] * b[2] - b[1] * a[2]
	end
	return s / 2
end
local function ccw(poly: { { number } }): { { number } }
	if area(poly) >= 0 then
		return poly
	end
	local out = {}
	for i = #poly, 1, -1 do
		table.insert(out, poly[i])
	end
	return out
end
-- The area two convex polygons share (Sutherland-Hodgman clipping).
local function shared(p: { { number } }, q: { { number } }): number
	local out = ccw(p)
	q = ccw(q)
	for i = 1, #q do
		if #out == 0 then
			return 0
		end
		local a, b = q[i], q[i % #q + 1]
		local input = out
		out = {}
		for j = 1, #input do
			local cur, prev = input[j], input[(j - 2) % #input + 1]
			local inCur, inPrev = cross2(a, b, cur) >= -1e-9, cross2(a, b, prev) >= -1e-9
			if inCur ~= inPrev then
				local d1, d2 = cross2(a, b, prev), cross2(a, b, cur)
				local t = d1 / (d1 - d2)
				table.insert(out, { prev[1] + (cur[1] - prev[1]) * t, prev[2] + (cur[2] - prev[2]) * t })
			end
			if inCur then
				table.insert(out, cur)
			end
		end
	end
	return if #out >= 3 then math.abs(area(out)) else 0
end

-- Every face of every visible block in the corridor that could show (not resting on or under the floor).
local function faces(root: any): { [string]: { Face } }
	local buckets: { [string]: { Face } } = {}
	for _, p in root:GetDescendants() do
		if not (p:IsA("Part") and p.Shape == Enum.PartType.Block and p.Transparency < 1 and not p:FindFirstChildWhichIsA("SpecialMesh")) then
			continue
		end
		local cf, s = p.CFrame, p.Size
		local pos = cf.Position
		local axes = { cf.RightVector, cf.UpVector, -cf.LookVector }
		local half = { s.X / 2, s.Y / 2, s.Z / 2 }
		for i = 1, 3 do
			local j, k = i % 3 + 1, (i + 1) % 3 + 1
			for _, sign in { 1, -1 } do
				local n = axes[i] * sign
				local center = pos + n * half[i]
				local a, b = axes[j] * half[j], axes[k] * half[k]
				local top = center.Y + math.abs(a.Y) + math.abs(b.Y)
				local resting = n.Y < -0.99 and center.Y <= GROUND + 0.01
				if top > GROUND + 1e-3 and not resting and half[j] * half[k] > 0.0025 then
					local nx, ny, nz = math.round(n.X * 1000), math.round(n.Y * 1000), math.round(n.Z * 1000)
					-- a basis in the plane, the same for every face with this normal
					local nn = roblox.Vector3.new(nx, ny, nz).Unit
					local ref = if math.abs(nn.Y) < 0.9 then roblox.Vector3.yAxis else roblox.Vector3.xAxis
					local e1 = nn:Cross(ref).Unit
					local e2 = nn:Cross(e1)
					local poly = {}
					for _, q in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
						local v = center + a * q[1] + b * q[2]
						table.insert(poly, { v:Dot(e1), v:Dot(e2) })
					end
					local d = nn:Dot(center)
					local key = `{nx},{ny},{nz},{math.floor(d * 20)}`
					buckets[key] = buckets[key] or {}
					table.insert(buckets[key], { part = p, nx = nx, ny = ny, nz = nz, d = d, poly = poly, e1 = e1, e2 = e2 })
				end
			end
		end
	end
	return buckets
end

H.test("zones: no two visible faces anywhere in the corridor lie on one plane overlapping (no z-fighting)", function()
	local buckets = faces(corridor())
	local bad = {}
	for key, list in buckets do
		local nx, ny, nz, q = string.match(key, "^(-?%d+),(-?%d+),(-?%d+),(-?%d+)$")
		-- this bucket and the next one up (a plane right on a bucket's edge)
		local others = buckets[`{nx},{ny},{nz},{tonumber(q) + 1}`] or {}
		for i, f in list do
			local function check(g: Face)
				if g.part ~= f.part and math.abs(g.d - f.d) < 0.004 then
					local overlap = shared(f.poly, g.poly)
					if overlap > 0.02 then
						table.insert(bad, `{f.part:GetFullName()} and {g.part:GetFullName()} ({string.format("%.3f", overlap)} studs²)`)
					end
				end
			end
			for j = i + 1, #list do
				check(list[j])
			end
			for _, g in others do
				check(g)
			end
		end
	end
	table.sort(bad)
	H.ok(#bad == 0, `{#bad} z-fighting face pairs:\n  ` .. table.concat(bad, "\n  ", 1, math.min(#bad, 30)))
end)

----------------------------------------------------------------------------------------------------
-- Walls, caps and the view down the corridor
----------------------------------------------------------------------------------------------------
local function luminance(c: any): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

H.test("zones: each zone's walls are a darker shade of its ground, unlike every other zone's, under a bright cap", function()
	for k, zone in Config.ZONES do
		H.ok(luminance(zone.wall) < luminance(zone.floor) - 0.05, `{zone.id}: the wall is darker than the floor`)
		local theme = ZoneThemes.theme(k)
		H.ok(luminance(theme.wallLight) < luminance(zone.floor), `{zone.id}: the wall's checker is darker than the floor too`)
		local _, _, v = theme.cap:ToHSV()
		H.ok(v >= 0.7, `{zone.id}: a bright cap (reads at night) ({theme.cap})`)
		for j = k + 1, #Config.ZONES do
			local other = Config.ZONES[j].wall
			local dist = math.abs(zone.wall.R - other.R) + math.abs(zone.wall.G - other.G) + math.abs(zone.wall.B - other.B)
			H.ok(dist > 0.15, `{zone.id} and {Config.ZONES[j].id} walls look alike ({dist})`)
		end
	end
end)

H.test("zones: the end of the corridor shows from the spawn: a pale back wall with a big waterfall and glowing lanterns", function()
	local spirit = zoneFolder(#Config.ZONES)
	local back, lanterns, fall = nil, 0, 0
	for _, p in spirit:GetDescendants() do
		if p:IsA("BasePart") then
			if p.Name == "Wall" and p.Size.Z >= Config.CORRIDOR_WIDTH and p.CFrame.Position.X >= Config.END_X then
				back = p
			elseif p.Name == "WallLanternLight" and p.Material == Enum.Material.Neon then
				lanterns += 1
			elseif (p.Name == "Waterfall" or p.Name == "WaterfallCore") and p.CFrame.Position.X > Config.END_X - 5 then
				fall = math.max(fall, p.Size.Y)
			end
		end
	end
	H.ok(back and luminance(back.Color) > 0.7, "a pale back wall")
	H.ok(lanterns >= 4, `lanterns glowing on it ({lanterns})`)
	H.ok(fall >= Config.WALL_HEIGHT * 0.8, `a waterfall down it ({fall})`)
end)

----------------------------------------------------------------------------------------------------
-- Budgets
----------------------------------------------------------------------------------------------------
-- Prop parts per zone (everything but the floor, walls, roof, water, nest and plank): rich zones, but
-- bounded (mobile). The corridor as a whole stays under world.spec's 6,000 parts.
local PROP_BUDGET = { Meadow = 300, Desert = 380, Jungle = 560, Lava = 480, Snow = 480, Space = 420, Spirit = 520 }

H.test("zones: props, particle emitters and lights stay within each zone's budget", function()
	local lines = {}
	for k, zone in Config.ZONES do
		local props, emitters, lights, rate = 0, 0, 0, 0
		for _, d in zoneFolder(k):GetDescendants() do
			if d:IsA("BasePart") and isProp(d, zone.id) then
				props += 1
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
				rate += d.Rate * d.Lifetime.Max
			elseif d:IsA("PointLight") then
				lights += 1
			end
		end
		table.insert(lines, `{zone.id} {props} props, {emitters} emitters (~{math.round(rate)} particles), {lights} lights`)
		H.ok(props <= PROP_BUDGET[zone.id], `{zone.id}: {props} prop parts (budget {PROP_BUDGET[zone.id]})`)
		H.ok(props >= PROP_BUDGET[zone.id] * 0.4, `{zone.id}: only {props} prop parts: a rich zone, please`)
		H.ok(emitters <= 16, `{zone.id}: {emitters} particle emitters`)
		H.ok(rate <= 450, `{zone.id}: ~{rate} particles alive at once`)
		H.ok(lights <= 14, `{zone.id}: {lights} lights`)
	end
	print("        " .. table.concat(lines, "\n        "))
end)

return nil
