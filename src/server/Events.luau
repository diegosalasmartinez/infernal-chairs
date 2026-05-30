-- Round events (modifiers applied on rounds 2+). Extracted from init.server so
-- the main loop stays readable. Each event is a table of optional hooks:
-- onPlayingStart, onStoppedStart, onRoundEnd. The active event is picked per
-- round; cleanup runs in onRoundEnd — do not leak state between rounds.
--
-- This module is a FACTORY: init.server calls `create(ctx)` passing a context
-- that bridges the shared state events need. Stable tables (activePlayers,
-- lockedToChair) are passed by reference (init mutates them in place, never
-- reassigns). Scalars that live in init and are read elsewhere
-- (walkSpeedOverride, jumpDisabled — read by thaw()) are written through
-- setter closures so the source of truth stays in init.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local ICE_TRACK_COLOR = Config.ICE_TRACK_COLOR
local ICE_WALK_SPEED = Config.ICE_WALK_SPEED
local DEFAULT_TRACK_COLOR = Config.DEFAULT_TRACK_COLOR
local DEFAULT_WALK_SPEED = Config.DEFAULT_WALK_SPEED
local SLOW_FLOOR_WALK_SPEED = Config.SLOW_FLOOR_WALK_SPEED
local MUD_PATCH_COUNT = Config.MUD_PATCH_COUNT
local MUD_PATCH_MIN_RADIUS = Config.MUD_PATCH_MIN_RADIUS
local MUD_PATCH_MAX_RADIUS = Config.MUD_PATCH_MAX_RADIUS
local MUD_PATCH_RING_MIN = Config.MUD_PATCH_RING_MIN
local MUD_PATCH_RING_MAX = Config.MUD_PATCH_RING_MAX

local function getArenaShell()
	local arena = Workspace:FindFirstChild("Arena")
	return arena and arena:FindFirstChild("Shell")
end

local function getCenterPointLight()
	local shell = getArenaShell()
	local part = shell and shell:FindFirstChild("CenterLight")
	return part and part:FindFirstChildOfClass("PointLight")
end

local function getTrack()
	local shell = getArenaShell()
	return shell and shell:FindFirstChild("Track")
end

local EVENT_KEYS = { "flickering", "ice", "mud", "fog" }

local function create(ctx)
	-- ctx = {
	--   activePlayers     : table   (stable ref, mutated in place by init)
	--   lockedToChair     : table   (stable ref)
	--   getCharacterParts : (player) -> root, humanoid
	--   setWalkSpeedOverride : (value | nil) -> ()   -- thaw() reads it in init
	--   setJumpDisabled      : (boolean) -> ()       -- thaw() reads it in init
	-- }
	local activePlayers = ctx.activePlayers
	local lockedToChair = ctx.lockedToChair
	local getCharacterParts = ctx.getCharacterParts

	local eventState = {} -- private per-event scratch state

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
				local track = getTrack()
				if track then
					track.Material = Enum.Material.Ice
					track.Color = ICE_TRACK_COLOR
					track.CustomPhysicalProperties = PhysicalProperties.new(0.919, 0, 0.15, 1000, 1)
				end
				ctx.setWalkSpeedOverride(ICE_WALK_SPEED)
				ctx.setJumpDisabled(true)
			end,
			onRoundEnd = function()
				local track = getTrack()
				if track then
					track.Material = Enum.Material.Plastic
					track.Color = DEFAULT_TRACK_COLOR
					track.CustomPhysicalProperties = nil
				end
				ctx.setWalkSpeedOverride(nil)
				ctx.setJumpDisabled(false)
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
					local patchRadius = MUD_PATCH_MIN_RADIUS
						+ math.random() * (MUD_PATCH_MAX_RADIUS - MUD_PATCH_MIN_RADIUS)
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
			-- Purely cosmetic: no gameplay effect, so the visible fog is built
			-- client-side from local smoke particles (see init.client.luau, driven
			-- by StateChanged.event == "fog"). The server only declares the event so
			-- the banner shows "FOG" and the round logic knows it's active. Keeping
			-- it client-side avoids replicating a heavy particle part and leaves the
			-- lobby (and the rest of Lighting) completely untouched.
			name = "FOG",
		},
	}

	return {
		definitions = EVENTS,
		keys = EVENT_KEYS,
	}
end

return create
