CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

--o que o nucleo (CompanionDogs_Companion.lua) e os handlers leem de cada arquivo de systems/, de
-- server/CompanionDogs/ e dos irm]aos de server/. Sem esta lista, um arquivo que nao carregou so aparece
-- no primeiro tick, como `attempt to call nil`, sem dizer qual. Aqui aparece no boot, com o arquivo e
-- o simbolo no erro. Quem chama estes simbolos nao os guarda: o invariante mora aqui.
local REQUIRED = {
    ["CompanionDogs_Breeding.lua"] = { "tickBreedingApproach", "tickGestation" },
    ["CompanionDogs_Commands.lua"] = { "tickPassiveBreeding" },
    ["CompanionDogs/breed/Collie.lua"] = { "collieCalmPass" },
    ["CompanionDogs/combat/LandGlide.lua"] = { "clearAttack", "stopCombat", "tickLandGlide" },
    ["CompanionDogs/combat/Threat.lua"] = { "inWorldNow", "playerFighting", "scanAlert", "scanQuietResult",
        "scanQuietSkip", "scanZombies", "updatePanicNotify", "warnRefusalInCombat", "zbox", "zseq" },
    ["CompanionDogs/core/Anim.lua"] = { "calmSince", "clearIdleVariation", "emitAnim", "idleVarNext",
        "lastAttackVar", "lastIdleVar", "pendingClears", "processAnimClears", "pulseDrinkAnim",
        "pulseEatAnim", "pulseSniffAnim", "restBeat", "restPose", "restState", "standUp", "updateRest" },
    ["CompanionDogs/life/Mounted.lua"] = { "tickCompanionInvincible", "tickMountedDogs", "wasInPlay" },
    ["systems/CompanionDogs_Carry.lua"] = { "tickCarriedGuard" },
    ["systems/CompanionDogs_Distract.lua"] = { "registerDistraction", "tryDistract" },
    ["systems/CompanionDogs_Feed.lua"] = { "findTroughNear" },
    ["systems/CompanionDogs_FenceHop.lua"] = { "clearClimbVars", "combatUnreach", "tickFenceHops",
        "tickFenceLandPush" },
    ["systems/CompanionDogs_Fire.lua"] = { "fireBaseline", "fireSafeTile", "pruneFireState" },
    ["systems/CompanionDogs_Follow.lua"] = { "followOwner", "followSteering", "ownerMoveState",
        "tickFenceSteer", "tickFollowSteer", "tryCombatVault" },
    ["systems/CompanionDogs_FollowStream.lua"] = { "tickFollowStream", "tickLandStream" },
    ["systems/CompanionDogs_GunGuard.lua"] = { "gunGuardRelease", "gunGuardUntil", "gunGuarded", "tickGunGuard" },
    ["systems/CompanionDogs_Hunting.lua"] = { "driveMemo", "setSniffTag", "sniffCursor", "trickDistract",
        "tryHunt", "trySniffPoint", "tryTrickGoto" },
    ["systems/CompanionDogs_Nearby.lua"] = { "processNearbyDogs" },
    ["systems/CompanionDogs_NetAuthority.lua"] = { "netAuthHeldMap", "netAuthRevoke", "tickNetAuthority" },
    ["systems/CompanionDogs_Presence.lua"] = { "reapClonesCellWide", "repairOwnership", "repairSplitIdentity" },
    ["systems/CompanionDogs_Sentinel.lua"] = { "sentinelWasAlarm" },
    ["systems/CompanionDogs_Stash.lua"] = { "respawnCompanion", "writeStashRecord" },
    ["systems/CompanionDogs_StrayRoad.lua"] = { "strayRoadTick" },
    ["systems/CompanionDogs_Strike.lua"] = { "bark", "strikeExchange", "zdmgSweep" },
    ["systems/CompanionDogs_Upkeep.lua"] = { "updateUpkeep" },
    ["systems/CompanionDogs_Vet.lua"] = { "vetRollHop" },
}

local function auditSystems()
    if isClient() then return end
    for file, names in pairs(REQUIRED) do
        for i = 1, #names do
            assert(CD[names[i]] ~= nil,
                "CompanionDogs: server/" .. file .. " nao carregou (falta CD." .. names[i] .. ")")
        end
    end
end

CD.evAdd(Events.OnGameStart, auditSystems, "audit")
CD.evAdd(Events.OnServerStarted, auditSystems, "audit")
