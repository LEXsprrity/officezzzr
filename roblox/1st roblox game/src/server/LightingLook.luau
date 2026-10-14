-- The day and night looks (pure: no services, so the tests apply it to real Lune instances). The DAY look
-- is a bright simulator day: strong sun, clean blue default sky with clouds, crisp shadows, thin light-blue
-- air and vivid colour. The NIGHT look is a clear, readable blue night (night has gameplay), never murky.
-- AmbientService blends them by Config.nightBlend. default.project.json ships the day look, so Studio's
-- edit mode shows the same; tests/lighting.spec.luau keeps the two in step.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local LightingLook = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- property -> { day, night } per instance
export type Look = { [string]: { any } }

LightingLook.LIGHTING = {
	Brightness = { 3, 1.6 },
	Ambient = { rgb(100, 104, 118), rgb(92, 108, 170) },
	OutdoorAmbient = { rgb(138, 142, 156), rgb(120, 140, 210) },
	ColorShift_Top = { rgb(255, 244, 222), rgb(170, 190, 255) },
	ColorShift_Bottom = { rgb(40, 55, 80), rgb(40, 50, 110) },
	ExposureCompensation = { 0, 0.3 },
	EnvironmentDiffuseScale = { 1, 0.6 },
	EnvironmentSpecularScale = { 0.2, 0.3 }, -- low by day: flat plastic, not glossy
} :: Look

LightingLook.EFFECTS = {
	Atmosphere = {
		Density = { 0.05, 0.08 }, -- thin: from the base you see down the whole corridor, day and night
		Color = { rgb(200, 228, 255), rgb(96, 120, 200) },
		Decay = { rgb(110, 160, 220), rgb(54, 70, 150) },
		Haze = { 0, 0.2 }, -- no haze by day (clear blue sky), a little at night
	},
	ColorCorrectionEffect = {
		TintColor = { rgb(255, 253, 248), rgb(208, 220, 255) },
		Saturation = { 0.28, 0.2 },
		Contrast = { 0.12, 0.1 },
		Brightness = { 0.03, 0.05 },
	},
	BloomEffect = {
		Intensity = { 0.35, 0.7 },
		Threshold = { 1.8, 1.3 },
	},
	SunRaysEffect = {
		Intensity = { 0.04, 0 },
	},
} :: { [string]: Look }

-- The sun stays high all day (DAY_CLOCK, morning to mid-afternoon, so no long orange sunrise/sunset
-- light on the base). Sunset and sunrise happen inside the night's fades, where the blend to the night
-- look hides them, and the clock never jumps.
LightingLook.DAY_CLOCK = { 9, 15 }
LightingLook.SUNSET, LightingLook.SUNRISE = 18.5, 29.5 -- clock at the end of the dusk fade / start of the dawn fade

function LightingLook.clockTime(now: number): number
	local night, left = Config.dayPhase(now)
	local dayStart, dayEnd = LightingLook.DAY_CLOCK[1], LightingLook.DAY_CLOCK[2]
	if not night then
		local p = 1 - left / Config.DAY_SECONDS
		return dayStart + (dayEnd - dayStart) * p
	end
	local fade = math.min(Config.NIGHT_FADE_SECONDS, Config.NIGHT_SECONDS / 2)
	local elapsed = Config.NIGHT_SECONDS - left
	local clock
	if elapsed < fade then
		clock = dayEnd + (LightingLook.SUNSET - dayEnd) * elapsed / fade
	elseif left < fade then
		clock = LightingLook.SUNRISE + (dayStart + 24 - LightingLook.SUNRISE) * (1 - left / fade)
	else
		clock = LightingLook.SUNSET + (LightingLook.SUNRISE - LightingLook.SUNSET) * (elapsed - fade) / (Config.NIGHT_SECONDS - 2 * fade)
	end
	return clock % 24
end

local function lerp(a: any, b: any, t: number): any
	if typeof(a) == "Color3" then
		return (a :: Color3):Lerp(b, t)
	end
	return a + (b - a) * t
end

function LightingLook.applyLook(inst: Instance, look: Look, t: number)
	for prop, pair in look do
		(inst :: any)[prop] = lerp(pair[1], pair[2], t)
	end
end

-- Sets the clock and blends every look by the night blend at `now`. `effects` maps class name → instance.
function LightingLook.apply(lighting: Instance, effects: { [string]: Instance }, now: number)
	(lighting :: any).ClockTime = LightingLook.clockTime(now)
	local t = Config.nightBlend(now)
	LightingLook.applyLook(lighting, LightingLook.LIGHTING, t)
	for className, look in LightingLook.EFFECTS do
		LightingLook.applyLook(effects[className], look, t)
	end
end

return LightingLook
