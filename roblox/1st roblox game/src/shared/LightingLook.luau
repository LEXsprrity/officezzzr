-- The day and night looks (pure: no services, so the tests apply it to real Lune instances). The DAY look
-- is a clear, natural simulator day: normal sun, clean blue default sky with clouds, crisp shadows, thin
-- clear air and lightly saturated colour (never glaring). The NIGHT look is a clear, readable blue night
-- (night has gameplay), never murky.
-- Neither phase moves: the sun stands still at DAY_CLOCK all day and the moon at NIGHT_CLOCK all night.
-- When the phase flips, every player's screen fades to black for about a second (fadeAlpha, drawn by
-- Client/DayNight), the look switches while it is black, and the screen fades back in. The server
-- (AmbientService) and every client switch on the same server-time flip (Config.dayPhase), so all agree.
-- default.project.json ships the day look, so Studio's edit mode shows the same; tests/lighting.spec.luau
-- keeps the two in step.
local Config = require(script.Parent:WaitForChild("Config"))

local LightingLook = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- property -> { day, night } per instance
export type Look = { [string]: { any } }

-- Day values are calm and natural (owner playtest: the old 3 Brightness, +0.28 saturation and bloom were
-- glaring and washed out): a normal sun, a plain grey-blue ambient, no exposure boost, a little saturation
-- and contrast, bloom only on the brightest neon. Night stays a clear, readable blue, bright enough that the
-- far zones (the dark Lava Fields and Deep Space) still read against the black sky from the spawn (owner).
LightingLook.LIGHTING = {
	Brightness = { 2, 1.7 },
	Ambient = { rgb(70, 72, 82), rgb(106, 120, 182) },
	OutdoorAmbient = { rgb(128, 130, 138), rgb(136, 154, 220) },
	ColorShift_Top = { rgb(236, 228, 212), rgb(170, 190, 255) },
	ColorShift_Bottom = { rgb(40, 55, 80), rgb(40, 50, 110) },
	ExposureCompensation = { -0.1, 0.25 },
	EnvironmentDiffuseScale = { 0.5, 0.6 },
	EnvironmentSpecularScale = { 0.1, 0.3 }, -- low by day: flat plastic, not glossy
} :: Look

LightingLook.EFFECTS = {
	Atmosphere = {
		Density = { 0, 0 }, -- no air fog at all: from the spawn you see down the whole corridor, day and night
		Color = { rgb(200, 228, 255), rgb(96, 120, 200) },
		Decay = { rgb(110, 160, 220), rgb(54, 70, 150) },
		Haze = { 0, 0 }, -- no haze day or night
	},
	ColorCorrectionEffect = {
		TintColor = { rgb(255, 255, 255), rgb(208, 220, 255) },
		Saturation = { 0.12, 0.15 },
		Contrast = { 0.04, 0.06 },
		Brightness = { 0, 0.03 },
	},
	BloomEffect = {
		Intensity = { 0.15, 0.5 },
		Threshold = { 2.5, 1.6 },
	},
	SunRaysEffect = {
		Intensity = { 0.02, 0 },
	},
} :: { [string]: Look }
-- Fixed clocks: the sun stands in the afternoon sky all day, the moon high in the sky all night.
LightingLook.DAY_CLOCK = 14
LightingLook.NIGHT_CLOCK = 0

-- The fade to black at each flip (seconds): FADE_OUT to black, BLACK held (centred on the flip, where the
-- look switches), FADE_IN back. About a second end to end.
LightingLook.FADE_OUT = 0.35
LightingLook.BLACK = 0.3
LightingLook.FADE_IN = 0.4

function LightingLook.clockTime(now: number): number
	local night = Config.dayPhase(now)
	return if night then LightingLook.NIGHT_CLOCK else LightingLook.DAY_CLOCK
end

-- How black the screen is at `now`, 0..1: 1 around each phase flip, 0 the rest of the time.
function LightingLook.fadeAlpha(now: number): number
	local night, left = Config.dayPhase(now)
	local elapsed = (if night then Config.NIGHT_SECONDS else Config.DAY_SECONDS) - left
	local half = LightingLook.BLACK / 2
	if left < half + LightingLook.FADE_OUT then -- fading out before the flip
		return math.clamp((half + LightingLook.FADE_OUT - left) / LightingLook.FADE_OUT, 0, 1)
	elseif elapsed < half + LightingLook.FADE_IN then -- fading back in after it
		return math.clamp((half + LightingLook.FADE_IN - elapsed) / LightingLook.FADE_IN, 0, 1)
	end
	return 0
end

function LightingLook.applyLook(inst: Instance, look: Look, night: boolean)
	local i = if night then 2 else 1
	for prop, pair in look do
		(inst :: any)[prop] = pair[i]
	end
end

-- Sets the fixed clock and the whole look of a phase at once. `effects` maps class name → instance
-- (a missing one is skipped: a client may not have it yet).
function LightingLook.applyPhase(lighting: Instance, effects: { [string]: Instance }, night: boolean)
	(lighting :: any).ClockTime = if night then LightingLook.NIGHT_CLOCK else LightingLook.DAY_CLOCK
	LightingLook.applyLook(lighting, LightingLook.LIGHTING, night)
	for className, look in LightingLook.EFFECTS do
		local inst = effects[className]
		if inst then
			LightingLook.applyLook(inst, look, night)
		end
	end
end

-- The look of the phase at server time `now`.
function LightingLook.apply(lighting: Instance, effects: { [string]: Instance }, now: number)
	LightingLook.applyPhase(lighting, effects, (Config.dayPhase(now)))
end

-- Every effect the looks touch, by class name, found under `lighting` (nil ones are left out).
function LightingLook.findEffects(lighting: Instance): { [string]: Instance }
	local out = {}
	for className in LightingLook.EFFECTS do
		out[className] = lighting:FindFirstChildOfClass(className :: any)
	end
	return out
end

return LightingLook
