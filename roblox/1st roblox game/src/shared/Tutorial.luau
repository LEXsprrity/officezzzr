--!strict
-- The first-time tutorial (owner 2026-10-19: "person spawns in, gets some red arrows that go until they reach a
-- seed with text on top saying steal a seed, then ... every single step from planting to waiting for growth").
-- Pure and shared: the steps, how each one advances, where a new player starts, whether an old save is a
-- veteran's, and the path math the red arrow trail is drawn along. Client/Tutorial draws it all; the server
-- only keeps the `tutorialDone` flag (ProfileStore, Server/TutorialService).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local Tutorial = {}

export type Step = {
	id: string,
	banner: string, -- the instruction at the top of the screen
}

-- In order (owner 2026-10-19: "u just really need 5 steps of the tutorial, go get first seed, go plant first
-- seed, go walk on treadmill, done"; the red arrows on the ground point the way, no words over the targets).
-- Each step's target and how it advances (Tutorial.advance):
--   steal:  a Meadow seed pod; advances when the server says they carry a seed (StatsUpdate `carrying`)
--   home:   their plot; advances when the seed goes into the seed bag (LootEvent "Stored"), back to steal
--           if the seed is lost on the way (caught, dropped, died)
--   plant:  their dirt (and the hotbar's seed slot); advances when a seed is planted (LootEvent "Planted")
--   speed:  their treadmill; advances once their Speed has gone up SPEED_GOAL since the step began
--   ready:  the next zone's Speed sign; finishes on the "Let's go!" button or when they reach the sign
Tutorial.STEPS = {
	{ id = "steal", banner = "Follow the red arrows to steal a seed!" },
	{ id = "home", banner = "Run home with your seed before the guardian catches you!" },
	{ id = "plant", banner = "Press 2, then click your brown dirt to plant your seed!" },
	{ id = "speed", banner = "Walk on your treadmill to get faster!" },
	{ id = "ready", banner = "" }, -- (filled in below from the next zone)
} :: { Step }

do
	local next = Config.ZONES[2]
	Tutorial.STEPS[5].banner = `All done! Get {Format.short(next.req)} Speed to reach the {next.name}.`
end

Tutorial.ARRIVE = 14 -- studs from the next zone's sign that finish the tutorial
Tutorial.SPEED_GOAL = 300 -- Speed to gain on the "get faster" step (a second on the treadmill, or ~300 studs of walking)
Tutorial.LOST_GRACE = 1.5 -- seconds after the carried seed goes before it counts as lost (the "Stored" event may follow)

-- The step's position in STEPS (nil for an unknown id, or "done").
function Tutorial.indexOf(id: string): number?
	for i, s in Tutorial.STEPS do
		if s.id == id then
			return i
		end
	end
	return nil
end

function Tutorial.step(id: string): Step?
	local i = Tutorial.indexOf(id)
	return if i then Tutorial.STEPS[i] else nil
end

-- What the client has seen happen, for advance(). Events: "near" (at the next zone's sign), "pickup", "lost",
-- "stored", "planted", "faster", "finish", "skip".
-- Returns the next step id, "done" when the tutorial is over, or `id` unchanged. Only moves forward,
-- except "lost" (the seed is gone: steal again). An event a later step already covers can jump ahead (a
-- player who plants a seed already in the bag).
function Tutorial.advance(id: string, event: string): string
	if id == "done" then
		return "done"
	end
	if event == "skip" then
		return "done"
	end
	local at = Tutorial.indexOf(id)
	if not at then
		return id
	end
	local function upTo(target: string, from: { string }): string
		return if table.find(from, id) then target else id
	end
	if event == "near" then
		return upTo("done", { "ready" })
	elseif event == "pickup" then
		return upTo("home", { "steal" })
	elseif event == "lost" then
		return upTo("steal", { "home" })
	elseif event == "stored" then
		return upTo("plant", { "steal", "home" })
	elseif event == "planted" then
		return upTo("speed", { "steal", "home", "plant" })
	elseif event == "faster" then
		return upTo("ready", { "speed" })
	elseif event == "finish" then
		return upTo("done", { "ready" })
	end
	return id
end

-- The "get faster" step is done once Speed rose SPEED_GOAL since it began.
function Tutorial.faster(startSpeed: number, speed: number): boolean
	return speed - startSpeed >= Tutorial.SPEED_GOAL
end

-- Where a player who hasn't finished starts (a new one at "steal"; one who left mid-way picks up where their
-- stats say they were). `stats`: carrying (table or false), seedBag, plants.
function Tutorial.startStep(stats: { [string]: any }): string
	if type(stats.carrying) == "table" then
		return "home"
	end
	local plants = if type(stats.plants) == "table" then stats.plants else {}
	if #plants > 0 then
		return "speed"
	end
	if type(stats.seedBag) == "table" then
		for _, n in stats.seedBag do
			if type(n) == "number" and n > 0 then
				return "plant"
			end
		end
	end
	return "steal"
end

----------------------------------------------------------------------------------------------------
-- The save
----------------------------------------------------------------------------------------------------
-- An old save (from before the tutorial: no `tutorialDone`) is a veteran's when they clearly played: any
-- money, a plant (on the plot or in the inventory), a seed in the bag, an Index entry, or VETERAN_SPEED.
Tutorial.VETERAN_SPEED = 1000

local function any(t: any): boolean
	return type(t) == "table" and next(t) ~= nil
end

function Tutorial.isVeteran(data: any): boolean
	if type(data) ~= "table" then
		return false
	end
	return (type(data.money) == "number" and data.money > 0)
		or (type(data.speed) == "number" and data.speed >= Tutorial.VETERAN_SPEED)
		or any(data.plants) or any(data.inv) or any(data.bag) or any(data.index)
end

-- `tutorialDone` from stored data: what was saved, or for a save from before it, whether they're a veteran.
-- No data at all (a brand new player): not done.
function Tutorial.doneFromSave(data: any): boolean
	if type(data) ~= "table" then
		return false
	end
	if type(data.tutorialDone) == "boolean" then
		return data.tutorialDone
	end
	return Tutorial.isVeteran(data)
end

----------------------------------------------------------------------------------------------------
-- The red arrow trail: path math
----------------------------------------------------------------------------------------------------
-- The route on the ground (Y = 0, the client drops each arrow onto the floor) from `from` to `to`, around
-- the plot fence and through the corridor mouth: out of the player's plot by its entrance, through the mouth
-- between the base and the corridor, into the plot by its entrance. `plot` (optional): the player's plot,
-- its centre, the point just outside its entrance and its half size.
export type PlotShape = { center: Vector3, entrance: Vector3, half: number }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function inPlot(plot: PlotShape?, p: Vector3): boolean
	if not plot then
		return false
	end
	return math.abs(p.X - plot.center.X) <= plot.half and math.abs(p.Z - plot.center.Z) <= plot.half
end

Tutorial.MOUTH = Vector3.new(Config.CORRIDOR_START_X, 0, 0) -- where the base's walkway meets the corridor

function Tutorial.route(from: Vector3, to: Vector3, plot: PlotShape?): { Vector3 }
	local a, b = flat(from), flat(to)
	local points = { a }
	local fromIn, toIn = inPlot(plot, a), inPlot(plot, b)
	if plot and fromIn and not toIn then
		table.insert(points, flat(plot.entrance))
	end
	local fromBase, toBase = a.X < Config.CORRIDOR_START_X, b.X < Config.CORRIDOR_START_X
	if fromBase ~= toBase then
		table.insert(points, Tutorial.MOUTH)
	end
	if plot and toIn and not fromIn then
		table.insert(points, flat(plot.entrance))
	end
	table.insert(points, b)
	-- (drop points that sit on top of each other: a zero-length leg has no direction)
	local out = { points[1] }
	for i = 2, #points do
		if (points[i] - out[#out]).Magnitude > 0.5 then
			table.insert(out, points[i])
		end
	end
	return out
end

function Tutorial.length(points: { Vector3 }): number
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	return total
end

-- The point `d` studs along the route, and the direction it heads there.
function Tutorial.pointAt(points: { Vector3 }, d: number): (Vector3, Vector3)
	for i = 2, #points do
		local leg = points[i] - points[i - 1]
		local len = leg.Magnitude
		if d <= len or i == #points then
			local dir = if len > 0 then leg / len else Vector3.new(1, 0, 0)
			return points[i - 1] + dir * math.clamp(d, 0, len), dir
		end
		d -= len
	end
	return points[1], Vector3.new(1, 0, 0)
end

Tutorial.SPACING = 6 -- studs between two arrows
Tutorial.MAX_ARROWS = 60 -- the trail shows this many at most (360 studs ahead of the player)
Tutorial.FLOW = 9 -- studs a second the arrows flow toward the target
Tutorial.FADE_IN = 8 -- studs over which an arrow fades in by the player...
Tutorial.FADE_OUT = 10 -- ...and out at the target (so none pops in or out)
Tutorial.STOP_SHORT = 3 -- the trail ends this far before the target

export type Arrow = { position: Vector3, direction: Vector3, alpha: number }

-- The arrows along the route at time `t` (seconds): every SPACING studs, sliding toward the target at FLOW
-- studs a second, each with an alpha (0..1) that fades it in near the player and out near the target, and
-- the far end of a long route (the MAX_ARROWS-th arrow) too. Deterministic in `t`, so the flow is smooth: the
-- first arrow is always the one nearest the player (alpha 0 right at their feet), so a frame later each arrow
-- is the same one, FLOW x dt further along.
function Tutorial.arrows(points: { Vector3 }, t: number): { Arrow }
	local out: { Arrow } = {}
	local total = Tutorial.length(points) - Tutorial.STOP_SHORT
	if #points < 2 or total <= 0 then
		return out
	end
	local phase = (t * Tutorial.FLOW) % Tutorial.SPACING
	local reach = math.min(total, Tutorial.SPACING * Tutorial.MAX_ARROWS)
	local d = phase
	while d <= reach and #out < Tutorial.MAX_ARROWS do
		local alpha = math.clamp(math.min(d / Tutorial.FADE_IN, (reach - d) / Tutorial.FADE_OUT), 0, 1)
		local position, direction = Tutorial.pointAt(points, d)
		table.insert(out, { position = position, direction = direction, alpha = alpha })
		d += Tutorial.SPACING
	end
	return out
end

-- Eases `current` toward `target` over a frame of `dt` seconds (frame-rate independent): the trail's start
-- follows the player this way, so it never jitters with their footsteps.
function Tutorial.follow(current: Vector3, target: Vector3, dt: number, rate: number?): Vector3
	local k = 1 - math.exp(-(rate or 12) * dt)
	return current:Lerp(target, k)
end

return Tutorial
