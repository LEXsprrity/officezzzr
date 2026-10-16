-- Steal a Seed bootstrap: collision groups, world, services, player lifecycle and saving.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Server = script.Parent
local Net = require(Server:WaitForChild("Net"))
local Sessions = require(Server:WaitForChild("Sessions"))
local ProfileStore = require(Server:WaitForChild("ProfileStore"))
local SpeedLogic = require(Server:WaitForChild("SpeedLogic"))
local WorldBuilder = require(Server:WaitForChild("WorldBuilder"))
local SpeedService = require(Server:WaitForChild("SpeedService"))
local SeedService = require(Server:WaitForChild("SeedService"))
local GuardService = require(Server:WaitForChild("GuardService"))
local PlotService = require(Server:WaitForChild("PlotService"))
local ShopService = require(Server:WaitForChild("ShopService"))
local TrailService = require(Server:WaitForChild("TrailService"))
local VipService = require(Server:WaitForChild("VipService"))
local BatTool = require(Server:WaitForChild("BatTool"))
local AmbientService = require(Server:WaitForChild("AmbientService"))
local RewardService = require(Server:WaitForChild("RewardService"))
local PlantGhosts = require(Server:WaitForChild("PlantGhosts"))
local FlowerPreviews = require(Server:WaitForChild("FlowerPreviews"))
local AdminService = require(Server:WaitForChild("AdminService"))

-- Guards pass through players (the catch is a distance check) and each other.
PhysicsService:RegisterCollisionGroup("Guards")
PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:CollisionGroupSetCollidable("Guards", "Players", false)
PhysicsService:CollisionGroupSetCollidable("Guards", "Guards", false)
PhysicsService:CollisionGroupSetCollidable("Players", "Players", false) -- players walk through each other (owner 2026-10-16)
PhysicsService:RegisterCollisionGroup("Decor")
PhysicsService:CollisionGroupSetCollidable("Guards", "Decor", false) -- big props stop players, never the guards

local plotInfos, nestInfos = WorldBuilder.load()
require(Server:WaitForChild("SolidProps")).apply(workspace:FindFirstChild("World")) -- trees, volcanoes... stop players
PlotService.init(plotInfos, WorldBuilder.sellPoints(workspace:FindFirstChild("World")))
SeedService.init(nestInfos)
GuardService.init(nestInfos)
ShopService.init()
RewardService.init(workspace:FindFirstChild("World"))
AdminService.init()
SpeedService.start()
PlotService.start()
task.spawn(PlantGhosts.publish) -- the planting preview's 3D ghosts, for the clients
task.spawn(FlowerPreviews.publish) -- every flower's 3D picture, for the HUD's Index, Plants and Sell cards
AmbientService.start()
RewardService.start()

-- DataStore (unavailable in Studio unless "Enable Studio Access to API Services" is on)
local store: ProfileStore.Store? = nil
do
	local ok, ds = pcall(DataStoreService.GetDataStore, DataStoreService, Config.DATASTORE_NAME)
	if ok then
		store = ProfileStore.new(ds, nil, nil, game.JobId)
	else
		warn("[Main] DataStore unavailable, progress will not save:", ds)
	end
end

-- Returns whether the profile reached the DataStore (Robux receipts are only confirmed after that).
-- `release`: the session is over (the player left), so its session lock goes with this save (ProfileStore).
local function save(s: Sessions.Session, release: boolean?): boolean
	if not store or not s.canSave then
		return false
	end
	s.profile.lastSeen = os.time()
	local ok, why = store:save(s.player.UserId, s.profile, release)
	if why == "locked" then
		s.canSave = false -- another server has this profile now: this session never writes it again
	end
	return ok
end
ShopService.save = save
AdminService.save = save

----------------------------------------------------------------------------------------------------
-- Characters
----------------------------------------------------------------------------------------------------
local function onCharacter(player: Player, char: Model)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	char:WaitForChild("HumanoidRootPart")
	local s = Sessions.get(player)
	if s then
		s.tracker = SpeedLogic.newState()
		hum.WalkSpeed = s.walkSpeed
		TrailService.apply(char, s.profile.equippedTrail) -- a respawned character needs its trail again
		BatTool.give(player) -- 1 equips it, a click swings it (BatSwing.client)
		if s.passes.VIP or VipService.isOwner(player) then
			char:WaitForChild("Head", 5)
			VipService.dress(char, s.passes.VIP == true, VipService.isOwner(player)) -- ...and its VIP (or OWNER) tag
		end
		if s.plot then
			task.defer(SpeedService.teleport, player, s.plot.spawnCFrame + Vector3.new(0, 3, 0))
		end
	end
	hum.Died:Connect(function()
		SeedService.returnCarry(player)
	end)
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, name in { "Speed", "Money" } do
		local v = Instance.new("StringValue")
		v.Name = name
		v.Value = "0"
		v.Parent = leaderstats
	end
	leaderstats.Parent = player

	local profile, canSave
	if store then
		profile, canSave = store:load(player.UserId)
	else
		profile, canSave = ProfileStore.defaultProfile(), false
	end
	if not player.Parent then
		if store and canSave then
			store:save(player.UserId, profile, true) -- left while loading: let the profile go for their next server
		end
		return
	end

	local s = Sessions.create(player, profile, canSave)
	ShopService.checkPasses(s)
	if not player.Parent or Sessions.get(player) ~= s then
		return -- left while the passes were checked (onPlayerRemoving saved; a plot now would never be freed)
	end
	if not PlotService.assign(s) then
		Sessions.remove(player)
		player:Kick("This server is full (8 plots). Please join another server.")
		save(s, true)
		return
	end
	PlotService.grantOffline(s)
	Sessions.pushFull(s)
	Sessions.pushCore(s)
	RewardService.playerReady(s)
	task.spawn(AdminService.playerReady, s) -- the admin panel, and grants the owner sent while they were away
	if not canSave then
		Net.toast(player, if store then "⚠️ Couldn't load your save; progress this session won't be saved." else "⚠️ Saving is off (no DataStore access).", "red")
	end

	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	player.CharacterRemoving:Connect(function()
		SeedService.returnCarry(player)
	end)
end

local function onPlayerRemoving(player: Player)
	local s = Sessions.get(player)
	if not s then
		return
	end
	SeedService.returnCarry(player)
	PlotService.release(player)
	save(s, true)
	Sessions.remove(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Autosave
task.spawn(function()
	while true do
		task.wait(Config.AUTOSAVE_INTERVAL)
		for _, s in Sessions.all() do
			task.spawn(save, s)
		end
	end
end)

game:BindToClose(function()
	if RunService:IsStudio() and not store then
		return
	end
	local pending = 0
	for _, s in Sessions.all() do
		pending += 1
		task.spawn(function()
			save(s, true)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)
