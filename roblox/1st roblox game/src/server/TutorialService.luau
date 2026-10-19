-- The first-time tutorial's one server piece: its `tutorialDone` flag (ProfileStore). Client/Tutorial draws the
-- steps and fires the Tutorial remote with "done" (the last step) or "skip" (the Skip button); either sets the
-- flag for good, so the tutorial never shows again (the next autosave or leaving saves it). Nothing else
-- trusts the client here: the flag only hides a tutorial.
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))

local TutorialService = {}

TutorialService.KINDS = { done = true, skip = true }

-- Marks the tutorial over for this session's profile. Returns whether the flag changed.
function TutorialService.finish(s: Sessions.Session, kind: any): boolean
	if not TutorialService.KINDS[kind] or s.profile.tutorialDone then
		return false
	end
	s.profile.tutorialDone = true
	Sessions.push(s.player, { tutorialDone = true })
	return true
end

function TutorialService.init()
	Net.Tutorial.OnServerEvent:Connect(function(player: Player, kind: any)
		local s = Sessions.get(player)
		if s and Sessions.allowRequest(s, 4) then
			TutorialService.finish(s, kind)
		end
	end)
end

return TutorialService
