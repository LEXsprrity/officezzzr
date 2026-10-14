--!strict
-- Pure treadmill rules shared by the server and the client: which belt a position stands on, whether it
-- is the player's own, and when the client loops the run-in-place animation. A belt is the part tagged
-- Role = "TreadmillBelt" with its plot's PlotIndex attribute (WorldBuilder). Only your own treadmill
-- pays Speed (SpeedService checks your plot's belt), so only your own one plays the animation.
local Treadmill = {}

-- Is `pos` (a HumanoidRootPart's position) standing on a belt with this CFrame and Size: inside its
-- footprint and up to 7 studs above its centre? Same box as WorldBuilder.onBelt, the server's check.
function Treadmill.onBelt(cf: CFrame, size: Vector3, pos: Vector3): boolean
	local rel = cf:PointToObjectSpace(pos)
	return math.abs(rel.X) <= size.X / 2 and math.abs(rel.Z) <= size.Z / 2 and rel.Y >= 0 and rel.Y <= 7
end

-- The belt `pos` stands on and its plot index (nil if the belt has none), or nil off every belt.
function Treadmill.beltAt(belts: { BasePart }, pos: Vector3): (BasePart?, number?)
	for _, belt in belts do
		if belt.Parent and Treadmill.onBelt(belt.CFrame, belt.Size, pos) then
			local plot = belt:GetAttribute("PlotIndex")
			return belt, if type(plot) == "number" then plot else nil
		end
	end
	return nil, nil
end

-- What standing at `pos` means for a player whose plot is `myPlot` (nil before the server sent it):
-- "own" (their treadmill: Speed and the run animation), "other" (somebody else's: nothing) or nil (on no
-- belt). A belt without a plot index, or a player without a plot, is never "own".
function Treadmill.standing(belts: { BasePart }, pos: Vector3, myPlot: number?): ("own" | "other")?
	local belt, plot = Treadmill.beltAt(belts, pos)
	if not belt then
		return nil
	end
	return if myPlot ~= nil and plot == myPlot then "own" else "other"
end

-- Whether the client loops the run animation: alive, on their own treadmill, and not walking (walking
-- already plays the run animation).
function Treadmill.shouldRun(standing: ("own" | "other")?, alive: boolean, moveMagnitude: number): boolean
	return alive and standing == "own" and moveMagnitude < 0.1
end

return Treadmill
