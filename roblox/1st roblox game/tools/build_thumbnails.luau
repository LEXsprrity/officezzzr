-- Builds ready-to-shoot marketing scenes for the game's icon and thumbnails: standalone place files the owner
-- opens in Studio, drops their avatar into and screenshots. Each scene is one boss chasing the player, who
-- runs toward the camera holding a big glowing seed over their head, in a slice of the boss's zone:
--   * the zone is copied from map/World.rbxm (the zone's folder and the next one, for the far view), with
--     every prop cleared out of the action area;
--   * the boss is its Guard asset with a CATCH pose (mid-lunge, jaw open) from BossRigs baked into the Bones'
--     CFrames (a Bone's Transform isn't saved; its CFrame is), so it is posed with no script running;
--   * the seed is the zone's Seed asset scaled up, with a glow (Highlight, PointLight, sparkles and a few
--     Neon stars: this is marketing, not the game's look);
--   * the player is a marked spot, the invisible part PUT_YOUR_AVATAR_HERE (the HumanoidRootPart's place,
--     facing the camera), plus BONECO_EXEMPLO, a plain-block stand-in in the pose, to delete once the real
--     avatar is in (Roblox avatar meshes can't ship in a file);
--   * a few of the zone's flowers (its Creature plant models) around them;
--   * bright, saturated lighting with some bloom, no fog, and a key light from the camera's side;
--   * Workspace.CurrentCamera framed for the shot: the icon (512x512, close-up) or the thumbnail (1920x1080,
--     with the big relief title "STEAL A SEED" on a SurfaceGui to the left of the characters).
-- It also writes LEIA-ME.txt, the owner's how-to (Portuguese). Deterministic: no randomness, no clock.
-- Run from the game folder (default output: <your Desktop>/Thumbnails):
--   lune run tools/build_thumbnails.luau [output folder]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("../tests/harness")
local Config = H.shared("Config")
local BossRigs = H.shared("BossRigs")

local Instance, Vector3, CFrame, Color3 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3
local Vector2, UDim2, Enum = roblox.Vector2, roblox.UDim2, roblox.Enum
local ColorSequence, ColorSequenceKeypoint = roblox.ColorSequence, roblox.ColorSequenceKeypoint
local NumberSequence, NumberSequenceKeypoint, NumberRange = roblox.NumberSequence, roblox.NumberSequenceKeypoint, roblox.NumberRange
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi

local function rgb(r: number, g: number, b: number): any
	return Color3.fromRGB(r, g, b)
end

local MARKER = "PUT_YOUR_AVATAR_HERE"
local STANDIN = "BONECO_EXEMPLO"
local SEED_NAME = "SEMENTE_BRILHANTE"
local SEED_HEIGHT = 7.5 -- studs: the seed, scaled up as far as it fits this tall (leaves and all)...
local SEED_WIDTH = 4.6 -- ...and this wide: about the avatar's size, like the reference's egg
local HIP = 3 -- a standard rig's HumanoidRootPart centre above the ground
-- Where the seed's bottom centre is held, in the rig's frame (ground under it, facing -Z): over the head,
-- a little in front, where a standard avatar's hands reach with the arms up.
local SEED_AT = CFrame.new(0, HIP + 2.6, -0.3)

----------------------------------------------------------------------------------------------------
-- The three scenes. Positions are in the scene's frame: origin on the ground at `at` in the zone, -Z into
-- the screen (the camera looks along it, toward +X in the world: down the corridor, away
-- from the base), +X screen right, +Y up. The player runs toward the camera, the boss right behind.
----------------------------------------------------------------------------------------------------
export type Shot = {
	eye: any, -- camera position
	at: any, -- what it looks at
	fov: number, -- vertical field of view (degrees)
	aspect: number, -- the screenshot's width / height (the title is placed for it)
}

export type Scene = {
	key: string, -- file name part: Icon_<key>.rbxl, Thumbnail_<key>.rbxl
	zone: string, -- Config.ZONES id
	guard: string, -- assets/Guard_<guard>.rbxm
	seed: string, -- the design in assets/Seed_<zone>.rbxm
	at: any, -- the scene's origin in the world (on the ground)
	boss: { pos: any, turn: number }, -- turn: radians toward the player (screen left)
	player: { pos: any, turn: number },
	pose: { phase: number, t: number, catch: number }, -- BossRigs.pose input (Chasing, flat out)
	extra: { { any } }, -- { bone (profile field), CFrame } added on top, in model axes
	glow: any, -- the seed's glow colour
	mouth: any, -- the boss's mouth light
	icon: Shot,
	thumb: Shot,
}

-- A CFrame at `eye` looking at `target` (Lune's CFrame.lookAt points the wrong way for most directions:
-- see Props.lookAt).
local function lookAt(eye: any, target: any): any
	local look = (target - eye).Unit
	local right = look:Cross(Vector3.new(0, 1, 0)).Unit
	return CFrame.fromMatrix(eye, right, right:Cross(look))
end

local function pitch(a: number): any -- positive: the front tips down
	return CFrame.Angles(-a, 0, 0)
end

-- The two framings (scene frame): the icon close and low, the characters filling the square; the thumbnail
-- wider, the characters right of centre and the title on the left.
local ICON: Shot = { eye = Vector3.new(1, 2.4, 19.5), at = Vector3.new(1.6, 8.3, -2), fov = 60, aspect = 1 }
local THUMB: Shot = { eye = Vector3.new(-4, 3, 24), at = Vector3.new(-6.2, 8.4, -2), fov = 56, aspect = 16 / 9 }

local SCENES: { Scene } = {
	{
		key = "VoidDragon", zone = "Space", guard = "VoidDragon", seed = "Design2",
		at = Vector3.new(1840, 0, -5),
		boss = { pos = Vector3.new(4, 0, -3.5), turn = 0.4 },
		player = { pos = Vector3.new(-2.4, 0, 4.5), turn = 0.3 },
		pose = { phase = pi / 2 - 0.5, t = 0.3456, catch = 0.135 },
		extra = { { "jaw", pitch(0.3) }, { "head", pitch(-0.15) } },
		glow = rgb(214, 140, 255), mouth = rgb(190, 110, 255),
		icon = ICON, thumb = THUMB,
	},
	{
		key = "Gorilla", zone = "Lava", guard = "VolcanoGorilla", seed = "Design1",
		at = Vector3.new(1060, 0, -5),
		boss = { pos = Vector3.new(4.2, 0, -4), turn = 0.35 },
		player = { pos = Vector3.new(-2.4, 0, 4.5), turn = 0.3 },
		pose = { phase = pi / 2 + 0.3, t = 0.4, catch = 0.135 },
		extra = { { "jaw", pitch(0.25) } },
		glow = rgb(255, 170, 60), mouth = rgb(255, 120, 40),
		icon = ICON, thumb = THUMB,
	},
	{
		key = "Lumistag", zone = "Spirit", guard = "Lumistag", seed = "Design2",
		at = Vector3.new(2150, 0, -5),
		boss = { pos = Vector3.new(4.5, 0, -5), turn = 0.45 },
		player = { pos = Vector3.new(-2.4, 0, 4.5), turn = 0.3 },
		pose = { phase = pi / 2 - 0.4, t = 0.4, catch = 0.24 },
		extra = {},
		glow = rgb(255, 160, 210), mouth = rgb(150, 230, 255),
		icon = ICON, thumb = THUMB,
	},
}

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------
local function new(class: string, props: { [string]: any }, parent: any?): any
	local inst = Instance.new(class)
	for k, v in props do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function zoneIndex(id: string): number
	for k, z in Config.ZONES do
		if z.id == id then
			return k
		end
	end
	error(`no zone {id}`)
end

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

local function bounds(inst: any): (any?, any?)
	local lo, hi
	local list = inst:GetDescendants()
	if inst:IsA("BasePart") then
		table.insert(list, inst)
	end
	for _, d in list do
		if d:IsA("BasePart") then
			local a, b = box(d)
			lo = if lo then lo:Min(a) else a
			hi = if hi then hi:Max(b) else b
		end
	end
	return lo, hi
end

-- Moves (and turns) a model built around the origin to `cf`.
local function place(model: any, cf: any)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = cf * d.CFrame
		end
	end
	local ok, pivot = pcall(function()
		return model.WorldPivot
	end)
	model.WorldPivot = cf * (if ok then pivot else CFrame.identity)
end

-- Scales a model about the origin (parts only: the seeds have no meshes or lights to scale).
local function scale(model: any, k: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size *= k
			d.CFrame = CFrame.new(d.CFrame.Position * k) * d.CFrame.Rotation
		end
	end
end

local function still(model: any)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
end

-- Lune keeps `.Font = Enum.Font.X` as a raw EnumItem the file format rejects: labels set FontFace instead.
local FREDOKA = roblox.Font.fromEnum(Enum.Font.FredokaOne)

----------------------------------------------------------------------------------------------------
-- The zone slice
----------------------------------------------------------------------------------------------------
local WORLD_FILE = fs.readFile("map/World.rbxm")

-- The zone's folder (and the next zone's, so the far view isn't the edge of the map), with every prop
-- that pokes up into the clear area (world box lo..hi) removed. Flat things on the floor stay.
local function zoneSlice(id: string, lo: any, hi: any): any
	local world = roblox.deserializeModel(WORLD_FILE)[1]
	local k = zoneIndex(id)
	local out = new("Folder", { Name = "Zona_" .. id })
	for i = k, math.min(k + 1, #Config.ZONES) do
		local folder = world.Corridor:FindFirstChild(`{i}_{Config.ZONES[i].id}`)
		assert(folder, `map/World.rbxm has no Corridor.{i}_{Config.ZONES[i].id}`)
		for _, child in folder:GetChildren() do
			local a, b = bounds(child)
			local inside = a and b and a.X < hi.X and b.X > lo.X and a.Z < hi.Z and b.Z > lo.Z
			if child.Name == "Ambience" or (inside and b.Y > Config.GROUND_Y + 0.6) then
				child:Destroy()
			end
		end
		folder.Parent = out
	end
	for _, d in out:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	return out
end

-- The zone's own flowers: its plant-creature models (the small, plain ones).
local function flowerModels(id: string): { any }
	local k = zoneIndex(id)
	local seed = string.gsub(Config.ZONES[k].seed, "%s", "")
	local folder = roblox.deserializeModel(fs.readFile(`assets/Creature_{seed}.rbxm`))[1]
	local list = {}
	for _, rarity in { "Common", "Uncommon", "Rare" } do
		for _, m in folder[rarity]:GetChildren() do
			if m.Name ~= "Bamboo" then
				table.insert(list, m)
			end
		end
	end
	return list
end

-- Flower spots (scene frame), clear of the characters and of the camera's view of them.
local FLOWERS = {
	{ -9, 7, 0.3 }, { -11.5, 1, 1.4 }, { 9.5, 8, 2.2 }, { 12, 1.5, 0.9 }, { -13.5, -6, 2.8 }, { 14, -7, 0.5 },
	{ -17, 6, 0.2 }, { 17, 6, 2.6 }, { -19, -12, 1.1 }, { 19, -13, 3.9 }, { -8, -15, 2.4 }, { 10, -17, 0.7 },
	{ -24, 0, 1.6 }, { 23, -1, 3.1 }, { -3, -18, 1 }, { 4, -20, 2 },
}

----------------------------------------------------------------------------------------------------
-- The boss, posed
----------------------------------------------------------------------------------------------------
-- Adds `cf` on top of what the bone already has, like BossRigs does (rotation after, in model axes).
local function add(pose: any, bone: string?, cf: any)
	if not bone then
		return
	end
	local e = pose[bone]
	pose[bone] = if e then CFrame.new(e.Position + cf.Position) * cf.Rotation * e.Rotation else cf
end

local function boss(scene: Scene): (any, { [string]: any })
	local model = roblox.deserializeModel(fs.readFile(`assets/Guard_{scene.guard}.rbxm`))[1]
	local profile = BossRigs.PROFILES[model:GetAttribute("BossRig")]
	local rig = BossRigs.rig(model.PrimaryPart, profile, model:GetAttribute("RigScale"))
	local pose = BossRigs.pose(profile, {
		state = "Chasing", t = scene.pose.t, age = 3, phase = scene.pose.phase, move = 1, catch = scene.pose.catch,
	})
	for _, e in scene.extra do
		add(pose, (profile :: any)[e[1]], e[2])
	end
	local transforms, world = BossRigs.solve(rig, pose)
	-- bake: a bone's posed frame is its CFrame then its Transform; the file keeps the CFrame only
	for _, j in rig.joints do
		j.bone.CFrame = j.local0 * transforms[j]
	end
	local at = {}
	for _, j in rig.joints do
		at[j.name] = world[j].Position
	end
	-- an angry glow in the mouth
	local mouth = rig.byName[profile.jaw or profile.head]
	new("PointLight", { Color = scene.mouth, Brightness = 2.5, Range = 10, Shadows = false }, mouth.bone)
	model.Name = "BOSS_" .. scene.guard
	still(model)
	return model, at
end

----------------------------------------------------------------------------------------------------
-- The glowing seed
----------------------------------------------------------------------------------------------------
local function seedModel(scene: Scene): any
	local folder = roblox.deserializeModel(fs.readFile(`assets/Seed_{scene.zone}.rbxm`))[1]
	local model = folder:FindFirstChild(scene.seed):Clone()
	local lo, hi = bounds(model)
	local k = math.min(SEED_HEIGHT / (hi.Y - lo.Y), SEED_WIDTH / (2 * math.max(-lo.X, hi.X, -lo.Z, hi.Z)))
	scale(model, k)
	lo, hi = lo * k, hi * k
	local height = hi.Y - lo.Y
	local reach = math.max(-lo.X, hi.X, -lo.Z, hi.Z) -- from its centre line
	model.Name = SEED_NAME
	model.WorldPivot = CFrame.identity
	still(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	new("Highlight", {
		FillColor = scene.glow, FillTransparency = 0.65, OutlineColor = rgb(255, 250, 200), OutlineTransparency = 0.1,
		DepthMode = Enum.HighlightDepthMode.Occluded,
	}, model)
	-- the glow: a light, sparkles and a ring of little Neon stars around it
	local core = new("Part", {
		Name = "Brilho", Size = Vector3.new(2 * reach, height, 2 * reach), CFrame = CFrame.new(0, height / 2, 0),
		Transparency = 1, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false,
	}, model)
	new("PointLight", { Color = scene.glow, Brightness = 4, Range = 16, Shadows = false }, core)
	new("ParticleEmitter", {
		Name = "Brilhos", Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(rgb(255, 255, 255), scene.glow), LightEmission = 1, Brightness = 2,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) }),
		Lifetime = NumberRange.new(1, 1.8), Rate = 30, Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(180, 180), RotSpeed = NumberRange.new(-90, 90), ZOffset = 1,
	}, core)
	for i = 1, 7 do
		local a = i * 2 * pi / 7 + 0.4
		local y = height * (0.25 + 0.6 * ((i * 3) % 7) / 6)
		local s = 0.45 + 0.2 * (i % 3)
		new("Part", {
			Name = "Estrela", Material = Enum.Material.Neon, Color = if i % 2 == 0 then scene.glow else rgb(255, 245, 190),
			Size = Vector3.new(s, s, s), CFrame = CFrame.new(cos(a) * (reach + 1.4), y, sin(a) * (reach + 0.8)) * CFrame.Angles(rad(45), rad(i * 20), rad(45)),
			Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false,
		}, model)
	end
	return model
end

----------------------------------------------------------------------------------------------------
-- The player: the marker, and a plain-block stand-in in the pose (arms up holding the seed, mid-stride)
----------------------------------------------------------------------------------------------------
-- Built facing -Z (the rig's front), HumanoidRootPart centre at (0, HIP, 0); its hands reach up under the
-- seed (SEED_AT).
local function standIn(): any
	local model = new("Model", { Name = STANDIN })
	local yellow, blue, green = rgb(245, 205, 48), rgb(13, 105, 172), rgb(40, 127, 71)
	local function block(name: string, size: any, cf: any, color: any): any
		return new("Part", {
			Name = name, Size = size, CFrame = cf, Color = color, Material = Enum.Material.SmoothPlastic,
			TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
			Anchored = true, CanCollide = false, CanTouch = false,
		}, model)
	end
	local torso = CFrame.new(0, HIP, 0) * CFrame.Angles(-0.12, 0, 0) -- leaning into the run
	block("Torso", Vector3.new(2, 2, 1), torso, blue)
	local head = block("Head", Vector3.new(1.2, 1.2, 1.2), torso * CFrame.new(0, 1.6, 0) * CFrame.Angles(0.1, 0, 0), yellow)
	new("Decal", { Name = "face", Texture = "rbxasset://textures/face.png", Face = Enum.NormalId.Front }, head)
	for _, side in { -1, 1 } do
		-- arms up over the head, hands under the seed, a little apart
		local shoulder = (torso * CFrame.new(side * 1.5, 0.75, 0)).Position
		local hand = SEED_AT * Vector3.new(side * 0.85, 0.1, 0)
		local along = (hand - shoulder).Unit
		local up = -along -- the arm's +Y, from the hand to the shoulder
		local center = (shoulder - along * 0.5 + hand) / 2
		local arm = CFrame.fromMatrix(center, Vector3.new(0, 0, -1):Cross(up).Unit, up)
		block(if side < 0 then "Left Arm" else "Right Arm", Vector3.new(1, (hand - shoulder).Magnitude + 0.5, 1), arm, yellow)
		-- mid-stride: right leg forward, left leg back
		local hip = torso * CFrame.new(side * 0.5, -1, 0) * CFrame.Angles(if side > 0 then 0.55 else -0.45, 0, 0)
		block(if side < 0 then "Left Leg" else "Right Leg", Vector3.new(1, 2, 1), hip * CFrame.new(0, -1, 0), green)
	end
	model.PrimaryPart = model.Torso
	model.WorldPivot = CFrame.new(0, HIP, 0)
	return model
end

----------------------------------------------------------------------------------------------------
-- Lighting: bright, saturated, a bit of bloom, no fog
----------------------------------------------------------------------------------------------------
local function lighting(game: any, focus: number, depth: number)
	local L = game:GetService("Lighting")
	L.Technology = Enum.Technology.Future
	L.ClockTime = 13
	L.GeographicLatitude = 30
	L.Brightness = 3
	L.Ambient = rgb(110, 110, 125)
	L.OutdoorAmbient = rgb(165, 165, 180)
	L.ColorShift_Top = rgb(255, 240, 215)
	L.ColorShift_Bottom = rgb(60, 80, 120)
	L.EnvironmentDiffuseScale = 1
	L.EnvironmentSpecularScale = 0.3
	L.GlobalShadows = true
	L.ShadowSoftness = 0.15
	L.ExposureCompensation = 0.15
	new("Sky", { Name = "Sky", SunAngularSize = 14, MoonAngularSize = 11, CelestialBodiesShown = true, StarCount = 0 }, L)
	new("Atmosphere", { Density = 0, Offset = 0, Haze = 0, Glare = 0, Color = rgb(200, 228, 255), Decay = rgb(110, 160, 220) }, L)
	new("BloomEffect", { Intensity = 0.7, Size = 28, Threshold = 1.3 }, L)
	new("ColorCorrectionEffect", { Saturation = 0.3, Contrast = 0.12, Brightness = 0.03, TintColor = rgb(255, 252, 245) }, L)
	new("SunRaysEffect", { Intensity = 0.04, Spread = 0.7 }, L)
	-- the characters stay sharp; the far zone softens a little
	new("DepthOfFieldEffect", { FocusDistance = focus, InFocusRadius = depth, NearIntensity = 0, FarIntensity = 0.25 }, L)
end

----------------------------------------------------------------------------------------------------
-- The title: "STEAL A" in white, "SEED" in a yellow-green gradient, both chunky FredokaOne with a thick dark
-- outline over a dark copy a little lower (relief). On a SurfaceGui facing the camera, at the screen spot
-- (sx, sy in -1..1) of the shot, `w` of the screen's width wide.
----------------------------------------------------------------------------------------------------
local function title(parent: any, cam: any, shot: Shot, sx: number, sy: number, w: number)
	local d = 12 -- studs in front of the camera
	local t = math.tan(rad(shot.fov) / 2)
	local width = w * 2 * t * shot.aspect * d
	local height = width * 0.62
	local center = cam.Position + cam.LookVector * d + cam.RightVector * (sx * t * shot.aspect * d) + cam.UpVector * (sy * t * d)
	-- the Front face (-Z) toward the camera, text upright and reading left to right: X = screen left
	local cf = CFrame.fromMatrix(center, -cam.RightVector, cam.UpVector) * CFrame.Angles(0, 0, rad(-4))
	local board = new("Part", {
		Name = "TITULO", Size = Vector3.new(width, height, 0.05), CFrame = cf, Transparency = 1,
		Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false,
	}, parent)
	local gui = new("SurfaceGui", {
		Name = "Titulo", Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(1000, 620), LightInfluence = 0, Brightness = 1, AlwaysOnTop = true,
	}, board)
	local dark = rgb(28, 40, 22)
	local function line(text: string, y: number, h: number, fill: { any }?)
		for layer = 1, 2 do
			local shadow = layer == 1
			local label = new("TextLabel", {
				Name = if shadow then text .. "_Relevo" else text, Text = text, FontFace = FREDOKA, TextScaled = true,
				BackgroundTransparency = 1, TextColor3 = if shadow then dark else rgb(255, 255, 255),
				Size = UDim2.new(0.94, 0, h, 0), Position = UDim2.new(0.03, 0, y + (if shadow then 0.035 else 0), 0),
				ZIndex = layer,
			}, gui)
			new("UIStroke", { Color = dark, Thickness = 16, LineJoinMode = Enum.LineJoinMode.Round }, label)
			if fill and not shadow then
				local keys = {}
				for i, c in fill do
					table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#fill - 1), c))
				end
				new("UIGradient", { Color = ColorSequence.new(keys), Rotation = 90 }, label)
			end
		end
	end
	line("STEAL A", 0.02, 0.36, nil)
	line("SEED", 0.36, 0.6, { rgb(255, 240, 70), rgb(160, 235, 60), rgb(60, 190, 60) })
end

----------------------------------------------------------------------------------------------------
-- One place file
----------------------------------------------------------------------------------------------------
local function build(scene: Scene, kind: "Icon" | "Thumbnail"): any
	local shot = if kind == "Icon" then scene.icon else scene.thumb
	local game = Instance.new("DataModel")
	local ws = game:GetService("Workspace")
	-- the scene's frame: origin at scene.at, looking down the corridor (+X)
	local frame = lookAt(scene.at, scene.at + Vector3.new(1, 0, 0))
	local function w(p: any): any
		return frame * p
	end
	local root = new("Model", { Name = "CENA_" .. scene.key }, ws)

	-- the zone, cleared around the action (from behind the boss to behind the camera)
	local lo = w(Vector3.new(-26, 0, -26)):Min(w(Vector3.new(26, 0, 40)))
	local hi = w(Vector3.new(-26, 0, -26)):Max(w(Vector3.new(26, 0, 40)))
	zoneSlice(scene.zone, lo, hi).Parent = root

	-- the boss
	local guard, bones = boss(scene)
	local bt = scene.boss.turn
	place(guard, w(CFrame.new(scene.boss.pos) * lookAt(Vector3.zero, Vector3.new(-sin(bt), 0, cos(bt)))))
	guard.Parent = root

	-- the player: marker, stand-in and seed
	local pt = scene.player.turn
	local body = w(CFrame.new(scene.player.pos) * lookAt(Vector3.zero, Vector3.new(-sin(pt), 0, cos(pt))))
	local marker = new("Part", {
		Name = MARKER, Size = Vector3.new(2, 2, 1), CFrame = body * CFrame.new(0, HIP, 0), Transparency = 1,
		Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false,
	}, ws)
	marker:SetAttribute("Ajuda", "Seleciona o teu avatar e corre o comando do LEIA-ME.txt na Command Bar: ele vem para aqui, virado para a camara.")
	local figure = standIn()
	place(figure, body)
	figure.Parent = root
	local seed = seedModel(scene)
	place(seed, body * SEED_AT * CFrame.Angles(rad(-8), rad(25), 0))
	seed.Parent = root

	-- flowers
	local flowers = new("Folder", { Name = "Flores" }, root)
	local models = flowerModels(scene.zone)
	for i, f in FLOWERS do
		local m = models[(i - 1) % #models + 1]:Clone()
		place(m, w(CFrame.new(f[1], 0, f[2]) * CFrame.Angles(0, f[3], 0)))
		still(m)
		m.Parent = flowers
	end

	-- camera, key light and title
	local eye, at = w(shot.eye), w(shot.at)
	-- (Studio's edit camera turns to face Focus when it opens the place: Focus is the framing's target)
	local cam = new("Camera", { Name = "Camera", CFrame = lookAt(eye, at), Focus = CFrame.new(at), FieldOfView = shot.fov }, ws)
	ws.CurrentCamera = cam
	local key = new("Part", {
		Name = "LuzFrontal", Size = Vector3.new(1, 1, 1), Transparency = 1,
		CFrame = lookAt(eye + Vector3.new(0, 9, 0) + cam.CFrame.RightVector * 6, w(Vector3.new(0, 6, 0))),
		Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false,
	}, root)
	new("SpotLight", { Face = Enum.NormalId.Front, Angle = 75, Brightness = 2.5, Range = 60, Color = rgb(255, 246, 230), Shadows = false }, key)
	if kind == "Thumbnail" then
		title(root, cam.CFrame, shot, -0.5, 0.42, 0.44)
	end
	local focus = (w(scene.player.pos) - eye).Magnitude
	lighting(game, focus, (scene.player.pos - scene.boss.pos).Magnitude + 10)

	-- a note in the place itself
	new("StringValue", {
		Name = "LEIA-ME", Value = `{kind} {scene.key}: le o LEIA-ME.txt (pasta Thumbnails). Mete o teu avatar em `
			.. `{MARKER}, apaga {STANDIN} e tira o screenshot sem mexer na camara.`,
	}, ws)
	return game, bones
end

----------------------------------------------------------------------------------------------------
-- LEIA-ME.txt
----------------------------------------------------------------------------------------------------
-- The Command Bar line that moves the selected rig onto the marker and poses it (R15 or R6): arms up over
-- the head, mid-stride, leaning into the run. Each joint keeps its original C0 in an attribute, so running
-- it again gives the same pose.
local POSE_COMMAND = table.concat({
	'local m=game.Selection:Get()[1] if m and not m:IsA("Model") then m=m:FindFirstAncestorOfClass("Model") end',
	'local k=workspace:FindFirstChild("' .. MARKER .. '")',
	"if m and k then m:PivotTo(k.CFrame)",
	'local P={RightShoulder={2.9,-0.3},LeftShoulder={2.9,0.3},["Right Shoulder"]={2.9,-0.3},["Left Shoulder"]={2.9,0.3},'
		.. 'RightElbow={0.5,0},LeftElbow={0.5,0},RightHip={0.55,0},LeftHip={-0.45,0},["Right Hip"]={0.55,0},["Left Hip"]={-0.45,0},'
		.. "RightKnee={-0.4,0},LeftKnee={-0.9,0},Root={-0.12,0},RootJoint={-0.12,0}}",
	'for _,d in m:GetDescendants() do local a=d:IsA("Motor6D") and P[d.Name] if a then',
	'local o=d:GetAttribute("C0_original") or d.C0 d:SetAttribute("C0_original",o)',
	"d.C0=CFrame.new(o.Position)*CFrame.Angles(0,0,a[2])*CFrame.Angles(a[1],0,0)*o.Rotation end end",
	'print("Avatar no sitio e na pose!") else warn("Seleciona primeiro o teu avatar no Explorer") end',
}, " ")

local function readme(): string
	local lines = {
		"STEAL A SEED - CENAS PARA O ICONE E AS THUMBNAILS",
		"=================================================",
		"",
		"Nesta pasta ha 6 ficheiros do Roblox Studio, cada um com uma cena pronta a fotografar:",
		"  Icon_VoidDragon.rbxl   Icon_Gorilla.rbxl   Icon_Lumistag.rbxl       -> ICONE (quadrado 512x512)",
		"  Thumbnail_VoidDragon.rbxl   Thumbnail_Gorilla.rbxl   Thumbnail_Lumistag.rbxl  -> THUMBNAIL (1920x1080)",
		"Em cada um: o boss a correr atras de ti de boca aberta, a semente gigante a brilhar, flores e a zona dele.",
		"A camara ja esta no sitio certo. Nas thumbnails o titulo STEAL A SEED ja esta na cena.",
		"",
		"1) ABRIR",
		"   Duplo clique no ficheiro (ou Roblox Studio -> File -> Open from File...).",
		"   NAO mexas na camara (nada de botao direito do rato / WASD / roda) ate tirares a foto.",
		"   Se mexeste sem querer: fecha SEM gravar e abre outra vez o ficheiro.",
		"",
		"2) POR O TEU AVATAR",
		"   a) No Explorer, apaga o boneco de exemplo: Workspace -> CENA_... -> " .. STANDIN .. " (Delete).",
		"      (Ele so mostra a pose. Se quiseres, podes deixa-lo e tirar a foto assim.)",
		"   b) Separador Avatar -> Rig Builder -> \"My Avatar\" (o teu avatar)",
		"      ou \"Block Avatar\" (R15 ou R6). Aparece um modelo novo no Workspace.",
		"   c) Clica nesse modelo no Explorer para o selecionar.",
		"   d) View -> Command Bar. Cola esta linha toda e carrega Enter:",
		"",
		POSE_COMMAND,
		"",
		"      Ele vai para o sitio marcado (" .. MARKER .. "), virado para a camara,",
		"      com os bracos no ar a segurar a semente e as pernas a correr.",
		"   e) Se as maos nao tocarem bem na semente: seleciona " .. SEED_NAME .. " e sobe/desce com a",
		"      ferramenta Move (ou muda a Position Y em Properties). Tambem podes rodar os bracos a mao",
		"      com o Animation Editor (separador Avatar) se preferires outra pose.",
		"",
		"3) TIRAR A FOTO",
		"   - Esconde os paineis para a vista ficar grande (Explorer/Properties/Toolbox: fecha-os ou",
		"     maximiza a janela do Studio).",
		"   - View -> Screenshot (guarda em Imagens\\Roblox) ou Win+Shift+S e recorta a vista 3D.",
		"   - ICONE: recorta um QUADRADO a volta das personagens. Tamanho final 512x512.",
		"   - THUMBNAIL: recorta 16:9 (largo). Tamanho final 1920x1080. O titulo fica a esquerda",
		"     e as personagens a direita; se a vista for mais estreita, alarga a janela do Studio.",
		"   - Dica: as faiscas da semente mexem-se sozinhas; tira 2 ou 3 fotos e escolhe a melhor.",
		"",
		"4) POR NO JOGO",
		"   create.roblox.com -> Creations (Dashboard) -> o jogo Steal a Seed -> Places -> Configure",
		"   (ou: no jogo -> Configure -> Places / Thumbnails):",
		"   - Icon: carrega a imagem quadrada 512x512.",
		"   - Thumbnails: carrega as imagens 1920x1080 (podes por as 3, uma de cada boss).",
		"   A Roblox demora uns minutos a aprovar as imagens.",
		"",
		"Para refazer estas cenas (por exemplo depois de mudar um boss ou a semente), na pasta do jogo:",
		"   lune run tools/build_thumbnails.luau",
	}
	return table.concat(lines, "\r\n") .. "\r\n"
end

----------------------------------------------------------------------------------------------------
local outDir = process.args[1] or `{process.env.USERPROFILE or process.env.HOME or "."}/Desktop/Thumbnails`
if not fs.isDir(outDir) then
	fs.writeDir(outDir)
end
for _, scene in SCENES do
	for _, kind in { "Icon", "Thumbnail" } do
		local game = build(scene, kind :: any)
		local path = `{outDir}/{kind}_{scene.key}.rbxl`
		fs.writeFile(path, roblox.serializePlace(game))
		print(`{path}: {#game:GetService("Workspace"):GetDescendants()} instances`)
	end
end
fs.writeFile(`{outDir}/LEIA-ME.txt`, readme())
print(`{outDir}/LEIA-ME.txt`)
