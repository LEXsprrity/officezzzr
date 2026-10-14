-- World generation: builds the real map with Lune's Roblox instances (every property is checked
-- against the reflection database), then checks the layout contract and the performance budget.
local H = require("./harness")
local Layout = require("./plot_layout")

local Config = H.shared("Config")
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
		local col = (i - 1) // 2
		local side = if i % 2 == 1 then 1 else -1
		local center = Vector3.new(Config.PLOT_FIRST_X - col * Config.PLOT_SPACING_X, Config.GROUND_Y, side * Config.PLOT_OFFSET_Z)
		H.ok((plot.center - center).Magnitude < 1e-3, "plot center")
		local toWalk = -side
		local half = Config.PLOT_SIZE / 2
		local entrance = center + Vector3.new(0, 0, toWalk * half)
		local function at(u: number, w: number, y: number)
			return entrance + Vector3.new(u, y, -toWalk * w)
		end
		-- the origin: the floor's top centre, looking into the plot
		H.ok((plot.origin.Position - (center + Vector3.new(0, 1, 0))).Magnitude < 1e-3, `plot {i} origin`)
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
		local path, tile
		for _, d in plot.model:GetChildren() do
			if d.Name == "MiddlePath" then
				path = d
			elseif d.Name == "EntranceTile" then
				tile = d
			end
		end
		H.ok(path ~= nil and math.abs(path.Size.X - Config.PLOT_PATH_WIDTH) < 1e-3 and math.abs(path.Size.Z - Config.PLOT_SIZE) < 1e-3, `plot {i} middle path`)
		H.ok(math.abs(path.CFrame.Position.X - center.X) < 1e-3, `plot {i} path down the middle`)
		H.ok(tile ~= nil and (Vector3.new(tile.CFrame.Position.X, 0, tile.CFrame.Position.Z) - Vector3.new(entrance.X, 0, entrance.Z)).Magnitude < 1e-3,
			`plot {i} entrance tile at the opening`)
		H.ok((plot.spawnCFrame.Position - at(0, 12, 4)).Magnitude < 1e-3, "spawn on the middle path")
		H.ok(not Planting.bedAt(plot.beds, plot.spawnCFrame.Position - Vector3.new(0, 3, 0)), "nobody spawns on a bed")
		-- The treadmill stands outside, in front of the plot. With a Treadmill model in assets/, the belt takes
		-- the model's belt: its running surface and its footprint, so it may shift a little along it.
		local beltDelta = plot.belt.CFrame.Position - at(15, -12, 1.1)
		H.ok(math.abs(beltDelta.Z) < 0.5 and math.abs(beltDelta.X) < 2 and beltDelta.Y > -1 and beltDelta.Y < 6, `belt position ({beltDelta})`)
		H.ok(math.min(plot.belt.Size.X, plot.belt.Size.Z) <= 5 and math.max(plot.belt.Size.X, plot.belt.Size.Z) <= 10,
			`a character-sized belt ({plot.belt.Size})`)
		H.eq(plot.belt:GetAttribute("Role"), "TreadmillBelt")
		H.eq(plot.belt:GetAttribute("PlotIndex"), i)
		H.eq(plot.model.PrimaryPart.Name, "Floor")
		H.ok(plot.soil:IsA("Folder") and plot.plants:IsA("Folder"), "soil/plants folders")
		H.ok(plot.signLabel:IsA("TextLabel"), "sign label")
		H.ok(plot.treadmillLabel:IsA("TextLabel"), "treadmill sign label")
	end
end)

H.test("world: nest contract is unchanged (centre, pods, guard home)", function()
	for k, nest in nests do
		local center = Vector3.new(Config.nestX(k), Config.GROUND_Y, 0)
		H.ok((nest.center - center).Magnitude < 1e-3, "nest centre")
		H.eq(#nest.podCFrames, Config.PODS_PER_NEST)
		for i, cf in nest.podCFrames do
			local a = math.pi / 2 + (i - 0.5) * math.pi / Config.PODS_PER_NEST
			local want = center + Vector3.new(math.cos(a) * 8, 2.5, math.sin(a) * 8)
			H.ok((cf.Position - want).Magnitude < 1e-3, "pod position")
		end
		H.ok((nest.guardHome - (center + Vector3.new(Config.GUARD_HOME_OFFSET, 0, 0))).Magnitude < 1e-3, "guard home")
		H.eq(nest.model.PrimaryPart:GetAttribute("Role"), "NestCore")
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
	local allowed = { Floor = true, Wall = true }
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
			H.ok(not d:IsA("PointLight"), `{d:GetFullName()}: no lamps in the base`)
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

H.test("world: base part budget (plots, plaza, lawn and walls < 1250)", function()
	local n = 0
	for _, root in baseArea() do
		n += #parts(root)
	end
	print(`        base area parts: {n}`)
	H.ok(n < 1250, `the base area has {n} parts`)
end)

H.test("world: no zone gates, arches, threshold lines, zone name signs or STEAL A SEED sign anywhere", function()
	local banned = { GatePillar = true, GateBeam = true, GateCap = true, GateTie = true, GateTrim = true, GateStrut = true,
		PillarFoot = true, PillarTop = true, Threshold = true, Garland = true, PillarBush = true, PillarOrb = true,
		GateLeaves = true, GateCapEnd = true, GoldFinial = true, PaperLantern = true, OrbitRing = true, SnowCap = true }
	for _, d in world:GetDescendants() do
		H.ok(not banned[d.Name], `{d:GetFullName()}: a gate piece`)
		local slot = d:GetAttribute("AssetSlot")
		H.ok(not (slot and (string.match(slot, "^Arch_") or slot == "SpawnSign")), `{d:GetFullName()}: the {slot} slot`)
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

H.test("world: beside each nest a small wooden plank on a post says the zone's recommended Speed", function()
	local Format = H.shared("Format")
	for k, zone in Config.ZONES do
		local folder = world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id))
		H.ok(folder ~= nil, "zone folder " .. zone.id)
		local sign = folder:FindFirstChild("SpeedSign")
		H.ok(sign and sign:IsA("Model"), `{zone.id}: a SpeedSign`)
		local plank, post = sign:FindFirstChild("Plank"), sign:FindFirstChild("PlankPost")
		H.ok(plank and post, `{zone.id}: a plank on a post`)
		-- small and chunky, wooden orange/brown, studded, decoration only
		H.ok(plank.Size.X <= 12 and plank.Size.Y <= 6 and plank.Size.Z >= 1, `{zone.id}: a small chunky plank`)
		for _, p in { plank, post } do
			H.ok(p.Color.R > p.Color.G and p.Color.G > p.Color.B and p.Color.R > 0.6, `{zone.id}: {p.Name} is orange/brown wood`)
			H.ok(not p.CanCollide and p.Anchored, `{zone.id}: {p.Name} is decoration`)
		end
		H.eq(plank.FrontSurface, Enum.SurfaceType.Studs, `{zone.id}: studded`)
		H.ok(post.CFrame.Position.Y + post.Size.Y / 2 <= plank.CFrame.Position.Y - plank.Size.Y / 2 + 0.01, "the post holds the plank up")
		-- next to the nest, toward the base, facing the players coming from it
		local nest = Vector3.new(Config.nestX(k), Config.GROUND_Y, 0)
		local flat = Vector3.new(plank.CFrame.Position.X, Config.GROUND_Y, plank.CFrame.Position.Z)
		H.ok((flat - nest).Magnitude < 40, `{zone.id}: next to the nest ({(flat - nest).Magnitude} studs)`)
		H.ok(flat.X < nest.X and math.abs(flat.Z) > 16 and math.abs(flat.Z) < Config.CORRIDOR_WIDTH / 2 - 10, `{zone.id}: in front of the nest, beside the run`)
		H.ok(plank.CFrame.LookVector.X < -0.99, `{zone.id}: faces the base`)
		local gui = plank:FindFirstChildOfClass("SurfaceGui")
		H.ok(gui and gui.Face == Enum.NormalId.Front, `{zone.id}: a SurfaceGui on the plank's front`)
		local texts = {}
		for _, l in gui:GetDescendants() do
			if l:IsA("TextLabel") then
				table.insert(texts, l.Text)
			end
		end
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

H.test("world: each plot has a small, non-colliding Upgrade Plot board just outside its gate", function()
	for i, plot in plots do
		local board = plot.upgradeBoard
		H.ok(board ~= nil and board:IsA("BasePart"), `plot {i} board`)
		H.eq(board.Parent, plot.model)
		H.eq(board.CanCollide, false, "the board never blocks the path")
		H.ok(board.Size.X <= 8 and board.Size.Y <= 5, "stud-sized, read up close")
		-- outside the fence (walkway side), beside the 14-stud path, near the gate
		local side = if i % 2 == 1 then 1 else -1
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

H.test("world: no neon on the corridor's floor or edges (no glowing strips, lines, rings or rivers)", function()
	for _, p in parts(world.Corridor) do
		if p.Material == Enum.Material.Neon then
			local s = p.Size
			local thinnest = math.min(s.X, s.Y, s.Z)
			local longest = math.max(s.X, s.Y, s.Z)
			local onFloor = p.CFrame.Position.Y - thinnest / 2 < Config.GROUND_Y + 1 and thinnest <= 0.6
			H.ok(not onFloor, `{p:GetFullName()}: neon on the floor`)
			local dims = { s.X, s.Y, s.Z }
			table.sort(dims)
			H.ok(not (longest >= 20 and dims[2] <= 3), `{p:GetFullName()}: a neon strip`)
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
		H.ok(edge.Size.Y > 0.1 and edge.Size.Y < 0.3 and not edge.CanCollide, `{zone.id}: a flat overlay`)
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

-- Decoration in a zone: everything visible but the floor, walls, their checker and caps, the nest and the
-- Speed plank (the Spirit Garden's roof is its cap; the zone edge and pond water are flat floor overlays).
local STRUCTURE = { Floor = true, FloorTile = true, Wall = true, WallTile = true, WallCap = true,
	Roof = true, RoofTile = true, RoofTrim = true, ZoneEdge = true, Pond = true, PondTile = true }
local function propParts(folder: any): number
	local id = string.match(folder.Name, "^%d+_(.+)$")
	local n = 0
	for _, p in parts(folder) do
		local inNest = p:FindFirstAncestor("Nest_" .. id)
		local inSign = p:FindFirstAncestor("SpeedSign")
		if not STRUCTURE[p.Name] and not inNest and not inSign and p.Transparency < 1 then
			n += 1
		end
	end
	return n
end

H.test("world: the early stages are clean, with only a few props", function()
	local counts = {}
	for k, zone in Config.ZONES do
		counts[k] = propParts(world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id)))
	end
	print(`        prop parts per zone: {table.concat(counts, ", ")}`)
	H.ok(counts[1] <= 60, `the Meadow is nearly empty ({counts[1]} prop parts)`)
	H.ok(counts[2] <= 80, `the Desert has few props ({counts[2]} prop parts)`)
	for k = 1, #Config.ZONES do
		local per100 = counts[k] / Config.ZONES[k].length * 100
		H.ok(per100 <= 30, `{Config.ZONES[k].id}: {per100} prop parts per 100 studs`)
	end
end)

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
