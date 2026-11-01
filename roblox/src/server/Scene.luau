-- The scene builder: draws a maze level as a Backrooms room in one Folder, Workspace.Maze.
-- It places what the coordinator returned and decides nothing: the watchers stand only on
-- state.guards, and the gems leave the view only when state.collected says so (ticket 09).
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
local HUM = { SoundId = "rbxassetid://9112823813", Volume = 0.06, RollOffMinDistance = 2, RollOffMaxDistance = 14 }
local HUMS = 8 -- at most this many lights hum
local ROOM_TONE = { SoundId = "rbxassetid://9125446564", Volume = 0.15 }
local DRONE = { SoundId = "rbxassetid://1843770413", Volume = 0.1 }

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

local Scene = {}
local ambience = false -- the room tone and the drone start at the first build and keep playing
local drawn -- what Scene.update moves: { maze, width, gems, watchers, marks }

-- Moves the scene to a reply's state: each watcher to its cell in state.guards (with PivotTo, so
-- any look moves the same way), each mark to its guard's cell in state.guardsNext, and gem i out
-- of view while state.collected[i] is true.
function Scene.update(state)
	for i, watcher in drawn.watchers do
		local _, size = watcher:GetBoundingBox()
		watcher:PivotTo(CFrame.new(Grid.toWorld(drawn.width, state.guards[i]) + Vector3.new(0, size.Y / 2, 0)))
		drawn.marks[i].Position = Grid.toWorld(drawn.width, state.guardsNext[i]) + Vector3.new(0, MARK.Size.Y / 2, 0)
	end
	for i, gem in drawn.gems do
		gem.Parent = if state.collected[i] then nil else drawn.maze
	end
end

-- Draws the level detail's variant in Workspace.Maze, with the watchers on state.guards from
-- the session start reply, and prints the [scene] line.
function Scene.build(detail, state)
	local variant = detail.variant
	local width, cells = variant.width, variant.width * variant.height
	local old = workspace:FindFirstChild("Maze")
	if old then
		old:Destroy()
	end
	local maze = new("Folder", workspace, { Name = "Maze" })
	local lights = new("Folder", maze, { Name = "Lights" })

	-- The pool that the dress step (ticket 24) fills in Edit mode. Until then it is missing, and
	-- the lights and the watchers use their fallback.
	local pool = ServerStorage:FindFirstChild("DressPool")
	pool = pool and pool:FindFirstChild("Art")
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
	new("PointLight", part(maze, EXIT, { Position = exitAt }), EXIT_LIGHT)
	drawn = { maze = maze, width = width, gems = {}, watchers = {}, marks = {} }
	for _, c in variant.gems do -- in the order of variant.gems, which state.collected follows
		local gemAt = Grid.toWorld(width, c) + Vector3.new(0, GEM_HEIGHT, 0)
		local gem = part(maze, GEM, { Position = gemAt })
		new("PointLight", gem, GEM_LIGHT)
		table.insert(drawn.gems, gem)
	end

	-- One watcher and one mark per guard; Scene.update stands them on the state's cells.
	for _ in state.guards do
		local watcher = artClone("Watcher") or plainWatcher()
		for _, d in watcher:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
			end
		end
		watcher.Parent = maze
		table.insert(drawn.watchers, watcher)
		table.insert(drawn.marks, part(maze, MARK))
	end
	Scene.update(state)

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
