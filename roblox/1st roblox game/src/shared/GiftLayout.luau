--!strict
-- Where everything sits in the "Free Gift!" window (Rewards.client), in design pixels. Pure, so the tests
-- can check that nothing overlaps (owner playtest 2026-10-15: the CLAIM! button covered the three steps):
-- the hint under the title bar, the Speed bag on the left, "~ LIMITED TIME! ~" and "25,000 SPEED!" on the
-- right, the three steps in a row under them and CLAIM! under the steps.
local GiftLayout = {}

export type Rect = { x: number, y: number, w: number, h: number }

GiftLayout.W, GiftLayout.H, GiftLayout.TITLE_H = 760, 580, 84
GiftLayout.STEP_W, GiftLayout.STEP_H, GiftLayout.STEP_GAP = 228, 120, 12

local W = GiftLayout.W
local STEPS_TOP = 356
local stepsLeft = (W - 3 * GiftLayout.STEP_W - 2 * GiftLayout.STEP_GAP) / 2

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

GiftLayout.rects = {
	hint = rect(24, 96, W - 48, 26),
	art = rect(28, 130, 280, 210),
	limited = rect(330, 148, 410, 58),
	amount = rect(324, 212, 420, 84),
	step1 = rect(stepsLeft, STEPS_TOP, GiftLayout.STEP_W, GiftLayout.STEP_H),
	step2 = rect(stepsLeft + GiftLayout.STEP_W + GiftLayout.STEP_GAP, STEPS_TOP, GiftLayout.STEP_W, GiftLayout.STEP_H),
	step3 = rect(stepsLeft + 2 * (GiftLayout.STEP_W + GiftLayout.STEP_GAP), STEPS_TOP, GiftLayout.STEP_W, GiftLayout.STEP_H),
	claim = rect((W - 320) / 2, STEPS_TOP + GiftLayout.STEP_H + 20, 320, 62),
} :: { [string]: Rect }

-- Inside a step (relative to it): its title, then its button (or the Like step's words).
GiftLayout.stepTitle = rect(8, 8, GiftLayout.STEP_W - 16, 30)
GiftLayout.stepBody = rect(12, 48, GiftLayout.STEP_W - 24, 56)

function GiftLayout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function GiftLayout.udim(r: Rect): (UDim2, UDim2)
	return UDim2.fromOffset(r.x, r.y), UDim2.fromOffset(r.w, r.h)
end

return GiftLayout
