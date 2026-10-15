--!strict
-- Free planting: while you carry a seed (or after pressing Plant on a seed or a plant in the Plants panel's
-- Inventory), a translucent 3D ghost of the plant follows the mouse (or your last tap, or the spot in front
-- of you on a gamepad) over your own plot's brown dirt beds: green where it may go, red where it may not
-- (Shared/Planting, the same rules the server checks). Click (tap, or R2 on a gamepad) to plant there: the
-- client only sends the spot (remote PlantSeed); PlotService.plantAt checks it all again and plants. Q or
-- the Cancel word cancels a picked seed or plant. The hotbar's seed slot (2) lives here too. Kept out of
-- HUD.client (its register headroom at -O0).
-- Turning (owner request 2026-10-15): while placing, the mouse wheel turns the ghost PLANT_YAW_STEP degrees a
-- notch (the camera doesn't zoom meanwhile: the wheel is sunk above the camera's own binding), L1 / R1 on a
-- gamepad, the two drawn turn buttons or a two-finger twist on a phone. The plant is planted facing that way
-- (PlantSeed's yaw; an inventory plant's ghost starts facing the way it did).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Planting = require(Shared:WaitForChild("Planting"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))
local Icons = require(Shared:WaitForChild("Icons"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StatsUpdate = Remotes:WaitForChild("StatsUpdate") :: RemoteEvent
local LootEvent = Remotes:WaitForChild("LootEvent") :: RemoteEvent
local PlantSeed = Remotes:WaitForChild("PlantSeed") :: RemoteEvent

local player = Players.LocalPlayer

local BAD = Color3.fromRGB(255, 80, 80)
local INK = Color3.fromRGB(25, 25, 35)
local HINT_RANGE = 90 -- a refusal shows while carrying within this many studs of your plot
local SEND_GAP = 0.3 -- seconds between two plant requests

----------------------------------------------------------------------------------------------------
-- What we know from the server
----------------------------------------------------------------------------------------------------
type PlantView = { slot: number, rarity: number, x: number?, z: number? }
local myPlot: number? = nil
-- `ghost` and `scale` (from the server, Server/PlantGhosts): which flower the planting ghost shows and how
-- big, the plant exactly as it will be when planted (a seed: its sprout size). Never its name.
local carrying: { zone: number, rarity: number, ghost: number?, scale: number? }? = nil
local plants: { PlantView } = {}
local slots = Config.SLOTS_START
-- A bagged seed or an inventory plant picked in the Inventory or with the hotbar's seed slot ("inv:<id>"
-- keys for inventory plants)
local bag: { key: string, zone: number, rarity: number, name: string, ghost: number, scale: number }? = nil
local seedBag: { [string]: number } = {}
-- Which way the next plant faces (degrees from facing the entrance, Planting.facing): kept from one seed to
-- the next (rows of plants facing alike); an inventory plant's ghost starts facing the way it did.
local yaw = 0
local shownYaw = 0 -- the ghost turns smoothly toward `yaw`

-- The rarity of the seed we would plant now, or nil when there is nothing to plant.
local function seedRarity(): number?
	if bag then
		return bag.rarity
	end
	return if carrying then carrying.rarity else nil
end

-- What the preview shows: the zone, rarity, ghost flower and size of what we would plant now.
local function seedLook(): (number, number, number, number)
	if bag then
		return bag.zone, bag.rarity, bag.ghost, bag.scale
	end
	local c = carrying or { zone = 1, rarity = 1, ghost = 1, scale = 1 }
	return c.zone, c.rarity, c.ghost or 1, c.scale or 1
end

----------------------------------------------------------------------------------------------------
-- My plot's beds and origin (found by their Role attributes, like the server's WorldBuilder.adopt)
----------------------------------------------------------------------------------------------------
local beds: { BasePart } = {}
local origin: CFrame? = nil
local foundFor: number? = nil

local function findPlot()
	beds, origin, foundFor = {}, nil, myPlot
	local world = workspace:FindFirstChild("World")
	if not world or not myPlot then
		return
	end
	for _, d in world:GetDescendants() do
		if d:GetAttribute("PlotIndex") ~= myPlot then
			continue
		end
		local role = d:GetAttribute("Role")
		if role == "PlantBed" and d:IsA("BasePart") then
			table.insert(beds, d)
		elseif role == "PlotOrigin" and d:IsA("Attachment") and d.Parent and d.Parent:IsA("BasePart") then
			origin = d.WorldCFrame
		end
	end
end

local function plotReady(): boolean
	if foundFor ~= myPlot or #beds == 0 or not origin then
		findPlot()
	end
	for _, b in beds do
		if not b.Parent then
			findPlot()
			break
		end
	end
	return #beds > 0 and origin ~= nil
end

----------------------------------------------------------------------------------------------------
-- The preview (owner request): a translucent 3D ghost of exactly the plant that will grow, at the size it
-- will have right when planted (a seed: its sprout; an inventory plant: its own size), standing where it
-- would grow and facing the way plants face. The ghosts come from the server
-- (ReplicatedStorage.PlantGhosts, Server/PlantGhosts): the seed's own flower, decided by its gene, as a
-- silhouette; its name stays a surprise until it is planted. Ghost-green where it may go, red where it may
-- not. Until its ghost has arrived, a see-through ball the size of its reach.
----------------------------------------------------------------------------------------------------
local GHOST_OK = Color3.fromRGB(190, 255, 205)
local GHOST_TRANSPARENCY = 0.5
local preview: Model? = nil
local previewKey = ""
local previewOk: boolean? = nil

local function ghostTemplate(zone: number, rarity: number, ghost: number): Instance?
	local folder = ReplicatedStorage:FindFirstChild("PlantGhosts")
	local template = folder and folder:FindFirstChild(`Ghost_{zone}_{rarity}_{ghost}`)
	return if template and template:IsA("Model") then template else nil
end

local function makePreview(zone: number, rarity: number, ghost: number, scale: number): Model
	local template = ghostTemplate(zone, rarity, ghost)
	local model: Model
	if template then
		-- The ghost is at plant scale 1: scaled like CreatureModels.applyScale scales the real plant.
		model = (template :: Model):Clone()
		model:ScaleTo(model:GetScale() * math.clamp(scale, 0.1, 4))
		for _, d in model:GetDescendants() do
			if d:IsA("SpecialMesh") and d.MeshType ~= Enum.MeshType.FileMesh then
				d.Scale = Vector3.one -- (built-in shapes follow their part's Size already)
			end
		end
	else
		model = Instance.new("Model")
		local d = Planting.radius(rarity) * 2
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(d, d, d)
		ball.PivotOffset = CFrame.new(0, -d / 2, 0) -- its pivot on the soil
		ball.Parent = model
		model.PrimaryPart = ball
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = GHOST_TRANSPARENCY
		end
	end
	model.Name = "PlantPreview"
	return model
end

local function showPreview(pos: Vector3?, ok: boolean)
	if not pos or not origin then
		if preview then
			preview.Parent = nil
		end
		return
	end
	local zone, rarity, ghost, scale = seedLook()
	local key = `{zone}:{rarity}:{ghost}:{math.round(scale * 1000)}:{ghostTemplate(zone, rarity, ghost) ~= nil}`
	if not preview or key ~= previewKey then
		if preview then
			preview:Destroy()
		end
		preview, previewKey, previewOk = makePreview(zone, rarity, ghost, scale), key, nil
	end
	local model = preview :: Model
	if ok ~= previewOk then
		previewOk = ok
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = if ok then GHOST_OK else BAD
			end
		end
	end
	model:PivotTo(CFrame.new(pos) * Planting.facing(origin :: CFrame, shownYaw)) -- the way the plant will face
	model.Parent = workspace
end

----------------------------------------------------------------------------------------------------
-- No hint box (owner: no flat 2D boxes; the green/red preview already says where the seed may go). A
-- refused click shows why for a moment, as small relief text centred near the bottom, and a bagged seed
-- gets a relief "Cancel" word under it (Q cancels too).
----------------------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "PlantingHint"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Enabled = false
local label = Instance.new("TextLabel")
label.Name = "Reason"
label.BackgroundTransparency = 1
label.AnchorPoint = Vector2.new(0.5, 1)
label.Position = UDim2.new(0.5, 0, 1, -150)
label.Size = UDim2.fromOffset(460, 26)
label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
label.TextScaled = true
label.TextColor3 = BAD
label.Text = ""
label.Visible = false
label.Parent = gui
UiFx.relief(label, 3, 3)
local cancel = Instance.new("TextButton")
cancel.Name = "Cancel"
cancel.BackgroundTransparency = 1
cancel.AnchorPoint = Vector2.new(0.5, 1)
cancel.Position = UDim2.new(0.5, 0, 1, -116)
cancel.Size = UDim2.fromOffset(110, 30)
cancel.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
cancel.TextScaled = true
cancel.TextColor3 = Color3.new(1, 1, 1)
cancel.Text = "Cancel"
cancel.Parent = gui
UiFx.relief(cancel :: any, 3, 3)
UiFx.pop(cancel)

-- Turning the ghost: `turn(1)` / `turn(-1)` one step; how to (a relief line), and on touch screens two bright
-- square buttons with a curved arrow drawn on each (a white arc with a dark outline and a head; no emoji).
local function turn(dir: number)
	yaw = Planting.normalizeYaw(yaw + dir * Config.PLANT_YAW_STEP) or 0
end
local turnHint = Instance.new("TextLabel")
turnHint.Name = "TurnHint"
turnHint.BackgroundTransparency = 1
turnHint.AnchorPoint = Vector2.new(0.5, 1)
turnHint.Position = UDim2.new(0.5, 0, 1, -88)
turnHint.Size = UDim2.fromOffset(260, 22)
turnHint.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
turnHint.TextScaled = true
turnHint.TextColor3 = Color3.new(1, 1, 1)
turnHint.Text = ""
turnHint.Parent = gui
UiFx.relief(turnHint, 2, 2)

local TURN_BLUE = Color3.fromRGB(60, 165, 255)
local function turnButton(dir: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = if dir > 0 then "TurnRight" else "TurnLeft"
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, dir * 142, 1, -18) -- beside the hotbar
	b.Size = UDim2.fromOffset(66, 66)
	b.BackgroundColor3 = TURN_BLUE
	b.AutoButtonColor = true
	b.Text = ""
	b.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = INK
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local lit = Instance.new("Frame") -- a lighter top half, like the HUD's buttons
	lit.Name = "Lit"
	lit.Size = UDim2.fromScale(1, 0.5)
	lit.BackgroundColor3 = Color3.new(1, 1, 1)
	lit.BackgroundTransparency = 0.75
	lit.BorderSizePixel = 0
	lit.Parent = b
	-- The arrow: an open ring (the gradient hides a slice of it on the arrow's side), outlined, and a head
	-- at its top end pointing the way it turns.
	-- (a stroke grows outward from its ring: the dark one starts 2 px inside the white one and ends 4 px past it)
	for i, ring in { { size = 30, thickness = 11, color = INK }, { size = 34, thickness = 5, color = Color3.new(1, 1, 1) } } do
		local arc = Instance.new("Frame")
		arc.Name = if i == 1 then "ArcOutline" else "Arc"
		arc.AnchorPoint = Vector2.new(0.5, 0.5)
		arc.Position = UDim2.fromScale(0.5, 0.54)
		arc.Size = UDim2.fromOffset(ring.size, ring.size)
		arc.BackgroundTransparency = 1
		arc.ZIndex = 2 + i
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = arc
		local line = Instance.new("UIStroke")
		line.Thickness = ring.thickness
		line.Color = ring.color
		line.Parent = arc
		local gap = Instance.new("UIGradient")
		gap.Rotation = if dir > 0 then -45 else 225 -- the open slice: upper right (clockwise) or upper left
		gap.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.66, 0), NumberSequenceKeypoint.new(0.67, 1), NumberSequenceKeypoint.new(1, 1),
		})
		gap.Parent = line
		arc.Parent = b
	end
	-- The head: a triangle at the arc's top end, pointing the way it turns (a turned square, half of it shown
	-- through an upright clipping frame)
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.AnchorPoint = Vector2.new(if dir > 0 then 0 else 1, 0.5)
	head.Position = UDim2.new(0.5, -dir * 6, 0.54, -19)
	head.Size = UDim2.fromOffset(13, 26)
	head.BackgroundTransparency = 1
	head.ClipsDescendants = true
	head.ZIndex = 5
	local tip = Instance.new("Frame")
	tip.Name = "Tip"
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromScale(if dir > 0 then 0 else 1, 0.5)
	tip.Size = UDim2.fromOffset(16, 16)
	tip.Rotation = 45
	tip.BackgroundColor3 = Color3.new(1, 1, 1)
	tip.BorderSizePixel = 0
	tip.ZIndex = 5
	local tipStroke = Instance.new("UIStroke")
	tipStroke.Thickness = 2.5
	tipStroke.Color = INK
	tipStroke.Parent = tip
	tip.Parent = head
	head.Parent = b
	b.Activated:Connect(function()
		turn(dir)
	end)
	b.Parent = gui
	UiFx.pop(b)
	return b
end
local turnLeft, turnRight = turnButton(-1), turnButton(1)
gui.Parent = player:WaitForChild("PlayerGui")

local refusedUntil, refusedText = 0, ""

-- `stuck`: carrying a seed in the base with the seed bag full, so it can't leave your back (SeedService
-- .storeCarried): said until there is room.
local BAG_FULL = "Seed bag full: plant or sell to make room for your seed!"
local function updateHint(nearPlot: boolean, stuck: boolean)
	local rarity = seedRarity()
	gui.Enabled = stuck or (rarity ~= nil and (bag ~= nil or nearPlot))
	if not gui.Enabled then
		return
	end
	cancel.Visible = bag ~= nil
	local refused = os.clock() < refusedUntil
	label.Visible = refused or stuck
	label.Text = if refused then refusedText else BAG_FULL
	-- how to turn the ghost, for the input in use (touch: the two buttons)
	local placing = rarity ~= nil and (bag ~= nil or nearPlot)
	local last = UserInputService:GetLastInputType()
	local touch = last == Enum.UserInputType.Touch
	turnLeft.Visible, turnRight.Visible = placing and touch, placing and touch
	turnHint.Visible = placing and not touch
	turnHint.Text = if string.find(last.Name, "Gamepad", 1, true) then "L1 / R1 to turn" else "Scroll to turn"
end

local onBagChanged = function() end -- (the hotbar's seed slot repaints, below)
local function stopBag()
	bag = nil
	onBagChanged()
end
cancel.Activated:Connect(stopBag)

----------------------------------------------------------------------------------------------------
-- The hotbar's seed slot (owner request): slot 2, beside the Bat (slot 1) in the HUD's hotbar, shows the
-- seed it would plant (as it looks, never its name) and how many seeds the bag holds. Pressing 2 (or tapping it) picks the seed most recently put in the bag (this
-- session; at first the rarest) and starts the planting ghost, like the Inventory's Plant button; 2 again,
-- Q or Cancel puts it back. Each press of 2 after planting picks the next most recent.
----------------------------------------------------------------------------------------------------
local RequestUseItem = Remotes:WaitForChild("RequestUseItem") :: RemoteEvent
local ShopUi = require(Shared:WaitForChild("ShopUi"))
local recent: { string } = {} -- bag keys, oldest first

-- Keeps `recent` in step with the bag: gone keys leave, new ones go last (the first time, rarest last).
local function trackBag()
	for i = #recent, 1, -1 do
		if (seedBag[recent[i]] or 0) <= 0 then
			table.remove(recent, i)
		end
	end
	local new = {}
	for key, n in seedBag do
		if n > 0 and not table.find(recent, key) and SeedPacks.parseBagKey(key) then
			table.insert(new, key)
		end
	end
	table.sort(new, function(a, b)
		local _, ra = SeedPacks.parseBagKey(a)
		local _, rb = SeedPacks.parseBagKey(b)
		if ra ~= rb then
			return (ra :: number) < (rb :: number)
		end
		return a < b
	end)
	for _, key in new do
		table.insert(recent, key)
	end
end

local seedSlot = Instance.new("TextButton")
seedSlot.Name = "SeedSlot"
seedSlot.LayoutOrder = 2
ShopUi.slot(seedSlot, "2") -- the hotbar's look (a dark see-through square, its number top-left)
local function slotText(name: string, text: string, size: UDim2, pos: UDim2, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.Size = size
	t.Position = pos
	t.Parent = seedSlot
	return t
end
-- With an empty bag: the Seeds icon, faded (no name: the picture says it)
local slotLabel = slotText("Label", "", UDim2.new(1, -16, 1, -16), UDim2.fromOffset(8, 8), Color3.new(1, 1, 1))
Icons.set(slotLabel, "Seeds", "🌱", 1)
slotLabel.TextTransparency = 0.35
local slotCount = slotText("Count", "0", UDim2.fromOffset(46, 28), UDim2.new(1, -50, 1, -30), Color3.new(1, 1, 1))
slotCount.TextXAlignment = Enum.TextXAlignment.Right
slotCount.ZIndex = 4 -- over the seed
local countStroke = Instance.new("UIStroke")
countStroke.Thickness = 3
countStroke.Color = INK
countStroke.Parent = slotCount
UiFx.relief(slotCount, 2, 2)

-- The seed the slot would plant, as it looks (its zone's design its gene picks, from
-- ReplicatedStorage.SeedLooks, Server/SeedService.publishLooks); the Seeds icon while the bag is empty.
local slotView = Instance.new("ViewportFrame")
slotView.Name = "SeedView"
slotView.BackgroundTransparency = 1
slotView.Size = UDim2.new(1, -4, 1, -4) -- the seed fills the slot
slotView.Position = UDim2.fromOffset(2, 2)
slotView.ZIndex = 2
slotView.Visible = false
slotView.Parent = seedSlot
local viewCamera = Instance.new("Camera")
viewCamera.FieldOfView = 40
viewCamera.CFrame = CFrame.lookAt(Vector3.new(0, 2.2, 5.4), Vector3.new(0, 1.4, 0))
viewCamera.Parent = slotView
slotView.CurrentCamera = viewCamera
local shownLook: Instance? = nil
local function showLook(key: string?)
	local zone, _, _, gene = SeedPacks.parseBagKey(key)
	local looks = ReplicatedStorage:FindFirstChild("SeedLooks")
	local folder = if looks and zone then looks:FindFirstChild(tostring(zone)) else nil
	local look = if folder then folder:FindFirstChild(tostring(Config.geneDesign(gene, #folder:GetChildren()))) else nil
	if look ~= shownLook then
		shownLook = look
		for _, c in slotView:GetChildren() do
			if not c:IsA("Camera") then
				c:Destroy()
			end
		end
		if look then
			look:Clone().Parent = slotView
		end
	end
	slotView.Visible = look ~= nil
	slotLabel.Visible = look == nil
end

local function paintSlot()
	showLook(recent[#recent])
	local count = SeedPacks.bagCount(seedBag)
	slotCount.Text = `x{count}`
	local picked = bag ~= nil and not string.find(bag.key, "^inv:")
	ShopUi.selectSlot(seedSlot, picked) -- picked: a white outline
end

local function useSeedSlot()
	if bag then
		stopBag() -- 2 again: put it back
	elseif #recent > 0 then
		RequestUseItem:FireServer("Seed:" .. recent[#recent]) -- the server answers with the planting preview (PlaceSeed)
	end
	paintSlot()
end
seedSlot.Activated:Connect(useSeedSlot)
onBagChanged = paintSlot
paintSlot()
task.spawn(function()
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("SeedHUD", 60)
	local hotbar = hud and hud:WaitForChild("Hotbar", 30)
	if hotbar then
		seedSlot.Parent = hotbar
		UiFx.pop(seedSlot)
	end
end)

----------------------------------------------------------------------------------------------------
-- Aiming and planting
----------------------------------------------------------------------------------------------------
local camera = workspace.CurrentCamera
local lastTouch: Vector2? = nil
local lastSent = 0

local function rootPart(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The point on my beds under a screen point (viewport coordinates), or nil.
local function bedUnder(screen: Vector2): Vector3?
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = beds
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	return if hit then hit.Position else nil
end

-- The point on my beds just in front of the character (gamepads), or nil.
local function bedAhead(): Vector3?
	local root = rootPart()
	if not root then
		return nil
	end
	local front = root.Position + Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit * 7
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = beds
	local hit = workspace:Raycast(front + Vector3.new(0, 8, 0), Vector3.new(0, -20, 0), params)
	return if hit then hit.Position else nil
end

local function aim(): Vector3?
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return if lastTouch then bedUnder(lastTouch) else bedAhead() -- (before the first tap: in front of you, to turn it)
	elseif string.find(last.Name, "Gamepad", 1, true) then
		return bedAhead()
	end
	return bedUnder(UserInputService:GetMouseLocation())
end

-- Would the server take a plant at `pos`? (The same check; the server has the last word.)
local function check(pos: Vector3, rarity: number): (boolean, Planting.Reason?)
	local spots: { Planting.Spot } = {}
	for _, p in plants do
		if p.x and p.z then
			table.insert(spots, { x = p.x, z = p.z, rarity = p.rarity, slot = p.slot })
		end
	end
	local root = rootPart()
	return Planting.check({
		beds = beds,
		origin = origin :: CFrame,
		plants = spots,
		pos = pos,
		rarity = rarity,
		root = if root then root.Position else nil,
		limit = slots,
	})
end

local function plantAt(pos: Vector3?)
	local rarity = seedRarity()
	if not pos or not rarity or not plotReady() or os.clock() - lastSent < SEND_GAP then
		return
	end
	local ok, why = check(pos, rarity)
	if not ok then
		refusedUntil, refusedText = os.clock() + 2, Planting.MESSAGES[why :: Planting.Reason]
		return
	end
	lastSent = os.clock()
	PlantSeed:FireServer(pos, if bag then bag.key else nil, yaw)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	elseif input.KeyCode == Enum.KeyCode.Two then
		useSeedSlot()
		return
	elseif not seedRarity() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if plotReady() then
			plantAt(bedUnder(UserInputService:GetMouseLocation()))
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		if plotReady() then
			plantAt(bedAhead())
		end
	elseif input.KeyCode == Enum.KeyCode.Q and bag then
		stopBag()
	end
end)

-- Turning while placing: the mouse wheel (sunk above the camera's own wheel binding, so the camera doesn't
-- zoom meanwhile) and L1 / R1. Bound only while there is something to place.
local TURN_ACTION = "PlantTurn"
local turnBound = false
local function onTurn(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if state == Enum.UserInputState.Change and input.Position.Z ~= 0 then
			turn(if input.Position.Z > 0 then -1 else 1)
		end
	elseif state == Enum.UserInputState.Begin then
		turn(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
	end
	return Enum.ContextActionResult.Sink
end
local function bindTurn(on: boolean)
	if on == turnBound then
		return
	end
	turnBound = on
	if on then
		ContextActionService:BindActionAtPriority(TURN_ACTION, onTurn, false, Enum.ContextActionPriority.High.Value,
			Enum.UserInputType.MouseWheel, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	else
		ContextActionService:UnbindAction(TURN_ACTION)
	end
end

-- A two-finger twist turns it too, in whole steps from where the twist began.
local twistFrom = 0
UserInputService.TouchRotate:Connect(function(_: { Vector2 }, rotation: number, _: number, state: Enum.UserInputState, processed: boolean)
	if processed or not seedRarity() then
		return
	end
	if state == Enum.UserInputState.Begin then
		twistFrom = yaw
	end
	local steps = math.round(rotation / Config.PLANT_YAW_STEP)
	yaw = Planting.normalizeYaw(twistFrom - steps * Config.PLANT_YAW_STEP) or 0
end)

-- Phones and tablets: a tap in the world plants there (and the preview stays where you tapped).
UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
	if processedByUI or not seedRarity() then
		return
	end
	lastTouch = position
	if plotReady() then
		plantAt(bedUnder(position))
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	local rarity = seedRarity()
	bindTurn(rarity ~= nil)
	-- the ghost turns smoothly to `yaw` (the short way round)
	local diff = (yaw - shownYaw + 540) % 360 - 180
	shownYaw = if math.abs(diff) < 0.5 then yaw else shownYaw + diff * math.min(1, dt * 18)
	local near = false
	if rarity and plotReady() then
		local root = rootPart()
		near = root ~= nil and (root.Position - (origin :: CFrame).Position).Magnitude < HINT_RANGE
		local pos = aim()
		if pos then
			showPreview(pos, (check(pos, rarity)))
		else
			showPreview(nil, false)
		end
	else
		showPreview(nil, false)
	end
	local root = rootPart()
	local stuck = carrying ~= nil and root ~= nil and root.Position.X < Config.CORRIDOR_START_X
		and SeedPacks.bagCount(seedBag) >= Config.SEED_BAG_MAX
	updateHint(near, stuck)
end)

----------------------------------------------------------------------------------------------------
-- The reveal: a seed's flower is a surprise until it is planted (PlotService draws it then), so its name
-- pops up over the new plant in its rarity's colour, as relief text, and floats away after a moment.
----------------------------------------------------------------------------------------------------
local REVEAL_SECONDS = 2
local function reveal(name: string, pos: Vector3, color: Color3)
	local anchor = Instance.new("Attachment")
	anchor.Name = "PlantReveal"
	anchor.WorldPosition = pos
	anchor.Parent = workspace.Terrain
	local board = Instance.new("BillboardGui")
	board.Adornee = anchor
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.Size = UDim2.fromOffset(300, 44)
	board.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	board.Parent = player:WaitForChild("PlayerGui")
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.new(1, -8, 1, -8)
	text.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	text.TextScaled = true
	text.TextColor3 = color
	text.Text = name
	text.Parent = board
	UiFx.relief(text, 3, 3)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = board
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(board, TweenInfo.new(REVEAL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = Vector3.new(0, 4, 0) }):Play()
	task.delay(REVEAL_SECONDS, function()
		board:Destroy()
		anchor:Destroy()
	end)
end

----------------------------------------------------------------------------------------------------
-- Server updates
----------------------------------------------------------------------------------------------------
StatsUpdate.OnClientEvent:Connect(function(partial: any)
	if type(partial) ~= "table" then
		return
	end
	if partial.plot ~= nil then
		myPlot = partial.plot
	end
	if partial.carrying ~= nil then
		carrying = if type(partial.carrying) == "table" then partial.carrying else nil
	end
	if type(partial.plants) == "table" then
		plants = partial.plants
	end
	if type(partial.slots) == "number" then
		slots = partial.slots
	end
	if type(partial.seedBag) == "table" then
		seedBag = partial.seedBag
		trackBag()
		if bag and not string.find(bag.key, "^inv:") and (seedBag[bag.key] or 0) <= 0 then
			stopBag() -- that seed is gone (planted or bag changed)
		end
		paintSlot()
	end
	if type(partial.inventory) == "table" and bag and string.find(bag.key, "^inv:") then
		local still = false
		for _, p in partial.inventory do
			still = still or (type(p) == "table" and `inv:{p.id}` == bag.key)
		end
		if not still then
			stopBag() -- that plant is gone from the inventory (planted or sold)
		end
	end

end)

LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "PlaceSeed" and type(data) == "table" and type(data.key) == "string" and type(data.rarity) == "number" then
		bag = {
			key = data.key, rarity = data.rarity, name = if type(data.name) == "string" then data.name else "the seed",
			zone = if type(data.zone) == "number" and Config.ZONES[data.zone] then data.zone else 1,
			ghost = if type(data.ghost) == "number" then data.ghost else 1,
			scale = if type(data.scale) == "number" and data.scale == data.scale then data.scale else 1,
		}
		if data.yaw ~= nil then -- an inventory plant: its ghost starts facing the way the plant did
			yaw = Planting.normalizeYaw(data.yaw) or yaw
		end
		lastTouch = nil
		paintSlot()
	elseif kind == "Planted" then
		stopBag() -- one seed per Plant press; press Plant again for the next
		if type(data) == "table" and type(data.name) == "string" and typeof(data.pos) == "Vector3" then
			local mut = Config.mutationById(if type(data.mutation) == "string" then data.mutation else nil)
			local rarity = Config.RARITIES[if type(data.rarity) == "number" then data.rarity else 1] or Config.RARITIES[1]
			reveal(data.name, data.pos, if mut then mut.color else rarity.color)
		end
	end
end)
