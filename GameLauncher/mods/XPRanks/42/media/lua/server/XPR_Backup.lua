XPR_Backup = {}

require "XPR_Identity"

local BACKUP_VERSION = 2
local BACKUP_PREFIX = "XPR_Backup_"
local BACKUP_SUFFIX = ".txt"
local AUTO_FILENAME = "auto_backup" .. BACKUP_SUFFIX
local INDEX_FILENAME = "backup_index.txt"

XPR_Backup.knownBackups = {}
XPR_Backup.lastAutoBackup = 0
local AUTO_THROTTLE_SEC = 60

local function getServerDir()
	if XPR_Env and XPR_Env.isSP() then
		return "XPRanks/Singleplayer/"
	end
	local name = getServerName and getServerName() or "default"
	return "XPRanks/" .. name .. "/"
end

local function serializeValue(val)
	if val == nil then return "" end
	if type(val) == "boolean" then return val and "true" or "false" end
	return tostring(val)
end

local function deserializeValue(val, targetType)
	if val == nil or val == "" then return nil end
	if targetType == "number" then
		return tonumber(val)
	elseif targetType == "boolean" then
		return val == "true"
	end
	return val
end

local function escapeUsername(name)
	if not name then return "" end
	return name:gsub("[%.=,|:]", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
end

local function unescapeUsername(name)
	if not name then return "" end
	return name:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end)
end

local function serializeFlatTable(t)
	if not t or type(t) ~= "table" then return "" end
	local parts = {}
	for k, v in pairs(t) do
		parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
	end
	return table.concat(parts, ",")
end

local function deserializeFlatTable(str)
	if not str or str == "" then return {} end
	local result = {}
	for pair in str:gmatch("[^,]+") do
		local k, v = pair:match("^(.-)=(.+)$")
		if k and v then
			result[k] = tonumber(v) or v
		end
	end
	return result
end

local function serializeItemsMap(items)
	if not items or type(items) ~= "table" then return "" end
	local parts = {}
	for itemId, entry in pairs(items) do
		local safeId = tostring(itemId):gsub("[:|]", function(c)
			return string.format("%%%02X", string.byte(c))
		end)
		parts[#parts + 1] = safeId .. ":" .. tostring(entry.tier or "") .. ":" .. (entry.active ~= false and "1" or "0")
	end
	return table.concat(parts, "|")
end

local function deserializeItemsMap(str)
	local items = {}
	if not str or str == "" then return items end
	for rec in str:gmatch("[^|]+") do
		local safeId, tier, activeFlag = rec:match("^(.-):(.-):(.-)$")
		if safeId then
			local itemId = safeId:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
			items[itemId] = { tier = tier, active = activeFlag == "1" }
		end
	end
	return items
end

local function getAutoBackupPath()
	return getServerDir() .. AUTO_FILENAME
end

local function makeBackupFilename()
	return getServerDir() .. BACKUP_PREFIX .. os.date("!%Y-%m-%d_%H-%M-%S") .. BACKUP_SUFFIX
end

local function getIndexPath()
	return getServerDir() .. INDEX_FILENAME
end

local function buildBackupString()
	local lines = {}
	lines[#lines + 1] = "XPR_BACKUP_VERSION=" .. BACKUP_VERSION
	lines[#lines + 1] = "XPR_BACKUP_TIMESTAMP=" .. os.date("!%Y-%m-%dT%H:%M:%SZ")
	lines[#lines + 1] = ""

	local gmd = ModData.getOrCreate("XPR_Global")
	lines[#lines + 1] = "# GLOBAL"

	local rewardCfg = gmd.rewardConfig or {}
	lines[#lines + 1] = "GLOBAL.rewardConfig.items=" .. serializeItemsMap(rewardCfg.items)

	local settings = gmd.settings or {}
	lines[#lines + 1] = "GLOBAL.settings.grantRewardBoxes=" .. serializeValue(settings.grantRewardBoxes)
	lines[#lines + 1] = "GLOBAL.settings.rewardBoxInterval=" .. serializeValue(settings.rewardBoxInterval)
	lines[#lines + 1] = "GLOBAL.settings.killXpFirearms=" .. serializeValue(settings.killXpFirearms)
	lines[#lines + 1] = "GLOBAL.settings.killXpMelee=" .. serializeValue(settings.killXpMelee)
	lines[#lines + 1] = "GLOBAL.settings.killXpVehicle=" .. serializeValue(settings.killXpVehicle)
	lines[#lines + 1] = "GLOBAL.settings.timeSurvivedXp=" .. serializeValue(settings.timeSurvivedXp)
	lines[#lines + 1] = "GLOBAL.settings.timeSurvivedIntervalHours=" .. serializeValue(settings.timeSurvivedIntervalHours)
	lines[#lines + 1] = "GLOBAL.settings.travelWalkXp=" .. serializeValue(settings.travelWalkXp)
	lines[#lines + 1] = "GLOBAL.settings.travelWalkTiles=" .. serializeValue(settings.travelWalkTiles)
	lines[#lines + 1] = "GLOBAL.settings.travelDriveXp=" .. serializeValue(settings.travelDriveXp)
	lines[#lines + 1] = "GLOBAL.settings.travelDriveTiles=" .. serializeValue(settings.travelDriveTiles)
	lines[#lines + 1] = "GLOBAL.settings.pvpXpEnabled=" .. serializeValue(settings.pvpXpEnabled)
	lines[#lines + 1] = "GLOBAL.settings.killXpPvp=" .. serializeValue(settings.killXpPvp)
	lines[#lines + 1] = "GLOBAL.settings.pvpCooldownMinutes=" .. serializeValue(settings.pvpCooldownMinutes)
	lines[#lines + 1] = "GLOBAL.settings.resetRankOnDeath=" .. serializeValue(settings.resetRankOnDeath)
	lines[#lines + 1] = "GLOBAL.settings.efficiencyXp=" .. serializeValue(settings.efficiencyXp)
	lines[#lines + 1] = "GLOBAL.settings.combatMasteringXp=" .. serializeValue(settings.combatMasteringXp)
	lines[#lines + 1] = "GLOBAL.settings.toughnessXp=" .. serializeValue(settings.toughnessXp)
	lines[#lines + 1] = "GLOBAL.settings.categoryXp=" .. serializeFlatTable(settings.categoryXp)
	lines[#lines + 1] = "GLOBAL.settings.rankCurveBaseXp=" .. serializeValue(settings.rankCurveBaseXp)
	lines[#lines + 1] = "GLOBAL.settings.rankCurveStep=" .. serializeValue(settings.rankCurveStep)
	lines[#lines + 1] = "GLOBAL.settings.tier1MaxRank=" .. serializeValue(settings.tier1MaxRank)
	lines[#lines + 1] = "GLOBAL.settings.tier2MaxRank=" .. serializeValue(settings.tier2MaxRank)
	local weights = settings.tierWeights or {}
	lines[#lines + 1] = "GLOBAL.settings.tierWeights.1=" .. serializeFlatTable(weights[1])
	lines[#lines + 1] = "GLOBAL.settings.tierWeights.2=" .. serializeFlatTable(weights[2])
	lines[#lines + 1] = "GLOBAL.settings.tierWeights.3=" .. serializeFlatTable(weights[3])
	lines[#lines + 1] = ""

	lines[#lines + 1] = "# PLAYERS"
	local playersTable
	local topologyStore
	if XPR_Env and XPR_Env.isSP() then
		local player = getSpecificPlayer(0)
		if player and XPR_RankData then
			local pd = XPR_RankData.getPlayerData(player)
			XPR_RankData.syncSPHistory(player, pd)
		end
		topologyStore = ModData.getOrCreate("XPR_SP")
		playersTable = topologyStore.history or {}
	else
		topologyStore = ModData.getOrCreate("XPR_PlayerStore")
		playersTable = topologyStore.players or {}
	end
	for key, value in pairs(playersTable) do
		local pd = value
		local recordKey = key
		if XPR_Env and XPR_Env.isSP() then
			pd = value
			recordKey = pd.id or tostring(key)
		end
		if pd then
			local prefix = "PLAYER." .. escapeUsername(recordKey) .. "."
			if XPR_Env and XPR_Env.isSP() then
				lines[#lines + 1] = prefix .. "name=" .. serializeValue(pd.name)
			end
			lines[#lines + 1] = prefix .. "rank=" .. serializeValue(pd.rank)
			lines[#lines + 1] = prefix .. "totalXp=" .. serializeValue(pd.totalXp)
			lines[#lines + 1] = prefix .. "maxRankVirtualLevel=" .. serializeValue(pd.maxRankVirtualLevel)
			lines[#lines + 1] = prefix .. "categories=" .. serializeFlatTable(pd.categories)
			lines[#lines + 1] = ""
		end
	end

	lines[#lines + 1] = "# LEADERBOARD EXCLUSIONS"
	for category, entries in pairs(topologyStore.leaderboardExclusions or {}) do
		for entryId, excluded in pairs(entries) do
			if excluded == true then
				lines[#lines + 1] = "EXCLUSION." .. escapeUsername(category) .. "."
					.. escapeUsername(entryId) .. "=true"
			end
		end
	end

	return table.concat(lines, "\n")
end

function XPR_Backup.loadIndex()
	local index = {}
	local reader = getFileReader(getIndexPath(), false)
	if reader then
		local line = reader:readLine()
		while line do
			if line ~= "" then
				local fn, ts = line:match("^(.+)|(.+)$")
				if fn and ts then
					index[#index + 1] = { filename = fn, timestamp = ts }
				end
			end
			line = reader:readLine()
		end
		reader:close()
	end
	return index
end

local function saveIndex()
	local lines = {}
	for _, entry in ipairs(XPR_Backup.knownBackups) do
		lines[#lines + 1] = entry.filename .. "|" .. entry.timestamp
	end
	local writer = getFileWriter(getIndexPath(), true, false)
	if writer then
		writer:writeln(table.concat(lines, "\n"))
		writer:close()
	end
end

local function addToIndex(filename, timestamp)
	for _, entry in ipairs(XPR_Backup.knownBackups) do
		if entry.filename == filename then
			entry.timestamp = timestamp
			saveIndex()
			return
		end
	end
	XPR_Backup.knownBackups[#XPR_Backup.knownBackups + 1] = { filename = filename, timestamp = timestamp }
	saveIndex()
end

function XPR_Backup.export()
	local filename = makeBackupFilename()
	local content = buildBackupString()
	local writer = getFileWriter(filename, true, false)
	if not writer then
		XPR_ErrorPrint("Backup FAILED: getFileWriter returned nil for " .. filename)
		return false, filename
	end
	writer:writeln(content)
	writer:close()
	XPR_dprint("[XPR] Backup exported to " .. filename .. " (" .. #content .. " bytes)")

	local ts = filename:match("XPR_Backup_(.+)%.[^%.]+$")
	addToIndex(filename, ts or os.date("!%Y-%m-%d_%H-%M-%S"))

	return true, filename
end

function XPR_Backup.autoBackup(force)
	local now = os.time()
	if not force and (now - XPR_Backup.lastAutoBackup < AUTO_THROTTLE_SEC) then
		return false
	end
	XPR_Backup.lastAutoBackup = now

	local filename = getAutoBackupPath()
	local content = buildBackupString()
	local writer = getFileWriter(filename, true, false)
	if not writer then
		XPR_ErrorPrint("Auto-backup FAILED: getFileWriter returned nil for " .. filename)
		return false
	end
	writer:writeln(content)
	writer:close()
	XPR_dprint("[XPR] Auto-backup written to " .. filename .. " (" .. #content .. " bytes)")

	addToIndex(filename, os.date("!%Y-%m-%d_%H-%M-%S"))

	return true
end

function XPR_Backup.listFiles()
	local seen = {}
	local unique = {}
	for _, b in ipairs(XPR_Backup.knownBackups) do
		if not seen[b.filename] then
			seen[b.filename] = true
			unique[#unique + 1] = b
		end
	end
	XPR_Backup.knownBackups = unique
	table.sort(unique, function(a, b) return a.filename > b.filename end)
	return unique
end

local function parseLine(line)
	if not line or line == "" then return nil, nil end
	if line:sub(1, 1) == "#" then return nil, nil end
	local key, value = line:match("^(.-)=(.*)$")
	return key, value
end

function XPR_Backup.import(filename)
	if not filename or filename == "" then
		return false, "No filename provided"
	end

	XPR_dprint("[XPR] import: attempting to load " .. filename)

	local reader = getFileReader(filename, false)
	if not reader then
		XPR_dprint("[XPR] Restore FAILED: file not found: " .. filename)
		return false, "Backup file not found:\n" .. filename:gsub("/", "\n")
	end

	local lines = {}
	local line = reader:readLine()
	while line do
		lines[#lines + 1] = line
		line = reader:readLine()
	end
	reader:close()

	local version = nil
	local timestamp = nil
	for _, l in ipairs(lines) do
		local k, v = parseLine(l)
		if k == "XPR_BACKUP_VERSION" then version = tonumber(v) end
		if k == "XPR_BACKUP_TIMESTAMP" then timestamp = v end
		if version and timestamp then break end
	end

	if not version then
		XPR_dprint("[XPR] Restore FAILED: no version found in backup file")
		return false, "Invalid backup file (no version)"
	end
	if version > BACKUP_VERSION then
		XPR_dprint("[XPR] Restore FAILED: backup version " .. version .. " is newer than supported version " .. BACKUP_VERSION)
		return false, "Backup version too new (v" .. version .. ")"
	end
	XPR_dprint("[XPR] Restoring from backup v" .. version .. " (" .. (timestamp or "unknown date") .. ")")

	local data = {}
	for _, l in ipairs(lines) do
		local k, v = parseLine(l)
		if k then data[k] = v end
	end

	local gmd = ModData.getOrCreate("XPR_Global")

	if not gmd.rewardConfig then gmd.rewardConfig = {} end
	local rawItems = data["GLOBAL.rewardConfig.items"]
	if rawItems ~= nil then
		gmd.rewardConfig.items = deserializeItemsMap(rawItems)
	end

	if not gmd.settings then gmd.settings = {} end
	local s = gmd.settings
	local restoredGrantBoxes = deserializeValue(data["GLOBAL.settings.grantRewardBoxes"], "boolean")
	if restoredGrantBoxes ~= nil then s.grantRewardBoxes = restoredGrantBoxes end
	s.rewardBoxInterval = deserializeValue(data["GLOBAL.settings.rewardBoxInterval"], "number") or s.rewardBoxInterval
	local legacyKillXp = deserializeValue(data["GLOBAL.settings.killXpAmount"], "number")
	s.killXpFirearms = deserializeValue(data["GLOBAL.settings.killXpFirearms"], "number")
		or deserializeValue(data["GLOBAL.settings.killXpFirearmsCombat"], "number")
		or legacyKillXp or s.killXpFirearms
	s.killXpMelee = deserializeValue(data["GLOBAL.settings.killXpMelee"], "number")
		or deserializeValue(data["GLOBAL.settings.killXpMeleeCombat"], "number")
		or legacyKillXp or s.killXpMelee
	s.killXpVehicle = deserializeValue(data["GLOBAL.settings.killXpVehicle"], "number")
		or deserializeValue(data["GLOBAL.settings.killXpVehicleZombieKill"], "number")
		or legacyKillXp or s.killXpVehicle
	s.timeSurvivedXp = deserializeValue(data["GLOBAL.settings.timeSurvivedXp"], "number") or s.timeSurvivedXp
	s.timeSurvivedIntervalHours = deserializeValue(data["GLOBAL.settings.timeSurvivedIntervalHours"], "number") or s.timeSurvivedIntervalHours
	s.travelWalkXp = deserializeValue(data["GLOBAL.settings.travelWalkXp"], "number") or s.travelWalkXp
	s.travelWalkTiles = deserializeValue(data["GLOBAL.settings.travelWalkTiles"], "number") or s.travelWalkTiles
	s.travelDriveXp = deserializeValue(data["GLOBAL.settings.travelDriveXp"], "number") or s.travelDriveXp
	s.travelDriveTiles = deserializeValue(data["GLOBAL.settings.travelDriveTiles"], "number") or s.travelDriveTiles
	local restoredPvpEnabled = deserializeValue(data["GLOBAL.settings.pvpXpEnabled"], "boolean")
	if restoredPvpEnabled ~= nil then s.pvpXpEnabled = restoredPvpEnabled end
	s.killXpPvp = deserializeValue(data["GLOBAL.settings.killXpPvp"], "number") or s.killXpPvp
	s.pvpCooldownMinutes = deserializeValue(data["GLOBAL.settings.pvpCooldownMinutes"], "number") or s.pvpCooldownMinutes
	local restoredResetOnDeath = deserializeValue(data["GLOBAL.settings.resetRankOnDeath"], "boolean")
	if restoredResetOnDeath ~= nil then s.resetRankOnDeath = restoredResetOnDeath end
	s.efficiencyXp = deserializeValue(data["GLOBAL.settings.efficiencyXp"], "number") or s.efficiencyXp
	s.combatMasteringXp = deserializeValue(data["GLOBAL.settings.combatMasteringXp"], "number") or s.combatMasteringXp
	s.toughnessXp = deserializeValue(data["GLOBAL.settings.toughnessXp"], "number") or s.toughnessXp
	local rawCatXp = data["GLOBAL.settings.categoryXp"]
	if rawCatXp and rawCatXp ~= "" then s.categoryXp = deserializeFlatTable(rawCatXp) end
	s.rankCurveBaseXp = deserializeValue(data["GLOBAL.settings.rankCurveBaseXp"], "number") or s.rankCurveBaseXp
	s.rankCurveStep = deserializeValue(data["GLOBAL.settings.rankCurveStep"], "number") or s.rankCurveStep
	s.tier1MaxRank = deserializeValue(data["GLOBAL.settings.tier1MaxRank"], "number") or s.tier1MaxRank
	s.tier2MaxRank = deserializeValue(data["GLOBAL.settings.tier2MaxRank"], "number") or s.tier2MaxRank
	s.tierWeights = s.tierWeights or {}
	for i = 1, 3 do
		local rawW = data["GLOBAL.settings.tierWeights." .. i]
		if rawW and rawW ~= "" then s.tierWeights[i] = deserializeFlatTable(rawW) end
	end

	ModData.transmit("XPR_Global")
	if XPR_SettingsStore and XPR_SettingsStore.broadcast then
		XPR_SettingsStore.broadcast()
	end
	if XPR_RewardConfigStore and XPR_RewardConfigStore.broadcast then
		XPR_RewardConfigStore.broadcast()
	end

	local playerUsernames = {}
	local pfxPrefix = "PLAYER."
	for key, _ in pairs(data) do
		if key:sub(1, #pfxPrefix) == pfxPrefix then
			local escapedName = key:sub(#pfxPrefix + 1):match("^(.-)%.")
			if escapedName then
				playerUsernames[unescapeUsername(escapedName)] = true
			end
		end
	end

	local isSP = XPR_Env and XPR_Env.isSP()
	local currentSPPlayer = nil
	local currentSPData = nil
	if isSP then
		currentSPPlayer = getSpecificPlayer(0)
		if currentSPPlayer and XPR_RankData then
			currentSPData = XPR_RankData.getPlayerData(currentSPPlayer)
		end
	end
	local store = isSP and ModData.getOrCreate("XPR_SP") or ModData.getOrCreate("XPR_PlayerStore")
	local storeTable
	if isSP then
		store.history = {}
		storeTable = store.history
	else
		store.players = store.players or {}
		storeTable = store.players
	end
	store.leaderboardExclusions = {}
	for key, value in pairs(data) do
		local escapedCategory, escapedEntryId = key:match("^EXCLUSION%.(.-)%.(.+)$")
		if escapedCategory and escapedEntryId and deserializeValue(value, "boolean") == true then
			local category = unescapeUsername(escapedCategory)
			local entryId = unescapeUsername(escapedEntryId)
			store.leaderboardExclusions[category] = store.leaderboardExclusions[category] or {}
			store.leaderboardExclusions[category][entryId] = true
		end
	end

	local onlineByName = {}
	if XPR_Env and XPR_Env.players then
		for _, p in ipairs(XPR_Env.players()) do
			onlineByName[p:getUsername()] = p
		end
	end

	local restoredCount = 0
	for uname in pairs(playerUsernames) do
		local pd = {}
		local pfx = "PLAYER." .. escapeUsername(uname) .. "."

		pd.rank = deserializeValue(data[pfx .. "rank"], "number") or pd.rank or 1
		pd.totalXp = deserializeValue(data[pfx .. "totalXp"], "number") or pd.totalXp or 0
		pd.maxRankVirtualLevel = deserializeValue(data[pfx .. "maxRankVirtualLevel"], "number") or pd.maxRankVirtualLevel or 0
		local rawCats = data[pfx .. "categories"]
		if rawCats and rawCats ~= "" then pd.categories = deserializeFlatTable(rawCats) end
		pd.categories = pd.categories or {}

		local logName = uname
		if isSP then
			local characterId = uname
			local characterName = deserializeValue(data[pfx .. "name"])
			if version == 1 and currentSPPlayer and currentSPData
			and currentSPPlayer:getUsername() == uname then
				characterId = currentSPData._id
				characterName = XPR_Identity.displayName(currentSPPlayer)
			end
			local historyEntry = {
				id = characterId,
				name = characterName or uname,
				rank = pd.rank,
				totalXp = pd.totalXp,
				maxRankVirtualLevel = pd.maxRankVirtualLevel,
				categories = pd.categories,
			}
			storeTable[#storeTable + 1] = historyEntry
			logName = historyEntry.name

			if currentSPPlayer then
				local currentMd = currentSPPlayer:getModData()
				if currentMd.XPR and currentMd.XPR._id == characterId then
					currentMd.XPR.rank = pd.rank
					currentMd.XPR.totalXp = pd.totalXp
					currentMd.XPR.maxRankVirtualLevel = pd.maxRankVirtualLevel
					currentMd.XPR.categories = pd.categories
				end
			end
		else
			storeTable[uname] = pd
			local online = onlineByName[uname]
			if online and XPR_RankData and XPR_RankData.syncToClient then
				XPR_RankData.syncToClient(online)
			end
		end

		restoredCount = restoredCount + 1
		XPR_dprint("[XPR] Restored data for " .. tostring(logName)
			.. " rank=" .. tostring(pd.rank) .. " totalXp=" .. tostring(pd.totalXp))
	end

	ModData.add(isSP and "XPR_SP" or "XPR_PlayerStore", store)
	if isSP then
		ModData.transmit("XPR_SP")
		if currentSPPlayer and XPR_RankData and XPR_RankData.syncToClient then
			XPR_RankData.syncToClient(currentSPPlayer)
		end
	end

	XPR_dprint("[XPR] Restore complete: " .. restoredCount .. " player(s)")
	return true, restoredCount
end

XPR_Backup._initialized = false

function XPR_Backup.init()
	if XPR_Backup._initialized then return end
	XPR_Backup._initialized = true

	local seen = {}

	local probeWriter = getFileWriter(getServerDir() .. ".xpr_init_probe.txt", true, false)
	if probeWriter then probeWriter:close() end

	local reader = getFileReader(getIndexPath(), true)
	if reader then
		local line = reader:readLine()
		while line do
			if line ~= "" then
				local fn, ts = line:match("^(.+)|(.+)$")
				if fn and ts and not seen[fn] then
					seen[fn] = true
					XPR_Backup.knownBackups[#XPR_Backup.knownBackups + 1] = { filename = fn, timestamp = ts }
				end
			end
			line = reader:readLine()
		end
		reader:close()
	end

	XPR_dprint("[XPR] XPR_Backup.init: knownBackups count=" .. #XPR_Backup.knownBackups)
end

local function sendToClient(player, command, args)
	XPR_Env.sendToClient(player, "XPRanks", command, args)
end

local function onClientCommand(module, command, player, args)
	if module ~= "XPRanks" then return end

	if command == "backupXPR" then
		if not player then return end
		if not XPR_AdminAccess or not XPR_AdminAccess.hasAdminCmdAccess(player) then
			XPR_dprint("[XPR] onClientCommand REJECTED (not admin): command=backupXPR player="
				.. tostring(player:getUsername()))
			return
		end
		local ok, filename = XPR_Backup.export()
		sendToClient(player, "backupResult", { success = ok, filename = filename })
	elseif command == "getBackupList" then
		if not player then return end
		if not XPR_AdminAccess or not XPR_AdminAccess.hasAdminCmdAccess(player) then
			XPR_dprint("[XPR] onClientCommand REJECTED (not admin): command=getBackupList player="
				.. tostring(player:getUsername()))
			return
		end
		local backups = XPR_Backup.listFiles()
		XPR_dprint("[XPR] XPR_Backup: getBackupList replying with " .. #backups .. " entries")
		sendToClient(player, "backupList", { backups = backups })
	elseif command == "restoreXPR" then
		if not player then return end
		if not XPR_AdminAccess or not XPR_AdminAccess.hasAdminCmdAccess(player) then
			XPR_dprint("[XPR] onClientCommand REJECTED (not admin): command=restoreXPR player="
				.. tostring(player:getUsername()))
			return
		end
		local filename = args and args.filename
		if not filename or filename == "" then
			sendToClient(player, "restoreResult", { success = false, message = "No file selected" })
			return
		end
		local ok, msg = XPR_Backup.import(filename)
		sendToClient(player, "restoreResult", { success = ok, message = tostring(msg) })
	end
end

Events.OnClientCommand.Add(onClientCommand)

Events.OnServerStarted.Add(function()
	XPR_Backup.init()
end)

Events.OnInitGlobalModData.Add(function()
	if XPR_Env and XPR_Env.isSP() then
		XPR_Backup.init()
	end
end)

return XPR_Backup
