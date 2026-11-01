-- Shows the coordinator status, the level list, and the claim panel, and sends this
-- client's Output lines to the server Script, which forwards them to build/roblox.log.
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = ReplicatedStorage:WaitForChild("Log")
local Coordinator = ReplicatedStorage:WaitForChild("Coordinator")
LogService.MessageOut:Connect(function(message, messageType)
	Log:FireServer(messageType.Name .. " " .. message)
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
local body = text("Body", 1, panel)
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
			showPanel(Coordinator:InvokeServer("open", level.id))
		end)
	end
	panel.Visible = false
	list.Visible = true
end
levels.Activated:Connect(openList)
play.Activated:Connect(function()
	showPanel(Coordinator:InvokeServer("play"))
end)

-- The list opens when the coordinator first answers (the server Script's status loop).
while ReplicatedStorage:GetAttribute("CoordinatorStatus") ~= "Coordinator ready" do
	ReplicatedStorage:GetAttributeChangedSignal("CoordinatorStatus"):Wait()
end
openList()
