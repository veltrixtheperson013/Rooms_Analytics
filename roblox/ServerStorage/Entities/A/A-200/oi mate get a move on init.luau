--[[

⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣤⣤⡤⠀⠀⠀⠀⠀⠀⠀⣠⠾⠛⣆⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⢀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⠶⠛⠉⠀⣰⠋⠀⠀⠀⠀⠀⢀⣤⠞⠁⠀⠀⢹⡄⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣾⠉⠉⠉⠙⠛⠒⠶⢤⣄⡀⠀⠀⠀⢀⡴⠋⠀⠀⠀⠀⣼⣃⣀⣀⣀⠀⣀⡴⠋⠁⠀⠀⠀⠀⠈⣧⠀⠀⠀⠀
⠀⠀⠀⠀⠀⢹⡀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠲⣄⣠⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠻⣇⡀⠀⠀⠀⠀⠀⠀⠀⣿⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠘⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢽⠄⠀⠀⠀⠀⠀⠀⠀⠾⠦⢤⣤⣤⣼⡧⠀⠀⠀⠀⠀⠀⠀⣼⠀⠀⠀⠀
⠀⠀⣰⣦⡴⠚⢿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⠀⠀⠀⠀
⠀⣰⠇⠉⠀⠀⠘⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀fucking gooner⠀⠀⠀⠀⠀⠀⡟⠀⠀⠀⠀
⠀⣿⠀⠀⠀⠀⠀⠹⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⡇⠀⠀⠀⠀
⠀⣿⠀⠀⠀⠀⠀⠀⢿⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣀⣀⣀⣀⣀⡀⠀⠀⣤⣤⣤⣄⣀⣀⣀⣀⣀⠀⠀⠀⣸⠀⠀⠀⠀⠀
⠀⠹⣖⠀⠀⠀⠀⠀⠈⣧⠀⠀⠀⠐⢺⡟⠉⠉⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⠉⠙⣏⠙⢃⡏⠀⠀⠀⠀⠀
⠀⠀⠹⣦⠀⠀⠀⠀⠀⠘⢷⡀⠀⠀⢸⠀⠀⠰⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⢹⣿⣿⣿⣿⣿⣿⠆⠀⢸⡀⠈⠉⠓⠶⣄⡀⠀
⠀⠀⠐⣾⠷⣄⠀⠀⠀⣠⠴⠟⠲⠶⠼⣧⡀⠀⢻⣿⣿⣿⣿⡿⠃⠀⠀⠀⠈⢿⣿⣿⣿⣿⠟⠀⢀⡾⠀⠀⠀⠀⠀⣈⣹⡄
⠀⠀⠀⠈⢷⡀⠀⠀⠾⠧⢤⣄⣀⡀⠀⠈⠛⠀⠀⠉⠛⠛⠉⠀⠀⠀⠲⠒⠀⠀⢈⡩⠉⠁⠀⠀⠞⠁⠀⠀⠀⢻⡍⠉⠀⠀
⠀⠀⠀⠀⠈⣷⠀⠀⠀⠀⠀⠀⡼⠁⠀⠀⢀⣤⣔⣒⡶⠀⠀⢧⣤⠴⠛⠲⠤⠴⠚⠁⢠⡴⣔⣲⠆⠀⢀⠀⠀⢸⡇⠀⠀⠀
⠀⠀⠀⠀⠀⣾⠀⠀⠀⠀⠀⣼⠁⠀⠀⠀⠉⠒⠈⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠂⠀⠀⢀⣴⠛⠳⣆⣸⠇⠀⠀⠀
⠀⠀⠀⡀⣰⠃⠀⠀⠀⠀⠀⣇⣠⠶⠋⠓⢶⡶⣶⠶⠒⠲⢦⡀⠀⠀⠀⠀⠀⠀⣀⣀⣤⡤⠴⠞⠋⠀⠀⠀⠈⠉⠀⠀⠀⠀
⠀⠀⣼⡿⠁⠀⠀⠀⠀⠀⠐⠛⠁⠀⠀⢀⡞⢰⠇⠀⠀⠀⠀⠙⠦⠀⠀⠀⠀⣼⣇⣁⣀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⣰⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣋⡄⣿⠀⠀⠀⠀⠀⠀⣧⠀⠀⠠⢿⣟⣷⠧⠀⠈⠙⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣩⡽⠋⠀⢻⠀⠀⠀⠀⠀⠀⢹⡄⠀⠈⠻⠻⠦⣄⠀⠀⠀⠘⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡼⠋⠀⠀⠀⢸⡇⠀⠀⠀⠀⠀⠈⣧⠀⠀⠀⠀⣿⠛⠇⠀⠀⠀⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⢻⡄⠀⠀⠀⠀⠀⠀⠀⠀⣸⢁⡀⠀⠀⠀⢸⢿⡀⠀⠀⠀⠀⠀⢹⡆⠀⢸⣷⣿⠀⠀⠀⠀⠀⢸⡄⠀⠀⠀⠀⠀⠀⠀⠀
⣦⣜⣧⠀⠀⠀⠀⠀⠀⠀⠀⠿⢾⣇⠀⠀⢀⡾⠘⣧⠀⠀⠀⠀⠀⠀⢻⡀⠈⢸⡀⠀⠀⠀⠀⠀⢸⡇⠀⠀⠀⠀⠀⠀⠀⠀
⠘⢯⡹⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⢙⣦⠴⠋⠀⠀⢻⡆⠀⠀⠀⠀⠀⠈⣧⠀⢸⡇⠀⠀⠀⠀⠀⢸⠃⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠈⠻⣮⠳⣄⠀⠀⠀⠀⠀⣠⡴⠋⠁⠀⠀⡀⠀⠀⢿⡀⠀⠀⠀⠀⠀⠘⣆⠘⡇⠀⠀⠀⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠈⠙⠶⣭⣒⣠⣠⡾⠋⠀⠀⠀⠀⠀⠙⠲⢦⣌⢷⡀⠀⠀⠀⠀⠀⠹⡆⣷⠀⠀⠀⠀⠀⣽⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠈⣽⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⢷⣀⠀⠀⠀⠀⠀⢻⣿⠀⠀⠀⠀⠀⣿⠛⠲⠦⣄⡀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⣾⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⣦⠀⠀⠀⠀⠈⣿⠀⠀⠀⠀⠀⣿⠀⠀⠀⠀⠙⢳⡄⠀⠀
⠀⠀⠀⠀⠀⠀⢰⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢷⡀⠀⠀⠀⠸⡆⠀⠀⠀⠀⣿⠀⠀⠀⠀⠀⠀⠹⣄⠀
⠀⠀⠀⠀⠀⠀⢸⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠻⡄⠀⠀⠀⢻⡀⠀⠀⠀⡏⠀⠀⠀⠀⠀⠀⠀⠹⣆
⠀⠀⠀⠀⠀⠀⠸⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⡀⠀⠀⠈⢷⡀⠀⢰⡇⠀⠀⠀⠀⠀⠀⠀⠀⢹
⠀⠀⠀⠀⠀⠀⣰⠿⣏⣆⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣧⠀⠀⠀⠈⠳⣄⠘⠷⠶⢤⣄⠀⠀⠀⠀⢀⡿
⠀⠀⠀⠀⠀⠀⣿⡀⠈⠳⣮⡲⢄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⡄⠀⠀⠀⠀⠘⣧⠀⠀⠀⠈⢳⡄⠀⣰⠟⠁
⠀⠀⠀⠀⠀⠀⠙⠳⢦⣤⣤⣹⣷⣭⡢⢄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⠀⠀⠀⠀⠀⠀⢸⡇⠀⠀⠀⠀⣿⠋⠁⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠲⢬⣁⠐⠀⠠⠤⠤⠄⠀⠀⣀⣽⡃⠀⠀⠀⠀⠀⠀⣼⠁⠀⠀⠀⣠⡏⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠓⠲⠶⠶⠶⠚⠛⠁⠈⢷⣔⠂⠀⠀⣀⡾⠳⠶⠶⠶⠟⠋⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⠀⠀⠀⠀⠀⠀⠈⠙⠛⠉⠉⢀⠀⠀⣀⡀⠀⠀⠀⠀⠀⠀⠀

Dumbass furry i wrote this script you broke it why do you credit yourself -veltrixtheperson013

]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EntityModules = ServerStorage:WaitForChild("ServerModules"):WaitForChild("Entities")
local JumpscareController = require(EntityModules:WaitForChild("Entity_Kill [BETA]"))
local MoveController = require(EntityModules:WaitForChild("Entity_Move [BETA]"))
local EntityUtils = require(EntityModules:WaitForChild("Entity_Util"))

local npc = script.Parent
local rnum = ReplicatedStorage:WaitForChild("rnum")
local generatedRooms = Workspace:WaitForChild("GeneratedRooms")

local killController = JumpscareController.new(npc, {
	MaxDistance = 55,           
	Damage = 100,               
	ScanRate = 0.05,            
	RequireActiv = true,        

	TargetHidingPlayers = false, 
	JumpscareObject = npc:WaitForChild("a200jumpscar") 
})

local moveController = MoveController.new(npc, {
	Speed = 15,                 
	RepathTime = 1.0,
	StuckTime = 0.8,
	MaxFailures = 5,
	ClipHeight = 2,

	Rebounds = 0,               
	StartHeadingToLobby = true, 
	ChasePlayer = true,         
	ChaseRange = 60,            

	LobbyExit = Workspace:WaitForChild("Lobbi"):WaitForChild("Exit")
})

local function spawnSequence()
	local currentRoomIndex = rnum.Value
	local targetRoomModel = generatedRooms:FindFirstChild(tostring(currentRoomIndex))

	if targetRoomModel then
		local spawnPart = targetRoomModel:FindFirstChild("Exit") or targetRoomModel.PrimaryPart
		if spawnPart then
			npc:PivotTo(spawnPart.CFrame)
		end
	end

	local spawnSound = npc:FindFirstChild("Spawn")
	if spawnSound then
		spawnSound:Play()
		task.wait(spawnSound.TimeLength + 0.5)
	end

	local footsteps = npc:FindFirstChild("Footsteps")
	if footsteps then
		footsteps.Playing = true
	end

	killController:Start()
	moveController:Start()

	task.spawn(function()
		while npc.Parent and moveController.ChasePlayer do
			EntityUtils.SetLightFlickerSpan(15, true)
			task.wait(0.25) 
		end
	end)
end

npc.Destroying:Connect(function()
	EntityUtils.SetLightFlickerSpan(30, false)
end)

spawnSequence()
