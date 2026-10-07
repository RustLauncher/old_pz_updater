XPR_RewardBox = XPR_RewardBox or {}

XPR_RewardBox.KEY_REWARD_RANK = "xpr_rewardRank"
XPR_RewardBox.KEY_AWARDED_TO = "xpr_awardedTo"

XPR_RewardBox.FULL_TYPES = {
	"XPRanks.XPR_RewardBox1",
	"XPRanks.XPR_RewardBox2",
	"XPRanks.XPR_RewardBox3",
	"XPRanks.XPR_RewardBox4",
	"XPRanks.XPR_RewardBox5",
}

local FULL_TYPE_SET = {}
for _, ft in ipairs(XPR_RewardBox.FULL_TYPES) do
	FULL_TYPE_SET[ft] = true
end

XPR_RewardBox.SPIN_DURATION_MS = 7000

function XPR_RewardBox.isRewardBox(item)
	if not item or not item.getFullType then return false end
	return FULL_TYPE_SET[item:getFullType()] == true
end

function XPR_RewardBox.pickVariantFullType(rank)
	rank = rank or 1
	local interval = (XPR_RewardConfig and XPR_RewardConfig.getBoxInterval and XPR_RewardConfig.getBoxInterval()) or 5
	local boxNumber = math.floor(rank / interval)
	if boxNumber < 1 then boxNumber = 1 end
	local index = ((boxNumber - 1) % #XPR_RewardBox.FULL_TYPES) + 1
	return XPR_RewardBox.FULL_TYPES[index]
end

function XPR_RewardBox.getLinkedRank(item)
	if not item or not item.getModData then return nil end
	local md = item:getModData()
	if not md then return nil end
	return tonumber(md[XPR_RewardBox.KEY_REWARD_RANK])
end

function XPR_RewardBox.buildDisplayName(rank)
	rank = rank or 1

	if XPR_RankCurve and rank >= XPR_RankCurve.MAX_RANK then
		local maxText = getText and getText("IGUI_XPR_RewardBox_MaxRankName")
		if maxText and maxText ~= "" and maxText ~= "IGUI_XPR_RewardBox_MaxRankName" then
			return maxText
		end
		return "Max Rank Reward Box"
	end

	local text = getText and getText("IGUI_XPR_RewardBox_Name", tostring(rank))
	if text and text ~= "" and text ~= "IGUI_XPR_RewardBox_Name" then
		return text
	end
	return "Rank " .. tostring(rank) .. " Reward Box"
end

function XPR_RewardBox.resolveAwardedToName(player)
	if not player or not player.getUsername then return "" end
	local uname = player:getUsername() or ""

	if XPR_Env and XPR_Env.isTrueSinglePlayer() and player.getDescriptor then
		local descriptor = player:getDescriptor()
		if descriptor and descriptor.getForename then
			local forename = descriptor:getForename()
			if forename and forename ~= "" and uname:sub(1, #forename) == forename then
				local surname = uname:sub(#forename + 1)
				if surname ~= "" then return forename .. " " .. surname end
			end
		end
	end

	return uname
end

function XPR_RewardBox.getAwardedTo(item)
	if not item or not item.getModData then return nil end
	local md = item:getModData()
	if not md then return nil end
	local name = md[XPR_RewardBox.KEY_AWARDED_TO]
	if not name or name == "" then return nil end
	return name
end

function XPR_RewardBox.applyDisplayName(item)
	if not item then return end
	local rank = XPR_RewardBox.getLinkedRank(item)
	if not rank then return end
	item:setName(XPR_RewardBox.buildDisplayName(rank))
	item:setCustomName(true)

	local awardedTo = XPR_RewardBox.getAwardedTo(item)
	if awardedTo then
		local tooltip = getText and getText("IGUI_XPR_RewardBox_AwardedTo", awardedTo)
		if not tooltip or tooltip == "" or tooltip == "IGUI_XPR_RewardBox_AwardedTo" then
			tooltip = "Awarded To: " .. awardedTo
		end
		item:setTooltip(tooltip)
	end

	item:syncItemFields()
end

return XPR_RewardBox
