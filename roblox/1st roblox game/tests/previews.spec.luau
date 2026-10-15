-- The flowers' 3D pictures: Server/FlowerPreviews copies every flower into ReplicatedStorage for the client,
-- Shared/FlowerView puts them in ViewportFrames, and the HUD's Index, Plants, Inventory and Sell cards use it.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Config = H.shared("Config")
local CreatureModels = H.server("CreatureModels")
local FlowerPreviews = H.server("FlowerPreviews")

local HUD = string.gsub(fs.readFile("src/client/HUD.client.luau"), "\r", "")

local BANNED = { "ParticleEmitter", "Light", "LuaSourceContainer", "Sparkles", "Fire", "Smoke", "Trail", "Beam", "Sound",
	"BillboardGui", "SurfaceGui", "ProximityPrompt", "ClickDetector", "JointInstance", "Constraint", "Attachment" }

local previews: any = nil
local function built(): any
	if not previews then
		previews = FlowerPreviews.publish(roblox.Instance.new("Folder"))
	end
	return previews
end

H.test("flower previews: every zone x rarity x flower, plain looks only, inert, measured", function()
	local folder = built()
	H.eq(folder.Name, FlowerPreviews.FOLDER)
	H.eq(FlowerPreviews.FOLDER, "FlowerPreviews")
	local models, parts = 0, 0
	for k in Config.ZONES do
		local zoneFolder = folder:FindFirstChild(tostring(k))
		H.ok(zoneFolder ~= nil, `zone {k}`)
		for r in Config.RARITIES do
			local rarityFolder = zoneFolder and zoneFolder:FindFirstChild(tostring(r))
			H.ok(rarityFolder ~= nil, `zone {k} rarity {r}`)
			local names = CreatureModels.variants(k, r)
			if #names == 0 then
				names = { FlowerPreviews.FALLBACK }
			end
			H.eq(#rarityFolder:GetChildren(), #names, `{k}/{r}: one preview per flower`)
			for _, name in names do
				local model = rarityFolder:FindFirstChild(name)
				H.ok(model and model:IsA("Model"), `{k}/{r}/{name}: a preview`)
				if not model then
					continue
				end
				models += 1
				H.ok((model:GetAttribute("ViewRadius") or 0) > 0 and (model:GetAttribute("ViewHeight") or 0) > 0, `{name}: measured for the camera`)
				local n = 0
				for _, d in model:GetDescendants() do
					for _, class in BANNED do
						H.ok(not d:IsA(class), `{k}/{r}/{name}: no {d.ClassName} ({d.Name})`)
					end
					if d:IsA("BasePart") then
						n += 1
						H.ok(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch and not d.CastShadow, `{d:GetFullName()}: inert`)
					end
				end
				H.ok(n > 0, `{name}: has parts`)
				parts += n
			end
		end
	end
	print(`        flower previews: {models} flowers, {parts} parts in ReplicatedStorage`)
	H.ok(parts < 4000, "light enough to replicate")
	-- Published once at start, replacing an old copy
	local parent = folder.Parent
	FlowerPreviews.publish(parent)
	H.eq(#parent:GetChildren(), 1, "republishing replaces the folder")
	previews = parent:FindFirstChild(FlowerPreviews.FOLDER)
	local main = fs.readFile("src/server/Main.server.luau")
	H.ok(string.find(main, "task.spawn(FlowerPreviews.publish)", 1, true) ~= nil, "published at start")
end)

H.test("plants view: each plant and inventory plant says its flower model (for its 3D picture)", function()
	local plot = fs.readFile("src/server/PlotService.luau")
	local _, count = string.gsub(plot, "flower = CreatureModels.flowerOf%(plant.zone, plant.rarity, plant.variant, plant.slot%)", "")
	H.eq(count, 2, "planted plants and inventory plants")
end)

H.test("FlowerView: finds a flower or seed design, frames it in a ViewportFrame, silhouettes, spins only on screen", function()
	local rs = H.services.ReplicatedStorage
	local FlowerView = H.shared("FlowerView")
	H.eq(FlowerView.FOLDER, FlowerPreviews.FOLDER)
	H.eq(FlowerView.FALLBACK, FlowerPreviews.FALLBACK)
	H.eq(FlowerView.flower(1, 1, "Nope"), nil, "nothing before the previews replicate")
	rs.__children.FlowerPreviews = built()
	-- seed designs, like SeedService.publishLooks
	local looks = roblox.Instance.new("Folder")
	looks.Name = "SeedLooks"
	local zoneLooks = roblox.Instance.new("Folder")
	zoneLooks.Name = "3"
	zoneLooks.Parent = looks
	for d = 1, 2 do
		local m = roblox.Instance.new("Model")
		m.Name = tostring(d)
		m.Parent = zoneLooks
	end
	rs.__children.SeedLooks = looks
	local frames = {}
	local ok, err = pcall(function()
		local name = CreatureModels.variants(2, 3)[1] or FlowerView.FALLBACK
		local model = FlowerView.flower(2, 3, name)
		H.ok(model ~= nil and model.Name == name, "the flower's own preview")
		H.eq(FlowerView.flower(2, 3, nil), FlowerView.flower(2, 3, FlowerView.FALLBACK), "nil: the fallback creature")
		for gene = 1, 4 do
			local look = FlowerView.seed(3, gene)
			H.ok(look ~= nil and look.Name == tostring(Config.geneDesign(gene, 2)), `gene {gene}: its seed design`)
		end
		H.eq(FlowerView.seed(5, 1), nil, "no designs for that zone")

		-- A picture: a ViewportFrame with its camera and a clone of the model
		local gui = roblox.Instance.new("ScreenGui")
		local card = roblox.Instance.new("Frame")
		card.Parent = gui
		local view = FlowerView.show(card, model)
		table.insert(frames, view)
		H.ok(view:IsA("ViewportFrame") and view.Name == "FlowerView" and view.Parent == card, "a ViewportFrame on the card")
		local camera = view:FindFirstChildOfClass("Camera")
		H.ok(camera ~= nil, "its own camera")
		local clone = view:FindFirstChild(name)
		H.ok(clone ~= nil and clone ~= model, "a clone of the preview")
		H.ok(model.Parent ~= view, "the preview itself stays put")
		local eye = camera.CFrame.Position
		local height = model:GetAttribute("ViewHeight")
		H.ok(eye.Y > height / 2, "looking down at it")
		H.ok(eye.Z < 0, "from the front (the flowers face -Z)")
		H.ok(eye.X ~= 0, "at a 3/4 angle")
		-- A silhouette: black, never spinning
		local before = FlowerView.spinCount()
		local dark = FlowerView.show(card, model, { silhouette = true, spin = true })
		table.insert(frames, dark)
		H.eq(dark.ImageColor3, roblox.Color3.new(0, 0, 0), "flat black")
		H.eq(FlowerView.spinCount(), before, "a silhouette doesn't spin")
		-- An empty frame while the previews replicate
		local empty = FlowerView.show(card, nil, { spin = true })
		table.insert(frames, empty)
		H.eq(#empty:GetChildren(), 1, "just its camera")

		-- Spinning: one shared loop turns only the pictures on screen, and drops destroyed ones
		local tick: ((number) -> ())? = nil
		local connections = 0
		H.services.RunService = {
			RenderStepped = {
				Connect = function(_, fn)
					tick = fn
					connections += 1
					return { Disconnect = function() end }
				end,
			},
		}
		local hiddenCard = roblox.Instance.new("Frame")
		hiddenCard.Visible = false
		hiddenCard.Parent = gui
		local shown = FlowerView.show(card, model, { spin = true })
		local hidden = FlowerView.show(hiddenCard, model, { spin = true })
		local gone = FlowerView.show(card, model, { spin = true })
		table.insert(frames, shown)
		H.eq(connections, 1, "one loop for every picture")
		H.eq(FlowerView.spinCount(), 3)
		local function camOf(f: any): any
			return f:FindFirstChildOfClass("Camera").CFrame
		end
		local a, b = camOf(shown), camOf(hidden)
		gone.Parent = nil
		H.ok(tick ~= nil, "the loop runs")
		;(tick :: any)(0.1)
		H.ok(camOf(shown) ~= a, "an on-screen picture turns")
		H.eq(camOf(hidden), b, "a hidden one doesn't")
		H.eq(FlowerView.spinCount(), 2, "a destroyed card's picture drops out")
		H.ok(FlowerView.onScreen(shown) and not FlowerView.onScreen(hidden), "onScreen")
		gui.Enabled = false
		H.ok(not FlowerView.onScreen(shown), "not while its ScreenGui is off")
		hiddenCard.Parent = nil
		shown.Parent = nil
		;(tick :: any)(0.1)
		H.eq(FlowerView.spinCount(), 0, "all gone: nothing left to turn")
	end)
	rs.__children.FlowerPreviews = nil
	rs.__children.SeedLooks = nil
	H.services.RunService = nil
	if not ok then
		error(err, 0)
	end
end)

H.test("HUD: the Index, Plants, Inventory and Sell cards show the flowers in 3D (FlowerView)", function()
	-- The Index: a picture per cell, the found ones turning, the others a silhouette over "???"
	local a = string.find(HUD, "local function renderIndex()", 1, true)
	local b = string.find(HUD, "-- SELL window", 1, true)
	local index = a and b and string.sub(HUD, a, b) or ""
	H.ok(string.find(index, "local FlowerView = require(Shared:WaitForChild(\"FlowerView\"))", 1, true), "the Index uses FlowerView")
	H.ok(string.find(index, "table.insert(out, { key = `{k}:{r}:{model}`, name = Format.plantName(model), model = model })", 1, true), "each cell knows its model")
	H.ok(string.find(index, "FlowerView.show(cell, FlowerView.flower(k, r, c.model), {", 1, true), "the cell's own flower")
	H.ok(string.find(index, "spin = got, silhouette = not got", 1, true), "turning once found, a silhouette until then")
	H.ok(string.find(index, "Text = if got then c.name else \"???\"", 1, true), "names stay a surprise")
	-- The Plants panel: plants and removed plants their own flower, bag seeds their seed design
	a = string.find(HUD, "-- Plants panel (right side)", 1, true)
	b = string.find(HUD, "-- Trail Shop strip scrolling", 1, true)
	local plants = a and b and string.sub(HUD, a, b) or ""
	H.ok(string.find(plants, "local FlowerView = require(Shared:WaitForChild(\"FlowerView\"))", 1, true), "the Plants panel uses FlowerView")
	H.ok(string.find(plants, "FlowerView.show(f, FlowerView.flower(p.zone, p.rarity, p.flower), {", 1, true), "a Plants card: its plant's flower")
	H.ok(string.find(plants, "FlowerView.show(f, look, {", 1, true), "an Inventory card: its look")
	H.ok(string.find(plants, "FlowerView.seed(e.zone, gene)", 1, true), "a bag seed: its seed design (by its gene, like the hotbar)")
	H.ok(string.find(plants, "FlowerView.flower(p.zone, p.rarity, p.flower))", 1, true), "a removed plant: its flower")
	-- The Sell cards
	a = string.find(HUD, "-- SELL window", 1, true)
	b = string.find(HUD, "end of SELL", 1, true)
	local sell = a and b and string.sub(HUD, a, b) or ""
	H.ok(string.find(sell, "FlowerView.show(c, FlowerView.flower(p.zone, p.rarity, p.flower), {", 1, true), "a Sell card: its flower")
	H.ok(string.find(sell, "ReplicatedStorage.ChildAdded:Connect(", 1, true) and string.find(sell, "child.Name == FlowerView.FOLDER", 1, true),
		"drawn again once the previews arrive")
	local spins = 0
	for _ in string.gmatch(HUD, "spin = true") do
		spins += 1
	end
	H.eq(spins, 4, "Plants, Inventory, Sell and the pack reveal's seed turn (only while on screen: FlowerView)")
end)
