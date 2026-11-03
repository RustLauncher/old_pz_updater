if not XPR_Env or not XPR_Env.runsServerLogic() then return end

XPR_RewardBoxServer = XPR_RewardBoxServer or {}

local function performGrant(player, entry)
	if not player or not entry or not entry.itemId then return end

	if XPR_RewardItems and XPR_RewardItems.isXpBonus(entry.itemId) then
		local bonusAmount = XPR_RewardItems.getXpBonusAmount(entry.itemId)
		if bonusAmount > 0 and XPR_RankData then
			XPR_RankData.addFlatXp(player, "Reward Box", bonusAmount)
		end
		return
	end

	local inventory = player:getInventory()
	if not inventory then return end

	local isSkillVhs = XPR_RewardItems and XPR_RewardItems.isSkillVhs(entry.itemId)
	local isRecipeItem = XPR_RewardItems and XPR_RewardItems.isRecipeItem(entry.itemId)
	local grantFullType = entry.itemId
	if isSkillVhs then
		grantFullType = XPR_RewardItems.getSkillVhsFullType(entry.itemId)
	elseif isRecipeItem then
		grantFullType = XPR_RewardItems.getRecipeItemFullType(entry.itemId)
	end
	if not grantFullType then
		XPR_dprint("[XPR] XPR_RewardBoxServer.performGrant: could not resolve FullType for "
			.. tostring(entry.itemId))
		return
	end

	local rolledItem = inventory:AddItem(grantFullType)
	if not rolledItem then
		XPR_dprint("[XPR] XPR_RewardBoxServer.performGrant: AddItem failed for " .. tostring(grantFullType))
		return
	end

	if isSkillVhs then
		local index = XPR_RewardItems.getSkillVhsIndex(entry.itemId)
		if index then
			rolledItem:setRecordedMediaIndexInteger(index)
		end
	elseif isRecipeItem then
		local recipeId = XPR_RewardItems.getRecipeItemId(entry.itemId)
		if recipeId and rolledItem.setLearnedRecipes then
			local recipeList = ArrayList.new()
			recipeList:add(recipeId)
			rolledItem:setLearnedRecipes(recipeList)

			local si = rolledItem.getScriptItem and rolledItem:getScriptItem()
			local baseName = (si and si:getDisplayName()) or grantFullType
			local recipeName = Translator and Translator.getRecipeName and Translator.getRecipeName(recipeId)
			if recipeName and recipeName ~= "" then
				local text = getText("IGUI_MagazineNameNoIssue", baseName, recipeName)
				rolledItem:setName(text)
				rolledItem:getModData().collectibleKey = text
			end
		end
	else
		local si = rolledItem.getScriptItem and rolledItem:getScriptItem()
		local mediaCat = si and si.getRecordedMediaCat and si:getRecordedMediaCat()
		if mediaCat and getZomboidRadio then
			local recordedMedia = getZomboidRadio():getRecordedMedia()
			local mediaData = recordedMedia and recordedMedia:getRandomFromCategory(mediaCat)
			if not mediaData and mediaCat == "Home-VHS" and recordedMedia then
				local mediaList = recordedMedia:getAllMediaForCategory(mediaCat)
				if mediaList and not mediaList:isEmpty() then
					mediaData = mediaList:get(ZombRand(mediaList:size()))
				end
			end
			if mediaData then
				rolledItem:setRecordedMediaData(mediaData)
			end
		end
	end

	if sendAddItemToContainer then
		sendAddItemToContainer(inventory, rolledItem)
	end

	XPR_dprint("[XPR] XPR_RewardBoxServer.performGrant: gave " .. tostring(grantFullType)
		.. " to " .. tostring(player:getUsername()))
end

local function resolvePendingGrants()
	if not XPR_RankData or not XPR_Env then return end
	local now = getTimestampMs and getTimestampMs() or 0

	for _, player in ipairs(XPR_Env.players()) do
		local pd = XPR_RankData.getPlayerData(player)
		if pd and pd.pendingRewardGrants and #pd.pendingRewardGrants > 0 then
			local remaining = {}
			for _, entry in ipairs(pd.pendingRewardGrants) do
				if entry.grantAtMs and now >= entry.grantAtMs then
					performGrant(player, entry)
				else
					remaining[#remaining + 1] = entry
				end
			end
			pd.pendingRewardGrants = remaining
		end

		if pd and pd.pendingRewardBoxes and #pd.pendingRewardBoxes > 0 then
			local boxes = pd.pendingRewardBoxes
			pd.pendingRewardBoxes = nil
			for _, box in ipairs(boxes) do
				XPR_RewardBoxServer.grant(player, box.boxRank, box.variantSeed)
			end
		end
	end
end

local SWEEP_INTERVAL_TICKS = 30
local sweepTicksLeft = SWEEP_INTERVAL_TICKS

local function onTick()
	sweepTicksLeft = sweepTicksLeft - 1
	if sweepTicksLeft > 0 then return end
	sweepTicksLeft = SWEEP_INTERVAL_TICKS
	resolvePendingGrants()
end

Events.OnTick.Add(onTick)

function XPR_RewardBoxServer.grant(player, rank, variantSeed, deferToast)
	if not player or not rank then return false end

	local fullType = XPR_RewardBox.pickVariantFullType(variantSeed or rank)
	local inventory = player:getInventory()
	if not inventory then return false end

	inventory:setDrawDirty(true)
	local item = inventory:AddItem(fullType)
	if not item then
		XPR_dprint("[XPR] XPR_RewardBoxServer.grant: AddItem failed for " .. tostring(fullType))
		return false
	end

	local md = item:getModData()
	md[XPR_RewardBox.KEY_REWARD_RANK] = rank
	md[XPR_RewardBox.KEY_AWARDED_TO] = XPR_RewardBox.resolveAwardedToName(player)

	if sendAddItemToContainer then
		sendAddItemToContainer(inventory, item)
	end
	XPR_RewardBox.applyDisplayName(item)

	XPR_dprint("[XPR] XPR_RewardBoxServer.grant: gave " .. tostring(fullType) .. " (rank="
		.. tostring(rank) .. ") to " .. tostring(player:getUsername()))

	if deferToast then return true end
	XPR_RewardBoxServer.sendBoxReceivedToast(player, rank)
	return true
end

function XPR_RewardBoxServer.sendBoxReceivedToast(player, rank)
	if not player then return end
	if XPR_Env and XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then return end
	XPR_Env.sendToClient(player, "XPRanks", "rewardBoxReceived", { rank = rank })
end

local function findItemById(container, itemID, depth)
	depth = depth or 0
	if not container or depth > 4 then return nil end

	local items = container:getItems()
	for i = 0, items:size() - 1 do
		local it = items:get(i)
		if it then
			if it:getID() == itemID then return it end
			if it.getInventory then
				local nested = it:getInventory()
				if nested then
					local found = findItemById(nested, itemID, depth + 1)
					if found then return found end
				end
			end
		end
	end
	return nil
end

function XPR_RewardBoxServer.openBox(player, itemID)
	if not player or not itemID then return end

	local inventory = player:getInventory()
	if not inventory then return end

	local box = findItemById(inventory, itemID, 0)

	if not box or not XPR_RewardBox.isRewardBox(box) then
		XPR_dprint("[XPR] XPR_RewardBoxServer.openBox: item " .. tostring(itemID)
			.. " not found or not a Reward Box for " .. tostring(player:getUsername()))
		return
	end

	local rank = XPR_RewardBox.getLinkedRank(box)
	if not rank then
		XPR_dprint("[XPR] XPR_RewardBoxServer.openBox: box has no linked rank, aborting")
		return
	end

	local rolledItemId = XPR_RewardConfig.rollItem(rank)
	if not rolledItemId then
		XPR_dprint("[XPR] XPR_RewardBoxServer.openBox: roll returned nil for rank " .. tostring(rank))
		return
	end

	local boxContainer = box:getContainer()
	if boxContainer then
		boxContainer:Remove(box)
		boxContainer:setDrawDirty(true)
		if sendRemoveItemFromContainer then
			sendRemoveItemFromContainer(boxContainer, box)
		end
	end

	if XPR_RankData then
		local pd = XPR_RankData.getPlayerData(player)
		if pd then
			pd.pendingRewardGrants = pd.pendingRewardGrants or {}
			pd.pendingRewardGrants[#pd.pendingRewardGrants + 1] = {
				itemId = rolledItemId,
				rank = rank,
				grantAtMs = (getTimestampMs and getTimestampMs() or 0) + XPR_RewardBox.SPIN_DURATION_MS,
			}
		end
	end

	XPR_dprint("[XPR] XPR_RewardBoxServer.openBox: " .. tostring(player:getUsername())
		.. " opened rank=" .. tostring(rank) .. " box -> " .. tostring(rolledItemId))

	if XPR_Env and XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then return end
	XPR_Env.sendToClient(player, "XPRanks", "rewardBoxResult", { itemId = rolledItemId, rank = rank })
end

local OPEN_BOX_COOLDOWN_MS = 500
local DEBUG_REWARD_BOX_COOLDOWN_MS = 500

local function sendDebugRewardBoxResult(player, code, rank, targetUsername)
	if not player or not XPR_Env then return end
	if XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then return end
	local payload = { code = code }
	if code == "success" or code == "queued" then
		payload.rank = rank
		payload.targetUsername = targetUsername
	end
	XPR_Env.sendToClient(player, "XPRanks", "debugRewardBoxResult", payload)
end

local function sendDebugPlayersDataResult(player, code)
	if not player or not XPR_Env then return end
	if XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then return end
	XPR_Env.sendToClient(player, "XPRanks", "debugPlayersDataResult", { code = code })
end

local function storedUsernameExists(username)
	if not XPR_RankData or not XPR_RankData.getAllPlayers then return false end
	for _, entry in ipairs(XPR_RankData.getAllPlayers() or {}) do
		if entry and entry.username == username then return true end
	end
	return false
end

local function handleDebugAddRewardBox(player, args)
	if not player then return end
	if not XPR_AdminAccess or not XPR_AdminAccess.hasDebugCmdAccess
			or not XPR_AdminAccess.hasDebugCmdAccess(player) then
		sendDebugRewardBoxResult(player, "rejectedSender")
		return
	end
	if XPR_Env and not XPR_Env.checkCooldown("debugAddRewardBox", player, DEBUG_REWARD_BOX_COOLDOWN_MS) then
		return
	end
	if type(args) ~= "table" or type(args.targetUsername) ~= "string"
			or args.targetUsername == "" or #args.targetUsername > 64 then
		sendDebugRewardBoxResult(player, "malformed")
		return
	end

	local rank = args.rank
	local maximumRank = (XPR_RankCurve and XPR_RankCurve.MAX_RANK) or 999
	if type(rank) ~= "number" or rank ~= rank or rank < 1 or rank > maximumRank
			or math.floor(rank) ~= rank then
		sendDebugRewardBoxResult(player, "invalidRank")
		return
	end

	local targetUsername = args.targetUsername
	local targetPlayer = XPR_Env and XPR_Env.findLivePlayerByUsername
		and XPR_Env.findLivePlayerByUsername(targetUsername)
	local targetIsStored = storedUsernameExists(targetUsername)
	if not targetPlayer and not targetIsStored then
		sendDebugRewardBoxResult(player, "invalidTarget")
		return
	end

	if targetPlayer then
		if XPR_RewardBoxServer.grant(targetPlayer, rank) then
			sendDebugRewardBoxResult(player, "success", rank, targetUsername)
		else
			sendDebugRewardBoxResult(player, "deliveryFailed")
		end
		return
	end

	if not XPR_RankData or not XPR_RankData.getPlayerDataByUsername then
		sendDebugRewardBoxResult(player, "deliveryFailed")
		return
	end
	local targetData = XPR_RankData.getPlayerDataByUsername(targetUsername)
	if not targetData then
		sendDebugRewardBoxResult(player, "deliveryFailed")
		return
	end
	targetData.pendingRewardBoxes = targetData.pendingRewardBoxes or {}
	targetData.pendingRewardBoxes[#targetData.pendingRewardBoxes + 1] = {
		boxRank = rank,
		variantSeed = nil,
	}
	sendDebugRewardBoxResult(player, "queued", rank, targetUsername)
end

local function handleDebugPlayersData(player)
	if not player then return end
	if not XPR_AdminAccess or not XPR_AdminAccess.hasDebugCmdAccess
			or not XPR_AdminAccess.hasDebugCmdAccess(player) then
		local configuredUsername = XPR_Config and XPR_Config.DEBUG_AUTHOR_USERNAME
		XPR_dprint("[XPR] Debug player-list request rejected for "
			.. tostring(player.getUsername and player:getUsername())
			.. " debug=" .. tostring(XPR_Config and XPR_Config.DEBUG == true)
			.. " usernameConfigured=" .. tostring(type(configuredUsername) == "string"
			and configuredUsername ~= ""))
		sendDebugPlayersDataResult(player, "rejectedSender")
		return
	end
	if XPR_Env and not XPR_Env.checkCooldown("debugGetPlayersData", player, 1000) then
		XPR_dprint("[XPR] Debug player-list request rate-limited for "
			.. tostring(player.getUsername and player:getUsername()))
		sendDebugPlayersDataResult(player, "cooldown")
		return
	end
	if XPR_RankData and XPR_RankData.sendPlayersData then
		if XPR_RankData.sendPlayersData(player) then return end
	else
		XPR_dprint("[XPR] Debug player-list request has no RankData sender")
	end
	sendDebugPlayersDataResult(player, "notReady")
end

local function onClientCommand(module, command, player, args)
	if module ~= "XPRanks" then return end
	if command == "getDebugPlayersData" then
		handleDebugPlayersData(player)
	elseif command == "addRewardBox" then
		handleDebugAddRewardBox(player, args)
	elseif command == "openRewardBox" then
		if not player or not args or not args.itemID then return end
		if XPR_Env and not XPR_Env.checkCooldown("openRewardBox", player, OPEN_BOX_COOLDOWN_MS) then return end
		XPR_RewardBoxServer.openBox(player, args.itemID)
	end
end

Events.OnClientCommand.Add(onClientCommand)

return XPR_RewardBoxServer
