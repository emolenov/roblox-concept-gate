local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local gameplay = script.Parent
local gate = gameplay.Parent
local hazards = gameplay:WaitForChild("PlayerHazards")
local smokeZones = hazards:WaitForChild("SmokeZones")
local fireTargets = gameplay:WaitForChild("InteriorV2"):WaitForChild("FireTargets")
local feedback = gameplay:WaitForChild("HazardFeedback")
local resetMissionRequest = gameplay:WaitForChild("ResetMissionRequest")
local challenge = gameplay:WaitForChild("FireChallengeV1")

local PLAYER_MAX_HEALTH = hazards:GetAttribute("PlayerMaxHealth") or 100
local FIRE_NEAR_DISTANCE = challenge:GetAttribute("FireNearDistance") or 2.5
local FIRE_MID_DISTANCE = challenge:GetAttribute("FireMidDistance") or 5
local FIRE_FAR_DISTANCE = challenge:GetAttribute("FireFarDistance") or 7
local FIRE_DAMAGE_NEAR = challenge:GetAttribute("FireDamageNear") or 60
local FIRE_DAMAGE_MID = challenge:GetAttribute("FireDamageMid") or 35
local FIRE_DAMAGE_FAR = challenge:GetAttribute("FireDamageFar") or 15
local MAX_FIRE_DAMAGE = challenge:GetAttribute("MaxFireDamage") or 75
local SMOKE_GRACE = challenge:GetAttribute("SmokeGrace") or 0.75
local SMOKE_RECOVERY = hazards:GetAttribute("SmokeRecoveryPerSecond") or 3
local FIRE_FLASH_INTERVAL = 0.22
local SMOKE_FEEDBACK_INTERVAL = 0.12

local playerStates = {}

local function pointInsideZone(point, zone)
	local localPoint = zone.CFrame:PointToObjectSpace(point)
	local half = zone.Size * 0.5
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function distanceToPart(point, part)
	local p = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	local dx = math.max(math.abs(p.X) - half.X, 0)
	local dy = math.max(math.abs(p.Y) - half.Y, 0)
	local dz = math.max(math.abs(p.Z) - half.Z, 0)
	return Vector3.new(dx, dy, dz).Magnitude
end

local function linkedFireIsActive(zone)
	local targetName = zone:GetAttribute("LinkedFireTarget") or zone:GetAttribute("TargetName")
	local target = typeof(targetName) == "string" and fireTargets:FindFirstChild(targetName)
	return target ~= nil and target:GetAttribute("State") == "Active"
end

local function resetPlayerHazardState(player)
	local state = playerStates[player] or {}
	state.smokeExposure = 0
	state.lastSmokeSend = 0
	state.lastSmokeInside = false
	state.lastSmokeDanger = false
	state.lastFirePulse = 0
	state.deathHandled = false
	state.lastDamageCause = "ОГОНЬ"
	state.allowedHealth = PLAYER_MAX_HEALTH
	playerStates[player] = state
	player:SetAttribute("SmokeExposureSeconds", 0)
	player:SetAttribute("InsideSmokeZone", false)
	player:SetAttribute("NearActiveFire", false)
	player:SetAttribute("LastHazardCause", "")
	feedback:FireClient(player, "SmokeState", false, false, 0)
	return state
end

local function prepareCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Script") and child.Name == "Health" then
			child:Destroy()
		end
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("Script") and child.Name == "Health" then
			child:Destroy()
		end
	end)
	humanoid.MaxHealth = PLAYER_MAX_HEALTH
	humanoid.Health = PLAYER_MAX_HEALTH
	local state = resetPlayerHazardState(player)
	feedback:FireClient(player, "Spawn", PLAYER_MAX_HEALTH)

	humanoid.HealthChanged:Connect(function(value)
		if state.deathHandled then return end
		if value > state.allowedHealth + 0.01 then
			humanoid.Health = state.allowedHealth
		else
			state.allowedHealth = math.max(0, value)
		end
	end)

	humanoid.Died:Connect(function()
		if state.deathHandled then return end
		state.deathHandled = true
		player:SetAttribute("InsideSmokeZone", false)
		player:SetAttribute("NearActiveFire", false)
		local cause = state.lastDamageCause == "ДЫМ" and "ДЫМ" or "ОГОНЬ"
		player:SetAttribute("LastHazardCause", cause)
		feedback:FireClient(player, "Death", "ПОЖАРНЫЙ ПОСТРАДАЛ — " .. cause .. " — ПОПРОБУЙ ЕЩЁ РАЗ")
		resetMissionRequest:Fire(player)
	end)
end

local function preparePlayer(player)
	player:SetAttribute("HazardFireDamageNear", FIRE_DAMAGE_NEAR)
	player:SetAttribute("HazardFireDamageMid", FIRE_DAMAGE_MID)
	player:SetAttribute("HazardFireDamageFar", FIRE_DAMAGE_FAR)
	player:SetAttribute("HazardSmokeGraceSeconds", SMOKE_GRACE)
	player.CharacterAdded:Connect(function(character)
		prepareCharacter(player, character)
	end)
	if player.Character then task.spawn(prepareCharacter, player, player.Character) end
end

for _, player in ipairs(Players:GetPlayers()) do preparePlayer(player) end
Players.PlayerAdded:Connect(preparePlayer)
Players.PlayerRemoving:Connect(function(player) playerStates[player] = nil end)

RunService.Heartbeat:Connect(function(deltaTime)
	local dt = math.min(deltaTime, 0.16)
	local now = os.clock()
	local dispatchActive = gate:GetAttribute("DispatchArrived") == true
	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerStates[player]
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not state or not humanoid or humanoid.Health <= 0 or not root then continue end
		if not dispatchActive then
			player:SetAttribute("NearActiveFire", false)
			state.smokeExposure = 0
			feedback:FireClient(player, "SmokeClear")
			continue
		end

		local fireDps = 0
		for _, node in ipairs(fireTargets:GetChildren()) do
			if node:IsA("Model") and node:GetAttribute("State") == "Active" then
				local hitbox = node:FindFirstChild("Hitbox")
				if hitbox and hitbox:IsA("BasePart") then
					local distance = distanceToPart(root.Position, hitbox)
					if distance <= FIRE_NEAR_DISTANCE then
						fireDps += FIRE_DAMAGE_NEAR
					elseif distance <= FIRE_MID_DISTANCE then
						fireDps += FIRE_DAMAGE_MID
					elseif distance <= FIRE_FAR_DISTANCE then
						fireDps += FIRE_DAMAGE_FAR
					end
				end
			end
		end
		fireDps = math.min(fireDps, MAX_FIRE_DAMAGE)
		local nearFire = fireDps > 0
		player:SetAttribute("NearActiveFire", nearFire)
		if nearFire then
			state.lastDamageCause = "ОГОНЬ"
			humanoid:TakeDamage(fireDps * dt)
			if now - state.lastFirePulse >= FIRE_FLASH_INTERVAL then
				state.lastFirePulse = now
				feedback:FireClient(player, "FireDamage")
			end
		end
		if humanoid.Health <= 0 then continue end

		local insideSmoke = false
		local smokeDps = 0
		for _, zone in ipairs(smokeZones:GetChildren()) do
			if zone:IsA("BasePart") and linkedFireIsActive(zone) and pointInsideZone(root.Position, zone) then
				insideSmoke = true
				smokeDps = math.max(smokeDps, zone:GetAttribute("DamagePerSecond") or 12)
			end
		end
		if insideSmoke then
			state.smokeExposure += dt
		else
			state.smokeExposure = math.max(0, state.smokeExposure - SMOKE_RECOVERY * dt)
		end

		local smokeDanger = insideSmoke and state.smokeExposure >= SMOKE_GRACE
		if smokeDanger then
			state.lastDamageCause = "ДЫМ"
			humanoid:TakeDamage(smokeDps * dt)
		end
		player:SetAttribute("SmokeExposureSeconds", state.smokeExposure)
		player:SetAttribute("InsideSmokeZone", insideSmoke)
		if insideSmoke ~= state.lastSmokeInside
			or smokeDanger ~= state.lastSmokeDanger
			or now - state.lastSmokeSend >= SMOKE_FEEDBACK_INTERVAL then
			state.lastSmokeInside = insideSmoke
			state.lastSmokeDanger = smokeDanger
			state.lastSmokeSend = now
			feedback:FireClient(player, "SmokeState", insideSmoke, smokeDanger, math.clamp(state.smokeExposure / SMOKE_GRACE, 0, 1))
		end
	end
end)

print("Fire Challenge hazard server ready: 60/35/15 DPS fire, smoke 12/18/22 DPS")