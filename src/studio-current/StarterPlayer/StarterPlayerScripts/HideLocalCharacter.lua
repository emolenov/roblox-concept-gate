local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local function hideLocalObject(instance)
	if instance:IsA("BasePart") then
		instance.LocalTransparencyModifier = 1
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		instance.Transparency = 1
	end
end

local function hideLocalCharacter(character)
	for _, descendant in ipairs(character:GetDescendants()) do
		hideLocalObject(descendant)
	end

	character.DescendantAdded:Connect(hideLocalObject)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not character.Parent then
			connection:Disconnect()
			return
		end
		for _, descendant in ipairs(character:GetDescendants()) do
			hideLocalObject(descendant)
		end
	end)
end

player.CharacterAdded:Connect(hideLocalCharacter)
if player.Character then
	hideLocalCharacter(player.Character)
end
