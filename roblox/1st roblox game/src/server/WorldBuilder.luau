-- Generates the whole map from primitives: base area with 8 fenced plots (each with a treadmill),
-- the walled corridor split into themed zones (ZoneThemes) with entry arches, a mother-plant nest
-- per zone, and the End. Decoration is anchored and non-colliding (see Props).
--
-- The map is hand-editable: map/World.rbxm (Rojo puts it at Workspace.World) is the source of truth, and
-- WorldBuilder.load() ADOPTS it at server start instead of rebuilding. Every piece gameplay needs carries
-- a Role attribute (plus PlotIndex or ZoneIndex), and the plant slots, spawn points, pods and guard homes
-- are tagged Attachments, so adopt() finds them by attribute wherever they were moved or reparented.
-- Only a map missing a required piece is regenerated from code (WorldBuilder.build()), with a warning.
-- Zone boundaries for gameplay (zoneAtX, guards) always come from Config, not from the zone floors.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))
local Props = require(script.Parent:WaitForChild("Props"))
local ZoneThemes = require(script.Parent:WaitForChild("ZoneThemes"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local WorldBuilder = {}

export type PlotInfo = {
	index: number,
	model: Model,
	center: Vector3,
	signLabel: TextLabel,
	pad: BasePart,
	spawnCFrame: CFrame,
	slotCFrames: { CFrame },
	belt: BasePart,
	treadmillLabel: TextLabel, -- the sign over the belt
	soil: Folder,
	plants: Folder,
	upgradeBoard: BasePart, -- the "Upgrade Plot" sign at the gate; PlotService adds its prompt and text
	upgradeLabels: { level: TextLabel, perk: TextLabel, price: TextLabel },
}

export type NestInfo = {
	zone: number,
	model: Model,
	center: Vector3,
	podCFrames: { CFrame },
	guardHome: Vector3,
}

local GROUND = Config.GROUND_Y
local HALF_W = Config.CORRIDOR_WIDTH / 2
local BASE_MIN_X = Config.PLOT_FIRST_X - Config.PLOT_SPACING_X * (Config.PLOT_COLUMNS - 1) - Config.PLOT_SIZE / 2 - 24
local BASE_HALF_Z = Config.PLOT_OFFSET_Z + Config.PLOT_SIZE / 2 + 20

local box, deco, ball, cylinder, flat = Props.box, Props.deco, Props.ball, Props.cylinder, Props.flat

-- Marks a piece gameplay needs, so adopt() finds it by attribute wherever it ends up.
local function tag<T>(inst: T, role: string, scope: "PlotIndex" | "ZoneIndex", index: number): T
	(inst :: any):SetAttribute("Role", role);
	(inst :: any):SetAttribute(scope, index)
	return inst
end

-- A tagged Attachment on `host` at world CFrame `cf` (slots, spawn, pods, guard home).
local function marker(host: BasePart, name: string, cf: CFrame, role: string, scope: "PlotIndex" | "ZoneIndex", index: number): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = host.CFrame:Inverse() * cf
	tag(a, role, scope, index)
	a.Parent = host
	return a
end

-- An invisible, non-colliding anchor part.
local function hidden(parent: Instance, name: string, size: Vector3, cf: CFrame): Part
	local p = deco(parent, name, size, cf, Color3.new(1, 1, 1))
	p.Transparency = 1
	p.CastShadow = false
	return p
end

-- A board facing -X (toward players coming from base) with big text lines.
local function sign(parent: Instance, pos: Vector3, size: Vector2, lines: { { text: string, color: Color3 } }, boardColor: Color3, material: Enum.Material?)
	local board = box(parent, "Sign", Vector3.new(size.X, size.Y, 1), Props.lookAt(pos, pos - Vector3.xAxis), boardColor, material)
	board.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = board
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	local total = 0
	for _, line in lines do
		total += (line :: any).scale or 1
	end
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.94, ((line :: any).scale or 1) / total)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = line.text
		label.TextColor3 = line.color
		label.LayoutOrder = i
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(25, 20, 30)
		stroke.Parent = label
		label.Parent = gui
	end
	return board
end

local function billboard(adornee: BasePart, text: string, size: UDim2, offset: Vector3, maxDistance: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	return label
end
WorldBuilder.billboard = billboard

----------------------------------------------------------------------------------------------------
-- Base area: a bright lawn with mowing stripes, a stone walkway, patterned orange walls and props.
----------------------------------------------------------------------------------------------------
local GRASS = Color3.fromRGB(92, 204, 70)
local GRASS_LIGHT = Color3.fromRGB(122, 224, 88)
local STONE = Color3.fromRGB(242, 216, 164)
local EDGE = Color3.fromRGB(214, 112, 68)
local WALL = Color3.fromRGB(240, 148, 76)
local WALL_PANELS = { Color3.fromRGB(255, 214, 140), Color3.fromRGB(255, 176, 84) }
local WALL_CAP = Color3.fromRGB(150, 92, 52)
local FLOWER_COLORS = {
	Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 215, 60), Color3.fromRGB(170, 110, 255),
	Color3.fromRGB(255, 150, 60), Color3.fromRGB(90, 190, 255), Color3.fromRGB(255, 255, 255),
}

-- A wall with a warm brick body, a wooden cap, a stripe and a row of alternating diamonds on its
-- inner face. `inward` points into the base.
local function patternWall(parent: Instance, center: Vector3, along: Vector3, inward: Vector3, len: number)
	local h = Config.WALL_HEIGHT
	local rot = Props.lookAt(Vector3.zero, along) -- local Z along the wall, X across it
	box(parent, "Wall", Vector3.new(4, h, len), CFrame.new(center + Vector3.new(0, h / 2, 0)) * rot, WALL, Enum.Material.Brick)
	deco(parent, "WallCap", Vector3.new(6, 2, len + 2), CFrame.new(center + Vector3.new(0, h + 1, 0)) * rot, WALL_CAP, Enum.Material.WoodPlanks)
	local face = center + inward * 2.3
	deco(parent, "WallStripe", Vector3.new(0.6, 3, len), CFrame.new(face + Vector3.new(0, 8, 0)) * rot, WALL_PANELS[1], Enum.Material.SmoothPlastic)
	deco(parent, "WallStripe", Vector3.new(0.6, 1.5, len), CFrame.new(face + Vector3.new(0, h - 4, 0)) * rot, WALL_CAP, Enum.Material.SmoothPlastic)
	local n = math.floor(len / 14)
	for i = 0, n - 1 do
		local offset = (i - (n - 1) / 2) * 14
		local cf = CFrame.new(face + along * offset + Vector3.new(0, 22, 0)) * rot * CFrame.Angles(math.rad(45), 0, 0)
		deco(parent, "WallDiamond", Vector3.new(0.6, 7, 7), cf, WALL_PANELS[i % 2 + 1], Enum.Material.SmoothPlastic).CastShadow = false
	end
end

local function buildBase(world: Folder)
	local base = Instance.new("Folder")
	base.Name = "Base"
	base.Parent = world
	local rng = Random.new(4242)

	local len = Config.CORRIDOR_START_X - BASE_MIN_X
	local midX = BASE_MIN_X + len / 2
	box(base, "Ground", Vector3.new(len, 4, BASE_HALF_Z * 2), CFrame.new(midX, GROUND - 2, 0), GRASS, Enum.Material.Grass)
	-- Mowing stripes (the walkway, plots and paths sit on top of them)
	for x = BASE_MIN_X + 16, Config.CORRIDOR_START_X - 16, 64 do
		flat(base, "LawnStripe", 32, BASE_HALF_Z * 2, Vector3.new(x, GROUND, 0), GRASS_LIGHT, Enum.Material.Grass, nil, 0.1)
	end
	flat(base, "Walkway", len, 36, Vector3.new(midX, GROUND, 0), STONE, Enum.Material.Pebble, nil, 0.3)
	for _, s in { -1, 1 } do
		flat(base, "WalkwayEdge", len, 2, Vector3.new(midX, GROUND, s * 19), EDGE, Enum.Material.Brick, nil, 0.4)
	end

	-- Perimeter walls, leaving the corridor mouth open at +X.
	patternWall(base, Vector3.new(BASE_MIN_X - 2, GROUND, 0), Vector3.zAxis, Vector3.xAxis, BASE_HALF_Z * 2 + 8)
	for _, s in { -1, 1 } do
		patternWall(base, Vector3.new(midX, GROUND, s * (BASE_HALF_Z + 2)), Vector3.xAxis, Vector3.new(0, 0, -s), len)
		-- Front walls run on to the outer edge of the side walls, closing the corner.
		local frontLen = BASE_HALF_Z + 4 - HALF_W
		patternWall(base, Vector3.new(Config.CORRIDOR_START_X + 2, GROUND, s * (HALF_W + frontLen / 2)), Vector3.zAxis, -Vector3.xAxis, frontLen)
	end

	-- The big sign floats over the corridor mouth; a drop-in SpawnSign hangs from the same bottom edge.
	local signPos = Vector3.new(Config.CORRIDOR_START_X - 6, GROUND + 22, 0)
	Assets.swap("SpawnSign", base, Assets.facing(signPos - Vector3.new(0, 6, 0), -Vector3.xAxis), function(into)
		sign(into, signPos, Vector2.new(44, 12), {
			{ text = "🌱 STEAL A SEED 🌱", color = Color3.fromRGB(255, 240, 120), scale = 1.4 },
			{ text = "Grab a seed. Run. Plant it. Get faster.", color = Color3.new(1, 1, 1) },
		} :: any, Color3.fromRGB(70, 170, 80))
	end, Vector3.new(1, 1, 0))

	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = base

	-- Street lamps along the walkway, between the plot paths
	for col = 0, Config.PLOT_COLUMNS do
		local x = Config.PLOT_FIRST_X + Config.PLOT_SPACING_X / 2 - col * Config.PLOT_SPACING_X
		for _, s in { -1, 1 } do
			Props.lamp(props, Vector3.new(x, GROUND, s * 22), Color3.fromRGB(255, 225, 150))
		end
	end

	-- A row of trees behind the plots and at the far end
	local backZ = Config.PLOT_OFFSET_Z + Config.PLOT_SIZE / 2 + 10
	for x = BASE_MIN_X + 20, Config.CORRIDOR_START_X - 20, 40 do
		for _, s in { -1, 1 } do
			Props.roundTree(props, Vector3.new(x + rng:NextNumber(-6, 6), GROUND, s * (backZ + rng:NextNumber(-1, 3))), rng,
				Color3.fromHSV(rng:NextNumber(0.26, 0.36), 0.7, 0.78))
		end
	end
	for z = -BASE_HALF_Z + 40, BASE_HALF_Z - 40, 36 do
		if math.abs(z) < 26 then
			continue -- keep the walkway clear
		end
		Props.roundTree(props, Vector3.new(BASE_MIN_X + 16, GROUND, z), rng, Color3.fromHSV(rng:NextNumber(0.26, 0.36), 0.7, 0.8))
	end

	-- Bushes and flowers in the gaps between plots
	for col = 0, Config.PLOT_COLUMNS - 2 do
		local x = Config.PLOT_FIRST_X - Config.PLOT_SPACING_X / 2 - col * Config.PLOT_SPACING_X
		for _, s in { -1, 1 } do
			for _, z in { 50, 80, 110 } do
				Props.bush(props, Vector3.new(x, GROUND, s * z), rng:NextNumber(4, 6), Color3.fromRGB(60, 170, 70))
				Props.flower(props, Vector3.new(x + rng:NextNumber(-4, 4), GROUND, s * (z + 12)), FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)])
			end
		end
	end

	-- Spawn plaza (between the first plots and the corridor): flower beds, trees and rocks
	for _, s in { -1, 1 } do
		local bed = Vector3.new(14, GROUND, s * 62)
		Props.disc(props, "FlowerBed", 22, bed, Color3.fromRGB(120, 80, 50), Enum.Material.Ground, 0.4)
		Props.disc(props, "FlowerBedRim", 24, bed, EDGE, Enum.Material.Brick, 0.3)
		for i = 1, 9 do
			local a = i / 9 * math.pi * 2
			local r = if i % 3 == 0 then 3 else 7
			Props.flower(props, bed + Vector3.new(math.cos(a) * r, 0.4, math.sin(a) * r), FLOWER_COLORS[i % #FLOWER_COLORS + 1], 2)
		end
		Props.roundTree(props, Vector3.new(40, GROUND, s * 100), rng, Color3.fromRGB(80, 190, 70), 14)
		Props.roundTree(props, Vector3.new(-12, GROUND, s * 118), rng, Color3.fromRGB(255, 150, 190), 12, "BlossomTree")
		Props.rock(props, Vector3.new(38, GROUND, s * 60), Vector3.new(6, 4, 5), Color3.fromRGB(150, 150, 160))
		Props.rock(props, Vector3.new(44, GROUND, s * 66), Vector3.new(3, 2, 3), Color3.fromRGB(170, 170, 180))
	end
	for _ = 1, 14 do
		local z = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(26, 34)
		Props.flower(props, Vector3.new(rng:NextNumber(BASE_MIN_X + 10, Config.CORRIDOR_START_X - 10), GROUND, z), FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)])
	end
end

----------------------------------------------------------------------------------------------------
-- Plots
----------------------------------------------------------------------------------------------------
local function slotLocal(i: number): (number, number)
	local row = (i - 1) // Config.SLOT_COLUMNS
	local col = (i - 1) % Config.SLOT_COLUMNS
	local u = (col - (Config.SLOT_COLUMNS - 1) / 2) * Config.SLOT_SPACING
	return u, 46 + row * Config.SLOT_SPACING
end

local PLOT_COLORS = {
	Color3.fromRGB(255, 96, 96), Color3.fromRGB(80, 150, 255), Color3.fromRGB(255, 200, 50), Color3.fromRGB(160, 100, 255),
	Color3.fromRGB(60, 215, 140), Color3.fromRGB(255, 120, 200), Color3.fromRGB(255, 145, 50), Color3.fromRGB(70, 210, 225),
}
local PLOT_GRASS = Color3.fromRGB(104, 212, 78)
local PLOT_GRASS_LIGHT = Color3.fromRGB(136, 230, 96)

local function buildPlot(world: Folder, index: number)
	local col = (index - 1) // 2
	local side = if index % 2 == 1 then 1 else -1
	local center = Vector3.new(Config.PLOT_FIRST_X - col * Config.PLOT_SPACING_X, GROUND, side * Config.PLOT_OFFSET_Z)
	local half = Config.PLOT_SIZE / 2
	local toWalk = -side -- the entrance faces the walkway at z = 0
	local entrance = center + Vector3.new(0, 0, toWalk * half)
	local function at(u: number, w: number, y: number): Vector3
		return entrance + Vector3.new(u, y, -toWalk * w)
	end
	local facingIn = Props.lookAt(Vector3.zero, Vector3.new(0, 0, -toWalk)) -- rotation looking into the plot
	local rng = Random.new(1000 + index)

	local model = tag(Instance.new("Model"), "Plot", "PlotIndex", index)
	model.Name = "Plot" .. index
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = world
	local color = PLOT_COLORS[index]

	-- Checkered lawn with a border in the plot's colour. The floor carries the plant slots and the spawn
	-- point (tagged Attachments), so they follow it when it is moved.
	local floor = tag(box(model, "Floor", Vector3.new(Config.PLOT_SIZE, 1, Config.PLOT_SIZE), CFrame.new(center + Vector3.new(0, 0.5, 0)),
		PLOT_GRASS, Enum.Material.Grass), "PlotFloor", "PlotIndex", index)
	model.PrimaryPart = floor
	for i = 1, Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS do
		local u, w = slotLocal(i)
		marker(floor, "Slot" .. i, CFrame.new(at(u, w, 1)) * facingIn, "Slot", "PlotIndex", index):SetAttribute("SlotIndex", i)
	end
	marker(floor, "Spawn", CFrame.new(at(-24, 12, 4)) * facingIn, "Spawn", "PlotIndex", index)
	local tile = Config.PLOT_SIZE / 7
	for i = 0, 6 do
		for j = 0, 6 do
			if (i + j) % 2 == 0 then
				local p = center + Vector3.new((i - 3) * tile, 1, (j - 3) * tile)
				flat(model, "Lawn", tile, tile, p, PLOT_GRASS_LIGHT, Enum.Material.Grass, nil, 0.05)
			end
		end
	end
	for _, s in { -1, 1 } do
		flat(model, "Trim", Config.PLOT_SIZE, 2, center + Vector3.new(0, 1, s * (half - 1)), color, Enum.Material.SmoothPlastic, nil, 0.08)
		flat(model, "Trim", 2, Config.PLOT_SIZE, center + Vector3.new(s * (half - 1), 1, 0), color, Enum.Material.SmoothPlastic, nil, 0.08)
	end

	-- Wooden fence (posts + rails) with a 20-stud gate on the walkway side
	local fenceH = 5
	local y1 = Vector3.new(0, 1, 0)
	Props.fence(model, center + y1 + Vector3.new(-half, 0, -toWalk * half), center + y1 + Vector3.new(half, 0, -toWalk * half), fenceH, 7)
	for _, sx in { -1, 1 } do
		Props.fence(model, center + y1 + Vector3.new(sx * half, 0, toWalk * half), center + y1 + Vector3.new(sx * half, 0, -toWalk * half), fenceH, 7)
		Props.fence(model, entrance + y1 + Vector3.new(sx * 11, 0, 0), entrance + y1 + Vector3.new(sx * half, 0, 0), fenceH, 7)
	end
	Assets.swap("PlotGate", model, Assets.facing(entrance + y1, Vector3.new(0, 0, toWalk)), function(into)
		for _, sx in { -1, 1 } do
			box(into, "GatePost", Vector3.new(2, 9, 2), CFrame.new(entrance + Vector3.new(sx * 10, 5.5, 0)), color, Enum.Material.WoodPlanks)
			ball(into, "GateFinial", 2.6, entrance + Vector3.new(sx * 10, 10.6, 0), color:Lerp(Color3.new(1, 1, 1), 0.35))
		end
		deco(into, "GateArch", Vector3.new(22, 1.6, 1.6), CFrame.new(entrance + Vector3.new(0, 9.6, 0)), color, Enum.Material.WoodPlanks)
	end, Vector3.new(1, 1.5, 0))

	-- Stone path from the gate to the walkway, and on to the pad
	local toWalkway = math.abs(entrance.Z) - 19
	flat(model, "Path", 14, toWalkway, Vector3.new(center.X, GROUND, entrance.Z + toWalk * toWalkway / 2), STONE, Enum.Material.Pebble, nil, 0.3)
	flat(model, "Path", 10, 5, at(0, 2.5, 1), STONE, Enum.Material.Pebble, nil, 0.1)

	-- House-icon sign over the gate
	local signPart = tag(box(model, "SignPost", Vector3.new(1, 1, 1), CFrame.new(entrance + Vector3.new(0, 12, 0)), color), "PlotSign", "PlotIndex", index)
	signPart.Transparency = 1
	signPart.CanCollide = false
	-- Sized in studs (not pixels) so it shrinks with distance, and only shown up close: from the
	-- walkway you read the nearby plots' names, not a wall of labels down the whole row.
	billboard(signPart, "🏠 Empty Plot", UDim2.fromScale(16, 3.6), Vector3.zero, 75)

	-- Planting pad just inside the gate, on a rim in the plot's colour
	tag(box(model, "PlantPad", Vector3.new(10, 1, 10), CFrame.new(at(0, 10, 1.2)), Color3.fromRGB(120, 80, 50), Enum.Material.Ground), "PlantPad", "PlotIndex", index)
	flat(model, "PadRim", 12, 12, at(0, 10, 1), color, Enum.Material.SmoothPlastic, nil, 0.3)

	-- Treadmill: stand on it to gain Speed (AFK works). It doesn't move you: the client plays the run
	-- animation in place and scrolls the belt texture. The belt is the gameplay piece; the frame around it
	-- is the Treadmill asset slot.
	local tmU, tmW0, tmLen = 30, 12, 28
	local beltCenter = at(tmU, tmW0 + tmLen / 2, 1.5)
	local belt = tag(box(model, "TreadmillBelt", Vector3.new(8, 1, tmLen), CFrame.new(beltCenter) * facingIn,
		Color3.fromRGB(40, 40, 45), Enum.Material.DiamondPlate), "TreadmillBelt", "PlotIndex", index)
	local tex = Instance.new("Texture")
	tex.Name = "Stripes"
	tex.Texture = "rbxasset://textures/SurfaceTextures/DiamondPlate.png"
	tex.Face = Enum.NormalId.Top
	tex.StudsPerTileU = 4
	tex.StudsPerTileV = 4
	tex.Transparency = 0.4
	tex.Parent = belt
	Assets.swap("Treadmill", model, Assets.facing(at(tmU, tmW0 + tmLen / 2, 1), Vector3.new(0, 0, toWalk)), function(into)
		box(into, "TreadmillFrame", Vector3.new(12, 1, tmLen + 4), CFrame.new(beltCenter - Vector3.new(0, 0.6, 0)) * facingIn, Color3.fromRGB(230, 60, 60))
		for _, s in { -1, 1 } do
			box(into, "TreadmillRail", Vector3.new(1, 3, tmLen), CFrame.new(beltCenter + Vector3.new(s * 4.5, 1.5, 0)) * facingIn, Color3.fromRGB(230, 60, 60))
		end
		box(into, "TreadmillStop", Vector3.new(8, 4, 1), CFrame.new(at(tmU, tmW0 - 0.5, 3)), Color3.fromRGB(230, 60, 60))
	end, Vector3.new(1, 6, 1))
	local tmSignPart = tag(box(model, "TreadmillSign", Vector3.new(1, 1, 1), CFrame.new(beltCenter + Vector3.new(0, 8, 0)), color), "TreadmillSign", "PlotIndex", index)
	tmSignPart.Transparency = 1
	tmSignPart.CanCollide = false
	-- PlotService writes the owner's live rate on it ("+X Speed/s").
	billboard(tmSignPart, "🏃 TREADMILL", UDim2.fromScale(10, 3.6), Vector3.zero, 60)

	-- A few props in the corners, clear of the slots, pad, treadmill and spawn point
	Props.roundTree(model, at(-35, 30, 1), rng, Color3.fromRGB(70, 185, 70), 10)
	for _, u in { -37, 37 } do
		Props.bush(model, at(u, 80, 1), 4.5, Color3.fromRGB(60, 165, 65))
	end
	for i = 1, 4 do
		for _, s in { -1, 1 } do
			Props.flower(model, at(s * (14 + i * 5), 2, 1), FLOWER_COLORS[(index + i) % #FLOWER_COLORS + 1], 1.4)
		end
	end

	-- "Upgrade Plot" board just outside the gate, beside the path (like an "Upgrade Pen" sign). Small and
	-- sized in studs, so it reads only up close. PlotService writes the owner's level and price on it and
	-- owns its prompt. The board is the gameplay piece; its posts and trim are the UpgradeSign slot.
	local boardPos = at(-17, -4, 3.4)
	local boardCF = Props.lookAt(boardPos, boardPos + Vector3.new(0, 0, toWalk)) -- front face toward the walkway
	Assets.swap("UpgradeSign", model, Assets.facing(Vector3.new(boardPos.X, GROUND, boardPos.Z), Vector3.new(0, 0, toWalk)), function(into)
		for _, s in { -1, 1 } do
			deco(into, "UpgradePost", Vector3.new(0.6, 3.4, 0.6), boardCF * CFrame.new(s * 2.4, -2.3, 0.3), Color3.fromRGB(110, 70, 40), Enum.Material.Wood)
		end
		deco(into, "UpgradeBoardTrim", Vector3.new(6.4, 0.4, 0.5), boardCF * CFrame.new(0, 1.9, 0), color, Enum.Material.SmoothPlastic)
	end, Vector3.new(1.2, 1.5, 0))
	local upgradeBoard = tag(deco(model, "UpgradeBoard", Vector3.new(6, 3.6, 0.4), boardCF, Color3.fromRGB(70, 46, 28), Enum.Material.WoodPlanks),
		"UpgradeBoard", "PlotIndex", index)
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Face = Enum.NormalId.Front
	boardGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	boardGui.PixelsPerStud = 50
	boardGui.LightInfluence = 0
	boardGui.MaxDistance = 45
	boardGui.Parent = upgradeBoard
	local boardList = Instance.new("UIListLayout")
	boardList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	boardList.VerticalAlignment = Enum.VerticalAlignment.Center
	boardList.SortOrder = Enum.SortOrder.LayoutOrder
	boardList.Parent = boardGui
	local function boardLine(name: string, text: string, textColor: Color3, height: number, order: number)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.92, height)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = textColor
		label.LayoutOrder = order
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(25, 20, 30)
		stroke.Parent = label
		label.Parent = boardGui
	end
	boardLine("Title", "⬆️ UPGRADE PLOT", Color3.fromRGB(255, 225, 90), 0.3, 1)
	boardLine("Level", "Level 1 → 2", Color3.new(1, 1, 1), 0.24, 2)
	boardLine("Perk", "", Color3.fromRGB(200, 240, 255), 0.16, 3)
	boardLine("Price", "", Color3.fromRGB(120, 255, 120), 0.26, 4)

	local soil = tag(Instance.new("Folder"), "Soil", "PlotIndex", index)
	soil.Name = "Soil"
	soil.Parent = model
	local plants = tag(Instance.new("Folder"), "Plants", "PlotIndex", index)
	plants.Name = "Plants"
	plants.Parent = model
end

----------------------------------------------------------------------------------------------------
-- Corridor & zones
----------------------------------------------------------------------------------------------------
-- The zone's entry arch: two pillars flush with the walls, a beam over the top, the name sign
-- (name + recommended Speed + guardian) and a glowing threshold line on the floor. The sign and the
-- threshold stay; the rest (with the zone's ornament) is the Arch_<zone> slot.
local function buildArch(folder: Instance, k: number)
	local zone = Config.ZONES[k]
	local theme = ZoneThemes.theme(k)
	local x0 = Config.zoneStartX(k)
	local h = Config.WALL_HEIGHT
	local x = x0 + 3
	Assets.swap("Arch_" .. zone.id, folder, Assets.facing(Vector3.new(x, GROUND, 0), -Vector3.xAxis), function(into)
		for _, s in { -1, 1 } do
			box(into, "GatePillar", Vector3.new(6, h + 10, 6), CFrame.new(x, GROUND + (h + 10) / 2, s * (HALF_W - 1)), theme.arch, theme.archMaterial)
			ball(into, "PillarCap", 8, Vector3.new(x, GROUND + h + 12, s * (HALF_W - 1)), theme.accent, Enum.Material.Neon)
		end
		deco(into, "ArchBeam", Vector3.new(7, 5, Config.CORRIDOR_WIDTH + 10), CFrame.new(x, GROUND + h + 6, 0), theme.arch, theme.archMaterial)
		deco(into, "ArchTrim", Vector3.new(7.4, 1, Config.CORRIDOR_WIDTH + 10.4), CFrame.new(x, GROUND + h + 3.2, 0), theme.accent, Enum.Material.Neon)
		ZoneThemes.archOrnament(into, k, x)
	end, Vector3.new(1, 1.5, 0))
	sign(folder, Vector3.new(x - 3.6, GROUND + h - 4, 0), Vector2.new(Config.CORRIDOR_WIDTH - 12, 13), {
		{ text = `{zone.icon} {string.upper(zone.name)} {zone.icon}`, color = Color3.new(1, 1, 1), scale = 1.5 },
		{ text = `⚡ Recommended Speed: {Format.short(zone.req)}`, color = Color3.fromRGB(255, 232, 90) },
		{ text = `Guardian: {zone.guard}`, color = theme.signText },
	} :: any, theme.sign, Enum.Material.SmoothPlastic)
	flat(folder, "Threshold", 3, Config.CORRIDOR_WIDTH, Vector3.new(x0 + 1.5, GROUND, 0), theme.accent, Enum.Material.Neon, nil, 0.1)
end

local function torii(folder: Instance, x: number, color: Color3, height: number)
	Assets.swap("Spirit_Torii", folder, Assets.facing(Vector3.new(x, GROUND, 0), -Vector3.xAxis), function(into)
		for _, s in { -1, 1 } do
			deco(into, "ToriiPillar", Vector3.new(3, height, 3), CFrame.new(x, GROUND + height / 2, s * (HALF_W - 6)), color, Enum.Material.SmoothPlastic)
			deco(into, "ToriiFoot", Vector3.new(4, 2, 4), CFrame.new(x, GROUND + 1, s * (HALF_W - 6)), Color3.fromRGB(35, 30, 35))
		end
		deco(into, "ToriiBeam", Vector3.new(4, 2.5, Config.CORRIDOR_WIDTH), CFrame.new(x, GROUND + height, 0), color)
		deco(into, "ToriiCap", Vector3.new(5, 1.2, Config.CORRIDOR_WIDTH + 4), CFrame.new(x, GROUND + height + 1.8, 0), Color3.fromRGB(35, 30, 35))
		deco(into, "ToriiBeam", Vector3.new(3, 1.5, Config.CORRIDOR_WIDTH - 12), CFrame.new(x, GROUND + height - 5, 0), color)
	end, Vector3.new(1, 1.5, 0))
end
WorldBuilder.torii = torii

-- The zone's nest. Its gameplay piece is NestCore, an invisible part where the mother bulb glows: it holds
-- the "Mother Plant" label and the tagged Attachments for the nest centre, the pods and the guard's home.
-- The mother plant itself (mound, stones, stem, bulb, leaves) is the Nest_<zone> slot.
local function buildNest(folder: Folder, k: number)
	local zone = Config.ZONES[k]
	local theme = ZoneThemes.theme(k)
	local x = Config.nestX(k)
	local center = Vector3.new(x, GROUND, 0)
	local model = tag(Instance.new("Model"), "Nest", "ZoneIndex", k)
	model.Name = "Nest_" .. zone.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = folder

	-- Non-colliding so neither runners nor the giant snag on it.
	Assets.swap("Nest_" .. zone.id, model, Assets.facing(center, -Vector3.xAxis), function(into)
		cylinder(into, "Mound", 1, 22, center + Vector3.new(0, 0.2, 0), theme.mound, Enum.Material.Ground)
		Props.disc(into, "GlowRing", 26, center, zone.seedColor, Enum.Material.Neon, 0.15)
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2
			Props.rock(into, center + Vector3.new(math.cos(a) * 12.5, 0, math.sin(a) * 12.5), Vector3.new(3, 2.2, 2.6), theme.nestStone, theme.nestStoneMaterial, a, false)
		end
		cylinder(into, "Stem", 14, 2, center + Vector3.new(0, 8, 0), Color3.fromRGB(60, 170, 60), Enum.Material.Grass)
		local bulb = ball(into, "MotherBulb", 8, center + Vector3.new(0, 16, 0), zone.seedColor, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = zone.seedColor
		light.Range = 30
		light.Brightness = 3
		light.Parent = bulb
		for i = 0, 3 do
			local a = i * math.pi / 2 + math.pi / 4
			Props.blob(into, "Leaf", Vector3.new(10, 0.8, 4.5),
				CFrame.new(center + Vector3.new(math.cos(a) * 5, 9, math.sin(a) * 5)) * CFrame.Angles(0, -a, math.rad(20)),
				theme.leaf, Enum.Material.Grass)
		end
		Props.emitOn(bulb, {
			color = zone.seedColor, rate = 6, lifetime = NumberRange.new(1.5, 2.5), speed = NumberRange.new(2, 4),
			size = NumberSequence.new(0.6), spread = Vector2.new(180, 180), lightEmission = 1,
		})
	end, Vector3.new(1, 2, 1))

	local core = tag(hidden(model, "NestCore", Vector3.new(2, 2, 2), CFrame.new(center + Vector3.new(0, 16, 0))), "NestCore", "ZoneIndex", k)
	model.PrimaryPart = core
	billboard(core, `{zone.icon} {zone.seed} Mother Plant`, UDim2.fromOffset(300, 40), Vector3.new(0, 8, 0), 250)
	marker(core, "Center", CFrame.new(center), "NestCenter", "ZoneIndex", k)
	-- Pods ring the mound on the -X half, so thieves grab and run home with the guard behind them.
	for i = 1, Config.PODS_PER_NEST do
		local a = math.pi / 2 + (i - 0.5) * math.pi / Config.PODS_PER_NEST
		marker(core, "Pod" .. i, CFrame.new(center + Vector3.new(math.cos(a) * 8, 2.5, math.sin(a) * 8)), "Pod", "ZoneIndex", k):SetAttribute("PodIndex", i)
	end
	marker(core, "GuardHome", CFrame.new(center + Vector3.new(Config.GUARD_HOME_OFFSET, 0, 0)), "GuardHome", "ZoneIndex", k)
end

local function buildCorridor(world: Folder)
	local corridor = Instance.new("Folder")
	corridor.Name = "Corridor"
	corridor.Parent = world
	local rng = Random.new(20260930)
	local h = Config.WALL_HEIGHT

	for k, zone in Config.ZONES do
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = string.format("%d_%s", k, zone.id)
		zoneFolder.Parent = corridor
		ZoneThemes.build(zoneFolder, k, rng, { torii = torii })
		buildArch(zoneFolder, k)
		buildNest(zoneFolder, k)
	end

	-- End of the line
	local endFolder = Instance.new("Folder")
	endFolder.Name = "End"
	endFolder.Parent = corridor
	box(endFolder, "EndWall", Vector3.new(4, h, Config.CORRIDOR_WIDTH + 8), CFrame.new(Config.END_X + 2, GROUND + h / 2, 0), Color3.fromRGB(210, 40, 45))
	torii(endFolder, Config.END_X - 40, Color3.fromRGB(255, 200, 60), 32)
	local pad = box(endFolder, "EndPad", Vector3.new(30, 1, Config.CORRIDOR_WIDTH - 8), CFrame.new(Config.END_X - 18, GROUND + 0.5, 0),
		Color3.fromRGB(255, 215, 0), Enum.Material.Neon)
	pad.CanCollide = false
	Props.emitter(endFolder, "EndConfetti", Vector3.new(30, 1, Config.CORRIDOR_WIDTH - 8), Vector3.new(Config.END_X - 18, GROUND + 30, 0), {
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 120)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 220, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 200, 255)),
		}),
		rate = 20, lifetime = NumberRange.new(4, 6), speed = NumberRange.new(2, 5), size = NumberSequence.new(0.5),
		direction = Enum.NormalId.Bottom, acceleration = Vector3.new(0, -3, 0), rotSpeed = NumberRange.new(-180, 180), lightEmission = 0.6,
	})
	sign(endFolder, Vector3.new(Config.END_X - 1, GROUND + h - 12, 0), Vector2.new(Config.CORRIDOR_WIDTH - 8, 14), {
		{ text = "⛩️ END OF THE LINE ⛩️", color = Color3.fromRGB(255, 230, 90) },
		{ text = "You made it!", color = Color3.new(1, 1, 1) },
	}, Color3.fromRGB(120, 20, 30))
end

----------------------------------------------------------------------------------------------------
-- Shop plaza: walk-up stalls in the spot after the last plot. Each stall's prompt carries an
-- "OpensShop" attribute; the HUD opens that menu when the local player triggers it.
----------------------------------------------------------------------------------------------------
local STALLS = {
	{ opens = "Shop", label = "🛒 SHOP", color = Color3.fromRGB(255, 90, 160), stripe = Color3.fromRGB(255, 235, 245) },
	{ opens = "Trails", label = "🏃 TRAIL SHOP", color = Color3.fromRGB(60, 160, 255), stripe = Color3.fromRGB(235, 245, 255) },
	{ opens = "Index", label = "📖 INDEX", color = Color3.fromRGB(160, 100, 255), stripe = Color3.fromRGB(245, 235, 255) },
}

local function buildShops(world: Folder)
	local spot = Config.MAX_PLAYERS + 1 -- laid out like one more plot
	local col = (spot - 1) // 2
	local side = if spot % 2 == 1 then 1 else -1
	local center = Vector3.new(Config.PLOT_FIRST_X - col * Config.PLOT_SPACING_X, GROUND, side * Config.PLOT_OFFSET_Z)
	local front = center + Vector3.new(0, 0, -side * Config.PLOT_SIZE / 2)
	local function at(u: number, w: number, y: number): Vector3
		return front + Vector3.new(u, y, side * w)
	end

	local model = Instance.new("Model")
	model.Name = "ShopPlaza"
	model.Parent = world
	flat(model, "Plaza", Config.PLOT_SIZE, Config.PLOT_SIZE, center, STONE, Enum.Material.Pebble, nil, 0.3)
	flat(model, "PlazaPath", 14, math.abs(front.Z) - 19, Vector3.new(center.X, GROUND, side * (19 + (math.abs(front.Z) - 19) / 2)), STONE, Enum.Material.Pebble, nil, 0.3)

	local spacing = 26
	for i, stall in STALLS do
		local u = (i - (#STALLS + 1) / 2) * spacing
		local w0 = 18 -- counter's distance in from the plaza's front edge
		-- The stall (ShopStall_<menu> slot, else ShopStall) faces the walkway.
		Assets.swap("ShopStall_" .. stall.opens, model, Assets.facing(at(u, w0 + 3.5, 0), Vector3.new(0, 0, -side)), function(into)
			box(into, "Counter", Vector3.new(16, 4, 3), CFrame.new(at(u, w0, 2)), stall.color, Enum.Material.WoodPlanks)
			deco(into, "CounterTop", Vector3.new(17, 0.6, 4), CFrame.new(at(u, w0, 4.3)), Color3.fromRGB(250, 245, 235), Enum.Material.SmoothPlastic)
			box(into, "Back", Vector3.new(16, 12, 1), CFrame.new(at(u, w0 + 8, 6)), stall.color, Enum.Material.WoodPlanks)
			for _, du in { -7.5, 7.5 } do
				for _, dw in { -1, 8 } do
					box(into, "Post", Vector3.new(1, 12, 1), CFrame.new(at(u + du, w0 + dw, 6)), Color3.fromRGB(110, 70, 40), Enum.Material.Wood)
				end
			end
			-- Striped awning sloping down toward the walkway
			local tilt = CFrame.Angles(math.rad(-side * 14), 0, 0)
			for s = 0, 7 do
				deco(into, "Awning", Vector3.new(2.25, 0.5, 12), CFrame.new(at(u - 7.875 + s * 2.25, w0 + 2.5, 12.5)) * tilt,
					if s % 2 == 0 then stall.color else stall.stripe, Enum.Material.Fabric)
			end
		end, Vector3.new(1, 1.5, 1.5))
		local signPart = deco(model, "StallSign", Vector3.new(1, 1, 1), CFrame.new(at(u, w0, 17)), stall.color)
		signPart.Transparency = 1
		billboard(signPart, stall.label, UDim2.fromScale(15, 3), Vector3.zero, 90)

		-- The prompt sits on an invisible part at the counter, so it stays when the stall is re-modelled.
		local promptHost = hidden(model, "StallPrompt", Vector3.new(16, 4, 3), CFrame.new(at(u, w0, 2)))
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = stall.label
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OpensShop", stall.opens)
		prompt.Parent = promptHost

		Props.lamp(model, at(u + spacing / 2, 4, 0), Color3.fromRGB(255, 225, 150))
	end
	for _, s in { -1, 1 } do
		Props.flower(model, at(s * 36, 6, 0), FLOWER_COLORS[(s + 2) % #FLOWER_COLORS + 1], 1.6)
		Props.bush(model, at(s * 38, 30, 0), 5, Color3.fromRGB(60, 170, 70))
	end
end

----------------------------------------------------------------------------------------------------
-- Adopting a (hand-edited) map
----------------------------------------------------------------------------------------------------
local function worldCFrame(a: Attachment): CFrame
	return (a.Parent :: BasePart).CFrame * a.CFrame
end

local function findLabel(root: Instance, name: string?): TextLabel?
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") and (name == nil or d.Name == name) then
			return d
		end
	end
	return nil
end

-- Reads everything gameplay needs from a map by its Role attributes (see the header). Returns the plot
-- and nest infos, or nil and the list of problems (which plot or zone, which role) when a required piece
-- is missing. Pieces that turn up twice (e.g. duplicated in Studio) are reported too, and the first wins.
function WorldBuilder.adopt(world: Instance): ({ PlotInfo }?, { NestInfo }?, { string })
	local problems: { string } = {}
	local notes: { string } = {}
	local found: { [string]: Instance } = {}
	for _, d in world:GetDescendants() do
		local role = d:GetAttribute("Role")
		if type(role) ~= "string" then
			continue
		end
		local plot, zone = d:GetAttribute("PlotIndex"), d:GetAttribute("ZoneIndex")
		local scope = if plot then `Plot {plot}` elseif zone then `Zone {zone}` else "World"
		local key = `{scope}/{role}{d:GetAttribute("SlotIndex") or d:GetAttribute("PodIndex") or ""}`
		if found[key] then
			table.insert(notes, `{key}: found twice, using {found[key]:GetFullName()}`)
		else
			found[key] = d
		end
	end

	local function need(scope: string, role: string, class: string, what: string, indexName: string?, index: number?): any
		local inst = found[`{scope}/{role}{index or ""}`]
		if not inst then
			local kind, n = string.match(scope, "^(%a+) (%d+)$")
			local extra = `, {if kind == "Plot" then "PlotIndex" else "ZoneIndex"} = {n}` .. (if indexName then `, {indexName} = {index}` else "")
			table.insert(problems, `{scope}: missing {what} (an instance with attributes Role = "{role}"{extra})`)
			return nil
		end
		if not inst:IsA(class) then
			table.insert(problems, `{scope}: {inst:GetFullName()} has Role "{role}" but is a {inst.ClassName}, not a {class}`)
			return nil
		end
		if inst:IsA("Attachment") and not (inst.Parent and inst.Parent:IsA("BasePart")) then
			table.insert(problems, `{scope}: {inst:GetFullName()} (Role "{role}") must sit inside a part`)
			return nil
		end
		return inst
	end

	local plots: { PlotInfo } = {}
	for i = 1, Config.MAX_PLAYERS do
		local scope = `Plot {i}`
		local model = need(scope, "Plot", "Model", "the plot model")
		local floor = need(scope, "PlotFloor", "BasePart", "the plot floor")
		local pad = need(scope, "PlantPad", "BasePart", "the planting pad")
		local belt = need(scope, "TreadmillBelt", "BasePart", "the treadmill belt")
		local signPart = need(scope, "PlotSign", "BasePart", "the name sign over the gate")
		local tmSign = need(scope, "TreadmillSign", "BasePart", "the treadmill sign")
		local board = need(scope, "UpgradeBoard", "BasePart", "the Upgrade Plot board")
		local spawn = need(scope, "Spawn", "Attachment", "the spawn point")
		local slots = {}
		for s = 1, Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS do
			local a = need(scope, "Slot", "Attachment", `plant slot {s}`, "SlotIndex", s)
			slots[s] = if a then worldCFrame(a) else CFrame.identity
		end
		local signLabel = signPart and findLabel(signPart)
		local tmLabel = tmSign and findLabel(tmSign)
		if signPart and not signLabel then
			table.insert(problems, `{scope}: the name sign {signPart:GetFullName()} has no TextLabel`)
		end
		if tmSign and not tmLabel then
			table.insert(problems, `{scope}: the treadmill sign {tmSign:GetFullName()} has no TextLabel`)
		end
		local labels = {}
		for key, name in { level = "Level", perk = "Perk", price = "Price" } do
			labels[key] = board and findLabel(board, name)
			if board and not labels[key] then
				table.insert(problems, `{scope}: the Upgrade Plot board has no "{name}" TextLabel`)
			end
		end
		if not (model and floor and pad and belt and signLabel and tmLabel and board and spawn and labels.level and labels.perk and labels.price) then
			continue
		end
		-- The plants and soil folders are rebuilt at runtime, so they are made if missing.
		local function folder(role: string): Folder
			local f = found[`{scope}/{role}`]
			if f and f:IsA("Folder") then
				return f
			end
			local made = tag(Instance.new("Folder"), role, "PlotIndex", i)
			made.Name = role
			made.Parent = model
			return made
		end
		plots[i] = {
			index = i,
			model = model,
			center = (floor.CFrame * CFrame.new(0, -floor.Size.Y / 2, 0)).Position,
			signLabel = signLabel,
			pad = pad,
			spawnCFrame = worldCFrame(spawn),
			slotCFrames = slots,
			belt = belt,
			treadmillLabel = tmLabel,
			soil = folder("Soil"),
			plants = folder("Plants"),
			upgradeBoard = board,
			upgradeLabels = labels :: any,
		}
	end

	local nests: { NestInfo } = {}
	for k in Config.ZONES do
		local scope = `Zone {k}`
		local model = need(scope, "Nest", "Model", "the nest model")
		local center = need(scope, "NestCenter", "Attachment", "the nest centre")
		local home = need(scope, "GuardHome", "Attachment", "the guard's home")
		local pods = {}
		for p = 1, Config.PODS_PER_NEST do
			local a = need(scope, "Pod", "Attachment", `seed pod {p}`, "PodIndex", p)
			pods[p] = if a then CFrame.new(worldCFrame(a).Position) else CFrame.identity
		end
		if model and center and home then
			nests[k] = {
				zone = k,
				model = model,
				center = worldCFrame(center).Position,
				podCFrames = pods,
				guardHome = worldCFrame(home).Position,
			}
		end
	end

	if #problems > 0 then
		for _, n in notes do
			table.insert(problems, n)
		end
		return nil, nil, problems
	end
	return plots, nests, notes
end

-- Generates the map from code into Workspace.World, replacing any map there, and adopts it. Also runs in
-- Studio edit mode (Command Bar): require(game.ServerScriptService.Server.WorldBuilder).build(). That
-- REPLACES the hand-edited map in the open place; tools/build_map.luau --force does it for map/World.rbxm.
function WorldBuilder.build(): ({ PlotInfo }, { NestInfo })
	Assets.audit()
	local old = workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "World"
	buildBase(world)
	for i = 1, Config.MAX_PLAYERS do
		buildPlot(world, i)
	end
	buildShops(world)
	buildCorridor(world)
	world.Parent = workspace
	local plots, nests, problems = WorldBuilder.adopt(world)
	assert(plots and nests, "the generated map breaks its own contract:\n" .. table.concat(problems, "\n"))
	return plots, nests
end

-- Server start: adopts the map in the place (Workspace.World, from map/World.rbxm) with every hand edit,
-- puts the assets folder's models into the pieces still built from code, and only regenerates the map
-- when a piece gameplay needs is missing.
function WorldBuilder.load(): ({ PlotInfo }, { NestInfo })
	local world = workspace:FindFirstChild("World")
	if world then
		local plots, nests, problems = WorldBuilder.adopt(world)
		if plots and nests then
			for _, note in problems do
				warn("[WorldBuilder] " .. note)
			end
			Assets.refresh(world)
			return plots, nests
		end
		warn("[WorldBuilder] Workspace.World is missing pieces the game needs, so this server regenerates the map from code"
			.. " (hand edits are not used until they are fixed in map/World.rbxm):\n  " .. table.concat(problems, "\n  "))
	else
		warn("[WorldBuilder] no Workspace.World in the place, so the map is generated from code")
	end
	return WorldBuilder.build()
end

-- Is `pos` standing on this plot's treadmill belt?
function WorldBuilder.onBelt(belt: BasePart, pos: Vector3): boolean
	local rel = belt.CFrame:PointToObjectSpace(pos)
	local size = belt.Size
	return math.abs(rel.X) <= size.X / 2 and math.abs(rel.Z) <= size.Z / 2 and rel.Y >= 0 and rel.Y <= 7
end

return WorldBuilder
