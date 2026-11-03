CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function clearAttack(animal, d)
    d.attackUntilMin = nil
    d.attackArmed = nil
    CD.combatTarget[animal:getOnlineID()] = nil
end

---Drops the combat target, the retreat and any pending attack order.
---@param animal IsoAnimal
---@param d table|nil companion ModData; read from the dog when nil
function CD.stopCombat(animal, d)
    d = d or CD.data(animal)
    local id = animal:getOnlineID()
    CD.combatTarget[id] = nil
    CD.combatMaintainDogs[id] = nil
    CD.setInCombat(animal, d, false)
    d.retreating = false
    d.combatMode = nil
    d.combatHold = nil
    d.cstall = nil
    d.retreatTile = nil
    d.combatFollowVault = nil
    clearAttack(animal, d)
end

-- square seco atras do dono para depositar o pet, nil se nenhuma das duas distancias serve
local function landingBehind(owner, sq, bz)
    local f = owner:getForwardDirection()
    local cell = getCell()
    for _, dist in ipairs({ CD.TELEPORT_BACK_DIST, 1 }) do
        local nx = (sq:getX() + 0.5) - f:getX() * dist
        local ny = (sq:getY() + 0.5) - f:getY() * dist
        local s = cell:getGridSquare(math.floor(nx), math.floor(ny), bz)
        if s and not s:isSolid() and not s:isSolidTrans() and CD.squareHasFloor(s) then
            return nx, ny, s
        end
    end
    return nil
end

local function teleportRecover(animal, owner)
    local sq = owner:getCurrentSquare()
    if not sq then return false end
    CD.perfCount("teleport.recover")
    animal:stopAllMovementNow()
    CD.clearClimbVars(animal)
    local bz = sq:getZ()
    local bx, by, tsq = sq:getX() + 0.5, sq:getY() + 0.5, sq
    local nx, ny, nsq = landingBehind(owner, sq, bz)
    if nx then
        bx, by, tsq = nx, ny, nsq
    end
    animal:setX(bx)
    animal:setY(by)
    animal:setZ(bz)
    animal:setCurrent(tsq)
    return true
end
CD.teleportRecover = teleportRecover

local function releaseLandGlide(animal, d)
    animal:setDeferredMovementEnabled(true)
    animal:setVariable("animalRunning", false)
    animal:setVariable("animalSpeed", 1.0)
    d.running = nil
    CD.holdStill(animal)
    CD.updateIdleVariation(animal)
    d.followPathTile = nil
    CD.landGlide[animal:getOnlineID()] = nil
end

local function applyGlidePose(animal, run)
    local b = animal:getBehavior()
    if b then
        b:setBlockMovement(true)
    end
    animal:setDeferredMovementEnabled(false)
    animal:setVariable("animalRunning", run and true or false)
    animal:setVariable("animalSpeed", run and CD.runAnimSpeed() or CD.walkAnimSpeed())
end

-- devolve true quando o planeio acabou e o registro deve sair de CD.landGlide
local function landGlideStep(id, g, now)
    local animal = g.animal
    if not animal or not animal:isExistInTheWorld() then return true end
    local d = CD.data(animal)
    if not d or d.fenceHop then return true end
    if g.combat then
        local z = CD.combatTarget[id]
        local zvalid = false
        if g.tx then
            zvalid = true
        else
            if z then
                zvalid = z ~= nil and CD.isThreatZombie(z) and CD.inWorldNow(z)
                    and math.floor(z:getZ()) == math.floor(animal:getZ())
            end
        end
        if not zvalid then
            if g.care then
                CD.letMove(animal)
                return true
            end
            g.combat = nil
        else
            local zx, zy = g.tx or z:getX(), g.ty or z:getY()
            local x, y = animal:getX(), animal:getY()
            local ddx, ddy = zx - x, zy - y
            local dist = math.sqrt(ddx * ddx + ddy * ddy)
            if dist <= CD.STRIKE_DIST + 0.2 then
                CD.letMove(animal)
                if not g.care then
                    CD.combatMaintainDogs[id] = animal
                end
                CD.landGlide[id] = nil
                return true
            end
            local cowner = (not g.care) and CD.getOwnerPlayer(animal) or nil
            if cowner and CD.dist2D(animal, cowner) > CD.TELEPORT_DIST then
                return teleportRecover(animal, cowner)
            end
            local dt = now - (g.lastMs or now)
            local maxdt = CD.STEER_MAX_DT_MS
            if dt < 0 then dt = 0 elseif dt > maxdt then dt = maxdt end
            g.lastMs = now
            local run = dist > CD.FOLLOW_RUN_DIST and CD.mayRunFrom(d)
            applyGlidePose(animal, run)
            local wm, rm = CD.vetGaitMult(d)
            local step = (run and CD.STEER_RUN_SPEED * (rm or wm) or CD.STEER_WALK_SPEED * wm) * dt / 1000
            local stopGap = CD.STRIKE_DIST
            local nx, ny = x, y
            if dist > stopGap then
                local sstep = math.min(step, dist - stopGap)
                nx, ny = x + ddx / dist * sstep, y + ddy / dist * sstep
            end
            if dist > 1e-3 then
                animal:setForwardDirection(ddx / dist, ddy / dist)
            end
            animal:setX(nx)
            animal:setY(ny)
            animal:setNextX(nx)
            animal:setNextY(ny)
            if CD.FENCE_LAND_USE_STREAM and isServer() then
                local rec = CD.landStreaming[id]
                if rec then
                    rec.animal = animal
                    rec.untilMs = now + 1000
                else
                    CD.landStreaming[id] = { animal = animal, untilMs = now + 1000 }
                end
            end
            return false
        end
    end
    local owner = CD.getOwnerPlayer(animal)
    if not owner or not owner:getCurrentSquare() then return false end
    if math.floor(owner:getZ()) ~= math.floor(animal:getZ()) then return true end

    local ox, oy = owner:getX(), owner:getY()
    local x, y = animal:getX(), animal:getY()
    local ddx, ddy = ox - x, oy - y
    local dist = math.sqrt(ddx * ddx + ddy * ddy)

    if dist > CD.TELEPORT_DIST then
        return teleportRecover(animal, owner)
    end

    if g.ox and (math.abs(ox - g.ox) + math.abs(oy - g.oy)) < CD.OWNER_STILL_EPS then
        g.stillSince = g.stillSince or now
    else
        g.ox, g.oy, g.stillSince = ox, oy, nil
    end

    if dist <= CD.followKeepFrom(d) + 0.3
       and g.stillSince and (now - g.stillSince) >= CD.OWNER_STILL_MS then
        releaseLandGlide(animal, d)
        return true
    end

    local dt = now - (g.lastMs or now)
    local maxdt = CD.STEER_MAX_DT_MS
    if dt < 0 then dt = 0 elseif dt > maxdt then dt = maxdt end
    g.lastMs = now
    local run = dist > CD.followRunFrom(d) and CD.mayRunFrom(d)
    applyGlidePose(animal, run)
    local wm, rm = CD.vetGaitMult(d)
    local step = (run and CD.STEER_RUN_SPEED * (rm or wm) or CD.STEER_WALK_SPEED * wm) * dt / 1000
    local stopGap = CD.followKeepFrom(d)
    local nx, ny = x, y
    if dist > stopGap then
        local sstep = math.min(step, dist - stopGap)
        nx, ny = x + ddx / dist * sstep, y + ddy / dist * sstep
    end
    if dist > 1e-3 then
        animal:setForwardDirection(ddx / dist, ddy / dist)
    end
    animal:setX(nx)
    animal:setY(ny)
    animal:setNextX(nx)
    animal:setNextY(ny)
    if CD.FENCE_LAND_USE_STREAM and isServer() then
        local rec = CD.landStreaming[id]
        if rec then
            rec.animal = animal
            rec.untilMs = now + 1000
        else
            CD.landStreaming[id] = { animal = animal, untilMs = now + 1000 }
        end
    end
    return false
end

local function tickLandGlide()
    if not CD.FENCE_LAND_GLIDE then return end
    local now = getTimestampMs()
    for id, g in pairs(CD.landGlide) do
        if landGlideStep(id, g, now) then
            CD.landGlide[id] = nil
        end
    end
end

CD.clearAttack = clearAttack
CD.tickLandGlide = tickLandGlide
