-- Exports the 10 bought treadmill models (models/treadmills/Treadmills.rbxl, Workspace.Treadmills: one
-- Tool per model) into assets/Treadmill_T1.rbxm ... assets/Treadmill_T10.rbxm, one per treadmill tier.
-- Each asset is a single Model holding only the visuals of the Tool's "Model" folder (the seller kit's Root,
-- SpeedPerSecond, BoundingBoxPart, its welds and its transparent SwapLeft/SwapRight buttons are dropped),
-- anchored and non-colliding, scaled so every tier's running surface is as wide as a character's treadmill
-- (BELT_WIDTH), its bottom centre at the origin. It also gets:
--   * an invisible part named "Belt": the running surface (footprint and top). Assets.fitUnder fits the
--     game's hidden TreadmillBelt to it, so the Speed check, the lock, the "+X/s" text and the board follow
--     whichever tier is shown;
--   * the console screen renamed "ConsoleScreen" (the tests find the console by name), see-through on the
--     tiers with `glass` (see TIERS);
--   * on the tiers with `groundOn` (see TIERS), a Pivot attribute at the ground point, so Assets stands the
--     model there instead of on its lowest point;
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
-- starts); the surface ends at the console (its screen), or where the seller's belt texture ends if that
-- comes first (tier 4: the texture stops 0.85 studs short of the screen, and the belt part runs on under the
-- console: the old surface reached in there, so the lock centre sat that much nearer the screen than the
-- middle of the belt you see). `top` is the surface's height above the model's bottom, read off the seller's
-- belt Beam (the scrolling texture drawn on it), in the source's studs.
-- `glass` (optional): the Transparency of the kit's screen and the panel behind it. Every kit screen stands
-- at the console end in front of the runner, from its shins to over its head, and the game turns the console
-- toward the walkway, so from there you see the back of the screen with the runner behind it. Tier 4's back
-- is a glowing opaque cyan slab and its belt is raised: all you saw was a fist beside a block of light (owner
-- screenshot 2026-10-15). Tiers 6 (cyan) and 7 (yellow) have the same opaque Neon back, taller than the
-- runner's head. See-through, the runner shows behind it.
-- `groundOn` (optional): the part whose bottom is the ground (the model's origin); without it, the model's
-- lowest point. Tier 4 stands on long curved front legs, in the same meshes as its side frames, that reach
-- 1.2 studs (game size) below everything else: on them its deck, rear wheel hub and frame hung in the air,
-- the belt 2.8 studs up (owner screenshot 2026-10-15). Set on its frame and hub (.002), the legs go into
-- the floor.
local TIERS = {
	{ tool = "Treadmill", belt = "Cube.056", top = 0.89 },
	{ tool = "Lucky BlockTreadmill", belt = "Belt.001", top = 0.45 },
	{ tool = "HackerTreadmill", belt = "Belt.001", top = 0.35 },
	{ tool = "Sci-FiTreadmill", belt = "scifi treadmil fix", top = 3.07, glass = 0.75, groundOn = "scifi treadmil fix.002" },
	{ tool = "The FreezeTreadmill", belt = "the fire treadmil test.004", top = 0.85 },
	{ tool = "FlameTreadmill", belt = "Cube.038", top = 0.80, glass = 0.75 },
	{ tool = "GoldenTreadmill", belt = "Vip Treadmil fix.005", top = 1.66, glass = 0.75 },
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
	local belt, screen, ground = nil, nil, nil
	for _, p in parts do
		if p.Name == spec.groundOn then
			assert(ground == nil, `{spec.tool}: two parts named {spec.groundOn}`)
			ground = p
		end
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
	assert(ground or not spec.groundOn, `{spec.tool}: no part {spec.groundOn}`)
	local size = hi - lo
	-- the models run along +Z with the console at the +Z end
	assert(size.Z > size.X and select(1, box(screen)).Z > (lo.Z + hi.Z) / 2, `{spec.tool}: not along +Z`)

	-- The running surface: the belt part's width, from its back end to the console (or to where the belt's
	-- scrolling texture ends, if sooner: a Beam over the belt part, along it, at the surface's height).
	local blo, bhi = box(belt)
	local surface = {
		x0 = blo.X, x1 = bhi.X,
		z0 = blo.Z, z1 = math.min(bhi.Z, select(1, box(screen)).Z),
		top = lo.Y + spec.top,
	}
	for _, d in model:GetDescendants() do
		local a0, a1 = if d:IsA("Beam") then d.Attachment0 else nil, if d:IsA("Beam") then d.Attachment1 else nil
		if a0 and a1 and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart") then
			local p0, p1 = (a0.Parent.CFrame * a0.CFrame).Position, (a1.Parent.CFrame * a1.CFrame).Position
			local over = p0.X > blo.X and p0.X < bhi.X and p1.X > blo.X and p1.X < bhi.X
			local along = math.abs(p1.Z - p0.Z) > (bhi.Z - blo.Z) / 2
			if over and along and math.abs(p0.Y - surface.top) < 0.2 then
				surface.z1 = math.min(surface.z1, math.max(p0.Z, p1.Z))
			end
		end
	end
	local s = math.min(BELT_WIDTH / (surface.x1 - surface.x0), MAX_SIZE.X / size.X, MAX_SIZE.Y / size.Y, MAX_SIZE.Z / size.Z)

	-- Scale about the bottom centre (at the groundOn part's bottom, if any) and move it to the origin,
	-- keeping every rotation.
	local floor = if ground then select(1, box(ground)).Y else lo.Y
	local origin = Vector3.new((lo.X + hi.X) / 2, floor, (lo.Z + hi.Z) / 2)
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
	-- The console screen and the video panel behind it (their folder) go: a black slab hiding the treadmill, and
	-- the game shows no video on it (owner 2026-10-20: "take this folder out of every single treadmill"). The
	-- screen still marks where the running surface ends (above).
	local screenFolder = screen.Parent
	if screenFolder and screenFolder:IsA("Folder") then
		screenFolder:Destroy()
	else
		screen:Destroy()
	end

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
	if ground then
		model:SetAttribute("Pivot", Vector3.zero) -- the ground point (the legs reach below it)
	end
	local out = size * s
	return model, string.format("T%-2d %-22s scale %.3f  model %.1f x %.1f x %.1f (w x h x l)  belt %.2f x %.2f, top %.2f, sunk %.2f",
		tier, spec.tool, s, out.X, out.Y, out.Z, marker.Size.X, marker.Size.Z, (surface.top - floor) * s, (floor - lo.Y) * s)
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
