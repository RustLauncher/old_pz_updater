if not XPR_Env or not XPR_Env.runsServerLogic() then return end

XPR_XpQueue = XPR_XpQueue or {}

local BUNDLE_THRESHOLD = 5

local pending = {}
local pendingXmod = {}
local quietDeadlineMs = {}

function XPR_XpQueue.queue(player, category, amount, label)
	if not player or not category or not amount or amount <= 0 then return end
	local uname = player:getUsername()
	if not uname then return end

	if label then
		pendingXmod[uname] = pendingXmod[uname] or {}
		local bucket = pendingXmod[uname][label]
		if bucket then
			bucket.amount = bucket.amount + amount
		else
			pendingXmod[uname][label] = { category = category, amount = amount }
		end
	else
		pending[uname] = pending[uname] or {}
		pending[uname][category] = (pending[uname][category] or 0) + amount
	end
	local quietMs = (XPR_Config and XPR_Config.NOTIFICATION_QUIET_MS) or 3000
	quietDeadlineMs[uname] = (getTimestampMs and getTimestampMs() or 0) + quietMs
end

function XPR_XpQueue.clearPlayer(player)
	if not player or not player.getUsername then return end
	local uname = player:getUsername()
	if not uname then return end
	pending[uname] = nil
	pendingXmod[uname] = nil
	quietDeadlineMs[uname] = nil
end

local function flushPlayer(uname)
	quietDeadlineMs[uname] = nil
	local buckets = pending[uname]
	local xmodBuckets = pendingXmod[uname]
	if not buckets and not xmodBuckets then return end

	local player = XPR_Env and XPR_Env.findLivePlayerByUsername(uname)
	if not player then return end

	local anyAwarded = false
	local stillPending = false

	for category, total in pairs(buckets or {}) do
		local award = math.floor(total / BUNDLE_THRESHOLD) * BUNDLE_THRESHOLD
		if award > 0 then
			buckets[category] = total - award
			XPR_RankData.addFlatXp(player, category, award, nil, true)
			XPR_RankData.sendXpGain(player, category, award)
			anyAwarded = true
		end
		if buckets[category] and buckets[category] > 0 then
			stillPending = true
		end
	end

	for label, bucket in pairs(xmodBuckets or {}) do
		local award = math.floor(bucket.amount / BUNDLE_THRESHOLD) * BUNDLE_THRESHOLD
		if award > 0 then
			bucket.amount = bucket.amount - award
			XPR_RankData.addFlatXp(player, bucket.category, award, nil, true)
			XPR_RankData.sendXpGain(player, bucket.category, award, label)
			anyAwarded = true
		end
		if bucket.amount > 0 then
			stillPending = true
		end
	end
	if xmodBuckets and not stillPending then
		pendingXmod[uname] = nil
	end
	if anyAwarded then
		XPR_RankData.syncToClient(player)
	end

	if not stillPending then
		pending[uname] = nil
	end
end

local SWEEP_INTERVAL_TICKS = 30
local sweepTicksLeft = SWEEP_INTERVAL_TICKS

local function onTick()
	sweepTicksLeft = sweepTicksLeft - 1
	if sweepTicksLeft > 0 then return end
	sweepTicksLeft = SWEEP_INTERVAL_TICKS

	local now = getTimestampMs and getTimestampMs() or 0
	for uname, deadlineMs in pairs(quietDeadlineMs) do
		if now >= deadlineMs then
			flushPlayer(uname)
		end
	end
end

Events.OnTick.Add(onTick)

return XPR_XpQueue
