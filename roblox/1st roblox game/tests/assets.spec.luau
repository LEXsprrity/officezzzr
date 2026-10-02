-- Drop-in models (Assets): the friend's real files in assets/, dummy models built here and injected into
-- ServerStorage.Assets, fitting, collision, variants, fallbacks, creatures and a whole map built with them.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Instance, Vector3, CFrame, Enum = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Enum
local Config = H.shared("Config")
local Assets = H.server("Assets")
local Props = H.server("Props")
local WorldBuilder = H.server("WorldBuilder")
local CreatureModels = require("./creature_loader").CreatureModels

local FAR = Vector3.new(500, 200, -300) -- where dummies sit before they're placed (Studio-like world coordinates)

-- A Model like one saved from Studio: unanchored, colliding parts somewhere far away. `boxes` are
-- { size, offset } pairs.
local function dummy(name: string, boxes: { { any } }, attrs: { [string]: any }?): any
	local m = Instance.new("Model")
	m.Name = name
	for i, b in boxes do
		local p = Instance.new("Part")
		p.Name = "Piece" .. i
		p.Size = b[1]
		p.CFrame = CFrame.new(FAR + b[2])
		p.Anchored = false
		p.CanCollide = true
		p.Parent = m
	end
	for k, v in attrs or {} do
		m:SetAttribute(k, v)
	end
	m.Parent = H.assets
	return m
end

local function scratch(): any
	local f = Instance.new("Folder")
	f.Name = "Scratch"
	f.Parent = H.workspace
	return f
end

local function partsOf(root: any): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function named(root: any, name: string): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d.Name == name then
			n += 1
		end
	end
	return n
end

local function warnedAbout(text: string): boolean
	for _, w in H.warnings do
		if string.find(w, text, 1, true) then
			return true
		end
	end
	return false
end

local function near(a: any, b: any, eps: number): boolean
	return (a - b).Magnitude <= eps
end

----------------------------------------------------------------------------------------------------
-- The friend's real files
----------------------------------------------------------------------------------------------------
H.test("assets: every file in assets/ loads and is named after a slot (or an alias)", function()
	H.eq(#H.assetErrors, 0, "files that don't load: " .. table.concat(H.assetErrors, "; "))
	for _, child in H.assets:GetChildren() do
		H.ok(Assets.slotFor(child.Name) ~= nil, `assets/{child.Name} matches no slot (check the name against assets/COMO_ADICIONAR_MODELOS.md)`)
	end
end)

H.test("assets: names match without case, accents, spaces or underscores, and Portuguese aliases work", function()
	for name, slot in {
		arvores = "Tree", ["Árvores"] = "Tree", ARVORES = "Tree", arbustos = "Bush", Arbustos = "Bush", Pedras = "Rock",
		Flores = "Flower", Postes = "Lamp", Cercas = "FenceSection", ["desert cactus"] = "Desert_Cactus",
		["creature_lotuswyrm"] = "Creature_LotusWyrm", ["Boneco de Neve"] = "Snow_Snowman", ["Portão"] = "PlotGate",
	} do
		H.eq(Assets.slotFor(name), slot, name)
	end
	H.eq(Assets.slotFor("Arvroes"), nil, "a typo matches nothing")
end)

H.test("assets: the friend's Arvores (3 variants) and Arbustos load as Tree and Bush", function()
	local tree, treeSlot = Assets.get("Tree")
	H.ok(tree ~= nil and tree:IsA("Folder"), "assets/arvores.rbxm is a folder of variants")
	H.eq(treeSlot, "Tree")
	local variants = {}
	for _, v in tree:GetChildren() do
		H.ok(v:IsA("Model"), v.Name .. " is a Model")
		H.eq(#partsOf(v), 2, v.Name .. ": trunk + canopy MeshParts")
		variants[v.Name] = true
	end
	for _, name in { "arvore_variant1", "arvore_variant2", "arvore_variant3" } do
		H.ok(variants[name], name)
	end
	local bush = Assets.get("Bush")
	H.ok(bush ~= nil and #partsOf(bush) == 1 and partsOf(bush)[1]:IsA("MeshPart"), "assets/arbustos.rbxm: one bush MeshPart")
end)

H.test("assets: tree variants are picked deterministically from the position, fitted, anchored and non-colliding", function()
	local folder = scratch()
	local fit = Vector3.new(16, 18, 16)
	local seen = {}
	for i = 1, 40 do
		local pos = Vector3.new(i * 37.3 - 600, 2, (i % 7) * 23.1 - 80)
		local cf = Assets.spin(pos)
		local a = Assets.place("Tree", folder, cf, fit)
		local b = Assets.place("Tree", folder, cf, fit)
		H.ok(a and b, "placed")
		H.eq(a:GetAttribute("Asset"), b:GetAttribute("Asset"), "same spot, same variant")
		seen[a:GetAttribute("Asset")] = true
		H.eq(a.Name, "Tree")
		-- fitted: inside the box, touching it on at least one axis, bottom centre on the pivot
		local lo, hi = Assets.bounds(a, cf)
		local size = hi - lo
		H.ok(size.X <= fit.X + 1e-3 and size.Y <= fit.Y + 1e-3 and size.Z <= fit.Z + 1e-3, `fits the box: {size}`)
		H.ok(math.abs(size.Y - fit.Y) < 1e-2 or math.abs(size.X - fit.X) < 1e-2 or math.abs(size.Z - fit.Z) < 1e-2, `fills the box: {size}`)
		H.ok(math.abs(lo.Y) < 1e-3, `stands on the ground ({lo.Y})`)
		H.ok(math.abs(lo.X + hi.X) < 1e-2 and math.abs(lo.Z + hi.Z) < 1e-2, "centred on the pivot")
		H.ok(near(Assets.pivotOf(a).Position, pos, 1e-3), "its pivot is the placement point")
		for _, p in partsOf(a) do
			H.ok(p:IsA("MeshPart"), "MeshParts stay MeshParts")
			H.ok(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery, `{p.Name}: anchored decoration`)
		end
		if a:GetAttribute("Asset") == "arvore_variant3" then
			local materials = {}
			for _, p in partsOf(a) do
				materials[tostring(p.Material)] = true
			end
			H.ok(materials[tostring(Enum.Material.Wood)] and materials[tostring(Enum.Material.Grass)], "variant3 keeps its Wood/Grass materials")
		end
	end
	for _, name in { "arvore_variant1", "arvore_variant2", "arvore_variant3" } do
		H.ok(seen[name], name .. " gets picked somewhere")
	end
	-- the templates themselves are never touched
	for _, p in partsOf(Assets.get("Tree")) do
		H.ok(not p.Anchored and p.CanCollide, "the template keeps its saved settings")
	end
	folder:Destroy()
end)

H.test("assets: the friend's trees and bushes replace the built-in ones, and the random layout doesn't shift", function()
	local folder = scratch()
	local rngA = H.Random.new(77)
	local tree = Props.roundTree(folder, Vector3.new(10, 0, 10), rngA, Config.ZONES[1].seedColor)
	H.ok(tree and tree:GetAttribute("Asset") ~= nil, "the Tree slot uses a model from assets/")
	H.eq(named(folder, "Trunk"), 0, "no built-in trunk")
	local bush = Props.bush(folder, Vector3.new(30, 0, 10), 5, Config.ZONES[1].seedColor)
	H.eq(bush and bush:GetAttribute("Asset"), "arbusto")
	-- the same draw without the asset folder's tree: the random sequence carries on identically
	local trees = Assets.get("Tree")
	trees.Parent = nil
	local rngB = H.Random.new(77)
	local built = Props.roundTree(folder, Vector3.new(50, 0, 10), rngB, Config.ZONES[1].seedColor)
	trees.Parent = H.assets
	H.ok(built and built:GetAttribute("Asset") == nil and named(built, "Trunk") == 1, "without the asset the tree is built from code")
	H.eq(rngA:NextNumber(), rngB:NextNumber(), "same random sequence afterwards")
	folder:Destroy()
end)

----------------------------------------------------------------------------------------------------
-- Dummy models
----------------------------------------------------------------------------------------------------
H.test("assets: a dummy lamp replaces the built-in one: fitted, anchored, non-colliding, scripts dropped, light kept", function()
	local m = dummy("Postes", { { Vector3.new(1, 10, 1), Vector3.new(0, 5, 0) }, { Vector3.new(3, 2, 3), Vector3.new(0.5, 11, 0) } })
	Instance.new("Script").Parent = m.Piece1
	local folder = scratch()
	local lamp = Props.lamp(folder, Vector3.new(0, 0, 0), roblox.Color3.new(1, 1, 0.6))
	m:Destroy()
	H.ok(lamp ~= nil and lamp:GetAttribute("Asset") == "Postes", "the alias Postes fills the Lamp slot")
	H.eq(named(folder, "LampPost"), 0, "no built-in post")
	local lo, hi = Assets.bounds(lamp)
	H.near(hi.Y - lo.Y, 10.5, 0.01, "as tall as the built-in lamp")
	H.near(lo.Y, 0, 1e-3, "stands on the ground")
	H.eq(lamp:GetAttribute("AssetSlot"), "Lamp")
	for _, p in partsOf(lamp) do
		H.ok(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery, "anchored decoration")
	end
	H.eq(named(lamp, "Script"), 0, "scripts are dropped")
	local light = nil
	for _, d in lamp:GetDescendants() do
		if d:IsA("PointLight") then
			light = d
		end
	end
	H.ok(light ~= nil and light.Parent:IsA("Attachment"), "the lamp's light carries over")
	local spot = (light.Parent.Parent.CFrame * light.Parent.CFrame).Position
	H.ok(spot.Y > 8, `the light sits near the top ({spot.Y})`)
	folder:Destroy()
end)

H.test("assets: KeepScale keeps the saved size, Yaw turns the model, solid slots keep their collision", function()
	local folder = scratch()
	local keep = dummy("Rock", { { Vector3.new(4, 2, 6), Vector3.zero } }, { KeepScale = true })
	local rock = Assets.place("Rock", folder, CFrame.new(1, 0, 1), Vector3.new(1, 1, 1))
	keep:Destroy()
	local lo, hi = Assets.bounds(rock)
	H.ok(near(hi - lo, Vector3.new(4, 2, 6), 1e-3), "KeepScale: not resized")

	local turned = dummy("Rock", { { Vector3.new(8, 2, 2), Vector3.zero } }, { Yaw = 90 })
	rock = Assets.place("Rock", folder, CFrame.new(0, 0, 0), Vector3.new(100, 4, 100))
	turned:Destroy()
	lo, hi = Assets.bounds(rock)
	H.ok(hi.Z - lo.Z > hi.X - lo.X + 1, "Yaw = 90 turns the long side from X to Z")

	local post = dummy("FencePost", { { Vector3.new(1, 6, 1), Vector3.zero } })
	local placed = Assets.place("FencePost", folder, CFrame.new(0, 0, 0), Vector3.new(2, 5.6, 2))
	post:Destroy()
	for _, p in partsOf(placed) do
		H.ok(p.Anchored and p.CanCollide, "a solid slot keeps CanCollide")
		H.ok(not p.CanTouch, "but never fires Touched")
	end
	folder:Destroy()
end)

H.test("assets: a missing or broken model falls back to the built-in piece, with a warning", function()
	local folder = scratch()
	H.eq(Assets.place("Lava_Rock", folder, CFrame.new(0, 0, 0), Vector3.one), nil, "no model: nil")
	for _, case in {
		{ name = "Desert_Mesa", make = function() return dummy("Desert_Mesa", {}) end, why = "no parts" },
		{ name = "Desert_Bone", make = function()
			local m = dummy("Desert_Bone", { { Vector3.one, Vector3.zero } })
			m.Piece1.Transparency = 1
			return m
		end, why = "no visible parts" },
		{ name = "Snow_Crystal", make = function()
			local f = Instance.new("Folder")
			f.Name = "Snow_Crystal"
			f.Parent = H.assets
			return f
		end, why = "empty folder" },
	} do
		local bad = case.make()
		H.eq(Assets.place(case.name, folder, CFrame.new(0, 0, 0), Vector3.one), nil, case.why)
		H.ok(warnedAbout(case.name), `{case.why}: warned`)
		local group = Assets.swap(case.name, folder, CFrame.new(0, 0, 0), function(into)
			Props.deco(into, "BuiltIn", Vector3.one, CFrame.new(0, 0.5, 0), roblox.Color3.new(1, 1, 1))
		end)
		H.ok(group and group:GetAttribute("Asset") == nil and named(group, "BuiltIn") == 1, `{case.why}: the built-in piece stays`)
		bad:Destroy()
	end
	folder:Destroy()
end)

H.test("assets: a file that matches no slot is reported", function()
	local typo = dummy("Arvroes", { { Vector3.one, Vector3.zero } })
	Assets.audit()
	typo:Destroy()
	H.ok(warnedAbout("assets/Arvroes matches no slot"), "warned about the typo")
end)

H.test("assets: a Creature_ model replaces the plant-creature and still gets rarity and mutation flair", function()
	local m = dummy("Creature_Sproutling", { { Vector3.new(6, 8, 6), Vector3.new(0, 4, 0) }, { Vector3.new(2, 2, 2), Vector3.new(0, 9, -2) } })
	local model = CreatureModels.build(1, 5, "Gold")
	m:Destroy()
	H.eq(model:GetAttribute("Asset"), "Creature_Sproutling")
	H.ok(model.PrimaryPart ~= nil, "has a body")
	H.eq(model:GetAttribute("Mutation"), "Gold")
	H.ok(named(model, "HaloOrb") == 6 and named(model, "AuraRing") == 1, "Legendary flair")
	H.eq(named(model, "InfoAnchor"), 1, "InfoAnchor for the label")
	local radius, height = CreatureModels.extents(model)
	H.ok(radius <= Config.CREATURE_FOOTPRINT, `within the footprint ({radius})`)
	H.ok(height > 4 and height < 7, `zone-1 height ({height})`)
	for _, p in partsOf(model) do
		H.ok(p.Anchored and not p.CanCollide and not p.CanQuery, "anchored decoration")
	end
	H.eq(CreatureModels.build(1, 1, nil).PrimaryPart.Name, "Body", "without it, the built-in creature")
end)

H.test("assets: every slot the code uses is known, and the guide lists every slot", function()
	H.ok(not warnedAbout("unknown slot"), "the code asked for a slot missing from Assets.SLOTS")
	local guide = fs.readFile("assets/COMO_ADICIONAR_MODELOS.md")
	for _, slot in Assets.SLOTS do
		H.ok(string.find(guide, "`" .. slot .. "`", 1, true) ~= nil, `the guide lists {slot}`)
	end
	for _, zone in Config.ZONES do
		H.ok(table.find(Assets.SLOTS, "Guard_" .. string.gsub(zone.guard, "%s", "")) ~= nil, zone.guard)
		H.ok(table.find(Assets.SLOTS, "Creature_" .. string.gsub(zone.seed, "%s", "")) ~= nil, zone.seed)
	end
end)

H.test("assets: a whole map built with dummy models keeps its contract (roles, prompts, no colliding props)", function()
	local slots = { "Arch_Meadow", "Nest_Desert", "Treadmill", "UpgradeSign", "PlotGate", "ShopStall", "SpawnSign", "FenceSection", "Spirit_Torii", "Lava_Volcano" }
	local made = {}
	for _, slot in slots do
		table.insert(made, dummy(slot, { { Vector3.new(4, 6, 2), Vector3.zero }, { Vector3.new(2, 2, 2), Vector3.new(0, 4, 0) } }))
	end
	local plots, nests = WorldBuilder.build() -- asserts the generated map adopts cleanly
	for _, m in made do
		m:Destroy()
	end
	local world = H.workspace:FindFirstChild("World")
	local used = {}
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Asset") then
			used[d:GetAttribute("AssetSlot")] = (used[d:GetAttribute("AssetSlot")] or 0) + 1
		end
	end
	H.eq(used.ShopStall_Shop, 1, "the shared ShopStall fills each stall")
	H.eq(used.ShopStall_Index, 1)
	for _, slot in slots do
		if slot ~= "ShopStall" then
			H.ok((used[slot] or 0) >= 1, slot .. " used")
		end
	end
	H.eq(#plots, Config.MAX_PLAYERS)
	H.eq(#nests[2].podCFrames, Config.PODS_PER_NEST, "the Desert nest keeps its pods")
	local prompts = 0
	for _, d in world:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("OpensShop") then
			prompts += 1
		end
	end
	H.eq(prompts, 3, "the stall prompts stay")
	local allowed = { Floor = true, Wall = true, GatePillar = true, EndWall = true }
	for _, p in partsOf(world.Corridor) do
		H.ok(p.Anchored, p:GetFullName() .. " anchored")
		if p.CanCollide and not allowed[p.Name] then
			error(`{p:GetFullName()} collides`)
		end
	end
	local volcano = nil
	for _, d in world:GetDescendants() do
		if d:GetAttribute("AssetSlot") == "Lava_Volcano" then
			volcano = d
		end
	end
	H.ok(volcano and #volcano:GetDescendants() > 0, "volcano")
	local emitters = 0
	for _, d in volcano:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			emitters += 1
		end
	end
	H.eq(emitters, 2, "the crater's smoke and embers carry over to the volcano model")
	WorldBuilder.build() -- leave a map built only from the real assets folder
end)

return nil
