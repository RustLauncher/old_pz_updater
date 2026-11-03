CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function worldMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

local pendingClears = { eat = {}, idle = {} }
local lastAttackVar = {}
local idleVarNext = {}
local lastIdleVar = {}
local restState, calmSince, restBeat = {}, {}, {}
local restPose = {}

local function pickDistinct(vars, last)
    if #vars <= 1 then return vars[1] end
    local i = ZombRand(#vars) + 1
    if vars[i] == last then
        i = (i % #vars) + 1
    end
    return vars[i]
end

local function emitEatVar(animal, on, var)
    var = var or CD.EAT_ANIM_VAR
    CD.emit("animvar", { id = animal:getOnlineID(), var = var, on = on and true or false }, animal)
end

-- um pulso por vez na camada de idle a transicao de sentar, a variacao de idle e a de descanso
-- disputam o mesmo balde, entao nenhuma começa por cima da outra.
local function pulseIdleVar(animal, oid, var, now)
    emitEatVar(animal, true, var)
    local ms = CD.idleAnimMs(animal, var)
    pendingClears.idle[oid] = { animal = animal, deadlineMs = now + ms, var = var }
    return ms
end

local function tickVariation(animal, oid, vars)
    if not vars or #vars == 0 then return end
    if pendingClears.idle[oid] then return end
    local now = getTimestampMs()
    local nxt = idleVarNext[oid]
    if nxt == nil then
        idleVarNext[oid] = now + ZombRand(CD.IDLE_GAP_MIN_MS, CD.IDLE_GAP_MAX_MS)
        return
    end
    if now < nxt then return end
    local var = pickDistinct(vars, lastIdleVar[oid])
    lastIdleVar[oid] = var
    idleVarNext[oid] = now + pulseIdleVar(animal, oid, var, now)
        + ZombRand(CD.IDLE_GAP_MIN_MS, CD.IDLE_GAP_MAX_MS)
end

local function updateIdleVariation(animal)
    if not CD.IDLE_ANIM_ENABLED then return end
    local oid = CD.animKey(animal)
    if restState[oid] then return end
    tickVariation(animal, oid, CD.IDLE_ANIM_VARS)
end
CD.updateIdleVariation = updateIdleVariation

local function clearIdleVariation(animal)
    local oid = CD.animKey(animal)
    local e = pendingClears.idle[oid]
    if e then
        emitEatVar(animal, false, e.var)
        pendingClears.idle[oid] = nil
    end
end

local function emitRestVar(animal, var, on)
    CD.emit("animvar", { id = animal:getOnlineID(), var = var, on = on and true or false }, animal)
end

local function setRest(animal, on)
    local id = CD.animKey(animal)
    on = on and true or false
    local pose = restPose[id]
    if (restState[id] or false) ~= on then
        restState[id] = on
        clearIdleVariation(animal)
        if on then
            local poses = CD.restPoses(animal)
            pose = poses[ZombRand(#poses) + 1]
            restPose[id] = pose
            emitRestVar(animal, pose.var, true)
            if pose.enter then
                pulseIdleVar(animal, id, pose.enter, getTimestampMs())
            end
        else
            emitRestVar(animal, pose and pose.var or CD.REST_ANIM_VAR, false)
            restPose[id] = nil
            if pose and pose.exit then
                pulseIdleVar(animal, id, pose.exit, getTimestampMs())
            end
        end
        restBeat[id] = worldMinutes()
    elseif on then
        if worldMinutes() - (restBeat[id] or 0) >= CD.REST_REASSERT_MIN then
            emitRestVar(animal, pose and pose.var or CD.REST_ANIM_VAR, true)
            restBeat[id] = worldMinutes()
        end
        tickVariation(animal, id, pose and pose.variation)
    end
end

local function standUp(animal)
    calmSince[CD.animKey(animal)] = nil
    setRest(animal, false)
end

local function updateRest(animal, d)
    if not CD.REST_ANIM_ENABLED then return end
    if not CD.restAnimEnabled(animal) then
        standUp(animal)
        return
    end
    local id = CD.animKey(animal)
    -- A faixa "far" fica quase sempre acesa em cidade; se ela contasse como alerta o cao nunca deitava.
    local alerted = d.alertTier ~= nil and d.alertTier ~= "far"
    if not (d.autoFeeding or d.inCombat or d.retreating or alerted) then
        calmSince[id] = calmSince[id] or worldMinutes()
        if worldMinutes() - calmSince[id] >= CD.REST_DWELL_MIN then
            setRest(animal, true)
        end
    else
        standUp(animal)
    end
end
CD.standUp, CD.updateRest, CD.setRest = standUp, updateRest, setRest

local function pulseFeedAnim(animal, var, silent, why)
    if not animal then return end
    local oid = CD.animKey(animal)
    local cur = oid and pendingClears.eat[oid]
    if cur and cur.var == var and getTimestampMs() < cur.deadlineMs then
        cur.deadlineMs = getTimestampMs() + CD.HANDFEED_EAT_MS
        if CD.DEBUG_ANIM then
            CD.log(string.format("[CD-ANIM] estende var=%s quem=%s cao=%s restava=%dms",
                tostring(var), tostring(why or "?"), tostring(oid), cur.deadlineMs - getTimestampMs()))
        end
        return
    end
    if CD.DEBUG_ANIM then
        local dt = (cur and cur.lastStartMs) and (getTimestampMs() - cur.lastStartMs) or -1
        CD.log(string.format("[CD-ANIM] COMECA  var=%s quem=%s cao=%s desdeOAnterior=%dms",
            tostring(var), tostring(why or "?"), tostring(oid), dt))
    end
    emitEatVar(animal, true, var)
    local snd = nil
    if not silent then
        snd = CD.breedVoice(animal, (var == CD.DRINK_ANIM_VAR) and "drink" or "eat")
        CD.emitStopSound(animal, CD.breedVoice(animal, "eat"))
        CD.emitStopSound(animal, CD.breedVoice(animal, "drink"))
        CD.emitSound(animal, snd)
    end
    pendingClears.eat[oid] = { animal = animal, deadlineMs = getTimestampMs() + CD.HANDFEED_EAT_MS,
        var = var, sound = snd, lastStartMs = getTimestampMs() }
end
---Plays the eat clip for HANDFEED_EAT_MS, extending one already running, with the breed's eating sound.
---@param animal IsoAnimal|nil
---@param silent boolean|nil no sound
---@param why string|nil label for the animation debug log
function CD.pulseEatAnim(animal, silent, why) pulseFeedAnim(animal, CD.EAT_ANIM_VAR, silent, why or "comer") end
---Plays the drink clip for HANDFEED_EAT_MS, extending one already running, with the breed's drinking sound.
---@param animal IsoAnimal|nil
---@param silent boolean|nil no sound
---@param why string|nil label for the animation debug log
function CD.pulseDrinkAnim(animal, silent, why) pulseFeedAnim(animal, CD.DRINK_ANIM_VAR, silent, why or "beber") end
---Plays the silent sniff clip for HANDFEED_EAT_MS, extending one already running.
---@param animal IsoAnimal|nil
---@param why string|nil label for the animation debug log
function CD.pulseSniffAnim(animal, why) pulseFeedAnim(animal, CD.SNIFF_ANIM_VAR, true, why or "faro") end

local function processAnimClears()
    local now
    for id, e in pairs(pendingClears.eat) do
        now = now or getTimestampMs()
        if now >= e.deadlineMs then
            emitEatVar(e.animal, false, e.var)
            if e.sound and e.animal then
                CD.emitStopSound(e.animal, e.sound)
            end
            pendingClears.eat[id] = nil
        end
    end
    for id, e in pairs(pendingClears.idle) do
        now = now or getTimestampMs()
        if now >= e.deadlineMs then
            emitEatVar(e.animal, false, e.var)
            pendingClears.idle[id] = nil
        end
    end
end

local function emitAnim(animal)
    if not CD.ATTACK_ANIM_ENABLED then return end
    clearIdleVariation(animal)
    local vars = CD.ATTACK_ANIM_VARS or { CD.ATTACK_ANIM_VAR }
    local oid = animal:getOnlineID()
    local key = CD.animKey(animal)
    local var = pickDistinct(vars, lastAttackVar[key])
    lastAttackVar[key] = var
    CD.emit("anim", { id = oid, var = var }, animal)
end

local function emitKnockdown(z)
    if isServer() then
        sendServerCommand(CD.MODULE, "knockdown", { zx = z:getX(), zy = z:getY(), zz = z:getZ() })
        return true
    end
    return CD.applyKnockdown(z)
end
CD.emitKnockdown = emitKnockdown

CD.calmSince = calmSince
CD.clearIdleVariation = clearIdleVariation
CD.emitAnim = emitAnim
CD.emitEatVar = emitEatVar
CD.idleVarNext = idleVarNext
CD.lastAttackVar = lastAttackVar
CD.lastIdleVar = lastIdleVar
CD.pendingClears = pendingClears
CD.processAnimClears = processAnimClears
CD.restBeat = restBeat
CD.restPose = restPose
CD.restState = restState
CD.standUp = standUp
CD.updateRest = updateRest
