local module = {}
local activeAim = {}
local runService = game:GetService("RunService")
local ClientToServer = game.ReplicatedStorage.Events.ClientToServer -- Communicates values with the server
function GetMouseDirectionFromPoint(point,range)
	local camera = workspace.CurrentCamera 
	local mouse = game.Players.LocalPlayer:GetMouse() -- Gets the mouse
	mouse.TargetFilter = workspace.Effects
	local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y) -- Generate a ray based on 2d mouse positions
	local direction = ((mouseRay.Origin + mouseRay.Direction*range)-point).Unit -- Calculates the direction
	return direction
end
function GetEnemyByPart(part,pvp_value)
	local pvp = pvp_value or game.Workspace.Live.PVP.Value -- Will return players if pvp value is on
	local targets = {}
	if part then
		local plrs = {}
		if pvp then
			for i,v in pairs(game.Players:GetChildren()) do
				table.insert(plrs,v.Character)
			end
		end
		for i,v1 in ipairs(plrs) do
			if part:IsDescendantOf(v1) and table.find(targets,v1)  == nil then
				table.insert(targets,v1)
			end
		end
		if part:IsDescendantOf(workspace.Enemies) then
			for _,v2 in ipairs(workspace.Enemies:GetChildren()) do
				if v2:IsAncestorOf(part) and table.find(targets,v2) == nil then
					table.insert(targets,v2)
				end
			end
		end
	end

	return targets
end
function module:New(object:'Model/Part of the projectile' ,range:number,speed:number,startattachment:Attachment) --Inlitializes the projectile for sub function calls
	if object and range and speed and startattachment then
		self = module
		self.Projectile = object
		self.Range = range
		self.Speed = speed
		self.StartAttachment = startattachment
		self.EndPosition = Vector3.new(0,0,0)
		self.Filter = {workspace.Effects,game.Players.LocalPlayer.Character}
		return self
	else
		return assert("Parameters missing in Project:New()")
	end
	
end

function module.SimulateProjectile (projectile,startPosition, startVelocity,duration,params) -- For server to fact check the projectile incase of any exploiters
	local position = startPosition
	local velocity = startVelocity
	local lifeTime = 0
	local MAX_LIFETIME = duration + 4
	local GRAVITY = Vector3.new(0,-game.Workspace.Gravity,0)
	local HIT_DETECT_RAYCAST_PARAMS = RaycastParams.new()
	HIT_DETECT_RAYCAST_PARAMS.FilterDescendantsInstances = params
	while lifeTime < MAX_LIFETIME do
		local dt = runService.Heartbeat:Wait()
		local oldPosition = position
		local newPosition = oldPosition + (velocity * dt) + (-GRAVITY * dt * dt)
		velocity = velocity + GRAVITY * dt
		position = newPosition
		lifeTime += dt
		local hitResult = game.Workspace:Blockcast(CFrame.new(oldPosition),projectile.Size, newPosition - oldPosition, HIT_DETECT_RAYCAST_PARAMS) -- Block casts  to check the hit is legit
		if hitResult then
			local enemies = GetEnemyByPart(hitResult.Instance) -- Check whether the part belongs to an enemy
			if #enemies > 0 then
				for i,v in ipairs(enemies) do
					v.Humanoid:TakeDamage(20) -- If so then we damage it
				end
			end
			return hitResult
		end
	end
	return false
end
function module:FireProjectile() -- Fires the projectile in client
	local startposition = self.StartAttachment.WorldPosition -- Sets up variables
	local endposition = self.EndPosition
	local object = self.Projectile
	local param= self.Filter
	local hit_effect = game.ReplicatedStorage.Effects.Explosion
	local speed = self.Speed
	local direction = endposition - startposition
	local blackhole = object:Clone() -- Clone the projectiles and place it to workspace.Effects
	blackhole.Parent = workspace.Effects
	blackhole.Position = startposition
	blackhole.Anchored = false
	local gravity = game.Workspace.Gravity
	local duration = direction.Magnitude/speed
	local force = direction/duration + Vector3.new(0, gravity * duration * 0.5, 0)
	local mlt = duration + 4 -- Max life time
	game.Debris:AddItem(blackhole,mlt) -- Makes the projectile to be destroyed after max life time reached
	local lt = 0 -- Current lifetime
	local thing = "nothing" 
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = param -- Does raycast
	blackhole:ApplyImpulse(force * blackhole.AssemblyMass) -- Applies impulse with velocity and mass of object in consideration
	local position = startposition
	local velocity = force
	local GRAVITY = Vector3.new(0,-workspace.Gravity,0) -- Puts gravity in vector 3 for future calculations
	while lt <mlt do
		local dt = runService.RenderStepped:Wait()
		lt += dt 
		local oldPosition = position
		local newPosition = oldPosition + (velocity * dt) + (-GRAVITY * dt^2) -- Puts gravity in positive and calculate the endposition
		velocity = velocity + GRAVITY * dt -- Updates velocity to the current time passed with gravity
		position = newPosition
		local hitresults = workspace:Blockcast(CFrame.new(oldPosition),object.Size,newPosition-oldPosition,params) -- Casts to check for hits
		if hitresults then
			local hit:BasePart = hit_effect:Clone() -- If there is a hit, make a hit effect
			hit.Parent = workspace.Effects
			hit.Position = hitresults.Position
			hit.Anchored = true
			hit.CanCollide = false
			for i,v in ipairs(hit:GetDescendants()) do
				if v:IsA("ParticleEmitter") then
					v:Emit(v:GetAttribute("EmitCount"))
				end
			end
			break
		end
	end
end
function module:Project()
	local projectile = self.Projectile -- Sets up variables
	local range = self.Range
	local speed = self.Speed
	local startattachment = self.StartAttachment
	local player = game.Players.LocalPlayer
	local att1 = startattachment
	local filter = self.Filter
	att1.Orientation = Vector3.new(0,0,90)
	local att2 = Instance.new("Attachment",player.Character.HumanoidRootPart) -- Creates attachment for the beam to show the trajectory
	local att3 = Instance.new("Attachment",player.Character.HumanoidRootPart)
	local beam = Instance.new("Beam",workspace.Effects) -- Creates the beam to show the trajectory
	beam.Width0 = 0.1 -- Configs the beam
	beam.Width1 = 0.1
	beam.Segments = 100
	beam.FaceCamera =true
	beam.Color = ColorSequence.new(Color3.new(1, 0.968627, 0.941176),Color3.new(1, 0.898039, 0.494118))
	beam.Brightness = 10
	local beam2 = beam:Clone()
	beam2.Parent = workspace.Effects
	beam.Segments = 100
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
		local direction = GetMouseDirectionFromPoint(player.Character.HumanoidRootPart.Position,range)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = filter -- Filter the raycast to the parameters
		local ray = workspace:Blockcast(CFrame.new(startattachment.WorldPosition),projectile.Size,direction * range,params) -- Block casts the projectile out with consideration of it's size, origin and direction
		if ray then
			local direction = (ray.Position - att1.WorldPosition) -- Calculates the direction of ray hit position and start
			local duration = direction.Magnitude/speed -- Calculate the duration of the projectile based on it's speed
			local maxHeight =  (0.125 * workspace.Gravity * duration^2) -- Calculates the max height of the parabolic trajectory, using h = 1/8 gt^2
			att2.WorldPosition = att1.WorldPosition + ((ray.Position - att1.WorldPosition)/2) + Vector3.new(0,maxHeight,0) -- Gets the middle position to set up the curve
			att3.WorldPosition = ray.Position
			att3.Orientation = Vector3.new(0,0,90)
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
		beam.CurveSize0 = att2.Position.Y/2 -- Sets up the curve
		beam.CurveSize1 = -beam.CurveSize0
		if workspace.Cache:FindFirstChild("Direction") then
			ClientToServer:InvokeServer("Value",workspace.Cache.Direction,att3.WorldPosition) -- Returns the end position to the server
		end
	end)
	activeAim[player.Character][2] = {att2,att3,beam,beam2}
end
function module:CancelProject(player:Player) -- Can be cancelled via client or server
	if runService:IsClient() then
		player = game.Players.LocalPlayer
	end
	if activeAim[player.Character] then
		activeAim[player.Character][1]:Disconnect() -- Cancels projectile projection
		for i,v in ipairs(activeAim[player.Character][2]) do
			v:Destroy()
		end
		activeAim[player.Character] = nil
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
