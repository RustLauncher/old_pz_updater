if isServer() and not isClient() then return end

XPR_ClientSync = XPR_ClientSync or {}

XPR_ClientSync.State = {
	rank = 1,
	totalXp = 0,
}

local function enabledSound(soundName)
	if XPR_ModOptions and XPR_ModOptions.areSoundsEnabled
			and not XPR_ModOptions.areSoundsEnabled() then
		return nil
	end
	return soundName
end

local function onServerCommand(module, command, args)
	if module ~= "XPRanks" then return end
	if command == "syncRank" then
		if not args then return end
		XPR_ClientSync.State.rank = args.rank or 1
		XPR_ClientSync.State.totalXp = args.totalXp or 0
		XPR_ClientSync.synced = true
	elseif command == "xpGain" then
		if not args or not args.category or not args.amount then return end
		if XPR_TickerFeed and XPR_TickerFeed.addXpGain then
			XPR_TickerFeed.addXpGain(args.category, args.amount, args.label)
		end
	elseif command == "rankUp" then
		if not args or not args.rank then return end
		if ObNoxToast and ObNoxToast.show then
			ObNoxToast.show(getText("IGUI_XPR_Toast_RankUp", args.rank), "rankup", nil,
				"XPRanks", args.rank, enabledSound("XPR_rank"))
		end
	elseif command == "leaderboardData" then
		if not args or not args.categories then return end
		if XPR_UI_Leaderboard and XPR_UI_Leaderboard.onData then
			XPR_UI_Leaderboard.onData(args.categories, args.isSP == true)
		end
	elseif command == "leaderboardCandidates" then
		if not args or not args.categories then return end
		if XPR_UI_LeaderboardExclude and XPR_UI_LeaderboardExclude.onData then
			XPR_UI_LeaderboardExclude.onData(args.categories)
		end
	elseif command == "leaderboardExcludeResult" then
		if not args then return end
		if XPR_UI_LeaderboardExclude and XPR_UI_LeaderboardExclude.onResult then
			XPR_UI_LeaderboardExclude.onResult(args.success == true, args.category,
				args.excluded == true)
		end
	elseif command == "rewardBoxResult" then
		if not args or not args.itemId or not args.rank then return end
		if XPR_UI_RewardReveal and XPR_UI_RewardReveal.open then
			XPR_UI_RewardReveal.open(args.itemId, args.rank)
		end
	elseif command == "rewardBoxReceived" then
		if not args or not args.rank then return end
		if ObNoxToast and ObNoxToast.show then
			local boxName = (XPR_RewardBox and XPR_RewardBox.buildDisplayName
				and XPR_RewardBox.buildDisplayName(args.rank))
				or ("Rank " .. tostring(args.rank) .. " Reward Box")
			local message = getText("IGUI_XPR_RewardBox_ReceivedToast", boxName)
			if not message or message == "" or message == "IGUI_XPR_RewardBox_ReceivedToast" then
				message = "Received: " .. boxName
			end
			ObNoxToast.show(message, "boxReward", nil, "XPRanks", nil,
				enabledSound("XPR_reward"))
		end
	elseif command == "playersData" then
		if not args or not args.players then return end
		if XPR_UI_PlayerPicker and XPR_UI_PlayerPicker.onPlayersData then
			XPR_UI_PlayerPicker.onPlayersData(args.players)
		end
	elseif command == "rewardConfigSync" then
		if not args or not args.items then return end
		if XPR_RewardItems and XPR_RewardItems.applySyncedConfig then
			XPR_RewardItems.applySyncedConfig(args.items)
		end
		if XPR_UI_RewardAdmin and XPR_UI_RewardAdmin.instance
				and XPR_UI_RewardAdmin.instance.applySyncedConfig then
			XPR_UI_RewardAdmin.instance:applySyncedConfig(args.items)
		end
	elseif command == "settingsSync" then
		if not args then return end
		XPR_ClientSync.pvpSynced = true
		if XPR_Categories and XPR_Categories.setPvpKillXpActive then
			XPR_Categories.setPvpKillXpActive(args.pvpXpEnabled == true)
		end
		if XPR_UI_Settings and XPR_UI_Settings.applySyncedSettings then
			XPR_UI_Settings.applySyncedSettings(args)
		end
	elseif command == "backupList" then
		if not args then return end
		if XPR_UI_BackupPicker and XPR_UI_BackupPicker.onBackupList then
			XPR_UI_BackupPicker.onBackupList(args.backups)
		end
	elseif command == "backupResult" then
		if not args then return end
		if ObNoxToast and ObNoxToast.show then
			local msg = args.success and getText("IGUI_XPR_Toast_BackupSaved", tostring(args.filename))
				or getText("IGUI_XPR_Toast_BackupFailed")
			ObNoxToast.show(msg, "debug", nil, "XPRanks")
		end
	elseif command == "restoreResult" then
		if not args then return end
		if ObNoxToast and ObNoxToast.show then
			local msg = args.success and getText("IGUI_XPR_Toast_RestoreComplete")
				or getText("IGUI_XPR_Toast_RestoreFailed", tostring(args.message))
			ObNoxToast.show(msg, "debug", nil, "XPRanks")
		end
	elseif command == "bulkOpResult" then
		if not args or not args.kind or not args.count then return end
		if ObNoxToast and ObNoxToast.show then
			local key = "IGUI_XPR_Toast_BulkResetComplete"
			if args.kind == "set" then key = "IGUI_XPR_Toast_BulkSetComplete"
			elseif args.kind == "addxp" then key = "IGUI_XPR_Toast_BulkAddXpComplete" end
			ObNoxToast.show(getText(key, args.count), "debug", nil, "XPRanks")
		end
	elseif command == "debugPlayersDataResult" then
		if not args or type(args.code) ~= "string" then return end
		if XPR_UI_PlayerPicker and XPR_UI_PlayerPicker.onPlayersDataError then
			XPR_UI_PlayerPicker.onPlayersDataError(args.code)
		end
	elseif command == "debugRewardBoxResult" then
		if not args or type(args.code) ~= "string" then return end
		local keyByCode = {
			invalidRank = "IGUI_XPR_Toast_DebugRewardBoxInvalidRank",
			invalidTarget = "IGUI_XPR_Toast_DebugRewardBoxInvalidTarget",
			targetUnavailable = "IGUI_XPR_Toast_DebugRewardBoxTargetUnavailable",
			rejectedSender = "IGUI_XPR_Toast_DebugRewardBoxRejected",
			malformed = "IGUI_XPR_Toast_DebugRewardBoxMalformed",
			deliveryFailed = "IGUI_XPR_Toast_DebugRewardBoxDeliveryFailed",
		}
		local message
		if (args.code == "success" or args.code == "queued")
				and type(args.rank) == "number" and type(args.targetUsername) == "string"
				and XPR_RewardBox and XPR_RewardBox.buildDisplayName then
			local boxName = XPR_RewardBox.buildDisplayName(args.rank)
			if args.code == "queued" then
				message = getText("IGUI_XPR_Toast_DebugRewardBoxQueued", boxName, args.targetUsername)
			else
				message = getText("IGUI_XPR_Toast_DebugRewardBoxSuccess", boxName, args.targetUsername)
			end
		else
			message = getText(keyByCode[args.code] or "IGUI_XPR_Toast_DebugRewardBoxRejected")
		end
		if ObNoxToast and ObNoxToast.show then
			ObNoxToast.show(message, "debug", nil, "XPRanks")
		end
	end
end

Events.OnServerCommand.Add(onServerCommand)

function XPR_ClientSync.getState(player)
	if XPR_Env and XPR_Env.isTrueSinglePlayer() and XPR_RankData then
		return XPR_RankData.getPlayerData(player)
	end
	return XPR_ClientSync.State
end

XPR_ClientSync.synced = false

XPR_ClientSync.pvpSynced = false

local RESYNC_RETRY_TICKS = 180
local RESYNC_MAX_ATTEMPTS = 10
local resyncState = nil

local function onResyncTick()
	if not resyncState then return end
	if XPR_ClientSync.synced then
		resyncState = nil
		return
	end

	resyncState.ticksLeft = resyncState.ticksLeft - 1
	if resyncState.ticksLeft > 0 then return end

	resyncState.attempts = resyncState.attempts + 1
	if resyncState.attempts > RESYNC_MAX_ATTEMPTS then
		XPR_dprint("[XPR] XPR_ClientSync: gave up retrying requestSync after "
			.. RESYNC_MAX_ATTEMPTS .. " attempts -- HUD may still show stale Rank/XP")
		resyncState = nil
		return
	end

	resyncState.ticksLeft = RESYNC_RETRY_TICKS
	sendClientCommand(resyncState.player, "XPRanks", "requestSync", {})
	if not XPR_ClientSync.pvpSynced then
		sendClientCommand(resyncState.player, "XPRanks", "getSettings", {})
	end
end

Events.OnTick.Add(onResyncTick)

local function onCreatePlayer(playerNum)
	local player = getSpecificPlayer(playerNum)
	if not player then return end
	XPR_ClientSync.synced = false
	XPR_ClientSync.pvpSynced = false
	resyncState = { player = player, attempts = 0, ticksLeft = 1 }
end

Events.OnCreatePlayer.Add(onCreatePlayer)

return XPR_ClientSync
