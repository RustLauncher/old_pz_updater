XPR_RewardConfig = XPR_RewardConfig or {}

local rng = newrandom()

XPR_RewardConfig.DEFAULT_BOX_INTERVAL = 5

function XPR_RewardConfig.getBoxInterval()
	if XPR_SettingsStore and XPR_SettingsStore.getRewardBoxInterval then
		return XPR_SettingsStore.getRewardBoxInterval()
	end
	return XPR_RewardConfig.DEFAULT_BOX_INTERVAL
end

XPR_RewardConfig.DEFAULT_GRANT_REWARD_BOXES = true

function XPR_RewardConfig.getGrantRewardBoxes()
	if XPR_SettingsStore and XPR_SettingsStore.getGrantRewardBoxes then
		return XPR_SettingsStore.getGrantRewardBoxes()
	end
	return XPR_RewardConfig.DEFAULT_GRANT_REWARD_BOXES
end

XPR_RewardConfig.TIERS = {
	{
		name = "Tier 1",
		minRank = 1,
		maxRank = 99,
		weights = { COMMON = 0.70, UNCOMMON = 0.25, RARE = 0.05 },
	},
	{
		name = "Tier 2",
		minRank = 100,
		maxRank = 300,
		weights = { COMMON = 0.35, UNCOMMON = 0.45, RARE = 0.20 },
	},
	{
		name = "Tier 3",
		minRank = 301,
		maxRank = math.huge,
		weights = { COMMON = 0.10, UNCOMMON = 0.30, RARE = 0.60 },
	},
}

function XPR_RewardConfig.getTiers()
	if XPR_SettingsStore and XPR_SettingsStore.getTiers then
		return XPR_SettingsStore.getTiers()
	end
	return XPR_RewardConfig.TIERS
end

function XPR_RewardConfig.getTierForRank(rank)
	rank = rank or 1
	local tiers = XPR_RewardConfig.getTiers()
	for _, tier in ipairs(tiers) do
		if rank >= tier.minRank and rank <= tier.maxRank then
			return tier
		end
	end
	return tiers[#tiers]
end

function XPR_RewardConfig.rollBand(rank)
	local tier = XPR_RewardConfig.getTierForRank(rank)
	local roll = rng:random(0, 9999) / 10000.0
	local acc = 0
	local order = { "COMMON", "UNCOMMON", "RARE" }
	for _, band in ipairs(order) do
		acc = acc + (tier.weights[band] or 0)
		if roll < acc then
			return band
		end
	end
	return order[#order]
end

function XPR_RewardConfig.rollItem(rank)
	local band = XPR_RewardConfig.rollBand(rank)
	local pool = XPR_RewardItems and XPR_RewardItems.getEffectivePool(band)
	if not pool or #pool == 0 then return nil end
	return pool[rng:random(1, #pool)]
end

return XPR_RewardConfig
