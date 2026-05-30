-- World.luau — runtime scene setup.
--   * Arena shell (Workspace.Arena.Shell): parametric geometry built from
--     ARENA_RADIUS — walls, ceiling, track, pillars, neon ring, boundary.
--   * Lobby signs (RulesSign, MatchStatusSign): attach SurfaceGui + labels.
--     The Parts live in the .rbxl; we just wire up the UI here because Rojo
--     UDim2 serialization in JSON is painful.
--   * Lobby ambient particles: subtle floating motes.
-- Lobby shell + decor itself lives in the .rbxl, edited visually in Studio.
-- Marketplace props must be pre-anchored in Studio (no runtime anchor pass)
-- — otherwise legacy Welds drop sub-parts at Play.
-- See ROBLOX_PLAYBOOK.md section 4 for the JSON vs code vs .rbxl decision matrix.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local ARENA_RADIUS = Config.ARENA_RADIUS
local ARENA_WALL_HEIGHT = Config.ARENA_WALL_HEIGHT
local ARENA_TRACK_RADIUS = Config.ARENA_TRACK_RADIUS
local ARENA_PILLAR_RADIUS = Config.ARENA_PILLAR_RADIUS
local ARENA_NEON_RADIUS = Config.ARENA_NEON_RADIUS
local DEFAULT_TRACK_COLOR = Config.DEFAULT_TRACK_COLOR

local SIGN_RULES = {
	"Music ON: you orbit chairs (no control)",
	"Music STOPS: run and press E to sit",
	"Last player without a chair is eliminated",
	"Rounds 2+ add events: ice, fog, mud, lights",
}

local matchStatusValue = nil

local function buildArena()
	-- Build the arena shell from code so it all derives from ARENA_RADIUS (see
	-- Config). default.project.json can't compute these relationships, so the
	-- walls/ceiling/floor/pillars/neon would otherwise be a dozen hand-synced
	-- numbers. Resizing the ring = change Config.ARENA_RADIUS, nothing else.
	local R = ARENA_RADIUS
	local H = ARENA_WALL_HEIGHT
	local span = R * 2

	local function makePart(name, parent, props)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Locked = true
		for key, value in props do
			part[key] = value
		end
		part.Parent = parent
		return part
	end

	-- Arena folder holds everything in the playing area: Shell (track, walls,
	-- ceiling, lights, ring boundary) and Decor (DiscoBall + chairs).
	-- The Folder is declared in default.project.json with $ignoreUnknownInstances,
	-- so we just findOrCreate it here.
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then
		arena = Instance.new("Folder")
		arena.Name = "Arena"
		arena.Parent = Workspace
	end

	-- migration cleanup: prior structure put Track and Room directly under Workspace.
	-- delete any leftovers from old .rbxl snapshots so we don't end up with duplicates.
	local oldTrack = Workspace:FindFirstChild("Track")
	if oldTrack then
		oldTrack:Destroy()
	end
	local oldRoom = Workspace:FindFirstChild("Room")
	if oldRoom then
		oldRoom:Destroy()
	end

	-- Shell holds the arena geometry (rebuilt every startup from ARENA_RADIUS).
	local existingShell = arena:FindFirstChild("Shell")
	if existingShell then
		existingShell:Destroy()
	end
	local shell = Instance.new("Folder")
	shell.Name = "Shell"
	shell.Parent = arena

	-- floor disc: the cylinder players orbit over and chairs sit on. referenced
	-- by the ice event via Workspace.Arena.Shell.Track.
	makePart("Track", shell, {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Plastic,
		Color = DEFAULT_TRACK_COLOR,
		Orientation = Vector3.new(0, 0, 90),
		Position = Vector3.new(0, 0.25, 0),
		Size = Vector3.new(0.5, ARENA_TRACK_RADIUS * 2, ARENA_TRACK_RADIUS * 2),
	})

	-- ceiling
	makePart("Ceiling", shell, {
		Material = Enum.Material.Concrete,
		Color = Color3.new(0.07, 0.06, 0.1),
		Position = Vector3.new(0, H, 0),
		Size = Vector3.new(span, 1, span),
	})

	-- center light (referenced by the flickering event via Arena.Shell.CenterLight)
	local centerLight = makePart("CenterLight", shell, {
		CanCollide = false,
		Transparency = 1,
		Position = Vector3.new(0, H * 0.8, 0),
		Size = Vector3.new(1, 1, 1),
	})
	local pointLight = Instance.new("PointLight")
	pointLight.Name = "Light"
	pointLight.Brightness = 3
	pointLight.Range = R * 1.15
	pointLight.Color = Color3.new(1, 0.95, 0.85)
	pointLight.Shadows = true
	pointLight.Parent = centerLight

	-- four walls + a neon strip along the top of each
	local wallColor = Color3.new(0.15, 0.1, 0.2)
	local neonColor = Color3.fromRGB(255, 140, 50)
	local walls = {
		{ name = "North", pos = Vector3.new(0, H / 2, R), size = Vector3.new(span, H, 1) },
		{ name = "South", pos = Vector3.new(0, H / 2, -R), size = Vector3.new(span, H, 1) },
		{ name = "East", pos = Vector3.new(R, H / 2, 0), size = Vector3.new(1, H, span) },
		{ name = "West", pos = Vector3.new(-R, H / 2, 0), size = Vector3.new(1, H, span) },
	}
	for _, wall in walls do
		makePart("Wall" .. wall.name, shell, {
			Material = Enum.Material.Brick,
			Color = wallColor,
			Position = wall.pos,
			Size = wall.size,
		})
	end
	local neonY = H - 3
	local neonStrips = {
		{ name = "North", pos = Vector3.new(0, neonY, ARENA_NEON_RADIUS), size = Vector3.new(span - 2, 0.4, 0.2) },
		{ name = "South", pos = Vector3.new(0, neonY, -ARENA_NEON_RADIUS), size = Vector3.new(span - 2, 0.4, 0.2) },
		{ name = "East", pos = Vector3.new(ARENA_NEON_RADIUS, neonY, 0), size = Vector3.new(0.2, 0.4, span - 2) },
		{ name = "West", pos = Vector3.new(-ARENA_NEON_RADIUS, neonY, 0), size = Vector3.new(0.2, 0.4, span - 2) },
	}
	for _, strip in neonStrips do
		makePart("NeonStrip" .. strip.name, shell, {
			CanCollide = false,
			Material = Enum.Material.Neon,
			Color = neonColor,
			Position = strip.pos,
			Size = strip.size,
		})
	end

	-- corner pillars (alternating cyan / magenta) with a matching glow
	local cyan = Color3.fromRGB(102, 230, 255)
	local magenta = Color3.fromRGB(255, 102, 217)
	local P = ARENA_PILLAR_RADIUS
	local pillars = {
		{ name = "NE", pos = Vector3.new(P, H / 2, P), color = cyan },
		{ name = "NW", pos = Vector3.new(-P, H / 2, P), color = magenta },
		{ name = "SE", pos = Vector3.new(P, H / 2, -P), color = magenta },
		{ name = "SW", pos = Vector3.new(-P, H / 2, -P), color = cyan },
	}
	for _, pillar in pillars do
		local part = makePart("Pillar" .. pillar.name, shell, {
			Material = Enum.Material.Neon,
			Color = pillar.color,
			Position = pillar.pos,
			Size = Vector3.new(2, H, 2),
		})
		local glow = Instance.new("PointLight")
		glow.Name = "Glow"
		glow.Brightness = 2
		glow.Range = 25
		glow.Color = pillar.color
		glow.Shadows = false
		glow.Parent = part
	end

	-- neon ring + invisible wall around the edge of the play floor. the ring is
	-- a visible boundary marker; the wall physically confines active players to
	-- the circle (spectators sit outside it, frozen, so they're unaffected).
	-- both are approximated as N short straight segments following the tangent.
	local ringRadius = ARENA_TRACK_RADIUS
	local segments = 48
	local segLength = (2 * math.pi * ringRadius / segments) * 1.05 -- slight overlap, no gaps
	local boundary = Instance.new("Folder")
	boundary.Name = "PlayBoundary"
	boundary.Parent = shell
	for i = 1, segments do
		local angle = (i - 1) * (math.pi * 2 / segments)
		local base = Vector3.new(math.cos(angle) * ringRadius, 0, math.sin(angle) * ringRadius)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		-- visible neon strip at floor level
		local neonPos = base + Vector3.new(0, 0.6, 0)
		makePart("RingNeon" .. i, boundary, {
			CanCollide = false,
			Material = Enum.Material.Neon,
			Color = neonColor,
			Size = Vector3.new(0.3, 0.5, segLength),
			CFrame = CFrame.lookAt(neonPos, neonPos + tangent),
		})
		-- invisible wall that blocks active players from leaving the circle
		local wallPos = base + Vector3.new(0, 6, 0)
		makePart("RingWall" .. i, boundary, {
			CanCollide = true,
			Transparency = 1,
			Size = Vector3.new(0.5, 12, segLength),
			CFrame = CFrame.lookAt(wallPos, wallPos + tangent),
		})
	end
end

local function setupRulesSign()
	-- the Part `Workspace.Lobby.Signs.RulesSign` is declared in default.project.json.
	-- we attach the SurfaceGui + labels here so we don't have to fight Rojo's
	-- UDim2 serialization in JSON.
	local lobby = Workspace:FindFirstChild("Lobby")
	local signs = lobby and lobby:FindFirstChild("Signs")
	local sign = signs and signs:FindFirstChild("RulesSign")
	if not sign then
		warn("[RulesSign] missing Workspace.Lobby.Signs.RulesSign: skipping setup")
		return
	end
	if sign:FindFirstChildOfClass("SurfaceGui") then
		return -- already set up (e.g. on hot reload)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = sign

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.18, 0)
	title.Position = UDim2.new(0, 0, 0.04, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 215, 0)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.Text = "HOW TO PLAY"
	title.Parent = gui

	local list = Instance.new("Frame")
	list.Name = "RulesList"
	list.Size = UDim2.new(0.92, 0, 0.7, 0)
	list.Position = UDim2.new(0.04, 0, 0.26, 0)
	list.BackgroundTransparency = 1
	list.Parent = gui

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 14)
	listLayout.Parent = list

	for index, ruleText in SIGN_RULES do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 70)
		row.BackgroundTransparency = 1
		row.LayoutOrder = index
		row.Parent = list

		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.new(0, 60, 0, 60)
		badge.Position = UDim2.new(0, 0, 0.5, 0)
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
		badge.TextColor3 = Color3.fromRGB(20, 16, 0)
		badge.TextScaled = true
		badge.Font = Enum.Font.GothamBlack
		badge.Text = tostring(index)
		badge.Parent = row

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 12)
		badgeCorner.Parent = badge

		local ruleLabel = Instance.new("TextLabel")
		ruleLabel.Size = UDim2.new(1, -80, 1, 0)
		ruleLabel.Position = UDim2.new(0, 80, 0, 0)
		ruleLabel.BackgroundTransparency = 1
		ruleLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
		ruleLabel.TextScaled = true
		ruleLabel.TextWrapped = true
		ruleLabel.TextXAlignment = Enum.TextXAlignment.Left
		ruleLabel.TextYAlignment = Enum.TextYAlignment.Center
		ruleLabel.Font = Enum.Font.Gotham
		ruleLabel.Text = ruleText
		ruleLabel.Parent = row
	end
end

local function setupLobbyAmbientParticles()
	-- subtle floating motes drifting down from the ceiling. uses default
	-- texture (white square) — no external asset required.
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return
	end
	if lobby:FindFirstChild("AmbientParticles") then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "AmbientParticles"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(70, 1, 70)
	anchor.Position = Vector3.new(0, 20, -200)
	anchor.Parent = lobby

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 6
	emitter.Lifetime = NumberRange.new(8, 14)
	emitter.Speed = NumberRange.new(0.6, 1.2)
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 200, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 160, 240)),
	})
	emitter.LightEmission = 0.6
	emitter.Acceleration = Vector3.new(0, -0.3, 0)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Parent = anchor
end

local function setupMatchStatusSign()
	-- live status board on the south wall of the lobby; updated via
	-- World.updateMatchStatus as the game state changes (waiting/warmup/in-match).
	-- the Part itself lives in the .rbxl (user-placed), expected under Lobby.Signs.
	local lobby = Workspace:FindFirstChild("Lobby")
	local signs = lobby and lobby:FindFirstChild("Signs")
	local sign = signs and signs:FindFirstChild("MatchStatusSign")
	if not sign then
		warn("[MatchStatusSign] missing Workspace.Lobby.Signs.MatchStatusSign: skipping setup (move it into Lobby/Signs in Studio)")
		return
	end
	if sign:FindFirstChildOfClass("SurfaceGui") then
		matchStatusValue = sign.SurfaceGui:FindFirstChild("Value")
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	-- the sign is on the south wall; the face that points back toward the
	-- center of the lobby is Back (+Z local), since the part is unrotated.
	gui.Face = Enum.NormalId.Back
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = sign

	local headline = Instance.new("TextLabel")
	headline.Name = "Headline"
	headline.Size = UDim2.new(1, 0, 0.32, 0)
	headline.Position = UDim2.new(0, 0, 0.08, 0)
	headline.BackgroundTransparency = 1
	headline.TextColor3 = Color3.fromRGB(200, 200, 200)
	headline.TextScaled = true
	headline.Font = Enum.Font.Gotham
	headline.Text = "MATCH STATUS"
	headline.Parent = gui

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Size = UDim2.new(0.92, 0, 0.55, 0)
	value.Position = UDim2.new(0.04, 0, 0.4, 0)
	value.BackgroundTransparency = 1
	value.TextColor3 = Color3.fromRGB(255, 215, 0)
	value.TextScaled = true
	value.Font = Enum.Font.GothamBlack
	value.Text = "—"
	value.Parent = gui

	matchStatusValue = value
end

local World = {}

function World.build()
	buildArena()
	setupRulesSign()
	setupLobbyAmbientParticles()
	setupMatchStatusSign()
end

function World.updateMatchStatus(text)
	if matchStatusValue then
		matchStatusValue.Text = text
	end
end

return World
