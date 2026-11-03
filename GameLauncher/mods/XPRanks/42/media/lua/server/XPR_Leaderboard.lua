XPR_Leaderboard = XPR_Leaderboard or {}

local STORE_KEY = "XPR_PlayerStore"
local SP_KEY = "XPR_SP"
local MAX_ROWS = 10

local ALL_CATEGORIES_KEY = "__ALL__"
XPR_Leaderboard.ALL_CATEGORIES_KEY = ALL_CATEGORIES_KEY

local function isExcluded(store, category, entryId)
	local exclusions = store.leaderboardExclusions
	if not exclusions then return false end
	local id = tostring(entryId)
	local allEntries = exclusions[ALL_CATEGORIES_KEY]
	if allEntries and allEntries[id] == true then return true end
	local categoryEntries = exclusions[category]
	return categoryEntries and categoryEntries[id] == true
end

local function isValidCategory(category)
	if category == ALL_CATEGORIES_KEY then return true end
	local categories = (XPR_Categories and XPR_Categories.getLeaderboardCategories
		and XPR_Categories.getLeaderboardCategories(true)) or {}
	for _, entry in ipairs(categories) do
		if entry.key == category then return true end
	end
	return false
end

local function sumCategoryXp(categoriesTable, category)
	local sourceKeys = (XPR_Categories and XPR_Categories.getLeaderboardSourceKeys
		and XPR_Categories.getLeaderboardSourceKeys(category)) or { category }
	if not categoriesTable then return nil end
	local total, any = 0, false
	for _, key in ipairs(sourceKeys) do
		local v = categoriesTable[key]
		if type(v) == "number" then
			total = total + v
			any = true
		end
	end
	if not any then return nil end
	return total
end

function XPR_Leaderboard.getTop(category, uncapped, includeExcluded)
	category = category or "Overall"

	local isSP = XPR_Env and XPR_Env.isSP()
	local rows = {}
	if isSP then
		local store = ModData.getOrCreate(SP_KEY)
		store.history = store.history or {}
		local player = getSpecificPlayer(0)
		if player and XPR_RankData then
			local pd = XPR_RankData.getPlayerData(player)
			XPR_RankData.syncSPHistory(player, pd)
		end

		for _, entry in ipairs(store.history) do
			local xp
			if category == "Overall" then
				xp = entry.totalXp
			else
				xp = sumCategoryXp(entry.categories, category)
			end
			local excluded = isExcluded(store, category, entry.id)
			if xp and xp > 0 and (includeExcluded or not excluded) then
				rows[#rows + 1] = {
					username = entry.name or "Unknown",
					entryId = tostring(entry.id),
					rank = entry.rank or 1,
					xp = xp,
					excluded = excluded == true,
				}
			end
		end
	else
		local store = ModData.getOrCreate(STORE_KEY)
		for username, pd in pairs(store.players or {}) do
			local xp
			if category == "Overall" then
				xp = pd.totalXp
			else
				xp = sumCategoryXp(pd.categories, category)
			end
			local excluded = isExcluded(store, category, username)
			if xp and xp > 0 and (includeExcluded or not excluded) then
				rows[#rows + 1] = {
					username = username,
					entryId = username,
					rank = pd.rank or 1,
					xp = xp,
					excluded = excluded == true,
				}
			end
		end
	end

	table.sort(rows, function(a, b) return a.xp > b.xp end)
	for i, row in ipairs(rows) do row.pos = i end
	if uncapped then return rows end

	local top = {}
	for i = 1, math.min(#rows, MAX_ROWS) do
		top[i] = rows[i]
	end
	return top
end

local function allCategoryCandidateRows()
	local rows = XPR_Leaderboard.getTop("Overall", true, true)
	local store = ModData.getOrCreate((XPR_Env and XPR_Env.isSP()) and SP_KEY or STORE_KEY)
	local allEntries = (store.leaderboardExclusions or {})[ALL_CATEGORIES_KEY] or {}
	for _, row in ipairs(rows) do
		row.excluded = allEntries[tostring(row.entryId)] == true
	end
	return rows
end

function XPR_Leaderboard.getAllCandidatesData()
	local categories = (XPR_Categories and XPR_Categories.getLeaderboardCategories
		and XPR_Categories.getLeaderboardCategories(true)) or {}

	local result = {}
	result[ALL_CATEGORIES_KEY] = allCategoryCandidateRows()
	for _, cat in ipairs(categories) do
		result[cat.key] = XPR_Leaderboard.getTop(cat.key, true, true)
	end
	return result
end

local function sendAllCandidates(player)
	if not player then return end
	XPR_Env.sendToClient(player, "XPRanks", "leaderboardCandidates", {
		categories = XPR_Leaderboard.getAllCandidatesData(),
	})
end

local function setEntryExclusion(player, category, entryId, excluded)
	if not player or not isValidCategory(category) or not entryId then return false end
	entryId = tostring(entryId)
	local store
	local exists = false
	if XPR_Env and XPR_Env.isSP() then
		store = ModData.getOrCreate(SP_KEY)
		for _, entry in ipairs(store.history or {}) do
			if tostring(entry.id) == entryId then
				exists = true
				break
			end
		end
	else
		store = ModData.getOrCreate(STORE_KEY)
		exists = store.players and store.players[entryId] ~= nil
	end
	if not exists then return false end
	store.leaderboardExclusions = store.leaderboardExclusions or {}
	store.leaderboardExclusions[category] = store.leaderboardExclusions[category] or {}
	if excluded then
		store.leaderboardExclusions[category][entryId] = true
	else
		store.leaderboardExclusions[category][entryId] = nil
	end
	XPR_dprint("[XPR] Set Leaderboard exclusion=" .. tostring(excluded == true)
		.. " entry=" .. entryId .. " category=" .. category
		.. " by=" .. tostring(player:getUsername()))
	return true
end

function XPR_Leaderboard.getAllCategoriesData(player)
	local categories = (XPR_Categories and XPR_Categories.getLeaderboardCategories
		and XPR_Categories.getLeaderboardCategories(true)) or { { key = "Overall" } }

	local isSP = XPR_Env and XPR_Env.isSP()
	local store
	local allRows = {}
	local currentEntry = nil
	for _, cat in ipairs(categories) do allRows[cat.key] = {} end

	local entryId = player and player.getUsername and player:getUsername()

	if isSP then
		store = ModData.getOrCreate(SP_KEY)
		store.history = store.history or {}
		local localPlayer = getSpecificPlayer(0)
		if localPlayer and XPR_RankData then
			local pd = XPR_RankData.getPlayerData(localPlayer)
			XPR_RankData.syncSPHistory(localPlayer, pd)
		end
		if player and XPR_RankData then
			local pd = XPR_RankData.getPlayerData(player)
			entryId = pd and pd._id
		end

		for _, entry in ipairs(store.history) do
			if entryId and tostring(entry.id) == tostring(entryId) then
				currentEntry = entry
			end
			for _, cat in ipairs(categories) do
				local xp
				if cat.key == "Overall" then
					xp = entry.totalXp
				else
					xp = sumCategoryXp(entry.categories, cat.key)
				end
				if xp and xp > 0 and not isExcluded(store, cat.key, entry.id) then
					local rows = allRows[cat.key]
					rows[#rows + 1] = {
						username = entry.name or "Unknown",
						entryId = tostring(entry.id),
						rank = entry.rank or 1,
						xp = xp,
					}
				end
			end
		end
	else
		store = ModData.getOrCreate(STORE_KEY)
		currentEntry = entryId and store.players and store.players[entryId]
		for username, pd in pairs(store.players or {}) do
			for _, cat in ipairs(categories) do
				local xp
				if cat.key == "Overall" then
					xp = pd.totalXp
				else
					xp = sumCategoryXp(pd.categories, cat.key)
				end
				if xp and xp > 0 and not isExcluded(store, cat.key, username) then
					local rows = allRows[cat.key]
					rows[#rows + 1] = {
						username = username,
						entryId = username,
						rank = pd.rank or 1,
						xp = xp,
					}
				end
			end
		end
	end

	local result = {}
	for _, cat in ipairs(categories) do
		local rows = allRows[cat.key]
		table.sort(rows, function(a, b) return a.xp > b.xp end)
		for i, row in ipairs(rows) do row.pos = i end

		local playerRow = nil
		if entryId then
			for _, row in ipairs(rows) do
				if tostring(row.entryId) == tostring(entryId) then
					playerRow = row
					break
				end
			end
		end
		if playerRow and playerRow.pos <= MAX_ROWS then playerRow = nil end
		if not playerRow and currentEntry and #rows >= MAX_ROWS then
			local currentXp
			if cat.key == "Overall" then
				currentXp = currentEntry.totalXp
			else
				currentXp = sumCategoryXp(currentEntry.categories, cat.key)
			end
			local currentId = isSP and currentEntry.id or entryId
			if (not currentXp or currentXp <= 0)
				and currentId and not isExcluded(store, cat.key, currentId) then
				playerRow = {
					username = isSP and (currentEntry.name or "Unknown") or tostring(entryId),
					entryId = tostring(currentId),
					rank = currentEntry.rank or 1,
					xp = 0,
					pos = #rows + 1,
				}
			end
		end

		local top = {}
		for i = 1, math.min(#rows, MAX_ROWS) do top[i] = rows[i] end

		result[cat.key] = { rows = top, playerRow = playerRow }
	end

	return result, isSP == true
end

function XPR_Leaderboard.sendLeaderboard(player)
	if not player then return end
	if XPR_Env and XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then return end
	local categoriesData, isSP = XPR_Leaderboard.getAllCategoriesData(player)
	XPR_Env.sendToClient(player, "XPRanks", "leaderboardData", {
		categories = categoriesData,
		isSP = isSP,
	})
end

local LEADERBOARD_COOLDOWN_MS = 2000

local function onClientCommand(module, command, player, args)
	if module ~= "XPRanks" then return end
	if not player then return end
	if command == "requestLeaderboard" then
		if XPR_Env and not XPR_Env.checkCooldown("leaderboard", player, LEADERBOARD_COOLDOWN_MS) then return end
		XPR_dprint("[XPR] XPR_Leaderboard.onClientCommand: requestLeaderboard (all categories) for "
			.. tostring(player:getUsername()))
		XPR_Leaderboard.sendLeaderboard(player)
	elseif command == "requestLeaderboardCandidates" then
		if not XPR_AdminAccess or not XPR_AdminAccess.hasAdminCmdAccess(player) then return end
		if XPR_Env and not XPR_Env.checkCooldown("leaderboardCandidates", player, LEADERBOARD_COOLDOWN_MS) then return end
		sendAllCandidates(player)
	elseif command == "setLeaderboardExclusion" then
		if not XPR_AdminAccess or not XPR_AdminAccess.hasAdminCmdAccess(player) then return end
		local category = args and args.category
		local entryId = args and args.entryId
		local excluded = args and args.excluded == true
		local success = setEntryExclusion(player, category, entryId, excluded)
		XPR_Env.sendToClient(player, "XPRanks", "leaderboardExcludeResult", {
			success = success,
			category = category,
			excluded = excluded,
		})
		if success then sendAllCandidates(player) end
	end
end

Events.OnClientCommand.Add(onClientCommand)

return XPR_Leaderboard
