-- Day/night lighting: both looks apply to a real (Lune) Lighting and its effects (every property name and
-- value type is checked against the Roblox reflection database), default.project.json ships the day look,
-- the sun and the moon stand still (one fixed clock per phase), and each flip hides behind a fade to black.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Config = H.shared("Config")
local LightingLook = H.shared("LightingLook")

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

H.test("lighting: a clear, natural day that doesn't glare, and night stays readable (bright blue ambient, not murky)", function()
	-- Owner playtest: the old day (Brightness 3, saturation +0.28, contrast +0.12, bloom 0.35) hurt the eyes.
	local L, E = LightingLook.LIGHTING, LightingLook.EFFECTS
	local cc = E.ColorCorrectionEffect
	H.ok(cc.Saturation[1] >= 0.05 and cc.Saturation[1] <= 0.2, "day colours a little saturated, not blown out")
	H.ok(cc.Contrast[1] <= 0.08 and cc.Brightness[1] <= 0.01, "no extra contrast or brightness by day")
	H.ok(L.Brightness[1] <= 2.5 and L.ExposureCompensation[1] <= 0, "a normal sun, no exposure boost")
	local outdoor = L.OutdoorAmbient[1]
	H.ok((outdoor.R + outdoor.G + outdoor.B) / 3 <= 0.55, "a plain outdoor ambient")
	H.ok(E.BloomEffect.Intensity[1] <= 0.25 and E.BloomEffect.Threshold[1] >= 2, "bloom only on the brightest neon")
	H.ok(E.SunRaysEffect.Intensity[1] <= 0.03, "faint sun rays")
	H.ok(E.Atmosphere.Density[1] <= 0.1, "thin air by day")
	local nightAmbient = L.OutdoorAmbient[2]
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
	H.eq(clock, LightingLook.DAY_CLOCK, "Studio shows the day clock")
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
		H.eq(atmosphere.Density[i], 0, `{phase}: no fog`)
		H.ok(atmosphere.Haze[i] <= 0.3, `{phase}: little haze ({atmosphere.Haze[i]})`)
	end
	H.eq(atmosphere.Haze[1], 0, "a clear day")
end)

H.test("lighting: the sun and the moon stand still: one fixed ClockTime per phase, day up high, night dark", function()
	H.ok(LightingLook.DAY_CLOCK >= 10 and LightingLook.DAY_CLOCK <= 15, `the day sun is high ({LightingLook.DAY_CLOCK})`)
	H.ok(LightingLook.NIGHT_CLOCK <= 2 or LightingLook.NIGHT_CLOCK >= 21, `the moon is up at night ({LightingLook.NIGHT_CLOCK})`)
	for s = 0, cycle * 2, 0.5 do
		local night = Config.dayPhase(s)
		local want = if night then LightingLook.NIGHT_CLOCK else LightingLook.DAY_CLOCK
		H.eq(LightingLook.clockTime(s), want, `clock at {s}s`)
		LightingLook.apply(H.lighting, effects, s)
		H.near(H.lighting.ClockTime, want, 1e-3, `Lighting.ClockTime at {s}s`)
	end
	-- the whole look is the phase's own, never a blend
	LightingLook.apply(H.lighting, effects, Config.DAY_SECONDS - 0.01)
	H.near(H.lighting.Brightness, LightingLook.LIGHTING.Brightness[1], 1e-3, "full day look right up to the flip")
	LightingLook.apply(H.lighting, effects, Config.DAY_SECONDS + 0.01)
	H.near(H.lighting.Brightness, LightingLook.LIGHTING.Brightness[2], 1e-3, "full night look right after it")
	H.ok(LightingLook.findEffects(H.lighting).Atmosphere == effects.Atmosphere, "findEffects finds the effects under Lighting")
end)

H.test("lighting: each phase flip fades every screen to black for about a second, the switch inside the black", function()
	local L = LightingLook
	local total = L.FADE_OUT + L.BLACK + L.FADE_IN
	H.ok(total >= 0.8 and total <= 1.5, `about a second ({total} s)`)
	for _, flip in { Config.DAY_SECONDS, cycle, cycle + Config.DAY_SECONDS } do
		H.eq(L.fadeAlpha(flip - 0.001), 1, `black just before the flip at {flip}`)
		H.eq(L.fadeAlpha(flip + 0.001), 1, `black just after the flip at {flip}`)
		H.eq(L.fadeAlpha(flip - L.BLACK / 2 - L.FADE_OUT - 0.01), 0, "clear before the fade out")
		H.eq(L.fadeAlpha(flip + L.BLACK / 2 + L.FADE_IN + 0.01), 0, "clear after the fade in")
		local mid = L.fadeAlpha(flip - L.BLACK / 2 - L.FADE_OUT / 2)
		H.ok(mid > 0.3 and mid < 0.7, `half way through the fade out ({mid})`)
		local last = -1
		for t = flip - 2, flip, 0.01 do
			local a = L.fadeAlpha(t)
			H.ok(a >= last - 1e-9 and a >= 0 and a <= 1, "fades out smoothly")
			last = a
		end
	end
	for s = 5, Config.DAY_SECONDS - 5, 1 do
		H.eq(L.fadeAlpha(s), 0, `no black mid-day ({s}s)`)
	end
	-- Client/DayNight draws it from the shared server clock and switches the local look on the flip
	local src = fs.readFile("src/client/DayNight.client.luau")
	H.ok(string.find(src, "LightingLook.fadeAlpha(now)", 1, true) and string.find(src, "workspace:GetServerTimeNow()", 1, true), "in sync from server time")
	H.ok(string.find(src, "LightingLook.applyPhase(Lighting", 1, true), "switches the look locally")
	H.ok(string.find(src, "IgnoreGuiInset = true", 1, true) and string.find(src, "DisplayOrder = 1000", 1, true), "covers the whole screen, HUD too")
	local amb = fs.readFile("src/server/AmbientService.luau")
	H.ok(not string.find(amb, "nightBlend", 1, true) and string.find(amb, "applyPhase", 1, true), "the server sets one fixed look per phase")
end)

return nil
