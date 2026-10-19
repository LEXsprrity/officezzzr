-- Builds a viewing place with a mutation's plants, built exactly as the game plants them (CreatureModels.build
-- with that mutation: for Haunted hauntify, wisps and the jack-o'-lantern; for Gold and Diamond their makeover,
-- Shared/Mutations): a row per zone, Common to Legendary from left to right, each on a pad in its rarity's colour
-- with a "Name / Rarity" label. Haunted shows the Haunted set (Halloween.SET) at dusk; any other mutation every
-- plant model, in daylight. Run from the game folder:
--   lune run tools/haunted_gallery.luau <out.rbxl> [Mutation]     (Mutation: Haunted when left out)
--   e.g. lune run tools/haunted_gallery.luau "$USERPROFILE/Desktop/Thumbnails/GoldGallery.rbxl" Gold
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("../tests/harness")

local Config = H.shared("Config")
local Halloween = H.shared("Halloween")
local CreatureModels = H.server("CreatureModels")
local Instance, Vector3, CFrame, Color3, UDim2 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.UDim2

local out = process.args[1]
assert(out, "usage: lune run tools/haunted_gallery.luau <out.rbxl> [Mutation]")
local mutation = process.args[2] or Halloween.MUTATION
local mut = Config.mutationById(mutation)
assert(mut, `unknown mutation {mutation}`)
local haunted = mutation == Halloween.MUTATION

-- The plants of (zone, rarity) the gallery shows, in gene order.
local function flowers(k: number, r: number): { string }
	return if haunted then Halloween.setFlowers(k, r) else CreatureModels.variants(k, r)
end

local SPACING_X, SPACING_Z = 22, 34

local game = Instance.new("DataModel")
local ws = game:GetService("Workspace")
local lighting = game:GetService("Lighting")
if haunted then
	lighting.ClockTime = 18.6
	lighting.Brightness = 1.6
	lighting.Ambient = Color3.fromRGB(95, 70, 130)
	lighting.OutdoorAmbient = Color3.fromRGB(120, 95, 150)
else
	lighting.ClockTime = 14
	lighting.Brightness = 2.2
	lighting.Ambient = Color3.fromRGB(110, 110, 120)
	lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
end

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
		n += #flowers(k, r)
	end
	cols = math.max(cols, n)
end

local ground = if haunted then Color3.fromRGB(45, 32, 60) else Color3.fromRGB(60, 70, 80)
part("Ground", Vector3.new(cols * SPACING_X + 60, 2, rows * SPACING_Z + 80), CFrame.new(0, -1, (rows - 1) * SPACING_Z / 2), ground, ws)
local spawn = Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = Vector3.new(8, 1, 8)
spawn.CFrame = CFrame.new(0, 0.5, -30)
spawn.Color = mut.color
spawn.Parent = ws

local placed = 0
for k = 1, rows do
	local zone = Config.ZONES[k]
	local z = (k - 1) * SPACING_Z
	local zoneSign = part("Zone_" .. zone.id, Vector3.new(4, 1, 4), CFrame.new(-(cols + 1) * SPACING_X / 2 - 6, 0.5, z), mut.color, ws)
	label(zoneSign, string.upper(zone.name), mut.color, 4)
	local col = 0
	for r, rarity in Config.RARITIES do
		for _, name in flowers(k, r) do
			local pick = table.find(CreatureModels.variants(k, r), name)
			if pick then
				local x = (col - (cols - 1) / 2) * SPACING_X
				local plant = CreatureModels.build(k, r, mutation, pick)
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
print(`placed {placed} {mutation} plants in {out}`)
