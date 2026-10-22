--!strict
-- The Shop window's geometry (pure, so the tests can check it; owner playtest 2026-10-15, round 2):
--   * the windows' sizes: the Shop is wide (1120 design px; modalScale still shrinks it to fit a phone),
--     the Trail Shop, Index and Sell keep 860;
--   * the card sizes for that width (packs and banners span it, passes two a row, Speed / Money /
--     upgrades three a row);
--   * the buy-button rows, like the reference: square buttons sized to their content (a square gift
--     button, then the R$ button with the Robux icon and the price), a small caption under each buy
--     button, sitting straight on the card art (no full-width tray), centred in their span;
--   * how much each button may pop on hover (UiFx PopScale): never so much that it grows past its
--     card's edge (the card clips it) or into its neighbour.
local ShopLayout = {}

ShopLayout.HOVER = 1.1 -- UiFx.HOVER: what a button pops to when nothing limits it

-- The window (HUD modal): design pixels.
ShopLayout.PAD = 14 -- the body's inset from the window's edges
ShopLayout.SCROLLBAR = 14
ShopLayout.TITLE_H = 40 -- the title floats over the window's top edge (Steal an Egg's look)
local WINDOWS = {
	Shop = { w = 1120, h = 640 },
	Index = { w = 860, h = 560 }, -- one zone a page (Steal an Egg's look)
	Candy = { w = 1120, h = 580 }, -- the Haunted seed's card (as wide as a pack's) and a line
}
ShopLayout.DEFAULT_W, ShopLayout.DEFAULT_H = 860, 600
ShopLayout.MAX_W, ShopLayout.MAX_H = 1120, 640 -- the biggest window (the studs and stripes cover it)

function ShopLayout.window(name: string?): (number, number)
	local w = name and WINDOWS[name]
	if w then
		return w.w, w.h
	end
	return ShopLayout.DEFAULT_W, ShopLayout.DEFAULT_H
end

-- The Shop's section tabs (Featured / Speed / Money, HUD; owner 2026-10-15): a column of big icons with
-- their words, part of the window (they scale and move with it). They hang just outside its right edge,
-- from its top, when the screen has room there; otherwise (a narrow phone) they're tucked inside: the
-- window grows TAB_W wider on its right (the body keeps its width, so the cards never sit under them) and
-- they stand in that margin under the title bar. Design pixels.
ShopLayout.TAB_W = 96 -- the column's width (a tab's word fits)
ShopLayout.TAB_ICON, ShopLayout.TAB_WORD, ShopLayout.TAB_PAD = 66, 24, 4 -- a tab: its icon, its word under it, the gap to the next
ShopLayout.TAB_H = 3 * (ShopLayout.TAB_ICON + ShopLayout.TAB_WORD) + 2 * ShopLayout.TAB_PAD
ShopLayout.TAB_GAP = 8 -- outside: from the window's right edge
ShopLayout.TAB_TOP = 6 -- outside: down from the window's top
ShopLayout.TAB_ACTIVE = 1.2 -- the active tab's icon grows to this

-- Fits window `name` on a screen `screenW` wide with `availH` free between Roblox's top bar and the
-- hotbar (design pixels, after the HUD's UIScale): its width (the Shop's grows when its tabs are tucked
-- inside), height, scale (never above design size, never below 0.3) and where the tabs go: "outside",
-- "inside", or nil for the windows without tabs. The window is centred, so "outside" needs the tabs'
-- room on both sides.
function ShopLayout.fit(name: string?, screenW: number, availH: number): (number, number, number, ("outside" | "inside")?)
	local w, h = ShopLayout.window(name)
	local function scaleFor(width: number): number
		return math.clamp(math.min((screenW - 24) / (width + 12), (availH - 12) / (h + 12)), 0.3, 1)
	end
	if name ~= "Shop" then
		return w, h, scaleFor(w), nil
	end
	local s = scaleFor(w)
	if (w + 2 * (ShopLayout.TAB_GAP + ShopLayout.TAB_W)) * s <= screenW - 16 then
		return w, h, s, "outside"
	end
	local wide = w + ShopLayout.TAB_W
	return wide, h, scaleFor(wide), "inside"
end

-- The tabs, top to bottom, and the Shop sections they scroll to (its "Section_FEATURED" title rows).
ShopLayout.TAB_SECTIONS = { "Featured", "Speed", "Money" }
ShopLayout.LIT_LINE = 0.4 -- a section's tab lights once its title has come up past this much of the body

-- Which tab is lit with the sections' titles at `tops` (on screen; a missing one isn't laid out yet) in a
-- body at `bodyTop`, `bodyH` tall: the last section whose title is at or above LIT_LINE of the body (the
-- PASSES between FEATURED and SPEED keep FEATURED lit, the UPGRADES after MONEY keep MONEY), the first
-- while none is; nil when no title is laid out (nothing to go by).
function ShopLayout.litTab(tops: { [string]: number }, bodyTop: number, bodyH: number): string?
	local line = bodyTop + bodyH * ShopLayout.LIT_LINE
	local lit: string? = nil
	local measured = false
	for _, name in ShopLayout.TAB_SECTIONS do
		local top = tops[name]
		if top then
			measured = true
			if top <= line then
				lit = name
			end
		end
	end
	if not measured then
		return nil
	end
	return lit or ShopLayout.TAB_SECTIONS[1]
end

-- The width a full-width row of the body spans ("1, -8" inside the body's 4 px padding, beside the scrollbar).
function ShopLayout.contentWidth(windowW: number): number
	return windowW - 2 * ShopLayout.PAD - ShopLayout.SCROLLBAR - 8 - 8
end

ShopLayout.GAP = 14 -- between cards in a grid
ShopLayout.CONTENT_W = ShopLayout.contentWidth(WINDOWS.Shop.w)
-- `n` cards a row across the Shop
function ShopLayout.cardWidth(n: number): number
	return math.floor((ShopLayout.CONTENT_W - (n - 1) * ShopLayout.GAP) / n)
end
ShopLayout.CARD_W, ShopLayout.CARD_H = ShopLayout.cardWidth(3), 300 -- Speed / Money / upgrades
ShopLayout.WIDE_W, ShopLayout.WIDE_H = ShopLayout.cardWidth(2), 214 -- passes
ShopLayout.PACK_H = 404 -- a seed pack (spans the Shop)
ShopLayout.BANNER_H = 132 -- "DOUBLE Your SPEED" (spans the Shop)
ShopLayout.CARD_STROKE = 3 -- the cards' thin bright outline (outside the card: its clip is the card's rect)

-- Buttons
ShopLayout.BUTTON_H = 52
ShopLayout.GIFT_W = 52 -- square
ShopLayout.BUTTON_STROKE = 3 -- the buttons' dark outline, drawn outside them (it pops with them)
ShopLayout.PAIR_GAP = 14 -- gift -> its buy button
ShopLayout.GROUP_GAP = 22 -- one pair -> the next button
ShopLayout.CAPTION_H = 20
ShopLayout.MARGIN = 12 -- from the card's edges
ShopLayout.MIN_BUY_W = 112

export type Button = { kind: "gift" | "buy", text: string?, icon: boolean?, caption: string?, minW: number? }
export type Rect = { x: number, y: number, w: number, h: number }
export type Placed = {
	kind: "gift" | "buy", text: string?, icon: boolean?, caption: string?,
	x: number, y: number, w: number, h: number,
	pop: number, -- its PopScale
	captionRect: Rect?,
}

-- A buy button's width for `text` ("1,600", "Owned"), with the Robux icon in front when `icon`: its padding,
-- the icon and the text at the button's text height (bold digits and letters ~0.55 of it, "," "." " " half that).
ShopLayout.CHAR_W = 20
function ShopLayout.buyWidth(text: string, icon: boolean?, minW: number?): number
	local w = 2 * 12 + (if icon then math.floor(ShopLayout.BUTTON_H * 0.62) + 6 else 0)
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		w += if ch == "," or ch == "." or ch == " " or ch == "!" then ShopLayout.CHAR_W / 2 else ShopLayout.CHAR_W
	end
	return math.max(minW or ShopLayout.MIN_BUY_W, math.ceil(w))
end

-- The y of a button row resting on the bottom of a card `cardH` tall (above its captions).
function ShopLayout.bottomY(cardH: number, captioned: boolean): number
	return cardH - ShopLayout.MARGIN - (if captioned then ShopLayout.CAPTION_H else 0) - ShopLayout.BUTTON_H
end

-- The pop each button may take: up to HOVER, but its popped outline stays inside the card (cardW x cardH)
-- and takes at most half the gap to its neighbours.
local function pops(placed: { Placed }, cardW: number, cardH: number)
	local st = ShopLayout.BUTTON_STROKE
	for i, p in placed do
		local a, b = p.w / 2 + st, p.h / 2 + st -- half extents with the outline
		local cx, cy = p.x + p.w / 2, p.y + p.h / 2
		local s = ShopLayout.HOVER
		s = math.min(s, (cx - 1) / a, (cardW - 1 - cx) / a, (cy - 1) / b, (cardH - 1 - cy) / b)
		for j, q in placed do
			if j ~= i then
				-- the outer gap between them at rest (horizontal neighbours in one row)
				local gap = math.max(q.x - st - (p.x + p.w + st), p.x - st - (q.x + q.w + st))
				if gap >= 0 then
					s = math.min(s, (a + gap / 2) / a)
				end
			end
		end
		p.pop = math.max(1, math.floor(s * 1000) / 1000)
	end
end

-- Places `buttons` in one row at `y` of a card (cardW x cardH), centred between `left` and `right`
-- (default: the whole card). A gift button is GIFT_W square; a buy button is sized to its text.
function ShopLayout.row(buttons: { Button }, cardW: number, cardH: number, y: number, left: number?, right: number?): { Placed }
	local placed: { Placed } = {}
	local total = 0
	for i, b in buttons do
		local w = if b.kind == "gift" then ShopLayout.GIFT_W else ShopLayout.buyWidth(b.text or "", b.icon, b.minW)
		local gap = if i == 1 then 0 elseif buttons[i - 1].kind == "gift" then ShopLayout.PAIR_GAP else ShopLayout.GROUP_GAP
		total += gap + w
		table.insert(placed, {
			kind = b.kind, text = b.text, icon = b.icon, caption = b.caption,
			x = gap, y = y, w = w, h = ShopLayout.BUTTON_H, pop = 1,
		})
	end
	local l, r = left or 0, right or cardW
	local x = l + math.floor((r - l - total) / 2)
	for _, p in placed do
		x += p.x
		p.x = x
		x += p.w
		if p.caption then
			p.captionRect = { x = p.x - 20, y = p.y + p.h + 2, w = p.w + 40, h = ShopLayout.CAPTION_H }
		end
	end
	pops(placed, cardW, cardH)
	return placed
end

-- A placed button's rect once popped (scaled about its centre, outline included): what the tests check.
function ShopLayout.popped(p: Placed): Rect
	local st = ShopLayout.BUTTON_STROKE
	local w, h = (p.w + 2 * st) * p.pop, (p.h + 2 * st) * p.pop
	return { x = p.x + p.w / 2 - w / 2, y = p.y + p.h / 2 - h / 2, w = w, h = h }
end

return ShopLayout
