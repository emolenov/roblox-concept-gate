-- Dispatch Loop V1: stable server-authoritative arcade vehicle and arrival gate.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

-- Archived Rescue/PlayableGate copies use server RunContext, so isolate their
-- executable logic for this Play session without changing the saved backups.
local isolatedArchiveScripts = 0
for _, archive in ipairs(ServerStorage:GetChildren()) do
	local archiveName = archive.Name
	if string.sub(archiveName, 1, 15) == "PlayableGateV1_"
		or string.sub(archiveName, 1, 6) == "Rescue" then
		for _, descendant in ipairs(archive:GetDescendants()) do
			if descendant:IsA("BaseScript") and not descendant.Disabled then
				descendant.Disabled = true
				isolatedArchiveScripts += 1
			end
		end
	end
end
for _, scene in ipairs(workspace:GetChildren()) do
	if scene.Name ~= "PlayableGateV1" and string.sub(scene.Name, 1, 6) == "Rescue" then
		for _, descendant in ipairs(scene:GetDescendants()) do
			if descendant:IsA("BaseScript") and not descendant.Disabled then
				descendant.Disabled = true
				isolatedArchiveScripts += 1
			end
		end
	end
end

local gameplay = script.Parent
local gate = gameplay.Parent
local dispatch = gate:WaitForChild("Dispatch")
local station = dispatch:WaitForChild("FireStation")
local route = dispatch:WaitForChild("StationRoute")
local truck = gate:WaitForChild("FiretruckPreview")
local vehicleRoot = truck:WaitForChild("DispatchVehicleRoot")
local drivePrompt = vehicleRoot:WaitForChild("DrivePrompt")
local hoseStation = gameplay:WaitForChild("HoseStation")
local hosePrompt = hoseStation:FindFirstChild("TakeHosePrompt", true)
local arrivalZone = gameplay:WaitForChild("FireTruckArrivalZone")
local arrivedRespawnMarker = gameplay:WaitForChild("ArrivedRespawnMarker")
local spawnLocation = gate:WaitForChild("FirefighterSpawn")
local remotes = gameplay:WaitForChild("DispatchRemotes")
local vehicleInput = remotes:WaitForChild("VehicleInput")
local vehicleExit = remotes:WaitForChild("VehicleExit")
local dispatchMessage = remotes:WaitForChild("DispatchMessage")
local vehicleEnter = remotes:FindFirstChild("VehicleEnter")
if not vehicleEnter then
	vehicleEnter = Instance.new("RemoteEvent")
	vehicleEnter.Name = "VehicleEnter"
	vehicleEnter.Parent = remotes
end
local resetMissionRequest = gameplay:WaitForChild("ResetMissionRequest")
local activeMission = gameplay:WaitForChild("ActiveMission")
local residentialStreet = gate:WaitForChild("ResidentialStreet")

local briefingRandom = Random.new()
local briefingVariants = {
	Pet = {
		"КОТЁНОК НА КРЫШЕ — СРОЧНО К ДОМУ",
		"КОТЁНОК ОТРЕЗАН ОГНЁМ НА КРЫШЕ",
		"НА КРЫШЕ КОТЁНОК — НУЖНА ПОЖАРНАЯ ПОМОЩЬ",
	},
	Resident = {
		"В ГОРЯЩЕМ ДОМЕ ОСТАЛСЯ ЧЕЛОВЕК",
		"ЧЕЛОВЕК ЗАБЛОКИРОВАН В ДОМЕ — НУЖНА ЭВАКУАЦИЯ",
		"ЖИТЕЛЬ ВНУТРИ ГОРЯЩЕГО ДОМА — СРОЧНЫЙ ВЫЗОВ",
	},
}
local lastBriefingIndex = {}
local currentBriefingMission = nil
local currentBriefingText = nil
local function buildIncidentBriefing(isNewCall)
	local mission = activeMission.Value
	local variants = briefingVariants[mission]
	if not variants then
		currentBriefingMission = mission
		currentBriefingText = (isNewCall and "НОВЫЙ ВЫЗОВ: " or "ВЫЗОВ: ") .. "ПОЖАР — САДИСЬ В МАШИНУ"
		return currentBriefingText
	end
	local previous = lastBriefingIndex[mission]
	local index
	if #variants == 1 then
		index = 1
	elseif previous then
		local roll = briefingRandom:NextInteger(1, #variants - 1)
		index = roll >= previous and roll + 1 or roll
	else
		index = briefingRandom:NextInteger(1, #variants)
	end
	lastBriefingIndex[mission] = index
	currentBriefingMission = mission
	currentBriefingText = (isNewCall and "НОВЫЙ ВЫЗОВ: " or "ВЫЗОВ: ") .. variants[index]
	return currentBriefingText
end

local function currentIncidentBriefing(isNewCall)
	if currentBriefingText == nil or currentBriefingMission ~= activeMission.Value then
		return buildIncidentBriefing(isNewCall)
	end
	return currentBriefingText
end


local MAX_SPEED = truck:GetAttribute("MaxSpeed") or 22
local REVERSE_SPEED = 8
local ACCELERATION = 14
local BRAKING = 22
local COAST_DECELERATION = 12
local STEER_RATE = math.rad(48)
local INPUT_TIMEOUT = 0.75
local DRIVE_S_TRIP_SECONDS = 23
local DRIVE_S_MOVING_SECONDS = 22
local DRIVE_A_TRIP_SECONDS = 32
local DRIVE_A_MOVING_SECONDS = 28
local DRIVE_RATING_RANK = {B = 1, A = 2, S = 3}

local driver = nil
local throttle = 0
local steering = 0
local speed = 0
local lastInputTime = 0
local vehicleCFrame = truck:GetPivot()
local stationVehicleCFrame = vehicleCFrame
local stationSpawnCFrame = spawnLocation.CFrame
local tripStartedAt = nil
local movingTime = 0
local blockedLastFrame = false
local hoseRelative = {}
local seat = truck:FindFirstChildWhichIsA("Seat", true)

local drivableParts = {}
for _, descendant in ipairs(route:GetDescendants()) do
	if descendant:IsA("BasePart") and (string.sub(descendant.Name, 1, 5) == "Road_" or descendant.Name == "DispatchGround") then
		table.insert(drivableParts, descendant)
	end
end
local residentialGround = gate:FindFirstChild("ResidentialGround")
if residentialGround and residentialGround:IsA("BasePart") then
	table.insert(drivableParts, residentialGround)
end
for _, name in ipairs({"GarageFloor", "Driveway"}) do
	local surface = station:FindFirstChild(name)
	if surface and surface:IsA("BasePart") then table.insert(drivableParts, surface) end
end
for _, descendant in ipairs(residentialStreet:GetDescendants()) do
	if descendant:IsA("BasePart")
		and (descendant.Material == Enum.Material.Asphalt
			or string.find(string.lower(descendant.Name), "asphalt", 1, true)) then
		table.insert(drivableParts, descendant)
	end
end
local driveSurfaces = RaycastParams.new()
driveSurfaces.FilterType = Enum.RaycastFilterType.Include
driveSurfaces.FilterDescendantsInstances = drivableParts
driveSurfaces.IgnoreWater = true

local function collectMountedHose()
	table.clear(hoseRelative)
	local pivot = truck:GetPivot()
	hoseRelative[hoseStation] = pivot:ToObjectSpace(hoseStation.CFrame)
	for _, descendant in ipairs(hoseStation:GetDescendants()) do
		if descendant:IsA("BasePart") then
			hoseRelative[descendant] = pivot:ToObjectSpace(descendant.CFrame)
		end
	end
end

local function updateMountedHose()
	for part, relative in pairs(hoseRelative) do
		if part.Parent then
			part.CFrame = vehicleCFrame * relative
		end
	end
end

local function pointInside(part, point)
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function isDriveSurface(position)
	local result = workspace:Raycast(position + Vector3.new(0, 12, 0), Vector3.new(0, -30, 0), driveSurfaces)
	return result ~= nil
end

local function setHoseAvailability(available)
	if not hosePrompt then return end
	available = available and driver == nil
	if available then
		hosePrompt.Enabled = true
		hosePrompt.ActionText = hoseStation:GetAttribute("HoseState") == "Equipped"
			and "Повесить шланг" or "Взять шланг"
	else
		hosePrompt.Enabled = false
		hosePrompt.ActionText = "Сначала прибудь к пожару"
	end
	hosePrompt.ObjectText = "Пожарный шланг"
end

local function updateSessionDriveBest(player, driveRating, tripElapsed)
	if not player then return false end
	local bestRating = player:GetAttribute("SessionBestDriveRating")
	local bestTime = player:GetAttribute("SessionBestDriveTime")
	local ratingRank = DRIVE_RATING_RANK[driveRating] or 0
	local bestRank = DRIVE_RATING_RANK[bestRating] or 0
	local isBetter = bestRating == nil
		or ratingRank > bestRank
		or (ratingRank == bestRank and (bestTime == nil or tripElapsed < bestTime))
	if isBetter then
		player:SetAttribute("SessionBestDriveRating", driveRating)
		player:SetAttribute("SessionBestDriveTime", tripElapsed)
	end
	return isBetter
end

local function drivingBriefingFor(player)
	local bestRating = player and player:GetAttribute("SessionBestDriveRating")
	local bestTime = player and player:GetAttribute("SessionBestDriveTime")
	if DRIVE_RATING_RANK[bestRating] and typeof(bestTime) == "number" then
		return string.format("ЕДЬ К ВЫЗОВУ • ПОБЕЙ РЕКОРД %s %.1f С", bestRating, bestTime)
	end
	return "ЕДЬ ПО ДОРОГЕ К ГОРЯЩЕМУ ДОМУ"
end

local function setArrived()
	if gate:GetAttribute("DispatchArrived") == true then return end
	local tripElapsed = tripStartedAt and (os.clock() - tripStartedAt) or movingTime
	local stuckCount = truck:GetAttribute("StuckCount") or 0
	local driveRating = "B"
	if tripElapsed <= DRIVE_S_TRIP_SECONDS
		and movingTime <= DRIVE_S_MOVING_SECONDS
		and stuckCount == 0 then
		driveRating = "S"
	elseif tripElapsed <= DRIVE_A_TRIP_SECONDS
		and movingTime <= DRIVE_A_MOVING_SECONDS
		and stuckCount <= 1 then
		driveRating = "A"
	end
	local isSessionBest = updateSessionDriveBest(driver, driveRating, tripElapsed)
	gate:SetAttribute("DispatchArrived", true)
	gate:SetAttribute("DispatchChallengeActive", true)
	gate:SetAttribute("DispatchState", "Arrived")
	truck:SetAttribute("Arrived", true)
	truck:SetAttribute("TripElapsed", tripElapsed)
	truck:SetAttribute("MovingTime", movingTime)
	truck:SetAttribute("DriveTime", tripElapsed)
	truck:SetAttribute("DriveRating", driveRating)
	speed = 0
	throttle = 0
	steering = 0
	truck:SetAttribute("CurrentSpeed", 0)
	spawnLocation.CFrame = vehicleCFrame * CFrame.new(0, -3, -9)
	for _, player in ipairs(Players:GetPlayers()) do
		player.RespawnLocation = spawnLocation
	end
	setHoseAvailability(false)
	local genericText = string.format("НА МЕСТЕ • %.1f С • ОЦЕНКА %s — БЕРИ ШЛАНГ", tripElapsed, driveRating)
	local recordText = string.format("НА МЕСТЕ • %.1f С • ОЦЕНКА %s • РЕКОРД! — БЕРИ ШЛАНГ", tripElapsed, driveRating)
	for _, player in ipairs(Players:GetPlayers()) do
		dispatchMessage:FireClient(player, "Arrived", player == driver and isSessionBest and recordText or genericText)
	end
end

local function releaseDriver(player, placeBesideTruck)
	if driver ~= player then return end
	vehicleInput:FireClient(player, "ForceStop")
	speed = 0
	throttle = 0
	steering = 0
	truck:SetAttribute("CurrentSpeed", 0)
	truck:SetAttribute("DriverUserId", 0)
	player:SetAttribute("DrivingFireTruck", false)
	drivePrompt.Enabled = true
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid then
		humanoid.Sit = false
		humanoid.PlatformStand = false
	end
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then weld:Destroy() end
	end
	if placeBesideTruck and root then
		character:PivotTo(vehicleCFrame * CFrame.new(0, 0, -5.2))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	driver = nil
	if gate:GetAttribute("DispatchArrived") == true then
		task.delay(0.6, function()
			if driver == nil then setHoseAvailability(true) end
		end)
	end
	dispatchMessage:FireClient(player, "Exited", gate:GetAttribute("DispatchArrived") == true
		and "БЕРИ ШЛАНГ И ТУШИ ПОЖАР" or "СЯДЬ В МАШИНУ И ПРОДОЛЖАЙ МАРШРУТ")
end

local function tryStartDriving(player)
	if driver or not player.Character then return end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return end
	if (root.Position - vehicleRoot.Position).Magnitude > drivePrompt.MaxActivationDistance + 4 then return end
	if hoseStation:GetAttribute("HoseState") == "Equipped" then
		dispatchMessage:FireClient(player, "Notice", "СНАЧАЛА ПОВЕСЬ ШЛАНГ")
		return
	end
	driver = player
	throttle = 0
	steering = 0
	lastInputTime = os.clock()
	truck:SetAttribute("DriverUserId", player.UserId)
	player:SetAttribute("DrivingFireTruck", true)
	drivePrompt.Enabled = false
	if not tripStartedAt then
		tripStartedAt = os.clock()
		truck:SetAttribute("TripStartTime", workspace:GetServerTimeNow())
	end
	if seat then
		seat.Anchored = true
		seat.CanCollide = false
		seat:Sit(humanoid)
	else
		player.Character:PivotTo(vehicleCFrame * CFrame.new(1.5, 0.8, 0))
		humanoid.Sit = true
	end
	dispatchMessage:FireClient(player, "Driving", drivingBriefingFor(player))
end

drivePrompt.Triggered:Connect(tryStartDriving)
vehicleEnter.OnServerEvent:Connect(tryStartDriving)

vehicleInput.OnServerEvent:Connect(function(player, newThrottle, newSteering)
	if player ~= driver then return end
	if typeof(newThrottle) ~= "number" or typeof(newSteering) ~= "number" then return end
	throttle = math.clamp(newThrottle, -1, 1)
	steering = math.clamp(newSteering, -1, 1)
	lastInputTime = os.clock()
end)

vehicleExit.OnServerEvent:Connect(function(player)
	releaseDriver(player, true)
end)

Players.PlayerRemoving:Connect(function(player)
	if driver == player then releaseDriver(player, false) end
end)

local function resetDispatchForNewMission()
	if driver then releaseDriver(driver, false) end
	vehicleCFrame = stationVehicleCFrame
	truck:PivotTo(vehicleCFrame)
	speed = 0
	throttle = 0
	steering = 0
	lastInputTime = 0
	tripStartedAt = nil
	movingTime = 0
	blockedLastFrame = false
	gate:SetAttribute("DispatchArrived", false)
	gate:SetAttribute("DispatchChallengeActive", false)
	gate:SetAttribute("DispatchState", "AwaitingDispatch")
	truck:SetAttribute("Arrived", false)
	truck:SetAttribute("DriverUserId", 0)
	truck:SetAttribute("CurrentSpeed", 0)
	truck:SetAttribute("TripElapsed", 0)
	truck:SetAttribute("MovingTime", 0)
	truck:SetAttribute("DriveTime", nil)
	truck:SetAttribute("DriveRating", nil)
	truck:SetAttribute("MaxRecordedSpeed", 0)
	truck:SetAttribute("FlipCount", 0)
	truck:SetAttribute("StuckCount", 0)
	spawnLocation.CFrame = stationSpawnCFrame
	drivePrompt.Enabled = true
	updateMountedHose()
	setHoseAvailability(false)
	for _, player in ipairs(Players:GetPlayers()) do
		player.RespawnLocation = spawnLocation
		player:SetAttribute("DrivingFireTruck", false)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root then
			character:PivotTo(spawnLocation.CFrame * CFrame.new(0, 3, 0))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	task.delay(0.25, function()
		local text = buildIncidentBriefing(true)
		for _, player in ipairs(Players:GetPlayers()) do
			dispatchMessage:FireClient(player, "DispatchCall", text)
		end
	end)
end

resetMissionRequest.Event:Connect(function(reason)
	if reason == "NewMission" then
		task.defer(resetDispatchForNewMission)
	end
end)

local function preparePlayer(player)
	player.RespawnLocation = spawnLocation
	player:SetAttribute("DrivingFireTruck", false)

	local function enforceCurrentDispatchSpawn(character)
		for _, delaySeconds in ipairs({0.15, 0.6, 1.4}) do
			task.delay(delaySeconds, function()
				if not player.Parent or player.Character ~= character then return end
				player.RespawnLocation = spawnLocation
				local root = character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - spawnLocation.Position).Magnitude > 60 then
					character:PivotTo(spawnLocation.CFrame * CFrame.new(0, 3, 0))
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
			end)
		end
	end

	player.CharacterAdded:Connect(enforceCurrentDispatchSpawn)
	if player.Character then enforceCurrentDispatchSpawn(player.Character) end
	task.delay(1, function()
		if player.Parent and gate:GetAttribute("DispatchArrived") ~= true then
			dispatchMessage:FireClient(player, "DispatchCall", currentIncidentBriefing(false))
		end
	end)
	player.CharacterRemoving:Connect(function()
		if driver == player then releaseDriver(player, false) end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do preparePlayer(player) end
Players.PlayerAdded:Connect(preparePlayer)

gate:SetAttribute("DispatchArrived", false)
gate:SetAttribute("DispatchChallengeActive", false)
gate:SetAttribute("DispatchState", "AwaitingDispatch")
truck:SetAttribute("Arrived", false)
truck:SetAttribute("DriverUserId", 0)
truck:SetAttribute("CurrentSpeed", 0)
truck:SetAttribute("MaxRecordedSpeed", 0)
truck:SetAttribute("MovingTime", 0)
truck:SetAttribute("DriveTime", nil)
truck:SetAttribute("DriveRating", nil)
truck:SetAttribute("FlipCount", 0)
truck:SetAttribute("StuckCount", 0)
spawnLocation.CFrame = CFrame.new(9848, 0.3, -49)
setHoseAvailability(false)
collectMountedHose()
updateMountedHose()

hoseStation:GetAttributeChangedSignal("HoseState"):Connect(function()
	setHoseAvailability(gate:GetAttribute("DispatchArrived") == true)
end)

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.08)
	if gate:GetAttribute("DispatchArrived") ~= true then
		setHoseAvailability(false)
	end

	if driver and (not driver.Parent or not driver.Character) then
		releaseDriver(driver, false)
	end

	if driver and os.clock() - lastInputTime > INPUT_TIMEOUT then
		throttle = 0
		steering = 0
	end

	local targetSpeed = throttle >= 0 and throttle * MAX_SPEED or throttle * REVERSE_SPEED
	local rate
	if throttle == 0 then
		rate = COAST_DECELERATION
	elseif math.sign(targetSpeed) == math.sign(speed) then
		rate = ACCELERATION
	else
		rate = BRAKING
	end
	if speed < targetSpeed then
		speed = math.min(targetSpeed, speed + rate * dt)
	elseif speed > targetSpeed then
		speed = math.max(targetSpeed, speed - rate * dt)
	end

	if driver and math.abs(speed) > 0.15 then
		local speedRatio = math.clamp(math.abs(speed) / MAX_SPEED, 0.28, 1)
		local reverseSign = speed >= 0 and 1 or -1
		vehicleCFrame = vehicleCFrame * CFrame.Angles(0, -steering * STEER_RATE * speedRatio * reverseSign * dt, 0)
		local candidate = vehicleCFrame * CFrame.new(speed * dt, 0, 0)
		if isDriveSurface(candidate.Position) then
			vehicleCFrame = candidate
			blockedLastFrame = false
		else
			speed = 0
			if not blockedLastFrame then
				truck:SetAttribute("StuckCount", (truck:GetAttribute("StuckCount") or 0) + 1)
				blockedLastFrame = true
			end
		end
		truck:PivotTo(vehicleCFrame)
		updateMountedHose()
	end

	if driver and math.abs(speed) > 1 then
		movingTime += dt
		truck:SetAttribute("MovingTime", movingTime)
	end
	truck:SetAttribute("CurrentSpeed", math.abs(speed))
	truck:SetAttribute("MaxRecordedSpeed", math.max(truck:GetAttribute("MaxRecordedSpeed") or 0, math.abs(speed)))

	if gate:GetAttribute("DispatchArrived") ~= true and pointInside(arrivalZone, vehicleCFrame.Position) then
		setArrived()
	end
end)

print(string.format("Dispatch Loop V1 server ready: arcade truck, route gate, delayed hose; isolated archive scripts=%d", isolatedArchiveScripts))