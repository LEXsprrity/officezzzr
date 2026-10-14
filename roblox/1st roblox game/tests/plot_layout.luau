-- Layout checks for the base, shared by world.spec (the map built from code) and map.spec (the committed
-- map/World.rbxm): plot fences are clean (no rail laid twice, no post twice, no post in a prop), plots have
-- no gate arch, there is no "FASTEST HERE" board, and each treadmill stands in front of its plot.
local H = require("./harness")

local Config = H.shared("Config")
local Assets = H.server("Assets")
local Vector3 = H.Vector3

local Layout = {}

local function named(world: any, name: string): { any }
	local out = {}
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			table.insert(out, d)
		end
	end
	return out
end

local function flat(v: any): any
	return Vector3.new(v.X, 0, v.Z)
end

-- No two fence rails lie along the same line at the same height with their lengths overlapping (the old
-- double fence between plots), and no two posts stand in the same spot.
function Layout.fencesDontOverlap(world: any, label: string)
	local rails = named(world, "FenceRail")
	H.ok(#rails > 0, `{label}: has fence rails`)
	for i = 1, #rails do
		local a = rails[i]
		local da = flat(a.CFrame.LookVector).Unit
		local ca = a.CFrame.Position
		for j = i + 1, #rails do
			local b = rails[j]
			local cb = b.CFrame.Position
			if math.abs(ca.Y - cb.Y) > 0.05 or math.abs(flat(b.CFrame.LookVector).Unit:Dot(da)) < 0.999 then
				continue
			end
			local off = flat(cb - ca)
			local along = off:Dot(da)
			local across = (off - da * along).Magnitude
			local overlap = (a.Size.Z + b.Size.Z) / 2 - math.abs(along)
			if across < 0.6 and overlap > 0.05 then
				error(`{label}: fence rails overlap by {overlap} studs: {a:GetFullName()} at {ca} and {b:GetFullName()} at {cb}`)
			end
		end
	end
	local posts = named(world, "FencePost")
	for i = 1, #posts do
		for j = i + 1, #posts do
			local d = flat(posts[i].CFrame.Position - posts[j].CFrame.Position).Magnitude
			if d < 0.9 then
				error(`{label}: two fence posts in one spot: {posts[i]:GetFullName()} and {posts[j]:GetFullName()} at {posts[i].CFrame.Position}`)
			end
		end
	end
end

-- No fence post pokes into a plot's treadmill, its boards, the owner's sign or the plaza's stalls (footprints).
function Layout.postsClearOfProps(world: any, plots: { any }, label: string)
	local props = {}
	for _, plot in plots do
		for _, child in plot.model:GetChildren() do
			if child.Name == "Treadmill" or child.Name == "UpgradeSign" or child.Name == "UpgradeBoard" or child.Name == "OwnerSign" or child.Name == "TreadmillBoard" then
				table.insert(props, child)
			end
		end
	end
	local plaza = world:FindFirstChild("ShopPlaza")
	for _, child in if plaza then plaza:GetChildren() else {} do
		if child:IsA("Model") then
			table.insert(props, child)
		end
	end
	local rewards = world:FindFirstChild("Rewards")
	for _, child in if rewards then rewards:GetChildren() else {} do
		if child:IsA("Model") then
			table.insert(props, child)
		end
	end
	H.ok(#props >= #plots * 3, `{label}: found the props`)
	local boxes = {}
	for _, prop in props do
		local lo, hi = Assets.bounds(prop)
		if lo and hi then
			table.insert(boxes, { lo = lo, hi = hi, name = prop:GetFullName() })
		end
	end
	for _, post in named(world, "FencePost") do
		local p, h = post.CFrame.Position, post.Size / 2
		for _, b in boxes do
			if p.X + h.X > b.lo.X + 0.01 and p.X - h.X < b.hi.X - 0.01 and p.Z + h.Z > b.lo.Z + 0.01 and p.Z - h.Z < b.hi.Z - 0.01
				and p.Y - h.Y < b.hi.Y and p.Y + h.Y > b.lo.Y then
				error(`{label}: fence post {post:GetFullName()} at {p} pokes into {b.name}`)
			end
		end
	end
end

-- The plots have plain fencing: no PlotGate piece, no gate posts, finials or arch.
function Layout.noPlotGate(world: any, label: string)
	for _, d in world:GetDescendants() do
		if d:GetAttribute("AssetSlot") == "PlotGate" or d.Name == "PlotGate" or d.Name == "GateArch" or d.Name == "GatePost" or d.Name == "GateFinial" then
			error(`{label}: {d:GetFullName()} is a plot gate piece`)
		end
	end
	H.eq(table.find(Assets.SLOTS, "PlotGate"), nil, "no PlotGate asset slot")
end

-- The old "⚡ FASTEST HERE ⚡" board is gone; the MOST MONEY/s board is the base's leaderboard.
function Layout.noFastestBoard(world: any, label: string)
	for _, d in world:GetDescendants() do
		if d:IsA("TextLabel") and string.find(string.upper(d.Text), "FASTEST", 1, true) then
			error(`{label}: {d:GetFullName()} still says "{d.Text}"`)
		end
		H.ok(not (d:IsA("BasePart") and d.Name == "Leaderboard"), `{label}: {d:GetFullName()} is the old leaderboard`)
	end
end

-- The strip in front of a plot, between its front fence and the walkway (where its treadmill and boards
-- stand), as world X/Z bounds with `margin` studs kept clear of the fence, the walkway and the neighbours'
-- strips. Returns (loX, hiX, loZ, hiZ).
function Layout.frontStrip(plot: any, margin: number): (number, number, number, number)
	local half = Config.PLOT_SIZE / 2
	local c = plot.center
	local side = if c.Z > 0 then 1 else -1
	local fence, walk = c.Z - side * half, side * Config.WALKWAY_WIDTH / 2
	local z0, z1 = math.min(fence, walk), math.max(fence, walk)
	return c.X - half + margin, c.X + half - margin, z0 + margin, z1 - margin
end

-- Each treadmill (its model and the belt) stands OUTSIDE its plot, in front of it: between the front fence
-- and the walkway, within its own plot's width (never in front of a neighbour), off the entrance path, and
-- about a character's size.
function Layout.treadmillsFit(plots: { any }, label: string)
	for i, plot in plots do
		local tm = plot.model:FindFirstChild("Treadmill")
		H.ok(tm ~= nil, `{label}: plot {i} has its treadmill`)
		local lo, hi = Assets.bounds(tm)
		local x0, x1, z0, z1 = Layout.frontStrip(plot, 0.5)
		H.ok(lo.X >= x0 and hi.X <= x1 and lo.Z >= z0 and hi.Z <= z1,
			`{label}: plot {i} treadmill {lo}..{hi} in front of its plot (x {x0}..{x1}, z {z0}..{z1}), clear of the fence and walkway`)
		local c = plot.center
		H.ok(lo.X > c.X + 7 or hi.X < c.X - 7, `{label}: plot {i} treadmill beside the entrance path, not on it`)
		local w, d = hi.X - lo.X, hi.Z - lo.Z
		H.ok(math.max(w, d) <= 13 and math.min(w, d) <= 8 and hi.Y - lo.Y <= 10, `{label}: plot {i} treadmill is character-sized ({hi - lo})`)
		local belt = plot.belt
		local bp = belt.CFrame.Position
		H.ok(bp.X >= lo.X - 0.5 and bp.X <= hi.X + 0.5 and bp.Z >= lo.Z - 0.5 and bp.Z <= hi.Z + 0.5, `{label}: plot {i} belt lies on its treadmill`)
	end
end

-- Every plot is fenced all round, with one opening at the path (built map only: hand edits may move it).
function Layout.plotsFullyFenced(world: any, plots: { any }, label: string)
	local rails = named(world, "FenceRail")
	local half = Config.PLOT_SIZE / 2
	for i, plot in plots do
		local c = plot.center
		local side = if c.Z > 0 then 1 else -1
		local front, back = c.Z - side * half, c.Z + side * half
		-- Each edge: a point on it, its direction, and how much rail it needs.
		local edges = {
			{ name = "front", from = Vector3.new(c.X - half, 0, front), dir = Vector3.xAxis, need = Config.PLOT_SIZE - 16 },
			{ name = "back", from = Vector3.new(c.X - half, 0, back), dir = Vector3.xAxis, need = Config.PLOT_SIZE },
			{ name = "-X side", from = Vector3.new(c.X - half, 0, math.min(front, back)), dir = Vector3.zAxis, need = Config.PLOT_SIZE },
			{ name = "+X side", from = Vector3.new(c.X + half, 0, math.min(front, back)), dir = Vector3.zAxis, need = Config.PLOT_SIZE },
		}
		for _, edge in edges do
			local spans = {}
			for _, r in rails do
				local p = flat(r.CFrame.Position)
				local rel = p - edge.from
				local t = rel:Dot(edge.dir)
				if math.abs(flat(r.CFrame.LookVector).Unit:Dot(edge.dir)) > 0.999 and (rel - edge.dir * t).Magnitude < 0.6
					and t > -0.5 and t < Config.PLOT_SIZE + 0.5 then
					table.insert(spans, { t - r.Size.Z / 2, t + r.Size.Z / 2 })
				end
			end
			table.sort(spans, function(a, b)
				return a[1] < b[1]
			end)
			local covered, reach = 0, -math.huge
			for _, s in spans do
				local a = math.max(s[1], reach)
				if s[2] > a then
					covered += s[2] - a
				end
				reach = math.max(reach, s[2])
			end
			H.ok(math.abs(covered - edge.need) < 0.1, `{label}: plot {i} {edge.name} fence covers {covered} of {edge.need} studs`)
		end
		-- The opening is where the path comes in.
		local mid = Vector3.new(c.X, 0, front)
		for _, r in rails do
			local p = flat(r.CFrame.Position)
			local reach = r.Size.Z / 2
			H.ok(not (math.abs(p.Z - front) < 0.6 and math.abs(p.X - mid.X) < 7 + reach), `{label}: plot {i} opening is clear`)
		end
	end
end

-- Every realistic-material part or texture in a map (the art direction is clean and cartoony: plastic,
-- studs, neon, glass; drop-in models get plastic from Assets). The treadmill belt's scrolling "Stripes"
-- texture is the one texture the map keeps. Returns a description of each offender.
function Layout.realisticBits(root: any): { string }
	local bad = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			if Assets.REALISTIC[d.Material.Name] then
				table.insert(bad, `{d:GetFullName()} ({d.Material.Name})`)
			end
			if d.MaterialVariant ~= "" then
				table.insert(bad, `{d:GetFullName()} (MaterialVariant {d.MaterialVariant})`)
			end
		elseif (d:IsA("Texture") or d:IsA("Decal")) and not (d.Name == "Stripes" and d.Parent:GetAttribute("Role") == "TreadmillBelt") then
			table.insert(bad, `{d:GetFullName()} ({d.ClassName})`)
		end
	end
	return bad
end

-- Everything that holds for any map, hand-edited or not.
function Layout.check(world: any, plots: { any }, label: string)
	Layout.fencesDontOverlap(world, label)
	Layout.postsClearOfProps(world, plots, label)
	Layout.noPlotGate(world, label)
	Layout.noFastestBoard(world, label)
	Layout.treadmillsFit(plots, label)
end

return Layout
