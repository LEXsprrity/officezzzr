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
	walkSpeed: number,
	income: number, -- cached $/s from plants, refreshed by PlotService
	passes: { [string]: boolean },
	cooldowns: { [string]: number },
	requests: { number },
	featuredPrompt: { slot: number, at: number }?, -- last featured-pack Robux prompt (SeedPacks.receiptSlot)
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
		walkSpeed = Config.walkSpeedFor(profile.speed),
		income = 0,
		passes = {},
		cooldowns = {},
		requests = {},
		featuredPrompt = nil,
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

function Sessions.speedMult(s: Session): number
	return Config.SPEED_MULT_TIERS[s.profile.speedMultTier].mult
end

function Sessions.treadmillMult(s: Session): number
	return Config.TREADMILL_TIERS[s.profile.treadmillTier].mult
end

function Sessions.moneyMult(s: Session): number
	return if s.passes.DoubleMoney then 2 else 1
end

function Sessions.maxSlots(s: Session): number
	return s.profile.slots + (if s.passes.ExtraSlots then Config.PASS_EXTRA_SLOTS else 0)
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
	return { zone = c.zone, rarity = c.rarity, mutation = c.mutation }
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
		baseSlots = p.slots,
		speedMultTier = p.speedMultTier,
		treadmillTier = p.treadmillTier,
		speedMult = Sessions.speedMult(s),
		treadmillMult = Sessions.treadmillMult(s),
		items = table.clone(p.items),
		seedBag = table.clone(p.seedBag),
		index = table.clone(p.index),
		reachedEnd = p.reachedEnd,
		passes = table.clone(s.passes),
		carrying = carryView(s),
		plot = if s.plot then s.plot.index else nil,
	})
end

function Sessions.pushCarry(s: Session)
	Sessions.push(s.player, { carrying = carryView(s) })
end

return Sessions
