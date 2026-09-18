local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local gameplay = script.Parent
local gate = gameplay.Parent
local missionType = gameplay:WaitForChild("MissionType")
local activeMission = gameplay:WaitForChild("ActiveMission")
local pet = gameplay:WaitForChild("PetRescueTarget")
local petBody = pet:WaitForChild("Body")
local petHead = pet:WaitForChild("Head")
local prompt = petHead:WaitForChild("PetPromptAttachment"):WaitForChild("TakeKittenPrompt")
local objectiveBillboard = petHead:WaitForChild("PetObjectiveBillboard")
local interior = gameplay:WaitForChild("InteriorV2")
local resident = interior:WaitForChild("RescueResident")
local residentPrompt = resident:WaitForChild("Torso"):WaitForChild("RescuePrompt")
local safeZone = gameplay:WaitForChild("RescueSafeZone")
local successAnchor = gameplay:WaitForChild("SuccessAnchor")
local successBillboard = successAnchor:WaitForChild("SuccessBillboard")
local missionMessage = gameplay:WaitForChild("MissionMessage")
local resetRequest = gameplay:WaitForChild("ResetMissionRequest")
local newCallPrompt = successAnchor:FindFirstChild("NewCallPrompt")
if not newCallPrompt then
	newCallPrompt = Instance.new("ProximityPrompt")
	newCallPrompt.Name = "NewCallPrompt"
	newCallPrompt.Parent = successAnchor
end
newCallPrompt.ActionText = utf8.char(1053,1086,1074,1099,1081,32,1074,1099,1079,1086,1074)
newCallPrompt.ObjectText = utf8.char(1044,1080,1089,1087,1077,1090,1095,1077,1088)
newCallPrompt.HoldDuration = 0.35
newCallPrompt.MaxActivationDistance = 10
newCallPrompt.RequiresLineOfSight = false
newCallPrompt.Enabled = false

local roofMission = gameplay:WaitForChild("PetRoofRescueV2")
local roofLanding = roofMission:WaitForChild("RoofLanding")
local ladderTopTarget = roofMission:WaitForChild("LadderTopTarget")
local truck = gate:WaitForChild("FiretruckPreview")
local ladder = truck:WaitForChild("LadderAssembly")
local ladderPrompt = ladder:WaitForChild("LadderPromptBase")
	:WaitForChild("LadderPromptAttachment"):WaitForChild("DeployLadderPrompt")
local baseTurntable = ladder:WaitForChild("BaseTurntable")
local leftRail = ladder:WaitForChild("LeftRail")
local rightRail = ladder:WaitForChild("RightRail")
local walkway = ladder:WaitForChild("LadderWalkway")
local accessLadder = ladder:WaitForChild("AccessLadder")
local accessPlatform = ladder:WaitForChild("AccessPlatform")

local VALID = {Resident = true, Pet = true, Random = true}
local random = Random.new()
local initialPetPivot = pet:GetAttribute("InitialPivot")
local petOwnerUserId = nil
local completing = false
local deploying = false
local roofNoticeShown = {}

local DEPLOY_RAISE_TIME = 0.9
local DEPLOY_EXTEND_TIME = 1.5
local LADDER_WIDTH = 3.1
local RUNG_COUNT = 20

local function rememberResidentAppearance()
	for _, descendant in ipairs(resident:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant:GetAttribute("PetMissionOriginalTransparency") == nil then
				descendant:SetAttribute("PetMissionOriginalTransparency", descendant.Transparency)
				descendant:SetAttribute("PetMissionOriginalCanCollide", descendant.CanCollide)
				descendant:SetAttribute("PetMissionOriginalCanQuery", descendant.CanQuery)
			end
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			if descendant:GetAttribute("PetMissionOriginalTransparency") == nil then
				descendant:SetAttribute("PetMissionOriginalTransparency", descendant.Transparency)
			end
		end
	end
end

local function rememberPetAppearance()
	for _, descendant in ipairs(pet:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("PetVisibleTransparency") == nil then
			descendant:SetAttribute("PetVisibleTransparency", descendant.Transparency)
		end
	end
end

local function setResidentVisible(visible)
	for _, descendant in ipairs(resident:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local original = descendant:GetAttribute("PetMissionOriginalTransparency")
			descendant.Transparency = visible and (typeof(original) == "number" and original or 0) or 1
			descendant.CanCollide = visible and descendant:GetAttribute("PetMissionOriginalCanCollide") == true
			descendant.CanQuery = visible and descendant:GetAttribute("PetMissionOriginalCanQuery") ~= false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			local original = descendant:GetAttribute("PetMissionOriginalTransparency")
			descendant.Transparency = visible and (typeof(original) == "number" and original or 0) or 1
		end
	end
	resident.Humanoid.DisplayDistanceType = visible
		and Enum.HumanoidDisplayDistanceType.Viewer or Enum.HumanoidDisplayDistanceType.None
	local instruction = resident:FindFirstChild("FollowerInstruction", true)
	if instruction and instruction:IsA("BillboardGui") and not visible then
		instruction.Enabled = false
	end
	if not visible then
		residentPrompt.Enabled = false
	end
end

local function setPetPartsVisible(visible)
	for _, descendant in ipairs(pet:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local original = descendant:GetAttribute("PetVisibleTransparency")
			descendant.Transparency = visible and (typeof(original) == "number" and original or 0) or 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = visible
		end
	end
	objectiveBillboard.Enabled = visible
		and pet:GetAttribute("PetState") == "Waiting"
		and gate:GetAttribute("PetRescued") ~= true
end

local function setPetAnchored(anchored)
	for _, descendant in ipairs(pet:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = not anchored
		end
	end
end

local function clearCarryWeld()
	local weld = petBody:FindFirstChild("PetCarryWeld")
	if weld then weld:Destroy() end
end

local function clearPlayerCarryAttributes()
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("CarryingPet", false)
	end
end

local function sendToPlayer(player, text, duration)
	if player and player.Parent then
		missionMessage:FireClient(player, "Ready", text, duration or 4)
	end
end

local function sendToAll(text, duration)
	for _, player in ipairs(Players:GetPlayers()) do
		sendToPlayer(player, text, duration)
	end
end

local function setLadderState(state)
	ladder:SetAttribute("State", state)
	roofMission:SetAttribute("LadderState", state)
	gate:SetAttribute("LadderState", state)
end

local function setLadderVisible(visible)
	for _, descendant in ipairs(ladder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant == ladder:FindFirstChild("LadderPromptBase") or descendant == walkway then
				descendant.Transparency = 1
			else
				local stored = descendant:GetAttribute("StoredTransparency")
				descendant.Transparency = visible and (typeof(stored) == "number" and stored or 0) or 1
			end
			descendant.CanTouch = false
			descendant.CanQuery = false
			if descendant ~= walkway and descendant ~= accessLadder and descendant ~= accessPlatform then
				descendant.CanCollide = false
			end
		end
	end
end

local function restoreStoredLadder()
	deploying = false
	setLadderState("Retracting")
	local pivot = truck:GetPivot()
	for _, descendant in ipairs(ladder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local relative = descendant:GetAttribute("StoredRelativeCFrame")
			local size = descendant:GetAttribute("StoredSize")
			if typeof(relative) == "CFrame" then descendant.CFrame = pivot * relative end
			if typeof(size) == "Vector3" then descendant.Size = size end
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	roofLanding.CanCollide = false
	roofLanding.CanTouch = false
	roofLanding.CanQuery = false
	ladder:SetAttribute("DeployedLength", 0)
	ladder:SetAttribute("DeployedAngleDegrees", 0)
	setLadderState("Stored")
end

local function setRoofMissionVisible(visible)
	setLadderVisible(visible)
	roofLanding.Transparency = visible and 0.08 or 1
	local deployed = visible and ladder:GetAttribute("State") == "Deployed"
	roofLanding.CanCollide = deployed
	roofLanding.CanQuery = deployed
	accessLadder.CanCollide = deployed
	accessLadder.CanQuery = deployed
	accessPlatform.CanCollide = deployed
	accessPlatform.CanQuery = deployed
end

local function clearRoofNotices()
	table.clear(roofNoticeShown)
end

local function resetPetState()
	clearCarryWeld()
	clearPlayerCarryAttributes()
	petOwnerUserId = nil
	completing = false
	setPetAnchored(true)
	if typeof(initialPetPivot) == "CFrame" then
		pet:PivotTo(initialPetPivot)
	end
	pet:SetAttribute("PetState", "Waiting")
	gate:SetAttribute("PetRescued", false)
	gate:SetAttribute("PetCarried", false)
	gate:SetAttribute("PetMissionComplete", false)
	gate:SetAttribute("MissionCompleted", false)
	roofMission:SetAttribute("PetMissionComplete", false)
	successBillboard.Enabled = false
	newCallPrompt.Enabled = false
	clearRoofNotices()
	restoreStoredLadder()
end

local function chooseMission(avoidMission)
	local requested = missionType.Value
	if not VALID[requested] then
		requested = "Random"
		missionType.Value = "Random"
	end
	local selected = requested
	if requested == "Random" then
		if avoidMission == "Resident" then
			selected = "Pet"
		elseif avoidMission == "Pet" then
			selected = "Resident"
		else
			selected = random:NextInteger(1, 2) == 1 and "Resident" or "Pet"
		end
	end
	activeMission.Value = selected
	gate:SetAttribute("ActiveMission", selected)
	return selected
end

local function ladderLayout(basePosition, topPosition, lengthOverride)
	local delta = topPosition - basePosition
	local fullLength = delta.Magnitude
	local direction = delta.Unit
	local length = lengthOverride or fullLength
	local endPosition = basePosition + direction * length
	local center = (basePosition + endPosition) * 0.5
	local up = math.abs(direction:Dot(Vector3.yAxis)) > 0.94 and Vector3.zAxis or Vector3.yAxis
	return CFrame.lookAt(center, endPosition, up), length, fullLength, direction
end

local function goalForPart(part, frame, length)
	if part == leftRail then
		return frame * CFrame.new(-LADDER_WIDTH * 0.5, 0.24, 0), Vector3.new(0.2, 0.2, length)
	elseif part == rightRail then
		return frame * CFrame.new(LADDER_WIDTH * 0.5, 0.24, 0), Vector3.new(0.2, 0.2, length)
	elseif part == walkway then
		return frame, Vector3.new(LADDER_WIDTH + 0.25, 0.18, length)
	end
	local index = part:GetAttribute("RungIndex")
	if typeof(index) == "number" then
		local alpha = RUNG_COUNT == 1 and 0.5 or (index - 1) / (RUNG_COUNT - 1)
		local z = length * 0.5 - 0.45 - alpha * math.max(0.1, length - 0.9)
		return frame * CFrame.new(0, 0.28, z), Vector3.new(LADDER_WIDTH, 0.18, 0.24)
	end
	return nil, nil
end

local function tweenLadderLayout(frame, length, duration)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tweens = {}
	for _, part in ipairs(ladder:GetChildren()) do
		if part:IsA("BasePart") then
			local goalCF, goalSize = goalForPart(part, frame, length)
			if goalCF and goalSize then
				local tween = TweenService:Create(part, info, {CFrame = goalCF, Size = goalSize})
				table.insert(tweens, tween)
				tween:Play()
			end
		end
	end
	task.wait(duration)
	for _, tween in ipairs(tweens) do tween:Cancel() end
	for _, part in ipairs(ladder:GetChildren()) do
		if part:IsA("BasePart") then
			local goalCF, goalSize = goalForPart(part, frame, length)
			if goalCF and goalSize then
				part.CFrame = goalCF
				part.Size = goalSize
			end
		end
	end
end

local function refreshLadderPrompt()
	local petMission = activeMission.Value == "Pet"
	local state = ladder:GetAttribute("State")
	if not petMission or gate:GetAttribute("DispatchArrived") ~= true then
		ladderPrompt.Enabled = false
		return
	end
	ladderPrompt.ObjectText = "Пожарная автолестница"
	if state == "Stored" then
		ladderPrompt.Enabled = true
		ladderPrompt.ActionText = gate:GetAttribute("ExteriorFiresOut") == true
			and "Развернуть лестницу" or "СНАЧАЛА ПОТУШИ ОГОНЬ"
	else
		ladderPrompt.Enabled = false
		ladderPrompt.ActionText = state == "Deployed" and "Лестница развёрнута" or "Лестница движется"
	end
end

local function refreshPetPrompt()
	local available = activeMission.Value == "Pet"
		and ladder:GetAttribute("State") == "Deployed"
		and gate:GetAttribute("PetRescued") ~= true
		and gate:GetAttribute("PetCarried") ~= true
		and pet:GetAttribute("PetState") == "Waiting"
	prompt.Enabled = available
	objectiveBillboard.Enabled = activeMission.Value == "Pet"
		and pet:GetAttribute("PetState") == "Waiting"
		and gate:GetAttribute("PetRescued") ~= true
	if activeMission.Value == "Pet" then residentPrompt.Enabled = false end
end

local function deployLadder(player)
	if deploying or activeMission.Value ~= "Pet" or ladder:GetAttribute("State") ~= "Stored" then
		return
	end
	if gate:GetAttribute("ExteriorFiresOut") ~= true then
		sendToPlayer(player, "СНАЧАЛА ПОТУШИ ОГОНЬ", 3)
		refreshLadderPrompt()
		return
	end
	if gate:GetAttribute("DispatchArrived") ~= true then return end

	deploying = true
	setLadderState("Deploying")
	refreshLadderPrompt()
	refreshPetPrompt()
	sendToPlayer(player, "АВТОЛЕСТНИЦА РАЗВОРАЧИВАЕТСЯ", 3)

	local basePosition = baseTurntable.Position + Vector3.new(0, 0.72, 0)
	local targetPosition = ladderTopTarget.Position
	local _, _, fullLength, direction = ladderLayout(basePosition, targetPosition)
	local compressed = math.min(12, fullLength * 0.55)
	local raisedFrame = ladderLayout(basePosition, targetPosition, compressed)
	tweenLadderLayout(raisedFrame, compressed, DEPLOY_RAISE_TIME)
	local finalFrame, finalLength = ladderLayout(basePosition, targetPosition)
	tweenLadderLayout(finalFrame, finalLength, DEPLOY_EXTEND_TIME)

	local horizontal = Vector3.new(direction.X, 0, direction.Z).Magnitude
	local angle = math.deg(math.atan2(math.abs(direction.Y), math.max(0.001, horizontal)))
	ladder:SetAttribute("DeployedLength", finalLength)
	ladder:SetAttribute("DeployedAngleDegrees", angle)
	walkway.CanCollide = true
	walkway.CanQuery = true
	accessLadder.CanCollide = true
	accessLadder.CanQuery = true
	accessPlatform.CanCollide = true
	accessPlatform.CanQuery = true
	roofLanding.CanCollide = true
	roofLanding.CanQuery = true
	setLadderState("Deployed")
	deploying = false
	refreshLadderPrompt()
	refreshPetPrompt()
	sendToAll("ПОДНИМИСЬ ПО ЛЕСТНИЦЕ К КОТЁНКУ", 6)
end

local function applyMission(announce, preserveSelection, avoidMission)
	resetPetState()
	local selected
	if preserveSelection and (activeMission.Value == "Resident" or activeMission.Value == "Pet") then
		selected = activeMission.Value
		gate:SetAttribute("ActiveMission", selected)
	else
		selected = chooseMission(avoidMission)
	end
	local petMission = selected == "Pet"
	setPetPartsVisible(petMission)
	setResidentVisible(not petMission)
	setRoofMissionVisible(petMission)
	if petMission then
		gate:SetAttribute("RescueFollowerActive", false)
		gate:SetAttribute("ResidentAtInteriorExit", false)
		gate:SetAttribute("RescueReady", false)
	end
	refreshLadderPrompt()
	refreshPetPrompt()
	if announce then
		task.delay(0.35, function()
			if activeMission.Value == selected then
				sendToAll(petMission
					and "КОТЁНОК ЗАСТРЯЛ НА КРЫШЕ!"
					or "В ДОМЕ ОСТАЛСЯ ЧЕЛОВЕК!", 5)
			end
		end)
	end
end

local function attachPet(player)
	if activeMission.Value ~= "Pet"
		or ladder:GetAttribute("State") ~= "Deployed"
		or gate:GetAttribute("PetCarried") == true
		or gate:GetAttribute("PetRescued") == true then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	if not humanoid or humanoid.Health <= 0 or not root or not torso then return end
	if (root.Position - pet:GetPivot().Position).Magnitude > prompt.MaxActivationDistance + 2 then return end

	clearCarryWeld()
	setPetAnchored(false)
	pet:PivotTo(torso.CFrame * CFrame.new(0, -0.05, -1.65))
	local weld = Instance.new("WeldConstraint")
	weld.Name = "PetCarryWeld"
	weld.Part0 = torso
	weld.Part1 = petBody
	weld.Parent = petBody

	petOwnerUserId = player.UserId
	player:SetAttribute("CarryingPet", true)
	gate:SetAttribute("PetCarried", true)
	pet:SetAttribute("PetState", "Carried")
	prompt.Enabled = false
	objectiveBillboard.Enabled = false
	sendToPlayer(player, "СПУСТИСЬ ПО ЛЕСТНИЦЕ И ОТНЕСИ КОТЁНКА В БЕЗОПАСНУЮ ЗОНУ", 7)
end

local function pointInSafeZone(position)
	local localPosition = safeZone.CFrame:PointToObjectSpace(position)
	return math.abs(localPosition.X) <= safeZone.Size.X * 0.5 + 1
		and math.abs(localPosition.Z) <= safeZone.Size.Z * 0.5 + 1
		and math.abs(localPosition.Y) <= 8
end

local function completePetRescue(player)
	if completing
		or activeMission.Value ~= "Pet"
		or gate:GetAttribute("PetRescued") == true
		or player.UserId ~= petOwnerUserId
		or player:GetAttribute("CarryingPet") ~= true then
		return
	end
	completing = true
	clearCarryWeld()
	player:SetAttribute("CarryingPet", false)
	gate:SetAttribute("PetCarried", false)
	gate:SetAttribute("PetRescued", true)
	gate:SetAttribute("PetMissionComplete", true)
	gate:SetAttribute("MissionCompleted", true)
	roofMission:SetAttribute("PetMissionComplete", true)
	pet:SetAttribute("PetState", "Safe")
	setPetAnchored(true)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local safePosition = safeZone.Position + Vector3.new(0, 1.45, 0)
	if root then
		local look = Vector3.new(root.Position.X, safePosition.Y, root.Position.Z)
		pet:PivotTo((look - safePosition).Magnitude > 0.1
			and CFrame.lookAt(safePosition, look) or CFrame.new(safePosition))
	else
		pet:PivotTo(CFrame.new(safePosition))
	end
	objectiveBillboard.Enabled = false
	successAnchor.Position = safePosition + Vector3.new(0, 3.1, 0)
	successBillboard.Message.Text = "КОТЁНОК СПАСЁН!"
	successBillboard.Enabled = true
	sendToPlayer(player, "КОТЁНОК СПАСЁН!", 7)
	petOwnerUserId = nil
end

prompt.Triggered:Connect(attachPet)
ladderPrompt.Triggered:Connect(function(player)
	if gate:GetAttribute("ExteriorFiresOut") == true then
		deployLadder(player)
	else
		sendToPlayer(player, "СНАЧАЛА ПОТУШИ ОГОНЬ", 3)
	end
end)

gate:GetAttributeChangedSignal("ExteriorFiresOut"):Connect(function()
	refreshLadderPrompt()
	if gate:GetAttribute("ExteriorFiresOut") == true and activeMission.Value == "Pet" then
		task.delay(0.2, function()
			if activeMission.Value == "Pet" and gate:GetAttribute("ExteriorFiresOut") == true then
				sendToAll("ПУТЬ К КОТЁНКУ БЕЗОПАСЕН — РАЗВЕРНИ ЛЕСТНИЦУ", 6)
			end
		end)
	end
end)

gate:GetAttributeChangedSignal("DispatchArrived"):Connect(refreshLadderPrompt)
ladder:GetAttributeChangedSignal("State"):Connect(function()
	refreshLadderPrompt()
	refreshPetPrompt()
end)

residentPrompt:GetPropertyChangedSignal("Enabled"):Connect(function()
	if activeMission.Value == "Pet" and residentPrompt.Enabled then
		task.defer(function()
			if activeMission.Value == "Pet" then residentPrompt.Enabled = false end
		end)
	end
end)

local function refreshNewCallPrompt()
	newCallPrompt.Enabled = gate:GetAttribute("MissionCompleted") == true
end

gate:GetAttributeChangedSignal("MissionCompleted"):Connect(refreshNewCallPrompt)
newCallPrompt.Triggered:Connect(function(player)
	if gate:GetAttribute("MissionCompleted") ~= true then return end
	newCallPrompt.Enabled = false
	sendToPlayer(player, "НОВЫЙ ВЫЗОВ — ВОЗВРАЩАЕМСЯ НА СТАНЦИЮ", 3)
	resetRequest:Fire("NewMission")
end)

missionType.Changed:Connect(function()
	applyMission(true, false)
end)

resetRequest.Event:Connect(function(reason)
	if typeof(reason) == "Instance"
		and reason:IsA("Player")
		and #Players:GetPlayers() > 1 then
		return
	end
	local previousMission = activeMission.Value
	task.defer(function()
		task.wait(0.1)
		applyMission(true, reason ~= "NewMission", reason == "NewMission" and previousMission or nil)
	end)
end)

local function returnCarriedPetAfterPlayerLoss(player)
	if petOwnerUserId ~= player.UserId or gate:GetAttribute("PetCarried") ~= true then return end
	clearCarryWeld()
	player:SetAttribute("CarryingPet", false)
	petOwnerUserId = nil
	setPetAnchored(true)
	if typeof(initialPetPivot) == "CFrame" then pet:PivotTo(initialPetPivot) end
	pet:SetAttribute("PetState", "Waiting")
	gate:SetAttribute("PetCarried", false)
	refreshPetPrompt()
	if activeMission.Value == "Pet" and gate:GetAttribute("MissionCompleted") ~= true then
		sendToAll("КОТЁНОК СНОВА НА КРЫШЕ — ЗАБЕРИ ЕГО", 5)
	end
end

local function preparePlayer(player)
	player:SetAttribute("CarryingPet", false)
	player.CharacterRemoving:Connect(function()
		returnCarriedPetAfterPlayerLoss(player)
	end)
	task.delay(3, function()
		if player.Parent and activeMission.Value == "Pet" then
			sendToPlayer(player, "КОТЁНОК ЗАСТРЯЛ НА КРЫШЕ!", 5)
		end
	end)
end
for _, player in ipairs(Players:GetPlayers()) do preparePlayer(player) end
Players.PlayerAdded:Connect(preparePlayer)
Players.PlayerRemoving:Connect(returnCarriedPetAfterPlayerLoss)

RunService.Heartbeat:Connect(function()
	if activeMission.Value ~= "Pet" then return end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root then
			if gate:GetAttribute("DispatchArrived") == true
				and not roofNoticeShown[player]
				and (root.Position - roofLanding.Position).Magnitude <= 55 then
				roofNoticeShown[player] = true
				sendToPlayer(player, "КОТЁНОК ЗАСТРЯЛ НА КРЫШЕ!", 5)
			end
			if gate:GetAttribute("PetCarried") == true
				and petOwnerUserId == player.UserId
				and pointInSafeZone(root.Position) then
				completePetRescue(player)
			end
		end
	end
end)

rememberResidentAppearance()
rememberPetAppearance()
applyMission(false, false)
refreshNewCallPrompt()
print("Pet Roof Rescue V2 ready; MissionType=" .. missionType.Value .. ", ActiveMission=" .. activeMission.Value)