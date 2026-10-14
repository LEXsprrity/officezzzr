-- The community rewards (TODO 6) on the Roblox side; the rules are in Rewards (pure).
--   * Free Gift: ClaimReward("Gift") from the window's CLAIM button. The server checks the community
--     (Player:IsInGroupAsync, then GroupService for a player who joined during this session), grants once per
--     account and toasts. The window opens by itself once, Config.FREE_GIFT_AUTO_OPEN s after joining, and
--     from the gift box placed here on the map's GiftSpot, where the free chest used to stand (GiftBox; its
--     prompt is handled on the client). There is no free chest any more (owner request).
--   * "MOST MONEY/s": every Config.MONEY_BOARD_INTERVAL s this server writes its players' income to an
--     OrderedDataStore and reads the top rows back. If the DataStore can't be used (Studio without API
--     access, outages) the board shows this server's players instead.
local DataStoreService = game:GetService("DataStoreService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local Rewards = require(script.Parent:WaitForChild("Rewards"))
local SpeedService = require(script.Parent:WaitForChild("SpeedService"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local GiftBox = require(script.Parent:WaitForChild("GiftBox"))

local RewardService = {}

local REQUESTS_PER_SECOND = 8
local GIFT_CLAIM_GAP = 2 -- seconds between two gift checks of one player

local members: Rewards.MemberCache = {}
local board: WorldBuilder.MoneyBoardLabels? = nil

----------------------------------------------------------------------------------------------------
-- Free Gift
----------------------------------------------------------------------------------------------------
-- Is the player in the community? Player:IsInGroupAsync (or the older, deprecated IsInGroup) can answer
-- from Roblox's cache for the session, so a "no" is checked again with GroupService:GetGroupsAsync (a web
-- call), which sees a group joined a minute ago. nil when both checks failed.
local function inCommunity(player: Player): boolean?
	local groupId = Config.COMMUNITY_GROUP_ID
	local ok, member = pcall(function()
		return (player :: any):IsInGroupAsync(groupId)
	end)
	if not ok then
		ok, member = pcall(player.IsInGroup, player, groupId)
	end
	if ok and member then
		return true
	end
	local okWeb, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if okWeb and type(groups) == "table" then
		for _, g in groups do
			if type(g) == "table" and g.Id == groupId then
				return true
			end
		end
		return false
	end
	return if ok then false else nil
end

local function claimGift(player: Player)
	local s = Sessions.get(player)
	if not s then
		return
	end
	local now = os.clock()
	if now < (s.cooldowns.Gift or 0) then
		return
	end
	s.cooldowns.Gift = math.huge -- one check at a time: it waits on Roblox's web API (Rewards.claimGift re-checks too)
	local ok, result = pcall(Rewards.claimGift, s.profile, Config.COMMUNITY_GROUP_ID, function()
		return Rewards.cachedMember(members, player.UserId, os.time(), function()
			return inCommunity(player)
		end)
	end)
	s.cooldowns.Gift = os.clock() + GIFT_CLAIM_GAP
	if not ok then
		warn("[RewardService] gift claim:", result)
		result = "error"
	end
	if not player.Parent then
		return
	end
	if result == "granted" then
		SpeedService.refresh(s)
		Sessions.pushFull(s)
	end
	local text, color = Rewards.giftMessage(result)
	Net.toast(player, text, color)
	Net.LootEvent:FireClient(player, "FreeGift", { result = result, claimed = s.profile.freeGift })
end

----------------------------------------------------------------------------------------------------
-- "MOST MONEY/s" board
----------------------------------------------------------------------------------------------------
local names: { [number]: string } = {}
local function nameOf(userId: number): string?
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.Name
	end
	if names[userId] == nil then
		local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		if ok and type(name) == "string" then
			names[userId] = name
		end
	end
	return names[userId]
end

local function incomeHere(): { Rewards.Row }
	local rows = {}
	for player, s in Sessions.all() do
		table.insert(rows, { userId = player.UserId, name = player.Name, income = s.income * Sessions.moneyMult(s) })
	end
	return rows
end

local function boardLoop()
	local labels = board
	if not labels then
		return
	end
	local okStore, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, Config.MONEY_BOARD_STORE)
	if not okStore then
		warn("[RewardService] the MOST MONEY/s board shows this server only (no DataStore):", store)
		store = nil
	end
	local written: { [number]: number } = {}
	local global: { Rewards.Row }? = nil
	local warned = false
	while true do
		local here = incomeHere()
		if store then
			for _, r in here do
				local value = Rewards.encodeIncome(r.income)
				if Rewards.shouldWrite(written[r.userId], value) then
					local ok = pcall(store.SetAsync, store, tostring(r.userId), value)
					if ok then
						written[r.userId] = value
					end
				end
			end
			local ok, page = pcall(function()
				return store:GetSortedAsync(false, Config.MONEY_BOARD_ROWS):GetCurrentPage()
			end)
			if ok then
				global = Rewards.parsePage(page)
			elseif not warned then
				warned = true
				warn("[RewardService] couldn't read the MOST MONEY/s board; showing the last list or this server:", page)
			end
		end
		local rows, source = Rewards.boardRows(global, here, Config.MONEY_BOARD_ROWS)
		local shown = {}
		for i, r in rows do
			r.name = r.name or nameOf(r.userId)
			shown[i] = Rewards.formatRow(i, r)
		end
		WorldBuilder.setMoneyBoard(labels, shown, Rewards.boardStatus(source, #rows))
		task.wait(Config.MONEY_BOARD_INTERVAL)
	end
end

----------------------------------------------------------------------------------------------------
-- `world`: the adopted map (Workspace.World).
function RewardService.init(world: Instance?)
	local giftSpot, labels = WorldBuilder.rewardPoints(world)
	board = labels
	Net.ClaimReward.OnServerEvent:Connect(function(player: Player, kind: any)
		local s = Sessions.get(player)
		if not s or not Sessions.allowRequest(s, REQUESTS_PER_SECOND) then
			return
		end
		if kind == "Gift" then
			claimGift(player)
		end
	end)
	if giftSpot then
		GiftBox.build(giftSpot)
	end
end

function RewardService.start()
	task.spawn(boardLoop)
end

-- A player's session is ready: the Free Gift window opens by itself once per account, a little later.
function RewardService.playerReady(s: Sessions.Session)
	task.delay(Config.FREE_GIFT_AUTO_OPEN, function()
		if s.player.Parent and Sessions.get(s.player) == s and Rewards.autoOpenGift(s.profile, Config.COMMUNITY_GROUP_ID) then
			Net.LootEvent:FireClient(s.player, "OpenFreeGift", {})
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	members[player.UserId] = nil
end)

return RewardService
