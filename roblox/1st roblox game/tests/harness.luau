-- Test harness: loads the real modules from src/ under Lune with a mocked Roblox environment.
-- `game:GetService("ReplicatedStorage").Shared.X` and `script.Parent.X` resolve to files in src/.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

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
		end
	end
	return node
end

local sharedNode = folder("Shared", "src/shared", nil)
local serverNode = folder("Server", "src/server", nil)

local services = {
	ReplicatedStorage = makeNode("ReplicatedStorage", nil, nil),
	ServerScriptService = makeNode("ServerScriptService", nil, nil),
}
services.ReplicatedStorage.__children.Shared = sharedNode
services.ServerScriptService.__children.Server = serverNode

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
	delay = function(_n, _fn) end,
}

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

-- A real (Lune) DataModel so instance-building modules like WorldBuilder can run; Lune checks
-- every property name and value type against the Roblox reflection database.
local dataModel = roblox.Instance.new("DataModel")
Harness.workspace = dataModel:GetService("Workspace")

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
	if cache[file] == nil then
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

Harness.Vector3 = roblox.Vector3

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
