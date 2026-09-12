local folder=Instance.new("Folder");folder.Name="AttackRegression";folder.Parent=workspace
local results={}; local function check(v,n) assert(v,n);table.insert(results,n) end
local origin=Vector3.new(0,11000,0)
local gui=Instance.new("Folder")
local fakePlayer={FindFirstChild=function(_,name) if name=="PlayerGui" then return gui end end,FindFirstChildOfClass=function(_,name) if name=="PlayerGui" then return gui end end,PlayerGui=gui}
local character=Instance.new("Model");character.Name="Character";character.Parent=folder;fakePlayer.Character=character
local root=Instance.new("Part");root.Name="HumanoidRootPart";root.Anchored=true;root.Position=origin+Vector3.new(8,0,0);root.Parent=character
local hum=Instance.new("Humanoid");hum.Parent=character
local fakePlayers={GetPlayers=function() return {fakePlayer} end,GetPlayerFromCharacter=function(_,c) if c==character then return fakePlayer end end}
local fakeStorage=Instance.new("Folder")
local event=Instance.new("BindableEvent");event.Name="TelemetryDeathEvent";event.Parent=fakeStorage
local ok,err=xpcall(function()
for _,name in {"Entity_Kill","Entity_Kill [BETA]"} do
 local testModule=Instance.new("ModuleScript");testModule.Name=name;testModule.Parent=folder
 testModule.Source=game.ServerStorage.ServerModules.Entities[name].Source:gsub('local Players = game:GetService%("Players"%)', [[
local fixture=workspace.AttackRegression
local fakePlayer={Character=fixture.Character}
local Players={GetPlayers=function() return {fakePlayer} end,GetPlayerFromCharacter=function(_,c) if c==fakePlayer.Character then return fakePlayer end end}
]]) :gsub('local ServerStorage = game:GetService%("ServerStorage"%)', 'local ServerStorage = workspace.AttackRegression')
 local K=require(testModule)
 local npc=Instance.new("Part");npc.Anchored=true;npc.Position=origin;npc.Parent=folder
 hum.Health=100; root.Position=origin+Vector3.new(8,0,0)
 local k=K.new(npc,{Damage=100,RequireActiv=false,TelemetryCause="Regression"})
 check(k:FindNearestVisibleTorso(origin)==root,name.." sees exposed player")
 local wall=Instance.new("Part");wall.Anchored=true;wall.Size=Vector3.new(1,20,20);wall.Position=origin+Vector3.new(4,0,0);wall.Parent=folder
 check(k:FindNearestVisibleTorso(origin)==nil,name.." wall blocks attack");wall:Destroy()
 local hide=Instance.new("BoolValue");hide.Name="Hiding";hide.Parent=character
 check(k:FindNearestVisibleTorso(origin)==nil,name.." respects hiding")
 if name:find("BETA") then
  local locker=K.new(npc,{TargetHidingPlayers=true,HidingKillRange=12})
  check(locker:FindNearestVisibleTorso(origin)==root,"locker hunter finds hidden player")
 end
 hide:Destroy();root.Position=origin
 check(k:FindNearestVisibleTorso(origin)==root,name.." zero-distance ray is valid")
 k:Attack(root);check(hum.Health==0 and hum:GetAttribute("TelemetryDeathCause")=="Regression",name.." lethal damage attributed")
 k:Attack(root);check(hum.Health==0,name.." dead target ignored")
 -- New humanoid represents a respawn, not resurrecting the dead object.
 hum:Destroy();hum=Instance.new("Humanoid");hum.Parent=character
 k.HitDebounces={};check(k:FindNearestVisibleTorso(origin)==root,name.." respawn can be targeted")
 npc:Destroy()
end
end,debug.traceback)
folder:Destroy();gui:Destroy();fakeStorage:Destroy()
return {passed=#results,checks=results,error=not ok and err or nil}
