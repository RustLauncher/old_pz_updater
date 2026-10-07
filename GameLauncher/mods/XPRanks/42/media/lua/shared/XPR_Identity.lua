XPR_Identity = XPR_Identity or {}

function XPR_Identity.displayName(player)
	if not player then return "Unknown" end
	if not (XPR_Env and XPR_Env.isSP()) then
		local username = player:getUsername()
		if username and username ~= "" then return username end
	end

	local descriptor = player:getDescriptor()
	local forename = (descriptor and descriptor:getForename()) or "Unknown"
	local surname = (descriptor and descriptor:getSurname()) or ""
	if surname ~= "" then return forename .. " " .. surname end
	return forename
end

return XPR_Identity
