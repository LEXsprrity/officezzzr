--!strict
-- UI icons: the PNGs in icons/ ("Free Icon Pack" by @gvesster), uploaded to Roblox as images. Their asset
-- ids live in icons/ids.json (Config.ICONS). Every icon stands in for an emoji (or "R$") in some text:
-- while its id is 0 the text is shown exactly as before, emoji and all, so nothing changes until the
-- icons are uploaded. Used by the HUD and by the world signs (server).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Icons = {}

-- What each icon replaces in text. Callers name the icon(s) a label may show, so a token can belong to
-- several icons ("🏃" is the Trail Shop on the Speed panel and the treadmill on its sign).
Icons.TOKENS = {
	Shop = { "🛒" },
	Index = { "📖" },
	TrailShop = { "🏃" },
	Speed = { "⚡" },
	Money = { "💰" },
	Robux = { "R$" },
	Gift = { "🎁" },
	SeedPack = { "💎" },
	PlotUpgrade = { "⬆️", "🏡" },
	Seeds = { "🌱" },
	Plants = { "🪴" },
	Bat = { "🏏" },
	Lock = { "🔒" },
	Close = { "✖" },
	Star = { "✨", "🌟" },
	DoubleMoney = { "💎" },
	ExtraSlots = { "💎" },
	Bag = { "🎒" },
	Leaderboard = { "⚡" }, -- leaderboard titles
	Treadmill = { "🏃" },
	Home = { "🏠" },
} :: { [string]: { string } }

-- "rbxassetid://<id>" for an uploaded icon, or nil while its id is 0 (not uploaded yet) or unknown.
function Icons.image(key: string): string?
	local id = Config.ICONS[key]
	if type(id) == "number" and id > 0 and id == math.floor(id) then
		return string.format("rbxassetid://%d", id)
	end
	return nil
end

export type Piece = { text: string?, key: string?, image: string? }

-- Splits `text` into text and icon pieces for the given icon key(s): every token of an icon that has an
-- image becomes an icon piece. With one key (a string) whose token isn't in the text, the icon goes in
-- front ("-- SEED PACKS --", "$1.2K"). Returns nil when no icon applies (show `text` as it is), and
-- whether the icon sits above the text (the text puts a line break right after the leading token, like
-- the hotbar's "🏏\nBat").
function Icons.parse(keys: string | { string }, text: string): ({ Piece }?, boolean)
	local list: { string } = if type(keys) == "string" then { keys } else keys
	local tokens: { { token: string, key: string, image: string } } = {}
	for _, key in list do
		local image = Icons.image(key)
		if image then
			for _, token in Icons.TOKENS[key] or {} :: { string } do
				table.insert(tokens, { token = token, key = key, image = image })
			end
		end
	end
	if #tokens == 0 then
		return nil, false
	end

	local pieces: { Piece } = {}
	local vertical = false
	local function addText(s: string)
		s = string.match(s, "^%s*(.-)%s*$") :: string
		if s ~= "" then
			table.insert(pieces, { text = s })
		end
	end
	local at = 1
	while true do
		local best: number?, bestEnd: number?, bestToken = nil, nil, nil
		for _, t in tokens do
			local s, e = string.find(text, t.token, at, true)
			if s and (best == nil or s < best) then
				best, bestEnd, bestToken = s, e, t
			end
		end
		if not best or not bestEnd or not bestToken then
			break
		end
		addText(string.sub(text, at, best - 1))
		if #pieces == 0 and string.sub(text, bestEnd + 1, bestEnd + 1) == "\n" then
			vertical = true
		end
		table.insert(pieces, { key = bestToken.key, image = bestToken.image })
		at = bestEnd + 1
	end
	addText(string.sub(text, at))

	local found = false
	for _, p in pieces do
		found = found or p.image ~= nil
	end
	if not found then
		if type(keys) ~= "string" then
			return nil, false
		end
		table.insert(pieces, 1, { key = keys, image = tokens[1].image })
	end
	return pieces, vertical
end

-- Text next to an inline icon hugs it ("Buy ·" [R$] "2,000"); text after a leading icon keeps the label's
-- alignment ([Shop] "Shop").
local function alignmentFor(label: TextLabel, iconBefore: boolean, iconAfter: boolean, inline: boolean): Enum.TextXAlignment
	if iconBefore and iconAfter then
		return Enum.TextXAlignment.Center
	elseif iconAfter then
		return Enum.TextXAlignment.Right
	elseif inline then
		return Enum.TextXAlignment.Left
	elseif label.TextXAlignment == Enum.TextXAlignment.Right then
		return Enum.TextXAlignment.Left -- hug the icon
	end
	return label.TextXAlignment
end

-- Shows `text` on `label` with the icon(s) `keys` in place of their emoji. With no uploaded icon this is
-- just `label.Text = text`. With one, the label's own text is emptied and an "IconRow" inside it lays out
-- square icons (ScaleType Fit, `size` (default 1) x the label's height, or x 60% of it when the icon sits
-- above the text) and the text between them, styled like the label. The text pieces share the room the
-- icons leave; with `textSize` (pixels) they take their natural width instead, so a wide centred label
-- (a section title) keeps icon and text together. Always write the label through this function afterwards.
function Icons.set(label: TextLabel, keys: string | { string }, text: string, size: number?, textSize: number?)
	local pieces, vertical = Icons.parse(keys, text)
	local row = label:FindFirstChild("IconRow")
	if not pieces then
		if row then
			row:Destroy()
		end
		label:SetAttribute("IconText", nil)
		label.Text = text
		return
	end
	local signature = table.concat({ text, if type(keys) == "string" then keys else table.concat(keys, ","), tostring(size), tostring(textSize) }, "|")
	if row and label:GetAttribute("IconText") == signature then
		return -- unchanged (the HUD rewrites some labels on every stats tick)
	end
	if row then
		row:Destroy()
	end
	label:SetAttribute("IconText", signature)
	label.Text = ""

	local newRow = Instance.new("Frame")
	newRow.Name = "IconRow"
	newRow.BackgroundTransparency = 1
	newRow.Size = UDim2.fromScale(1, 1)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = if label.TextXAlignment == Enum.TextXAlignment.Left then Enum.HorizontalAlignment.Left
		elseif label.TextXAlignment == Enum.TextXAlignment.Right then Enum.HorizontalAlignment.Right
		else Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = if vertical then UDim.new(0, 0) else UDim.new(0.015, 0)
	layout.Parent = newRow

	local iconSize = (size or 1) * (if vertical then 0.6 else 1)
	for i, piece in pieces :: { Piece } do
		if piece.image then
			local icon = Instance.new("ImageLabel")
			icon.Name = "Icon_" .. (piece.key :: string)
			icon.BackgroundTransparency = 1
			icon.Image = piece.image
			icon.ScaleType = Enum.ScaleType.Fit
			icon.SizeConstraint = Enum.SizeConstraint.RelativeYY -- square, from the label's height
			icon.Size = UDim2.fromScale(iconSize, iconSize)
			icon.LayoutOrder = i
			icon.Parent = newRow
			continue
		end
		local prev, nextPiece = pieces[i - 1], pieces[i + 1]
		local part = Instance.new("TextLabel")
		part.Name = "Text" .. i
		part.BackgroundTransparency = 1
		part.Text = piece.text :: string
		part.FontFace = label.FontFace
		part.TextColor3 = label.TextColor3
		part.TextScaled = label.TextScaled and textSize == nil
		part.TextSize = textSize or label.TextSize
		part.TextWrapped = label.TextWrapped
		part.TextTransparency = label.TextTransparency
		part.TextStrokeTransparency = label.TextStrokeTransparency
		part.TextStrokeColor3 = label.TextStrokeColor3
		part.TextXAlignment = if vertical then Enum.TextXAlignment.Center
			else alignmentFor(label, prev ~= nil and prev.image ~= nil, nextPiece ~= nil and nextPiece.image ~= nil, i > 2)
		part.LayoutOrder = i
		part.Size = if vertical then UDim2.fromScale(1, 0) else UDim2.fromScale(0, 1)
		if textSize and not vertical then
			part.AutomaticSize = Enum.AutomaticSize.X
		else
			-- Share what the icons leave by length, so the pieces scale to about the same text size.
			local flex = Instance.new("UIFlexItem")
			flex.FlexMode = Enum.UIFlexMode.Custom
			flex.GrowRatio = math.max(1, utf8.len(piece.text :: string) or #(piece.text :: string))
			flex.ShrinkRatio = 0
			flex.Parent = part
		end
		for _, child in label:GetChildren() do
			if child:IsA("UIStroke") or child:IsA("UITextSizeConstraint") then
				(child :: Instance):Clone().Parent = part
			end
		end
		part.Parent = newRow
	end
	newRow.Parent = label
end

return Icons
