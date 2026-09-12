local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local PROFILE_STORE_NAME = "RoomsTelemetryPreferences_v1"
local TELEMETRY_STORE_NAME = "RoomsTelemetryAggregates_v1"
local TELEMETRY_KEY = "global"
local SCAN_INTERVAL = 1
local BACKEND_REPUBLISH_INTERVAL = 600
local BACKEND_STARTUP_REPUBLISH_DELAY = 30

local profileServiceModule = nil
local serverModules = ServerStorage:FindFirstChild("ServerModules")
if serverModules and serverModules:FindFirstChild("Misc") then
	profileServiceModule = serverModules.Misc:FindFirstChild("ProfileService")
end
if not profileServiceModule and ServerStorage:FindFirstChild("Misc") then
	profileServiceModule = ServerStorage.Misc:FindFirstChild("ProfileService")
end
assert(profileServiceModule, "[Telemetry] ProfileService module not found")

local ProfileService = require(profileServiceModule)
local ProfileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, {
	TelemetryPromptShown = false,
})
local TelemetryStore = DataStoreService:GetDataStore(TELEMETRY_STORE_NAME)

local consentRemote = ReplicatedStorage:FindFirstChild("TelemetryConsent")
if not consentRemote then
	consentRemote = Instance.new("RemoteEvent")
	consentRemote.Name = "TelemetryConsent"
	consentRemote.Parent = ReplicatedStorage
end

local deathEvent = ServerStorage:FindFirstChild("TelemetryDeathEvent")
if not deathEvent then
	deathEvent = Instance.new("BindableEvent")
	deathEvent.Name = "TelemetryDeathEvent"
	deathEvent.Parent = ServerStorage
end

local profiles = {}
local sessions = {}
local pendingSaves = 0
local consentTimes = {}

local debugEnabledValue = ServerStorage:FindFirstChild("TelemetryDebugEnabled")
if not debugEnabledValue then
	debugEnabledValue = Instance.new("BoolValue")
	debugEnabledValue.Name = "TelemetryDebugEnabled"
	debugEnabledValue.Value = false
	debugEnabledValue.Parent = ServerStorage
end

local backendUrlValue = ServerStorage:FindFirstChild("AnalyticsBackendUrl") or ReplicatedStorage:FindFirstChild("AnalyticsBackendUrl")
if not backendUrlValue then
	backendUrlValue = Instance.new("StringValue")
	backendUrlValue.Name = "AnalyticsBackendUrl"
	backendUrlValue.Value = ""
	backendUrlValue.Parent = ServerStorage
end

local backendTokenValue = ServerStorage:FindFirstChild("AnalyticsBackendToken")
if not backendTokenValue then
	backendTokenValue = Instance.new("StringValue")
	backendTokenValue.Name = "AnalyticsBackendToken"
	backendTokenValue.Value = ""
	backendTokenValue.Parent = ServerStorage
end

local function debugLog(...)
	if debugEnabledValue.Value then
		print("[Telemetry]", ...)
	end
end

local function aggregateSummary(data)
	if type(data) ~= "table" then
		return "non-table payload"
	end
	return string.format(
		"sessions=%s deaths=%s avgPlaytime=%s avgRooms=%s",
		tostring(data.TotalSessions or 1),
		tostring(data.TotalDeaths or data.deaths or 0),
		tostring(math.floor(tonumber(data.AveragePlaytimeSeconds or data.playtimeSeconds or 0) or 0)),
		tostring(math.floor(tonumber(data.AverageRoomsTravelledBeforeLeave or data.roomsTravelled or 0) or 0))
	)
end

local function utcNow()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function utcHour(timestamp)
	return os.date("!%Y-%m-%dT%H:00:00Z", timestamp or os.time())
end

local function utcDay(timestamp)
	return os.date("!%Y-%m-%d", timestamp or os.time())
end

local function safeKey(value)
	value = tostring(value or "Unknown")
	value = value:gsub("[^%w_%-%.]", "_")
	if value == "" then
		return "Unknown"
	end
	return string.sub(value, 1, 64)
end

local function dictCount(dict)
	local count = 0
	for _ in pairs(dict) do
		count += 1
	end
	return count
end

local function increment(dict, key, amount)
	key = safeKey(key)
	dict[key] = (tonumber(dict[key]) or 0) + (amount or 1)
end

local function incrementRaw(dict, key, amount)
	key = tostring(key or "Unknown")
	if key == "" then key = "Unknown" end
	key = string.sub(key, 1, 80)
	dict[key] = (tonumber(dict[key]) or 0) + (amount or 1)
end

local function getEnvironmentCategory()
	if RunService:IsStudio() then
		return "InStudio"
	end
	return "Game"
end

local function getAccountAgeGroup(player)
	local days = tonumber(player.AccountAge)
	if not days then
		return "Unknown"
	end
	if days < 7 then
		return "0-6 days"
	elseif days < 30 then
		return "7-29 days"
	elseif days < 180 then
		return "30-179 days"
	elseif days < 365 then
		return "180-364 days"
	elseif days < 1095 then
		return "1-2 years"
	end
	return "3+ years"
end

local function getRoomNumber(room)
	if not room then return nil end
	return tonumber(room:GetAttribute("PendingNumber")) or tonumber(room.Name)
end

local function getRoot(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function pointInsideModel(model, point)
	if not model or not model:IsA("Model") then return false end
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then return false end
	local localPoint = cf:PointToObjectSpace(point)
	local margin = 4
	return math.abs(localPoint.X) <= size.X / 2 + margin
		and math.abs(localPoint.Y) <= size.Y / 2 + margin
		and math.abs(localPoint.Z) <= size.Z / 2 + margin
end

local function getPlayerRoom(player)
	local root = getRoot(player)
	if not root then return nil end

	local generatedRooms = workspace:FindFirstChild("GeneratedRooms")
	if not generatedRooms then return nil end

	local bestRoom = nil
	local bestNumber = -math.huge
	for _, room in ipairs(generatedRooms:GetChildren()) do
		if room:IsA("Model") and pointInsideModel(room, root.Position) then
			local number = getRoomNumber(room) or 0
			if number > bestNumber then
				bestRoom = room
				bestNumber = number
			end
		end
	end
	return bestRoom
end

local function markRoomVisit(player, room)
	local session = sessions[player]
	if not session or not session.enabled or not room then return end

	local number = getRoomNumber(room)
	if number then
		session.visitedRooms[number] = true
		if number > (session.maxRoomNumber or 0) then
			debugLog(player.Name, "entered room", number)
		end
		session.maxRoomNumber = math.max(session.maxRoomNumber or 0, number)
	end

	local section = room:GetAttribute("Section")
	if section then
		local sectionKey = safeKey(section)
		if not session.sections[sectionKey] then
			debugLog(player.Name, "crossed section", sectionKey)
		end
		session.sections[sectionKey] = true
	end

	local miniSection = room:GetAttribute("MiniSection")
	if miniSection then
		local miniSectionKey = safeKey(miniSection)
		if not session.miniSections[miniSectionKey] then
			debugLog(player.Name, "crossed mini-section", miniSectionKey)
		end
		session.miniSections[miniSectionKey] = true
	end
end

local function attachDeathWatcher(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 10)
	end
	if not humanoid then return end

	humanoid.Died:Connect(function()
		task.defer(function()
			local session = sessions[player]
			if not session or not session.enabled or session.lastDeathHumanoid == humanoid then return end
			session.lastDeathHumanoid = humanoid
			local cause = humanoid:GetAttribute("TelemetryDeathCause") or "Unknown"
			session.deaths += 1
			increment(session.deathCauses, cause)
		end)
	end)
end

local function startScanner(player)
	task.spawn(function()
		while sessions[player] do
			local session = sessions[player]
			if session.enabled then
				markRoomVisit(player, getPlayerRoom(player))
			end
			task.wait(SCAN_INTERVAL)
		end
	end)
end

local function promptIfNeeded(player)
	local profile = profiles[player]
	if not profile or profile.Data.TelemetryPromptShown then return end

	profile.Data.TelemetryPromptShown = true
	debugLog(player.Name, "showing telemetry consent prompt")
	consentRemote:FireClient(player, "Prompt", {
		title = "Help improve Rooms",
		body = "We collect anonymized gameplay telemetry: join and leave times in UTC hour buckets, playtime length, death counts and what caused them, rooms traveled before leaving, sections crossed, broad account-age group, and whether the session came from Studio or the live game. We use this only to improve the game for everyone. Results are anonymized and are not stored with your Roblox user ID or username.",
		accept = "Share anonymous stats",
		decline = "Opt out",
	})
end

local function createSession(player)
	local profile = profiles[player]
	local enabled = profile and profile.Data.TelemetryConsent == true
	local now = os.time()

	sessions[player] = {
		enabled = enabled,
		id = HttpService:GenerateGUID(false),
		joinTimestamp = now,
		joinUtc = utcNow(),
		joinHourUtc = utcHour(now),
		deaths = 0,
		deathCauses = {},
		maxRoomNumber = 0,
		visitedRooms = {},
		sections = {},
		miniSections = {},
		environment = getEnvironmentCategory(),
		accountAgeGroup = getAccountAgeGroup(player),
		pendingDeathCause = nil,
	}
	debugLog(player.Name, "session created", "enabled", enabled, "joinUtc", sessions[player].joinUtc, "environment", sessions[player].environment, "accountAgeGroup", sessions[player].accountAgeGroup)
end

local function aggregateSession(session, leaveTimestamp)
	local playtime = math.max(0, leaveTimestamp - session.joinTimestamp)
	local roomsTravelled = dictCount(session.visitedRooms)
	local sectionsCrossed = dictCount(session.sections)
	local miniSectionsCrossed = dictCount(session.miniSections)

	return {
		joinUtc = session.joinUtc,
		joinHourUtc = session.joinHourUtc,
		leaveUtc = utcNow(),
		leaveHourUtc = utcHour(leaveTimestamp),
		dayUtc = utcDay(leaveTimestamp),
		playtimeSeconds = playtime,
		deaths = session.deaths,
		deathCauses = session.deathCauses,
		roomsTravelled = roomsTravelled,
		sections = session.sections,
		miniSections = session.miniSections,
		sectionsCrossed = sectionsCrossed,
		miniSectionsCrossed = miniSectionsCrossed,
		environment = session.environment or getEnvironmentCategory(),
		accountAgeGroup = session.accountAgeGroup or "Unknown",
	}
end

local function updateAggregate(data, sessionData, skipBreakdowns)
	data = type(data) == "table" and data or {}
	data.Version = 1
	data.TotalSessions = (tonumber(data.TotalSessions) or 0) + 1
	data.Revision = data.TotalSessions
	data.TotalPlaytimeSeconds = (tonumber(data.TotalPlaytimeSeconds) or 0) + sessionData.playtimeSeconds
	data.AveragePlaytimeSeconds = data.TotalPlaytimeSeconds / data.TotalSessions
	data.TotalDeaths = (tonumber(data.TotalDeaths) or 0) + sessionData.deaths
	data.TotalRoomsTravelled = (tonumber(data.TotalRoomsTravelled) or 0) + sessionData.roomsTravelled
	data.AverageRoomsTravelledBeforeLeave = data.TotalRoomsTravelled / data.TotalSessions
	data.TotalSectionsCrossed = (tonumber(data.TotalSectionsCrossed) or 0) + sessionData.sectionsCrossed
	data.AverageSectionsCrossedBeforeLeave = data.TotalSectionsCrossed / data.TotalSessions
	data.TotalMiniSectionsCrossed = (tonumber(data.TotalMiniSectionsCrossed) or 0) + sessionData.miniSectionsCrossed
	data.AverageMiniSectionsCrossedBeforeLeave = data.TotalMiniSectionsCrossed / data.TotalSessions
	data.LastUpdatedUtc = sessionData.leaveUtc

	data.JoinHoursUtc = type(data.JoinHoursUtc) == "table" and data.JoinHoursUtc or {}
	data.LeaveHoursUtc = type(data.LeaveHoursUtc) == "table" and data.LeaveHoursUtc or {}
	data.SessionsByDayUtc = type(data.SessionsByDayUtc) == "table" and data.SessionsByDayUtc or {}
	data.DeathCauses = type(data.DeathCauses) == "table" and data.DeathCauses or {}
	data.SectionsCrossed = type(data.SectionsCrossed) == "table" and data.SectionsCrossed or {}
	data.MiniSectionsCrossed = type(data.MiniSectionsCrossed) == "table" and data.MiniSectionsCrossed or {}
	data.Environments = type(data.Environments) == "table" and data.Environments or {}
	data.AccountAgeGroups = type(data.AccountAgeGroups) == "table" and data.AccountAgeGroups or {}

	incrementRaw(data.JoinHoursUtc, sessionData.joinHourUtc)
	incrementRaw(data.LeaveHoursUtc, sessionData.leaveHourUtc)
	incrementRaw(data.SessionsByDayUtc, sessionData.dayUtc)
	increment(data.Environments, sessionData.environment or "Game")
	incrementRaw(data.AccountAgeGroups, sessionData.accountAgeGroup or "Unknown")

	for cause, amount in pairs(sessionData.deathCauses) do
		increment(data.DeathCauses, cause, amount)
	end
	for section in pairs(sessionData.sections) do
		increment(data.SectionsCrossed, section)
	end
	for miniSection in pairs(sessionData.miniSections) do
		increment(data.MiniSectionsCrossed, miniSection)
	end

	if not skipBreakdowns then
		local environment = safeKey(sessionData.environment or "Game")
		data.Categories = type(data.Categories) == "table" and data.Categories or {}
		data.Categories[environment] = updateAggregate(data.Categories[environment], sessionData, true)
	end

	return data
end

local function postToBackend(aggregate)
	local url, token = backendUrlValue.Value, backendTokenValue.Value
	if url == "" or token == "" then return false end
	local encoded, payload = pcall(HttpService.JSONEncode, HttpService, aggregate)
	if not encoded then warn("[Telemetry] Could not encode aggregate"); return false end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return HttpService:RequestAsync({
				Url = url, Method = "POST",
				Headers = {["Content-Type"] = "application/json", ["X-Rooms-Token"] = token},
				Body = payload,
			})
		end)
		if ok and result.Success then
			script:SetAttribute("LastUploadUtc", utcNow())
			script:SetAttribute("UploadFailures", 0)
			return true
		end
		script:SetAttribute("UploadFailures", (script:GetAttribute("UploadFailures") or 0) + 1)
		if ok and result.StatusCode >= 400 and result.StatusCode < 500 and result.StatusCode ~= 429 then
			warn("[Telemetry] Backend rejected upload", result.StatusCode)
			return false
		end
		if attempt < 3 then task.wait(2 ^ (attempt - 1)) end
	end
	warn("[Telemetry] Upload failed after retries; stored aggregate will be republished")
	return false
end

local function republishStoredAggregate(reason)
	local url = backendUrlValue.Value
	if type(url) ~= "string" or url == "" then
		debugLog("skipping backend republish; AnalyticsBackendUrl is empty")
		return
	end

	local ok, aggregate = pcall(function()
		return TelemetryStore:GetAsync(TELEMETRY_KEY)
	end)
	if not ok then
		warn("[Telemetry] Failed to load aggregate for backend republish:", aggregate)
		return
	end
	if type(aggregate) ~= "table" or (tonumber(aggregate.TotalSessions) or 0) <= 0 then
		debugLog("skipping backend republish; no aggregate sessions yet")
		return
	end

	debugLog("republishing stored aggregate", reason or "manual", aggregateSummary(aggregate))
	aggregate.RecentSessionIds = nil
	postToBackend(aggregate)
end

local function startBackendRepublisher()
	task.spawn(function()
		task.wait(BACKEND_STARTUP_REPUBLISH_DELAY)
		republishStoredAggregate("startup")

		while true do
			task.wait(BACKEND_REPUBLISH_INTERVAL)
			republishStoredAggregate("interval")
		end
	end)
end

local function saveSession(player)
	local session = sessions[player]
	if not session then return end

	markRoomVisit(player, getPlayerRoom(player))
	sessions[player] = nil

	if not session.enabled then return end

	local sessionData = aggregateSession(session, os.time())
	debugLog(player.Name, "saving session", aggregateSummary(sessionData))
	pendingSaves += 1
	local savedAggregate
	local lastError
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return TelemetryStore:UpdateAsync(TELEMETRY_KEY, function(data)
				data = type(data) == "table" and data or {}
				data.RecentSessionIds = type(data.RecentSessionIds) == "table" and data.RecentSessionIds or {}
				if data.RecentSessionIds[session.id] then return data end
				local updated = updateAggregate(data, sessionData)
				updated.RecentSessionIds[session.id] = os.time()
				for id, timestamp in pairs(updated.RecentSessionIds) do
					if os.time() - timestamp > 3600 then updated.RecentSessionIds[id] = nil end
				end
				return updated
			end)
		end)
		if ok then savedAggregate = result; break end
		lastError = result
		if attempt < 3 then task.wait(attempt) end
	end
	if savedAggregate then
		-- Retry identifiers stay inside DataStore and are never sent to the website.
		savedAggregate.RecentSessionIds = nil
		postToBackend(savedAggregate)
	else
		warn("[Telemetry] Aggregate save failed after retries:", lastError)
	end
	pendingSaves -= 1
end

local function loadProfile(player)
	debugLog(player.Name, "loading telemetry profile")
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId, "ForceLoad")
	if not profile then
		player:Kick("Unable to load player data. Please rejoin.")
		return nil
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile:ListenToRelease(function()
		profiles[player] = nil
		sessions[player] = nil
		if player.Parent == Players then
			player:Kick("Your data was opened from another server. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:Release()
		return nil
	end

	profiles[player] = profile
	player:SetAttribute("TelemetryConsent", profile.Data.TelemetryConsent == true)
	debugLog(player.Name, "telemetry profile loaded", "consent", profile.Data.TelemetryConsent, "promptShown", profile.Data.TelemetryPromptShown)
	return profile
end

consentRemote.OnServerEvent:Connect(function(player, action, value)
	local profile = profiles[player]
	if action == "Ready" then
		promptIfNeeded(player)
		return
	end
	if action ~= "SetPreference" or not profile or type(value) ~= "boolean" then return end
	if os.clock() - (consentTimes[player] or -math.huge) < 1 then return end
	consentTimes[player] = os.clock()

	local consent = value == true
	profile.Data.TelemetryConsent = consent
	profile.Data.TelemetryPromptShown = true
	player:SetAttribute("TelemetryConsent", consent)
	profile:Save()
	debugLog(player.Name, "telemetry preference saved", consent)

	local session = sessions[player]
	if session then
		if session.enabled ~= consent then createSession(player) end
	end
end)

deathEvent.Event:Connect(function(player, cause)
	local session = sessions[player]
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not session or not session.enabled or not humanoid then return end
	humanoid:SetAttribute("TelemetryDeathCause", safeKey(cause))
end)

Players.PlayerAdded:Connect(function(player)
	local profile = loadProfile(player)
	if not profile then return end

	createSession(player)
	startScanner(player)

	player.CharacterAdded:Connect(function(character)
		attachDeathWatcher(player, character)
	end)
	if player.Character then
		attachDeathWatcher(player, player.Character)
	end

	task.defer(function()
		task.wait(2)
		promptIfNeeded(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	consentTimes[player] = nil
	saveSession(player)

	local profile = profiles[player]
	if profile then
		profiles[player] = nil
		profile:Release()
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			saveSession(player)
			local profile = profiles[player]
			if profile then profiles[player] = nil; profile:Release() end
		end)
	end
	task.wait()
	local deadline = os.clock() + 25
	while pendingSaves > 0 and os.clock() < deadline do task.wait(0.1) end
end)

startBackendRepublisher()
