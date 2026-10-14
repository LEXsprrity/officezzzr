-- Debug view of the bosses' code animation (BossRigs) without Studio: poses a Guard asset's skeleton and
-- prints a side view (front to the left) and a top view of its Bones, rest ("." marks) against the pose
-- ("o" body/legs, "H" head, "~" tail, "w" wings/fins; "#" the ground), plus the key bones' heights.
-- Run from the game folder:
--   lune run tools/boss_pose.luau [zone|pet] [state] [phase]
-- e.g. lune run tools/boss_pose.luau Spirit Sleeping, or Lava Chasing 1.6 (stride phase in radians).
-- With no zone it lists every boss's resting and sleeping heights.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("../tests/harness")
local Config = H.shared("Config")
local BossRigs = H.shared("BossRigs")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local function load(zone: any): (any, any, any)
	local key = BossRigs.BY_ZONE[zone.id]
	local profile = BossRigs.PROFILES[key]
	local model = roblox.deserializeModel(fs.readFile("assets/Guard_" .. string.gsub(zone.guard, "%s", "") .. ".rbxm"))[1]
	return BossRigs.rig(model.PrimaryPart, profile, profile.scale), profile, key
end

local function posed(rig: any, profile: any, state: string, phase: number, t: number): any
	local moving = state == "Chasing" or state == "Returning"
	local _, world = BossRigs.solve(rig, BossRigs.pose(profile, {
		state = state, t = t, age = 2, phase = phase, move = if moving then 1 else 0,
	}))
	return world
end

local function marks(profile: any): { [string]: string }
	local m = {}
	local function set(list: { string }?, c: string)
		for _, b in list or {} do
			m[b] = c
		end
	end
	set(profile.tail, "~")
	set(profile.spine, "~")
	set(profile.neck, "n")
	for _, w in profile.wings or {} do
		set(w.bones, "w")
	end
	for _, w in profile.fins or {} do
		set(w.bones, "w")
	end
	m[profile.head] = "H"
	if profile.jaw then
		m[profile.jaw] = "J"
	end
	m[profile.body] = "B"
	return m
end

-- One view: `project` maps a model-space point to (across, up) on the page; `ground` draws y = 0.
local function view(rig: any, world: any, profile: any, project: (Vector3) -> (number, number), ground: boolean)
	local W, Hh = 72, 22
	local h0, h1, v0, v1 = math.huge, -math.huge, math.huge, -math.huge
	for _, j in rig.joints do
		for _, p in { j.rest.Position, world[j].Position, Vector3.zero } do
			local h, v = project(p)
			h0, h1, v0, v1 = math.min(h0, h), math.max(h1, h), math.min(v0, v), math.max(v1, v)
		end
	end
	local function at(p: Vector3): (number, number)
		local h, v = project(p)
		return math.floor((h - h0) / math.max(h1 - h0, 1e-3) * (W - 1)) + 1, math.floor((v - v0) / math.max(v1 - v0, 1e-3) * (Hh - 1)) + 1
	end
	local grid = {}
	for y = 1, Hh do
		grid[y] = table.create(W, " ")
	end
	if ground then
		local _, g = at(Vector3.zero)
		for x = 1, W do
			grid[g][x] = "#"
		end
	end
	for _, j in rig.joints do
		local x, y = at(j.rest.Position)
		if grid[y][x] == " " or grid[y][x] == "#" then
			grid[y][x] = "."
		end
	end
	local m = marks(profile)
	for _, j in rig.joints do
		local x, y = at(world[j].Position)
		grid[y][x] = m[j.name] or "o"
	end
	for y = Hh, 1, -1 do
		print("  |" .. table.concat(grid[y]) .. "|")
	end
end

local args = process.args
local function zoneOf(name: string): any
	for _, z in Config.ZONES do
		if z.id == name or BossRigs.BY_ZONE[z.id] == name then
			return z
		end
	end
	error("no zone or pet " .. name)
end

if not args[1] then
	print(string.format("%-8s %-15s %8s %8s %8s %8s", "zone", "pet", "body", "asleep", "head", "asleep"))
	for _, zone in Config.ZONES do
		local rig, profile, key = load(zone)
		local w = posed(rig, profile, "Sleeping", 0, 1)
		local b, h = rig.byName[profile.body], rig.byName[profile.head]
		print(string.format("%-8s %-15s %8.2f %8.2f %8.2f %8.2f", zone.id, key, b.rest.Position.Y, w[b].Position.Y, h.rest.Position.Y, w[h].Position.Y))
	end
	return
end

local zone = zoneOf(args[1])
local state = args[2] or "Sleeping"
local phase = tonumber(args[3]) or 0
local rig, profile, key = load(zone)
local world = posed(rig, profile, state, phase, 1)
print(`{zone.id}: {key} {state} (phase {phase}). Side view, front to the left:`)
view(rig, world, profile, function(p)
	return p.Z, p.Y
end, true)
print("Top view, front to the left, its right side at the bottom:")
view(rig, world, profile, function(p)
	return p.Z, -p.X
end, false)
local function line(name: string?)
	local j = name and rig.byName[name]
	if j then
		local a, b = j.rest.Position, world[j].Position
		print(string.format("  %-26s rest (%6.2f %6.2f %6.2f)  posed (%6.2f %6.2f %6.2f)", j.name, a.X, a.Y, a.Z, b.X, b.Y, b.Z))
	end
end
line(profile.body)
line(profile.head)
for _, l in profile.legs or {} do
	line(l.knee)
	line(l.foot)
end
local low, lowest = math.huge, "?"
for _, j in rig.joints do
	if world[j].Position.Y < low then
		low, lowest = world[j].Position.Y, j.name
	end
end
print(string.format("  lowest bone %.2f (%s)", low, lowest))
