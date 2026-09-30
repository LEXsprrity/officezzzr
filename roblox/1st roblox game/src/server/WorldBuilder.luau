-- Generates the whole map from primitives: base area with 8 fenced plots (each with a treadmill),
-- the walled corridor split into themed zones with signs, a mother-plant nest per zone, and the End.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

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

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function box(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	return part({ Name = name, Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic, Parent = parent })
end

local function ball(parent: Instance, name: string, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	return part({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = CFrame.new(pos),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})
end

local function cylinder(parent: Instance, name: string, height: number, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	-- Cylinders run along local X, so rotate them upright.
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})
end

-- A board facing -X (toward players coming from base) with big text lines.
local function sign(parent: Instance, pos: Vector3, size: Vector2, lines: { { text: string, color: Color3 } }, boardColor: Color3)
	local board = box(parent, "Sign", Vector3.new(size.X, size.Y, 1), CFrame.lookAt(pos, pos - Vector3.xAxis), boardColor)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = board
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = gui
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1 / #lines)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = line.text
		label.TextColor3 = line.color
		label.LayoutOrder = i
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
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
-- Base area
----------------------------------------------------------------------------------------------------
local function buildBase(world: Folder)
	local base = Instance.new("Folder")
	base.Name = "Base"
	base.Parent = world

	local len = Config.CORRIDOR_START_X - BASE_MIN_X
	box(base, "Ground", Vector3.new(len, 4, BASE_HALF_Z * 2),
		CFrame.new(BASE_MIN_X + len / 2, GROUND - 2, 0), Color3.fromRGB(110, 200, 90), Enum.Material.Grass)
	box(base, "Walkway", Vector3.new(len, 0.2, 36),
		CFrame.new(BASE_MIN_X + len / 2, GROUND + 0.1, 0), Color3.fromRGB(235, 220, 180), Enum.Material.Pebble)

	-- Perimeter walls, leaving the corridor mouth open at +X.
	local wallColor = Color3.fromRGB(255, 255, 255)
	local h = Config.WALL_HEIGHT
	box(base, "WallBack", Vector3.new(4, h, BASE_HALF_Z * 2), CFrame.new(BASE_MIN_X - 2, GROUND + h / 2, 0), wallColor)
	for _, s in { -1, 1 } do
		box(base, "WallSide", Vector3.new(len, h, 4), CFrame.new(BASE_MIN_X + len / 2, GROUND + h / 2, s * (BASE_HALF_Z + 2)), wallColor)
		local frontLen = BASE_HALF_Z - HALF_W
		box(base, "WallFront", Vector3.new(4, h, frontLen),
			CFrame.new(Config.CORRIDOR_START_X + 2, GROUND + h / 2, s * (HALF_W + frontLen / 2)), wallColor)
	end
	for _, w in base:GetChildren() do
		if w.Name:sub(1, 4) == "Wall" then
			(w :: BasePart).Transparency = 0.6
		end
	end

	sign(base, Vector3.new(Config.CORRIDOR_START_X - 6, GROUND + 20, 0), Vector2.new(40, 10), {
		{ text = "🌱 STEAL A SEED 🌱", color = Color3.fromRGB(255, 240, 120) },
		{ text = "Grab a seed. Run. Plant it. Get faster.", color = Color3.new(1, 1, 1) },
	}, Color3.fromRGB(60, 150, 70))
end

local function slotLocal(i: number): (number, number)
	local row = (i - 1) // Config.SLOT_COLUMNS
	local col = (i - 1) % Config.SLOT_COLUMNS
	local u = (col - (Config.SLOT_COLUMNS - 1) / 2) * Config.SLOT_SPACING
	return u, 46 + row * Config.SLOT_SPACING
end

local PLOT_COLORS = {
	Color3.fromRGB(255, 120, 120), Color3.fromRGB(120, 170, 255), Color3.fromRGB(255, 210, 90), Color3.fromRGB(160, 110, 255),
	Color3.fromRGB(110, 225, 160), Color3.fromRGB(255, 150, 210), Color3.fromRGB(255, 160, 80), Color3.fromRGB(110, 220, 230),
}

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

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = world
	local color = PLOT_COLORS[index]

	local floor = box(model, "Floor", Vector3.new(Config.PLOT_SIZE, 1, Config.PLOT_SIZE), CFrame.new(center + Vector3.new(0, 0.5, 0)),
		color:Lerp(Color3.new(1, 1, 1), 0.55), Enum.Material.SmoothPlastic)
	model.PrimaryPart = floor

	-- Fence with a 20-stud gate on the walkway side
	local fenceH, fenceColor = 5, Color3.fromRGB(255, 255, 255)
	box(model, "Fence", Vector3.new(Config.PLOT_SIZE, fenceH, 1), CFrame.new(center + Vector3.new(0, fenceH / 2 + 1, -toWalk * half)), fenceColor)
	for _, sx in { -1, 1 } do
		box(model, "Fence", Vector3.new(1, fenceH, Config.PLOT_SIZE), CFrame.new(center + Vector3.new(sx * half, fenceH / 2 + 1, 0)), fenceColor)
		local seg = (Config.PLOT_SIZE - 20) / 2
		box(model, "Fence", Vector3.new(seg, fenceH, 1), CFrame.new(entrance + Vector3.new(sx * (10 + seg / 2), fenceH / 2 + 1, 0)), fenceColor)
		box(model, "GatePost", Vector3.new(2, 9, 2), CFrame.new(entrance + Vector3.new(sx * 10, 5.5, 0)), color)
	end

	-- House-icon sign over the gate
	local signPart = box(model, "SignPost", Vector3.new(1, 1, 1), CFrame.new(entrance + Vector3.new(0, 12, 0)), color)
	signPart.Transparency = 1
	signPart.CanCollide = false
	local signLabel = billboard(signPart, "🏠 Empty Plot", UDim2.fromOffset(260, 60), Vector3.zero, 400)

	-- Planting pad just inside the gate
	local pad = box(model, "PlantPad", Vector3.new(10, 1, 10), CFrame.new(at(0, 10, 1.2)), Color3.fromRGB(120, 80, 50), Enum.Material.Ground)

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
local function decorate(folder: Folder, k: number, rng: Random)
	local zone = Config.ZONES[k]
	local x0 = Config.zoneStartX(k)
	local count = math.floor(zone.length / 70)
	for _ = 1, count do
		local x = x0 + rng:NextNumber(20, zone.length - 20)
		local z = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(HALF_W - 12, HALF_W - 3)
		local p = Vector3.new(x, GROUND, z)
		if zone.id == "Meadow" then
			cylinder(folder, "Stem", 3, 0.4, p + Vector3.new(0, 1.5, 0), Color3.fromRGB(60, 150, 50))
			ball(folder, "Flower", 2, p + Vector3.new(0, 3.3, 0), Color3.fromHSV(rng:NextNumber(), 0.6, 1))
			ball(folder, "Bush", 5, p + Vector3.new(rng:NextNumber(-3, 3), 1.5, 0), Color3.fromRGB(70, 170, 60), Enum.Material.Grass)
		elseif zone.id == "Desert" then
			local h = rng:NextNumber(6, 12)
			cylinder(folder, "Cactus", h, 3, p + Vector3.new(0, h / 2, 0), Color3.fromRGB(60, 150, 70), Enum.Material.Grass)
			cylinder(folder, "Arm", 4, 1.6, p + Vector3.new(1.5, h * 0.6, 0), Color3.fromRGB(60, 150, 70), Enum.Material.Grass)
			ball(folder, "Rock", rng:NextNumber(3, 6), p + Vector3.new(rng:NextNumber(-4, 4), 0.5, 0), Color3.fromRGB(190, 140, 90), Enum.Material.Sandstone)
		elseif zone.id == "Jungle" then
			local h = rng:NextNumber(14, 26)
			cylinder(folder, "Trunk", h, 2.5, p + Vector3.new(0, h / 2, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
			ball(folder, "Canopy", rng:NextNumber(10, 16), p + Vector3.new(0, h, 0), Color3.fromRGB(40, 140, 50), Enum.Material.LeafyGrass)
		elseif zone.id == "Lava" then
			local pool = cylinder(folder, "LavaPool", 0.3, rng:NextNumber(6, 12), p + Vector3.new(0, 0.1, 0), Color3.fromRGB(255, 100, 20), Enum.Material.Neon)
			pool.CanTouch = false
			ball(folder, "Rock", rng:NextNumber(4, 8), p + Vector3.new(rng:NextNumber(-5, 5), 1, 0), Color3.fromRGB(50, 35, 35), Enum.Material.Basalt)
		elseif zone.id == "Snow" then
			for i = 0, 2 do
				local s = 8 - i * 2.5
				box(folder, "Pine", Vector3.new(s, 3, s), CFrame.new(p + Vector3.new(0, 3 + i * 3, 0)) * CFrame.Angles(0, math.rad(45), 0),
					Color3.fromRGB(40, 110, 70), Enum.Material.Grass).CanCollide = false
			end
			ball(folder, "Snowball", rng:NextNumber(3, 6), p + Vector3.new(rng:NextNumber(-4, 4), 1, 0), Color3.fromRGB(250, 250, 255), Enum.Material.Snow)
		elseif zone.id == "Space" then
			ball(folder, "Orb", rng:NextNumber(2, 5), p + Vector3.new(0, rng:NextNumber(8, 30), 0), Color3.fromHSV(rng:NextNumber(0.55, 0.85), 0.7, 1), Enum.Material.Neon)
			box(folder, "Crystal", Vector3.new(2, rng:NextNumber(4, 9), 2), CFrame.new(p + Vector3.new(0, 3, 0)) * CFrame.Angles(0.3, rng:NextNumber(0, 6), 0.2),
				Color3.fromRGB(150, 120, 255), Enum.Material.Glass).CanCollide = false
		else -- Spirit Garden
			cylinder(folder, "Trunk", 10, 1.5, p + Vector3.new(0, 5, 0), Color3.fromRGB(90, 50, 40), Enum.Material.Wood)
			ball(folder, "Blossom", rng:NextNumber(8, 12), p + Vector3.new(0, 11, 0), Color3.fromRGB(255, 170, 200), Enum.Material.Grass)
			local lantern = box(folder, "Lantern", Vector3.new(1.5, 2, 1.5), CFrame.new(p + Vector3.new(3, 2, 0)), Color3.fromRGB(255, 200, 90), Enum.Material.Neon)
			lantern.CanCollide = false
		end
	end
end

local function torii(folder: Instance, x: number, color: Color3, height: number)
	for _, s in { -1, 1 } do
		box(folder, "ToriiPillar", Vector3.new(3, height, 3), CFrame.new(x, GROUND + height / 2, s * (HALF_W - 6)), color)
	end
	box(folder, "ToriiBeam", Vector3.new(4, 2.5, Config.CORRIDOR_WIDTH), CFrame.new(x, GROUND + height, 0), color)
	box(folder, "ToriiBeam", Vector3.new(3, 1.5, Config.CORRIDOR_WIDTH - 12), CFrame.new(x, GROUND + height - 5, 0), color)
end

local function buildNest(folder: Folder, k: number): NestInfo
	local zone = Config.ZONES[k]
	local x = Config.nestX(k)
	local center = Vector3.new(x, GROUND, 0)
	local model = Instance.new("Model")
	model.Name = "Nest_" .. zone.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = folder

	-- Non-colliding so neither runners nor the giant snag on it.
	local mound = cylinder(model, "Mound", 1, 22, center + Vector3.new(0, 0.2, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Ground)
	model.PrimaryPart = mound
	cylinder(model, "Stem", 14, 2, center + Vector3.new(0, 8, 0), Color3.fromRGB(60, 160, 60), Enum.Material.Grass)
	local bulb = ball(model, "MotherBulb", 8, center + Vector3.new(0, 16, 0), zone.seedColor, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = zone.seedColor
	light.Range = 30
	light.Brightness = 3
	light.Parent = bulb
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local leaf = box(model, "Leaf", Vector3.new(9, 0.6, 4),
			CFrame.new(center + Vector3.new(math.cos(a) * 5, 9, math.sin(a) * 5)) * CFrame.Angles(0, -a, math.rad(20)),
			Color3.fromRGB(70, 190, 70), Enum.Material.Grass)
		leaf.CanCollide = false
	end
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
		local x0 = Config.zoneStartX(k)
		local mid = x0 + zone.length / 2
		box(zoneFolder, "Floor", Vector3.new(zone.length, 4, Config.CORRIDOR_WIDTH), CFrame.new(mid, GROUND - 2, 0),
			zone.floor, (Enum.Material :: any)[zone.material])
		for _, s in { -1, 1 } do
			box(zoneFolder, "Wall", Vector3.new(zone.length, h, 4), CFrame.new(mid, GROUND + h / 2, s * (HALF_W + 2)),
				zone.wall, Enum.Material.SmoothPlastic)
		end

		-- Gate arch + sign with the recommended Speed
		local gateColor = zone.guardColor
		for _, s in { -1, 1 } do
			box(zoneFolder, "GatePillar", Vector3.new(4, h, 4), CFrame.new(x0 + 2, GROUND + h / 2, s * (HALF_W - 2)), gateColor)
		end
		sign(zoneFolder, Vector3.new(x0 + 2, GROUND + h - 7, 0), Vector2.new(Config.CORRIDOR_WIDTH - 8, 12), {
			{ text = `{zone.icon} {string.upper(zone.name)}`, color = Color3.new(1, 1, 1) },
			{ text = `Recommended Speed: {Format.short(zone.req)}`, color = Color3.fromRGB(255, 230, 90) },
			{ text = `Guardian: {zone.guard}`, color = Color3.fromRGB(255, 170, 170) },
		}, gateColor:Lerp(Color3.new(0, 0, 0), 0.35))

		if zone.id == "Spirit" then
			for i = 1, 5 do
				torii(zoneFolder, x0 + i * zone.length / 6, Color3.fromRGB(210, 40, 45), 26)
			end
		end
		decorate(zoneFolder, k, rng)
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
