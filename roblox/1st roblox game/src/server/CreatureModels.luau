-- Plant-creatures for planted seeds: one distinct creature per zone, built from Parts, WedgeParts and
-- built-in SpecialMesh shapes (no uploaded meshes). Every creature hatches from its seed (a husk or pad at
-- its feet) and carries a leaf/flower motif, so it still reads as a plant.
--
-- Models are built in local space: the pivot is the origin on top of the soil, the creature faces -Z
-- (LookVector), and at scale 1 everything fits inside Config.CREATURE_FOOTPRINT. PlotService pivots the
-- model onto its slot and scales it with Model:ScaleTo, which scales around that pivot.
--
-- Rarity adds flair (aura ring, recoloured trims, Neon, light, sparkles, a halo); a mutation tints and
-- swaps materials and adds particles. Config.CREATURE_ASSETS can swap in an uploaded model per zone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CreatureModels = {}

local V = Vector3.new
local rad = math.rad
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = rgb(255, 255, 255)
local PUPIL = rgb(25, 20, 35)
local MOUTH = rgb(70, 25, 40)
local CHEEK = rgb(255, 140, 175)

-- A CFrame at `pos` whose LookVector (-Z) points along `dir`. Built with fromMatrix rather than
-- CFrame.lookAt so it also handles vertical directions (and matches Lune's CFrame in the tests).
local function along(pos: Vector3, dir: Vector3): CFrame
	local look = dir.Unit
	local right = look:Cross(Vector3.yAxis)
	right = if right.Magnitude < 1e-3 then Vector3.xAxis else right.Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look))
end

-- A point on a sphere's surface (sunk in by `inset`), facing outward.
local function onSphere(center: Vector3, radius: number, dir: Vector3, inset: number?): CFrame
	local n = dir.Unit
	return along(center + n * (radius - (inset or 0)), n)
end

----------------------------------------------------------------------------------------------------
-- Builder
----------------------------------------------------------------------------------------------------
-- Roles decide how rarity and mutations restyle a part:
--   skin/accent/leaf/flower/husk  tinted by mutations
--   trim   small accents: take the rarity colour from Uncommon up, Neon from Rare up
--   glow   Neon zone accents: take the mutation colour
--   eye    never restyled
export type Builder = {
	model: Model,
	body: BasePart?,
	parts: { BasePart },
	roles: { [BasePart]: string },
}

local function newPart(b: Builder, role: string, name: string, class: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new(class) :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or SMOOTH
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	if role == "glow" or role == "eye" then
		p.CastShadow = false
	end
	p.Parent = b.model
	b.roles[p] = role
	table.insert(b.parts, p)
	return p
end

local function shaped(b: Builder, role: string, name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = newPart(b, role, name, "Part", size, cf, color, material) :: Part
	p.Shape = shape
	p.Size = size -- changing Shape can adjust Size (Ball and Cylinder constrain it), so set it again
	return p
end

local function ball(b: Builder, role: string, name: string, d: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	return shaped(b, role, name, Enum.PartType.Ball, Vector3.one * d, CFrame.new(pos), color, material)
end

local function block(b: Builder, role: string, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	return newPart(b, role, name, "Part", size, cf, color, material)
end

-- Non-uniform sphere (a Block with a built-in Sphere SpecialMesh): leaves, petals, bellies, heads.
local function ellipsoid(b: Builder, role: string, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = newPart(b, role, name, "Part", size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Cylinder from a to b (Roblox cylinders run along their local X axis).
local function stalk(b: Builder, role: string, name: string, from: Vector3, to: Vector3, d: number, color: Color3, material: Enum.Material?): Part
	local cf = along((from + to) / 2, to - from) * CFrame.Angles(0, math.pi / 2, 0)
	return shaped(b, role, name, Enum.PartType.Cylinder, V((to - from).Magnitude, d, d), cf, color, material)
end

local function wedge(b: Builder, role: string, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	return newPart(b, role, name, "WedgePart", size, cf, color, material)
end

-- One eye (white, pupil, shine: 3 parts) sitting on `cf`, which faces outward.
local function eye(b: Builder, cf: CFrame, d: number)
	ball(b, "eye", "Eye", d, cf.Position, WHITE)
	ball(b, "eye", "Pupil", d * 0.55, (cf * CFrame.new(0, -0.03 * d, -0.3 * d)).Position, PUPIL)
	ball(b, "eye", "Shine", d * 0.2, (cf * CFrame.new(0.12 * d, 0.15 * d, -0.52 * d)).Position, WHITE, NEON)
end

-- A pair of eyes on a (roughly) spherical head.
local function eyes(b: Builder, head: Vector3, radius: number, spread: number, up: number, d: number)
	for _, sx in { -1, 1 } do
		eye(b, onSphere(head, radius, V(sx * spread, up, -1), d * 0.3), d)
	end
end

local function mouth(b: Builder, head: Vector3, radius: number, down: number, size: Vector3)
	ellipsoid(b, "eye", "Mouth", size, onSphere(head, radius, V(0, -down, -1), size.Z * 0.3), MOUTH)
end

-- Seed husk the creature hatched from.
local function husk(b: Builder, color: Color3, material: Enum.Material?)
	ellipsoid(b, "husk", "SeedHusk", V(2.6, 0.7, 2.6), CFrame.new(0, 0.2, 0), color, material)
end

-- A leaf/petal whose long axis (X) points outward at compass angle `theta` (0 = +X, 90 = +Z), its outer
-- end lifted by `lift` degrees.
local function radial(pos: Vector3, theta: number, lift: number): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, -rad(theta), 0) * CFrame.Angles(0, 0, rad(lift))
end

----------------------------------------------------------------------------------------------------
-- The seven creatures (sizes in studs at scale 1, origin on the soil, facing -Z)
----------------------------------------------------------------------------------------------------
local BUILDERS: { (Builder, Config.Zone) -> () } = {}

-- 1 Sproutling (Meadow): a round green bulb with a big two-leaf sprout, leaf arms and rosy cheeks.
BUILDERS[1] = function(b, zone)
	local green = zone.seedColor
	local dark = green:Lerp(Color3.new(0, 0, 0), 0.35)
	husk(b, rgb(160, 110, 60))
	for _, sx in { -1, 1 } do
		ellipsoid(b, "accent", "Foot", V(0.8, 0.45, 1.05), CFrame.new(sx * 0.55, 0.45, -0.25), dark)
	end
	local c = V(0, 1.9, 0)
	b.body = ball(b, "skin", "Body", 2.6, c, green)
	ellipsoid(b, "accent", "Belly", V(1.5, 1.5, 0.5), onSphere(V(0, 1.7, 0), 1.3, V(0, 0, -1), 0.3), rgb(215, 250, 150))
	eyes(b, c, 1.3, 0.38, 0.35, 0.62)
	for _, sx in { -1, 1 } do
		ellipsoid(b, "flower", "Cheek", V(0.42, 0.24, 0.1), onSphere(c, 1.3, V(sx * 0.9, 0.05, -1)), CHEEK)
		ellipsoid(b, "leaf", "LeafArm", V(0.95, 0.16, 0.55), CFrame.new(sx * 1.2, 1.75, -0.1) * CFrame.Angles(0, 0, sx * rad(25)), dark, Enum.Material.Grass)
		ellipsoid(b, "leaf", "SproutLeaf", V(1.3, 0.14, 0.7), CFrame.new(sx * 0.62, 3.95, 0) * CFrame.Angles(0, 0, sx * rad(35)), green:Lerp(WHITE, 0.15), Enum.Material.Grass)
	end
	mouth(b, c, 1.3, 0.2, V(0.5, 0.2, 0.12))
	stalk(b, "accent", "Stem", V(0, 3.05, 0), V(0, 3.8, 0), 0.22, dark)
	ball(b, "trim", "Bud", 0.45, V(0, 3.9, 0), rgb(255, 220, 60))
end

-- 2 Cactopod (Desert): a barrel cactus on four stubby legs, saguaro arms, spines and a pink flower crown.
BUILDERS[2] = function(b, zone)
	local green = zone.seedColor
	local dark = green:Lerp(Color3.new(0, 0, 0), 0.3)
	local light = green:Lerp(WHITE, 0.35)
	husk(b, rgb(225, 185, 110), Enum.Material.Sand)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			stalk(b, "accent", "Leg", V(sx * 0.5, 0.95, sz * 0.5), V(sx * 0.9, 0.12, sz * 0.9), 0.42, dark)
		end
	end
	b.body = shaped(b, "skin", "Body", Enum.PartType.Cylinder, V(2.8, 2, 2), CFrame.new(0, 2.35, 0) * CFrame.Angles(0, 0, math.pi / 2), green)
	ball(b, "skin", "Dome", 2, V(0, 3.75, 0), green)
	for _, phi in { -55, 55, 180 } do
		block(b, "accent", "Rib", V(0.22, 2.6, 0.22), CFrame.new(math.sin(rad(phi)) * 0.98, 2.4, -math.cos(rad(phi)) * 0.98), light)
	end
	for _, arm in { { sx = -1, y = 2.3 }, { sx = 1, y = 1.9 } } do
		local x = arm.sx * 1.4
		stalk(b, "skin", "Arm", V(arm.sx * 0.9, arm.y, 0), V(arm.sx * 1.65, arm.y, 0), 0.5, green)
		stalk(b, "skin", "Arm", V(x, arm.y - 0.25, 0), V(x, arm.y + 1, 0), 0.5, green)
		ball(b, "skin", "ArmTip", 0.5, V(x, arm.y + 1, 0), green)
	end
	eyes(b, V(0, 3, 0), 1, 0.36, 0, 0.6)
	mouth(b, V(0, 2.4, 0), 1, 0, V(0.7, 0.22, 0.12))
	for _, s in { { phi = 110, y = 1.7 }, { phi = 200, y = 2.9 }, { phi = 250, y = 2.1 } } do
		local dir = V(math.sin(rad(s.phi)), 0, -math.cos(rad(s.phi)))
		block(b, "accent", "Spine", V(0.07, 0.07, 0.4), along(V(0, s.y, 0) + dir * 1.1, dir), rgb(255, 245, 210))
	end
	ball(b, "trim", "FlowerCore", 0.4, V(0, 4.8, 0), rgb(255, 220, 60))
	for k = 0, 4 do
		local theta = k * 72
		local pos = V(math.cos(rad(theta)) * 0.38, 4.78, math.sin(rad(theta)) * 0.38)
		ellipsoid(b, "flower", "Petal", V(0.62, 0.14, 0.34), radial(pos, theta, 25), rgb(255, 80, 165))
	end
end

-- 3 Fernosaur (Jungle): a long-necked leaf dinosaur with fern fronds down its back and a fiddlehead tail.
BUILDERS[3] = function(b, zone)
	local green = zone.seedColor
	local dark = green:Lerp(Color3.new(0, 0, 0), 0.3)
	local lime, fern = rgb(160, 235, 60), rgb(90, 210, 70)
	husk(b, rgb(80, 120, 55), Enum.Material.Grass)
	b.body = ellipsoid(b, "skin", "Body", V(1.9, 1.6, 2.5), CFrame.new(0, 1.75, 0.25), green)
	ellipsoid(b, "accent", "Belly", V(1.4, 1, 1.9), CFrame.new(0, 1.4, 0.05), rgb(210, 245, 160))
	for _, sx in { -1, 1 } do
		for _, z in { -0.45, 0.95 } do
			stalk(b, "accent", "Leg", V(sx * 0.6, 1.4, z), V(sx * 0.6, 0.1, z), 0.6, dark)
		end
	end
	stalk(b, "skin", "Neck", V(0, 2.3, -0.55), V(0, 3.7, -0.95), 0.75, green)
	ball(b, "skin", "NeckJoint", 0.72, V(0, 3.7, -0.95), green)
	stalk(b, "skin", "Neck", V(0, 3.7, -0.95), V(0, 4.7, -0.85), 0.62, green)
	local head = V(0, 4.95, -0.9)
	ellipsoid(b, "skin", "Head", V(1.05, 0.85, 1.35), CFrame.new(head), green)
	eyes(b, head + V(0, 0.1, 0), 0.55, 0.75, 0.3, 0.42)
	mouth(b, head - V(0, 0.12, 0), 0.62, 0.1, V(0.45, 0.1, 0.1))
	stalk(b, "leaf", "Tail", V(0, 1.7, 1.15), V(0, 2.35, 1.35), 0.5, lime)
	stalk(b, "leaf", "Tail", V(0, 2.35, 1.35), V(0, 3, 1.15), 0.4, lime)
	ball(b, "leaf", "Fiddlehead", 0.6, V(0, 3.1, 0.9), lime, Enum.Material.Grass)
	for i, z in { -0.25, 0.2, 0.65, 1.05 } do
		ellipsoid(b, "leaf", "Frond", V(0.14, 0.95, 0.55), CFrame.new(0, 2.7, z) * CFrame.Angles(rad(-20), 0, 0),
			if i % 2 == 1 then lime else fern, Enum.Material.Grass)
	end
	for _, sx in { -1, 1 } do
		ellipsoid(b, "trim", "Crest", V(0.12, 0.6, 0.4), CFrame.new(sx * 0.18, 5.45, -0.85) * CFrame.Angles(0, 0, sx * rad(-20)), rgb(255, 210, 60))
	end
end

-- 4 Magmabloom (Lava Fields): a cracked magma-rock body with glowing seams, rock fists, and a blazing
-- sunflower head of Neon petals.
BUILDERS[4] = function(b, zone)
	local rock = rgb(175, 60, 40)
	local lava, flame = rgb(255, 200, 50), zone.seedColor
	husk(b, rgb(60, 42, 42), Enum.Material.Basalt)
	for _, sx in { -1, 1 } do
		block(b, "accent", "Leg", V(0.75, 1, 0.85), CFrame.new(sx * 0.55, 0.55, 0), rock:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Rock)
	end
	local c = V(0, 2, 0)
	b.body = ball(b, "skin", "Body", 2.3, c, rock, Enum.Material.Rock)
	for _, crack in { { dir = V(-0.5, 0.25, -1), roll = 20 }, { dir = V(0.55, -0.3, -1), roll = -35 }, { dir = V(1, 0.4, 0.3), roll = 60 } } do
		block(b, "glow", "LavaCrack", V(0.12, 1.1, 0.12), onSphere(c, 1.15, crack.dir, 0.03) * CFrame.Angles(0, 0, rad(crack.roll)), lava, NEON)
	end
	ellipsoid(b, "glow", "Core", V(0.9, 0.9, 0.3), onSphere(c, 1.15, V(0, -0.1, -1), 0.08), lava, NEON)
	for _, sx in { -1, 1 } do
		stalk(b, "skin", "Arm", V(sx * 1, 2.3, 0), V(sx * 1.3, 1.45, -0.3), 0.55, rock, Enum.Material.Rock)
		ball(b, "skin", "Fist", 0.65, V(sx * 1.3, 1.4, -0.3), rock, Enum.Material.Rock)
	end
	stalk(b, "accent", "Stem", V(0, 3.05, 0), V(0, 3.95, -0.1), 0.5, rgb(110, 70, 40))
	local face = V(0, 4.6, -0.1)
	for k = 0, 7 do
		local theta = k * 45
		local pos = face + V(math.cos(rad(theta)) * 0.95, math.sin(rad(theta)) * 0.95, 0.12)
		ellipsoid(b, "glow", "Petal", V(1, 0.5, 0.18), CFrame.new(pos) * CFrame.Angles(0, 0, rad(theta)), if k % 2 == 0 then flame else lava, NEON)
	end
	ball(b, "flower", "Face", 1.4, face, rgb(255, 175, 60))
	eyes(b, face, 0.7, 0.45, 0.2, 0.42)
	mouth(b, face, 0.7, 0.45, V(0.4, 0.16, 0.1))
end

-- 5 Frostbulb (Snow Peaks): an icy teardrop bulb in a red knitted scarf, crowned with ice crystals.
BUILDERS[5] = function(b, zone)
	local ice = zone.seedColor
	local frost = ice:Lerp(WHITE, 0.35)
	local scarf = rgb(230, 45, 70)
	husk(b, rgb(215, 235, 250), Enum.Material.Snow)
	for _, sx in { -1, 1 } do
		ellipsoid(b, "accent", "Foot", V(0.8, 0.45, 1), CFrame.new(sx * 0.55, 0.45, -0.2), frost)
		ellipsoid(b, "leaf", "FrostLeaf", V(0.95, 0.18, 0.5), CFrame.new(sx * 1.25, 1.9, -0.05) * CFrame.Angles(0, 0, sx * rad(-20)), frost:Lerp(WHITE, 0.3), Enum.Material.Glacier)
	end
	local c = V(0, 2, 0)
	b.body = ball(b, "skin", "Body", 2.6, c, ice, Enum.Material.Ice)
	ellipsoid(b, "skin", "Bulb", V(1.9, 1.5, 1.9), CFrame.new(0, 3.3, 0), frost, Enum.Material.Ice)
	ellipsoid(b, "skin", "BulbTip", V(0.9, 1.3, 0.9), CFrame.new(0, 4.25, 0), frost:Lerp(WHITE, 0.4), Enum.Material.Ice)
	shaped(b, "accent", "Scarf", Enum.PartType.Cylinder, V(0.45, 1.9, 1.9), CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.pi / 2), scarf, Enum.Material.Fabric)
	block(b, "accent", "ScarfTail", V(0.45, 1, 0.12), onSphere(V(0, 2.5, 0), 1.2, V(0.5, 0, -1)) * CFrame.Angles(0, 0, rad(10)), scarf, Enum.Material.Fabric)
	for k = 0, 3 do
		local theta = 45 + k * 90
		local pos = V(math.cos(rad(theta)) * 0.5, 4.5, math.sin(rad(theta)) * 0.5)
		block(b, "trim", "Crystal", V(0.3, 1.1, 0.3), radial(pos, theta, -30), rgb(150, 240, 255), NEON)
	end
	block(b, "glow", "CrownCrystal", V(0.42, 2, 0.42), CFrame.new(0, 5.45, 0) * CFrame.Angles(0, rad(45), 0), rgb(170, 245, 255), NEON)
	eyes(b, c, 1.3, 0.4, 0.35, 0.6)
	mouth(b, c, 1.3, 0.05, V(0.45, 0.18, 0.12))
end

-- 6 Starpetal (Deep Space): a floating cyclops star-flower on a Neon stem, framed by five star petals,
-- with glowing antennae and two little moons.
BUILDERS[6] = function(b, zone)
	local violet = zone.seedColor
	local magenta, gold = rgb(255, 110, 225), rgb(255, 240, 120)
	husk(b, rgb(70, 45, 120), Enum.Material.Glass)
	stalk(b, "glow", "Stem", V(0, 0.5, 0), V(0, 3, 0), 0.28, magenta, NEON)
	for _, sx in { -1, 1 } do
		ellipsoid(b, "leaf", "StemLeaf", V(1, 0.14, 0.5), CFrame.new(sx * 0.5, 1.2, 0) * CFrame.Angles(0, 0, sx * rad(30)), rgb(120, 90, 235))
	end
	local c = V(0, 4, 0)
	b.body = ball(b, "skin", "Body", 2.2, c, violet)
	for _, dir in { V(0.9, 0.5, 0.3), V(-0.8, -0.3, 0.6), V(0.2, 0.8, 0.8) } do
		ball(b, "glow", "BodyStar", 0.28, onSphere(c, 1.1, dir, 0.05).Position, gold, NEON)
	end
	for k = 0, 4 do
		local theta = rad(90 + k * 72)
		local dir = V(math.cos(theta), math.sin(theta), 0)
		ellipsoid(b, "flower", "StarPetal", V(0.95, 0.5, 0.2), CFrame.new(c + dir * 1.15 + V(0, 0, 0.3)) * CFrame.Angles(0, 0, theta), magenta)
		ball(b, "glow", "PetalTip", 0.3, c + dir * 1.6 + V(0, 0, 0.3), gold, NEON)
	end
	eye(b, onSphere(c, 1.1, V(0, 0.15, -1), 0.35), 1)
	mouth(b, c, 1.1, 0.5, V(0.55, 0.2, 0.12))
	for _, sx in { -1, 1 } do
		stalk(b, "skin", "Antenna", V(sx * 0.35, 4.95, 0), V(sx * 0.75, 6.5, 0.1), 0.12, violet:Lerp(Color3.new(0, 0, 0), 0.3))
		ball(b, "trim", "AntennaTip", 0.42, V(sx * 0.78, 6.65, 0.1), rgb(140, 255, 140), NEON)
	end
	ball(b, "glow", "Moon", 0.45, V(-1.25, 5.9, 0.6), rgb(120, 230, 255), NEON)
	ball(b, "glow", "Moon", 0.35, V(1.2, 2.6, -0.7), rgb(255, 180, 120), NEON)
end

-- 7 Lotus Wyrm (Spirit Garden): a coral-pink dragon coiling up out of a lotus on a lily pad, with golden
-- horns, whiskers and fins and a glowing spirit pearl.
BUILDERS[7] = function(b, zone)
	local skin = rgb(245, 80, 120)
	local cream, gold = rgb(255, 215, 140), rgb(255, 200, 60)
	local pink = zone.seedColor
	shaped(b, "husk", "LilyPad", Enum.PartType.Cylinder, V(0.16, 2.8, 2.8), CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(70, 170, 90), Enum.Material.Grass)
	for k = 0, 5 do
		local theta = k * 60
		local pos = V(math.cos(rad(theta)) * 0.85, 0.45, math.sin(rad(theta)) * 0.85)
		ellipsoid(b, "flower", "LotusPetal", V(1.1, 0.22, 0.6), radial(pos, theta, 35), if k % 2 == 0 then pink else pink:Lerp(WHITE, 0.6))
	end
	ellipsoid(b, "flower", "LotusHeart", V(1.5, 0.55, 1.5), CFrame.new(0, 0.45, 0), rgb(255, 225, 238))
	local segs = {}
	for i = 0, 6 do
		local theta = rad(i * 62)
		local pos = V(math.cos(theta) * 0.6, 0.95 + i * 0.6, math.sin(theta) * 0.6)
		segs[i] = pos
		local seg = ball(b, if i % 2 == 0 then "skin" else "accent", if i == 3 then "Body" else "Coil", 1.3 - 0.06 * i, pos, if i % 2 == 0 then skin else cream)
		if i == 3 then
			b.body = seg
		end
		if i % 2 == 1 then
			local tangent = V(-math.sin(theta), 0.35, math.cos(theta))
			wedge(b, "trim", "Fin", V(0.12, 0.55, 0.7), along(pos + V(0, (1.3 - 0.06 * i) * 0.45, 0), tangent), gold)
		end
	end
	stalk(b, "skin", "Neck", segs[6], V(0, 5.5, -0.45), 0.75, skin)
	local head = V(0, 5.85, -0.5)
	ellipsoid(b, "skin", "Head", V(1.3, 1, 1.5), CFrame.new(head), skin)
	ellipsoid(b, "accent", "Snout", V(0.95, 0.6, 0.8), CFrame.new(0, 5.65, -1.15), cream)
	eyes(b, head + V(0, 0.1, 0), 0.62, 0.75, 0.35, 0.42)
	for _, sx in { -1, 1 } do
		stalk(b, "trim", "Horn", V(sx * 0.35, 6.25, -0.3), V(sx * 0.65, 7.2, 0.25), 0.2, gold)
		stalk(b, "trim", "Whisker", V(sx * 0.35, 5.55, -1.4), V(sx * 1.05, 5.25, -1.15), 0.08, gold)
	end
	ball(b, "glow", "SpiritPearl", 0.55, V(0.85, 7, -0.7), rgb(255, 245, 220), NEON)
end

----------------------------------------------------------------------------------------------------
-- Measuring (also used by the tests)
----------------------------------------------------------------------------------------------------
-- How far a part reaches along unit vector u (its support function).
local function reach(p: BasePart, u: Vector3): number
	local cf, half = p.CFrame, p.Size / 2
	local c = cf.Position:Dot(u)
	local x, y, z = cf.RightVector:Dot(u), cf.UpVector:Dot(u), cf.LookVector:Dot(u)
	if p:IsA("Part") then
		if p.Shape == Enum.PartType.Ball then
			return c + half.X
		elseif p.Shape == Enum.PartType.Cylinder then
			return c + math.abs(half.X * x) + half.Y * math.sqrt(y * y + z * z)
		end
	end
	local mesh = p:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == Enum.MeshType.Sphere then
		return c + math.sqrt((half.X * x) ^ 2 + (half.Y * y) ^ 2 + (half.Z * z) ^ 2)
	end
	return c + math.abs(half.X * x) + math.abs(half.Y * y) + math.abs(half.Z * z)
end

-- (radius, height) of a model still at its build pose: the widest horizontal reach from the pivot axis
-- and the highest point above the soil.
function CreatureModels.extents(model: Model): (number, number)
	local radius, height = 0, 0
	local dirs = {}
	for i = 0, 31 do
		local a = i * math.pi / 16
		dirs[i + 1] = V(math.cos(a), 0, math.sin(a))
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			height = math.max(height, reach(d, Vector3.yAxis))
			for _, u in dirs do
				radius = math.max(radius, reach(d, u))
			end
		end
	end
	return radius, height
end

function CreatureModels.partCount(model: Model): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------------------------------------------
-- Rarity, mutations and zone effects
----------------------------------------------------------------------------------------------------
local function particles(parent: Instance, name: string, color: ColorSequence, rate: number, size: number, lifetime: number, speed: number, accel: Vector3)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = SPARKLE_TEXTURE
	e.Color = color
	e.Rate = rate
	e.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = accel
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = 0.6
	e.Parent = parent
	return e
end

-- Signature particles and glow for the later zones (the grander creatures).
local ZONE_FX: { [number]: { color: Color3, rate: number, size: number, lifetime: number, speed: number, accel: Vector3, light: boolean } } = {
	[3] = { color = rgb(210, 255, 120), rate = 2, size = 0.25, lifetime = 3, speed = 0.6, accel = V(0, 0.3, 0), light = false }, -- spores
	[4] = { color = rgb(255, 150, 40), rate = 6, size = 0.35, lifetime = 1.6, speed = 2, accel = V(0, 3, 0), light = true }, -- embers
	[5] = { color = rgb(220, 245, 255), rate = 4, size = 0.3, lifetime = 3, speed = 0.8, accel = V(0, -1.2, 0), light = true }, -- snow
	[6] = { color = rgb(255, 250, 200), rate = 5, size = 0.4, lifetime = 2, speed = 0.5, accel = Vector3.zero, light = true }, -- stars
	[7] = { color = rgb(255, 170, 215), rate = 6, size = 0.4, lifetime = 3.5, speed = 0.8, accel = V(0, 0.6, 0), light = true }, -- petals
}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 80, 80)),
	ColorSequenceKeypoint.new(0.25, rgb(255, 220, 60)),
	ColorSequenceKeypoint.new(0.5, rgb(80, 255, 120)),
	ColorSequenceKeypoint.new(0.75, rgb(80, 160, 255)),
	ColorSequenceKeypoint.new(1, rgb(220, 90, 255)),
})

-- Celestial (exclusive, premium seed packs only) is the rarest look: a deep-violet starry body, white Neon
-- leaves and petals, cyan glow, a soft star halo and slow drifting stars.
local CELESTIAL_VIOLET = rgb(55, 25, 140)
local CELESTIAL_WHITE = rgb(240, 242, 255)
local CELESTIAL_STARS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.5, rgb(190, 150, 255)),
	ColorSequenceKeypoint.new(1, rgb(120, 240, 255)),
})

local TINTED = { skin = 1, accent = 1, leaf = 0.8, flower = 0.8, husk = 0.45, asset = 0.5 }

local function applyMutation(b: Builder, mut: Config.Mutation)
	local i = 0
	for _, p in b.parts do
		local role = b.roles[p]
		local weight = TINTED[role]
		i += 1
		if role == "glow" then
			p.Color = if mut.id == "Rainbow" then Color3.fromHSV((i * 0.13) % 1, 0.7, 1) else mut.color
		elseif weight then
			if mut.id == "Gold" then
				p.Color = p.Color:Lerp(mut.color, 0.75 * weight)
				p.Material = Enum.Material.Foil
			elseif mut.id == "Rainbow" then
				if role == "skin" or role == "asset" then
					p:SetAttribute("Mutation", "Rainbow") -- the client cycles its colour
				else
					p.Color = p.Color:Lerp(Color3.fromHSV((i * 0.13) % 1, 0.75, 1), 0.7 * weight)
				end
			elseif mut.id == "Night" then
				p.Color = p.Color:Lerp(rgb(45, 45, 130), 0.6 * weight)
			elseif mut.id == "Celestial" then
				if role == "leaf" or role == "flower" then
					p.Color = CELESTIAL_WHITE
					p.Material = NEON
				else
					p.Color = p.Color:Lerp(CELESTIAL_VIOLET, 0.85 * weight)
					p.Material = SMOOTH
					p.Reflectance = 0.2 -- a starry sheen under the lights
				end
			else
				p.Color = p.Color:Lerp(mut.color, 0.55 * weight)
			end
		end
	end
end

local function decorate(b: Builder, zoneIndex: number, rarityIndex: number, mut: Config.Mutation?)
	local body = b.body :: BasePart
	local rarity = Config.RARITIES[rarityIndex]
	local _, top = CreatureModels.extents(b.model)

	if mut then
		applyMutation(b, mut)
	end
	-- Trims take the rarity colour (after the mutation, so rarity stays readable on a mutated creature).
	if rarityIndex >= 2 then
		for p, role in b.roles do
			if role == "trim" then
				p.Color = rarity.color
				if rarityIndex >= 3 then
					p.Material = NEON
				end
			end
		end
	end
	-- Aura ring on the soil
	if rarityIndex >= 2 then
		local ring = shaped(b, "fx", "AuraRing", Enum.PartType.Cylinder, V(0.1, Config.CREATURE_FOOTPRINT - 0.1, Config.CREATURE_FOOTPRINT - 0.1),
			CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2), rarity.color, NEON)
		ring.Transparency = if rarityIndex >= 4 then 0.25 else 0.5
		ring.CastShadow = false
	end
	-- Halo of glowing orbs above the head: Legendary (rarity colour) and/or Celestial (white stars).
	-- A Legendary Celestial alternates the two, so it stays within the part budget.
	local celestial = mut ~= nil and mut.id == "Celestial"
	if rarityIndex >= 5 or celestial then
		for k = 0, 5 do
			local a = k * math.pi / 3
			local color = if not celestial then rarity.color elseif rarityIndex >= 5 and k % 2 == 0 then rarity.color else CELESTIAL_WHITE
			local orb = ball(b, "fx", "HaloOrb", if celestial then 0.36 else 0.3, V(math.cos(a) * 0.8, top + 0.35, math.sin(a) * 0.8), color, NEON)
			orb.CastShadow = false
		end
		top += 0.5
	end

	-- One light per creature: mutation, else rarity (Rare+), else the zone's glow.
	local fx = ZONE_FX[zoneIndex]
	local lightColor = if mut then mut.color elseif rarityIndex >= 3 then rarity.color elseif fx and fx.light then fx.color else nil
	if lightColor then
		local light = Instance.new("PointLight")
		light.Color = lightColor
		light.Range = 8 + rarityIndex * 1.5 + (if mut then 3 else 0)
		light.Brightness = 1.6
		light.Shadows = false
		light.Parent = body
	end

	if fx then
		particles(body, "ZoneFX", ColorSequence.new(fx.color), fx.rate, fx.size, fx.lifetime, fx.speed, fx.accel)
	end
	if rarityIndex >= 4 then
		particles(body, "RaritySparkles", ColorSequence.new(rarity.color), 2 + rarityIndex, 0.45, 1.4, 2, Vector3.zero)
	end
	if mut then
		b.model:SetAttribute("Mutation", mut.id)
		if celestial then
			-- Slow, long-lived stars that drift around the creature
			local stars = particles(body, "MutationSparkles", CELESTIAL_STARS, 5, 0.6, 4, 0.4, V(0, 0.15, 0))
			stars.LightEmission = 1
			stars.RotSpeed = NumberRange.new(-30, 30)
		else
			particles(body, "MutationSparkles", if mut.id == "Rainbow" then RAINBOW else ColorSequence.new(mut.color), 7, 0.5, 1.2, 2.5, Vector3.zero)
		end
	end

	-- Anchors PlotService hangs the Info billboard and the Remove prompt on (they scale with the model).
	local info = Instance.new("Attachment")
	info.Name = "InfoAnchor"
	info.CFrame = body.CFrame:Inverse() * CFrame.new(0, top + 0.3, 0)
	info.Parent = body
	local prompt = Instance.new("Attachment")
	prompt.Name = "PromptAnchor"
	prompt.CFrame = body.CFrame:Inverse() * CFrame.new(0, 1.5, 0)
	prompt.Parent = body
	b.model:SetAttribute("CreatureHeight", top)
end

----------------------------------------------------------------------------------------------------
-- Optional uploaded models (Config.CREATURE_ASSETS)
----------------------------------------------------------------------------------------------------
local templates: { [number]: Model } = {}

-- Loads every configured asset once (yields). Call from a spawned thread; build() never waits for it and
-- falls back to the procedural creature until (or unless) the asset has loaded.
function CreatureModels.preload()
	for zoneIndex, id in Config.CREATURE_ASSETS do
		if type(id) == "number" and id > 0 and not templates[zoneIndex] then
			local ok, result = pcall(function()
				return game:GetService("InsertService"):LoadAsset(id)
			end)
			local model = ok and (result:FindFirstChildWhichIsA("Model") or result)
			if not model then
				warn("[CreatureModels] could not load asset", id, "for zone", zoneIndex, result)
				continue
			end
			model = model:Clone()
			local biggest: BasePart? = nil
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanTouch = false
					d.CanQuery = false
					if not biggest or d.Size.Magnitude > biggest.Size.Magnitude then
						biggest = d
					end
				elseif d:IsA("Script") or d:IsA("LocalScript") then
					d:Destroy()
				end
			end
			if not biggest then
				warn("[CreatureModels] asset", id, "has no parts")
				continue
			end
			model.PrimaryPart = model.PrimaryPart or biggest
			-- Pivot at the bottom centre of the bounding box, then fit the footprint and a zone-ish height.
			local box, size = model:GetBoundingBox()
			local primary = model.PrimaryPart :: BasePart
			primary.PivotOffset = primary.CFrame:Inverse() * (box * CFrame.new(0, -size.Y / 2, 0))
			model:PivotTo(CFrame.identity)
			local targetHeight = 4.5 + 0.5 * zoneIndex
			-- ScaleTo is absolute (relative to the asset's original size) and clones keep the scale factor,
			-- so the fit is stored as BaseScale and applyScale multiplies the plant's scale onto it.
			local base = model:GetScale() * math.min(targetHeight / size.Y, Config.CREATURE_FOOTPRINT / math.max(size.X, size.Z))
			model:ScaleTo(base)
			model:SetAttribute("BaseScale", base)
			templates[zoneIndex] = model
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Public
----------------------------------------------------------------------------------------------------
-- Builds the creature for (zone, rarity, mutation?) at the origin (see the header). The model's
-- PrimaryPart is its body and its pivot is the origin.
function CreatureModels.build(zoneIndex: number, rarityIndex: number, mutation: string?): Model
	local zone = Config.ZONES[zoneIndex]
	local model: Model
	local b: Builder
	local template = templates[zoneIndex]
	if template then
		model = template:Clone()
		b = { model = model, body = model.PrimaryPart, parts = {}, roles = {} }
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(b.parts, d)
				b.roles[d] = "asset"
			end
		end
	else
		model = Instance.new("Model")
		b = { model = model, body = nil, parts = {}, roles = {} }
		BUILDERS[zoneIndex](b, zone)
	end
	model.Name = zone.seed
	model:SetAttribute("Zone", zoneIndex)
	decorate(b, zoneIndex, rarityIndex, Config.mutationById(mutation))
	local body = b.body :: BasePart
	model.PrimaryPart = body
	body.PivotOffset = body.CFrame:Inverse() -- pivot = origin on the soil, so ScaleTo grows from the ground
	return model
end

-- Scales a placed creature (around its soil pivot) to `scale` times its build size, and records `scale`
-- (the logical scale) for the client's idle sway. Uploaded templates were already fitted with ScaleTo,
-- which is absolute, so their BaseScale is multiplied in; procedural creatures have none (1).
-- Built-in Sphere meshes already follow their part's Size. ScaleTo may also scale SpecialMesh.Scale, which
-- would grow them twice, so those are reset to 1 afterwards.
function CreatureModels.applyScale(model: Model, scale: number)
	model:ScaleTo((model:GetAttribute("BaseScale") or 1) * scale)
	for _, d in model:GetDescendants() do
		if d:IsA("SpecialMesh") and d.MeshType ~= Enum.MeshType.FileMesh then
			d.Scale = Vector3.one
		end
	end
	model:SetAttribute("Scale", scale)
end

-- Scale for a plant of this weight: grows with weight/sprout weight (sprout ~1, full-grown ~1.9) and a
-- little with rarity, clamped so the biggest still fits its slot.
function CreatureModels.scaleFor(zoneIndex: number, rarityIndex: number, weight: number): number
	local ratio = math.max(weight, 0) / Config.sproutWeight(zoneIndex, rarityIndex)
	local s = ratio ^ Config.CREATURE_GROWTH_EXPONENT * (1 + Config.CREATURE_RARITY_SCALE * (rarityIndex - 1))
	return math.clamp(s, Config.CREATURE_MIN_SCALE, Config.CREATURE_MAX_SCALE)
end

return CreatureModels
