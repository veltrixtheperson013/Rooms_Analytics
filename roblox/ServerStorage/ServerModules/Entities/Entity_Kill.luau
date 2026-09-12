--[[
	v3ltrixx 2026

	2/11/26:
		Made the entity less stupid

--]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local KillHandler = {}
KillHandler.__index = KillHandler

-- Canstruction
function KillHandler.new(npc, config)

	local self = setmetatable({}, KillHandler)

	self.NPC = npc
	self.Config = config or {}

	self.MaxDistance = self.Config.MaxDistance or 50
	self.Damage = self.Config.Damage or 100
	self.ScanRate = self.Config.ScanRate or 0.1

	self.RequireActiv = self.Config.RequireActiv ~= false

	self.JumpscareObject = self.Config.JumpscareObject

	self.Running = false
	self.CanAttack = true

	return self
end

-- Hide and seek but the seeker has 360 vision
function KillHandler:FindNearestVisibleTorso(sourcePosition)

	local nearestTorso = nil
	local minDistance = self.MaxDistance

	for _, player in ipairs(Players:GetPlayers()) do

		local character = player.Character
		if character and character ~= self.NPC then

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local torso = character:FindFirstChild("HumanoidRootPart")

			if torso and humanoid and humanoid.Health > 0 and not character:FindFirstChild("Hiding") then

				local distance = (torso.Position - sourcePosition).Magnitude

				if distance < minDistance then

					local rayParams = RaycastParams.new()
					rayParams.FilterType = Enum.RaycastFilterType.Exclude
					rayParams.FilterDescendantsInstances = {self.NPC, character}
					rayParams.IgnoreWater = true

					local result = Workspace:Raycast(sourcePosition, torso.Position - sourcePosition, rayParams)

					if not result then
						minDistance = distance
						nearestTorso = torso
					end
				end
			end
		end
	end

	return nearestTorso
end

-- Im gonna make you shit your pants
function KillHandler:TriggerJumpscare(player, character)

	if not self.JumpscareObject then return end
	if not player or not player:FindFirstChild("PlayerGui") then return end

	local existing = player.PlayerGui:FindFirstChild(self.JumpscareObject.Name)
	if existing then
		existing:Destroy()
	end

	local clone = self.JumpscareObject:Clone()
	clone.Parent = player.PlayerGui

	local effect = clone:FindFirstChild("JumpscareEffect")
	if effect then
		effect.Enabled = true
	end
end

-- AAAAAAAAAAAAAAH RUN
function KillHandler:Attack(targetRoot)

	if not targetRoot or not targetRoot.Parent or not self.NPC.Parent then return end
	local character = targetRoot.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid.Health <= 0 then return end

	local player = Players:GetPlayerFromCharacter(character)
	local cause = self.Config.TelemetryCause or self.NPC:GetAttribute("TelemetryCause") or self.NPC.Name
	if humanoid.Health - self.Damage <= 0 then humanoid:SetAttribute("TelemetryDeathCause", cause) end
	if player and humanoid.Health > 0 and humanoid.Health - self.Damage <= 0 then
		local telemetryEvent = ServerStorage:FindFirstChild("TelemetryDeathEvent")
		if telemetryEvent and telemetryEvent:IsA("BindableEvent") then
			telemetryEvent:Fire(player, cause)
		end
	end

	humanoid.Health -= self.Damage

	if humanoid.Health <= 0 then self:TriggerJumpscare(player, character) end
end

-- Roller coaster
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

		local target = self:FindNearestVisibleTorso(self.NPC.Position)

		if target then
			self.CanAttack = false
			self:Attack(target)
			task.wait()
			self.CanAttack = true
		end
	end
end

----------------------------------------------------
function KillHandler:Start()
	task.spawn(function()
		self:Run()
	end)
end

function KillHandler:Stop()
	self.Running = false
end

return KillHandler
