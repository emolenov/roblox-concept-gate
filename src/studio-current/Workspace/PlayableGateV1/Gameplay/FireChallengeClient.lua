local Players = game:GetService("Players")
local player = Players.LocalPlayer
local gate = script:FindFirstAncestor("PlayableGateV1")
local challenge = gate:WaitForChild("Gameplay"):WaitForChild("FireChallengeV1")
local feedback = challenge:WaitForChild("ChallengeFeedback")

local gui = Instance.new("ScreenGui")
gui.Name = "FireChallengeGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 45
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "ObjectivePanel"
panel.AnchorPoint = Vector2.new(0.5,0)
panel.Position = UDim2.fromScale(0.5,0.025)
panel.Size = UDim2.fromOffset(430,64)
panel.BackgroundColor3 = Color3.fromRGB(27,34,43)
panel.BackgroundTransparency = 0.13
panel.BorderSizePixel = 0
panel.Parent = gui
panel.Visible = gate:GetAttribute("DispatchArrived") == true
gate:GetAttributeChangedSignal("DispatchArrived"):Connect(function()
	panel.Visible = gate:GetAttribute("DispatchArrived") == true
end)
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255,142,43)
stroke.Thickness = 2
stroke.Transparency = 0.15
stroke.Parent = panel

local counter = Instance.new("TextLabel")
counter.Name = "FireCounter"
counter.BackgroundTransparency = 1
counter.Position = UDim2.fromOffset(8,4)
counter.Size = UDim2.new(1,-16,0,28)
counter.Font = Enum.Font.GothamBold
counter.Text = "ОЧАГИ ПОЖАРА: 0"
counter.TextColor3 = Color3.fromRGB(255,228,92)
counter.TextSize = 21
counter.Parent = panel

local objective = Instance.new("TextLabel")
objective.Name = "Objective"
objective.BackgroundTransparency = 1
objective.Position = UDim2.fromOffset(8,32)
objective.Size = UDim2.new(1,-16,0,24)
objective.Font = Enum.Font.GothamSemibold
objective.Text = ""
objective.TextColor3 = Color3.fromRGB(238,244,255)
objective.TextSize = 16
objective.Parent = panel

local warning = Instance.new("TextLabel")
warning.Name = "SpreadWarning"
warning.AnchorPoint = Vector2.new(0.5,0.5)
warning.Position = UDim2.fromScale(0.5,0.23)
warning.Size = UDim2.fromOffset(430,54)
warning.BackgroundColor3 = Color3.fromRGB(118,42,15)
warning.BackgroundTransparency = 0.08
warning.BorderSizePixel = 0
warning.Font = Enum.Font.GothamBlack
warning.Text = "ОГОНЬ РАСПРОСТРАНЯЕТСЯ!"
warning.TextColor3 = Color3.fromRGB(255,230,90)
warning.TextSize = 23
warning.Visible = false
warning.Parent = gui
local wc = Instance.new("UICorner")
wc.CornerRadius = UDim.new(0,10)
wc.Parent = warning

local warningVersion = 0
feedback.OnClientEvent:Connect(function(action, value)
	if action == "FireCount" then
		counter.Text = string.format("ОЧАГИ ПОЖАРА: %d", tonumber(value) or 0)
	elseif action == "Objective" then
		objective.Text = tostring(value or "")
	elseif action == "SpreadWarning" then
		warningVersion += 1
		local version = warningVersion
		warning.Visible = true
		task.delay(challenge:GetAttribute("WarningDuration") or 2, function()
			if version == warningVersion then warning.Visible = false end
		end)
	elseif action == "Reset" then
		warningVersion += 1
		warning.Visible = false
		counter.Text = string.format("ОЧАГИ ПОЖАРА: %d", challenge:GetAttribute("ActiveFireCount") or 0)
		objective.Text = ""
	end
end)

counter.Text = string.format("ОЧАГИ ПОЖАРА: %d", challenge:GetAttribute("ActiveFireCount") or 0)