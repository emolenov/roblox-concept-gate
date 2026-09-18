local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local gameplay = script.Parent
local gate = gameplay.Parent
local waterInput = gameplay:WaitForChild("WaterInput")
-- Exterior gate messages use the existing minimal client UI channel.
local missionMessage = gameplay:WaitForChild("MissionMessage")

local spraying = false
local lastSent = 0
local serverVisualUntil = 0
local serverVisualOrigin
local serverVisualTarget
local instructionGui
local missionGui
local missionMessageVersion = 0
local hasSprayed = false
local mobileSprayGui
local mobileSprayButton
local LOCAL_SPRAY_ATTRIBUTE = "LocalHoseSpraying"

local function hideInstruction()
	if instructionGui then
		instructionGui:Destroy()
		instructionGui = nil
	end
end

local function showInstruction()
	if instructionGui or hasSprayed or player:GetAttribute("HoseEquipped") ~= true then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
	instructionGui = Instance.new("ScreenGui")
	instructionGui.Name = "HoseInstructionGui"
	instructionGui.ResetOnSpawn = false
	instructionGui.IgnoreGuiInset = false
	instructionGui.Parent = playerGui

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 1)
	message.Position = UDim2.fromScale(0.5, 0.92)
	message.Size = UDim2.fromOffset(620, 64)
	message.BackgroundColor3 = Color3.fromRGB(25, 70, 105)
	message.BackgroundTransparency = 0.1
	message.BorderSizePixel = 0
	message.TextColor3 = Color3.new(1, 1, 1)
	message.TextStrokeTransparency = 0.55
	message.Font = Enum.Font.GothamBold
	message.TextScaled = true
	message.Text = "Зажми левую кнопку мыши и направь воду на огонь"
	message.Parent = instructionGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = message
end

local function hideMissionMessage()
	missionMessageVersion += 1
	if missionGui then
		missionGui:Destroy()
		missionGui = nil
	end
end

local function showMissionMessage(kind, text, duration)
	hideMissionMessage()
	local version = missionMessageVersion
	local playerGui = player:WaitForChild("PlayerGui")
	missionGui = Instance.new("ScreenGui")
	missionGui.Name = "ExteriorMissionGui"
	missionGui.ResetOnSpawn = false
	missionGui.IgnoreGuiInset = false
	missionGui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.12)
	label.Size = UDim2.fromOffset(640, 64)
	label.BackgroundColor3 = kind == "Ready"
		and Color3.fromRGB(42, 145, 76)
		or Color3.fromRGB(180, 62, 45)
	label.BackgroundTransparency = 0.08
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.55
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = missionGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label

	if typeof(duration) == "number" and duration > 0 then
		task.delay(duration, function()
			if missionGui and missionMessageVersion == version then
				hideMissionMessage()
			end
		end)
	end
end

-- Visible water rendering is owned by Gameplay.WaterImpactVFX.WaterVFXClient.
-- Do not instantiate the retired local stream here.

local function getCharacterParts()
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local tool = character:FindFirstChild("FireHoseTool")
	local handle = tool and tool:FindFirstChild("Handle")
	local nozzleTip = handle and handle:FindFirstChild("NozzleTipAttachment")
	return humanoid, nozzleTip
end

local function setLocalSprayState(value)
	player:SetAttribute(LOCAL_SPRAY_ATTRIBUTE, value == true)
end

local function beginSpray()
	if player:GetAttribute("HoseEquipped") ~= true then return end
	local _, nozzleTip = getCharacterParts()
	if not nozzleTip then return end
	spraying = true
	hasSprayed = true
	setLocalSprayState(true)
	hideInstruction()
end

local function endSpray()
	spraying = false
	setLocalSprayState(false)
	waterInput:FireServer(false)
end

local function ensureMobileSprayButton()
	if not UserInputService.TouchEnabled then return end
	if mobileSprayGui and mobileSprayGui.Parent and mobileSprayButton then return end
	local playerGui = player:WaitForChild("PlayerGui")
	mobileSprayGui = Instance.new("ScreenGui")
	mobileSprayGui.Name = "MobileHoseGui"
	mobileSprayGui.ResetOnSpawn = false
	mobileSprayGui.DisplayOrder = 90
	mobileSprayGui.Parent = playerGui
	mobileSprayButton = Instance.new("TextButton")
	mobileSprayButton.Name = "SprayButton"
	mobileSprayButton.AnchorPoint = Vector2.new(0.5, 0.5)
	mobileSprayButton.Position = UDim2.fromScale(0.87, 0.64)
	mobileSprayButton.Size = UDim2.fromOffset(96, 96)
	mobileSprayButton.BackgroundColor3 = Color3.fromRGB(35, 126, 185)
	mobileSprayButton.BackgroundTransparency = 0.12
	mobileSprayButton.Text = "WATER"
	mobileSprayButton.TextColor3 = Color3.new(1, 1, 1)
	mobileSprayButton.TextScaled = true
	mobileSprayButton.Font = Enum.Font.GothamBold
	mobileSprayButton.AutoButtonColor = true
	mobileSprayButton.Active = true
	mobileSprayButton.Visible = false
	mobileSprayButton.Parent = mobileSprayGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = mobileSprayButton
	mobileSprayButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			beginSpray()
		end
	end)
	mobileSprayButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			endSpray()
		end
	end)
end

local function updateMobileSprayButton()
	if not UserInputService.TouchEnabled then return end
	ensureMobileSprayButton()
	if mobileSprayButton then
		mobileSprayButton.Visible = player:GetAttribute("HoseEquipped") == true
	end
end

local function getAimTarget(origin)
	if UserInputService.TouchEnabled then
		local camera = workspace.CurrentCamera
		if camera then
			local viewport = camera.ViewportSize
			local ray = camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.46)
			return origin + ray.Direction * 75
		end
	end
	return mouse.Hit.Position
end

local function setWaterVisual(_origin, _target, _visible)
	-- Rendering is delegated to Gameplay.WaterImpactVFX.WaterVFXClient.
	return
end

local function ensureStandardCamera()
	local camera = workspace.CurrentCamera
	local humanoid = getCharacterParts()
	if camera and humanoid then
		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
		if camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

player.CharacterAdded:Connect(function()
	hasSprayed = false
	setLocalSprayState(false)
	hideInstruction()
	hideMissionMessage()
	task.defer(ensureStandardCamera)
	task.defer(updateMobileSprayButton)
end)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(ensureStandardCamera)
player:GetAttributeChangedSignal("HoseEquipped"):Connect(function()
	if player:GetAttribute("HoseEquipped") == true then
		showInstruction()
	else
		spraying = false
		setLocalSprayState(false)
		serverVisualUntil = 0
		waterInput:FireServer(false)
		setWaterVisual(Vector3.zero, Vector3.zero, false)
		hideInstruction()
	end
	updateMobileSprayButton()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		beginSpray()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		endSpray()
	end
end)

missionMessage.OnClientEvent:Connect(function(kind, text, duration)
	if kind == "Hide" then
		hideMissionMessage()
	elseif (kind == "Blocked" or kind == "Ready") and typeof(text) == "string" then
		showMissionMessage(kind, text, duration)
	end
end)

waterInput.OnClientEvent:Connect(function(message, origin, target)
	if message == "Complete" then
		spraying = false
		serverVisualUntil = 0
		setWaterVisual(Vector3.zero, Vector3.zero, false)
	elseif message == "Reset" then
		spraying = false
		hasSprayed = false
		serverVisualUntil = 0
		hideInstruction()
		hideMissionMessage()
		setWaterVisual(Vector3.zero, Vector3.zero, false)
	elseif message == "HoseStored" then
		spraying = false
		serverVisualUntil = 0
		setWaterVisual(Vector3.zero, Vector3.zero, false)
		hideInstruction()
	elseif message == "Spray" and typeof(origin) == "Vector3" and typeof(target) == "Vector3" then
		serverVisualOrigin = origin
		serverVisualTarget = target
		serverVisualUntil = os.clock() + 0.18
	end
end)

RunService:BindToRenderStep("PlayableGateV1CameraGuard", Enum.RenderPriority.Camera.Value + 25, ensureStandardCamera)

RunService.RenderStepped:Connect(function()
	local humanoid, nozzleTip = getCharacterParts()
	if not humanoid or not nozzleTip then
		setWaterVisual(Vector3.zero, Vector3.zero, false)
		return
	end

	if player:GetAttribute("HoseEquipped") == true and spraying then
		local origin = nozzleTip.WorldPosition
		local target = getAimTarget(origin)
		local offset = target - origin
		if offset.Magnitude > 75 then
			target = origin + offset.Unit * 75
		end
		setWaterVisual(origin, target, true)

		local now = os.clock()
		if now - lastSent >= 0.08 then
			lastSent = now
			waterInput:FireServer(true, target)
		end
	elseif serverVisualUntil > os.clock() and serverVisualOrigin and serverVisualTarget then
		setWaterVisual(serverVisualOrigin, serverVisualTarget, true)
	else
		setWaterVisual(Vector3.zero, Vector3.zero, false)
	end
end)

ensureStandardCamera()
setLocalSprayState(false)
updateMobileSprayButton()
if player:GetAttribute("HoseEquipped") == true then
	showInstruction()
end
