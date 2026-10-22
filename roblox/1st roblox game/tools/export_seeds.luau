-- Exports the seed models into assets/Seed_<ZoneId>.rbxm: a Folder per zone holding its 2 designs, Models named
-- "Design1" and "Design2" (never the fruit's name: a seed is only ever "Rare Seed"). Every design is used
-- by one zone only, themed for its biome (owner 2026-10-22): our own designs (tools/seed_designs.luau) and
-- the three bought ones the owner likes (models/seeds/PlantsByLoxsy.rbxm, PlantsByLoxxsy > Tools > Seeds:
-- one Tool per seed, "... Seed"). A seed's gene picks its design (Config.geneDesign), whatever its rarity,
-- so a pod, the seed carried from it and the same seed in the bag look alike.
-- Each design keeps only the seed's visible parts and its packet art (Decals): the Tool's invisible
-- Handle, every weld, script, light, particle and see-through Neon glow is dropped, and a solid Neon part
-- turns Plastic (owner: no brightness around the seed; the Dawnfruit keeps its orange sun). Anchored, non-colliding, bottom centre at the origin; the game fits it to the pod (3 studs) or the
-- carried seed (2.4) and welds it for carrying (SeedService.seedLook). Run from the game folder:
--   lune run tools/export_seeds.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local Enum = roblox.Enum

local SeedDesigns = require("./seed_designs")

local SOURCE = "models/seeds/PlantsByLoxsy.rbxm"

-- Config.ZONES order (id) and the two designs each zone's seeds look like: a SeedDesigns name, or a bought
-- Tool's name ("... Seed").
local ZONES = {
	{ id = "Meadow", tools = { "Clover", "Daisy" } },
	{ id = "Desert", tools = { "Sunpetal Seed", "Cactus" } },
	{ id = "Jungle", tools = { "Dawnfruit Seed", "Pitcher" } },
	{ id = "Lava", tools = { "Amberpine Seed", "Obsidian" } },
	{ id = "Snow", tools = { "FrostPine", "IceCrystal" } },
	{ id = "Space", tools = { "Planet", "Alien" } },
	{ id = "Spirit", tools = { "Sakura", "Lotus" } },
}

-- World-axis box of one part.
local function box(p: any): (any, any)
	local cf, h = p.CFrame, p.Size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local e = Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	)
	return cf.Position - e, cf.Position + e
end

local KEEP = { "BasePart", "Decal", "SpecialMesh", "SurfaceAppearance", "Model" }
local function keeps(d: any): boolean
	for _, class in KEEP do
		if d:IsA(class) then
			return true
		end
	end
	return false
end

local function export(tool: any, design: number): any
	local model = roblox.Instance.new("Model")
	model.Name = `Design{design}`
	for _, child in tool:GetChildren() do
		child:Clone().Parent = model
	end
	for _, d in model:GetDescendants() do
		if d.Parent == nil then
			continue
		end
		if not keeps(d) then
			d:Destroy()
		elseif d:IsA("BasePart") and (d.Name == "Handle" or d.Transparency >= 1) then
			d:Destroy()
		elseif d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			if d.Transparency > 0 then
				d:Destroy()
			else
				d.Material = Enum.Material.Plastic
			end
		end
	end
	for _, d in model:GetDescendants() do -- (a sub-model left without parts: the Dawnfruit's glowing sun)
		if d.Parent and d:IsA("Model") and not d:FindFirstChildWhichIsA("BasePart", true) then
			d:Destroy()
		end
	end
	local lo, hi, biggest = nil, nil, nil
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CastShadow = true
			local a, b = box(p)
			lo = if lo then lo:Min(a) else a
			hi = if hi then hi:Max(b) else b
			if not biggest or p.Size.Magnitude > biggest.Size.Magnitude then
				biggest = p
			end
		end
	end
	assert(biggest and lo and hi, `{tool.Name} has no visible parts`)
	-- bottom centre to the origin
	local shift = CFrame.new(-Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2))
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CFrame = shift * p.CFrame
		end
	end
	model.PrimaryPart = biggest
	model:SetAttribute("Design", design)
	return model
end

local roots = roblox.deserializeModel(fs.readFile(SOURCE))
local seeds = nil
for _, d in roots[1]:GetDescendants() do
	if d.Name == "Seeds" and d.Parent and d.Parent.Name == "Tools" then
		seeds = d
	end
end
assert(seeds, "no PlantsByLoxxsy > Tools > Seeds folder")

local used = {}
for _, zone in ZONES do
	local folder = roblox.Instance.new("Folder")
	folder.Name = "Seed_" .. zone.id
	for i, name in zone.tools do
		assert(not used[name], `{name} is used by two zones`)
		used[name] = true
		local tool = SeedDesigns.build(name) or seeds:FindFirstChild(name)
		assert(tool, `no design or Tool named {name}`)
		export(tool, i).Parent = folder
	end
	local out = `assets/Seed_{zone.id}.rbxm`
	fs.writeFile(out, roblox.serializeModel({ folder }))
	local parts = 0
	for _, d in folder:GetDescendants() do
		parts += if d:IsA("BasePart") then 1 else 0
	end
	print(`{out}: {table.concat(zone.tools, ", ")} ({parts} parts)`)
end
