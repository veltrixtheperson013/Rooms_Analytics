--[[
	!! BETA !!
	MAY BE UNSTABLE
	
	6/1/26:
	- Model and pivot compatibility via GetPivot().Position
	- Fixed raycast self-occlusion bugs by pushing origin 1 stud forward
	- Added hit debounce per player to prevent double-dipping damage spam
	- Cleaned up telemetry checks for server-side integration
	- Integrated TargetHidingPlayers / HidingKillRange mechanics for specialized entities (A-270)
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local KillHandler = {}
KillHandler.__index = KillHandler

function KillHandler.new(npc, config)
	local self = setmetatable({}, KillHandler)

	self.NPC = npc
	self.Config = config or {}

	-- Attack Configuration
	self.MaxDistance = self.Config.MaxDistance or 50
	self.Damage = self.Config.Damage or 100
	self.ScanRate = self.Config.ScanRate or 0.05 -- High speed synchronization rate

	-- Specialized Target Properties
	self.TargetHidingPlayers = self.Config.TargetHidingPlayers == true
	self.HidingKillRange = self.Config.HidingKillRange or self.MaxDistance

	self.RequireActiv = self.Config.RequireActiv ~= false
	self.JumpscareObject = self.Config.JumpscareObject

	self.Running = false
	self.CanAttack = true
	self.HitDebounces = {} -- Tracks individual players to avoid frame double-dipping

	return self
end

-- Helper to safely grab position whether NPC is a Part or Model
local function getNPCPosition(npc)
	if npc:IsA("Model") then
		return npc:GetPivot().Position
	end
	return npc.Position
end

function KillHandler:FindNearestVisibleTorso(sourcePosition)
	local nearestTorso = nil
	local minDistance = self.MaxDistance

	-- Exclude both the NPC and its entire sub-hierarchy safely
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {self.NPC}
	rayParams.IgnoreWater = true

	local hidingKillRange = self.HidingKillRange or self.MaxDistance

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character ~= self.NPC and not self.HitDebounces[player] then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local torso = character:FindFirstChild("HumanoidRootPart")

			if torso and humanoid and humanoid.Health > 0 then
				local isHiding = character:FindFirstChild("Hiding") ~= nil

				-- FEATURE: Exclusive Trait Filter
				-- If entity targets lockers but player is exposed -> SKIP
				-- If entity targets exposed but player is in locker -> SKIP
				if (self.TargetHidingPlayers and not isHiding) or (not self.TargetHidingPlayers and isHiding) then
					continue
				end

				local targetPos = torso.Position
				local distance = (targetPos - sourcePosition).Magnitude

				-- FEATURE: Visibility / Proximity Check
				if isHiding then
					-- Hiding players: Proximity-only check (Locker geo blocks raycasts)
					if distance < hidingKillRange and distance < minDistance then
						minDistance = distance
						nearestTorso = torso
					end
				else
					-- Non-hiding players: Full raycast line-of-sight check
					if distance < minDistance then
						local result = Workspace:Raycast(sourcePosition, targetPos - sourcePosition, rayParams)

						-- If no static geometry intercepts the cast, the target is clearly visible
						if not result or result.Instance:IsDescendantOf(character) then
							minDistance = distance
							nearestTorso = torso
						end
					end
				end
			end
		end
	end

	return nearestTorso
end

-- *luigi scream.png*
function KillHandler:TriggerJumpscare(player)
	if not self.JumpscareObject then return end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local existing = playerGui:FindFirstChild(self.JumpscareObject.Name)
	if existing then
		existing:Destroy()
	end

	local clone = self.JumpscareObject:Clone()
	clone.Parent = playerGui

	local effect = clone:FindFirstChild("JumpscareEffect")
	if effect then
		effect.Enabled = true
	end
end

function KillHandler:Attack(targetRoot)
	if not targetRoot or not targetRoot.Parent or not self.NPC.Parent then return end
	local character = targetRoot.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	-- Apply individual player debounce instantly
	self.HitDebounces[player] = true

	-- Telemetry Handling
	local cause = self.Config.TelemetryCause or self.NPC:GetAttribute("TelemetryCause") or self.NPC.Name
	if humanoid.Health - self.Damage <= 0 then humanoid:SetAttribute("TelemetryDeathCause", cause) end
	if humanoid.Health - self.Damage <= 0 then
		local telemetryEvent = ServerStorage:FindFirstChild("TelemetryDeathEvent")
		if telemetryEvent and telemetryEvent:IsA("BindableEvent") then
			pcall(function()
				telemetryEvent:Fire(player, cause)
			end)
		end
	end

	humanoid.Health = math.max(0, humanoid.Health - self.Damage)

	if humanoid.Health <= 0 then self:TriggerJumpscare(player) end

	-- Clean up player tracking table shortly after engagement
	task.delay(0.5, function()
		self.HitDebounces[player] = nil
	end)
end

function KillHandler:Run()
	if self.Running then return end
	self.Running = true

	while self.Running and self.NPC.Parent do
		task.wait(self.ScanRate)
		if not self.Running or not self.NPC.Parent then break end

		if self.RequireActiv then
			local activ = self.NPC:FindFirstChild("Activ")
			if not activ or not activ.Value then
				continue
			end
		end

		if not self.CanAttack then
			continue
		end

		local currentPos = getNPCPosition(self.NPC)
		local target = self:FindNearestVisibleTorso(currentPos)

		if target then
			self:Attack(target)
		end
	end
end

-- hi
function KillHandler:Start()
	task.spawn(function()
		self:Run()
	end)
end

-- bye
function KillHandler:Stop()
	self.Running = false
	table.clear(self.HitDebounces)
end

return KillHandler
