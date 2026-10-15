-- Exports the 10 bought treadmill models (models/treadmills/Treadmills.rbxl, Workspace.Treadmills: one
-- Tool per model) into assets/Treadmill_T1.rbxm ... assets/Treadmill_T10.rbxm, one per treadmill tier.
-- Each asset is a single Model holding only the visuals of the Tool's "Model" folder (the seller kit's Root,
-- SpeedPerSecond, BoundingBoxPart, its welds and its transparent SwapLeft/SwapRight buttons are dropped),
-- anchored and non-colliding, scaled so every tier's running surface is as wide as a character's treadmill
-- (BELT_WIDTH), its bottom centre at the origin. It also gets:
--   * an invisible part named "Belt": the running surface (footprint and top). Assets.fitUnder fits the
--     game's hidden TreadmillBelt to it, so the Speed check, the lock, the "+X/s" text and the board follow
--     whichever tier is shown;
--   * the console screen renamed "ConsoleScreen" (the tests find the console by name);
--   * attributes Yaw = 180 (the models' console is at their +Z end; the game's front is -Z), KeepScale =
--     true (already scaled here), Tier and Source (the Tool it came from).
-- The meshes keep the seller's mesh asset ids. Run from the game folder:
--   lune run tools/export_treadmills.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local NumberSequence, NumberSequenceKeypoint = roblox.NumberSequence, roblox.NumberSequenceKeypoint

local SOURCE = "models/treadmills/Treadmills.rbxl"
local BELT_WIDTH = 4.5 -- studs: every tier's running surface is this wide (the old treadmill's belt)
local MAX_SIZE = Vector3.new(12, 9.8, 14.5) -- and the whole model never bigger than this (width, height, length)

-- Tier order, most basic first. `belt` is the part that is the running surface (its width and where it
-- starts); the surface ends at the console. `top` is the surface's height above the model's bottom, read
-- off the seller's belt Beam (the scrolling texture drawn on it), in the source's studs.
local TIERS = {
	{ tool = "Treadmill", belt = "Cube.056", top = 0.89 },
	{ tool = "Lucky BlockTreadmill", belt = "Belt.001", top = 0.45 },
	{ tool = "HackerTreadmill", belt = "Belt.001", top = 0.35 },
	{ tool = "Sci-FiTreadmill", belt = "scifi treadmil fix", top = 3.07 },
	{ tool = "The FreezeTreadmill", belt = "the fire treadmil test.004", top = 0.85 },
	{ tool = "FlameTreadmill", belt = "Cube.038", top = 0.80 },
	{ tool = "GoldenTreadmill", belt = "Vip Treadmil fix.005", top = 1.66 },
	{ tool = "CelebrityTreadmill", belt = "Cube.017", top = 1.38 },
	{ tool = "DemonicTreadmill", belt = "Belt.001", top = 0.35 },
	{ tool = "AngelicTreadmill", belt = "Belt.002", top = 0.42 },
}

-- World-axis box of one part.
local function box(p: any): (any, any)
	local cf, h = p.CFrame, p.Size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local e = Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	)
	return cf.Position - e, cf.Position + e
end

local function scaleSequence(seq: any, s: number): any
	local points = {}
	for _, k in seq.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(k.Time, k.Value * s, k.Envelope * s))
	end
	return NumberSequence.new(points)
end

local function export(spec: any, tier: number, tool: any): (any, string)
	local folder = tool:FindFirstChild("Model")
	assert(folder, `{spec.tool} has no Model folder`)
	local model = roblox.Instance.new("Model")
	model.Name = `Treadmill_T{tier}`
	-- (the folder is cloned whole: a clone keeps only references inside itself, and the belt's scrolling
	-- Beam lives in "Beam Holder" with its Attachment1 in "Beam Part", so child by child it lost its end)
	for _, child in folder:Clone():GetChildren() do
		child.Parent = model
	end

	-- Drop the kit's leftovers: welds (to the old Root), its invisible screen-swap buttons, any code.
	for _, d in model:GetDescendants() do
		if d.Parent == nil then
			continue
		end
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("LuaSourceContainer") or d:IsA("Tool")
			or d:IsA("ClickDetector") or d:IsA("ProximityPrompt") or d:IsA("TouchTransmitter") then
			d:Destroy()
		elseif d:IsA("BasePart") and (d.Name == "SwapLeft" or d.Name == "SwapRight") then
			d:Destroy()
		end
	end

	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	local belt, screen = nil, nil
	for _, p in parts do
		if p.Transparency < 1 then
			local a, b = box(p)
			lo, hi = lo:Min(a), hi:Max(b)
		end
		if p.Name == spec.belt then
			assert(belt == nil, `{spec.tool}: two parts named {spec.belt}`)
			belt = p
		elseif p.Name == "VideoFeedScreen" then
			screen = p
		end
	end
	assert(belt and screen, `{spec.tool}: no belt part {spec.belt} or no VideoFeedScreen`)
	local size = hi - lo
	-- the models run along +Z with the console at the +Z end
	assert(size.Z > size.X and select(1, box(screen)).Z > (lo.Z + hi.Z) / 2, `{spec.tool}: not along +Z`)

	-- The running surface: the belt part's width, from its back end to the console.
	local blo, bhi = box(belt)
	local surface = {
		x0 = blo.X, x1 = bhi.X,
		z0 = blo.Z, z1 = math.min(bhi.Z, select(1, box(screen)).Z),
		top = lo.Y + spec.top,
	}
	local s = math.min(BELT_WIDTH / (surface.x1 - surface.x0), MAX_SIZE.X / size.X, MAX_SIZE.Y / size.Y, MAX_SIZE.Z / size.Z)

	-- Scale about the bottom centre and move it to the origin, keeping every rotation.
	local origin = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	for _, p in parts do
		p.Size *= s
		p.CFrame = CFrame.new((p.CFrame.Position - origin) * s) * p.CFrame.Rotation
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") then
			d.CFrame = CFrame.new(d.CFrame.Position * s) * d.CFrame.Rotation
		elseif d:IsA("Beam") then
			d.Width0 *= s
			d.Width1 *= s
			d.CurveSize0 *= s
			d.CurveSize1 *= s
		elseif d:IsA("ParticleEmitter") then
			d.Size = scaleSequence(d.Size, s)
		end
	end
	screen.Name = "ConsoleScreen"

	local marker = roblox.Instance.new("Part")
	marker.Name = "Belt"
	marker.Size = Vector3.new(surface.x1 - surface.x0, 0.2, surface.z1 - surface.z0) * s
	local mid = Vector3.new((surface.x0 + surface.x1) / 2, surface.top, (surface.z0 + surface.z1) / 2)
	marker.CFrame = CFrame.new((mid - origin) * s - Vector3.new(0, 0.1, 0))
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker.Parent = model
	model.PrimaryPart = marker

	model:SetAttribute("Yaw", 180)
	model:SetAttribute("KeepScale", true)
	model:SetAttribute("Tier", tier)
	model:SetAttribute("Source", spec.tool)
	local out = size * s
	return model, string.format("T%-2d %-22s scale %.3f  model %.1f x %.1f x %.1f (w x h x l)  belt %.2f x %.2f, top %.2f",
		tier, spec.tool, s, out.X, out.Y, out.Z, marker.Size.X, marker.Size.Z, (surface.top - lo.Y) * s)
end

local place = roblox.deserializePlace(fs.readFile(SOURCE))
local folder = place:GetService("Workspace"):FindFirstChild("Treadmills")
assert(folder, `{SOURCE} has no Workspace.Treadmills`)
for tier, spec in TIERS do
	local tool = folder:FindFirstChild(spec.tool)
	assert(tool, `{SOURCE}: no {spec.tool}`)
	local model, line = export(spec, tier, tool)
	fs.writeFile(`assets/Treadmill_T{tier}.rbxm`, roblox.serializeModel({ model }))
	print(line)
end
