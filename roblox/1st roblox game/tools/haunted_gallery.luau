-- Builds a viewing place with every plant of the Haunted set (Halloween.SET), built exactly as the game plants
-- them (CreatureModels.build with the Haunted mutation: hauntify, wisps, the jack-o'-lantern): a row per zone,
-- Common to Legendary from left to right, each on a pad in its rarity's colour with a "Name / Rarity" label,
-- at dusk. Run from the game folder:
--   lune run tools/haunted_gallery.luau <out.rbxl>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("../tests/harness")

local Config = H.shared("Config")
local Halloween = H.shared("Halloween")
local CreatureModels = H.server("CreatureModels")
local Instance, Vector3, CFrame, Color3, UDim2 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.UDim2

local out = process.args[1]
assert(out, "usage: lune run tools/haunted_gallery.luau <out.rbxl>")

local SPACING_X, SPACING_Z = 22, 34

local game = Instance.new("DataModel")
local ws = game:GetService("Workspace")
local lighting = game:GetService("Lighting")
lighting.ClockTime = 18.6
lighting.Brightness = 1.6
lighting.Ambient = Color3.fromRGB(95, 70, 130)
lighting.OutdoorAmbient = Color3.fromRGB(120, 95, 150)

local function part(name: string, size: any, cf: any, color: any, parent: any): any
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = roblox.Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function label(adornee: any, text: string, color: any, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(8, 2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 140
	gui.Adornee = adornee
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.RichText = true
	t.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
	t.TextColor3 = color
	t.TextStrokeTransparency = 0
	t.Text = text
	t.Parent = gui
	gui.Parent = adornee
end

local rows = #Config.ZONES
local cols = 0
for k = 1, rows do
	local n = 0
	for r = 1, #Config.RARITIES do
		n += #Halloween.setFlowers(k, r)
	end
	cols = math.max(cols, n)
end

part("Ground", Vector3.new(cols * SPACING_X + 60, 2, rows * SPACING_Z + 80), CFrame.new(0, -1, (rows - 1) * SPACING_Z / 2),
	Color3.fromRGB(45, 32, 60), ws)
local spawn = Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = Vector3.new(8, 1, 8)
spawn.CFrame = CFrame.new(0, 0.5, -30)
spawn.Color = Color3.fromRGB(255, 125, 20)
spawn.Parent = ws

local placed = 0
for k = 1, rows do
	local zone = Config.ZONES[k]
	local z = (k - 1) * SPACING_Z
	local zoneSign = part("Zone_" .. zone.id, Vector3.new(4, 1, 4), CFrame.new(-(cols + 1) * SPACING_X / 2 - 6, 0.5, z), Color3.fromRGB(255, 125, 20), ws)
	label(zoneSign, string.upper(zone.name), Color3.fromRGB(255, 160, 40), 4)
	local col = 0
	for r, rarity in Config.RARITIES do
		for _, name in Halloween.setFlowers(k, r) do
			local pick = table.find(CreatureModels.variants(k, r), name)
			if pick then
				local x = (col - (cols - 1) / 2) * SPACING_X
				local plant = CreatureModels.build(k, r, Halloween.MUTATION, pick)
				plant.Name = name
				-- (built on the origin; Lune has no PivotTo) to (x, 1, z), facing the spawn
				local to = CFrame.new(x, 1, z) * CFrame.Angles(0, math.pi, 0)
				for _, d in plant:GetDescendants() do
					if d:IsA("BasePart") then
						d.CFrame = to * d.CFrame
						d.Anchored = true
					end
				end
				plant.Parent = ws
				local pad = part("Pad", Vector3.new(SPACING_X - 4, 1, SPACING_X - 4), CFrame.new(x, 0.5, z), rarity.color:Lerp(Color3.new(0, 0, 0), 0.35), plant)
				label(pad, `{name}\n<font size="20">{rarity.id}</font>`, Color3.new(1, 1, 1), Config.creatureHeight(k, r) + 3)
				placed += 1
			else
				print(`missing: {zone.id} {rarity.id} {name}`)
			end
			col += 1
		end
	end
end

fs.writeFile(out, roblox.serializePlace(game))
print(`placed {placed} Haunted plants in {out}`)
