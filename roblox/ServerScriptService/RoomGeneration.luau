--!strict
-- Perpetual Strict Room Generation System (Optimized for 1000+ Persistent Rooms with Auto-Recovery)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- Localized Globals for Micro-Optimization over 1,000+ persistent iterations
local table_insert = table.insert
local table_remove = table.remove
local math_random = math.random
local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local string_upper = string.upper
local string_lower = string.lower

-- System Types & Strict State Machine Definitions
type SystemState = "Idle" | "Preloading" | "Ready"
type TemplateEntry = { name: string, spawned: number }
type EntityConfig = { prob: number, id: number, name: string, force: boolean, spawnAtLobby: boolean?, useNewRoom: boolean? }

local State: { Idle: SystemState, Preloading: SystemState, Ready: SystemState } = {
	Idle = "Idle",
	Preloading = "Preloading",
	Ready = "Ready"
}

-- Modules
local roomModule = script:WaitForChild("Room")
local room = require(roomModule) :: any

-- Replication Values
local Section = ReplicatedStorage:WaitForChild("Section") :: StringValue
local rnum = ReplicatedStorage:WaitForChild("rnum") :: NumberValue
local prevRoomValue = ReplicatedStorage:WaitForChild("prevRoom") :: ObjectValue
local LatestRoom = ReplicatedStorage:WaitForChild("LatestRoom") :: ObjectValue
local generateBindable = ReplicatedStorage:WaitForChild("GenerateRoom") :: BindableEvent

-- Optional bindable for manual jumps
local jumpBindable = ReplicatedStorage:FindFirstChild("JumpToRoom") :: BindableEvent?

-- Internal Memory Management
local currentSystemState: SystemState = State.Idle
local isCommitLockActive = false
local prevRoom: Instance? = prevRoomValue.Value or Workspace:FindFirstChild("Lobbi")

-- Register Lobby Bounds immediately
local lobbyRoom = Workspace:FindFirstChild("Lobbi")
if lobbyRoom then
	room.RegisterSpawn(lobbyRoom)
else
	warn("[Main] Could not find Lobbi to register spawn bounds — spawn clip protection disabled")
end

-- Configuration Variables
local SectionsConfig: { [string]: any } = {}
local Sections: { string } = {}
local curSection: string? = nil
local usedSections: { [string]: boolean } = {}
local roomQueue: { TemplateEntry } = {}
local queueBuilt = false
local lastTemplate = ""

local nextRoom: Model? = nil
local nextInfo: any = nil

-- Safe MiniSection Initialization
local sectionValue = ReplicatedStorage:FindFirstChild("MiniSection") :: StringValue?
if not sectionValue then
	local newSec = Instance.new("StringValue")
	newSec.Name = "MiniSection"
	newSec.Parent = ReplicatedStorage
	sectionValue = newSec
end

-- Safely Require MiniSections Configuration
local mod = script:WaitForChild("Room"):FindFirstChild("MiniSections")
if mod and mod:IsA("ModuleScript") then
	local ok, result = pcall(require, mod)
	if ok and type(result) == "table" then
		SectionsConfig = result
	else
		warn("[Main] Failed to require MiniSections module:", result)
	end
else
	warn("[Main] Missing MiniSections ModuleScript")
end

--- ====================================================================
--- STRING & CONFIGURATION UTILITIES
--- ====================================================================

local function trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize(list: { any }): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, v in ipairs(list) do
		if type(v) == "string" then
			local s = trim(v)
			if s ~= "" and not seen[s] then
				seen[s] = true
				table_insert(out, s)
			end
		end
	end
	return out
end

local function resolve(sectionName: string): { string }
	sectionName = string_upper(trim(sectionName))
	if type(SectionsConfig) ~= "table" then return {} end

	local configAsAny: any = SectionsConfig
	if configAsAny[1] ~= nil then
		return normalize(configAsAny :: { any })
	end

	local list = SectionsConfig[sectionName]
	if list == nil then
		for k, v in pairs(SectionsConfig) do
			if string_upper(trim(tostring(k))) == sectionName then
				list = v
				break
			end
		end
		if list == nil then
			for _, v in pairs(SectionsConfig) do
				if type(v) == "table" then
					list = v
					break
				end
			end
		end
	end
	return normalize(list)
end

local function reload()
	local key = string_upper(trim(Section.Value))
	Sections = resolve(key)

	if #Sections == 0 then
		local roomsRoot = ServerStorage:FindFirstChild("Rooms")
		local folder = roomsRoot and roomsRoot:FindFirstChild(key)
		if folder then
			local fallback = {}
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("Folder") then table_insert(fallback, child.Name) end
			end
			fallback = normalize(fallback)
			if #fallback > 0 then
				Sections = fallback
			end
		end
	end
	usedSections = {}
	curSection = nil
	roomQueue = {}
	queueBuilt = false
	if sectionValue then sectionValue.Value = "" end
end

reload()

local function pickSection()
	if #Sections == 0 then
		curSection = nil
		if sectionValue then sectionValue.Value = "" end
		return
	end
	curSection = Sections[math_random(1, #Sections)]
	usedSections = {}
	roomQueue = {}
	queueBuilt = false
	if sectionValue then sectionValue.Value = curSection :: string end
end

local function shuffle(t: { any }): { any }
	for i = #t, 2, -1 do
		local j = math_random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

local function buildQueue()
	roomQueue = {}
	queueBuilt = true
	if type(curSection) ~= "string" or curSection == "" then return end

	local key = string_upper(trim(Section.Value))
	local roomsRoot = ServerStorage:FindFirstChild("Rooms")
	local folder = roomsRoot and roomsRoot:FindFirstChild(key) and roomsRoot[key]:FindFirstChild(curSection :: string)

	if not folder or not folder:IsA("Folder") then return end

	local templates: { TemplateEntry } = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			if not room.IsForbiddenForStep(child.Name, room.step) then
				table_insert(templates, { name = child.Name, spawned = 0 })
			end
		end
	end

	if #templates == 0 then return end
	roomQueue = shuffle(templates)
end

local function popTemplate(): string?
	if #roomQueue == 0 then return nil end
	local target = (rnum.Value or 0) + 1
	local totalWeight = 0
	local candidates = {}
	local previousTemplate = prevRoom and (prevRoom:GetAttribute("Template") or prevRoom.Name)
	for i, entry in ipairs(roomQueue) do
		if not room.IsForbiddenForStep(entry.name, target) and room.IsLayoutAllowed(entry.name, target) and (entry.name ~= lastTemplate or #roomQueue == 1) then
			local info = room.info[entry.name]
			local baseWeight = math.sqrt(math.max(1, info and info.Weight or 1))
			local weight = baseWeight * room.GetLayoutWeight(entry.name, target, previousTemplate)
			totalWeight += weight
			table_insert(candidates, {index = i, weight = weight})
		end
	end
	if totalWeight <= 0 then return nil end
	local pick = room.random:NextNumber(0, totalWeight)
	local index = candidates[#candidates].index
	for _, candidate in ipairs(candidates) do
		pick -= candidate.weight
		if pick <= 0 then index = candidate.index; break end
	end
	local entry = table_remove(roomQueue, index)
	entry.spawned += 1
	lastTemplate = entry.name
	if entry.spawned == 1 and room.random:NextNumber() < 0.25 then
		table_insert(roomQueue, entry)
	end
	return entry.name
end

local function nextSection(): string?
	if #Sections <= 1 then return curSection end
	if curSection ~= nil then usedSections[curSection :: string] = true end

	local candidates = {}
	for _, name in ipairs(Sections) do
		if name ~= curSection and usedSections[name] ~= true then table_insert(candidates, name) end
	end

	if #candidates == 0 then
		usedSections = {}
		if curSection ~= nil then usedSections[curSection :: string] = true end
		for _, name in ipairs(Sections) do
			if name ~= curSection then table_insert(candidates, name) end
		end
	end

	if #candidates > 0 then
		curSection = candidates[math_random(1, #candidates)]
		roomQueue = {}
		queueBuilt = false
		if sectionValue then sectionValue.Value = curSection :: string end
	end
	return curSection
end

--- ====================================================================
--- ENTITIES & DECORATION LOGIC
--- ====================================================================

local Entities: { [string]: { EntityConfig } } = {
	A = {
		{ prob = 15, id = 26,  name = "A-25",  force = true, spawnAtLobby = true },
		{ prob = 14, id = 60,  name = "A-60",  force = true, spawnAtLobby = true },
		{ prob = 12, id = 85,  name = "A-85",  force = true, spawnAtLobby = true },
		{ prob = 12, id = 200, name = "A-200", force = true, useNewRoom = false },
	},
	B = {
		{ prob = 20, id = 1, name = "B-30", force = true, useNewRoom = false },
	},
}

local Ranges = {
	{ name = "A", startAt = 1,   endBefore = 401 },
	{ name = "B", startAt = 401, endBefore = 801 },
}

local function getSectionName(n: number): string
	for _, s in ipairs(Ranges) do
		if n >= s.startAt and n < s.endBefore then return s.name end
	end
	return "A"
end

local function addDoor(r: Model): Model?
	if not r or not r:IsA("Model") then return nil end
	local doorSection = r:GetAttribute("ExitDoorSection") or r:GetAttribute("Section") or Section.Value
	if r:GetAttribute("Template") == "B-sectionentrance" or r.Name == "B-sectionentrance" then
		doorSection = "B"
	end
	local doorName = tostring(doorSection) .. "door"
	for _, child in ipairs(r:GetChildren()) do
		if child:IsA("Model") and string_lower(child.Name) == string_lower(doorName) then return child end
	end
	local template = ServerStorage:FindFirstChild(doorName)
	local exit = r:FindFirstChild("Exit")
	if not template or not exit or not exit:IsA("BasePart") then return nil end
	local clone = template:Clone() :: Model
	clone.Name = doorName
	clone.Parent = r
	pcall(function()
		clone:PivotTo(exit.CFrame)
	end)
	return clone
end

local function setLights(r: Model)
	local folder = r:FindFirstChild("Lights") or r:FindFirstChild("Light")
	if not folder then return end
	local lights = folder:GetChildren()
	if #lights == 0 then return end

	local maxFlickers = math_max(1, math_min(4, math_ceil(#lights * 0.35)))
	local flickerCount = 0

	if Section.Value == "B" then
		for _, light in ipairs(lights) do
			local roll = math_random()
			local flicker = light:FindFirstChild("Flicker")
			if roll < 0.30 then
				light:SetAttribute("LightDead", true)
				light:SetAttribute("LightDimFactor", 0)
				if flicker and flicker:IsA("BoolValue") then flicker.Value = false end
			elseif roll < 0.80 and flickerCount < maxFlickers then
				flickerCount += 1
				if flicker and flicker:IsA("BoolValue") then flicker.Value = true end
			else
				if flicker and flicker:IsA("BoolValue") then flicker.Value = false end
			end
		end
	else
		local chance = math_min(0.25 * (#lights / 9), 0.45)
		for _, light in ipairs(lights) do
			local flicker = light:FindFirstChild("Flicker")
			if flicker and flicker:IsA("BoolValue") then
				local enabled = flickerCount < maxFlickers and math_random() < chance
				if enabled then flickerCount += 1 end
				flicker.Value = enabled
			end
		end
	end
end

local function spawnEnts(startCF: CFrame, endCF: CFrame)
	local key = Section.Value
	local list = Entities[key]
	local folder = ServerStorage:FindFirstChild("Entities") and ServerStorage.Entities:FindFirstChild(key)
	if not folder or not list then return end

	for _, ent in ipairs(list) do
		local cf = ent.useNewRoom and endCF or startCF
		local lobby = Workspace:FindFirstChild("Lobbi")
		if ent.spawnAtLobby and lobby then
			local lobbyExit = lobby:FindFirstChild("Exit")
			if lobbyExit and lobbyExit:IsA("BasePart") then
				cf = lobbyExit.CFrame
			end
		end
		local template = folder:FindFirstChild(ent.name)
		if template and cf then
			room.RandomizedSpawn(ent.prob, ent.id, template, cf, ent.force)
		end
	end
end

--- ====================================================================
--- MEMORY PIPELINE CONTROL ENGINE (WITH PLAYTEST AUTO-ROLLBACK)
--- ====================================================================

local function clearPreload()
	if nextRoom then
		-- Fire explicit unbinding routines in the module script to avoid memory leaks
		if type(room.ForgetGeneratedRoom) == "function" then
			pcall(function() room.ForgetGeneratedRoom(nextRoom) end)
		end
		nextRoom:Destroy()
	end
	if prevRoom then
		pcall(function() room.SyncStateFromRoom(prevRoom) end)
	end
	nextRoom = nil
	nextInfo = nil
	currentSystemState = State.Idle
end

local function waitForPreload(): boolean
	if currentSystemState == State.Ready and nextRoom ~= nil then return true end

	local waited = 0
	while currentSystemState == State.Preloading and waited < 10 do
		task.wait(0.1)
		waited += 0.1
	end
	return currentSystemState == State.Ready and nextRoom ~= nil
end

local function preloadIsStale(): (boolean, number, number)
	if not nextRoom then return false, 0, 0 end
	local expectedNumber = (rnum.Value or 0) + 1
	local preloadedNumber = nextInfo and nextInfo.number or nextRoom:GetAttribute("PendingNumber") or 0
	return preloadedNumber ~= expectedNumber, preloadedNumber, expectedNumber
end

local function preload()
	if currentSystemState ~= State.Idle or nextRoom ~= nil then return end
	currentSystemState = State.Preloading

	task.defer(function()
		local target = (rnum.Value or 0) + 1
		local desired = getSectionName(target)

		if desired ~= Section.Value then
			Section.Value = desired
			reload()
			pickSection()
		end
		if curSection == nil then
			if #Sections == 0 then reload() end
			pickSection()
		end

		local generatedModel: Model? = nil
		local generatedInfo: any = nil

		for attempt = 1, 25 do
			-- Continuous staleness checking: Did a developer modify rnum mid-generation loop?
			if (rnum.Value or 0) + 1 ~= target then
				if generatedModel then generatedModel:Destroy() end
				currentSystemState = State.Idle
				return
			end

			if curSection ~= nil and not queueBuilt then buildQueue() end
			if curSection ~= nil and queueBuilt and #roomQueue == 0 then
				nextSection()
				buildQueue()
			end

			local t = popTemplate()
			if not t and curSection ~= nil then
				nextSection()
				buildQueue()
				t = popTemplate()
			end

			generatedModel, generatedInfo = room.Generate(prevRoom, curSection, t, target, target)
			if generatedModel then break end

			if curSection ~= nil and #roomQueue == 0 then
				nextSection()
				buildQueue()
			end
		end

		if currentSystemState ~= State.Preloading then
			if generatedModel then generatedModel:Destroy() end
			return
		end

		if generatedModel then
			addDoor(generatedModel)
			setLights(generatedModel)
			generatedModel:SetAttribute("PendingNumber", target)
			nextRoom = generatedModel
			nextInfo = generatedInfo
			currentSystemState = State.Ready
		else
			-- DYNAMIC ROLLBACK: Avoid hardlocking the generation system during studio testing!
			warn(string.format("[Main Recovery] Room generation failed/stale at target index %d. Resetting states and self-healing...", target))
			room.generationStopped = false
			currentSystemState = State.Idle

			-- Force a tiny wait interval and attempt to self-heal the pipeline automatically
			task.wait(0.5)
			preload()
		end
	end)
end

local function commit()
	-- Playtest self-healing toggle check
	if room.generationStopped then 
		warn("[Main Recovery] Pipeline was stopped. Forcing clear & re-enabling for testing.")
		room.generationStopped = false
		clearPreload()
	end

	if isCommitLockActive then return end
	isCommitLockActive = true

	local stale, preloadedNumber, expectedNumber = preloadIsStale()
	if stale then 
		warn(string.format("[Main Recovery] Detected modified rnum (%d). Expected: %d. Re-aligning generation pipeline.", preloadedNumber, expectedNumber))
		clearPreload() 
	end

	if currentSystemState ~= State.Ready or not nextRoom then
		if not waitForPreload() then
			isCommitLockActive = false
			-- If wait failed, dynamically rebuild configuration and kickstart pipeline again
			preload()
			return
		end
	end

	stale, preloadedNumber, expectedNumber = preloadIsStale()
	if stale then
		clearPreload()
		if not waitForPreload() then
			isCommitLockActive = false
			preload()
			return
		end
	end

	local committed = nextRoom
	if not committed then
		isCommitLockActive = false
		preload()
		return
	end

	rnum.Value += 1
	local oldRoom = prevRoom
	room.ApplyRoomNumber(committed, rnum.Value, Section.Value)

	prevRoom = committed
	prevRoomValue.Value = committed
	LatestRoom.Value = committed
	committed.Name = tostring(rnum.Value)

	if oldRoom and committed then
		local oldExit = oldRoom:FindFirstChild("Exit")
		local committedExit = committed:FindFirstChild("Exit")
		if oldExit and oldExit:IsA("BasePart") and committedExit and committedExit:IsA("BasePart") then
			spawnEnts(oldExit.CFrame, committedExit.CFrame)
		end
	end

	nextRoom = nil
	nextInfo = nil
	currentSystemState = State.Idle
	isCommitLockActive = false

	preload()
end

--- ====================================================================
--- MANUAL ROOM JUMP
--- ====================================================================

local function jumpToRoom(targetNumber: number, anchorRoom: Model?)
	if type(targetNumber) ~= "number" or targetNumber < 1 then
		warn("[Main] jumpToRoom: invalid targetNumber", targetNumber)
		return
	end

	local waited = 0
	while isCommitLockActive and waited < 5 do
		task.wait(0.05)
		waited += 0.05
	end
	if isCommitLockActive then
		warn("[Main] jumpToRoom: commit lock still held after timeout, forcing unlock")
		isCommitLockActive = false
	end

	clearPreload()

	if anchorRoom then
		prevRoom = anchorRoom
		prevRoomValue.Value = anchorRoom
		LatestRoom.Value = anchorRoom
	end

	rnum.Value = targetNumber - 1

	local desired = getSectionName(targetNumber)
	if desired ~= Section.Value then
		Section.Value = desired
	end
	reload()
	pickSection()

	room.generationStopped = false
	preload()

	print(string.format("[Main] jumpToRoom → targeting room %d (section %s)", targetNumber, Section.Value))
end

--- ====================================================================
--- INITIALIZATION & LISTENERS
--- ====================================================================

if generateBindable and generateBindable:IsA("BindableEvent") then
	generateBindable.Event:Connect(function()
		task.spawn(commit)
	end)
else
	warn("[Main] GenerateRoom is missing or not a BindableEvent")
end

if jumpBindable and jumpBindable:IsA("BindableEvent") then
	jumpBindable.Event:Connect(function(targetNumber: number, anchorRoom: Model?)
		task.spawn(jumpToRoom, targetNumber, anchorRoom)
	end)
end

-- Fallback dynamic detector for playtesting. If you manually change rnum in the properties pane,
-- this listener cleanly resets the look-ahead pipeline without breaking everything.
rnum.Changed:Connect(function(newValue)
	if not isCommitLockActive and currentSystemState == State.Ready then
		local stale, preloadedNumber, expectedNumber = preloadIsStale()
		if stale then
			clearPreload()
			preload()
		end
	end
end)

preload()

return {
	JumpToRoom = jumpToRoom,
}
