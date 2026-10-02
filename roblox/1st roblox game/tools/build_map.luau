-- Bakes the generated map into map/World.rbxm so it is visible in Studio edit mode (Rojo puts it
-- in Workspace.World). The server still rebuilds the map when the game starts, replacing this copy,
-- so gameplay always uses the code's map. Run from the game folder, before `rojo build`:
--   lune run tools/build_map.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("../tests/harness")

local WorldBuilder = H.server("WorldBuilder")
WorldBuilder.build()
local world = H.workspace:FindFirstChild("World")
assert(world, "WorldBuilder.build() made no Workspace.World")

local count = 0
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	elseif d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
		-- Lune keeps `.Font = Enum.Font.X` as a raw EnumItem the file format rejects; store it as FontFace.
		local font = d.Font
		if typeof(font) == "EnumItem" then
			d.FontFace = roblox.Font.fromEnum(font)
		end
	end
end
fs.writeFile("map/World.rbxm", roblox.serializeModel({ world }))
print(`map/World.rbxm: {count} parts`)
