local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local gate = script:FindFirstAncestor("PlayableGateV1")
local gameplay = gate:WaitForChild("Gameplay")
local activeMission = gameplay:WaitForChild("ActiveMission")
local interior = gameplay:WaitForChild("InteriorV2")
local fireTargets = interior:WaitForChild("FireTargets")
local challenge = gameplay:WaitForChild("FireChallengeV1")
local feedback = challenge:WaitForChild("ChallengeFeedback")
local discoveryZone = challenge:WaitForChild("PersonDiscoveryZone")
local resetRequest = gameplay:WaitForChild("ResetMissionRequest")
local rescueResident = interior:WaitForChild("RescueResident")
local rescuePrompt = rescueResident:FindFirstChild("RescuePrompt", true)

local recoveryAccumulator = 0
local publishedActiveCount = -1
local spreadGeneration = 0
local discoveryDebounce = {}

local function dispatchReady()
	return gate:GetAttribute("DispatchArrived") == true
end

local function orderedNodes(stage)
	local result = {}
	for _, node in ipairs(fireTargets:GetChildren()) do
		if node:IsA("Model") and (not stage or node:GetAttribute("MissionStage") == stage) then
			table.insert(result, node)
		end
	end
	table.sort(result, function(a, b)
		return (a:GetAttribute("DeterministicOrder") or 999) < (b:GetAttribute("DeterministicOrder") or 999)
	end)
	return result
end

local function setVisual(node, state, warning)
	local active = state == "Active"
	for _, descendant in ipairs(node:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant.Name == "Hitbox" then
				descendant.Transparency = 1
				descendant.CanQuery = active
			elseif descendant.Name == "WarningGlow" then
				descendant.Transparency = warning and 0.28 or 1
			elseif descendant:GetAttribute("FireVisual") then
				descendant.Transparency = active and (descendant:GetAttribute("ActiveTransparency") or 0) or 1
			elseif descendant:GetAttribute("SmokeVisual") then
				if active then
					descendant.Transparency = descendant:GetAttribute("ActiveTransparency") or 0.45
				elseif warning then
					descendant.Transparency = 0.78
				else
					descendant.Transparency = 1
				end
			end
		elseif descendant:IsA("Light") then
			descendant.Enabled = active or warning
			if warning then
				descendant.Brightness = 0.65
			else
				descendant.Brightness = 1.8
			end
		end
	end
end

local function countActive(stage)
	local count = 0
	for _, node in ipairs(fireTargets:GetChildren()) do
		if node:IsA("Model")
			and node:GetAttribute("State") == "Active"
			and (not stage or node:GetAttribute("MissionStage") == stage) then
			count += 1
		end
	end
	return count
end

local function updateRescueGate()
	if activeMission.Value == "Pet" then
		gate:SetAttribute("RescueReady", false)
		if rescuePrompt then rescuePrompt.Enabled = false end
		return
	end
	local upper = fireTargets:FindFirstChild("InteriorFire_UpperHall")
	local room = fireTargets:FindFirstChild("InteriorFire_RescueRoom")
	local ready = upper ~= nil and room ~= nil
		and upper:GetAttribute("State") == "Extinguished"
		and room:GetAttribute("State") == "Extinguished"
	gate:SetAttribute("RescueReady", ready)
	if rescuePrompt then
		rescuePrompt.Enabled = ready
			and activeMission.Value == "Resident"
			and gate:GetAttribute("RescueFollowerActive") ~= true
			and gate:GetAttribute("ResidentRescued") ~= true
	end
end

local function currentObjective(player)
	if gate:GetAttribute("MissionCompleted") == true then
		return ""
	end
	if activeMission.Value == "Pet" then
		if player:GetAttribute("CarryingPet") == true then
			return "ОТНЕСИ КОТЁНКА В БЕЗОПАСНУЮ ЗОНУ"
		elseif gate:GetAttribute("LadderState") == "Deployed" then
			return "ПОДНИМИСЬ ПО ЛЕСТНИЦЕ К КОТЁНКУ"
		elseif gate:GetAttribute("ExteriorFiresOut") == true then
			return "РАЗВЕРНИ АВТОЛЕСТНИЦУ"
		end
		return ""
	end
	if gate:GetAttribute("RescueFollowerActive") == true then
		if rescueResident:GetAttribute("FollowerSpace") == "Exterior" then
			return "ДОВЕДИ ЧЕЛОВЕКА ДО БЕЗОПАСНОЙ ЗОНЫ"
		end
		return "ВЕДИ ЧЕЛОВЕКА К ВЫХОДУ"
	elseif player:GetAttribute("RescuePersonFound") == true then
		return "РАСЧИСТИ ПУТЬ И ВЫВЕДИ ЧЕЛОВЕКА"
	elseif gate:GetAttribute("ExteriorFiresOut") == true then
		return "ОТКРОЙ ДВЕРЬ И НАЙДИ ЧЕЛОВЕКА"
	end
	return ""
end

local function publish(player)
	local active = countActive()
	challenge:SetAttribute("ActiveFireCount", active)
	if active ~= publishedActiveCount then
		publishedActiveCount = active
		feedback:FireAllClients("FireCount", active)
	end
	if player then
		feedback:FireClient(player, "Objective", currentObjective(player))
	else
		for _, current in ipairs(Players:GetPlayers()) do
			feedback:FireClient(current, "Objective", currentObjective(current))
		end
	end
	updateRescueGate()
end

local function activateNode(node, wasSpread)
	if not node or node:GetAttribute("State") ~= "Dormant" then
		return false
	end
	node:SetAttribute("WarningActive", false)
	node:SetAttribute("State", "Active")
	node:SetAttribute("Active", true)
	node:SetAttribute("Extinguished", false)
	node:SetAttribute("Health", node:GetAttribute("MaxHealth") or challenge:GetAttribute("ExtinguishDuration") or 2.5)
	node:SetAttribute("LastWaterHit", -1000)
	setVisual(node, "Active", false)
	if wasSpread then
		challenge:SetAttribute("SpreadCount", (challenge:GetAttribute("SpreadCount") or 0) + 1)
	end
	publish()
	return true
end

local function cancelWarning(node)
	if not node then return end
	node:SetAttribute("WarningActive", false)
	if node:GetAttribute("State") == "Dormant" then
		setVisual(node, "Dormant", false)
	end
end

local function firstDormantNeighbor()
	if countActive("Interior") >= (challenge:GetAttribute("MaxInternalActive") or 6) then
		return nil, nil
	end
	for _, source in ipairs(orderedNodes("Interior")) do
		if source:GetAttribute("State") == "Active" then
			local neighbors = string.split(source:GetAttribute("Neighbors") or "", ",")
			for _, neighborName in ipairs(neighbors) do
				neighborName = string.gsub(neighborName, "^%s*(.-)%s*$", "%1")
				local neighbor = fireTargets:FindFirstChild(neighborName)
				if neighbor
					and neighbor:GetAttribute("MissionStage") == "Interior"
					and neighbor:GetAttribute("State") == "Dormant"
					and neighbor:GetAttribute("WarningActive") ~= true then
					return source, neighbor
				end
			end
		end
	end
	return nil, nil
end

local function warnAndSpread(source, target, generation)
	if not target or target:GetAttribute("State") ~= "Dormant" then return end
	target:SetAttribute("WarningActive", true)
	setVisual(target, "Dormant", true)
	feedback:FireAllClients("SpreadWarning", target.Name)
	local warningDuration = challenge:GetAttribute("WarningDuration") or 2
	task.wait(warningDuration)
	if generation ~= spreadGeneration then
		cancelWarning(target)
		return
	end
	if source:GetAttribute("State") == "Active"
		and target:GetAttribute("State") == "Dormant"
		and countActive("Interior") < (challenge:GetAttribute("MaxInternalActive") or 6) then
		activateNode(target, true)
	else
		cancelWarning(target)
		publish()
	end
end

local function startSpreadLoop()
	if activeMission.Value ~= "Resident" then
		spreadGeneration += 1
		return
	end
	spreadGeneration += 1
	local generation = spreadGeneration
	task.spawn(function()
		local interval = challenge:GetAttribute("SpreadInterval") or 8
		local warning = challenge:GetAttribute("WarningDuration") or 2
		while generation == spreadGeneration do
			if activeMission.Value ~= "Resident" then break end
			if not dispatchReady() then
				task.wait(0.25)
				continue
			end
			task.wait(math.max(0.1, interval - warning))
			if generation ~= spreadGeneration then break end
			if not dispatchReady() then continue end
			local source, target = firstDormantNeighbor()
			if source and target then
				warnAndSpread(source, target, generation)
			else
				task.wait(warning)
			end
		end
	end)
end

local function resetChallenge()
	spreadGeneration += 1
	challenge:SetAttribute("AttemptId", (challenge:GetAttribute("AttemptId") or 0) + 1)
	challenge:SetAttribute("AttemptStartTime", workspace:GetServerTimeNow())
	challenge:SetAttribute("ExtinguishedCount", 0)
	challenge:SetAttribute("SpreadCount", 0)
	publishedActiveCount = -1
	for _, node in ipairs(orderedNodes()) do
		local state = node:GetAttribute("InitialState") or "Active"
		if activeMission.Value == "Pet" and node:GetAttribute("MissionStage") == "Interior" then
			state = "Dormant"
		end
		node:SetAttribute("State", state)
		node:SetAttribute("Active", state == "Active")
		node:SetAttribute("Extinguished", false)
		node:SetAttribute("WarningActive", false)
		node:SetAttribute("Health", node:GetAttribute("MaxHealth") or 2.5)
		node:SetAttribute("LastWaterHit", -1000)
		node:SetAttribute("CountedAttemptId", nil)
		setVisual(node, state, false)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("RescuePersonFound", false)
	end
	feedback:FireAllClients("Reset")
	publish()
	if dispatchReady() then
		startSpreadLoop()
	end
end

local function onNodeStateChanged(node)
	local state = node:GetAttribute("State")
	if state == "Extinguished" then
		local attempt = challenge:GetAttribute("AttemptId")
		if node:GetAttribute("CountedAttemptId") ~= attempt then
			node:SetAttribute("CountedAttemptId", attempt)
			challenge:SetAttribute("ExtinguishedCount", (challenge:GetAttribute("ExtinguishedCount") or 0) + 1)
		end
	elseif state ~= "Active" then
		cancelWarning(node)
	end
	publish()
end

for _, node in ipairs(orderedNodes()) do
	node:GetAttributeChangedSignal("State"):Connect(function()
		onNodeStateChanged(node)
	end)
end

gate:GetAttributeChangedSignal("ExteriorFiresOut"):Connect(function()
	publish()
end)

gate:GetAttributeChangedSignal("LadderState"):Connect(function()
	publish()
end)

gate:GetAttributeChangedSignal("PetCarried"):Connect(function()
	publish()
end)

gate:GetAttributeChangedSignal("RescueFollowerActive"):Connect(function()
	publish()
end)

rescueResident:GetAttributeChangedSignal("FollowerSpace"):Connect(function()
	publish()
end)

gate:GetAttributeChangedSignal("MissionCompleted"):Connect(function()
	publish()
end)

local function discoverPlayer(player)
	if activeMission.Value ~= "Resident" then return end
	if not player or discoveryDebounce[player] then return end
	discoveryDebounce[player] = true
	player:SetAttribute("RescuePersonFound", true)
	feedback:FireClient(player, "Objective", currentObjective(player))
	local room = fireTargets:FindFirstChild("InteriorFire_RescueRoom")
	if room and room:GetAttribute("State") == "Dormant" and room:GetAttribute("WarningActive") ~= true then
		local generation = spreadGeneration
		room:SetAttribute("WarningActive", true)
		setVisual(room, "Dormant", true)
		feedback:FireAllClients("SpreadWarning", room.Name)
		task.delay(challenge:GetAttribute("WarningDuration") or 2, function()
			if generation == spreadGeneration and room:GetAttribute("State") == "Dormant" then
				activateNode(room, true)
			else
				cancelWarning(room)
			end
		end)
	end
	task.delay(1, function() discoveryDebounce[player] = nil end)
end

discoveryZone.Touched:Connect(function(hit)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if player then discoverPlayer(player) end
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("RescuePersonFound", false)
	task.defer(function() publish(player) end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	player:SetAttribute("RescuePersonFound", false)
end

resetRequest.Event:Connect(function(reasonOrPlayer)
	if typeof(reasonOrPlayer) == "Instance"
		and reasonOrPlayer:IsA("Player")
		and #Players:GetPlayers() > 1 then
		return
	end
	task.defer(resetChallenge)
end)

activeMission.Changed:Connect(function()
	task.defer(resetChallenge)
end)

gate:GetAttributeChangedSignal("DispatchArrived"):Connect(function()
	if dispatchReady() then
		task.defer(resetChallenge)
	else
		spreadGeneration += 1
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if not dispatchReady() then
		recoveryAccumulator = 0
		return
	end
	recoveryAccumulator += dt
	if recoveryAccumulator < 0.1 then return end
	local step = recoveryAccumulator
	recoveryAccumulator = 0
	local now = workspace:GetServerTimeNow()
	local changed = false
	for _, node in ipairs(orderedNodes()) do
		if node:GetAttribute("State") == "Active" then
			local maximum = node:GetAttribute("MaxHealth") or 2.5
			local health = node:GetAttribute("Health") or maximum
			local delaySeconds = node:GetAttribute("RecoveryDelay") or challenge:GetAttribute("RecoveryDelay") or 1
			if health < maximum and now - (node:GetAttribute("LastWaterHit") or -1000) >= delaySeconds then
				local rate = node:GetAttribute("RecoveryRate") or challenge:GetAttribute("RecoveryRate") or 0.14
				node:SetAttribute("Health", math.min(maximum, health + maximum * rate * step))
				changed = true
			end
		end
	end
	if changed then publish() end
end)

resetChallenge()
print("Fire Challenge V1 server ready: 9 nodes, deterministic spread, recovery enabled")
