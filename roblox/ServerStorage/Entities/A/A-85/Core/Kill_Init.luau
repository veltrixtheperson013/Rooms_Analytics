--[[
	v3ltrixx 2026

	entity kill initializer
-]]
local JumpscareController = require(game.ServerStorage.ServerModules.Entities.Entity_Kill)

local npc = script.Parent.Parent

local controller = JumpscareController.new(npc, {

	-- ITS.. ITS NOT SHUTTING DOWN!!
	MaxDistance = 55,
	Damage = 100,
	ScanRate = 0.1,

	-- I told you, we need to work on your behavior
	RequireActiv = true,

	-- Object referee
	JumpscareObject = npc:WaitForChild("a85jumpscar")

})

controller:Start()

