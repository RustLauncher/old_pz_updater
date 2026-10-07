XPR_Env = XPR_Env or {}

function XPR_Env.isDedicated()
	return isServer() and not isClient()
end

function XPR_Env.isHost()
	return isServer() and isClient()
end

function XPR_Env.isCoopClient()
	return isClient() and not isServer()
end

function XPR_Env.isSP()
	return not isServer() and not isClient()
end

function XPR_Env.runsServerLogic()
	return isServer() or XPR_Env.isSP()
end

function XPR_Env.isTrueSinglePlayer()
	return XPR_Env.isSP()
end

function XPR_Env.players()
	if XPR_Env.isSP() then
		local p = getSpecificPlayer(0)
		if p then return { p } end
		return {}
	end

	local result = {}
	local list = getOnlinePlayers()
	if list then
		local n = list:size()
		for i = 0, n - 1 do
			local p = list:get(i)
			if p then result[#result + 1] = p end
		end
	end

	if XPR_Env.isHost() then
		local hostPlayer = getSpecificPlayer(0)
		if hostPlayer then
			local already = false
			for _, p in ipairs(result) do
				if p == hostPlayer then already = true; break end
			end
			if not already then result[#result + 1] = hostPlayer end
		end
	end

	return result
end

function XPR_Env.findLivePlayerByUsername(uname)
	if not uname then return nil end
	for _, p in ipairs(XPR_Env.players()) do
		if p and p:getUsername() == uname then return p end
	end
	return nil
end

function XPR_Env.isModActive(modID)
	if not modID or modID == "" then return false end
	local list = getActivatedMods()
	if not list then return false end
	local n = list:size()
	for i = 0, n - 1 do
		if list:get(i) == modID then return true end
	end
	return false
end

local DCS_MOD_ID = "[B42]DailyChallengeSystem"

function XPR_Env.isDCSActive()
	return XPR_Env.isModActive(DCS_MOD_ID)
end

function XPR_Env.sendToClient(player, module, command, args)
	if not player then return end
	if isServer() then
		sendServerCommand(player, module, command, args)
	end
	if (XPR_Env.isHost() and player == getSpecificPlayer(0)) or XPR_Env.isSP() then
		triggerEvent("OnServerCommand", module, command, args)
	end
end

function XPR_Env.sendToAllClients(module, command, args)
	if isServer() and XPR_Env.isServerNetworkReady() then
		sendServerCommand(module, command, args)
	end
	if XPR_Env.isHost() or XPR_Env.isSP() then
		triggerEvent("OnServerCommand", module, command, args)
	end
end

local commandCooldowns = {}

function XPR_Env.checkCooldown(key, player, cooldownMs)
	if not key or not player or not player.getUsername then return true end
	local uname = player:getUsername()
	if not uname then return true end

	commandCooldowns[key] = commandCooldowns[key] or {}
	local bucket = commandCooldowns[key]
	local now = getTimestampMs and getTimestampMs() or 0
	local last = bucket[uname]
	if last and (now - last) < cooldownMs then
		return false
	end
	bucket[uname] = now
	return true
end

XPR_Env._networkReady = false
function XPR_Env.isServerNetworkReady() return XPR_Env._networkReady == true end

Events.OnServerStarted.Add(function()
	XPR_dprint("[XPR] Events.OnServerStarted FIRED -- isServer()=" .. tostring(isServer())
		.. " isClient()=" .. tostring(isClient()))
	XPR_Env._networkReady = true
end)

return XPR_Env
