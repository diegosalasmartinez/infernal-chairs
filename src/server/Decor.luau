-- Decor.luau — places optional Marketplace props into predefined slots in the
-- arena + lobby. The slots exist NOW (shown as labelled placeholders); dropping
-- in a real asset is then trivial:
--   1. Save the model as assets/<name>.rbxm
--   2. Declare it in default.project.json under ReplicatedStorage.Templates,
--      e.g.  "DiscoBall": { "$path": "assets/disco_ball.rbxm" }
--   3. Done — it auto-places into every slot whose `template` matches that name.
-- Slots without a matching template show a magenta placeholder + floating label
-- (toggle SHOW_PLACEHOLDERS) so you can see the intended layout while shopping.
-- Several slots can share one template (e.g. all four Speakers).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

-- Props are cloned, anchored and positioned as-is. Cleaning the asset (removing
-- stray Sounds, unwanted scripts, etc.) is done manually in Studio before saving
-- the .rbxm — the code does not touch a prop's contents.

-- DEBUG: show a labelled marker at every slot that has no asset yet. Set false
-- once the arena/lobby are dressed (or to preview without the markers).
local SHOW_PLACEHOLDERS = true

local R = Config.ARENA_RADIUS
local H = Config.ARENA_WALL_HEIGHT
local P = Config.ARENA_PILLAR_RADIUS

-- Each slot: world position, yaw in degrees (facing), the Templates child name
-- to look for, and a human label. Only the ARENA lives here — its slots derive
-- from ARENA_RADIUS so they re-scale with the ring. Lobby decor (sofas, plants,
-- jukebox, etc.) is positioned visually in Studio and saved as a single .rbxm
-- (Workspace.Lobby.Decor → assets/lobby-decor.rbxm), because the lobby is fixed
-- size and you're better off dragging props with the mouse than guessing
-- coordinates.
local SLOTS = {
	-- DiscoBall is the only slot positioned by pivot center (hangs from ceiling);
	-- everything else uses `floor = true` so the bottom of the model's bounding
	-- box sits exactly at slot.pos.Y (avoids buried/floating props regardless of
	-- where each Marketplace model puts its pivot).
	{ name = "DiscoBall", pos = Vector3.new(0, H - 5, 0), yaw = 0, template = "DiscoBall", label = "DISCO BALL" },
	{
		name = "DjBooth",
		pos = Vector3.new(0, 0.5, R - 6),
		yaw = 180,
		template = "DjBooth",
		label = "DJ BOOTH",
		floor = true,
	},
	{
		name = "SpeakerNE",
		pos = Vector3.new(P - 6, 0.5, P - 6),
		yaw = 225,
		template = "Speaker",
		label = "SPEAKER",
		floor = true,
	},
	{
		name = "SpeakerNW",
		pos = Vector3.new(-(P - 6), 0.5, P - 6),
		yaw = 135,
		template = "Speaker",
		label = "SPEAKER",
		floor = true,
	},
	{
		name = "SpeakerSE",
		pos = Vector3.new(P - 6, 0.5, -(P - 6)),
		yaw = 315,
		template = "Speaker",
		label = "SPEAKER",
		floor = true,
	},
	{
		name = "SpeakerSW",
		pos = Vector3.new(-(P - 6), 0.5, -(P - 6)),
		yaw = 45,
		template = "Speaker",
		label = "SPEAKER",
		floor = true,
	},
}

local function placeTemplate(template, slot, parent)
	local model = template:Clone()
	model.Name = slot.name
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	local cf = CFrame.new(slot.pos) * CFrame.Angles(0, math.rad(slot.yaw), 0)
	if model:IsA("Model") then
		if not model.PrimaryPart then
			model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
		end
		if model.PrimaryPart then
			model:PivotTo(cf)
		end
	elseif model:IsA("BasePart") then
		model.CFrame = cf
	end
	model.Parent = parent

	-- floor flag: after the pivot is set, measure the bounding box and shift the
	-- model up/down so its bottom sits exactly at slot.pos.Y. Models from the
	-- Marketplace pivot in different places (center, base, off-corner), so we
	-- can't predict the right Y from the pivot alone — measure-and-correct is
	-- the robust workaround.
	if slot.floor then
		-- the bbox CFrame is the bbox CENTER (not the model pivot, which can be
		-- off-center). using the pivot here causes levitation when models pivot
		-- above their geometric center. measure bbox center -> compute real
		-- bottom -> shift the whole model by the correction.
		local bboxCf, bboxSize
		if model:IsA("Model") then
			bboxCf, bboxSize = model:GetBoundingBox()
		elseif model:IsA("BasePart") then
			bboxCf, bboxSize = model.CFrame, model.Size
		end
		if bboxCf and bboxSize then
			local bottomY = bboxCf.Y - bboxSize.Y / 2
			local correction = slot.pos.Y - bottomY
			local shift = Vector3.new(0, correction, 0)
			if model:IsA("Model") then
				model:PivotTo(model:GetPivot() + shift)
			else
				model.CFrame = model.CFrame + shift
			end
		end
	end

	return model
end

local function placeMarker(slot, parent)
	local marker = Instance.new("Part")
	marker.Name = slot.name .. "Placeholder"
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 0.55
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 0, 200)
	marker.Size = Vector3.new(2, 2, 2)
	marker.CFrame = CFrame.new(slot.pos)
	marker.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 130, 0, 28)
	billboard.StudsOffset = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = marker

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 210, 255)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = slot.label
	label.Parent = billboard
end

local Decor = {}

function Decor.build()
	local templates = ReplicatedStorage:FindFirstChild("Templates")
	local existing = Workspace:FindFirstChild("Decor")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = Workspace

	for _, slot in SLOTS do
		local template = templates and templates:FindFirstChild(slot.template)
		if template then
			placeTemplate(template, slot, folder)
		elseif SHOW_PLACEHOLDERS then
			placeMarker(slot, folder)
		end
	end
end

return Decor
