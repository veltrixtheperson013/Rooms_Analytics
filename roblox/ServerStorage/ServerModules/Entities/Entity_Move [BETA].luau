--[[
	!! BETA !!
	MAY BE UNSTABLE
	
	
	6/1/26:
	PivotTo() Compatibility
	some optimizations
	cleaner code
	removed herobrine
--]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

local Controller = {}
Controller.__index = Controller

function Controller.new(npc, config)
	local self = setmetatable({}, Controller)

	self.NPC = npc
	self.Config = config or {}

	-- Movement Settings
	self.Speed = self.Config.Speed or 150
	self.RepathTime = self.Config.RepathTime or 1.5
	self.StuckTime = self.Config.StuckTime or 1.2
	self.MaxFailures = self.Config.MaxFailures or 4
	self.ClipHeight = self.Config.ClipHeight or 2

	-- Rebound Tracking
	self.Rebounds = self.Config.Rebounds or 0
	self.CurrentRebound = 0
	self.HeadingToLobby = self.Config.StartHeadingToLobby or false
	self.LobbyExit = self.Config.LobbyExit

	-- Targeting Settings
	self.ChasePlayer = self.Config.ChasePlayer or false
	self.ChaseRange = self.Config.ChaseRange or math.huge
	self.TargetPlayer = nil

	self.MoveToken = 0
	self.CurrentTarget = nil

	-- State Management
	self.Activ = npc:FindFirstChild("Activ") or Instance.new("BoolValue")
	self.Activ.Name = "Activ"
	self.Activ.Parent = npc

	-- Pathfinding Agent Variations
	self.PathConfigs = {
		{AgentRadius = 2, AgentHeight = 6, AgentCanJump = false},
		{AgentRadius = 1, AgentHeight = 4, AgentCanJump = false},
		{AgentRadius = 0.5, AgentHeight = 2, AgentCanJump = false},
		{AgentRadius = 1, AgentHeight = 4, AgentCanJump = true},
	}

	-- Disable physics collisions for the entity parts
	for _, part in ipairs(npc:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Massless = true
		end
	end
	if npc:IsA("BasePart") then
		npc.CanCollide = false
		npc.Massless = true
	end

	return self
end

function Controller:GetTouchingParts()
	local touching = {}
	if self.NPC:IsA("BasePart") then
		touching = self.NPC:GetTouchingParts()
	else
		for _, part in ipairs(self.NPC:GetDescendants()) do
			if part:IsA("BasePart") then
				for _, other in ipairs(part:GetTouchingParts()) do
					if not other:IsDescendantOf(self.NPC) then table.insert(touching, other) end
				end
			end
		end
	end
	touching[#touching + 1] = self.NPC
	return touching
end

function Controller:IsStuckOnCanQueryPart()
	local touching = self:GetTouchingParts()
	for _, part in ipairs(touching) do
		if part:IsA("BasePart") and part.CanQuery then
			return true, part
		end
	end
	return false, nil
end

function Controller:GetTouchingCanQueryParts()
	local out = {}
	local touching = self:GetTouchingParts()
	for _, part in ipairs(touching) do
		if part:IsA("BasePart") and part.CanQuery then
			out[#out + 1] = part
		end
	end
	return out
end

-- go go gadget aim-9 sidewinder
function Controller:GetClosestPlayer()
	local npc = self.NPC
	local closest = nil
	local closestDist = self.ChaseRange
	local npcPosition = npc:IsA("Model") and npc:GetPivot().Position or npc.Position

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")

		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and not char:FindFirstChild("Hiding") then
			local dist = (root.Position - npcPosition).Magnitude
			if dist < closestDist then
				closest = root
				closestDist = dist
			end
		end
	end

	return closest
end

function Controller:ComputePath(startPos, endPos)
	for _, cfg in ipairs(self.PathConfigs) do
		local path = PathfindingService:CreatePath(cfg)
		local ok = pcall(function()
			path:ComputeAsync(startPos, endPos)
		end)

		if ok and path.Status == Enum.PathStatus.Success then
			return path
		end
	end
end

function Controller:UpdateNPCPlacement(position, direction)
	if self.NPC:IsA("Model") then
		self.NPC:PivotTo(CFrame.new(position, position + direction))
	else
		self.NPC.CFrame = CFrame.new(position, position + direction)
	end
end

function Controller:DirectMove(targetPos, token)
	local npc = self.NPC
	local currentPos = npc:GetPivot().Position
	local lastPos = currentPos
	local stuckTimer = 0
	local unstuckNudgeUsed = false

	while (targetPos - currentPos).Magnitude > 3 do
		if token ~= self.MoveToken or not npc.Parent then
			return false
		end

		local dt = task.wait()
		currentPos = npc:GetPivot().Position

		local delta = targetPos - currentPos
		if delta.Magnitude <= 0.05 then
			return true
		end

		local dir = delta.Unit
		local newPos = currentPos + dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude)

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {self.NPC}
		params.RespectCanCollide = true

		local hit = workspace:Raycast(currentPos, dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude), params)

		if hit and hit.Instance.CanCollide then
			local n = hit.Normal
			local slid = dir - n * dir:Dot(n)
			if slid.Magnitude <= 0.05 then
				return false
			end
			dir = slid.Unit
			newPos = currentPos + dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude)
		end

		self:UpdateNPCPlacement(newPos, dir)

		if (currentPos - lastPos).Magnitude < 0.05 then
			stuckTimer += dt
			if not unstuckNudgeUsed and stuckTimer > 0.25 and self:IsStuckOnCanQueryPart() then
				unstuckNudgeUsed = true
				self:UpdateNPCPlacement(newPos + Vector3.new(0, self.ClipHeight, 0), dir)
				stuckTimer = 0
				lastPos = npc:GetPivot().Position
			end
			if stuckTimer > self.StuckTime then
				return false
			end
		else
			stuckTimer = 0
			lastPos = currentPos
		end
	end

	return true
end

function Controller:StepToward(targetPos, dt)
	local npc = self.NPC
	local currentPos = npc:GetPivot().Position
	local delta = targetPos - currentPos

	if delta.Magnitude <= 2 then
		return true
	end

	local dir = delta.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {self.NPC}
	params.RespectCanCollide = true

	local hit = workspace:Raycast(currentPos, dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude), params)
	if hit and hit.Instance.CanCollide then
		local n = hit.Normal
		local slid = dir - n * dir:Dot(n)
		if slid.Magnitude > 0.05 then
			dir = slid.Unit
		else
			return false
		end
	end

	local newPos = currentPos + dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude)
	self:UpdateNPCPlacement(newPos, dir)
	return false
end

function Controller:ClipToTarget(pos)
	if typeof(pos) ~= "Vector3" then return false end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {self.NPC}

	local origin = pos + Vector3.new(0, 24, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -80, 0), rayParams)
	local safePos = hit and (hit.Position + Vector3.new(0, self.ClipHeight, 0)) or (pos + Vector3.new(0, self.ClipHeight, 0))

	if self.NPC:IsA("Model") then
		self.NPC:PivotTo(CFrame.new(safePos))
	else
		self.NPC.CFrame = CFrame.new(safePos)
	end
	return true
end

function Controller:GetNearestRoomMiddle(position)
	local rooms = workspace:FindFirstChild("GeneratedRooms")
	if not rooms or typeof(position) ~= "Vector3" then return nil end

	local bestMiddle = nil
	local bestDistance = math.huge
	for _, room in ipairs(rooms:GetChildren()) do
		local middle = room:FindFirstChild("Middle", true)
		if middle and middle:IsA("BasePart") then
			local distance = (middle.Position - position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				bestMiddle = middle
			end
		end
	end

	return bestMiddle
end

function Controller:RecoverToNearestMiddle(targetPos)
	local currentPos = self.NPC:GetPivot().Position
	local middle = self:GetNearestRoomMiddle(currentPos)
	if not middle then return false end

	if self.LastRecoveryMiddle and self.LastRecoveryMiddle.Parent then
		if (self.LastRecoveryMiddle.Position - middle.Position).Magnitude < 1 then
			return false
		end
	end

	self.LastRecoveryMiddle = middle
	self:ClipToTarget(middle.Position)
	task.wait(0.05)
	return typeof(targetPos) == "Vector3"
end

function Controller:MoveTo(targetPos)
	local npc = self.NPC
	if typeof(targetPos) ~= "Vector3" or not npc or not npc.Parent then
		self.Activ.Value = false
		return
	end

	self.MoveToken += 1
	local token = self.MoveToken
	self.Activ.Value = true
	local failures = 0

	while failures < self.MaxFailures do
		if token ~= self.MoveToken or not npc.Parent then return end

		local currentPos = npc:GetPivot().Position
		local path = self:ComputePath(currentPos, targetPos)
		if token ~= self.MoveToken or not npc.Parent then return end
		local attemptFailed = false

		if not path then
			if self:DirectMove(targetPos, token) then
				break
			end
			failures += 1
			task.wait(self.RepathTime)
			continue
		end

		for _, wp in ipairs(path:GetWaypoints()) do
			local lastPos = npc:GetPivot().Position
			local stuckTimer = 0
			local unstuckNudgeUsed = false

			while (wp.Position - npc:GetPivot().Position).Magnitude > 2 do
				if token ~= self.MoveToken or not npc.Parent then return end

				local dt = task.wait()
				currentPos = npc:GetPivot().Position
				local delta = wp.Position - currentPos
				if delta.Magnitude <= 0.05 then
					break
				end
				local dir = delta.Unit
				local newPos = currentPos + dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude)

				self:UpdateNPCPlacement(newPos, dir)

				if (npc:GetPivot().Position - lastPos).Magnitude < 0.05 then
					stuckTimer += dt
					if not unstuckNudgeUsed and stuckTimer > 0.25 then
						if self:IsStuckOnCanQueryPart() then
							unstuckNudgeUsed = true -- boop
							self:ClipToTarget(wp.Position)
							stuckTimer = 0
							lastPos = npc:GetPivot().Position
						end
					end
					if stuckTimer > self.StuckTime then
						failures += 1
						attemptFailed = true
						break
					end
				else
					stuckTimer = 0
					lastPos = npc:GetPivot().Position
				end
			end

			if attemptFailed then break end

			if wp.Action == Enum.PathWaypointAction.Jump then
				if npc:IsA("Model") then
					npc:PivotTo(npc:GetPivot() + Vector3.new(0, 8, 0))
				else
					npc.CFrame += Vector3.new(0, 8, 0)
				end
			end
		end

		if not attemptFailed then break end
		task.wait(self.RepathTime)
	end

	if token ~= self.MoveToken or not npc.Parent then return end
	if failures >= self.MaxFailures then
		if self:RecoverToNearestMiddle(targetPos) then
			failures = 0
			if not self:DirectMove(targetPos, token) then
				self:ClipToTarget(targetPos)
			end
		else
			self:ClipToTarget(targetPos)
		end
	end

	if token ~= self.MoveToken or not npc.Parent then return end
	self.Activ.Value = false
	self:ReachedTarget()
end

function Controller:ChasePlayers()
	self.Activ.Value = true

	while self.NPC.Parent and self.ChasePlayer do
		local root = self:GetClosestPlayer()

		if root then
			self.TargetPlayer = root
			local token = self.MoveToken + 1
			self.MoveToken = token

			while self.NPC.Parent and self.ChasePlayer and root.Parent do
				if token ~= self.MoveToken then break end
				local dt = task.wait(0.03)

				-- Step toward our current target
				self:StepToward(root.Position, dt)

				-- Check if someone else became closer
				local newClosest = self:GetClosestPlayer()
				if not newClosest then 
					break 
				elseif newClosest ~= root then
					-- Switch targets dynamically
					root = newClosest
					self.TargetPlayer = newClosest
				end
			end
		else
			task.wait(0.5)
		end
	end

	self.Activ.Value = false
end

function Controller:GetLatestExit()
	local latest = game:GetService("ReplicatedStorage"):FindFirstChild("LatestRoom")
	if latest and latest.Value and latest.Value:FindFirstChild("Exit") then
		return latest.Value.Exit
	end

	local rooms = workspace:FindFirstChild("GeneratedRooms")
	if not rooms then return end

	local best, bestNum

	for _, r in ipairs(rooms:GetChildren()) do
		local n = tonumber(r.Name)
		if n and (not bestNum or n > bestNum) then
			bestNum = n
			best = r
		end
	end

	return best and best:FindFirstChild("Exit")
end

function Controller:GoToExit()
	self.HeadingToLobby = false
	local exit = self:GetLatestExit()
	if exit then
		self:MoveTo(exit.Position)
	else
		task.delay(0.25, function()
			if self.NPC.Parent and not self.ChasePlayer then
				self:GoToExit()
			end
		end)
	end
end

function Controller:GoToLobby()
	self.HeadingToLobby = true
	if self.LobbyExit then
		self:MoveTo(self.LobbyExit.Position)
	else
		self.NPC:Destroy()
	end
end

function Controller:ReachedTarget()
	if self.ChasePlayer then return end

	if not self.HeadingToLobby then
		if self.Rebounds == 0 then
			self.NPC:Destroy()
			return
		end

		self.CurrentRebound += 1
		self:GoToLobby()
	else
		if self.CurrentRebound >= self.Rebounds then
			self.NPC:Destroy()
			return
		end

		self:GoToExit()
	end
end

function Controller:PlaySound(name)
	local s = self.NPC:FindFirstChild(name)
	if s then
		s:Play()
		task.wait(s.TimeLength)
	end
end

function Controller:LoopSound(name, on)
	local s = self.NPC:FindFirstChild(name)
	if s then
		s.Looped = true
		if on then s:Play() else s:Stop() end
	end
end

-- officer earl-inator
function Controller:Start()
	if self.Started then return end
	self.Started = true
	self:PlaySound("Spawn")
	if not self.NPC.Parent then return end
	self:LoopSound("Footsteps", true)
	self:LoopSound("Footsteps2", true)

	if self.ChasePlayer then
		task.spawn(function()
			self:ChasePlayers()
		end)
		return
	end

	if self.HeadingToLobby then
		self:GoToLobby()
	else
		self:GoToExit()
	end
end

return Controller
