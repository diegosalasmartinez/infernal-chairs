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

-- Local aliases so the rest of the file stays readable (avoid Config.FOO repetition).
-- Match cadence
local MIN_PLAYERS = Config.MIN_PLAYERS
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
local eventState = {}
local walkSpeedOverride = nil
local jumpDisabled = false -- when true, thaw() leaves jump kill-switched on

local function log(phase, message)
	print(string.format("[GameLoop:%s] %s", phase, message))
end

local function broadcast(phase, message, sub, duration)
	StateChanged:FireAllClients({
		phase = phase,
		message = message,
		sub = sub,
		duration = duration,
		event = activeEvent,
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
		warn("[Chairs] ReplicatedStorage.Templates.Chair missing — check assets/chair.rbxm")
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
		warn(string.format("[Chairs] expected Model, got %s — fix assets/chair.rbxm", template.ClassName))
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

cloneChairsFromTemplate()
setupChairModels()
setupChairPrompts()

-- ===== Round events =====
-- Each event has optional hooks: onPlayingStart, onStoppedStart, onRoundEnd.
-- activeEvent is picked at the start of each round (rounds 2+). cleanup runs
-- onRoundEnd; do not leak state between rounds.

local function getCenterPointLight()
	local part = Workspace:FindFirstChild("Room") and Workspace.Room:FindFirstChild("CenterLight")
	return part and part:FindFirstChildOfClass("PointLight")
end

local EVENTS = {
	flickering = {
		name = "FLICKERING LIGHTS",
		onPlayingStart = function()
			local light = getCenterPointLight()
			if not light then
				return
			end
			-- snapshot the ambient lighting state so we can swing the whole room
			-- to near-pitch-black on the OFF cycle and restore on cleanup.
			eventState.flickering = {
				running = true,
				origAmbient = Lighting.Ambient,
				origOutdoorAmbient = Lighting.OutdoorAmbient,
				origBrightness = Lighting.Brightness,
			}
			local state = eventState.flickering
			task.spawn(function()
				while state.running do
					-- OFF: kill the point light AND drop room ambient to almost zero
					light.Enabled = false
					Lighting.Ambient = Color3.new(0, 0, 0)
					Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
					Lighting.Brightness = 0
					task.wait(2.5 + math.random() * 1) -- 2.5-3.5s OFF
					if not state.running then
						break
					end
					-- ON: restore everything
					light.Enabled = true
					Lighting.Ambient = state.origAmbient
					Lighting.OutdoorAmbient = state.origOutdoorAmbient
					Lighting.Brightness = state.origBrightness
					task.wait(0.8 + math.random() * 0.4) -- 0.8-1.2s ON
				end
			end)
		end,
		onRoundEnd = function()
			local state = eventState.flickering
			if state then
				state.running = false
				Lighting.Ambient = state.origAmbient
				Lighting.OutdoorAmbient = state.origOutdoorAmbient
				Lighting.Brightness = state.origBrightness
				eventState.flickering = nil
			end
			local light = getCenterPointLight()
			if light then
				light.Enabled = true
			end
		end,
	},
	ice = {
		name = "ICE FLOOR",
		-- Friction=0 + FrictionWeight=1000 gives effective friction ≈ 0.0003 against
		-- the character — practically frictionless. Also disable jump so players
		-- can't escape the slide, and raise WalkSpeed for more skidding momentum.
		onPlayingStart = function()
			local track = Workspace:FindFirstChild("Track")
			if track then
				track.Material = Enum.Material.Ice
				track.Color = ICE_TRACK_COLOR
				track.CustomPhysicalProperties = PhysicalProperties.new(0.919, 0, 0.15, 1000, 1)
			end
			walkSpeedOverride = ICE_WALK_SPEED
			jumpDisabled = true
		end,
		onRoundEnd = function()
			local track = Workspace:FindFirstChild("Track")
			if track then
				track.Material = Enum.Material.Plastic
				track.Color = DEFAULT_TRACK_COLOR
				track.CustomPhysicalProperties = nil
			end
			walkSpeedOverride = nil
			jumpDisabled = false
		end,
	},
	mud = {
		name = "MUD FLOOR",
		onPlayingStart = function()
			local data = { patches = {}, conn = nil, onMudLast = {} }
			eventState.mud = data
			-- spawn many varied mud patches scattered across the running area.
			-- players see them during orbit and have to plan a path through.
			for _ = 1, MUD_PATCH_COUNT do
				local angle = math.random() * math.pi * 2
				local radius = MUD_PATCH_RING_MIN + math.random() * (MUD_PATCH_RING_MAX - MUD_PATCH_RING_MIN)
				local patchRadius = MUD_PATCH_MIN_RADIUS + math.random() * (MUD_PATCH_MAX_RADIUS - MUD_PATCH_MIN_RADIUS)
				local diameter = patchRadius * 2
				local patch = Instance.new("Part")
				patch.Name = "MudPatch"
				patch.Anchored = true
				patch.CanCollide = false
				patch.Shape = Enum.PartType.Cylinder
				patch.Size = Vector3.new(0.2, diameter, diameter)
				patch.Material = Enum.Material.Slate
				patch.Color = Color3.new(0.22, 0.16, 0.1)
				patch.CFrame = CFrame.new(math.cos(angle) * radius, 0.6, math.sin(angle) * radius)
					* CFrame.Angles(0, 0, math.rad(90))
				patch:SetAttribute("Radius", patchRadius)
				patch.Parent = Workspace
				table.insert(data.patches, patch)
			end
			-- per-frame: if player is inside any mud patch -> SLOW, else DEFAULT.
			-- transitions only when crossing a boundary (no per-frame WalkSpeed writes).
			data.conn = RunService.Heartbeat:Connect(function()
				local current = eventState.mud
				if not current then
					return
				end
				for player in activePlayers do
					if not lockedToChair[player] then
						local character = player.Character
						local root = character and character:FindFirstChild("HumanoidRootPart")
						if root then
							local onMud = false
							for _, patch in current.patches do
								local r = patch:GetAttribute("Radius") or MUD_PATCH_MIN_RADIUS
								local dx = root.Position.X - patch.Position.X
								local dz = root.Position.Z - patch.Position.Z
								if dx * dx + dz * dz < r * r then
									onMud = true
									break
								end
							end
							if current.onMudLast[player] ~= onMud then
								current.onMudLast[player] = onMud
								local _, humanoid = getCharacterParts(player)
								if humanoid and humanoid.WalkSpeed > 0 then
									humanoid.WalkSpeed = onMud and SLOW_FLOOR_WALK_SPEED or DEFAULT_WALK_SPEED
								end
							end
						end
					end
				end
			end)
		end,
		onRoundEnd = function()
			local data = eventState.mud
			if not data then
				return
			end
			if data.conn then
				data.conn:Disconnect()
			end
			for _, patch in data.patches do
				patch:Destroy()
			end
			for player in activePlayers do
				local _, humanoid = getCharacterParts(player)
				if humanoid and humanoid.WalkSpeed > 0 then
					humanoid.WalkSpeed = DEFAULT_WALK_SPEED
				end
			end
			eventState.mud = nil
		end,
	},
	fog = {
		name = "FOG",
		onPlayingStart = function()
			local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
			if not atmosphere then
				return
			end
			-- snapshot the atmosphere so we can restore exact values on cleanup
			eventState.fog = {
				origDensity = atmosphere.Density,
				origOffset = atmosphere.Offset,
				origColor = atmosphere.Color,
				origDecay = atmosphere.Decay,
				origGlare = atmosphere.Glare,
				origHaze = atmosphere.Haze,
			}
			-- thick yellowish-grey fog. high density obscures distant chairs; haze
			-- makes the air itself murky.
			atmosphere.Density = 0.85
			atmosphere.Offset = 0.25
			atmosphere.Color = Color3.new(0.45, 0.4, 0.35)
			atmosphere.Decay = Color3.new(0.4, 0.4, 0.45)
			atmosphere.Glare = 0
			atmosphere.Haze = 5
		end,
		onRoundEnd = function()
			local state = eventState.fog
			local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
			if atmosphere and state then
				atmosphere.Density = state.origDensity
				atmosphere.Offset = state.origOffset
				atmosphere.Color = state.origColor
				atmosphere.Decay = state.origDecay
				atmosphere.Glare = state.origGlare
				atmosphere.Haze = state.origHaze
			end
			eventState.fog = nil
		end,
	},
}

local EVENT_KEYS = { "flickering", "ice", "mud", "fog" }

local function runEventHook(name)
	local ev = activeEvent and EVENTS[activeEvent]
	if ev and ev[name] then
		ev[name]()
	end
end

local function pickRandomEvent()
	return EVENT_KEYS[math.random(#EVENT_KEYS)]
end

local function waitForEnoughPlayers()
	while #Players:GetPlayers() < MIN_PLAYERS do
		task.wait(1)
	end
end

local function startMatch()
	matchInProgress = true
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
	local roundNumber = 0

	while countActive() > 1 do
		roundNumber += 1
		-- cleanup previous round's event + welds. round 1 has no event to clean.
		runEventHook("onRoundEnd")
		activeEvent = nil
		releaseSits()

		-- round 1 is always normal; rounds 2+ pick a random event.
		if roundNumber > 1 then
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
		broadcast("Playing", "MUSIC ON — KEEP MOVING", string.format("%d players left", countActive()), musicDuration)
		freezeAllActives()
		startOrbiting()
		runEventHook("onPlayingStart")
		PlayMusic:FireAllClients()
		task.wait(musicDuration)

		log("Stopped", string.format("sit now (%ds grace)", SIT_GRACE_SECS))
		local stoppedSub = eventLabel and (eventLabel .. " — press E to sit") or "press E near a chair"
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
	stopOrbiting()
	releaseSits()
	thawAllActives()
	matchInProgress = false
	thawAllSpectators()

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
