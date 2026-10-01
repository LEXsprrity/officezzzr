-- Generates the whole map from primitives: base area with 8 fenced plots (each with a treadmill),
-- the walled corridor split into themed zones (ZoneThemes) with entry arches, a mother-plant nest
-- per zone, and the End. Decoration is anchored and non-colliding (see Props).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))
local Props = require(script.Parent:WaitForChild("Props"))
local ZoneThemes = require(script.Parent:WaitForChild("ZoneThemes"))

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
	soil: Folder,
	plants: Folder,
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
local BASE_MIN_X = Config.PLOT_FIRST_X - Config.PLOT_SPACING_X * 3 - Config.PLOT_SIZE / 2 - 40
local BASE_HALF_Z = Config.PLOT_OFFSET_Z + Config.PLOT_SIZE / 2 + 20

local box, deco, ball, cylinder, flat = Props.box, Props.deco, Props.ball, Props.cylinder, Props.flat

-- A board facing -X (toward players coming from base) with big text lines.
local function sign(parent: Instance, pos: Vector3, size: Vector2, lines: { { text: string, color: Color3 } }, boardColor: Color3, material: Enum.Material?)
	local board = box(parent, "Sign", Vector3.new(size.X, size.Y, 1), CFrame.lookAt(pos, pos - Vector3.xAxis), boardColor, material)
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
	local rot = CFrame.lookAt(Vector3.zero, along) -- local Z along the wall, X across it
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

	sign(base, Vector3.new(Config.CORRIDOR_START_X - 6, GROUND + 22, 0), Vector2.new(44, 12), {
		{ text = "🌱 STEAL A SEED 🌱", color = Color3.fromRGB(255, 240, 120), scale = 1.4 },
		{ text = "Grab a seed. Run. Plant it. Get faster.", color = Color3.new(1, 1, 1) },
	} :: any, Color3.fromRGB(70, 170, 80))

	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = base

	-- Street lamps along the walkway, between the plot paths
	for col = 0, 4 do
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
	for col = 0, 2 do
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
		Props.roundTree(props, Vector3.new(-12, GROUND, s * 118), rng, Color3.fromRGB(255, 150, 190), 12) -- a blossom tree
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

local function buildPlot(world: Folder, index: number): PlotInfo
	local col = (index - 1) // 2
	local side = if index % 2 == 1 then 1 else -1
	local center = Vector3.new(Config.PLOT_FIRST_X - col * Config.PLOT_SPACING_X, GROUND, side * Config.PLOT_OFFSET_Z)
	local half = Config.PLOT_SIZE / 2
	local toWalk = -side -- the entrance faces the walkway at z = 0
	local entrance = center + Vector3.new(0, 0, toWalk * half)
	local function at(u: number, w: number, y: number): Vector3
		return entrance + Vector3.new(u, y, -toWalk * w)
	end
	local facingIn = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -toWalk)) -- rotation looking into the plot
	local rng = Random.new(1000 + index)

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = world
	local color = PLOT_COLORS[index]

	-- Checkered lawn with a border in the plot's colour
	local floor = box(model, "Floor", Vector3.new(Config.PLOT_SIZE, 1, Config.PLOT_SIZE), CFrame.new(center + Vector3.new(0, 0.5, 0)),
		PLOT_GRASS, Enum.Material.Grass)
	model.PrimaryPart = floor
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
		box(model, "GatePost", Vector3.new(2, 9, 2), CFrame.new(entrance + Vector3.new(sx * 10, 5.5, 0)), color, Enum.Material.WoodPlanks)
		ball(model, "GateFinial", 2.6, entrance + Vector3.new(sx * 10, 10.6, 0), color:Lerp(Color3.new(1, 1, 1), 0.35))
	end
	deco(model, "GateArch", Vector3.new(22, 1.6, 1.6), CFrame.new(entrance + Vector3.new(0, 9.6, 0)), color, Enum.Material.WoodPlanks)

	-- Stone path from the gate to the walkway, and on to the pad
	local toWalkway = math.abs(entrance.Z) - 19
	flat(model, "Path", 14, toWalkway, Vector3.new(center.X, GROUND, entrance.Z + toWalk * toWalkway / 2), STONE, Enum.Material.Pebble, nil, 0.3)
	flat(model, "Path", 10, 5, at(0, 2.5, 1), STONE, Enum.Material.Pebble, nil, 0.1)

	-- House-icon sign over the gate
	local signPart = box(model, "SignPost", Vector3.new(1, 1, 1), CFrame.new(entrance + Vector3.new(0, 12, 0)), color)
	signPart.Transparency = 1
	signPart.CanCollide = false
	local signLabel = billboard(signPart, "🏠 Empty Plot", UDim2.fromOffset(260, 60), Vector3.zero, 400)

	-- Planting pad just inside the gate, on a rim in the plot's colour
	local pad = box(model, "PlantPad", Vector3.new(10, 1, 10), CFrame.new(at(0, 10, 1.2)), Color3.fromRGB(120, 80, 50), Enum.Material.Ground)
	flat(model, "PadRim", 12, 12, at(0, 10, 1), color, Enum.Material.SmoothPlastic, nil, 0.3)

	-- Treadmill: a conveyor that pushes toward a stop rail, so standing on it (AFK) keeps you on it.
	local tmU, tmW0, tmLen = 30, 12, 28
	local beltCenter = at(tmU, tmW0 + tmLen / 2, 1.5)
	local belt = box(model, "TreadmillBelt", Vector3.new(8, 1, tmLen), CFrame.new(beltCenter) * facingIn,
		Color3.fromRGB(40, 40, 45), Enum.Material.DiamondPlate)
	belt.AssemblyLinearVelocity = Vector3.new(0, 0, toWalk * 6) -- pushes toward the gate end
	local tex = Instance.new("Texture")
	tex.Name = "Stripes"
	tex.Texture = "rbxasset://textures/SurfaceTextures/DiamondPlate.png"
	tex.Face = Enum.NormalId.Top
	tex.StudsPerTileU = 4
	tex.StudsPerTileV = 4
	tex.Transparency = 0.4
	tex.Parent = belt
	box(model, "TreadmillFrame", Vector3.new(12, 1, tmLen + 4), CFrame.new(beltCenter - Vector3.new(0, 0.6, 0)) * facingIn, Color3.fromRGB(230, 60, 60))
	for _, s in { -1, 1 } do
		box(model, "TreadmillRail", Vector3.new(1, 3, tmLen), CFrame.new(beltCenter + Vector3.new(s * 4.5, 1.5, 0)) * facingIn, Color3.fromRGB(230, 60, 60))
	end
	box(model, "TreadmillStop", Vector3.new(8, 4, 1), CFrame.new(at(tmU, tmW0 - 0.5, 3)), Color3.fromRGB(230, 60, 60))
	local tmSignPart = box(model, "TreadmillSign", Vector3.new(1, 1, 1), CFrame.new(beltCenter + Vector3.new(0, 8, 0)), color)
	tmSignPart.Transparency = 1
	tmSignPart.CanCollide = false
	billboard(tmSignPart, "🏃 TREADMILL", UDim2.fromOffset(160, 36), Vector3.zero, 120)

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

	local slotCFrames = {}
	for i = 1, Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS do
		local u, w = slotLocal(i)
		slotCFrames[i] = CFrame.new(at(u, w, 1)) * facingIn
	end

	local soil = Instance.new("Folder")
	soil.Name = "Soil"
	soil.Parent = model
	local plants = Instance.new("Folder")
	plants.Name = "Plants"
	plants.Parent = model

	return {
		index = index,
		model = model,
		center = center,
		signLabel = signLabel,
		pad = pad,
		spawnCFrame = CFrame.new(at(-24, 12, 4)) * facingIn,
		slotCFrames = slotCFrames,
		belt = belt,
		soil = soil,
		plants = plants,
	}
end

----------------------------------------------------------------------------------------------------
-- Corridor & zones
----------------------------------------------------------------------------------------------------
-- The zone's entry arch: two pillars flush with the walls, a beam over the top, the name sign
-- (name + recommended Speed + guardian) and a glowing threshold line on the floor.
local function buildArch(folder: Instance, k: number)
	local zone = Config.ZONES[k]
	local theme = ZoneThemes.theme(k)
	local x0 = Config.zoneStartX(k)
	local h = Config.WALL_HEIGHT
	local x = x0 + 3
	for _, s in { -1, 1 } do
		box(folder, "GatePillar", Vector3.new(6, h + 10, 6), CFrame.new(x, GROUND + (h + 10) / 2, s * (HALF_W - 1)), theme.arch, theme.archMaterial)
		ball(folder, "PillarCap", 8, Vector3.new(x, GROUND + h + 12, s * (HALF_W - 1)), theme.accent, Enum.Material.Neon)
	end
	deco(folder, "ArchBeam", Vector3.new(7, 5, Config.CORRIDOR_WIDTH + 10), CFrame.new(x, GROUND + h + 6, 0), theme.arch, theme.archMaterial)
	deco(folder, "ArchTrim", Vector3.new(7.4, 1, Config.CORRIDOR_WIDTH + 10.4), CFrame.new(x, GROUND + h + 3.2, 0), theme.accent, Enum.Material.Neon)
	sign(folder, Vector3.new(x - 3.6, GROUND + h - 4, 0), Vector2.new(Config.CORRIDOR_WIDTH - 12, 13), {
		{ text = `{zone.icon} {string.upper(zone.name)} {zone.icon}`, color = Color3.new(1, 1, 1), scale = 1.5 },
		{ text = `⚡ Recommended Speed: {Format.short(zone.req)}`, color = Color3.fromRGB(255, 232, 90) },
		{ text = `Guardian: {zone.guard}`, color = theme.signText },
	} :: any, theme.sign, Enum.Material.SmoothPlastic)
	flat(folder, "Threshold", 3, Config.CORRIDOR_WIDTH, Vector3.new(x0 + 1.5, GROUND, 0), theme.accent, Enum.Material.Neon, nil, 0.1)
	ZoneThemes.archOrnament(folder, k, x)
end

local function torii(folder: Instance, x: number, color: Color3, height: number)
	for _, s in { -1, 1 } do
		deco(folder, "ToriiPillar", Vector3.new(3, height, 3), CFrame.new(x, GROUND + height / 2, s * (HALF_W - 6)), color, Enum.Material.SmoothPlastic)
		deco(folder, "ToriiFoot", Vector3.new(4, 2, 4), CFrame.new(x, GROUND + 1, s * (HALF_W - 6)), Color3.fromRGB(35, 30, 35))
	end
	deco(folder, "ToriiBeam", Vector3.new(4, 2.5, Config.CORRIDOR_WIDTH), CFrame.new(x, GROUND + height, 0), color)
	deco(folder, "ToriiCap", Vector3.new(5, 1.2, Config.CORRIDOR_WIDTH + 4), CFrame.new(x, GROUND + height + 1.8, 0), Color3.fromRGB(35, 30, 35))
	deco(folder, "ToriiBeam", Vector3.new(3, 1.5, Config.CORRIDOR_WIDTH - 12), CFrame.new(x, GROUND + height - 5, 0), color)
end
WorldBuilder.torii = torii

local function buildNest(folder: Folder, k: number): NestInfo
	local zone = Config.ZONES[k]
	local theme = ZoneThemes.theme(k)
	local x = Config.nestX(k)
	local center = Vector3.new(x, GROUND, 0)
	local model = Instance.new("Model")
	model.Name = "Nest_" .. zone.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = folder

	-- Non-colliding so neither runners nor the giant snag on it.
	local mound = cylinder(model, "Mound", 1, 22, center + Vector3.new(0, 0.2, 0), theme.mound, Enum.Material.Ground)
	model.PrimaryPart = mound
	Props.disc(model, "GlowRing", 26, center, zone.seedColor, Enum.Material.Neon, 0.15)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		Props.rock(model, center + Vector3.new(math.cos(a) * 12.5, 0, math.sin(a) * 12.5), Vector3.new(3, 2.2, 2.6), theme.nestStone, theme.nestStoneMaterial, a)
	end
	cylinder(model, "Stem", 14, 2, center + Vector3.new(0, 8, 0), Color3.fromRGB(60, 170, 60), Enum.Material.Grass)
	local bulb = ball(model, "MotherBulb", 8, center + Vector3.new(0, 16, 0), zone.seedColor, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = zone.seedColor
	light.Range = 30
	light.Brightness = 3
	light.Parent = bulb
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		Props.blob(model, "Leaf", Vector3.new(10, 0.8, 4.5),
			CFrame.new(center + Vector3.new(math.cos(a) * 5, 9, math.sin(a) * 5)) * CFrame.Angles(0, -a, math.rad(20)),
			theme.leaf, Enum.Material.Grass)
	end
	Props.emitOn(bulb, {
		color = zone.seedColor, rate = 6, lifetime = NumberRange.new(1.5, 2.5), speed = NumberRange.new(2, 4),
		size = NumberSequence.new(0.6), spread = Vector2.new(180, 180), lightEmission = 1,
	})
	billboard(bulb, `{zone.icon} {zone.seed} Mother Plant`, UDim2.fromOffset(300, 40), Vector3.new(0, 8, 0), 250)

	-- Pods ring the mound on the -X half, so thieves grab and run home with the guard behind them.
	local podCFrames = {}
	for i = 1, Config.PODS_PER_NEST do
		local a = math.pi / 2 + (i - 0.5) * math.pi / Config.PODS_PER_NEST
		podCFrames[i] = CFrame.new(center + Vector3.new(math.cos(a) * 8, 2.5, math.sin(a) * 8))
	end

	return {
		zone = k,
		model = model,
		center = center,
		podCFrames = podCFrames,
		guardHome = center + Vector3.new(Config.GUARD_HOME_OFFSET, 0, 0),
	}
end

local function buildCorridor(world: Folder): { NestInfo }
	local corridor = Instance.new("Folder")
	corridor.Name = "Corridor"
	corridor.Parent = world
	local nests = {}
	local rng = Random.new(20260930)
	local h = Config.WALL_HEIGHT

	for k, zone in Config.ZONES do
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = string.format("%d_%s", k, zone.id)
		zoneFolder.Parent = corridor
		ZoneThemes.build(zoneFolder, k, rng, { torii = torii })
		buildArch(zoneFolder, k)
		nests[k] = buildNest(zoneFolder, k)
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

	return nests
end

----------------------------------------------------------------------------------------------------

function WorldBuilder.build(): ({ PlotInfo }, { NestInfo })
	local world = Instance.new("Folder")
	world.Name = "World"
	buildBase(world)
	local plots = {}
	for i = 1, Config.MAX_PLAYERS do
		plots[i] = buildPlot(world, i)
	end
	local nests = buildCorridor(world)
	world.Parent = workspace
	return plots, nests
end

-- Is `pos` standing on this plot's treadmill belt?
function WorldBuilder.onBelt(belt: BasePart, pos: Vector3): boolean
	local rel = belt.CFrame:PointToObjectSpace(pos)
	local size = belt.Size
	return math.abs(rel.X) <= size.X / 2 and math.abs(rel.Z) <= size.Z / 2 and rel.Y >= 0 and rel.Y <= 7
end

return WorldBuilder
