-- WaterAndAftermathV1: client-only visual layer.
-- This script never fires WaterInput and never writes FireNode Health or State.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local vfx = script.Parent
local gameplay = vfx.Parent
local gate = gameplay.Parent
local waterInput = gameplay:WaitForChild("WaterInput")

local originPart = vfx:WaitForChild("OriginAnchor")
local impactPart = vfx:WaitForChild("ImpactAnchor")
local originAttachment = originPart:WaitForChild("OriginAttachment")
local impactAttachment = impactPart:WaitForChild("ImpactAttachment")

local streamCore = originAttachment:WaitForChild("StreamCore")
local streamBody = originAttachment:WaitForChild("StreamBody")
local streamEdge = originAttachment:WaitForChild("StreamEdge")
local beams = {streamCore, streamBody, streamEdge}

local nozzleDroplets = originAttachment:WaitForChild("NozzleDroplets")
local impactDroplets = impactAttachment:WaitForChild("ImpactDroplets")
local impactHeavyDrops = impactAttachment:WaitForChild("ImpactHeavyDrops")
local impactMist = impactAttachment:WaitForChild("ImpactMist")
local fireSteam = impactAttachment:WaitForChild("FireSteam")
local impactEmitters = {impactDroplets, impactHeavyDrops, impactMist}
local impactSplashCore = vfx:WaitForChild("ImpactSplashCore")
local impactSplashHalo = vfx:WaitForChild("ImpactSplashHalo")

local spraying = false
local confirmedFireUntil = 0
local confirmedTarget
local confirmedFireNode

local function getNozzle()
	local character = player.Character
	local tool = character and character:FindFirstChild("FireHoseTool")
	local handle = tool and tool:FindFirstChild("Handle")
	return handle and handle:FindFirstChild("NozzleTipAttachment")
end

local function getAimPosition(origin)
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

local function isFireNode(instance)
	return instance
		and instance:IsA("Model")
		and instance:GetAttribute("State") ~= nil
		and instance:GetAttribute("Health") ~= nil
		and instance:FindFirstChild("Hitbox", true) ~= nil
end

local function fireNodeFromInstance(instance)
	local current = instance
	while current and current ~= gameplay do
		if isFireNode(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function nearestActiveFireNode(position)
	local nearest
	local nearestDistance = math.huge
	for _, node in ipairs(gameplay:GetDescendants()) do
		if isFireNode(node) and node:GetAttribute("State") == "Active" then
			local hitbox = node:FindFirstChild("Hitbox", true)
			if hitbox and hitbox:IsA("BasePart") then
				local distance = (hitbox:GetClosestPointOnSurface(position) - position).Magnitude
				if distance < nearestDistance and distance <= 6 then
					nearest = node
					nearestDistance = distance
				end
			end
		end
	end
	return nearest
end

local function setEnabled(list, enabled)
	for _, item in ipairs(list) do
		item.Enabled = enabled
	end
end

local function hideAll()
	setEnabled(beams, false)
	nozzleDroplets.Enabled = false
	setEnabled(impactEmitters, false)
	fireSteam.Enabled = false
	fireSteam.Rate = 0
	impactSplashCore.Transparency = 1
	impactSplashHalo.Transparency = 1
end

local function visualRaycast(origin, aim)
	local offset = aim - origin
	if offset.Magnitude < 0.1 then
		return origin, nil, nil, false
	end
	local direction = offset.Unit * math.min(offset.Magnitude, 75)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filters = {vfx}
	local character = player.Character
	if character then
		table.insert(filters, character)
	end
	for _, name in ipairs({"LocalWaterStream", "LocalWaterOrigin", "LocalWaterImpact", "WaterImpactGlow"}) do
		local legacy = gameplay:FindFirstChild(name)
		if legacy then
			table.insert(filters, legacy)
		end
	end
	params.FilterDescendantsInstances = filters
	params.IgnoreWater = true
	local result = workspace:Raycast(origin, direction, params)
	if result then
		return result.Position, result.Normal, fireNodeFromInstance(result.Instance), true
	end
	return origin + direction, -direction.Unit, nil, false
end

local function healthScale(node)
	if not node then
		return 1
	end
	local maximum = node:GetAttribute("MaxHealth") or 2.5
	local health = node:GetAttribute("Health") or maximum
	if maximum <= 0 then
		return 0
	end
	return math.clamp(health / maximum, 0, 1)
end

local function showWater(origin, target, normal, hasSurface, activeFireNode)
	local distance = (target - origin).Magnitude
	if distance < 0.1 then
		hideAll()
		return
	end

	originPart.CFrame = CFrame.lookAt(origin, target)
	if normal and normal.Magnitude > 0.01 then
		impactPart.CFrame = CFrame.lookAt(target + normal.Unit * 0.045, target + normal.Unit)
	else
		impactPart.CFrame = CFrame.lookAt(target, origin)
	end
	impactSplashCore.CFrame = impactPart.CFrame
	impactSplashHalo.CFrame = impactPart.CFrame
	local impactPulse = 0.94 + math.sin(os.clock() * 21) * 0.08
	impactSplashCore.Size = Vector3.new(0.82, 0.82, 0.82) * impactPulse
	impactSplashHalo.Size = Vector3.new(1.55, 0.72, 1.55) * impactPulse
	impactSplashCore.Transparency = hasSurface and 0.30 or 1
	impactSplashHalo.Transparency = hasSurface and 0.62 or 1

	local wave = os.clock() * 8
	local sharedBend0 = 0.10 + math.sin(wave) * 0.045
	local sharedBend1 = -0.10 + math.cos(wave * 0.9) * 0.045
	streamCore.CurveSize0 = sharedBend0
	streamCore.CurveSize1 = sharedBend1
	streamBody.CurveSize0 = sharedBend0 + math.sin(wave * 0.72) * 0.025
	streamBody.CurveSize1 = sharedBend1 + math.cos(wave * 0.8) * 0.025
	streamEdge.CurveSize0 = sharedBend0 + math.sin(wave * 1.15) * 0.07
	streamEdge.CurveSize1 = sharedBend1 + math.cos(wave * 1.05) * 0.07

	setEnabled(beams, true)
	nozzleDroplets.Enabled = true
	setEnabled(impactEmitters, hasSurface)

	if activeFireNode then
		local ratio = healthScale(activeFireNode)
		if ratio > 0.7 then
			fireSteam.Rate = 18
		elseif ratio > 0.4 then
			fireSteam.Rate = 30
		elseif ratio > 0.15 then
			fireSteam.Rate = 46
		else
			fireSteam.Rate = 68
		end
		fireSteam.Enabled = true
	else
		fireSteam.Rate = 0
		fireSteam.Enabled = false
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		and player:GetAttribute("HoseEquipped") == true
		and getNozzle() then
		spraying = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		spraying = false
		hideAll()
	end
end)

player:GetAttributeChangedSignal("HoseEquipped"):Connect(function()
	if player:GetAttribute("HoseEquipped") ~= true then
		spraying = false
		confirmedFireUntil = 0
		confirmedTarget = nil
		hideAll()
	end
end)

player:GetAttributeChangedSignal("LocalHoseSpraying"):Connect(function()
	if player:GetAttribute("LocalHoseSpraying") == true
		and player:GetAttribute("HoseEquipped") == true
		and getNozzle() then
		spraying = true
	else
		spraying = false
		hideAll()
	end
end)

player.CharacterAdded:Connect(function()
	spraying = false
	confirmedFireUntil = 0
	confirmedTarget = nil
	hideAll()
end)

waterInput.OnClientEvent:Connect(function(message, _, target)
	if message == "Spray" and typeof(target) == "Vector3" then
		confirmedFireUntil = os.clock() + 0.24
		confirmedTarget = target
		confirmedFireNode = nearestActiveFireNode(target)
	elseif message == "Reset" or message == "HoseStored" or message == "Complete" then
		spraying = false
		confirmedFireUntil = 0
		confirmedTarget = nil
		hideAll()
	end
end)

RunService:BindToRenderStep("WaterAndAftermathV1", Enum.RenderPriority.Camera.Value + 12, function()
	local nozzle = getNozzle()
	if not spraying or player:GetAttribute("HoseEquipped") ~= true or not nozzle then
		hideAll()
		return
	end

	local origin = nozzle.WorldPosition
	local target, normal, localFireNode, hasSurface = visualRaycast(origin, getAimPosition(origin))
	local confirmed = confirmedTarget
		and confirmedFireUntil > os.clock()
		and (confirmedTarget - target).Magnitude <= 6

	local activeFireNode
	if confirmed and confirmedFireNode and confirmedFireNode:GetAttribute("State") == "Active" then
		activeFireNode = confirmedFireNode
		target = confirmedTarget
		hasSurface = true
	elseif localFireNode and localFireNode:GetAttribute("State") == "Active" then
		activeFireNode = nil
	end
	showWater(origin, target, normal, hasSurface, activeFireNode)
end)

hideAll()
