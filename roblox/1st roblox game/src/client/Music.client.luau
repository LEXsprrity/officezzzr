-- Background music (a player's suggestion, owner 2026-10-16). In the base: a shuffled day list, or a calmer
-- night list at night (Config.dayPhase, the same clock as the lighting). Out in the corridor the music fades
-- away and only the zone's nature sounds loop (owner: "when you go into the corridor the music should stop
-- and just be forest sounds"), Config.MUSIC_AMBIENCE by zone (Config.zoneAtX, like the zone banner).
-- The HUD's Music switch sets our MusicMuted attribute: everything fades out.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local rng = Random.new()

local current: Sound? = nil -- what plays now (fading in or at full volume)
local currentKey: string? = nil -- "day", "night", "zone:<k>" or nil (silence)
local order: { number } = {} -- the shuffled list being played
local nextIndex = 1

local function fadeOut(sound: Sound)
	local tween = TweenService:Create(sound, TweenInfo.new(Config.MUSIC_FADE), { Volume = 0 })
	tween.Completed:Connect(function()
		sound:Destroy()
	end)
	tween:Play()
end

local function start(id: number, volume: number, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.SoundId = "rbxassetid://" .. id
	sound.Looped = looped
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(Config.MUSIC_FADE), { Volume = volume }):Play()
	return sound
end

local function shuffled(list: { number }): { number }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = rng:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- The next track of the list; when the list runs out it is shuffled again.
local playNext: () -> ()
function playNext()
	if nextIndex > #order then
		order = shuffled(order)
		nextIndex = 1
	end
	local key = currentKey
	local sound = start(order[nextIndex], Config.MUSIC_VOLUME, false)
	nextIndex += 1
	current = sound
	sound.Ended:Connect(function()
		if current == sound and currentKey == key then
			sound:Destroy()
			playNext()
		end
	end)
end

local function switchTo(key: string?)
	if key == currentKey then
		return
	end
	currentKey = key
	if current then
		fadeOut(current)
		current = nil
	end
	if not key then
		return
	end
	local zone = tonumber(string.match(key, "^zone:(%d+)$"))
	if zone then
		local id = Config.MUSIC_AMBIENCE[zone]
		if id then
			current = start(id, Config.MUSIC_AMBIENCE_VOLUME, true)
		end
		return
	end
	order = shuffled(Config.MUSIC[key])
	nextIndex = 1
	playNext()
end

-- What should play right now.
local function wanted(): string?
	if player:GetAttribute("MusicMuted") then
		return nil
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local zone = root and Config.zoneAtX(root.Position.X)
	if zone then
		return "zone:" .. zone
	end
	local night = Config.dayPhase(workspace:GetServerTimeNow())
	return if night then "night" else "day"
end

while true do
	local ok, key = pcall(wanted)
	if ok then
		switchTo(key)
	end
	task.wait(0.5)
end
