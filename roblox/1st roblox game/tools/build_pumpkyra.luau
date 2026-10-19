-- Pumpkyra, a Halloween plant of our own (owner 2026-10-19: "one halloween plant of your own with maybe a
-- pumpkin as inspiration", at the level of the Legendary designs in assets/Creature_*.rbxm): a twisting dark
-- vine rising from a haunted mound, jagged pumpkin leaves with glowing veins, two curling tendrils with little
-- pumpkin buds, and on top a ribbed jack-o'-lantern blossom with a glowing carved face, a crown of purple
-- flame petals, embers, green spores and purple wisps. About 9 studs tall like the Legendaries, built only
-- from Parts (no uploads), its front (the face) toward -Z like the other plants, the ground under it at y 0.
-- Writes, into the output folder (default <your Desktop>/Thumbnails):
--   * Pumpkyra.rbxm: the model alone, ready to drop into a Creature_*.rbxm rarity folder;
--   * PlantPreview_Pumpkyra.rbxl: a Halloween night with it at game size next to the Pyronis (for scale)
--     and a giant one behind, the camera already framed.
-- Deterministic. Run from the game folder:
--   lune run tools/build_pumpkyra.luau [output folder]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance, Vector3, CFrame, Color3 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3
local Vector2, Enum = roblox.Vector2, roblox.Enum
local ColorSequence, ColorSequenceKeypoint = roblox.ColorSequence, roblox.ColorSequenceKeypoint
local NumberSequence, NumberSequenceKeypoint, NumberRange = roblox.NumberSequence, roblox.NumberSequenceKeypoint, roblox.NumberRange
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi

local function rgb(r: number, g: number, b: number): any
	return Color3.fromRGB(r, g, b)
end
local V = Vector3.new

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

local ORANGE = rgb(255, 125, 20)
local ORANGE_DARK = rgb(225, 92, 10)
local GLOW = rgb(255, 205, 70) -- the carved face's candle light
local PURPLE = rgb(150, 60, 230)
local PURPLE_DARK = rgb(70, 30, 105)
local GREEN = rgb(140, 255, 60)
local VINE = rgb(48, 58, 38)
local VINE_DARK = rgb(30, 28, 36)
local LEAF = rgb(78, 130, 52)
local SOIL = rgb(52, 34, 48)
local NEON, SMOOTH = Enum.Material.Neon, Enum.Material.SmoothPlastic

----------------------------------------------------------------------------------------------------
-- Building blocks
----------------------------------------------------------------------------------------------------
local model: any

local function part(name: string, size: any, cf: any, color: any, material: any?, class: string?): any
	return new(class or "Part", {
		Name = name, Size = size, CFrame = cf, Color = color, Material = material or SMOOTH,
		Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
		TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
	}, model)
end

local function ellipsoid(name: string, size: any, cf: any, color: any, material: any?): any
	local p = part(name, size, cf, color, material)
	new("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, p)
	return p
end

-- A frame at `pos` whose X axis points along `dir`.
local function along(pos: any, dir: any): any
	local x = dir.Unit
	local up = if math.abs(x.Y) > 0.95 then V(1, 0, 0) else V(0, 1, 0)
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(pos, x, y, z)
end

-- A cylinder from `a` to `b`, `d` thick (a Part's cylinder runs along its X axis).
local function stalk(name: string, a: any, b: any, d: number, color: any, material: any?): any
	local p = part(name, V((b - a).Magnitude + d * 0.4, d, d), along((a + b) / 2, b - a), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A triangle (two mirrored wedges) standing in the plane facing -Z at `cf`: `w` wide, `h` tall, its point up.
local function triangle(name: string, cf: any, w: number, h: number, t: number, color: any, material: any?)
	for side = -1, 1, 2 do
		-- a WedgePart is full height at its back (+Z) and slopes down to its front (-Z): turned so its back
		-- is the triangle's middle and its slope faces out along X, its thickness along Z
		part(name, V(t, h, w / 2), cf * CFrame.new(side * w / 4, 0, 0) * CFrame.Angles(0, -side * pi / 2, 0), color, material, "WedgePart")
	end
end

local function emitter(parent: any, name: string, props: { [string]: any })
	local base = {
		Name = name, LightEmission = 1, Brightness = 2, LightInfluence = 0,
		EmissionDirection = Enum.NormalId.Top,
	}
	for k, v in props do
		base[k] = v
	end
	return new("ParticleEmitter", base, parent)
end

local function seq(...: any): any
	local list = { ... }
	local keys = {}
	for i, c in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#list - 1), c))
	end
	return ColorSequence.new(keys)
end

local function nums(...: number): any
	local list = { ... }
	local keys = {}
	for i = 1, #list, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(list[i], list[i + 1]))
	end
	return NumberSequence.new(keys)
end

----------------------------------------------------------------------------------------------------
-- Pumpkyra
----------------------------------------------------------------------------------------------------
local HEAD = V(0, 7.15, 0) -- the jack-o'-lantern's centre
local HEAD_W, HEAD_H = 3.0, 2.25

local function build(): any
	model = new("Model", { Name = "Pumpkyra" })

	-- the haunted mound, and a ring of purple glow in the soil
	local mound = ellipsoid("Mound", V(3.4, 0.8, 3.4), CFrame.new(0, 0.1, 0), SOIL)
	model.PrimaryPart = mound
	local ring = part("SoilGlow", V(0.06, 3.0, 3.0), CFrame.new(0, 0.33, 0) * CFrame.Angles(0, 0, pi / 2), PURPLE, NEON)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.55
	ring.CastShadow = false

	-- the vine: six twisting segments, thinner as they rise, thorns at the joints
	local points = {}
	for i = 0, 6 do
		local t = i / 6
		table.insert(points, V(0.42 * sin(i * 1.15) * (1 - t * 0.6), 0.25 + t * (HEAD.Y - HEAD_H * 0.45 - 0.25), 0.36 * cos(i * 1.35 + 0.4) * (1 - t * 0.6)))
	end
	for i = 1, 6 do
		local d = 0.62 - i * 0.045
		stalk("Vine", points[i], points[i + 1], d, if i % 2 == 0 then VINE else VINE:Lerp(PURPLE_DARK, 0.35))
		if i >= 2 and i <= 5 then
			local out = V(cos(i * 2.3), 0, sin(i * 2.3))
			local at = points[i] + out * d * 0.45
			part("Thorn", V(0.12, 0.42, 0.22), along(at, out + V(0, 0.6, 0)) * CFrame.Angles(0, 0, -pi / 2), VINE_DARK, SMOOTH, "WedgePart")
		end
	end

	-- three jagged pumpkin leaves low on the vine, a glowing green vein on each
	for i, a in { 0.35, 2.45, 4.35 } do
		local dir = V(cos(a), 0, sin(a))
		local at = V(0, 1.0 + i * 0.45, 0) + dir * 1.15
		local cf = CFrame.new(at) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, rad(18 + i * 4))
		local tint = LEAF:Lerp(PURPLE_DARK, 0.2 * (i - 1))
		ellipsoid("Leaf", V(2.6, 0.14, 1.7), cf, tint)
		for lobe = -1, 1, 2 do -- (the side lobes of a pumpkin leaf)
			ellipsoid("LeafLobe", V(1.3, 0.12, 0.9), cf * CFrame.new(-0.15, -0.01, lobe * 0.7) * CFrame.Angles(0, lobe * rad(40), 0), tint)
		end
		part("LeafVein", V(2.2, 0.06, 0.08), cf * CFrame.new(0.1, 0.07, 0), GREEN, NEON).CastShadow = false
	end

	-- two tendrils curling out and down, each ending in a little pumpkin bud with a green glow
	for side = -1, 1, 2 do
		local from = points[if side < 0 then 4 else 5]
		local p = from
		local tips = { V(0.75, 0.45, -0.2), V(0.6, 0.05, -0.15), V(0.25, -0.55, 0) }
		for _, step in tips do
			local q = p + V(step.X * side, step.Y, step.Z)
			stalk("Tendril", p, q, 0.16, VINE)
			p = q
		end
		local bud = ellipsoid("Bud", V(0.75, 0.6, 0.75), CFrame.new(p + V(0, -0.3, 0)), ORANGE)
		part("BudStem", V(0.1, 0.18, 0.1), CFrame.new(p + V(0, 0.02, 0)), VINE)
		local spark = part("BudGlow", V(0.22, 0.22, 0.22), CFrame.new(p + V(0, -0.3, -0.34)), GREEN, NEON)
		spark.Shape = Enum.PartType.Ball
		spark.CastShadow = false
		new("PointLight", { Color = GREEN, Brightness = 1.2, Range = 4, Shadows = false }, bud)
	end

	-- the jack-o'-lantern blossom: a core and six ribbed lobes around it
	local core = ellipsoid("Pumpkin", V(HEAD_W * 0.82, HEAD_H, HEAD_W * 0.82), CFrame.new(HEAD), ORANGE)
	for i = 0, 5 do
		local a = i * pi / 3 + pi / 6
		local out = V(cos(a), 0, sin(a))
		ellipsoid("PumpkinRib", V(HEAD_W * 0.56, HEAD_H * 0.94, HEAD_W * 0.62), CFrame.new(HEAD + out * HEAD_W * 0.24) * CFrame.Angles(0, -a, 0), if i % 2 == 0 then ORANGE_DARK else ORANGE)
	end
	-- the carved face toward -Z: triangle eyes, a triangle nose and a jagged grin, all glowing
	local front = HEAD.Z - HEAD_W * 0.45 -- (the face parts are thick: their backs sink into the curved front)
	local face = CFrame.new(HEAD.X, HEAD.Y, front)
	for side = -1, 1, 2 do
		triangle("Eye", face * CFrame.new(side * 0.5, 0.32, 0) * CFrame.Angles(0, 0, side * rad(-12)), 0.58, 0.5, 0.45, GLOW, NEON)
	end
	triangle("Nose", face * CFrame.new(0, -0.02, 0.05), 0.3, 0.24, 0.45, GLOW, NEON)
	part("Grin", V(1.3, 0.24, 0.5), face * CFrame.new(0, -0.42, 0.1), GLOW, NEON)
	for i, x in { -0.45, -0.15, 0.15, 0.45 } do
		local up = i % 2 == 0
		part("Fang", V(0.16, 0.16, 0.5), face * CFrame.new(x, if up then -0.3 else -0.54, 0.05) * CFrame.Angles(0, 0, pi / 4), if up then ORANGE else ORANGE_DARK)
	end
	-- the candle inside: light, and flames flickering out of the eyes
	local candle = part("Candle", V(0.4, 0.4, 0.4), CFrame.new(HEAD + V(0, 0.1, -0.4)), GLOW)
	candle.Transparency = 1
	candle.CastShadow = false
	new("PointLight", { Color = rgb(255, 150, 40), Brightness = 2.6, Range = 13, Shadows = false }, candle)
	for side = -1, 1, 2 do
		local eye = new("Attachment", { Name = "EyeFlame", CFrame = core.CFrame:Inverse() * (face * CFrame.new(side * 0.5, 0.42, -0.05)) }, core)
		emitter(eye, "EyeFire", {
			Texture = "rbxasset://textures/particles/fire_main.dds", Color = seq(rgb(255, 240, 150), ORANGE, PURPLE),
			Size = nums(0, 0.35, 1, 0.05), Transparency = nums(0, 0.25, 1, 1),
			Lifetime = NumberRange.new(0.35, 0.6), Rate = 18, Speed = NumberRange.new(0.6, 1.2),
			SpreadAngle = Vector2.new(15, 15), RotSpeed = NumberRange.new(-90, 90),
		})
	end

	-- the crown: five purple flame petals opening around the top, a curled stem and a little leaf
	local top = HEAD + V(0, HEAD_H * 0.42, 0)
	for i = 0, 4 do
		local a = i * 2 * pi / 5 + pi / 10
		local out = V(cos(a), 0, sin(a))
		local at = top + out * 0.62 + V(0, 0.5, 0)
		local petal = part("FlamePetal", V(0.16, 1.25, 0.62), CFrame.new(at) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, rad(-24)) * CFrame.Angles(0, pi / 2, 0), PURPLE, NEON, "WedgePart")
		petal.Transparency = 0.1
		petal.CastShadow = false
	end
	stalk("Stem", top + V(0, -0.05, 0), top + V(0.12, 0.55, 0.05), 0.3, VINE)
	stalk("StemCurl", top + V(0.12, 0.55, 0.05), top + V(0.5, 0.78, 0.1), 0.2, VINE)
	ellipsoid("StemLeaf", V(0.75, 0.08, 0.42), CFrame.new(top + V(-0.3, 0.45, 0.1)) * CFrame.Angles(0, 0.3, rad(-25)), LEAF)

	-- embers rising from the crown, green spores around the head, purple wisps from the mound, two ghostly
	-- ribbons spiralling up the vine
	local crown = new("Attachment", { Name = "Crown", CFrame = core.CFrame:Inverse() * CFrame.new(top + V(0, 0.6, 0)) }, core)
	emitter(crown, "Embers", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = seq(rgb(255, 220, 120), ORANGE, PURPLE),
		Size = nums(0, 0.3, 1, 0), Transparency = nums(0, 0, 1, 1),
		Lifetime = NumberRange.new(1.2, 2.2), Rate = 14, Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(35, 35), Acceleration = V(0, 1, 0),
	})
	emitter(core, "Spores", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = seq(rgb(210, 255, 150), GREEN),
		Size = nums(0, 0.18, 0.5, 0.26, 1, 0), Transparency = nums(0, 0.2, 1, 1),
		Lifetime = NumberRange.new(1.5, 2.5), Rate = 8, Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180), Shape = Enum.ParticleEmitterShape.Sphere,
	})
	emitter(mound, "Wisps", {
		Texture = "rbxasset://textures/particles/smoke_main.dds", Color = seq(PURPLE, PURPLE_DARK),
		Size = nums(0, 0.8, 1, 2.2), Transparency = nums(0, 0.75, 0.4, 0.6, 1, 1),
		Lifetime = NumberRange.new(2, 3.5), Rate = 4, Speed = NumberRange.new(0.3, 0.7),
		SpreadAngle = Vector2.new(60, 60), RotSpeed = NumberRange.new(-20, 20), LightEmission = 0.6,
	})
	for side = -1, 1, 2 do
		local a0 = new("Attachment", { Name = "RibbonBase", CFrame = mound.CFrame:Inverse() * CFrame.new(side * 0.9, 0.35, 0) }, mound)
		local a1 = new("Attachment", { Name = "RibbonTop", CFrame = core.CFrame:Inverse() * CFrame.new(HEAD + V(side * 0.7, -0.7, 0)) }, core)
		new("Beam", {
			Name = "GhostRibbon", Attachment0 = a0, Attachment1 = a1, Color = seq(PURPLE, GREEN),
			Transparency = nums(0, 0.8, 0.5, 0.35, 1, 0.8), Width0 = 0.25, Width1 = 0.12,
			CurveSize0 = side * 2.2, CurveSize1 = side * -1.6, Segments = 24, LightEmission = 1, FaceCamera = true,
		}, a0)
	end

	model.WorldPivot = CFrame.identity
	return model
end

----------------------------------------------------------------------------------------------------
-- The preview place
----------------------------------------------------------------------------------------------------
local function moved(m: any, cf: any, k: number?): any
	local s = k or 1
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size *= s
			d.CFrame = cf * (CFrame.new(d.CFrame.Position * s) * d.CFrame.Rotation)
		elseif d:IsA("Attachment") and s ~= 1 then
			d.CFrame = CFrame.new(d.CFrame.Position * s) * d.CFrame.Rotation
		elseif d:IsA("Beam") then
			d.Width0 *= s
			d.Width1 *= s
			d.CurveSize0 *= s
			d.CurveSize1 *= s
		elseif d:IsA("ParticleEmitter") then
			local keys = {}
			for _, p in d.Size.Keypoints do
				table.insert(keys, NumberSequenceKeypoint.new(p.Time, p.Value * s, p.Envelope * s))
			end
			d.Size = NumberSequence.new(keys)
		elseif d:IsA("PointLight") then
			d.Range = math.min(d.Range * s, 60)
		end
	end
	m.WorldPivot = cf
	return m
end

local function preview(plant: any): any
	local game = Instance.new("DataModel")
	local ws = game:GetService("Workspace")
	local ground = new("Part", {
		Name = "Chao", Size = V(160, 1, 160), CFrame = CFrame.new(0, -0.5, 0), Color = rgb(58, 74, 50),
		Material = Enum.Material.Grass, Anchored = true,
	}, ws)
	ground.TopSurface = Enum.SurfaceType.Smooth

	-- facing the camera (+Z): the game size one in front, the Pyronis beside it, a giant one behind
	local turn = CFrame.Angles(0, pi, 0)
	moved(plant:Clone(), CFrame.new(0, 0, 0) * turn).Parent = ws
	local giant = moved(plant:Clone(), CFrame.new(9, 0, -16) * turn * CFrame.Angles(0, -0.35, 0), 2.6)
	giant.Name = "Pumpkyra_Gigante"
	giant.Parent = ws
	local lotus = roblox.deserializeModel(fs.readFile("assets/Creature_LotusWyrm.rbxm"))[1]
	local pyronis = lotus.Legendary.Pyronis:Clone()
	local lo, sum, n = math.huge, V(0, 0, 0), 0
	for _, d in pyronis:GetDescendants() do
		if d:IsA("BasePart") then
			lo = math.min(lo, d.CFrame.Position.Y - d.Size.Y / 2)
			sum += d.CFrame.Position
			n += 1
		end
	end
	local pivot = CFrame.new(sum / n)
	for _, d in pyronis:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CFrame = CFrame.new(-5.5 - pivot.Position.X, -lo, -pivot.Position.Z) * d.CFrame
		end
	end
	pyronis.Name = "Pyronis_ParaComparar"
	pyronis.Parent = ws

	local L = game:GetService("Lighting")
	L.Technology = Enum.Technology.Future
	L.ClockTime = 0
	L.Brightness = 1.5
	L.Ambient = rgb(80, 50, 120)
	L.OutdoorAmbient = rgb(125, 85, 165)
	L.ColorShift_Top = rgb(255, 160, 80)
	L.ExposureCompensation = 0.4
	L.GlobalShadows = true
	new("Sky", { StarCount = 3000, MoonAngularSize = 14 }, L)
	new("Atmosphere", { Density = 0.3, Haze = 1.2, Color = rgb(120, 70, 170), Decay = rgb(55, 20, 85) }, L)
	new("BloomEffect", { Intensity = 0.8, Size = 26, Threshold = 1.2 }, L)
	new("ColorCorrectionEffect", { Saturation = 0.3, Contrast = 0.15, TintColor = rgb(240, 225, 255) }, L)

	local eye, at = V(1.5, 6.5, 17), V(0.5, 5, 0)
	local look = (at - eye).Unit
	local right = look:Cross(V(0, 1, 0)).Unit
	local cam = new("Camera", {
		Name = "Camera", CFrame = CFrame.fromMatrix(eye, right, right:Cross(look).Unit, -look),
		Focus = CFrame.new(at), FieldOfView = 50,
	}, ws)
	ws.CurrentCamera = cam
	local key = new("Part", {
		Name = "LuzFrontal", Size = V(1, 1, 1), Transparency = 1, CFrame = CFrame.new(eye + V(4, 6, 0)),
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
	}, ws)
	new("PointLight", { Brightness = 1.2, Range = 40, Color = rgb(255, 235, 220), Shadows = false }, key)
	return game
end

-- The Blender Pumpkyra (tools/blender/pumpkyra.py, uploaded with tools/blender/roblox_model.mjs), as Roblox
-- imported it: its MeshParts made still, the glow inside the pumpkin Neon, a candle light, flames from the
-- eyes, embers from the crown, spores round the head and purple wisps from the mound; its pivot on the ground.
local function finish(model: any): any
	local byName = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			byName[d.Name] = d
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	local core, petals, mound = byName.PumpkinGlow, byName.Petals, byName.Mound
	core.Material = NEON
	core.Color = rgb(255, 175, 50)
	core.CastShadow = false
	new("PointLight", { Color = rgb(255, 150, 40), Brightness = 3, Range = 14, Shadows = false }, core)
	local head = core.CFrame.Position
	for side = -1, 1, 2 do
		local eye = new("Attachment", { Name = "EyeFlame", CFrame = core.CFrame:Inverse() * CFrame.new(head + V(side * 0.6, 0.45, -1.35)) }, core)
		emitter(eye, "EyeFire", {
			Texture = "rbxasset://textures/particles/fire_main.dds", Color = seq(rgb(255, 240, 150), ORANGE, PURPLE),
			Size = nums(0, 0.35, 1, 0.05), Transparency = nums(0, 0.3, 1, 1),
			Lifetime = NumberRange.new(0.35, 0.6), Rate = 14, Speed = NumberRange.new(0.6, 1.2),
			SpreadAngle = Vector2.new(15, 15), RotSpeed = NumberRange.new(-90, 90),
		})
	end
	local crown = new("Attachment", { Name = "Crown", CFrame = petals.CFrame:Inverse() * CFrame.new(head + V(0, 2.2, 0)) }, petals)
	emitter(crown, "Embers", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = seq(rgb(255, 220, 120), ORANGE, PURPLE),
		Size = nums(0, 0.3, 1, 0), Transparency = nums(0, 0, 1, 1),
		Lifetime = NumberRange.new(1.2, 2.2), Rate = 14, Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(35, 35), Acceleration = V(0, 1, 0),
	})
	emitter(core, "Spores", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = seq(rgb(210, 255, 150), GREEN),
		Size = nums(0, 0.18, 0.5, 0.26, 1, 0), Transparency = nums(0, 0.2, 1, 1),
		Lifetime = NumberRange.new(1.5, 2.5), Rate = 8, Speed = NumberRange.new(1.5, 2.5),
		SpreadAngle = Vector2.new(180, 180),
	})
	emitter(mound, "Wisps", {
		Texture = "rbxasset://textures/particles/smoke_main.dds", Color = seq(PURPLE, PURPLE_DARK),
		Size = nums(0, 0.8, 1, 2.2), Transparency = nums(0, 0.75, 0.4, 0.6, 1, 1),
		Lifetime = NumberRange.new(2, 3.5), Rate = 4, Speed = NumberRange.new(0.3, 0.7),
		SpreadAngle = Vector2.new(60, 60), RotSpeed = NumberRange.new(-20, 20), LightEmission = 0.6,
	})
	model.PrimaryPart = mound
	model.WorldPivot = CFrame.identity
	return model
end

-- With a second argument (the imported model's .rbxm), the Blender version; else the Parts one.
local plant = if process.args[2]
	then finish(roblox.deserializeModel(fs.readFile(process.args[2]))[1])
	else build()
local count = 0
for _, d in plant:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
local outDir = process.args[1] or `{process.env.USERPROFILE or process.env.HOME or "."}/Desktop/Thumbnails`
if not fs.isDir(outDir) then
	fs.writeDir(outDir)
end
fs.writeFile(`{outDir}/Pumpkyra.rbxm`, roblox.serializeModel({ plant }))
fs.writeFile(`{outDir}/PlantPreview_Pumpkyra.rbxl`, roblox.serializePlace(preview(plant)))
print(`{outDir}/Pumpkyra.rbxm: {count} parts`)
print(`{outDir}/PlantPreview_Pumpkyra.rbxl`)
