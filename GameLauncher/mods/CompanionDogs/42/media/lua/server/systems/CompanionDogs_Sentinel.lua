CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local wasAlarm = {}
CD.sentinelWasAlarm = wasAlarm

local function worldMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

local function retreat(animal, owner, z)
    local ox, oy = owner:getX(), owner:getY()
    local dx, dy = ox - z:getX(), oy - z:getY()
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then
        dx, dy, len = 0, 1, 1
    end
    local tx = math.floor(ox + (dx / len) * CD.RETREAT_BACK_DIST)
    local ty = math.floor(oy + (dy / len) * CD.RETREAT_BACK_DIST)
    local tz = math.floor(owner:getZ())
    CD.data(animal).retreatTile = { x = tx, y = ty, z = tz }
    if animal then
        animal:setAttackedBy(nil)
        animal:setDebugStress(0)
        animal:setVariable("animalSpeed", CD.runAnimSpeed())
        animal:setVariable("animalRunning", true)
        CD.letMove(animal)
        CD.pathStatEmit(animal, "retreat")
        -- Retirada e corrida como qualquer outra: sem a escala propria vale a cheia do upkeep.
        CD.applyGaitScale(animal, CD.combatRunScale(), nil, CD.data(animal))
        animal:pathToLocation(tx, ty, tz)
        CD.forcePathfind(animal)
    end
end

local function scanSentinelZombies(animal, radius)
    local ax = math.floor(animal:getX())
    local ay = math.floor(animal:getY())
    local az = math.floor(animal:getZ())
    local R = math.ceil(radius)
    local nearBand = CD.SENTINEL_BAND_NEAR
    local best, bestDist, count, nearCount = nil, radius, 0, 0
    local zlist = CD.zsnap(animal, ax, ay, az, R, "sq.sentinel")
    for zi = 1, #zlist do
        local o = zlist[zi]
        local dd = CD.dist2D(animal, o)
        if dd <= radius then
            count = count + 1
            if dd <= nearBand then
                nearCount = nearCount + 1
            end
            if dd <= bestDist then
                best, bestDist = o, dd
            end
        end
    end
    if not best then return nil, 0, 0, 0 end
    return best, bestDist, count, nearCount
end
CD.scanSentinelZombies = scanSentinelZombies

-- A faixa so AFROUXA com a margem de histerese; apertar e imediato.
local function alertBand(dist, prev)
    local close = CD.SENTINEL_BAND_CLOSE
    local near = CD.SENTINEL_BAND_NEAR
    local hyst = CD.SENTINEL_BAND_HYST
    if prev == "close" or prev == "group" then close = close + hyst
    elseif prev == "near" then near = near + hyst end
    if dist <= close then return "close" end
    if dist <= near then return "near" end
    return "far"
end

local function sentinelLOS(animal, target)
    return LosUtil.lineClearCollide(
        math.floor(target:getX()), math.floor(target:getY()), math.floor(target:getZ()),
        math.floor(animal:getX()), math.floor(animal:getY()), math.floor(animal:getZ()),
        false)
end

local function updateSentinel(animal, owner, d)
    local spd = getGameSpeed()
    if spd > 1 then return end
    if owner:isAsleep() then return end

    local interval = CD.SENTINEL_SCAN_INTERVAL_MS
    if (d.zQuiet or 0) >= CD.SCAN_QUIET_STREAK then
        interval = interval * (1 + CD.SCAN_QUIET_SKIP_MAX)
    end
    if CD.cooldown(animal, "scan", interval) then
        return
    end

    local prevTier = d.alertTier
    local mode = CD.getAlertMode(animal)
    local silent = mode == "silent"
    local quiet = mode == "quiet"
    if silent then
        d.alertTier = nil
        if prevTier ~= nil then
            CD.transmit(animal)
        end
        return
    end
    if prevTier == nil then
        wasAlarm[animal:getOnlineID()] = nil
    end

    local radius = quiet and CD.sentinelQuietRadius() or CD.effectiveSentinelRadius(animal)
    local nearest, dist, _, nearCount = scanSentinelZombies(animal, radius)
    CD.scanQuietResult(d, nearest ~= nil)

    if not nearest then
        if not (d.alertTier and not CD.cooledDown(animal, "detect", CD.SENTINEL_ALERT_HOLD_MS)) then
            d.alertTier = nil
            if prevTier ~= nil then
                CD.transmit(animal)
            end
        end
        return
    end
    CD.stamp(animal, "detect")

    local st = CD.getState(animal)
    local autoProtectOn = CD.autoProtectEnabled() and CD.getAutoProtect(animal)
    local protecting = autoProtectOn and d.protectUntilMin and worldMinutes() < d.protectUntilMin
    local engageR = (st == CD.STATE_GUARD or protecting) and CD.GUARD_RADIUS
        or ((st == CD.STATE_FOLLOW) and CD.FOLLOW_DEFEND_RADIUS or nil)
    local engageDist = dist
    if st == CD.STATE_FOLLOW and owner then
        engageDist = CD.dist2D(owner, nearest)
    end
    if not quiet and CD.combatEnabled() and CD.breedCanFight(animal) and engageR and engageDist <= engageR then
        local commanded = d.attackUntilMin and worldMinutes() < d.attackUntilMin
        local willEngage = st == CD.STATE_GUARD or protecting or commanded
            or (autoProtectOn and CD.playerFighting(owner))
            or (not d.standDown and (CD.combatInitiative() or CD.playerFighting(owner)))
        if not willEngage and autoProtectOn then
            if nearest then
                local t = nearest:getTarget()
                if t == owner or t == animal then
                    willEngage = true
                end
            end
        end
        if willEngage then
            d.alertTier = nil
            if prevTier ~= nil then
                CD.transmit(animal)
            end
            return
        end
    end

    local seen = (sentinelLOS(animal, nearest) == false)
    -- A multidao so conta dentro da faixa media, entao alarme implica zumbi ate SENTINEL_BAND_NEAR
    -- e a faixa "far" fica muda por construcao.
    local crowd = nearCount >= CD.SENTINEL_ALARM_COUNT
    local alarm = dist <= CD.SENTINEL_CLOSE_DIST
        or crowd
        or (seen and dist <= CD.SENTINEL_SEEN_DIST)
    local barking = alarm and not quiet
    local tier = crowd and "group" or alertBand(dist, prevTier)
    local escalated = prevTier ~= tier

    if animal and (CD.getState(animal) ~= CD.STATE_FOLLOW or CD.dist2D(animal, owner) <= CD.followKeepFrom(d)) then
        animal:faceThisObject(nearest)
    end

    local id = animal:getOnlineID()
    if barking then
        local escalatedUp = not wasAlarm[id]
        if escalatedUp or CD.cooledDown(animal, "alarmBark", CD.SENTINEL_ALARM_BARK_COOLDOWN_MS) then
            if CD.bark(animal) then
                CD.stamp(animal, "alarmBark")
                if CD.sentinelBarkAttracts()
                    and not CD.cooldown(animal, "noise", CD.SENTINEL_NOISE_COOLDOWN_MS) then
                    local noise = CD.breedNumber(animal, "barkNoiseMult")
                    addSound(animal, math.floor(animal:getX()), math.floor(animal:getY()), math.floor(animal:getZ()),
                        math.floor(CD.SENTINEL_BARK_RADIUS * noise + 0.5),
                        math.floor(CD.SENTINEL_BARK_VOLUME * noise + 0.5))
                end
            end
        end
        -- Halo so na entrada em grupo, e com o cooldown do latido: uma multidao na fronteira da
        -- faixa entra e sai de "group" a cada varredura e viraria enxurrada no canto da tela.
        if tier == "group" and prevTier ~= "group"
            and not CD.cooldown(animal, "alertHalo", CD.SENTINEL_ALARM_BARK_COOLDOWN_MS) then
            CD.notifyOwner(owner, "alert", { tier = tier, name = d.name, breed = CD.getBreed(animal) })
        end
    elseif tier ~= "far" and ((prevTier == nil and CD.cooledDown(animal, "growl", CD.BARK_COOLDOWN_MS))
        or CD.cooledDown(animal, "growl", CD.SENTINEL_AWARE_COOLDOWN_MS)) then
        CD.stamp(animal, "growl")
        CD.emitSound(animal, CD.breedVoice(animal, "growl"))
    end
    wasAlarm[id] = barking or nil

    if prevTier == nil then
        CD.addSkillXP(animal, "scent", CD.SCENT_XP_PER_DETECT)
    end

    d.alertTier = tier
    if escalated then
        CD.transmit(animal)
    end
end
CD.retreat, CD.updateSentinel = retreat, updateSentinel
