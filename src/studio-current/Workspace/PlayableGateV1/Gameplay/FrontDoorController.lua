local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local gameplay = script.Parent
local gate = gameplay.Parent
local activeMission = gameplay:WaitForChild("ActiveMission")
local system = gameplay:WaitForChild("FrontDoorSystem")
local exteriorDoor = system:WaitForChild("ExteriorFrontDoor")
local interiorDoor = system:WaitForChild("InteriorFrontDoor")
local exteriorAssembly = exteriorDoor:WaitForChild("DoorAssembly")
local interiorAssembly = interiorDoor:WaitForChild("DoorAssembly")
local exteriorLeaf = exteriorAssembly:WaitForChild("DoorLeaf")
local interiorLeaf = interiorAssembly:WaitForChild("DoorLeaf")
local exteriorBlocker = system:WaitForChild("ExteriorDoorBlocker")
local interiorBlocker = system:WaitForChild("InteriorDoorBlocker")
local exteriorZone = system:WaitForChild("ExteriorDoorSafetyZone")
local interiorZone = system:WaitForChild("InteriorDoorSafetyZone")
local exteriorPrompt = exteriorLeaf:WaitForChild("ExteriorDoorPromptAttachment"):WaitForChild("ExteriorDoorPrompt")
local interiorPrompt = interiorLeaf:WaitForChild("InteriorDoorPromptAttachment"):WaitForChild("InteriorDoorPrompt")
local missionMessage = gameplay:WaitForChild("MissionMessage")
local rescueResident = gameplay:WaitForChild("InteriorV2"):WaitForChild("RescueResident")

local MOVE_TIME = 0.5
local tweenInfo = TweenInfo.new(MOVE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local transitioning = false

local function pointInZone(point, zone)
	local p = zone.CFrame:PointToObjectSpace(point)
	local h = zone.Size * 0.5
	return math.abs(p.X) <= h.X
		and math.abs(p.Y) <= h.Y
		and math.abs(p.Z) <= h.Z
end

local function playerInZone(player, zone)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return pointInZone(root.Position, zone)
end

local function doorwayOccupied()
	for _, player in Players:GetPlayers() do
		if playerInZone(player, exteriorZone) or playerInZone(player, interiorZone) then
			return true
		end
	end

	local followerRoot = rescueResident:FindFirstChild("HumanoidRootPart")
	if followerRoot
		and gate:GetAttribute("RescueFollowerActive") == true
		and gate:GetAttribute("ResidentRescued") ~= true
		and (pointInZone(followerRoot.Position, exteriorZone) or pointInZone(followerRoot.Position, interiorZone)) then
		return true
	end
	return false
end

local function setPromptState()
	local petMission = activeMission.Value == "Pet"
	local firesOut = gate:GetAttribute("ExteriorFiresOut") == true
	local isOpen = gate:GetAttribute("FrontDoorOpen") == true
	for _, prompt in {exteriorPrompt, interiorPrompt} do
		prompt.ObjectText = "Входная дверь"
		if petMission then
			prompt.ActionText = "Вход не нужен"
		elseif not firesOut then
			prompt.ActionText = "Сначала потуши пожар"
		elseif isOpen then
			prompt.ActionText = "Закрыть дверь"
		else
			prompt.ActionText = "Открыть дверь"
		end
		prompt.Enabled = not transitioning and not petMission
	end
end

local function setMovingCollision()
	exteriorLeaf.CanCollide = false
	interiorLeaf.CanCollide = false
	exteriorBlocker.CanCollide = false
	interiorBlocker.CanCollide = false
end

local function setClosedCollision()
	exteriorLeaf.CanCollide = true
	interiorLeaf.CanCollide = true
	exteriorBlocker.CanCollide = true
	interiorBlocker.CanCollide = true
end

local function createAssemblyTween(assembly, goal)
	local start = assembly:GetPivot()
	local value = Instance.new("NumberValue")
	value.Value = 0
	value.Parent = script
	local connection = value:GetPropertyChangedSignal("Value"):Connect(function()
		assembly:PivotTo(start:Lerp(goal, value.Value))
	end)
	local tween = TweenService:Create(value, tweenInfo, {Value = 1})
	return tween, value, connection
end

local function tweenDoors(exteriorGoal, interiorGoal)
	local exteriorTween, exteriorValue, exteriorConnection = createAssemblyTween(exteriorAssembly, exteriorGoal)
	local interiorTween, interiorValue, interiorConnection = createAssemblyTween(interiorAssembly, interiorGoal)
	exteriorTween:Play()
	interiorTween:Play()
	exteriorTween.Completed:Wait()
	exteriorAssembly:PivotTo(exteriorGoal)
	interiorAssembly:PivotTo(interiorGoal)
	exteriorConnection:Disconnect()
	interiorConnection:Disconnect()
	exteriorValue:Destroy()
	interiorValue:Destroy()
end

local function openDoor(player)
	if activeMission.Value == "Pet" then
		missionMessage:FireClient(player, "Blocked", "КОТЁНОК НА КРЫШЕ — ИСПОЛЬЗУЙ АВТОЛЕСТНИЦУ", 3)
		setPromptState()
		return
	end
	if transitioning or gate:GetAttribute("FrontDoorOpen") == true then
		return
	end
	if gate:GetAttribute("ExteriorFiresOut") ~= true then
		missionMessage:FireClient(player, "Blocked", "Сначала потуши огонь снаружи", 2.4)
		setPromptState()
		return
	end

	transitioning = true
	gate:SetAttribute("FrontDoorTransitioning", true)
	setPromptState()
	setMovingCollision()
	tweenDoors(
		exteriorAssembly:GetAttribute("OpenPivot"),
		interiorAssembly:GetAttribute("OpenPivot")
	)
	gate:SetAttribute("FrontDoorOpen", true)
	transitioning = false
	gate:SetAttribute("FrontDoorTransitioning", false)
	setPromptState()
end

local function closeDoor(player)
	if transitioning or gate:GetAttribute("FrontDoorOpen") ~= true then
		return
	end
	if doorwayOccupied() then
		missionMessage:FireClient(player, "Blocked", "Освободи дверной проём", 1.8)
		return
	end

	transitioning = true
	gate:SetAttribute("FrontDoorTransitioning", true)
	gate:SetAttribute("FrontDoorOpen", false)
	setPromptState()
	setMovingCollision()
	tweenDoors(
		exteriorAssembly:GetAttribute("ClosedPivot"),
		interiorAssembly:GetAttribute("ClosedPivot")
	)

	-- Keep moving panels non-collidable and reopen if someone entered the doorway
	-- during the half-second closing motion.
	if doorwayOccupied() then
		tweenDoors(
			exteriorAssembly:GetAttribute("OpenPivot"),
			interiorAssembly:GetAttribute("OpenPivot")
		)
		gate:SetAttribute("FrontDoorOpen", true)
	else
		setClosedCollision()
	end
	transitioning = false
	gate:SetAttribute("FrontDoorTransitioning", false)
	setPromptState()
end

local function onTriggered(player)
	if transitioning then
		return
	end
	if gate:GetAttribute("FrontDoorOpen") == true then
		closeDoor(player)
	else
		openDoor(player)
	end
end

exteriorPrompt.Triggered:Connect(onTriggered)
interiorPrompt.Triggered:Connect(onTriggered)
gate:GetAttributeChangedSignal("ExteriorFiresOut"):Connect(setPromptState)
activeMission.Changed:Connect(function()
	if activeMission.Value == "Pet" then
		gate:SetAttribute("FrontDoorOpen", false)
		exteriorAssembly:PivotTo(exteriorAssembly:GetAttribute("ClosedPivot"))
		interiorAssembly:PivotTo(interiorAssembly:GetAttribute("ClosedPivot"))
		setClosedCollision()
	end
	setPromptState()
end)

gate:SetAttribute("FrontDoorOpen", false)
gate:SetAttribute("FrontDoorTransitioning", false)
exteriorAssembly:PivotTo(exteriorAssembly:GetAttribute("ClosedPivot"))
interiorAssembly:PivotTo(interiorAssembly:GetAttribute("ClosedPivot"))
setClosedCollision()
setPromptState()
