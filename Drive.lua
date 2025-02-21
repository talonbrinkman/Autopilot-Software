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
	showRays = false,
	obstacleDetected = false,
	blinker = nil,
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

local function blink()
	while carState.blinker == "left" do
		car["FL Turn Signal"].Transparency = 0
		car["BL Turn Signal"].Transparency = 0
		SoundManager.playSound(6107429348, 1, nil, car.DriverSeat.Sound)
		wait(1)
		car["FL Turn Signal"].Transparency = 1
		car["BL Turn Signal"].Transparency = 1
		SoundManager.playSound(6107429348, 1, nil, car.DriverSeat.Sound)
		wait(1)
	end
	while carState.blinker == "right" do
		car["FR Turn Signal"].Transparency = 0
		car["BR Turn Signal"].Transparency = 0
		SoundManager.playSound(6107429348, 1, nil, car.DriverSeat.Sound)
		wait(1)
		car["FR Turn Signal"].Transparency = 1
		car["BR Turn Signal"].Transparency = 1
		SoundManager.playSound(6107429348, 1, nil, car.DriverSeat.Sound)
		wait(1)
	end
end

local function changeBlinker(blinker)
	if carState.blinker == blinker then
		carState.blinker = nil
	else
		carState.blinker = blinker
	end

	if carState.blinker == "left" or carState.blinker == "right" then
		spawn(function()
			blink()
		end)
	end
end

local function detectObstacle()
	local rays = {}
	local origin = car.Detector.Position
	local distance = 30
	local width = 10
	local numRays = 100

	for _, child in ipairs(car:GetChildren()) do
		if child.Name == "RayVisualizer" then
			child:Destroy()
		end
	end

	local halfWidth = width / 2
	local spacing = width / (numRays - 1)

	for i = 0, numRays - 1 do
		local lateralOffset = -halfWidth + (i * spacing)
		local offsetPosition = car.Detector.CFrame.Position + (car.Detector.CFrame.RightVector * lateralOffset) + (car.Detector.CFrame.UpVector * 0)
		local direction = car.Detector.CFrame.LookVector * distance

		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {car, workspace.Roads}
		raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
		local result = workspace:Raycast(offsetPosition, direction, raycastParams)

		if carState.showRays then
			local hitPosition = result and result.Position or (offsetPosition + direction)
			local color = result and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(21, 140, 232)
			drawRay(offsetPosition, hitPosition, color, car)
		end

		if result then
			local hitInstance = result.Instance
			local hitDistance = (result.Position - offsetPosition).Magnitude
			table.insert(rays, {instance = hitInstance, distance = hitDistance, offset = i})
			if hitInstance.Parent.Name == "Car" and hitInstance.Parent:FindFirstChild("DriverSeat") and hitInstance.Parent.DriverSeat.Throttle == 0 and not hitInstance.Parent.DriverSeat.Occupant then
				print("Car not moving and has no one in it")
			end
		end
	end

	if #rays > 0 then
		local offsetSum = 0
		local distanceSum = 0
		for _, ray in ipairs(rays) do
			offsetSum = offsetSum + ray.offset
			distanceSum = distanceSum + ray.distance
		end
		local averageOffset = math.round(offsetSum / #rays)
		local averageDistance = math.round(distanceSum / #rays)
		return averageOffset, averageDistance
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

function turnVehicle(direction)
	wait(1)
	if direction == "left" then
		if not carState.blinker then
			changeBlinker("left")
		end
		accelerateVehicle(0.5)
		wait(0.5)
		steerVehicle(-0.5)
		wait(2.5)
		changeBlinker(nil)
	elseif direction == "right" then
		if not carState.blinker then
			changeBlinker("right")
		end
		accelerateVehicle(0.25)
		steerVehicle(-0.5)
		wait(1)
		steerVehicle(1)
		wait(3.5)
		changeBlinker(nil)
	elseif direction == "straight" then
		accelerateVehicle(0.5)
		wait(2)
		changeBlinker(nil)
	end
end

local function updateMotors()
	if carState.autopilotEnabled then
		local averageObjectOffset, averageObjectDistance = detectObstacle()
		local objectAccelerationAdjustment = 1
		local objectSteerAdjustment = 0
		
		if averageObjectOffset and averageObjectDistance then
			if averageObjectOffset < 35 then
				objectSteerAdjustment = 0.5
				objectAccelerationAdjustment = 0.5
			elseif averageObjectOffset > 65 then
				objectSteerAdjustment = -0.5
				objectAccelerationAdjustment = 0.5
			else
				accelerateVehicle(0)
				return
			end
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

		local stopSignRayOrigin = car.Detector.CFrame * Vector3.new(0, 0, -15)
		local stopSignRayDirection = Vector3.new(0, -50, 0)
		local stopSignRay = workspace:Raycast(stopSignRayOrigin, stopSignRayDirection, raycastParams)
		if carState.showRays then
			drawRay(stopSignRayOrigin, stopSignRay and stopSignRay.Position or (stopSignRayOrigin + stopSignRayDirection), Color3.fromRGB(255, 0, 0), car)
		end
		
		local straightDetectionRayOrigin = car.Detector.CFrame * Vector3.new(0, 0, -75)
		local straightDetectionRayDirection = Vector3.new(0, -50, 0)
		local straightDetectionRay = workspace:Raycast(straightDetectionRayOrigin, straightDetectionRayDirection, raycastParams)
		if carState.showRays then
			drawRay(straightDetectionRayOrigin, straightDetectionRay and straightDetectionRay.Position or (straightDetectionRayOrigin + straightDetectionRayDirection), Color3.fromRGB(0, 255, 0), car)
		end
		local leftDetectionRayOrigin = car.Detector.CFrame * Vector3.new(-37.5, 0, -37.5)
		local leftDetectionRayDirection = Vector3.new(0, -50, 0)
		local leftDetectionRay = workspace:Raycast(leftDetectionRayOrigin, leftDetectionRayDirection, raycastParams)
		if carState.showRays then
			drawRay(leftDetectionRayOrigin, leftDetectionRay and leftDetectionRay.Position or (leftDetectionRayOrigin + leftDetectionRayDirection), Color3.fromRGB(255, 0, 0), car)
		end
		local rightDetectionRayOrigin = car.Detector.CFrame * Vector3.new(37.5, 0, -37.5)
		local rightDetectionRayDirection = Vector3.new(0, -50, 0)
		local rightDetectionRay = workspace:Raycast(rightDetectionRayOrigin, rightDetectionRayDirection, raycastParams)
		if carState.showRays then
			drawRay(rightDetectionRayOrigin, rightDetectionRay and rightDetectionRay.Position or (rightDetectionRayOrigin + rightDetectionRayDirection), Color3.fromRGB(0, 0, 255), car)
		end

		if downRay then
			if stopSignRay and stopSignRay.Instance.Parent.Name == "Intersection Road" then
				local straightAvailable = straightDetectionRay and straightDetectionRay.Instance.Parent.Name == "Straight Road"
				local leftAvailable = leftDetectionRay and leftDetectionRay.Instance.Parent.Name == "Straight Road"
				local rightAvailable = rightDetectionRay and rightDetectionRay.Instance.Parent.Name == "Straight Road"
				accelerateVehicle(0)
				steerVehicle(0)
				if straightAvailable and not leftAvailable and not rightAvailable then
					turnVehicle("straight")
				elseif not straightAvailable and leftAvailable and not rightAvailable then
					turnVehicle("left")
				elseif not straightAvailable and not leftAvailable and rightAvailable then
					turnVehicle("right")
				elseif straightAvailable and leftAvailable and not rightAvailable then
					if car.DriverSeat.Occupant then
						if carState.blinker == "left" then
							turnVehicle("left")
						else
							turnVehicle("straight")
						end
					else
						local direction = math.random(1, 2)
						if direction == 1 then
							turnVehicle("left")
						elseif direction == 2 then
							turnVehicle("straight")
						end
					end
				elseif straightAvailable and not leftAvailable and rightAvailable then
					if car.DriverSeat.Occupant then
						if carState.blinker == "right" then
							turnVehicle("right")
						else
							turnVehicle("straight")
						end
					else
						local direction = math.random(1, 2)
						if direction == 1 then
							turnVehicle("right")
						elseif direction == 2 then
							turnVehicle("straight")
						end
					end
				elseif not straightAvailable and leftAvailable and rightAvailable then
					if car.DriverSeat.Occupant then
						if carState.blinker == "left" then
							turnVehicle("left")
						elseif carState.blinker == "right" then
							turnVehicle("right")
						end
					else
						local direction = math.random(1, 2)
						if direction == 1 then
							turnVehicle("left")
						elseif direction == 2 then
							turnVehicle("right")
						end
					end
				elseif straightAvailable and leftAvailable and rightAvailable then
					if car.DriverSeat.Occupant then
						if carState.blinker == "left" then
							turnVehicle("left")
						elseif carState.blinker == "right" then
							turnVehicle("right")
						else
							turnVehicle("straight")
						end
					else
						local direction = math.random(1, 3)
						if direction == 1 then
							turnVehicle("left")
						elseif direction == 2 then
							turnVehicle("right")
						elseif direction == 3 then
							turnVehicle("straight")
						end
					end
				end
			else
				local leftRayOrigin = Vector3.new(car.Detector.Position.X, downRay.Position.Y + 0.25, car.Detector.Position.Z)
				local leftRayDirection = -car.Detector.CFrame.RightVector * roadWidth
				local leftRay = workspace:Raycast(leftRayOrigin, leftRayDirection, raycastParams)
				if carState.showRays then
					drawRay(leftRayOrigin, leftRay and leftRay.Position or (leftRayOrigin + leftRayDirection), Color3.fromRGB(21, 140, 232), car)
				end

				local rightRayOrigin = Vector3.new(car.Detector.Position.X, downRay.Position.Y + 0.25, car.Detector.Position.Z)
				local rightRayDirection = car.Detector.CFrame.RightVector * roadWidth
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
			if key == "F" then
				carState.autopilotEnabled = not carState.autopilotEnabled
				if carState.autopilotEnabled then
					SoundManager.playSound(4611349448, 1, nil, car.DriverSeat.Sound)
					changeLEDStrips(Color3.fromRGB(21, 140, 232))
				else
					SoundManager.playSound(4611348524, 1, nil, car.DriverSeat.Sound)
					changeLEDStrips(Color3.fromRGB(255, 0, 0))
				end
				for _, child in ipairs(car:GetChildren()) do
					if child.Name == "RayVisualizer" then
						child:Destroy()
					end
				end
				updateMotors()
			elseif key == "R" then
				carState.showRays = not carState.showRays
				for _, child in ipairs(car:GetChildren()) do
					if child.Name == "RayVisualizer" then
						child:Destroy()
					end
				end
			elseif key == "Q" then
				changeBlinker("left")
			elseif key == "E" then
				changeBlinker("right")
			end
		end
	end
end)

weldMeshesToChassis(car.Meshes)
changeLEDStrips(Color3.fromRGB(255, 0, 0))
if carState.autopilotEnabled then
	SoundManager.playSound(4611349448, 1, nil, car.DriverSeat.Sound)
	changeLEDStrips(Color3.fromRGB(21, 140, 232))
end
while true do
	if carState.autopilotEnabled then
		updateMotors()
	end
	wait(0.01)
end
