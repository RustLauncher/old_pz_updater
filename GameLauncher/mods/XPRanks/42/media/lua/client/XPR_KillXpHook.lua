if isServer() and not isClient() then return end

XPR_KillXpHook = XPR_KillXpHook or {}

local weaponHitCache = {}
local HIT_CACHE_TTL_MS = 5000

local function nowMs()
	return (getTimestampMs and getTimestampMs()) or 0
end

local function cacheHit(zombie, attacker, perkName)
	if not zombie or not attacker or not attacker.getUsername then return end
	weaponHitCache[zombie] = {
		uname = attacker:getUsername(),
		perkName = perkName,
		tMs = nowMs(),
	}
end

local function consumeHit(zombie)
	if not zombie then return nil, nil, false end
	local entry = weaponHitCache[zombie]
	weaponHitCache[zombie] = nil
	if not entry then return nil, nil, false end
	if nowMs() - (entry.tMs or 0) > HIT_CACHE_TTL_MS then return nil, nil, true end
	local player = XPR_Env and XPR_Env.findLivePlayerByUsername(entry.uname)
	if not player then return nil, nil, true end
	return player, entry.perkName, true
end

local hitSweepTicksLeft = 30
local function onHitCacheSweep()
	hitSweepTicksLeft = hitSweepTicksLeft - 1
	if hitSweepTicksLeft > 0 then return end
	hitSweepTicksLeft = 30
	local cutoff = nowMs() - HIT_CACHE_TTL_MS
	for z, entry in pairs(weaponHitCache) do
		if (entry.tMs or 0) < cutoff then weaponHitCache[z] = nil end
	end
end
Events.OnTick.Add(onHitCacheSweep)

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

local function resolveKillCategory(perkName)
	if not perkName then return nil end
	return XPR_KILL_PERK_CATEGORY and XPR_KILL_PERK_CATEGORY[perkName]
end

local function onClientWeaponHitCharacter(attacker, target, weapon, damage)
	if not XPR_Env.isTrueSinglePlayer() then return end
	if not attacker or not target then return end
	if not (instanceof and instanceof(attacker, "IsoPlayer")) then return end
	if not (instanceof and instanceof(target, "IsoZombie")) then return end

	if weapon and weapon.isBareHands and weapon:isBareHands() then
		cacheHit(target, attacker, "BareHands")
		return
	end

	local perkName = resolvePerkName(attacker, weapon)
	if not perkName then
		XPR_dprint("[XPR] XPR_KillXpHook (client): onWeaponHitCharacter -- resolvePerkName returned nil")
		return
	end

	cacheHit(target, attacker, perkName)
end

Events.OnWeaponHitCharacter.Add(onClientWeaponHitCharacter)

local function resolveLocalVehicleKillDriver(zombie)
	if not zombie or not zombie.getAttackedBy then return nil end
	local attacker = zombie:getAttackedBy()
	if not attacker then return nil end
	if not (instanceof and instanceof(attacker, "IsoPlayer")) then return nil end
	if not attacker.getVehicle then return nil end
	local vehicle = attacker:getVehicle()
	if not vehicle or not vehicle.getDriver then return nil end
	if vehicle:getDriver() ~= attacker then return nil end
	return attacker
end

local function onClientZombieDead(zombie)
	if not XPR_Env.isTrueSinglePlayer() then return end
	if not zombie then return end

	local player, perkName, hadHit = consumeHit(zombie)
	if player and perkName then
		XPR_dprint("[XPR] XPR_KillXpHook (client): sending reportKillXp perkName="
			.. tostring(perkName))
		sendClientCommand(player, "XPRanks", "reportKillXp", {
			perkName = perkName,
		})
	end
	if hadHit then return end

	XPR_dprint("[XPR] XPR_KillXpHook (client): onZombieDead -- no cached hit for this zombie, checking vehicle")
	local driver = resolveLocalVehicleKillDriver(zombie)
	if not driver then return end

	XPR_dprint("[XPR] XPR_KillXpHook (client): sending reportVehicleKillXp")
	sendClientCommand(driver, "XPRanks", "reportVehicleKillXp", {})
end

Events.OnZombieDead.Add(onClientZombieDead)

return XPR_KillXpHook
