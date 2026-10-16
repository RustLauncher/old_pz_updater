CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local fireBaseline = {}
CD.fireBaseline = fireBaseline

local fireSafeTile = {}
CD.fireSafeTile = fireSafeTile

local lastSafeSq = {}

local FIRE_ESCAPE_RADIUS = 6

local FIRE_KILL_RATE = 0.0038

local function squareHasFire(sq)
    if not sq then return false end
    local props = sq:getProperties()
    return (props ~= nil and props:has(IsoFlagType.burning)) or sq:haveFire()
end

local function findFireEscapeTile(cell, sq, towardX, towardY)
    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()
    local best, bestD = nil, nil
    for r = 1, FIRE_ESCAPE_RADIUS do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local s = cell:getGridSquare(cx + dx, cy + dy, cz)
                    if s and s:isFree(false) and not s:getProperties():has(IsoFlagType.water)
                       and not squareHasFire(s) then
                        local ddx, ddy = (cx + dx) - towardX, (cy + dy) - towardY
                        local d = ddx * ddx + ddy * ddy
                        if not bestD or d < bestD then
                            best, bestD = s, d
                        end
                    end
                end
            end
        end
        if best then break end
    end
    return best
end

-- setIsInvincible nao para o fogo: a queimadura passa por CombatManager.applyDamage, que subtrai
-- vida direto, e isInvincible so e honrado dentro do setHealth.
-- A sonda e so isOnFire: FireCheck acende o animal no mesmo tick em que ele pisa no square em
-- chamas, entao ler o square por passada so antecipava um tick e custava quatro chamadas por cao.
local FIRE_SAFE_TILE_PASSES = 10

local fireTick = 0
local firePass = 0
local function tickCompanionFire()
    fireTick = fireTick + 1
    if fireTick < CD.FIRE_GUARD_TICKS then return end
    fireTick = 0
    local cell = getCell()
    if not cell then return end
    firePass = firePass + 1
    local snapTile = firePass >= FIRE_SAFE_TILE_PASSES
    if snapTile then
        firePass = 0
    end
    local wildInv = CD.wildDogsInvincible()
    local dogs = wildInv and CD.regDogs() or CD.regCompanions()
    for i = 1, #dogs do
        local a = dogs[i]
        if a:isExistInTheWorld() then
            local id = a:getOnlineID()
            local validId = id ~= -1
            if a:isOnFire() then
                CD.perfCount("fire.active")
                local base
                if validId then
                    base = fireBaseline[id]
                    if not base then
                        base = a:getHealth()
                        fireBaseline[id] = base
                    end
                else
                    base = a:getHealth()
                end
                local mult = getGameTime():getMultiplier()
                local target = base
                local survive = math.min(0.9, FIRE_KILL_RATE * 0.9 * mult * 1.5)
                if survive > target then
                    target = survive
                end
                if a:getHealth() < target then
                    a:setHealth(target)
                end
                a:StopBurning()
                local sq = a:getSquare()
                if sq and squareHasFire(sq) then
                    local tx, ty = a:getX(), a:getY()
                    local owner = CD.getOwnerPlayer(a)
                    local os = owner and owner:getCurrentSquare()
                    if os then
                        tx, ty = os:getX(), os:getY()
                    end
                    local esc = findFireEscapeTile(cell, sq, tx, ty)
                    if validId and not (esc and CD.squareHasFloor(esc)) then
                        local safe = fireSafeTile[id]
                        if safe then
                            local ss = cell:getGridSquare(safe.x, safe.y, safe.z)
                            if ss and ss:isFree(false) and not ss:getProperties():has(IsoFlagType.water)
                               and CD.squareHasFloor(ss) and not squareHasFire(ss) then
                                esc = ss
                            end
                        end
                    end
                    if esc and CD.squareHasFloor(esc) then
                        a:stopAllMovementNow()
                        a:setX(esc:getX() + 0.5)
                        a:setY(esc:getY() + 0.5)
                        a:setZ(esc:getZ())
                        a:setCurrent(esc)
                    end
                end
            elseif validId then
                fireBaseline[id] = a:getHealth()
                -- Tile seguro a cada 3 s e so quando o square mudou: e o refugio de quando o anel
                -- de fuga falha, nao precisa acompanhar cada passo.
                local sq = snapTile and a:getSquare() or nil
                if sq and sq ~= lastSafeSq[id] then
                    lastSafeSq[id] = sq
                    local t = fireSafeTile[id]
                    if t then t.x, t.y, t.z = sq:getX(), sq:getY(), sq:getZ()
                    else fireSafeTile[id] = { x = sq:getX(), y = sq:getY(), z = sq:getZ() } end
                end
            end
        end
    end
end

-- Morte apaga na hora; o prune fica para o despawn sem morte, que e raro, e por isso anda 15x mais devagar.
local function onCharacterDeath(chr)
    if not chr or not instanceof(chr, "IsoAnimal") then return end
    local id = chr:getOnlineID()
    if id == -1 then return end
    CD.perfCount("death.animal")
    -- A flag de queda e copiada para o cadaver: com ela ligada o corpo usaria a pose de ragdoll.
    CD.releaseFallFlag(chr)
    fireBaseline[id] = nil
    fireSafeTile[id] = nil
    lastSafeSq[id] = nil
    CD.zbox[id] = nil
    CD.combatUnreach[id] = nil
end
if not isClient() then
    Events.OnCharacterDeath.Add(onCharacterDeath)
end

local PRUNE_PASSES = 15
local prunePass = 0
local function pruneFireState()
    prunePass = prunePass + 1
    if prunePass < PRUNE_PASSES then return end
    prunePass = 0
    local cell = getCell()
    if not cell then return end
    CD.perfCount("sweep.animals")
    local list = cell:getAnimals()
    local present = {}
    for i = 0, list:size() - 1 do
        local a = list:get(i)
        if a then
            local id = a:getOnlineID()
            present[id] = true
        end
    end
    for id in pairs(fireBaseline) do
        if not present[id] then
            CD.perfCount("prune.stale")
            fireBaseline[id] = nil
        end
    end
    for id in pairs(fireSafeTile) do
        if not present[id] then
            fireSafeTile[id] = nil
        end
    end
    for id in pairs(lastSafeSq) do
        if not present[id] then
            lastSafeSq[id] = nil
        end
    end
    for id in pairs(CD.zbox) do
        if not present[id] then
            CD.zbox[id] = nil
        end
    end
    for id in pairs(CD.combatUnreach) do
        if not present[id] then
            CD.combatUnreach[id] = nil
        end
    end
    local nowMin = CD.worldMinutes()
    if not CD._unreachPruneMin or (nowMin - CD._unreachPruneMin) >= CD.UNREACH_PRUNE_MIN then
        CD._unreachPruneMin = nowMin
        local nowMs = getTimestampMs()
        for _, unr in pairs(CD.combatUnreach) do
            for z, untilMs in pairs(unr) do
                local gone = untilMs <= nowMs
                if not gone then
                    local alive = z:isExistInTheWorld()
                    gone = not alive
                end
                if gone then
                    unr[z] = nil
                end
            end
        end
    end
    CD.strayScavengePrune(present)
end
CD.tickCompanionFire, CD.pruneFireState = tickCompanionFire, pruneFireState
