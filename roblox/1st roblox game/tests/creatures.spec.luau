-- Plant-creature models: every zone builds within budget, rarity/mutation flair, size vs weight, slot fit.
local roblox = require("@lune/roblox")
local H = require("./harness")
local loaded = require("./creature_loader")

local CreatureModels, Config = loaded.CreatureModels, loaded.Config

local function find(model, name: string)
	local out = {}
	for _, d in model:GetDescendants() do
		if d.Name == name then
			table.insert(out, d)
		end
	end
	return out
end

-- The built-in creatures (the game falls back to them when assets/ has no plant model): these tests
-- set the plant models aside (tests/plants.spec checks those).
local function builtIn(name: string, fn: () -> ())
	H.test(name, function()
		H.withoutAssets("Creature_", fn)
	end)
end

builtIn("creatures: every zone x rarity x mutation builds within the part and footprint budget", function()
	local mutations = { false }
	for _, m in Config.MUTATIONS do
		table.insert(mutations, m.id)
	end
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			for _, mut in mutations do
				local label = `{Config.ZONES[k].seed} r{r} {mut or "-"}`
				local model = CreatureModels.build(k, r, mut or nil)
				local n = CreatureModels.partCount(model)
				H.ok(n >= 15 and n <= 40, `{label}: {n} parts`)
				H.ok(model.PrimaryPart ~= nil and model.PrimaryPart.Name == "Body", label .. ": PrimaryPart is Body")
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						H.ok(d.Anchored and not d.CanCollide and not d.CanQuery, `{label}: {d.Name} anchored, no collide/query`)
					end
				end
				local radius = CreatureModels.extents(model)
				H.ok(radius <= Config.CREATURE_FOOTPRINT / 2 + 0.01, `{label}: footprint radius {radius}`)
				H.eq(#find(model, "InfoAnchor"), 1, label .. " InfoAnchor")
				H.eq(#find(model, "PromptAnchor"), 1, label .. " PromptAnchor")
				H.eq(model:GetAttribute("Mutation"), mut or nil, label .. " Mutation attribute")
				model:Destroy()
			end
		end
	end
end)

builtIn("creatures: later zones stand taller, and the Info anchor sits above the top", function()
	local last = 0
	for k = 1, #Config.ZONES do
		local model = CreatureModels.build(k, 1, nil)
		local _, height = CreatureModels.extents(model)
		H.ok(height > last + 0.1, `{Config.ZONES[k].seed} height {height} vs previous {last}`)
		H.ok(height >= 4, `{Config.ZONES[k].seed} at least 4 studs tall`)
		local anchor = find(model, "InfoAnchor")[1]
		H.ok((model.PrimaryPart.CFrame * anchor.CFrame).Position.Y > height, "InfoAnchor above the creature")
		last = height
		model:Destroy()
	end
end)

builtIn("creatures: rarity adds flair step by step", function()
	local function flair(r)
		local model = CreatureModels.build(1, r, nil)
		local out = {
			ring = #find(model, "AuraRing"),
			light = #model.PrimaryPart:GetChildren() > 0 and model.PrimaryPart:FindFirstChildOfClass("PointLight") ~= nil,
			sparkles = #find(model, "RaritySparkles"),
			halo = #find(model, "HaloOrb"),
			neonTrim = find(model, "Bud")[1].Material == roblox.Enum.Material.Neon,
		}
		model:Destroy()
		return out
	end
	local common, uncommon, rare, epic, legendary = flair(1), flair(2), flair(3), flair(4), flair(5)
	H.eq(common.ring, 0, "common ring")
	H.ok(not common.light and not common.neonTrim, "common is plain")
	H.eq(uncommon.ring, 1, "uncommon ring")
	H.ok(rare.light and rare.neonTrim, "rare glows")
	H.eq(rare.sparkles, 0, "rare sparkles")
	H.eq(epic.sparkles, 1, "epic sparkles")
	H.eq(legendary.halo, 6, "legendary halo")
end)

builtIn("creatures: mutations tint, swap materials and add particles", function()
	for _, m in Config.MUTATIONS do
		local plain = CreatureModels.build(2, 1, nil)
		local model = CreatureModels.build(2, 1, m.id)
		H.eq(#find(model, "MutationSparkles"), 1, m.id .. " particles")
		H.ok(model.PrimaryPart:FindFirstChildOfClass("PointLight") ~= nil, m.id .. " light")
		if m.id == "Gold" then
			H.eq(model.PrimaryPart.Material, roblox.Enum.Material.Foil, "gold is foil")
		elseif m.id == "Rainbow" then
			H.eq(model.PrimaryPart:GetAttribute("Mutation"), "Rainbow", "rainbow body cycles on the client")
		elseif m.id == "Celestial" then
			H.ok(model.PrimaryPart.Color ~= plain.PrimaryPart.Color, "celestial tints the body")
			H.ok(model.PrimaryPart.Reflectance > 0, "celestial body has a sheen")
			for _, petal in find(model, "Petal") do
				H.eq(petal.Material, roblox.Enum.Material.Neon, "celestial petals glow")
			end
			H.eq(#find(model, "HaloOrb"), 6, "celestial halo even on a Common")
			H.eq(find(model, "MutationSparkles")[1].LightEmission, 1, "celestial stars glow")
		else
			H.ok(model.PrimaryPart.Color ~= plain.PrimaryPart.Color, m.id .. " tints the body")
		end
		plain:Destroy()
		model:Destroy()
	end
end)

H.test("creatures: scale grows with weight and rarity, within the clamp", function()
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			local last = 0
			for step = 0, 10 do
				local w = Config.plantWeight(k, r, Config.GROW_TIME * step / 10, 1)
				local s = CreatureModels.scaleFor(k, r, w)
				H.ok(s >= last, "monotonic in weight")
				H.ok(s >= Config.CREATURE_MIN_SCALE and s <= Config.CREATURE_MAX_SCALE, "clamped")
				last = s
			end
		end
	end
	local sprout = CreatureModels.scaleFor(1, 1, Config.sproutWeight(1, 1))
	local grown = CreatureModels.scaleFor(1, 1, Config.sproutWeight(1, 1) * Config.GROW_MAX_FACTOR)
	H.ok(grown / sprout >= 1.7, `full-grown is visibly bigger ({grown / sprout}x)`)
	H.ok(CreatureModels.scaleFor(1, 5, Config.sproutWeight(1, 5)) > sprout, "legendary sprout is bigger than common")
end)
H.test("creatures: the biggest creatures fit the planting spacing and the plot", function()
	local Planting = H.shared("Planting")
	-- Planting spaces plants by their full-grown reach: never smaller than the real biggest creature
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			local biggest = CreatureModels.scaleFor(k, r, Config.sproutWeight(k, r) * Config.GROW_MAX_FACTOR * 1.2)
			H.ok(Planting.radius(r) >= Config.creatureFootprint(r) * biggest / 2 - 1e-6, `zone {k} rarity {r} reach`)
		end
	end
	local L = #Config.RARITIES
	H.ok(math.abs(Planting.radius(L) - Config.creatureFootprint(L) * Config.CREATURE_MAX_SCALE / 2) < 0.2, "the biggest reach is about the max scale")
	H.ok(2 * Planting.radius(L) - Planting.minDistance(L, L) <= 1 + 1e-6, "neighbours overlap by at most a stud")
	-- Common..Rare (the base footprint) fit the default grid, and every default spot keeps them inside the fence
	local small = 0
	for r = 1, L do
		if Config.creatureFootprint(r) <= Config.CREATURE_FOOTPRINT then
			small = r
		end
	end
	H.ok(small >= 3, "Common..Rare have the base footprint")
	H.ok(Planting.minDistance(small, small) <= Config.SLOT_SPACING, "two full-grown Rares fit the default grid")
	local half = Config.PLOT_SIZE / 2
	local reach = Planting.radius(small)
	for i, c in Planting.candidates() do
		H.ok(math.abs(c[1]) + reach <= half - 0.5 and math.abs(c[2]) + reach <= half - 0.5, `spot {i} ({c[1]}, {c[2]}) fits inside the fence`)
	end
	-- the bigger ones (Epic, Legendary) must stand further inside the bed, so they reach at most
	-- PLANT_FENCE_OVERHANG past the fence line from anywhere planting allows
	local outer = half - Config.BED_FENCE_GAP
	for r = 1, L do
		H.ok(outer - Planting.bedMargin(r) + Planting.radius(r) <= half + Config.PLANT_FENCE_OVERHANG + 1e-6, `rarity {r} stays off the fence`)
		H.ok(Planting.bedMargin(r) >= Config.PLANT_BED_MARGIN, `rarity {r} margin`)
	end
	H.ok(Planting.bedMargin(L) > Planting.bedMargin(1), "Legendaries stand further inside the bed")
end)

H.test("creatures: applyScale keeps an uploaded template's fit (BaseScale)", function()
	-- Lune has no Model:ScaleTo, so this mock follows Roblox: ScaleTo sets an absolute scale factor
	-- relative to the original asset, and a clone of a fitted template keeps that factor.
	local function mockModel(attrs)
		local m = { scale = attrs.BaseScale or 1, attrs = attrs }
		function m:ScaleTo(s)
			self.scale = s
		end
		function m:GetAttribute(k)
			return self.attrs[k]
		end
		function m:SetAttribute(k, v)
			self.attrs[k] = v
		end
		function m:GetDescendants()
			return {}
		end
		return m
	end
	local template = mockModel({ BaseScale = 0.12 }) -- e.g. a 50-stud asset fitted down to ~6 studs
	CreatureModels.applyScale(template, 1.9)
	H.near(template.scale, 0.12 * 1.9, 1e-9, "scale is relative to the fitted size")
	H.eq(template.attrs.Scale, 1.9, "Scale attribute stays the logical scale")
	CreatureModels.applyScale(template, 2.5)
	H.near(template.scale, 0.12 * 2.5, 1e-9, "rescaling stays relative to the fit")
	local procedural = mockModel({})
	CreatureModels.applyScale(procedural, 1.9)
	H.near(procedural.scale, 1.9, 1e-9, "procedural creatures have no BaseScale")
end)

return nil
