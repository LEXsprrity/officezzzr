-- New players' first steps, logged to Roblox's onboarding funnel (Creator Hub > Analytics > Funnels), to see
-- where they leave (owner 2026-10-29: Day 1 retention 2.93%, 7.4 min a play). Only players who join without
-- the tutorial done are followed (new ones; ProfileStore marks veterans' old saves done). Each step is logged
-- once a session; Roblox counts each onboarding step once per player, so a rejoin can't count it twice.
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))

local Funnel = {}

-- In order: the funnel's steps 1..n.
Funnel.STEPS = { "Joined", "Stole a seed", "Brought it home", "Planted", "Finished tutorial", "First sale", "Zone 2 Speed" }

Funnel.SPEED_CHECK = 5 -- seconds between checks for the Speed to reach the second zone

-- Sends one step (replaced in tests). A failed call only loses a data point.
function Funnel.send(player: Player, step: number, name: string)
	pcall(function()
		game:GetService("AnalyticsService"):LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

local followed: { [Player]: { [number]: boolean } } = {}

-- Starts following a player who just joined (`isNew`: their tutorial isn't done yet).
function Funnel.start(player: Player, isNew: boolean)
	if isNew then
		followed[player] = {}
		Funnel.mark(player, "Joined")
	end
end

-- Logs `name` for a followed player, the first time this session.
function Funnel.mark(player: Player, name: string)
	local done = followed[player]
	local step = table.find(Funnel.STEPS, name)
	if not done or not step or done[step] then
		return
	end
	done[step] = true
	Funnel.send(player, step, name)
end

function Funnel.stop(player: Player)
	followed[player] = nil
end

function Funnel.following(player: Player): boolean
	return followed[player] ~= nil
end

-- The Speed step: every followed player whose Speed reached the second zone's.
function Funnel.checkSpeed()
	local need = Config.ZONES[2].req
	for player in followed do
		local s = Sessions.get(player)
		if s and s.profile.speed >= need then
			Funnel.mark(player, "Zone 2 Speed")
		end
	end
end

function Funnel.init()
	task.spawn(function()
		while true do
			task.wait(Funnel.SPEED_CHECK)
			Funnel.checkSpeed()
		end
	end)
end

return Funnel
