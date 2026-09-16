local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local gameplay = script.Parent
local gate = gameplay.Parent
local interior = gameplay:WaitForChild("InteriorV2")
local fireTargets = interior:WaitForChild("FireTargets")
local resident = interior:WaitForChild("RescueResident")
local humanoid = resident:WaitForChild("Humanoid")
local root = resident:WaitForChild("HumanoidRootPart")
local instruction = resident:WaitForChild("Head"):WaitForChild("FollowerInstruction")
local safeZone = gameplay:WaitForChild("RescueSafeZone")
local successAnchor = gameplay:WaitForChild("SuccessAnchor")
local successBillboard = successAnchor:WaitForChild("SuccessBillboard")
local portals = interior:WaitForChild("Portals")
local externalEntranceTrigger = portals:WaitForChild("ExternalEntranceTrigger")
local interiorExitTrigger = portals:WaitForChild("InteriorExitTrigger")
local interiorArrivalMarker = portals:WaitForChild("InteriorArrivalMarker")
local exteriorReturnMarker = portals:WaitForChild("ExteriorReturnMarker")
local exteriorDirection = (exteriorReturnMarker.Position - externalEntranceTrigger.Position).Unit

local PATH_REBUILD_INTERVAL = 0.4
local NAVIGATION_TICK = 0.1
local FOLLOW_DISTANCE = 5
local STOP_DISTANCE = 4
local SLOW_DISTANCE = 6
local PLAYER_NEAR_SAFE_DISTANCE = 10
local EXIT_READY_DISTANCE = 5.5
local BASE_WALK_SPEED = 18
local CATCH_UP_SPEED = 22
local MAX_CATCH_UP_SPEED = 24
local WAYPOINT_REACHED_DISTANCE = 2.5
local GOAL_SHIFT_FOR_REBUILD = 2.5
local MOVE_REFRESH_INTERVAL = 0.35
local DIRECT_MOVE_REFRESH_INTERVAL = 0.22
local STUCK_REBUILD_DELAY = 1.15
local EMERGENCY_DISTANCE = 30
local EMERGENCY_REBUILD_ATTEMPTS = 3

local loopGeneration = 0
local finishing = false
local followerStartedAt = 0
local emergencyRepositionUsed = false
local lastProgressPosition = root.Position
local lastProgressTime = os.clock()
local stuckRebuildAttempts = 0

local directMoveTarget = nil
local lastDirectMoveTime = -math.huge

local pathState = {
	path = nil,
	waypoints = {},
	index = 1,
	lastGoal = nil,
	lastBuildTime = -math.huge,
	blocked = true,
	blockedConnection = nil,
	lastMoveTarget = nil,
	lastMoveTime = -math.huge,
}

local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
animator.Parent = humanoid
local runAnimation = resident:WaitForChild("FollowerRunAnimation")
local idleAnimation = resident:WaitForChild("FollowerIdleAnimation")
local runTrack
local idleTrack

local function loadAnimation(animation, priority)
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = true
	track.Priority = priority
	return track
end

runTrack = loadAnimation(runAnimation, Enum.AnimationPriority.Movement)
idleTrack = loadAnimation(idleAnimation, Enum.AnimationPriority.Idle)

local function showIdle()
	if runTrack and runTrack.IsPlaying then
		runTrack:Stop(0.15)
	end
	if idleTrack and not idleTrack.IsPlaying then
		idleTrack:Play(0.15)
	end
end

local function showRunning(actualSpeed)
	if idleTrack and idleTrack.IsPlaying then
		idleTrack:Stop(0.12)
	end
	if runTrack then
		if not runTrack.IsPlaying then
			runTrack:Play(0.12)
		end
		runTrack:AdjustSpeed(math.clamp(actualSpeed / 14, 0.85, 1.7))
	end
end

humanoid.Running:Connect(function(actualSpeed)
	if gate:GetAttribute("RescueFollowerActive") == true and actualSpeed > 0.6 then
		showRunning(actualSpeed)
	else
		showIdle()
	end
end)
showIdle()

local function registerCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("RescueFollowerNPC")
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup("RescueFollowerPlayer")
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable("RescueFollowerNPC", "RescueFollowerPlayer", false)
	end)
end

local function setPlayerCollisionGroup(character)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "RescueFollowerPlayer"
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "RescueFollowerPlayer"
		end
	end)
end

local function preparePlayer(player)
	player.CharacterAdded:Connect(setPlayerCollisionGroup)
	if player.Character then
		setPlayerCollisionGroup(player.Character)
	end
end

registerCollisionGroups()
for _, player in Players:GetPlayers() do
	preparePlayer(player)
end
Players.PlayerAdded:Connect(preparePlayer)

local function setResidentAnchored(anchored)
	for _, descendant in resident:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
		end
	end
	if not anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
end

local function setResidentCollisionGroups()
	for _, descendant in resident:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "RescueFollowerNPC"
			descendant.CanTouch = false
			if descendant ~= root then
				descendant.CanCollide = false
			end
		end
	end
	root.CanCollide = true
end

local function getOwner()
	local userId = gate:GetAttribute("RescueFollowerPlayerUserId")
	if typeof(userId) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

local function getLivingPlayerRoot(player)
	local character = player and player.Character
	local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not playerHumanoid or playerHumanoid.Health <= 0 or not playerRoot then
		return nil
	end
	return playerRoot
end

local function horizontalDistance(a, b)
	local delta = Vector3.new(a.X - b.X, 0, a.Z - b.Z)
	return delta.Magnitude
end

local function pointInZone(point, zone, horizontalPadding)
	local localPoint = zone.CFrame:PointToObjectSpace(point)
	local half = zone.Size * 0.5
	return math.abs(localPoint.X) <= half.X + horizontalPadding
		and math.abs(localPoint.Y) <= half.Y + 6
		and math.abs(localPoint.Z) <= half.Z + horizontalPadding
end

local function clearPath()
	if pathState.blockedConnection then
		pathState.blockedConnection:Disconnect()
		pathState.blockedConnection = nil
	end
	pathState.path = nil
	pathState.waypoints = {}
	pathState.index = 1
	pathState.lastGoal = nil
	pathState.blocked = true
	pathState.lastMoveTarget = nil
end

local function stopMoving(state)
	humanoid.WalkSpeed = 0
	humanoid:MoveTo(root.Position)
	humanoid.Jump = false
	if state then
		resident:SetAttribute("FollowerState", state)
	end
end

local function setDynamicSpeed(distance)
	if distance < STOP_DISTANCE then
		humanoid.WalkSpeed = 0
	elseif distance <= SLOW_DISTANCE then
		local alpha = math.clamp((distance - STOP_DISTANCE) / (SLOW_DISTANCE - STOP_DISTANCE), 0, 1)
		humanoid.WalkSpeed = 8 + 10 * alpha
	elseif distance > 20 then
		humanoid.WalkSpeed = MAX_CATCH_UP_SPEED
	elseif distance > 12 then
		humanoid.WalkSpeed = CATCH_UP_SPEED
	else
		humanoid.WalkSpeed = BASE_WALK_SPEED
	end
end

local function rebuildPath(goal, force)
	local now = os.clock()
	local goalShift = pathState.lastGoal and (goal - pathState.lastGoal).Magnitude or math.huge
	local routeUsable = pathState.path
		and not pathState.blocked
		and pathState.index <= #pathState.waypoints

	if not force and routeUsable then
		if now - pathState.lastBuildTime < PATH_REBUILD_INTERVAL then
			return true
		end
		if goalShift < GOAL_SHIFT_FOR_REBUILD then
			return true
		end
	end

	if pathState.blockedConnection then
		pathState.blockedConnection:Disconnect()
		pathState.blockedConnection = nil
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = 1.35,
		AgentHeight = 4.8,
		AgentCanJump = true,
		AgentCanClimb = true,
		WaypointSpacing = 3,
		Costs = {
			Water = math.huge,
		},
	})
	local ok = pcall(function()
		path:ComputeAsync(root.Position, goal)
	end)
	pathState.lastBuildTime = now
	pathState.lastGoal = goal

	if not ok or path.Status ~= Enum.PathStatus.Success then
		pathState.path = nil
		pathState.waypoints = {}
		pathState.index = 1
		pathState.blocked = true
		return false
	end

	pathState.path = path
	pathState.waypoints = path:GetWaypoints()
	pathState.index = 2
	pathState.blocked = false
	pathState.lastMoveTarget = nil

	while pathState.index <= #pathState.waypoints
		and (pathState.waypoints[pathState.index].Position - root.Position).Magnitude <= WAYPOINT_REACHED_DISTANCE do
		pathState.index += 1
	end

	pathState.blockedConnection = path.Blocked:Connect(function(blockedIndex)
		if blockedIndex >= pathState.index then
			pathState.blocked = true
		end
	end)
	return true
end

local function issueContinuousMove(goal)
	rebuildPath(goal, false)

	while pathState.index <= #pathState.waypoints
		and (pathState.waypoints[pathState.index].Position - root.Position).Magnitude <= WAYPOINT_REACHED_DISTANCE do
		pathState.index += 1
	end

	local moveTarget = goal
	local waypoint = pathState.waypoints[pathState.index]
	if waypoint then
		moveTarget = waypoint.Position
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
	end

	local now = os.clock()
	local targetChanged = not pathState.lastMoveTarget
		or (moveTarget - pathState.lastMoveTarget).Magnitude > 0.6
	if targetChanged or now - pathState.lastMoveTime >= MOVE_REFRESH_INTERVAL then
		humanoid:MoveTo(moveTarget)
		pathState.lastMoveTarget = moveTarget
		pathState.lastMoveTime = now
	end
end

local function issueDirectMove(goal)
	local now = os.clock()
	local targetChanged = not directMoveTarget or (goal - directMoveTarget).Magnitude > 0.6
	if targetChanged or now - lastDirectMoveTime >= DIRECT_MOVE_REFRESH_INTERVAL then
		humanoid:MoveTo(goal)
		directMoveTarget = goal
		lastDirectMoveTime = now
	end
end

local function moveContinuously(goal, state, referenceDistance, useDirectMovement)
	if referenceDistance < STOP_DISTANCE then
		stopMoving(state)
		return
	end
	setDynamicSpeed(referenceDistance)
	if useDirectMovement then
		issueDirectMove(goal)
	else
		issueContinuousMove(goal)
	end
	resident:SetAttribute("FollowerState", state)
end

local function getExteriorFollowGoal(playerRoot)
	local goal = playerRoot.Position - playerRoot.CFrame.LookVector * FOLLOW_DISTANCE
	local exteriorProjection = (goal - externalEntranceTrigger.Position):Dot(exteriorDirection)
	local minimumExteriorProjection = 1.4
	if exteriorProjection < minimumExteriorProjection then
		goal += exteriorDirection * (minimumExteriorProjection - exteriorProjection)
	end
	return goal
end

local function isFreeEmergencyPosition(position, character)
	if pointInZone(position, safeZone, 1) then
		return false
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = {resident, character}
	for _, part in workspace:GetPartBoundsInBox(CFrame.new(position), Vector3.new(2.5, 4.8, 2.5), overlap) do
		if part.CanCollide then
			return false
		end
	end
	return true
end

local function groundEmergencyCandidate(candidate, character)
	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	raycast.FilterDescendantsInstances = {resident, character}
	local result = workspace:Raycast(candidate + Vector3.new(0, 14, 0), Vector3.new(0, -40, 0), raycast)
	if not result then
		return nil
	end
	local boxCFrame, boxSize = resident:GetBoundingBox()
	local rootToBottom = root.Position.Y - (boxCFrame.Position.Y - boxSize.Y * 0.5)
	local grounded = Vector3.new(candidate.X, result.Position.Y + rootToBottom + 0.05, candidate.Z)
	if not isFreeEmergencyPosition(grounded, character) then
		return nil
	end
	return grounded
end

local function tryEmergencyReposition(playerRoot)
	if emergencyRepositionUsed then
		return false
	end

	local candidates = {}
	for index = #pathState.waypoints, math.max(pathState.index, 1), -1 do
		local waypointPosition = pathState.waypoints[index].Position
		local distanceToPlayer = horizontalDistance(waypointPosition, playerRoot.Position)
		if distanceToPlayer >= 7 and distanceToPlayer <= 14 then
			table.insert(candidates, waypointPosition)
		end
	end
	local behind = playerRoot.Position - playerRoot.CFrame.LookVector * 9
	table.insert(candidates, behind)
	table.insert(candidates, behind + playerRoot.CFrame.RightVector * 4)
	table.insert(candidates, behind - playerRoot.CFrame.RightVector * 4)

	for _, candidate in candidates do
		local grounded = groundEmergencyCandidate(candidate, playerRoot.Parent)
		if grounded then
			local delta = grounded - root.Position
			resident:PivotTo(resident:GetPivot() + delta)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			emergencyRepositionUsed = true
			gate:SetAttribute("FollowerEmergencyRepositionUsed", true)
			clearPath()
			lastProgressPosition = root.Position
			lastProgressTime = os.clock()
			stuckRebuildAttempts = 0
			return true
		end
	end
	return false
end

local function trackProgress(goal, playerRoot, allowEmergency, useDirectMovement)
	local now = os.clock()
	if (root.Position - lastProgressPosition).Magnitude >= 0.45 then
		lastProgressPosition = root.Position
		lastProgressTime = now
		stuckRebuildAttempts = 0
		return
	end

	if (root.Position - goal).Magnitude <= 6 or now - lastProgressTime < STUCK_REBUILD_DELAY then
		return
	end

	stuckRebuildAttempts += 1
	lastProgressTime = now
	lastProgressPosition = root.Position
	if useDirectMovement then
		directMoveTarget = nil
		issueDirectMove(goal)
		if stuckRebuildAttempts >= 2 then
			humanoid.Jump = true
		end
	else
		pathState.blocked = true
		humanoid.Jump = true
		rebuildPath(goal, true)
	end

	if allowEmergency
		and (root.Position - playerRoot.Position).Magnitude > EMERGENCY_DISTANCE
		and stuckRebuildAttempts >= EMERGENCY_REBUILD_ATTEMPTS then
		tryEmergencyReposition(playerRoot)
	end
end

local function recordSameSpaceDistance(playerRoot)
	local distance = (root.Position - playerRoot.Position).Magnitude
	local currentMaximum = gate:GetAttribute("FollowerMaximumDistance")
	if typeof(currentMaximum) ~= "number" or distance > currentMaximum then
		gate:SetAttribute("FollowerMaximumDistance", distance)
	end
	return distance
end

local function transferToExterior(playerRoot)
	if gate:GetAttribute("FrontDoorOpen") ~= true then
		return false
	end

	local exteriorCFrame = exteriorReturnMarker.CFrame * CFrame.new(0, 0, 0.8)
	resident:PivotTo(exteriorCFrame)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	resident:SetAttribute("FollowerSpace", "Exterior")
	resident:SetAttribute("FollowerState", "FollowingOutside")
	gate:SetAttribute("ResidentAtInteriorExit", false)
	if followerStartedAt > 0 then
		gate:SetAttribute("FollowerExitElapsedSeconds", workspace:GetServerTimeNow() - followerStartedAt)
	end
	clearPath()
	lastProgressPosition = root.Position
	lastProgressTime = os.clock()
	stuckRebuildAttempts = 0

	humanoid.WalkSpeed = BASE_WALK_SPEED
	humanoid:MoveTo(getExteriorFollowGoal(playerRoot))
	return true
end

local function completeRescue(player, playerRoot)
	if finishing or gate:GetAttribute("ResidentRescued") == true then
		return
	end
	finishing = true
	stopMoving("Safe")

	local pivotPosition = resident:GetPivot().Position
	local lookTarget = Vector3.new(playerRoot.Position.X, pivotPosition.Y, playerRoot.Position.Z)
	if (lookTarget - pivotPosition).Magnitude > 0.1 then
		resident:PivotTo(CFrame.lookAt(pivotPosition, lookTarget))
	end
	setResidentAnchored(true)

	if followerStartedAt > 0 then
		gate:SetAttribute("FollowerTotalElapsedSeconds", workspace:GetServerTimeNow() - followerStartedAt)
	end
	gate:SetAttribute("ResidentRescued", true)
	gate:SetAttribute("MissionCompleted", true)
	gate:SetAttribute("RescueReady", false)
	gate:SetAttribute("RescueFollowerActive", false)
	gate:SetAttribute("ResidentAtInteriorExit", false)
	resident:SetAttribute("FollowerState", "Safe")
	instruction.Enabled = false
	showIdle()

	successAnchor.Position = resident:GetPivot().Position + Vector3.new(0, 4.2, 0)
	successBillboard.Message.Text = "ЧЕЛОВЕК СПАСЁН!"
	successBillboard.Enabled = true

	local started = player:GetAttribute("MissionStartTime")
	if typeof(started) == "number" then
		gate:SetAttribute("MissionElapsedSeconds", workspace:GetServerTimeNow() - started)
	end
end

local RETURN_ROUTE_FIRE_NAMES = {
	"InteriorFire_Entry",
	"InteriorFire_Hall",
	"InteriorFire_StairsBottom",
	"InteriorFire_StairsLanding",
	"InteriorFire_UpperHall",
}

local function returnRouteIsClear()
	for _, name in ipairs(RETURN_ROUTE_FIRE_NAMES) do
		local node = fireTargets:FindFirstChild(name)
		if node and node:GetAttribute("State") == "Active" then
			return false
		end
	end
	return true
end

local function runFollower(generation)
	setResidentCollisionGroups()
	setResidentAnchored(false)
	humanoid.WalkSpeed = BASE_WALK_SPEED
	humanoid.AutoRotate = true
	humanoid.PlatformStand = false
	humanoid.Sit = false
	resident:SetAttribute("FollowerSpace", "Interior")
	resident:SetAttribute("FollowerState", "FollowingInside")
	gate:SetAttribute("ResidentAtInteriorExit", false)
	gate:SetAttribute("FollowerExitElapsedSeconds", nil)
	gate:SetAttribute("FollowerTotalElapsedSeconds", nil)
	gate:SetAttribute("FollowerMaximumDistance", 0)
	gate:SetAttribute("FollowerEmergencyRepositionUsed", false)
	followerStartedAt = workspace:GetServerTimeNow()
	emergencyRepositionUsed = false
	clearPath()
	lastProgressPosition = root.Position
	lastProgressTime = os.clock()
	stuckRebuildAttempts = 0

	instruction.Enabled = true
	task.delay(4, function()
		if loopGeneration == generation and instruction.Parent then
			instruction.Enabled = false
		end
	end)

	while loopGeneration == generation
		and gate:GetAttribute("RescueFollowerActive") == true
		and gate:GetAttribute("ResidentRescued") ~= true do

		local player = getOwner()
		local playerRoot = getLivingPlayerRoot(player)
		if not playerRoot then
			stopMoving("WaitingForPlayer")
			task.wait(PATH_REBUILD_INTERVAL)
			continue
		end

		local space = resident:GetAttribute("FollowerSpace")
		local playerInside = player:GetAttribute("InsideInteriorV2") == true
		if space == "Interior" and not returnRouteIsClear() then
			stopMoving("WaitingForClearPath")
			task.wait(NAVIGATION_TICK)
			continue
		end
		local goal
		local allowEmergency = false
		local useDirectMovement = false

		if space == "Interior" then
			if playerInside then
				gate:SetAttribute("ResidentAtInteriorExit", false)
				local playerDistance = recordSameSpaceDistance(playerRoot)
				if playerDistance < STOP_DISTANCE then
					stopMoving("FollowingInside")
				else
					goal = playerRoot.Position - playerRoot.CFrame.LookVector * FOLLOW_DISTANCE
					moveContinuously(goal, "FollowingInside", playerDistance, true)
					allowEmergency = true
					useDirectMovement = true
				end
			else
				goal = Vector3.new(
					interiorArrivalMarker.Position.X - 2.1,
					interiorArrivalMarker.Position.Y - 1.8,
					interiorArrivalMarker.Position.Z
				)
				local exitDistance = (root.Position - goal).Magnitude
				if exitDistance <= EXIT_READY_DISTANCE then
					gate:SetAttribute("ResidentAtInteriorExit", true)
					stopMoving("AtInteriorExit")
					if gate:GetAttribute("FrontDoorOpen") == true then
						transferToExterior(playerRoot)
						goal = nil
					end
				else
					gate:SetAttribute("ResidentAtInteriorExit", false)
					moveContinuously(goal, "GoingToInteriorExit", exitDistance, true)
					useDirectMovement = true
				end
			end
		else
			local playerDistance = recordSameSpaceDistance(playerRoot)
			local npcInSafeZone = pointInZone(root.Position, safeZone, 0.8)
			local playerNearSafeZone = horizontalDistance(playerRoot.Position, safeZone.Position) <= PLAYER_NEAR_SAFE_DISTANCE
				and math.abs(playerRoot.Position.Y - safeZone.Position.Y) <= 10

			if npcInSafeZone then
				stopMoving("WaitingInSafeZone")
				if playerNearSafeZone then
					completeRescue(player, playerRoot)
					break
				end
			elseif playerNearSafeZone then
				goal = Vector3.new(
					safeZone.Position.X,
					safeZone.Position.Y + 1.1,
					safeZone.Position.Z
				)
				local safeDistance = (root.Position - goal).Magnitude
				setDynamicSpeed(math.max(safeDistance, SLOW_DISTANCE))
				issueContinuousMove(goal)
				resident:SetAttribute("FollowerState", "GoingToSafeZone")
				allowEmergency = true
			else
				if playerDistance < STOP_DISTANCE then
					stopMoving("FollowingOutside")
				else
					goal = getExteriorFollowGoal(playerRoot)
					moveContinuously(goal, "FollowingOutside", playerDistance)
					allowEmergency = true
				end
			end
		end

		if goal then
			trackProgress(goal, playerRoot, allowEmergency, useDirectMovement)
		end
		task.wait(NAVIGATION_TICK)
	end
end

local function beginFollower()
	if gate:GetAttribute("RescueFollowerActive") ~= true or gate:GetAttribute("ResidentRescued") == true then
		return
	end
	loopGeneration += 1
	finishing = false
	local generation = loopGeneration
	task.spawn(runFollower, generation)
end

local function stopFollowerIfInactive()
	if gate:GetAttribute("RescueFollowerActive") == true then
		beginFollower()
		return
	end
	loopGeneration += 1
	clearPath()
	instruction.Enabled = false
	if gate:GetAttribute("ResidentRescued") ~= true then
		stopMoving("Waiting")
		setResidentAnchored(true)
	end
end

gate:GetAttributeChangedSignal("RescueFollowerActive"):Connect(stopFollowerIfInactive)
setResidentCollisionGroups()
if gate:GetAttribute("RescueFollowerActive") == true then
	beginFollower()
else
	setResidentAnchored(true)
	instruction.Enabled = false
end
