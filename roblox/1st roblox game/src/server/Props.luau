-- Primitive kit for the generated world: solid blocks, non-colliding decoration, ellipsoids, floor
-- overlays, lights, particle emitters, and a few reusable cartoon props (trees, flowers, lamps, fences).
-- Only clean cartoony materials: SmoothPlastic (the default), studded Plastic (Props.studs), Neon for
-- glow and Glass for water and crystals; never the realistic ones (Assets.REALISTIC).
-- Everything is anchored. Decoration never collides, never fires Touched and is skipped by raycasts,
-- so neither players, guards nor the camera snag on it.
--
-- The reusable props are asset slots (see Assets): each is a group Model that a drop-in model from the
-- assets folder can replace. Pass `slot = false` to build one untagged, inside a bigger piece.
local Assets = require(script.Parent:WaitForChild("Assets"))

local Props = {}

-- A CFrame at `pos` looking at `target`, like CFrame.lookAt. Built with fromMatrix because the map is
-- baked under Lune, whose CFrame.lookAt points the wrong way for most directions.
function Props.lookAt(pos: Vector3, target: Vector3): CFrame
	local look = (target - pos).Unit
	local right = look:Cross(Vector3.yAxis)
	right = if right.Magnitude < 1e-3 then Vector3.xAxis else right.Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look))
end

type Slot = string | false | nil
local function slotOr(slot: Slot, default: string): string | false
	return if slot == nil then default else slot
end

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

-- The classic studded Roblox plastic on the given faces (default: the top). The map's base look.
function Props.studs<T>(p: T, faces: { string }?): T
	(p :: any).Material = Enum.Material.Plastic
	for _, face in faces or { "TopSurface" } do
		(p :: any)[face] = Enum.SurfaceType.Studs
	end
	return p
end

-- Non-colliding block.
function Props.deco(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Props.box(parent, name, size, cf, color, material)
	Props.ghost(p)
	return p
end

-- Every face but the bottom one: the corridor's props are studded all over, like its floor and walls
-- (owner playtest: everything in the same classic studded plastic).
Props.STUD_FACES = { "TopSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" }

-- A non-colliding block in studded plastic on every visible face: what the corridor's props are built of.
-- Small bits cast no shadow (cheaper on mobile, and their shadows are only specks).
function Props.block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Props.studs(Props.deco(parent, name, size, cf, color), Props.STUD_FACES)
	if size.X * size.Y * size.Z < 4 then
		p.CastShadow = false
	end
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
	local cf = Props.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0) -- local X along a->b
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

----------------------------------------------------------------------------------------------------
-- Level ground (owner playtest: steps and z-fighting between floor pieces). Every walkable surface of the
-- map (lawn, walkway, paths, plot ground, beds, entrance tiles, plaza, zone floors) has its top at the
-- ground level, and its pieces TILE: they meet edge to edge, never overlapping on the same plane. A
-- checker is both colours as separate tiles side by side (not light tiles laid over a dark floor), on a
-- slab sunk TILE_THICKNESS below the ground level.
----------------------------------------------------------------------------------------------------
Props.TILE_THICKNESS = 0.2

export type Rect = { number } -- { x0, x1, z0, z1 } in world studs, axis-aligned

-- What is left of rectangle `r` once every rectangle in `holes` is cut out of it: a few rectangles that
-- tile the rest exactly (none overlapping).
function Props.subtract(r: Rect, holes: { Rect }): { Rect }
	local eps = 1e-3
	local pieces = { r }
	for _, h in holes do
		local nextPieces = {}
		for _, p in pieces do
			if h[1] < p[2] - eps and h[2] > p[1] + eps and h[3] < p[4] - eps and h[4] > p[3] + eps then
				local mx0, mx1 = math.max(p[1], h[1]), math.min(p[2], h[2])
				for _, q in { { p[1], h[1], p[3], p[4] }, { h[2], p[2], p[3], p[4] }, { mx0, mx1, p[3], h[3] }, { mx0, mx1, h[4], p[4] } } do
					if q[2] - q[1] > eps and q[4] - q[3] > eps then
						table.insert(nextPieces, q)
					end
				end
			else
				table.insert(nextPieces, p)
			end
		end
		pieces = nextPieces
	end
	return pieces
end

-- A solid floor tile over rectangle `r`, its top at `top`, TILE_THICKNESS thick (or `thickness`).
function Props.tile(parent: Instance, name: string, r: Rect, top: number, color: Color3, thickness: number?): Part
	local t = thickness or Props.TILE_THICKNESS
	local p = Props.box(parent, name, Vector3.new(r[2] - r[1], t, r[4] - r[3]), CFrame.new((r[1] + r[2]) / 2, top - t / 2, (r[3] + r[4]) / 2), color)
	Props.studs(p)
	p.CastShadow = false
	return p
end

-- A level checker over rectangle `r`: cells `cellX` x `cellZ` studs counted from its -X/-Z corner,
-- `light` where (column + row) is even and `dark` where it is odd, each a solid studded tile with its top
-- at `top`. Whatever lies in `holes` is left out (cells there are cut to fit around it). Returns the tiles.
function Props.checker(parent: Instance, name: string, r: Rect, cellX: number, cellZ: number, top: number,
	light: Color3, dark: Color3, holes: { Rect }?): { Part }
	local out = {}
	for i = 0, math.ceil((r[2] - r[1]) / cellX - 1e-6) - 1 do
		for j = 0, math.ceil((r[4] - r[3]) / cellZ - 1e-6) - 1 do
			local cell = { r[1] + i * cellX, math.min(r[1] + (i + 1) * cellX, r[2]), r[3] + j * cellZ, math.min(r[3] + (j + 1) * cellZ, r[4]) }
			for _, piece in Props.subtract(cell, holes or {}) do
				table.insert(out, Props.tile(parent, name, piece, top, if (i + j) % 2 == 0 then light else dark))
			end
		end
	end
	return out
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
	lightInfluence: number?, -- 0: as bright at night as by day (fire, glow)
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
	if spec.lightInfluence then
		e.LightInfluence = spec.lightInfluence
	end
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

function Props.roundTree(parent: Instance, pos: Vector3, rng: Random, leaf: Color3, height: number?, slot: Slot): Model?
	return Assets.swap(slotOr(slot, "Tree"), parent, Assets.spin(pos), function(into)
		local h = height or rng:NextNumber(9, 14)
		Props.cylinder(into, "Trunk", h, 1.8, pos + Vector3.new(0, h / 2, 0), Props.WOOD)
		local r = rng:NextNumber(9, 12)
		Props.ball(into, "Canopy", r, pos + Vector3.new(0, h + r * 0.2, 0), leaf)
		Props.ball(into, "Canopy", r * 0.7, pos + Vector3.new(r * 0.35, h + r * 0.55, rng:NextNumber(-2, 2)), leaf:Lerp(Color3.new(1, 1, 0.6), 0.15))
	end)
end

function Props.flower(parent: Instance, pos: Vector3, petal: Color3, height: number?, slot: Slot): Model?
	return Assets.swap(slotOr(slot, "Flower"), parent, Assets.spin(pos), function(into)
		local h = height or 1.6
		Props.cylinder(into, "Stem", h, 0.3, pos + Vector3.new(0, h / 2, 0), Color3.fromRGB(70, 170, 60)).CastShadow = false
		local head = Props.blob(into, "Flower", Vector3.new(1.6, 0.7, 1.6), CFrame.new(pos + Vector3.new(0, h + 0.2, 0)), petal)
		head.CastShadow = false
	end)
end

function Props.bush(parent: Instance, pos: Vector3, size: number, color: Color3, slot: Slot): Model?
	return Assets.swap(slotOr(slot, "Bush"), parent, Assets.spin(pos), function(into)
		Props.blob(into, "Bush", Vector3.new(size * 1.3, size, size), CFrame.new(pos + Vector3.new(0, size * 0.35, 0)), color)
	end)
end

function Props.rock(parent: Instance, pos: Vector3, size: Vector3, color: Color3, material: Enum.Material?, yaw: number?, slot: Slot): Model?
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0)
	return Assets.swap(slotOr(slot, "Rock"), parent, cf, function(into)
		Props.blob(into, "Rock", size, cf + Vector3.new(0, size.Y * 0.3, 0), color, material)
	end)
end

-- A street lamp; its light carries over to a drop-in model that has none of its own.
function Props.lamp(parent: Instance, pos: Vector3, glow: Color3, height: number?, slot: Slot): Model?
	return Assets.swap(slotOr(slot, "Lamp"), parent, CFrame.new(pos), function(into)
		local h = height or 9
		Props.cylinder(into, "LampPost", h, 0.6, pos + Vector3.new(0, h / 2, 0), Color3.fromRGB(45, 45, 55))
		local head = Props.ball(into, "LampHead", 1.8, pos + Vector3.new(0, h + 0.6, 0), glow, Enum.Material.Neon)
		head.CastShadow = false
		Props.light(head, glow, 22, 1.4)
	end, Vector3.new(3, 1, 3))
end

-- A chunky studded wooden fence from a to b (on the ground at a.Y): square posts every ~`spacing` studs, studded
-- on every face, and two thick rails between
-- each pair. Solid, like a real fence; used around plots, never inside the corridor. Each post is a
-- FencePost slot and each stretch of rails between two posts a FenceSection slot. Runs that meet share a
-- post: pass the same `posts` table to each, and a post already standing at a spot is not built twice.
function Props.fence(parent: Instance, a: Vector3, b: Vector3, height: number, spacing: number, post: Color3?, rail: Color3?,
	posts: { [string]: boolean }?)
	local postColor, railColor = post or Props.WOOD, rail or Props.WOOD_LIGHT
	local delta = b - a
	local len = delta.Magnitude
	local n = math.max(1, math.round(len / spacing))
	local dir = delta.Unit
	local along = CFrame.fromMatrix(Vector3.zero, dir, Vector3.yAxis) -- local X along the run (asset frame)
	local rot = Props.lookAt(Vector3.zero, dir) -- local -Z along the run
	local seg = len / n
	for i = 0, n do
		local p = a + dir * (seg * i)
		local key = `{math.round(p.X * 10)},{math.round(p.Y * 10)},{math.round(p.Z * 10)}`
		if not (posts and posts[key]) then
			if posts then
				posts[key] = true
			end
			Assets.swap("FencePost", parent, CFrame.new(p) * along, function(into)
				Props.studs(Props.box(into, "FencePost", Vector3.new(1.8, height + 0.8, 1.8), CFrame.new(p + Vector3.new(0, (height + 0.8) / 2, 0)), postColor),
					{ "TopSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" })
			end, Vector3.new(2, 1, 2))
		end
		if i < n then
			local mid = p + dir * (seg / 2)
			Assets.swap("FenceSection", parent, CFrame.new(mid) * along, function(into)
				for _, y in { height * 0.38, height * 0.82 } do
					Props.studs(Props.box(into, "FenceRail", Vector3.new(1, 1.1, seg), CFrame.new(mid + Vector3.new(0, y, 0)) * rot, railColor),
						{ "TopSurface", "LeftSurface", "RightSurface" })
				end
			end, Vector3.new(1, 1.3, 0))
		end
	end
end

return Props
