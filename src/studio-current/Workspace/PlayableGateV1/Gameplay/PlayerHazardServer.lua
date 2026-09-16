local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local gameplay = script.Parent
local gate = gameplay.Parent
local hazards = gameplay:WaitForChild("PlayerHazards")
local fireZones = hazards:WaitForChild("FireZones")
local smokeZones = hazards:WaitForChild("SmokeZones")
local fireTargets = gameplay:WaitForChild("InteriorV2"):WaitForChild("FireTargets")
local feedback = gameplay:WaitForChild("HazardFeedback")
local resetMissionRequest = gameplay:WaitForChild("ResetMissionRequest")

local PLAYER_MAX_HEALTH = hazards:GetAttribute("PlayerMaxHealth") or 100
local FIRE_DAMAGE_PER_SECOND = hazards:GetAttribute("FireDamagePerSecond") or 25
local SMOKE_DAMAGE_PER_SECOND = hazards:GetAttribute("SmokeDamagePerSecond") or 7
local SMOKE_GRACE_SECONDS = hazards:GetAttribute("SmokeGraceSeconds") or 1.5
local SMOKE_RECOVERY_PER_SECOND = hazards:GetAttribute("SmokeRecoveryPerSecond") or 3
local FIRE_FLASH_INTERVAL = 0.28
local SMOKE_FEEDBACK_INTERVAL = 0.12

local playerStates = {}

local function pointInsideZone(point, zone)
	local localPoint = zone.CFrame:PointToObjectSpace(point)
	local half = zone.Size * 0.5
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function linkedFireIsActive(zone)
	local targetName = zone:GetAttribute("TargetName")
	if typeof(targetName) ~= "string" then
		return false
	end
	local target = fireTargets:FindFirstChild(targetName)
	return target ~= nil and target:GetAttribute("Extinguished") ~= true
end

local function getLivingCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function resetPlayerHazardState(player)
	local state = playerStates[player] or {}
	state.smokeExposure = 0
	state.lastSmokeSend = 0
	state.lastSmokeInside = false
	state.lastSmokeDanger = false
	state.lastFirePulse = 0
	state.deathHandled = false
	playerStates[player] = state
	player:SetAttribute("SmokeExposureSeconds", 0)
	player:SetAttribute("InsideSmokeZone", false)
	player:SetAttribute("NearActiveFire", false)
	feedback:FireClient(player, "SmokeState", false, false, 0)
	return state
end

local function prepareCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	humanoid.MaxHealth = PLAYER_MAX_HEALTH
	humanoid.Health = PLAYER_MAX_HEALTH
	local state = resetPlayerHazardState(player)
	feedback:FireClient(player, "Spawn", PLAYER_MAX_HEALTH)

	humanoid.Died:Connect(function()
		if state.deathHandled then
			return
		end
		state.deathHandled = true
		player:SetAttribute("InsideSmokeZone", false)
		player:SetAttribute("NearActiveFire", false)
		feedback:FireClient(player, "Death", "ПОЖАРНЫЙ ПОСТРАДАЛ — ПОПРОБУЙ ЕЩЁ РАЗ")
		resetMissionRequest:Fire(player)
	end)
end

local function preparePlayer(player)
	player:SetAttribute("HazardFireDamagePerSecond", FIRE_DAMAGE_PER_SECOND)
	player:SetAttribute("HazardSmokeDamagePerSecond", SMOKE_DAMAGE_PER_SECOND)
	player:SetAttribute("HazardSmokeGraceSeconds", SMOKE_GRACE_SECONDS)
	player.CharacterAdded:Connect(function(character)
		prepareCharacter(player, character)
	end)
	if player.Character then
		task.spawn(prepareCharacter, player, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	preparePlayer(player)
end
Players.PlayerAdded:Connect(preparePlayer)
Players.PlayerRemoving:Connect(function(player)
	playerStates[player] = nil
end)

RunService.Heartbeat:Connect(function(deltaTime)
	local dt = math.min(deltaTime, 0.2)
	local now = os.clock()

	for _, player in Players:GetPlayers() do
		local state = playerStates[player]
		local character, humanoid, root = getLivingCharacter(player)
		if not state or not character then
			continue
		end

		local activeFireZoneCount = 0
		for _, zone in fireZones:GetChildren() do
			if zone:IsA("BasePart")
				and linkedFireIsActive(zone)
				and pointInsideZone(root.Position, zone) then
				activeFireZoneCount += 1
			end
		end

		local nearFire = activeFireZoneCount > 0
		player:SetAttribute("NearActiveFire", nearFire)
		if nearFire then
			local damage = FIRE_DAMAGE_PER_SECOND * dt * activeFireZoneCount
			humanoid:TakeDamage(damage)
			if now - state.lastFirePulse >= FIRE_FLASH_INTERVAL then
				state.lastFirePulse = now
				feedback:FireClient(player, "FireDamage")
			end
		end

		if humanoid.Health <= 0 then
			continue
		end

		local insideSmoke = false
		for _, zone in smokeZones:GetChildren() do
			if zone:IsA("BasePart")
				and linkedFireIsActive(zone)
				and pointInsideZone(root.Position, zone) then
				insideSmoke = true
				break
			end
		end

		if insideSmoke then
			state.smokeExposure += dt
		else
			state.smokeExposure = math.max(0, state.smokeExposure - SMOKE_RECOVERY_PER_SECOND * dt)
		end

		local smokeDanger = insideSmoke and state.smokeExposure >= SMOKE_GRACE_SECONDS
		if smokeDanger then
			humanoid:TakeDamage(SMOKE_DAMAGE_PER_SECOND * dt)
		end

		player:SetAttribute("SmokeExposureSeconds", state.smokeExposure)
		player:SetAttribute("InsideSmokeZone", insideSmoke)

		if insideSmoke ~= state.lastSmokeInside
			or smokeDanger ~= state.lastSmokeDanger
			or now - state.lastSmokeSend >= SMOKE_FEEDBACK_INTERVAL then
			state.lastSmokeInside = insideSmoke
			state.lastSmokeDanger = smokeDanger
			state.lastSmokeSend = now
			local intensity = math.clamp(state.smokeExposure / SMOKE_GRACE_SECONDS, 0, 1)
			feedback:FireClient(player, "SmokeState", insideSmoke, smokeDanger, intensity)
		end
	end
end)
