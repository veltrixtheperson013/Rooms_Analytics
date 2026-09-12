local source=game.ServerScriptService.TelemetryService.Source
local module=Instance.new("ModuleScript"); module.Name="TelemetryRegression"
local begin=assert(source:find("local function utcNow",1,true))
local ending=assert(source:find("local function postToBackend",begin,true))
module.Source='local RunService=game:GetService("RunService")\nlocal HttpService=game:GetService("HttpService")\nlocal sessions={}\nlocal profiles={}\nlocal debugLog=function() end\n'..source:sub(begin,ending-1)..'\nreturn {aggregateSession=aggregateSession,updateAggregate=updateAggregate,attachDeathWatcher=attachDeathWatcher,sessions=sessions}'
module.Parent=game.ServerStorage
local api=require(module)
local results={};local function check(v,n) assert(v,n);table.insert(results,n) end
local folder=Instance.new("Folder");folder.Name="TelemetryRegression";folder.Parent=workspace
local ok,err=xpcall(function()
local session={enabled=true,joinTimestamp=os.time()-20,joinUtc="2026-09-12T00:00:00Z",joinHourUtc="2026-09-12T00:00:00Z",visitedRooms={[50]=true,[51]=true},deaths=1,deathCauses={["A-85"]=1},sections={A=true},miniSections={Office=true},environment="InStudio",accountAgeGroup="3+ years"}
local data=api.aggregateSession(session,os.time())
check(data.roomsTravelled==2,"counts visited rooms rather than farthest number")
local aggregate=api.updateAggregate(nil,data)
check(aggregate.TotalSessions==1 and aggregate.Revision==1,"revision matches cumulative sessions")
check(aggregate.TotalDeaths==1 and aggregate.DeathCauses["A-85"]==1,"death cause aggregate")
check(aggregate.Categories.InStudio.TotalSessions==1,"Studio category breakdown")
local template=game.Players:GetPlayers()[1].Character
local previous=template.Archivable;template.Archivable=true
local character=template:Clone();template.Archivable=previous
for _,x in character:GetDescendants() do if x:IsA("BaseScript") then x:Destroy() end end
character:PivotTo(CFrame.new(0,12000,0));character.Parent=folder
local humanoid=character:FindFirstChildOfClass("Humanoid")
humanoid.BreakJointsOnDeath=false;humanoid.Health=100
local player={};session.deaths=0;session.deathCauses={};api.sessions[player]=session
api.attachDeathWatcher(player,character);api.attachDeathWatcher(player,character)
humanoid:SetAttribute("TelemetryDeathCause","A-85");humanoid.Health=0;humanoid:ChangeState(Enum.HumanoidStateType.Dead)
task.wait(0.2)
check(session.deaths==1 and session.deathCauses["A-85"]==1,"duplicate Died listeners count one attributed death")
session.enabled=false
humanoid:Destroy();humanoid=Instance.new("Humanoid");humanoid.BreakJointsOnDeath=false;humanoid.Parent=character
api.attachDeathWatcher(player,character);humanoid.Health=0;task.wait(0.2)
check(session.deaths==1,"opt-out ignores deaths")
end,debug.traceback)
folder:Destroy();module:Destroy()
return {passed=#results,checks=results,error=not ok and err or nil}
