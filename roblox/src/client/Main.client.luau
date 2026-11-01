-- Shows the coordinator status, the level list, and the claim panel, sends the maze keys to the
-- server Script and moves the camera after each reply, and sends this client's Output lines to
-- the server Script, which forwards them to build/roblox.log.
local ContextActionService = game:GetService("ContextActionService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Log = ReplicatedStorage:WaitForChild("Log")
local Coordinator = ReplicatedStorage:WaitForChild("Coordinator")
local State = ReplicatedStorage:WaitForChild("State")
local Grid = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Grid"))
LogService.MessageOut:Connect(function(message, messageType)
	Log:FireServer(messageType.Name .. " " .. message)
end)

-- The avatar stays on the cell the server puts it on: no default controls (turned off when the
-- character is there, below) and no reset button. No chat window either: it covers the level list.
-- default.project.json turns the chat off in a place built by make roblox (Chat.LoadDefaultChat; live
-- sync cannot set it), and the call below hides it in a place that still loads it.
local controls = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
task.spawn(function() -- both calls do nothing until Roblox's own UI scripts have loaded
	repeat
		local ok = pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false)
		task.wait(0.2)
	until ok
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
end)

local gui = Instance.new("ScreenGui")
gui.ResetOnSpawn = false -- keep the label when a character spawns
local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(260, 32)
label.Position = UDim2.fromOffset(8, 8)
label.Parent = gui
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function show()
	label.Text = ReplicatedStorage:GetAttribute("CoordinatorStatus") or "Connecting…"
end
ReplicatedStorage:GetAttributeChangedSignal("CoordinatorStatus"):Connect(show)
show()

-- The level list and the claim panel. GUI names hold letters, digits, and _ only:
-- agents click buttons by their path, which cannot hold a dot or a space.
local function new(class, props)
	local o = Instance.new(class)
	for k, v in props do
		o[k] = v
	end
	return o
end
local function text(name, order, parent) -- a block of wrapped text
	return new("TextLabel", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 18,
		Text = "", -- not the default "Label"
		Parent = parent,
	})
end

local levels = new("TextButton", {
	Name = "Levels",
	Text = "Levels",
	Size = UDim2.fromOffset(100, 32),
	Position = UDim2.fromOffset(276, 8),
	Parent = gui,
})
local list = new("ScrollingFrame", {
	Name = "List",
	Visible = false,
	Size = UDim2.fromOffset(520, 420),
	Position = UDim2.fromOffset(8, 48),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = gui,
})
new("UIListLayout", { Name = "Layout", SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = list })
local panel = new("Frame", {
	Name = "Panel",
	Visible = false,
	Size = UDim2.fromOffset(520, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.fromOffset(8, 48),
	Parent = gui,
})
new("UIListLayout", { Name = "Layout", SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = panel })
local body = text("Body", 4, panel) -- below Play and the note, which stay on screen when the text is long
local play = new("TextButton", { Name = "Play", Text = "Play", LayoutOrder = 2, Size = UDim2.fromOffset(120, 36), Parent = panel })
local note = text("Note", 3, panel)

-- A reply from the server Script: the panel text (kept if the reply has none), a note,
-- and whether Play shows.
local function showPanel(view)
	body.Text = view.text or body.Text
	note.Text = view.note or ""
	play.Visible = view.play == true
	list.Visible = false
	panel.Visible = true
end

local leave -- clears the last level's HUD, map view, and camera; defined with the HUD below
local showWhy -- the Show why button, made with the HUD below

local function openLevel(id) -- a click on a level's button, or "Play in Roblox" on the web page
	local reply = Coordinator:InvokeServer("open", id) -- the server Script removes the last level's maze
	leave() -- after the reply, so a move reply sent before the server handled open is cleared too
	showPanel(reply)
end
local function openList() -- fetched each time, so levels made during play appear
	local found, err = Coordinator:InvokeServer("levels")
	if not found then
		return showPanel({ text = err })
	end
	for _, b in list:GetChildren() do
		if b:IsA("TextButton") then
			b:Destroy()
		end
	end
	for i, level in found do
		local b = new("TextButton", {
			Name = "Level_" .. (level.id:gsub("%W", "_")),
			Text = level.text,
			LayoutOrder = i,
			Size = UDim2.new(1, -12, 0, 36),
			TextSize = 18,
			Parent = list,
		})
		b.Activated:Connect(function()
			openLevel(level.id)
		end)
	end
	panel.Visible = false
	list.Visible = true
end
levels.Activated:Connect(openList)
local function pressPlay()
	local reply = Coordinator:InvokeServer("play")
	if not reply then -- the player opened another level while the session started
		return
	end
	if reply.playing then -- the claim panel leaves the view during play; Levels brings it back
		panel.Visible = false
		showWhy.Visible = reply.showWhy == true -- a level with no reveal has no Show why
	else
		showPanel(reply)
	end
end
play.Activated:Connect(pressPlay)
-- "Play in Roblox" on the web page: the server Script sets RemoteOpen = "<id>#<n>", and the client
-- opens that level and presses Play, exactly as the clicks do.
Players.LocalPlayer:GetAttributeChangedSignal("RemoteOpen"):Connect(function()
	local id = tostring(Players.LocalPlayer:GetAttribute("RemoteOpen") or ""):match("^([%w_%-]+)#")
	if id then
		openLevel(id)
		pressPlay()
	end
end)

-- During play: the Show why caption and turn, the move count, caught or escaped, the last note,
-- the keys, two buttons that do what Space and R do, and Show why.
local hud = new("Frame", {
	Name = "Hud",
	Visible = false,
	Size = UDim2.fromOffset(520, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 8, 1, -8),
	Parent = gui,
})
new("UIListLayout", { Name = "Layout", SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = hud })
local moves = text("Moves", 1, hud)
local status = text("Status", 2, hud)
local message = text("Message", 3, hud)
text("Hint", 4, hud).Text = "W step · A/D turn · S turn around · Space wait · R restart · M map"
local waitButton = new("TextButton", { Name = "Wait", Text = "Wait", LayoutOrder = 5, Size = UDim2.fromOffset(120, 36), Parent = hud })
local restartButton =
	new("TextButton", { Name = "Restart", Text = "Restart", LayoutOrder = 6, Size = UDim2.fromOffset(120, 36), Parent = hud })
showWhy = new(
	"TextButton",
	{ Name = "ShowWhy", Text = "Show why", LayoutOrder = 7, Size = UDim2.fromOffset(120, 36), Visible = false, Parent = hud }
)
local caption = text("Caption", -2, hud) -- the coordinator's caption while Show why runs
local turn = text("Turn", -1, hud)

local view -- the last state the server sent, with the maze's width and height
local facing = "up" -- the camera's facing: turning changes only this, so no move is sent
local mapView = false

-- Sets a HUD label's text; an empty label leaves the view, so it shows no blank box.
local function say(target, s)
	target.Text = s
	target.Visible = s ~= ""
end

function leave()
	view, mapView, hud.Visible = nil, false, false
	say(message, "")
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

local ORDER = { "up", "right", "down", "left" } -- clockwise, so D turns to the next one
local TURN = {
	[Enum.KeyCode.A] = -1,
	[Enum.KeyCode.Left] = -1,
	[Enum.KeyCode.D] = 1,
	[Enum.KeyCode.Right] = 1,
	[Enum.KeyCode.S] = 2,
	[Enum.KeyCode.Down] = 2,
}
local SEND = { [Enum.KeyCode.Space] = "stay", [Enum.KeyCode.R] = "reset" } -- W and Up send the facing

-- Sets LocalTransparencyModifier on every part under root: 1 hides them on this client only.
local function seeThrough(root, value)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = value
		end
	end
end

-- Moves the camera with a short tween. First person: at eye height in the avatar's cell, looking
-- along the facing, with the local character hidden. Map view: high above the maze, looking
-- straight down with row 0 at the top as on the web page; the ceiling and the light panels leave
-- this client's view, and the local character shows again.
local function aim()
	local camera, maze = workspace.CurrentCamera, workspace:FindFirstChild("Maze")
	if not maze then -- opening another level removed it
		return
	end
	local goal
	if mapView then
		local middle = (Grid.toWorld(view.width, 0) + Grid.toWorld(view.width, view.width * view.height - 1)) / 2
		local above = middle + Vector3.new(0, Grid.WALL_HEIGHT + math.max(view.width, view.height) * Grid.CELL, 0)
		goal = CFrame.lookAt(above, middle, Grid.FACING.up)
	else
		local eye = Grid.toWorld(view.width, view.state.pos) + Vector3.new(0, Grid.EYE_HEIGHT, 0)
		goal = CFrame.lookAt(eye, eye + Grid.FACING[facing])
	end
	local hide = if mapView then 1 else 0
	maze.Ceiling.LocalTransparencyModifier = hide
	seeThrough(maze.Lights, hide)
	seeThrough(Players.LocalPlayer.Character, 1 - hide)
	camera.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(camera, TweenInfo.new(0.15), { CFrame = goal }):Play()
end

-- The server sends each state it draws: the session start, and every move reply.
State.OnClientEvent:Connect(function(sent)
	if not Players.LocalPlayer.Character then -- the character first: when it spawns, Roblox resets the camera
		Players.LocalPlayer.CharacterAdded:Wait()
	end
	controls:Disable()
	view, facing = sent, sent.facing or facing
	moves.Text = ("%d move%s"):format(sent.moves, if sent.moves == 1 then "" else "s")
	say(
		status,
		if sent.state.status == "caught"
			then "Caught!"
			elseif sent.state.status == "escaped" then "You escaped!"
			else ""
	)
	hud.Visible = true
	aim()
end)

-- Show why: the server Script sets the ShowWhy attribute (the caption) while it runs, and ShowWhyTurn
-- on a rigged maze. While it runs the camera looks down on the maze; when it stops, first person.
local me = Players.LocalPlayer
local function whyChanged()
	local shown = me:GetAttribute("ShowWhy")
	say(caption, shown or "")
	say(turn, me:GetAttribute("ShowWhyTurn") or "")
	showWhy.Text = if shown then "Stop" else "Show why"
	mapView = shown ~= nil
	if view then
		aim()
	end
end
me:GetAttributeChangedSignal("ShowWhy"):Connect(whyChanged)
me:GetAttributeChangedSignal("ShowWhyTurn"):Connect(function()
	say(turn, me:GetAttribute("ShowWhyTurn") or "")
end)
whyChanged()
showWhy.Activated:Connect(function()
	local reply = Coordinator:InvokeServer("showwhy") -- on a fair maze, returns when the replay ends
	if reply then
		say(message, reply.note or "")
	end
end)

-- One key: W steps along the facing, A, D, and S turn, Space waits, R restarts, M switches the
-- map view. The server Script drops a move while another is in flight. While Show why runs, any
-- game key only stops it.
local function press(key)
	if me:GetAttribute("ShowWhy") then
		task.spawn(Coordinator.InvokeServer, Coordinator, "showwhy", "stop")
		return
	end
	if not view or (view.state.status ~= "playing" and key ~= Enum.KeyCode.R) then
		return -- after caught or escaped only R works, as on the web page
	end
	if key == Enum.KeyCode.M then
		mapView = not mapView
		aim()
	elseif TURN[key] then
		facing = ORDER[(table.find(ORDER, facing) - 1 + TURN[key]) % 4 + 1]
		aim()
	else
		local name = SEND[key] or facing
		task.spawn(function() -- InvokeServer waits for the reply, and a key handler must not wait
			local reply = Coordinator:InvokeServer("act", name)
			if reply then
				say(message, reply.note or "")
			end
		end)
	end
end
-- Above the default bindings, so Space never jumps. The arrows do the same as W, A, S, D.
ContextActionService:BindActionAtPriority("Maze", function(_, inputState, input)
	if inputState == Enum.UserInputState.Begin then
		press(input.KeyCode)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.A, Enum.KeyCode.Left,
	Enum.KeyCode.S, Enum.KeyCode.Down, Enum.KeyCode.D, Enum.KeyCode.Right, Enum.KeyCode.Space, Enum.KeyCode.R, Enum.KeyCode.M)
waitButton.Activated:Connect(function()
	press(Enum.KeyCode.Space)
end)
restartButton.Activated:Connect(function()
	press(Enum.KeyCode.R)
end)

-- The list opens when the coordinator first answers (the server Script's status loop).
while ReplicatedStorage:GetAttribute("CoordinatorStatus") ~= "Coordinator ready" do
	ReplicatedStorage:GetAttributeChangedSignal("CoordinatorStatus"):Wait()
end
openList()
