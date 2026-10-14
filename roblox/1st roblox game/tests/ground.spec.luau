-- Level ground (owner playtest: floor tiles at slightly different heights, and the plot entrance tile and
-- the grass z-fighting in a jagged pattern). Every floor piece's top is at the ground level, and no two
-- visible surfaces near the ground lie on the same plane overlapping each other (z-fighting), on the
-- generated map and on map/World.rbxm.
local H = require("./harness")
local roblox = require("@lune/roblox")
local MapTool = require("../tools/map_tool")

local Config = H.shared("Config")
local WorldBuilder = H.server("WorldBuilder")
local Props = H.server("Props")
local Assets = H.server("Assets")
local Vector3 = roblox.Vector3
local Enum = roblox.Enum

local GROUND = Config.GROUND_Y
-- What makes up the ground: every one of these has its top exactly at GROUND.
local FLOOR = {
	LawnTile = true, Walkway = true, Path = true, EntranceTile = true, PathTile = true, BedTile = true, Grass = true,
	Plaza = true, PlazaPath = true, FloorTile = true, ZoneEdge = true,
}

-- The horizontal top face of a part: its height and its outline seen from above (a convex polygon of
-- {x, z} points), or nil for anything that isn't a block or a flat disc lying level.
local function topFace(p: any): (number?, { { number } }?)
	if not p:IsA("Part") or p:FindFirstChildWhichIsA("SpecialMesh") then
		return nil, nil
	end
	local cf, s = p.CFrame, p.Size
	local axes = { cf.RightVector, cf.UpVector, -cf.LookVector }
	local half = { s.X / 2, s.Y / 2, s.Z / 2 }
	local up
	for i, a in axes do
		if math.abs(a.Y) > 0.999 then
			up = i
		end
	end
	if not up then
		return nil, nil
	end
	local top = cf.Position.Y + half[up]
	local others = {}
	for i = 1, 3 do
		if i ~= up then
			table.insert(others, i)
		end
	end
	local a, b = axes[others[1]] * half[others[1]], axes[others[2]] * half[others[2]]
	local c = cf.Position
	if p.Shape == Enum.PartType.Cylinder then
		if up ~= 1 then -- a cylinder's round faces are on its X axis
			return nil, nil
		end
		local r = math.min(half[2], half[3])
		local poly = {}
		for k = 0, 15 do
			local t = k / 16 * math.pi * 2
			table.insert(poly, { c.X + math.cos(t) * r, c.Z + math.sin(t) * r })
		end
		return top, poly
	elseif p.Shape ~= Enum.PartType.Block then
		return nil, nil
	end
	local poly = {}
	for _, sgn in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
		local v = c + a * sgn[1] + b * sgn[2]
		table.insert(poly, { v.X, v.Z })
	end
	return top, poly
end

-- The area two convex polygons share (Sutherland-Hodgman clipping).
local function cross(o: { number }, a: { number }, b: { number }): number
	return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
end
local function area(poly: { { number } }): number
	local s = 0
	for i = 1, #poly do
		local a, b = poly[i], poly[i % #poly + 1]
		s += a[1] * b[2] - b[1] * a[2]
	end
	return s / 2
end
local function ccw(poly: { { number } }): { { number } }
	if area(poly) >= 0 then
		return poly
	end
	local out = {}
	for i = #poly, 1, -1 do
		table.insert(out, poly[i])
	end
	return out
end
local function shared(p: { { number } }, q: { { number } }): number
	local out = ccw(p)
	q = ccw(q)
	for i = 1, #q do
		if #out == 0 then
			return 0
		end
		local a, b = q[i], q[i % #q + 1]
		local input = out
		out = {}
		for j = 1, #input do
			local cur, prev = input[j], input[(j - 2) % #input + 1]
			local inCur, inPrev = cross(a, b, cur) >= -1e-9, cross(a, b, prev) >= -1e-9
			if inCur ~= inPrev then
				local d1, d2 = cross(a, b, prev), cross(a, b, cur)
				local t = d1 / (d1 - d2)
				table.insert(out, { prev[1] + (cur[1] - prev[1]) * t, prev[2] + (cur[2] - prev[2]) * t })
			end
			if inCur then
				table.insert(out, cur)
			end
		end
	end
	return if #out >= 3 then math.abs(area(out)) else 0
end

-- Every pair of visible surfaces in the floor band (up to 0.6 above the ground) on the same plane that
-- overlap: z-fighting. Imported art models (a slot's model) are left out, they are drawn as they come.
local function coplanarOverlaps(world: any): { string }
	local faces = {}
	for _, p in world:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local model = p:FindFirstAncestorWhichIsA("Model")
			local art = model and (model:GetAttribute("Asset") ~= nil or model:FindFirstAncestor("Plants") ~= nil)
			local top, poly = topFace(p)
			if not art and top and top <= GROUND + 0.6 and top >= GROUND - 2 then
				local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
				for _, v in poly :: any do
					x0, x1, z0, z1 = math.min(x0, v[1]), math.max(x1, v[1]), math.min(z0, v[2]), math.max(z1, v[2])
				end
				table.insert(faces, { part = p, top = top, poly = poly, box = { x0, x1, z0, z1 } })
			end
		end
	end
	table.sort(faces, function(a, b)
		return a.top < b.top
	end)
	local bad = {}
	for i = 1, #faces do
		local f = faces[i]
		for j = i + 1, #faces do
			local g = faces[j]
			if g.top - f.top > 0.005 then
				break
			end
			local a, b = f.box, g.box
			if a[1] < b[2] - 1e-3 and a[2] > b[1] + 1e-3 and a[3] < b[4] - 1e-3 and a[4] > b[3] + 1e-3 then
				local overlap = shared(f.poly, g.poly)
				if overlap > 0.01 then
					table.insert(bad, `{f.part:GetFullName()} and {g.part:GetFullName()} overlap on the same plane (y {f.top}, {overlap} studs²)`)
				end
			end
		end
	end
	return bad
end

local function floorTops(world: any): { string }
	local bad, count = {}, 0
	for _, p in world:GetDescendants() do
		if p:IsA("BasePart") and FLOOR[p.Name] then
			count += 1
			local top = p.CFrame.Position.Y + p.Size.Y / 2
			if math.abs(top - GROUND) > 1e-3 then
				table.insert(bad, `{p:GetFullName()} top at {top}, not the ground ({GROUND})`)
			end
		end
	end
	if count < 100 then
		table.insert(bad, `only {count} floor pieces`)
	end
	return bad
end

local function check(world: any, label: string)
	local bad = floorTops(world)
	H.ok(#bad == 0, `{label}: {#bad} floor pieces off the ground level:\n  ` .. table.concat(bad, "\n  ", 1, math.min(#bad, 40)))
	bad = coplanarOverlaps(world)
	H.ok(#bad == 0, `{label}: {#bad} z-fighting pairs:\n  ` .. table.concat(bad, "\n  ", 1, math.min(#bad, 40)))
	-- the plots' beds are flush with the ground too (plants stand level with the grass)
	local plots = WorldBuilder.adopt(world)
	H.ok(plots ~= nil, `{label} adopts`)
	for i, plot in plots do
		for b, bed in plot.beds do
			local top = bed.CFrame.Position.Y + bed.Size.Y / 2
			H.ok(math.abs(top - GROUND) < 1e-3, `{label}: plot {i} bed {b} top {top} level with the ground`)
		end
		H.ok(math.abs(plot.origin.Position.Y - GROUND) < 1e-3, `{label}: plot {i} origin on the ground`)
	end
end

H.test("ground: the shared cut and checker tile exactly (no gaps, no overlaps)", function()
	local pieces = Props.subtract({ 0, 10, 0, 10 }, { { 2, 4, 2, 4 }, { 3, 12, 6, 8 }, { -5, 1, -5, 1 } })
	local sum = 0
	for i, p in pieces do
		sum += (p[2] - p[1]) * (p[4] - p[3])
		for j = i + 1, #pieces do
			local q = pieces[j]
			H.ok(not (p[1] < q[2] - 1e-6 and p[2] > q[1] + 1e-6 and p[3] < q[4] - 1e-6 and p[4] > q[3] + 1e-6), "pieces don't overlap")
		end
	end
	H.near(sum, 100 - 4 - 14 - 1, 1e-6, "the area left (the holes, clipped to the square)")
end)

H.test("ground: the generated map is level and nothing z-fights", function()
	check(H.workspace:FindFirstChild("World"), "built")
end)

H.test("ground: map/World.rbxm is level and nothing z-fights (with the assets' models in)", function()
	local world = MapTool.load(MapTool.PATH)
	Assets.refresh(world)
	check(world, "map")
end)

return nil
