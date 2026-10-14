-- World generation: builds the real map with Lune's Roblox instances (every property is checked
-- against the reflection database), then checks the layout contract and the performance budget.
local H = require("./harness")
local Layout = require("./plot_layout")

local Config = H.shared("Config")
local Treadmill = H.shared("Treadmill")
local WorldBuilder = H.server("WorldBuilder")
local Vector3 = H.Vector3
local CFrame = require("@lune/roblox").CFrame
local Enum = require("@lune/roblox").Enum

local plots, nests = WorldBuilder.build()
local world = H.workspace:FindFirstChild("World")

local function parts(root: any): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

H.test("world: builds one plot per player slot and one nest per zone", function()
	H.ok(world ~= nil, "World folder parented to workspace")
	H.eq(#plots, Config.MAX_PLAYERS)
	H.eq(#nests, #Config.ZONES)
end)

H.test("world: plot layout contract (two dirt beds, a grass path, origin, spawn, the treadmill in front)", function()
	local Planting = H.shared("Planting")
	for i, plot in plots do
		local x, z = Config.spotXZ(Config.plotSpot(i))
		local side = math.sign(z)
		local center = Vector3.new(x, Config.GROUND_Y, z)
		H.ok((plot.center - center).Magnitude < 1e-3, "plot center")
		local toWalk = -side
		local half = Config.PLOT_SIZE / 2
		local entrance = center + Vector3.new(0, 0, toWalk * half)
		local function at(u: number, w: number, y: number)
			return entrance + Vector3.new(u, y, -toWalk * w)
		end
		-- the origin: the middle of its ground (level with the lawn), looking into the plot
		H.ok((plot.origin.Position - center).Magnitude < 1e-3, `plot {i} origin`)
		H.ok(plot.origin.LookVector:Dot(Vector3.new(0, 0, -toWalk)) > 0.999, `plot {i} origin looks into the plot`)
		-- two dirt beds, one each side of the path, as Planting.defaultBeds says
		H.eq(#plot.beds, 2, `plot {i} has two dirt beds`)
		for b, want in Planting.defaultBeds() do
			local bed = plot.beds[b]
			H.eq(bed:GetAttribute("BedIndex"), b)
			H.ok((bed.CFrame.Position - plot.origin:PointToWorldSpace(want.center)).Magnitude < 1e-3, `plot {i} bed {b} position`)
			H.ok((bed.Size - want.size).Magnitude < 1e-3, `plot {i} bed {b} size`)
			H.ok(bed.Material == Enum.Material.Plastic and bed.TopSurface == Enum.SurfaceType.Studs, `plot {i} bed {b} is studded dirt`)
			local rel = plot.origin:PointToObjectSpace(bed.CFrame.Position)
			H.ok(math.abs(rel.X) - bed.Size.X / 2 >= Config.PLOT_PATH_WIDTH / 2 - 1e-3, `plot {i} bed {b} leaves the middle path free`)
			H.ok(math.abs(rel.X) + bed.Size.X / 2 <= half - 1, `plot {i} bed {b} inside the fence`)
		end
		H.ok(plot.beds[1].CFrame.Position.X ~= plot.beds[2].CFrame.Position.X, "left and right")
		-- the grass path down the middle, from the entrance to the back fence, and the tile at the opening
		-- (a checker of PathTiles, level with the ground, cut round the entrance tile where they meet)
		local tile, pathArea, x0, x1, z0, z1 = nil, 0, math.huge, -math.huge, math.huge, -math.huge
		for _, d in plot.model:GetChildren() do
			if d.Name == "PathTile" then
				local p, s = d.CFrame.Position, d.Size
				pathArea += s.X * s.Z
				x0, x1 = math.min(x0, p.X - s.X / 2), math.max(x1, p.X + s.X / 2)
				z0, z1 = math.min(z0, p.Z - s.Z / 2), math.max(z1, p.Z + s.Z / 2)
				H.ok(math.abs(p.Y + s.Y / 2 - Config.GROUND_Y) < 1e-3, `plot {i} path tile level with the ground`)
			elseif d.Name == "EntranceTile" then
				tile = d
			end
		end
		H.ok(math.abs(x1 - x0 - Config.PLOT_PATH_WIDTH) < 1e-3 and math.abs(z1 - z0 - Config.PLOT_SIZE) < 1e-3, `plot {i} middle path`)
		H.ok(math.abs((x0 + x1) / 2 - center.X) < 1e-3, `plot {i} path down the middle`)
		H.ok(tile ~= nil and math.abs(pathArea + (tile.Size.X * tile.Size.Z) / 2 - Config.PLOT_PATH_WIDTH * Config.PLOT_SIZE) < 1e-2,
			`plot {i}: the path's tiles and the entrance tile's inner half cover the path exactly ({pathArea})`)
		H.ok(tile ~= nil and (Vector3.new(tile.CFrame.Position.X, 0, tile.CFrame.Position.Z) - Vector3.new(entrance.X, 0, entrance.Z)).Magnitude < 1e-3,
			`plot {i} entrance tile at the opening`)
		H.ok((plot.spawnCFrame.Position - at(0, 12, 4)).Magnitude < 1e-3, "spawn on the middle path")
		H.ok(not Planting.bedAt(plot.beds, plot.spawnCFrame.Position - Vector3.new(0, 3, 0)), "nobody spawns on a bed")
		-- The treadmill stands outside, in front of the plot. With a Treadmill model in assets/, the belt takes
		-- the model's belt: its running surface and its footprint, so it may shift a little along it (it runs
		-- straight out toward the walkway, along z).
		local beltDelta = plot.belt.CFrame.Position - at(15, -12, 1.1)
		H.ok(math.abs(beltDelta.X) < 0.5 and math.abs(beltDelta.Z) < 2 and beltDelta.Y > -1 and beltDelta.Y < 6, `belt position ({beltDelta})`)
		-- its front end (the runner's facing, Treadmill.FRONT) points at the middle walkway, not along it
		local front = plot.belt.CFrame:VectorToWorldSpace(Vector3.new(0, 0, Treadmill.FRONT))
		H.ok(front.Z * -math.sign(center.Z) > 0.999, `plot {i} treadmill faces the middle walkway ({front})`)
		H.ok(math.min(plot.belt.Size.X, plot.belt.Size.Z) <= 5 and math.max(plot.belt.Size.X, plot.belt.Size.Z) <= 10,
			`a character-sized belt ({plot.belt.Size})`)
		H.eq(plot.belt:GetAttribute("Role"), "TreadmillBelt")
		H.eq(plot.belt:GetAttribute("PlotIndex"), i)
		H.eq(plot.model.PrimaryPart.Name, "Floor")
		H.ok(plot.soil:IsA("Folder") and plot.plants:IsA("Folder"), "soil/plants folders")
		H.ok(plot.signLabel:IsA("TextLabel"), "sign label")
		H.ok(plot.model:FindFirstChild("TreadmillSign", true) == nil, "no \"TREADMILL\" sign over the treadmill")
	end
end)

H.test("world: nests against the left wall, pods on the floor right by the boss's right flank, nothing under them (centre, pods, guard home)", function()
	local halfW = Config.CORRIDOR_WIDTH / 2
	for k, nest in nests do
		local center = Config.nestCenter(k)
		H.ok((nest.center - center).Magnitude < 1e-3, "nest centre")
		-- all the way on the runner's left (-Z, walking +X from the base), the boss's flank by the wall
		H.ok(center.Z <= -(halfW - 20) and center.Z >= -(halfW - 15.5), `zone {k}: nest against the left wall ({center.Z})`)
		H.eq(Config.zoneAtX(center.X), k, `zone {k}: nest inside its zone`)
		H.eq(Config.zoneAtX(nest.guardHome.X), k, `zone {k}: the boss sleeps inside its zone`)
		H.eq(#nest.podCFrames, Config.PODS_PER_NEST)
		local xs, zs = {}, {}
		for i, cf in nest.podCFrames do
			local want = center + Config.podOffset(k, i)
			H.ok((cf.Position - want).Magnitude < 1e-3, "pod position")
			local rel = cf.Position - nest.guardHome
			-- right next to the boss, at its right (toward the middle): the 3-stud pod a few studs off its flank,
			-- along its body (its root at rel 0, facing the base)
			local off = rel.Z - 1.5 - Config.BOSS_REACH[Config.ZONES[k].id].side
			H.ok(off >= 0.5 and off <= 7, `zone {k} pod {i}: {off} studs off the boss's right flank ({rel})`)
			H.ok(rel.X >= -9 and rel.X <= 7, `zone {k} pod {i}: beside the boss, not ahead of it ({rel})`)
			H.near(cf.Position.Y - Config.GROUND_Y, 1.5, 1e-6, `zone {k} pod {i}: the 3-stud pod rests on the floor`)
			for j, other in nest.podCFrames do
				if j ~= i then
					H.ok((other.Position - cf.Position).Magnitude > 4, `zone {k}: pods {i} and {j} apart`)
				end
			end
			xs[rel.X] = true
			zs[rel.Z] = true
		end
		-- a loose scatter: no two pods share a row or a column (not a grid, not a line)
		local nx, nz = 0, 0
		for _ in xs do
			nx += 1
		end
		for _ in zs do
			nz += 1
		end
		H.ok(nx == Config.PODS_PER_NEST and nz == Config.PODS_PER_NEST, `zone {k}: pods scattered, not in a grid`)
		-- no mother plant, and nothing visible at all: no patch, ring or pebbles under the pods (owner requests)
		for _, d in nest.model:GetDescendants() do
			H.ok(not (d.Name == "MotherBulb" or d.Name == "Mound" or d.Name == "Stem" or d.Name == "Leaf"), `zone {k}: no mother plant ({d:GetFullName()})`)
			H.ok(not d:IsA("BasePart") or d.Transparency >= 1, `zone {k}: nothing drawn under the pods ({d:GetFullName()})`)
			H.ok(not d:IsA("Decal") and not d:IsA("ParticleEmitter"), `zone {k}: no ring decal or sparkles ({d:GetFullName()})`)
		end
		H.ok((nest.guardHome - (center + Vector3.new(Config.GUARD_HOME_OFFSET, 0, 0))).Magnitude < 1e-3, "guard home")
		H.eq(nest.model.PrimaryPart:GetAttribute("Role"), "NestCore")
	end
end)

H.test("world: the wall props make room for each nest (nothing stands in the boss or among the pods)", function()
	local ZoneThemes = H.server("ZoneThemes")
	local Assets = H.server("Assets")
	for k, zone in Config.ZONES do
		local x0, x1, z0, z1 = ZoneThemes.nestKeepOut(k)
		local home = Config.nestCenter(k) + Vector3.new(Config.GUARD_HOME_OFFSET, 0, 0)
		H.ok(x0 < home.X - 24 and x1 >= home.X + 24 and z0 <= -Config.CORRIDOR_WIDTH / 2, `{zone.id}: the corner holds the boss`)
		for i = 1, Config.PODS_PER_NEST do
			local p = Config.nestCenter(k) + Config.podOffset(k, i)
			H.ok(p.X - 2 > x0 and p.X + 2 < x1 and p.Z + 2 < z1, `{zone.id}: the corner holds pod {i}`)
		end
		local folder = world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id))
		for _, child in folder:GetChildren() do
			if child.Name == "Nest_" .. zone.id or child.Name == "SpeedSign" then
				continue
			end
			local lo, hi = Assets.bounds(child)
			if not lo or not hi or lo.Y > Config.GROUND_Y + Config.WALL_HEIGHT then
				continue -- invisible, or up in the sky
			end
			local inside = lo.X < x1 and hi.X > x0 and lo.Z < z1 and hi.Z > z0
			local alongWall = hi.Z <= -(Config.CORRIDOR_WIDTH / 2) + 0.1 -- the wall, its checker, cap and vines
			local structure = child.Name == "Floor" or child.Name == "FloorTile" or child.Name == "ZoneEdge" or child.Name == "Ambience"
				or child.Name == "RiverBank" or child.Name == "LavaRiver" or string.find(child.Name, "^Wall") or string.find(child.Name, "^Roof")
				or child.Name == "Icicle" or string.find(child.Name, "^Vine")
			H.ok(not inside or alongWall or structure, `{zone.id}: {child.Name} stands in the nest's corner ({lo} .. {hi})`)
			if child.Name == "Pond" or child.Name == "PondTile" then
				H.ok(not inside, `{zone.id}: a pond in the nest's corner`)
			end
		end
	end
end)

H.test("world: everything is anchored", function()
	for _, p in parts(world) do
		if not p.Anchored then
			error(`{p:GetFullName()} is not anchored`)
		end
	end
end)

-- Inside the corridor only the floor and walls (the Spirit Garden's back wall too) may collide, so props
-- never block runners or the guards' MoveTo line.
H.test("world: corridor props never collide (only floor/walls)", function()
	local allowed = { Floor = true, FloorTile = true, ZoneEdge = true, Wall = true } -- (the floor's level tiles are solid)
	local corridor = world:FindFirstChild("Corridor")
	for _, p in parts(corridor) do
		if p.CanCollide and not allowed[p.Name] then
			error(`{p:GetFullName()} collides`)
		end
	end
end)

H.test("world: part budget (corridor < 6k, whole map < 8k)", function()
	local corridor = world:FindFirstChild("Corridor")
	local total = 0
	local lines = {}
	for _, zoneFolder in corridor:GetChildren() do
		local n = #parts(zoneFolder)
		total += n
		table.insert(lines, `{zoneFolder.Name}={n}`)
	end
	table.sort(lines)
	local all = #parts(world)
	print(`        corridor parts: {total} ({table.concat(lines, ", ")}); whole map: {all}`)
	H.ok(total < 6000, `corridor has {total} parts`)
	H.ok(all < 8000, `map has {all} parts`)
end)

-- The base is kept plain so the plants stand out: the lawn, walls, plot fences and gameplay pieces only.
local function baseArea(): { any }
	local out = {}
	for _, child in world:GetChildren() do
		if child.Name ~= "Corridor" then
			table.insert(out, child)
		end
	end
	return out
end

H.test("world: the base is plain (no trees, bushes, flowers, lamps or rocks outside the corridor)", function()
	local banned = { Tree = true, BlossomTree = true, Bush = true, Flower = true, Lamp = true, Rock = true }
	for _, root in baseArea() do
		for _, d in root:GetDescendants() do
			if d:IsA("Model") and banned[d:GetAttribute("AssetSlot")] then
				error(`{d:GetFullName()} is a {d:GetAttribute("AssetSlot")} in the base`)
			end
			-- (a treadmill model's console screen may glow: that's no lamp)
			local tm = d:FindFirstAncestor("Treadmill")
			H.ok(not d:IsA("PointLight") or (tm and tm:GetAttribute("AssetSlot") == "Treadmill"), `{d:GetFullName()}: no lamps in the base`)
		end
	end
	for i, plot in plots do
		local posts = 0
		for _, d in plot.model:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("AssetSlot") == "FencePost" then
				posts += 1
			end
		end
		-- Plots behind the front column share their +X side and two corner posts with the plot in front.
		H.ok(posts >= 18 and posts <= 32, `plot {i} has a simple wooden fence ({posts} posts)`)
	end
end)

H.test("world: plots are compact and share one clean fence (no double fences, gates or FASTEST board)", function()
	local half = Config.PLOT_SIZE / 2
	-- Neighbouring plots touch, and the front plots sit near the corridor mouth.
	H.eq(Config.PLOT_SPACING_X, Config.PLOT_SIZE)
	H.ok(Config.CORRIDOR_START_X - (Config.PLOT_FIRST_X + half) <= 30, "the front plots are near the corridor mouth")
	local front = Config.PLOT_OFFSET_Z - half - Config.WALKWAY_WIDTH / 2
	H.ok(front >= 16 and front <= 30, `the plots are near the walkway, with room for the treadmill in front ({front})`)
	Layout.check(world, plots, "built map")
	Layout.plotsFullyFenced(world, plots, "built map")
	for i, plot in plots do
		-- the owner's sign hangs on the front fence beside the opening, facing the walkway
		local sign = plot.signLabel:FindFirstAncestorWhichIsA("BasePart")
		local side = if plot.center.Z > 0 then 1 else -1
		local entrance = plot.center - Vector3.new(0, 0, side * half)
		local p = sign.CFrame.Position
		H.ok(math.abs(p.Z - entrance.Z) < 2.5 and side * (entrance.Z - p.Z) > 0, `plot {i} sign on the fence, just outside it`)
		H.ok(math.abs(p.X - entrance.X) > 8 and math.abs(p.X - entrance.X) < 25 and p.Y > 1.5 and p.Y < 6, `plot {i} sign beside the opening, fence high`)
		H.ok(sign.CFrame.LookVector.Z * -side > 0.999, `plot {i} sign faces the walkway`)
		H.eq(plot.signLabel.Text, "🏠 Empty Plot")
		-- no dark panel (owner playtest): a light wooden plank with the name straight on it, nothing in front
		local h, s, v = sign.Color:ToHSV()
		H.ok(v > 0.7 and s < 0.7, `plot {i} sign is light wood ({sign.Color}, {h})`)
		local gui = plot.signLabel:FindFirstAncestorWhichIsA("SurfaceGui")
		H.ok(gui ~= nil and gui.Parent == sign and gui.Face == Enum.NormalId.Front, `plot {i} name painted on the plank's front`)
		H.ok(gui.MaxDistance > 0 and gui.MaxDistance <= 90, `plot {i} name reads only fairly close`)
		for _, d in plot.model:GetDescendants() do
			if d:IsA("BasePart") and d ~= sign and d.Transparency < 1 then
				local rel = sign.CFrame:PointToObjectSpace(d.CFrame.Position)
				H.ok(not (math.abs(rel.X) < sign.Size.X / 2 and math.abs(rel.Y) < sign.Size.Y / 2 and rel.Z < 0 and rel.Z > -1.5),
					`plot {i}: {d.Name} covers the name`)
			end
		end
	end
end)

H.test("world: no server script builds the old FASTEST HERE board", function()
	local fs = require("@lune/fs")
	for _, dir in { "src/server", "src/shared", "src/client" } do
		for _, entry in fs.readDir(dir) do
			if string.match(entry, "%.luau$") then
				local text = fs.readFile(dir .. "/" .. entry)
				H.ok(not string.find(text, "FASTEST HERE", 1, true), `{dir}/{entry} mentions the FASTEST HERE board`)
			end
		end
	end
end)

-- (1600 since the ground is level: every checker is both colours as tiles side by side, not light tiles
-- laid over a floor, ~300 more simple anchored blocks)
H.test("world: base part budget (plots, plaza, lawn and walls < 1600)", function()
	local n = 0
	for _, root in baseArea() do
		n += #parts(root)
	end
	print(`        base area parts: {n}`)
	H.ok(n < 1600, `the base area has {n} parts`)
end)

H.test("world: no zone gates, arches, threshold lines, zone name signs or STEAL A SEED sign anywhere", function()
	local banned = { GatePillar = true, GateBeam = true, GateCap = true, GateTie = true, GateTrim = true, GateStrut = true,
		PillarFoot = true, PillarTop = true, Threshold = true, Garland = true, PillarBush = true, PillarOrb = true,
		GateLeaves = true, GateCapEnd = true, GoldFinial = true, PaperLantern = true, OrbitRing = true, SnowCap = true,
		ToriiPillar = true, ToriiFoot = true, ToriiBeam = true, ToriiCap = true } -- (the owner removed the Spirit Garden's torii too)
	for _, d in world:GetDescendants() do
		H.ok(not banned[d.Name], `{d:GetFullName()}: a gate piece`)
		local slot = d:GetAttribute("AssetSlot")
		H.ok(not (slot and (string.match(slot, "^Arch_") or slot == "SpawnSign" or slot == "Spirit_Torii")), `{d:GetFullName()}: the {slot} slot`)
		H.ok(not string.match(d.Name, "^Arch_") and d.Name ~= "SpawnSign", `{d:GetFullName()}: an arch or the spawn sign`)
		if d:IsA("TextLabel") then
			local text = string.upper(d.Text)
			H.ok(not string.find(text, "STEAL A SEED", 1, true), `{d:GetFullName()} says "{d.Text}"`)
			H.ok(not string.find(text, "GUARDIAN", 1, true) and not string.find(text, "RECOMMENDED SPEED", 1, true), `{d:GetFullName()} is a zone sign`)
			for _, zone in Config.ZONES do
				H.ok(not string.find(text, string.upper(zone.name), 1, true), `{d:GetFullName()} names the {zone.name}`)
			end
		end
	end
	local Assets = H.server("Assets")
	for _, slot in Assets.SLOTS do
		H.ok(not string.match(slot, "^Arch_") and slot ~= "SpawnSign", `no {slot} asset slot`)
	end
end)

H.test("world: just in front of each sleeping boss a small wooden plank on a post says the zone's recommended Speed", function()
	local Format = H.shared("Format")
	for k, zone in Config.ZONES do
		local folder = world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id))
		H.ok(folder ~= nil, "zone folder " .. zone.id)
		local sign = folder:FindFirstChild("SpeedSign")
		H.ok(sign and sign:IsA("Model"), `{zone.id}: a SpeedSign`)
		local plank, post = sign:FindFirstChild("Plank"), sign:FindFirstChild("PlankPost")
		H.ok(plank and post, `{zone.id}: a plank on a post`)
		-- small and chunky, wooden orange/brown, studded, decoration only
		-- owner's reference: a ~6 x 3.5 board at about a player's chest height on a short thick post
		H.ok(plank.Size.X >= 5.5 and plank.Size.X <= 6.5 and plank.Size.Y >= 3 and plank.Size.Y <= 4 and plank.Size.Z >= 0.8, `{zone.id}: a small chunky plank ({plank.Size})`)
		local plankTop = plank.CFrame.Position.Y + plank.Size.Y / 2 - Config.GROUND_Y
		H.ok(plankTop >= 4.5 and plankTop <= 6, `{zone.id}: about chest height (top {plankTop} studs up)`)
		H.ok(post.Size.Y <= 2.5 and post.Size.X >= 1.2 and post.Size.Z >= 1.2, `{zone.id}: a short thick post ({post.Size})`)
		H.eq(plank:GetAttribute("Role"), "SpeedPlank", `{zone.id}: the plank is tagged for the client`)
		H.eq(plank:GetAttribute("ZoneIndex"), k, `{zone.id}: with its zone`)
		for _, p in { plank, post } do
			H.ok(p.Color.R > p.Color.G and p.Color.G > p.Color.B and p.Color.R > 0.6, `{zone.id}: {p.Name} is orange/brown wood`)
			H.ok(not p.CanCollide and p.Anchored, `{zone.id}: {p.Name} is decoration`)
		end
		H.eq(plank.FrontSurface, Enum.SurfaceType.Studs, `{zone.id}: studded`)
		H.ok(post.CFrame.Position.Y + post.Size.Y / 2 <= plank.CFrame.Position.Y - plank.Size.Y / 2 + 0.01, "the post holds the plank up")
		-- just in front of the sleeping boss (base side), a little to its left, a few studs from its nose,
		-- facing the players coming from the base (owner's reference)
		local home = Config.nestCenter(k) + Vector3.new(Config.GUARD_HOME_OFFSET, 0, 0)
		local nose = home.X - Config.BOSS_REACH[zone.id].front
		local flat = Vector3.new(plank.CFrame.Position.X, Config.GROUND_Y, plank.CFrame.Position.Z)
		H.ok(flat.X < nose - 1 and flat.X > nose - 6, `{zone.id}: a few studs in front of the boss's nose ({nose - flat.X})`)
		H.ok(flat.Z < home.Z and flat.Z > home.Z - 6, `{zone.id}: a little left of the boss ({flat.Z - home.Z})`)
		H.ok(math.abs(flat.Z) + plank.Size.X / 2 < Config.CORRIDOR_WIDTH / 2 - 4, `{zone.id}: clear of the left wall`)
		H.ok(plank.CFrame.LookVector.X < -0.99, `{zone.id}: faces the base`)
		local gui = plank:FindFirstChildOfClass("SurfaceGui")
		H.ok(gui and gui.Face == Enum.NormalId.Front, `{zone.id}: a SurfaceGui on the plank's front`)
		local texts = {}
		for _, l in gui:GetDescendants() do
			if l:IsA("TextLabel") then
				table.insert(texts, l.Text)
				H.ok(l.FontFace.Style == Enum.FontStyle.Italic and l.FontFace.Weight.Value >= Enum.FontWeight.Bold.Value, `{zone.id}: bold italic`)
				local stroke = l:FindFirstChildOfClass("UIStroke")
				H.ok(stroke and stroke.Thickness >= 3 and stroke.Color.R < 0.2, `{zone.id}: a dark outline`)
				H.eq(l.TextColor3, Config.speedPlankColor(0, k), `{zone.id}: a new player's colour`)
			end
		end
		H.eq(#texts, 2, `{zone.id}: two lines`)
		local all = table.concat(texts, " ")
		if zone.req > 0 then
			H.ok(string.find(all, "👟 " .. Format.short(zone.req), 1, true) and string.find(all, "recommended", 1, true), `{zone.id}: says "{all}"`)
		else
			H.ok(string.find(all, "Start here", 1, true), `{zone.id}: says "{all}"`)
		end
	end
	local top = WorldBuilder.speedSignText(3)
	H.eq(top, "👟 500K")
end)

H.test("world: the Speed plank reads GREEN from the recommended Speed up and RED below it (per player, client-side)", function()
	for k, zone in Config.ZONES do
		H.eq(Config.speedPlankColor(zone.req, k), Config.PLANK_GREEN, `{zone.id}: green right at the threshold`)
		H.eq(Config.speedPlankColor(zone.req * 10 + 1, k), Config.PLANK_GREEN, `{zone.id}: green above it`)
		if zone.req > 0 then
			H.eq(Config.speedPlankColor(zone.req - 1, k), Config.PLANK_RED, `{zone.id}: red just below it`)
			H.eq(Config.speedPlankColor(0, k), Config.PLANK_RED, `{zone.id}: red for a new player`)
		else
			H.eq(Config.speedPlankColor(0, k), Config.PLANK_GREEN, `{zone.id}: the start zone is always green`)
		end
	end
	local g, r = Config.PLANK_GREEN, Config.PLANK_RED
	H.ok(g.G > g.R and g.G > g.B and r.R > r.G and r.R > r.B, "green is green, red is red")
	local fs = require("@lune/fs")
	local src = fs.readFile("src/client/SpeedPlanks.client.luau")
	H.ok(string.find(src, "\"SpeedPlank\"", 1, true) and string.find(src, "GetAttribute(\"ZoneIndex\")", 1, true), "finds the planks by attribute")
	H.ok(string.find(src, "Config.speedPlankColor(speed, k)", 1, true) and string.find(src, "StatsUpdate.OnClientEvent", 1, true), "recolours from the player's Speed")
	-- the text is rewritten from Config at runtime too (a map built with older reqs still reads right), with
	-- the same function WorldBuilder bakes into the map
	H.ok(string.find(src, "Format.speedPlank(Config.ZONES[k].req)", 1, true) and string.find(src, "d.Text = top", 1, true)
		and string.find(src, "d.Text = bottom", 1, true), "the client writes the plank's text from the zone's req")
	local Format = H.shared("Format")
	for k, zone in Config.ZONES do
		local a, b = WorldBuilder.speedSignText(k)
		local c, d = Format.speedPlank(zone.req)
		H.ok(a == c and b == d, `{zone.id}: WorldBuilder and the client agree`)
	end
	H.eq((Format.speedPlank(7.5e6)), "👟 7.5M")
	H.eq((Format.speedPlank(0)), "🌱 Start here")
end)

H.test("world: every zone has particle ambience", function()
	for k, zone in Config.ZONES do
		local folder = world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id))
		local emitters = 0
		for _, d in folder:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				emitters += 1
			end
		end
		H.ok(emitters >= 2, `{zone.id} has particle ambience ({emitters})`)
	end
end)

H.test("world: shop plaza has a walk-up stall for the Shop, the Trail Shop, the Index and selling", function()
	local plaza = world:FindFirstChild("ShopPlaza")
	H.ok(plaza ~= nil, "ShopPlaza model")
	local opens = {}
	for _, d in plaza:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			opens[d:GetAttribute("OpensShop")] = true
		end
	end
	for _, id in { "Shop", "Trails", "Index", "Sell" } do
		H.ok(opens[id], `stall opens {id}`)
	end
end)

H.test("world: the shop plaza stands by the corridor mouth (-Z side), the plots fill the other spots nearest first", function()
	local half = Config.PLOT_SIZE / 2
	local px, pz = Config.spotXZ(Config.PLAZA_SPOT)
	-- owner request: the -Z row reads stalls (by the corridor mouth), then plots
	H.eq(px, Config.PLOT_FIRST_X, "the plaza is in the front column")
	H.ok(pz < 0, "on the -Z side of the walkway")
	local spots = {}
	for i, plot in plots do
		local spot = Config.plotSpot(i)
		H.ok(spot ~= Config.PLAZA_SPOT and not spots[spot], `plot {i} has its own spot ({spot})`)
		spots[spot] = true
		H.ok(i == 1 or plot.center.X <= plots[i - 1].center.X, `plot {i} is no nearer the corridor than plot {i - 1}`)
		H.ok(math.abs(plot.center.X - px) >= Config.PLOT_SIZE - 1e-3 or math.sign(plot.center.Z) ~= math.sign(pz), `plot {i} clear of the plaza`)
	end
	H.eq(#plots, Config.MAX_PLAYERS)
	-- every stall, ring and sand piece of the plaza stays in its spot (off the plots, the walkway and the rewards corner)
	local plaza = world:FindFirstChild("ShopPlaza")
	for _, d in plaza:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "PlazaPath" then
			local p = d.CFrame.Position
			H.ok(math.abs(p.X - px) <= half and math.abs(p.Z - pz) <= half, `{d:GetFullName()} in the plaza's spot ({p})`)
		end
	end
	local spot, board = WorldBuilder.rewardPoints(world)
	for _, part in { spot, board.status.Parent.Parent } do
		local p = part.CFrame.Position
		H.ok(p.X > px + half + 4, `{part.Name} beside the plaza, toward the corridor mouth, not in it`)
	end
end)

H.test("world: each plot has a small, non-colliding Upgrade Plot board just outside its gate", function()
	for i, plot in plots do
		local board = plot.upgradeBoard
		H.ok(board ~= nil and board:IsA("BasePart"), `plot {i} board`)
		H.eq(board.Parent, plot.model)
		H.eq(board.CanCollide, false, "the board never blocks the path")
		H.ok(board.Size.X <= 8 and board.Size.Y <= 5, "stud-sized, read up close")
		-- outside the fence (walkway side), beside the 14-stud path, near the gate
		local side = math.sign(plot.center.Z)
		local entranceZ = plot.center.Z - side * Config.PLOT_SIZE / 2
		local p = board.CFrame.Position
		H.ok(math.abs(p.Z) < math.abs(entranceZ), `plot {i} board is outside the plot`)
		H.ok(math.abs(p.Z - entranceZ) <= 8, "near the gate")
		H.ok(math.abs(p.X - plot.center.X) > 7 + board.Size.X / 2, "clear of the path")
		-- Its front (LookVector, where the SurfaceGui is) faces the walkway. Built with Props.lookAt, which is
		-- correct under Lune too (Lune's own CFrame.lookAt is not), so the baked map matches Roblox.
		H.ok(board.CFrame.LookVector:Dot(Vector3.new(0, 0, -side)) > 0.99, "its front faces the walkway")
		local gui = board:FindFirstChildOfClass("SurfaceGui")
		H.ok(gui ~= nil and gui.Face == Enum.NormalId.Front, "text on the front face")
		for _, key in { "level", "cash", "robux" } do
			H.ok(plot.upgradeLabels[key]:IsA("TextLabel") and plot.upgradeLabels[key]:IsDescendantOf(gui), key .. " label")
		end
		H.ok(plot.upgradeLabels.buttons and plot.upgradeLabels.buttons:IsDescendantOf(gui), "the buttons row")
		H.ok(plot.upgradeLabels.cash:IsDescendantOf(plot.upgradeLabels.buttons) and plot.upgradeLabels.robux:IsDescendantOf(plot.upgradeLabels.buttons),
			"both prices sit on the buttons")
	end
end)


----------------------------------------------------------------------------------------------------
-- Art direction (owner playtest): clean cartoony look, a 3x wider corridor, no zone gates, wall caps,
-- few props early, no finish line, market stalls.
----------------------------------------------------------------------------------------------------
local Assets = H.server("Assets")

H.test("world: no realistic materials or textures anywhere on the map (plastic, studs, neon, glass only)", function()
	local bad = Layout.realisticBits(world)
	H.eq(#bad, 0, "realistic bits: " .. table.concat(bad, ", ", 1, math.min(#bad, 8)))
	local plastic = 0
	for _, p in parts(world) do
		if p.Material == Enum.Material.Plastic and p.TopSurface == Enum.SurfaceType.Studs then
			plastic += 1
		end
	end
	H.ok(plastic > 500, `lots of studded plastic ({plastic} parts)`)
end)

H.test("world: the corridor is 192 studs wide, wall to wall, in every zone", function()
	H.eq(Config.CORRIDOR_WIDTH, 192)
	local halfW = Config.CORRIDOR_WIDTH / 2
	for k, zone in Config.ZONES do
		local folder = world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id))
		local floor = folder:FindFirstChild("Floor")
		H.ok(floor and math.abs(floor.Size.Z - Config.CORRIDOR_WIDTH) < 1e-3 and floor.CanCollide, `{zone.id} floor spans the width`)
		local sides = {}
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") and p.Name == "Wall" and p.Size.X >= zone.length - 1 then
				local inner = math.abs(p.CFrame.Position.Z) - p.Size.Z / 2
				H.ok(math.abs(inner - halfW) < 1e-3 and p.CanCollide, `{zone.id} wall's inner face at {inner}`)
				H.ok(p.Size.Y >= Config.WALL_HEIGHT, "tall walls")
				sides[math.sign(p.CFrame.Position.Z)] = true
			end
		end
		H.ok(sides[1] and sides[-1], `{zone.id} has both walls`)
	end
end)

H.test("world: no finish line: the Spirit Garden's back wall ends the corridor, with no End area or sign", function()
	H.eq(world.Corridor:FindFirstChild("End"), nil, "no End folder")
	local spirit = world.Corridor:FindFirstChild(string.format("%d_%s", #Config.ZONES, Config.ZONES[#Config.ZONES].id))
	local back = nil
	for _, p in spirit:GetChildren() do
		if p:IsA("BasePart") and p.Name == "Wall" and p.Size.Z >= Config.CORRIDOR_WIDTH and p.CFrame.Position.X >= Config.END_X then
			back = p
		end
	end
	H.ok(back and back.CanCollide, "a solid back wall closes the corridor at END_X")
	for _, d in world:GetDescendants() do
		H.ok(not (d:IsA("BasePart") and (d.Name == "EndPad" or d.Name == "EndWall" or d.Name == "EndConfetti")), `{d:GetFullName()}: finish piece`)
		if d:IsA("TextLabel") then
			local text = string.upper(d.Text)
			for _, banned in { "END OF THE LINE", "YOU MADE IT", "FINISH" } do
				H.ok(not string.find(text, banned, 1, true), `{d:GetFullName()} says "{d.Text}"`)
			end
		end
	end
	local fs = require("@lune/fs")
	for _, path in { "src/client/HUD.client.luau", "src/server/SpeedService.luau", "src/server/WorldBuilder.luau" } do
		local text = string.upper(fs.readFile(path))
		H.ok(not string.find(text, "END OF THE LINE", 1, true) and not string.find(text, "REACHED THE END", 1, true), `{path} has no finish message`)
	end
end)

-- The only glow on the floor is lava (and the Deep Space craters' goo) pooling in ragged blobs: rows of a
-- pool side by side, its brighter spots on them. No glowing strips, lines, rings or rivers anywhere.
local FLOOR_GLOW = { LavaPool = true, LavaHot = true, CraterGoo = true, GooHot = true }
H.test("world: no neon on the corridor's floor or edges but lava pools (no glowing strips, lines, rings or rivers)", function()
	local pools = {}
	for _, p in parts(world.Corridor) do
		if p.Material == Enum.Material.Neon then
			local s = p.Size
			local thinnest = math.min(s.X, s.Y, s.Z)
			local longest = math.max(s.X, s.Y, s.Z)
			local onFloor = p.CFrame.Position.Y - thinnest / 2 < Config.GROUND_Y + 1 and thinnest <= 0.6
			local dims = { s.X, s.Y, s.Z }
			table.sort(dims)
			if onFloor then
				H.ok(FLOOR_GLOW[p.Name], `{p:GetFullName()}: neon on the floor`)
				if p.Name ~= "LavaHot" and p.Name ~= "GooHot" then -- a pool's rows (not its bright spots), gathered by zone and height
					local key = `{p.Parent:GetFullName()}/{p.Name}/{math.round((p.CFrame.Position.Y + s.Y / 2) * 100)}`
					local pos = p.CFrame.Position
					pools[key] = pools[key] or {}
					table.insert(pools[key], { pos.X - s.X / 2, pos.X + s.X / 2, pos.Z - s.Z / 2, pos.Z + s.Z / 2 })
				end
			else
				H.ok(not (longest >= 20 and dims[2] <= 3), `{p:GetFullName()}: a neon strip`)
			end
		end
	end
	-- each pool (the rows touching one another) makes a blob, not a line
	for key, rows in pools do
		local group = {}
		local function root(i: number): number
			while group[i] ~= i do
				i = group[i]
			end
			return i
		end
		for i = 1, #rows do
			group[i] = i
		end
		for i = 1, #rows do
			for j = i + 1, #rows do
				local a, b = rows[i], rows[j]
				if a[1] <= b[2] + 0.01 and b[1] <= a[2] + 0.01 and a[3] <= b[4] + 0.01 and b[3] <= a[4] + 0.01 then
					group[root(i)] = root(j)
				end
			end
		end
		local boxes = {}
		for i, r in rows do
			local g = root(i)
			local b = boxes[g] or { math.huge, -math.huge, math.huge, -math.huge }
			b[1], b[2], b[3], b[4] = math.min(b[1], r[1]), math.max(b[2], r[2]), math.min(b[3], r[3]), math.max(b[4], r[4])
			boxes[g] = b
		end
		for _, b in boxes do
			local w, d = b[2] - b[1], b[4] - b[3]
			H.ok(math.max(w, d) / math.min(w, d) <= 4 and math.min(w, d) >= 4, `{key}: a pool, not a strip ({w} x {d})`)
		end
	end
end)

H.test("world: each zone starts with a soft border strip a shade lighter than its floor (no glow)", function()
	for k, zone in Config.ZONES do
		local folder = world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id))
		local edge = folder:FindFirstChild("ZoneEdge")
		H.ok(edge, `{zone.id}: a ZoneEdge`)
		H.ok(math.abs(edge.Size.Z - Config.CORRIDOR_WIDTH) < 1e-3 and edge.Size.X <= 8, `{zone.id}: a narrow strip across the corridor`)
		H.ok(math.abs(edge.CFrame.Position.X - edge.Size.X / 2 - Config.zoneStartX(k)) < 1e-3, `{zone.id}: at the zone's entrance`)
		H.ok(edge.Material == Enum.Material.Plastic and edge.TopSurface == Enum.SurfaceType.Studs, `{zone.id}: flat studded plastic`)
		local f, c = zone.floor, edge.Color
		local diff = (c.R - f.R) + (c.G - f.G) + (c.B - f.B)
		H.ok(diff > 0 and diff < 0.6, `{zone.id}: a little lighter than the floor ({diff})`)
		H.ok(math.abs(edge.CFrame.Position.Y + edge.Size.Y / 2 - Config.GROUND_Y) < 1e-3, `{zone.id}: level with the floor (not laid over it)`)
	end
end)

H.test("world: ponds are flat studded checker water with notched lily pads, a flower and reeds", function()
	local ponds, tones, pads, cuts, petals, reeds = 0, {}, 0, 0, 0, 0
	for _, p in parts(world.Corridor) do
		H.ok(p.Name ~= "PondRim", "no pond rim")
		if p.Name == "Pond" or p.Name == "PondTile" then
			if p.Name == "Pond" then
				ponds += 1
			end
			H.ok(p.Material == Enum.Material.Plastic and p.Transparency == 0, `{p:GetFullName()}: solid studded plastic water`)
			H.ok(p.Color.B > p.Color.R and p.Color.B > p.Color.G, "blue water")
			tones[p.Color:ToHex()] = true
		elseif p.Name == "LilyPad" then
			pads += 1
		elseif p.Name == "LilyCut" then
			cuts += 1
		elseif p.Name == "LilyPetal" then
			petals += 1
		elseif p.Name == "Reed" then
			reeds += 1
			H.ok(p.Size.Y >= 5, "tall reeds")
		end
	end
	local nTones = 0
	for _ in tones do
		nTones += 1
	end
	H.ok(ponds >= 5, `ponds (rows) {ponds}`)
	H.eq(nTones, 2, "a checker of two blues")
	H.ok(pads >= 4 and cuts == pads, `each lily pad has its wedge cut ({pads} pads, {cuts} cuts)`)
	H.ok(petals >= 2, "a flower on a pad")
	H.ok(reeds >= 3, "reeds")
end)

H.test("world: ponds are sunken: the water sits below the floor in a hole cut through it, on a solid bed", function()
	local ZoneThemes = H.server("ZoneThemes")
	local sink = ZoneThemes.POND_SINK
	H.ok(sink >= 0.3 and sink <= 0.5, `the water sits 0.3-0.5 studs down ({sink})`)
	local ground = Config.GROUND_Y
	local function rect(p: any): (number, number, number, number)
		local pos, size = p.CFrame.Position, p.Size
		return pos.X - size.X / 2, pos.X + size.X / 2, pos.Z - size.Z / 2, pos.Z + size.Z / 2
	end
	local function top(p: any): number
		return p.CFrame.Position.Y + p.Size.Y / 2
	end
	local ON_WATER = { LilyCut = true, LilyPetal = true, LilyHeart = true, Koi = true }
	local rows = 0
	for _, folder in world.Corridor:GetChildren() do
		local floors, water, pads = {}, {}, {}
		for _, p in folder:GetDescendants() do
			if p:IsA("BasePart") then
				if p.Name == "Floor" or p.Name == "FloorTile" or p.Name == "ZoneEdge" then
					table.insert(floors, p)
				elseif p.Name == "Pond" or p.Name == "PondTile" then
					table.insert(water, p)
				elseif p.Name == "LilyPad" then
					table.insert(pads, p)
				elseif not ON_WATER[p.Name] and p.Transparency < 1 and p.Size.Y < 0.6 and p.CFrame.Position.Y < ground + 1 then -- any other flat overlay
					table.insert(floors, p)
				end
			end
		end
		for _, w in water do
			local wx0, wx1, wz0, wz1 = rect(w)
			local wtop = top(w)
			H.ok(wtop < ground - sink + 0.1 and wtop > ground - sink - 0.1, `{w:GetFullName()}: water top {wtop} sits below the floor`)
			local bed = false
			for _, f in floors do
				local fx0, fx1, fz0, fz1 = rect(f)
				local overlaps = wx0 < fx1 - 1e-3 and wx1 > fx0 + 1e-3 and wz0 < fz1 - 1e-3 and wz1 > fz0 + 1e-3
				if overlaps and top(f) > wtop - 0.06 then
					error(`{f:GetFullName()} (top {top(f)}) covers the sunken water of {w:GetFullName()}`)
				end
				if f.Name == "Floor" and f.CanCollide and fx0 <= wx0 + 1e-3 and fx1 >= wx1 - 1e-3 and fz0 <= wz0 + 1e-3 and fz1 >= wz1 - 1e-3
					and math.abs(top(f) - (w.CFrame.Position.Y - w.Size.Y / 2)) < 1e-3 then
					bed = true
				end
			end
			H.ok(bed, `{w:GetFullName()}: a solid bed right under the water`)
			if w.Name == "Pond" then
				rows += 1
			end
		end
		for _, pad in pads do
			local bottom = pad.CFrame.Position.Y - pad.Size.X / 2 -- a cylinder lies on its X axis
			H.ok(bottom > ground - sink - 0.05 and bottom < ground - sink + 0.2, `{pad:GetFullName()} floats on the water ({bottom})`)
		end
	end
	H.ok(rows >= 5, `sunken pond rows {rows}`)
	-- the zone's first Floor is still the full-width slab under the ground's tiles (the cut keeps it whole
	-- across Z)
	local Props = H.server("Props")
	for k, zone in Config.ZONES do
		local floor = world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id)):FindFirstChild("Floor")
		H.ok(math.abs(top(floor) - (ground - Props.TILE_THICKNESS)) < 1e-3, `{zone.id}: the first Floor is the slab under the ground`)
	end
end)

H.test("world: every zone wall has a cap", function()
	local halfW = Config.CORRIDOR_WIDTH / 2
	for k, zone in Config.ZONES do
		local folder = world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id))
		local caps = 0
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") and p.Name == "WallCap" and p.Size.X >= zone.length - 1 and math.abs(p.CFrame.Position.Z) > halfW - 2 then
				caps += 1
				H.ok(p.CFrame.Position.Y > Config.WALL_HEIGHT, "on top of the wall")
			end
		end
		H.ok(caps >= 2, `{zone.id}: both walls capped ({caps})`)
	end
end)

-- (Each zone's props, set pieces and their part, emitter and light budgets: tests/zones.spec.luau. The
-- owner's art pass made every zone rich, the Meadow included, so the old "few props early" rule is gone.)

H.test("world: the base is wider than the corridor and its front walls close the corners of the corridor mouth", function()
	local halfW = Config.CORRIDOR_WIDTH / 2
	local front = {}
	for _, p in world.Base:GetChildren() do
		if p:IsA("BasePart") and p.Name == "Wall" and math.abs(p.CFrame.Position.X - (Config.CORRIDOR_START_X + 2)) < 0.1 then
			table.insert(front, p)
		end
	end
	H.eq(#front, 2, "a front wall each side of the mouth")
	for _, p in front do
		local lo, hi = Assets.bounds(p)
		local near = math.min(math.abs(lo.Z), math.abs(hi.Z))
		H.ok(math.abs(near - halfW) < 1e-3, `the front wall starts right at the corridor wall ({near})`)
	end
	local _, hi = Assets.bounds(front[1])
	local _, hi2 = Assets.bounds(front[2])
	local outer = math.max(math.abs(hi.Z), math.abs(hi2.Z))
	for _, plot in plots do -- the plots sit inside the base, clear of its side walls
		H.ok(math.abs(plot.center.Z) + Config.PLOT_SIZE / 2 < outer - 4, "plot inside the base")
	end
end)

H.test("world: four market stalls (posts, stone counter, striped scalloped awning, glowing ring, title, prompt)", function()
	local plaza = world:FindFirstChild("ShopPlaza")
	local labels = { Shop = "🛒 SHOP", Trails = "🏃 TRAIL SHOP", Index = "📖 INDEX", Sell = "SELL" }
	local awningColors = {}
	for _, d in plaza:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			local opens = d:GetAttribute("OpensShop")
			local host = d.Parent
			local stall = plaza:FindFirstChild("ShopStall_" .. opens)
			H.ok(stall and stall:IsA("Model"), `{opens}: its stall`)
			H.eq(d.ObjectText, labels[opens], `{opens}: prompt text`)
			H.eq(d.KeyboardKeyCode, Enum.KeyCode.E)
			local count = { Post = 0, Counter = 0, Awning = 0, Scallop = 0 }
			local white, colored = 0, nil
			for _, p in stall:GetDescendants() do
				if p:IsA("BasePart") and count[p.Name] then
					count[p.Name] += 1
					if p.Name == "Awning" then
						if p.Color.R > 0.95 and p.Color.G > 0.95 and p.Color.B > 0.95 then
							white += 1
						else
							colored = p.Color
						end
					end
				end
			end
			H.eq(count.Post, 4, `{opens}: four posts`)
			H.ok(count.Counter >= 3, `{opens}: a counter on three sides`)
			H.ok(count.Awning >= 6 and white >= 3 and colored, `{opens}: a striped awning`)
			H.eq(count.Scallop, count.Awning, `{opens}: a scalloped edge`)
			table.insert(awningColors, colored)
			-- the glowing ring in front of it (toward the walkway), within reach of the prompt
			local ring = nil
			for _, r in plaza:GetChildren() do
				if r:IsA("BasePart") and r.Material == Enum.Material.Neon and (r.Name == "StallRing" or r.Name == "SellCircle")
					and math.abs(r.CFrame.Position.X - host.CFrame.Position.X) < 1 then
					ring = r
				end
			end
			H.ok(ring and not ring.CanCollide and math.abs(ring.CFrame.Position.Z) < math.abs(host.CFrame.Position.Z), `{opens}: a glowing ring in front`)
			H.ok((ring.CFrame.Position - host.CFrame.Position).Magnitude < d.MaxActivationDistance, `{opens}: the prompt works from the ring`)
			local title = nil
			for _, l in plaza:GetDescendants() do
				if l:IsA("TextLabel") and l.Text == labels[opens] then
					title = l
				end
			end
			H.ok(title and title.Parent:IsA("BillboardGui") and title.Parent.Adornee.CFrame.Position.Y > host.CFrame.Position.Y + 12, `{opens}: a title floating over the awning`)
			H.ok(title:FindFirstChildOfClass("UIStroke").Thickness >= 4, `{opens}: outlined title`)
		end
	end
	H.eq(#awningColors, 4, "four stalls")
	for i = 1, #awningColors do
		for j = i + 1, #awningColors do
			local a, b = awningColors[i], awningColors[j]
			H.ok(math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) > 0.3, "each stall has its own awning colour")
		end
	end
end)
