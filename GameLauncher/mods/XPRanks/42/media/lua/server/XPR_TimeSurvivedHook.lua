if not XPR_Env or not XPR_Env.runsServerLogic() then return end

XPR_TimeSurvivedHook = XPR_TimeSurvivedHook or {}

local MS_PER_HOUR = 60 * 60 * 1000

local lastCheckMs = {}

local function currentGameTimeMs()
	local gt = getGameTime and getGameTime()
	local cal = gt and gt.getCalender and gt:getCalender()
	return cal and cal.getTimeInMillis and cal:getTimeInMillis()
end

local function onEveryOneMinute()
	local nowMs = currentGameTimeMs()
	if not nowMs then return end
	if not XPR_RankData or not XPR_Categories then return end

	local intervalHours = XPR_Categories.getTimeSurvivedIntervalHours()
	local xpPerInterval = XPR_Categories.getTimeSurvivedXp()

	for _, player in ipairs(XPR_Env.players()) do
		if player and player.getUsername and not player:isDead() then
			local uname = player:getUsername()
			if uname then
				local lastMs = lastCheckMs[uname]
				if not lastMs then
					lastCheckMs[uname] = nowMs
				else
					local deltaMs = nowMs - lastMs
					if deltaMs < 0 then deltaMs = 0 end
					lastCheckMs[uname] = nowMs

					if deltaMs > 0 and intervalHours > 0 then
						local pd = XPR_RankData.getPlayerData(player)
						if pd then
							local deltaHours = deltaMs / MS_PER_HOUR
							local total = (pd.timeSurvivedRemainderHours or 0) + deltaHours
							local crossed = math.floor(total / intervalHours)
							if crossed > 0 and xpPerInterval > 0 and XPR_XpQueue then
								XPR_XpQueue.queue(player, XPR_TIME_SURVIVED_CATEGORY, crossed * xpPerInterval)
							end
							pd.timeSurvivedRemainderHours = total - (crossed * intervalHours)
						end
					end
				end
			end
		end
	end
end

Events.EveryOneMinute.Add(onEveryOneMinute)

local function onCreatePlayer(playerNum)
	local player = getSpecificPlayer(playerNum)
	if not player then return end
	local uname = player:getUsername()
	if not uname then return end
	lastCheckMs[uname] = nil
end

Events.OnCreatePlayer.Add(onCreatePlayer)

return XPR_TimeSurvivedHook
