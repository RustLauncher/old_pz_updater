local CROSSMOD_PERK_YIELD = {
	Efficiency = { label = "Efficiency" },
	CombatMastering = { label = "Combat Mastering" },
	Toughness = { label = "Toughness" },
}

local function onAddXP(chr, perk, amount)
	if not XPR_Env or not XPR_Env.runsServerLogic() then return end
	if not XPR_RankData then return end
	if not chr then return end

	if not (instanceof and instanceof(chr, "IsoPlayer")) then return end

	if XPR_RecordedMediaGuard and XPR_RecordedMediaGuard.active then
		XPR_dprint("[XPR] addXp: suppressed (recorded media grant) perk="
			.. tostring(perk and perk.getId and perk:getId()) .. " amount=" .. tostring(amount))
		return
	end

	if not perk then return end
	if not perk.getId then return end
	local perkName = perk:getId()
	if not perkName then return end

	local category = XPR_PERK_TO_CATEGORY and XPR_PERK_TO_CATEGORY[perkName]
	if category then
		XPR_dprint("[XPR] addXp: perk=" .. perkName .. " amount=" .. tostring(amount)
			.. " -> " .. category)
	elseif XPR_KILL_PERK_CATEGORY and XPR_KILL_PERK_CATEGORY[perkName] then
		XPR_dprint("[XPR] addXp: perk=" .. perkName .. " amount=" .. tostring(amount)
			.. " -> " .. XPR_KILL_PERK_CATEGORY[perkName]
			.. " (kill-only, not per-hit -- see XPR_KillXpHook.lua)")
	else
		XPR_ErrorPrint("!! XP NOT MAPPED !! perk=" .. perkName .. " amount=" .. tostring(amount))
	end

	if not category then return end

	local crossmod = CROSSMOD_PERK_YIELD[perkName]
	local xp
	local tickerLabel
	if crossmod then
		xp = XPR_Categories and XPR_Categories.getCrossModXp and XPR_Categories.getCrossModXp(perkName)
		tickerLabel = crossmod.label
	else
		xp = XPR_Categories and XPR_Categories.getCategoryXp and XPR_Categories.getCategoryXp(category)
	end
	if not xp or xp <= 0 then return end

	if XPR_ActivityXpGuard and XPR_ActivityXpGuard.shouldSuppress and XPR_ActivityXpGuard.shouldSuppress(chr) then
		return
	end

	if not XPR_XpQueue then return end
	XPR_XpQueue.queue(chr, category, xp, tickerLabel)
end

Events.AddXP.Add(onAddXP)
