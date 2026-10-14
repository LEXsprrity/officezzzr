--!strict
-- The money ($) button on the Upgrade boards (the plot's, WorldBuilder, and the treadmill's, TreadmillBoard):
-- red by default, GREEN while its owner can afford what it buys (owner request). The server paints it red
-- and writes the price it shows as the painted button's "Price" attribute (none when there is nothing to
-- buy); each client recolours only its own boards' buttons from its own money (Effects.client).
local BoardButton = {}

export type Colors = { fill: Color3, edge: Color3 }

BoardButton.RED = { fill = Color3.fromRGB(225, 40, 40), edge = Color3.fromRGB(90, 10, 10) } :: Colors
BoardButton.GREEN = { fill = Color3.fromRGB(55, 195, 60), edge = Color3.fromRGB(15, 80, 20) } :: Colors

-- The attribute on the painted button with the money price it shows.
BoardButton.PRICE_ATTRIBUTE = "Price"

-- Green when `money` covers `price` (money >= price), red otherwise, and red with no money known (not
-- your board) or nothing to buy (no price).
function BoardButton.cashColors(money: number?, price: number?): Colors
	if type(money) == "number" and type(price) == "number" and money == money and price == price and money >= price then
		return BoardButton.GREEN
	end
	return BoardButton.RED
end

return BoardButton
