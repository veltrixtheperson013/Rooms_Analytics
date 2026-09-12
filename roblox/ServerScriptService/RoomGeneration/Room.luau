local Room = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

Room.info = require(script:WaitForChild("RoomInfo"))
Room.furniture = require(script:WaitForChild("Furniture"))
local SpecialRooms = require(script:WaitForChild("SpecialRooms"))

Room.lastTurnDirection = nil
Room.random = Random.new()
local BuildingLayout = require(script:WaitForChild("BuildingLayout"))
local configuredSeed = script.Parent:GetAttribute("BuildingSeed")
Room.buildingSeed = type(configuredSeed) == "number" and math.floor(configuredSeed) or Room.random:NextInteger(1, 2147483646)
Room.layout = BuildingLayout.new(Room.buildingSeed, script.Parent:GetAttribute("BuildingNoiseScale"), script.Parent:GetAttribute("BuildingNoiseStrength"))
script:SetAttribute("ActiveBuildingSeed", Room.buildingSeed)

function Room.IsLayoutAllowed(name, step)
	local info = Room.info[name]
	if Room.layout.Strength == 0 or not (info and info.Stairs) then return true end
	-- Keep a floor for at least twelve rooms, including after preload rollback.
	for _, placed in ipairs(Room.GeneratedRoomsInfo) do
		local placedInfo = Room.info[placed.template]
		local distance = (step or 0) - (placed.number or 0)
		if distance > 0 and distance < 12 and placedInfo and placedInfo.Stairs then return false end
	end
	return true
end

function Room.GetLayoutWeight(name, step, previousTemplate)
	return Room.layout:Weight(name, Room.info[name], step, previousTemplate and Room.info[previousTemplate])
end

Room.turnValue = 0
local MAX_CUMULATIVE_TURNS = 2
local EARLY_FORBIDDEN_UNTIL_STEP = 15  -- raised from 7; staircases near spawn cause clipping nightmares

Room.placedBounds = {}
local OVERLAP_MARGIN = 15

Room.generationStopped = false

Room.GeneratedRoomsInfo = {}
Room.SpawnedEntitiesInfo = {}

-- Stores the lobby/spawn AABB so generated rooms can be rejected if they clip it
Room.spawnBounds = nil

function Room.ForgetGeneratedRoom(generatedRoom)
	if not generatedRoom then return end
	for i = #Room.GeneratedRoomsInfo, 1, -1 do
		if Room.GeneratedRoomsInfo[i].room == generatedRoom then
			table.remove(Room.GeneratedRoomsInfo, i)
		end
	end
	for i = #Room.placedBounds, 1, -1 do
		if Room.placedBounds[i].room == generatedRoom then
			table.remove(Room.placedBounds, i)
		end
	end
	if generatedRoom.Parent then
		generatedRoom:Destroy()
	end
end

function Room.ApplyRoomNumber(generatedRoom, roomNumber, sectionName)
	if not generatedRoom then return end
	local sectionTag = sectionName or generatedRoom:GetAttribute("Section") or "?"
	local roomNumberString = string.format("%03d", roomNumber)
	local sign = generatedRoom:FindFirstChild("Sign")
	if sign then
		for _, label in ipairs(sign:GetDescendants()) do
			if label:IsA("TextLabel") then
				label.Text = tostring(sectionTag) .. "-" .. roomNumberString
			end
		end
	end
	for _, label in ipairs(generatedRoom:GetDescendants()) do
		if label:IsA("TextLabel") and string.find(label.Text or "", "%a%-%d+") then
			label.Text = tostring(sectionTag) .. "-" .. roomNumberString
		end
	end
	generatedRoom:SetAttribute("PendingNumber", roomNumber)
	generatedRoom:SetAttribute("Section", sectionTag)
end

function Room.SyncStateFromRoom(committedRoom)
	local template = committedRoom and (committedRoom:GetAttribute("Template") or committedRoom.Name)
	local info = template and Room.info[template]
	Room.lastRoomName = template
	if info and info.Direction then
		Room.lastTurnDirection = info.Direction
		Room.turnValue = (info.Direction == "Right") and 1 or -1
	else
		Room.lastTurnDirection = nil
		Room.turnValue = 0
	end
end

local function pivotTo(instance, cframe)
	if not instance then return end
	if instance:IsA("Model") then
		if instance.PrimaryPart then
			instance:SetPrimaryPartCFrame(cframe)
		else
			local firstPart = nil
			for _, v in ipairs(instance:GetDescendants()) do
				if v:IsA("BasePart") then
					firstPart = v
					break
				end
			end
			if firstPart then
				local modelCf = firstPart.CFrame
				local offset = modelCf:toObjectSpace(instance:GetModelCFrame() and instance:GetModelCFrame() or modelCf)
				instance:MoveTo(cframe.Position)
				if instance.PivotTo then
					pcall(function() instance:PivotTo(cframe) end)
				end
			else
				warn("[Room] Can't position model (no BasePart found):", instance.Name)
			end
		end
	else
		if instance:IsA("BasePart") then
			instance.CFrame = cframe
		else
			pcall(function()
				if instance.CFrame then instance.CFrame = cframe end
			end)
		end
	end
end

local function getAABB(model)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local found = false
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local cf = part.CFrame
			local size = part.Size
			local sx, sy, sz = size.X / 2, size.Y / 2, size.Z / 2
			for _, offset in ipairs({
				Vector3.new(sx, sy, sz), Vector3.new(sx, sy, -sz),
				Vector3.new(sx, -sy, sz), Vector3.new(sx, -sy, -sz),
				Vector3.new(-sx, sy, sz), Vector3.new(-sx, sy, -sz),
				Vector3.new(-sx, -sy, sz), Vector3.new(-sx, -sy, -sz),
				}) do
				local world = cf:PointToWorldSpace(offset)
				minX = math.min(minX, world.X)
				minY = math.min(minY, world.Y)
				minZ = math.min(minZ, world.Z)
				maxX = math.max(maxX, world.X)
				maxY = math.max(maxY, world.Y)
				maxZ = math.max(maxZ, world.Z)
			end
			found = true
		end
	end
	if not found then return nil end
	return {min = Vector3.new(minX, minY, minZ), max = Vector3.new(maxX, maxY, maxZ)}
end

local function overlaps(a, b, margin)
	margin = margin or OVERLAP_MARGIN
	local aMin = a.min + Vector3.new(margin, margin, margin)
	local aMax = a.max - Vector3.new(margin, margin, margin)
	local bMin = b.min + Vector3.new(margin, margin, margin)
	local bMax = b.max - Vector3.new(margin, margin, margin)
	if aMin.X >= aMax.X or aMin.Y >= aMax.Y or aMin.Z >= aMax.Z then return false end
	if bMin.X >= bMax.X or bMin.Y >= bMax.Y or bMin.Z >= bMax.Z then return false end
	return aMin.X < bMax.X and aMax.X > bMin.X
		and aMin.Y < bMax.Y and aMax.Y > bMin.Y
		and aMin.Z < bMax.Z and aMax.Z > bMin.Z
end

local function checkOverlap(newBounds)
	if not newBounds then return false end
	for _, existing in ipairs(Room.placedBounds) do
		if overlaps(newBounds, existing) then
			return true
		end
	end
	return false
end

-- Call this once from the main gen script, passing the lobby/spawn model.
-- Registers its AABB so Generate() can reject rooms that clip through it.
function Room.RegisterSpawn(spawnRoom)
	if not spawnRoom or not spawnRoom:IsA("Model") then return end
	local bounds = getAABB(spawnRoom)
	if bounds then
		Room.spawnBounds = bounds
		print("[Room] Spawn bounds registered:", spawnRoom.Name)
	else
		warn("[Room] RegisterSpawn: getAABB returned nil for", spawnRoom.Name)
	end
end

function Room.SpawnEntity(entityTemplate, spawnCFrame)
	if not entityTemplate then
		warn("[Room] SpawnEntity called with nil template")
		return nil
	end

	local clone = entityTemplate:Clone()
	clone.Parent = Workspace
	if clone:IsA("Model") then
		if clone.PrimaryPart then
			pcall(function() clone:PivotTo(spawnCFrame) end)
		else
			if clone.PivotTo then
				pcall(function() clone:PivotTo(spawnCFrame) end)
			else
				local bp
				for _, v in ipairs(clone:GetDescendants()) do
					if v:IsA("BasePart") then bp = v; break end
				end
				if bp then
					local offset = spawnCFrame - bp.CFrame
					for _, v in ipairs(clone:GetDescendants()) do
						if v:IsA("BasePart") then
							v.CFrame = v.CFrame + offset.Position
						end
					end
				end
			end
		end
	else
		pcall(function() clone.CFrame = spawnCFrame end)
	end

	local info = {
		name = entityTemplate.Name,
		model = clone,
		cframe = spawnCFrame,
		time = tick(),
	}
	table.insert(Room.SpawnedEntitiesInfo, info)
	return info
end

function Room.RandomizedSpawn(chance, doorNumSpawn, entityTemplate, spawnCFrame, flicker)
	if type(chance) ~= "number" or chance < 1 then
		warn("[Room] RandomizedSpawn got invalid chance:", chance)
		return nil
	end

	local rnumValue = ReplicatedStorage:FindFirstChild("rnum")
	if not rnumValue or not rnumValue.Value then
		warn("[Room] RandomizedSpawn: missing rnum value")
		return nil
	end
	local rnum = rnumValue.Value

	if rnum == doorNumSpawn then
		return Room.SpawnEntity(entityTemplate, spawnCFrame)
	end

	if rnum > doorNumSpawn then
		local roll = math.random(1, math.max(1, math.floor(chance)))
		if roll == 1 then
			task.delay(1.5, function()
				local ok, _ = pcall(function()
					local lightsToggle = Workspace:FindFirstChild("LightsToggle")
					if lightsToggle and lightsToggle:IsA("BoolValue") then
						lightsToggle.Value = true
					end
				end)
			end)
			return Room.SpawnEntity(entityTemplate, spawnCFrame)
		end
	end

	return nil
end

Room.lastRoomName = nil

Room.forbiddenEarlyRooms = {
	"Staircase_Up", "Staircase_Up2", "Catwalk_hole",
	"Basicintersection", "LeftBasicintersection", "RightBasicintersection",
	"Staircase_Down", "BasicTurn_Left", "BasicTurn_Right"
}

-- Public helper so room gen can call the same check before building queues.
function Room.IsForbiddenForStep(roomName, step)
	if type(roomName) ~= "string" then return false end
	if (step or math.huge) > EARLY_FORBIDDEN_UNTIL_STEP then return false end
	for _, forbidden in ipairs(Room.forbiddenEarlyRooms) do
		if string.lower(forbidden) == string.lower(roomName) then return true end
	end
	return false
end

function Room.GetRandom(prevRoom, miniSection, forcedTemplateName, desiredRnum, globalRoomCount)
	local rnumValue = ReplicatedStorage:FindFirstChild("rnum")
	local sectionValue = ReplicatedStorage:FindFirstChild("Section")
	if not rnumValue or not sectionValue then
		warn("[Room] GetRandom: missing ReplicatedStorage values (rnum/Section)")
		return nil
	end
	local rnum = desiredRnum or rnumValue.Value

	local function isForbidden(roomName)
		return Room.IsForbiddenForStep(roomName, Room.step)
	end

	local function canUseTemplate(roomName)
		if not Room.IsLayoutAllowed(roomName, rnum) then return false, "floor landing spacing" end
		local info = Room.info[roomName]
		local direction = info and info.Direction
		local hasStairs = info and info.Stairs
		local prevTemplate = prevRoom and (prevRoom:GetAttribute("Template") or prevRoom.Name)
		local prevInfo = prevTemplate and Room.info[prevTemplate]
		local prevHadStairs = prevInfo and prevInfo.Stairs

		if prevTemplate and prevTemplate == roomName then return false, "same previous room" end
		if Room.lastRoomName and Room.lastRoomName == roomName then return false, "same last room" end
		if direction and direction == Room.lastTurnDirection then return false, "same turn direction" end
		if hasStairs and prevHadStairs then return false, "consecutive stairs" end

		-- HARDCODED: Prevent intersections from spawning directly after any staircase to fix a clipping issue
		if prevTemplate and string.find(prevTemplate, "Staircase") and string.find(roomName, "intersection") then
			return false, "intersection after staircase forbidden"
		end

		if direction then
			local delta = (direction == "Right") and 1 or -1
			if math.abs(Room.turnValue + delta) > MAX_CUMULATIVE_TURNS then
				return false, "too many cumulative turns"
			end
		end
		return true
	end

	local function markTemplate(roomName)
		local info = Room.info[roomName]
		local direction = info and info.Direction
		if direction then
			Room.lastTurnDirection = direction
			local delta = (direction == "Right") and 1 or -1
			Room.turnValue = Room.turnValue + delta
		else
			Room.lastTurnDirection = nil
			Room.turnValue = 0
		end
		Room.lastRoomName = roomName
	end

	local roomsRoot = ServerStorage:FindFirstChild("Rooms")
	local sectionFolder = roomsRoot and roomsRoot:FindFirstChild(sectionValue.Value)
	if not sectionFolder then
		warn("[Room] Rooms section folder missing for Section:", tostring(sectionValue.Value))
		return nil
	end

	local templatesFolder = sectionFolder
	if type(miniSection) == "string" and miniSection ~= "" then
		local msFolder = sectionFolder:FindFirstChild(miniSection)
		if msFolder then
			templatesFolder = msFolder
		else
			warn("[Room] MiniSection folder not found under section folder:", tostring(miniSection))
		end
	end
	print("[Room] GetRandom context:", "Section=", tostring(sectionValue.Value), "MiniSection=", tostring(miniSection), "Folder=", templatesFolder:GetFullName())

	local specialLookupNum = globalRoomCount or rnum
	local special = SpecialRooms[specialLookupNum]
	if special then
		local specialRoom = templatesFolder:FindFirstChild(special)
		if not specialRoom and templatesFolder ~= sectionFolder then
			specialRoom = sectionFolder:FindFirstChild(special)
		end
		if not specialRoom then
			local specialRoomsFolder = roomsRoot and roomsRoot:FindFirstChild("SpecialRooms")
			if specialRoomsFolder then
				specialRoom = specialRoomsFolder:FindFirstChild(special)
			end
		end
		if specialRoom then
			if isForbidden(special) then
				warn("[Room] Special room requested but forbidden for early step:", special)
				specialRoom = nil
			else
				local usable, reason = canUseTemplate(special)
				if not usable then
					warn("[Room] Special room rejected:", special, reason)
					specialRoom = nil
				else
					print("[Room] Using special room:", specialRoom.Name)
					markTemplate(specialRoom.Name)
					return specialRoom
				end
			end
		else
			warn("[Room] Special room requested but not found:", special)
		end
	end

	if type(forcedTemplateName) == "string" and forcedTemplateName ~= "" then
		local forcedModel = templatesFolder:FindFirstChild(forcedTemplateName)
		if not forcedModel and templatesFolder ~= sectionFolder then
			forcedModel = sectionFolder:FindFirstChild(forcedTemplateName)
		end
		if forcedModel and forcedModel:IsA("Model") then
			if isForbidden(forcedTemplateName) then
				warn("[Room] Forced template is forbidden for early step, ignoring:", forcedTemplateName)
			else
				local usable, reason = canUseTemplate(forcedTemplateName)
				if usable then
					markTemplate(forcedTemplateName)
					print("[Room] Forced template accepted:", tostring(forcedTemplateName), "MiniSection=", tostring(miniSection), "TurnAccum=", tostring(Room.turnValue))
					return forcedModel
				else
					warn("[Room] Forced template rejected:", tostring(forcedTemplateName), reason)
				end
			end
		else
			warn("[Room] Forced template not found, falling back:", tostring(forcedTemplateName), "MiniSection=", tostring(miniSection))
		end
	end

	local availableTemplates = {}
	for _, child in ipairs(templatesFolder:GetChildren()) do
		if child:IsA("Model") then
			availableTemplates[child.Name] = true
		end
	end

	local totalWeight = 0
	local entries = {}
	for name, info in pairs(Room.info) do
		if not info.Section or info.Section == sectionValue.Value then
			if not isForbidden(name) then
				if templatesFolder == sectionFolder or availableTemplates[name] == true then
					local w = tonumber(info.Weight) or 0
					if w > 0 then
						local prevTemplate = prevRoom and (prevRoom:GetAttribute("Template") or prevRoom.Name)
						if Room.lastRoomName == name or prevTemplate == name then
							w = math.max(1, math.floor(w * 0.2))
						end
						if info.Direction and info.Direction == Room.lastTurnDirection then
							w = math.max(1, math.floor(w * 0.35))
						end
						if w > 12 then
							w = 12 + math.sqrt(w - 12)
						end
						w *= Room.GetLayoutWeight(name, rnum, prevTemplate)
						table.insert(entries, {name = name, weight = w, info = info})
						totalWeight = totalWeight + w
					end
				end
			end
		end
	end

	if totalWeight <= 0 or #entries == 0 then
		warn("[Room] No room entries available for Section:", tostring(sectionValue.Value))
		return nil
	end

	local attempts = 0
	local maxAttempts = 12
	while attempts < maxAttempts do
		attempts = attempts + 1
		local pick = Room.random:NextNumber(0, totalWeight)
		local cumulative = 0
		local chosenName
		for _, e in ipairs(entries) do
			cumulative = cumulative + e.weight
			if pick <= cumulative then
				chosenName = e.name
				break
			end
		end
		if not chosenName then
			chosenName = entries[#entries].name
		end
		local templateModel = templatesFolder and templatesFolder:FindFirstChild(chosenName)
		if not templateModel and templatesFolder ~= sectionFolder then
			warn("[Room] Template missing in MiniSection folder, falling back to section folder:", tostring(chosenName))
			templateModel = sectionFolder:FindFirstChild(chosenName)
		end
		if not templateModel then
			local newEntries, newTotal = {}, 0
			for _, e in ipairs(entries) do
				if e.name ~= chosenName then
					table.insert(newEntries, e)
					newTotal = newTotal + e.weight
				end
			end
			entries, totalWeight = newEntries, newTotal
			if totalWeight <= 0 then
				warn("[Room] No valid templates remain after filtering missing templates")
				return nil
			end
		else
			local usable = canUseTemplate(chosenName)
			if usable then
				markTemplate(chosenName)
				print("[Room] Chosen template:", tostring(chosenName), "MiniSection=", tostring(miniSection), "TurnAccum=", tostring(Room.turnValue))
				return templateModel
			end
		end
	end

	local fallbackFolder = templatesFolder
	if fallbackFolder then
		for _, v in ipairs(fallbackFolder:GetChildren()) do
			local usable = canUseTemplate(v.Name)
			if v:IsA("Model") and not isForbidden(v.Name) and usable then
				warn("[Room] Falling back to available template:", v.Name)
				markTemplate(v.Name)
				return v
			end
		end
	end

	if templatesFolder ~= sectionFolder then
		for _, v in ipairs(sectionFolder:GetChildren()) do
			local usable = canUseTemplate(v.Name)
			if v:IsA("Model") and not isForbidden(v.Name) and usable then
				warn("[Room] Falling back to section root template:", v.Name)
				markTemplate(v.Name)
				return v
			end
		end
	end

	warn("[Room] GetRandom failed after attempts:", attempts)
	return nil
end

function Room.Generate(prevRoom, miniSection, forcedTemplateName, desiredRnum, globalRoomCount)
	if Room.generationStopped then return nil end

	local previousStep = Room.step
	local prevLastTurnDirection = Room.lastTurnDirection
	local prevTurnValue = Room.turnValue
	local prevLastRoomName = Room.lastRoomName

	if not prevRoom or not prevRoom:IsA("Model") then
		local fallback = ReplicatedStorage:FindFirstChild("prevRoom")
		if fallback and fallback.Value and fallback.Value:IsA("Model") then
			prevRoom = fallback.Value
		else
			local startRoom = Workspace:FindFirstChild("StartRoom")
			if not startRoom then
				warn("[Room] No prevRoom and no StartRoom found")
				Room.step = previousStep
				Room.lastTurnDirection = prevLastTurnDirection
				Room.turnValue = prevTurnValue
				Room.lastRoomName = prevLastRoomName
				return nil
			end
			prevRoom = startRoom
		end
	end

	local rnumVal = ReplicatedStorage:FindFirstChild("rnum")
	if not rnumVal then
		warn("[Room] Generate: rnum missing in ReplicatedStorage")
		Room.step = previousStep
		Room.lastTurnDirection = prevLastTurnDirection
		Room.turnValue = prevTurnValue
		Room.lastRoomName = prevLastRoomName
		return nil
	end
	local rnum = desiredRnum or (rnumVal.Value + 1)
	Room.step = rnum

	local template = Room.GetRandom(prevRoom, miniSection, forcedTemplateName, rnum, globalRoomCount)
	if not template then
		warn("[Room] Generate: no template selected")
		Room.step = previousStep
		Room.lastTurnDirection = prevLastTurnDirection
		Room.turnValue = prevTurnValue
		Room.lastRoomName = prevLastRoomName
		return nil
	end

	local newRoom = template:Clone()

	pcall(function() newRoom:SetAttribute("Template", template.Name) end)
	if type(miniSection) == "string" and miniSection ~= "" then
		pcall(function() newRoom:SetAttribute("MiniSection", miniSection) end)
	end
	local sectionVal = ReplicatedStorage:FindFirstChild("Section")

	if not newRoom:FindFirstChild("Entrance") or not newRoom:FindFirstChild("Exit") then
		warn("[Room] Generated room missing Entrance or Exit:", newRoom.Name)
		newRoom:Destroy()
		Room.step = previousStep
		Room.lastTurnDirection = prevLastTurnDirection
		Room.turnValue = prevTurnValue
		Room.lastRoomName = prevLastRoomName
		return nil
	end

	if not prevRoom:FindFirstChild("Exit") then
		warn("[Room] PrevRoom missing Exit:", prevRoom.Name)
		newRoom:Destroy()
		Room.step = previousStep
		Room.lastTurnDirection = prevLastTurnDirection
		Room.turnValue = prevTurnValue
		Room.lastRoomName = prevLastRoomName
		return nil
	end
	newRoom.PrimaryPart = newRoom:FindFirstChild("Entrance") or newRoom.PrimaryPart
	pcall(function() newRoom:PivotTo(prevRoom.Exit.CFrame) end)

	local newBounds = getAABB(newRoom)

	-- Reject rooms that overlap already-placed rooms
	if newBounds and checkOverlap(newBounds) then
		warn("[Room] Overlap detected for template:", template.Name, "— rejecting and retrying")
		newRoom:Destroy()
		Room.step = previousStep
		Room.lastTurnDirection = prevLastTurnDirection
		Room.turnValue = prevTurnValue
		Room.lastRoomName = prevLastRoomName
		return nil
	end

	-- INTERIOR LOBBY BOUNDS SYSTEM (Allows doorway mesh-bleeding)
	if newBounds and Room.spawnBounds then
		-- Shrings the boundary check inward by 4 studs. 
		-- This explicitly allows your entrance seam/wall filler parts to overlap at the door frame,
		-- but blocks the room if it cuts deep into the actual lobby interior.
		local BLEED_ALLOWANCE = 4 
		local strictLobbyBounds = {
			min = Room.spawnBounds.min + Vector3.new(BLEED_ALLOWANCE, BLEED_ALLOWANCE, BLEED_ALLOWANCE),
			max = Room.spawnBounds.max - Vector3.new(BLEED_ALLOWANCE, BLEED_ALLOWANCE, BLEED_ALLOWANCE)
		}

		if overlaps(newBounds, strictLobbyBounds, 0) then
			warn("[Room] Room body deeply clips spawn zone interior, rejecting:", template.Name)
			newRoom:Destroy()
			Room.step = previousStep
			Room.lastTurnDirection = prevLastTurnDirection
			Room.turnValue = prevTurnValue
			Room.lastRoomName = prevLastRoomName
			return nil
		end
	end

	if newRoom:FindFirstChild("Entrance") and newRoom.Entrance:IsA("BasePart") then
		newRoom.Entrance.Transparency = 1
	end
	if newRoom:FindFirstChild("Exit") and newRoom.Exit:IsA("BasePart") then
		newRoom.Exit.Transparency = 1
	end

	local sectionTag = sectionVal and sectionVal.Value or "?"
	local roomNumberString = string.format("%03d", rnum)
	if newRoom:FindFirstChild("Sign") and newRoom.Sign:FindFirstChild("txt") and newRoom.Sign.txt:FindFirstChild("TextLabel") then
		newRoom.Sign.txt.TextLabel.Text = tostring(sectionTag) .. "-" .. roomNumberString
	end
	local sign = newRoom:FindFirstChild("Sign")
	if sign then
		for _, label in ipairs(sign:GetDescendants()) do
			if label:IsA("TextLabel") then
				label.Text = tostring(sectionTag) .. "-" .. roomNumberString
			end
		end
	end
	for _, label in ipairs(newRoom:GetDescendants()) do
		if label:IsA("TextLabel") and string.find(label.Text or "", "%a%-%d+") then
			label.Text = tostring(sectionTag) .. "-" .. roomNumberString
		end
	end

	local furnishedItems = {}
	local ok, result = pcall(function() return Room.furniture.FurnishRoom(newRoom) end)
	if ok and result then
		furnishedItems = result
	else
		warn("[Room] FurnishRoom error:", result)
	end

	local genFolder = Workspace:FindFirstChild("GeneratedRooms") or Instance.new("Folder", Workspace)
	genFolder.Name = "GeneratedRooms"
	newRoom.Parent = genFolder

	local info = {
		room = newRoom,
		number = rnum,
		template = template.Name,
		miniSection = miniSection,
		furnishedItems = furnishedItems,
		time = tick(),
	}
	table.insert(Room.GeneratedRoomsInfo, info)

	if newBounds then
		newBounds.room = newRoom
		table.insert(Room.placedBounds, newBounds)
	end
	pcall(function()
		newRoom:SetAttribute("PendingNumber", rnum)
		newRoom:SetAttribute("Section", sectionTag)
	end)

	local function burnout(lightModel, roomNumber)
		local DEAD_ROOM = 100
		local MAX_DIM_ROOM = 100

		local modelLight = lightModel:FindFirstChild("Light")
		if not (modelLight and modelLight:IsA("BasePart")) then return end

		if roomNumber >= DEAD_ROOM then
			lightModel:SetAttribute("LightDead", true)
			lightModel:SetAttribute("LightDimFactor", 0)
			local flickerFlag = lightModel:FindFirstChild("Flicker")
			if flickerFlag and flickerFlag:IsA("BoolValue") then flickerFlag.Value = false end
			return
		end

		local dimFactor = math.clamp(1 - (roomNumber / MAX_DIM_ROOM), 0, 1)
		lightModel:SetAttribute("LightDead", false)
		lightModel:SetAttribute("LightDimFactor", dimFactor)
	end

	for _, child in ipairs(newRoom:GetDescendants()) do
		if child:IsA("Model") and child:FindFirstChild("Light") and child:FindFirstChild("Flicker") then
			burnout(child, rnum)
		end
	end

	return newRoom, info
end

return Room
