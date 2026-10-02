-- World generation: builds the real map with Lune's Roblox instances (every property is checked
-- against the reflection database), then checks the layout contract and the performance budget.
local H = require("./harness")

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
			local facing = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -toWalk))
			H.ok(cf.LookVector:Dot(facing.LookVector) > 0.999, `plot {i} slot {s} rotation changed`)
		end
		H.ok((plot.pad.CFrame.Position - at(0, 10, 1.2)).Magnitude < 1e-3, `pad position {plot.pad.CFrame.Position} vs {at(0, 10, 1.2)}`)
		H.ok((plot.spawnCFrame.Position - at(-24, 12, 4)).Magnitude < 1e-3, "spawn position")
		H.ok((plot.belt.CFrame.Position - at(30, 26, 1.5)).Magnitude < 1e-3, "belt position")
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
		H.eq(nest.model.PrimaryPart.Name, "Mound")
	end
end)

H.test("world: everything is anchored", function()
	for _, p in parts(world) do
		if not p.Anchored then
			error(`{p:GetFullName()} is not anchored`)
		end
	end
end)

-- Inside the corridor only the floor, walls, the zone arches' wall-flush pillars and the end wall
-- may collide, so props never block runners or the guards' MoveTo line.
H.test("world: corridor props never collide (only floor/walls/pillars)", function()
	local allowed = { Floor = true, Wall = true, GatePillar = true, EndWall = true }
	local corridor = world:FindFirstChild("Corridor")
	for _, p in parts(corridor) do
		if p.CanCollide and not allowed[p.Name] then
			error(`{p:GetFullName()} collides`)
		end
	end
	-- Pillars stay flush with the walls: at least 56 of the 64 studs stay open.
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

H.test("world: shop plaza has a walk-up stall for the Shop, the Trail Shop and the Index", function()
	local plaza = world:FindFirstChild("ShopPlaza")
	H.ok(plaza ~= nil, "ShopPlaza model")
	local opens = {}
	for _, d in plaza:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			opens[d:GetAttribute("OpensShop")] = true
		end
	end
	for _, id in { "Shop", "Trails", "Index" } do
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
		-- Built with lookAt toward the walkway (compared the same way, since Lune's CFrame.lookAt mirrors Z:
		-- in Lune, lookAt(0, +Z).LookVector is -Z; Roblox gives +Z).
		local facing = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -side))
		H.ok(board.CFrame.LookVector:Dot(facing.LookVector) > 0.99, "its front faces the walkway")
		local gui = board:FindFirstChildOfClass("SurfaceGui")
		H.ok(gui ~= nil and gui.Face == Enum.NormalId.Front, "text on the front face")
		for _, key in { "level", "perk", "price" } do
			H.ok(plot.upgradeLabels[key]:IsA("TextLabel") and plot.upgradeLabels[key]:IsDescendantOf(gui), key .. " label")
		end
	end
end)

H.test("world: the baked edit-mode map (map/World.rbxm) matches the code (rerun tools/build_map.luau)", function()
	local fs = require("@lune/fs")
	local baked = require("@lune/roblox").deserializeModel(fs.readFile("map/World.rbxm"))[1]
	H.ok(baked ~= nil and baked.Name == "World", "map/World.rbxm holds a World folder")
	local function names(root: any): { [string]: number }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				out[d.Name] = (out[d.Name] or 0) + 1
			end
		end
		return out
	end
	local want, got = names(world), names(baked)
	for name, n in want do
		H.eq(got[name], n, `baked map has {n} x {name}; run: lune run tools/build_map.luau`)
	end
	for name in got do
		H.ok(want[name] ~= nil, `baked map has stale part {name}; run: lune run tools/build_map.luau`)
	end
end)
