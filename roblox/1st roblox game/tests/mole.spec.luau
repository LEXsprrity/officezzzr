-- The Meadow boss rig (GiantMole): builds with Lune's Roblox instances, every bone is joined, and the
-- animation produces a finite pose for every joint in every state.
local H = require("./harness")
local roblox = require("@lune/roblox")
local GiantMole = H.shared("GiantMole")

local function newRig()
	local model = roblox.Instance.new("Model")
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = roblox.Vector3.new(6, 6, 3)
	root.CFrame = roblox.CFrame.new(0, 9, 0)
	root.Parent = model
	local head = GiantMole.build(model, root, roblox.CFrame.new(0, 0, 0))
	return model, root, head
end

H.test("mole: builds a rig with every joint, all parts massless and non-colliding", function()
	local model, root, head = newRig()
	H.eq(head.Name, "Head")
	H.eq(model:GetAttribute("Rig"), "GiantMole")
	local motors, parts = {}, 0
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			H.ok(motors[d.Name] == nil, "unique joint " .. d.Name)
			motors[d.Name] = d
			H.ok(d.Part0 ~= nil and d.Part1 ~= nil, d.Name .. " has both parts")
		elseif d:IsA("BasePart") and d ~= root then
			parts += 1
			H.ok(d.Massless and not d.CanCollide and not d.CanQuery and not d.CanTouch and not d.Anchored, d.Name .. " is a loose visual part")
			local held = d:FindFirstChildOfClass("WeldConstraint") or d:FindFirstChildOfClass("Motor6D")
			H.ok(held ~= nil, d.Name .. " is attached to the rig")
		end
	end
	for _, name in GiantMole.JOINTS do
		H.ok(motors[name] ~= nil, "joint " .. name)
	end
	H.ok(parts >= 60 and parts <= 140, `part budget ({parts})`)
end)

H.test("mole: the joints reproduce the rest pose (C0 * C1^-1 puts each bone where it was built)", function()
	local model = newRig()
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local placed = d.Part0.CFrame * d.C0 * d.C1:Inverse()
			H.ok((placed.Position - d.Part1.CFrame.Position).Magnitude < 1e-3, d.Name .. " rest position")
		end
	end
end)

H.test("mole: every state poses every joint with finite values, and the swipe overlays", function()
	for _, state in { "Sleeping", "Waking", "Chasing", "Returning", "Stunned" } do
		for _, t in { 0, 0.13, 0.5, 1.7, 4.2 } do
			local pose = GiantMole.pose(state, t, t, t * 9, nil)
			for _, name in GiantMole.JOINTS do
				local cf = pose[name]
				H.ok(cf ~= nil, `{state} poses {name}`)
				local x, y, z, r00 = cf:GetComponents()
				H.ok(x == x and y == y and z == z and r00 == r00 and math.abs(x) < 10 and math.abs(y) < 10 and math.abs(z) < 10, `{state} {name} is finite and small`)
			end
		end
	end
	local calm = GiantMole.pose("Chasing", 1, 1, 3, nil)
	local swipe = GiantMole.pose("Chasing", 1, 1, 3, 0.3)
	H.ok(calm.ShoulderR ~= swipe.ShoulderR, "a recent catch swipes the right paw")
	H.ok(GiantMole.look("Sleeping").zzz and not GiantMole.look("Chasing").zzz, "Zzz only while asleep")
	H.ok(GiantMole.look("Chasing").lamp and not GiantMole.look("Sleeping").lamp, "headlamp on when awake")
	H.ok(GiantMole.look("Stunned").stars, "stun stars")
end)

-- Lowest point of every visible part over sampled frames, per state (ground is y = 0).
local function lowestPerState(): { [string]: { y: number, part: string } }
	local model, root = newRig()
	local motors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	local out = {}
	for _, state in { "Sleeping", "Waking", "Chasing", "Returning", "Stunned" } do
		local low = { y = math.huge, part = "" }
		for i = 0, 95 do
			local t = i / 24
			local speed = if state == "Chasing" then 16 elseif state == "Returning" then 9.6 else 0
			local phase = t * speed / GiantMole.STRIDE * 2 * math.pi
			local pose = GiantMole.pose(state, t, t, phase, if state == "Chasing" and t > 2 then t - 2 else nil)
			local world = { [root] = root.CFrame }
			for _, name in GiantMole.JOINTS do
				local m = motors[name]
				world[m.Part1] = world[m.Part0] * m.C0 * pose[name] * m.C1:Inverse()
			end
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d ~= root and d.Transparency < 1 then
					local bone = d
					local w = d:FindFirstChildOfClass("WeldConstraint")
					if not world[d] and w then
						bone = w.Part0
					end
					local cf = world[bone] * (bone.CFrame:Inverse() * d.CFrame)
					local size = d.Size
					if d.Shape == roblox.Enum.PartType.Ball then
						local m = math.min(size.X, size.Y, size.Z)
						size = roblox.Vector3.new(m, m, m)
					elseif d.Shape == roblox.Enum.PartType.Cylinder then
						local m = math.min(size.Y, size.Z)
						size = roblox.Vector3.new(size.X, m, m)
					end
					local _, _, _, _, _, _, r10, r11, r12 = cf:GetComponents()
					local round = if d:FindFirstChildOfClass("SpecialMesh") or d.Shape == roblox.Enum.PartType.Ball then 0.8 else 1
					local half = (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2 * round
					local y = cf.Position.Y - half
					if y < low.y then
						low = { y = y, part = d.Name .. "@" .. bone.Name }
					end
				end
			end
		end
		out[state] = low
	end
	return out
end

H.test("mole: no part sinks into the ground in any animation (claws may graze it)", function()
	local bad = {}
	for state, low in lowestPerState() do
		if low.y <= -0.9 then
			table.insert(bad, `{state}: {low.part} reaches y = {math.floor(low.y * 100) / 100}`)
		end
	end
	H.ok(#bad == 0, table.concat(bad, "; "))
end)
