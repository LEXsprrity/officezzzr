-- Local-only effects: "+$1.2M" income popups, event sounds, camera shake, the treadmill belt scroll,
-- rainbow mutations, hiding other players' plot prompts, and the treadmill lock, sprint and Speed popups.
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

local function consider(inst: Instance)
	if inst:IsA("Texture") and inst.Name == "Stripes" then
		stripes[inst] = true
	elseif inst:IsA("ProximityPrompt") then
		watchPrompt(inst)
	elseif inst:IsA("BasePart") and inst:GetAttribute("Role") == "TreadmillBelt" then
		belts[inst] = true
	elseif inst:IsA("Model") and inst:GetAttribute("Role") == "Plot" then
		local function owner()
			local index = inst:GetAttribute("PlotIndex")
			if inst:GetAttribute("OwnerUserId") == player.UserId and type(index) == "number" then
				myPlot = index
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
		belts[inst] = nil
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
type Grade = { TintColor: Color3, Saturation: number, Brightness: number, Contrast: number }
local NEUTRAL: Grade = { TintColor = Color3.new(1, 1, 1), Saturation = 0, Brightness = 0, Contrast = 0 }
local ZONE_GRADE: { [string]: Grade } = {
	Meadow = { TintColor = Color3.fromRGB(255, 255, 240), Saturation = 0.1, Brightness = 0.02, Contrast = 0 },
	Desert = { TintColor = Color3.fromRGB(255, 238, 208), Saturation = 0.08, Brightness = 0.03, Contrast = 0.04 },
	Jungle = { TintColor = Color3.fromRGB(228, 255, 222), Saturation = 0.12, Brightness = 0, Contrast = 0.04 },
	Lava = { TintColor = Color3.fromRGB(255, 214, 196), Saturation = 0.15, Brightness = 0, Contrast = 0.1 },
	Snow = { TintColor = Color3.fromRGB(232, 244, 255), Saturation = -0.05, Brightness = 0.04, Contrast = 0.02 },
	Space = { TintColor = Color3.fromRGB(218, 204, 255), Saturation = 0.18, Brightness = -0.03, Contrast = 0.1 },
	Spirit = { TintColor = Color3.fromRGB(255, 232, 242), Saturation = 0.1, Brightness = 0.02, Contrast = 0 },
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
-- character is held in place (its root anchored on this client only, centred on the belt, facing the
-- front) and sprints in place (its own run animation from the Animate script, sped up), with a "+X" Speed
-- popup over it about every second. The only way off is jumping (Space / the mobile jump button), which
-- puts you just beside the belt; you can't be locked again for a moment. Dying, a respawn or the server
-- moving you off the belt just unlocks. The server sees a player standing still on their belt: the AFK
-- treadmill gain, well inside the movement check. Other players' treadmills pay nothing (the server only
-- checks your plot's belt and toasts "This isn't your treadmill"), so they don't lock or animate.
----------------------------------------------------------------------------------------------------
local runTrack: AnimationTrack? = nil
local runHumanoid: Humanoid? = nil
local lock = Treadmill.newLock()
local lockedBelt: BasePart? = nil
local lockedRoot: BasePart? = nil
local jumpQueued = false
local nextPopup = 0
-- What the Speed popups need from the stats (StatsUpdate sends partial tables).
local stats = { speed = 0, walkSpeed = 0, equippedTrail = nil :: string?, treadmillMult = 1 }

StatsUpdate.OnClientEvent:Connect(function(partial: { [string]: any })
	if type(partial) ~= "table" then
		return
	end
	if partial.plot ~= nil then
		myPlot = if type(partial.plot) == "number" then partial.plot else nil
	end
	for _, key in { "speed", "walkSpeed", "treadmillMult" } do
		if type(partial[key]) == "number" then
			(stats :: any)[key] = partial[key]
		end
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

local function release()
	if lockedRoot and lockedRoot.Parent then
		lockedRoot.Anchored = false
	end
	lockedRoot, lockedBelt = nil, nil
end

-- "[sneaker] +1.6K" over the character, floating up and fading: the Speed a second on the treadmill pays.
local POPUP_LIFE = 2
local function speedPopup(root: BasePart)
	local amount = Treadmill.perSecond(stats.walkSpeed, stats.speed, stats.equippedTrail, stats.treadmillMult)
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
		lockedBelt, lockedRoot = belt, root
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = Treadmill.lockCFrame(belt.CFrame, belt.Size, root.Position)
		root.Anchored = true
		nextPopup = now + 0.5
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
