-- Animates the zone bosses (rigged pets with a "Rig" attribute, built on the server by GuardService) on
-- this client: every frame it poses their Bones (Bone.Transform) with BossRigs from the guard's "State"
-- attribute, cross-fading between states, and drives the local look: footstep dust and thumps, and the
-- floating Zzz while asleep. Only bosses within ANIMATE_RANGE of the camera are posed. Near a side wall
-- the body slides inward a little (BossRigs.wallShift) so it never pokes through. Purely visual: nothing
-- here replicates or touches gameplay.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossRigs = require(Shared:WaitForChild("BossRigs"))
local Config = require(Shared:WaitForChild("Config"))

local ANIMATE_RANGE = 150 -- studs from the camera
local WALL = Config.CORRIDOR_WIDTH / 2 - 1 -- the side walls' inner faces, less a stud
local FULL_SPEED = 6 -- studs/s at which the gait reaches full swing
local MAX_STRIDES = 3 -- stride cycles per second, at most (the late zones' bosses run very fast)

type Boss = {
	model: Model,
	root: BasePart,
	profile: BossRigs.Profile,
	rig: BossRigs.Rig,
	lo: Vector3, -- the body's rest bounds around the root's ground point (studs, model axes)
	hi: Vector3,
	stride: number, -- studs per stride cycle
	legged: boolean,
	dust: ParticleEmitter,
	thump: Sound,
	zzz: BillboardGui?,
	zLabels: { TextLabel },
	state: string,
	stateSince: number,
	wokeAt: number?,
	fromPose: BossRigs.Pose?, -- the pose being faded out after a state change
	lastPose: BossRigs.Pose?,
	lastPos: Vector3?,
	speed: number,
	phase: number,
}

local bosses: { [Model]: Boss } = {}

local function makeZzz(head: BasePart): (BillboardGui, { TextLabel })
	local gui = Instance.new("BillboardGui")
	gui.Name = "Zzz"
	gui.Size = UDim2.fromOffset(120, 140)
	gui.StudsOffsetWorldSpace = Vector3.new(2.5, 7.5, 0)
	gui.MaxDistance = 100
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

-- Dust kicked up at the boss's feet (rate set by its speed) and a heavy footstep sound.
local function makeFeet(root: BasePart, hip: number): (ParticleEmitter, Sound)
	local a = Instance.new("Attachment")
	a.Name = "BossFeet"
	a.Position = Vector3.new(0, -(root.Size.Y / 2 + hip), 0)
	a.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Name = "Dust"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(205, 192, 170), Color3.fromRGB(235, 228, 214))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = NumberRange.new(4, 10)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Acceleration = Vector3.new(0, -10, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Rate = 0
	e.Parent = a
	local s = Instance.new("Sound")
	s.Name = "Thump"
	s.SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
	s.Volume = 0.6
	s.RollOffMaxDistance = 140
	s.Parent = root
	return e, s
end

local function track(model: Model)
	if bosses[model] or not model.Parent then
		return
	end
	local profile = BossRigs.PROFILES[model:GetAttribute("Rig") :: any]
	local root = model:FindFirstChild("HumanoidRootPart")
	local lo, hi = model:GetAttribute("BodyMin"), model:GetAttribute("BodyMax")
	if not profile or not root or not root:IsA("BasePart") or typeof(lo) ~= "Vector3" or typeof(hi) ~= "Vector3" then
		return
	end
	local body: Model? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("BossRig") ~= nil then
			body = d
			break
		end
	end
	local host = body and body.PrimaryPart
	if not body or not host then
		return
	end
	local scale = tonumber(body:GetAttribute("RigScale")) or 1
	if profile.halfWidth then
		local w = profile.halfWidth * scale
		lo, hi = Vector3.new(-w, lo.Y, lo.Z), Vector3.new(w, hi.Y, hi.Z)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local dust, thump = makeFeet(root, if humanoid then humanoid.HipHeight else 0)
	local boss: Boss = {
		model = model, root = root, profile = profile, rig = BossRigs.rig(host, profile, scale), lo = lo, hi = hi,
		stride = profile.stride * scale, legged = profile.legs ~= nil and #profile.legs > 0,
		dust = dust, thump = thump, zLabels = {},
		state = (model:GetAttribute("State") :: string?) or "Sleeping", stateSince = os.clock(), speed = 0, phase = 0,
	}
	thump.PlaybackSpeed = math.clamp(1.1 - scale * 0.08, 0.45, 0.9)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		boss.zzz, boss.zLabels = makeZzz(head)
	end
	bosses[model] = boss
end

local function untrack(model: Model)
	local boss = bosses[model]
	if boss then
		for _, d in { boss.zzz, boss.thump, boss.dust.Parent } do
			if d then
				d:Destroy()
			end
		end
		bosses[model] = nil
	end
end

local function animate(boss: Boss, t: number, dt: number, serverNow: number)
	local model, root = boss.model, boss.root
	local state = (model:GetAttribute("State") :: string?) or "Sleeping"
	if state ~= boss.state then
		if boss.state == "Sleeping" then
			boss.wokeAt = t
		end
		boss.fromPose = boss.lastPose
		boss.state = state
		boss.stateSince = t
	end

	-- Ground speed from how far the root moved, smoothed; it drives the stride phase.
	local pos = root.Position
	if boss.lastPos and dt > 0 then
		local d = pos - boss.lastPos
		local v = Vector3.new(d.X, 0, d.Z).Magnitude / dt
		boss.speed += (math.min(v, 400) - boss.speed) * math.min(1, dt * 8)
	end
	boss.lastPos = pos
	local before = boss.phase
	boss.phase += math.min(boss.speed / boss.stride, MAX_STRIDES) * 2 * math.pi * dt
	local moving = boss.speed > 2 and (state == "Chasing" or state == "Returning")

	local catchAt = model:GetAttribute("CatchAt") :: number?
	local age = t - boss.stateSince
	local pose = BossRigs.pose(boss.profile, {
		state = state, t = t, age = age, phase = boss.phase,
		move = if moving then math.clamp(boss.speed / FULL_SPEED, 0, 1) else 0,
		woke = if boss.wokeAt and t - boss.wokeAt < BossRigs.WAKE_TIME then t - boss.wokeAt else nil,
		catch = if catchAt and serverNow - catchAt < BossRigs.CATCH_TIME then math.max(0, serverNow - catchAt) else nil,
	})
	boss.lastPose = pose
	if boss.fromPose and age < BossRigs.BLEND_TIME then
		local w = age / BossRigs.BLEND_TIME
		pose = BossRigs.blend(boss.fromPose :: BossRigs.Pose, pose, w * w * (3 - 2 * w))
	else
		boss.fromPose = nil
	end

	local shift = BossRigs.wallShift(pos, root.CFrame.LookVector, boss.lo, boss.hi, WALL)
	local transforms = BossRigs.solve(boss.rig, pose, shift)
	for joint, cf in transforms do
		joint.bone.Transform = cf
	end

	-- Footsteps: a thump every half stride, dust while running.
	if moving and boss.legged and math.floor(before / math.pi) ~= math.floor(boss.phase / math.pi) then
		boss.thump:Play()
	end
	boss.dust.Rate = if moving then math.min(boss.speed, 120) * (if state == "Chasing" then 0.6 else 0.25) else 0

	if boss.zzz then
		local asleep = state == "Sleeping"
		boss.zzz.Enabled = asleep
		if asleep then
			for i, z in boss.zLabels do
				local k = (t * 0.45 + i / 3) % 1
				z.Position = UDim2.fromScale(0.3 + 0.35 * k + 0.08 * math.sin(t * 2 + i), 1 - k)
				z.Size = UDim2.fromScale(0.22 + 0.3 * k, 0.22 + 0.3 * k)
				z.TextTransparency = if k < 0.15 then 1 - k / 0.15 else math.max(0, (k - 0.6) / 0.4)
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local t = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for model, boss in bosses do
		if not model.Parent then
			untrack(model)
		elseif (boss.root.Position - eye).Magnitude <= ANIMATE_RANGE then
			animate(boss, t, dt, serverNow)
		else
			boss.lastPos = nil -- (no speed spike from the distance it covered unseen)
			boss.dust.Rate = 0
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
	if inst:IsA("Model") and bosses[inst] then
		untrack(inst)
	end
end)
