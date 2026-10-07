if not XPR_Env or not XPR_Env.runsServerLogic() then return end

XPR_TravelHook = XPR_TravelHook or {}

local SWEEP_INTERVAL_TICKS = 30
local sweepTicksLeft = SWEEP_INTERVAL_TICKS

local WALK_JITTER_DEADZONE = 0.05
local DRIVE_JITTER_DEADZONE = 0.1

local WALK_TELEPORT_CAP_TILES = 10
local DRIVE_TELEPORT_CAP_TILES = 150

local lastPos = {}

local function resolveTravelKind(player)
	local vehicle = player:getVehicle()
	if vehicle then
		if vehicle:isDriver(player) then
			return XPR_TRAVEL_DRIVE_CATEGORY, DRIVE_JITTER_DEADZONE, DRIVE_TELEPORT_CAP_TILES
		end
		return nil, nil, DRIVE_TELEPORT_CAP_TILES
	end
	return XPR_TRAVEL_WALK_CATEGORY, WALK_JITTER_DEADZONE, WALK_TELEPORT_CAP_TILES
end

local function accumulateAndAward(player, remainderField, dist, category, xpPerThreshold, tilesPerThreshold)
	if not XPR_RankData then return end
	local pd = XPR_RankData.getPlayerData(player)
	if not pd then return end

	local total = (pd[remainderField] or 0) + dist
	if tilesPerThreshold <= 0 then
		pd[remainderField] = total
		return
	end

	local crossed = math.floor(total / tilesPerThreshold)
	if crossed > 0 and xpPerThreshold > 0 and XPR_XpQueue then
		XPR_XpQueue.queue(player, category, crossed * xpPerThreshold)
	end
	pd[remainderField] = total - (crossed * tilesPerThreshold)
end

local function onTick()
	sweepTicksLeft = sweepTicksLeft - 1
	if sweepTicksLeft > 0 then return end
	sweepTicksLeft = SWEEP_INTERVAL_TICKS

	if not XPR_Env or not XPR_Env.runsServerLogic() then return end

	for _, player in ipairs(XPR_Env.players()) do
		if player and player.getUsername and not player:isDead() then
			local uname = player:getUsername()
			if uname then
				local px, py, pz = player:getX(), player:getY(), player:getZ()
				local prev = lastPos[uname]

				if not prev then
					lastPos[uname] = { x = px, y = py, z = pz }
				else
					local kind, deadzone, teleportCap = resolveTravelKind(player)

					if prev.z ~= pz then
						lastPos[uname] = { x = px, y = py, z = pz }
					else
						local dx = px - prev.x
						local dy = py - prev.y
						local dist = math.sqrt(dx * dx + dy * dy)

						if dist > teleportCap then
							lastPos[uname] = { x = px, y = py, z = pz }
						elseif kind and deadzone and dist > deadzone then
							if kind == XPR_TRAVEL_DRIVE_CATEGORY then
								accumulateAndAward(player, "travelDriveRemainderTiles", dist,
									XPR_TRAVEL_DRIVE_CATEGORY,
									XPR_Categories.getTravelDriveXp(),
									XPR_Categories.getTravelDriveTiles())
							else
								accumulateAndAward(player, "travelWalkRemainderTiles", dist,
									XPR_TRAVEL_WALK_CATEGORY,
									XPR_Categories.getTravelWalkXp(),
									XPR_Categories.getTravelWalkTiles())
							end
							lastPos[uname] = { x = px, y = py, z = pz }
						end
					end
				end
			end
		end
	end
end

Events.OnTick.Add(onTick)

local function onCreatePlayer(playerNum)
	local player = getSpecificPlayer(playerNum)
	if not player then return end
	local uname = player:getUsername()
	if not uname then return end
	lastPos[uname] = nil
end

Events.OnCreatePlayer.Add(onCreatePlayer)

return XPR_TravelHook
