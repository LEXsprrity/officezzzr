-- Drop-in models from the `assets/` folder (Rojo maps it to ServerStorage.Assets): each file is named
-- after a slot ("Tree", "Lava_Volcano", "Creature_Sproutling", ...; Portuguese aliases like "Arvores"
-- work too) and holds one Model, or a Folder of variant Models. Every map piece built from code is a
-- group Model tagged with its slot (AssetSlot) and the space it uses (FitSize); a slot's model replaces
-- that group, fitted into the same space. Without an asset (or with a broken one) the built-in piece
-- stays. See assets/COMO_ADICIONAR_MODELOS.md.
--
-- Everything here also runs under Lune (tools/build_map.luau and the tests), which has no Model methods
-- (no GetBoundingBox/ScaleTo/PivotTo): bounds and pivots are computed from part CFrames and sizes, and
-- placement falls back to moving and resizing the parts by hand when Model:ScaleTo is missing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Assets = {}

----------------------------------------------------------------------------------------------------
-- Slots
----------------------------------------------------------------------------------------------------
local function compact(name: string): string
	return (string.gsub(name, "%s", ""))
end

-- Every slot the game knows, in the order the guide lists them.
Assets.SLOTS = {
	"Tree", "BlossomTree", "Bush", "Rock", "Flower", "Lamp", "FencePost", "FenceSection",
	"Meadow_Flower", "Meadow_Mushroom",
	"Desert_Cactus", "Desert_Skull", "Desert_Bone", "Desert_Mesa",
	"Jungle_Tree", "Jungle_Fern", "Jungle_Log",
	"Lava_Volcano", "Lava_Rock", "Lava_Obsidian",
	"Snow_Pine", "Snow_Snowman", "Snow_Crystal",
	"Space_Planet", "Space_Crystal", "Space_Asteroid", "Space_Mushroom", "Space_UFO",
	"Spirit_Torii", "Spirit_Lantern", "Spirit_CherryTree",
	"Treadmill", "UpgradeSign", "PlotGate", "ShopStall", "ShopStall_Shop", "ShopStall_Trails", "ShopStall_Index", "SpawnSign",
} :: { string }
for _, zone in Config.ZONES do
	table.insert(Assets.SLOTS, "Arch_" .. zone.id)
	table.insert(Assets.SLOTS, "Nest_" .. zone.id)
end
for _, zone in Config.ZONES do
	table.insert(Assets.SLOTS, "Creature_" .. compact(zone.seed))
end
for _, zone in Config.ZONES do
	table.insert(Assets.SLOTS, "Guard_" .. compact(zone.guard))
end

-- When a slot has no model, the game tries its fallback before building the piece from code.
Assets.FALLBACK = {
	Meadow_Flower = "Flower",
	ShopStall_Shop = "ShopStall",
	ShopStall_Trails = "ShopStall",
	ShopStall_Index = "ShopStall",
} :: { [string]: string }

-- Solid slots keep the collision the model was saved with; every other slot is pure decoration.
Assets.SOLID = {
	FencePost = true, FenceSection = true,
	ShopStall = true, ShopStall_Shop = true, ShopStall_Trails = true, ShopStall_Index = true,
} :: { [string]: boolean }

-- Other names a file or folder may have (compared without case, accents, spaces or underscores).
Assets.ALIASES = {
	Arvores = "Tree", Arvore = "Tree", Arbustos = "Bush", Arbusto = "Bush",
	Pedras = "Rock", Pedra = "Rock", Rochas = "Rock", Flores = "Flower", Flor = "Flower",
	Postes = "Lamp", Poste = "Lamp", Luminarias = "Lamp", Cercas = "FenceSection", Cerca = "FenceSection",
	Esteira = "Treadmill", Portao = "PlotGate", Barraca = "ShopStall", Barracas = "ShopStall",
	Cactos = "Desert_Cactus", Cacto = "Desert_Cactus", Pinheiros = "Snow_Pine", Pinheiro = "Snow_Pine",
	BonecoDeNeve = "Snow_Snowman", Cerejeiras = "Spirit_CherryTree", Cerejeira = "Spirit_CherryTree",
} :: { [string]: string }

local FOLD: { [string]: string } = {}
for plain, accented in { a = "àáâãäåÀÁÂÃÄÅ", e = "èéêëÈÉÊË", i = "ìíîïÌÍÎÏ", o = "òóôõöÒÓÔÕÖ", u = "ùúûüÙÚÛÜ", c = "çÇ", n = "ñÑ" } do
	for _, code in utf8.codes(accented) do
		FOLD[utf8.char(code)] = plain
	end
end

local keyCache: { [string]: string } = {}
-- "Árvores", "arvores" and "ARVORES " all give "arvores"; "Desert_Cactus" gives "desertcactus".
function Assets.key(name: string): string
	local cached = keyCache[name]
	if cached then
		return cached
	end
	local folded = string.gsub(name, utf8.charpattern, function(ch)
		return FOLD[ch]
	end)
	local k = string.gsub(string.lower(folded), "[^%w]", "")
	keyCache[name] = k
	return k
end

local SLOT_BY_KEY: { [string]: string } = {}
for _, slot in Assets.SLOTS do
	SLOT_BY_KEY[Assets.key(slot)] = slot
end
for alias, slot in Assets.ALIASES do
	SLOT_BY_KEY[Assets.key(alias)] = slot
end

-- The slot a file/folder name stands for, or nil.
function Assets.slotFor(name: string): string?
	return SLOT_BY_KEY[Assets.key(name)]
end

----------------------------------------------------------------------------------------------------
-- Lookup
----------------------------------------------------------------------------------------------------
local warned: { [string]: boolean } = {}
local function warnOnce(id: string, message: string)
	if not warned[id] then
		warned[id] = true
		warn(message)
	end
end

function Assets.folder(): Instance?
	return ServerStorage:FindFirstChild("Assets")
end

local function own(slot: string): (Instance?, string?)
	local folder = Assets.folder()
	if not folder then
		return nil
	end
	for _, child in folder:GetChildren() do
		if Assets.slotFor(child.Name) == slot then
			return child, child.Name
		end
	end
	return nil
end

-- The template for `slot` (or its fallback): a Model, a lone part, or a Folder of variants. Also returns
-- the slot that matched.
function Assets.get(slot: string): (Instance?, string?)
	if not SLOT_BY_KEY[Assets.key(slot)] then
		warnOnce("unknown:" .. slot, `[Assets] the code asked for an unknown slot "{slot}" (add it to Assets.SLOTS)`)
	end
	local s: string? = slot
	while s do
		local template = own(s)
		if template then
			return template, s
		end
		s = Assets.FALLBACK[s]
	end
	return nil
end

-- Warns once about files in the assets folder that match no slot (a typo in a name, usually).
function Assets.audit()
	local folder = Assets.folder()
	if not folder then
		return
	end
	for _, child in folder:GetChildren() do
		if not Assets.slotFor(child.Name) then
			warnOnce("audit:" .. child.Name, `[Assets] assets/{child.Name} matches no slot, so the game doesn't use it (see assets/COMO_ADICIONAR_MODELOS.md)`)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Geometry (pure CFrame math, so it runs the same in Roblox and under Lune)
----------------------------------------------------------------------------------------------------
local function partsOf(root: Instance): { BasePart }
	local out = {}
	if root:IsA("BasePart") then
		table.insert(out, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- Axis-aligned bounds of the visible parts under `root`, in `frame`'s space (world space if nil).
function Assets.bounds(root: Instance, frame: CFrame?): (Vector3?, Vector3?)
	local inv = if frame then frame:Inverse() else CFrame.identity
	local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	for _, p in partsOf(root) do
		if p.Transparency >= 1 then
			continue
		end
		local cf = inv * p.CFrame
		local h = p.Size / 2
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local ex = math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z
		local ey = math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z
		local ez = math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
		local c = cf.Position
		x0, y0, z0 = math.min(x0, c.X - ex), math.min(y0, c.Y - ey), math.min(z0, c.Z - ez)
		x1, y1, z1 = math.max(x1, c.X + ex), math.max(y1, c.Y + ey), math.max(z1, c.Z + ez)
	end
	if x0 > x1 then
		return nil, nil
	end
	return Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
end

local function biggest(parts: { BasePart }): BasePart?
	local best: BasePart? = nil
	for _, p in parts do
		if not best or p.Size.Magnitude > (best :: BasePart).Size.Magnitude then
			best = p
		end
	end
	return best
end

-- The model's pivot: PrimaryPart.CFrame * PivotOffset (what Studio's pivot tools move).
function Assets.pivotOf(model: Model): CFrame?
	local ok, pivot = pcall(function()
		return (model :: any):GetPivot()
	end)
	if ok then
		return pivot
	end
	local primary = model.PrimaryPart
	if primary then
		return primary.CFrame * primary.PivotOffset
	end
	return nil
end

-- Sets the model's pivot to `cf` through its PrimaryPart (picking the biggest part if it has none).
local function setPivot(model: Model, cf: CFrame)
	local primary = model.PrimaryPart or biggest(partsOf(model))
	if primary then
		model.PrimaryPart = primary
		primary.PivotOffset = primary.CFrame:Inverse() * cf
	end
end

-- A CFrame at `pos` whose front (-Z, LookVector) faces horizontal direction `dir`.
function Assets.facing(pos: Vector3, dir: Vector3): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, math.atan2(-dir.X, -dir.Z), 0)
end

-- A stable pseudo-random number in [0, 1) from a position: the same in Roblox and under Lune (whose
-- Random stand-in has a different sequence), so a baked map and a regenerated one pick the same variants.
function Assets.hash(pos: Vector3): number
	local x = math.round(pos.X * 4) * 73856093 % 4294967296
	local y = math.round(pos.Y * 4) * 83492791 % 4294967296
	local z = math.round(pos.Z * 4) * 19349663 % 4294967296
	return bit32.bxor(x, y, z) % 10007 / 10007
end

-- A ground CFrame at `pos` turned by a stable pseudo-random yaw, for round props (trees, rocks...).
function Assets.spin(pos: Vector3): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, Assets.hash(pos) * math.pi * 2, 0)
end

----------------------------------------------------------------------------------------------------
-- Placing
----------------------------------------------------------------------------------------------------
local function variantsOf(template: Instance): { Instance }
	if not template:IsA("Folder") then
		return { template }
	end
	local out = {}
	local function collect(folder: Instance)
		for _, child in folder:GetChildren() do
			if child:IsA("Model") or child:IsA("BasePart") then
				table.insert(out, child)
			elseif child:IsA("Folder") then
				collect(child)
			end
		end
	end
	collect(template)
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

local function native(model: Model): boolean
	local ok, fn = pcall(function()
		return (model :: any).ScaleTo
	end)
	return ok and type(fn) == "function"
end

-- Clones `source` and fits it (see Assets.place). Errors on a broken model.
local function fitClone(slot: string, source: Instance, settings: Instance, cframe: CFrame, fitSize: Vector3?): Model
	local model: Model
	if source:IsA("Model") then
		model = source:Clone()
	else -- a lone part saved on its own
		model = Instance.new("Model")
		source:Clone().Parent = model
	end
	local ok, err = pcall(function()
		for _, d in model:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				d:Destroy() -- models carry no code into the game
			end
		end
		local parts = partsOf(model)
		assert(#parts > 0, "it has no parts")

		local yaw = tonumber(settings:GetAttribute("Yaw") or source:GetAttribute("Yaw")) or 0
		local turn = CFrame.Angles(0, math.rad(yaw), 0)
		local lo, hi = Assets.bounds(model, turn:Inverse()) -- bounds after turning it by Yaw
		assert(lo and hi, "it has no visible parts")
		local size = (hi :: Vector3) - (lo :: Vector3)

		local keep = settings:GetAttribute("KeepScale") == true or source:GetAttribute("KeepScale") == true
		local s = 1
		if fitSize and not keep then
			local best = math.huge
			for _, axis in { "X", "Y", "Z" } do
				local want, have = (fitSize :: any)[axis], (size :: any)[axis]
				if want > 0 and want < math.huge and have > 1e-3 then
					best = math.min(best, want / have)
				end
			end
			if best < math.huge then
				s = math.clamp(best, 0.01, 100)
			end
		end
		assert(s == s, "its size is not a number")

		-- Pivot: the bottom centre of its bounds, axes turned by Yaw (front = -Z after the turn).
		local bottom = Vector3.new(((lo :: Vector3).X + (hi :: Vector3).X) / 2, (lo :: Vector3).Y, ((lo :: Vector3).Z + (hi :: Vector3).Z) / 2)
		local pivot = turn:Inverse() * CFrame.new(bottom)

		local solid = Assets.SOLID[slot] == true
		for _, p in parts do
			p.Anchored = true
			p.CanTouch = false
			if not solid then
				p.CanCollide = false
				p.CanQuery = false
			end
		end

		if native(model) then
			setPivot(model, pivot)
			if s ~= 1 then
				-- ScaleTo may also scale built-in SpecialMesh shapes, which already follow their part's Size.
				local meshScales = {}
				for _, d in model:GetDescendants() do
					if d:IsA("SpecialMesh") and d.MeshType ~= Enum.MeshType.FileMesh then
						meshScales[d] = d.Scale
					end
				end
				(model :: any):ScaleTo((model :: any):GetScale() * s)
				for mesh, scale in meshScales do
					mesh.Scale = scale
				end
			end
			(model :: any):PivotTo(cframe)
		else
			local inv = pivot:Inverse()
			for _, p in parts do
				local rel = inv * p.CFrame
				p.Size *= s
				p.CFrame = cframe * CFrame.new(rel.Position * s) * rel.Rotation
			end
			for _, d in model:GetDescendants() do
				if d:IsA("Attachment") then
					d.CFrame = CFrame.new(d.CFrame.Position * s) * d.CFrame.Rotation
				elseif d:IsA("SpecialMesh") and d.MeshType == Enum.MeshType.FileMesh then
					d.Scale *= s
				end
			end
			setPivot(model, cframe)
		end
		model.Name = slot
		model:SetAttribute("Asset", source.Name)
	end)
	if not ok then
		model:Destroy()
		error(err, 0)
	end
	return model
end

-- Clones the slot's model (one of its variants, picked from `cframe`'s position), anchors it, sets the
-- slot's collision policy, puts its bottom centre at `cframe` (front = -Z of `cframe`) and, unless it has
-- KeepScale = true, scales it uniformly so it fits inside `fitSize` (0 or math.huge = that axis is free).
-- Returns nil when the slot has no model or the model is broken (warned once); never errors.
function Assets.place(slot: string, parent: Instance?, cframe: CFrame, fitSize: Vector3?): Model?
	local template, matched = Assets.get(slot)
	if not template then
		return nil
	end
	local variants = variantsOf(template)
	if #variants == 0 then
		warnOnce("broken:" .. template.Name, `[Assets] assets/{template.Name} is an empty folder; the game builds {slot} from code instead`)
		return nil
	end
	local source = variants[math.floor(Assets.hash(cframe.Position) * #variants) + 1]
	local ok, result = pcall(fitClone, matched :: string, source, template, cframe, fitSize)
	if not ok then
		result = string.gsub(tostring(result), "^.-:%d+: ", "") -- drop the "file:line:" prefix
	end
	if not ok then
		warnOnce("broken:" .. source:GetFullName(), `[Assets] assets/{template.Name} ({source.Name}) can't be used, so the game builds {slot} from code instead: {result}`)
		return nil
	end
	local model = result :: Model
	model.Name = slot
	model.Parent = parent
	return model
end

-- Carries the built-in piece's lights and particles over to its replacement, at the same relative spot
-- (scaled to the new height), unless the model brings its own.
local EFFECTS = { "Light", "ParticleEmitter", "Fire", "Smoke", "Sparkles" }
local function isEffect(d: Instance): boolean
	for _, class in EFFECTS do
		if d:IsA(class) then
			return true
		end
	end
	return false
end

local function carryEffects(group: Model, placed: Model, fit: Vector3)
	for _, d in placed:GetDescendants() do
		if isEffect(d) then
			return
		end
	end
	local from, to = Assets.pivotOf(group), Assets.pivotOf(placed)
	local primary = placed.PrimaryPart
	if not (from and to and primary) then
		return
	end
	local _, hi = Assets.bounds(placed, to)
	local ratio = if hi and fit.Y > 0 then (hi :: Vector3).Y / fit.Y else 1
	for _, d in group:GetDescendants() do
		local host = d.Parent
		if isEffect(d) and host and (host:IsA("BasePart") or host:IsA("Attachment")) then
			local pos = if host:IsA("BasePart") then host.CFrame.Position else ((host.Parent :: BasePart).CFrame * (host :: Attachment).CFrame).Position
			local spot = Instance.new("Attachment")
			spot.Name = d.Name .. "Spot"
			spot.CFrame = primary.CFrame:Inverse() * (to * CFrame.new((from :: CFrame):PointToObjectSpace(pos) * ratio))
			spot.Parent = primary
			d:Clone().Parent = spot
		end
	end
end

-- Replaces a slot group (a piece built from code, or an earlier model) with the slot's model, at the
-- group's current pivot (so hand moves are kept) and in its FitSize. Returns the new model, or nil.
function Assets.replace(group: Model): Model?
	local slot = group:GetAttribute("AssetSlot")
	local pivot = Assets.pivotOf(group)
	if type(slot) ~= "string" or not pivot or not group.Parent then
		return nil
	end
	local fit = group:GetAttribute("FitSize")
	local fitSize = if typeof(fit) == "Vector3" then fit else nil
	local placed = Assets.place(slot, group.Parent, pivot :: CFrame, fitSize)
	if not placed then
		return nil
	end
	placed.Name = group.Name
	placed:SetAttribute("AssetSlot", slot)
	if fitSize then
		placed:SetAttribute("FitSize", fitSize)
		carryEffects(group, placed, fitSize)
	end
	group:Destroy()
	return placed
end

-- Builds a map piece: `build(container)` makes the piece from code inside a group Model named `slot`,
-- tagged with AssetSlot and FitSize (the space the piece uses around `cframe`, a ground point whose -Z is
-- the piece's front: twice its reach either side and its height above the ground, times `slack`, where a
-- 0 component leaves that axis free). The group's pivot is `cframe`. If the slot has a model, it replaces
-- the group right away. With `slot` false the piece is built straight into `parent`, untagged.
local DEFAULT_SLACK = Vector3.new(1.5, 1, 1.5) -- as tall as the built-in piece, up to 1.5x as wide
function Assets.swap(slot: string | false, parent: Instance, cframe: CFrame, build: (Instance) -> (), slack: Vector3?): Model?
	if not slot then
		build(parent)
		return nil
	end
	local group = Instance.new("Model")
	group.Name = slot
	build(group)
	local lo, hi = Assets.bounds(group, cframe)
	if lo and hi then
		local k = slack or DEFAULT_SLACK
		local reach = Vector3.new(math.max(-lo.X, hi.X) * 2, math.max(hi.Y, 0.1), math.max(-lo.Z, hi.Z) * 2)
		group:SetAttribute("AssetSlot", slot)
		group:SetAttribute("FitSize", reach * k)
		setPivot(group, cframe)
	end
	group.Parent = parent
	if lo and Assets.get(slot) then
		return Assets.replace(group) or group
	end
	return group
end

-- Puts the assets folder's models into a map: every slot group still built from code (or, with `all`,
-- every slot group) whose slot has a model is replaced where it stands. Returns how many were replaced.
function Assets.refresh(root: Instance, all: boolean?): number
	Assets.audit()
	local groups = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Model") and type(d:GetAttribute("AssetSlot")) == "string" and (all or d:GetAttribute("Asset") == nil) then
			table.insert(groups, d)
		end
	end
	local n = 0
	local have: { [string]: boolean } = {}
	for _, group in groups do
		local slot = group:GetAttribute("AssetSlot") :: string
		if have[slot] == nil then
			have[slot] = Assets.get(slot) ~= nil
		end
		if have[slot] and group.Parent and Assets.replace(group) then
			n += 1
		end
	end
	return n
end

-- The scale factor a fitted model was given (Model:GetScale in Roblox; 1 under Lune, which resizes the
-- parts themselves).
function Assets.scaleOf(model: Model): number
	local ok, s = pcall(function()
		return (model :: any):GetScale()
	end)
	return if ok and type(s) == "number" then s else 1
end

return Assets
