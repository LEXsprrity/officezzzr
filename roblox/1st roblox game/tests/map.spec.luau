-- The hand-editable map: map/World.rbxm is the source of truth and the server adopts it. Contract of the
-- committed file, adoption of a hand-edited map, the fallback when a required piece is missing, the
-- --force guard on tools/build_map.luau and tools/apply_assets.luau keeping hand edits.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")
local MapTool = require("../tools/map_tool")

local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
local Config = H.shared("Config")
local WorldBuilder = H.server("WorldBuilder")
local Assets = H.server("Assets")

local TMP = "tests/_tmp_World.rbxm"

local function withRole(world: any, role: string, scope: string, index: number): any
	for _, d in world:GetDescendants() do
		if d:GetAttribute("Role") == role and d:GetAttribute(scope) == index then
			return d
		end
	end
	return nil
end

local function attWorld(a: any): any
	return a.Parent.CFrame * a.CFrame
end

H.test("map: map/World.rbxm loads, has every required piece and gives usable plot and nest info", function()
	local world = MapTool.load(MapTool.PATH)
	local plots, nests, problems = WorldBuilder.adopt(world)
	H.ok(plots and nests, "map/World.rbxm doesn't validate:\n" .. table.concat(problems, "\n"))
	H.eq(#problems, 0, "duplicates: " .. table.concat(problems, "; "))
	H.eq(#plots, Config.MAX_PLAYERS)
	H.eq(#nests, #Config.ZONES)
	for i, plot in plots do
		H.eq(#plot.slotCFrames, Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS, `plot {i} slots`)
		for s, cf in plot.slotCFrames do
			H.ok((cf.Position - plot.center).Magnitude < Config.PLOT_SIZE, `plot {i} slot {s} on its plot`)
		end
		local top = plot.belt.CFrame * CFrame.new(0, plot.belt.Size.Y / 2 + 3, 0)
		H.ok(WorldBuilder.onBelt(plot.belt, top.Position), `plot {i}: standing on the belt counts`)
		H.ok(not WorldBuilder.onBelt(plot.belt, top.Position + Vector3.new(0, 0, plot.belt.Size.Z)), `plot {i}: beside it doesn't`)
		H.ok((plot.pad.CFrame.Position - plot.center).Magnitude < Config.PLOT_SIZE, `plot {i} pad`)
		H.ok(plot.signLabel:IsA("TextLabel") and plot.treadmillLabel:IsA("TextLabel"), `plot {i} labels`)
		H.ok(plot.upgradeLabels.level and plot.upgradeLabels.perk and plot.upgradeLabels.price, `plot {i} board labels`)
		H.ok(plot.soil:IsA("Folder") and plot.plants:IsA("Folder"), `plot {i} folders`)
	end
	for k, nest in nests do
		H.eq(#nest.podCFrames, Config.PODS_PER_NEST, `zone {k} pods`)
		for _, cf in nest.podCFrames do
			H.ok((cf.Position - nest.center).Magnitude < 15, `zone {k} pod near its nest`)
		end
		H.ok(math.abs(nest.guardHome.X - nest.center.X) < 60, `zone {k} guard home near its nest`)
		H.ok(nest.center.X > Config.zoneStartX(k) and nest.center.X < Config.zoneStartX(k) + Config.ZONES[k].length, `zone {k} nest inside its zone`)
	end
end)

H.test("map: a hand-edited map is adopted as it is, and gameplay follows the moved pieces", function()
	local world = MapTool.load(MapTool.PATH)
	-- Move and turn plot 1's treadmill belt, move its pad, reparent its name sign, turn its floor (with the
	-- slots and spawn on it), move a nest and add a decoration of the friend's own.
	local belt = withRole(world, "TreadmillBelt", "PlotIndex", 1)
	local oldBelt = belt.CFrame
	belt.CFrame = CFrame.new(oldBelt.Position + Vector3.new(-12, 0, 6)) * CFrame.Angles(0, math.rad(90), 0) * oldBelt.Rotation
	local pad = withRole(world, "PlantPad", "PlotIndex", 1)
	pad.CFrame += Vector3.new(5, 0, -3)
	local sign = withRole(world, "PlotSign", "PlotIndex", 1)
	sign.Parent = world
	local floor = withRole(world, "PlotFloor", "PlotIndex", 2)
	floor.CFrame = floor.CFrame * CFrame.Angles(0, math.rad(90), 0) + Vector3.new(0, 0, 4)
	local core = withRole(world, "NestCore", "ZoneIndex", 3)
	core.CFrame += Vector3.new(-20, 0, 6)
	local mine = Instance.new("Part")
	mine.Name = "FriendsStatue"
	mine.Anchored = true
	mine.Parent = world

	local plots, nests, problems = WorldBuilder.adopt(world)
	H.ok(plots and nests, "still valid: " .. table.concat(problems, "; "))
	H.eq(plots[1].belt, belt, "the same belt part")
	local top = belt.CFrame * CFrame.new(0, 3, 0)
	H.ok(WorldBuilder.onBelt(plots[1].belt, top.Position), "the belt check uses the belt's new place")
	H.ok(not WorldBuilder.onBelt(plots[1].belt, (oldBelt * CFrame.new(0, 3, 10)).Position), "...not the old one")
	H.ok((plots[1].pad.CFrame.Position - pad.CFrame.Position).Magnitude < 1e-4, "the pad's new place")
	H.eq(plots[1].signLabel.Parent.Parent, sign, "the reparented sign is still found")
	local slot1 = floor:FindFirstChild("Slot1")
	H.ok((plots[2].slotCFrames[1].Position - attWorld(slot1).Position).Magnitude < 1e-3, "slots follow the turned floor")
	H.ok(plots[2].slotCFrames[1].LookVector:Dot(attWorld(slot1).LookVector) > 0.999, "...and turn with it")
	H.ok((plots[2].spawnCFrame.Position - attWorld(floor:FindFirstChild("Spawn")).Position).Magnitude < 1e-3, "so does the spawn")
	H.ok((nests[3].podCFrames[1].Position - attWorld(core:FindFirstChild("Pod1")).Position).Magnitude < 1e-3, "pods follow the moved nest")
	H.ok((nests[3].guardHome - attWorld(core:FindFirstChild("GuardHome")).Position).Magnitude < 1e-3, "so does the guard's home")

	-- The server adopts it as it is: nothing is rebuilt, the hand edits stay.
	local loadedPlots = WorldBuilder.load()
	H.eq(H.workspace:FindFirstChild("World"), world, "the same World, not a regenerated one")
	H.eq(loadedPlots[1].belt, belt)
	H.ok(world:FindFirstChild("FriendsStatue") ~= nil, "decorations of his own stay")
end)

H.test("map: a map missing a required piece is reported (plot and role) and the server regenerates it", function()
	local world = MapTool.load(MapTool.PATH)
	withRole(world, "PlantPad", "PlotIndex", 3):Destroy()
	withRole(world, "Pod", "ZoneIndex", 5):SetAttribute("Role", nil)
	local plots, _, problems = WorldBuilder.adopt(world)
	H.eq(plots, nil, "not valid")
	local text = table.concat(problems, "\n")
	H.ok(string.find(text, "Plot 3: missing the planting pad", 1, true) and string.find(text, `Role = "PlantPad", PlotIndex`, 1, true), text)
	H.ok(string.find(text, "Zone 5: missing seed pod", 1, true) ~= nil, text)

	local before = #H.warnings
	local loaded = WorldBuilder.load()
	H.ok(#H.warnings > before and string.find(H.warnings[#H.warnings], "Plot 3: missing the planting pad", 1, true) ~= nil, "warned which plot and role")
	H.ok(H.workspace:FindFirstChild("World") ~= world, "regenerated from code")
	H.eq(#loaded, Config.MAX_PLAYERS)
	H.ok(loaded[3].pad ~= nil, "plot 3 has a pad again")
end)

H.test("map: tools/build_map.luau refuses to overwrite an existing map without --force", function()
	fs.writeFile(TMP, "hand-edited map")
	local ok, message = MapTool.regenerate({}, TMP)
	H.eq(ok, false, "refused")
	H.ok(string.find(message, "--force", 1, true) ~= nil, "says how to force it")
	H.eq(fs.readFile(TMP), "hand-edited map", "the file is untouched")
	ok = MapTool.regenerate({ "--force" }, TMP)
	H.ok(ok, "--force regenerates")
	local plots = WorldBuilder.adopt(MapTool.load(TMP))
	H.ok(plots ~= nil, "the regenerated map validates")
	fs.removeFile(TMP)
end)

H.test("map: tools/apply_assets.luau puts new models into the map where the pieces stand, keeping hand edits", function()
	local world = MapTool.load(MapTool.PATH)
	local rock = nil
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("AssetSlot") == "Spirit_Lantern" and not d:GetAttribute("Asset") then
			rock = d
			break
		end
	end
	H.ok(rock ~= nil, "a lantern still built from code")
	local moved = Assets.pivotOf(rock) * CFrame.new(3, 0, -2) * CFrame.Angles(0, 1, 0)
	for _, p in rock:GetDescendants() do
		if p:IsA("BasePart") then
			p.CFrame = moved * Assets.pivotOf(rock):Inverse() * p.CFrame
		end
	end
	rock.Name = "MovedLantern"
	local mine = Instance.new("Part")
	mine.Name = "FriendsStatue"
	mine.Anchored = true
	mine.Parent = world
	MapTool.save(world, TMP)

	local m = Instance.new("Model")
	m.Name = "Spirit_Lantern"
	local p = Instance.new("Part")
	p.Size = Vector3.new(2, 7, 2)
	p.Parent = m
	m.Parent = H.assets
	local ok, message = MapTool.applyAssets({}, TMP)
	m:Destroy()
	H.ok(ok, message)
	local after = MapTool.load(TMP)
	fs.removeFile(TMP)
	local lantern = after:FindFirstChild("MovedLantern", true)
	H.ok(lantern and lantern:GetAttribute("Asset") == "Spirit_Lantern", "the moved lantern is now the model")
	H.ok((Assets.pivotOf(lantern).Position - moved.Position).Magnitude < 1e-3, "where it was moved to")
	H.ok(Assets.pivotOf(lantern).LookVector:Dot(moved.LookVector) > 0.999, "turned the way it was turned")
	H.ok(after:FindFirstChild("FriendsStatue") ~= nil, "hand-added pieces stay")
	H.ok(WorldBuilder.adopt(after) ~= nil, "still validates")
end)

return nil
