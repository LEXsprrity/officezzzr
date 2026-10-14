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

H.test("world: plot layout contract is unchanged (slots, pad, spawn, belt)", function()
	for i, plot in plots do
		local col = (i - 1) // 2
		local side = if i % 2 == 1 then 1 else -1
		local center = Vector3.new(Config.PLOT_FIRST_X - col * Config.PLOT_SPACING_X, Config.GROUND_Y, side * Config.PLOT_OFFSET_Z)
		H.ok((plot.center - center).Magnitude < 1e-3, "plot center")
		local toWalk = -side
		local entrance = center + Vector3.new(0, 0, toWalk * Config.PLOT_SIZE / 2)
		local function at(u: number, w: number, y: number)
			return entrance + Vector3.new(u, y, -toWalk * w)
		end
		H.eq(#plot.slotCFrames, Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS, "slot count")
		for s, cf in plot.slotCFrames do
			local row = (s - 1) // Config.SLOT_COLUMNS
			local c = (s - 1) % Config.SLOT_COLUMNS
			local want = at((c - (Config.SLOT_COLUMNS - 1) / 2) * Config.SLOT_SPACING, 46 + row * Config.SLOT_SPACING, 1)
			H.ok((cf.Position - want).Magnitude < 1e-3, `plot {i} slot {s} moved`)
			H.ok(cf.LookVector:Dot(Vector3.new(0, 0, -toWalk)) > 0.999, `plot {i} slot {s} must look into the plot`)
		end
		H.ok((plot.pad.CFrame.Position - at(0, 10, 1.2)).Magnitude < 1e-3, `pad position {plot.pad.CFrame.Position} vs {at(0, 10, 1.2)}`)
		H.ok((plot.spawnCFrame.Position - at(-24, 12, 4)).Magnitude < 1e-3, "spawn position")
		-- With a Treadmill model in assets/, the belt takes the model's belt: its running surface and its
		-- footprint, so it may shift a little along the treadmill.
		local beltDelta = plot.belt.CFrame.Position - at(30, 21, 1.5)
		H.ok(math.abs(beltDelta.X) < 0.5 and math.abs(beltDelta.Z) < 2 and beltDelta.Y > -1e-3 and beltDelta.Y < 6, `belt position ({beltDelta})`)
		H.ok(plot.belt.Size.X <= 6 and plot.belt.Size.Z <= 18, `a plot-sized belt ({plot.belt.Size})`)
		H.eq(plot.model.PrimaryPart.Name, "Floor")
		H.ok(plot.soil:IsA("Folder") and plot.plants:IsA("Folder"), "soil/plants folders")
		H.ok(plot.signLabel:IsA("TextLabel"), "sign label")
		H.ok(plot.treadmillLabel:IsA("TextLabel"), "treadmill sign label (PlotService writes the owner's Speed/s on it)")
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

-- Inside the corridor only the floor, walls (the Spirit Garden's back wall too) and the gates' wall-flush pillars
-- may collide, so props never block runners or the guards' MoveTo line.
H.test("world: corridor props never collide (only floor/walls/pillars)", function()
	local allowed = { Floor = true, Wall = true, GatePillar = true }
	local corridor = world:FindFirstChild("Corridor")
	for _, p in parts(corridor) do
		if p.CanCollide and not allowed[p.Name] then
			error(`{p:GetFullName()} collides`)
		end
	end
	-- Pillars stay flush with the walls: at most 4 studs proud of each wall.
	for _, p in parts(corridor) do
		if p.Name == "GatePillar" then
			H.ok(math.abs(p.CFrame.Position.Z) - p.Size.Z / 2 >= Config.CORRIDOR_WIDTH / 2 - 4, "pillar intrudes into the corridor")
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
	H.ok(Config.PLOT_OFFSET_Z - half <= 32, "the plots are near the walkway")
	Layout.check(world, plots, "built map")
	Layout.plotsFullyFenced(world, plots, "built map")
	for _, plot in plots do
		local sign = plot.signLabel.Parent.Adornee
		local side = if plot.center.Z > 0 then 1 else -1
		local entrance = plot.center - Vector3.new(0, 0, side * half)
		local p = sign.CFrame.Position
		H.ok(math.abs(p.X - entrance.X) < 1 and math.abs(p.Z - entrance.Z) < 1 and p.Y > 6, "the name sign floats over the opening")
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

H.test("world: every zone has an entry sign with its name and recommended Speed", function()
	local Format = H.shared("Format")
	for k, zone in Config.ZONES do
		local folder = world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id))
		H.ok(folder ~= nil, "zone folder " .. zone.id)
		local found = false
		for _, d in folder:GetDescendants() do
			if d:IsA("TextLabel") and string.find(d.Text, string.upper(zone.name), 1, true) then
				local speedLine = false
				for _, sib in d.Parent:GetChildren() do
					if sib:IsA("TextLabel") and string.find(sib.Text, Format.short(zone.req), 1, true) and string.find(sib.Text, "Speed", 1, true) then
						speedLine = true
					end
				end
				found = found or speedLine
			end
		end
		H.ok(found, "sign for " .. zone.id)
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
-- Art direction (owner playtest): clean cartoony look, a 3x wider corridor, a gate per zone, wall caps,
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
			if p:IsA("BasePart") and p.Name == "Wall" and p.Size.X > 100 then
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

H.test("world: every zone has a chunky gate at its entrance, and every wall a cap", function()
	local halfW = Config.CORRIDOR_WIDTH / 2
	for k, zone in Config.ZONES do
		local folder = world.Corridor:FindFirstChild(string.format("%d_%s", k, zone.id))
		local gate = folder:FindFirstChild("Arch_" .. zone.id)
		H.ok(gate and gate:IsA("Model") and gate:GetAttribute("AssetSlot") == "Arch_" .. zone.id, `{zone.id}: the Arch_ slot holds its gate`)
		local pillars, beam = {}, nil
		for _, p in gate:GetDescendants() do
			if p:IsA("BasePart") and p.Name == "GatePillar" then
				table.insert(pillars, p)
			elseif p:IsA("BasePart") and p.Name == "GateBeam" then
				beam = p
			end
		end
		H.eq(#pillars, 2, `{zone.id}: two pillars`)
		local x0 = Config.zoneStartX(k)
		for _, p in pillars do
			H.ok(p.Size.X >= 10 and p.Size.Z >= 10, `{zone.id}: chunky pillars`)
			H.ok(math.abs(p.CFrame.Position.X - x0) < 15 and p.Size.Y > Config.WALL_HEIGHT, `{zone.id}: at the entrance, above the walls`)
		end
		H.ok(beam and beam.Size.Z >= Config.CORRIDOR_WIDTH and beam.CFrame.Position.Y > Config.WALL_HEIGHT, `{zone.id}: a beam over the whole corridor`)
		local caps = 0
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") and p.Name == "WallCap" and p.Size.X > 100 and math.abs(p.CFrame.Position.Z) > halfW - 2 then
				caps += 1
				H.ok(p.CFrame.Position.Y > Config.WALL_HEIGHT, "on top of the wall")
			end
		end
		H.ok(caps >= 2, `{zone.id}: both walls capped ({caps})`)
	end
end)

-- Decoration in a zone: everything visible but the floor, walls, their checker and caps, the gate, the
-- sign and the nest (the Spirit Garden's roof is its cap).
local STRUCTURE = { Floor = true, FloorTile = true, Wall = true, WallTile = true, WallCap = true, Threshold = true, Sign = true,
	Roof = true, RoofTile = true, RoofTrim = true }
local function propParts(folder: any): number
	local id = string.match(folder.Name, "^%d+_(.+)$")
	local n = 0
	for _, p in parts(folder) do
		local inGate = p:FindFirstAncestor("Arch_" .. id)
		local inNest = p:FindFirstAncestor("Nest_" .. id)
		if not STRUCTURE[p.Name] and not inGate and not inNest and p.Transparency < 1 then
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
