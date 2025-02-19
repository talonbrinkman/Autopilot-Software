local SoundManager = require(game:GetService("ReplicatedStorage")["Sound Manager"])
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local event = ReplicatedStorage:FindFirstChild("VehicleKeyPress")

local car = script.Parent.Parent
local driveSeat = script.Parent

local frontLeftMotor = car["Chassis"]["Front Left Motor"]
local frontRightMotor = car["Chassis"]["Front Right Motor"]
local backLeftMotor = car["Chassis"]["Back Left Motor"]
local backRightMotor = car["Chassis"]["Back Right Motor"]
local frontLeftServo = car["Chassis"]["Front Left Servo"]
local frontRightServo = car["Chassis"]["Front Right Servo"]
local backLeftServo = car["Chassis"]["Back Left Servo"]
local backRightServo = car["Chassis"]["Back Right Servo"]
local steeringWheelServo = car.Meshes.Interior["Steering Wheel"]["Steering Wheel"]["Steering Wheel Servo"]

local maxSpeed = 30
local maxSteer = 30
local rearWheelSteeringEnabled = true
local carState = {
	autopilotEnabled = false,
	obstacleDetected = false,
	showRays = false,
}

local Kp = 0.5  -- Proportional gain
local Ki = 0.01 -- Integral gain
local Kd = 0.2  -- Derivative gain
local previousError = 0
local integral = 0

local function weldMeshesToChassis(model)
	for _, part in pairs(model:GetChildren()) do
		if part:IsA("MeshPart") then
			local weld = Instance.new("WeldConstraint")
			weld.Parent = part
			weld.Part0 = part
			weld.Part1 = car.Chassis
			part.Anchored = false
		end
		if part:IsA("Model") and part.Name ~= "Steering Wheel" then
			weldMeshesToChassis(part)
		end
	end
end

local function drawRay(origin: Vector3, hitPosition: Vector3, color: Color3, parent: Instance)
	local rayPart = Instance.new("Part")
	rayPart.Size = Vector3.new(0.05, 0.05, (hitPosition - origin).Magnitude)
	rayPart.Anchored = true
	rayPart.CanCollide = false
	rayPart.Color = color
	rayPart.CFrame = CFrame.new(origin, hitPosition) * CFrame.new(0, 0, -rayPart.Size.Z / 2)
	rayPart.Name = "RayVisualizer"
	rayPart.Parent = parent
end

local function changeLEDStrips(color)
	for _, mesh in pairs(car.Meshes:GetChildren()) do
		if mesh.Name == "LED Strip" then
			mesh.Color = color
		end
	end
end

local function changeBrakeLights(braking)
	if braking then
		for _, mesh in pairs(car.Meshes:GetChildren()) do
			if mesh.Name == "Brake Light" then
				mesh.Material = Enum.Material.Neon
				mesh.SurfaceLight.Enabled = true
			end
		end
	else
		for _, mesh in pairs(car.Meshes:GetChildren()) do
			if mesh.Name == "Brake Light" then
				mesh.Material = Enum.Material.SmoothPlastic
				mesh.SurfaceLight.Enabled = false
			end
		end
	end
end

local function detectObstacle()
	local rays = {}
	local origin = car.Detector.Position
	local distance = 50
	local angleIncrement = 0.5
	local angleRange = 30

	for _, child in ipairs(car:GetChildren()) do
		if child.Name == "RayVisualizer" then
			child:Destroy()
		end
	end

	for i = -angleRange / 2, angleRange / 2, angleIncrement do
		local direction = (car.Detector.CFrame * CFrame.Angles(0, math.rad(i), 0)).RightVector * distance

		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {car, workspace.Roads}
		raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
		local result = workspace:Raycast(origin, direction, raycastParams)

		local hitPosition = result and result.Position or (origin + direction)
		
		if carState.showRays then
			local color = result and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(21, 140, 232)
			drawRay(origin, result and result.Position or (origin + direction), color, car)
		end
		
		if result then
			local hitInstance = result.Instance
			local hitDistance = (result.Position - origin).Magnitude
			table.insert(rays, {instance = hitInstance, distance = hitDistance, angle = i})
		end
	end

	if #rays > 0 then
		local sum = 0
		for _, ray in ipairs(rays) do
			sum = sum + ray.angle
		end
		local averageHitAngle = sum / #rays
		return -averageHitAngle
	end

	return nil
end

function accelerateVehicle(throttle)
	if throttle == 0 then
		changeBrakeLights(true)
	else
		changeBrakeLights(false)
	end
	frontLeftMotor.AngularVelocity = -maxSpeed * throttle
	frontRightMotor.AngularVelocity = maxSpeed * throttle
	backLeftMotor.AngularVelocity = -maxSpeed * throttle
	backRightMotor.AngularVelocity = maxSpeed * throttle
end

function steerVehicle(angle)
	steeringWheelServo.TargetAngle = maxSteer * angle * 1.5
	frontLeftServo.TargetAngle = -maxSteer * angle
	frontRightServo.TargetAngle = -maxSteer * angle
	if rearWheelSteeringEnabled then
		backLeftServo.TargetAngle = (maxSteer * angle)/3
		backRightServo.TargetAngle = (maxSteer * angle)/3
	end
end

local function updateMotors()
	if carState.autopilotEnabled then
		local averageHitAngle = detectObstacle()
		local objectAccelerationAdjustment = 1
		local objectSteerAdjustment = 0

		if averageHitAngle and averageHitAngle < -5 then
			objectSteerAdjustment = 0.5
			objectAccelerationAdjustment = 1
		elseif averageHitAngle and averageHitAngle > 5 then
			objectSteerAdjustment = -0.5
			objectAccelerationAdjustment = 1
		elseif averageHitAngle and averageHitAngle >= -5 and averageHitAngle <= 5 then
			accelerateVehicle(0)
			return
		end

		local roadWidth = 36
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {car, workspace.Obstacles}
		raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

		local downRayOrigin = car.Detector.Position
		local downRayDirection = Vector3.new(0, -50, 0)
		local downRay = workspace:Raycast(downRayOrigin, downRayDirection, raycastParams)
		if carState.showRays then
			drawRay(downRayOrigin, downRay and downRay.Position or (downRayOrigin + downRayDirection), Color3.fromRGB(21, 140, 232), car)
		end

		local stopSignRayOrigin = car.Detector.CFrame * Vector3.new(15, 0, 0)
		local stopSignRayDirection = Vector3.new(0, -50, 0)
		local stopSignRay = workspace:Raycast(stopSignRayOrigin, stopSignRayDirection, raycastParams)
		if carState.showRays then
			drawRay(stopSignRayOrigin, stopSignRay and stopSignRay.Position or (stopSignRayOrigin + stopSignRayDirection), Color3.fromRGB(21, 140, 232), car)
		end
		
		local straightDetectionRayOrigin = car.Detector.CFrame * Vector3.new(75, 0, 0)
		local straightDetectionRayDirection = Vector3.new(0, -50, 0)
		local straightDetectionRay = workspace:Raycast(straightDetectionRayOrigin, straightDetectionRayDirection, raycastParams)
		if carState.showRays then
			drawRay(straightDetectionRayOrigin, straightDetectionRay and straightDetectionRay.Position or (straightDetectionRayOrigin + straightDetectionRayDirection), Color3.fromRGB(21, 140, 232), car)
		end
		local leftDetectionRayOrigin = car.Detector.CFrame * Vector3.new(37.5, 0, -37.5)
		local leftDetectionRayDirection = Vector3.new(0, -50, 0)
		local leftDetectionRay = workspace:Raycast(leftDetectionRayOrigin, leftDetectionRayDirection, raycastParams)
		if carState.showRays then
			drawRay(leftDetectionRayOrigin, leftDetectionRay and leftDetectionRay.Position or (leftDetectionRayOrigin + leftDetectionRayDirection), Color3.fromRGB(21, 140, 232), car)
		end
		local rightDetectionRayOrigin = car.Detector.CFrame * Vector3.new(37.5, 0, 37.5)
		local rightDetectionRayDirection = Vector3.new(0, -50, 0)
		local rightDetectionRay = workspace:Raycast(rightDetectionRayOrigin, rightDetectionRayDirection, raycastParams)
		if carState.showRays then
			drawRay(rightDetectionRayOrigin, rightDetectionRay and rightDetectionRay.Position or (rightDetectionRayOrigin + rightDetectionRayDirection), Color3.fromRGB(255, 0, 0), car)
		end

		if downRay then
			if stopSignRay and stopSignRay.Instance.Parent.Name == "Intersection Road" then
				if straightDetectionRay and straightDetectionRay.Instance.Parent.Name == "Straight Road" then
					print("Straight Detected")
				end
				if leftDetectionRay and leftDetectionRay.Instance.Parent.Name == "Straight Road" then
					print("Left Detected")
				end
				if rightDetectionRay and rightDetectionRay.Instance.Parent.Name == "Straight Road" then
					print("Right Detected")
				end
				accelerateVehicle(0)
				steerVehicle(0)
				wait(1)
				accelerateVehicle(0.5)
				wait(0.5)
				steerVehicle(-0.5)
				wait(2.5)
			else
				local leftRayOrigin = Vector3.new(car.Detector.Position.X, downRay.Position.Y + 0.25, car.Detector.Position.Z)
				local leftRayDirection = car.Detector.CFrame.LookVector * roadWidth
				local leftRay = workspace:Raycast(leftRayOrigin, leftRayDirection, raycastParams)
				if carState.showRays then
					drawRay(leftRayOrigin, leftRay and leftRay.Position or (leftRayOrigin + leftRayDirection), Color3.fromRGB(21, 140, 232), car)
				end

				local rightRayOrigin = Vector3.new(car.Detector.Position.X, downRay.Position.Y + 0.25, car.Detector.Position.Z)
				local rightRayDirection = -car.Detector.CFrame.LookVector * roadWidth
				local rightRay = workspace:Raycast(rightRayOrigin, rightRayDirection, raycastParams)
				if carState.showRays then
					drawRay(rightRayOrigin, rightRay and rightRay.Position or (rightRayOrigin + rightRayDirection), Color3.fromRGB(255, 0, 0), car)
				end

				if leftRay and rightRay then
					local leftRayDistance = (leftRay.Position - car.Detector.Position).Magnitude
					local rightRayDistance = (rightRay.Position - car.Detector.Position).Magnitude
					local error = (leftRayDistance - (0.8 * roadWidth)) / roadWidth
					integral = integral + error * 0.01
					local derivative = (error - previousError) / 0.01
					local steeringAdjustment = -(Kp * error + Ki * integral + Kd * derivative)
					steeringAdjustment = math.clamp(steeringAdjustment, -1, 1)

					accelerateVehicle(0.5 * objectAccelerationAdjustment)
					steerVehicle(steeringAdjustment + objectSteerAdjustment)

					previousError = error
				else
					accelerateVehicle(0)
					steerVehicle(0)
				end
			end
		end
	else
		accelerateVehicle(driveSeat.Throttle)
		steerVehicle(driveSeat.SteerFloat)
	end
end

driveSeat.Changed:Connect(function(property)
	if property == "ThrottleFloat" or property == "SteerFloat" then
		if not carState.autopilotEnabled then
			updateMotors()
		end
	end

	if property == "Occupant" and not driveSeat.Occupant then
		carState.autopilotEnabled = false
		updateMotors()
	end
end)

event.OnServerEvent:Connect(function(player, vehicle, key)
	if vehicle ~= car then
		return
	end
	if vehicle and vehicle:IsA("Model") then
		local seat = vehicle:FindFirstChildOfClass("VehicleSeat")
		if seat and seat.Occupant and seat.Occupant.Parent == player.Character then
			if key == "E" then
				carState.autopilotEnabled = not carState.autopilotEnabled
				if carState.autopilotEnabled then
					SoundManager.playSound(4611349448, nil, player)
					changeLEDStrips(Color3.fromRGB(21, 140, 232))
				else
					SoundManager.playSound(4611348524, nil, player)
					changeLEDStrips(Color3.fromRGB(255, 0, 0))
				end
				updateMotors()
			elseif key == "Q" then
				carState.showRays = not carState.showRays
				for _, child in ipairs(car:GetChildren()) do
					if child.Name == "RayVisualizer" then
						child:Destroy()
					end
				end
			end
		end
	end
end)

weldMeshesToChassis(car.Meshes)
changeLEDStrips(Color3.new(1, 0, 0.0156863))
while true do
	if carState.autopilotEnabled then
		updateMotors()
	end
	wait(0.01)
end
