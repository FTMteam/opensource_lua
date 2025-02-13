local module = {}
local activeAim = {} -- A table of active aiming beams
local runService = game:GetService("RunService")
local ClientToServer = game.ReplicatedStorage.Events.ClientToServer -- Communicates values with the server
-- THIS SCRIPT CREATES AN AIMING BEAM EFFECT TO SHOW WHERE THE PROJECTILE WILL GO, THIS SCRIPT ALSO FIRES THE PROJECTILE ON THE CLIENT AND SIMULATES THE PROJECTILE ON THE SERVER
-- I have not fired the projectile on the server because this will reduce latency from the player's perspective and reduce network latency
-- CREDITS TO FTMteam
function GetMouseDirectionFromPoint(point,range)
	local camera = workspace.CurrentCamera 
	local mouse = game.Players.LocalPlayer:GetMouse()
	mouse.TargetFilter = workspace.Effects
	local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y) -- Creates a ray based on the mouse position in 3d to obtain mouse's position and direction in 3d
	local direction = ((mouseRay.Origin + mouseRay.Direction*range)-point).Unit --Obtains the direction of the mouse's 3d origin to the starting point, this is done by minusing the 3d origin of mouse by the starting point to give a direction of the 3d origin from the starting point
	return direction -- Returns the direction
end
function GetEnemyByPart(part,pvp_value)
	local pvp = pvp_value or game.Workspace.Live.PVP.Value --Checks if a pvp_value has been specified in the parameters, if not it will take the pvp value in workspace's settings
	local targets = {} -- Creates an empty table to store any targets that needs to be returned
	if part then -- Ensure the part parameter exists, so it doesn't error
		local plrs = {}
		if pvp then -- If player versus player is enabled, it will take players into consideration
			for i,v in pairs(game.Players:GetChildren()) do
				table.insert(plrs,v.Character)
			end
		end
		for i,v1 in ipairs(plrs) do
			if part:IsDescendantOf(v1) and table.find(targets,v1)  == nil then -- Logic to check if the part is a descendant of the players, if it is, it will add the player to the targets
				table.insert(targets,v1)
			end
		end
		if part:IsDescendantOf(workspace.Enemies) then
			for _,v2 in ipairs(workspace.Enemies:GetChildren()) do
				if v2:IsAncestorOf(part) and table.find(targets,v2) == nil then -- Logic to check if the part is a descendant of the players, if it is, it will add the enemy to the targets
					table.insert(targets,v2)
				end
			end
		end
	end

	return targets
end
function module:New(object:'Model/Part of the projectile' ,range:number,speed:number,startattachment:Attachment) --Inlitializes the projectile for sub function calls
	if object and range and speed and startattachment then -- Ensures the parameters exist
		self = module -- Allow the functions to be called from the function's return
		self.Projectile = object --Creates a self object to be used in future functions
		self.Range = range -- Custom settings for the object
		self.Speed = speed
		self.StartAttachment = startattachment
		self.EndPosition = Vector3.new(0,0,0) -- Defines endposition that will be changed in the future
		self.Filter = {workspace.Effects,game.Players.LocalPlayer.Character} 
		return self -- Returns the self object to the client
	else
		return assert("Parameters missing in Project:New()") -- If no parameters it will error
	end
	
end

function module.SimulateProjectile (projectile,startPosition, startVelocity,duration,params) -- For server to fact check the projectile incase of any exploiters
	local position = startPosition -- Sets position to the initial position
	local velocity = startVelocity -- Sets velocity to the initial velocity
	local lifeTime = 0 -- Sets the current lifetime of the projectile to be 0
	local MAX_LIFETIME = duration + 4
	local GRAVITY = Vector3.new(0,-game.Workspace.Gravity,0) -- Changes the gravity to be in a vector3 as it will be used in physics calculations in the future
	local HIT_DETECT_RAYCAST_PARAMS = RaycastParams.new()
	HIT_DETECT_RAYCAST_PARAMS.FilterDescendantsInstances = params
	while lifeTime < MAX_LIFETIME do -- Loops through the projectile's lifetime
		local dt = runService.Heartbeat:Wait() -- Gets the deltatime passed of the heartbeat, i used heartbeat because it calls before physics simulation starts
		local oldPosition = position -- Gets the old position of the previous deltatime
		local newPosition = oldPosition + (velocity * dt) + (-GRAVITY * dt * dt) -- Uses the kinematic equation to obtain the position of the projectile in it's current time
		velocity = velocity + GRAVITY * dt -- Updates the velocity based on the gravity it's going down in
		position = newPosition  -- Updates the position to the new position
		lifeTime += dt -- Updates the lifetime of the projectile to the time it has been passed, indicated through delta time
		local hitResult = game.Workspace:Blockcast(CFrame.new(oldPosition),projectile.Size, newPosition - oldPosition, HIT_DETECT_RAYCAST_PARAMS) -- Block casts  to check the hit is legit by raycasting of the currentposition of the projectile, it's size and the direction it is facing
		if hitResult then -- If something is going to hit in the object
			local enemies = GetEnemyByPart(hitResult.Instance) -- Check whether the part belongs to an enemy
			if #enemies > 0 then -- If it belong to an enemy it will loop through all the enemies it is colliding with and deal damage to it
				for i,v in ipairs(enemies) do
					v.Humanoid:TakeDamage(20) -- If so then we damage it
				end
			end
			return hitResult -- Returns the part for the server to manipulate
		end
	end
	return false -- If no hit throughout the whole lifetime, it will return false
end
-- The simulateprojectile function is useful because it allows us to simulate the projectile without actually creating a new projectile in the server, this helps reduce latency by preventing the client from waiting for the response of the server when firing
-- It also ensures that no exploiters can fake the position of the projectile and make it seem like the projectile never hit the enemies
function module:FireProjectile() -- Fires the projectile in client
	local startposition = self.StartAttachment.WorldPosition -- Sets up variables
	local endposition = self.EndPosition
	local object = self.Projectile
	local param= self.Filter
	local hit_effect = game.ReplicatedStorage.Effects.Explosion -- Obtains the hit effect
	local speed = self.Speed
	local direction = endposition - startposition -- Obtains the direction of the projectile being fired from the aiming process
	local blackhole = object:Clone() -- Clone the projectiles and place it to workspace.Effects
	blackhole.Parent = workspace.Effects
	blackhole.Position = startposition
	blackhole.Anchored = false
	local gravity = game.Workspace.Gravity -- Gets the gravity of the game to calculate the force needed for the projectile to reach it's endposition
	local duration = direction.Magnitude/speed -- Obtains the duration of the projectile by dividing the magnitude of the direction ( also the distance) by the speed the projectile travels in which is the distance travelled in studs per second
	local runService = game:GetService("RunService")
	local force = direction/duration + Vector3.new(0, gravity * duration * 0.5, 0) -- Calculate the velocity/force of the projectile by obtaining the constant velocity ( direction divide by the duration) and then putting the gravity into consideration, this uses the kinematic equation of motion being initial velocity = displacement/time + 1/2at^2 
	local mlt = duration + 4 -- Max life time
	game.Debris:AddItem(blackhole,mlt) -- Makes the projectile to be destroyed after max life time reached
	local lt = 0 -- Current lifetime
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = param -- Does raycast
	blackhole:ApplyImpulse(force * blackhole.AssemblyMass) -- Applies impulse with velocity and mass of object
	local position = startposition
	local velocity = force
	local GRAVITY = Vector3.new(0,-workspace.Gravity,0) -- Puts gravity in vector 3 for future calculations
	while lt <mlt do -- Loops through the projectile's lifetime
		local dt = runService.RenderStepped:Wait() -- Obtains the delta time of the renderstepped
		lt += dt --Adds it to the total time passed
		local oldPosition = position
		local newPosition = oldPosition + (velocity * dt) + (-GRAVITY * dt^2) -- Ues kinematic equation to obtain the new position of the projectile based on it's gravity and initial velocity
		velocity = velocity + GRAVITY * dt -- Updates velocity to the current time passed with gravity
		position = newPosition-- Updates the currentposition variable to the newposition
		local hitresults = workspace:Blockcast(CFrame.new(oldPosition),object.Size,newPosition-oldPosition,params) --Blockcasts to check if  the projectile hits anything
		if hitresults then -- If it hits something
			local hit:BasePart = hit_effect:Clone() -- If there is a hit, make a hit effect
			hit.Parent = workspace.Effects
			hit.Position = hitresults.Position
			hit.Anchored = true
			hit.CanCollide = false
			for i,v in ipairs(hit:GetDescendants()) do
				if v:IsA("ParticleEmitter") then
					v:Emit(v:GetAttribute("EmitCount")) -- Emit the explosion effect
				end
			end
			break -- Breaks the loop from continuing as the projectile would have stopped
		end
	end
end
function module:Project() -- Sets up the aiming process of the projectile for the player to aim on where the projectile should reach
	local projectile = self.Projectile -- Sets up variables
	local range = self.Range
	local speed = self.Speed
	local startattachment = self.StartAttachment
	local player = game.Players.LocalPlayer
	local att1 = startattachment
	local filter = self.Filter
	att1.Orientation = Vector3.new(0,0,90)
	local att2 = Instance.new("Attachment",player.Character.HumanoidRootPart) -- Creates attachment for the beam to show the trajectory
	local att3 = Instance.new("Attachment",player.Character.HumanoidRootPart) -- Creates an attachment for the other end of the beam
	local beam = Instance.new("Beam",workspace.Effects) -- Creates the beam to show the trajectory
	beam.Width0 = 0.1 -- Configs the beam
	beam.Width1 = 0.1
	beam.Segments = 100
	beam.FaceCamera =true
	beam.Color = ColorSequence.new(Color3.new(1, 0.968627, 0.941176),Color3.new(1, 0.898039, 0.494118)) -- Makes the beam yellow ish
	beam.Brightness = 10
	local beam2 = beam:Clone()
	beam2.Parent = workspace.Effects
	beam.Segments = 100 -- Sets it to a high segment to create a smooth  curve
	beam2.Segments = 100
	if activeAim[player.Character] then 
		activeAim[player.Character][1]:Disconnect()-- Cancels out any previous trajectory lines
		for i,v in ipairs(activeAim[player.Character][2]) do
			v:Destroy()
		end
		activeAim[player.Character] = nil
	end
	activeAim[player.Character]= {} -- Creates a blank table to store the trajectory attachment and beam
	activeAim[player.Character][1]	= game:GetService("RunService").RenderStepped:Connect(function()
		local direction = GetMouseDirectionFromPoint(player.Character.HumanoidRootPart.Position,range) -- Obtains the direction of the mouse's 3d position to the player's hum position
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = filter -- Filter the raycast to the parameters
		local ray = workspace:Blockcast(CFrame.new(startattachment.WorldPosition),projectile.Size,direction * range,params) -- Block casts the projectile out with consideration of it's size, origin and direction to see whether the beamline will hit anything
		if ray then -- If the beam will hit anything, it will set the endbeam position to the hit position instead of it going through the object
			local direction = (ray.Position - att1.WorldPosition) -- Calculates the direction of ray hit position and start
			local duration = direction.Magnitude/speed -- Calculate the duration of the projectile based on it's speed
			local maxHeight =  (0.125 * workspace.Gravity * duration^2) -- Calculates the max height of the parabolic trajectory, using h = 1/8 gt^2
			att2.WorldPosition = att1.WorldPosition + ((ray.Position - att1.WorldPosition)/2) + Vector3.new(0,maxHeight,0) -- Gets the middle position to set up the curve
			att3.WorldPosition = ray.Position
			att3.Orientation = Vector3.new(0,0,90) -- Sets the orientation so the curve is position towards the sky to project a more realistic travel path of the projectile
		else
			local endPosition = CFrame.new(startattachment.WorldPosition + (direction * range)).Position -- Does the same thing as above but instead it takes the max reachable range/height instead of the hit position
			local direction = (endPosition - att1.WorldPosition)

			local duration = direction.Magnitude/speed
			local maxHeight =  (0.125 * workspace.Gravity * duration^2)
			att2.WorldPosition = att1.WorldPosition + ((endPosition - att1.WorldPosition)/2) + Vector3.new(0,maxHeight,0)
			att3.WorldPosition = endPosition
			att3.Orientation = Vector3.new(0,0,90)
		end
		beam.Attachment0 = att1
		beam.Attachment1 = att3
		beam.CurveSize0 = att2.Position.Y/2 -- Sets up the curve to the highest point of the projectile over 2 as there are 2 curves
		beam.CurveSize1 = -beam.CurveSize0 -- Inverse of the curvesize0 to make it smooth
		if workspace.Cache:FindFirstChild("Direction") then
			ClientToServer:InvokeServer("Value",workspace.Cache.Direction,att3.WorldPosition) -- Returns the end position to the server
		end
	end)
	activeAim[player.Character][2] = {att2,att3,beam,beam2} -- Logs the active beam it has been created
end
function module:CancelProject(player:Player) -- Can be cancelled via client or server
	if runService:IsClient() then -- If the method is called from the client, it will only remove the beam of the client ensuring no exploiters can remove other people's
		player = game.Players.LocalPlayer
	end
	if activeAim[player.Character] then
		activeAim[player.Character][1]:Disconnect() -- Cancels projectile projection
		for i,v in ipairs(activeAim[player.Character][2]) do
			v:Destroy() -- Destroys the beams and the attachments
		end
		activeAim[player.Character] = nil -- Sets the active beam of the player to be nil
	end
end
return module




-- EXAMPLE USAGE ON CLIENT 
--[[
	local uis = game:GetService("UserInputService")
	local projectilesystem = require(game.ReplicatedStorage.ProjectilePVP)
	local object 
	uis.InputBegan:Connect(function(input,proc)
		local char = game.Players.LocalPlayer.Character
		if not proc and input.UserInputType == Enum.UserInputType.MouseButton1 then
			object = projectilesystem:New(game.ReplicatedStorage.Projectiles.BlackholeProjectile,50,200,char.HumanoidRootPart.RootAttachment)
			object:Project()
		end

	end)
	uis.InputEnded:Connect(function(input,proc)
		if not proc and input.UserInputType == Enum.UserInputType.MouseButton1 then
			if object then
				object:CancelProject(game.Players.LocalPlayer)
				object.EndPosition = workspace.Cache.Direction.Value
				object:FireProjectile()
			end
		end
	end)
]]
