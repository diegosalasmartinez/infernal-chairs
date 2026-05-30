-- Client entry point: wires the server's RemoteEvents to the UI (Hud module),
-- music, SFX, and the fog effect. UI construction + logic lives in Hud.luau;
-- this file stays focused on the bridges between server signals and effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Hud = require(script.Hud)

-- Polish: paste real Marketplace SoundIds here (or leave empty for silent SFX).
-- Volume tunable per SFX so you can match levels with the music track.
local STOP_SFX_ID = ""
local ELIMINATE_SFX_ID = ""
local STOP_SFX_VOLUME = 1
local ELIMINATE_SFX_VOLUME = 1

local Events = ReplicatedStorage:WaitForChild("Events")
local PlayMusic = Events:WaitForChild("PlayMusic")
local StopMusic = Events:WaitForChild("StopMusic")
local StateChanged = Events:WaitForChild("StateChanged")
local YouEliminated = Events:WaitForChild("YouEliminated")

local Music = SoundService:WaitForChild("Music")

local function buildSfx(id, volume)
	-- empty id means "no asset configured yet"; we still create the Sound object
	-- so the caller doesn't need to nil-check, but Play() is a no-op below.
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local stopSfx = buildSfx(STOP_SFX_ID, STOP_SFX_VOLUME)
local eliminateSfx = buildSfx(ELIMINATE_SFX_ID, ELIMINATE_SFX_VOLUME)

local function playSfx(sound)
	if sound.SoundId == "" then
		return
	end
	sound:Play()
end

-- Fog event: purely cosmetic, so it's built here on the client (per the
-- project's client-effects pattern) as local smoke particles confined to the
-- arena volume. Local = no network replication of a heavy particle part, and
-- the lobby + global Lighting stay untouched. Toggled by payload.event.
local fogVolume = nil
local function setFogActive(active)
	if active then
		if fogVolume then
			return
		end
		local anchor = Instance.new("Part")
		anchor.Name = "FogVolume"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(130, 24, 130)
		anchor.Position = Vector3.new(0, 14, 0)

		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		-- emit throughout the whole box volume (not just its surfaces) so the
		-- fog fills the arena evenly rather than clinging to the edges
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		-- Perf: live particle count = Rate * avg(Lifetime). The GPU cost of fog
		-- is overdraw (count * size^2 of overlapping transparent sprites), so we
		-- keep the count modest (~36 * 15 ≈ 540 alive) and get the density from
		-- bigger, more opaque puffs instead of sheer quantity.
		emitter.Rate = 36
		emitter.Lifetime = NumberRange.new(12, 18)
		emitter.Speed = NumberRange.new(0, 0.8)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-8, 8)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 32),
			NumberSequenceKeypoint.new(1, 44),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.18, 0.42),
			NumberSequenceKeypoint.new(0.82, 0.42),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Color = ColorSequence.new(Color3.fromRGB(205, 202, 195))
		emitter.LightEmission = 0.2
		emitter.LightInfluence = 0 -- unlit: cheaper than sampling scene light per particle
		emitter.Parent = anchor
		anchor.Parent = workspace
		-- fill the volume immediately instead of waiting for puffs to accumulate
		emitter:Emit(180)
		fogVolume = anchor
	elseif fogVolume then
		fogVolume:Destroy()
		fogVolume = nil
	end
end

PlayMusic.OnClientEvent:Connect(function(soundId)
	if soundId and soundId ~= "" and Music.SoundId ~= soundId then
		Music.SoundId = soundId
		Music.TimePosition = 0
	end
	Music:Play()
end)

StopMusic.OnClientEvent:Connect(function()
	Music:Stop()
	playSfx(stopSfx)
end)

StateChanged.OnClientEvent:Connect(function(payload)
	Hud.applyState(payload)
	setFogActive(payload.event == "fog")
end)

YouEliminated.OnClientEvent:Connect(function()
	playSfx(eliminateSfx)
	Hud.flashEliminated()
end)
