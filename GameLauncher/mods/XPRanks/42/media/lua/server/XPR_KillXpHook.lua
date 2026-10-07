if not XPR_Env or not XPR_Env.runsServerLogic() then return end

XPR_KillXpHook = XPR_KillXpHook or {}

local lastHitCache = {}
local HIT_CACHE_TTL_MS = 5000

local function nowMs()
	return (getTimestampMs and getTimestampMs()) or 0
end

local function cacheHit(zombie, attacker, perkName)
	if not zombie or not attacker or not attacker.getUsername then return end
	lastHitCache[zombie] = {
		uname = attacker:getUsername(),
		perkName = perkName,
		tMs = nowMs(),
	}
end

local function consumeHit(zombie)
	if not zombie then return nil, nil, false end
	local entry = lastHitCache[zombie]
	lastHitCache[zombie] = nil
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
	for z, entry in pairs(lastHitCache) do
		if (entry.tMs or 0) < cutoff then lastHitCache[z] = nil end
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

local function auditKillPerk(perkName)
	if XPR_KILL_PERK_CATEGORY and XPR_KILL_PERK_CATEGORY[perkName] then return end
	XPR_ErrorPrint("!! KILL XP NOT MAPPED !! perk=" .. tostring(perkName)
		.. " -- add to XPR_KILL_PERK_CATEGORY in XPR_Categories.lua")
end

local function resolveVehicleKillDriver(zombie)
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

local function awardKillXp(player, category, xp)
	if not player or not category or not xp or xp <= 0 then return end
	if not XPR_XpQueue then return end
	XPR_XpQueue.queue(player, category, xp)
	if XPR_ZOMBIE_KILL_CATEGORY then
		XPR_XpQueue.queue(player, XPR_ZOMBIE_KILL_CATEGORY, xp)
	end
end

local function killXpForCategory(category)
	if category == "Combat - Firearms" then
		return XPR_Categories.getKillXpAmount("firearms")
	end
	return XPR_Categories.getKillXpAmount("melee")
end

local function onWeaponHitCharacter(attacker, target, weapon, damage)
	if XPR_Env.isTrueSinglePlayer() then return end
	if not attacker or not target then return end
	if not (instanceof and instanceof(attacker, "IsoPlayer")) then return end
	if not (instanceof and instanceof(target, "IsoZombie")) then return end

	if weapon and weapon.isBareHands and weapon:isBareHands() then
		cacheHit(target, attacker, "BareHands")
		return
	end

	local perkName = resolvePerkName(attacker, weapon)
	if not perkName then return end

	cacheHit(target, attacker, perkName)
end

Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)

local function onZombieDead(zombie)
	if XPR_Env.isTrueSinglePlayer() then return end
	if not zombie then return end

	local attacker, perkName, hadHit = consumeHit(zombie)
	if attacker then
		auditKillPerk(perkName)
		local category = resolveKillCategory(perkName)
		if category then
			awardKillXp(attacker, category, killXpForCategory(category))
		end
	end
	if hadHit then return end

	local driver = resolveVehicleKillDriver(zombie)
	if not driver then return end
	if not XPR_XpQueue or not XPR_ZOMBIE_KILL_CATEGORY then return end
	XPR_XpQueue.queue(driver, XPR_ZOMBIE_KILL_CATEGORY, (XPR_Categories.getKillXpAmount("vehicle")))
end

Events.OnZombieDead.Add(onZombieDead)

local function onClientCommand(module, command, player, args)
	if module ~= "XPRanks" then return end
	if command ~= "reportKillXp" and command ~= "reportVehicleKillXp" then return end
	if not (XPR_Env and XPR_Env.isTrueSinglePlayer()) then
		XPR_dprint("[XPR] XPR_KillXpHook.onClientCommand: REJECTED " .. tostring(command)
			.. " outside true SP, player=" .. tostring(player and player.getUsername and player:getUsername()))
		return
	end
	if command == "reportKillXp" then
		if not player then
			XPR_dprint("[XPR] XPR_KillXpHook.onClientCommand: reportKillXp aborted, player is nil")
			return
		end
		if not args or not args.perkName then
			XPR_dprint("[XPR] XPR_KillXpHook.onClientCommand: reportKillXp aborted, args="
				.. tostring(args) .. " perkName=" .. tostring(args and args.perkName))
			return
		end
		XPR_dprint("[XPR] XPR_KillXpHook.onClientCommand: reportKillXp perkName="
			.. tostring(args.perkName))
		auditKillPerk(args.perkName)
		local category = resolveKillCategory(args.perkName)
		XPR_dprint("[XPR] XPR_KillXpHook.onClientCommand: resolveKillCategory("
			.. tostring(args.perkName) .. ") = " .. tostring(category))
		if not category then return end
		awardKillXp(player, category, killXpForCategory(category))
	elseif command == "reportVehicleKillXp" then
		if not player then
			XPR_dprint("[XPR] XPR_KillXpHook.onClientCommand: reportVehicleKillXp aborted, player is nil")
			return
		end
		if not player.getVehicle then return end
		local vehicle = player:getVehicle()
		if not vehicle or not vehicle.getDriver or vehicle:getDriver() ~= player then
			XPR_dprint("[XPR] XPR_KillXpHook.onClientCommand: reportVehicleKillXp rejected, "
				.. tostring(player:getUsername()) .. " is not currently driving a vehicle")
			return
		end
		if not XPR_XpQueue or not XPR_ZOMBIE_KILL_CATEGORY then return end
		XPR_XpQueue.queue(player, XPR_ZOMBIE_KILL_CATEGORY, (XPR_Categories.getKillXpAmount("vehicle")))
	end
end

Events.OnClientCommand.Add(onClientCommand)

return XPR_KillXpHook
