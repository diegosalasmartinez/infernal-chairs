local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Events = ReplicatedStorage:WaitForChild("Events")
local PlayMusic = Events:WaitForChild("PlayMusic")
local StopMusic = Events:WaitForChild("StopMusic")
local StateChanged = Events:WaitForChild("StateChanged")
local YouEliminated = Events:WaitForChild("YouEliminated")
local Chairs = Workspace:WaitForChild("Chairs")

local MIN_PLAYERS = 2
local INTERMISSION_SECS = 5
local MUSIC_MIN_SECS = 5
local MUSIC_MAX_SECS = 12
local SIT_GRACE_SECS = 3
local POST_MATCH_SECS = 6

local CHAIR_RADIUS_MIN = 0
local CHAIR_RADIUS_MAX = 10
local CHAIR_MIN_SEPARATION = 5
local CHAIR_PLACEMENT_ATTEMPTS = 100

local activePlayers = {}

local function log(phase, message)
	print(string.format("[GameLoop:%s] %s", phase, message))
end

local function broadcast(phase, message, sub)
	StateChanged:FireAllClients({ phase = phase, message = message, sub = sub })
end

local function countActive()
	local n = 0
	for _ in activePlayers do
		n += 1
	end
	return n
end

local function allChairs()
	local out = {}
	for _, chair in Chairs:GetChildren() do
		if chair:IsA("Seat") then
			table.insert(out, chair)
		end
	end
	return out
end

local function setChairEnabled(chair, enabled)
	chair.Transparency = enabled and 0 or 1
	chair.CanCollide = enabled
	chair.Disabled = not enabled
end

local function pickRandomPositions(count)
	local positions = {}
	local attempts = 0
	while #positions < count and attempts < CHAIR_PLACEMENT_ATTEMPTS do
		attempts += 1
		local angle = math.random() * math.pi * 2
		local radius = math.random(CHAIR_RADIUS_MIN, CHAIR_RADIUS_MAX)
		local candidate = Vector3.new(math.cos(angle) * radius, 1, math.sin(angle) * radius)
		local ok = true
		for _, existing in positions do
			if (existing - candidate).Magnitude < CHAIR_MIN_SEPARATION then
				ok = false
				break
			end
		end
		if ok then
			table.insert(positions, candidate)
		end
	end
	return positions
end

local function showVisibleChairs(visibleCount)
	local chairs = allChairs()
	local positions = pickRandomPositions(visibleCount)
	for i, chair in chairs do
		local isVisible = i <= visibleCount
		if isVisible and positions[i] then
			chair.Position = positions[i]
		end
		setChairEnabled(chair, isVisible)
	end
end

local function hideAllChairs()
	for _, chair in allChairs() do
		setChairEnabled(chair, false)
	end
end

local function getSeatedActivePlayers()
	local seated = {}
	for _, chair in allChairs() do
		if chair.Occupant and not chair.Disabled then
			local character = chair.Occupant.Parent
			local player = Players:GetPlayerFromCharacter(character)
			if player and activePlayers[player] then
				seated[player] = chair
			end
		end
	end
	return seated
end

local function eliminate(player)
	activePlayers[player] = nil
	YouEliminated:FireClient(player)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	activePlayers[player] = nil
end)

local function waitForEnoughPlayers()
	while #Players:GetPlayers() < MIN_PLAYERS do
		task.wait(1)
	end
end

local function startMatch()
	activePlayers = {}
	for _, player in Players:GetPlayers() do
		activePlayers[player] = true
	end
	log("Match", string.format("starting with %d players", countActive()))
end

while true do
	log("Waiting", string.format("need %d, have %d", MIN_PLAYERS, #Players:GetPlayers()))
	broadcast("Waiting", "WAITING FOR PLAYERS", string.format("%d / %d", #Players:GetPlayers(), MIN_PLAYERS))
	waitForEnoughPlayers()
	startMatch()

	while countActive() > 1 do
		local visibleChairs = math.max(1, countActive() - 1)
		showVisibleChairs(visibleChairs)
		log("Intermission", string.format("%d players, %d chairs, %ds break", countActive(), visibleChairs, INTERMISSION_SECS))
		broadcast(
			"Intermission",
			"GET READY",
			string.format("%d players · %d chair%s", countActive(), visibleChairs, visibleChairs == 1 and "" or "s")
		)
		task.wait(INTERMISSION_SECS)

		local musicDuration = math.random(MUSIC_MIN_SECS, MUSIC_MAX_SECS)
		log("Playing", string.format("music ON for %ds", musicDuration))
		broadcast("Playing", "MUSIC ON — KEEP MOVING", string.format("%d players left", countActive()))
		PlayMusic:FireAllClients()
		task.wait(musicDuration)

		log("Stopped", string.format("sit now (%ds grace)", SIT_GRACE_SECS))
		broadcast("Stopped", "SIT NOW!", "music stopped")
		StopMusic:FireAllClients()
		task.wait(SIT_GRACE_SECS)

		local seated = getSeatedActivePlayers()
		for player, chair in seated do
			log("Eliminate", string.format("  SAFE: %s on %s", player.Name, chair.Name))
		end
		for player in activePlayers do
			if not seated[player] then
				log("Eliminate", string.format("  OUT:  %s", player.Name))
				eliminate(player)
			end
		end
	end

	if countActive() == 1 then
		local winner = next(activePlayers)
		log("Winner", string.format("*** %s wins! ***", winner.Name))
		broadcast("Winner", "WINNER", winner.Name)
	else
		log("Winner", "no winner (everyone fell out)")
		broadcast("Winner", "NO WINNER", "nobody made it")
	end

	log("Reset", string.format("next match in %ds", POST_MATCH_SECS))
	hideAllChairs()
	activePlayers = {}
	task.wait(POST_MATCH_SECS)
end
