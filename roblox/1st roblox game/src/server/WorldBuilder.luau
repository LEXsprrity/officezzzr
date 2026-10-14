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
local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Icons"))
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
	upgradeBoard: BasePart, -- the "Upgrade" sign at the gate; PlotService adds its prompts and text
	upgradeLabels: UpgradeLabels,
}

-- What PlotService writes on an Upgrade board (WorldBuilder.setUpgradeBoard). `buttons` (the row holding
-- the two buttons, hidden at the last level) is optional, so a hand-made board only needs the labels.
export type UpgradeLabels = { level: TextLabel, cash: TextLabel, robux: TextLabel, buttons: GuiObject? }

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
-- Base area: kept plain so the plants are the show (like a simulator's base). A studded lawn in big
-- checker tiles of two close greens, a soft sand walkway, plain tan checker walls with a grass top, and
-- nothing else on the ground: no trees, bushes, flowers, lamps or rocks.
----------------------------------------------------------------------------------------------------
local GRASS = Color3.fromRGB(106, 196, 50)
local GRASS_LIGHT = Color3.fromRGB(124, 212, 64)
local SAND = Color3.fromRGB(240, 222, 168)
local WALL = Color3.fromRGB(196, 128, 80)
local WALL_LIGHT = Color3.fromRGB(212, 144, 94)
local WALL_TOP = Color3.fromRGB(90, 214, 64)
local FENCE_POST = Color3.fromRGB(84, 64, 58)
local FENCE_RAIL = Color3.fromRGB(198, 108, 56)
local TILE = 14 -- lawn checker; a plot (84 studs) is 6 x 6 tiles
local WALL_ROWS = 4 -- wall checker rows (WALL_HEIGHT 44 → 11-stud tiles)

-- The classic studded plastic look on the given faces (default: the top).
local function studs<T>(p: T, faces: { string }?): T
	(p :: any).Material = Enum.Material.Plastic
	for _, face in faces or { "TopSurface" } do
		(p :: any)[face] = Enum.SurfaceType.Studs
	end
	return p
end

-- Each plot's Upgrade board (docs/references/08-upgrade-sign-reference.png): a dark navy panel in a
-- studded frame, on a short post.
local BOARD_SIZE = Vector2.new(7.6, 4.8)
local BOARD_RIM = 0.8 -- the frame's width
local BOARD_NAVY = Color3.fromRGB(30, 36, 60)
local BOARD_CORNER = Color3.fromRGB(44, 54, 92)
local BOARD_POST = Color3.fromRGB(24, 29, 50)
local BOARD_PPS = 50 -- SurfaceGui pixels per stud
local BOARD_TEXT = {
	open = Color3.fromRGB(110, 240, 70), -- "Level 6 > Level 7"
	max = Color3.fromRGB(255, 210, 60), -- "MAX LEVEL"
	empty = Color3.fromRGB(190, 195, 210), -- nobody owns the plot
}
local BOARD_BUTTONS = {
	{ name = "Cash", text = "$500", fill = Color3.fromRGB(225, 40, 40), edge = Color3.fromRGB(90, 10, 10), width = 0.58 },
	{ name = "Robux", text = "R$ 25", fill = Color3.fromRGB(165, 45, 230), edge = Color3.fromRGB(55, 10, 80), width = 0.38 },
}

-- The board's SurfaceGui, inside the frame: "Upgrade" (white, outlined), "Level X > Level Y" (green) and
-- a row of two buttons, red with the money price and purple with the Robux price. PlotService finds the
-- labels it writes by name: Level, Cash and Robux, and hides the Buttons row at the last level.
local function buildUpgradeGui(board: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BOARD_PPS
	gui.LightInfluence = 0
	gui.MaxDistance = 45
	gui.Parent = board
	local inset = UDim.new(0, math.round((BOARD_RIM + 0.15) * BOARD_PPS))
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = inset
	padding.PaddingRight = inset
	padding.PaddingTop = inset
	padding.PaddingBottom = inset
	padding.Parent = gui
	local function list(parent: Instance, direction: Enum.FillDirection, gap: number)
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = direction
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(gap, 0)
		layout.Parent = parent
	end
	local function text(parent: Instance, name: string, value: string, color: Color3, size: UDim2, order: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Size = size
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = value
		label.TextColor3 = color
		label.LayoutOrder = order
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(15, 15, 25)
		stroke.Parent = label
		label.Parent = parent
		return label
	end
	list(gui, Enum.FillDirection.Vertical, 0.03)
	text(gui, "Title", "Upgrade", Color3.new(1, 1, 1), UDim2.fromScale(1, 0.3), 1)
	text(gui, "Level", "Level 1 > Level 2", BOARD_TEXT.open, UDim2.fromScale(1, 0.22), 2)
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 0.4)
	row.LayoutOrder = 3
	row.Parent = gui
	list(row, Enum.FillDirection.Horizontal, 0.04)
	for i, spec in BOARD_BUTTONS do
		local button = Instance.new("Frame")
		button.Name = spec.name .. "Button"
		button.BackgroundColor3 = spec.fill
		button.Size = UDim2.fromScale(spec.width, 1)
		button.LayoutOrder = i
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
		local edge = Instance.new("UIStroke")
		edge.Thickness = 3
		edge.Color = spec.edge
		edge.Parent = button
		local shine = Instance.new("UIGradient") -- a little lighter at the top, like a raised button
		shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
		shine.Rotation = 90
		shine.Parent = button
		local label = text(button, spec.name, spec.text, Color3.new(1, 1, 1), UDim2.fromScale(0.88, 0.78), 1)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		button.Parent = row
	end
end

-- Plots and the shop plaza (spot MAX_PLAYERS + 1) alternate sides of the walkway, column by column.
local function spotCenter(spot: number): Vector3
	local col = (spot - 1) // 2
	local side = if spot % 2 == 1 then 1 else -1
	return Vector3.new(Config.PLOT_FIRST_X - col * Config.PLOT_SPACING_X, GROUND, side * Config.PLOT_OFFSET_Z)
end

-- Light checker tiles over the area x0..x1, z0..z1 (the dark ones are the floor underneath). Tiles that
-- something else covers completely (`hiddenBy(minX, maxX, minZ, maxZ)` is true) are skipped.
local function checker(parent: Instance, x0: number, x1: number, z0: number, z1: number, y: number,
	hiddenBy: ((number, number, number, number) -> boolean)?)
	for i = 0, math.ceil((x1 - x0) / TILE) - 1 do
		for j = 0, math.ceil((z1 - z0) / TILE) - 1 do
			if (i + j) % 2 == 1 then
				continue
			end
			local ax, bx = x0 + i * TILE, math.min(x0 + (i + 1) * TILE, x1)
			local az, bz = z0 + j * TILE, math.min(z0 + (j + 1) * TILE, z1)
			if hiddenBy and hiddenBy(ax, bx, az, bz) then
				continue
			end
			studs(flat(parent, "LawnTile", bx - ax, bz - az, Vector3.new((ax + bx) / 2, y, (az + bz) / 2), GRASS_LIGHT, nil, nil, 0.1))
		end
	end
end

-- A plain wall: tan studded plastic, a checker of two close tans on its inner face and a strip of grass
-- on top. `inward` points into the base.
local function plainWall(parent: Instance, center: Vector3, along: Vector3, inward: Vector3, len: number)
	local h = Config.WALL_HEIGHT
	local rot = Props.lookAt(Vector3.zero, along) -- local Z along the wall, X across it
	local sides = { "LeftSurface", "RightSurface" }
	studs(box(parent, "Wall", Vector3.new(4, h, len), CFrame.new(center + Vector3.new(0, h / 2, 0)) * rot, WALL), sides)
	studs(deco(parent, "WallTop", Vector3.new(4.4, 1, len), CFrame.new(center + Vector3.new(0, h + 0.5, 0)) * rot, WALL_TOP))
	local n = math.max(1, math.round(len / (h / WALL_ROWS)))
	local w, rh = len / n, h / WALL_ROWS
	local face = center + inward * 2.05
	for i = 0, n - 1 do
		for r = 0, WALL_ROWS - 1 do
			if (i + r) % 2 == 0 then
				local pos = face + along * ((i + 0.5) * w - len / 2) + Vector3.new(0, (r + 0.5) * rh, 0)
				local tile = studs(deco(parent, "WallTile", Vector3.new(0.1, rh, w), CFrame.new(pos) * rot, WALL_LIGHT), sides)
				tile.CastShadow = false
			end
		end
	end
end

local function buildBase(world: Folder)
	local base = Instance.new("Folder")
	base.Name = "Base"
	base.Parent = world

	local len = Config.CORRIDOR_START_X - BASE_MIN_X
	local midX = BASE_MIN_X + len / 2
	studs(box(base, "Ground", Vector3.new(len, 4, BASE_HALF_Z * 2), CFrame.new(midX, GROUND - 2, 0), GRASS))
	-- The lawn checker, minus the tiles under the plots and the walkway.
	local covered = { { -1e9, 1e9, -18, 18 } } -- the walkway (36 wide)
	for spot = 1, Config.MAX_PLAYERS do
		local c = spotCenter(spot)
		local half = Config.PLOT_SIZE / 2
		table.insert(covered, { c.X - half, c.X + half, c.Z - half, c.Z + half })
	end
	local lawn = Instance.new("Folder")
	lawn.Name = "Lawn"
	lawn.Parent = base
	checker(lawn, BASE_MIN_X, Config.CORRIDOR_START_X, -BASE_HALF_Z, BASE_HALF_Z, GROUND, function(ax, bx, az, bz)
		for _, r in covered do
			if ax >= r[1] and bx <= r[2] and az >= r[3] and bz <= r[4] then
				return true
			end
		end
		return false
	end)
	studs(flat(base, "Walkway", len, 36, Vector3.new(midX, GROUND, 0), SAND, nil, nil, 0.3))

	-- Perimeter walls, leaving the corridor mouth open at +X.
	plainWall(base, Vector3.new(BASE_MIN_X - 2, GROUND, 0), Vector3.zAxis, Vector3.xAxis, BASE_HALF_Z * 2 + 8)
	for _, s in { -1, 1 } do
		plainWall(base, Vector3.new(midX, GROUND, s * (BASE_HALF_Z + 2)), Vector3.xAxis, Vector3.new(0, 0, -s), len)
		-- Front walls run on to the outer edge of the side walls, closing the corner.
		local frontLen = BASE_HALF_Z + 4 - HALF_W
		plainWall(base, Vector3.new(Config.CORRIDOR_START_X + 2, GROUND, s * (HALF_W + frontLen / 2)), Vector3.zAxis, -Vector3.xAxis, frontLen)
	end

	-- The big sign floats over the corridor mouth; a drop-in SpawnSign hangs from the same bottom edge.
	local signPos = Vector3.new(Config.CORRIDOR_START_X - 6, GROUND + 22, 0)
	Assets.swap("SpawnSign", base, Assets.facing(signPos - Vector3.new(0, 6, 0), -Vector3.xAxis), function(into)
		sign(into, signPos, Vector2.new(44, 12), {
			{ text = "🌱 STEAL A SEED 🌱", color = Color3.fromRGB(255, 240, 120), scale = 1.4 },
			{ text = "Grab a seed. Run. Plant it. Get faster.", color = Color3.new(1, 1, 1) },
		} :: any, Color3.fromRGB(70, 170, 80))
	end, Vector3.new(1, 1, 0))
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

local function buildPlot(world: Folder, index: number)
	local center = spotCenter(index)
	local side = math.sign(center.Z)
	local half = Config.PLOT_SIZE / 2
	local toWalk = -side -- the entrance faces the walkway at z = 0
	local entrance = center + Vector3.new(0, 0, toWalk * half)
	local function at(u: number, w: number, y: number): Vector3
		return entrance + Vector3.new(u, y, -toWalk * w)
	end
	local facingIn = Props.lookAt(Vector3.zero, Vector3.new(0, 0, -toWalk)) -- rotation looking into the plot

	local model = tag(Instance.new("Model"), "Plot", "PlotIndex", index)
	model.Name = "Plot" .. index
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = world
	local color = PLOT_COLORS[index]

	-- The same studded checker lawn as the base, one stud up, so the fence and the plants frame the plot.
	-- The floor carries the plant slots and the spawn point (tagged Attachments), so they follow it when it
	-- is moved.
	local floor = tag(studs(box(model, "Floor", Vector3.new(Config.PLOT_SIZE, 1, Config.PLOT_SIZE), CFrame.new(center + Vector3.new(0, 0.5, 0)),
		GRASS)), "PlotFloor", "PlotIndex", index)
	model.PrimaryPart = floor
	for i = 1, Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS do
		local u, w = slotLocal(i)
		marker(floor, "Slot" .. i, CFrame.new(at(u, w, 1)) * facingIn, "Slot", "PlotIndex", index):SetAttribute("SlotIndex", i)
	end
	marker(floor, "Spawn", CFrame.new(at(-24, 12, 4)) * facingIn, "Spawn", "PlotIndex", index)
	checker(model, center.X - half, center.X + half, center.Z - half, center.Z + half, GROUND + 1)

	-- Simple wooden fence (dark posts, two warm rails) with a 20-stud gate on the walkway side
	local fenceH, spacing = 4.5, 12
	local y1 = Vector3.new(0, 1, 0)
	local function fence(a: Vector3, b: Vector3)
		Props.fence(model, a + y1, b + y1, fenceH, spacing, FENCE_POST, FENCE_RAIL)
	end
	fence(center + Vector3.new(-half, 0, -toWalk * half), center + Vector3.new(half, 0, -toWalk * half))
	for _, sx in { -1, 1 } do
		fence(center + Vector3.new(sx * half, 0, toWalk * half), center + Vector3.new(sx * half, 0, -toWalk * half))
		fence(entrance + Vector3.new(sx * 11, 0, 0), entrance + Vector3.new(sx * half, 0, 0))
	end
	Assets.swap("PlotGate", model, Assets.facing(entrance + y1, Vector3.new(0, 0, toWalk)), function(into)
		for _, sx in { -1, 1 } do
			box(into, "GatePost", Vector3.new(2, 9, 2), CFrame.new(entrance + Vector3.new(sx * 10, 5.5, 0)), color)
			ball(into, "GateFinial", 2.6, entrance + Vector3.new(sx * 10, 10.6, 0), color:Lerp(Color3.new(1, 1, 1), 0.35))
		end
		deco(into, "GateArch", Vector3.new(22, 1.6, 1.6), CFrame.new(entrance + Vector3.new(0, 9.6, 0)), color)
	end, Vector3.new(1, 1.5, 0))

	-- Sand path from the walkway to the gate, and on to the pad
	local toWalkway = math.abs(entrance.Z) - 18
	studs(flat(model, "Path", 14, toWalkway, Vector3.new(center.X, GROUND, entrance.Z + toWalk * toWalkway / 2), SAND, nil, nil, 0.3))
	studs(flat(model, "Path", 10, 5, at(0, 2.5, 1), SAND, nil, nil, 0.15))

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

	-- "Upgrade" board just outside the gate, beside the path: a chunky dark navy sign on a short post, with
	-- "Level X > Level Y" and two buttons, a red one with the money price and a purple one with the Robux
	-- price. Sized in studs, so it reads only up close. PlotService writes it (WorldBuilder.setUpgradeBoard)
	-- and owns its two prompts. The board (the panel with the text) is the gameplay piece; its studded
	-- frame and post are the UpgradeSign slot.
	local boardPos = at(-17, -4, BOARD_SIZE.Y / 2 + 2)
	local boardCF = Props.lookAt(boardPos, boardPos + Vector3.new(0, 0, toWalk)) -- front face toward the walkway
	Assets.swap("UpgradeSign", model, Assets.facing(Vector3.new(boardPos.X, GROUND, boardPos.Z), Vector3.new(0, 0, toWalk)), function(into)
		local w, h, rim = BOARD_SIZE.X, BOARD_SIZE.Y, BOARD_RIM
		local front = CFrame.new(0, 0, -0.15) -- the frame stands a little proud of the panel
		for _, s in { -1, 1 } do
			studs(deco(into, "UpgradeFrame", Vector3.new(w, rim, 1), boardCF * front * CFrame.new(0, s * (h - rim) / 2, 0), BOARD_NAVY), { "FrontSurface", "TopSurface" })
			studs(deco(into, "UpgradeFrame", Vector3.new(rim, h - 2 * rim, 1), boardCF * front * CFrame.new(s * (w - rim) / 2, 0, 0), BOARD_NAVY), { "FrontSurface" })
			for _, t in { -1, 1 } do
				studs(deco(into, "UpgradeCorner", Vector3.new(rim + 0.2, rim + 0.2, 1.15), boardCF * front * CFrame.new(s * (w - rim) / 2, t * (h - rim) / 2, 0), BOARD_CORNER), { "FrontSurface", "TopSurface" })
			end
		end
		local postHeight = boardPos.Y - GROUND - h / 2 + 0.2
		studs(deco(into, "UpgradePost", Vector3.new(1.4, postHeight, 1), boardCF * CFrame.new(0, -(h / 2 + postHeight / 2 - 0.2), 0.05), BOARD_POST), { "FrontSurface" })
	end, Vector3.new(1.2, 1.5, 0))
	local upgradeBoard = tag(studs(deco(model, "UpgradeBoard", Vector3.new(BOARD_SIZE.X, BOARD_SIZE.Y, 0.6), boardCF, BOARD_NAVY), { "BackSurface" }),
		"UpgradeBoard", "PlotIndex", index)
	buildUpgradeGui(upgradeBoard)

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
	-- Sell old plants (docs/references/09-sell-stall-reference.png): an open wooden stall with a red-and-white
	-- awning, a soft green glowing circle on the floor in front and big red "SELL" text over it. The server
	-- measures the sell distance from its prompt part (WorldBuilder.sellPoints).
	{ opens = "Sell", label = "SELL", color = Color3.fromRGB(225, 35, 45), stripe = Color3.fromRGB(250, 248, 245), action = "Sell plants" },
}
local STALL_SPACING = 21 -- four 18-stud awnings across the 84-stud plaza
local SELL_WOOD = Color3.fromRGB(150, 112, 78)
local SELL_WOOD_DARK = Color3.fromRGB(104, 76, 56)
local SELL_GLOW = Color3.fromRGB(70, 255, 140)
local SELL_TEXT = Color3.fromRGB(235, 30, 40)

-- The SELL stall's look (asset slot ShopStall_Sell, which doesn't fall back to ShopStall): a long plank
-- counter, four posts, a back shelf and the striped awning with a striped valance on its front edge.
local function sellStall(into: Instance, at: (number, number, number) -> Vector3, u: number, w0: number, side: number, stall: { [string]: any })
	box(into, "Counter", Vector3.new(16, 3.4, 2.6), CFrame.new(at(u, w0, 1.7)), SELL_WOOD_DARK, Enum.Material.WoodPlanks)
	box(into, "CounterTop", Vector3.new(17, 0.6, 3.6), CFrame.new(at(u, w0, 3.7)), SELL_WOOD, Enum.Material.WoodPlanks)
	deco(into, "CounterPlank", Vector3.new(16.4, 0.5, 0.4), CFrame.new(at(u, w0 - 1.4, 2.2)), SELL_WOOD, Enum.Material.WoodPlanks)
	deco(into, "Shelf", Vector3.new(16, 0.6, 2), CFrame.new(at(u, w0 + 6.8, 4.5)), SELL_WOOD, Enum.Material.WoodPlanks)
	for _, du in { -7.5, 7.5 } do
		for _, post in { { w = -1, h = 11.4 }, { w = 7, h = 13.4 } } do -- up to the sloping awning
			box(into, "Post", Vector3.new(1, post.h, 1), CFrame.new(at(u + du, w0 + post.w, post.h / 2)), SELL_WOOD_DARK, Enum.Material.Wood)
		end
	end
	local tilt = CFrame.Angles(math.rad(-side * 14), 0, 0)
	for s = 0, 7 do
		local color = if s % 2 == 0 then stall.color else stall.stripe
		local cf = CFrame.new(at(u - 7.875 + s * 2.25, w0 + 3, 12.6)) * tilt
		deco(into, "Awning", Vector3.new(2.25, 0.5, 11), cf, color, Enum.Material.Fabric)
		deco(into, "Valance", Vector3.new(2.25, 1.2, 0.4), cf * CFrame.new(0, -0.8, -side * 5.4), color, Enum.Material.Fabric)
	end
end

-- The soft green glowing circle in front of the SELL stall: a Neon rim under a lighter, see-through fill.
local function sellCircle(parent: Instance, pos: Vector3)
	local rim = Props.disc(parent, "SellCircle", 17, pos, SELL_GLOW, Enum.Material.Neon, 0.15)
	rim.Transparency = 0.25
	local fill = Props.disc(parent, "SellCircleFill", 14.6, pos, Color3.fromRGB(170, 255, 190), Enum.Material.SmoothPlastic, 0.25)
	fill.Transparency = 0.45
end

local function buildShops(world: Folder)
	local center = spotCenter(Config.MAX_PLAYERS + 1) -- laid out like one more plot
	local side = math.sign(center.Z)
	local front = center + Vector3.new(0, 0, -side * Config.PLOT_SIZE / 2)
	local function at(u: number, w: number, y: number): Vector3
		return front + Vector3.new(u, y, side * w)
	end

	local model = Instance.new("Model")
	model.Name = "ShopPlaza"
	model.Parent = world
	-- The lawn runs on under the stalls; a sand apron in front of the counters and a path from the walkway.
	local toWalkway = math.abs(front.Z) - 18
	studs(flat(model, "PlazaPath", 14, toWalkway, Vector3.new(center.X, GROUND, side * (18 + toWalkway / 2)), SAND, nil, nil, 0.3))
	studs(flat(model, "Plaza", Config.PLOT_SIZE, 22, at(0, 11, 0), SAND, nil, nil, 0.3))

	for i, stall in STALLS do
		local u = (i - (#STALLS + 1) / 2) * STALL_SPACING
		local w0 = 18 -- counter's distance in from the plaza's front edge
		local selling = stall.opens == "Sell"
		-- The stall (ShopStall_<menu> slot, else ShopStall) faces the walkway.
		Assets.swap("ShopStall_" .. stall.opens, model, Assets.facing(at(u, w0 + 3.5, 0), Vector3.new(0, 0, -side)), function(into)
			if selling then
				sellStall(into, at, u, w0, side, stall)
				return
			end
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
		local signPart = deco(model, "StallSign", Vector3.new(1, 1, 1), CFrame.new(at(u, w0, if selling then 18 else 17)), stall.color)
		signPart.Transparency = 1
		local signLabel = billboard(signPart, stall.label, if selling then UDim2.fromScale(13, 4.6) else UDim2.fromScale(15, 3), Vector3.zero, 90)
		if selling then -- big red "SELL" with a dark outline, like the reference
			signLabel.TextColor3 = SELL_TEXT
			local stroke = signLabel:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Thickness = 5
			stroke.Color = Color3.fromRGB(70, 8, 12)
			sellCircle(model, at(u, 7, 0.3)) -- on the plaza's sand, in front of the counter
		end

		-- The prompt sits on an invisible part at the counter, so it stays when the stall is re-modelled.
		local promptHost = hidden(model, "StallPrompt", Vector3.new(16, 4, 3), CFrame.new(at(u, w0, 2)))
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = stall.action or "Open"
		prompt.ObjectText = stall.label
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OpensShop", stall.opens)
		prompt.Parent = promptHost
	end
end

----------------------------------------------------------------------------------------------------
-- Community rewards corner (docs/references/06-free-chest-and-leaderboard.png): the FREE chest on a green
-- glowing circle and the tall "MOST MONEY/s" board, against the inside of the front wall on the -Z side
-- of the corridor mouth, by the spawn. Every run to the corridor passes it, and it is off the walkway,
-- the plots and the plaza. RewardService finds both by their Role (WorldBuilder.rewardPoints).
----------------------------------------------------------------------------------------------------
local CHEST_POS = Vector3.new(Config.CORRIDOR_START_X - 10, GROUND, -(HALF_W + 32)) -- ground point under the chest
local MONEY_BOARD_POS = Vector3.new(Config.CORRIDOR_START_X - 4, GROUND, -(HALF_W + 14)) -- ground point under the board
local MONEY_PANEL = Vector2.new(12, 18) -- the list panel (studs); its bottom edge is 4 studs up
local MONEY_PPS = 40
local CHEST_RED = Color3.fromRGB(205, 45, 40)
local CHEST_GOLD = Color3.fromRGB(255, 196, 40)
local FREE_GREEN = Color3.fromRGB(90, 255, 70)
local BOARD_CYAN = Color3.fromRGB(95, 205, 255)
local BOARD_BLUE = Color3.fromRGB(40, 125, 235)

-- The chest's look (asset slot FreeChest): a red chest with a round lid, gold bands, lock and a green gem.
-- `cf` is the ground point under it, front (-Z) toward the base.
local function freeChest(into: Instance, cf: CFrame)
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?)
		local p = deco(into, name, size, cf * offset, color)
		if shape then
			p.Shape = shape
		end
		return p
	end
	piece("ChestBody", Vector3.new(6.4, 3.2, 4.2), CFrame.new(0, 1.9, 0), CHEST_RED)
	piece("ChestLid", Vector3.new(6.4, 4.2, 4.2), CFrame.new(0, 3.5, 0), CHEST_RED, Enum.PartType.Cylinder) -- along X: a half-round lid
	piece("ChestBase", Vector3.new(6.8, 0.5, 4.6), CFrame.new(0, 0.55, 0), CHEST_GOLD)
	piece("ChestRim", Vector3.new(6.8, 0.4, 4.6), CFrame.new(0, 3.4, 0), CHEST_GOLD)
	for _, x in { -2.2, 2.2 } do
		piece("ChestBand", Vector3.new(0.6, 3.2, 4.5), CFrame.new(x, 1.9, 0), CHEST_GOLD)
		piece("LidBand", Vector3.new(0.6, 4.5, 4.5), CFrame.new(x, 3.5, 0), CHEST_GOLD, Enum.PartType.Cylinder)
	end
	piece("ChestLock", Vector3.new(1.4, 1.6, 0.3), CFrame.new(0, 3.0, -2.2), CHEST_GOLD)
	piece("Keyhole", Vector3.new(0.35, 0.7, 0.1), CFrame.new(0, 2.85, -2.38), Color3.fromRGB(40, 25, 20))
	piece("ChestGem", Vector3.new(1, 0.5, 1), CFrame.new(0, 5.75, 0), Color3.fromRGB(60, 220, 80))
end

-- The board's frame (asset slot MoneyBoard): a studded cyan frame with a stepped blue cap on a pedestal.
-- `panelCF` is the panel's centre, front toward the base.
local function moneyBoardFrame(into: Instance, panelCF: CFrame)
	local w, h, rim = MONEY_PANEL.X, MONEY_PANEL.Y, 1
	local back = CFrame.new(0, 0, 0.2)
	for _, s in { -1, 1 } do
		studs(deco(into, "BoardRim", Vector3.new(rim, h + 2 * rim, 1.2), panelCF * back * CFrame.new(s * (w + rim) / 2, 0, 0), BOARD_CYAN), { "FrontSurface" })
		studs(deco(into, "BoardRim", Vector3.new(w, rim, 1.2), panelCF * back * CFrame.new(0, s * (h + rim) / 2, 0), BOARD_CYAN), { "FrontSurface", "TopSurface" })
	end
	studs(deco(into, "BoardCap", Vector3.new(w + 4, 1.6, 1.8), panelCF * back * CFrame.new(0, h / 2 + rim + 0.8, 0), BOARD_BLUE), { "FrontSurface", "TopSurface" })
	studs(deco(into, "BoardCap", Vector3.new(w - 3, 1.2, 1.6), panelCF * back * CFrame.new(0, h / 2 + rim + 2.2, 0), BOARD_CYAN), { "FrontSurface", "TopSurface" })
	local foot = panelCF.Position.Y - h / 2 - rim -- the frame's bottom, above the pedestal
	studs(box(into, "BoardPedestal", Vector3.new(w + 1, foot - GROUND, 4), panelCF * CFrame.new(0, -(h / 2 + rim) - (foot - GROUND) / 2, 0.4),
		Color3.fromRGB(165, 222, 255)), { "FrontSurface", "TopSurface" })
end

-- The board's SurfaceGui: the green "MOST MONEY/s" title, a dark list of Config.MONEY_BOARD_ROWS white rows
-- (Rank, Name, a green "Money/s" tag and the Value) and a Status line ("Loading...", then where the list
-- comes from). RewardService finds them by name and writes them (WorldBuilder.setMoneyBoard).
local function buildMoneyBoardGui(panel: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = MONEY_PPS
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = panel
	local function label(parent: Instance, name: string, value: string, color: Color3, size: UDim2, pos: UDim2, stroke: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Size = size
		l.Position = pos
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = value
		l.TextColor3 = color
		if stroke > 0 then
			local s = Instance.new("UIStroke")
			s.Thickness = stroke
			s.Color = Color3.fromRGB(15, 40, 20)
			s.Parent = l
		end
		l.Parent = parent
		return l
	end
	label(gui, "Title", "MOST MONEY/s", Color3.fromRGB(140, 255, 60), UDim2.fromScale(0.96, 0.1), UDim2.fromScale(0.02, 0.01), 4)
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundColor3 = Color3.fromRGB(18, 22, 38)
	list.Size = UDim2.fromScale(0.92, 0.82)
	list.Position = UDim2.fromScale(0.04, 0.12)
	list.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = list
	local rows = Config.MONEY_BOARD_ROWS
	for i = 1, rows do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BackgroundColor3 = Color3.fromRGB(245, 247, 252)
		row.Size = UDim2.new(0.94, 0, 1 / rows, -6)
		row.Position = UDim2.new(0.03, 0, (i - 1) / rows, 3)
		row.Visible = false
		row.Parent = list
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 6)
		rc.Parent = row
		label(row, "Rank", tostring(i), Color3.fromRGB(255, 205, 40), UDim2.fromScale(0.12, 0.8), UDim2.fromScale(0.01, 0.1), 2)
		local name = label(row, "Name", "", Color3.fromRGB(25, 25, 35), UDim2.fromScale(0.5, 0.62), UDim2.fromScale(0.14, 0.19), 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local tag = Instance.new("Frame")
		tag.Name = "Tag"
		tag.BackgroundColor3 = Color3.fromRGB(70, 205, 90)
		tag.Size = UDim2.fromScale(0.32, 0.36)
		tag.Position = UDim2.fromScale(0.66, 0.06)
		tag.Parent = row
		local tc = Instance.new("UICorner")
		tc.CornerRadius = UDim.new(0, 4)
		tc.Parent = tag
		label(tag, "TagText", "Money/s", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.9), UDim2.fromScale(0.05, 0.05), 0)
		label(row, "Value", "", Color3.fromRGB(25, 25, 35), UDim2.fromScale(0.32, 0.5), UDim2.fromScale(0.66, 0.46), 0)
	end
	label(gui, "Status", "Loading...", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.05), UDim2.fromScale(0.05, 0.945), 2)
end

local function buildRewards(world: Folder)
	local model = Instance.new("Model")
	model.Name = "Rewards"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = world
	local toBase = -Vector3.xAxis

	-- The chest on its green circle, "FREE!" above it and a countdown under that (written on each client:
	-- the cooldown is per player). The prompt sits on an invisible part, so it stays when re-modelled.
	local chestCF = Assets.facing(CHEST_POS + Vector3.new(0, 0.3, 0), toBase)
	local rimDisc = Props.disc(model, "ChestCircle", 11, CHEST_POS, FREE_GREEN, Enum.Material.Neon, 0.15)
	rimDisc.Transparency = 0.25
	local fill = Props.disc(model, "ChestCircleFill", 9, CHEST_POS, Color3.fromRGB(170, 255, 190), Enum.Material.SmoothPlastic, 0.25)
	fill.Transparency = 0.45
	Assets.swap("FreeChest", model, chestCF, function(into)
		freeChest(into, chestCF)
	end, Vector3.new(1.3, 1.3, 1.3))
	local host = hidden(model, "FreeChestPrompt", Vector3.new(6.4, 5, 4.4), chestCF * CFrame.new(0, 2.8, 0))
	host:SetAttribute("Role", "FreeChest")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Claim"
	prompt.ObjectText = "Free Chest"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("FreeChest", true)
	prompt.Parent = host
	local gui = Instance.new("BillboardGui")
	gui.Name = "ChestSign"
	gui.Size = UDim2.fromScale(10, 4.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6.6, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Adornee = host
	gui.Parent = host
	for _, spec in {
		{ name = "ChestFree", text = "FREE!", color = FREE_GREEN, y = 0, h = 0.68, stroke = 5, visible = true },
		{ name = "ChestTimer", text = "", color = Color3.new(1, 1, 1), y = 0.7, h = 0.3, stroke = 3, visible = false },
	} do
		local l = Instance.new("TextLabel")
		l.Name = spec.name
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, spec.h)
		l.Position = UDim2.fromScale(0, spec.y)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = spec.text
		l.TextColor3 = spec.color
		l.Visible = spec.visible
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = spec.stroke
		stroke.Color = Color3.fromRGB(10, 60, 15)
		stroke.Parent = l
		l.Parent = gui
	end

	-- The board: the panel with the list is the gameplay piece; its frame, cap and pedestal are the
	-- MoneyBoard slot.
	local panelPos = MONEY_BOARD_POS + Vector3.new(0, 4 + MONEY_PANEL.Y / 2, 0)
	local panelCF = Props.lookAt(panelPos, panelPos + toBase) -- front face toward the base
	Assets.swap("MoneyBoard", model, Assets.facing(MONEY_BOARD_POS, toBase), function(into)
		moneyBoardFrame(into, panelCF)
	end, Vector3.new(1.2, 1.2, 0))
	local panel = studs(deco(model, "MoneyBoard", Vector3.new(MONEY_PANEL.X, MONEY_PANEL.Y, 0.6), panelCF, Color3.fromRGB(30, 60, 120)), { "BackSurface" })
	panel:SetAttribute("Role", "MoneyBoard")
	buildMoneyBoardGui(panel)
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
		local labels: { [string]: any } = {}
		for key, name in { level = "Level", cash = "Cash", robux = "Robux" } do
			labels[key] = board and findLabel(board, name)
			if board and not labels[key] then
				table.insert(problems, `{scope}: the Upgrade board has no "{name}" TextLabel`)
			end
		end
		local buttons = board and board:FindFirstChild("Buttons", true)
		labels.buttons = if buttons and buttons:IsA("GuiObject") then buttons else nil
		if not (model and floor and pad and belt and signLabel and tmLabel and board and spawn and labels.level and labels.cash and labels.robux) then
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
	buildRewards(world)
	buildCorridor(world)
	world.Parent = workspace
	local plots, nests, problems = WorldBuilder.adopt(world)
	assert(plots and nests, "the generated map breaks its own contract:\n" .. table.concat(problems, "\n"))
	return plots, nests
end

-- The SELL stalls' prompt parts (a ProximityPrompt with OpensShop = "Sell" on a part, or on an Attachment
-- in a part), wherever the map has them: PlotService only sells to players standing near one. A map
-- without one is warned about; the game still runs (plants can still be removed with R).
function WorldBuilder.sellPoints(world: Instance?): { BasePart }
	local out: { BasePart } = {}
	for _, d in if world then world:GetDescendants() else {} do
		if d:IsA("ProximityPrompt") and d:GetAttribute("OpensShop") == "Sell" then
			local host = d.Parent
			if host and host:IsA("Attachment") then
				host = host.Parent
			end
			if host and host:IsA("BasePart") then
				table.insert(out, host)
			end
		end
	end
	if #out == 0 then
		warn(`[WorldBuilder] the map has no SELL stall (a ProximityPrompt with OpensShop = "Sell"), so plants can't be sold at a stall`)
	end
	return out
end

-- What RewardService writes on the "MOST MONEY/s" board: one entry per row (Rank, Name, Value labels and
-- the row frame, hidden when empty) and the Status line.
export type MoneyBoardLabels = { rows: { { frame: GuiObject, name: TextLabel, value: TextLabel } }, status: TextLabel }

-- The community rewards' pieces, wherever the map has them: the free chest's prompt part (Role
-- "FreeChest", holding a ProximityPrompt) and the board's labels (the Role "MoneyBoard" part's Row1..RowN
-- and Status). A map without one is warned about and the game runs without that reward.
function WorldBuilder.rewardPoints(world: Instance?): (BasePart?, MoneyBoardLabels?)
	local chest: BasePart?, board: BasePart? = nil, nil
	local all: { Instance } = if world then world:GetDescendants() else {}
	for _, d in all do
		local role = d:GetAttribute("Role")
		if role == "FreeChest" and d:IsA("BasePart") and d:FindFirstChildOfClass("ProximityPrompt") then
			chest = chest or d
		elseif role == "MoneyBoard" and d:IsA("BasePart") then
			board = board or d
		end
	end
	local labels: MoneyBoardLabels? = nil
	if board then
		local rows = {}
		for i = 1, Config.MONEY_BOARD_ROWS do
			local row = board:FindFirstChild("Row" .. i, true)
			local name = row and row:FindFirstChild("Name")
			local value = row and row:FindFirstChild("Value")
			if not (row and row:IsA("GuiObject") and name and name:IsA("TextLabel") and value and value:IsA("TextLabel")) then
				break
			end
			table.insert(rows, { frame = row, name = name, value = value })
		end
		local status = findLabel(board, "Status")
		if #rows > 0 and status then
			labels = { rows = rows, status = status }
		end
	end
	if not chest then
		warn(`[WorldBuilder] the map has no free chest (a part with Role = "FreeChest" holding a ProximityPrompt)`)
	end
	if not labels then
		warn(`[WorldBuilder] the map has no "MOST MONEY/s" board (a part with Role = "MoneyBoard" and its Row1.. / Status labels)`)
	end
	return chest, labels
end

-- Writes the board: `rows` already ranked and formatted (Rewards.formatRow), `status` the line under the
-- list. Rows past the list are hidden.
function WorldBuilder.setMoneyBoard(labels: MoneyBoardLabels, rows: { { name: string, value: string } }, status: string)
	for i, row in labels.rows do
		local r = rows[i]
		row.frame.Visible = r ~= nil
		row.name.Text = if r then r.name else ""
		row.value.Text = if r then r.value else ""
	end
	labels.status.Text = status
end

-- The fixed sign texts that show an icon once it is uploaded (Config.ICONS), matched by their exact text so
-- signs hand-edited to say something else are left alone. The plot and treadmill signs are rewritten by
-- PlotService through Icons.set too; these are their texts before anyone owns the plot.
WorldBuilder.SIGN_ICONS = {
	["🛒 SHOP"] = "Shop",
	["🏃 TRAIL SHOP"] = "TrailShop",
	["📖 INDEX"] = "Index",
	["🏠 Empty Plot"] = "Home",
	["🏃 TREADMILL"] = "Treadmill",
} :: { [string]: string }

-- Writes a plot's Upgrade board. `level` is the owner's plot level (nil: nobody owns the plot) and `robux`
-- the price on the purple button (default: the tier's placeholder, Config.plotUpgradeProduct). Below the
-- last level: "Level X > Level Y" and both buttons (the red one with the money price and the PlotUpgrade
-- icon, the purple one with the Robux icon); at the last level "MAX LEVEL" and no buttons.
function WorldBuilder.setUpgradeBoard(labels: UpgradeLabels, level: number?, robux: number?)
	local open = level ~= nil and level < Config.PLOT_LEVEL_MAX
	if labels.buttons then
		labels.buttons.Visible = open
	end
	if level == nil then
		labels.level.Text = "Empty plot"
		labels.level.TextColor3 = BOARD_TEXT.empty
	elseif not open then
		labels.level.Text = "MAX LEVEL"
		labels.level.TextColor3 = BOARD_TEXT.max
	else
		labels.level.Text = `Level {level} > Level {level + 1}`
		labels.level.TextColor3 = BOARD_TEXT.open
	end
	if open then
		local _, product = Config.plotUpgradeProduct(level :: number)
		Icons.set(labels.cash, "PlotUpgrade", Format.money(Config.plotUpgradePrice((level :: number) + 1)), 0.8)
		Icons.set(labels.robux, "Robux", Format.robux(robux or (product :: Config.DevProduct).robux), 0.8)
	else
		Icons.set(labels.cash, {}, "")
		Icons.set(labels.robux, {}, "")
	end
end

-- Puts the uploaded icons on the map's signs at runtime, so map/World.rbxm itself keeps the emoji text and
-- never needs regenerating for icons. Does nothing while no icon is uploaded. Returns how many signs changed.
function WorldBuilder.applyIcons(world: Instance): number
	local count = 0
	for _, d in world:GetDescendants() do
		if d:IsA("TextLabel") then
			local key = WorldBuilder.SIGN_ICONS[d.Text]
			if key and Icons.image(key) then
				Icons.set(d, key, d.Text)
				count += 1
			end
		end
	end
	return count
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
			WorldBuilder.applyIcons(world)
			return plots, nests
		end
		warn("[WorldBuilder] Workspace.World is missing pieces the game needs, so this server regenerates the map from code"
			.. " (hand edits are not used until they are fixed in map/World.rbxm):\n  " .. table.concat(problems, "\n  "))
	else
		warn("[WorldBuilder] no Workspace.World in the place, so the map is generated from code")
	end
	local plots, nests = WorldBuilder.build()
	WorldBuilder.applyIcons(workspace:FindFirstChild("World") :: Instance)
	return plots, nests
end

-- Is `pos` standing on this plot's treadmill belt?
function WorldBuilder.onBelt(belt: BasePart, pos: Vector3): boolean
	local rel = belt.CFrame:PointToObjectSpace(pos)
	local size = belt.Size
	return math.abs(rel.X) <= size.X / 2 and math.abs(rel.Z) <= size.Z / 2 and rel.Y >= 0 and rel.Y <= 7
end

return WorldBuilder
