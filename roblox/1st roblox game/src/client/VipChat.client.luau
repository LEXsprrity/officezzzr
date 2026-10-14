-- The VIP gamepass's chat tag: a gold, bold [VIP] in front of the name of every player whose VIP attribute the
-- server set (Server/VipService, from the server's own pass check; the client never decides it). Its own
-- script: TextChatService has one OnIncomingMessage callback per client, and the HUD is near the locals limit.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local TAG = `<font color="#FFCE28"><b>[VIP]</b></font> `

TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
	local source = message.TextSource
	local player = source and Players:GetPlayerByUserId(source.UserId)
	if not player or player:GetAttribute("VIP") ~= true then
		return nil
	end
	local props = Instance.new("TextChatMessageProperties")
	props.PrefixText = TAG .. message.PrefixText
	return props
end
