local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events")
local PlayMusic = Events:WaitForChild("PlayMusic")
local StopMusic = Events:WaitForChild("StopMusic")
local StateChanged = Events:WaitForChild("StateChanged")
local YouEliminated = Events:WaitForChild("YouEliminated")

local Music = SoundService:WaitForChild("Music")

local PHASE_COLORS = {
	Waiting = Color3.fromRGB(220, 220, 220),
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

local bannerFrame = Instance.new("Frame")
bannerFrame.Size = UDim2.new(0.6, 0, 0.13, 0)
bannerFrame.Position = UDim2.new(0.2, 0, 0.03, 0)
bannerFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
bannerFrame.BackgroundTransparency = 0.25
bannerFrame.BorderSizePixel = 0
bannerFrame.Parent = screenGui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 10)
bannerCorner.Parent = bannerFrame

local bannerPadding = Instance.new("UIPadding")
bannerPadding.PaddingTop = UDim.new(0, 8)
bannerPadding.PaddingBottom = UDim.new(0, 8)
bannerPadding.PaddingLeft = UDim.new(0, 16)
bannerPadding.PaddingRight = UDim.new(0, 16)
bannerPadding.Parent = bannerFrame

local bannerLabel = Instance.new("TextLabel")
bannerLabel.Size = UDim2.new(1, 0, 0.65, 0)
bannerLabel.BackgroundTransparency = 1
bannerLabel.TextColor3 = Color3.new(1, 1, 1)
bannerLabel.TextScaled = true
bannerLabel.Font = Enum.Font.GothamBold
bannerLabel.Text = "INFERNAL CHAIRS"
bannerLabel.Parent = bannerFrame

local subLabel = Instance.new("TextLabel")
subLabel.Size = UDim2.new(1, 0, 0.35, 0)
subLabel.Position = UDim2.new(0, 0, 0.65, 0)
subLabel.BackgroundTransparency = 1
subLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
subLabel.TextScaled = true
subLabel.Font = Enum.Font.Gotham
subLabel.Text = ""
subLabel.Parent = bannerFrame

local countdownFrame = Instance.new("Frame")
countdownFrame.Size = UDim2.new(0, 130, 0, 110)
countdownFrame.Position = UDim2.new(1, -150, 0, 25)
countdownFrame.AnchorPoint = Vector2.new(0, 0)
countdownFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
countdownFrame.BackgroundTransparency = 0.25
countdownFrame.BorderSizePixel = 0
countdownFrame.Visible = false
countdownFrame.Parent = screenGui

local countdownCorner = Instance.new("UICorner")
countdownCorner.CornerRadius = UDim.new(0, 10)
countdownCorner.Parent = countdownFrame

local countdownCaption = Instance.new("TextLabel")
countdownCaption.Size = UDim2.new(1, 0, 0.3, 0)
countdownCaption.Position = UDim2.new(0, 0, 0, 6)
countdownCaption.BackgroundTransparency = 1
countdownCaption.TextColor3 = Color3.fromRGB(200, 200, 200)
countdownCaption.TextScaled = true
countdownCaption.Font = Enum.Font.Gotham
countdownCaption.Text = ""
countdownCaption.Parent = countdownFrame

local countdownLabel = Instance.new("TextLabel")
countdownLabel.Size = UDim2.new(1, 0, 0.65, 0)
countdownLabel.Position = UDim2.new(0, 0, 0.3, 0)
countdownLabel.BackgroundTransparency = 1
countdownLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
countdownLabel.TextScaled = true
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

PlayMusic.OnClientEvent:Connect(function()
	Music:Play()
end)

StopMusic.OnClientEvent:Connect(function()
	Music:Stop()
end)

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

StateChanged.OnClientEvent:Connect(function(payload)
	bannerLabel.Text = payload.message or ""
	subLabel.Text = payload.sub or ""
	bannerLabel.TextColor3 = PHASE_COLORS[payload.phase] or Color3.new(1, 1, 1)

	local config = COUNTDOWN_PHASES[payload.phase]
	if config and payload.duration then
		task.spawn(startCountdown, payload.duration, config.caption, config.color)
	else
		stopCountdown()
	end
end)

local overlayToken = 0
YouEliminated.OnClientEvent:Connect(function()
	overlayToken += 1
	local myToken = overlayToken
	overlay.Visible = true
	task.wait(3)
	if myToken == overlayToken then
		overlay.Visible = false
	end
end)
