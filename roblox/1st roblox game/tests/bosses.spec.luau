-- The zone bosses: the owner's rigged pets (models/bosses/Pets.rbxl) exported into the Guard_<Name> slots
-- (tools/export_bosses.luau), and the code animation every client plays on them (BossRigs).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local Config = H.shared("Config")
local BossRigs = H.shared("BossRigs")
local Assets = H.server("Assets")

local PLAYER_HEIGHT = 5 -- studs, a default character
-- The bought kit (*.rbxl is gitignored, so a fresh checkout may not have it): checked when it is there.
local KIT = "models/bosses/Pets.rbxl"
local SOURCE = if fs.isFile(KIT) then roblox.deserializePlace(fs.readFile(KIT)) else nil

local function slotOf(zone: any): string
	return "Guard_" .. string.gsub(zone.guard, "%s", "")
end

-- Every bone name a profile uses.
local function bonesOf(p: any): { string }
	local out = {}
	local function add(name: string?)
		if name then
			table.insert(out, name)
		end
	end
	add(p.body)
	add(p.head)
	add(p.jaw)
	for _, list in { p.neck, p.tail, p.spine, p.twitch } do
		for _, b in list or {} do
			add(b)
		end
	end
	for _, l in p.legs or {} do
		add(l.hip)
		add(l.knee)
		add(l.foot)
		add(l.tip)
	end
	for _, list in { p.wings, p.fins } do
		for _, w in list or {} do
			for _, b in w.bones do
				add(b)
			end
		end
	end
	for b in p.rest or {} do
		add(b)
	end
	return out
end

local function boneCount(root: any): { [string]: number }
	local n = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Bone") then
			n[d.Name] = (n[d.Name] or 0) + 1
		end
	end
	return n
end

-- The exported model placed like GuardService does: its ground point at the origin, front -Z.
local function placed(zone: any): any
	local model = Assets.place(slotOf(zone), nil, CFrame.identity, Vector3.new(30, 23.25, 30))
	assert(model, `{slotOf(zone)} doesn't place`)
	return model
end

local function rigOf(zone: any): (any, any, any)
	local model = placed(zone)
	local profile = BossRigs.PROFILES[model:GetAttribute("BossRig")]
	return BossRigs.rig(model.PrimaryPart, profile, model:GetAttribute("RigScale")), profile, model
end

local function finite(cf: any): boolean
	for _, v in { cf:GetComponents() } do
		if v ~= v or math.abs(v) == math.huge then
			return false
		end
	end
	return true
end

H.test("bosses: each zone's guard slot holds its own rigged pet, with no scripts or animation leftovers", function()
	local pets = {}
	for _, zone in Config.ZONES do
		local key = BossRigs.BY_ZONE[zone.id]
		local profile = BossRigs.PROFILES[key]
		H.ok(profile and profile.pet == key, `{zone.id}: a profile for {key}`)
		H.ok(not pets[key], `{key} guards only one zone`)
		pets[key] = true
		local template = Assets.get(slotOf(zone))
		H.ok(template and template:IsA("Model"), `{zone.id}: assets/{slotOf(zone)}.rbxm`)
		H.eq(template:GetAttribute("BossRig"), key, `{slotOf(zone)} is the {key}`)
		H.eq(template:GetAttribute("RigScale"), profile.scale, `{slotOf(zone)} scale`)
		H.eq(template:GetAttribute("KeepScale"), true)
		H.eq(template:GetAttribute("Pivot"), Vector3.zero)
		H.ok(template.PrimaryPart and template.PrimaryPart.Name == "RootPart", "the bone host is its PrimaryPart")
		local meshes, bones = 0, 0
		for _, d in template:GetDescendants() do
			for _, banned in { "LuaSourceContainer", "AnimationController", "Animator", "KeyframeSequence", "Animation", "JointInstance", "Constraint", "WeldConstraint", "ValueBase" } do
				H.ok(not d:IsA(banned), `{slotOf(zone)}: {d:GetFullName()} ({d.ClassName}) left in`)
			end
			if d:IsA("MeshPart") then
				meshes += 1
				H.ok(d.HasSkinnedMesh, `{d.Name} is skinned`)
				H.ok(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, `{d.Name}: anchored decoration`)
			elseif d:IsA("Bone") then
				bones += 1
				H.ok(d.Parent == template.PrimaryPart or d.Parent:IsA("Bone"), `{d.Name} under the RootPart`)
			end
		end
		H.ok(meshes >= 10 and bones >= 20, `{key}: {meshes} meshes, {bones} bones`)
	end
	-- the source kit itself has no code
	for _, d in if SOURCE then SOURCE:GetDescendants() else {} do
		H.ok(not d:IsA("LuaSourceContainer"), `Pets.rbxl has a script: {d:GetFullName()}`)
	end
end)

H.test("bosses: the rig profiles name only bones that exist (in the kit and in the exported asset), each once", function()
	local folder = SOURCE and SOURCE.Workspace.PetTemplates
	for key, p in BossRigs.PROFILES do
		local inKit = if folder then boneCount(folder:FindFirstChild(key)) else nil
		local zone = nil
		for _, z in Config.ZONES do
			if BossRigs.BY_ZONE[z.id] == key then
				zone = z
			end
		end
		H.ok(zone, `{key} guards a zone`)
		local inAsset = boneCount(Assets.get(slotOf(zone)))
		for _, name in bonesOf(p) do
			if inKit then
				H.eq(inKit[name], 1, `{key}: bone {name} in the kit`)
			end
			H.eq(inAsset[name], 1, `{key}: bone {name} in the asset`)
		end
		local rig = BossRigs.rig(Assets.get(slotOf(zone)).PrimaryPart, p, p.scale)
		local feet = 0
		for _, l in p.legs or {} do
			if l.foot then
				feet += 1
			end
		end
		H.eq(#rig.followers, feet, `{key}: every foot follows its leg`)
		for _, f in rig.followers do
			H.ok(f.parent == nil or not f.parent.follow, `{f.name}: not under another follower`)
		end
	end
end)

H.test("bosses: 2-3.7x a player tall, taller in later zones, on the ground, inside the corridor", function()
	local last = 0
	for k, zone in Config.ZONES do
		local model = placed(zone)
		local lo, hi = Assets.bounds(model)
		local size = hi - lo
		H.ok(hi.Y >= 2 * PLAYER_HEIGHT and hi.Y <= 3.7 * PLAYER_HEIGHT, `{zone.id}: {hi.Y} studs tall`)
		H.ok(hi.Y >= last - 0.5, `{zone.id}: not smaller than the zone before ({hi.Y} < {last})`)
		last = hi.Y
		H.ok(lo.Y > -0.5 and lo.Y < 1.5, `{zone.id}: stands on the ground (bottom at {lo.Y})`)
		H.ok(size.X <= 36 and size.Z <= 40, `{zone.id}: {size.X} wide, {size.Z} long`)
		H.ok(size.X < Config.CORRIDOR_WIDTH / 4, `{zone.id}: a small part of the corridor's width`)
		-- the root's ground point is where it was placed (its Pivot), not the middle of its bounds
		local host = model.PrimaryPart
		local profile = BossRigs.PROFILES[model:GetAttribute("BossRig")]
		H.ok((host.CFrame.Position - Vector3.new(0, -(profile.drop or 0) * profile.scale, 0)).Magnitude < 1e-3, `{zone.id}: RootPart on the pivot`)
		if k == #Config.ZONES then
			-- the last boss sleeps facing the base with its back to the corridor's end wall
			local home = Config.nestX(k) + Config.GUARD_HOME_OFFSET
			H.ok(home + hi.Z < Config.END_X - 1, `{zone.id}: its back clears the end wall`)
		end
	end
end)

H.test("bosses: placed anywhere (Pivot), the pet's RootPart lands on the guard's feet facing its front", function()
	local zone = Config.ZONES[1]
	local at = CFrame.new(120, 3, -40) * CFrame.Angles(0, math.rad(90), 0)
	local model = Assets.place(slotOf(zone), nil, at, Vector3.new(30, 23.25, 30))
	local host = model.PrimaryPart
	H.ok((host.CFrame.Position - at.Position).Magnitude < 1e-3, "on the ground point")
	H.ok((host.CFrame.LookVector - at.LookVector).Magnitude < 1e-3, "facing the same way")
end)

local STATES = { "Sleeping", "Waking", "Chasing", "Returning", "Stunned" }

H.test("bosses: every state's pose is finite, keeps feet, hands and bodies above the ground, nothing flies off", function()
	for _, zone in Config.ZONES do
		local rig, profile, model = rigOf(zone)
		local lo, hi = Assets.bounds(model)
		local reach = (hi - lo).Magnitude
		local floorOf = {}
		for _, j in rig.joints do
			floorOf[j] = math.min(0, j.rest.Position.Y) - 0.06 * rig.scale
		end
		local moved = {}
		for _, state in STATES do
			for i = 0, 23 do
				local t = i * 0.137
				local input = {
					state = state, t = t, age = t, phase = i / 24 * 2 * math.pi, move = if state == "Chasing" or state == "Returning" then 1 else 0,
					woke = if state == "Waking" or state == "Chasing" then (i % 6) * 0.1 else nil,
					catch = if state == "Returning" then (i % 7) * 0.09 else nil,
				}
				local pose = BossRigs.pose(profile, input)
				local transforms, world = BossRigs.solve(rig, pose)
				for j, cf in transforms do
					H.ok(finite(cf), `{zone.id} {state}: {j.name} transform is not finite`)
					local at = world[j].Position
					H.ok(at.Y >= floorOf[j], `{zone.id} {state} t={t}: {j.name} under the ground ({at.Y})`)
					H.ok((at - j.rest.Position).Magnitude <= 0.6 * reach, `{zone.id} {state}: {j.name} flew off`)
					if (at - j.rest.Position).Magnitude > 0.05 * rig.scale then
						moved[state] = true
					end
				end
			end
			H.ok(moved[state], `{zone.id}: the {state} pose moves something`)
		end
		-- blending two states stays finite
		local a = BossRigs.pose(profile, { state = "Sleeping", t = 1, age = 1, phase = 0, move = 0 })
		local b = BossRigs.pose(profile, { state = "Chasing", t = 1, age = 1, phase = 1, move = 1, woke = 0.1 })
		for _, cf in BossRigs.solve(rig, BossRigs.blend(a, b, 0.4)) do
			H.ok(finite(cf), `{zone.id}: blended pose`)
		end
	end
end)

H.test("bosses: the gait really steps (legs swing back and forth, feet lift), snakes and sharks sway", function()
	for _, zone in Config.ZONES do
		local rig, profile = rigOf(zone)
		local function at(phase: number, name: string): any
			local _, world = BossRigs.solve(rig, BossRigs.pose(profile, { state = "Chasing", t = 0, age = 2, phase = phase, move = 1 }))
			return world[rig.byName[name]].Position
		end
		if profile.legs then
			local l = profile.legs[1]
			local probe = l.foot or l.knee or l.hip
			local a, b = at(math.pi / 2, probe), at(3 * math.pi / 2, probe)
			H.ok((a - b).Magnitude > 0.15 * rig.scale, `{zone.id}: {probe} moves through the stride`)
		else
			local tip = profile.tail[#profile.tail]
			local a, b = at(math.pi / 2, tip), at(3 * math.pi / 2, tip)
			H.ok(math.abs(a.X - b.X) > 0.15 * rig.scale, `{zone.id}: the tail sweeps side to side`)
		end
	end
end)

H.test("bosses: near a side wall the body slides inward to stay inside it (visual only)", function()
	local wall = Config.CORRIDOR_WIDTH / 2 - 1
	local lo, hi = Vector3.new(-14, 0, -12), Vector3.new(14, 15, 20)
	-- in the middle: nothing
	H.eq(BossRigs.wallShift(Vector3.new(500, 0, 0), Vector3.new(-1, 0, 0), lo, hi, wall), Vector3.zero)
	-- at the chase clamp, facing any way, the shifted body stays inside
	local clamp = Config.CORRIDOR_WIDTH / 2 - 6
	for _, z in { clamp, -clamp } do
		for deg = 0, 345, 15 do
			local look = Vector3.new(math.cos(math.rad(deg)), 0, math.sin(math.rad(deg)))
			local pos = Vector3.new(800, 0, z)
			local shift = BossRigs.wallShift(pos, look, lo, hi, wall)
			local f = look.Unit
			local r = Vector3.new(-f.Z, 0, f.X)
			for _, x in { lo.X, hi.X } do
				for _, zz in { lo.Z, hi.Z } do
					local worldZ = pos.Z + r.Z * (x + shift.X) - f.Z * (zz + shift.Z)
					H.ok(math.abs(worldZ) <= wall + 1e-3, `facing {deg}°: a corner at z={worldZ}`)
				end
			end
		end
	end
end)

H.test("bosses: the client animator poses only nearby bosses, from BossRigs; the old Giant Mole is gone", function()
	local animator = fs.readFile("src/client/GuardAnimator.client.luau")
	H.ok(string.find(animator, "local ANIMATE_RANGE = 150", 1, true) ~= nil, "animates within ~150 studs")
	H.ok(string.find(animator, "BossRigs.solve(", 1, true) ~= nil and string.find(animator, "joint.bone.Transform = cf", 1, true) ~= nil, "poses Bone.Transform")
	H.ok(not fs.isFile("src/shared/GiantMole.luau"), "GiantMole.luau removed")
	H.ok(string.find(fs.readFile("src/server/GuardService.luau"), "GiantMole", 1, true) == nil, "GuardService no longer builds the mole")
end)

return nil
