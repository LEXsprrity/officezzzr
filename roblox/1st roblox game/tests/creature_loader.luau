-- Loads src/server/CreatureModels.luau under Lune with the real (Lune) Roblox instance API, so its models
-- can be built and measured. Lune checks every property name and value type against the reflection
-- database. Returns (CreatureModels, Config).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Config = H.shared("Config")
local configNode = {}
local assetsNode = {}
local sharedNode = { WaitForChild = function(_, name)
	return if name == "Config" then configNode else nil
end }
local serverNode = { WaitForChild = function(_, name)
	assert(name == "Assets", "CreatureModels required server module " .. name)
	return assetsNode
end }

local env = {
	game = { GetService = function(_, name)
		assert(name == "ReplicatedStorage", "CreatureModels touched service " .. name)
		return { WaitForChild = function()
			return sharedNode
		end }
	end },
	script = { Parent = serverNode },
	require = function(target)
		if target == assetsNode then
			return H.server("Assets") -- reads the harness's ServerStorage.Assets
		end
		assert(target == configNode, "unexpected require")
		return Config
	end,
	warn = function(...)
		table.insert(H.warnings, table.concat({ ... }, " "))
	end,
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
}

local file = "src/server/CreatureModels.luau"
local CreatureModels = luau.load(fs.readFile(file), { debugName = file, environment = env })()
return { CreatureModels = CreatureModels, Config = Config }
