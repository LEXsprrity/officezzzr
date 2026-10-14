-- Local-only effects: "+$1.2M" income popups, event sounds, camera shake, the treadmill belt scroll,
-- rainbow mutations, hiding other players' plot prompts, the Upgrade boards' button pops, and the treadmill
-- lock, sprint and Speed popups and the invisible walls that keep you off other players' treadmills.
-- Nothing here affects game state.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Icons = require(Shared:WaitForChild("Icons"))
local Treadmill = require(Shared:WaitForChild("Treadmill"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local BoardButton = require(Shared:WaitForChild("BoardButton"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local LootEvent = remotes:WaitForChild("LootEvent") :: RemoteEvent
local IncomePopup = remotes:WaitForChild("IncomePopup") :: RemoteEvent
local StatsUpdate = remotes:WaitForChild("StatsUpdate") :: RemoteEvent

----------------------------------------------------------------------------------------------------
-- Income popups
----------------------------------------------------------------------------------------------------
local MAX_POPUPS = 40
local livePopups = 0

IncomePopup.OnClientEvent:Connect(function(amount: number, position: Vector3)
	if livePopups >= MAX_POPUPS or typeof(position) ~= "Vector3" then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > 150 then
		return
	end
	livePopups += 1
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 40)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = attachment
	gui.Parent = attachment
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 255, 120)
	label.Text = "+" .. Format.money(amount)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui

	local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	task.delay(1.25, function()
		attachment:Destroy()
		livePopups -= 1
	end)
end)

----------------------------------------------------------------------------------------------------
-- Sounds + shake
----------------------------------------------------------------------------------------------------
local function play(name: string, volume: number?)
	local id = Config.SOUNDS[name]
	if not id then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(5, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local shakeUntil, shakePower = 0, 0
local function shake(seconds: number, power: number)
	shakeUntil = os.clock() + seconds
	shakePower = power
end

RunService:BindToRenderStep("SeedShake", Enum.RenderPriority.Camera.Value + 1, function()
	local left = shakeUntil - os.clock()
	if left > 0 then
		local camera = workspace.CurrentCamera
		local p = shakePower * left
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * p), math.rad((math.random() - 0.5) * p), 0)
	end
end)

local SOUND_FOR = {
	Pickup = "Pickup", Planted = "Plant", Caught = "Caught", GuardWake = "Wake",
	Bat = "Bat", Bought = "Buy", End = "Pickup", PackRoll = "Buy", Announce = "Pickup", SoldPlants = "Buy", FreeChest = "Buy",
}

LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	local sound = SOUND_FOR[kind]
	if sound then
		play(sound)
	end
	if kind == "Caught" then
		shake(0.6, 6)
	elseif kind == "GuardWake" then
		shake(0.4, 3)
	elseif kind == "Bat" and data and data.hit then
		shake(0.2, 3)
	end
end)

----------------------------------------------------------------------------------------------------
-- World decoration that must follow streaming: belts, rainbow mutations, owner-only prompts
----------------------------------------------------------------------------------------------------
local stripes: { [Texture]: boolean } = {}
local belts: { [BasePart]: boolean? } = {} -- every plot's treadmill belt (Role = "TreadmillBelt")
-- The local player's plot index: from StatsUpdate `plot`, or from the plot Model PlotService marks with
-- our OwnerUserId (in case the first full stats arrived before this script listened).
local myPlot: number? = nil
local rainbows: { [BasePart]: boolean? } = {}

-- Other players' treadmills: an invisible solid box over each belt that isn't ours (Treadmill.blockBox), made
-- on this client only, so we can't step onto it. Our own belt stays open. It rides inside its belt, so it
-- streams out with it.
local blocks: { [BasePart]: BasePart } = {}
local function syncBlock(belt: BasePart)
	local block = blocks[belt] or belt:FindFirstChild("TreadmillBlock") :: BasePart? -- or a belt that streamed back in
	if not belt.Parent or (myPlot ~= nil and belt:GetAttribute("PlotIndex") == myPlot) then
		if block then
			block:Destroy()
		end
		blocks[belt] = nil
		return
	end
	local wall: BasePart = block or Instance.new("Part")
	wall.Name = "TreadmillBlock"
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanTouch = false
	wall.CastShadow = false
	wall.Transparency = 1
	local cf, size = Treadmill.blockBox(belt.CFrame, belt.Size)
	wall.Size = size
	wall.CFrame = cf
	wall.Parent = belt
	blocks[belt] = wall
end

local function setMyPlot(index: number?)
	if index == myPlot then
		return
	end
	myPlot = index
	for belt in belts do
		syncBlock(belt)
	end
end

-- Plant-creatures (PlotService tags them with RestPivot and Scale) get an idle sway, see the end of the file.
type Creature = {
	rest: CFrame?,
	scale: number,
	phase: number,
	parts: { BasePart },
	offsets: { CFrame }, -- each part relative to RestPivot
	written: { CFrame }, -- where the sway last put each part
	dirty: boolean,
}
local creatures: { [Model]: Creature } = {}

local function watchCreature(model: Model)
	if creatures[model] then
		return
	end
	local c: Creature = { rest = nil, scale = 1, phase = 0, parts = {}, offsets = {}, written = {}, dirty = true }
	creatures[model] = c
	local function dirty()
		c.dirty = true
	end
	model:GetAttributeChangedSignal("Scale"):Connect(dirty) -- the server rescaled it: new rest pose
	model:GetAttributeChangedSignal("RestPivot"):Connect(dirty)
end

local function watchPrompt(prompt: ProximityPrompt)
	local function apply()
		local owner = prompt:GetAttribute("OwnerUserId")
		if owner ~= nil then
			prompt.Enabled = owner == player.UserId
		end
	end
	apply()
	prompt:GetAttributeChangedSignal("OwnerUserId"):Connect(apply)
end

-- The red $ button on your own Upgrade boards (the plot's and the treadmill's) turns green while you can
-- afford it (BoardButton.cashColors): the server writes the price it shows on the painted button ("Price");
-- your money comes with StatsUpdate. Somebody else's boards stay red.
local myMoney: number? = nil
local cashDetectors: { [ClickDetector]: boolean } = {}

local function paintedOf(detector: ClickDetector): GuiObject?
	local hit = detector.Parent
	local painted = hit and hit:FindFirstChild("Painted")
	local button = painted and painted:IsA("ObjectValue") and painted.Value
	return if button and button:IsA("GuiObject") then button else nil
end

local function paintCash(detector: ClickDetector)
	local button = paintedOf(detector)
	if not button or button.Name ~= "CashButton" then
		return
	end
	local mine = detector:GetAttribute("OwnerUserId") == player.UserId
	local price = button:GetAttribute(BoardButton.PRICE_ATTRIBUTE)
	local colors = BoardButton.cashColors(if mine then myMoney else nil, if type(price) == "number" then price else nil)
	button.BackgroundColor3 = colors.fill
	local edge = button:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Color = colors.edge
	end
end

local function repaintCash()
	for detector in cashDetectors do
		if detector.Parent then
			paintCash(detector)
		else
			cashDetectors[detector] = nil
		end
	end
end

-- Follows one board button's click detector: repaints when its owner, its painted button or the price changes.
local function watchCash(detector: ClickDetector)
	local hit = detector.Parent
	local painted = hit and hit:FindFirstChild("Painted")
	if not (painted and painted:IsA("ObjectValue")) then
		return
	end
	local hooked: Instance? = nil
	local function refresh()
		local button = paintedOf(detector)
		if button and button ~= hooked and button.Name == "CashButton" then
			hooked = button
			button:GetAttributeChangedSignal(BoardButton.PRICE_ATTRIBUTE):Connect(function()
				paintCash(detector)
			end)
		end
		paintCash(detector)
	end
	cashDetectors[detector] = true
	painted.Changed:Connect(refresh)
	detector:GetAttributeChangedSignal("OwnerUserId"):Connect(refresh)
	refresh()
end

-- The Upgrade boards' painted buttons (PlotService): a ClickDetector on an invisible part over each, with
-- its owner's OwnerUserId and its reach in "Reach". Only the owner can click or tap it (the server re-checks).
-- The mouse keeps its normal arrow over it, and the painted button (the hit part's "Painted" value)
-- inflates while the mouse is over it and squashes on a click, like the HUD's buttons.
local function watchClick(detector: ClickDetector)
	local function apply()
		local owner = detector:GetAttribute("OwnerUserId")
		local reach = detector:GetAttribute("Reach")
		if owner ~= nil and type(reach) == "number" then
			detector.MaxActivationDistance = if owner == player.UserId then reach else 0
		end
	end
	apply()
	detector:GetAttributeChangedSignal("OwnerUserId"):Connect(apply)
	watchCash(detector)
	local function pop(how: "hover" | "rest" | "press")
		local button = paintedOf(detector)
		if button then
			UiFx.worldPop(button, how)
		end
	end
	detector.MouseHoverEnter:Connect(function(who: Player)
		if who == player then
			pop("hover")
		end
	end)
	detector.MouseHoverLeave:Connect(function(who: Player)
		if who == player then
			pop("rest")
		end
	end)
	detector.MouseClick:Connect(function(who: Player)
		if who == player then
			pop("press")
		end
	end)
end

local function consider(inst: Instance)
	if inst:IsA("Texture") and inst.Name == "Stripes" then
		stripes[inst] = true
	elseif inst:IsA("ProximityPrompt") then
		watchPrompt(inst)
	elseif inst:IsA("ClickDetector") then
		watchClick(inst)
	elseif inst:IsA("BasePart") and inst:GetAttribute("Role") == "TreadmillBelt" then
		belts[inst] = true
		syncBlock(inst)
		for _, property in { "CFrame", "Size" } do
			inst:GetPropertyChangedSignal(property):Connect(function()
				if belts[inst] then
					syncBlock(inst)
				end
			end)
		end
	elseif inst:IsA("Model") and inst:GetAttribute("Role") == "Plot" then
		local function owner()
			local index = inst:GetAttribute("PlotIndex")
			if inst:GetAttribute("OwnerUserId") == player.UserId and type(index) == "number" then
				setMyPlot(index)
			end
		end
		owner()
		inst:GetAttributeChangedSignal("OwnerUserId"):Connect(owner)
	elseif inst:IsA("BasePart") and inst:GetAttribute("Mutation") == "Rainbow" then
		rainbows[inst] = true
	elseif inst:IsA("Model") and inst:GetAttribute("Mutation") == "Rainbow" then
		task.defer(function()
			local body = inst.PrimaryPart or inst:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				rainbows[body] = true
			end
		end)
	end
	if inst:IsA("Model") and inst:GetAttribute("RestPivot") ~= nil then
		watchCreature(inst)
	elseif inst:IsA("BasePart") and inst.Parent and creatures[inst.Parent :: Model] then
		local c = creatures[inst.Parent :: Model]
		c.dirty = true -- a part arrived after its creature
		-- A server rescale resizes every part. Re-measure when the new Size lands too, in case the Scale
		-- attribute was processed before the rescaled CFrames arrived.
		inst:GetPropertyChangedSignal("Size"):Connect(function()
			c.dirty = true
		end)
	end
	-- Pods re-roll in place, so their mutation can change after they stream in.
	if inst:IsA("BasePart") and string.sub(inst.Name, 1, 7) == "SeedPod" then
		inst:GetAttributeChangedSignal("Mutation"):Connect(function()
			rainbows[inst] = if inst:GetAttribute("Mutation") == "Rainbow" then true else nil
		end)
	end
end

for _, d in workspace:GetDescendants() do
	consider(d)
end
workspace.DescendantAdded:Connect(consider)
workspace.DescendantRemoving:Connect(function(inst)
	if inst:IsA("Texture") then
		stripes[inst] = nil
	elseif inst:IsA("BasePart") then
		rainbows[inst] = nil
		if belts[inst] then
			belts[inst] = nil
			blocks[inst] = nil -- its wall goes with it
		end
		local c = inst.Parent and creatures[inst.Parent :: Model]
		if c then
			c.dirty = true
		end
	elseif inst:IsA("Model") then
		creatures[inst] = nil
	end
end)

RunService.Heartbeat:Connect(function(dt)
	for tex in stripes do
		tex.OffsetStudsV = (tex.OffsetStudsV + dt * 6) % tex.StudsPerTileV
	end
	local hue = (os.clock() * 0.25) % 1
	for part in rainbows do
		part.Color = Color3.fromHSV(hue, 0.8, 1)
	end
end)

----------------------------------------------------------------------------------------------------
-- Creature idle sway: ONE loop moves every plant-creature near the camera with a single BulkMoveTo.
-- Creature parts are anchored, so this is local only and never replicates. Each part's offset from the
-- creature's RestPivot is cached, and re-read when the server rescales the creature (its Scale attribute).
----------------------------------------------------------------------------------------------------
local SWAY_HZ = 30
local SWAY_RANGE = 160 -- studs from the camera

local function capture(model: Model, c: Creature): boolean
	local rest = model:GetAttribute("RestPivot")
	if typeof(rest) ~= "CFrame" then
		return false
	end
	-- A part still where the sway last put it wasn't moved by the server, so its cached offset still holds;
	-- any other part now sits at its server (rest) pose and is measured again.
	local index = {}
	for i, part in c.parts do
		index[part] = i
	end
	local inv = rest:Inverse()
	local parts, offsets, written = {}, {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local i = index[d]
			local untouched = i ~= nil and (d.Position - c.written[i].Position).Magnitude < 1e-3
			table.insert(parts, d)
			table.insert(offsets, if untouched then c.offsets[i] else inv * d.CFrame)
			table.insert(written, d.CFrame)
		end
	end
	c.rest = rest
	c.scale = model:GetAttribute("Scale") or 1
	c.phase = (rest.Position.X * 0.37 + rest.Position.Z * 0.61) % (2 * math.pi)
	c.parts, c.offsets, c.written = parts, offsets, written
	c.dirty = false
	return true
end

local swayWait = 0
local swayParts: { BasePart } = {}
local swayCFrames: { CFrame } = {}
RunService.Heartbeat:Connect(function(dt)
	swayWait -= dt
	local camera = workspace.CurrentCamera
	if swayWait > 0 or not camera then
		return
	end
	swayWait = 1 / SWAY_HZ
	local eye = camera.CFrame.Position
	local t = os.clock()
	table.clear(swayParts)
	table.clear(swayCFrames)
	for model, c in creatures do
		if c.dirty and not capture(model, c) then
			continue
		end
		local rest = c.rest :: CFrame
		if (rest.Position - eye).Magnitude > SWAY_RANGE then
			continue
		end
		-- Gentle bob plus a small sway around the soil pivot (a few degrees), de-synced per slot.
		local p = c.phase
		local pose = rest
			* CFrame.new(0, (math.sin(t * 1.7 + p) + 1) * 0.04 * c.scale, 0)
			* CFrame.Angles(math.sin(t * 1.3 + p) * 0.03, math.sin(t * 0.7 + p) * 0.05, math.sin(t * 1.1 + p * 1.7) * 0.035)
		for i, part in c.parts do
			local cf = pose * c.offsets[i]
			c.written[i] = cf
			table.insert(swayParts, part)
			table.insert(swayCFrames, cf)
		end
	end
	if #swayParts > 0 then
		workspace:BulkMoveTo(swayParts, swayCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

----------------------------------------------------------------------------------------------------
-- Per-zone colour grading: a local ColorCorrectionEffect on the camera sets each zone's mood
-- (warm desert, hot lava, cold snow, purple space). It stacks with the server's day/night grade.
----------------------------------------------------------------------------------------------------
-- (Kept gentle: a light tint, no extra brightness, little saturation, so no zone glares.)
type Grade = { TintColor: Color3, Saturation: number, Brightness: number, Contrast: number }
local NEUTRAL: Grade = { TintColor = Color3.new(1, 1, 1), Saturation = 0, Brightness = 0, Contrast = 0 }
local ZONE_GRADE: { [string]: Grade } = {
	Meadow = { TintColor = Color3.fromRGB(255, 255, 246), Saturation = 0.04, Brightness = 0, Contrast = 0 },
	Desert = { TintColor = Color3.fromRGB(255, 244, 226), Saturation = 0.03, Brightness = 0, Contrast = 0.02 },
	Jungle = { TintColor = Color3.fromRGB(238, 255, 234), Saturation = 0.06, Brightness = 0, Contrast = 0.02 },
	Lava = { TintColor = Color3.fromRGB(255, 226, 212), Saturation = 0.08, Brightness = 0, Contrast = 0.05 },
	Snow = { TintColor = Color3.fromRGB(238, 246, 255), Saturation = -0.03, Brightness = -0.02, Contrast = 0.02 },
	Space = { TintColor = Color3.fromRGB(228, 218, 255), Saturation = 0.08, Brightness = -0.03, Contrast = 0.05 },
	Spirit = { TintColor = Color3.fromRGB(255, 240, 246), Saturation = 0.04, Brightness = 0, Contrast = 0 },
}

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "ZoneGrade"
local gradeZone: string? = "?"
local lastGradeCheck = 0

local function attachGrade()
	local camera = workspace.CurrentCamera
	if camera then
		grade.Parent = camera
	end
end
attachGrade()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(attachGrade)

RunService.Heartbeat:Connect(function()
	if os.clock() - lastGradeCheck < 0.3 then
		return
	end
	lastGradeCheck = os.clock()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local k = if root then Config.zoneAtX(root.Position.X) else nil
	local id = if k then Config.ZONES[k].id else nil
	if id ~= gradeZone then
		gradeZone = id
		local target = if id then ZONE_GRADE[id] or NEUTRAL else NEUTRAL
		TweenService:Create(grade, TweenInfo.new(1.5, Enum.EasingStyle.Sine), target :: any):Play()
	end
end)

----------------------------------------------------------------------------------------------------
-- Treadmill: step on your OWN plot's belt and you are locked on it (Shared/Treadmill.stepLock): the
-- character is held in place (centred on the belt, facing the front, the console: put back there every
-- frame, with AutoRotate off and its WalkSpeed 0 on this client only, so the walking keys don't move it) and
-- sprints in place (its own run animation from the Animate script, sped up), with a "+X" Speed popup over
-- it about every second. The only way off is jumping (Space / the mobile jump button), which puts you just
-- beside the belt; you can't be locked again for a moment. Dying, a respawn or the server moving you off
-- the belt just unlocks. The root is NEVER anchored: a root anchored on the client stops replicating, so the
-- server kept the last position from before the lock (just off the belt) and paid no Speed (owner playtest:
-- "Speed isn't going up"). Held this way the server sees a player standing still on their belt: the AFK
-- treadmill gain, well inside the movement check. Other players' treadmills pay nothing (the server only
-- checks your plot's belt) and can't be stepped on (their invisible walls, above).
----------------------------------------------------------------------------------------------------
local runTrack: AnimationTrack? = nil
local runHumanoid: Humanoid? = nil
local lock = Treadmill.newLock()
local lockedBelt: BasePart? = nil
local lockedRoot: BasePart? = nil
local lockedHumanoid: Humanoid? = nil -- its AutoRotate is off and its WalkSpeed 0 (locally) while locked
local lockedWalkSpeed = 16 -- the server's WalkSpeed for it, put back when it leaves
local walkSpeedHook: RBXScriptConnection? = nil -- keeps it 0 when the server sends a new WalkSpeed
local lockedLift = 0 -- how high the root stood over the belt's top when it was locked
local jumpQueued = false

local function beltTop(belt: BasePart): number
	return (belt.CFrame * CFrame.new(0, belt.Size.Y / 2, 0)).Position.Y
end
local nextPopup = 0
-- What the Speed popups need from the stats (StatsUpdate sends partial tables).
local stats = { treadmillTier = 1, equippedTrail = nil :: string? }

StatsUpdate.OnClientEvent:Connect(function(partial: { [string]: any })
	if type(partial) ~= "table" then
		return
	end
	if partial.plot ~= nil then
		setMyPlot(if type(partial.plot) == "number" then partial.plot else nil)
	end
	if type(partial.treadmillTier) == "number" then
		stats.treadmillTier = partial.treadmillTier
	end
	if type(partial.money) == "number" and partial.money ~= myMoney then
		myMoney = partial.money
		repaintCash()
	end
	if type(partial.equippedTrail) == "string" then
		stats.equippedTrail = partial.equippedTrail
	end
end)

UserInputService.JumpRequest:Connect(function()
	if lock.mode == "locked" then
		jumpQueued = true
	end
end)

-- The belt `pos` stands on if it is our own plot's.
local function ownBeltAt(pos: Vector3): BasePart?
	local list = {}
	for belt in belts do
		table.insert(list, belt)
	end
	local belt, plot = Treadmill.beltAt(list, pos)
	if belt and myPlot ~= nil and plot == myPlot then
		return belt
	end
	return nil
end

local function runAnimation(char: Model): Animation?
	local animate = char:FindFirstChild("Animate")
	local run = animate and animate:FindFirstChild("run")
	return run and run:FindFirstChildWhichIsA("Animation") or nil
end

-- The middle of our plot (the side of the belt we jump off to), if its floor has streamed in.
local function myPlotCenter(): Vector3?
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Role") == "Plot" and d:GetAttribute("PlotIndex") == myPlot then
			local floor = d.PrimaryPart
			return if floor then floor.Position else nil
		end
	end
	return nil
end

-- Stops the walking keys from moving a locked character: its WalkSpeed is 0 on this client only (the
-- server's own value, what it pays the treadmill from, is untouched). A new WalkSpeed from the server
-- (more Speed, a stun) is remembered for when it leaves and set back to 0.
local function holdStill(humanoid: Humanoid)
	lockedWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0
	walkSpeedHook = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if humanoid.WalkSpeed ~= 0 then
			lockedWalkSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = 0
		end
	end)
end

local function release()
	if walkSpeedHook then
		walkSpeedHook:Disconnect()
		walkSpeedHook = nil
	end
	if lockedHumanoid and lockedHumanoid.Parent then
		lockedHumanoid.AutoRotate = true
		lockedHumanoid.WalkSpeed = lockedWalkSpeed
	end
	lockedRoot, lockedBelt, lockedHumanoid = nil, nil, nil
end

-- "[sneaker] +1.6K" over the character, floating up and fading: the Speed a second on the treadmill pays.
local POPUP_LIFE = 2
local function speedPopup(root: BasePart)
	local amount = Treadmill.perSecond(stats.treadmillTier, stats.equippedTrail)
	if amount <= 0 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = root.Position + Vector3.new((math.random() - 0.5) * 4, 3.5 + math.random() * 0.8, (math.random() - 0.5) * 4)
	attachment.Parent = workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(6.5, 1.7) -- studs, so the far ones look smaller
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = attachment
	gui.Parent = attachment
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(122, 58, 235)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(32, 12, 70)
	stroke.Parent = label
	label.Parent = gui
	Icons.set(label, "Speed", "⚡ " .. Treadmill.gainText(amount))

	local info = TweenInfo.new(POPUP_LIFE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = Vector3.new(0, 5, 0) }):Play()
	-- Fade only the last part of the rise, so several stay readable stacked above the runner.
	local fade = TweenInfo.new(POPUP_LIFE * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, POPUP_LIFE * 0.55)
	for _, d in gui:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, fade, { TextTransparency = 1 }):Play()
		elseif d:IsA("ImageLabel") then
			TweenService:Create(d, fade, { ImageTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, fade, { Transparency = 1 }):Play()
		end
	end
	task.delay(POPUP_LIFE + 0.05, function()
		attachment:Destroy()
	end)
end

player.CharacterAdded:Connect(function()
	release()
	lock = Treadmill.newLock()
	jumpQueued = false
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local alive = humanoid ~= nil and root ~= nil and humanoid.Health > 0

	-- Locked: still on the belt we were locked to (a server teleport moves us off it)?
	local belt: BasePart? = nil
	if lock.mode == "locked" and lockedBelt and lockedBelt.Parent and root and root == lockedRoot then
		if Treadmill.onBelt(lockedBelt.CFrame, lockedBelt.Size, root.Position) then
			belt = lockedBelt
		end
	elseif root then
		belt = ownBeltAt(root.Position)
	end
	local action = Treadmill.stepLock(lock, { now = now, onOwnBelt = belt ~= nil, alive = alive, jumped = jumpQueued })
	jumpQueued = false
	if action == "lock" and root and belt then
		lockedBelt, lockedRoot, lockedHumanoid = belt, root, humanoid
		if humanoid then
			humanoid.AutoRotate = false -- the walking keys mustn't turn it away from the console
			holdStill(humanoid)
		end
		-- (unanchored, so this move and every frame's hold replicate: the server must see it on the belt)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = Treadmill.lockCFrame(belt.CFrame, belt.Size, root.Position)
		lockedLift = root.Position.Y - beltTop(belt)
		nextPopup = now + 0.5
	elseif lock.mode == "locked" and root and belt and root == lockedRoot then
		-- Still locked: keep it facing the console (nothing may turn it while it runs), centred and at the
		-- height it stood over the belt (a new tier's model moves the belt: PlotService swaps it on an upgrade).
		local held = Treadmill.lockCFrame(belt.CFrame, belt.Size, root.Position)
		held += Vector3.new(0, beltTop(belt) + lockedLift - root.Position.Y, 0)
		if root.CFrame.LookVector:Dot(held.LookVector) < 0.999 or (held.Position - root.Position).Magnitude > 0.05 then
			root.CFrame = held
			root.AssemblyLinearVelocity = Vector3.zero
		end
	elseif action == "exit" and root and lockedBelt then
		local from = lockedBelt
		release()
		root.CFrame = CFrame.new(Treadmill.exitPosition(from.CFrame, from.Size, root.Position, myPlotCenter())) * root.CFrame.Rotation
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	elseif action == "unlock" or action == "exit" then
		release()
	end

	-- Sprint in place while locked.
	local standing: ("own" | "other")? = if lock.mode == "locked" then "own" else nil
	local want = humanoid ~= nil and Treadmill.shouldRun(standing, alive)
	if humanoid ~= runHumanoid then
		if runTrack then
			runTrack:Stop(0)
		end
		runTrack, runHumanoid = nil, humanoid
	end
	if want and not runTrack and char and humanoid then
		local anim = runAnimation(char)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if anim and animator then
			runTrack = animator:LoadAnimation(anim)
			local track = runTrack :: AnimationTrack
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Action
			track:Play(0.15)
			track:AdjustSpeed(Treadmill.RUN_ANIM_SPEED)
		end
	elseif not want and runTrack then
		runTrack:Stop(0.2)
		runTrack = nil
	end

	if want and root and now >= nextPopup then
		nextPopup = now + 1
		speedPopup(root)
	end
end)
