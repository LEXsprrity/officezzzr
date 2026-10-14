--!strict
-- The zone guardians are the owner's bought rigged pets (models/bosses/Pets.rbxl, exported to
-- assets/Guard_<Name>.rbxm by tools/export_bosses.luau): skinned MeshParts deformed by Bones. They carry
-- no Roblox animations: every client poses the Bones by code (GuardAnimator.client) from the guard's
-- "State" attribute with this module, which is pure math, so the Lune tests run the exact same poses.
--
-- Space: "model space" is the frame of the pet's bone host (its RootPart): on the ground under the pet,
-- front = -Z, right = +X, up = +Y. Profiles are written in the source file's studs; a rig built from an
-- exported (scaled) model knows its scale and multiplies every offset by it.
--
-- A pose maps bone names to a CFrame in model axes: its rotation turns the bone (and everything below
-- it) about the bone's own pivot, its position moves it. solve() turns that into each Bone.Transform.
-- The kits' feet and hands are IK targets parented to the root, not to the legs, so they are
-- "followers": glued to the end of their leg as it swings, and (feet) never pushed below the ground.
local BossRigs = {}

local sin, cos, abs, max, min, exp, pi = math.sin, math.cos, math.abs, math.max, math.min, math.exp, math.pi

export type Leg = {
	hip: string, -- the bone that swings the whole leg (or arm)
	knee: string?, -- bends to lift the foot
	foot: string?, -- the kit's IK-target bone carrying the foot: follows the end of the leg
	tip: string?, -- the leg's last bone, which the foot follows (default: knee, else hip)
	side: number, -- -1 left (-X), 1 right (+X)
	front: boolean,
	splay: boolean?, -- sideways legs (the mole's paddles): swing about Y instead of X
}

export type Wing = { bones: { string }, side: number }

-- How it lies asleep (angles in radians, distances in source studs). Legs: `hip`/`knee` swing the front
-- and rear legs (positive: the foot goes forward; a splayed leg turns about Y instead), `tuck` rolls them
-- in under the body.
export type Lie = {
	drop: number, -- the body sinks this much (onto its belly)
	tilt: number?, -- the body pitches (positive: front down; the gorilla lies on its front)
	neck: { number }?, -- pitch of each neck bone (positive: tips forward and down)
	pull: Vector3?, -- the first neck bone moves (the turtle pulls its head into the shell)
	head: number?, -- the head's pitch (positive: nose down)
	headDrop: number?, -- the head moves down
	turn: number?, -- the head turns aside (positive: to its left)
	hip: { front: number, rear: number }?,
	knee: { front: number, rear: number }?,
	tuck: number?,
	curl: number?, -- the tail curls round to its left (spread along it)
	spine: { number }?, -- snake: yaw of each body bone on the ground (the coil)
}

export type Profile = {
	pet: string, -- the Model's name in Pets.rbxl (Workspace.PetTemplates)
	kind: "quad" | "ape" | "snake" | "shark" | "dragon",
	scale: number, -- export scale (source studs -> game studs)
	drop: number?, -- the export lowers the pet this much (source studs): the shark floats in the kit
	stride: number, -- source studs per stride cycle (or per swim/slither wave)
	body: string, -- the bone that carries the torso
	head: string,
	neck: { string }?,
	jaw: string?,
	tail: { string }?,
	spine: { string }?, -- snake: the body on the ground, from the neck back to the tail root
	legs: { Leg }?,
	wings: { Wing }?,
	fins: { Wing }?,
	twitch: { string }?, -- ears / whiskers / tongue that flick now and then
	gait: "trot" | "gallop" | "biped",
	swing: number, -- leg swing at full speed (radians)
	bend: number, -- knee bend while a foot is lifted (radians)
	bob: number, -- body bounce while running (source studs)
	hop: number, -- the wake-up hop (source studs)
	lunge: number, -- the catch lunge (source studs)
	bite: number?, -- the head's dip in the catch (radians, default 0.3; negative rears up)
	wobble: number?, -- the head's dizzy wobble when stunned (radians, default 0.3)
	lie: Lie, -- asleep
	eyes: { string }, -- the eyeball MeshParts (not the lids), hidden asleep: eyes closed
	rest: { [string]: CFrame }?, -- a fixed pose under everything (the gorilla's T-pose arms come down)
	halfWidth: number?, -- half its width as posed, when the rest bounds say otherwise (source studs)
}

local function pitch(a: number): CFrame -- positive: the front tips down, the back up, the top forward
	return CFrame.Angles(-a, 0, 0)
end
local function swing(a: number): CFrame -- positive: a hanging leg's foot goes forward
	return CFrame.Angles(a, 0, 0)
end
local function yaw(a: number): CFrame -- positive: the front turns left (-X)
	return CFrame.Angles(0, a, 0)
end
local function roll(a: number): CFrame -- positive: the right (+X) side goes up
	return CFrame.Angles(0, 0, a)
end
local function move(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

----------------------------------------------------------------------------------------------------
-- The seven bosses, by the pet's name. Bone names are the kit's own (checked by tests/bosses.spec).
----------------------------------------------------------------------------------------------------
local function leg(hip: string, knee: string?, foot: string?, side: number, front: boolean, extra: { [string]: any }?): Leg
	local l: any = { hip = hip, knee = knee, foot = foot, side = side, front = front }
	for k, v in extra or {} do
		l[k] = v
	end
	return l
end

BossRigs.PROFILES = {
	-- Meadow: a sea-green turtle with a yellow shell. Waddles on four stumpy legs; sleeps tucked in.
	Turtle = {
		pet = "Turtle", kind = "quad", scale = 4.6, stride = 2.4, gait = "trot",
		body = "Root.M.002", neck = { "Root.M.011", "Root.M.012", "Root.M.013" }, head = "Root.M.014", jaw = "Root.M.029",
		tail = { "Root.M.004", "Root.M.005", "Root.M.006" },
		legs = {
			leg("Leg.L.003", "Leg.L.007", "Leg.L.001-IKTarget.001", -1, true),
			leg("Leg.R.003", "Leg.R.007", "Leg.R.001-IKTarget.001", 1, true),
			leg("Leg.L", "Leg.L.001", "Leg.L.001-IKTarget", -1, false),
			leg("Leg.R", "Leg.R.001", "Leg.R.001-IKTarget", 1, false),
		},
		swing = 0.75, bend = 0.8, bob = 0.1, hop = 0.35, lunge = 0.7,
		lie = {
			drop = 0.12, pull = Vector3.new(0, -0.1, 0.5), neck = { 0.55, 0.25, -0.2 }, head = 0.35, curl = 0.5,
			hip = { front = -0.35, rear = 0.35 }, knee = { front = 0.6, rear = -0.6 }, tuck = 0.45,
		},
		eyes = { "Icosphere.009", "Icosphere.022", "Icosphere.023", "Icosphere.024", "Icosphere.025", "Icosphere.026" },
	},
	-- Desert: a red mole with splayed digging paws and whiskers.
	RedMole = {
		pet = "RedMole", kind = "quad", scale = 5.2, stride = 2.6, gait = "trot",
		body = "Root.M.002", head = "Root.M.007", tail = { "Root.M.004", "Root.M.005" },
		twitch = { "Root.L", "Root.L.003", "Root.L.006", "Root.R", "Root.R.003", "Root.R.006" },
		legs = {
			leg("Leg.L.003", "Leg.L.007", "Leg.L.001-IKTarget.001", -1, true, { splay = true }),
			leg("Leg.R.003", "Leg.R.007", "Leg.R.001-IKTarget.001", 1, true, { splay = true }),
			leg("Leg.L", "Leg.L.001", "Leg.L.001-IKTarget", -1, false, { splay = true }),
			leg("Leg.R", "Leg.R.001", "Leg.R.001-IKTarget", 1, false, { splay = true }),
		},
		swing = 0.65, bend = 0.6, bob = 0.1, hop = 0.35, lunge = 0.8, bite = -0.15, wobble = 0.1,
		lie = { drop = 0.08, head = 0.05, headDrop = 0.04, hip = { front = 0.3, rear = -0.3 }, tuck = 0.15, curl = 0.4 },
		eyes = { "Plane.019", "Plane.020" },
	},
	-- Jungle: a snake reared up like a cobra, its tail along the ground. Slithers; strikes.
	GiantSnake = {
		pet = "GiantSnake", kind = "snake", scale = 2.0, stride = 7, gait = "biped",
		body = "Root.M.002", spine = { "Root.M.010", "Root.M.031", "Root.M.020" },
		neck = { "Root.M.011", "Root.M.012", "Root.M.013", "Root.M.014", "Root.M.015", "Root.M.016", "Root.M.017", "Root.M.018" },
		head = "Root.M.019", jaw = "Root.M.021", twitch = { "Root.M.022" },
		tail = { "Root.M.004", "Root.M.033", "Root.M.032", "Root.M.005", "Root.M.006", "Root.M.007", "Root.M.008", "Root.M.009" },
		swing = 0.3, bend = 0, bob = 0, hop = 0.12, lunge = 1.6,
		lie = { drop = 0, neck = { 0.8, 0.45, 0.2, -0.1, -0.3, -0.3, -0.3, -0.25 }, head = -0.3, spine = { 0.5, -0.6, 0.6 }, curl = 1.4 },
		eyes = { "Plane.027", "Plane.028" },
	},
	-- Lava Fields: a lava gorilla. The kit holds it in a T-pose, so its arms come down (rest); it
	-- knuckle-gallops, beats its chest awake and smashes down on a catch.
	GorillaVulcano = {
		pet = "GorillaVulcano", kind = "ape", scale = 2.4, stride = 3.6, gait = "gallop",
		body = "Root.M.002", neck = { "Root.M.025", "Root.M.003" }, head = "Root.M.013", jaw = "Root.M.015",
		legs = {
			leg("Root.L", "Root.L.001", "Root.L.001-IKTarget", -1, true),
			leg("Root.R", "Root.R.001", "Root.R.001-IKTarget", 1, true),
			leg("Root.L.003", "Root.L.016", "Root.L.016-IKTarget", -1, false),
			leg("Root.R.003", "Root.R.016", "Root.R.016-IKTarget", 1, false),
		},
		rest = {
			["Root.L"] = roll(1.05) * swing(0.2),
			["Root.R"] = roll(-1.05) * swing(0.2),
			["Root.L.001"] = swing(0.5),
			["Root.R.001"] = swing(0.5),
			["Root.L.001-IKTarget"] = swing(1.2), -- knuckles down, fingers forward
			["Root.R.001-IKTarget"] = swing(1.2),
		},
		swing = 0.7, bend = 0.7, bob = 0.15, hop = 0.45, lunge = 0.9,
		lie = { drop = 0, tilt = 1.4, neck = { -0.1, -0.2 }, head = -0.7, hip = { front = 2.5, rear = 0.6 }, knee = { front = 0.3, rear = 0 } },
		eyes = { "eye2", "eye3", "eye4", "Body.014" },
		halfWidth = 5.6, -- with its arms down (its rest bounds are the T-pose)
	},
	-- Snow Peaks: an ice shark gliding just over the snow: tail sweeps, fins paddle, jaws snap.
	IceShark = {
		pet = "IceShark", kind = "shark", scale = 4.1, drop = 0.62, stride = 3.4, gait = "biped",
		body = "Body.M", head = "Body.M.023", jaw = "Body.M.024",
		tail = { "Body.M.001", "Body.M.002", "Body.M.003", "Body.M.007" },
		fins = { { bones = { "Body.L" }, side = -1 }, { bones = { "Body.R" }, side = 1 } },
		twitch = { "Body.M.011" },
		swing = 0.4, bend = 0, bob = 0.1, hop = 0.4, lunge = 0.9,
		lie = { drop = 0.75, head = 0.08, curl = 0.6 },
		eyes = { "Ice Shark Eye Neon", "Ice Shark Body.036", "Ice Shark Body.037", "Ice Shark Body.038" },
	},
	-- Deep Space: a two-legged void dragon with big wings: flaps as it runs, folds them asleep.
	VoidDragon = {
		pet = "VoidDragon", kind = "dragon", scale = 1.85, stride = 3.4, gait = "biped",
		body = "Root.M.016", neck = { "Root.M.017", "Root.M.018", "Root.M.019" }, head = "Root.M.020", jaw = "Root.M.022",
		tail = { "Root.M.021", "Root.M.023", "Root.M.024", "Root.M.025", "Root.M.026", "Root.M.027", "Root.M.028", "Root.M.029" },
		wings = {
			{ bones = { "Root.L.004", "Root.L" }, side = -1 },
			{ bones = { "Root.R.004", "Root.R" }, side = 1 },
		},
		legs = {
			leg("Root.L.003", "Root.L.007", "Root.L.016-IKTarget", -1, false, { tip = "Root.L.016" }),
			leg("Root.R.003", "Root.R.007", "Root.R.016-IKTarget", 1, false, { tip = "Root.R.016" }),
		},
		swing = 0.7, bend = 0.8, bob = 0.15, hop = 0.5, lunge = 0.9,
		lie = { drop = 1.5, neck = { 0.9, 0.9, 0.5 }, head = -0.3, hip = { front = 0.5, rear = 0.5 }, knee = { front = -0.9, rear = -0.9 }, curl = 1.2 },
		eyes = { "DragonPurple.009", "DragonPurple.012", "DragonPurple.013", "DragonPurple.014", "DragonPurple.015" },
	},
	-- Spirit Garden: a glowing stag with antlers. Gallops in bounds, lies down to sleep, rams on a catch.
	Lumistag = {
		pet = "Lumistag", kind = "quad", scale = 1.8, stride = 5.5, gait = "gallop",
		body = "Root.M.002", head = "Root.M.008", tail = { "Root.M.006" },
		twitch = { "Root.L.001", "Root.L.002", "Root.R.001", "Root.R.002" },
		legs = {
			leg("Leg.L.003", "Leg.L.007", "Leg.L.001-IKTarget.001", -1, true),
			leg("Leg.R.003", "Leg.R.007", "Leg.R.001-IKTarget.001", 1, true),
			leg("Leg.L", "Leg.L.001", "Leg.L.001-IKTarget", -1, false),
			leg("Leg.R", "Leg.R.001", "Leg.R.001-IKTarget", 1, false),
		},
		swing = 0.7, bend = 1.0, bob = 0.3, hop = 0.6, lunge = 1.2,
		lie = { drop = 1.9, head = 0.5, headDrop = 0.6, turn = 0.5, hip = { front = -1.3, rear = 1.8 }, knee = { front = 2.4, rear = -2.6 } },
		eyes = { "PalpBottom.012", "PalpBottom.013", "PalpBottom.014", "PalpBottom.017" },
	},
} :: { [string]: Profile }

-- Which pet guards which zone (Config.ZONES ids).
BossRigs.BY_ZONE = {
	Meadow = "Turtle", Desert = "RedMole", Jungle = "GiantSnake", Lava = "GorillaVulcano",
	Snow = "IceShark", Space = "VoidDragon", Spirit = "Lumistag",
} :: { [string]: string }

BossRigs.CATCH_TIME = 0.6 -- seconds of the catch lunge / bite
BossRigs.WAKE_TIME = 0.6 -- seconds of the wake-up hop (it carries on into the chase)
BossRigs.BLEND_TIME = 0.25 -- cross-fade between two states' poses

----------------------------------------------------------------------------------------------------
-- Poses
----------------------------------------------------------------------------------------------------
export type Pose = { [string]: CFrame }

export type Input = {
	state: string, -- the guard's State attribute: Sleeping, Waking, Chasing, Returning, Stunned
	t: number, -- clock (seconds)
	age: number, -- seconds in this state
	phase: number, -- stride phase (radians), advanced by ground speed
	move: number, -- 0 standing still .. 1 running flat out
	woke: number?, -- seconds since it woke (the alert hop), nil once over
	catch: number?, -- seconds since its last catch, nil once over
}

-- Adds `cf` on top of what the bone already has (its rotation applied after, in model axes).
local function add(pose: Pose, bone: string?, cf: CFrame)
	if not bone then
		return
	end
	local e = pose[bone]
	if e then
		pose[bone] = CFrame.new(e.Position + cf.Position) * cf.Rotation * e.Rotation
	else
		pose[bone] = cf
	end
end

local function each(pose: Pose, bones: { string }?, cf: CFrame)
	for _, b in bones or {} do
		add(pose, b, cf)
	end
end

-- A wave down a chain: bone i turns by amp * sin(phase - lag * i), growing toward the end.
local function wave(pose: Pose, bones: { string }?, phase: number, amp: number, lag: number, grow: number, around: (number) -> CFrame)
	for i, b in bones or {} do
		add(pose, b, around(amp * (1 + grow * (i - 1)) * sin(phase - lag * (i - 1))))
	end
end

-- Legs in a gait: each leg swings about the hip, and the knee lifts the foot on the way forward.
local function gaitOffset(p: Profile, l: Leg): number
	if p.gait == "trot" then
		return if l.front == (l.side < 0) then 0 else pi
	elseif p.gait == "gallop" then
		return (if l.front then 0 else pi) + (if l.side > 0 then 0.35 else 0)
	end
	return if l.side < 0 then 0 else pi -- biped
end

local function legs(pose: Pose, p: Profile, phase: number, amp: number)
	for _, l in p.legs or {} do
		local ph = phase + gaitOffset(p, l)
		local a = p.swing * amp * sin(ph)
		local lift = p.bend * amp * max(0, cos(ph))
		if l.splay then
			add(pose, l.hip, yaw(l.side * a) * roll(l.side * lift * 0.6))
		else
			add(pose, l.hip, swing(a))
			add(pose, l.knee, swing(if l.front then -lift else lift))
		end
	end
end

local function sides(pose: Pose, list: { Wing }?, f: (side: number) -> CFrame)
	for _, w in list or {} do
		each(pose, w.bones, f(w.side))
	end
end

-- Asleep: lying down (the profile's `lie`), breathing slowly. The eyes close too (GuardAnimator hides the
-- profile's eye meshes).
BossRigs.BREATH = 1.6 -- radians per second: a breath every ~4 s
local function sleep(pose: Pose, p: Profile, t: number)
	local lie = p.lie
	local breathe = sin(t * BossRigs.BREATH)
	add(pose, p.body, move(0, -lie.drop + 0.025 * breathe, 0) * pitch((lie.tilt or 0) + 0.015 * breathe))
	if lie.pull then
		add(pose, p.neck and p.neck[1], CFrame.new(lie.pull))
	end
	for i, b in p.neck or {} do
		add(pose, b, pitch(((lie.neck or {})[i] or 0) * (1 + 0.03 * breathe)))
	end
	add(pose, p.head, move(0, -(lie.headDrop or 0), 0) * yaw(lie.turn or 0) * pitch((lie.head or 0) + 0.02 * breathe))
	add(pose, p.jaw, pitch(0.02 + 0.02 * breathe))
	for _, l in p.legs or {} do
		local hip = if lie.hip then (if l.front then lie.hip.front else lie.hip.rear) else 0
		local knee = if lie.knee then (if l.front then lie.knee.front else lie.knee.rear) else 0
		if l.splay then
			add(pose, l.hip, yaw(l.side * hip) * roll(-l.side * (lie.tuck or 0)))
		else
			add(pose, l.hip, roll(-l.side * (lie.tuck or 0)) * swing(hip))
			add(pose, l.knee, swing(knee))
		end
	end
	-- the tail curls round to one side, swaying a little with each breath
	local tail = p.tail or {}
	for _, b in tail do
		add(pose, b, yaw((lie.curl or 0) / max(#tail, 1) + 0.03 * sin(t * 0.5)))
	end
	for i, b in p.spine or {} do
		add(pose, b, yaw((lie.spine or {})[i] or 0))
	end
	-- wings folded back along the body; fins flat on the ground
	sides(pose, p.wings, function(side)
		return yaw(-side * 0.75) * roll(-side * 0.55)
	end)
	sides(pose, p.fins, function(side)
		return roll(-side * (0.35 + 0.03 * breathe))
	end)
	for i, b in p.twitch or {} do
		local k = sin(t * (1.3 + 0.4 * i) + i)
		add(pose, b, yaw(0.06 * k * k * k)) -- a lazy twitch now and then
	end
end

-- Awake: the gait (scaled by `amp`), and the idle sway when standing.
local function awake(pose: Pose, p: Profile, s: Input, amp: number)
	local phase, t = s.phase, s.t
	local still = 1 - amp
	local kind = p.kind
	add(pose, p.head, yaw(0.25 * still * sin(t * 0.9)) * pitch(0.03 * sin(t * 2.4)))
	add(pose, p.body, move(0, 0.02 * sin(t * 2.4), 0))
	if kind == "quad" or kind == "ape" then
		legs(pose, p, phase, amp)
		if p.gait == "gallop" then
			add(pose, p.body, move(0, p.bob * amp * (0.5 - 0.5 * cos(2 * phase)), 0) * pitch(0.12 * amp * sin(phase)))
			add(pose, p.head, pitch(-0.12 * amp * sin(phase)))
		else
			add(pose, p.body, move(0, p.bob * amp * abs(sin(phase)), 0) * roll(0.05 * amp * sin(phase)))
			add(pose, p.head, pitch(0.06 * amp * sin(2 * phase)))
		end
		if kind == "ape" then
			add(pose, p.body, pitch(0.3 * amp)) -- leans into the knuckle run
			add(pose, p.head, pitch(-0.3 * amp))
		end
		wave(pose, p.tail, phase, 0.18 * amp + 0.06 * still, 0.7, 0.3, yaw)
	elseif kind == "snake" then
		local ph = if amp > 0.05 then phase else t * 1.2
		local a = p.swing * max(amp, 0.25)
		wave(pose, p.spine, ph, a, 0.9, 0, yaw)
		wave(pose, p.tail, ph - 2.7, a, 0.9, 0.15, yaw)
		-- the reared neck leans in and sways; the head keeps looking ahead
		each(pose, p.neck, pitch(0.04 * amp))
		wave(pose, p.neck, ph + 0.6, 0.03, 0.4, 0, roll)
		add(pose, p.head, yaw(-a * 1.2 * sin(ph - 0.9)))
	elseif kind == "shark" then
		local ph = if amp > 0.05 then phase else t * 1.6
		local a = 0.4 + 0.6 * amp
		add(pose, p.body, move(0, 0.12 * sin(t * 2.1) + p.bob * amp * sin(2 * ph), 0) * yaw(0.06 * a * sin(ph)))
		add(pose, p.head, yaw(-0.06 * a * sin(ph)))
		wave(pose, p.tail, ph - 0.8, p.swing * a, 0.8, 0.3, yaw)
		sides(pose, p.fins, function(side)
			return roll(side * (0.1 + 0.18 * a * sin(ph + 1)))
		end)
	elseif kind == "dragon" then
		legs(pose, p, phase, amp)
		add(pose, p.body, move(0, p.bob * amp * abs(sin(phase)), 0) * pitch(0.22 * amp))
		each(pose, p.neck, pitch(-0.07 * amp))
		local flapRate = 5 + 5 * amp
		local flap = sin(t * flapRate)
		sides(pose, p.wings, function(side)
			return roll(side * ((0.2 + 0.6 * amp) * flap + 0.1))
		end)
		wave(pose, p.tail, phase, 0.12 * amp + 0.05 * still, 0.6, 0.2, yaw)
	end
	for i, b in p.twitch or {} do
		local k = sin(t * (7 + i) + i * 1.7)
		add(pose, b, yaw(0.12 * k * k * k))
	end
end

-- The wake-up: one hop, head flung up, mouth open, tail up. Decays into whatever comes next.
local function alert(pose: Pose, p: Profile, w: number)
	local hop = if w < 0.4 then sin(pi * w / 0.4) else 0
	local fade = exp(-w * 4)
	add(pose, p.body, move(0, p.hop * hop, 0) * pitch(-0.12 * hop))
	add(pose, p.head, pitch(-0.4 * fade))
	add(pose, p.jaw, pitch(0.45 * fade))
	if p.tail then
		each(pose, p.tail, pitch(0.6 * fade / #p.tail)) -- the whole tail comes up by ~0.6 rad
	end
	if p.kind == "ape" then
		-- chest beat: the arms come up in front, one after the other
		for _, l in p.legs or {} do
			if l.front then
				add(pose, l.hip, swing(1.3 * fade * (0.6 + 0.4 * sin(w * 30 + (if l.side < 0 then 0 else pi)))))
			end
		end
	elseif p.kind == "dragon" then
		sides(pose, p.wings, function(side)
			return roll(side * 0.7 * fade)
		end)
	elseif p.kind == "snake" then
		each(pose, p.neck, pitch(-0.08 * fade))
	end
end

-- The catch: a lunge with a bite (snake: a strike; gorilla: a two-fisted smash; stag: an antler ram).
local function catch(pose: Pose, p: Profile, c: number)
	local k = min(c / BossRigs.CATCH_TIME, 1)
	local s = sin(pi * k)
	local open = if k < 0.45 then sin(pi * k / 0.45) else 0
	local bite = p.bite or 0.3
	add(pose, p.body, move(0, 0.15 * p.hop * s, -p.lunge * s) * pitch(0.4 * bite * s))
	add(pose, p.jaw, pitch(0.7 * open))
	if p.kind == "snake" then
		each(pose, p.neck, pitch(0.09 * s))
		add(pose, p.head, pitch(-0.3 * s))
	elseif p.kind == "ape" then
		local up = if k < 0.5 then sin(pi * k / 0.5) else 0
		local down = if k >= 0.5 then sin(pi * (k - 0.5) / 0.5) else 0
		for _, l in p.legs or {} do
			if l.front then
				add(pose, l.hip, swing(2.4 * up + 0.8 * down))
			end
		end
		add(pose, p.body, pitch(-0.2 * up + 0.3 * down))
	elseif p.pet == "Lumistag" then
		add(pose, p.head, pitch(0.7 * s))
	elseif p.kind == "dragon" then
		sides(pose, p.wings, function(side)
			return roll(side * 0.6 * s)
		end)
		add(pose, p.head, pitch(0.25 * s))
	else
		add(pose, p.head, pitch(bite * s))
	end
end

-- Stunned by a bat: dizzy wobble.
local function dizzy(pose: Pose, p: Profile, t: number)
	add(pose, p.body, roll(0.12 * sin(t * 6)) * pitch(0.05 * sin(t * 3)))
	local w = p.wobble or 0.3
	add(pose, p.head, roll(w * sin(t * 4)) * yaw(w * cos(t * 4)))
	add(pose, p.jaw, pitch(0.25))
end

function BossRigs.pose(p: Profile, s: Input): Pose
	local pose: Pose = {}
	for bone, cf in p.rest or {} do
		pose[bone] = cf
	end
	if s.state == "Sleeping" then
		sleep(pose, p, s.t)
	else
		local amp = math.clamp(s.move, 0, 1)
		if s.state == "Returning" then
			amp *= 0.75
			add(pose, p.head, pitch(0.12)) -- grumpy walk home
		end
		awake(pose, p, s, amp)
		if s.state == "Stunned" then
			dizzy(pose, p, s.t)
		end
		if s.woke and s.woke < BossRigs.WAKE_TIME then
			alert(pose, p, s.woke)
		end
	end
	if s.catch and s.catch < BossRigs.CATCH_TIME then
		catch(pose, p, s.catch)
	end
	return pose
end

-- The pose `w` of the way from a to b (a bone missing from one side counts as unmoved).
function BossRigs.blend(a: Pose, b: Pose, w: number): Pose
	local out: Pose = {}
	for bone, cf in a do
		out[bone] = cf:Lerp(b[bone] or CFrame.identity, w)
	end
	for bone, cf in b do
		if not a[bone] then
			out[bone] = CFrame.identity:Lerp(cf, w)
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Rig: the bones of one pet, and solving a pose into Bone.Transform
----------------------------------------------------------------------------------------------------
export type Joint = {
	name: string,
	bone: any, -- the Bone instance
	parent: Joint?, -- nil: hangs straight off the host part
	local0: CFrame, -- Bone.CFrame
	rest: CFrame, -- rest CFrame in model space
	turn: CFrame, -- rest rotation
	follow: Joint?, -- a foot/hand glued to the end of this bone
	plant: boolean, -- a foot: flat, and never below its rest height
	under: { Joint }?, -- a follower's bones (toes, fingers): kept above the ground with it
	floor: number?, -- ...at this height (model space)
}

export type Rig = {
	profile: Profile,
	scale: number,
	joints: { Joint }, -- parents before children, followers' subtrees last
	byName: { [string]: Joint },
	followers: { Joint },
	tops: { Joint }, -- bones straight under the host that are not followers (the wall shift moves them)
}

-- Reads the Bones under `host` (the pet's RootPart). `scale` is the export scale (the model's RigScale).
function BossRigs.rig(host: any, profile: Profile, scale: number): Rig
	local rig: Rig = { profile = profile, scale = scale, joints = {}, byName = {}, followers = {}, tops = {} }
	local followOf: { [string]: string } = {}
	for _, l in profile.legs or {} do
		if l.foot then
			followOf[l.foot] = l.tip or l.knee or l.hip
		end
	end
	local later: { Joint } = {}
	local function walk(inst: any, parent: Joint?, rest: CFrame, under: boolean)
		for _, child in inst:GetChildren() do
			if child:IsA("Bone") then
				local cf = rest * child.CFrame
				local j: Joint = {
					name = child.Name, bone = child, parent = parent, local0 = child.CFrame, rest = cf,
					turn = cf.Rotation, follow = nil, plant = false,
				}
				rig.byName[child.Name] = j
				local isFollower = followOf[child.Name] ~= nil
				local deferred = under or isFollower
				table.insert(if deferred then later else rig.joints, j)
				if parent == nil and not isFollower then
					table.insert(rig.tops, j)
				end
				walk(child, j, cf, deferred)
			end
		end
	end
	walk(host, nil, CFrame.identity, false)
	for _, j in later do
		table.insert(rig.joints, j)
	end
	for foot, leader in followOf do
		local f, l = rig.byName[foot], rig.byName[leader]
		if f and l then
			f.follow = l
			f.plant = f.rest.Position.Y < 0.6 * scale -- a foot on the ground (the gorilla's hands are not)
			local under, floor = {}, math.min(0, f.rest.Position.Y)
			local function collect(j: Joint)
				for _, other in rig.joints do
					if other.parent == j then
						table.insert(under, other)
						floor = math.min(floor, other.rest.Position.Y)
						collect(other)
					end
				end
			end
			collect(f)
			f.under, f.floor = under, floor
			table.insert(rig.followers, f)
		end
	end
	return rig
end

-- Every bone's Transform for `pose` (identity for the bones it leaves alone), and every bone's posed
-- CFrame in model space. `shift` (game studs, model axes) moves the whole body (the wall nudge).
function BossRigs.solve(rig: Rig, pose: Pose, shift: Vector3?): ({ [Joint]: CFrame }, { [Joint]: CFrame })
	local out: { [Joint]: CFrame } = {}
	local world: { [Joint]: CFrame } = {}
	local s = rig.scale
	local tops: { [Joint]: boolean } = {}
	if shift and shift.Magnitude > 1e-4 then
		for _, j in rig.tops do
			tops[j] = true
		end
	end
	for _, j in rig.joints do
		local parentWorld = if j.parent then world[j.parent] else CFrame.identity
		local base = parentWorld * j.local0
		local d = pose[j.name]
		local follow = j.follow
		local target: CFrame
		if follow then
			-- glued to its leader's end, then lifted back to the ground if it went under
			target = world[follow] * follow.rest:Inverse() * j.rest
			if j.plant then
				-- a foot stays flat, and never sinks under the ground
				local at = target.Position
				target = CFrame.new(at.X, max(at.Y, j.rest.Position.Y), at.Z) * j.turn
			end
			if d then
				target = CFrame.new(target.Position + d.Position * s) * d.Rotation * target.Rotation
			end
		elseif d or tops[j] then
			-- the pose's rotation about the bone's pivot in model axes, on top of where its parent took it
			local offset = if d then d.Position * s else Vector3.zero
			if tops[j] then
				offset += shift :: Vector3
			end
			local turn = if d then d.Rotation else CFrame.identity
			local t = j.turn:Inverse() * CFrame.new(offset) * turn * j.turn
			target = base * t
		else
			target = base
		end
		world[j] = target
		out[j] = base:Inverse() * target
	end
	-- no hand, foot, finger or toe goes under the ground: lift the follower with all its bones
	for _, f in rig.followers do
		local low = world[f].Position.Y
		for _, j in f.under or {} do
			low = min(low, world[j].Position.Y)
		end
		local dy = (f.floor or 0) - low
		if dy > 1e-6 then
			local up = Vector3.new(0, dy, 0)
			world[f] += up
			out[f] = ((if f.parent then world[f.parent] else CFrame.identity) * f.local0):Inverse() * world[f]
			for _, j in f.under or {} do
				world[j] += up
			end
		end
	end
	return out, world
end

-- How far (game studs) to slide the body sideways so it stays inside the corridor's walls, for a guard
-- whose root is at `pos` facing `look`, with its body spanning lo..hi (game studs, model axes) around it.
-- Purely visual: the server's guard (and the catch) stay where they are.
function BossRigs.wallShift(pos: Vector3, look: Vector3, lo: Vector3, hi: Vector3, halfWidth: number): Vector3
	local f = Vector3.new(look.X, 0, look.Z)
	if f.Magnitude < 1e-3 then
		return Vector3.zero
	end
	f = f.Unit
	local r = Vector3.new(-f.Z, 0, f.X) -- model +X in world
	-- world Z reach of the body box: corners of x in lo.X..hi.X (along r) and z in lo.Z..hi.Z (along -f)
	local zMax, zMin = -math.huge, math.huge
	for _, x in { lo.X, hi.X } do
		for _, z in { lo.Z, hi.Z } do
			local wz = pos.Z + r.Z * x - f.Z * z
			zMax, zMin = max(zMax, wz), min(zMin, wz)
		end
	end
	local push = 0
	if zMax > halfWidth then
		push = halfWidth - zMax
	elseif zMin < -halfWidth then
		push = -halfWidth - zMin
	end
	if push == 0 then
		return Vector3.zero
	end
	-- world +Z in model axes: x = r.Z, z = -f.Z
	return Vector3.new(r.Z * push, 0, -f.Z * push)
end

return BossRigs
