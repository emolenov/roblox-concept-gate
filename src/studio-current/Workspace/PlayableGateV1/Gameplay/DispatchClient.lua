-- Dispatch Loop V1 client: short call UI and WASD arcade input.
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local gate = script:FindFirstAncestor("PlayableGateV1")
local gameplay = gate:WaitForChild("Gameplay")
local remotes = gameplay:WaitForChild("DispatchRemotes")
local vehicleInput = remotes:WaitForChild("VehicleInput")
local vehicleExit = remotes:WaitForChild("VehicleExit")
local dispatchMessage = remotes:WaitForChild("DispatchMessage")
local vehicleEnter = remotes:WaitForChild("VehicleEnter")
local vehicleRoot = gate:WaitForChild("FiretruckPreview"):WaitForChild("DispatchVehicleRoot")
local drivePrompt = vehicleRoot:WaitForChild("DrivePrompt")

local gui = Instance.new("ScreenGui")
gui.Name = "DispatchGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 80
gui.Parent = player:WaitForChild("PlayerGui")

local banner = Instance.new("TextLabel")
banner.Name = "DispatchBanner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.fromScale(0.5, 0.12)
banner.Size = UDim2.fromOffset(570, 62)
banner.BackgroundColor3 = Color3.fromRGB(190, 42, 38)
banner.BackgroundTransparency = 0.08
banner.BorderSizePixel = 0
banner.TextColor3 = Color3.fromRGB(255, 247, 214)
banner.TextStrokeTransparency = 0.75
banner.Font = Enum.Font.GothamBold
banner.TextSize = 23
banner.TextWrapped = true
banner.Visible = false
banner.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = banner
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 218, 92)
stroke.Thickness = 2
stroke.Parent = banner

local controls = Instance.new("TextLabel")
controls.Name = "DriveControls"
controls.AnchorPoint = Vector2.new(0.5, 1)
controls.Position = UDim2.fromScale(0.5, 0.95)
controls.Size = UDim2.fromOffset(410, 42)
controls.BackgroundColor3 = Color3.fromRGB(25, 31, 38)
controls.BackgroundTransparency = 0.16
controls.BorderSizePixel = 0
controls.Text = "WASD — ЕХАТЬ     E — ВЫЙТИ"
controls.TextColor3 = Color3.fromRGB(245, 249, 255)
controls.Font = Enum.Font.GothamSemibold
controls.TextSize = 18
controls.Visible = false
controls.Parent = gui
local controlsCorner = Instance.new("UICorner")
controlsCorner.CornerRadius = UDim.new(0, 9)
controlsCorner.Parent = controls

local mobileEnterButton = Instance.new("TextButton")
mobileEnterButton.Name = "MobileDriveButton"
mobileEnterButton.AnchorPoint = Vector2.new(0.5, 0.5)
mobileEnterButton.Position = UDim2.fromScale(0.60, 0.74)
mobileEnterButton.Size = UDim2.fromOffset(118, 64)
mobileEnterButton.BackgroundColor3 = Color3.fromRGB(196, 48, 42)
mobileEnterButton.BackgroundTransparency = 0.08
mobileEnterButton.BorderSizePixel = 0
mobileEnterButton.Text = "DRIVE"
mobileEnterButton.TextColor3 = Color3.new(1, 1, 1)
mobileEnterButton.Font = Enum.Font.GothamBold
mobileEnterButton.TextScaled = true
mobileEnterButton.Visible = false
mobileEnterButton.Parent = gui
local mobileEnterCorner = Instance.new("UICorner")
mobileEnterCorner.CornerRadius = UDim.new(0, 12)
mobileEnterCorner.Parent = mobileEnterButton

mobileEnterButton.Activated:Connect(function()
	if not UserInputService.TouchEnabled or player:GetAttribute("DrivingFireTruck") == true then return end
	vehicleEnter:FireServer()
end)

local bannerVersion = 0
local held = {W=false, A=false, S=false, D=false}
local actionsBound = false
local mobileDriveButtons = {}
if UserInputService.TouchEnabled then
	local layout = {
		DispatchForward = {"GO", UDim2.new(1, -235, 1, -168)},
		DispatchBackward = {"BACK", UDim2.new(1, -235, 1, -72)},
		DispatchLeft = {"<", UDim2.new(1, -305, 1, -120)},
		DispatchRight = {">", UDim2.new(1, -165, 1, -120)},
		DispatchExit = {"EXIT", UDim2.new(1, -165, 1, -200)},
	}
	for name, config in pairs(layout) do
		local button = Instance.new("TextButton")
		button.Name = name
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = config[2]
		button.Size = UDim2.fromOffset(64, 64)
		button.BackgroundColor3 = Color3.fromRGB(28, 42, 58)
		button.BackgroundTransparency = 0.08
		button.BorderSizePixel = 0
		button.Text = config[1]
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.Visible = false
		button.Parent = gui
		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0.5, 0)
		buttonCorner.Parent = button
		mobileDriveButtons[name] = button
	end
end

local function showBanner(text, seconds, green)
	bannerVersion += 1
	local version = bannerVersion
	banner.Text = tostring(text or "")
	banner.BackgroundColor3 = green and Color3.fromRGB(40, 145, 77) or Color3.fromRGB(190, 42, 38)
	banner.Visible = true
	banner.TextTransparency = 0
	banner.BackgroundTransparency = 0.08
	if seconds then
		task.delay(seconds, function()
			if version ~= bannerVersion then return end
			TweenService:Create(banner, TweenInfo.new(0.35), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
			task.delay(0.4, function()
				if version == bannerVersion then banner.Visible = false end
			end)
		end)
	end
end

local function updateMobileEnterButton()
	if not UserInputService.TouchEnabled or player:GetAttribute("DrivingFireTruck") == true then
		mobileEnterButton.Visible = false
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	mobileEnterButton.Visible = drivePrompt.Enabled
		and root ~= nil
		and (root.Position - vehicleRoot.Position).Magnitude <= drivePrompt.MaxActivationDistance + 4
end

local function sendInput()
	local throttle = (held.W and 1 or 0) + (held.S and -1 or 0)
	local steering = (held.D and 1 or 0) + (held.A and -1 or 0)
	vehicleInput:FireServer(throttle, steering)
end

local function driveAction(actionName, state)
	local down = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
	if actionName == "DispatchForward" then held.W = down
	elseif actionName == "DispatchBackward" then held.S = down
	elseif actionName == "DispatchLeft" then held.A = down
	elseif actionName == "DispatchRight" then held.D = down
	elseif actionName == "DispatchExit" and state == Enum.UserInputState.Begin then
		vehicleExit:FireServer()
	end
	sendInput()
	return Enum.ContextActionResult.Sink
end

local function isDrivePointer(input)
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

for name, button in pairs(mobileDriveButtons) do
	button.InputBegan:Connect(function(input)
		if isDrivePointer(input) then
			driveAction(name, Enum.UserInputState.Begin)
		end
	end)
	button.InputEnded:Connect(function(input)
		if isDrivePointer(input) then
			driveAction(name, Enum.UserInputState.End)
		end
	end)
end

local function bindDriving()
	if actionsBound then return end
	actionsBound = true
	local priority = Enum.ContextActionPriority.High.Value + 50
	ContextActionService:BindActionAtPriority("DispatchForward", driveAction, false, priority, Enum.KeyCode.W, Enum.KeyCode.Up)
	ContextActionService:BindActionAtPriority("DispatchBackward", driveAction, false, priority, Enum.KeyCode.S, Enum.KeyCode.Down)
	ContextActionService:BindActionAtPriority("DispatchLeft", driveAction, false, priority, Enum.KeyCode.A, Enum.KeyCode.Left)
	ContextActionService:BindActionAtPriority("DispatchRight", driveAction, false, priority, Enum.KeyCode.D, Enum.KeyCode.Right)
	ContextActionService:BindActionAtPriority("DispatchExit", driveAction, false, priority, Enum.KeyCode.E, Enum.KeyCode.Space)
	if UserInputService.TouchEnabled then
		for _, button in pairs(mobileDriveButtons) do
			button.Visible = true
		end
	end
	controls.Visible = not UserInputService.TouchEnabled
end

local function unbindDriving()
	if not actionsBound then return end
	vehicleInput:FireServer(0, 0)
	for _, name in ipairs({"DispatchForward","DispatchBackward","DispatchLeft","DispatchRight","DispatchExit"}) do
		ContextActionService:UnbindAction(name)
	end
	table.clear(held)
	held.W, held.A, held.S, held.D = false, false, false, false
	for _, button in pairs(mobileDriveButtons) do
		button.Visible = false
	end
	actionsBound = false
	controls.Visible = false
end

player:GetAttributeChangedSignal("DrivingFireTruck"):Connect(function()
	if player:GetAttribute("DrivingFireTruck") == true then bindDriving() else unbindDriving() end
end)
if player:GetAttribute("DrivingFireTruck") == true then bindDriving() end

local inputAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	updateMobileEnterButton()
	if not actionsBound then
		inputAccumulator = 0
		return
	end
	inputAccumulator += dt
	if inputAccumulator >= 0.12 then
		inputAccumulator = 0
		sendInput()
	end
end)

dispatchMessage.OnClientEvent:Connect(function(action, text)
	if action == "DispatchCall" then
		showBanner(text, nil, false)
	elseif action == "Driving" then
		showBanner(text, 4, false)
	elseif action == "Arrived" then
		showBanner(text, 6, true)
	elseif action == "Exited" or action == "Notice" then
		showBanner(text, 4, action == "Exited" and gate:GetAttribute("DispatchArrived") == true)
	end
end)

vehicleInput.OnClientEvent:Connect(function(action)
	if action == "ForceStop" then
		unbindDriving()
	end
end)

gate:GetAttributeChangedSignal("DispatchArrived"):Connect(function()
	if gate:GetAttribute("DispatchArrived") == true then
		showBanner("ТЫ НА МЕСТЕ — ВЫХОДИ И БЕРИ ШЛАНГ", 6, true)
	end
end)

task.delay(1, function()
	if gate:GetAttribute("DispatchArrived") ~= true then
		showBanner("ПОЖАР! САДИСЬ В МАШИНУ", nil, false)
	end
end)