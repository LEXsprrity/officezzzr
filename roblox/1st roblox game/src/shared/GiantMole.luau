--!strict
-- The Meadow boss: a star-nosed Giant Mole in a miner's helmet, built as a real rig (bones joined by
-- Motor6Ds) so it can be animated. The server builds it (GuardService); every client animates it
-- locally from the guard's "State" attribute (GuardAnimator.client) using GiantMole.pose, which is
-- pure math so the Lune tests and the preview exporter run the exact same animation.
--
-- Space: built around a ground CFrame (on the floor under the HumanoidRootPart, front = -Z).
-- Studs, X right, Y up. About 13 wide, 15 tall (helmet) and 24 long (nose to tail).
local GiantMole = {}

local rad, sin, cos, abs, exp, clamp, pi = math.rad, math.sin, math.cos, math.abs, math.exp, math.clamp, math.pi

local FUR = Color3.fromRGB(86, 66, 60)
local FUR_LIGHT = Color3.fromRGB(132, 104, 90)
local BELLY = Color3.fromRGB(168, 134, 112)
local PINK = Color3.fromRGB(242, 150, 160)
local STAR = Color3.fromRGB(255, 120, 168)
local CLAW = Color3.fromRGB(252, 238, 210)
local HELMET = Color3.fromRGB(255, 196, 36)
local METAL = Color3.fromRGB(88, 90, 98)

-- Joint name -> { parent bone, child bone }. Order matters: parents before children.
GiantMole.JOINTS = {
	"Spine", "Neck", "Nose", "HelmetJ", "HaloJ",
	"ShoulderL", "ShoulderR", "WristL", "WristR", "HipL", "HipR", "TailJ",
}

GiantMole.HEAD_LABEL_OFFSETS = { status = 9.5, name = 7.4 } -- above the Head bone's centre

type Builder = { model: Model, ground: CFrame }

local function newPart(b: Builder, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = b.ground * cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = b.model
	return p
end

-- An ellipsoid: a block with a built-in Sphere mesh, so Size sets the three radii.
local function blob(b: Builder, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = newPart(b, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A cylinder whose axis runs from local point a to b (Roblox cylinders run along their X axis).
local function rod(b: Builder, name: string, a: Vector3, c: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	local dir = c - a
	local len = dir.Magnitude
	local x = dir.Unit
	local up = if abs(x.Y) > 0.95 then Vector3.zAxis else Vector3.yAxis
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	local cf = CFrame.fromMatrix((a + c) / 2, x, y, z)
	return newPart(b, name, Vector3.new(len, diameter, diameter), cf, color, material, Enum.PartType.Cylinder)
end

local function weld(bone: BasePart, part: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = bone
	w.Part1 = part
	w.Parent = part
end

-- A Motor6D whose pivot is at `pivot` (ground space): bones rotate around their real joint.
local function joint(b: Builder, name: string, part0: BasePart, part1: BasePart, pivot: Vector3)
	local world = b.ground * CFrame.new(pivot)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * world
	m.C1 = part1.CFrame:Inverse() * world
	m.Parent = part1
end

local function emitter(parent: BasePart, offset: Vector3): ParticleEmitter
	local a = Instance.new("Attachment")
	a.Name = "DirtAttachment"
	a.Position = offset
	a.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Name = "Dirt"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(122, 88, 58), Color3.fromRGB(160, 128, 92))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = NumberRange.new(4, 9)
	e.SpreadAngle = Vector2.new(55, 55)
	e.Acceleration = Vector3.new(0, -14, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Rate = 0 -- the client turns it up with speed
	e.Parent = a
	return e
end

-- Builds the rig into `model` around `ground`, joined to `root` (the HumanoidRootPart). Returns the Head.
function GiantMole.build(model: Model, root: BasePart, ground: CFrame): BasePart
	local b: Builder = { model = model, ground = ground }
	local V = Vector3.new

	-- Body: a pear of fur with a lighter belly and a ridge of tufts.
	local body = blob(b, "MoleBody", V(12.5, 9.5, 15), CFrame.new(0, 5.4, 0), FUR, Enum.Material.Fabric)
	joint(b, "Spine", root, body, V(0, 5.4, 0))
	weld(body, blob(b, "Rump", V(11, 8.4, 7), CFrame.new(0, 5.2, 5.4), FUR, Enum.Material.Fabric))
	weld(body, blob(b, "Belly", V(9.6, 6.8, 12.4), CFrame.new(0, 4.1, -0.9), BELLY, Enum.Material.Fabric))
	for i, z in { -4.5, -2, 0.5, 3, 5.5 } do
		local tuft = newPart(b, "Tuft", V(1.3, 1.5, 2.2), CFrame.new(0, 9.9 - abs(z) * 0.12, z) * CFrame.Angles(rad(-35), 0, rad(if i % 2 == 0 then 8 else -8)), FUR_LIGHT, Enum.Material.Fabric)
		weld(body, tuft)
	end

	-- Head
	local head = blob(b, "Head", V(8.6, 7.6, 8.4), CFrame.new(0, 8.2, -8.4), FUR, Enum.Material.Fabric)
	joint(b, "Neck", body, head, V(0, 7.2, -6))
	weld(head, blob(b, "Snout", V(3.8, 3.3, 5.4), CFrame.new(0, 7.2, -12.6), FUR_LIGHT, Enum.Material.Fabric))
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		local eye = blob(b, "Eye" .. side, V(1, 1.05, 0.7), CFrame.new(s * 2.15, 9.6, -11.75), Color3.fromRGB(22, 18, 24), Enum.Material.SmoothPlastic)
		eye.Reflectance = 0.25
		weld(head, eye)
		weld(head, newPart(b, "Shine", V(0.34, 0.34, 0.2), CFrame.new(s * 2.0, 9.85, -12.08), Color3.new(1, 1, 1), Enum.Material.Neon, Enum.PartType.Ball))
		weld(head, newPart(b, "Brow", V(1.8, 0.38, 0.5), CFrame.new(s * 2.15, 10.55, -11.6) * CFrame.Angles(0, 0, rad(-s * 16)), Color3.fromRGB(52, 38, 34)))
		weld(head, blob(b, "Cheek", V(1.7, 1.0, 0.4), CFrame.new(s * 3.05, 7.9, -10.9) * CFrame.Angles(0, rad(s * 38), 0), Color3.fromRGB(255, 150, 170)))
		weld(head, blob(b, "Ear", V(1.2, 2.0, 1.6), CFrame.new(s * 4.05, 10.2, -7.6), FUR_LIGHT, Enum.Material.Fabric))
		for i, dy in { -0.35, 0.1, 0.55 } do
			local base = V(s * 1.7, 7.2 + dy, -13.9)
			local tip = base + V(s * 3.6, dy * 1.6 - 0.3, 0.9 + i * 0.25)
			weld(head, rod(b, "Whisker", base, tip, 0.13, Color3.fromRGB(235, 230, 220)))
		end
		weld(head, newPart(b, "Tooth", V(0.78, 1.15, 0.36), CFrame.new(s * 0.43, 5.55, -14.45), Color3.fromRGB(255, 252, 240)))
	end
	weld(head, newPart(b, "Mouth", V(2.3, 0.22, 0.22), CFrame.new(0, 6.15, -14.35), Color3.fromRGB(70, 30, 36)))

	-- The star nose: a pink core ringed by 16 little tentacles that wiggle as it sniffs.
	local star = newPart(b, "StarCore", V(1.6, 1.6, 1.6), CFrame.new(0, 7.2, -15.45), STAR, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	joint(b, "Nose", head, star, V(0, 7.2, -15.1))
	for i = 1, 16 do
		local a = i / 16 * 2 * pi
		local dir = V(cos(a), sin(a), 0)
		local from = V(0, 7.2, -15.45) + dir * 0.55
		local to = V(0, 7.2, -15.45) + dir * 1.85 + V(0, 0, -0.75)
		weld(star, rod(b, "Tentacle", from, to, 0.5, if i % 2 == 0 then STAR else PINK))
	end

	-- Miner's helmet with a working headlamp.
	local helmet = blob(b, "Helmet", V(8, 5.2, 8), CFrame.new(0, 11.7, -8.2), HELMET, Enum.Material.SmoothPlastic)
	joint(b, "HelmetJ", head, helmet, V(0, 10.8, -8.2))
	weld(helmet, rod(b, "Brim", V(0, 10.45, -8.3), V(0, 10.9, -8.3), 9.4, HELMET:Lerp(Color3.new(0, 0, 0), 0.12)))
	weld(helmet, rod(b, "Band", V(-4.05, 11.0, -8.2), V(4.05, 11.0, -8.2), 0.6, Color3.fromRGB(60, 52, 48)))
	weld(helmet, rod(b, "LampHousing", V(0, 12.0, -11.5), V(0, 12.0, -13.0), 2.5, METAL, Enum.Material.Metal))
	local lens = rod(b, "Lens", V(0, 12.0, -12.95), V(0, 12.0, -13.2), 2.0, Color3.fromRGB(255, 244, 176), Enum.Material.Neon)
	weld(helmet, lens)
	local lamp = Instance.new("SpotLight")
	lamp.Name = "Lamp"
	lamp.Face = Enum.NormalId.Right -- the lens's +X points forward (rod axis)
	lamp.Angle = 55
	lamp.Range = 46
	lamp.Brightness = 5
	lamp.Color = Color3.fromRGB(255, 236, 170)
	lamp.Shadows = true
	lamp.Enabled = false
	lamp.Parent = lens

	-- Stun halo: three stars that only show (and spin) when stunned.
	local halo = newPart(b, "HaloCore", V(0.2, 0.2, 0.2), CFrame.new(0, 16.0, -8.4), HELMET)
	halo.Transparency = 1
	joint(b, "HaloJ", head, halo, V(0, 16.0, -8.4))
	for i = 1, 3 do
		local a = i / 3 * 2 * pi
		local starPart = newPart(b, "StunStar", V(1.4, 1.4, 0.35), CFrame.new(cos(a) * 3.2, 16.0, -8.4 + sin(a) * 3.2) * CFrame.Angles(0, -a, rad(45)), Color3.fromRGB(255, 230, 60), Enum.Material.Neon)
		starPart.Transparency = 1
		weld(halo, starPart)
	end

	-- Front arms: the mole's giant shovel paws with five claws each.
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		local arm = blob(b, "UpperArm" .. side, V(3.6, 5.4, 3.8), CFrame.new(s * 5.7, 4.8, -5.2), FUR, Enum.Material.Fabric)
		joint(b, "Shoulder" .. side, body, arm, V(s * 5.0, 6.8, -5.0))
		local paw = blob(b, "Paw" .. side, V(5.8, 1.6, 5.4), CFrame.new(s * 6.8, 1.35, -7.3) * CFrame.Angles(0, 0, rad(-s * 18)), PINK, Enum.Material.SmoothPlastic)
		joint(b, "Wrist" .. side, arm, paw, V(s * 6.1, 2.5, -6.2))
		for i = -2, 2 do
			local base = V(s * 6.8 + i * 1.05, 1.0, -9.6)
			weld(paw, rod(b, "Claw", base, base + V(i * 0.25, -0.55, -2.7), 0.62, CLAW))
		end
		emitter(paw, V(0, -0.8, 0))

		-- Back legs: short and stubby, with little pink feet.
		local thigh = blob(b, "Thigh" .. side, V(3.8, 4.2, 4.6), CFrame.new(s * 4.5, 3.1, 5.0), FUR, Enum.Material.Fabric)
		joint(b, "Hip" .. side, body, thigh, V(s * 4.3, 4.6, 4.8))
		weld(thigh, blob(b, "Foot", V(2.9, 1.0, 3.8), CFrame.new(s * 4.7, 0.6, 3.6), PINK))
		for i = -1, 1 do
			local base = V(s * 4.7 + i * 0.8, 0.5, 1.8)
			weld(thigh, rod(b, "Claw", base, base + V(0, -0.2, -1.1), 0.42, CLAW))
		end
		emitter(thigh, V(0, -2.4, -1.2))
	end

	-- Tail
	local tail = rod(b, "Tail", V(0, 5.8, 7.6), V(0, 7.3, 10.6), 0.95, PINK)
	joint(b, "TailJ", body, tail, V(0, 5.8, 7.6))

	local thump = Instance.new("Sound")
	thump.Name = "Thump"
	thump.SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
	thump.PlaybackSpeed = 0.45
	thump.Volume = 0.9
	thump.RollOffMaxDistance = 140
	thump.Parent = body

	model:SetAttribute("Rig", "GiantMole")
	return head
end

----------------------------------------------------------------------------------------------------
-- Animation: offsets applied on top of each joint's rest C0 (C0 = restC0 * offset).
----------------------------------------------------------------------------------------------------
export type Pose = { [string]: CFrame }

local A = CFrame.Angles
local function P(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function sleeping(t: number): Pose
	local breath = sin(t * 1.35)
	return {
		Spine = P(0, -0.55 + 0.22 * breath, 0) * A(rad(3), 0, rad(1.5 * sin(t * 0.45))),
		Neck = P(0, -0.7, 0.3) * A(rad(-17 - 2.5 * breath), 0, rad(7)),
		HelmetJ = P(0, -0.35, -1.0) * A(rad(-24), 0, rad(-9)),
		Nose = A(0, 0, rad(5 * sin(t * 1.9))),
		HaloJ = CFrame.identity,
		ShoulderL = A(rad(40), rad(-12), rad(14)),
		ShoulderR = A(rad(40), rad(12), rad(-14)),
		WristL = A(rad(-30), 0, 0),
		WristR = A(rad(-30), 0, 0),
		HipL = A(rad(22), 0, 0),
		HipR = A(rad(22), 0, 0),
		TailJ = A(0, rad(10 * sin(t * 0.7)), 0),
	}
end

local function alert(t: number): Pose
	return {
		Spine = P(0, 0.9, 0) * A(rad(-9), 0, 0),
		Neck = A(rad(16), 0, 0),
		HelmetJ = P(0, 0.25, 0) * A(rad(9), 0, 0),
		Nose = A(0, 0, rad(22 * sin(t * 16))),
		HaloJ = CFrame.identity,
		ShoulderL = A(rad(-12), 0, rad(-38)),
		ShoulderR = A(rad(-12), 0, rad(38)),
		WristL = A(rad(25), 0, 0),
		WristR = A(rad(25), 0, 0),
		HipL = A(rad(8), 0, 0),
		HipR = A(rad(8), 0, 0),
		TailJ = A(rad(20), rad(25 * sin(t * 12)), 0),
	}
end

-- Gallop: `p` is the stride phase (radians), `k` scales the amplitude (1 chase, ~0.5 walking home).
local function gallop(t: number, p: number, k: number, grumpy: boolean): Pose
	local pose: Pose = {
		Spine = P(0, 0.75 * k * abs(sin(p)) + 0.6, 0) * A(rad(-6 * k + 5 * k * sin(2 * p)), rad(4 * k * sin(p)), rad(3 * k * sin(p))),
		Neck = A(rad((if grumpy then -10 else 4) + 6 * k * sin(2 * p + 0.6)), rad(-4 * k * sin(p)), 0),
		HelmetJ = P(0, 0.3 * k * abs(sin(p + 0.4)), 0) * A(rad(5 * k * sin(2 * p + 1.2)), 0, 0),
		Nose = A(0, 0, rad(18 * sin(t * (if grumpy then 6 else 15)))),
		HaloJ = CFrame.identity,
		TailJ = A(rad(10), rad(30 * k * sin(2 * p)), 0),
	}
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		local ap = p + (if s > 0 then pi else 0) -- arms alternate like a front crawl
		local lp = ap + pi
		pose["Shoulder" .. side] = A(rad(52 * k * sin(ap)), rad(s * 16 * k * cos(ap)), rad(s * (14 + 10 * k * cos(ap))))
		-- The wrist cancels most of the arm swing so the paw stays level, then flicks dirt as it lifts.
		pose["Wrist" .. side] = A(rad(-0.9 * 52 * k * sin(ap) + 14 * k * math.max(0, sin(ap + 0.9))), 0, 0)
		pose["Hip" .. side] = A(rad(24 * k * sin(lp)), 0, 0)
	end
	return pose
end

local function stunned(t: number): Pose
	local pose: Pose = {
		Spine = P(0, 0.2, 0) * A(rad(4 * sin(t * 3)), rad(10 * sin(t * 5)), rad(9 * sin(t * 6))),
		Neck = A(rad(-12), 0, rad(16 * sin(t * 7))),
		HelmetJ = P(0.3, -0.2, -0.3) * A(rad(12), 0, rad(18)),
		Nose = A(0, 0, rad(30 * sin(t * 4))),
		HaloJ = A(0, t * 4.5, 0),
		TailJ = A(rad(-25), 0, 0),
	}
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		pose["Shoulder" .. side] = A(rad(12 * sin(t * 4 + s)), 0, rad(s * (24 + 8 * sin(t * 5))))
		pose["Wrist" .. side] = A(rad(30), 0, 0)
		pose["Hip" .. side] = A(rad(8), 0, 0)
	end
	return pose
end

local function lerpPose(a: Pose, b: Pose, alpha: number): Pose
	local out: Pose = {}
	for _, name in GiantMole.JOINTS do
		out[name] = a[name]:Lerp(b[name], alpha)
	end
	return out
end

-- The pose for `state` at time `t` (seconds), `age` seconds after entering it. `phase` is the stride
-- phase (grows with distance walked). `swipeAge` is the time since the last catch swipe, if recent.
function GiantMole.pose(state: string, t: number, age: number, phase: number, swipeAge: number?): Pose
	local pose: Pose
	if state == "Sleeping" then
		-- Settle back down over 0.8 s if it was awake a moment ago.
		pose = if age < 0.8 then lerpPose(alert(t), sleeping(t), clamp(age / 0.8, 0, 1)) else sleeping(t)
	elseif state == "Waking" then
		-- Pops up with a springy overshoot.
		local k = 1 - exp(-7 * age) * cos(13 * age)
		pose = lerpPose(sleeping(t), alert(t), clamp(k, 0, 1.15))
	elseif state == "Chasing" then
		local chase = gallop(t, phase, 1, false)
		pose = if age < 0.35 then lerpPose(alert(t), chase, age / 0.35) else chase
	elseif state == "Returning" then
		pose = gallop(t, phase, 0.5, true)
	elseif state == "Stunned" then
		pose = stunned(t)
	else
		pose = alert(t)
	end
	if swipeAge and swipeAge >= 0 and swipeAge < 0.6 then
		-- A big overhead swipe with the right paw.
		local w = sin(swipeAge / 0.6 * pi)
		pose.ShoulderR = pose.ShoulderR:Lerp(A(rad(135), rad(-25), rad(30)), w)
		pose.WristR = pose.WristR:Lerp(A(rad(-45), 0, 0), w)
		pose.Spine = pose.Spine * A(0, rad(-16 * w), rad(-6 * w))
	end
	return pose
end

-- The local look per state: eye shape and colour, headlamp, stun stars, dirt.
export type Look = { eyeY: number, eyeColor: Color3, eyeNeon: boolean, lamp: boolean, stars: boolean, dirtPerSpeed: number, zzz: boolean }
function GiantMole.look(state: string): Look
	local awake = state ~= "Sleeping"
	return {
		eyeY = if awake then 1.05 else 0.16,
		eyeColor = if state == "Chasing" then Color3.fromRGB(255, 50, 40) else Color3.fromRGB(22, 18, 24),
		eyeNeon = state == "Chasing",
		lamp = awake and state ~= "Stunned",
		stars = state == "Stunned",
		dirtPerSpeed = if state == "Chasing" then 2.2 elseif state == "Returning" then 1 else 0,
		zzz = not awake,
	}
end

GiantMole.STRIDE = 10 -- studs per full stride cycle

return GiantMole
