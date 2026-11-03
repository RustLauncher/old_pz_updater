XPR_RankCurve = XPR_RankCurve or {}

XPR_RankCurve.BASE_XP = 40
XPR_RankCurve.STEP = 20

function XPR_RankCurve.getBaseXp()
	if XPR_SettingsStore and XPR_SettingsStore.getRankCurveBaseXp then
		return XPR_SettingsStore.getRankCurveBaseXp()
	end
	return XPR_RankCurve.BASE_XP
end

function XPR_RankCurve.getStep()
	if XPR_SettingsStore and XPR_SettingsStore.getRankCurveStep then
		return XPR_SettingsStore.getRankCurveStep()
	end
	return XPR_RankCurve.STEP
end

XPR_RankCurve.MAX_RANK = 999

function XPR_RankCurve.requiredXp(rank)
	if rank <= 1 then return 0 end
	return XPR_RankCurve.getBaseXp() + XPR_RankCurve.getStep() * (rank - 2)
end

function XPR_RankCurve.cumulativeXpForRank(rank)
	if not rank or rank <= 1 then return 0 end

	local base, step = XPR_RankCurve.getBaseXp(), XPR_RankCurve.getStep()
	local n = rank - 1
	return n * base + step * ((n - 1) * n) / 2
end

function XPR_RankCurve.getRankForXp(totalXp)
	if not totalXp or totalXp <= 0 then return 1 end

	local base, step = XPR_RankCurve.getBaseXp(), XPR_RankCurve.getStep()
	local rank
	if step == 0 then
		rank = 1 + math.floor(totalXp / base)
	else
		local a = step / 2
		local b = base - step / 2
		local disc = b * b + 4 * a * totalXp
		local k = (-b + math.sqrt(disc)) / (2 * a)
		rank = 1 + math.floor(k + 1e-9)
	end

	if rank < 1 then rank = 1 end
	if rank > XPR_RankCurve.MAX_RANK then rank = XPR_RankCurve.MAX_RANK end
	return rank
end

return XPR_RankCurve
