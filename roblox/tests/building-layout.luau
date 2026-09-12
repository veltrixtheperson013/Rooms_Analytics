local Layout=require(game.ServerScriptService.RoomGeneration.Room.BuildingLayout)
local a=Layout.new(12345);local b=Layout.new(12345);local c=Layout.new(98765)
local checks=0;local changed=0;local maxDelta=0
local function check(v,n) assert(v,n);checks+=1 end
for step=1,200 do
 local value=a:Sample(step)
 check(value==b:Sample(step),"same seed")
 if math.abs(value-c:Sample(step))>0.001 then changed+=1 end
 maxDelta=math.max(maxDelta,math.abs(value-a:Sample(step+1)))
end
check(changed>150,"different seeds")
check(maxDelta<0.12,"smooth room-to-room changes")
local straight=0;local turns=0;local stairs=0
for step=1,200 do
 straight+=a:Weight("Basic_OfficeLongCorridor",{},step)
 turns+=a:Weight("BasicTurn_Right",{Direction="Right"},step)
 stairs+=a:Weight("Staircase_Up",{Stairs=true},step)
end
check(straight>turns*2,"corridor preference")
check(straight>stairs*4,"stairs remain rare")
check(Layout.new(1,18,0):Weight("Staircase_Up",{Stairs=true},30)==1,"strength zero disables bias")
local Room=require(game.ServerScriptService.RoomGeneration.Room)
check(Room.IsForbiddenForStep("RightBasicIntersection",1),"case-insensitive early safety")
local old=Room.GeneratedRoomsInfo
Room.GeneratedRoomsInfo={{number=20,template="Staircase_Up"}}
check(not Room.IsLayoutAllowed("Staircase_Down",25),"stairs spaced across floor")
check(Room.IsLayoutAllowed("Staircase_Down",32),"stairs allowed after twelve rooms")
Room.GeneratedRoomsInfo=old
return {assertions=checks,differentSeedSamples=changed,maxAdjacentNoiseDelta=maxDelta,weights={straight=straight/200,turns=turns/200,stairs=stairs/200},activeSeed=Room.buildingSeed}
