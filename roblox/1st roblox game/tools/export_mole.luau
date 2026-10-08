-- Exports the Giant Mole rig and a sampled animation timeline as JSON for the browser preview.
--   lune run tools/export_mole.luau <out.json>
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("../tests/harness")
local GiantMole = H.shared("GiantMole")
local CFrame = roblox.CFrame

local model = roblox.Instance.new("Model")
local root = roblox.Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = roblox.Vector3.new(6, 6, 3)
root.CFrame = CFrame.new(0, 9, 0)
root.Parent = model
GiantMole.build(model, root, CFrame.new(0, 0, 0))

local function comps(cf: any): { number }
	local out = { cf:GetComponents() }
	for i, v in out do
		out[i] = math.round(v * 1000) / 1000
	end
	return out
end

-- Bones: the root plus every joint's Part1, in JOINTS order (parents first).
local bones = { root }
local boneIndex = { [root] = 1 }
local motors = {}
for _, name in GiantMole.JOINTS do
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == name then
			motors[name] = d
			table.insert(bones, d.Part1)
			boneIndex[d.Part1] = #bones
		end
	end
end

local parts = {}
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") and d ~= root then
		local bone = d
		local w = d:FindFirstChildOfClass("WeldConstraint")
		if not boneIndex[d] and w then
			bone = w.Part0
		end
		local mesh = d:FindFirstChildOfClass("SpecialMesh")
		table.insert(parts, {
			name = d.Name,
			shape = if mesh then "Ellipsoid" else d.Shape.Name,
			size = { d.Size.X, d.Size.Y, d.Size.Z },
			color = { math.round(d.Color.R * 255), math.round(d.Color.G * 255), math.round(d.Color.B * 255) },
			material = d.Material.Name,
			transparency = d.Transparency,
			bone = boneIndex[bone],
			rel = comps(bone.CFrame:Inverse() * d.CFrame),
		})
	end
end

-- Timeline: [state, seconds, ground speed]
local timeline = {
	{ "Sleeping", 4, 0 }, { "Waking", 0.9, 0 }, { "Chasing", 4, 16 }, { "Stunned", 2.5, 0 },
	{ "Chasing", 1.5, 16 }, { "Returning", 3, 9.6 }, { "Sleeping", 2.5, 0 },
}
local FPS = 24
local frames = {}
local t, phase = 0, 0
local swipeAt = 4 + 0.9 + 2.4 -- a catch swipe mid-chase
for _, seg in timeline do
	local state, dur, speed = seg[1], seg[2], seg[3]
	local n = math.floor(dur * FPS)
	for i = 0, n - 1 do
		local age = i / FPS
		local pose = GiantMole.pose(state, t, age, phase, if t >= swipeAt then t - swipeAt else nil)
		local world = { [root] = root.CFrame }
		local boneCFs = { comps(root.CFrame) }
		for _, name in GiantMole.JOINTS do
			local m = motors[name]
			local cf = world[m.Part0] * m.C0 * pose[name] * m.C1:Inverse()
			world[m.Part1] = cf
			table.insert(boneCFs, comps(cf))
		end
		table.insert(frames, { state = state, speed = speed, bones = boneCFs })
		t += 1 / FPS
		phase += speed / GiantMole.STRIDE * 2 * math.pi / FPS
	end
end

local looks = {}
for _, s in { "Sleeping", "Waking", "Chasing", "Returning", "Stunned" } do
	local l = GiantMole.look(s)
	looks[s] = { eyeY = l.eyeY, eyeColor = { math.round(l.eyeColor.R * 255), math.round(l.eyeColor.G * 255), math.round(l.eyeColor.B * 255) }, eyeNeon = l.eyeNeon, lamp = l.lamp, stars = l.stars, zzz = l.zzz }
end

local out = process.args[1] or "mole_preview.json"
fs.writeFile(out, serde.encode("json", { fps = FPS, parts = parts, frames = frames, looks = looks }))
print(`{out}: {#parts} parts, {#bones} bones, {#frames} frames`)
