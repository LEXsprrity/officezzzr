-- Grounds the exported plant models in assets/Creature_*.rbxm on their base (tools/plant_ground.luau), in
-- place. Run from the game folder: lune run tools/ground_plants.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local PlantGround = require("./plant_ground")

for _, file in fs.readDir("assets") do
	if string.sub(file, 1, 9) == "Creature_" and string.sub(file, -5) == ".rbxm" then
		local roots = roblox.deserializeModel(fs.readFile("assets/" .. file))
		local moved = 0
		for _, root in roots do
			for _, m in root:GetDescendants() do
				if m:IsA("Model") and m:GetAttribute("Source") then
					local had = m:GetAttribute("Pivot")
					local gap = PlantGround.apply(m)
					if gap > 0 or m:GetAttribute("Pivot") ~= had then
						moved += 1
						print(string.format("%-24s %-20s lowered %.2f, ground point %s", file, m.Name, gap, tostring(m:GetAttribute("Pivot"))))
					end
				end
			end
		end
		if moved > 0 then
			fs.writeFile("assets/" .. file, roblox.serializeModel(roots))
		end
	end
end
