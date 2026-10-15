-- The Shop's PASSES section (client): one bright card per gamepass in Config.GAMEPASSES, in Shop order, each
-- in its own colour: its icon (2x Money: the cash on a gold "x2" coin, PassCards.COINS; VIP: the VIP ticket),
-- its name, its one-line benefit and a green R$ button with its price, or a gold "Owned" (PassCards.OWNED)
-- once the server says the player owns it (StatsUpdate
-- `passes`, from the server's own check). Clicking asks the server ("Pass:<name>"), which prompts the
-- purchase, or says "coming soon" while the pass has no id. The HUD hands in its card style (`Deps`), so
-- these look like every other Shop card; this module only decides what goes on them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local PassCards = {}

-- Vivid card colours, none of them green, so the green R$ button always stands out (owner reference
-- 2026-10-15: gold for 2x Money, a rainbow for Fast Grow).
PassCards.COLORS = {
	DoubleMoney = Color3.fromRGB(255, 190, 20),
	DoubleSpeed = Color3.fromRGB(30, 165, 255),
	DoubleLuck = Color3.fromRGB(255, 85, 165),
	VIP = Color3.fromRGB(225, 45, 70),
	FastGrow = Color3.fromRGB(150, 90, 255),
	ExtraSlots = Color3.fromRGB(255, 120, 40),
} :: { [string]: Color3 }
PassCards.RAINBOW = { FastGrow = true } :: { [string]: boolean } -- painted with a rainbow instead
PassCards.DEFAULT_COLOR = Color3.fromRGB(165, 70, 255) -- a pass added to Config without a colour here
-- Passes whose icon sits on a gold coin with a stamp (owner reference: the cash on a gold "x2" coin)
PassCards.COINS = { DoubleMoney = "x2" } :: { [string]: string }
-- The "Owned" button (pass cards and the Shop's banners): bright gold, a dark outline, white relief words
PassCards.OWNED = Color3.fromRGB(255, 200, 30)

export type Card = {
	name: string,
	title: string, -- "2X SPEED"
	about: string, -- the benefit line
	icon: string?, -- Icons key; nil = a gold "VIP" badge
	coin: string?, -- the icon on a gold coin with this stamp ("x2"), PassCards.COINS
	color: Color3,
	rainbow: boolean, -- a rainbow card (PassCards.RAINBOW)
	owned: boolean,
	caption: string, -- the button: "Owned", "R$ 299", or "Buy" while there's no price at all
}

-- What a pass's card shows, for a player who owns `passes` (the client's copy) at `price` Robux.
function PassCards.view(name: string, passes: { [string]: boolean }?, price: number): Card
	local pass = Config.GAMEPASSES[name]
	local owned = passes ~= nil and passes[name] == true
	return {
		name = name,
		title = string.upper(pass.label),
		about = pass.about,
		icon = pass.icon,
		coin = PassCards.COINS[name],
		color = PassCards.COLORS[name] or PassCards.DEFAULT_COLOR,
		rainbow = PassCards.RAINBOW[name] == true,
		owned = owned,
		caption = if owned then "Owned" elseif price > 0 then Format.robux(price) else "Buy",
	}
end

export type Deps = {
	card: (grid: Instance, order: number, view: Card) -> Frame, -- the Shop's card (shopCard + the VIP badge)
	button: (card: Frame, view: Card, onClick: () -> ()) -> GuiObject, -- its bottom row (buyRow)
	price: (pass: Config.Gamepass) -> number, -- Robux, from GetProductInfo or the placeholder
	buy: (name: string) -> (), -- asks the server
}

-- Builds every pass's card into `grid`. Returns them by pass name.
function PassCards.render(grid: Instance, passes: { [string]: boolean }?, deps: Deps): { [string]: Frame }
	local cards = {}
	for i, name in Config.passNames() do
		local view = PassCards.view(name, passes, deps.price(Config.GAMEPASSES[name]))
		local c = deps.card(grid, i, view)
		c.Name = "Pass_" .. name
		deps.button(c, view, function()
			if not view.owned then
				deps.buy(name)
			end
		end)
		cards[name] = c
	end
	return cards
end

return PassCards
