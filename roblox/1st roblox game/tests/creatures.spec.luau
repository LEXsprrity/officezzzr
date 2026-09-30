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

H.test("creatures: every zone x rarity x mutation builds within the part and footprint budget", function()
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

H.test("creatures: later zones stand taller, and the Info anchor sits above the top", function()
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

H.test("creatures: rarity adds flair step by step", function()
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

H.test("creatures: mutations tint, swap materials and add particles", function()
	for _, m in Config.MUTATIONS do
		local plain = CreatureModels.build(2, 1, nil)
		local model = CreatureModels.build(2, 1, m.id)
		H.eq(#find(model, "MutationSparkles"), 1, m.id .. " particles")
		H.ok(model.PrimaryPart:FindFirstChildOfClass("PointLight") ~= nil, m.id .. " light")
		if m.id == "Gold" then
			H.eq(model.PrimaryPart.Material, roblox.Enum.Material.Foil, "gold is foil")
		elseif m.id == "Rainbow" then
			H.eq(model.PrimaryPart:GetAttribute("Mutation"), "Rainbow", "rainbow body cycles on the client")
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

H.test("creatures: the biggest creatures fit their slots and the plot", function()
	local r = Config.CREATURE_FOOTPRINT * Config.CREATURE_MAX_SCALE / 2
	H.ok(2 * r - Config.SLOT_SPACING <= 1, `max-size neighbours overlap by {2 * r - Config.SLOT_SPACING} studs`)
	local half = Config.PLOT_SIZE / 2
	for i = 1, Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS do
		-- mirrors WorldBuilder's slotLocal: u across the plot, w inward from the gate
		local row = (i - 1) // Config.SLOT_COLUMNS
		local col = (i - 1) % Config.SLOT_COLUMNS
		local u = (col - (Config.SLOT_COLUMNS - 1) / 2) * Config.SLOT_SPACING
		local w = 46 + row * Config.SLOT_SPACING
		H.ok(math.abs(u) + r <= half - 0.5, `slot {i} fits across ({math.abs(u) + r})`)
		H.ok(w + r <= Config.PLOT_SIZE - 0.5, `slot {i} fits before the back fence ({w + r})`)
	end
end)

return nil
