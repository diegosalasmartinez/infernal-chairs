local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Events = ReplicatedStorage:WaitForChild("Events")
local PlayMusic = Events:WaitForChild("PlayMusic")
local StopMusic = Events:WaitForChild("StopMusic")
local StateChanged = Events:WaitForChild("StateChanged")
local YouEliminated = Events:WaitForChild("YouEliminated")
local Chairs = Workspace:WaitForChild("Chairs")

local Config = require(script.Config)
local World = require(script.World)
local Decor = require(script.Decor)
local Debris = game:GetService("Debris")

-- Local aliases so the rest of the file stays readable (avoid Config.FOO repetition).
-- Match cadence
local MIN_PLAYERS = Config.MIN_PLAYERS
local LOBBY_WARMUP_SECS = Config.LOBBY_WARMUP_SECS
local INTERMISSION_SECS = Config.INTERMISSION_SECS
local MUSIC_MIN_SECS = Config.MUSIC_MIN_SECS
local MUSIC_MAX_SECS = Config.MUSIC_MAX_SECS
local SIT_GRACE_SECS = Config.SIT_GRACE_SECS
local POST_MATCH_SECS = Config.POST_MATCH_SECS
local VERDICT_PAUSE_SECS = Config.VERDICT_PAUSE_SECS
-- Chair placement
local CHAIR_COUNT = Config.CHAIR_COUNT
local CHAIR_RADIUS_MIN = Config.CHAIR_RADIUS_MIN
local CHAIR_RADIUS_MAX = Config.CHAIR_RADIUS_MAX
local CHAIR_MIN_SEPARATION = Config.CHAIR_MIN_SEPARATION
local CHAIR_PLACEMENT_ATTEMPTS = Config.CHAIR_PLACEMENT_ATTEMPTS
-- Orbit
local ORBIT_RADIUS = Config.ORBIT_RADIUS
local ORBIT_ANGULAR_SPEED = Config.ORBIT_ANGULAR_SPEED
local ORBIT_HEIGHT = Config.ORBIT_HEIGHT
-- Movement defaults
local DEFAULT_WALK_SPEED = Config.DEFAULT_WALK_SPEED
local DEFAULT_JUMP_POWER = Config.DEFAULT_JUMP_POWER
local DEFAULT_JUMP_HEIGHT = Config.DEFAULT_JUMP_HEIGHT
-- Sit
local SIT_PROMPT_DISTANCE = Config.SIT_PROMPT_DISTANCE
-- Spectator
local SPECTATOR_RING_OFFSET_MIN = Config.SPECTATOR_RING_OFFSET_MIN
local SPECTATOR_RING_OFFSET_MAX = Config.SPECTATOR_RING_OFFSET_MAX
local SPECTATOR_HEIGHT = Config.SPECTATOR_HEIGHT
-- Audio / polish
local MUSIC_TRACKS = Config.MUSIC_TRACKS
local LOBBY_MUSIC_TRACKS = Config.LOBBY_MUSIC_TRACKS
-- Debug
local FORCE_EVENT = Config.FORCE_EVENT
-- Arena geometry
local ARENA_RADIUS = Config.ARENA_RADIUS
local ARENA_WALL_HEIGHT = Config.ARENA_WALL_HEIGHT
local ARENA_TRACK_RADIUS = Config.ARENA_TRACK_RADIUS
local ARENA_PILLAR_RADIUS = Config.ARENA_PILLAR_RADIUS
local ARENA_NEON_RADIUS = Config.ARENA_NEON_RADIUS
-- Visual / event constants
local DEFAULT_TRACK_COLOR = Config.DEFAULT_TRACK_COLOR
local ICE_TRACK_COLOR = Config.ICE_TRACK_COLOR
local ICE_WALK_SPEED = Config.ICE_WALK_SPEED
local SLOW_FLOOR_WALK_SPEED = Config.SLOW_FLOOR_WALK_SPEED
local MUD_PATCH_COUNT = Config.MUD_PATCH_COUNT
local MUD_PATCH_MIN_RADIUS = Config.MUD_PATCH_MIN_RADIUS
local MUD_PATCH_MAX_RADIUS = Config.MUD_PATCH_MAX_RADIUS
local MUD_PATCH_RING_MIN = Config.MUD_PATCH_RING_MIN
local MUD_PATCH_RING_MAX = Config.MUD_PATCH_RING_MAX

local activePlayers = {}
local orbitState = {}
local orbitConnection = nil
local lockedToChair = {}
local sitWelds = {}
local sitListeners = {} -- per-player connections that re-seat them if Sit flips false
local matchInProgress = false
local activeEvent = nil
local walkSpeedOverride = nil -- set by the events module (ice); read by thaw()
local jumpDisabled = false -- set by the events module (ice); read by thaw()

local function log(phase, message)
	print(string.format("[GameLoop:%s] %s", phase, message))
end

local lastBroadcastEvent = nil
local function broadcast(phase, message, sub, duration)
	-- eventChanged tells the client to animate the banner when an event newly
	-- appears (or disappears). cleared back to nil between matches in the reset path.
	local eventChanged = activeEvent ~= lastBroadcastEvent
	lastBroadcastEvent = activeEvent
	StateChanged:FireAllClients({
		phase = phase,
		message = message,
		sub = sub,
		duration = duration,
		event = activeEvent,
		eventChanged = eventChanged,
	})
end

local function countActive()
	local n = 0
	for _ in activePlayers do
		n += 1
	end
	return n
end

local function allChairs()
	-- each chair is a Model containing a Seat + decorative Parts. we return
	-- the Seat instances so callers can still use chair:Sit(), chair.Transparency etc.
	local out = {}
	for _, chairModel in Chairs:GetChildren() do
		if chairModel:IsA("Model") then
			local seat = chairModel:FindFirstChildOfClass("Seat")
			if seat then
				table.insert(out, seat)
			end
		end
	end
	return out
end

local function cloneChairsFromTemplate()
	-- the chair Model is loaded by Rojo from assets/chair.rbxm.
	local templates = ReplicatedStorage:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("Chair")
	if not template then
		warn("[Chairs] ReplicatedStorage.Templates.Chair missing: check assets/chair.rbxm")
		return false
	end
	print(
		string.format(
			"[Chairs] Template: %s (%s, %d descendants)",
			template.Name,
			template.ClassName,
			#template:GetDescendants()
		)
	)
	if not template:IsA("Model") then
		warn(string.format("[Chairs] expected Model, got %s: fix assets/chair.rbxm", template.ClassName))
		return false
	end

	for i = 1, CHAIR_COUNT do
		local chair
		if template:IsA("Model") then
			chair = template:Clone()
		else
			-- defensive: wrap a single-Part template in a Model
			chair = Instance.new("Model")
			local part = template:Clone()
			part.Parent = chair
		end
		chair.Name = "Chair" .. i

		-- chairs are static; force every part to be anchored so they don't fall
		for _, descendant in chair:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end

		-- find the template's Seat; if missing, add an invisible one at the
		-- bounding-box top so chair:Sit() has somewhere to plant the humanoid.
		local seat = chair:FindFirstChildWhichIsA("Seat", true)
		if not seat then
			local cf, size = chair:GetBoundingBox()
			seat = Instance.new("Seat")
			seat.Name = "Seat"
			seat.Anchored = true
			seat.CanCollide = false
			seat.Transparency = 1
			seat.Size = Vector3.new(2, 0.5, 2)
			seat.CFrame = cf * CFrame.new(0, size.Y / 2 - 0.25, 0)
			seat.Parent = chair
		end
		seat.Disabled = true

		chair.PrimaryPart = seat
		chair.Parent = Chairs
	end

	return true
end

local function setupChairModels()
	-- set each chair model's PrimaryPart to its Seat so Model:PivotTo() moves
	-- the whole chair around the seat position.
	for _, chairModel in Chairs:GetChildren() do
		if chairModel:IsA("Model") then
			local seat = chairModel:FindFirstChildOfClass("Seat")
			if seat then
				chairModel.PrimaryPart = seat
			end
		end
	end
end

local function setChairEnabled(chair, enabled)
	-- toggle every BasePart in the chair Model (seat, backrest, legs)
	local model = chair.Parent
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = enabled and 0 or 1
			part.CanCollide = enabled
		end
	end
	-- Seat.Disabled stays true permanently: sitting is gated by the
	-- ProximityPrompt + chair:Sit() flow below.
end

local function pickRandomPositions(count)
	local positions = {}
	local attempts = 0
	while #positions < count and attempts < CHAIR_PLACEMENT_ATTEMPTS do
		attempts += 1
		local angle = math.random() * math.pi * 2
		local radius = math.random(CHAIR_RADIUS_MIN, CHAIR_RADIUS_MAX)
		local candidate = Vector3.new(math.cos(angle) * radius, 2, math.sin(angle) * radius)
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
			chair.Parent:PivotTo(CFrame.new(positions[i]))
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
	-- read from our own lock table instead of Seat.Occupant; the engine clears
	-- Occupant when the player tries to jump, even though our WeldConstraint
	-- still pins them. Trust the lock, not the engine's seat state.
	local seated = {}
	for player, chair in lockedToChair do
		if activePlayers[player] then
			seated[player] = chair
		end
	end
	return seated
end

local function getCharacterParts(player)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil, nil
	end
	return root, humanoid
end

local function freezeAndAssign(player, angle)
	local root, humanoid = getCharacterParts(player)
	if not root or not humanoid then
		log("Orbit", string.format("skip freeze for %s (no character yet)", player.Name))
		return
	end
	-- give server network ownership so the client can't fight our CFrame writes
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	orbitState[player] = { angle = angle }
end

local function thaw(player)
	orbitState[player] = nil
	local root, humanoid = getCharacterParts(player)
	if not root or not humanoid then
		return
	end
	pcall(function()
		root:SetNetworkOwner(player)
	end)
	humanoid.WalkSpeed = walkSpeedOverride or DEFAULT_WALK_SPEED
	if jumpDisabled then
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	else
		humanoid.JumpPower = DEFAULT_JUMP_POWER
		humanoid.JumpHeight = DEFAULT_JUMP_HEIGHT
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end

local function freezeInPlace(player)
	-- like freezeAndAssign but stays where the player is (no orbit). also fully
	-- kills jump (state-level) and zeros velocity so they snap to a stop.
	local root, humanoid = getCharacterParts(player)
	if not root or not humanoid then
		return
	end
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	root.AssemblyLinearVelocity = Vector3.zero
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function freezeAllActivesInPlace()
	for player in activePlayers do
		if not lockedToChair[player] then
			freezeInPlace(player)
		end
	end
end

local function applyOrbit(dt)
	for player, state in orbitState do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			state.angle += ORBIT_ANGULAR_SPEED * dt
			local cos, sin = math.cos(state.angle), math.sin(state.angle)
			local pos = Vector3.new(cos * ORBIT_RADIUS, ORBIT_HEIGHT, sin * ORBIT_RADIUS)
			local tangent = Vector3.new(-sin, 0, cos)
			root.CFrame = CFrame.new(pos, pos + tangent)
		end
	end
end

local function startOrbiting()
	if orbitConnection then
		return
	end
	orbitConnection = RunService.Heartbeat:Connect(applyOrbit)
end

local function stopOrbiting()
	if orbitConnection then
		orbitConnection:Disconnect()
		orbitConnection = nil
	end
end

local function freezeAllActives()
	local players = {}
	for player in activePlayers do
		table.insert(players, player)
	end
	if #players == 0 then
		return
	end
	for i, player in players do
		local angle = (i - 1) * (math.pi * 2 / #players)
		freezeAndAssign(player, angle)
	end
	applyOrbit(0)
end

local function thawAllActives()
	for player in activePlayers do
		thaw(player)
	end
end

local function isChairTaken(chair)
	for _, claimedChair in lockedToChair do
		if claimedChair == chair then
			return true
		end
	end
	return false
end

local function onSitPrompt(player, chair)
	if not activePlayers[player] then
		return
	end
	if lockedToChair[player] then
		return
	end
	if chair.Transparency >= 1 or isChairTaken(chair) then
		return
	end
	local root, humanoid = getCharacterParts(player)
	if not root or not humanoid then
		return
	end
	-- Seat:Sit forces the seating regardless of Seat.Disabled. The engine creates
	-- a SeatWeld and triggers the sit animation. We then layer a WeldConstraint
	-- as a backup so a jump attempt can't physically release them.
	chair:Sit(humanoid)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = chair
	weld.Parent = chair
	sitWelds[player] = weld
	lockedToChair[player] = chair
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.WalkSpeed = 0
	humanoid.AutoJumpEnabled = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	-- if the engine flips Sit to false (jump attempt), snap it back immediately.
	-- without this, the jump animation plays even though the weld holds them.
	sitListeners[player] = humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
		if lockedToChair[player] and not humanoid.Sit then
			humanoid.Sit = true
		end
	end)
	-- claim the chair: nobody else can sit here this round
	local prompt = chair:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end
end

local function setupChairPrompts()
	for _, chair in allChairs() do
		if chair:FindFirstChildOfClass("ProximityPrompt") then
			continue
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SitPrompt"
		prompt.ActionText = "Sit"
		prompt.ObjectText = ""
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = SIT_PROMPT_DISTANCE
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = chair
		prompt.Triggered:Connect(function(player)
			onSitPrompt(player, chair)
		end)
	end
end

local function enableSittingPrompts()
	for _, chair in allChairs() do
		local prompt = chair:FindFirstChildOfClass("ProximityPrompt")
		if prompt and chair.Transparency < 1 then
			prompt.Enabled = true
		end
	end
end

local function disableAllPrompts()
	for _, chair in allChairs() do
		local prompt = chair:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end
	end
end

local function releaseSits()
	for player, conn in sitListeners do
		conn:Disconnect()
	end
	table.clear(sitListeners)
	for player, weld in sitWelds do
		weld:Destroy()
		local _, humanoid = getCharacterParts(player)
		if humanoid then
			humanoid.JumpPower = DEFAULT_JUMP_POWER
			humanoid.JumpHeight = DEFAULT_JUMP_HEIGHT
			humanoid.WalkSpeed = DEFAULT_WALK_SPEED
			humanoid.AutoJumpEnabled = true
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			humanoid.Sit = false
		end
	end
	table.clear(sitWelds)
	table.clear(lockedToChair)
	disableAllPrompts()
end

local function isSpectator(player)
	return matchInProgress and not activePlayers[player]
end

local function applySpectatorState(player)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local angle = math.random() * math.pi * 2
	local radius = ORBIT_RADIUS
		+ SPECTATOR_RING_OFFSET_MIN
		+ math.random() * (SPECTATOR_RING_OFFSET_MAX - SPECTATOR_RING_OFFSET_MIN)
	local pos = Vector3.new(math.cos(angle) * radius, SPECTATOR_HEIGHT, math.sin(angle) * radius)
	root.CFrame = CFrame.lookAt(pos, Vector3.new(0, SPECTATOR_HEIGHT, 0))
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function clearSpectatorState(player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = DEFAULT_WALK_SPEED
	humanoid.JumpPower = DEFAULT_JUMP_POWER
	humanoid.JumpHeight = DEFAULT_JUMP_HEIGHT
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
end

local function thawAllSpectators()
	for _, player in Players:GetPlayers() do
		if not activePlayers[player] then
			clearSpectatorState(player)
		end
	end
end

local function onCharacterAdded(player, character)
	-- the engine respawns at a SpawnLocation; we yank them to the spectator
	-- ring as soon as the root part exists.
	character:WaitForChild("HumanoidRootPart", 5)
	if isSpectator(player) then
		applySpectatorState(player)
		return
	end
	-- if an active player dies mid-match (rare — happens on physics glitches
	-- or external kills since freeze + lock should prevent normal deaths)
	-- their new character spawns at the lobby with default speed. Re-apply
	-- whatever state the current phase expects.
	if matchInProgress and activePlayers[player] then
		if orbitConnection then
			-- mid-Playing: rejoin the orbit at the same angle they had before
			local previousAngle = orbitState[player] and orbitState[player].angle or 0
			freezeAndAssign(player, previousAngle)
		else
			-- post-Playing phases (Stopped/Judgement): apply the active event's
			-- walkspeed override + jump lock via thaw().
			thaw(player)
		end
	end
end

local function cleanupPlayer(player)
	activePlayers[player] = nil
	orbitState[player] = nil
	lockedToChair[player] = nil
	local weld = sitWelds[player]
	if weld then
		weld:Destroy()
		sitWelds[player] = nil
	end
	local conn = sitListeners[player]
	if conn then
		conn:Disconnect()
		sitListeners[player] = nil
	end
end

local function eliminate(player)
	cleanupPlayer(player)
	YouEliminated:FireClient(player)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end
end

Players.PlayerRemoving:Connect(cleanupPlayer)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

World.build()
Decor.build()

cloneChairsFromTemplate()
setupChairModels()
setupChairPrompts()

-- ===== Round events =====
-- Event definitions live in Events.luau. We hand it a context bridging the
-- shared state events read/write: stable tables (activePlayers, lockedToChair)
-- by reference, and the scalars thaw() reads (walkSpeedOverride, jumpDisabled)
-- via setters so init keeps the source of truth.
local createEvents = require(script.Events)
local eventsModule = createEvents({
	activePlayers = activePlayers,
	lockedToChair = lockedToChair,
	getCharacterParts = getCharacterParts,
	setWalkSpeedOverride = function(value)
		walkSpeedOverride = value
	end,
	setJumpDisabled = function(value)
		jumpDisabled = value
	end,
})
local EVENTS = eventsModule.definitions
local EVENT_KEYS = eventsModule.keys

local function runEventHook(name)
	local ev = activeEvent and EVENTS[activeEvent]
	if ev and ev[name] then
		ev[name]()
	end
end

local function pickRandomEvent()
	return EVENT_KEYS[math.random(#EVENT_KEYS)]
end

local function spawnWinnerParticles(player)
	-- emit gold confetti from the winner's root part for POST_MATCH_SECS. uses
	-- no external asset (default white square texture) so it works offline.
	local root = select(1, getCharacterParts(player))
	if not root then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "WinnerConfetti"
	emitter.Rate = 80
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Speed = NumberRange.new(14, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 160, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 200)),
	})
	emitter.LightEmission = 0.5
	emitter.Acceleration = Vector3.new(0, -25, 0)
	emitter.Parent = root
	Debris:AddItem(emitter, POST_MATCH_SECS + 1)
end

local function playLobbyMusic()
	-- empty pool = no lobby music configured yet, skip
	if #LOBBY_MUSIC_TRACKS == 0 then
		return
	end
	local track = LOBBY_MUSIC_TRACKS[math.random(#LOBBY_MUSIC_TRACKS)]
	PlayMusic:FireAllClients(track)
end

local function waitForEnoughPlayers()
	while #Players:GetPlayers() < MIN_PLAYERS do
		local headcount = #Players:GetPlayers()
		-- keep the banner + sign in sync as players join/leave during the wait
		broadcast("Waiting", "WAITING FOR PLAYERS", string.format("%d / %d", headcount, MIN_PLAYERS))
		World.updateMatchStatus(string.format("WAITING FOR PLAYERS  ·  %d / %d", headcount, MIN_PLAYERS))
		task.wait(1)
	end
end

-- After enough players are present, wait LOBBY_WARMUP_SECS while still in the
-- lobby. Players see a "MATCH STARTING IN Xs" countdown. If headcount drops
-- below MIN_PLAYERS at any point, abort the warmup so we don't kick off a
-- match with too few players.
local function runLobbyWarmup()
	if LOBBY_WARMUP_SECS <= 0 then
		return true
	end
	local deadline = os.clock() + LOBBY_WARMUP_SECS
	while os.clock() < deadline do
		local headcount = #Players:GetPlayers()
		if headcount < MIN_PLAYERS then
			log("Warmup", string.format("headcount fell to %d, aborting", headcount))
			return false
		end
		local remaining = math.max(0, deadline - os.clock())
		broadcast(
			"Warmup",
			"MATCH STARTING",
			string.format("%d players ready  ·  starting in %ds", headcount, math.ceil(remaining)),
			remaining
		)
		World.updateMatchStatus(string.format("STARTING IN %ds", math.ceil(remaining)))
		task.wait(1)
	end
	return true
end

local function startMatch()
	matchInProgress = true
	-- clear in place (don't reassign) so references handed to other modules
	-- (e.g. the events module) stay valid across matches
	table.clear(activePlayers)
	for _, player in Players:GetPlayers() do
		activePlayers[player] = true
	end
	log("Match", string.format("starting with %d players", countActive()))
end

while true do
	log("Waiting", string.format("need %d, have %d", MIN_PLAYERS, #Players:GetPlayers()))
	broadcast("Waiting", "WAITING FOR PLAYERS", string.format("%d / %d", #Players:GetPlayers(), MIN_PLAYERS))
	World.updateMatchStatus(string.format("WAITING FOR PLAYERS  ·  %d / %d", #Players:GetPlayers(), MIN_PLAYERS))
	playLobbyMusic()
	waitForEnoughPlayers()
	-- enough players reached; give new joiners a window before starting.
	-- if someone leaves during warmup we go back to Waiting.
	if not runLobbyWarmup() then
		continue
	end
	startMatch()
	World.updateMatchStatus("MATCH IN PROGRESS")
	local roundNumber = 0

	while countActive() > 1 do
		roundNumber += 1
		-- cleanup previous round's event + welds. round 1 has no event to clean.
		runEventHook("onRoundEnd")
		activeEvent = nil
		releaseSits()

		-- round 1 is always normal; rounds 2+ pick a random event.
		-- (FORCE_EVENT overrides both for debugging a specific event.)
		if FORCE_EVENT then
			activeEvent = FORCE_EVENT
		elseif roundNumber > 1 then
			activeEvent = pickRandomEvent()
		end
		local eventLabel = activeEvent and EVENTS[activeEvent].name

		local visibleChairs = math.max(1, countActive() - 1)
		showVisibleChairs(visibleChairs)
		log(
			"Intermission",
			string.format(
				"%d players, %d chairs, %ds break%s",
				countActive(),
				visibleChairs,
				INTERMISSION_SECS,
				activeEvent and (" · event=" .. activeEvent) or ""
			)
		)
		local intermissionSub =
			string.format("%d players · %d chair%s", countActive(), visibleChairs, visibleChairs == 1 and "" or "s")
		if eventLabel then
			intermissionSub = intermissionSub .. " · ★ " .. eventLabel
		end
		broadcast("Intermission", "GET READY", intermissionSub)
		task.wait(INTERMISSION_SECS)

		local musicDuration = math.random(MUSIC_MIN_SECS, MUSIC_MAX_SECS)
		log("Playing", string.format("music ON for %ds", musicDuration))
		broadcast("Playing", "MUSIC ON: KEEP MOVING", string.format("%d players left", countActive()), musicDuration)
		freezeAllActives()
		startOrbiting()
		runEventHook("onPlayingStart")
		local trackId = MUSIC_TRACKS[math.random(#MUSIC_TRACKS)]
		PlayMusic:FireAllClients(trackId)
		task.wait(musicDuration)

		log("Stopped", string.format("sit now (%ds grace)", SIT_GRACE_SECS))
		local stoppedSub = eventLabel and (eventLabel .. ": press E to sit") or "press E near a chair"
		broadcast("Stopped", "SIT NOW!", stoppedSub, SIT_GRACE_SECS)
		stopOrbiting()
		thawAllActives()
		runEventHook("onStoppedStart")
		enableSittingPrompts()
		StopMusic:FireAllClients()

		-- wait up to SIT_GRACE_SECS, but bail early if every visible chair is claimed
		local deadline = os.clock() + SIT_GRACE_SECS
		while os.clock() < deadline do
			local lockedCount = 0
			for _ in lockedToChair do
				lockedCount += 1
			end
			if lockedCount >= visibleChairs then
				log("Stopped", "all chairs claimed, ending round early")
				break
			end
			task.wait(0.15)
		end

		-- verdict pause: nobody moves, nobody can sit anymore. dramatic 2s freeze
		-- before we decide who got eliminated.
		log("Judgement", "freezing for verdict")
		disableAllPrompts()
		freezeAllActivesInPlace()
		broadcast("Judgement", "TIME'S UP", "verdict incoming...")
		task.wait(VERDICT_PAUSE_SECS)

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

	-- match over: tear down any leftover freeze/orbit/sit/event state
	runEventHook("onRoundEnd")
	activeEvent = nil
	lastBroadcastEvent = nil
	stopOrbiting()
	releaseSits()
	thawAllActives()
	matchInProgress = false
	thawAllSpectators()

	if countActive() == 1 then
		local winner = next(activePlayers)
		log("Winner", string.format("*** %s wins! ***", winner.Name))
		broadcast("Winner", "WINNER", winner.Name)
		spawnWinnerParticles(winner)
	else
		log("Winner", "no winner (everyone fell out)")
		broadcast("Winner", "NO WINNER", "nobody made it")
	end

	log("Reset", string.format("next match in %ds", POST_MATCH_SECS))
	broadcast("Reset", "NEXT MATCH", "starting soon...", POST_MATCH_SECS)
	playLobbyMusic()
	hideAllChairs()
	table.clear(activePlayers)
	task.wait(POST_MATCH_SECS)

	-- kill all characters so the engine respawns them via SpawnLocations (which
	-- now live inside Workspace.Lobby). matchInProgress is already false, so
	-- applySpectatorState() won't yank them back to the arena ring.
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end
end
