-- Hud.luau — builds and drives all the on-screen UI (top banner, countdown,
-- eliminated overlay, welcome tutorial). Extracted from init.client so the
-- LocalScript stays focused on wiring RemoteEvents + audio + the fog effect.
--
-- Public API:
--   Hud.applyState(payload)  -- react to a StateChanged payload (banner text,
--                               color, event punch, countdown, visibility)
--   Hud.flashEliminated()    -- show the red ELIMINATED overlay for 3s

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local PHASE_COLORS = {
	Waiting = Color3.fromRGB(220, 220, 220),
	Warmup = Color3.fromRGB(255, 180, 90),
	Intermission = Color3.fromRGB(120, 220, 255),
	Playing = Color3.fromRGB(120, 255, 140),
	Stopped = Color3.fromRGB(255, 200, 60),
	Judgement = Color3.fromRGB(255, 80, 80),
	Winner = Color3.fromRGB(255, 215, 0),
	Reset = Color3.fromRGB(200, 200, 200),
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InfernalChairsUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = PlayerGui

-- =====================================================================
-- HUD TUNING (banner + countdown)
-- Both overlays share these constants — they sit at the same top edge
-- with the same height + visual style, only differing in horizontal anchor.
-- Per-overlay sizes (width, inner padding, TextSize) live in their
-- creation blocks below. Search for `bannerFrame` or `countdownFrame`.
-- =====================================================================
local HUD_TOP = 24
local HUD_HEIGHT = 70
local HUD_BG = Color3.fromRGB(15, 15, 20)
local HUD_BG_TRANSPARENCY = 0.25
local HUD_CORNER = UDim.new(0, 10)

local bannerFrame = Instance.new("Frame")
bannerFrame.Size = UDim2.new(0.5, 0, 0, HUD_HEIGHT)
bannerFrame.Position = UDim2.new(0.5, 0, 0, HUD_TOP)
bannerFrame.AnchorPoint = Vector2.new(0.5, 0)
bannerFrame.BackgroundColor3 = HUD_BG
bannerFrame.BackgroundTransparency = HUD_BG_TRANSPARENCY
bannerFrame.BorderSizePixel = 0
bannerFrame.Parent = screenGui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = HUD_CORNER
bannerCorner.Parent = bannerFrame

local bannerScale = Instance.new("UIScale")
bannerScale.Scale = 1
bannerScale.Parent = bannerFrame

local bannerPadding = Instance.new("UIPadding")
bannerPadding.PaddingTop = UDim.new(0, 6)
bannerPadding.PaddingBottom = UDim.new(0, 6)
bannerPadding.PaddingLeft = UDim.new(0, 16)
bannerPadding.PaddingRight = UDim.new(0, 16)
bannerPadding.Parent = bannerFrame

local bannerLabel = Instance.new("TextLabel")
bannerLabel.Size = UDim2.new(1, 0, 0.62, 0)
bannerLabel.BackgroundTransparency = 1
bannerLabel.TextColor3 = Color3.new(1, 1, 1)
bannerLabel.TextSize = 32
bannerLabel.Font = Enum.Font.GothamBold
bannerLabel.Text = "INFERNAL CHAIRS"
bannerLabel.Parent = bannerFrame

local subLabel = Instance.new("TextLabel")
subLabel.Size = UDim2.new(1, 0, 0.28, 0)
subLabel.Position = UDim2.new(0, 0, 0.62, 0)
subLabel.BackgroundTransparency = 1
subLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
subLabel.TextSize = 18
subLabel.Font = Enum.Font.Gotham
subLabel.Text = ""
subLabel.Parent = bannerFrame

local countdownFrame = Instance.new("Frame")
countdownFrame.Size = UDim2.new(0, 116, 0, HUD_HEIGHT)
countdownFrame.Position = UDim2.new(1, -24, 0, HUD_TOP)
countdownFrame.AnchorPoint = Vector2.new(1, 0)
countdownFrame.BackgroundColor3 = HUD_BG
countdownFrame.BackgroundTransparency = HUD_BG_TRANSPARENCY
countdownFrame.BorderSizePixel = 0
countdownFrame.Visible = false
countdownFrame.Parent = screenGui

local countdownCorner = Instance.new("UICorner")
countdownCorner.CornerRadius = HUD_CORNER
countdownCorner.Parent = countdownFrame

local countdownCaption = Instance.new("TextLabel")
countdownCaption.Size = UDim2.new(1, 0, 0.38, 0)
countdownCaption.Position = UDim2.new(0, 0, 0, 4)
countdownCaption.BackgroundTransparency = 1
countdownCaption.TextColor3 = Color3.fromRGB(200, 200, 200)
countdownCaption.TextSize = 14
countdownCaption.Font = Enum.Font.Gotham
countdownCaption.Text = ""
countdownCaption.Parent = countdownFrame

local countdownLabel = Instance.new("TextLabel")
countdownLabel.Size = UDim2.new(1, 0, 0.60, 0)
countdownLabel.Position = UDim2.new(0, 0, 0.32, 0)
countdownLabel.BackgroundTransparency = 1
countdownLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
countdownLabel.TextSize = 38
countdownLabel.Font = Enum.Font.GothamBold
countdownLabel.Text = ""
countdownLabel.Parent = countdownFrame

local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.ZIndex = 10
overlay.Parent = screenGui

local overlayLabel = Instance.new("TextLabel")
overlayLabel.Size = UDim2.new(0.7, 0, 0.25, 0)
overlayLabel.Position = UDim2.new(0.15, 0, 0.375, 0)
overlayLabel.BackgroundTransparency = 1
overlayLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
overlayLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
overlayLabel.TextStrokeTransparency = 0.3
overlayLabel.TextScaled = true
overlayLabel.Font = Enum.Font.GothamBlack
overlayLabel.Text = "ELIMINATED"
overlayLabel.ZIndex = 11
overlayLabel.Parent = overlay

-- Welcome tutorial: shown once per session (script runs once when the LocalPlayer joins).
local welcomeFrame = Instance.new("Frame")
welcomeFrame.Size = UDim2.new(1, 0, 1, 0)
welcomeFrame.BackgroundColor3 = Color3.fromRGB(8, 6, 14)
welcomeFrame.BackgroundTransparency = 0.15
welcomeFrame.BorderSizePixel = 0
welcomeFrame.ZIndex = 20
welcomeFrame.Parent = screenGui

local WELCOME_RULES = {
	"Music ON: you orbit the chairs automatically (you have no control)",
	"Music STOPS: run to a chair and press E to sit",
	"Last player without a chair gets eliminated",
	"Rounds 2+ add a twist: ice, fog, mud, flickering lights",
}

local welcomePanel = Instance.new("Frame")
welcomePanel.Size = UDim2.new(0, 720, 0, 450) -- 80 padding + 44 title + 28 gap + 212 rules + 28 gap + 52 button + 6 slack
welcomePanel.Position = UDim2.new(0.5, 0, 0.5, 0)
welcomePanel.AnchorPoint = Vector2.new(0.5, 0.5)
welcomePanel.BackgroundColor3 = Color3.fromRGB(20, 16, 30)
welcomePanel.BackgroundTransparency = 0.05
welcomePanel.BorderSizePixel = 0
welcomePanel.ZIndex = 21
welcomePanel.Parent = welcomeFrame

local welcomeCorner = Instance.new("UICorner")
welcomeCorner.CornerRadius = UDim.new(0, 18)
welcomeCorner.Parent = welcomePanel

local welcomePadding = Instance.new("UIPadding")
welcomePadding.PaddingTop = UDim.new(0, 40)
welcomePadding.PaddingBottom = UDim.new(0, 40)
welcomePadding.PaddingLeft = UDim.new(0, 44)
welcomePadding.PaddingRight = UDim.new(0, 44)
welcomePadding.Parent = welcomePanel

-- UIListLayout stacks title / rules / button vertically with consistent spacing,
-- so we don't have to hand-tune absolute Y positions when content changes.
local welcomeStack = Instance.new("UIListLayout")
welcomeStack.FillDirection = Enum.FillDirection.Vertical
welcomeStack.HorizontalAlignment = Enum.HorizontalAlignment.Center
welcomeStack.VerticalAlignment = Enum.VerticalAlignment.Top
welcomeStack.SortOrder = Enum.SortOrder.LayoutOrder
welcomeStack.Padding = UDim.new(0, 28)
welcomeStack.Parent = welcomePanel

local welcomeTitle = Instance.new("TextLabel")
welcomeTitle.Size = UDim2.new(1, 0, 0, 44)
welcomeTitle.BackgroundTransparency = 1
welcomeTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
welcomeTitle.TextSize = 32
welcomeTitle.Font = Enum.Font.GothamBlack
welcomeTitle.Text = "WELCOME TO INFERNAL CHAIRS"
welcomeTitle.LayoutOrder = 1
welcomeTitle.ZIndex = 22
welcomeTitle.Parent = welcomePanel

local rulesList = Instance.new("Frame")
rulesList.Size = UDim2.new(1, 0, 0, 212) -- 4 rows × 50 + 3 gaps × 4
rulesList.BackgroundTransparency = 1
rulesList.LayoutOrder = 2
rulesList.ZIndex = 22
rulesList.Parent = welcomePanel

local rulesLayout = Instance.new("UIListLayout")
rulesLayout.FillDirection = Enum.FillDirection.Vertical
rulesLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
rulesLayout.SortOrder = Enum.SortOrder.LayoutOrder
rulesLayout.Padding = UDim.new(0, 4)
rulesLayout.Parent = rulesList

for index, ruleText in WELCOME_RULES do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 50)
	row.BackgroundTransparency = 1
	row.LayoutOrder = index
	row.ZIndex = 22
	row.Parent = rulesList

	local numberBadge = Instance.new("TextLabel")
	numberBadge.Size = UDim2.new(0, 40, 0, 40)
	numberBadge.Position = UDim2.new(0, 0, 0.5, 0)
	numberBadge.AnchorPoint = Vector2.new(0, 0.5)
	numberBadge.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	numberBadge.TextColor3 = Color3.fromRGB(20, 16, 0)
	numberBadge.TextSize = 28
	numberBadge.Font = Enum.Font.GothamBlack
	numberBadge.Text = tostring(index)
	numberBadge.ZIndex = 23
	numberBadge.Parent = row

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 10)
	badgeCorner.Parent = numberBadge

	local ruleLabel = Instance.new("TextLabel")
	ruleLabel.Size = UDim2.new(1, -68, 1, 0)
	ruleLabel.Position = UDim2.new(0, 68, 0, 0)
	ruleLabel.BackgroundTransparency = 1
	ruleLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
	ruleLabel.TextSize = 20
	ruleLabel.TextWrapped = true
	ruleLabel.TextXAlignment = Enum.TextXAlignment.Left
	ruleLabel.TextYAlignment = Enum.TextYAlignment.Center
	ruleLabel.Font = Enum.Font.Gotham
	ruleLabel.Text = ruleText
	ruleLabel.ZIndex = 23
	ruleLabel.Parent = row
end

local welcomeButton = Instance.new("TextButton")
welcomeButton.Size = UDim2.new(0, 200, 0, 52)
welcomeButton.BackgroundColor3 = Color3.fromRGB(255, 90, 60)
welcomeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
welcomeButton.TextSize = 22
welcomeButton.Font = Enum.Font.GothamBold
welcomeButton.Text = "GOT IT"
welcomeButton.BorderSizePixel = 0
welcomeButton.AutoButtonColor = true
welcomeButton.LayoutOrder = 3
welcomeButton.ZIndex = 22
welcomeButton.Parent = welcomePanel

local welcomeButtonCorner = Instance.new("UICorner")
welcomeButtonCorner.CornerRadius = UDim.new(0, 10)
welcomeButtonCorner.Parent = welcomeButton

welcomeButton.Activated:Connect(function()
	welcomeFrame.Visible = false
end)

-- countdown shown during phases listed here (top-right timer)
local COUNTDOWN_PHASES = {
	Stopped = { caption = "SIT NOW IN", color = Color3.fromRGB(255, 90, 90) },
}

local countdownToken = 0

local function stopCountdown()
	countdownToken += 1
	countdownFrame.Visible = false
end

local function startCountdown(duration, caption, color)
	countdownToken += 1
	local myToken = countdownToken
	countdownCaption.Text = caption
	countdownLabel.TextColor3 = color
	countdownFrame.Visible = true
	local startedAt = os.clock()
	while countdownToken == myToken do
		local remaining = math.max(0, duration - (os.clock() - startedAt))
		countdownLabel.Text = string.format("%.1fs", remaining)
		if remaining <= 0 then
			break
		end
		task.wait(0.05)
	end
end

local EVENT_FLASH_COLOR = Color3.fromRGB(255, 215, 0)
local TWEEN_PUNCH_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_PUNCH_IN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function punchBanner(basePhaseColor)
	-- scale-up + gold flash, then back. signals "the rules changed".
	bannerScale.Scale = 1
	bannerLabel.TextColor3 = EVENT_FLASH_COLOR
	TweenService:Create(bannerScale, TWEEN_PUNCH_OUT, { Scale = 1.25 }):Play()
	task.delay(0.2, function()
		TweenService:Create(bannerScale, TWEEN_PUNCH_IN, { Scale = 1 }):Play()
		TweenService:Create(bannerLabel, TWEEN_PUNCH_IN, { TextColor3 = basePhaseColor }):Play()
	end)
end

local Hud = {}

function Hud.applyState(payload)
	bannerLabel.Text = payload.message or ""
	subLabel.Text = payload.sub or ""
	local phaseColor = PHASE_COLORS[payload.phase] or Color3.new(1, 1, 1)
	bannerLabel.TextColor3 = phaseColor

	if payload.eventChanged and payload.event then
		punchBanner(phaseColor)
	end

	local config = COUNTDOWN_PHASES[payload.phase]
	if config and payload.duration then
		task.spawn(startCountdown, payload.duration, config.caption, config.color)
	else
		stopCountdown()
	end

	-- Hide HUD entirely while we're in the lobby (Waiting). Once a match
	-- starts the banner reappears with the current phase / event info.
	bannerFrame.Visible = payload.phase ~= "Waiting"
end

local overlayToken = 0
function Hud.flashEliminated()
	overlayToken += 1
	local myToken = overlayToken
	overlay.Visible = true
	task.wait(3)
	if myToken == overlayToken then
		overlay.Visible = false
	end
end

return Hud
