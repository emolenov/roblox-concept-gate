local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gameplay = script.Parent
local feedback = gameplay:WaitForChild("HazardFeedback")
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("FirefighterHealthGui")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "FirefighterHealthGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 100
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "HealthPanel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 14)
panel.Size = UDim2.fromOffset(330, 58)
panel.BackgroundColor3 = Color3.fromRGB(24, 31, 38)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local label = Instance.new("TextLabel")
label.Name = "Title"
label.Position = UDim2.fromOffset(12, 5)
label.Size = UDim2.fromOffset(108, 24)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.Text = "ЗДОРОВЬЕ"
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 17
label.TextXAlignment = Enum.TextXAlignment.Left
label.Parent = panel

local valueLabel = Instance.new("TextLabel")
valueLabel.Name = "Value"
valueLabel.AnchorPoint = Vector2.new(1, 0)
valueLabel.Position = UDim2.new(1, -12, 0, 5)
valueLabel.Size = UDim2.fromOffset(95, 24)
valueLabel.BackgroundTransparency = 1
valueLabel.Font = Enum.Font.GothamBold
valueLabel.Text = "100 / 100"
valueLabel.TextColor3 = Color3.new(1, 1, 1)
valueLabel.TextSize = 16
valueLabel.TextXAlignment = Enum.TextXAlignment.Right
valueLabel.Parent = panel

local barBackground = Instance.new("Frame")
barBackground.Name = "BarBackground"
barBackground.Position = UDim2.fromOffset(12, 34)
barBackground.Size = UDim2.new(1, -24, 0, 14)
barBackground.BackgroundColor3 = Color3.fromRGB(68, 76, 84)
barBackground.BorderSizePixel = 0
barBackground.ClipsDescendants = true
barBackground.Parent = panel

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = barBackground

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = Color3.fromRGB(52, 196, 82)
barFill.BorderSizePixel = 0
barFill.Parent = barBackground

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = barFill

local fireFlash = Instance.new("Frame")
fireFlash.Name = "FireDamageFlash"
fireFlash.Size = UDim2.fromScale(1, 1)
fireFlash.BackgroundColor3 = Color3.fromRGB(220, 35, 25)
fireFlash.BackgroundTransparency = 1
fireFlash.BorderSizePixel = 0
fireFlash.ZIndex = 20
fireFlash.Parent = gui

local smokeOverlay = Instance.new("Frame")
smokeOverlay.Name = "SmokeOverlay"
smokeOverlay.Size = UDim2.fromScale(1, 1)
smokeOverlay.BackgroundColor3 = Color3.fromRGB(55, 61, 66)
smokeOverlay.BackgroundTransparency = 1
smokeOverlay.BorderSizePixel = 0
smokeOverlay.ZIndex = 10
smokeOverlay.Parent = gui

local smokeWarning = Instance.new("TextLabel")
smokeWarning.Name = "SmokeWarning"
smokeWarning.AnchorPoint = Vector2.new(0.5, 0)
smokeWarning.Position = UDim2.new(0.5, 0, 0, 82)
smokeWarning.Size = UDim2.fromOffset(440, 48)
smokeWarning.BackgroundColor3 = Color3.fromRGB(65, 69, 72)
smokeWarning.BackgroundTransparency = 0.16
smokeWarning.BorderSizePixel = 0
smokeWarning.Font = Enum.Font.GothamBold
smokeWarning.Text = "ДЫМ — ВЫЙДИ ИЗ ЗОНЫ"
smokeWarning.TextColor3 = Color3.new(1, 1, 1)
smokeWarning.TextScaled = true
smokeWarning.TextStrokeTransparency = 0.6
smokeWarning.Visible = false
smokeWarning.ZIndex = 21
smokeWarning.Parent = gui

local smokeCorner = Instance.new("UICorner")
smokeCorner.CornerRadius = UDim.new(0, 10)
smokeCorner.Parent = smokeWarning

local deathMessage = Instance.new("TextLabel")
deathMessage.Name = "DeathMessage"
deathMessage.AnchorPoint = Vector2.new(0.5, 0.5)
deathMessage.Position = UDim2.fromScale(0.5, 0.48)
deathMessage.Size = UDim2.fromOffset(760, 92)
deathMessage.BackgroundColor3 = Color3.fromRGB(145, 28, 25)
deathMessage.BackgroundTransparency = 0.08
deathMessage.BorderSizePixel = 0
deathMessage.Font = Enum.Font.GothamBold
deathMessage.Text = "ПОЖАРНЫЙ ПОСТРАДАЛ — ПОПРОБУЙ ЕЩЁ РАЗ"
deathMessage.TextColor3 = Color3.new(1, 1, 1)
deathMessage.TextScaled = true
deathMessage.TextStrokeTransparency = 0.55
deathMessage.Visible = false
deathMessage.ZIndex = 30
deathMessage.Parent = gui

local deathCorner = Instance.new("UICorner")
deathCorner.CornerRadius = UDim.new(0, 14)
deathCorner.Parent = deathMessage

local healthConnection
local maxHealthConnection
local smokeTween
local flashTween

local function healthColor(health)
	if health > 60 then
		return Color3.fromRGB(52, 196, 82)
	elseif health >= 30 then
		return Color3.fromRGB(245, 190, 45)
	else
		return Color3.fromRGB(225, 55, 45)
	end
end

local function updateHealth(humanoid)
	local maximum = math.max(1, humanoid.MaxHealth)
	local health = math.clamp(humanoid.Health, 0, maximum)
	barFill.Size = UDim2.fromScale(health / maximum, 1)
	barFill.BackgroundColor3 = healthColor(health)
	valueLabel.Text = ("%d / %d"):format(math.floor(health + 0.5), math.floor(maximum + 0.5))
end

local function bindCharacter(character)
	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end
	if maxHealthConnection then
		maxHealthConnection:Disconnect()
		maxHealthConnection = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	updateHealth(humanoid)
	healthConnection = humanoid.HealthChanged:Connect(function()
		updateHealth(humanoid)
	end)
	maxHealthConnection = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateHealth(humanoid)
	end)
end

local function pulseFireDamage()
	if flashTween then
		flashTween:Cancel()
	end
	fireFlash.BackgroundTransparency = 0.82
	local tween = TweenService:Create(
		fireFlash,
		TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1}
	)
	flashTween = tween
	tween.Completed:Once(function()
		if flashTween == tween then flashTween = nil end
		tween:Destroy()
	end)
	tween:Play()
end

local function setSmokeState(insideSmoke, dangerous, intensity)
	if smokeTween then
		smokeTween:Cancel()
	end
	smokeWarning.Visible = insideSmoke and dangerous
	local targetTransparency = 1
	if insideSmoke then
		targetTransparency = dangerous and 0.78 or (0.92 - 0.05 * math.clamp(intensity or 0, 0, 1))
	end
	if math.abs(smokeOverlay.BackgroundTransparency - targetTransparency) < 0.001 then
		smokeOverlay.BackgroundTransparency = targetTransparency
		return
	end
	local tween = TweenService:Create(
		smokeOverlay,
		TweenInfo.new(insideSmoke and 0.12 or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = targetTransparency}
	)
	smokeTween = tween
	tween.Completed:Once(function()
		if smokeTween == tween then smokeTween = nil end
		tween:Destroy()
	end)
	tween:Play()
end

player.CharacterAdded:Connect(function(character)
	deathMessage.Visible = false
	setSmokeState(false, false, 0)
	task.spawn(bindCharacter, character)
end)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

feedback.OnClientEvent:Connect(function(message, a, b, c)
	if message == "FireDamage" then
		pulseFireDamage()
	elseif message == "SmokeState" then
		setSmokeState(a == true, b == true, c)
	elseif message == "Death" then
		setSmokeState(false, false, 0)
		deathMessage.Text = typeof(a) == "string" and a or "ПОЖАРНЫЙ ПОСТРАДАЛ — ПОПРОБУЙ ЕЩЁ РАЗ"
		deathMessage.Visible = true
	elseif message == "Spawn" then
		deathMessage.Visible = false
		setSmokeState(false, false, 0)
	end
end)
