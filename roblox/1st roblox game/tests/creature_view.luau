-- Dev tool, not a test: ASCII front and side views of the plant-creatures, for checking silhouettes
-- without Studio. From the game folder:  lune run tests/creature_view.luau [zone 1-7] [rarity 1-5] [mutation]
-- Each part prints as the first letter of its name (B = Body, o/* = eyes, m = mouth).
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local loaded = require("./creature_loader")
local CreatureModels, Config = loaded.CreatureModels, loaded.Config
local Enum, Vector3 = roblox.Enum, roblox.Vector3

local function inside(p, pt): boolean
	local l = p.CFrame:PointToObjectSpace(pt)
	local h = p.Size / 2
	if p:IsA("Part") and p.Shape == Enum.PartType.Ball then
		return l.Magnitude <= h.X
	elseif p:IsA("Part") and p.Shape == Enum.PartType.Cylinder then
		return math.abs(l.X) <= h.X and l.Y * l.Y + l.Z * l.Z <= h.Y * h.Y
	elseif p:FindFirstChildOfClass("SpecialMesh") then
		return (l.X / h.X) ^ 2 + (l.Y / h.Y) ^ 2 + (l.Z / h.Z) ^ 2 <= 1
	elseif math.abs(l.X) > h.X or math.abs(l.Y) > h.Y or math.abs(l.Z) > h.Z then
		return false
	elseif p:IsA("WedgePart") then
		return (l.Y + h.Y) / (2 * h.Y) <= (l.Z + h.Z) / (2 * h.Z)
	end
	return true
end

local CHARS = { Body = "B", Eye = "o", Pupil = "*", Shine = "*", Mouth = "m" }

-- Looks along +Z (front view) or +X (side view, the creature's front on the left).
local function view(model, front: boolean): { string }
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local _, height = CreatureModels.extents(model)
	local lines = {}
	for yi = math.ceil(height / 0.27), 0, -1 do
		local row = {}
		for xi = -14, 14 do
			local c = " "
			for di = -20, 20 do
				local a, d = xi * 0.13, di * 0.1
				local pt = if front then Vector3.new(a, yi * 0.27, d) else Vector3.new(d, yi * 0.27, a)
				local hit = nil
				for _, p in parts do
					if inside(p, pt) then
						hit = p
						break
					end
				end
				if hit then
					c = CHARS[hit.Name] or string.lower(string.sub(hit.Name, 1, 1))
					break
				end
			end
			table.insert(row, c)
		end
		table.insert(lines, table.concat(row))
	end
	return lines
end

local zoneArg, rarity, mutation = tonumber(process.args[1]), tonumber(process.args[2]) or 1, process.args[3]
for k = zoneArg or 1, zoneArg or #Config.ZONES do
	local model = CreatureModels.build(k, rarity, mutation)
	local radius, height = CreatureModels.extents(model)
	print(string.format("== %s  r%d %s  parts %d  radius %.2f  height %.2f   (front | side)", Config.ZONES[k].seed, rarity,
		mutation or "", CreatureModels.partCount(model), radius, height))
	local f, s = view(model, true), view(model, false)
	for i = 1, #f do
		print(f[i] .. " | " .. s[i])
	end
end
