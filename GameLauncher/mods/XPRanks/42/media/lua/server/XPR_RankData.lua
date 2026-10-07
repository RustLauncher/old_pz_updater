if not XPR_Env or not XPR_Env.runsServerLogic() then return end

XPR_RankData = XPR_RankData or {}

require "XPR_Identity"

local STORE_KEY = "XPR_PlayerStore"
local SP_KEY = "XPR_SP"

local pendingRankUp = {}

local SWEEP_INTERVAL_TICKS = 30
local sweepTicksLeft = SWEEP_INTERVAL_TICKS

local function onRankUpTick()
	sweepTicksLeft = sweepTicksLeft - 1
	if sweepTicksLeft > 0 then return end
	sweepTicksLeft = SWEEP_INTERVAL_TICKS

	local now = getTimestampMs and getTimestampMs() or 0
	for uname, entry in pairs(pendingRankUp) do
		if now >= entry.deadlineMs then
			pendingRankUp[uname] = nil
			local pd = XPR_RankData.getPlayerData(entry.player)
			if pd and pd.rank and pd.rank > 1 then
				XPR_RankData.showRankUpToast(entry.player, pd.rank)
			end

			if entry.boxToastRanks and XPR_RewardBoxServer and XPR_RewardBoxServer.sendBoxReceivedToast then
				for _, boxRank in ipairs(entry.boxToastRanks) do
					XPR_RewardBoxServer.sendBoxReceivedToast(entry.player, boxRank)
				end
			end
		end
	end
end

Events.OnTick.Add(onRankUpTick)

local function defaultData()
	return {
		rank = 1,
		totalXp = 0,
		categories = {},
		maxRankVirtualLevel = 0,
		timeSurvivedRemainderHours = 0,
		travelWalkRemainderTiles = 0,
		travelDriveRemainderTiles = 0,
	}
end

local function copyCategories(categories)
	local copy = {}
	for category, amount in pairs(categories or {}) do
		copy[category] = amount
	end
	return copy
end

local function wipeProgressData(pd)
	if not pd then return end
	pd.rank = 1
	pd.totalXp = 0
	pd.categories = {}
	pd.maxRankVirtualLevel = 0
	pd.timeSurvivedRemainderHours = 0
	pd.travelWalkRemainderTiles = 0
	pd.travelDriveRemainderTiles = 0
	pd.pendingRewardGrants = nil
	pd.pendingRewardBoxes = nil
end

function XPR_RankData.wipePlayerProgressByUsername(uname)
	if not uname then return nil end
	local store = ModData.getOrCreate(STORE_KEY)
	local pd = store.players and store.players[uname]
	if not pd then return nil end
	wipeProgressData(pd)
	return pd
end

local function getSPStore()
	local store = ModData.getOrCreate(SP_KEY)
	store.history = store.history or {}
	return store
end

local function createCharacterId()
	local timestamp = getTimestampMs and getTimestampMs() or 0
	local randomPart = ZombRand and ZombRand(100000) or 0
	return tostring(timestamp) .. "_" .. tostring(randomPart)
end

local historyRefCache = {}

function XPR_RankData.syncSPHistory(player, pd)
	if not (XPR_Env and XPR_Env.isSP()) then return end
	if not player or not pd or not pd._id then return end

	local store = getSPStore()
	local historyEntry = historyRefCache[pd._id]
	if not historyEntry then
		for _, entry in ipairs(store.history) do
			if entry.id == pd._id then
				historyEntry = entry
				break
			end
		end
		if not historyEntry then
			historyEntry = { id = pd._id }
			store.history[#store.history + 1] = historyEntry
		end
		historyRefCache[pd._id] = historyEntry
	end

	historyEntry.name = XPR_Identity.displayName(player)
	historyEntry.rank = pd.rank or 1
	historyEntry.totalXp = pd.totalXp or 0
	historyEntry.categories = copyCategories(pd.categories)
	historyEntry.maxRankVirtualLevel = pd.maxRankVirtualLevel or 0
end

function XPR_RankData.getPlayerDataByUsername(uname)
	if not uname then return defaultData() end

	if XPR_Env and XPR_Env.isSP() then
		local player = getSpecificPlayer(0)
		if player and player:getUsername() == uname then
			return XPR_RankData.getPlayerData(player)
		end
		return defaultData()
	end

	local store = ModData.getOrCreate(STORE_KEY)
	if not store.players then store.players = {} end
	if not store.players[uname] then
		store.players[uname] = defaultData()
	end
	local pd = store.players[uname]

	if pd.rank and pd.rank > XPR_RankCurve.MAX_RANK then
		pd.rank = XPR_RankCurve.MAX_RANK
	end

	return pd
end

function XPR_RankData.getPlayerData(player)
	if not player then return defaultData() end
	local uname = player:getUsername()
	if not uname then return defaultData() end

	if XPR_Env and XPR_Env.isSP() then
		local md = player:getModData()
		local store = getSPStore()
		local adoptedLegacyData = nil
		if store.data then
			for legacyName, legacyData in pairs(store.data) do
				if not md.XPR and legacyName == uname then
					adoptedLegacyData = legacyData
				else
					local legacyId = legacyData._id or ("legacy_" .. tostring(legacyName))
					local alreadyRecorded = false
					for _, entry in ipairs(store.history) do
						if entry.id == legacyId then
							alreadyRecorded = true
							break
						end
					end
					if not alreadyRecorded then
						store.history[#store.history + 1] = {
							id = legacyId,
							name = legacyName,
							rank = legacyData.rank or 1,
							totalXp = legacyData.totalXp or 0,
							categories = copyCategories(legacyData.categories),
							maxRankVirtualLevel = legacyData.maxRankVirtualLevel or 0,
						}
					end
				end
			end
			store.data = nil
		end
		if not md.XPR then
			if adoptedLegacyData then
				md.XPR = adoptedLegacyData
				XPR_dprint("[XPR] Migrated legacy SP Rank data to character "
					.. tostring(XPR_Identity.displayName(player)))
			else
				md.XPR = defaultData()
			end
		end

		local pd = md.XPR
		if not pd._id then pd._id = createCharacterId() end
		if pd.rank and pd.rank > XPR_RankCurve.MAX_RANK then
			pd.rank = XPR_RankCurve.MAX_RANK
		end
		pd.categories = pd.categories or {}
		if pd.maxRankVirtualLevel == nil then pd.maxRankVirtualLevel = 0 end
		XPR_RankData.syncSPHistory(player, pd)
		return pd
	end

	return XPR_RankData.getPlayerDataByUsername(uname)
end

function XPR_RankData.getAllPlayers()
	if XPR_Env and XPR_Env.isSP() then
		local player = getSpecificPlayer(0)
		if not player then return {} end
		local pd = XPR_RankData.getPlayerData(player)
		return { {
			username = player:getUsername(),
			rank = pd.rank or 1,
			totalXp = pd.totalXp or 0,
		} }
	end

	local store = ModData.getOrCreate(STORE_KEY)
	local playersTable = store.players
	if not playersTable then
		playersTable = {}
		store.players = playersTable
	end

	local result = {}
	local included = {}
	for uname, pd in pairs(playersTable) do
		result[#result + 1] = { username = uname, rank = pd.rank or 1, totalXp = pd.totalXp or 0 }
		included[uname] = true
	end

	if XPR_Env and XPR_Env.players then
		for _, player in ipairs(XPR_Env.players()) do
			if player and player.getUsername then
				local uname = player:getUsername()
				if uname and not included[uname] then
					local pd = XPR_RankData.getPlayerData(player)
					result[#result + 1] = {
						username = uname,
						rank = pd.rank or 1,
						totalXp = pd.totalXp or 0,
					}
					included[uname] = true
				end
			end
		end
	end

	table.sort(result, function(a, b) return a.username < b.username end)
	return result
end

local function pruneDeadStoreEntries()
	if XPR_Env and XPR_Env.isSP() then return end
	local store = ModData.getOrCreate(STORE_KEY)
	if not store.players then return end

	local online = {}
	if XPR_Env then
		for _, p in ipairs(XPR_Env.players()) do
			if p and p.getUsername then online[p:getUsername()] = true end
		end
	end

	local pruned = 0
	for uname, pd in pairs(store.players) do
		if not online[uname] and (pd.totalXp or 0) == 0 then
			store.players[uname] = nil
			pruned = pruned + 1
		end
	end
	if pruned > 0 then
		XPR_dprint("[XPR] pruneDeadStoreEntries: removed " .. pruned
			.. " zero-XP offline entries from XPR_PlayerStore")
	end
end

Events.EveryTenMinutes.Add(function()
	if not XPR_Env or not XPR_Env.runsServerLogic() then return end
	pruneDeadStoreEntries()
end)

local function onCharacterDeath(character)
	if not (XPR_Env and XPR_Env.runsServerLogic()) then return end
	if not (character and instanceof and instanceof(character, "IsoPlayer")) then return end

	if XPR_Env.isSP() then
		local md = character:getModData()
		if not md.XPR then return end
		XPR_RankData.syncSPHistory(character, md.XPR)
		if md.XPR._id then historyRefCache[md.XPR._id] = nil end
		local uname = character:getUsername()
		if uname then pendingRankUp[uname] = nil end
		if XPR_XpQueue and XPR_XpQueue.clearPlayer then
			XPR_XpQueue.clearPlayer(character)
		end
		md.XPR = nil
		XPR_dprint("[XPR] Finalized SP Hall of Fame entry for "
			.. tostring(XPR_Identity.displayName(character)))
		return
	end

	if not (XPR_SettingsStore and XPR_SettingsStore.getResetRankOnDeath
			and XPR_SettingsStore.getResetRankOnDeath()) then
		return
	end
	local uname = character.getUsername and character:getUsername()
	if not uname then return end
	local wiped = XPR_RankData.wipePlayerProgressByUsername(uname)
	if not wiped then return end
	if pendingRankUp[uname] then pendingRankUp[uname] = nil end
	if XPR_XpQueue and XPR_XpQueue.clearPlayer then
		XPR_XpQueue.clearPlayer(character)
	end
	XPR_RankData.syncToClient(character)
	XPR_dprint("[XPR] XPR_RankData.onCharacterDeath: progress wiped for "
		.. tostring(uname) .. " (resetRankOnDeath=true)")
end

Events.OnCharacterDeath.Add(onCharacterDeath)

local function findLivePlayerByUsername(uname)
	if not uname or not XPR_Env then return nil end
	return XPR_Env.findLivePlayerByUsername(uname)
end

local function clampXpAward(flatXp)
	local amount = tonumber(flatXp) or 0
	if amount <= 0 then return nil end
	amount = math.floor(amount)
	local maximum = (XPR_Config and XPR_Config.MAX_XP_PER_AWARD) or 100000
	if amount > maximum then
		XPR_dprint("[XPR] WARNING: XP award clamped from " .. tostring(amount)
			.. " to " .. tostring(maximum))
		amount = maximum
	end
	return amount
end

local function grantRewardBoxesForRange(player, firstLevel, lastLevel, rewardRank, deferToasts, offlinePd)
	if XPR_RewardConfig and XPR_RewardConfig.getGrantRewardBoxes and not XPR_RewardConfig.getGrantRewardBoxes() then
		return
	end
	if not XPR_RewardBoxServer or not XPR_RewardBoxServer.grant then return end
	if not firstLevel or not lastLevel or lastLevel < firstLevel then return end

	local interval = (XPR_RewardConfig and XPR_RewardConfig.getBoxInterval and XPR_RewardConfig.getBoxInterval()) or 5
	if interval < 1 then interval = 5 end
	local firstRewardLevel = math.floor((firstLevel - 1) / interval) * interval + interval
	if firstRewardLevel > lastLevel then return end

	local totalDue = math.floor((lastLevel - firstRewardLevel) / interval) + 1
	local maximum = (XPR_Config and XPR_Config.MAX_REWARD_BOXES_PER_AWARD) or 50
	local grantCount = math.min(totalDue, maximum)
	for index = 0, grantCount - 1 do
		local level = firstRewardLevel + index * interval
		local boxRank = level
		local variantSeed = nil
		if rewardRank then
			boxRank = rewardRank
			variantSeed = level
		end

		if offlinePd then
			offlinePd.pendingRewardBoxes = offlinePd.pendingRewardBoxes or {}
			offlinePd.pendingRewardBoxes[#offlinePd.pendingRewardBoxes + 1] =
				{ boxRank = boxRank, variantSeed = variantSeed }
		else
			local uname = deferToasts and player.getUsername and player:getUsername()
			local pendingEntry = uname and pendingRankUp[uname]
			if pendingEntry then
				XPR_RewardBoxServer.grant(player, boxRank, variantSeed, true)
				pendingEntry.boxToastRanks = pendingEntry.boxToastRanks or {}
				pendingEntry.boxToastRanks[#pendingEntry.boxToastRanks + 1] = boxRank
			else
				XPR_RewardBoxServer.grant(player, boxRank, variantSeed)
			end
		end
	end

	if totalDue > maximum then
		XPR_dprint("[XPR] WARNING: Reward Box catch-up limited to " .. tostring(maximum)
			.. " boxes; skipped " .. tostring(totalDue - maximum)
			.. " pathological catch-up grants")
	end
end

function XPR_RankData.addFlatXp(player, perkName, flatXp, debugLabel, skipSync)
	if not player then return end
	if not XPR_Env or not XPR_Env.runsServerLogic() then return end
	flatXp = clampXpAward(flatXp)
	if not flatXp then return end

	local pd = XPR_RankData.getPlayerData(player)
	local oldRank = pd.rank or 0
	local oldTotalXp = pd.totalXp or 0

	pd.totalXp = oldTotalXp + flatXp
	pd.rank = XPR_RankCurve.getRankForXp(pd.totalXp)

	pd.categories = pd.categories or {}
	if perkName then
		pd.categories[perkName] = (pd.categories[perkName] or 0) + flatXp
	end

	local uname = player:getUsername() or "unknown"
	XPR_dprint("[XPR] " .. uname .. " +" .. tostring(flatXp) .. " Rank XP from " .. tostring(debugLabel or perkName) .. " (total=" .. tostring(pd.totalXp) .. ", rank=" .. tostring(pd.rank) .. ")")

	triggerEvent("XPR_OnXpGained", player, {
		oldXp = oldTotalXp,
		newXp = pd.totalXp,
		category = perkName,
		amount = flatXp,
	})

	if pd.rank > oldRank then
		triggerEvent("XPR_OnRankUp", player, { oldRank = oldRank, newRank = pd.rank })
		XPR_dprint("[XPR] " .. uname .. " RANK UP! " .. tostring(oldRank) .. " -> " .. tostring(pd.rank))
		XPR_RankData.scheduleRankUpToast(player)

		grantRewardBoxesForRange(player, oldRank + 1, pd.rank, nil, true)

		if XPR_Backup and XPR_Backup.autoBackup then
			XPR_Backup.autoBackup()
		end
	end

	if pd.rank >= XPR_RankCurve.MAX_RANK and XPR_RewardBoxServer and XPR_RewardBoxServer.grant then
		local virtualLevelXp = XPR_RankCurve.requiredXp(XPR_RankCurve.MAX_RANK + 1)
		if virtualLevelXp > 0 then
			local capBaseXp = XPR_RankCurve.cumulativeXpForRank(XPR_RankCurve.MAX_RANK)
			local xpPastCap = pd.totalXp - capBaseXp
			if xpPastCap < 0 then xpPastCap = 0 end
			local virtualLevel = math.floor(xpPastCap / virtualLevelXp)
			local lastLevel = pd.maxRankVirtualLevel or 0

			if virtualLevel > lastLevel then
				grantRewardBoxesForRange(player, lastLevel + 1, virtualLevel,
					XPR_RankCurve.MAX_RANK)
				pd.maxRankVirtualLevel = virtualLevel
			end
		end
	end

	if not skipSync then
		XPR_RankData.syncToClient(player)
	end
end

function XPR_RankData.addFlatXpOffline(uname, perkName, flatXp, debugLabel)
	if not uname then return end
	if not XPR_Env or not XPR_Env.runsServerLogic() then return end
	flatXp = clampXpAward(flatXp)
	if not flatXp then return end

	local pd = XPR_RankData.getPlayerDataByUsername(uname)
	if not pd then return end
	local oldRank = pd.rank or 0
	pd.totalXp = (pd.totalXp or 0) + flatXp
	pd.rank = XPR_RankCurve.getRankForXp(pd.totalXp)

	pd.categories = pd.categories or {}
	if perkName then
		pd.categories[perkName] = (pd.categories[perkName] or 0) + flatXp
	end

	XPR_dprint("[XPR] (offline) " .. uname .. " +" .. tostring(flatXp) .. " Rank XP from "
		.. tostring(debugLabel or perkName) .. " (total=" .. tostring(pd.totalXp) .. ", rank=" .. tostring(pd.rank) .. ")")

	if pd.rank > oldRank then
		grantRewardBoxesForRange(nil, oldRank + 1, pd.rank, nil, false, pd)
	end

	if pd.rank >= XPR_RankCurve.MAX_RANK then
		local virtualLevelXp = XPR_RankCurve.requiredXp(XPR_RankCurve.MAX_RANK + 1)
		if virtualLevelXp > 0 then
			local capBaseXp = XPR_RankCurve.cumulativeXpForRank(XPR_RankCurve.MAX_RANK)
			local xpPastCap = pd.totalXp - capBaseXp
			if xpPastCap < 0 then xpPastCap = 0 end
			local virtualLevel = math.floor(xpPastCap / virtualLevelXp)
			local lastLevel = pd.maxRankVirtualLevel or 0
			if virtualLevel > lastLevel then
				grantRewardBoxesForRange(nil, lastLevel + 1, virtualLevel,
					XPR_RankCurve.MAX_RANK, false, pd)
				pd.maxRankVirtualLevel = virtualLevel
			end
		end
	end
end

function XPR_RankData.syncToClient(player)
	if not player then
		XPR_dprint("[XPR] syncToClient: called with nil player, aborting")
		return
	end
	if XPR_Env and XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then
		XPR_dprint("[XPR] syncToClient: dedicated + network not ready, aborting for "
			.. tostring(player:getUsername()))
		return
	end

	local pd = XPR_RankData.getPlayerData(player)
	XPR_dprint("[XPR] syncToClient: sending syncRank to " .. tostring(player:getUsername())
		.. " rank=" .. tostring(pd.rank) .. " totalXp=" .. tostring(pd.totalXp))
	XPR_Env.sendToClient(player, "XPRanks", "syncRank", {
		rank = pd.rank,
		totalXp = pd.totalXp,
	})
	XPR_dprint("[XPR] syncToClient: sendToClient call completed")
end

function XPR_RankData.sendXpGain(player, category, amount, tickerLabel)
	if not player then return end
	if not category or not amount or amount <= 0 then return end
	if XPR_Env and XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then return end
	XPR_Env.sendToClient(player, "XPRanks", "xpGain",
		{ category = category, amount = amount, label = tickerLabel })
end

function XPR_RankData.scheduleRankUpToast(player)
	if not player or not player.getUsername then return end
	local uname = player:getUsername()
	if not uname then return end
	local existing = pendingRankUp[uname]
	local quietMs = (XPR_Config and XPR_Config.NOTIFICATION_QUIET_MS) or 3000
	pendingRankUp[uname] = {
		player = player,
		deadlineMs = (getTimestampMs and getTimestampMs() or 0) + quietMs,
		boxToastRanks = (existing and existing.boxToastRanks) or nil,
	}
end

function XPR_RankData.showRankUpToast(player, rank)
	if not player then return end
	if not rank or rank <= 1 then return end
	if XPR_Env and XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then return end
	XPR_Env.sendToClient(player, "XPRanks", "rankUp", { rank = rank })
end

function XPR_RankData.sendPlayersData(player)
	if not player then return false end
	local players = XPR_RankData.getAllPlayers()
	if XPR_Env and XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then return false end
	XPR_Env.sendToClient(player, "XPRanks", "playersData", { players = players })
	return true
end

local BULK_OP_BATCH_SIZE = 50
local BULK_OP_SWEEP_INTERVAL_TICKS = 30
local bulkOpSweepTicksLeft = BULK_OP_SWEEP_INTERVAL_TICKS
local bulkOp = nil

local function startBulkOp(kind, requestedBy, usernames, rank, xpIntoRank, amount)
	bulkOp = {
		kind = kind,
		usernames = usernames,
		index = 1,
		rank = rank,
		xpIntoRank = xpIntoRank,
		amount = amount,
		requestedBy = requestedBy,
	}
	XPR_dprint("[XPR] Admin " .. kind .. " started for " .. #usernames
		.. " selected players (chunked, " .. BULK_OP_BATCH_SIZE
		.. "/sweep), requested by " .. tostring(requestedBy))
end

local function processBulkOpBatch()
	if not bulkOp then return end
	local finish = math.min(bulkOp.index + BULK_OP_BATCH_SIZE - 1, #bulkOp.usernames)
	for i = bulkOp.index, finish do
		local uname = bulkOp.usernames[i]
		if bulkOp.kind == "set" then
			local pd = XPR_RankData.getPlayerDataByUsername(uname)
			pd.rank = bulkOp.rank
			pd.totalXp = XPR_RankCurve.cumulativeXpForRank(bulkOp.rank) + bulkOp.xpIntoRank
			local live = findLivePlayerByUsername(uname)
			if live then XPR_RankData.syncToClient(live) end
		elseif bulkOp.kind == "addxp" then
			local live = findLivePlayerByUsername(uname)
			if live then
				XPR_RankData.addFlatXp(live, nil, bulkOp.amount, "Admin")
			else
				XPR_RankData.addFlatXpOffline(uname, nil, bulkOp.amount, "Admin")
			end
		else
			local pd = XPR_RankData.getPlayerDataByUsername(uname)
			wipeProgressData(pd)
			local live = findLivePlayerByUsername(uname)
			if live then XPR_RankData.syncToClient(live) end
		end
	end
	bulkOp.index = finish + 1
	if bulkOp.index > #bulkOp.usernames then
		XPR_dprint("[XPR] Admin " .. bulkOp.kind .. " finished for " .. #bulkOp.usernames
			.. " players, requested by " .. tostring(bulkOp.requestedBy))
		local requester = bulkOp.requestedBy and findLivePlayerByUsername(bulkOp.requestedBy)
		if requester and XPR_Env then
			XPR_Env.sendToClient(requester, "XPRanks", "bulkOpResult", {
				kind = bulkOp.kind,
				count = #bulkOp.usernames,
			})
		end
		bulkOp = nil
	end
end

Events.OnTick.Add(function()
	if not bulkOp then return end
	bulkOpSweepTicksLeft = bulkOpSweepTicksLeft - 1
	if bulkOpSweepTicksLeft > 0 then return end
	bulkOpSweepTicksLeft = BULK_OP_SWEEP_INTERVAL_TICKS
	if not XPR_Env or not XPR_Env.runsServerLogic() then return end
	processBulkOpBatch()
end)

local ADMIN_ONLY_COMMANDS = {
	getPlayersData = true,
	resetRank = true,
	setRank = true,
	addXp = true,
}

local REQUEST_SYNC_COOLDOWN_MS = 1000

local function onClientCommand(module, command, player, args)
	if module ~= "XPRanks" then return end
	XPR_dprint("[XPR] XPR_RankData.onClientCommand: command=" .. tostring(command)
		.. " player=" .. tostring(player and player.getUsername and player:getUsername())
		.. " args=" .. tostring(args))

	if ADMIN_ONLY_COMMANDS[command] then
		if not XPR_AdminAccess or not XPR_AdminAccess.hasAdminCmdAccess(player) then
			XPR_dprint("[XPR] onClientCommand REJECTED (not admin): command=" .. tostring(command)
				.. " player=" .. tostring(player and player.getUsername and player:getUsername()))
			return
		end
	end

	if command == "requestSync" then
		if XPR_Env and not XPR_Env.checkCooldown("requestSync", player, REQUEST_SYNC_COOLDOWN_MS) then return end
		XPR_RankData.syncToClient(player)
	elseif command == "getPlayersData" then
		XPR_RankData.sendPlayersData(player)
	elseif command == "resetRank" then
		if not player then return end
		if not args or not args.targetUsernames or #args.targetUsernames == 0 then return end
		startBulkOp("reset", player:getUsername(), args.targetUsernames)
	elseif command == "setRank" then
		if not player then return end
		if not args or not args.targetUsernames or #args.targetUsernames == 0 then return end
		local rank = tonumber(args.rank) or 1
		if rank < 1 then rank = 1 end
		if rank > XPR_RankCurve.MAX_RANK then rank = XPR_RankCurve.MAX_RANK end
		local xpIntoRank = tonumber(args.totalXp) or 0
		if xpIntoRank < 0 then xpIntoRank = 0 end
		startBulkOp("set", player:getUsername(), args.targetUsernames, rank, xpIntoRank)
	elseif command == "addXp" then
		if not player then return end
		if not args or not args.targetUsernames or #args.targetUsernames == 0 then return end
		local amount = clampXpAward(args.amount)
		if not amount then return end
		startBulkOp("addxp", player:getUsername(), args.targetUsernames, nil, nil, amount)
	end
end

Events.OnClientCommand.Add(onClientCommand)

return XPR_RankData
