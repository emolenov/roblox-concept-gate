local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local graybox = script.Parent
local fireTruck = graybox:WaitForChild("FireTruck")
local fireMarker = graybox:WaitForChild("FireMarker")

local START_DELAY = 2
local MOVE_DURATION = 4
local MARKER_DELAY = 0.2
local TOTAL_DURATION = 8
local TARGET_POSITION = Vector3.new(0, 1.3, 2)

local sequenceStartedAt = os.clock()

task.wait(START_DELAY)

local startPivot = fireTruck:GetPivot()
local endPivot = CFrame.new(TARGET_POSITION) * startPivot.Rotation
local elapsed = 0

while elapsed < MOVE_DURATION do
	local deltaTime = RunService.Heartbeat:Wait()
	elapsed = math.min(elapsed + deltaTime, MOVE_DURATION)

	local alpha = elapsed / MOVE_DURATION
	local easedAlpha = TweenService:GetValue(
		alpha,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)

	fireTruck:PivotTo(startPivot:Lerp(endPivot, easedAlpha))
end

fireTruck:PivotTo(endPivot)
task.wait(MARKER_DELAY)
fireMarker.Transparency = 1

local remainingTime = TOTAL_DURATION - (os.clock() - sequenceStartedAt)
if remainingTime > 0 then
	task.wait(remainingTime)
end
