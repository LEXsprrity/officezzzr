--!strict
-- Free planting: while you carry a seed (or after pressing Plant on a bagged seed in the 🌱 Seeds menu), a
-- see-through preview follows the mouse (or your last tap, or the spot in front of you on a gamepad) over
-- your own plot's brown dirt beds: green where the seed may go, red where it may not (Shared/Planting, the
-- same rules the server checks). Click (tap, or R2 on a gamepad) to plant there: the client only sends the
-- spot (remote PlantSeed); PlotService.plantAt checks it all again and plants. Q or the ✖ button cancels a
-- bagged seed. Kept out of HUD.client (its register headroom at -O0).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Planting = require(Shared:WaitForChild("Planting"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StatsUpdate = Remotes:WaitForChild("StatsUpdate") :: RemoteEvent
local LootEvent = Remotes:WaitForChild("LootEvent") :: RemoteEvent
local PlantSeed = Remotes:WaitForChild("PlantSeed") :: RemoteEvent

local player = Players.LocalPlayer

local GOOD = Color3.fromRGB(90, 255, 120)
local BAD = Color3.fromRGB(255, 80, 80)
local HINT_RANGE = 90 -- the hint shows while carrying within this many studs of your plot
local SEND_GAP = 0.3 -- seconds between two plant requests

----------------------------------------------------------------------------------------------------
-- What we know from the server
----------------------------------------------------------------------------------------------------
type PlantView = { slot: number, rarity: number, x: number?, z: number? }
local myPlot: number? = nil
local carrying: { zone: number, rarity: number }? = nil
local plants: { PlantView } = {}
local slots = Config.SLOTS_START
local bag: { key: string, rarity: number, name: string }? = nil -- a bagged seed picked in the Seeds menu
local seedBag: { [string]: number } = {}

-- The rarity of the seed we would plant now, or nil when there is nothing to plant.
local function seedRarity(): number?
	if bag then
		return bag.rarity
	end
	return if carrying then carrying.rarity else nil
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
-- The preview: a see-through disc the size of the plant's full-grown reach, with a little sprout
----------------------------------------------------------------------------------------------------
local preview = Instance.new("Model")
preview.Name = "PlantPreview"
local function ghost(name: string, shape: Enum.PartType, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = 0.45
	p.Parent = preview
	return p
end
local disc = ghost("Disc", Enum.PartType.Cylinder, Vector3.new(0.2, 4, 4))
local sprout = ghost("Sprout", Enum.PartType.Ball, Vector3.new(1.6, 1.6, 1.6))

local function showPreview(pos: Vector3?, ok: boolean, rarity: number)
	if not pos then
		preview.Parent = nil
		return
	end
	local d = Planting.radius(rarity) * 2
	disc.Size = Vector3.new(0.2, d, d)
	disc.CFrame = CFrame.new(pos + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	sprout.CFrame = CFrame.new(pos + Vector3.new(0, 1.1, 0))
	local color = if ok then GOOD else BAD
	disc.Color, sprout.Color = color, color
	preview.Parent = workspace
end

----------------------------------------------------------------------------------------------------
-- The hint under the screen's middle (and the ✖ that cancels a bagged seed)
----------------------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "PlantingHint"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Enabled = false
local hint = Instance.new("Frame")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -150)
hint.Size = UDim2.fromOffset(360, 40)
hint.BackgroundColor3 = Color3.fromRGB(30, 34, 50)
hint.BackgroundTransparency = 0.2
hint.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = hint
local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Position = UDim2.fromOffset(10, 4)
label.Size = UDim2.new(1, -56, 1, -8)
label.Font = Enum.Font.FredokaOne
label.TextScaled = true
label.TextColor3 = Color3.new(1, 1, 1)
label.Text = ""
label.Parent = hint
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Parent = label
local cancel = Instance.new("TextButton")
cancel.AnchorPoint = Vector2.new(1, 0.5)
cancel.Position = UDim2.new(1, -5, 0.5, 0)
cancel.Size = UDim2.fromOffset(34, 32)
cancel.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
cancel.Font = Enum.Font.FredokaOne
cancel.TextScaled = true
cancel.TextColor3 = Color3.new(1, 1, 1)
cancel.Text = "✖"
cancel.Parent = hint
UiFx.pop(cancel)
local cancelCorner = Instance.new("UICorner")
cancelCorner.CornerRadius = UDim.new(0, 8)
cancelCorner.Parent = cancel
gui.Parent = player:WaitForChild("PlayerGui")

local refusedUntil, refusedText = 0, ""

local function inputWord(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Tap"
	elseif string.find(last.Name, "Gamepad", 1, true) then
		return "Press R2 on"
	end
	return "Click"
end

local function updateHint(nearPlot: boolean)
	local rarity = seedRarity()
	gui.Enabled = rarity ~= nil and (bag ~= nil or nearPlot)
	if not gui.Enabled then
		return
	end
	cancel.Visible = bag ~= nil
	if os.clock() < refusedUntil then
		label.Text = refusedText
		label.TextColor3 = BAD
		return
	end
	label.TextColor3 = Color3.new(1, 1, 1)
	local what = if bag then bag.name else "your seed"
	label.Text = `{inputWord()} your brown dirt to plant {what}`
end

local function stopBag()
	bag = nil
end
cancel.Activated:Connect(stopBag)

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
		return if lastTouch then bedUnder(lastTouch) else nil
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
	PlantSeed:FireServer(pos, if bag then bag.key else nil)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not seedRarity() then
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

RunService.RenderStepped:Connect(function()
	local rarity = seedRarity()
	local near = false
	if rarity and plotReady() then
		local root = rootPart()
		near = root ~= nil and (root.Position - (origin :: CFrame).Position).Magnitude < HINT_RANGE
		local pos = aim()
		if pos then
			showPreview(pos, (check(pos, rarity)), rarity)
		else
			showPreview(nil, false, rarity)
		end
	else
		showPreview(nil, false, 1)
	end
	updateHint(near)
end)

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
		if bag and (seedBag[bag.key] or 0) <= 0 then
			stopBag() -- that seed is gone (planted or bag changed)
		end
	end
end)

LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "PlaceSeed" and type(data) == "table" and type(data.key) == "string" and type(data.rarity) == "number" then
		bag = { key = data.key, rarity = data.rarity, name = if type(data.name) == "string" then data.name else "the seed" }
		lastTouch = nil
	elseif kind == "Planted" then
		stopBag() -- one seed per Plant press; press Plant again for the next
	end
end)
