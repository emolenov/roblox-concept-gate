local Players = game:GetService("Players")

local gameplay = script.Parent
local gate = gameplay.Parent
local billboard = gameplay:WaitForChild("ExteriorStatusAnchor"):WaitForChild("ExteriorStatusBillboard")

local function updateFromGate()
	local visible = gate:GetAttribute("ExteriorFiresOut") == true
	if visible then
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("InsideInteriorV2") == true then
				visible = false
				break
			end
		end
	end
	billboard.Enabled = visible
end

gate:GetAttributeChangedSignal("ExteriorFiresOut"):Connect(updateFromGate)
task.spawn(function()
	while script.Parent do
		updateFromGate()
		task.wait(0.2)
	end
end)
updateFromGate()

local function preparePlayer(player)
	player:GetAttributeChangedSignal("InsideInteriorV2"):Connect(function()
		updateFromGate()
	end)
end

for _, player in Players:GetPlayers() do
	preparePlayer(player)
end
Players.PlayerAdded:Connect(preparePlayer)
