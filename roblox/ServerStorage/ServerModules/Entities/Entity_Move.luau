--[[
	v3ltrixx 2026

	2/11/26:
		Added more configs to support the new entity "A-200" (runs to players)
		General improvements

--]]
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

local Controller = {}
Controller.__index = Controller

-- A function my demeted ass forgot
function Controller.new(npc, config)

	local self = setmetatable({}, Controller)

	self.NPC = npc
	self.Config = config or {}

	self.Speed = self.Config.Speed or 150
	self.RepathTime = self.Config.RepathTime or 1.5
	self.StuckTime = self.Config.StuckTime or 1.2
	self.MaxFailures = self.Config.MaxFailures or 4
	self.ClipHeight = self.Config.ClipHeight or 2

	self.Rebounds = self.Config.Rebounds or 0
	self.CurrentRebound = 0
	self.HeadingToLobby = self.Config.StartHeadingToLobby or false

	self.LobbyExit = self.Config.LobbyExit

	-- Config
	self.ChasePlayer = self.Config.ChasePlayer or false
	self.ChaseRange = self.Config.ChaseRange or math.huge
	self.TargetPlayer = nil

	self.MoveToken = 0
	self.CurrentTarget = nil

	self.Activ = npc:FindFirstChild("Activ") or Instance.new("BoolValue")
	self.Activ.Name = "Activ"
	self.Activ.Parent = npc

	self.PathConfigs = {
		{AgentRadius = 2, AgentHeight = 6, AgentCanJump = false},
		{AgentRadius = 1, AgentHeight = 4, AgentCanJump = false},
		{AgentRadius = 0.5, AgentHeight = 2, AgentCanJump = false},
		{AgentRadius = 1, AgentHeight = 4, AgentCanJump = true},
	}

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

-- Part toucher (no files buddy weirdo)
function Controller:GetTouchingParts()
	local t = self.NPC:GetTouchingParts()
	t[#t+1] = self.NPC
	return t
end

-- Detection: are we stuck on a part that has CanQuery (e.g. triggers/decor that block movement)?
function Controller:IsStuckOnCanQueryPart()
	local touching = self.NPC:GetTouchingParts()
	for _, part in ipairs(touching) do
		if part:IsA("BasePart") and part.CanQuery then
			return true, part
		end
	end
	return false, nil
end

-- Optional: get all touching parts that have CanQuery (for debugging or custom handling)
function Controller:GetTouchingCanQueryParts()
	local out = {}
	local touching = self.NPC:GetTouchingParts()
	for _, part in ipairs(touching) do
		if part:IsA("BasePart") and part.CanQuery then
			out[#out + 1] = part
		end
	end
	return out
end

-- Closest player diddler (trust)
function Controller:GetClosestPlayer()

	local npc = self.NPC
	local closest = nil
	local closestDist = self.ChaseRange

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")

		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and not char:FindFirstChild("Hiding") then
			local dist = (root.Position - npc.Position).Magnitude
			if dist < closestDist then
				closest = root
				closestDist = dist
			end
		end
	end

	return closest
end

-- Slow ahh roblox pathfinder
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

-- Fallback in case i, wait no, the script forgot how to work
function Controller:DirectMove(targetPos, token)

	local npc = self.NPC
	local lastPos = npc.Position
	local stuckTimer = 0
	local unstuckNudgeUsed = false

	while (targetPos - npc.Position).Magnitude > 3 do

		if token ~= self.MoveToken or not npc.Parent then
			return false
		end

		local dt = task.wait()
		local delta = targetPos - npc.Position
		if delta.Magnitude <= 0.05 then
			return true
		end
		local dir = delta.Unit
		local newPos = npc.Position + dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude)

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {self.NPC}
		params.RespectCanCollide = true

		local hit = workspace:Raycast(npc.Position, dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude), params)

		-- Ignore parts that don't physically block (CanQuery-only triggers, etc.) so we don't get stuck
		if hit and hit.Instance.CanCollide then
			local n = hit.Normal
			local slid = dir - n * dir:Dot(n)
			if slid.Magnitude <= 0.05 then
				return false
			end
			dir = slid.Unit
			newPos = npc.Position + dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude)
		end

		npc.CFrame = CFrame.new(newPos, newPos + dir) -- technically deprecated but whatever it works

		if (npc.Position - lastPos).Magnitude < 0.05 then
			stuckTimer += dt
			if not unstuckNudgeUsed and stuckTimer > 0.25 and self:IsStuckOnCanQueryPart() then
				unstuckNudgeUsed = true
				npc.CFrame = CFrame.new(newPos + Vector3.new(0, self.ClipHeight, 0), newPos + dir)
				stuckTimer = 0
				lastPos = npc.Position
			end
			if stuckTimer > self.StuckTime then
				return false
			end
		else
			stuckTimer = 0
			lastPos = npc.Position
		end
	end

	return true
end

function Controller:StepToward(targetPos, dt)

	local npc = self.NPC
	local delta = targetPos - npc.Position
	if delta.Magnitude <= 2 then
		return true
	end

	local dir = delta.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {self.NPC}
	params.RespectCanCollide = true

	local hit = workspace:Raycast(npc.Position, dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude), params)
	if hit and hit.Instance.CanCollide then
		local n = hit.Normal
		local slid = dir - n * dir:Dot(n)
		if slid.Magnitude > 0.05 then
			dir = slid.Unit
		else
			return false
		end
	end

	local newPos = npc.Position + dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude)
	npc.CFrame = CFrame.new(newPos, newPos + dir)
	return false
end

-- self explanitory
function Controller:ClipToTarget(pos)
	if typeof(pos) ~= "Vector3" then return false end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {self.NPC}

	local origin = pos + Vector3.new(0, 24, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -80, 0), rayParams)
	local safePos = hit and (hit.Position + Vector3.new(0, self.ClipHeight, 0)) or (pos + Vector3.new(0, self.ClipHeight, 0))
	self.NPC.CFrame = CFrame.new(safePos)
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
	local middle = self:GetNearestRoomMiddle(self.NPC.Position)
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

-- Movement shit
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

		local path = self:ComputePath(npc.Position, targetPos)
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

			local lastPos = npc.Position
			local stuckTimer = 0
			local unstuckNudgeUsed = false

			while (wp.Position - npc.Position).Magnitude > 2 do

				if token ~= self.MoveToken or not npc.Parent then return end

				local dt = task.wait()
				local delta = wp.Position - npc.Position
				if delta.Magnitude <= 0.05 then
					break
				end
				local dir = delta.Unit

				local newPos = npc.Position + dir * math.min(self.Speed * math.min(dt, 0.1), delta.Magnitude)
				npc.CFrame = CFrame.new(newPos, newPos + dir)

				if (npc.Position - lastPos).Magnitude < 0.05 then
					stuckTimer += dt
					-- If we're stuck and touching a CanQuery part, try a one-time nudge to unstick
					if not unstuckNudgeUsed and stuckTimer > 0.25 then
						local onCanQuery = self:IsStuckOnCanQueryPart()
						if onCanQuery then
							unstuckNudgeUsed = true
							self:ClipToTarget(wp.Position)
							stuckTimer = 0
							lastPos = npc.Position
						end
					end
					if stuckTimer > self.StuckTime then
						failures += 1
						attemptFailed = true
						break
					end
				else
					stuckTimer = 0
					lastPos = npc.Position
				end
			end

			if attemptFailed then break end

			if wp.Action == Enum.PathWaypointAction.Jump then
				npc.CFrame += Vector3.new(0, 8, 0)
			end
		end

		if not attemptFailed then
			break
		end

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

-- Chase loop (scawy)
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
				self:StepToward(root.Position, dt)
				local closest = self:GetClosestPlayer()
				if not closest then break end
				root = closest
				self.TargetPlayer = closest
			end
		else
			task.wait(0.5)
		end
	end

	self.Activ.Value = false
end

-- Exit changer updater (added this cause i forgot again im really demented huh)
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

-- Rebound handler i think
function Controller:ReachedTarget()

	-- Ignore rebounds when chasing (me irl trust trust)
	if self.ChasePlayer then
		return
	end

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

-- me and ur mom at 3am:
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

-- Do i really have to explain this?
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
