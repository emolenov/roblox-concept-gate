-- WaterAndAftermathV1: visual-only flame scaling, steam, and persistent soot.
-- This controller observes FireNode attributes but never writes Health, State,
-- timing, mission gates, damage, raycasts, or extinguish progress.
local polish = script.Parent
local burntState = polish:WaitForChild("BurntState")
local gate = script:FindFirstAncestor("PlayableGateV1")
local fireTargets = gate:WaitForChild("Gameplay"):WaitForChild("InteriorV2"):WaitForChild("FireTargets")
local residualDuration = polish:GetAttribute("ResidualSteamDuration") or 3

local steamGeneration = {}
local lastExtinguished = {}

local function rememberFlame(part)
	if part:GetAttribute("VFXBaseSize") == nil then
		part:SetAttribute("VFXBaseSize", part.Size)
	end
	if part:GetAttribute("VFXBaseCFrame") == nil then
		part:SetAttribute("VFXBaseCFrame", part.CFrame)
	end
end

local function healthTier(node)
	local maximum = node:GetAttribute("MaxHealth") or 2.5
	local health = node:GetAttribute("Health") or maximum
	local ratio = maximum > 0 and math.clamp(health / maximum, 0, 1) or 0
	if ratio > 0.70 then
		return 1.00, ratio
	elseif ratio > 0.40 then
		return 0.80, ratio
	elseif ratio > 0.15 then
		return 0.55, ratio
	end
	return 0.30, ratio
end

local function refreshFlameVisual(node)
	local state = node:GetAttribute("State")
	local active = state == "Active"
	local scale, ratio = healthTier(node)
	for _, descendant in ipairs(node:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("FireVisual") then
			rememberFlame(descendant)
			local baseSize = descendant:GetAttribute("VFXBaseSize")
			local baseCFrame = descendant:GetAttribute("VFXBaseCFrame")
			if active and typeof(baseSize) == "Vector3" and typeof(baseCFrame) == "CFrame" then
				descendant.Size = baseSize * scale
				descendant.CFrame = baseCFrame * CFrame.new(0, -baseSize.Y * (1 - scale) * 0.5, 0)
				local baseTransparency = descendant:GetAttribute("ActiveTransparency") or 0
				descendant.Transparency = math.clamp(baseTransparency + (1 - scale) * 0.12, 0, 0.9)
			elseif typeof(baseSize) == "Vector3" and typeof(baseCFrame) == "CFrame" then
				descendant.Size = baseSize
				descendant.CFrame = baseCFrame
			end
		elseif descendant:IsA("Light") and active then
			descendant.Brightness = 0.55 + 1.25 * math.max(ratio, 0.15)
		end
	end
end

local function setMarksVisible(group, visible)
	for _, descendant in ipairs(group:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("BurntVisual") then
			descendant.Transparency = visible
				and (descendant:GetAttribute("BurntTransparency") or 0.45)
				or 1
		end
	end
end

local function stopResidualSteam(group)
	steamGeneration[group] = (steamGeneration[group] or 0) + 1
	for _, descendant in ipairs(group:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") and descendant.Name == "ResidualSteam" then
			descendant.Enabled = false
		end
	end
end

local function startResidualSteam(group)
	local generation = (steamGeneration[group] or 0) + 1
	steamGeneration[group] = generation
	for _, descendant in ipairs(group:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") and descendant.Name == "ResidualSteam" then
			descendant.Enabled = true
		end
	end
	task.delay(residualDuration, function()
		if steamGeneration[group] ~= generation then
			return
		end
		for _, descendant in ipairs(group:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") and descendant.Name == "ResidualSteam" then
				descendant.Enabled = false
			end
		end
	end)
end

local function bindGroup(group)
	local nodeName = group:GetAttribute("LinkedFireNode")
	local node = typeof(nodeName) == "string" and fireTargets:FindFirstChild(nodeName)
	if not node then
		setMarksVisible(group, false)
		stopResidualSteam(group)
		warn("WaterAndAftermathV1 missing linked FireNode: " .. tostring(nodeName))
		return
	end

	for _, descendant in ipairs(node:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("FireVisual") then
			rememberFlame(descendant)
		end
	end

	local function refreshAftermath(initial)
		local extinguished = node:GetAttribute("State") == "Extinguished"
			or node:GetAttribute("Extinguished") == true
		setMarksVisible(group, extinguished)
		if extinguished then
			if not initial and not lastExtinguished[group] then
				startResidualSteam(group)
			end
		else
			stopResidualSteam(group)
		end
		lastExtinguished[group] = extinguished
	end

	local function refreshAll(initial)
		refreshFlameVisual(node)
		refreshAftermath(initial)
	end

	node:GetAttributeChangedSignal("Health"):Connect(function()
		refreshFlameVisual(node)
	end)
	node:GetAttributeChangedSignal("State"):Connect(function()
		refreshAll(false)
	end)
	node:GetAttributeChangedSignal("Extinguished"):Connect(function()
		refreshAftermath(false)
	end)
	refreshAll(true)
end

for _, group in ipairs(burntState:GetChildren()) do
	if group:IsA("Folder") then
		bindGroup(group)
	end
end
