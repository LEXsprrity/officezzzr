--!strict
-- The mutations that give a plant model a whole new look (owner 2026-10-19: "i like the halloween mutations ...
-- lets add golden types diamond types besides the mutant halloween types"), shared by the server's plant
-- (CreatureModels) and the HUD's 3D pictures of it (FlowerView), so both match:
--   * Haunted: Halloween.hauntify (toxic-green glow, pumpkin orange, deep purple, orange-to-purple wisps);
--   * Gold (goldify): rich metallic gold. Every colour goes onto a gold ramp by its brightness: darks deep
--     amber (Metal), the middle rich gold (Foil), brights pale or white gold (Foil); Neon glows bright gold;
--     its particles become golden sparkles, its beams and lights gold;
--   * Diamond (diamondify): icy crystal on the same idea: darks deep ice blue and middles icy cyan (Ice),
--     brights white crystal (Glass, a little see-through: never invisible); Neon glows cyan-white; its
--     particles become white-cyan glints.
-- A colour's place on the ramp is its brightness, half absolute and half relative to the plant's own range
-- (its RANGE_LO..RANGE_HI share of the surface, by brightness), so a dark plant still has bright gold in it
-- and a pale one deep amber, then lifted (LIFT) so most of a plant is the rich middle. Everything is decided
-- by colour (whatever the parts' order) and our Flair parts (the rarity halo, the jack-o'-lantern:
-- Halloween.FLAIR) keep theirs. A makeover replaces the plant's palette (Shared/Palettes.OVERRIDDEN); the
-- other mutations only tint it (CreatureModels.applyMutation).
local Halloween = require(script.Parent:WaitForChild("Halloween"))

local Mutations = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Mutations.SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
Mutations.RANGE_LO = 0.1 -- the plant's own dark end: the brightness under which this share of its surface lies
Mutations.RANGE_HI = 0.9 -- ...and its bright end
Mutations.MIN_RANGE = 0.08 -- a plant flatter than this (one colour) sits on the ramp by its absolute brightness
Mutations.LIFT = 0.6 -- the tone is raised to this power: most plants are dark greens, and most of a made-over plant
-- should be the rich middle of the ramp, not its dark end

export type Look = {
	dark: Color3, -- the ramp: tone 0
	mid: Color3, -- tone 0.5
	bright: Color3, -- tone 1
	glow: Color3, -- Neon parts, beams' and lights' colour
	sparkles: ColorSequence, -- particles
	darkMaterial: Enum.Material, -- tone under DARK_TONE
	material: Enum.Material, -- the middle
	brightMaterial: Enum.Material, -- tone at BRIGHT_TONE and over
	darkTone: number,
	brightTone: number,
	brightTransparency: number, -- at least this see-through on brightMaterial parts (0: opaque)
	reflectance: number, -- at least this shiny (not Neon)
}

Mutations.LOOKS = {
	Gold = {
		dark = rgb(125, 70, 8),
		mid = rgb(235, 172, 30),
		bright = rgb(255, 240, 185),
		glow = rgb(255, 214, 70),
		sparkles = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 250, 215)),
			ColorSequenceKeypoint.new(0.5, rgb(255, 214, 70)),
			ColorSequenceKeypoint.new(1, rgb(230, 150, 20)),
		}),
		darkMaterial = Enum.Material.Metal,
		material = Enum.Material.Foil,
		brightMaterial = Enum.Material.Foil,
		darkTone = 0.25,
		brightTone = 0.75,
		brightTransparency = 0,
		reflectance = 0.1,
	},
	Diamond = {
		dark = rgb(45, 120, 185),
		mid = rgb(135, 220, 250),
		bright = rgb(240, 252, 255),
		glow = rgb(205, 250, 255),
		sparkles = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 255, 255)),
			ColorSequenceKeypoint.new(0.5, rgb(170, 240, 255)),
			ColorSequenceKeypoint.new(1, rgb(255, 255, 255)),
		}),
		darkMaterial = Enum.Material.Ice,
		material = Enum.Material.Ice,
		brightMaterial = Enum.Material.Glass,
		darkTone = 0.25,
		brightTone = 0.7,
		brightTransparency = 0.25,
		reflectance = 0.2,
	},
} :: { [string]: Look }

-- The mutations that repaint a plant model entirely (makeover), in the order of Config.MUTATIONS.
Mutations.REPAINTS = { "Gold", "Diamond", Halloween.MUTATION }

local function surface(p: BasePart): number
	local s = p.Size
	return if p.Transparency >= 0.95 then 0 else s.X * s.Y + s.Y * s.Z + s.X * s.Z
end

function Mutations.brightness(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- The plant's own brightness range (lo, hi) over `parts` (not Neon): the brightness under which RANGE_LO and
-- RANGE_HI of its surface lie, by colour (a whole colour at a time, ties by hex), so the parts' order never
-- matters.
function Mutations.range(parts: { BasePart }): (number, number)
	type Group = { hex: string, light: number, area: number }
	local byHex: { [string]: Group } = {}
	local groups: { Group } = {}
	local total = 0
	for _, p in parts do
		if p.Material == Enum.Material.Neon then
			continue
		end
		local hex = p.Color:ToHex()
		local g = byHex[hex]
		if not g then
			g = { hex = hex, light = Mutations.brightness(p.Color), area = 0 }
			byHex[hex] = g
			table.insert(groups, g)
		end
		local a = surface(p)
		g.area += a
		total += a
	end
	if #groups == 0 then
		return 0, 1
	end
	table.sort(groups, function(a, b)
		if a.light ~= b.light then
			return a.light < b.light
		end
		return a.hex < b.hex
	end)
	local lo, hi = groups[1].light, groups[#groups].light
	local acc = 0
	local foundLo = false
	for _, g in groups do
		acc += g.area
		if not foundLo and acc >= Mutations.RANGE_LO * total then
			lo, foundLo = g.light, true
		end
		if acc >= Mutations.RANGE_HI * total then
			hi = g.light
			break
		end
	end
	return lo, hi
end

-- Where colour `c` sits on the ramp (0 dark .. 1 bright) in a plant whose range is lo..hi.
function Mutations.tone(c: Color3, lo: number, hi: number): number
	local light = Mutations.brightness(c)
	local relative = if hi - lo >= Mutations.MIN_RANGE then math.clamp((light - lo) / (hi - lo), 0, 1) else light
	return math.clamp(0.5 * relative + 0.5 * light, 0, 1) ^ Mutations.LIFT
end

-- The ramp's colour at `tone`.
function Mutations.ramp(look: Look, tone: number): Color3
	return if tone < 0.5 then look.dark:Lerp(look.mid, tone / 0.5) else look.mid:Lerp(look.bright, (tone - 0.5) / 0.5)
end

-- Gives every part, particle emitter, beam and light under `root` (not our Flair) the look (see above).
function Mutations.restyle(root: Instance, look: Look)
	local parts: { BasePart } = {}
	for _, d in root:GetDescendants() do
		if d:GetAttribute(Halloween.FLAIR) then
			continue
		elseif d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("ParticleEmitter") then
			d.Color = look.sparkles
			d.Texture = Mutations.SPARKLE_TEXTURE
			d.FlipbookLayout = Enum.ParticleFlipbookLayout.None -- (a flipbook would cut the sparkle into frames)
			d.LightEmission = math.max(d.LightEmission, 0.6)
		elseif d:IsA("Beam") then
			d.Color = ColorSequence.new(look.glow)
		elseif d:IsA("Light") then
			d.Color = look.glow
		end
	end
	local lo, hi = Mutations.range(parts)
	for _, p in parts do
		if p.Material == Enum.Material.Neon then
			p.Color = look.glow
			continue
		end
		local tone = Mutations.tone(p.Color, lo, hi)
		p.Color = Mutations.ramp(look, tone)
		p.Reflectance = math.max(p.Reflectance, look.reflectance)
		if tone >= look.brightTone then
			p.Material = look.brightMaterial
			if p.Transparency < look.brightTransparency then
				p.Transparency = look.brightTransparency
			end
		elseif tone < look.darkTone then
			p.Material = look.darkMaterial
		else
			p.Material = look.material
		end
	end
end

function Mutations.goldify(root: Instance)
	Mutations.restyle(root, Mutations.LOOKS.Gold)
end

function Mutations.diamondify(root: Instance)
	Mutations.restyle(root, Mutations.LOOKS.Diamond)
end

-- Whether `mutation` repaints a plant model entirely.
function Mutations.repaints(mutation: string?): boolean
	return mutation ~= nil and table.find(Mutations.REPAINTS, mutation) ~= nil
end

-- Gives the plant model under `root` its mutation's makeover (Haunted, Gold, Diamond); true if it had one.
function Mutations.makeover(root: Instance, mutation: string?): boolean
	if mutation == Halloween.MUTATION then
		Halloween.hauntify(root)
	elseif mutation and Mutations.LOOKS[mutation] then
		Mutations.restyle(root, Mutations.LOOKS[mutation])
	else
		return false
	end
	return true
end

return Mutations
