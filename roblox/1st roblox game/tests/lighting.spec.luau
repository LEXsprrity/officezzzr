-- Day/night lighting: both looks apply to a real (Lune) Lighting and its effects (every property name and
-- value type is checked against the Roblox reflection database), default.project.json ships the day look,
-- and the clock keeps the sun high by day and never jumps.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Config = H.shared("Config")
local LightingLook = H.server("LightingLook")

local cycle = Config.DAY_SECONDS + Config.NIGHT_SECONDS
local effects = {}
for className in LightingLook.EFFECTS do
	local inst = roblox.Instance.new(className)
	inst.Parent = H.lighting
	effects[className] = inst
end

local function close(a: any, b: any, eps: number): boolean
	if typeof(a) == "Color3" then
		return math.abs(a.R - b.R) <= eps and math.abs(a.G - b.G) <= eps and math.abs(a.B - b.B) <= eps
	end
	return math.abs(a - b) <= eps
end

H.test("lighting: the day and night looks apply to real Lighting instances", function()
	LightingLook.apply(H.lighting, effects, 60) -- mid-day
	for prop, pair in LightingLook.LIGHTING do
		H.ok(close(H.lighting[prop], pair[1], 1e-3), `day {prop}`)
	end
	LightingLook.apply(H.lighting, effects, Config.DAY_SECONDS + Config.NIGHT_SECONDS / 2) -- mid-night
	for className, look in LightingLook.EFFECTS do
		for prop, pair in look do
			H.ok(close(effects[className][prop], pair[2], 1e-3), `night {className}.{prop}`)
		end
	end
	H.ok(H.lighting.ClockTime < 5 or H.lighting.ClockTime > 19, "the moon is up at mid-night")
end)

H.test("lighting: vivid by day, and night stays readable (bright blue ambient, not murky)", function()
	local cc = LightingLook.EFFECTS.ColorCorrectionEffect
	H.ok(cc.Saturation[1] >= 0.2 and cc.Saturation[1] <= 0.35, "day saturation up")
	H.ok(LightingLook.EFFECTS.Atmosphere.Density[1] <= 0.1, "thin air by day")
	local nightAmbient = LightingLook.LIGHTING.OutdoorAmbient[2]
	H.ok(nightAmbient.B > nightAmbient.R and (nightAmbient.R + nightAmbient.G + nightAmbient.B) / 3 > 0.5, "night ambient is blue and bright")
end)

H.test("lighting: default.project.json ships the day look", function()
	local project = serde.decode("json", fs.readFile("default.project.json"))
	local lighting = project.tree.Lighting
	local function check(props: { [string]: any }, look: { [string]: { any } }, what: string)
		for prop, pair in look do
			local v = props[prop]
			H.ok(v ~= nil, `{what}.{prop} is set in default.project.json`)
			local want = pair[1]
			if typeof(want) == "Color3" then
				v = roblox.Color3.new(v[1], v[2], v[3])
			end
			H.ok(close(v, want, 0.003), `{what}.{prop}: project {v} vs day look {want}`)
		end
	end
	check(lighting["$properties"], LightingLook.LIGHTING, "Lighting")
	for _, child in lighting do
		if type(child) == "table" and child["$className"] and LightingLook.EFFECTS[child["$className"]] then
			check(child["$properties"], LightingLook.EFFECTS[child["$className"]], child["$className"])
		end
	end
	local clock = lighting["$properties"].ClockTime
	H.ok(clock >= LightingLook.DAY_CLOCK[1] and clock <= LightingLook.DAY_CLOCK[2], "Studio shows a day-time clock")
end)

H.test("lighting: from spawn you see to the end of the map (no streaming cut-off, thin air, no fog)", function()
	local project = serde.decode("json", fs.readFile("default.project.json"))
	local ws = project.tree.Workspace["$properties"] or {}
	-- The whole map is always there: either streaming is off, or its radius covers base to back wall.
	local span = Config.END_X + 400 -- the base reaches ~250 studs behind x = 0; the camera can stand anywhere
	H.ok(ws.StreamingEnabled == false or (ws.StreamingMinRadius or 0) >= span, `streaming would cut the map ({ws.StreamingEnabled}, min radius {ws.StreamingMinRadius})`)
	local props = project.tree.Lighting["$properties"]
	H.ok(props.FogEnd == nil or props.FogEnd >= 100000, "no Lighting fog")
	local atmosphere = LightingLook.EFFECTS.Atmosphere
	for i, phase in { "day", "night" } do
		H.ok(atmosphere.Density[i] <= 0.1, `{phase}: thin air ({atmosphere.Density[i]})`)
		H.ok(atmosphere.Haze[i] <= 0.3, `{phase}: little haze ({atmosphere.Haze[i]})`)
	end
	H.eq(atmosphere.Haze[1], 0, "a clear day")
end)

H.test("lighting: the sun stays high all day, sets and rises inside the night fades, and the clock never jumps", function()
	local prev = LightingLook.clockTime(0)
	for s = 1, cycle * 2 do
		local now = s
		local clock = LightingLook.clockTime(now)
		local step = (clock - prev) % 24
		H.ok(step < 0.5, `clock jumps by {step} h at {now}s`)
		prev = clock
		local night, left = Config.dayPhase(now)
		if not night then
			H.ok(clock >= LightingLook.DAY_CLOCK[1] - 1e-6 and clock <= LightingLook.DAY_CLOCK[2] + 1e-6, `day clock {clock}`)
		elseif Config.nightBlend(now) >= 0.999 then
			-- Fully night: the sun is down (after 18:30, before 05:30).
			H.ok(clock >= LightingLook.SUNSET - 1e-6 or clock <= LightingLook.SUNRISE - 24 + 1e-6, `full night at {clock} ({left}s left)`)
		end
	end
end)

return nil
