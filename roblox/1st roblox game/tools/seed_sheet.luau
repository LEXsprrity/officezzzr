-- A picture of every seed design (assets/Seed_*.rbxm, after tools/export_seeds.luau), rendered in Blender:
-- one column per zone, Design1 at the back and Design2 in front. Writes the parts as JSON, then run Blender:
--   lune run tools/seed_sheet.luau <parts.json>
--   blender -b -P tools/blender/render_parts.py -- <parts.json> <sheet.png>
-- (bought MeshParts and Unions are drawn as ellipsoids of their size: a preview, not the real mesh)
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local ZONES = { "Meadow", "Desert", "Jungle", "Lava", "Snow", "Space", "Spirit" }
local out = {}
for zi, z in ZONES do
	local folder = roblox.deserializeModel(fs.readFile(`assets/Seed_{z}.rbxm`))[1]
	for _, m in folder:GetChildren() do
		local d = m:GetAttribute("Design")
		local item = { zone = z, col = zi, row = d, parts = {} }
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				local shape = p.ClassName
				if p.ClassName == "Part" then
					shape = tostring(p.Shape):match("%.(%w+)$")
					if p:FindFirstChildWhichIsA("SpecialMesh") then shape = "Egg" end
				elseif p.ClassName == "MeshPart" or p.ClassName == "UnionOperation" then
					shape = "Egg"
				end
				local c = { p.CFrame:GetComponents() }
				table.insert(item.parts, { shape = shape, size = { p.Size.X, p.Size.Y, p.Size.Z }, cf = c, color = { p.Color.R, p.Color.G, p.Color.B } })
			end
		end
		table.insert(out, item)
	end
end
fs.writeFile(process.args[1], serde.encode("json", out))
print(#out, "designs")
