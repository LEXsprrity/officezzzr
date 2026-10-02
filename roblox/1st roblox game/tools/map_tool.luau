-- Shared by tools/build_map.luau and tools/apply_assets.luau (and the tests): read, write, regenerate
-- and refresh map/World.rbxm, the hand-editable map that Rojo puts at Workspace.World.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("../tests/harness")

local MapTool = {}

MapTool.PATH = "map/World.rbxm"

-- Loads a map file into the harness's Workspace (replacing any World there) and returns its World.
function MapTool.load(path: string): any
	local roots = roblox.deserializeModel(fs.readFile(path))
	assert(#roots == 1 and roots[1].Name == "World", `{path} must hold exactly one instance named World (got {#roots})`)
	local old = H.workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	roots[1].Parent = H.workspace
	return roots[1]
end

-- Writes a World folder to `path`; returns its part count.
function MapTool.save(world: any, path: string): number
	local count = 0
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		elseif d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			-- Lune keeps `.Font = Enum.Font.X` as a raw EnumItem the file format rejects; store it as FontFace.
			local ok, font = pcall(function()
				return d.Font
			end)
			if ok and typeof(font) == "EnumItem" then
				d.FontFace = roblox.Font.fromEnum(font)
			end
		end
	end
	fs.writeFile(path, roblox.serializeModel({ world }))
	return count
end

-- Regenerates the map from code into `path`. Refuses to replace an existing file unless `args` has
-- "--force", because that discards every hand edit in it. Returns (ok, message).
function MapTool.regenerate(args: { string }, path: string): (boolean, string)
	local force = table.find(args, "--force") ~= nil
	if fs.isFile(path) and not force then
		return false, `{path} already exists, and it is the hand-edited map: the game uses it as it is.\n`
			.. `Not touching it. To REGENERATE the map from code anyway (this DISCARDS every hand edit in it), run:\n`
			.. `  lune run tools/build_map.luau --force\n`
			.. `To put new models from assets/ into the current map instead, run: lune run tools/apply_assets.luau`
	end
	if fs.isFile(path) then
		print(`WARNING: regenerating {path} from code. Every hand edit in it is discarded (git still has the old file).`)
	end
	local WorldBuilder = H.server("WorldBuilder")
	WorldBuilder.build()
	local world = H.workspace:FindFirstChild("World")
	assert(world, "WorldBuilder.build() made no Workspace.World")
	local count = MapTool.save(world, path)
	return true, `{path}: regenerated from code, {count} parts, {MapTool.assetCount(world)} pieces from assets/`
end

-- How many pieces of a map came from the assets folder.
function MapTool.assetCount(world: any): number
	local n = 0
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("AssetSlot") and d:GetAttribute("Asset") then
			n += 1
		end
	end
	return n
end

-- Puts the assets folder's models into the map file at `path`, keeping every hand edit: each piece that
-- is still built from code (or, with "--all", every slot piece) is replaced where it stands. The map must
-- still validate afterwards. Returns (ok, message).
function MapTool.applyAssets(args: { string }, path: string): (boolean, string)
	if not fs.isFile(path) then
		return false, `{path} doesn't exist; make it first with: lune run tools/build_map.luau`
	end
	local Assets = H.server("Assets")
	local WorldBuilder = H.server("WorldBuilder")
	local world = MapTool.load(path)
	local n = Assets.refresh(world, table.find(args, "--all") ~= nil)
	local plots, _, problems = WorldBuilder.adopt(world)
	if not plots then
		return false, `{path} doesn't validate, so it was not written:\n  ` .. table.concat(problems, "\n  ")
	end
	if n == 0 then
		return true, `{path}: nothing to replace (no piece still built from code has a model in assets/)`
	end
	local count = MapTool.save(world, path)
	return true, `{path}: {n} pieces replaced by models from assets/ ({count} parts)`
end

return MapTool
