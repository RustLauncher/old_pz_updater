CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function combatDriveTile(animal, d, otx, oty, otz, pathFn)
    d.combatHold = nil
    if animal then
        local run = CD.mayRunFrom(d)
        animal:setVariable("animalSpeed", run and CD.runAnimSpeed() or CD.walkAnimSpeed())
        animal:setVariable("animalRunning", run)
        -- A velocidade de verdade e a escala de marcha, nao o animalSpeed. Sem carimbar aqui vale o
        -- que o upkeep deixou, que e a escala cheia; o valor e lido na ENTRADA do node, entao tem que
        -- estar escrito antes do pathTo desta passada.
        CD.applyGaitScale(animal, CD.combatRunScale(), nil, d)
    end
    local px, py = animal:getX(), animal:getY()
    local hijacked = CD.pathStatHijack(animal, "combate")
    if not hijacked and CD.DMG_DEBUG and CD.pathHijacked then
        hijacked = CD.pathHijacked(animal)
    end
    if hijacked then
        d.combatHijacks = (d.combatHijacks or 0) + 1
    end

    local nowMs = getTimestampMs()
    local moved = d.combatLastX and (math.abs(px - d.combatLastX) + math.abs(py - d.combatLastY)) or 999
    if moved >= CD.COMBAT_STALL_EPS then
        d.combatLastX, d.combatLastY, d.combatStallMs = px, py, nowMs
    end
    -- Cao em resolve assincrono nao sai do lugar. Sem o piso de tempo abaixo, "parado" viraria motivo
    -- pra re-emitir, e a re-emissao e justamente o que o deixou parado.
    local stalled = d.combatStallMs and (nowMs - d.combatStallMs) >= CD.COMBAT_STALL_REPATH_MS
    local sinceIssue = (d.combatPathMs and (nowMs - d.combatPathMs)) or 999999

    local pt = d.combatPathTile
    if pt then
        if pt.x == otx and pt.y == oty and pt.z == otz then
            -- Alvo no mesmo tile: o caminho emitido continua valendo. So travamento real refaz, e
            -- nunca antes do A* ter tido tempo de voltar.
            if not stalled or sinceIssue < CD.COMBAT_PATH_RESOLVE_MS then
                CD.forcePathfind(animal)
                return
            end
        else
            -- Estrada que sobra ate a ponta guardada, e quanto o alvo ja se afastou dela. Aritmetica
            -- em Lua sobre a ponta: nenhuma chamada nova a engine.
            local dx, dy = px - (pt.x + 0.5), py - (pt.y + 0.5)
            local lead = CD.COMBAT_REPATH_LEAD
            local outOfRoad = (dx * dx + dy * dy) <= (lead * lead)
            local drifted = (math.abs(otx - pt.x) + math.abs(oty - pt.y)) > CD.COMBAT_GOAL_DRIFT
            if sinceIssue < CD.COMBAT_REPATH_MS or not (outOfRoad or drifted or stalled) then
                CD.forcePathfind(animal)
                return
            end
        end
    end

    d.combatPathTile = { x = otx, y = oty, z = otz }
    d.combatPathMs = nowMs
    d.combatLastX, d.combatLastY, d.combatStallMs = px, py, nowMs
    CD.letMove(animal)
    pathFn()
    CD.forcePathfind(animal)
    if CD.DEBUG_PATH then
        CD.logPath(animal, "combate", otx, oty)
    end
end

local function stillActiveFor(animal, owner)
    if not CD.isCompanion(animal) then return false end
    local tok = CD.data(animal).companionToken
    if tok == nil then return false end
    return tok == CD.playerData(owner).token
end

-- devolve true enquanto o cao deve continuar na fila de combate
local function maintainCombatOne(id, animal)
    if not animal:isExistInTheWorld() then return false end
    local owner = CD.getOwnerPlayer(animal)
    if not owner then return false end
    if not stillActiveFor(animal, owner) then return false end
    if CD.dist2D(animal, owner) > CD.TELEPORT_DIST then return true end
    local d = CD.data(animal)
    if d.fenceHop then return true end
    if isServer() and CD.landGlide[id] then return true end
    if animal:getVariableBoolean("ClimbFence") then
        CD.clearClimbVars(animal)
    end
    if d.combatMode == "retreat" then
        local rt = d.retreatTile
        if rt then
            combatDriveTile(animal, d, rt.x, rt.y, rt.z,
                function()
                    CD.pathStatEmit(animal, "retreat")
                    animal:pathToLocation(rt.x, rt.y, rt.z)
                end)
        end
        return true
    end
    local z = CD.combatTarget[id]
    local valid = false
    if z then
        valid = CD.isThreatZombie(z) and CD.inWorldNow(z)
            and math.floor(z:getZ()) == math.floor(animal:getZ())
    end
    if not valid then
        CD.letMove(animal)
        return true
    end
    animal:faceThisObject(z)
    if d.combatFollowVault and CD.tryCombatVault(animal, z, d, getTimestampMs()) then return true end
    if CD.dist2D(animal, z) <= CD.STRIKE_DIST and not CD.pathBlocked(animal, z) then
        animal:setVariable("animalRunning", false)
        animal:setVariable("animalSpeed", 0)
        animal:stopAllMovementNow()
        d.combatHold = true
        CD.holdStill(animal)
        d.combatPathTile, d.combatPathMs, d.combatStallMs = nil, nil, nil
    else
        combatDriveTile(animal, d, math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ()),
            function()
                CD.pathStatEmit(animal, "combate")
                animal:pathToCharacter(z)
            end)
    end
    return true
end

local function maintainCombat()
    for id, animal in pairs(CD.combatMaintainDogs) do
        if not maintainCombatOne(id, animal) then
            CD.combatMaintainDogs[id] = nil
        end
    end
end

-- devolve true enquanto o cao deve continuar na fila de follow
local function maintainFollowersOne(animal)
    if not animal:isExistInTheWorld() then return false end
    local owner = CD.getOwnerPlayer(animal)
    if not owner then return false end
    if not stillActiveFor(animal, owner) then return false end
    if CD.data(animal).breedTarget then return true end
    local sameFloor = math.floor(owner:getZ()) == math.floor(animal:getZ())
    if sameFloor and CD.dist2D(animal, owner) <= CD.TELEPORT_DIST then
        CD.followOwner(animal, owner)
    end
    return true
end

local function maintainFollowers()
    for id, animal in pairs(CD.followMaintainDogs) do
        if not maintainFollowersOne(animal) then
            CD.followMaintainDogs[id] = nil
        end
    end
end

-- Heranca so em SP: em MP o username sobrevive a morte. O gate de um jogador nao descarta tela
-- dividida (ao carregar o save so o jogador 1 existe), dai os dois sinais de split abaixo.
---@param a IsoAnimal
---@param myKey string|nil owner key of the single local player
---@return boolean
---@nodiscard
CD.orphanIsSplitScreen = function(a, myKey)
    local key = CD.data(a).ownerKey
    if key == nil or key == "" or key == myKey then return false end
    if CD.splitKeySeen(key) then return true end
    return string.find(key, "#", 1, true) ~= nil
end

local function tickAdoptOrphans()
    if isServer() or isClient() then return end
    if getNumActivePlayers() ~= 1 then return end
    local now = getTimestampMs()
    if CD._adoptSinceMs == nil then
        CD._adoptSinceMs = now
    end
    if (now - CD._adoptSinceMs) < 300000 then return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    local myKey = CD.ownerKey(player)
    CD.regEach(CD.regCompanions(), function(a)
        if not a:isDead() and not CD.isOwnedBy(a, player) and not CD.orphanIsSplitScreen(a, myKey) then
            CD.adoptOrphan(a, player)
            CD.notifyOwner(player, "inherited", { id = a:getOnlineID(), name = CD.data(a).name, breed = CD.getBreed(a) })
        end
    end)
end
CD.maintainFollowers, CD.maintainCombat, CD.tickAdoptOrphans = maintainFollowers, maintainCombat, tickAdoptOrphans
