--[[
	CEnfosGameSpawner - A single unit spawner for Enfos.
]]
if CEnfosGameSpawner == nil then
	CEnfosGameSpawner = class({})
end


function CEnfosGameSpawner:ReadConfiguration( name, kv, gameRound )
	self._gameRound = gameRound
	self._dependentSpawners = {}

	self._szChampionNPCClassName = kv.ChampionNPCName or ""
	self._szGroupWithUnit = kv.GroupWithUnit or ""
	self._szName = name
	self._szNPCClassName = kv.NPCName or ""
	self._szRadiantSpawnerName = kv.RadiantSpawnerName or ""
	self._szDireSpawnerName = kv.DireSpawnerName or ""
	self._szWaitForUnit = kv.WaitForUnit or ""
	self._szRadiantWaypointName = kv.Waypoint or ""
	self._szDireWaypointName = kv.Waypoint or ""
	self._waypointEntity = nil

	self._nChampionLevel = tonumber( kv.ChampionLevel or 1 )
	self._nChampionMax = tonumber( kv.ChampionMax or 1 )
	self._nCreatureLevel = tonumber( kv.CreatureLevel or 1 )
	self._nTotalUnitsToSpawn = tonumber( kv.TotalUnitsToSpawn or 0 )
	self._nUnitsPerSpawn = tonumber( kv.UnitsPerSpawn or 0 )
	self._nUnitsPerSpawn = tonumber( kv.UnitsPerSpawn or 1 )

	self._flChampionChance = tonumber( kv.ChampionChance or 0 )
	self._flInitialWait = tonumber( kv.WaitForTime or 0 )
	self._flSpawnInterval = tonumber( kv.SpawnInterval or 0 )

	self._bDontGiveGoal = ( tonumber( kv.DontGiveGoal or 0 ) ~= 0 )
	self._bDontOffsetSpawn = ( tonumber( kv.DontOffsetSpawn or 0 ) ~= 0 )
end


function CEnfosGameSpawner:PostLoad( spawnerList )
	self._waitForUnit = spawnerList[ self._szWaitForUnit ]
	if self._szWaitForUnit ~= "" and not self._waitForUnit then
		print( "%s has a wait for unit %s that is missing from the round data.", self._szName, self._szWaitForUnit )
	elseif self._waitForUnit then
		table.insert( self._waitForUnit._dependentSpawners, self )
	end

	self._groupWithUnit = spawnerList[ self._szGroupWithUnit ]
	if self._szGroupWithUnit ~= "" and not self._groupWithUnit then
		print ("%s has a group with unit %s that is missing from the round data.", self._szName, self._szGroupWithUnit )
	elseif self._groupWithUnit then
		table.insert( self._groupWithUnit._dependentSpawners, self )
	end
end


function CEnfosGameSpawner:Precache()
	PrecacheUnitByNameAsync( self._szNPCClassName, function( sg ) self._sg = sg end )
	if self._szChampionNPCClassName ~= "" then
		PrecacheUnitByNameAsync( self._szChampionNPCClassName, function( sg ) self._sgChampion = sg end )
	end
end


function CEnfosGameSpawner:Begin()
	self._nUnitsSpawnedThisRound = 0
	self._nChampionsSpawnedThisRound = 0
	self._nUnitsCurrentlyAlive = 0
	_goodGuyPlayer = false
	_badGuyPlayer = false
	
	---------------------------------------------------------------------
	--- Radiant Spawn Setup initial
	---------------------------------------------------------------------
	self._vecRadiantSpawnLocation = nil
	if self._szRadiantSpawnerName ~= "" then
		local entSpawner = Entities:FindByName( nil, self._szRadiantSpawnerName )
		if not entSpawner then
			print( string.format( "Failed to find spawner named %s for %s\n", self._szRadiantSpawnerName, self._szName ) )
		end
		self._vecRadiantSpawnLocation = entSpawner:GetAbsOrigin()
	end
	
	self._entRadiantWaypoint = nil
	if self._szRadiantWaypointName ~= "" and not self._bDontGiveGoal then
		self._entRadiantWaypoint = Entities:FindByName( nil, self._szRadiantWaypointName )
		if not self._entRadiantWaypoint then
			print( string.format( "Failed to find waypoint named %s for %s", self._szRadiantWaypointName, self._szName ) )
		end
	end
	
	---------------------------------------------------------------------
	-- Dire spawn setup initial
	---------------------------------------------------------------------
	self._vecDireSpawnLocation = nil
	if self._szDireSpawnerName ~= "" then
		local entSpawner = Entities:FindByName( nil, self._szDireSpawnerName )
		if not entSpawner then
			print( string.format( "Failed to find spawner named %s for %s\n", self._szDireSpawnerName, self._szName ) )
		end
		self._vecDireSpawnLocation = entSpawner:GetAbsOrigin()
	end
	
	self._entDireWaypoint = nil
	if self._szDireWaypointName ~= "" and not self._bDontGiveGoal then
		self._entDireWaypoint = Entities:FindByName( nil, self._szDireWaypointName )
		if not self._entDireWaypoint then
			print( string.format( "Failed to find waypoint named %s for %s", self._szDireWaypointName, self._szName ) )
		end
	end
	
	

	if self._waitForUnit ~= nil or self._groupWithUnit ~= nil then
		self._flNextSpawnTime = nil
	else
		self._flNextSpawnTime = GameRules:GetGameTime() + self._flInitialWait
	end
end


function CEnfosGameSpawner:End()
	if self._sg ~= nil then
		UnloadSpawnGroupByHandle( self._sg )
		self._sg = nil
	end
	if self._sgChampion ~= nil then
		UnloadSpawnGroupByHandle( self._sgChampion )
		self._sgChampion = nil
	end
end


function CEnfosGameSpawner:ParentSpawned( parentSpawner )
	if parentSpawner == self._groupWithUnit then
		-- Make sure we use the same spawn location as parentSpawner.
		self:_DoSpawn()
	elseif parentSpawner == self._waitForUnit then
		if parentSpawner:IsFinishedSpawning() and self._flNextSpawnTime == nil then
			self._flNextSpawnTime = parentSpawner._flNextSpawnTime + self._flInitialWait
		end
	end
end


function CEnfosGameSpawner:Think()
	if not self._flNextSpawnTime then
		return
	end
	
	if GameRules:GetGameTime() >= self._flNextSpawnTime then
		self:_DoSpawn()
		for _,s in pairs( self._dependentSpawners ) do
			s:ParentSpawned( self )
		end

		if self:IsFinishedSpawning() then
			self._flNextSpawnTime = nil
		else
			self._flNextSpawnTime = self._flNextSpawnTime + self._flSpawnInterval
		end
	end
end


function CEnfosGameSpawner:GetTotalUnitsToSpawn()
	return self._nTotalUnitsToSpawn
end


function CEnfosGameSpawner:IsFinishedSpawning()
	return ( self._nTotalUnitsToSpawn <= self._nUnitsSpawnedThisRound ) or ( self._groupWithUnit ~= nil )
end

-- Returns the current spawn location for the Radiant
function CEnfosGameSpawner:_GetRadiantSpawnLocation()
	if self._groupWithUnit then
		return self._groupWithUnit:_GetRadiantSpawnLocation()
	else
		return self._vecRadiantSpawnLocation
	end
end

-- Returns the current spawn location for the Dire
function CEnfosGameSpawner:_GetDireSpawnLocation()
	if self._groupWithUnit then
		return self._groupWithUnit:_GetDireSpawnLocation()
	else
		return self._vecDireSpawnLocation
	end
end


function CEnfosGameSpawner:_GetRadiantSpawnWaypoint()
	if self._groupWithUnit then
		return self._groupWithUnit:_GetRadiantSpawnWaypoint()
	else
		return self._entRadiantWaypoint
	end
end

function CEnfosGameSpawner:_GetDireSpawnWaypoint()
	if self._groupWithUnit then
		return self._groupWithUnit:_GetDireSpawnWaypoint()
	else
		return self._entDireWaypoint
	end
end

	---------------------------------------------------------------------
	--- Radiant Spawn Location Updater
	---------------------------------------------------------------------
function CEnfosGameSpawner:_UpdateRadiantSpawn()
	self._vecRadiantSpawnLocation = Vector( 0, 0, 0 )
	self._entRadiantWaypoint = nil
	local spawnInfo = self._gameRound:ChooseRadiantSpawnInfo()
	if spawnInfo == nil then
		return
	end
	
	local entSpawner = Entities:FindByName( nil, spawnInfo.szRadiantSpawnerName )
	if not entSpawner then
		return
	end
	self._vecRadiantSpawnLocation = entSpawner:GetAbsOrigin()
	
	if not self._bDontGiveGoal then
		self._entRadiantWaypoint = Entities:FindByName( nil, spawnInfo.szRadiantFirstWaypoint )
		if not self._entRadiantWaypoint then
			print( string.format( "Failed to find a waypoint named %s for %s.", spawnInfo.szRadiantFirstWaypoint, self._szName ) )
			return
		end
	end
end

	---------------------------------------------------------------------
	--- Dire Spawn Location Updater
	---------------------------------------------------------------------
function CEnfosGameSpawner:_UpdateDireSpawn()
	self._vecDireSpawnLocation = Vector( 0, 0, 0 )
	self._entDireWaypoint = nil

	local spawnInfo = self._gameRound:ChooseDireSpawnInfo()
	if spawnInfo == nil then
		print( string.format( "Failed to get Dire spawn info for spawner %s.", self._szName ) )
		return
	end
	
	local entSpawner = Entities:FindByName( nil, spawnInfo.szDireSpawnerName )
	if not entSpawner then
		print( string.format( "Failed to find spawner named %s for %s.", spawnInfo.szDireSpawnerName, self._szName ) )
		return
	end
	self._vecDireSpawnLocation = entSpawner:GetAbsOrigin()


	if not self._bDontGiveGoal then
		self._entDireWaypoint = Entities:FindByName( nil, spawnInfo.szDireFirstWaypoint )
		if not self._entDireWaypoint then
			print( string.format( "Failed to find a waypoint named %s for %s.", spawnInfo.szFirstWaypoint, self._szName ) )
			return
		end
	end
end

function CEnfosGameSpawner:_CheckSinglePlayer()
	for nPlayerID = 0, DOTA_MAX_PLAYERS-1 do
		if ( PlayerResource:IsValidPlayer( nPlayerID ) ) then
			local team = PlayerResource:GetPlayer(nPlayerID):GetAssignedHero():GetTeam()
			if(team == 2) then
				_goodGuyPlayer = true
			elseif(team == 3) then
				_badGuyPlayer = true
			end
		end
	end
end


function CEnfosGameSpawner:_DoSpawn()
	CEnfosGameSpawner:_CheckSinglePlayer()

	local nUnitsToSpawn = math.min( self._nUnitsPerSpawn, self._nTotalUnitsToSpawn - self._nUnitsSpawnedThisRound )

	if nUnitsToSpawn <= 0 then
		return
	elseif self._nUnitsSpawnedThisRound == 0 then
		print( string.format( "Started spawning %s at %.2f", self._szName, GameRules:GetGameTime() ) )
	end

	if self._szRadiantSpawnerName == "" then
		self:_UpdateRadiantSpawn()
	end
	
	if self._szDireSpawnerName == "" then
		self:_UpdateDireSpawn()
	end
	
	local vRadiantSpawnLocation = self:_GetRadiantSpawnLocation()
	
	if not vRadiantSpawnLocation then return end
	for iUnit = 1,nUnitsToSpawn do
		local bIsChampion = RollPercentage( self._flChampionChance )
		if self._nChampionsSpawnedThisRound >= self._nChampionMax then
			bIsChampion = false
		end

		local szNPCClassToSpawn = self._szNPCClassName
		if bIsChampion and self._szChampionNPCClassName ~= "" then
			szNPCClassToSpawn = self._szChampionNPCClassName
		end

		local vRadSpawnLocation = vRadiantSpawnLocation
		if not self._bDontOffsetSpawn then
			vRadSpawnLocation = vRadSpawnLocation + RandomVector( RandomFloat( 0, 200 ) )
		end
		
		------------------------------------
		-- Spawn Radiant Mobs
		------------------------------------
		if(_goodGuyPlayer) then
			local entUnit = CreateUnitByName( szNPCClassToSpawn, vRadSpawnLocation, true, nil, nil, DOTA_TEAM_BADGUYS)
			if entUnit then
				if entUnit:IsCreature() then
					if bIsChampion then
						self._nChampionsSpawnedThisRound = self._nChampionsSpawnedThisRound + 1
						entUnit:CreatureLevelUp( ( self._nChampionLevel - 1 ) )
						entUnit:SetChampion( true )
						local nParticle = ParticleManager:CreateParticle( "heavens_halberd", PATTACH_ABSORIGIN_FOLLOW, entUnit )
						ParticleManager:ReleaseParticleIndex( nParticle )
						entUnit:SetModelScale( 1.1, 0 )
					else
						entUnit:CreatureLevelUp( self._nCreatureLevel - 1 )
					end
				end
				local entWp = self:_GetRadiantSpawnWaypoint()
				if entWp ~= nil then
					entUnit:SetInitialGoalEntity( entWp )
				end
				self._nUnitsSpawnedThisRound = self._nUnitsSpawnedThisRound + 1
				self._nUnitsCurrentlyAlive = self._nUnitsCurrentlyAlive + 1
				entUnit.Enfos_IsCore = true
				--entUnit:SetDeathXP( self._gameRound:GetXPPerCoreUnit() )
			end
		else
			self._nUnitsCurrentlyAlive = self._nUnitsCurrentlyAlive + 1
			self._nUnitsSpawnedThisRound = self._nUnitsSpawnedThisRound + 1
		end
		
		local vDireSpawnLocation = self:_GetDireSpawnLocation()
		local vDirSpawnLocation = vDireSpawnLocation
		if not self._bDontOffsetSpawn then
			vDirSpawnLocation = vDirSpawnLocation + RandomVector( RandomFloat( 0, 200 ) )
		end
		
		------------------------------
		-- Spawn Dire Mobs
		------------------------------
		if(_badGuyPlayer) then
			local entUnit2 = CreateUnitByName( szNPCClassToSpawn, vDirSpawnLocation, true, nil, nil, DOTA_TEAM_GOODGUYS)
			if entUnit2 then
				if entUnit2:IsCreature() then
					if bIsChampion then
						self._nChampionsSpawnedThisRound = self._nChampionsSpawnedThisRound + 1
						entUnit2:CreatureLevelUp( ( self._nChampionLevel - 1 ) )
						entUnit2:SetChampion( true )
						local nParticle = ParticleManager:CreateParticle( "heavens_halberd", PATTACH_ABSORIGIN_FOLLOW, entUnit2 )
						ParticleManager:ReleaseParticleIndex( nParticle )
						entUnit2:SetModelScale( 1.1, 0 )
					else
						entUnit2:CreatureLevelUp( self._nCreatureLevel - 1 )
					end
				end
				local entWp = self:_GetDireSpawnWaypoint()
				if entWp ~= nil then
					entUnit2:SetInitialGoalEntity( entWp )
				end
				self._nUnitsSpawnedThisRound = self._nUnitsSpawnedThisRound + 1
				self._nUnitsCurrentlyAlive = self._nUnitsCurrentlyAlive + 1
				entUnit2.Enfos_IsCore = true
				--entUnit2:SetDeathXP( self._gameRound:GetXPPerCoreUnit() )
			end
		else
			self._nUnitsCurrentlyAlive = self._nUnitsCurrentlyAlive + 1
			self._nUnitsSpawnedThisRound = self._nUnitsSpawnedThisRound + 1
		end
	end
end


function CEnfosGameSpawner:StatusReport()
	print( string.format( "** Spawner %s", self._szNPCClassName ) )
	print( string.format( "%d of %d spawned", self._nUnitsSpawnedThisRound, self._nTotalUnitsToSpawn ) )
end