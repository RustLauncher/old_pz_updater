if not XPR_Env or not XPR_Env.runsServerLogic() then return end
if XPR_Env.isSP() then return end

XPR_PvpKillXpHook = XPR_PvpKillXpHook or {}

local HIT_CACHE_TTL_MS = 5000

local pvpHitCache = {}

local victimCooldowns = {}

local function nowMs()
	return (getTimestampMs and getTimestampMs()) or 0
end

local function cacheHit(victim, attacker, perkName)
	if not victim or not attacker or not attacker.getUsername then return end
	local uname = attacker:getUsername()
	if not uname then return end
	pvpHitCache[victim] = {
		uname = uname,
		perkName = perkName,
		tMs = nowMs(),
	}
end

local function consumeHit(victim)
	if not victim then return nil end
	local entry = pvpHitCache[victim]
	pvpHitCache[victim] = nil
	if not entry then return nil end
	if nowMs() - (entry.tMs or 0) > HIT_CACHE_TTL_MS then return nil end
	return entry.uname, entry.perkName
end

local pvpSweepTicksLeft = 30
local function pvpCacheSweep()
	pvpSweepTicksLeft = pvpSweepTicksLeft - 1
	if pvpSweepTicksLeft > 0 then return end
	pvpSweepTicksLeft = 30
	local cutoff = nowMs() - HIT_CACHE_TTL_MS
	for v, entry in pairs(pvpHitCache) do
		if (entry.tMs or 0) < cutoff then pvpHitCache[v] = nil end
	end
end
Events.OnTick.Add(pvpCacheSweep)

local function resolvePerkName(attacker, weapon)
	local primaryItem = attacker.getPrimaryHandItem and attacker:getPrimaryHandItem() or nil
	local w = primaryItem or weapon
	if not w then return nil end
	if not w.getPerk then return nil end
	local perk = w:getPerk()
	if not perk then return nil end
	if not perk.getId then return nil end
	return perk:getId()
end

local function cooldownKey(attackerUname, victimUname)
	return attackerUname .. "|" .. victimUname
end

local function isPerVictimCoolingDown(attackerUname, victimUname)
	local minutes = (XPR_SettingsStore and XPR_SettingsStore.getPvpCooldownMinutes
		and XPR_SettingsStore.getPvpCooldownMinutes()) or 30
	if minutes <= 0 then return false end
	local last = victimCooldowns[cooldownKey(attackerUname, victimUname)]
	if not last then return false end
	return (nowMs() - last) < (minutes * 60000)
end

local function recordVictimCooldown(attackerUname, victimUname)
	victimCooldowns[cooldownKey(attackerUname, victimUname)] = nowMs()
end

local function eitherInNonPvpZone(attacker, victim)
	if not NonPvpZone or not NonPvpZone.isInNonPvpZone then return true end
	local aIn = true
	local vIn = true
	if attacker and attacker.getX then aIn = NonPvpZone.isInNonPvpZone(attacker) end
	if victim and victim.getX then vIn = NonPvpZone.isInNonPvpZone(victim) end
	return aIn == true or vIn == true
end

local function bothSafetyOn(attacker, victim)
	local function safetyOn(p)
		if not (p and p.getSafety) then return true end
		local safety = p:getSafety()
		if not (safety and safety.isEnabled) then return true end
		return safety:isEnabled() == true
	end
	return safetyOn(attacker) and safetyOn(victim)
end

local function resolveVehicleKillDriver(victim)
	if not victim or not victim.getAttackedBy then return nil end
	local attacker = victim:getAttackedBy()
	if not attacker then return nil end
	if not (instanceof and instanceof(attacker, "IsoPlayer")) then return nil end
	if not attacker.getVehicle then return nil end
	local vehicle = attacker:getVehicle()
	if not vehicle or not vehicle.getDriver then return nil end
	if vehicle:getDriver() ~= attacker then return nil end
	return attacker
end

local function resolveAwardedAttacker(victim, candidateUname)
	if not XPR_Categories or not XPR_Categories.isPvpKillXpActive
			or not XPR_Categories.isPvpKillXpActive() then
		return nil
	end
	local victimUname = victim.getUsername and victim:getUsername()
	if not victimUname then return nil end

	if not candidateUname then return nil end
	if candidateUname == victimUname then return nil end

	local attacker = XPR_Env and XPR_Env.findLivePlayerByUsername(candidateUname)
	if not attacker then return nil end

	if bothSafetyOn(attacker, victim) then return nil end
	if eitherInNonPvpZone(attacker, victim) then return nil end
	if isPerVictimCoolingDown(candidateUname, victimUname) then
		XPR_dprint("[XPR] XPR_PvpKillXpHook: award blocked by per-victim cooldown attacker="
			.. candidateUname .. " victim=" .. victimUname)
		return nil
	end
	return attacker
end

local function awardPvpKillXp(attacker, victim, category)
	if not attacker or not victim then return end
	if not XPR_XpQueue then return end
	local xp = XPR_Categories and XPR_Categories.getPvpXpAmount and XPR_Categories.getPvpXpAmount() or 10
	if xp <= 0 then return end

	local attackerUname = attacker:getUsername()
	local victimUname = victim.getUsername and victim:getUsername()
	if not attackerUname or not victimUname then return end

	XPR_dprint("[XPR] XPR_PvpKillXpHook: awarding PVP kill XP attacker=" .. attackerUname
		.. " victim=" .. victimUname .. " category=" .. tostring(category)
		.. " xp=" .. tostring(xp))

	if category then
		XPR_XpQueue.queue(attacker, category, xp)
	end
	if XPR_PVP_KILL_CATEGORY then
		XPR_XpQueue.queue(attacker, XPR_PVP_KILL_CATEGORY, xp)
	end
	recordVictimCooldown(attackerUname, victimUname)
end

local function onPvpWeaponHitCharacter(attacker, target, weapon, damage)
	if not XPR_Categories or not XPR_Categories.isPvpKillXpActive
			or not XPR_Categories.isPvpKillXpActive() then
		return
	end
	if not attacker or not target then return end
	if not (instanceof and instanceof(attacker, "IsoPlayer")) then return end
	if not (instanceof and instanceof(target, "IsoPlayer")) then return end
	if attacker == target then return end

	if weapon and weapon.isBareHands and weapon:isBareHands() then
		cacheHit(target, attacker, "BareHands")
		return
	end

	local perkName = resolvePerkName(attacker, weapon)
	if not perkName then return end

	cacheHit(target, attacker, perkName)
end

Events.OnWeaponHitCharacter.Add(onPvpWeaponHitCharacter)

local function onPvpCharacterDeath(character)
	if not XPR_Categories or not XPR_Categories.isPvpKillXpActive
			or not XPR_Categories.isPvpKillXpActive() then
		return
	end
	if not character then return end
	if not (instanceof and instanceof(character, "IsoPlayer")) then return end

	local victimUname = character.getUsername and character:getUsername()
	if not victimUname then return end

	local attackedBy = character.getAttackedBy and character:getAttackedBy()
	if not attackedBy or not (instanceof and instanceof(attackedBy, "IsoPlayer")) then
		return
	end
	local attackedByUname = attackedBy.getUsername and attackedBy:getUsername()
	if not attackedByUname then return end

	local hitUname, perkName = consumeHit(character)
	if hitUname then
		if hitUname == attackedByUname then
			local attacker = resolveAwardedAttacker(character, hitUname)
			if attacker then
				local category = XPR_KILL_PERK_CATEGORY and XPR_KILL_PERK_CATEGORY[perkName]
				if category then
					awardPvpKillXp(attacker, character, category)
				else
					XPR_ErrorPrint("!! PVP KILL XP: unmapped weapon perk '" .. tostring(perkName)
						.. "' -- add to XPR_KILL_PERK_CATEGORY in XPR_Categories.lua")
				end
			end
		end
		return
	end

	local driver = resolveVehicleKillDriver(character)
	if not driver then return end
	if not (driver.getUsername and driver:getUsername() == attackedByUname) then return end
	local attacker = resolveAwardedAttacker(character, attackedByUname)
	if attacker then
		awardPvpKillXp(attacker, character, nil)
	end
end

Events.OnCharacterDeath.Add(onPvpCharacterDeath)

return XPR_PvpKillXpHook
