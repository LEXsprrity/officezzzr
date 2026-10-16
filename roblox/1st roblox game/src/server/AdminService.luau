-- The owner's admin panel, server side (owner 2026-10-16: "make a admin panel", to pay players back for
-- bug reports). Admins are Config.ADMIN_USER_IDS, anyone at Config.ADMIN_MIN_RANK or above in the community,
-- and everyone in Studio. They get the player attribute IsAdmin, which shows the panel (AdminPanel.client).
--   client -> server: Admin(target name, grant) (AdminGrant: Money, Speed or Seed); non-admins are ignored
--   server -> client: LootEvent "AdminResult" { text, ok } to the admin
-- A player in this server gets the grant at once (and a gold toast). Anyone else, by username, gets it the
-- next time they join any server: it waits in the Config.ADMIN_GRANTS_STORE DataStore under their user id.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AdminGrant = require(Shared:WaitForChild("AdminGrant"))
local Server = script.Parent
local Net = require(Server:WaitForChild("Net"))
local Sessions = require(Server:WaitForChild("Sessions"))
local SpeedService = require(Server:WaitForChild("SpeedService"))

local AdminService = {}

-- Main sets this to its save(s): a grant is saved right away.
AdminService.save = function(_s: Sessions.Session): boolean
	return false
end

local admins: { [Player]: boolean } = {}
local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end

local pending: DataStore? = nil
do
	local ok, ds = pcall(DataStoreService.GetDataStore, DataStoreService, Config.ADMIN_GRANTS_STORE)
	if ok then
		pending = ds
	end
end

local function keyFor(userId: number): string
	return "u" .. userId
end

function AdminService.isAdmin(player: Player): boolean
	if RunService:IsStudio() or table.find(Config.ADMIN_USER_IDS, player.UserId) then
		return true
	end
	local ok, rank = pcall(player.GetRankInGroup, player, Config.COMMUNITY_GROUP_ID)
	return ok and type(rank) == "number" and rank >= Config.ADMIN_MIN_RANK
end

local function reply(admin: Player, text: string, ok: boolean)
	Net.LootEvent:FireClient(admin, "AdminResult", { text = text, ok = ok })
end

-- Gives a grant to someone in this server, saves it and tells them.
local function giveNow(s: Sessions.Session, g: AdminGrant.Grant): number
	local given = AdminGrant.apply(s.profile, g, roll)
	if g.kind == "Speed" then
		SpeedService.refresh(s)
	end
	Sessions.pushFull(s)
	Sessions.pushCore(s)
	task.spawn(AdminService.save, s)
	local shown = if g.kind == "Seed" then AdminGrant.describe({ kind = "Seed", zone = g.zone, rarity = g.rarity, count = given }) else AdminGrant.describe(g)
	Net.toast(s.player, `You got {shown} from the dev! Thanks for the help`, "gold", "Gift")
	return given
end

-- Someone in this server by username or display name: exact first, then a unique start of one.
local function findHere(name: string): Player?
	local lower = string.lower(name)
	local starts: { Player } = {}
	for _, p in Players:GetPlayers() do
		local user, display = string.lower(p.Name), string.lower(p.DisplayName)
		if user == lower or display == lower then
			return p
		end
		if string.sub(user, 1, #lower) == lower or string.sub(display, 1, #lower) == lower then
			table.insert(starts, p)
		end
	end
	return if #starts == 1 then starts[1] else nil
end

local function queue(userId: number, g: AdminGrant.Grant): (boolean, string?)
	local store = pending
	if not store then
		return false, "no DataStore here"
	end
	local full = false
	local ok, err = pcall(store.UpdateAsync, store, keyFor(userId), function(old: any)
		local list = if type(old) == "table" then old else {}
		if #list >= Config.ADMIN_PENDING_MAX then
			full = true
			return nil
		end
		table.insert(list, g)
		return list
	end)
	if full then
		return false, "they already have too many waiting"
	end
	return ok, if ok then nil else tostring(err)
end

local function onAdmin(admin: Player, target: any, raw: any)
	if not admins[admin] then
		return
	end
	local s = Sessions.get(admin)
	if s and not Sessions.allowRequest(s, 4) then
		return
	end
	local g, why = AdminGrant.check(raw)
	if not g then
		reply(admin, `Not sent: {why}`, false)
		return
	end
	if type(target) ~= "string" or #target < 1 or #target > 40 then
		reply(admin, "Type a player's name", false)
		return
	end
	local here = findHere(target)
	local ts = here and Sessions.get(here)
	if here and ts then
		giveNow(ts, g)
		reply(admin, `Gave {AdminGrant.describe(g)} to {here.Name}`, true)
		print(`[Admin] {admin.Name} gave {AdminGrant.describe(g)} to {here.Name}`)
		return
	end
	local okId, userId = pcall(Players.GetUserIdFromNameAsync, Players, target)
	if not okId or type(userId) ~= "number" then
		reply(admin, `No player called "{target}"`, false)
		return
	end
	local queued, err = queue(userId, g)
	if queued then
		reply(admin, `{target} isn't here: they get {AdminGrant.describe(g)} next time they join`, true)
		print(`[Admin] {admin.Name} queued {AdminGrant.describe(g)} for {target} ({userId})`)
	else
		reply(admin, `Couldn't send it ({err})`, false)
	end
end

-- On join (once the save is loaded): marks admins and hands over any grants waiting for this player.
function AdminService.playerReady(s: Sessions.Session)
	local player = s.player
	if AdminService.isAdmin(player) and player.Parent then
		admins[player] = true
		player:SetAttribute("IsAdmin", true)
	end
	local store = pending
	if not store or not s.canSave then
		return -- a save that can't be written would lose them: they stay waiting
	end
	local ok, list = pcall(store.RemoveAsync, store, keyFor(player.UserId))
	if not ok then
		warn("[AdminService] pending grants:", list)
		return
	end
	if type(list) ~= "table" then
		return
	end
	local here = player.Parent ~= nil and Sessions.get(player) == s
	for _, raw in list do
		local g = AdminGrant.check(raw)
		if g and here then
			giveNow(s, g)
		elseif g then
			queue(player.UserId, g) -- left while we fetched them: keep them for next time
		end
	end
end

function AdminService.init()
	Net.Admin.OnServerEvent:Connect(onAdmin)
	Players.PlayerRemoving:Connect(function(p)
		admins[p] = nil
	end)
end

return AdminService
