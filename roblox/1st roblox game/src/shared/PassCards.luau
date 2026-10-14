-- The Shop's PASSES section (client): one bright card per gamepass in Config.GAMEPASSES, in Shop order, each
-- in its own colour: its icon (VIP: a gold relief "VIP" badge instead), its name, its one-line benefit and a
-- green R$ button with its price, or a grey "Owned" once the server says the player owns it (StatsUpdate
-- `passes`, from the server's own check). Clicking asks the server ("Pass:<name>"), which prompts the
-- purchase, or says "coming soon" while the pass has no id. The HUD hands in its card style (`Deps`), so
-- these look like every other Shop card; this module only decides what goes on them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local PassCards = {}

PassCards.COLORS = {
	DoubleMoney = Color3.fromRGB(70, 205, 30),
	DoubleSpeed = Color3.fromRGB(30, 165, 255),
	DoubleLuck = Color3.fromRGB(20, 200, 170),
	VIP = Color3.fromRGB(255, 180, 20),
	FastGrow = Color3.fromRGB(140, 215, 20),
	ExtraSlots = Color3.fromRGB(255, 120, 40),
} :: { [string]: Color3 }
PassCards.DEFAULT_COLOR = Color3.fromRGB(165, 70, 255) -- a pass added to Config without a colour here

export type Card = {
	name: string,
	title: string, -- "2X SPEED"
	about: string, -- the benefit line
	icon: string?, -- Icons key; nil = the VIP badge
	color: Color3,
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
		color = PassCards.COLORS[name] or PassCards.DEFAULT_COLOR,
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
