-- The scene builder: draws a maze level as a Backrooms room in one Folder, Workspace.Maze.
-- It places what the coordinator returned and decides nothing: the watchers stand only on
-- state.guards, and the gems leave the view only when state.collected says so (ticket 09).
-- Decor (ticket 26) only dresses the room: props stand away from the start, the exit, the gems,
-- and every cell a watcher can stand on, and a decor model can give the watchers their look.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")

local Grid = require(ReplicatedStorage.Shared.Grid)

-- The look. Starting values from the research table (.scratch/roblox-pivot/research/
-- backrooms-art-kits.md, section 2); the person tunes them in Studio (ticket 13, part 2).
-- An unknown MaterialVariant name falls back to the base material, so the surfaces need no art.
local WALL = { Material = Enum.Material.Plaster, MaterialVariant = "RA_Wall", Color = Color3.fromRGB(196, 180, 110) }
local FLOOR = { Material = Enum.Material.Carpet, MaterialVariant = "RA_Floor", Color = Color3.fromRGB(150, 130, 80) }
local CEILING =
	{ Material = Enum.Material.CeramicTiles, MaterialVariant = "RA_Ceiling", Color = Color3.fromRGB(220, 214, 190) }
local PANEL = { Size = Vector3.new(4, 0.2, 4) } -- the thin part under the ceiling that holds a light
local PLAIN_PANEL = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 250, 235) } -- the panel without the art
local LIGHT = { Face = Enum.NormalId.Bottom, Brightness = 1.5, Range = 14, Color = Color3.fromRGB(255, 244, 214) }
local EXIT = { Material = Enum.Material.Neon, Color = Color3.fromRGB(80, 255, 120), Size = Vector3.new(4, 0.4, 4) }
local EXIT_LIGHT = { Range = 10 }
local GEM = {
	Material = Enum.Material.Neon,
	Color = Color3.fromRGB(80, 200, 255),
	Shape = Enum.PartType.Ball,
	Size = Vector3.new(1.5, 1.5, 1.5),
}
local GEM_LIGHT = { Range = 6 }
local GEM_HEIGHT = 3 -- studs from the floor to a gem's centre
local WATCHER_BODY = { Color = Color3.fromRGB(10, 10, 10), Size = Vector3.new(1.6, 5, 0.8) } -- the watcher without the art
local WATCHER_HEAD = { Color = Color3.fromRGB(10, 10, 10), Size = Vector3.new(1.4, 1.4, 1.2) }
local WATCHER_EYE = { Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1), Size = Vector3.new(0.3, 0.15, 0.1) }
local MARK = { -- on the floor of a guard's next cell: faint red, as on the web page
	Material = Enum.Material.Neon,
	Color = Color3.fromRGB(255, 107, 127),
	Transparency = 0.6,
	Size = Vector3.new(6, 0.05, 6),
	CanCollide = false,
	CanQuery = false,
}
local GLOW = { -- a checked cell in Show why (ticket 12): a thin green tile on the floor
	Material = Enum.Material.Neon,
	Color = Color3.fromRGB(80, 255, 120),
	Size = Vector3.new(7, 0.06, 7),
	CanCollide = false,
	CanQuery = false,
}
local EXIT_RED = Color3.fromRGB(255, 60, 60) -- the exit during Show why on a rigged maze
local CLICK = { SoundId = "rbxassetid://9120484192", Volume = 0.5 } -- the light switch, when the lights cut out
local HUM = { SoundId = "rbxassetid://9112823813", Volume = 0.06, RollOffMinDistance = 2, RollOffMaxDistance = 14 }
local HUMS = 8 -- at most this many lights hum
local ROOM_TONE = { SoundId = "rbxassetid://9125446564", Volume = 0.15 }
local DRONE = { SoundId = "rbxassetid://1843770413", Volume = 0.1 }
-- Decor props. The decor gate's box for a prop is 4 x 6 x 4 studs, centred on the model's pivot.
local PROP_GAP = 2 -- studs from a wall's face to a prop's pivot, so the box touches the wall
local PROP_HEIGHT = 3 -- studs from the floor to a prop's pivot, so the box stands on the floor
local PROP_SLOTS = 3 -- spots that one decor model fills
local PROP_MAX = 12 -- props in one level

-- One instance with the properties of each table, parented last.
local function new(class, parent, ...)
	local o = Instance.new(class)
	for _, props in { ... } do
		for k, v in props do
			o[k] = v
		end
	end
	o.Parent = parent
	return o
end

-- Every new Part: anchored, since a new Part falls when Play starts, and with no touch events.
local function part(parent, ...)
	return new("Part", parent, { Anchored = true, CanTouch = false }, ...)
end

-- A looped sound. If it does not load, it stays silent; nothing else depends on it.
local function play(parent, props)
	new("Sound", parent, { Looped = true }, props):Play()
end

-- A clone of a pool model for the scene, or nil (the caller then uses its fallback). The dress
-- step (ticket 24) sets checkedNodes to the number of instances the decor gate checked; a clone
-- with any other count is dropped. Never look up anything inside a pool model by name: those
-- names come from the model's creator.
local function checkedClone(model)
	local nodes = model and model:GetAttribute("checkedNodes")
	local clone = nodes and model:Clone()
	if clone and #clone:GetDescendants() + 1 == nodes then
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		return clone
	end
	if clone then
		clone:Destroy()
	end
	return nil
end

-- A clone is only for looking at: its parts take no hits, no touch events, and no raycasts.
local function inert(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
		end
	end
end

-- The watcher without the art: a dark stack with two white eyes on its front (-Z) side. Its
-- pivot is the centre of its box, as the dress step leaves pool models.
local function plainWatcher()
	local m = Instance.new("Model")
	local body, head, eye = WATCHER_BODY.Size, WATCHER_HEAD.Size, WATCHER_EYE.Size
	part(m, WATCHER_BODY, { Position = Vector3.new(0, body.Y / 2, 0) })
	part(m, WATCHER_HEAD, { Position = Vector3.new(0, body.Y + head.Y / 2, 0) })
	for _, side in { -1, 1 } do
		part(m, WATCHER_EYE, { Position = Vector3.new(side * head.X / 4, body.Y + head.Y * 0.6, -(head.Z + eye.Z) / 2) })
	end
	m.WorldPivot = m:GetBoundingBox()
	return m
end

-- The models in one folder of this level's decor in the pool (Decor.<level id>.<where>) that pass the
-- checked clone, in the folder's order. A model that fails is left out, with a log line; <n> is its
-- place in the folder. Nothing is read from a model, not even its name.
local function goodModels(levelDecor, where)
	local group = levelDecor and levelDecor:FindFirstChild(where)
	local models = if group then group:GetChildren() else {}
	local good = {}
	for n, model in models do
		local probe = checkedClone(model)
		if probe then
			probe:Destroy() -- a spare, only to see that it passes: every use makes its own clone
			table.insert(good, model)
		else
			print(("[decor] dropped %s %d: count mismatch"):format(where, n))
		end
	end
	return good
end

local SIDES = { "up", "right", "down", "left" } -- clockwise, the keys of Grid.FACING
local CORNERS = { { "up", "right" }, { "right", "down" }, { "down", "left" }, { "left", "up" } } -- two sides that meet

-- Where props can stand: { wall = {...}, corner = {...} }, each a list in cell order of { cell, at }
-- (`at` is where the prop's pivot goes). A wall spot is an open cell with a wall on at least one side;
-- a corner spot is one with walls on two sides that meet. Never the start, the exit, a gem cell, or a
-- cell a watcher stands on in any turn: those come from the runtime's drawing.guardsByTurn, and
-- nothing about the watchers is worked out here. The pivot sits PROP_GAP studs from the wall's face
-- (from both faces in a corner) and PROP_HEIGHT studs up, turned a quarter turn to face away from the wall.
local function propSpots(detail, isWall)
	local variant = detail.variant
	local width, height = variant.width, variant.height
	local skip = { [variant.start] = true, [variant.exit] = true }
	for _, c in variant.gems do
		skip[c] = true
	end
	local turns = detail.drawing and detail.drawing.guardsByTurn or {}
	for _, turn in turns do
		for _, c in turn do
			skip[c] = true
		end
	end

	local function walled(c, side) -- is the cell on this side of c a wall? The edge of the board is not.
		local f = Grid.FACING[side]
		local col, row = c % width + f.X, c // width + f.Z
		return col >= 0 and col < width and row >= 0 and row < height and isWall[row * width + col] == true
	end
	local function spot(c, a, b) -- b: the second wall of a corner
		local toward = Grid.FACING[a] + (if b then Grid.FACING[b] else Vector3.zero)
		local at = Grid.toWorld(width, c) + toward * (Grid.CELL / 2 - PROP_GAP) + Vector3.new(0, PROP_HEIGHT, 0)
		return { cell = c, at = CFrame.lookAt(at, at - Grid.FACING[a]) }
	end

	local spots = { wall = {}, corner = {} }
	for c = 0, width * height - 1 do
		if not isWall[c] and not skip[c] then
			local hasWall = {}
			for _, side in SIDES do
				hasWall[side] = walled(c, side)
			end
			for _, side in SIDES do
				if hasWall[side] then
					table.insert(spots.wall, spot(c, side))
					break
				end
			end
			for _, pair in CORNERS do
				if hasWall[pair[1]] and hasWall[pair[2]] then
					table.insert(spots.corner, spot(c, pair[1], pair[2]))
					break
				end
			end
		end
	end
	return spots
end

-- n items of the list, evenly spaced along it (all of them if it has fewer).
local function spread(list, n)
	n = math.min(n, #list)
	local out = {}
	for i = 0, n - 1 do
		table.insert(out, list[i * #list // n + 1])
	end
	return out
end

-- The props, in `folder`: up to PROP_SLOTS clones of every model that passes the check, on spots
-- spread along the level, at most PROP_MAX in all. The clones are queued one round of models at a
-- time, so spots next to each other get different models. Corner models go first, and a cell holds
-- one prop. Returns how many props stand.
local function placeProps(folder, detail, levelDecor, isWall)
	local models = { corner = goodModels(levelDecor, "corner"), wall = goodModels(levelDecor, "wall") }
	if #models.corner + #models.wall == 0 then
		return 0 -- no decor: nothing else is looked at
	end
	local spots, taken, placed = propSpots(detail, isWall), {}, 0
	for _, where in { "corner", "wall" } do
		local free, queue = {}, {}
		for _, s in spots[where] do
			if not taken[s.cell] then
				table.insert(free, s)
			end
		end
		for _ = 1, PROP_SLOTS do
			for _, model in models[where] do
				table.insert(queue, model)
			end
		end
		for i, s in spread(free, math.min(#queue, PROP_MAX - placed)) do
			local clone = checkedClone(queue[i])
			if clone then
				inert(clone)
				clone:PivotTo(s.at)
				clone.Parent = folder
				taken[s.cell] = true
				placed += 1
			end
		end
	end
	return placed
end

local Scene = {}
local ambience = false -- the room tone and the drone start at the first build and keep playing
local drawn -- what Scene.update moves: { maze, width, gems, watchers, marks, exit, glow, materials }

-- Stands each watcher on its cell in guards, a list of cells in guard order (with PivotTo, so any
-- look moves the same way).
function Scene.watchers(guards)
	for i, watcher in drawn.watchers do
		local _, size = watcher:GetBoundingBox()
		watcher:PivotTo(CFrame.new(Grid.toWorld(drawn.width, guards[i]) + Vector3.new(0, size.Y / 2, 0)))
	end
end

-- Moves the scene to a reply's state: each watcher to its cell in state.guards, each mark to its
-- guard's cell in state.guardsNext, and gem i out of view while state.collected[i] is true.
function Scene.update(state)
	Scene.watchers(state.guards)
	for i, mark in drawn.marks do
		mark.Position = Grid.toWorld(drawn.width, state.guardsNext[i]) + Vector3.new(0, MARK.Size.Y / 2, 0)
	end
	for i, gem in drawn.gems do
		gem.Parent = if state.collected[i] then nil else drawn.maze
	end
end

-- Show why: a glow tile on the floor of each cell in cells, in place of the last ones.
function Scene.glow(cells)
	drawn.glow:ClearAllChildren()
	for _, c in cells do
		part(drawn.glow, GLOW, { Position = Grid.toWorld(drawn.width, c) + Vector3.new(0, GLOW.Size.Y / 2, 0) })
	end
end

-- Show why on a rigged maze. on = true: every light under Lights goes out, the light panels turn to
-- SmoothPlastic, the switch clicks, the exit turns red, and the next-cell marks leave the view (as
-- on the web page). on = false: all of it comes back, and the glow tiles go.
function Scene.reveal(on)
	for _, d in drawn.maze.Lights:GetDescendants() do
		if d:IsA("Light") then
			d.Enabled = not on
		elseif d:IsA("BasePart") then
			drawn.materials[d] = drawn.materials[d] or d.Material
			d.Material = if on then Enum.Material.SmoothPlastic else drawn.materials[d]
		end
	end
	drawn.exit.Color = if on then EXIT_RED else EXIT.Color
	for _, mark in drawn.marks do
		mark.Transparency = if on then 1 else MARK.Transparency
	end
	Scene.glow({})
	if on then
		new("Sound", drawn.maze, CLICK):Play()
	end
end

-- Draws the level detail's variant in Workspace.Maze, with the watchers on state.guards from
-- the session start reply, and prints the [decor] and [scene] lines.
function Scene.build(detail, state)
	local variant = detail.variant
	local width, cells = variant.width, variant.width * variant.height
	local old = workspace:FindFirstChild("Maze")
	if old then
		old:Destroy()
	end
	local maze = new("Folder", workspace, { Name = "Maze" })
	local lights = new("Folder", maze, { Name = "Lights" })
	local decorFolder = new("Folder", maze, { Name = "Decor" }) -- the props, and only they

	-- The pool that the dress step (ticket 24) fills in Edit mode: the art, and each level's decor.
	-- Until then it is missing: the lights and the watchers use their fallback, and no props stand.
	local dress = ServerStorage:FindFirstChild("DressPool")
	local pool = dress and dress:FindFirstChild("Art")
	local levelDecor = dress and dress:FindFirstChild("Decor")
	levelDecor = levelDecor and levelDecor:FindFirstChild(detail.id)
	local usedArt = false
	local function artClone(name)
		local clone = checkedClone(pool and pool:FindFirstChild(name))
		usedArt = usedArt or clone ~= nil
		return clone
	end

	local isWall = {}
	for _, c in variant.walls do
		isWall[c] = true
		part(maze, WALL, {
			Size = Vector3.new(Grid.CELL, Grid.WALL_HEIGHT, Grid.CELL),
			Position = Grid.toWorld(width, c) + Vector3.new(0, Grid.WALL_HEIGHT / 2, 0),
		})
	end
	local area = Vector3.new(width * Grid.CELL, 1, variant.height * Grid.CELL)
	local middle = (Grid.toWorld(width, 0) + Grid.toWorld(width, cells - 1)) / 2
	part(maze, FLOOR, { Size = area, Position = middle - Vector3.new(0, 0.5, 0) })
	-- named, so the client's map view can take it out of its own view
	part(maze, CEILING, { Name = "Ceiling", Size = area, Position = middle + Vector3.new(0, Grid.WALL_HEIGHT + 0.5, 0) })

	-- A light on every second open cell: a checkerboard, so every second cell along any corridor.
	-- Our SurfaceLight is the only light; the art has none (the decor gate rejects lights).
	local lightCells = {}
	for c = 0, cells - 1 do
		if not isWall[c] and (c % width + c // width) % 2 == 0 then
			table.insert(lightCells, c)
		end
	end
	local humEvery = math.ceil(#lightCells / HUMS)
	for i, c in lightCells do
		local ceiling = Grid.toWorld(width, c) + Vector3.new(0, Grid.WALL_HEIGHT, 0)
		local fixture = artClone("CeilingLight")
		local panel = part(lights, PANEL, if fixture then { Transparency = 1 } else PLAIN_PANEL, {
			Position = ceiling - Vector3.new(0, PANEL.Size.Y / 2, 0),
		})
		new("SurfaceLight", panel, LIGHT)
		if fixture then -- hangs from the ceiling; the dress step already scaled it to fit
			local _, size = fixture:GetBoundingBox()
			fixture:PivotTo(CFrame.new(ceiling - Vector3.new(0, size.Y / 2, 0)))
			fixture.Parent = panel
		end
		if (i - 1) % humEvery == 0 then
			play(panel, HUM)
		end
	end

	local exitAt = Grid.toWorld(width, variant.exit) + Vector3.new(0, EXIT.Size.Y / 2, 0)
	local exit = part(maze, EXIT, { Position = exitAt })
	new("PointLight", exit, EXIT_LIGHT)
	drawn = {
		maze = maze,
		width = width,
		gems = {},
		watchers = {},
		marks = {},
		exit = exit,
		glow = new("Folder", maze, { Name = "Glow" }), -- Show why's tiles
		materials = {}, -- each light part's own material, while Show why has the lights out
	}
	for _, c in variant.gems do -- in the order of variant.gems, which state.collected follows
		local gemAt = Grid.toWorld(width, c) + Vector3.new(0, GEM_HEIGHT, 0)
		local gem = part(maze, GEM, { Position = gemAt })
		new("PointLight", gem, GEM_LIGHT)
		table.insert(drawn.gems, gem)
	end

	-- One watcher and one mark per guard; Scene.update stands them on the state's cells. Each watcher's
	-- look is the level's decor watcher if it passes the check, else the cached look the brief names
	-- for it, else the art watcher, else the plain stack. The brief's "watcher:" text (lowercased, up
	-- to ; or . or the end) is a comma-separated list of names in watcher order; with more watchers
	-- than names the list starts over. The names are only ever folder names.
	local lookModel = goodModels(levelDecor, "watcher")[1]
	local names = {}
	local named = string.match(string.lower(tostring(detail.brief or "")), "watcher:%s*([^;%.\n]*)") or ""
	for item in string.gmatch(named, "[^,]+") do
		local name = string.match(item, "^%s*(.-)%s*$")
		if name ~= "" then
			table.insert(names, name)
		end
	end
	local looks = dress and dress:FindFirstChild("Looks")
	local used = {} -- which look each watcher got, for the log
	for i in state.guards do
		local j = i
		while #names > 0 and j > #names do
			j -= #names
		end
		local name = names[j]
		local cached = name and looks and looks:FindFirstChild(name)
		local watcher, look = lookModel and checkedClone(lookModel), "decor"
		if not watcher then
			watcher, look = cached and checkedClone(cached), "looks:" .. tostring(name)
		end
		if not watcher then
			watcher, look = artClone("Watcher"), "art"
		end
		if not watcher then
			look = "plain"
		end
		table.insert(used, look)
		watcher = watcher or plainWatcher()
		inert(watcher)
		watcher.Parent = maze
		table.insert(drawn.watchers, watcher)
		table.insert(drawn.marks, part(maze, MARK))
	end
	Scene.update(state)

	local props = placeProps(decorFolder, detail, levelDecor, isWall)
	-- Floor props the brief asks for ("floor: <name> every <n> tiles", n from 2 to 9): a checked clone of
	-- PropCache[<name>] lying on every open cell whose index is a multiple of n, but not the start or the
	-- exit. Visual only, like all decor; the name is only ever a folder name.
	local floorName, every = string.match(string.lower(tostring(detail.brief or "")), "floor:%s*([^;%.\n]-)%s+every%s+(%d)%s+tiles")
	local step = tonumber(every)
	if floorName and step and step >= 2 and step <= 9 then
		local cache = dress and dress:FindFirstChild("PropCache")
		local source = cache and cache:FindFirstChild(floorName)
		local placedFloor = 0
		local v = detail.variant
		for c = 0, v.width * v.height - 1, step do
			if source and not isWall[c] and c ~= v.start and c ~= v.exit and placedFloor < 60 then
				local clone = checkedClone(source)
				if clone then
					inert(clone)
					clone:PivotTo(CFrame.new(Grid.toWorld(v.width, c) + Vector3.new(0, 0.75, 0)))
					clone.Parent = decorFolder
					placedFloor += 1
				end
			end
		end
		print(("[decor] floor %s every %d: %d placed"):format(floorName, step, placedFloor))
	end
	local look = table.concat(used, ",") -- each watcher's look, in order
	print(("[decor] placed %d props, watcher look %s"):format(props, look))

	if not ambience then
		ambience = true
		play(SoundService, ROOM_TONE)
		play(SoundService, DRONE)
	end

	print(
		("[scene] built %s: %d walls, %d lights, %d watchers, art %s"):format(
			detail.presentation.title,
			#variant.walls,
			#lightCells,
			#state.guards,
			if usedArt then "yes" else "no"
		)
	)
end

return Scene
