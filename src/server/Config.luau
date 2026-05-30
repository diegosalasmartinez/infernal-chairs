-- Tunable constants for the game loop, geometry, and events.
-- Required by init.server.luau via `require(script.Config)`.

local Config = {}

-- ===== Match cadence =====
Config.MIN_PLAYERS = 3
-- Once MIN_PLAYERS is reached the loop waits LOBBY_WARMUP_SECS extra before
-- starting the match. Gives new joiners a window to land in the lobby
-- instead of being dropped straight into the arena. If headcount falls
-- below MIN_PLAYERS during warmup, the countdown cancels.
Config.LOBBY_WARMUP_SECS = 10
Config.INTERMISSION_SECS = 5
Config.MUSIC_MIN_SECS = 7
Config.MUSIC_MAX_SECS = 15
Config.SIT_GRACE_SECS = 30
Config.POST_MATCH_SECS = 6
Config.VERDICT_PAUSE_SECS = 2

-- ===== Arena geometry (single source of truth) =====
-- Everything about the play space derives from ARENA_RADIUS via the factors
-- below — walls, ceiling, floor disc, orbit ring, chair scatter, pillars and
-- neon strips all scale together, so resizing the ring is a ONE-LINE change
-- (just ARENA_RADIUS). The arena shell is built in code (buildArena in
-- init.server.luau) precisely because default.project.json can't compute
-- these relationships; hand-tuned JSON numbers drift out of sync.
local ARENA_RADIUS = 100 -- center-to-wall distance, studs (was effectively 70)
local ORBIT_RADIUS = ARENA_RADIUS * 0.69 -- players orbit at ~70% of the radius
Config.ARENA_RADIUS = ARENA_RADIUS
Config.ARENA_WALL_HEIGHT = 32
Config.ARENA_TRACK_RADIUS = ARENA_RADIUS * 0.78 -- floor disc the chairs sit on
Config.ARENA_PILLAR_RADIUS = ARENA_RADIUS * 0.92 -- corner pillars, just inside the walls
Config.ARENA_NEON_RADIUS = ARENA_RADIUS * 0.99 -- neon strips hugging the walls

-- ===== Chair placement =====
Config.CHAIR_COUNT = 4
Config.CHAIR_RADIUS_MIN = 0
Config.CHAIR_RADIUS_MAX = math.floor(ARENA_RADIUS * 0.31) -- chairs scatter within the inner ~31%
Config.CHAIR_MIN_SEPARATION = 5
Config.CHAIR_PLACEMENT_ATTEMPTS = 100

-- ===== Orbit (forced rotation during Playing) =====
Config.ORBIT_RADIUS = ORBIT_RADIUS
Config.ORBIT_ANGULAR_SPEED = 0.45
Config.ORBIT_HEIGHT = 3.5 -- track top is at Y=0.5; R15 root sits ~3 studs above feet

-- ===== Movement defaults (restored after orbit/event by thaw) =====
Config.DEFAULT_WALK_SPEED = 16
Config.DEFAULT_JUMP_POWER = 50
Config.DEFAULT_JUMP_HEIGHT = 7.2 -- modern Roblox characters use JumpHeight, not JumpPower

-- ===== Sit (ProximityPrompt) =====
Config.SIT_PROMPT_DISTANCE = 4 -- prompt only fires when essentially touching the chair

-- ===== Spectator ring (relative to ORBIT_RADIUS) =====
Config.SPECTATOR_RING_OFFSET_MIN = 12
Config.SPECTATOR_RING_OFFSET_MAX = 18 -- ORBIT_RADIUS + this stays inside ARENA_RADIUS
Config.SPECTATOR_HEIGHT = 3

-- ===== Visual defaults =====
Config.DEFAULT_TRACK_COLOR = Color3.new(0.4, 0.35, 0.3)

-- ===== Audio =====
-- Music: pool of SoundIds picked at random each match. Add more entries to rotate.
-- The first one is the current music asset (kept for back-compat with default.project.json).
Config.MUSIC_TRACKS = {
	"rbxassetid://127798544476125",
}
-- Lobby music: chill background loop while players wait between matches.
-- Empty list = no lobby music (PlayMusic is just skipped during Waiting/Reset).
Config.LOBBY_MUSIC_TRACKS = {}
-- SFX: paste Marketplace SoundIds here. Empty string = silent (no SFX plays).
-- Suggested: short alarm/siren for STOP, short buzzer/chime for ELIMINATE.
Config.STOP_SFX_ID = ""
Config.ELIMINATE_SFX_ID = ""
Config.STOP_SFX_VOLUME = 1
Config.ELIMINATE_SFX_VOLUME = 1

-- ===== Events =====
-- DEBUG: force a specific event every round (including round 1, which is
-- normally event-free). Set to nil for normal behavior (round 1 normal,
-- rounds 2+ random). Valid values: "flickering", "ice", "mud", "fog".
Config.FORCE_EVENT = nil
-- Ice
Config.ICE_TRACK_COLOR = Color3.fromRGB(128, 187, 219) -- matches Marketplace asset 4902389321 "SlipperyIce" (Pastel Blue)
Config.ICE_WALK_SPEED = 28
-- Mud: many scattered patches cover the running area (out to ~the orbit ring).
-- Count scales with arena area (radius^2) so coverage stays consistent.
Config.SLOW_FLOOR_WALK_SPEED = 6
Config.MUD_PATCH_COUNT = math.floor(28 * (ORBIT_RADIUS / 48) ^ 2)
Config.MUD_PATCH_MIN_RADIUS = 4
Config.MUD_PATCH_MAX_RADIUS = 10
Config.MUD_PATCH_RING_MIN = 6
Config.MUD_PATCH_RING_MAX = ORBIT_RADIUS * 0.95

return Config
