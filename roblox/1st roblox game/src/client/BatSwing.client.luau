-- Swinging the Bat (owner 2026-10-16): 1 / the hotbar slot only equips it (HUD.client); with it in hand a
-- left click (a tap on mobile: the Tool's Activated) swings it: the strike animation, the swoosh and the
-- bat's trail, then RequestUseItem "Bat" (the server stuns the nearest awake guard in reach, only while
-- the bat is in hand: BatTool.equipped). One swing per Config.BAT_COOLDOWN, like the server's.
-- The strike, a baseball swing (owner 2026-10-16: "add some bat hitting animation"): the bat cocked back
-- by the head with the body turned away, then whipped round across the front with the whole torso, a
-- follow-through, and back. Played on the joints (the right shoulder, and on R15 the waist and the left
-- shoulder), so it needs no uploaded animation. A hit (LootEvent "BatHit", to everyone) bursts into a
-- comic "POW!", stars and a thwack where it landed; whoever was hit spins as they fly (LootEvent "Knock")
-- and their camera shakes.
-- A joint's Transform doesn't replicate, so the server passes each swing on (LootEvent "BatSwing" to every
-- client) and every other client plays the same strike on that character.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestUseItem = remotes:WaitForChild("RequestUseItem") :: RemoteEvent
local LootEvent = remotes:WaitForChild("LootEvent") :: RemoteEvent

local player = Players.LocalPlayer

local WIND_UP, STRIKE, HOLD, RECOVER = 0.16, 0.12, 0.08, 0.22 -- seconds
local nextSwing = 0
local swinging = false

-- The joints a swing turns, by name (R15, then R6), and each one's pose: { cocked back, swung through }.
-- Offsets on top of the bat-holding pose, the arm held out in front.
local JOINTS = {
	{ names = { "RightShoulder", "Right Shoulder" }, back = CFrame.Angles(math.rad(40), math.rad(75), math.rad(10)),
		through = CFrame.Angles(math.rad(5), math.rad(-85), math.rad(-10)) },
	{ names = { "LeftShoulder" }, back = CFrame.Angles(math.rad(70), math.rad(45), 0), -- the other hand on the bat
		through = CFrame.Angles(math.rad(80), math.rad(-60), 0) },
	{ names = { "Waist" }, back = CFrame.Angles(0, math.rad(35), math.rad(-5)), through = CFrame.Angles(0, math.rad(-45), math.rad(5)) },
}

local function jointsOf(char: Model): { { motor: Motor6D, back: CFrame, through: CFrame } }
	local out = {}
	for _, j in JOINTS do
		for _, name in j.names do
			local m = char:FindFirstChild(name, true)
			if m and m:IsA("Motor6D") then
				table.insert(out, { motor = m, back = j.back, through = j.through })
				break
			end
		end
	end
	return out
end

local function play(sound: Instance?)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

-- A joint's offset at time t of the swing: eased back into the wind-up, whipped through (fast at the
-- end), held a moment on the follow-through, eased home.
local function poseAt(t: number, back: CFrame, through: CFrame): CFrame
	if t < WIND_UP then
		local a = t / WIND_UP
		return CFrame.identity:Lerp(back, a * (2 - a))
	elseif t < WIND_UP + STRIKE then
		local a = (t - WIND_UP) / STRIKE
		return back:Lerp(through, a * a)
	elseif t < WIND_UP + STRIKE + HOLD then
		return through
	end
	local a = math.clamp((t - WIND_UP - STRIKE - HOLD) / RECOVER, 0, 1)
	return through:Lerp(CFrame.identity, a * (2 - a))
end

local animate: (char: Model, tool: Instance, onHit: (() -> ())?, onDone: (() -> ())?) -> ()

local function swing(tool: Tool)
	local now = os.clock()
	if swinging or now < nextSwing then
		return
	end
	local char = tool.Parent
	if not char or not char:IsA("Model") then
		return
	end
	nextSwing = now + Config.BAT_COOLDOWN
	swinging = true
	animate(char, tool, function()
		RequestUseItem:FireServer("Bat") -- the hit lands mid-swing
	end, function()
		swinging = false
	end)
end

-- The strike on `char`'s arm with `tool`: the swoosh and trail, `onHit` mid-swing, `onDone` at the end.
animate = function(char: Model, tool: Instance, onHit: (() -> ())?, onDone: (() -> ())?)
	local handle = tool:FindFirstChild("Handle")
	play(handle and handle:FindFirstChild("Swoosh"))
	local trail = handle and handle:FindFirstChildWhichIsA("Trail")
	if trail then
		trail.Enabled = true
	end
	local joints = jointsOf(char)
	local start = os.clock()
	local fired = false
	local bases: { CFrame } = {}
	local written: { CFrame? } = {}
	local conn: RBXScriptConnection
	conn = RunService.Stepped:Connect(function()
		local t = os.clock() - start
		for i, j in joints do
			if j.motor.Parent then
				-- the animations set Transform every frame; when none did since our last write, keep our base
				-- (multiplying our own pose again would spin the joint)
				if j.motor.Transform ~= written[i] then
					bases[i] = j.motor.Transform
				end
				local pose = (bases[i] or CFrame.identity) * poseAt(t, j.back, j.through)
				written[i] = pose
				j.motor.Transform = pose
			end
		end
		if not fired and t >= WIND_UP + STRIKE * 0.6 then
			fired = true
			if onHit then
				onHit()
			end
		end
		if t >= WIND_UP + STRIKE + HOLD + RECOVER then
			conn:Disconnect()
			for i, j in joints do
				if j.motor.Parent and j.motor.Transform == written[i] then
					j.motor.Transform = bases[i] or CFrame.identity
				end
			end
			if onDone then
				onDone()
			end
			if trail then
				trail.Enabled = false
			end
		end
	end)
end

local function watchTool(tool: Instance)
	if tool and tool:IsA("Tool") and tool.Name == "Bat" and not tool:GetAttribute("SwingWired") then
		tool:SetAttribute("SwingWired", true)
		tool.Activated:Connect(function()
			swing(tool)
		end)
		tool.Equipped:Connect(function()
			local handle = tool:FindFirstChild("Handle")
			play(handle and handle:FindFirstChild("Equip"))
		end)
	end
end

local function watch(container: Instance)
	for _, c in container:GetChildren() do
		watchTool(c)
	end
	container.ChildAdded:Connect(watchTool)
end

player.CharacterAdded:Connect(watch)
if player.Character then
	watch(player.Character)
end
local backpack = player:FindFirstChildOfClass("Backpack") -- (a later one: ChildAdded below)
if backpack then
	watch(backpack)
end
player.ChildAdded:Connect(function(c)
	if c:IsA("Backpack") then
		watch(c)
	end
end)

-- Where a bat hit lands: a burst of stars and sparks, a comic "POW!" that pops up and fades, and the bat's
-- thwack (the hitter's own bat sound, played at the spot so everyone near hears it).
local POW_WORDS = { "POW!", "BONK!", "WHACK!", "BAM!" }
local POW_COLORS = { Color3.fromRGB(255, 225, 40), Color3.fromRGB(255, 120, 40), Color3.fromRGB(255, 70, 90) }
local function hitBurst(at: Vector3, hitter: Player?)
	local spot = Instance.new("Part")
	spot.Name = "BatHit"
	spot.Anchored, spot.CanCollide, spot.CanTouch, spot.CanQuery = true, false, false, false
	spot.Transparency = 1
	spot.Size = Vector3.new(1, 1, 1)
	spot.CFrame = CFrame.new(at)
	spot.Parent = workspace
	Debris:AddItem(spot, 1.5)

	local stars = Instance.new("ParticleEmitter")
	stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	stars.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 255, 255))
	stars.LightEmission = 0.6
	stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	stars.Lifetime = NumberRange.new(0.35, 0.6)
	stars.Speed = NumberRange.new(18, 30)
	stars.SpreadAngle = Vector2.new(180, 180)
	stars.Drag = 4
	stars.Rate = 0
	stars.Parent = spot
	stars:Emit(26)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(7, 3.5)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = spot
	local word = Instance.new("TextLabel")
	word.BackgroundTransparency = 1
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Position = UDim2.fromScale(0.5, 0.5)
	word.Size = UDim2.fromScale(0.3, 0.3)
	word.Rotation = math.random(-14, 14)
	word.Font = Enum.Font.FredokaOne
	word.TextScaled = true
	word.Text = POW_WORDS[math.random(#POW_WORDS)]
	word.TextColor3 = POW_COLORS[math.random(#POW_COLORS)]
	word.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(16, 18, 26)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = word
	TweenService:Create(word, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
	task.delay(0.55, function()
		TweenService:Create(word, TweenInfo.new(0.4), { TextTransparency = 1, Position = UDim2.fromScale(0.5, 0.2) }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	end)

	local char = hitter and hitter.Character
	local tool = char and char:FindFirstChild("Bat")
	local handle = tool and tool:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild("Hit")
	if sound and sound:IsA("Sound") then
		local copy = sound:Clone()
		copy.Parent = spot
		copy:Play()
	end
end

-- The hit player's camera shakes for a moment.
local function shake(hum: Humanoid)
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 0.35 or not hum.Parent then
			conn:Disconnect()
			hum.CameraOffset = Vector3.zero
			return
		end
		local k = 0.9 * (1 - t / 0.35)
		hum.CameraOffset = Vector3.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
	end)
end

-- A knock (fly a little way), someone else's swing (the server passes it on), and a hit: the bat's thwack
LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "Knock" and type(data) == "table" and typeof(data.velocity) == "Vector3" then
		-- Caught by a boss or hit with a bat: fly a little way (SpeedService.knock). The humanoid lets go
		-- (PlatformStand) so the fling isn't braked, then stands back up.
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and root and hum.Health > 0 then
			hum.PlatformStand = true
			root.AssemblyLinearVelocity = data.velocity
			-- a tumble while flying: a spin round the way they fly
			local flat = Vector3.new(data.velocity.X, 0, data.velocity.Z)
			local axis = if flat.Magnitude > 0.1 then flat.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
			root.AssemblyAngularVelocity = -axis * 6 + Vector3.yAxis * (math.random() - 0.5) * 6
			shake(hum)
			task.delay(tonumber(data.seconds) or 0.7, function()
				if hum.Parent then
					hum.PlatformStand = false
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end)
		end
	elseif kind == "BatSwing" and type(data) == "table" and typeof(data.player) == "Instance" and data.player ~= player then
		local char = (data.player :: Player).Character
		local tool = char and char:FindFirstChild("Bat")
		if char and tool then
			animate(char, tool)
		end
	elseif kind == "BatHit" and type(data) == "table" and typeof(data.at) == "Vector3" then
		hitBurst(data.at, if typeof(data.player) == "Instance" then data.player else nil)
	end
end)
