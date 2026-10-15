-- Test harness: loads the real modules from src/ under Lune with a mocked Roblox environment.
-- `game:GetService("ReplicatedStorage").Shared.X` and `script.Parent.X` resolve to files in src/.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Harness = {}

----------------------------------------------------------------------------------------------------
-- Virtual instance tree over src/
----------------------------------------------------------------------------------------------------
type Node = { Name: string, Parent: Node?, __file: string?, __children: { [string]: Node } }

local function makeNode(name: string, parent: Node?, file: string?): Node
	local node = { Name = name, Parent = parent, __file = file, __children = {} }
	return setmetatable(node, {
		__index = function(self, key)
			if key == "WaitForChild" or key == "FindFirstChild" then
				return function(this, childName)
					local child = rawget(this, "__children")[childName]
					if child == nil and key == "WaitForChild" then
						error(`mock WaitForChild: {childName} not found under {rawget(this, "Name")}`)
					end
					return child
				end
			end
			return rawget(self, "__children")[key]
		end,
	}) :: any
end

local function folder(name: string, dir: string, parent: Node?): Node
	local node = makeNode(name, parent, nil)
	for _, entry in fs.readDir(dir) do
		local modName = string.match(entry, "^(.-)%.luau$")
		if modName and not string.find(modName, "%.server$") and not string.find(modName, "%.client$") then
			node.__children[modName] = makeNode(modName, node, dir .. "/" .. entry)
		elseif fs.isDir(dir .. "/" .. entry) then -- a sub-folder (Rojo makes it a Folder), e.g. Server/Zones
			node.__children[entry] = folder(entry, dir .. "/" .. entry, node)
		end
	end
	return node
end

local sharedNode = folder("Shared", "src/shared", nil)
-- Like default.project.json: icons/ids.json is the JSON ModuleScript Shared.IconIds (Config.ICONS).
sharedNode.__children.IconIds = makeNode("IconIds", sharedNode, "icons/ids.json")
-- ...and monetization/ids.json is Shared.MonetizationIds (the gamepass / developer product ids).
-- Tests run with every id = 0 (the "coming soon" stubs) so shop rules are tested the same way whatever ids
-- the game ships with; monetization.spec checks the real monetization/ids.json separately.
sharedNode.__children.MonetizationIds = makeNode("MonetizationIds", sharedNode, "tests/fixtures/monetization_stub.json")
local serverNode = folder("Server", "src/server", nil)

local services = {
	ReplicatedStorage = makeNode("ReplicatedStorage", nil, nil),
	ServerScriptService = makeNode("ServerScriptService", nil, nil),
}
services.ReplicatedStorage.__children.Shared = sharedNode
services.ServerScriptService.__children.Server = serverNode

-- A real (Lune) DataModel so instance-building modules like WorldBuilder can run; Lune checks
-- every property name and value type against the Roblox reflection database.
local dataModel = roblox.Instance.new("DataModel")
Harness.workspace = dataModel:GetService("Workspace")
Harness.serverStorage = dataModel:GetService("ServerStorage")
services.ServerStorage = Harness.serverStorage :: any
Harness.lighting = dataModel:GetService("Lighting")
-- The mocked services (a test may add one, e.g. RunService, or put a real Folder under ReplicatedStorage.__children)
Harness.services = services

-- The assets folder, loaded like Rojo maps it: each assets/<Name>.rbxm(x) becomes ServerStorage.Assets.<Name>.
-- Files that don't load are listed in Harness.assetErrors (a test fails on them).
Harness.assets = roblox.Instance.new("Folder")
Harness.assets.Name = "Assets"
Harness.assets.Parent = Harness.serverStorage
Harness.assetFiles = {} :: { string }
Harness.assetErrors = {} :: { string }
if fs.isDir("assets") then
	for _, entry in fs.readDir("assets") do
		local name = string.match(entry, "^(.+)%.rbxmx?$")
		if name then
			table.insert(Harness.assetFiles, entry)
			local ok, roots = pcall(roblox.deserializeModel, fs.readFile("assets/" .. entry))
			if ok and #roots == 1 then
				roots[1].Name = name
				roots[1].Parent = Harness.assets
			else
				table.insert(Harness.assetErrors, `assets/{entry}: {if ok then `{#roots} top-level instances (save exactly one Model or Folder)` else roots}`)
			end
		end
	end
end

local game = {
	GetService = function(_, name: string)
		local s = services[name]
		if not s then
			error("mock game:GetService: " .. name .. " is not mocked")
		end
		return s
	end,
}

----------------------------------------------------------------------------------------------------
-- Globals
----------------------------------------------------------------------------------------------------
Harness.warnings = {} :: { string }

local taskMock = {
	wait = function(n: number?)
		return n or 0 -- never actually sleep in tests
	end,
	spawn = function(fn, ...)
		fn(...)
	end,
	defer = function(fn, ...)
		fn(...)
	end,
	delay = function(n: number, fn, ...) -- never runs by itself: a test may run Harness.delayed's entries
		table.insert(Harness.delayed, { seconds = n, fn = fn, args = table.pack(...) })
	end,
}
Harness.delayed = {} :: { { seconds: number, fn: (...any) -> (), args: any } }

-- Runs (and clears) every task.delay callback queued so far.
function Harness.runDelayed()
	local queued = Harness.delayed
	Harness.delayed = {}
	for _, d in queued do
		d.fn(table.unpack(d.args, 1, d.args.n))
	end
end

-- Roblox's Random isn't in Lune: a small seeded stand-in (same API shape, different sequence).
local RandomMock = {}
RandomMock.__index = RandomMock
function RandomMock.new(seed: number?)
	return setmetatable({ state = math.floor(seed or os.clock() * 1e6) % 2147483647 + 1 }, RandomMock)
end
function RandomMock:NextNumber(lo: number?, hi: number?): number
	self.state = (self.state * 48271) % 2147483647
	local u = (self.state - 1) / 2147483646
	if lo == nil then
		return u
	end
	return (lo :: number) + u * ((hi :: number) - (lo :: number))
end
function RandomMock:NextInteger(lo: number, hi: number): number
	return math.min(hi, lo + math.floor(self:NextNumber() * (hi - lo + 1)))
end
Harness.Random = RandomMock

local cache: { [string]: any } = {}
local requireModule

local function envFor(node: Node)
	return {
		script = node,
		game = game,
		require = requireModule,
		task = taskMock,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring((select(i, ...))))
			end
			table.insert(Harness.warnings, table.concat(parts, " "))
		end,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Vector2 = roblox.Vector2,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Font = roblox.Font,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Instance = roblox.Instance,
		Enum = roblox.Enum,
		Random = RandomMock,
		workspace = Harness.workspace,
		typeof = typeof,
	}
end

requireModule = function(node: any)
	local file = type(node) == "table" and rawget(node, "__file")
	if not file then
		error("mock require: not a module node")
	end
	if cache[file] == nil and string.match(file, "%.json$") then
		cache[file] = serde.decode("json", fs.readFile(file)) -- Rojo makes a .json file a ModuleScript returning its data
	elseif cache[file] == nil then
		local source = fs.readFile(file)
		local chunk = luau.load(source, { debugName = file, environment = envFor(node) })
		cache[file] = chunk()
	end
	return cache[file]
end

function Harness.shared(name: string): any
	return requireModule(sharedNode.__children[name])
end

function Harness.server(name: string): any
	return requireModule(serverNode.__children[name])
end

-- Stands `value` in for the server module `name` (before anything requires it), e.g. Net, whose remotes
-- can't be parented to the mocked ReplicatedStorage. Keeps the first stand-in if called again.
function Harness.stubServer(name: string, value: any): any
	local file = rawget(serverNode.__children[name], "__file")
	if cache[file] == nil then
		cache[file] = value
	end
	return cache[file]
end

Harness.Vector3 = roblox.Vector3

-- Runs a client script (src/client/*.client.luau) with the mocked modules, and `overrides` on top of the
-- globals (e.g. a workspace stand-in); `services` adds or replaces services for game:GetService.
function Harness.runClient(file: string, overrides: { [string]: any }, extraServices: { [string]: any }?)
	local node = makeNode(string.match(file, "([^/]+)%.luau$") or file, nil, nil)
	local env = envFor(node)
	env.game = {
		GetService = function(_, name: string)
			local s = (extraServices or {})[name] or services[name]
			if not s then
				error("mock game:GetService: " .. name .. " is not mocked")
			end
			return s
		end,
	}
	for k, v in overrides do
		env[k] = v
	end
	for k, v in { print = print, os = os, math = math, string = string, table = table, tostring = tostring, tonumber = tonumber, type = type, pairs = pairs, ipairs = ipairs, select = select, error = error, pcall = pcall, setmetatable = setmetatable, coroutine = coroutine } do
		if env[k] == nil then
			env[k] = v
		end
	end
	luau.load(fs.readFile(file), { debugName = file, environment = env })()
end

-- Runs `fn` with the assets whose names start with `prefix` set aside (e.g. "Creature_": the built-in
-- creatures instead of the plant models), then puts them back, even if `fn` fails.
function Harness.withoutAssets(prefix: string, fn: () -> ())
	local aside = {}
	for _, child in Harness.assets:GetChildren() do
		if string.sub(child.Name, 1, #prefix) == prefix then
			child.Parent = nil
			table.insert(aside, child)
		end
	end
	local ok, err = pcall(fn)
	for _, child in aside do
		child.Parent = Harness.assets
	end
	if not ok then
		error(err, 0)
	end
end

----------------------------------------------------------------------------------------------------
-- Tiny test runner
----------------------------------------------------------------------------------------------------
local tests: { { name: string, fn: () -> () } } = {}

function Harness.test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

function Harness.ok(cond: any, msg: string?)
	if not cond then
		error(msg or "expected truthy", 2)
	end
end

function Harness.eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(`{msg or "not equal"}: got {tostring(a)}, expected {tostring(b)}`, 2)
	end
end

function Harness.near(a: number, b: number, eps: number, msg: string?)
	if math.abs(a - b) > eps then
		error(`{msg or "not near"}: got {a}, expected {b} ± {eps}`, 2)
	end
end

function Harness.deepEq(a: any, b: any, path: string?): (boolean, string?)
	path = path or "root"
	if type(a) ~= type(b) then
		return false, `{path}: type {type(a)} vs {type(b)}`
	end
	if type(a) ~= "table" then
		if a ~= b then
			return false, `{path}: {tostring(a)} vs {tostring(b)}`
		end
		return true
	end
	for k, v in a do
		local ok, why = Harness.deepEq(v, b[k], `{path}.{tostring(k)}`)
		if not ok then
			return false, why
		end
	end
	for k in b do
		if a[k] == nil then
			return false, `{path}.{tostring(k)} missing on left`
		end
	end
	return true
end

function Harness.run(): number
	local failed = 0
	for _, t in tests do
		local ok, err = pcall(t.fn)
		if ok then
			print("  PASS  " .. t.name)
		else
			failed += 1
			print("  FAIL  " .. t.name .. "\n        " .. tostring(err))
		end
	end
	print(string.format("\n%d/%d passed", #tests - failed, #tests))
	return failed
end

return Harness
