XPR_AdminAccess = XPR_AdminAccess or {}

local DEBUG_AUTHOR_STEAM_ID = "76561198704029394"

function XPR_AdminAccess.hasAdminCmdAccess(player)
	if XPR_Env and XPR_Env.isTrueSinglePlayer() then return true end

	if not player then return false end

	local role = player.getRole and player:getRole()
	if role and role.hasAdminTool and role:hasAdminTool() == true then
		return true
	end

	return false
end

function XPR_AdminAccess.hasDebugCmdAccess(player)
	if not XPR_Config or XPR_Config.DEBUG ~= true then return false end

	if XPR_Env and XPR_Env.isTrueSinglePlayer() then
		if not getCurrentUserSteamID then return false end
		local steamId = getCurrentUserSteamID()
		return type(steamId) == "string" and steamId == DEBUG_AUTHOR_STEAM_ID
	end

	if not player or not player.getUsername then return false end
	local configuredUsername = XPR_Config.DEBUG_AUTHOR_USERNAME
	if type(configuredUsername) ~= "string" or configuredUsername == "" then return false end
	return player:getUsername() == configuredUsername and XPR_AdminAccess.hasAdminCmdAccess(player)
end

return XPR_AdminAccess
