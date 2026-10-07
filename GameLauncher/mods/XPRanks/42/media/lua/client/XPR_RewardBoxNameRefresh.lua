if isServer() and not isClient() then return end

local lastRefreshMs = 0
local REFRESH_COOLDOWN_MS = 5000

local function refreshRewardBoxNames()
	local now = getTimestampMs and getTimestampMs() or 0
	if now - lastRefreshMs < REFRESH_COOLDOWN_MS then return end
	lastRefreshMs = now

	if not getNumActivePlayers then return end
	for i = 0, getNumActivePlayers() - 1 do
		local pObj = getSpecificPlayer(i)
		local inv = pObj and pObj:getInventory()
		local items = inv and inv:getItems()
		if items then
			for j = 0, items:size() - 1 do
				local it = items:get(j)
				if it and XPR_RewardBox.isRewardBox(it) then
					local rank = XPR_RewardBox.getLinkedRank(it)
					local expectedName = rank and XPR_RewardBox.buildDisplayName(rank)
					if expectedName and it.getName and it:getName() ~= expectedName then
						XPR_RewardBox.applyDisplayName(it)
					end
				end
			end
		end
	end
end

Events.OnTick.Add(refreshRewardBoxNames)

return true
