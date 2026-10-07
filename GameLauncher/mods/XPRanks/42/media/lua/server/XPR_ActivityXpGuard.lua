XPR_ActivityXpGuard = XPR_ActivityXpGuard or {}

local READING_ANIM_PATTERN = "read"

function XPR_ActivityXpGuard.shouldSuppress(player)
	if not player then return false end
	if not player.getVariableString then
		XPR_dprint("[XPR] XPR_ActivityXpGuard DIAG: player has no getVariableString method")
		return false
	end

	local performingAction = player:getVariableString("PerformingAction")
	if not performingAction or performingAction == "" then return false end

	if string.find(string.lower(performingAction), READING_ANIM_PATTERN, 1, true) then
		local uname = (player.getUsername and player:getUsername()) or "?"
		XPR_dprint("[XPR] XPR_ActivityXpGuard: SUPPRESSED (reading animation) player="
			.. uname .. " PerformingAction=" .. performingAction)
		return true
	end

	return false
end

return XPR_ActivityXpGuard
