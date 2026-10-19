--!strict
-- Colour variants of the plant models (owner 2026-10-19: more visual variety; a late-game garden of the same
-- few models looked copy-pasted, and there are no models left to add). A seed's gene (Config.rollGene) picks
-- a palette as well as its flower: Natural (the model as it is, NATURAL_WEIGHT of the seeds) or one of LIST,
-- each turning the plant toward its hue. Purely cosmetic: income, weight and price never look at it.
--   * The pick (of) hashes the gene (an integer hash, the same on every machine), so it is independent of the
--     flower pick ((gene-1) % n + 1) and of the weight variance (Config.geneVariance): every flower comes in
--     every palette.
--   * A plant keeps its palette (`palette`, nil = Natural; PlantGhosts.seedPlant stores it, ProfileStore saves
--     it), so plants from before palettes stay Natural and never change.
--   * Haunted, Gold, Diamond and Rainbow repaint the whole plant (Shared/Mutations.makeover; the client cycles
--     a Rainbow plant's colours), so a seed of any of them has no palette (ofSeed, shown, OVERRIDDEN); Night
--     and Celestial tint over it.
--   * The recolour (apply) is by colour, whatever the parts' order, like Halloween.hauntify, so the server's
--     plant (CreatureModels.build) and the HUD's 3D picture of it (FlowerView) match. It turns hues only:
--     every colour keeps its saturation and brightness (Neon stays as bright), whites, greys and blacks stay.
local Palettes = {}

export type Palette = { id: string, hue: number, weight: number, swatch: Color3 }

Palettes.NATURAL = "Natural"
Palettes.NATURAL_WEIGHT = 44 -- of 100: the original look stays the most common
-- The palettes in gene order (the weights, with NATURAL_WEIGHT, make 100). Don't reorder or reweigh them: a
-- seed in a bag would grow in another palette. (Amber, not Gold: Gold is a mutation.)
Palettes.LIST = {
	{ id = "Crimson", hue = 350 / 360, weight = 14, swatch = Color3.fromRGB(225, 30, 60) },
	{ id = "Amber", hue = 38 / 360, weight = 14, swatch = Color3.fromRGB(255, 170, 30) },
	{ id = "Azure", hue = 210 / 360, weight = 14, swatch = Color3.fromRGB(40, 140, 255) },
	{ id = "Violet", hue = 280 / 360, weight = 14, swatch = Color3.fromRGB(165, 70, 255) },
} :: { Palette }

-- The mutations that repaint a plant entirely: no palette under them.
Palettes.OVERRIDDEN = { Haunted = true, Gold = true, Diamond = true, Rainbow = true } :: { [string]: boolean }

-- The palette with this id (untrusted), or nil (Natural, or not a palette).
function Palettes.byId(id: any): Palette?
	for _, p in Palettes.LIST do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- 32-bit multiply, exact in doubles (each product stays under 2^53).
local function mul32(a: number, b: number): number
	local lo = a * (b % 65536)
	local hi = (a * (b // 65536)) % 65536
	return (lo + hi * 65536) % 4294967296
end

-- An integer hash of the gene (lowbias32, salted): spreads neighbouring genes and has nothing to do with
-- gene % n or the sine hashes Config uses.
function Palettes.hash(gene: number): number
	local x = bit32.bxor(math.floor(gene) % 4294967296, 0x9e3779b9)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x7feb352d)
	x = bit32.bxor(x, bit32.rshift(x, 15))
	x = mul32(x, 0x846ca68b)
	return bit32.bxor(x, bit32.rshift(x, 16))
end

-- The palette id a gene picks, or nil for Natural.
function Palettes.of(gene: number): string?
	local roll = Palettes.hash(gene) % 100 - Palettes.NATURAL_WEIGHT
	if roll < 0 then
		return nil
	end
	for _, p in Palettes.LIST do
		roll -= p.weight
		if roll < 0 then
			return p.id
		end
	end
	return nil
end

-- The palette a seed of this mutation with this gene grows in (what its plant keeps), nil for Natural: none
-- under a mutation that repaints the plant, none without a gene (a seed from before genes).
function Palettes.ofSeed(gene: number?, mutation: string?): string?
	if not gene or (mutation and Palettes.OVERRIDDEN[mutation]) then
		return nil
	end
	return Palettes.of(gene)
end

-- The palette a plant shows (a known id, not under a repainting mutation), or nil for Natural.
function Palettes.shown(palette: any, mutation: string?): string?
	local p = Palettes.byId(palette)
	if not p or (mutation and Palettes.OVERRIDDEN[mutation]) then
		return nil
	end
	return p.id
end

-- "Azure " before a plant's flower name ("Azure Duality Rose"), "" for Natural.
function Palettes.prefix(palette: any, mutation: string?): string
	local id = Palettes.shown(palette, mutation)
	return if id then id .. " " else ""
end

----------------------------------------------------------------------------------------------------
-- The recolour. A colour is CHROMATIC when it has a hue to turn (saturation at least CHROMA, brightness at
-- least DARK); FOLIAGE when that hue is green (FOLIAGE_LO..FOLIAGE_HI). The plant's own colour is the
-- biggest hue family (BINS around the wheel, by surface) among what turns: its blossom's (every chromatic
-- colour but the foliage) when the blossom covers at least BLOSSOM_SHARE of the surface, so the leaves stay
-- green; otherwise (an all-green plant, a green creature) every chromatic colour. Every colour that turns is
-- rotated round the wheel by the same angle, the one that brings that family's hue onto the palette's, so
-- the plant keeps its contrasts. A plant already of the palette's hue still turns MIN_SHIFT.
----------------------------------------------------------------------------------------------------
Palettes.CHROMA = 0.2
Palettes.DARK = 0.12
Palettes.FOLIAGE_LO = 0.17 -- (61 degrees: yellows are blossom)
Palettes.FOLIAGE_HI = 0.47 -- (169 degrees: teals are blossom)
Palettes.BLOSSOM_SHARE = 0.15
Palettes.BINS = 12
Palettes.MIN_SHIFT = 0.07
Palettes.TINT_SHARE = 0.1
Palettes.TINT = 0.3 -- the wash's saturation...
Palettes.LIGHT = 0.45 -- ...on whites and greys at least this bright

-- The attribute on the parts CreatureModels adds to a plant (Halloween.FLAIR: its halo, the jack-o'-lantern),
-- which keep their colours.
Palettes.FLAIR = "Flair"

local function surface(p: BasePart): number
	local s = p.Size
	return if p.Transparency >= 0.95 then 0 else s.X * s.Y + s.Y * s.Z + s.X * s.Z
end

local function chromatic(c: Color3): (boolean, number)
	local h, s, v = c:ToHSV()
	return s >= Palettes.CHROMA and v >= Palettes.DARK, h
end

local function isFoliage(h: number): boolean
	return h >= Palettes.FOLIAGE_LO and h <= Palettes.FOLIAGE_HI
end

-- How far round the wheel hue `h` is from the foliage's greens (0 among them).
local function fromFoliage(h: number): number
	if isFoliage(h) then
		return 0
	end
	return math.min((Palettes.FOLIAGE_LO - h) % 1, (h - Palettes.FOLIAGE_HI) % 1)
end
Palettes.fromFoliage = fromFoliage

-- shift: the hue turn (a share of the wheel); blossom: only the blossom turns (the foliage stays); tint: the
-- plant has almost no colour (under TINT_SHARE of its surface chromatic: a white crystal), so its light
-- whites and greys take a pale wash of the palette's `hue` too (their brightness kept).
export type Plan = { shift: number, blossom: boolean, tint: boolean, hue: number }

-- How `parts` turn for `palette` (an id): the hue shift (a share of the wheel) and whether only the blossom
-- turns (the foliage stays). nil for Natural, an unknown palette or nothing to turn.
function Palettes.plan(parts: { BasePart }, palette: string?): Plan?
	local p = Palettes.byId(palette)
	if not p then
		return nil
	end
	-- the colours by hex, sorted (sums in a fixed order: the same plan whatever the parts' order)
	type Group = { hex: string, hue: number, area: number, foliage: boolean }
	local byHex: { [string]: Group } = {}
	local groups: { Group } = {}
	local total, blossomArea, chromaArea = 0, 0, 0
	for _, part in parts do
		local area = surface(part)
		total += area
		local turns, h = chromatic(part.Color)
		if turns and area > 0 then
			local hex = part.Color:ToHex()
			local g = byHex[hex]
			if not g then
				g = { hex = hex, hue = h, area = 0, foliage = isFoliage(h) }
				byHex[hex] = g
				table.insert(groups, g)
			end
			g.area += area
			chromaArea += area
		end
	end
	table.sort(groups, function(a, b)
		return a.hex < b.hex
	end)
	for _, g in groups do
		if not g.foliage then
			blossomArea += g.area
		end
	end
	local blossom = total > 0 and blossomArea >= Palettes.BLOSSOM_SHARE * total
	local bins: { number } = table.create(Palettes.BINS, 0)
	for _, g in groups do
		if not blossom or not g.foliage then
			local b = math.clamp(math.floor(g.hue * Palettes.BINS), 0, Palettes.BINS - 1) + 1
			bins[b] += g.area
		end
	end
	local best, bestArea = 0, 0
	for b, area in bins do
		if area > bestArea then
			best, bestArea = b, area
		end
	end
	if best == 0 then -- (nothing has a hue: only the wash)
		return if total > 0 then { shift = 0, blossom = false, tint = true, hue = p.hue } else nil
	end
	local sum, weight = 0, 0
	for _, g in groups do
		if (not blossom or not g.foliage) and math.clamp(math.floor(g.hue * Palettes.BINS), 0, Palettes.BINS - 1) + 1 == best then
			sum += g.hue * g.area
			weight += g.area
		end
	end
	local own = sum / weight
	local shift = (p.hue - own + 0.5) % 1 - 0.5 -- the short way round, in [-0.5, 0.5)
	if math.abs(shift) < Palettes.MIN_SHIFT then
		-- (on past the palette's hue, unless that ends near the greens: then back the other way, so the
		-- blossom never fades into the leaves)
		shift = if shift < 0 then -Palettes.MIN_SHIFT else Palettes.MIN_SHIFT
		if fromFoliage((own + shift) % 1) < Palettes.MIN_SHIFT then
			shift = -shift
		end
	end
	return { shift = shift, blossom = blossom, tint = chromaArea < Palettes.TINT_SHARE * total, hue = p.hue }
end

-- `c` turned by `plan`: its hue rotated (saturation and brightness kept) when it turns (a light white or grey
-- of a colourless plant: washed with the palette's hue), else as it is.
function Palettes.recolor(c: Color3, plan: Plan): Color3
	local h, s, v = c:ToHSV()
	if s < Palettes.CHROMA or v < Palettes.DARK then
		return if plan.tint and v >= Palettes.LIGHT then Color3.fromHSV(plan.hue, math.max(s, Palettes.TINT), v) else c
	elseif plan.blossom and isFoliage(h) then
		return c
	end
	return Color3.fromHSV((h + plan.shift) % 1, s, v)
end

local function recolorSequence(seq: ColorSequence, plan: Plan): ColorSequence
	local keys = {}
	for _, k in seq.Keypoints do
		table.insert(keys, ColorSequenceKeypoint.new(k.Time, Palettes.recolor(k.Value, plan)))
	end
	return ColorSequence.new(keys)
end

-- Gives every part, particle emitter, beam and light under `root` (not our Flair) the palette's colours (see
-- above). Nothing for Natural.
function Palettes.apply(root: Instance, palette: string?)
	local parts: { BasePart } = {}
	local effects: { Instance } = {}
	for _, d in root:GetDescendants() do
		if d:GetAttribute(Palettes.FLAIR) then
			continue
		elseif d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Light") then
			table.insert(effects, d)
		end
	end
	local plan = Palettes.plan(parts, palette)
	if not plan then
		return
	end
	for _, p in parts do
		p.Color = Palettes.recolor(p.Color, plan)
	end
	for _, e in effects do
		if e:IsA("ParticleEmitter") or e:IsA("Beam") then
			e.Color = recolorSequence(e.Color, plan)
		elseif e:IsA("Light") then
			e.Color = Palettes.recolor(e.Color, plan)
		end
	end
end

return Palettes
