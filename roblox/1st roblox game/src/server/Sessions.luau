-- Per-player runtime state around the saved profile, plus the derived numbers every service needs
-- (multipliers, effective slots) and the StatsUpdate/leaderstats push.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(script.Parent:WaitForChild("Net"))
local SpeedLogic = require(script.Parent:WaitForChild("SpeedLogic"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))

local Sessions = {}

export type Carry = {
	zone: number,
	rarity: number,
	mutation: string?,
	gene: number?, -- the seed's hidden flower and size (Config.rollGene)
	ghost: number?, -- what its planting ghost shows (PlantGhosts.seedLook): the flower's n...
	scale: number?, -- ...at the size it has when planted
	shown: number?, -- the rarity its pod showed (2x Luck may have raised `rarity`); it goes back to the pod as that
	pod: number,
	model: Model?,
}

export type Session = {
	player: Player,
	profile: ProfileStore.Profile,
	canSave: boolean,
	plot: any?, -- WorldBuilder.PlotInfo
	tracker: SpeedLogic.State,
	carry: Carry?,
	stunnedUntil: number,
	knockedUntil: number, -- os.clock() until which a knockback flight is under way (SpeedService.knock)
	walkSpeed: number,
	income: number, -- cached $/s from plants, refreshed by PlotService
	passes: { [string]: boolean },
	cooldowns: { [string]: number },
	requests: { number },
	growNow: { [string]: number }, -- Grow Now product -> the plant id its last prompt was for (ProcessReceipt finishes that one)
}

local byPlayer: { [Player]: Session } = {}

function Sessions.create(player: Player, profile: ProfileStore.Profile, canSave: boolean): Session
	local s: Session = {
		player = player,
		profile = profile,
		canSave = canSave,
		plot = nil,
		tracker = SpeedLogic.newState(),
		carry = nil,
		stunnedUntil = 0,
		knockedUntil = 0,
		walkSpeed = Config.walkSpeedFor(profile.speed),
		income = 0,
		passes = {},
		cooldowns = {},
		requests = {},
		growNow = {},
	}
	byPlayer[player] = s
	return s
end

function Sessions.get(player: Player): Session?
	return byPlayer[player]
end

function Sessions.remove(player: Player)
	byPlayer[player] = nil
end

function Sessions.all(): { [Player]: Session }
	return byPlayer
end

-- What the Speed passes multiply every Speed gain by (2x Speed, VIP).
function Sessions.passSpeedMult(s: Session): number
	return Config.passSpeedMult(s.passes)
end

-- Speed gain multiplier: the equipped trail x the Speed passes.
function Sessions.speedMult(s: Session): number
	return Config.trailMult(s.profile.equippedTrail) * Sessions.passSpeedMult(s)
end

-- Speed per stud right now: the flat base x the trail x the Speed passes.
function Sessions.speedPerStud(s: Session): number
	return Config.speedPerStud(s.profile.equippedTrail, Sessions.passSpeedMult(s))
end

-- What a step (server tick) on their own treadmill pays right now: its tier's fixed value x the trail x the Speed passes.
function Sessions.treadmillPerStep(s: Session): number
	return Config.treadmillPerStep(s.profile.treadmillTier, s.profile.equippedTrail, Sessions.passSpeedMult(s))
end

-- Plant income multiplier besides day/night: plot level x the money passes (2x Money, VIP).
function Sessions.moneyMult(s: Session): number
	return Config.moneyMult(s.profile.plotLevel, s.passes)
end

-- How much faster their plants grow (Fast Grow), and the luck multiplier their steals roll with (2x Luck).
function Sessions.growMult(s: Session): number
	return Config.passGrowMult(s.passes)
end
function Sessions.luckMult(s: Session): number
	return Config.passLuckMult(s.passes)
end

function Sessions.maxSlots(s: Session): number
	return Config.plotSlots(s.profile.plotLevel) + (if s.passes.ExtraSlots then Config.PASS_EXTRA_SLOTS else 0)
end

-- Simple per-player request budget for remotes: at most `perSecond` calls in any 1 s window.
function Sessions.allowRequest(s: Session, perSecond: number): boolean
	local now = os.clock()
	local kept = {}
	for _, t in s.requests do
		if now - t < 1 then
			table.insert(kept, t)
		end
	end
	s.requests = kept
	if #kept >= perSecond then
		return false
	end
	table.insert(kept, now)
	return true
end

function Sessions.push(player: Player, partial: { [string]: any })
	Net.StatsUpdate:FireClient(player, partial)
end

local function carryView(s: Session): any
	local c = s.carry
	if not c then
		return false
	end
	return { zone = c.zone, rarity = c.rarity, mutation = c.mutation, ghost = c.ghost, scale = c.scale } -- (never the flower's name)
end

-- Money/speed/income change often; send just those (and mirror them to leaderstats).
function Sessions.pushCore(s: Session)
	local p = s.profile
	Sessions.push(s.player, {
		money = p.money,
		speed = p.speed,
		walkSpeed = s.walkSpeed,
		income = s.income * Sessions.moneyMult(s),
	})
	local ls = s.player:FindFirstChild("leaderstats")
	if ls then
		local speedValue = ls:FindFirstChild("Speed") :: StringValue?
		local moneyValue = ls:FindFirstChild("Money") :: StringValue?
		if speedValue then
			speedValue.Value = Format.short(p.speed)
		end
		if moneyValue then
			moneyValue.Value = Format.money(p.money)
		end
	end
end

function Sessions.pushFull(s: Session)
	local p = s.profile
	Sessions.push(s.player, {
		money = p.money,
		speed = p.speed,
		walkSpeed = s.walkSpeed,
		income = s.income * Sessions.moneyMult(s),
		slots = Sessions.maxSlots(s),
		plotLevel = p.plotLevel,
		trails = table.clone(p.trails),
		equippedTrail = p.equippedTrail,
		treadmillTier = p.treadmillTier,
		speedMult = Sessions.speedMult(s),
		items = table.clone(p.items),
		seedBag = table.clone(p.seedBag),
		index = table.clone(p.index),
		reachedEnd = p.reachedEnd,
		freeGift = p.freeGift, -- the Free Gift window's CLAIMED state
		passes = table.clone(s.passes),
		carrying = carryView(s),
		plot = if s.plot then s.plot.index else nil,
	})
end

function Sessions.pushCarry(s: Session)
	Sessions.push(s.player, { carrying = carryView(s) })
end

return Sessions
