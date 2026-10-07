XPR_API = XPR_API or {}

LuaEventManager.AddEvent("XPR_OnRankUp")
LuaEventManager.AddEvent("XPR_OnXpGained")

function XPR_API.AwardXp(player, amount, tickerLabel, categoryKey)
	if not XPR_Env or not XPR_Env.runsServerLogic() then return false end
	if not player then return false end

	amount = tonumber(amount)
	if not amount or amount <= 0 then return false end

	if type(tickerLabel) ~= "string" or tickerLabel == "" then
		tickerLabel = "Bonus"
	end

	if type(categoryKey) ~= "string" or categoryKey == "" then
		categoryKey = tickerLabel
	end

	if not XPR_RankData then return false end

	XPR_RankData.addFlatXp(player, categoryKey, amount, tickerLabel)
	XPR_RankData.sendXpGain(player, tickerLabel, amount)
	return true
end

function XPR_API.GetRank(player)
	if not XPR_Env or not XPR_Env.runsServerLogic() then return 0 end
	if not player then return 0 end
	if not XPR_RankData then return 0 end

	local pd = XPR_RankData.getPlayerData(player)
	return pd and pd.rank or 0
end

function XPR_API.IsRankOrAbove(player, requiredRank)
	requiredRank = tonumber(requiredRank)
	if not requiredRank then return false end
	return XPR_API.GetRank(player) >= requiredRank
end

function XPR_API.GetTotalXp(player)
	if not XPR_Env or not XPR_Env.runsServerLogic() then return 0 end
	if not player then return 0 end
	if not XPR_RankData then return 0 end

	local pd = XPR_RankData.getPlayerData(player)
	return pd and pd.totalXp or 0
end

function XPR_API.GetXpForRank(rank)
	rank = tonumber(rank)
	if not rank then return 0 end
	if not XPR_RankCurve then return 0 end
	return XPR_RankCurve.cumulativeXpForRank(rank)
end

function XPR_API.GetXpToNextRank(player)
	if not XPR_Env or not XPR_Env.runsServerLogic() then return 0 end
	if not player then return 0 end
	if not XPR_RankData or not XPR_RankCurve then return 0 end

	local pd = XPR_RankData.getPlayerData(player)
	if not pd then return 0 end
	local rank = pd.rank or 1
	if rank >= XPR_RankCurve.MAX_RANK then return 0 end

	local xpIntoRank = (pd.totalXp or 0) - XPR_RankCurve.cumulativeXpForRank(rank)
	local xpNeeded = XPR_RankCurve.requiredXp(rank + 1) - xpIntoRank
	if xpNeeded < 0 then xpNeeded = 0 end
	return xpNeeded
end

function XPR_API.GetLocalRank()
	if isServer() and not isClient() then return 0 end
	if not XPR_ClientSync or not XPR_ClientSync.getState then return 0 end

	local player = getSpecificPlayer and getSpecificPlayer(0)
	local state = XPR_ClientSync.getState(player)
	return (state and state.rank) or 0
end

return XPR_API
