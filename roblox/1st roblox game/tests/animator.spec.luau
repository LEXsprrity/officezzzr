-- The bosses end to end, as close to Studio as Lune gets: each zone's guard body built like GuardService
-- builds it (GuardBody), and the real GuardAnimator.client run on it frame by frame, its Bone.Transforms
-- read back. (Roblox draws a skinned mesh from its Bones only when the mesh is joined to the Bones' part
-- by a skinning joint inside the same Model: those joints are checked here too.)
local roblox = require("@lune/roblox")
local H = require("./harness")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local Config = H.shared("Config")
local BossRigs = H.shared("BossRigs")
local GuardBody = H.server("GuardBody")

local function buildGuard(k: number): (any, any)
	local zone = Config.ZONES[k]
	local S = Config.GUARD_SCALE
	local hip = 2 * S
	local model = roblox.Instance.new("Model")
	model.Name = "Guard_" .. zone.id
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * S
	root.Transparency = 1
	local home = Vector3.new(400 * k, 0, 0)
	root.CFrame = CFrame.lookAt(home + Vector3.new(0, hip + root.Size.Y / 2, 0), home + Vector3.new(-10, hip + root.Size.Y / 2, 0))
	root.Parent = model
	model.PrimaryPart = root
	local placed, rig = GuardBody.fromAsset(model, root, zone, hip)
	assert(placed and rig, `{zone.id}: no rigged body`)
	model:SetAttribute("State", "Sleeping")
	model.Parent = H.workspace
	return model, root
end

local function petOf(model: any): any
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("BossRig") then
			return d
		end
	end
	return nil
end

H.test("animator: each pet's skinned meshes hang off its bone host by Motor6Ds inside the pet's Model (Studio binds skinning only through such joints)", function()
	for k, zone in Config.ZONES do
		local model, root = buildGuard(k)
		local pet = petOf(model)
		local host = pet.PrimaryPart
		local welds = 0
		for _, d in pet:GetDescendants() do
			if d:IsA("BasePart") then
				H.ok(not d.Anchored, `{zone.id}: {d.Name} unanchored (moves with the chase)`)
			end
			if d:IsA("MeshPart") then
				H.ok(d.HasSkinnedMesh, `{zone.id}: {d.Name} skinned`)
				local joint = d:FindFirstChildOfClass("Motor6D")
				H.ok(joint and joint.Part0 == host and joint.Part1 == d, `{zone.id}: {d.Name} joined to {host.Name} by a Motor6D`)
				if joint then
					local gap = ((host.CFrame * joint.C0).Position - (d.CFrame * joint.C1).Position).Magnitude
					H.ok(gap < 1e-3, `{zone.id}: {d.Name}'s Motor6D holds it where it was placed ({gap} off)`)
				end
				H.ok(d:FindFirstChildOfClass("WeldConstraint") == nil, `{zone.id}: {d.Name} has no WeldConstraint to the guard's root (it would bypass the rig)`)
			elseif d:IsA("WeldConstraint") then
				welds += 1
				H.ok(d.Parent == host and d.Part0 == root and d.Part1 == host, `{zone.id}: only the bone host is welded to the root ({d:GetFullName()})`)
			end
		end
		H.eq(welds, 1, `{zone.id}: one weld, bone host -> root`)
		model:Destroy()
	end
end)

H.test("animator: GuardAnimator.client poses every boss's Bones by frame: asleep it lies down with its eyes shut, chasing its legs swing", function()
	local models, roots = {}, {}
	for k in Config.ZONES do
		models[k], roots[k] = buildGuard(k)
	end
	-- the client's world: the real instances, with stand-ins for what Lune lacks (events, camera, sound)
	local stepped = nil
	local spawned = {}
	local printed = {}
	local camera = { CFrame = CFrame.identity }
	local now = 1000 -- the client's clock: advanced by each frame
	local clockOs = setmetatable({ clock = function()
		return now
	end }, { __index = os })
	local ws = setmetatable({
		CurrentCamera = camera,
		GetDescendants = function()
			return H.workspace:GetDescendants()
		end,
		GetServerTimeNow = function()
			return now
		end,
		DescendantAdded = { Connect = function() end },
		DescendantRemoving = { Connect = function() end },
	}, { __index = function(_, k)
		error("workspace stand-in: " .. tostring(k))
	end })
	local RunService = { RenderStepped = { Connect = function(_, fn)
		stepped = fn
	end } }
	local function sound(): any
		local real = roblox.Instance.new("Sound")
		return setmetatable({}, {
			__index = function(_, k)
				if k == "Play" or k == "Stop" then
					return function() end
				elseif k == "Destroy" then
					return function()
						real:Destroy()
					end
				end
				return real[k]
			end,
			__newindex = function(_, k, v)
				real[k] = v
			end,
		})
	end
	H.runClient("src/client/GuardAnimator.client.luau", {
		workspace = ws,
		Instance = { new = function(class: string)
			return if class == "Sound" then sound() else roblox.Instance.new(class)
		end },
		task = {
			spawn = function(fn)
				table.insert(spawned, coroutine.create(fn))
			end,
			wait = function()
				coroutine.yield()
			end,
			defer = function(fn, ...)
				fn(...)
			end,
		},
		os = clockOs,
		print = function(line)
			table.insert(printed, line)
		end,
	}, { RunService = RunService })
	H.ok(stepped ~= nil, "it renders every frame")
	for _, co in spawned do
		local ok, err = coroutine.resume(co)
		H.ok(ok, `its tracking loop runs: {err}`)
	end
	H.eq(#printed, #Config.ZONES, "one Output line per boss it animates")

	local dt = 1 / 60
	local function frame()
		now += dt
		stepped(dt)
	end
	for k, zone in Config.ZONES do
		local model, root = models[k], roots[k]
		local pet = petOf(model)
		local profile = BossRigs.PROFILES[pet:GetAttribute("BossRig")]
		camera.CFrame = root.CFrame
		local bones = {}
		for _, d in pet:GetDescendants() do
			if d:IsA("Bone") then
				bones[d.Name] = d
			end
		end
		local function eyesShown(): number
			local n = 0
			for _, name in profile.eyes do
				local eye = pet:FindFirstChild(name)
				H.ok(eye and eye:IsA("MeshPart"), `{zone.id}: eye mesh {name}`)
				if eye and eye.Transparency < 1 then
					n += 1
				end
			end
			return n
		end

		-- asleep: the body sinks onto the ground, the eyes shut
		for _ = 1, 30 do
			frame()
		end
		local body = bones[profile.body].Transform
		H.ok(body ~= CFrame.identity, `{zone.id}: the sleeping body bone is posed`)
		H.eq(eyesShown(), 0, `{zone.id}: eyes shut asleep`)
		local posed = 0
		for _, b in bones do
			if b.Transform ~= CFrame.identity then
				posed += 1
			end
		end
		H.ok(posed >= 5, `{zone.id}: {posed} bones posed asleep`)

		-- chasing: run along -X at its chase speed; a leg (or the tail) keeps changing
		model:SetAttribute("State", "Chasing")
		local speed = Config.guardChaseSpeed(k)
		local probe = if profile.legs then profile.legs[1].hip else (profile.tail :: any)[#(profile.tail :: any)]
		local seen = {}
		for i = 1, 90 do
			root.CFrame = root.CFrame + Vector3.new(-speed * dt, 0, 0)
			for _, d in pet:GetDescendants() do
				if d:IsA("BasePart") then
					d.CFrame = d.CFrame + Vector3.new(-speed * dt, 0, 0) -- (no physics here: the welds carry them in Studio)
				end
			end
			camera.CFrame = root.CFrame
			frame()
			if i > 30 then
				table.insert(seen, bones[probe].Transform)
			end
		end
		local most = 0
		for _, a in seen do
			for _, b in seen do
				local _, angle = (a:Inverse() * b):ToAxisAngle()
				most = math.max(most, math.abs(angle))
			end
		end
		H.ok(most > 0.4, `{zone.id}: {probe} swings through {most} rad while running`)
		H.eq(eyesShown(), #profile.eyes, `{zone.id}: eyes open awake`)
	end
	for _, m in models do
		m:Destroy()
	end
end)

return nil
