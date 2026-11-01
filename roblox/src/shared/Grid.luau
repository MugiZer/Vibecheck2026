-- Grid to world, for the server Script (the scene) and the client (the camera).
-- Cell c is column c % width and row c // width, with row 0 at the top, as on the web page.
-- Columns run along +X and rows along +Z, so row 0 is the -Z side. The floor's top is at Y = 0.
local Grid = {
	CELL = 8, -- studs per cell; the person tunes these in Studio (ticket 13, part 2)
	WALL_HEIGHT = 10, -- studs
	EYE_HEIGHT = 4.5, -- studs above the floor, about where Roblox's own first-person camera sits
}

-- The four facings as world directions.
Grid.FACING = {
	up = Vector3.new(0, 0, -1),
	down = Vector3.new(0, 0, 1),
	left = Vector3.new(-1, 0, 0),
	right = Vector3.new(1, 0, 0),
}

-- The centre of cell c, on the floor.
function Grid.toWorld(width, c)
	return Vector3.new(c % width, 0, c // width) * Grid.CELL
end

return Grid
