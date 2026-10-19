-- The first-time tutorial (owner 2026-10-19: "person spawns in, gets some red arrows that go until they reach a
-- seed with text on top saying steal a seed, then ... every single step from planting to waiting for growth and
-- that to be red arrow animated and smooth"). Only while StatsUpdate says `tutorialDone` is false (a new player;
-- ProfileStore treats old saves of players who clearly played as done). Each step (Shared/Tutorial.STEPS):
--   * a trail of glowing red chevrons on the ground from the player to the step's target, flowing toward it
--     (Tutorial.route / Tutorial.arrows: around the plot fence and through the corridor mouth), its start
--     easing after the player so it never jitters;
--   * big floating relief words over the target ("STEAL A SEED", "RUN HOME!", "PLANT IT HERE", "WAITING FOR IT
--     TO GROW" with the sprout timer...), bobbing gently, with a red arrow under them;
--   * one studded banner at the top with the instruction and a Skip button (the last step: "Let's go!").
-- Steps advance by themselves when the player does the thing (Tutorial.advance, from what the server already
-- tells the client: StatsUpdate, LootEvent "Stored" / "Planted" / "Sprouted"). Moving from one step to the
-- next fades the trail, the words and the banner out and back in. Done or skipped, the server saves it
-- (remote Tutorial, Server/TutorialService) and it never shows again. Display only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))
local ShopUi = require(Shared:WaitForChild("ShopUi"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local GrowNowUi = require(Shared:WaitForChild("GrowNowUi"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StatsUpdate = Remotes:WaitForChild("StatsUpdate") :: RemoteEvent
local LootEvent = Remotes:WaitForChild("LootEvent") :: RemoteEvent
local TutorialRemote = Remotes:WaitForChild("Tutorial") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local new = ShopUi.new

local RED = Color3.fromRGB(255, 30, 30) -- the arrows (Neon: they glow by day and by night)
local BANNER = Color3.fromRGB(35, 150, 255)
local SKIP = Color3.fromRGB(225, 25, 35)
local GO = Color3.fromRGB(105, 235, 25)
local INK = ShopUi.INK
local FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

----------------------------------------------------------------------------------------------------
-- What the server tells us
----------------------------------------------------------------------------------------------------
local stats: { [string]: any } = { money = 0, speed = 0, income = 0, carrying = false, plants = {}, seedBag = {} }
local step: string? = nil -- the current step's id (nil: not running)
local stepStart = 0 -- os.clock() when it began
local stepMoney, stepSpeed = 0, 0 -- money and Speed when it began
local lostAt: number? = nil -- when the carried seed went (it may have been stored: LootEvent "Stored" follows)
local plantPos: Vector3? = nil -- the planted seed's top (LootEvent "Planted" / "Sprouted")

----------------------------------------------------------------------------------------------------
-- Finding the targets in the map (by the Role attributes WorldBuilder tags; Workspace replicates them)
----------------------------------------------------------------------------------------------------
-- (cached: the map is big; a list is looked up again once one of its pieces is gone)
local found: { [string]: { Instance } } = {}
local function tagged(role: string, key: string?, value: any): { Instance }
	local id = `{role}|{key}|{value}`
	local cached = found[id]
	if cached and #cached > 0 then
		local fresh = true
		for _, inst in cached do
			fresh = fresh and inst.Parent ~= nil
		end
		if fresh then
			return cached
		end
	end
	local out = {}
	local world = workspace:FindFirstChild("World") or workspace
	for _, d in world:GetDescendants() do
		if d:GetAttribute("Role") == role and (key == nil or d:GetAttribute(key) == value) then
			table.insert(out, d)
		end
	end
	found[id] = out
	return out
end

local function positionOf(inst: Instance): Vector3?
	if inst:IsA("Attachment") then
		return inst.WorldPosition
	elseif inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

local function rootPos(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position else nil
end

local function nearest(list: { Instance }, to: Vector3?): Vector3?
	local best, bestD = nil, math.huge
	for _, inst in list do
		local p = positionOf(inst)
		if p then
			local d = if to then (p - to).Magnitude else 0
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best
end

-- The player's plot: its shape for Tutorial.route, and its pieces.
local function myPlot(): (Tutorial.PlotShape?, number?)
	local index = stats.plot
	if type(index) ~= "number" then
		return nil, nil
	end
	local origin = tagged("PlotOrigin", "PlotIndex", index)[1]
	if not (origin and origin:IsA("Attachment")) then
		return nil, index
	end
	local cf = origin.WorldCFrame
	local half = Config.PLOT_SIZE / 2
	return { center = cf.Position, entrance = cf.Position - cf.LookVector * (half + 4), half = half }, index
end

-- A plant of ours near `pos` (the planted seed; any, without it). `seedling`: only one still sprouting (its
-- model carries SproutUntil), for the grow step's timer.
local function plantNear(pos: Vector3?, seedling: boolean): Model?
	local _, index = myPlot()
	local plants = index and tagged("Plants", "PlotIndex", index)[1]
	local best, bestD = nil, math.huge
	for _, m in (if plants then plants:GetChildren() else {}) :: { Instance } do
		if m:IsA("Model") and (not seedling or m:GetAttribute("SproutUntil") ~= nil) then
			local d = if pos then (m:GetPivot().Position - pos).Magnitude else 0
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

-- Where the current step points (and how high its words float over it).
local function targetOf(id: string): (Vector3?, number)
	local here = rootPos()
	local plot, index = myPlot()
	if id == "run" or id == "steal" then
		return nearest(tagged("Pod", "ZoneIndex", 1), here) or (Config.nestCenter(1) + Config.podOffset(1, 1)), 5
	elseif id == "home" then
		return if plot then plot.center else nil, 9
	elseif id == "plant" then
		return nearest(if index then tagged("PlantBed", "PlotIndex", index) else {}, here), 6
	elseif id == "grow" or id == "earn" then
		local plant = plantNear(plantPos, id == "grow")
		return if plant then plant:GetPivot().Position else plantPos, 6
	elseif id == "speed" then
		return nearest(if index then tagged("TreadmillBelt", "PlotIndex", index) else {}, here), 6
	elseif id == "ready" then
		return nearest(tagged("SpeedPlank", "ZoneIndex", 2), here), 9
	end
	return nil, 6
end

----------------------------------------------------------------------------------------------------
-- The red arrow trail: chevrons of two glowing red bars each, laid flat on the floor
----------------------------------------------------------------------------------------------------
local ARM = Vector3.new(0.7, 0.25, 3.2)
local folder = new("Folder", { Name = "TutorialArrows", Parent = workspace })
local arms: { BasePart } = {}
for i = 1, Tutorial.MAX_ARROWS * 2 do
	arms[i] = new("Part", {
		Name = "Arrow", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Material = Enum.Material.Neon, Color = RED, Size = ARM, Transparency = 1, Parent = folder,
	})
end
local LEFT = CFrame.new(-1.0, 0, 1.0) * CFrame.Angles(0, math.rad(-45), 0) -- from the chevron's tip, back and out
local RIGHT = CFrame.new(1.0, 0, 1.0) * CFrame.Angles(0, math.rad(45), 0)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local function floorAt(p: Vector3): number
	rayParams.FilterDescendantsInstances = if player.Character then { folder, player.Character } else { folder }
	local hit = workspace:Raycast(Vector3.new(p.X, Config.GROUND_Y + 40, p.Z), Vector3.new(0, -80, 0), rayParams)
	return if hit then hit.Position.Y else Config.GROUND_Y
end

local trailFrom: Vector3? = nil -- the trail's start, easing after the player
local target: Vector3? = nil -- where the trail and the words point now
local labelHeight = 6
local shown = 0 -- 0..1: the trail and the words fade together between steps
local want = 0 -- what `shown` heads for
local pending = false -- a new step's target is waiting for the old one to fade out

local function drawTrail(t: number, dt: number)
	local parts, frames = {}, {}
	local here = rootPos()
	local count = 0
	if here and target and shown > 0.01 then
		trailFrom = if trailFrom then Tutorial.follow(trailFrom, here, dt) else here
		local plot = myPlot()
		local route = Tutorial.route(trailFrom :: Vector3, target, plot)
		for _, a in Tutorial.arrows(route, t) do
			count += 1
			local y = floorAt(a.position) + 0.2
			local tip = CFrame.lookAt(Vector3.new(a.position.X, y, a.position.Z), Vector3.new(a.position.X + a.direction.X, y, a.position.Z + a.direction.Z))
			-- a soft ripple running toward the target on top of the flow
			local glow = 0.8 + 0.2 * math.sin(t * 6 - a.position.Magnitude * 0.35)
			local fade = 1 - a.alpha * shown * glow
			local l, r = arms[count * 2 - 1], arms[count * 2]
			table.insert(parts, l)
			table.insert(frames, tip * LEFT)
			table.insert(parts, r)
			table.insert(frames, tip * RIGHT)
			l.Transparency, r.Transparency = fade, fade
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	for i = count * 2 + 1, #arms do
		if arms[i].Transparency < 1 then
			arms[i].Transparency = 1
		end
	end
end

----------------------------------------------------------------------------------------------------
-- The words over the target (a BillboardGui on an invisible anchor that glides to each target)
----------------------------------------------------------------------------------------------------
local anchor = new("Part", {
	Name = "TutorialAnchor", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1,
	Size = Vector3.new(0.2, 0.2, 0.2), Parent = folder,
})
local board = new("BillboardGui", {
	Name = "TutorialLabel", Adornee = anchor, AlwaysOnTop = true, LightInfluence = 0, MaxDistance = math.huge,
	Size = UDim2.fromOffset(460, 170), ResetOnSpawn = false, Enabled = false, Parent = playerGui,
})
local boardGroup = new("CanvasGroup", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), GroupTransparency = 1, Parent = board })
local title = ShopUi.label(boardGroup, 5, { Name = "Title", Text = "", Size = UDim2.new(1, -20, 0, 66), Position = UDim2.fromOffset(10, 4), ZIndex = 2 })
UiFx.relief(title, 5, 5)
local sub = ShopUi.label(boardGroup, 4, {
	Name = "Sub", Text = "", Size = UDim2.new(1, -60, 0, 40), Position = UDim2.fromOffset(30, 72), ZIndex = 2,
	TextColor3 = Color3.fromRGB(255, 225, 90),
})
UiFx.relief(sub, 3, 4)
-- The red arrow under the words, pointing down at the target (a V of two outlined bars)
local function vee(parent: Instance, size: number, y: UDim): Frame
	local holder = new("Frame", { Name = "Vee", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, y.Scale, y.Offset), Size = UDim2.fromOffset(size, size), Parent = parent })
	for side = -1, 1, 2 do
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side * size * 0.2, 0.42, 0), Size = UDim2.fromOffset(size * 0.26, size * 0.72),
			Rotation = -side * 45, BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 3, Parent = holder,
		})
		new("UIStroke", { Thickness = 3, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = bar })
	end
	return holder
end
local boardVee = vee(boardGroup, 46, UDim.new(0, 118))

----------------------------------------------------------------------------------------------------
-- The banner (top of the screen, under the zone banner) with Skip / Let's go!
----------------------------------------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "Tutorial", ResetOnSpawn = false, Enabled = false, DisplayOrder = 4, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local uiScale = new("UIScale", { Parent = gui }) -- the HUD's design pixels: 900 tall at scale 1
local function rescale()
	local cam = workspace.CurrentCamera
	uiScale.Scale = math.clamp((if cam then cam.ViewportSize.Y else 900) / 900, 0.55, 1.25)
end
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

local W, H = 780, 100
local bannerGroup = new("CanvasGroup", {
	Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 160), Size = UDim2.fromOffset(W, H + 34),
	BackgroundTransparency = 1, GroupTransparency = 1, Parent = gui,
})
local plate = new("Frame", { Name = "Plate", Position = UDim2.fromOffset(4, 30), Size = UDim2.fromOffset(W - 8, H), BackgroundColor3 = BANNER, BorderSizePixel = 0, Parent = bannerGroup })
new("UIStroke", { Thickness = 5, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = plate })
ShopUi.studs(plate, BANNER)
ShopUi.bevel(plate)
local text = ShopUi.label(plate, 3, { Name = "Text", Text = "", Size = UDim2.new(1, -190, 1, -22), Position = UDim2.fromOffset(16, 11), ZIndex = 3 })
UiFx.relief(text, 3, 3)
-- "STEP 3 / 8" on a small tag over the plate's top-left corner
local tag = new("Frame", { Name = "Step", Position = UDim2.fromOffset(18, 4), Size = UDim2.fromOffset(150, 36), BackgroundColor3 = Color3.fromRGB(255, 200, 40), BorderSizePixel = 0, ZIndex = 4, Parent = bannerGroup })
new("UIStroke", { Thickness = 4, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = tag })
ShopUi.bevel(tag, 4)
local tagText = ShopUi.label(tag, 3, { Name = "Text", Text = "", Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), ZIndex = 5 })

local function plateButton(name: string, word: string, color: Color3): TextButton
	local b = new("TextButton", {
		Name = name, Text = "", AutoButtonColor = true, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(150, 60), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 4, Parent = plate,
	})
	new("UIStroke", { Thickness = 4, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	ShopUi.studs(b, color, nil, 4)
	ShopUi.bevel(b, 4)
	UiFx.relief(ShopUi.label(b, 3, { Name = "Word", Text = word, Size = UDim2.new(1, -20, 1, -16), Position = UDim2.fromOffset(10, 8), ZIndex = 6 }), 3, 3)
	UiFx.pop(b)
	return b
end
local skip = plateButton("Skip", "Skip", SKIP)
local go = plateButton("Go", "Let's go!", GO)
go.Visible = false
gui.Parent = playerGui

-- The pointer at the hotbar's seed slot (the plant step): a red V bobbing over it. In a ScreenGui of its own
-- with no UIScale, so it can sit on the slot's AbsolutePosition.
local pointerGui = new("ScreenGui", { Name = "TutorialPointer", ResetOnSpawn = false, Enabled = false, DisplayOrder = 6, Parent = playerGui })
local pointer = vee(pointerGui, 54, UDim.new(0, 0))
pointer.AnchorPoint = Vector2.new(0.5, 1)

local function seedSlot(): GuiObject?
	local hud = playerGui:FindFirstChild("SeedHUD")
	local hotbar = hud and hud:FindFirstChild("Hotbar")
	local slot = hotbar and hotbar:FindFirstChild("SeedSlot")
	if hud and hud:IsA("ScreenGui") then
		pointerGui.IgnoreGuiInset = hud.IgnoreGuiInset
	end
	return if slot and slot:IsA("GuiObject") and slot.Visible then slot else nil
end

----------------------------------------------------------------------------------------------------
-- Steps
----------------------------------------------------------------------------------------------------
local function fadeTo(inst: Instance, value: number)
	TweenService:Create(inst, FADE, { GroupTransparency = value }):Play()
end

local stop: () -> () = function() end

local function show(id: string)
	local s = Tutorial.step(id)
	if not s then
		return
	end
	-- the banner: fades out, takes the new words, fades back in
	fadeTo(bannerGroup, 1)
	task.delay(FADE.Time, function()
		if step ~= id then
			return
		end
		text.Text = s.banner
		tagText.Text = `STEP {Tutorial.indexOf(id)} / {#Tutorial.STEPS}`
		go.Visible = id == "ready"
		skip.Visible = id ~= "ready"
		fadeTo(bannerGroup, 0)
	end)
	-- the trail and the words: fade out, glide to the new target, fade back in (drawn every frame below)
	want, pending = 0, true
end

local function setStep(id: string)
	if id == step then
		return
	end
	if id == "done" then
		stop()
		return
	end
	step = id
	stepStart = os.clock()
	stepMoney, stepSpeed = stats.money or 0, stats.speed or 0
	lostAt = nil
	show(id)
end

local function on(event: string)
	if step then
		setStep(Tutorial.advance(step, event))
	end
end

local finished = false
local function finish(kind: string)
	if finished then
		return
	end
	finished = true
	TutorialRemote:FireServer(kind)
	stop()
end
skip.Activated:Connect(function()
	finish("skip")
end)
go.Activated:Connect(function()
	on("finish")
end)

local heartbeat: RBXScriptConnection? = nil
stop = function()
	if step and not finished then
		finished = true
		TutorialRemote:FireServer("done")
	end
	step = nil
	want, pending = 0, false
	fadeTo(bannerGroup, 1)
	fadeTo(boardGroup, 1)
	pointerGui.Enabled = false
	task.delay(0.6, function() -- let it all fade out first
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
		gui.Enabled = false
		board.Enabled = false
		folder:Destroy()
	end)
end

-- Every frame: the trail, the words, the pointer, and the checks that need the player's position or a clock.
local function frame(dt: number)
	local t = os.clock()
	local id = step
	-- fade: toward `want`; a pending step swaps its target once the old one has faded out
	shown += (want - shown) * (1 - math.exp(-10 * dt))
	if id and pending and shown < 0.03 then
		local pos, height = targetOf(id)
		target, labelHeight = pos, height
		trailFrom = nil
		pending = false
		if pos then
			anchor.Position = pos
		end
		local s = Tutorial.step(id)
		title.Text = if s then s.label else ""
	elseif id and not pending then
		-- (the pod, the bed, the treadmill and the sign stay put; the seedling may still turn up or become its plant)
		local pos = if target and not (id == "grow" or id == "earn" or id == "home") then target else targetOf(id)
		if pos then
			target = pos
			want = 1
		end
	end
	if target then
		anchor.Position = Tutorial.follow(anchor.Position, target, dt, 8)
	end
	board.StudsOffsetWorldSpace = Vector3.new(0, labelHeight + 0.6 * math.sin(t * 2.2), 0)
	boardVee.Position = UDim2.new(0.5, 0, 0, 118 + 5 * math.sin(t * 4))
	boardGroup.GroupTransparency = 1 - shown
	drawTrail(t, dt)

	-- the words under the title: the sprout timer, the plant's $/s, the Speed gained, the Speed needed
	if id == "grow" then
		local seedling = plantNear(plantPos, true)
		local left = if seedling then GrowNowUi.left(seedling:GetAttribute("SproutUntil")) else 0
		sub.Text = if left > 0 then `Grows in {GrowNowUi.clock(left)}` else "Almost there!"
	elseif id == "earn" then
		sub.Text = `{Format.money(stats.income or 0)}/s`
	elseif id == "speed" then
		sub.Text = `Speed +{Format.short(math.max(0, (stats.speed or 0) - stepSpeed))} / {Tutorial.SPEED_GOAL}`
	elseif id == "ready" then
		sub.Text = `{Format.short(Config.ZONES[2].req)} Speed`
	else
		sub.Text = ""
	end

	-- the pointer at the hotbar's seed slot while there is a seed to pick
	local slot = if id == "plant" then seedSlot() else nil
	pointerGui.Enabled = slot ~= nil
	if slot then
		local p = slot.AbsolutePosition
		pointer.Position = UDim2.fromOffset(p.X + slot.AbsoluteSize.X / 2, p.Y - 6 - 8 * (0.5 + 0.5 * math.sin(t * 5)))
	end

	-- the checks
	if not id or pending then
		return
	end
	local here = rootPos()
	if (id == "run" or id == "ready") and here and target then
		local flatD = Vector3.new(here.X - target.X, 0, here.Z - target.Z).Magnitude
		if flatD <= (if id == "run" then Tutorial.NEAR else Tutorial.ARRIVE) then
			on("near")
		end
	elseif id == "home" and lostAt and t - lostAt >= Tutorial.LOST_GRACE then
		on("lost")
	elseif id == "earn" and Tutorial.earned(stepMoney, stats.money or 0, t - stepStart) then
		on("earned")
	elseif id == "speed" and Tutorial.faster(stepSpeed, stats.speed or 0) then
		on("faster")
	end
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------
local started = false
local function start()
	if started then
		return
	end
	started = true
	gui.Enabled = true
	board.Enabled = true
	heartbeat = RunService.Heartbeat:Connect(frame)
	-- a player who left mid-way picks up where their stats say (a seed on their back, in the bag, planted...)
	-- (picking up at grow or earn, the plant is whichever of theirs plantNear finds)
	setStep(Tutorial.startStep(stats))
end

StatsUpdate.OnClientEvent:Connect(function(partial: { [string]: any })
	if type(partial) ~= "table" then
		return
	end
	local wasCarrying = stats.carrying
	for k, v in partial do
		stats[k] = v
	end
	if partial.tutorialDone == true then
		if step then
			finished = true -- (done on another server: nothing to send)
			stop()
		end
		started = true -- never starts now
		return
	end
	if partial.tutorialDone == false and not started then
		task.delay(1, start) -- the plants view and the plot arrive with it or right after
	end
	if partial.carrying ~= nil and step then
		if type(partial.carrying) == "table" then
			lostAt = nil
			on("pickup")
		elseif wasCarrying and step == "home" then
			lostAt = os.clock() -- caught, dropped or died, unless "Stored" follows
		end
	end
end)

LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if not step then
		return
	end
	if kind == "Stored" then
		lostAt = nil
		on("stored")
	elseif kind == "Planted" then
		plantPos = if type(data) == "table" and typeof(data.pos) == "Vector3" then data.pos else plantPos
		on("planted")
	elseif kind == "Sprouted" then
		plantPos = if type(data) == "table" and typeof(data.pos) == "Vector3" then data.pos else plantPos
		on("sprouted")
	end
end)
