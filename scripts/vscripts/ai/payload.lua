--[[
	-this allied ai will walk along a path marked out by points in the map
	-it will move faster depending on the number off allies in range
	-it will also loop its path
]]

local PathPoints = {} 						--stores all the coordinates of the points of the path
local maxSpeed = 250 							--200 maximum movespeed of the payload (payload moves faster the more allies that are in range)
local allyDetectionRadius = 400 	--range allies need to be for the payload to move

function Spawn()
	getPathPoints()
	local totalDist = calcTotalDist()
	CustomNetTables:SetTableValue("game", "dist_total", { value = totalDist })
	CustomNetTables:SetTableValue("game", "dist_good", { value = 0 })
	CustomNetTables:SetTableValue("game", "dist_bad", { value = 0})
	CustomNetTables:SetTableValue("game", "round", { value = 1 })
	CustomNetTables:SetTableValue("payload", "nextPath", { value = 2 })
	CustomNetTables:SetTableValue("game", "units_pushing", { value = 0 })
	local abil = thisEntity:FindAbilityByName("dummy_lua")
	if abil ~= nil then
		print("casting dummy ability")
		abil:CastAbility()
	else
		print("ability not found")
	end
	thisEntity:SetContextThink("FollowPath", FollowPath, 0.2)
	thisEntity:SetContextThink("UpdateCurDist", UpdateCurDist, 1)
end

--[[
	finds all the points and populates PathPoints
	points are named: path_ .. index
]]
function getPathPoints()
	local indexDiff = 0
	local i = 10
	while( indexDiff < 20 )
	do
		local entName = "path_" .. tostring(i)
		local target = Entities:FindByName( nil, entName)
		if target~=nil then
			indexDiff = 0
			local point = target:GetAbsOrigin()
			table.insert(PathPoints, point)
		else
			indexDiff = indexDiff + 1
		end

		i = i + 1
	end
end

function calcTotalDist()
	local total = 0
	for i=2, #PathPoints do
		if PathPoints[i]~=nil then
			total = total + DistBetweenPoints(PathPoints[i], PathPoints[i-1])
		end
	end
	return total
end

--makes the payload move from 1 point to the next
function FollowPath()
	--if index is out of range then reset to 1
	local nextPathIndex = CustomNetTables:GetTableValue("payload", "nextPath").value
	if PathPoints[nextPathIndex] == nil then
		CustomNetTables:SetTableValue("payload", "nextPath", { value = 1 })
	end
	
	local round = CustomNetTables:GetTableValue("game", "round").value
	local allyTeam = DOTA_TEAM_GOODGUYS
	local enemyTeam = DOTA_TEAM_BADGUYS
	if round == 2 then
		allyTeam = DOTA_TEAM_BADGUYS
		enemyTeam = DOTA_TEAM_GOODGUYS
	end

	local nextPoint = PathPoints[nextPathIndex]

	--find and count the number off allies
	local allyHeroesNearby = FindUnitsInRadius(
		allyTeam,
		thisEntity:GetAbsOrigin(),
		nil,
		allyDetectionRadius,
		DOTA_UNIT_TARGET_TEAM_FRIENDLY,
		DOTA_UNIT_TARGET_HERO,
		DOTA_UNIT_TARGET_FLAG_PLAYER_CONTROLLED +
			DOTA_UNIT_TARGET_FLAG_NOT_DOMINATED +
			DOTA_UNIT_TARGET_FLAG_NOT_SUMMONED +
			DOTA_UNIT_TARGET_FLAG_NOT_ILLUSIONS +
			DOTA_UNIT_TARGET_FLAG_NOT_ATTACK_IMMUNE,
		FIND_ANY_ORDER,
		false)
							  
	local enemyHeroesNearby = FindUnitsInRadius(
		enemyTeam,
		thisEntity:GetAbsOrigin(),
		nil,
		allyDetectionRadius,
		DOTA_UNIT_TARGET_TEAM_FRIENDLY,
		DOTA_UNIT_TARGET_HERO,
		DOTA_UNIT_TARGET_FLAG_PLAYER_CONTROLLED +
			DOTA_UNIT_TARGET_FLAG_NOT_DOMINATED +
			DOTA_UNIT_TARGET_FLAG_NOT_SUMMONED +
			DOTA_UNIT_TARGET_FLAG_NOT_ILLUSIONS +
			DOTA_UNIT_TARGET_FLAG_NOT_ATTACK_IMMUNE,
		FIND_ANY_ORDER,
		false)

		
	local allyCount = #allyHeroesNearby
	CustomNetTables:SetTableValue("game", "units_pushing", { value = allyCount })

	local usedMove = false
	
	local gamestate = CustomNetTables:GetTableValue("gamestate", "state").value

	--execute move command to the next path point if there is ally heroes nearby
	if gamestate=="in_progress" and allyCount > 0 and #enemyHeroesNearby == 0 then
		local moveOrder = {
			UnitIndex = thisEntity:entindex(),
			OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
			Position = nextPoint
		}
		setSpeed(allyCount)
		ExecuteOrderFromTable(moveOrder)
		usedMove = true
	end

	--if no move command was executed then execute a stop command
	if usedMove == false then
		local stopOrder = {
			UnitIndex = thisEntity:entindex(),
			OrderType = DOTA_UNIT_ORDER_STOP
		}
		ExecuteOrderFromTable(stopOrder)
	end

	--increment nextPathIndex if close enough the to current target
	local payloadPoint = thisEntity:GetAbsOrigin()
	local diff = payloadPoint - nextPoint
	local dist = #diff
	if dist < 150 then
		CustomNetTables:SetTableValue("payload", "nextPath", { value = nextPathIndex+1 })
	end
	
	
	AddFOWViewer(DOTA_TEAM_BADGUYS, thisEntity:GetAbsOrigin(), 800, 0.2, false)
	AddFOWViewer(DOTA_TEAM_GOODGUYS, thisEntity:GetAbsOrigin(), 800, 0.2, false)

	return 0.2
end

--the more allies in range, the faster the payload moves
function setSpeed(allyCount)
	CustomNetTables:SetTableValue("game", "units_pushing", { value = allyCount })
	local speed = maxSpeed*(allyCount/PlayerResource:GetTeamPlayerCount())
	thisEntity:SetBaseMoveSpeed(speed)
end

--updates the current distance travelled in custom net tables
function UpdateCurDist()
	local curTotal = 0
	local nextPathIndex = CustomNetTables:GetTableValue("payload", "nextPath").value
	for i=1, nextPathIndex-1 do
		curTotal = curTotal + DistBetweenPoints(PathPoints[i], PathPoints[i+1])
	end
	local distToNextPt = DistBetweenPoints(PathPoints[nextPathIndex], thisEntity:GetAbsOrigin())
	curTotal = curTotal - distToNextPt
	
	local totalDist = CustomNetTables:GetTableValue("game", "dist_total")
	local percent  = curTotal/totalDist.value
	local round = CustomNetTables:GetTableValue("game", "round")	
		
	if round.value == 1 then
		CustomNetTables:SetTableValue("game", "dist_good", { value = percent })
		
	--round 2
	else
		CustomNetTables:SetTableValue("game", "dist_bad", { value = percent })
		
		local good = CustomNetTables:GetTableValue("game", "dist_good").value
		local bad = CustomNetTables:GetTableValue("game", "dist_bad").value
		if bad > good then
			Frosti:SetWinner()
		end
	end
	
	return 1
end

--2d length between vector a and b
function DistBetweenPoints(a, b)
	local diff = a-b
	return diff:Length2D()
end 