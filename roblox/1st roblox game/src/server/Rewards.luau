--!strict
-- Pure: the community rewards' rules (TODO 6). The Free Gift (Speed for members of the owner's community,
-- once per account) and the "MOST MONEY/s" board (encoding for the OrderedDataStore, merging,
-- formatting). RewardService does the Roblox side around it (group checks, the DataStore, the board's
-- labels). (The free chest is gone: owner request, the FREE GIFT box stands where it was.)
--
-- Why only the group counts: likes can't be checked in game, and Roblox's Community Rules don't allow
-- prizes in exchange for something (a like or a favourite). The window asks for a like and a favourite
-- as a favour; the reward needs the one thing that can be checked and that games commonly reward,
-- membership of the game's community (group).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))

local Rewards = {}

type Profile = {
	speed: number,
	money: number,
	freeGift: boolean,
	giftShown: boolean,
}

----------------------------------------------------------------------------------------------------
-- Free Gift
----------------------------------------------------------------------------------------------------
-- A usable community id: a positive whole number (0 = not set up yet).
function Rewards.groupReady(groupId: any): boolean
	return type(groupId) == "number" and groupId > 0 and groupId == math.floor(groupId)
end

export type GiftResult = "granted" | "soon" | "claimed" | "notMember" | "error"

-- Claims the Free Gift. `isMember()` checks the community (true / false, or nil when the check failed)
-- and is only called when it matters. Grants Config.FREE_GIFT_SPEED once per profile.
function Rewards.claimGift(p: Profile, groupId: number, isMember: () -> boolean?): GiftResult
	if not Rewards.groupReady(groupId) then
		return "soon"
	end
	if p.freeGift then
		return "claimed"
	end
	local member = isMember()
	if member == nil then
		return "error"
	end
	if not member then
		return "notMember"
	end
	p.freeGift = true
	p.speed += Config.FREE_GIFT_SPEED
	return "granted"
end

-- What the player is told after a claim.
function Rewards.giftMessage(result: GiftResult): (string, string)
	if result == "granted" then
		return `🎁 +{Format.commas(Config.FREE_GIFT_SPEED)} Speed! Thanks for joining the community!`, "gold"
	elseif result == "soon" then
		return "🎁 The Free Gift is coming soon!", "blue"
	elseif result == "claimed" then
		return "🎁 You already claimed the Free Gift.", "blue"
	elseif result == "notMember" then
		return `Join the {Config.COMMUNITY_NAME} community on the game page first, then press CLAIM! (Just joined? Give it a minute.)`, "red"
	end
	return "Couldn't check the community right now. Try again in a moment.", "red"
end

-- Whether the window should open by itself now (once per account, only while there is something to
-- claim). Marks it shown.
function Rewards.autoOpenGift(p: Profile, groupId: number): boolean
	if p.giftShown or p.freeGift or not Rewards.groupReady(groupId) then
		return false
	end
	p.giftShown = true
	return true
end

-- Community membership with a cache: a "yes" is kept for the session (the reward is once anyway), a "no"
-- for NEGATIVE_CACHE seconds (so a player who just joined can claim soon after, but repeated clicks don't
-- hammer the web API). A failed check (nil) isn't cached.
Rewards.NEGATIVE_CACHE = 10
export type MemberCache = { [number]: { member: boolean, at: number } }
function Rewards.cachedMember(cache: MemberCache, userId: number, now: number, check: () -> boolean?): boolean?
	local hit = cache[userId]
	if hit and (hit.member or now - hit.at < Rewards.NEGATIVE_CACHE) then
		return hit.member
	end
	local member = check()
	if member ~= nil then
		cache[userId] = { member = member, at = now }
	end
	return member
end

----------------------------------------------------------------------------------------------------
-- "MOST MONEY/s" board
----------------------------------------------------------------------------------------------------
-- OrderedDataStore values are whole numbers up to 2^63, and income spans $0 to past $1Qa/s, so the board
-- stores log10(1 + income) in fixed point: the order is the same and the value reads back to about
-- 6 significant digits.
Rewards.ENCODE_SCALE = 1e7
function Rewards.encodeIncome(income: number): number
	if type(income) ~= "number" or income ~= income or income <= 0 then
		return 0
	end
	return math.floor(math.log10(1 + math.min(income, 1e300)) * Rewards.ENCODE_SCALE + 0.5)
end

function Rewards.decodeIncome(value: any): number
	if type(value) ~= "number" or value ~= value or value <= 0 then
		return 0
	end
	return 10 ^ (value / Rewards.ENCODE_SCALE) - 1
end

-- Whether a server should write this player's value: it changed, and it isn't a first 0 (players who
-- never earned don't fill the store; one who drops to 0 is written once).
function Rewards.shouldWrite(lastWritten: number?, encoded: number): boolean
	return encoded ~= lastWritten and (encoded > 0 or (lastWritten or 0) > 0)
end

export type Row = { userId: number, name: string?, income: number }

-- The entries of one GetSortedAsync page ({ key = "<userId>", value = <encoded> }) as rows. Bad entries
-- are skipped.
function Rewards.parsePage(entries: any): { Row }
	local out: { Row } = {}
	if type(entries) ~= "table" then
		return out
	end
	for _, e in entries do
		local userId: number? = if type(e) == "table" then tonumber(e.key) else nil
		if userId and userId > 0 and type(e.value) == "number" then
			table.insert(out, { userId = userId, income = Rewards.decodeIncome(e.value) })
		end
	end
	return out
end

-- The board's rows: the global top (`global`, nil while the DataStore can't be read) merged with this
-- server's players (`here`, live: they replace their own stored value), best income first (ties: lower
-- user id), at most `size`, nobody twice. Without a global list it is this server's players only.
-- Returns the rows and where they come from: "global" or "server".
function Rewards.boardRows(global: { Row }?, here: { Row }, size: number): ({ Row }, string)
	local byUser: { [number]: Row } = {}
	if global then
		for _, r in global do
			if not byUser[r.userId] then
				byUser[r.userId] = r
			end
		end
	end
	for _, r in here do
		byUser[r.userId] = r
	end
	local rows: { Row } = {}
	for _, r in byUser do
		if r.income > 0 or global == nil then
			table.insert(rows, r)
		end
	end
	table.sort(rows, function(a, b)
		if a.income ~= b.income then
			return a.income > b.income
		end
		return a.userId < b.userId
	end)
	while #rows > size do
		table.remove(rows)
	end
	return rows, if global then "global" else "server"
end

Rewards.NAME_MAX = 14
-- A row as the board shows it: "1", the name (cut to NAME_MAX characters with "..") and "$54.8T".
function Rewards.formatRow(rank: number, row: Row): { rank: string, name: string, value: string }
	local name = row.name or "Player"
	if #name > Rewards.NAME_MAX then
		name = string.sub(name, 1, Rewards.NAME_MAX - 2) .. ".."
	end
	return { rank = tostring(rank), name = name, value = Format.money(row.income) }
end

-- The line under the list.
function Rewards.boardStatus(source: string, count: number): string
	if count == 0 then
		return "No one is earning yet!"
	end
	return if source == "global" then "All servers · updates every minute" else "This server · updates every minute"
end

return Rewards
