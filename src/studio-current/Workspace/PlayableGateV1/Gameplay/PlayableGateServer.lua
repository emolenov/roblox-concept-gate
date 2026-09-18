-- Exterior fire gate extends the existing playable mission without changing its interior rules.
local Players = game:GetService("Players")

local gameplay = script.Parent
local gate = gameplay.Parent
local activeMission = gameplay:WaitForChild("ActiveMission")
local spawnLocation = gate:WaitForChild("FirefighterSpawn")
local hoseStation = gameplay:WaitForChild("HoseStation")
local hoseStationVisual = hoseStation:WaitForChild("HoseStationVisual")
local dockedNozzle = hoseStationVisual:WaitForChild("DockedNozzle")
local hoseCoil = hoseStationVisual:WaitForChild("HoseCoil")
local prompt = dockedNozzle:WaitForChild("NozzleGrip"):WaitForChild("TakeHosePrompt")
local hoseLine = hoseStation:WaitForChild("HoseLine")
local hoseHint = hoseStation:WaitForChild("TakeHoseHint")
local waterInput = gameplay:WaitForChild("WaterInput")
local interiorV2 = gameplay:WaitForChild("InteriorV2")
local fireTargets = interiorV2:WaitForChild("FireTargets")
local successBillboard = gameplay:WaitForChild("SuccessAnchor"):WaitForChild("SuccessBillboard")
local resident = interiorV2:WaitForChild("RescueResident")
local insideMarker = interiorV2:WaitForChild("ResidentInsideMarker")
local safeMarker = interiorV2:WaitForChild("ResidentSafeMarker")
local rescuePrompt = resident:WaitForChild("Torso"):WaitForChild("RescuePrompt")
local portals = interiorV2:WaitForChild("Portals")
local externalEntranceTrigger = portals:WaitForChild("ExternalEntranceTrigger")
local interiorExitTrigger = portals:WaitForChild("InteriorExitTrigger")
local interiorArrivalMarker = portals:WaitForChild("InteriorArrivalMarker")
local exteriorReturnMarker = portals:WaitForChild("ExteriorReturnMarker")
local exteriorFireGate = portals:WaitForChild("ExteriorFireGate")
local missionMessage = gameplay:WaitForChild("MissionMessage")
local resetMissionRequest = gameplay:WaitForChild("ResetMissionRequest")

local lastSpray = {}
local correctedSpawn = {}
local portalCooldown = {}
local exteriorHintCooldown = {}
local completed = false
local HOSE_STORED = "Stored"
local HOSE_EQUIPPED = "Equipped"

local function dispatchReady()
	return gate:GetAttribute("DispatchArrived") == true
end

local function hideExteriorMissionMessage(player)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild("ExteriorMissionGui")
	if gui then
		gui:Destroy()
	end
end

local function showExteriorMissionMessage(player, kind, text, duration)
	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 3)
	if not playerGui then
		return
	end
	hideExteriorMissionMessage(player)

	local gui = Instance.new("ScreenGui")
	gui.Name = "ExteriorMissionGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui

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
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label

	if typeof(duration) == "number" and duration > 0 then
		task.delay(duration, function()
			if gui.Parent then
				gui:Destroy()
			end
		end)
	end
end

local function rememberFireTargetAppearance()
	for _, target in fireTargets:GetChildren() do
		if target:IsA("Model") then
			for _, descendant in target:GetDescendants() do
				if descendant:IsA("BasePart") then
					if descendant:GetAttribute("MissionResetTransparency") == nil then
						descendant:SetAttribute("MissionResetTransparency", descendant.Transparency)
					end
					if descendant:GetAttribute("MissionResetCanQuery") == nil then
						descendant:SetAttribute("MissionResetCanQuery", descendant.CanQuery)
					end
				elseif descendant:IsA("Light") or descendant:IsA("ParticleEmitter") then
					if descendant:GetAttribute("MissionResetEnabled") == nil then
						descendant:SetAttribute("MissionResetEnabled", descendant.Enabled)
					end
				end
			end
		end
	end
end

local function setDockedNozzleVisible(visible)
	for _, descendant in dockedNozzle:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = visible and 0 or 1
		end
	end
end

local function setHoseStationState(state, ownerUserId)
	local stored = state == HOSE_STORED
	local available = dispatchReady()
	hoseStation:SetAttribute("HoseState", stored and HOSE_STORED or HOSE_EQUIPPED)
	hoseStation:SetAttribute("HoseOwnerUserId", stored and nil or ownerUserId)
	prompt.Enabled = available
	prompt.ActionText = available and (stored and "Взять шланг" or "Повесить шланг") or "Сначала прибудь к пожару"
	prompt.ObjectText = "Пожарный шланг"
	hoseHint.Enabled = stored and available
	hoseCoil.Color = stored and Color3.fromRGB(255, 194, 45) or Color3.fromRGB(125, 125, 125)
	hoseCoil.Transparency = stored and 0 or 0.35
	setDockedNozzleVisible(stored)
	if stored then
		hoseLine.Enabled = false
		hoseLine.Attachment1 = nil
	end
end

local function resetHoseStation()
	setHoseStationState(HOSE_STORED, nil)
end

local function destroyPlayerHoseTools(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	for _, container in {backpack, character} do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child.Name == "FireHoseTool" then
					child:Destroy()
				end
			end
		end
	end
end

local function applyFireNodeVisual(target, state)
	local active = state == "Active"
	for _, descendant in target:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Name == "Hitbox" then
				descendant.Transparency = 1
				descendant.CanQuery = active
			elseif descendant.Name == "WarningGlow" then
				descendant.Transparency = 1
			elseif descendant:GetAttribute("FireVisual") then
				descendant.Transparency = active and (descendant:GetAttribute("ActiveTransparency") or 0) or 1
			elseif descendant:GetAttribute("SmokeVisual") then
				descendant.Transparency = active and (descendant:GetAttribute("ActiveTransparency") or 0.45) or 1
			end
		elseif descendant:IsA("Light") then
			descendant.Enabled = active
		end
	end
end

local function resetFireTargets()
	completed = false
	gate:SetAttribute("AllFiresOut", false)
	gate:SetAttribute("ExteriorFiresOut", false)
	exteriorFireGate.CanCollide = true
	exteriorFireGate.CanTouch = true
	exteriorFireGate.CanQuery = true
	successBillboard.Enabled = false

	for _, target in fireTargets:GetChildren() do
		if target:IsA("Model") then
			local maximum = target:GetAttribute("MaxHealth") or 2.5
			local initialState = target:GetAttribute("InitialState") or "Active"
			target:SetAttribute("Health", maximum)
			target:SetAttribute("State", initialState)
			target:SetAttribute("Active", initialState == "Active")
			target:SetAttribute("Extinguished", false)
			target:SetAttribute("WarningActive", false)
			target:SetAttribute("LastWaterHit", -1000)
			applyFireNodeVisual(target, initialState)
		end
	end
end

local function resetRescueState()
	gate:SetAttribute("RescueReady", false)
	gate:SetAttribute("ResidentRescued", false)
	gate:SetAttribute("RescueFollowerActive", false)
	gate:SetAttribute("RescueFollowerPlayerUserId", nil)
	gate:SetAttribute("ResidentAtInteriorExit", false)
	gate:SetAttribute("MissionElapsedSeconds", nil)
	resident:SetAttribute("FollowerSpace", "Interior")
	resident:SetAttribute("FollowerState", "Waiting")
	rescuePrompt.Enabled = false
	resident:PivotTo(insideMarker.CFrame)
	successBillboard.Message.Text = "ЧЕЛОВЕК СПАСЁН!"
	successBillboard.Enabled = false
end

local function clearPlayerMissionState(player)
	lastSpray[player] = nil
	player:SetAttribute("HoseEquipped", false)
	player:SetAttribute("InsideInteriorV2", false)
	player:SetAttribute("MissionStartTime", nil)

	destroyPlayerHoseTools(player)
	hideExteriorMissionMessage(player)
	missionMessage:FireClient(player, "Hide")
end

local function resetMissionAfterDeath()
	resetHoseStation()
	resetFireTargets()
	resetRescueState()
	gate:SetAttribute("FrontDoorOpen", false)
	for _, player in Players:GetPlayers() do
		clearPlayerMissionState(player)
	end
	waterInput:FireAllClients("Reset")
end

local function preparePlayer(player)
	player.RespawnLocation = spawnLocation
	player:SetAttribute("HoseEquipped", false)
	player:SetAttribute("InsideInteriorV2", false)
	player:SetAttribute("MissionStartTime", nil)

	local function correctCharacterSpawn(character)
		task.defer(function()
			local root = character:WaitForChild("HumanoidRootPart", 10)
			if not root then
				return
			end

			if (root.Position - spawnLocation.Position).Magnitude > 50 and not correctedSpawn[player] then
				correctedSpawn[player] = true
				player.RespawnLocation = spawnLocation
				root.CFrame = spawnLocation.CFrame * CFrame.new(0, 3, 0)
			end
		end)
	end

	player.CharacterAdded:Connect(correctCharacterSpawn)
	if player.Character then
		correctCharacterSpawn(player.Character)
	end
end

local function makeToolPart(name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function createHoseTool(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	destroyPlayerHoseTools(player)

	local tool = Instance.new("Tool")
	tool.Name = "FireHoseTool"
	tool.ToolTip = "Пожарный шланг"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -0.25, -0.55) * CFrame.Angles(math.rad(-18), 0, 0)

	local handle = makeToolPart(
		"Handle",
		Vector3.new(0.46, 0.46, 1.5),
		CFrame.new(),
		Color3.fromRGB(90, 100, 112),
		Enum.Material.Metal
	)
	handle.Parent = tool

	local barrel = makeToolPart(
		"NozzleBarrel",
		Vector3.new(0.62, 0.62, 0.95),
		handle.CFrame * CFrame.new(0, 0, -1.05),
		Color3.fromRGB(255, 184, 40),
		Enum.Material.Metal
	)
	barrel.Parent = tool

	local mouth = makeToolPart(
		"NozzleMouth",
		Vector3.new(0.78, 0.78, 0.28),
		handle.CFrame * CFrame.new(0, 0, -1.67),
		Color3.fromRGB(220, 55, 45),
		Enum.Material.SmoothPlastic
	)
	mouth.Parent = tool

	for _, part in {barrel, mouth} do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = handle
	end

	local tip = Instance.new("Attachment")
	tip.Name = "NozzleTipAttachment"
	tip.Position = Vector3.new(0, 0, -1.82)
	tip.Parent = handle

	local connector = Instance.new("Attachment")
	connector.Name = "HoseConnectorAttachment"
	connector.Position = Vector3.new(0, 0, 0.72)
	connector.Parent = handle

	tool.Parent = player.Backpack
	humanoid:EquipTool(tool)
	return tool
end

for _, player in Players:GetPlayers() do
	preparePlayer(player)
end
Players.PlayerAdded:Connect(preparePlayer)
Players.PlayerRemoving:Connect(function(player)
	lastSpray[player] = nil
	correctedSpawn[player] = nil
	portalCooldown[player] = nil
	exteriorHintCooldown[player] = nil
	if hoseStation:GetAttribute("HoseState") == HOSE_EQUIPPED
		and hoseStation:GetAttribute("HoseOwnerUserId") == player.UserId then
		setHoseStationState(HOSE_STORED, nil)
	end
	if gate:GetAttribute("RescueFollowerActive") == true
		and gate:GetAttribute("RescueFollowerPlayerUserId") == player.UserId
		and gate:GetAttribute("ResidentRescued") ~= true then
		local upperHall = fireTargets:FindFirstChild("InteriorFire_UpperHall")
		local rescueRoom = fireTargets:FindFirstChild("InteriorFire_RescueRoom")
		local rescueReady = activeMission.Value == "Resident"
			and upperHall ~= nil
			and rescueRoom ~= nil
			and upperHall:GetAttribute("Extinguished") == true
			and rescueRoom:GetAttribute("Extinguished") == true
		gate:SetAttribute("RescueFollowerPlayerUserId", nil)
		gate:SetAttribute("RescueFollowerActive", false)
		gate:SetAttribute("RescueReady", rescueReady)
		rescuePrompt.Enabled = rescueReady
	end
end)

resetMissionRequest.Event:Connect(resetMissionAfterDeath)

local function getPlayerFromTouch(hit)
	local character = hit and hit:FindFirstAncestorOfClass("Model")
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function updateHoseLineForInterior(player, isInside)
	if isInside then
		hoseLine.Enabled = false
		return
	end
	if hoseStation:GetAttribute("HoseState") ~= HOSE_EQUIPPED
		or hoseStation:GetAttribute("HoseOwnerUserId") ~= player.UserId
		or player:GetAttribute("HoseEquipped") ~= true then
		hoseLine.Enabled = false
		hoseLine.Attachment1 = nil
		return
	end
	local character = player.Character
	local tool = character and character:FindFirstChild("FireHoseTool")
	local handle = tool and tool:FindFirstChild("Handle")
	local connector = handle and handle:FindFirstChild("HoseConnectorAttachment")
	if connector then
		hoseLine.Attachment1 = connector
		hoseLine.Enabled = true
	end
end

local function teleportThroughPortal(player, sourceCFrame, destinationCFrame, isInside)
	local now = os.clock()
	if portalCooldown[player] and now < portalCooldown[player] then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return
	end

	portalCooldown[player] = now + 1.0
	local relativeRotation = sourceCFrame.Rotation:ToObjectSpace(root.CFrame.Rotation)
	local destinationRotation = destinationCFrame.Rotation * relativeRotation
	local localVelocity = sourceCFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
	local mappedVelocity = destinationCFrame:VectorToWorldSpace(localVelocity)

	player:SetAttribute("InsideInteriorV2", isInside)
	root.CFrame = CFrame.new(destinationCFrame.Position - (isInside and destinationCFrame.LookVector * 3.0 or Vector3.zero)) * destinationRotation
	root.AssemblyLinearVelocity = Vector3.new(mappedVelocity.X, math.max(0, mappedVelocity.Y), mappedVelocity.Z)
	root.AssemblyAngularVelocity = Vector3.zero
	updateHoseLineForInterior(player, isInside)
end

exteriorFireGate.Touched:Connect(function(hit)
	local player = getPlayerFromTouch(hit)
	if not player or gate:GetAttribute("ExteriorFiresOut") == true then
		return
	end
	local now = os.clock()
	if exteriorHintCooldown[player] and now < exteriorHintCooldown[player] then
		return
	end
	exteriorHintCooldown[player] = now + 1.5
	missionMessage:FireClient(player, "Blocked", "Сначала потуши огонь снаружи", 2.4)
end)

externalEntranceTrigger.Touched:Connect(function(hit)
	local player = getPlayerFromTouch(hit)
	if not player or player:GetAttribute("InsideInteriorV2") == true then
		return
	end
	if gate:GetAttribute("ExteriorFiresOut") ~= true then
		missionMessage:FireClient(player, "Blocked", "Сначала потуши огонь снаружи", 2.4)
		return
	end
	if gate:GetAttribute("FrontDoorOpen") ~= true then
		return
	end
	hideExteriorMissionMessage(player)
	teleportThroughPortal(player, externalEntranceTrigger.CFrame, interiorArrivalMarker.CFrame, true)
end)

interiorExitTrigger.Touched:Connect(function(hit)
	local player = getPlayerFromTouch(hit)
	if player
		and player:GetAttribute("InsideInteriorV2") == true
		and gate:GetAttribute("FrontDoorOpen") == true then
		teleportThroughPortal(player, interiorExitTrigger.CFrame, exteriorReturnMarker.CFrame, false)
	end
end)

local function equipHoseForPlayer(player)
	if not dispatchReady() then
		return false
	end
	if hoseStation:GetAttribute("HoseState") ~= HOSE_STORED then
		return false
	end
	local tool = createHoseTool(player)
	local handle = tool and tool:FindFirstChild("Handle")
	local connector = handle and handle:FindFirstChild("HoseConnectorAttachment")
	if not tool or not connector then
		destroyPlayerHoseTools(player)
		return false
	end

	setHoseStationState(HOSE_EQUIPPED, player.UserId)
	player:SetAttribute("HoseEquipped", true)
	if player:GetAttribute("MissionStartTime") == nil then
		player:SetAttribute("MissionStartTime", workspace:GetServerTimeNow())
	end
	hoseLine.Attachment1 = connector
	hoseLine.Enabled = player:GetAttribute("InsideInteriorV2") ~= true
	return true
end

local function storeHoseFromPlayer(player)
	if hoseStation:GetAttribute("HoseState") ~= HOSE_EQUIPPED
		or hoseStation:GetAttribute("HoseOwnerUserId") ~= player.UserId then
		return false
	end
	lastSpray[player] = nil
	waterInput:FireClient(player, "HoseStored")
	destroyPlayerHoseTools(player)
	player:SetAttribute("HoseEquipped", false)
	setHoseStationState(HOSE_STORED, nil)
	return true
end

prompt.Triggered:Connect(function(player)
	if not dispatchReady() then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - hoseStation.Position).Magnitude > prompt.MaxActivationDistance + 3 then
		return
	end

	if hoseStation:GetAttribute("HoseState") == HOSE_STORED then
		equipHoseForPlayer(player)
	elseif hoseStation:GetAttribute("HoseState") == HOSE_EQUIPPED then
		storeHoseFromPlayer(player)
	end
end)

local function getTargetFromHit(instance)
	local current = instance
	while current and current.Parent ~= fireTargets do
		current = current.Parent
	end
	if current and current:IsA("Model") and current.Parent == fireTargets then
		return current
	end
	return nil
end

local function extinguish(target)
	if target:GetAttribute("Extinguished") then
		return
	end

	target:SetAttribute("Health", 0)
	target:SetAttribute("State", "Extinguished")
	target:SetAttribute("Active", false)
	target:SetAttribute("Extinguished", true)
	target:SetAttribute("WarningActive", false)
	applyFireNodeVisual(target, "Extinguished")
end

local function checkExteriorCompletion()
	if gate:GetAttribute("ExteriorFiresOut") == true then
		return true
	end

	for _, target in fireTargets:GetChildren() do
		if target:IsA("Model")
			and target:GetAttribute("MissionStage") == "Exterior"
			and not target:GetAttribute("Extinguished") then
			return false
		end
	end

	gate:SetAttribute("ExteriorFiresOut", true)
	exteriorFireGate.CanCollide = false
	exteriorFireGate.CanTouch = false
	exteriorFireGate.CanQuery = false
	for _, player in Players:GetPlayers() do
		local text = activeMission.Value == "Pet"
			and "ПУТЬ К КОТЁНКУ БЕЗОПАСЕН — РАЗВЕРНИ ЛЕСТНИЦУ"
			or "ВХОД БЕЗОПАСЕН — ЗАЙДИ В ДОМ"
		showExteriorMissionMessage(player, "Ready", text, 6)
	end
	return true
end

local function checkCompletion()
	local activeCount = 0
	for _, target in fireTargets:GetChildren() do
		if target:IsA("Model") and target:GetAttribute("State") == "Active" then
			activeCount += 1
		end
	end
	gate:SetAttribute("AllFiresOut", activeCount == 0)

	local upperHall = fireTargets:FindFirstChild("InteriorFire_UpperHall")
	local rescueRoom = fireTargets:FindFirstChild("InteriorFire_RescueRoom")
	local rescueReady = upperHall ~= nil
		and rescueRoom ~= nil
		and upperHall:GetAttribute("Extinguished") == true
		and rescueRoom:GetAttribute("Extinguished") == true
	gate:SetAttribute("RescueReady", rescueReady)
	rescuePrompt.Enabled = rescueReady
		and activeMission.Value == "Resident"
		and gate:GetAttribute("ResidentRescued") ~= true
		and gate:GetAttribute("RescueFollowerActive") ~= true
	successBillboard.Enabled = false
	if activeCount == 0 then
		waterInput:FireAllClients("Complete")
	end
end

rescuePrompt.Triggered:Connect(function(player)
	if activeMission.Value ~= "Resident"
		or gate:GetAttribute("RescueReady") ~= true
		or gate:GetAttribute("ResidentRescued") == true
		or gate:GetAttribute("RescueFollowerActive") == true then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - resident:GetPivot().Position).Magnitude > rescuePrompt.MaxActivationDistance + 3 then
		return
	end

	gate:SetAttribute("RescueReady", false)
	gate:SetAttribute("RescueFollowerPlayerUserId", player.UserId)
	gate:SetAttribute("RescueFollowerActive", true)
	rescuePrompt.Enabled = false
end)

waterInput.OnServerEvent:Connect(function(player, active, targetPosition)
	if not dispatchReady() then
		lastSpray[player] = nil
		return
	end
	if active ~= true then
		lastSpray[player] = nil
		return
	end
	if hoseStation:GetAttribute("HoseState") ~= HOSE_EQUIPPED
		or hoseStation:GetAttribute("HoseOwnerUserId") ~= player.UserId
		or player:GetAttribute("HoseEquipped") ~= true
		or typeof(targetPosition) ~= "Vector3" then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local tool = character and character:FindFirstChild("FireHoseTool")
	local handle = tool and tool:FindFirstChild("Handle")
	local nozzleTip = handle and handle:FindFirstChild("NozzleTipAttachment")
	if not root or not nozzleTip then
		return
	end

	local originPosition = nozzleTip.WorldPosition
	local direction = targetPosition - originPosition
	if direction.Magnitude < 0.1 then
		return
	end
	direction = direction.Unit * math.min(direction.Magnitude + 2, 80)

	local now = workspace:GetServerTimeNow()
	local previous = lastSpray[player]
	lastSpray[player] = now
	if not previous or now - previous > 0.35 then
		return
	end
	local amount = math.clamp(now - previous, 0, 0.15)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {fireTargets}
	params.IgnoreWater = true
	local result = workspace:Raycast(originPosition, direction, params)
	if not result then
		return
	end

	local target = getTargetFromHit(result.Instance)
	if not target
		or target:GetAttribute("State") ~= "Active"
		or target:GetAttribute("Extinguished") then
		return
	end

	waterInput:FireClient(player, "Spray", originPosition, result.Position)

	local health = math.max(0, (target:GetAttribute("Health") or target:GetAttribute("MaxHealth") or 2.5) - amount)
	target:SetAttribute("LastWaterHit", now)
	target:SetAttribute("Health", health)
	if health <= 0 then
		extinguish(target)
		checkExteriorCompletion()
		checkCompletion()
	end
end)

rememberFireTargetAppearance()
resetHoseStation()
resetFireTargets()
resetRescueState()
