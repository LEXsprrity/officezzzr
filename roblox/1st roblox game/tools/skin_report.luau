-- Which Bones really deform the bosses' meshes. The skin weights live in the mesh files (the kit's
-- MeshParts only hold asset ids), so this reads the copies Roblox Studio keeps in its local content cache
-- (%LOCALAPPDATA%/Roblox/rbx-storage, filled once the kit was opened in Studio): every v6/v7 mesh with a
-- SKINNING chunk whose bones are one of the pets' bones, laid out like them (the bind pose times the kit's
-- Size/InitialSize, moved by one offset), counts for that pet. It writes models/bosses/skinning.json:
--   { [pet] = { meshes = n, bones = { [bone] = weighted vertices }, parts = { [MeshPart] = { [bone] = vertices } } } }
-- which tests/bosses.spec checks the rig profiles against (a profile bone with no weight moves nothing).
-- Run from the game folder, after opening models/bosses/Pets.rbxl in Studio:
--   lune run tools/skin_report.luau [cache folder]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local H = require("../tests/harness")
local BossRigs = H.shared("BossRigs")

local SOURCE = "models/bosses/Pets.rbxl"
local OUT = "models/bosses/skinning.json"
local CACHE = process.args[1] or ((process.env.LOCALAPPDATA or "") .. "/Roblox/rbx-storage")

type Bone = { name: string, pos: Vector3, weighted: number }

-- The SKINNING chunk of a "version 6.00"/"version 7.00" mesh: its bones (bind positions) and how many
-- vertices each one weighs on. nil for any other file.
local function readSkin(path: string): { Bone }?
	local s = fs.readFile(path)
	local at = string.find(s, "version [67]%.00\n")
	if not at then
		return nil
	end
	local b = buffer.fromstring(s)
	local p = at - 1 + 13
	while p + 16 <= #s do
		local chunk = string.gsub(buffer.readstring(b, p, 8), "%z", "")
		local size = buffer.readu32(b, p + 12)
		if chunk == "SKINNING" then
			local q = p + 16
			local nSkin = buffer.readu32(b, q)
			q += 4
			local skinAt = q
			q += nSkin * 8
			local nBones = buffer.readu32(b, q)
			q += 4
			local bones: { Bone } = {}
			local nameAt = {}
			for k = 1, nBones do
				local o = q + (k - 1) * 60
				nameAt[k] = buffer.readu32(b, o)
				bones[k] = {
					name = "",
					pos = roblox.Vector3.new(buffer.readf32(b, o + 48), buffer.readf32(b, o + 52), buffer.readf32(b, o + 56)),
					weighted = 0,
				}
			end
			q += nBones * 60
			local nameSize = buffer.readu32(b, q)
			q += 4
			local names = buffer.readstring(b, q, nameSize)
			q += nameSize
			for k, bone in bones do
				local e = string.find(names, "\0", nameAt[k] + 1, true) or nameSize + 1
				bone.name = string.sub(names, nameAt[k] + 1, e - 1)
			end
			local nSub = buffer.readu32(b, q)
			q += 4
			for k = 1, nSub do
				local o = q + (k - 1) * 72
				local first, count, nIdx = buffer.readu32(b, o + 8), buffer.readu32(b, o + 12), buffer.readu32(b, o + 16)
				for v = first, first + count - 1 do
					for j = 0, 3 do
						local slot = buffer.readu8(b, skinAt + v * 8 + j)
						if buffer.readu8(b, skinAt + v * 8 + 4 + j) > 0 and slot < nIdx then
							local bone = bones[buffer.readu16(b, o + 20 + slot * 2) + 1]
							if bone then
								bone.weighted += 1
							end
						end
					end
				end
			end
			return bones
		end
		p += 16 + size
	end
	return nil
end

-- Every pet of the kit: its bones' rest positions (RootPart space) and its meshes' Size/InitialSize.
local place = roblox.deserializePlace(fs.readFile(SOURCE))
local pets = {}
for _, m in place.Workspace.PetTemplates:GetChildren() do
	local host = m:IsA("Model") and m:FindFirstChild("RootPart")
	if host then
		local pos: { [string]: Vector3 } = {}
		local function walk(inst: any, cf: any)
			for _, c in inst:GetChildren() do
				if c:IsA("Bone") then
					local w = cf * c.CFrame
					pos[c.Name] = w.Position
					walk(c, w)
				end
			end
		end
		walk(host, roblox.CFrame.identity)
		local reach = 0
		for _, p in pos do
			reach = math.max(reach, p.Magnitude)
		end
		local parts = {}
		for _, d in m:GetChildren() do
			if d:IsA("MeshPart") then
				local k = d.Size / d.InitialSize
				table.insert(parts, { name = d.Name, cf = host.CFrame:Inverse() * d.CFrame, k = k })
			end
		end
		pets[m.Name] = { pos = pos, parts = parts, extent = math.max(reach, 1) }
	end
end

-- How far a mesh's bind pose is from one of a pet's MeshParts: each bone's bind position, scaled like the
-- part (Size/InitialSize) and placed by its CFrame, against the kit bone (nil if a bone is missing).
local function misfit(bones: { Bone }, pet: any, part: any): number?
	local worst = 0
	for _, bone in bones do
		local at = pet.pos[bone.name]
		if not at then
			return nil
		end
		worst = math.max(worst, (part.cf * (bone.pos * part.k) - at).Magnitude)
	end
	return worst / pet.extent
end

local report = {}
local files, skinned = 0, 0
assert(fs.isDir(CACHE), `no Studio content cache at {CACHE} (pass its folder)`)
for _, sub in fs.readDir(CACHE) do
	local dir = CACHE .. "/" .. sub
	if fs.isDir(dir) then
		for _, f in fs.readDir(dir) do
			files += 1
			local ok, bones = pcall(readSkin, dir .. "/" .. f)
			if ok and bones and #bones >= 1 then
				skinned += 1
				for key in BossRigs.PROFILES do
					local pet = pets[key]
					local best, bestFit = nil, 1e-3 -- (bind poses are exact: float noise only)
					for _, part in pet.parts do
						local fit = misfit(bones, pet, part)
						if fit and fit < bestFit then
							best, bestFit = part, fit
						end
					end
					if best then
						local r = report[key] or { meshes = 0, bones = {}, parts = {} }
						report[key] = r
						r.meshes += 1
						local weights = r.parts[best.name] or {}
						r.parts[best.name] = weights
						for _, bone in bones do
							if bone.weighted > 0 then
								r.bones[bone.name] = (r.bones[bone.name] or 0) + bone.weighted
								weights[bone.name] = (weights[bone.name] or 0) + bone.weighted
							end
						end
					end
				end
			end
		end
	end
end
print(`{files} cached files, {skinned} skinned meshes`)
for key in BossRigs.PROFILES do
	local r = report[key]
	local n, found = 0, 0
	for _ in if r then r.bones else {} do
		n += 1
	end
	for _ in if r then r.parts else {} do
		found += 1
	end
	print(string.format("%-15s %2d of %2d MeshParts found, %3d weighted bones", key, found, #pets[key].parts, n))
end
fs.writeFile(OUT, serde.encode("json", report, true))
print("wrote " .. OUT)
