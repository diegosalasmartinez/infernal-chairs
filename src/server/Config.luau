-- Tunable constants for the game loop, geometry, and events.
-- Required by init.server.luau via `require(script.Config)`.

local Config = {}

-- ===== Match cadence =====
Config.MIN_PLAYERS = 2
Config.INTERMISSION_SECS = 5
Config.MUSIC_MIN_SECS = 7
Config.MUSIC_MAX_SECS = 15
Config.SIT_GRACE_SECS = 30
Config.POST_MATCH_SECS = 6
Config.VERDICT_PAUSE_SECS = 2

-- ===== Chair placement =====
Config.CHAIR_COUNT = 4
Config.CHAIR_RADIUS_MIN = 0
Config.CHAIR_RADIUS_MAX = 22
Config.CHAIR_MIN_SEPARATION = 5
Config.CHAIR_PLACEMENT_ATTEMPTS = 100

-- ===== Orbit (forced rotation during Playing) =====
Config.ORBIT_RADIUS = 48
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
Config.SPECTATOR_RING_OFFSET_MAX = 18 -- keep enough margin to room walls at ±70
Config.SPECTATOR_HEIGHT = 3

-- ===== Visual defaults =====
Config.DEFAULT_TRACK_COLOR = Color3.new(0.4, 0.35, 0.3)

-- ===== Events =====
-- Ice
Config.ICE_TRACK_COLOR = Color3.fromRGB(128, 187, 219) -- matches Marketplace asset 4902389321 "SlipperyIce" (Pastel Blue)
Config.ICE_WALK_SPEED = 28
-- Mud: many scattered patches cover ~75% of the running area
Config.SLOW_FLOOR_WALK_SPEED = 6
Config.MUD_PATCH_COUNT = 28
Config.MUD_PATCH_MIN_RADIUS = 4
Config.MUD_PATCH_MAX_RADIUS = 10
Config.MUD_PATCH_RING_MIN = 6
Config.MUD_PATCH_RING_MAX = 45

return Config
