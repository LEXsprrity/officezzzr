-- Animates rigged guardians (models with a "Rig" attribute, built on the server) on this client:
-- sets each Motor6D's C0 from GiantMole.pose every frame, and drives the local look (eyes, headlamp,
-- stun stars, dirt, footstep thumps, floating Zzz) from the guard's "State" attribute. Purely visual:
-- nothing here replicates or touches gameplay.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GiantMole = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GiantMole"))

local ANIMATE_RANGE = 360 -- studs from the camera

type Rig = {
	model: Model,
	root: BasePart?,
	motors: { [string]: Motor6D },
	rest: { [string]: CFrame },
	eyes: { BasePart },
	lens: BasePart?,
	lamp: SpotLight?,
	stars: { BasePart },
	dirt: { ParticleEmitter },
	thump: Sound?,
	zzz: BillboardGui?,
	zLabels: { TextLabel },
	state: string,
	stateSince: number,
	lastPos: Vector3?,
	speed: number,
	phase: number,
	lookState: string?,
}

local rigs: { [Model]: Rig } = {}

local function makeZzz(head: BasePart): (BillboardGui, { TextLabel })
	local gui = Instance.new("BillboardGui")
	gui.Name = "Zzz"
	gui.Size = UDim2.fromOffset(120, 140)
	gui.StudsOffsetWorldSpace = Vector3.new(2.5, 7.5, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.Adornee = head
	local labels = {}
	for i = 1, 3 do
		local z = Instance.new("TextLabel")
		z.BackgroundTransparency = 1
		z.Font = Enum.Font.FredokaOne
		z.Text = "Z"
		z.TextScaled = true
		z.TextColor3 = Color3.fromRGB(200, 225, 255)
		z.AnchorPoint = Vector2.new(0.5, 0.5)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(40, 50, 90)
		stroke.Parent = z
		z.Parent = gui
		labels[i] = z
	end
	gui.Parent = head
	return gui, labels
end

local function track(model: Model)
	if rigs[model] or model:GetAttribute("Rig") ~= "GiantMole" then
		return
	end
	local rig: Rig = {
		model = model, root = model:FindFirstChild("HumanoidRootPart") :: BasePart?, motors = {}, rest = {},
		eyes = {}, stars = {}, dirt = {}, zLabels = {}, state = "Sleeping", stateSince = os.clock(),
		speed = 0, phase = 0,
	}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			rig.motors[d.Name] = d
			rig.rest[d.Name] = d.C0
		elseif d:IsA("BasePart") then
			if d.Name == "EyeL" or d.Name == "EyeR" then
				table.insert(rig.eyes, d)
			elseif d.Name == "Lens" then
				rig.lens = d
			elseif d.Name == "StunStar" then
				table.insert(rig.stars, d)
			end
		elseif d:IsA("SpotLight") and d.Name == "Lamp" then
			rig.lamp = d
		elseif d:IsA("ParticleEmitter") and d.Name == "Dirt" then
			table.insert(rig.dirt, d)
		elseif d:IsA("Sound") and d.Name == "Thump" then
			rig.thump = d
		end
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		rig.zzz, rig.zLabels = makeZzz(head)
	end
	rig.state = (model:GetAttribute("State") :: string?) or "Sleeping"
	rigs[model] = rig
end

local function untrack(model: Model)
	local rig = rigs[model]
	if rig then
		if rig.zzz then
			rig.zzz:Destroy()
		end
		rigs[model] = nil
	end
end

local function applyLook(rig: Rig)
	if rig.lookState == rig.state then
		return
	end
	rig.lookState = rig.state
	local look = GiantMole.look(rig.state)
	for _, eye in rig.eyes do
		eye.Size = Vector3.new(eye.Size.X, look.eyeY, eye.Size.Z)
		eye.Color = look.eyeColor
		eye.Material = if look.eyeNeon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	if rig.lamp then
		rig.lamp.Enabled = look.lamp
	end
	if rig.lens then
		rig.lens.Material = if look.lamp then Enum.Material.Neon else Enum.Material.SmoothPlastic
		rig.lens.Color = if look.lamp then Color3.fromRGB(255, 244, 176) else Color3.fromRGB(150, 150, 140)
	end
	for _, s in rig.stars do
		s.Transparency = if look.stars then 0 else 1
	end
	if rig.zzz then
		rig.zzz.Enabled = look.zzz
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local t = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for model, rig in rigs do
		if not model.Parent then
			untrack(model)
			continue
		end
		local root = rig.root
		if not root or (root.Position - eye).Magnitude > ANIMATE_RANGE then
			continue
		end

		local state = (model:GetAttribute("State") :: string?) or "Sleeping"
		if state ~= rig.state then
			rig.state = state
			rig.stateSince = t
		end

		-- Ground speed from how far the root moved, smoothed; it drives the stride phase.
		local pos = root.Position
		if rig.lastPos and dt > 0 then
			local d = pos - rig.lastPos
			local v = Vector3.new(d.X, 0, d.Z).Magnitude / dt
			rig.speed += (math.min(v, 200) - rig.speed) * math.min(1, dt * 8)
		end
		rig.lastPos = pos
		local before = rig.phase
		rig.phase += rig.speed / GiantMole.STRIDE * 2 * math.pi * dt
		local moving = rig.speed > 2 and (state == "Chasing" or state == "Returning")
		if moving and rig.thump and math.floor(before / math.pi) ~= math.floor(rig.phase / math.pi) then
			rig.thump.PlaybackSpeed = 0.4 + math.random() * 0.12
			rig.thump:Play()
		end

		local swipeAt = model:GetAttribute("SwipeAt") :: number?
		local pose = GiantMole.pose(state, t, t - rig.stateSince, rig.phase, if swipeAt then serverNow - swipeAt else nil)
		for name, motor in rig.motors do
			local offset = pose[name]
			if offset then
				motor.C0 = rig.rest[name] * offset
			end
		end

		applyLook(rig)
		local look = GiantMole.look(state)
		local rate = if moving then rig.speed * look.dirtPerSpeed else 0
		for _, e in rig.dirt do
			e.Rate = rate
		end
		if look.zzz then
			for i, z in rig.zLabels do
				local k = (t * 0.45 + i / 3) % 1
				z.Position = UDim2.fromScale(0.3 + 0.35 * k + 0.08 * math.sin(t * 2 + i), 1 - k)
				z.Size = UDim2.fromScale(0.22 + 0.3 * k, 0.22 + 0.3 * k)
				z.TextTransparency = if k < 0.15 then 1 - k / 0.15 else math.max(0, (k - 0.6) / 0.4)
			end
		end
	end
end)

local function consider(inst: Instance)
	if inst:IsA("Model") and inst:GetAttribute("Rig") ~= nil then
		task.defer(track, inst) -- let its parts arrive first
	end
end
for _, d in workspace:GetDescendants() do
	consider(d)
end
workspace.DescendantAdded:Connect(consider)
workspace.DescendantRemoving:Connect(function(inst)
	if inst:IsA("Model") and rigs[inst] then
		untrack(inst)
	end
end)
