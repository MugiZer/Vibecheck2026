-- The place's only HTTP caller (a LocalScript cannot use HttpService). It asks the
-- coordinator for its status, forwards every Output line to build/roblox.log, and
-- answers the client's level list, claim panel, Play, and moves.
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Grid = require(ReplicatedStorage.Shared.Grid)
local Scene = require(script.Parent.Scene)

local BASE = ServerStorage.CoordinatorUrl.Value -- written by make roblox (ROBLOX_URL)

-- One coordinator request, JSON in and out. Returns the status code and the decoded
-- body (nil if it is not JSON), or nil and the error if encoding or the request failed.
-- timeout: seconds to wait for the reply, 30 if not given.
local function call(method, path, body, timeout)
	local req = {
		Url = BASE .. path,
		Method = method,
		Headers = { ["Content-Type"] = "application/json" },
		Timeout = timeout or 30, -- the first call after a cold start took 11 s
	}
	local ok, res = pcall(function()
		if body then
			req.Body = HttpService:JSONEncode(body) -- throws on text that is not valid UTF-8
		end
		return HttpService:RequestAsync(req)
	end)
	if not ok then
		return nil, tostring(res)
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
	return res.StatusCode, if decoded then data else nil
end

-- Output forwarding: one POST a second. Never print or warn in here, so a failed
-- send cannot make more lines.
local pending = {}
LogService.MessageOut:Connect(function(message, messageType)
	table.insert(pending, "[server] " .. messageType.Name .. " " .. message)
end)
ReplicatedStorage.Log.OnServerEvent:Connect(function(_player, line)
	table.insert(pending, "[client] " .. tostring(line))
end)
task.spawn(function()
	while true do
		task.wait(1)
		if #pending > 0 then
			local lines = pending
			pending = {}
			call("POST", "/api/roblox/log", { lines = lines })
		end
	end
end)

-- The level list, the claim panel, and Play, for the client through the Coordinator
-- RemoteFunction. The client gets only the text it shows; the level detail and the
-- session stay here.
local TAGS = { unwinnable = "rigged", winnable = "fair", ["exactly-one"] = "one shot" } -- as on the web page
-- shortcut: one player per Play Solo session, and sessions are never cleaned up (here or on the coordinator); upgrade when the place is published or has more than one player
local byPlayer = {} -- [player] = { detail = <the open level's detail>, session = { sessionId, seq, artifactId, busy } }

-- The text for a request that did not get a 200: the server's error, or how to start it.
local function why(body)
	return type(body) == "table" and body.error or "Start `make run` in WSL"
end

-- Status: ask until the coordinator answers, every 3 s. On start, and after a move gets no reply.
-- timeout: seconds each ask may take (30 if not given, for Studio's cold start).
local function waitForCoordinator(timeout)
	while true do
		local t0 = DateTime.now().UnixTimestampMillis
		local code, status = call("GET", "/api/status", nil, timeout)
		if code == 200 and status then
			ReplicatedStorage:SetAttribute("CoordinatorStatus", "Coordinator ready")
			print(("[status] coordinator reachable in %d ms (verifier: %s, model: %s)"):format(
				DateTime.now().UnixTimestampMillis - t0,
				status.verifier.why,
				status.model.why
			))
			return
		end
		ReplicatedStorage:SetAttribute("CoordinatorStatus", "Start `make run` in WSL")
		task.wait(3)
	end
end

-- Stands the avatar on cell state.pos and sends the client the state to show. Only the server
-- moves the avatar, and only to the cell the runtime returned.
local function show(player, open, state, moves, facing)
	local variant, character = open.detail.variant, player.Character
	local root = character.HumanoidRootPart
	-- shortcut: R15 height (an R6 avatar stands 2 studs into the floor), add the leg height if the place allows R6
	local at = Grid.toWorld(variant.width, state.pos) + Vector3.new(0, character.Humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(at, at + Grid.FACING.up)
	ReplicatedStorage.State:FireClient(player, {
		state = state,
		moves = moves,
		facing = facing,
		width = variant.width,
		height = variant.height,
	})
end

local ops = {}

function ops.levels()
	local code, levels = call("GET", "/api/artifacts")
	if code ~= 200 then
		return nil, why(levels)
	end
	local out = {}
	for _, a in levels do
		if a.template == "maze" then -- slingshot levels play only on the web page
			local kind = a.template .. (if a.example then " · example" else "")
			table.insert(out, { id = a.id, text = ("%s   [%s] [%s]"):format(a.title, TAGS[a.label] or "custom", kind) })
		end
	end
	return out
end

function ops.open(player, id)
	-- Opening a level leaves the one being played: its session and its maze go.
	byPlayer[player] = nil
	if workspace:FindFirstChild("Maze") then
		workspace.Maze:Destroy()
	end
	if type(id) ~= "string" or not id:match("^[%w_%-]+$") then
		return { text = "no such level" }
	end
	local code, detail = call("GET", "/api/artifacts/" .. id)
	if code ~= 200 then
		return { text = why(detail) }
	end
	byPlayer[player] = { detail = detail }
	local lines = { detail.presentation.title, detail.presentation.story or "", detail.claim }
	if detail.label == nil then -- a web upload: its stored claim says the requirement is "shown below"
		table.insert(lines, "In Roblox the requirement's Lean text is not shown; it is on the web page.")
	end
	table.insert(lines, detail.scope)
	if detail.example then
		table.insert(lines, "Prepared example, checked by lake comparator")
	else -- "Generated by " .. nil would stop the panel
		table.insert(lines, if detail.generatedBy
			then "Generated by " .. detail.generatedBy .. ", checked by lake comparator"
			else "Checked by lake comparator")
		table.insert(lines, "Made by an AI model, may be wrong.")
	end
	local web = detail.template ~= "maze"
	return {
		text = table.concat(lines, "\n\n"),
		play = not web,
		note = if web then "This game plays on the web page for now." else nil,
	}
end

function ops.play(player)
	local open = byPlayer[player]
	-- The GUI shows Play only on an open maze level; any other call gets a note, not an error.
	if not open then
		return { note = "Pick a level first." }
	end
	if open.detail.template ~= "maze" then
		return { note = "This game plays on the web page for now." }
	end
	local code, body = call("POST", "/api/sessions", { artifactId = open.detail.id })
	if byPlayer[player] ~= open then -- the player opened another level while the session started
		return nil
	end
	if code ~= 200 then
		return { note = why(body), play = code ~= 409 } -- 409, a stale level: the server's text, and no Play
	end
	open.session = { sessionId = body.sessionId, seq = body.seq, artifactId = open.detail.id }
	local line = ("[play] session %s on %s: pos %s"):format(
		body.sessionId:sub(1, 6),
		open.detail.presentation.title,
		tostring(body.state.pos)
	)
	print(line)
	Scene.build(open.detail, body.state)

	-- The avatar. Characters do not load by themselves (CharacterAutoLoads is off), so nothing
	-- falls or respawns while the level list is open.
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		player:LoadCharacter()
		humanoid = player.Character:WaitForChild("Humanoid")
	end
	humanoid.WalkSpeed, humanoid.JumpHeight = 0, 0 -- the avatar never walks or jumps by itself
	player.Character:WaitForChild("HumanoidRootPart").Anchored = true -- only the server moves it, to the cell the runtime returned
	show(player, open, body.state, 0, "up")
	return { note = line, playing = true }
end

-- A key press from the client: one move in flight per session, always with the seq from the
-- last reply. A reply moves the avatar and the scene; anything else is a note for the screen.
function ops.act(player, name)
	local open = byPlayer[player]
	local session = open and open.session
	if not session or session.busy or type(name) ~= "string" then
		return nil -- no level playing, or a move is in flight: the key press is dropped
	end
	session.busy = true
	local code, body = call("POST", "/api/sessions/" .. session.sessionId .. "/act", { seq = session.seq, action = name })
	if byPlayer[player] ~= open or open.session ~= session then -- the player left this session while the move was in flight
		session.busy = false
		return nil
	end
	local reply = {}
	if code == 200 then
		session.seq = body.seq
		Scene.update(body.state)
		show(player, open, body.state, body.moves, if name == "reset" then "up" else nil) -- a restart faces up, as Play does
		print(("[move] %s -> pos %s, guards %s, status %s, moves %d"):format(
			name,
			tostring(body.state.pos),
			table.concat(body.state.guards, ","),
			body.state.status,
			body.moves
		))
	elseif code == 409 and type(body) == "table" and body.seq then -- a stale move: take the seq, drop the key press
		session.seq = body.seq
	elseif code == 404 then -- the coordinator restarted and forgot the session: a new one on the same level
		reply = ops.play(player)
		if open.session ~= session then
			reply = { note = "The server restarted; the level starts again." }
		end
	elseif not code then -- no reply: ask until the coordinator answers (one retry loop at a time)
		if ReplicatedStorage:GetAttribute("CoordinatorStatus") == "Coordinator ready" then
			ReplicatedStorage:SetAttribute("CoordinatorStatus", "Start `make run` in WSL")
			-- 5 s per ask: one ask that hangs while the server restarts must not hold up "ready" for 30 s
			task.spawn(waitForCoordinator, 5)
		end
	else -- 400: the runtime refused the move, and the state does not change
		reply = { note = why(body) }
	end
	session.busy = false
	return reply
end

ReplicatedStorage.Coordinator.OnServerInvoke = function(player, op, arg)
	if ops[op] then
		return ops[op](player, arg)
	end
	return nil
end

waitForCoordinator()
