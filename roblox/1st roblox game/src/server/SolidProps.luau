-- Big decoration players bump into (owner 2026-10-16: "add collision to the decorations like the trees and
-- volcanos"). The map is built with every prop a non-colliding ghost (Props); when the server starts this
-- turns the big set pieces solid: the trees, rocks, volcanoes, pyramids, crystals, shrines... (the slots
-- in SolidProps.SLOTS). Their parts join the "Decor" collision group, which the guards don't collide with
-- (Main), so a boss never snags on a tree while chasing; only players are stopped. Small or flat pieces
-- (flowers, ferns, bones, craters, lava vents, glowing bits) stay ghosts so nobody trips on a pebble.
local SolidProps = {}

SolidProps.GROUP = "Decor"
SolidProps.MIN_SIZE = 2 -- studs: a part smaller than this on every axis stays a ghost

SolidProps.SLOTS = {
	Tree = true, BlossomTree = true, Rock = true, Lamp = true,
	Meadow_Tree = true, Meadow_Rock = true,
	Desert_Cactus = true, Desert_Mesa = true, Desert_Pyramid = true, Desert_Ruins = true, Desert_Palm = true, Desert_Rock = true,
	Jungle_Tree = true, Jungle_Log = true, Jungle_Ruins = true, Jungle_Bamboo = true,
	Lava_Volcano = true, Lava_Rock = true, Lava_Obsidian = true, Lava_Basalt = true, Lava_DeadTree = true,
	Snow_Pine = true, Snow_Snowman = true, Snow_Crystal = true, Snow_Cliff = true, Snow_Igloo = true,
	Space_Crystal = true, Space_Asteroid = true, Space_Mushroom = true, Space_UFO = true, Space_Rocket = true, Space_Rock = true,
	Spirit_Torii = true, Spirit_Lantern = true, Spirit_CherryTree = true, Spirit_Shrine = true, Spirit_Bamboo = true, Spirit_Rock = true,
} :: { [string]: boolean }

-- Whether one part of a solid prop should collide: big enough, visible, not a glow.
function SolidProps.solidPart(p: BasePart): boolean
	local s = p.Size
	return math.max(s.X, s.Y, s.Z) >= SolidProps.MIN_SIZE and p.Transparency < 0.5 and p.Material ~= Enum.Material.Neon
end

-- Turns the big props under `world` solid. Returns how many parts now collide.
function SolidProps.apply(world: Instance?): number
	if not world then
		return 0
	end
	local n = 0
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and SolidProps.SLOTS[d:GetAttribute("AssetSlot") or ""] then
			for _, p in d:GetDescendants() do
				if p:IsA("BasePart") and not p.CanCollide and SolidProps.solidPart(p) then
					p.CanCollide = true
					p.CanTouch = false
					p.CollisionGroup = SolidProps.GROUP
					n += 1
				end
			end
		end
	end
	return n
end

return SolidProps
