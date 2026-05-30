-- Decor.luau — places Marketplace props at slots inside the arena.
--
-- Templates live in ReplicatedStorage.Templates (which is part of the .rbxl,
-- NOT in assets/*.rbxm — Rojo can't roundtrip Marketplace assets with binary
-- props like MaterialVariantSerialized/AeroMeshData; see ROBLOX_PLAYBOOK.md
-- section 3 + 12). To add a new arena slot:
--   1. Drop the Marketplace model into ReplicatedStorage.Templates in Studio.
--   2. Add an entry to SLOTS below referencing that template name.
--   3. Ctrl+S, then F5.
--
-- Slots with no matching template show a magenta placeholder + floating label
-- (toggle SHOW_PLACEHOLDERS).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local SHOW_PLACEHOLDERS = true

local H = Config.ARENA_WALL_HEIGHT

-- Each slot: world position, yaw + pitch in degrees (facing), the Templates
-- child name to look for, and a human label. The ARENA decor is what lives
-- here — slot positions derive from ARENA_RADIUS / WALL_HEIGHT / PILLAR_RADIUS
-- so they re-scale with the ring. Lobby decor is edited visually in Studio
-- inside Workspace.Lobby.Decor (lives in the .rbxl).
--
-- `floor = true` shifts the model up so its bbox bottom sits at slot.pos.Y
-- (used for ground-standing props; not needed for ceiling-hung ones).
local SLOTS = {
	{
		name = "DiscoBall",
		pos = Vector3.new(0, H - 5, 0),
		yaw = 0,
		pitch = 90, -- model's natural axis points sideways; pitch it so it hangs down
		template = "DiscoBall",
		label = "DISCO BALL",
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
	local cf = CFrame.new(slot.pos) * CFrame.Angles(math.rad(slot.pitch or 0), math.rad(slot.yaw or 0), 0)
	if model:IsA("Model") then
		-- compensate for templates whose WorldPivot is NOT at the bbox center.
		-- Marketplace assets often have weird pivots (inherited from how they were
		-- imported / duplicated in Studio). A naive PivotTo(cf) lands the *pivot*
		-- at cf, but the visible geometry can be tens of studs away. We shift by
		-- (pivot - bbox center) so the geometry lands at cf regardless of pivot.
		local bboxCf = model:GetBoundingBox()
		local pivotOffset = model:GetPivot().Position - bboxCf.Position
		model:PivotTo(cf + pivotOffset)
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

	-- find or create the Arena folder (declared in default.project.json with
	-- $ignoreUnknownInstances so it exists already in steady state).
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then
		arena = Instance.new("Folder")
		arena.Name = "Arena"
		arena.Parent = Workspace
	end

	-- migration cleanup: prior structure had Workspace.Decor at the root.
	local oldDecor = Workspace:FindFirstChild("Decor")
	if oldDecor then
		oldDecor:Destroy()
	end

	local existing = arena:FindFirstChild("Decor")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = arena

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
