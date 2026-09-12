local folder=Instance.new("Folder"); folder.Name="EntityRegression"; folder.Parent=workspace
local results={}
local function check(ok,name) assert(ok,name); table.insert(results,name) end
local origin=Vector3.new(0,10000,0)
local modules=game.ServerStorage.ServerModules.Entities
local ok,err=xpcall(function()
for _,name in {"Entity_Move","Entity_Move [BETA]"} do
 local C=require(modules[name]); local part=Instance.new("Part");part.Anchored=true;part.Position=origin;part.Parent=folder
 local c=C.new(part,{Speed=300,RepathTime=0.01,MaxFailures=2})
 c:StepToward(origin+Vector3.new(4,0,0),1)
 check((part.Position-(origin+Vector3.new(4,0,0))).Magnitude<0.01,name.." clamped step")
 part.Position=origin
 check(c:DirectMove(origin+Vector3.new(20,0,0),c.MoveToken),name.." direct movement completes")
 part.Position=origin
 local reached=false; c.ReachedTarget=function() reached=true end
 local calls=0
 c.ComputePath=function() calls+=1; if calls==1 then return nil end; return {GetWaypoints=function() return {{Position=origin+Vector3.new(20,0,0),Action=Enum.PathWaypointAction.Walk}} end} end
 c.DirectMove=function() return false end
 c:MoveTo(origin+Vector3.new(20,0,0))
 check(reached and calls==2 and (part.Position-(origin+Vector3.new(20,0,0))).Magnitude<=2,name.." retry recovers")
 c.ComputePath=function() c.MoveToken+=1;return nil end; reached=false;c:MoveTo(origin)
 check(not reached,name.." cancelled path does not finish")
 local before=part.Position;local wall=Instance.new("Part");wall.Anchored=true;wall.Size=Vector3.new(1,20,20);wall.Position=before+Vector3.new(3,0,0);wall.Parent=folder
 c:StepToward(before+Vector3.new(15,0,0),0.1)
 check((part.Position-before).Magnitude<0.01,name.." head-on wall blocks chase")
 wall:Destroy();part:Destroy()
end
local model=Instance.new("Model");model.Parent=folder
local p=Instance.new("Part");p.Anchored=true;p.Position=origin;p.Parent=model
local c=require(modules["Entity_Move [BETA]"]).new(model,{Speed=100})
check(type(c:GetTouchingParts())=="table","Model touching parts")
c:StepToward(origin+Vector3.new(4,0,0),1)
check((model:GetPivot().Position-origin-Vector3.new(4,0,0)).Magnitude<0.01,"Model pivot movement")
model:Destroy()
end,debug.traceback)
folder:Destroy()
return {passed=#results,checks=results,error=not ok and err or nil}
