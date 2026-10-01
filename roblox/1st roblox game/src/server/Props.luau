-- Primitive kit for the generated world: solid blocks, non-colliding decoration, ellipsoids, floor
-- overlays, lights, particle emitters, and a few reusable cartoon props (trees, flowers, lamps, fences).
-- Everything is anchored. Decoration never collides, never fires Touched and is skipped by raycasts,
-- so neither players, guards nor the camera snag on it.
local Props = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end
Props.part = part

-- Turns a part into pure decoration.
function Props.ghost(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	return p
end

-- Solid block (collides): floors, walls, fences.
function Props.box(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	return part({ Name = name, Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic, Parent = parent })
end

-- Non-colliding block.
function Props.deco(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Props.box(parent, name, size, cf, color, material)
	Props.ghost(p)
	return p
end

function Props.ball(parent: Instance, name: string, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	local p = part({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = CFrame.new(pos),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	Props.ghost(p)
	return p
end

-- Upright cylinder (cylinders run along local X, so rotate them).
function Props.cylinder(parent: Instance, name: string, height: number, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	local p = part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	Props.ghost(p)
	return p
end

-- Cylinder between two points (branches, bones, arms).
function Props.rod(parent: Instance, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0) -- local X along a->b
	local p = part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(len, diameter, diameter),
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	Props.ghost(p)
	return p
end

-- Ellipsoid of any proportions (dunes, leaves, canopies, snow drifts): a block with a sphere mesh.
function Props.blob(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Props.deco(parent, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Thin floor overlay lying on `y` (paths, stripes, cracks, puddles). Casts no shadow.
function Props.flat(parent: Instance, name: string, sizeX: number, sizeZ: number, pos: Vector3, color: Color3, material: Enum.Material?, yaw: number?, thickness: number?): Part
	local t = thickness or 0.2
	local p = Props.deco(parent, name, Vector3.new(sizeX, t, sizeZ),
		CFrame.new(pos + Vector3.new(0, t / 2, 0)) * CFrame.Angles(0, yaw or 0, 0), color, material)
	p.CastShadow = false
	return p
end

-- Flat round overlay (puddles, rugs, craters).
function Props.disc(parent: Instance, name: string, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?, thickness: number?): Part
	local t = thickness or 0.2
	local p = Props.cylinder(parent, name, t, diameter, pos + Vector3.new(0, t / 2, 0), color, material)
	p.CastShadow = false
	return p
end

function Props.light(p: BasePart, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = p
	return light
end

export type EmitterSpec = {
	texture: string?,
	color: ColorSequence | Color3,
	rate: number,
	lifetime: NumberRange,
	speed: NumberRange,
	size: NumberSequence,
	transparency: NumberSequence?,
	direction: Enum.NormalId?,
	acceleration: Vector3?,
	spread: Vector2?,
	rotation: NumberRange?,
	rotSpeed: NumberRange?,
	lightEmission: number?,
	drag: number?,
}

Props.TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	spark = "rbxasset://textures/particles/fire_sparks_main.dds",
}

-- A ParticleEmitter on `host`; particles spawn throughout the host's box.
function Props.emitOn(host: BasePart, spec: EmitterSpec): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = spec.texture or Props.TEX.sparkle
	e.Color = if typeof(spec.color) == "Color3" then ColorSequence.new(spec.color :: Color3) else spec.color :: ColorSequence
	e.Rate = spec.rate
	e.Lifetime = spec.lifetime
	e.Speed = spec.speed
	e.Size = spec.size
	e.Transparency = spec.transparency or NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.EmissionDirection = spec.direction or Enum.NormalId.Top
	e.Acceleration = spec.acceleration or Vector3.zero
	e.SpreadAngle = spec.spread or Vector2.new(20, 20)
	e.Rotation = spec.rotation or NumberRange.new(0, 360)
	e.RotSpeed = spec.rotSpeed or NumberRange.new(0)
	e.LightEmission = spec.lightEmission or 0
	e.Drag = spec.drag or 0
	e.Parent = host
	return e
end

-- An invisible emitter volume (e.g. a slab over the corridor that snows).
function Props.emitter(parent: Instance, name: string, size: Vector3, pos: Vector3, spec: EmitterSpec): Part
	local host = Props.deco(parent, name, size, CFrame.new(pos), Color3.new(1, 1, 1))
	host.Transparency = 1
	host.CastShadow = false
	Props.emitOn(host, spec)
	return host
end

----------------------------------------------------------------------------------------------------
-- Reusable cartoon props. `pos` is the ground point under the prop.
----------------------------------------------------------------------------------------------------
Props.WOOD = Color3.fromRGB(150, 98, 58)
Props.WOOD_LIGHT = Color3.fromRGB(196, 138, 82)

function Props.roundTree(parent: Instance, pos: Vector3, rng: Random, leaf: Color3, height: number?)
	local h = height or rng:NextNumber(9, 14)
	Props.cylinder(parent, "Trunk", h, 1.8, pos + Vector3.new(0, h / 2, 0), Props.WOOD, Enum.Material.Wood)
	local r = rng:NextNumber(9, 12)
	Props.ball(parent, "Canopy", r, pos + Vector3.new(0, h + r * 0.2, 0), leaf, Enum.Material.Grass)
	Props.ball(parent, "Canopy", r * 0.7, pos + Vector3.new(r * 0.35, h + r * 0.55, rng:NextNumber(-2, 2)), leaf:Lerp(Color3.new(1, 1, 0.6), 0.15), Enum.Material.Grass)
end

function Props.flower(parent: Instance, pos: Vector3, petal: Color3, height: number?)
	local h = height or 1.6
	Props.cylinder(parent, "Stem", h, 0.3, pos + Vector3.new(0, h / 2, 0), Color3.fromRGB(70, 170, 60)).CastShadow = false
	local head = Props.blob(parent, "Flower", Vector3.new(1.6, 0.7, 1.6), CFrame.new(pos + Vector3.new(0, h + 0.2, 0)), petal)
	head.CastShadow = false
end

function Props.bush(parent: Instance, pos: Vector3, size: number, color: Color3)
	Props.blob(parent, "Bush", Vector3.new(size * 1.3, size, size), CFrame.new(pos + Vector3.new(0, size * 0.35, 0)), color, Enum.Material.Grass)
end

function Props.rock(parent: Instance, pos: Vector3, size: Vector3, color: Color3, material: Enum.Material?, yaw: number?)
	Props.blob(parent, "Rock", size, CFrame.new(pos + Vector3.new(0, size.Y * 0.3, 0)) * CFrame.Angles(0, yaw or 0, 0), color, material or Enum.Material.Slate)
end

function Props.lamp(parent: Instance, pos: Vector3, glow: Color3, height: number?): Part
	local h = height or 9
	Props.cylinder(parent, "LampPost", h, 0.6, pos + Vector3.new(0, h / 2, 0), Color3.fromRGB(45, 45, 55), Enum.Material.Metal)
	local head = Props.ball(parent, "LampHead", 1.8, pos + Vector3.new(0, h + 0.6, 0), glow, Enum.Material.Neon)
	head.CastShadow = false
	Props.light(head, glow, 22, 1.4)
	return head
end

-- A wooden fence from a to b (on the ground at a.Y): posts every ~`spacing` studs and two rails.
-- Solid, like a real fence; used around plots, never inside the corridor.
function Props.fence(parent: Instance, a: Vector3, b: Vector3, height: number, spacing: number, post: Color3?, rail: Color3?)
	local postColor, railColor = post or Props.WOOD, rail or Props.WOOD_LIGHT
	local delta = b - a
	local len = delta.Magnitude
	local n = math.max(1, math.round(len / spacing))
	local dir = delta.Unit
	for i = 0, n do
		local p = a + dir * (len * i / n)
		Props.box(parent, "FencePost", Vector3.new(1, height + 0.6, 1), CFrame.new(p + Vector3.new(0, (height + 0.6) / 2, 0)), postColor, Enum.Material.Wood)
	end
	local rot = CFrame.lookAt(Vector3.zero, dir) -- local -Z along the run
	for _, y in { height * 0.38, height * 0.82 } do
		Props.box(parent, "FenceRail", Vector3.new(0.5, 0.8, len), CFrame.new((a + b) / 2 + Vector3.new(0, y, 0)) * rot, railColor, Enum.Material.WoodPlanks)
	end
end

return Props
