CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function vetLog(fmt, ...)
    if CD.VET_DEBUG then
        CD.log(string.format("[CD-VET] " .. fmt, ...))
    end
end

local function roll(chance)
    if chance <= 0 then return false end
    return ZombRand(0, 10000) / 10000 < chance
end

local function onCooldown(d, now)
    return d.vetLastHitMin ~= nil and (now - d.vetLastHitMin) < CD.VET_LESION_COOLDOWN_MIN
end

local function aggravation(animal, d)
    local m = 1
    local base = d.maxHealth or 1
    if base <= 0 then
        base = 1
    end
    if animal:getHealth() / base < CD.WOUNDED_ENTER_FRAC then
        m = m * CD.VET_AGGR_LOWHP
    end
    if CD.getStress(animal) > CD.VET_AGGR_STRESS_MIN then
        m = m * CD.VET_AGGR_STRESS
    end
    if m > CD.VET_AGGR_CAP then
        m = CD.VET_AGGR_CAP
    end
    return m
end

local function subject(animal, d)
    return { id = animal:getOnlineID(), name = d.name, breed = CD.getBreed(animal) }
end

local function whine(animal)
    CD.emitSound(animal, CD.breedVoice(animal, "whine"))
end

-- Cao doente larga o trabalho na hora: caca e guarda sao as duas ordens que a recusa cobre.
local function dropWork(animal, d)
    if d.huntMode then
        CD.clearHuntMode(animal)
    end
    if CD.getState(animal) == CD.STATE_GUARD then
        CD.setState(animal, CD.STATE_FOLLOW)
        CD.letMove(animal)
    end
end

local function releaseStay(animal, d)
    if d.vetStayForced == nil then return end
    d.vetStayForced = nil
    if CD.getState(animal) == CD.STATE_STAY then
        CD.setState(animal, CD.STATE_FOLLOW)
        CD.letMove(animal)
    end
end

local function newWound(animal, d, now, kind)
    d.vetKind = kind
    d.vetStage = 0
    d.vetDress = 0
    d.vetCureMin = 0
    d.vetExpoMin = 0
    d.vetLastHitMin = now
    d.vetBleedMin = 0
    d.vetPaw = roll(CD.VET_FRONT_PAW_CHANCE) and "front" or "back"
    CD.vetApplyLimpVars(animal)
    dropWork(animal, d)
    whine(animal)
end

local function lesion(animal, owner, d, now, source)
    newWound(animal, d, now, "cut")
    CD.perfCount("vet.lesion")
    vetLog("lesao cao=%s fonte=%s hp=%.2f", tostring(d.name), source, animal:getHealth())
    CD.notifyOwner(owner, "vetwound", subject(animal, d))
    CD.transmit(animal)
end

local function sprain(animal, owner, d, now)
    newWound(animal, d, now, "sprain")
    CD.perfCount("vet.sprain")
    vetLog("entorse cao=%s", tostring(d.name))
    CD.notifyOwner(owner, "vetsprain", subject(animal, d))
    CD.transmit(animal)
end

local function fracture(animal, owner, d, now)
    d.vetBroken = 1
    d.vetLastHitMin = now
    CD.stopCombat(animal, d)
    whine(animal)
    CD.perfCount("vet.fracture")
    vetLog("fratura cao=%s", tostring(d.name))
    CD.notifyOwner(owner, "vetfracture", subject(animal, d))
    CD.transmit(animal)
end

-- O curativo fica no cao ate sair: volta ao dono como bandagem suja ao remover ou ao curar.
local function returnDressing(owner, d)
    local t = d.vetDressItem
    d.vetDressItem = nil
    d.vetDressDirty = nil
    if t == nil or owner == nil then return end
    local it = owner:getInventory():AddItem(t)
    if it then
        it:SynchSpawn()
    end
end

local function heal(animal, owner, d)
    returnDressing(owner, d)
    d.vetKind = nil
    d.vetStage = nil
    d.vetDress = nil
    d.vetCureMin = nil
    d.vetExpoMin = nil
    d.vetPaw = nil
    d.vetBleedMin = nil
    d.vetBroken = nil
    d.vetStageMin = nil
    d.vetInfectMin = nil
    d.vetCrit = nil
    d.vetAbxMin = nil
    d.vetGarlicMin = nil
    d.vetAidPlantain, d.vetAidAloe, d.vetAidComfrey, d.vetSplint = nil, nil, nil, nil
    -- O descanso existe para o cao nao colecionar ferida na mesma luta. Curado, ele nao tem mais o que
    -- proteger: deixar o carimbo de pe daria duas horas de cao intocavel com a ficha limpa.
    d.vetLastHitMin = nil
    releaseStay(animal, d)
    CD.vetApplyLimpVars(animal)
    CD.perfCount("vet.heal")
    vetLog("curou cao=%s", tostring(d.name))
    CD.notifyOwner(owner, "vethealed", subject(animal, d))
    CD.transmit(animal)
end

local function cureInfection(animal, owner, d)
    d.vetStage = 0
    d.vetStageMin = nil
    d.vetInfectMin = nil
    d.vetCrit = nil
    d.vetGarlicMin = nil
    d.vetCureMin = 0
    releaseStay(animal, d)
    CD.perfCount("vet.cureinfect")
    vetLog("infeccao curada cao=%s", tostring(d.name))
    CD.notifyOwner(owner, "vetrecovered", subject(animal, d))
    CD.transmit(animal)
end

local function setStage(animal, owner, d, stage)
    d.vetStage = stage
    d.vetStageMin = 0
    d.vetCureMin = 0
    CD.perfCount("vet.stage" .. tostring(stage))
    vetLog("estagio %d cao=%s", stage, tostring(d.name))
    if stage == 1 then
        d.vetInfectMin = 0
        CD.notifyOwner(owner, "vetinfected", subject(animal, d))
    else
        CD.notifyOwner(owner, "vetfever", subject(animal, d))
    end
    CD.transmit(animal)
end

-- Critico e estado de vida: infeccao com a vida num decimo. E estado, nao pose: em Ficar o cao deita
-- sozinho e nenhuma ordem de mover chega. Sai sozinho quando a vida sobe.
local function setCritical(animal, owner, d, on)
    if on and d.vetCrit == nil then
        d.vetCrit = 1
        d.vetStayForced = 1
        dropWork(animal, d)
        CD.stopCombat(animal, d)
        CD.setState(animal, CD.STATE_STAY)
        whine(animal)
        CD.perfCount("vet.critical")
        CD.notifyOwner(owner, "vetcritical", subject(animal, d))
        CD.transmit(animal)
    elseif not on and d.vetCrit ~= nil then
        d.vetCrit = nil
        releaseStay(animal, d)
        CD.transmit(animal)
    end
end

local function cureMult(animal, owner, d)
    if d.inCombat then return 0 end
    if CD.getState(animal) == CD.STATE_STAY then return 1 end
    local active = owner ~= nil and d.companionToken ~= nil and d.companionToken == CD.playerData(owner).token
    if not active then return 1 end
    return CD.VET_WORK_CURE_MULT
end

local function drain(animal, d, step, perDay, floorFrac)
    local base = d.maxHealth or 1
    if base <= 0 then
        base = 1
    end
    local floor = floorFrac * base
    local hp = animal:getHealth()
    if hp <= floor then return hp end
    local nh = hp - perDay * (step / 1440)
    if nh < floor then
        nh = floor
    end
    animal:setIsInvincible(false)
    animal:setHealth(nh)
    animal:setIsInvincible(true)
    return nh
end

local function medsTick(animal, owner, d, step)
    -- O emplastro de alho e o antibiotico de erva: cura a infeccao do mesmo jeito, so que mais devagar.
    if d.vetGarlicMin ~= nil then
        d.vetGarlicMin = d.vetGarlicMin - step
        if d.vetGarlicMin <= 0 then
            d.vetGarlicMin = nil
            if (d.vetStage or 0) >= 1 then
                cureInfection(animal, owner, d)
            end
        end
    end
    if d.vetAbxMin == nil then return end
    d.vetAbxMin = d.vetAbxMin - step
    if d.vetAbxMin > 0 then return end
    d.vetAbxMin = nil
    if (d.vetStage or 0) >= 1 then
        cureInfection(animal, owner, d)
    end
    -- Antibiotico nao mata virus: so encurta a gripe que o cao ja esta carregando.
    if d.vetFluMin ~= nil then
        d.vetFluMin = d.vetFluMin * CD.VET_FLU_ABX_CUT
    end
end

-- Com a letalidade desligada nenhum dreno do vetcare passa do piso; ligada, a vida vai a zero e o
-- caminho de morte e o mesmo da negligencia.
local function drainFloor()
    if CD.deathEnabled() then return 0 end
    return CD.VET_SAFE_HEALTH_FLOOR
end

local function infectionTick(animal, owner, d, step)
    -- Sangramento e do curativo, nao da infeccao: ferida sem bandagem sangra em qualquer estagio,
    -- ate coagular sozinha em meio dia.
    if d.vetKind == "cut" and (d.vetDress or 0) == 0 then
        local bled = d.vetBleedMin or 0
        if bled < CD.VET_BLEED_STOP_MIN then
            drain(animal, d, step, CD.VET_BLEED_DRAIN_PER_DAY, drainFloor())
            bled = bled + step
            d.vetBleedMin = bled
            if bled >= CD.VET_BLEED_STOP_MIN then
                CD.perfCount("vet.bleedstop")
                vetLog("parou de sangrar cao=%s", tostring(d.name))
                if owner ~= nil then
                    CD.notifyOwner(owner, "vetbleedstopped", subject(animal, d))
                end
                CD.transmit(animal)
            end
        end
    end
    local stage = d.vetStage or 0
    if stage == 0 then return end
    -- Sem dono resolvido a cadeia congela: ninguem ve o aviso, ninguem pode salvar.
    if owner == nil then return end
    local hp = drain(animal, d, step, CD.VET_STAGE_DRAIN_PER_DAY[stage] or 0, drainFloor())
    local base = d.maxHealth or 1
    if base <= 0 then
        base = 1
    end
    setCritical(animal, owner, d, hp <= CD.VET_CRIT_HEALTH_FRAC * base)
    -- O corpo vence a infeccao sozinho em dois dias; o antibiotico so encurta.
    d.vetInfectMin = (d.vetInfectMin or 0) + step * CD.vetRecoveryRate(d)
    if d.vetInfectMin >= CD.VET_INFECT_HEAL_MIN then
        cureInfection(animal, owner, d)
        return
    end
    -- Bandagem nao cura infeccao: so o antibiotico ou o alho seguram a febre.
    if stage < 2 and d.vetAbxMin == nil and d.vetGarlicMin == nil then
        d.vetStageMin = (d.vetStageMin or 0) + step
        if d.vetStageMin >= CD.VET_STAGE_MIN then
            setStage(animal, owner, d, 2)
        end
    end
end

local function advance(animal, owner, d, step)
    local dressed = d.vetDress or 0
    local mult = cureMult(animal, owner, d)
    local stage = d.vetStage or 0
    if stage >= 1 then return end
    d.vetCureMin = (d.vetCureMin or 0) + step * mult * CD.vetAidHealMult(d)
    if d.vetCureMin >= CD.vetHealGoal(d) then
        heal(animal, owner, d)
        return
    end
    if d.vetKind ~= "cut" then return end
    if CD.vetShielded(d, CD.worldMinutes()) then
        d.vetExpoMin = 0
        return
    end
    d.vetExpoMin = (d.vetExpoMin or 0) + step
    if d.vetExpoMin < CD.VET_INFECT_WINDOW_MIN then return end
    d.vetExpoMin = 0
    local chance = CD.VET_INFECT_CHANCE[dressed] or 0
    if d.vetDressDirty ~= nil then
        chance = CD.VET_INFECT_CHANCE_DIRTY
    end
    if roll(chance * CD.vetAidInfectMult(d)) then
        CD.perfCount("vet.infect")
        setStage(animal, owner, d, 1)
    end
end

-- Verme e evolucao do estomago virado, nao efeito colateral dele: enquanto o bicho esta doente, o
-- relogio de incubacao corre e cada janela fechada rola uma vez. Correr mesmo com o cao sem sede, que
-- e o que segura a CURA do estomago: ficar sem beber nao protege de verme, so adia a melhora.
-- A dose corre mesmo com o estomago ja curado: o verme e cronico e o remedio leva horas.
local function dewormTick(animal, owner, d, step)
    if d.vetDewormMin == nil then return end
    local left = d.vetDewormMin - step
    local acted = left <= CD.VET_DEWORM_MIN - CD.VET_DEWORM_ACT_MIN
    if acted and d.vetWorms ~= nil then
        d.vetWorms = nil
        d.vetCourseWorms = nil
        CD.perfCount("vet.dewormed")
        vetLog("vermifugo agiu cao=%s", tostring(d.name))
        CD.notifyOwner(owner, "vetdewormed", subject(animal, d))
        CD.transmit(animal)
    end
    if left <= 0 then
        d.vetDewormMin = nil
        CD.transmit(animal)
        return
    end
    d.vetDewormMin = left
end

local function wormsTick(animal, owner, d, step)
    if d.vetWorms ~= nil or d.vetDewormMin ~= nil then return end
    if CD.vetProtected(d, "vetDewormPrevUntilMin", CD.worldMinutes()) then return end
    local expo = (d.vetWormsExpoMin or 0) + step
    if expo < CD.VET_WORMS_WINDOW_MIN then
        d.vetWormsExpoMin = expo
        return
    end
    d.vetWormsExpoMin = 0
    if not roll(CD.vetWormsChance()) then return end
    d.vetWorms = 1
    CD.perfCount("vet.worms")
    vetLog("verme cao=%s", tostring(d.name))
    CD.notifyOwner(owner, "vetworms", subject(animal, d))
    CD.transmit(animal)
end

local function gastroTick(animal, owner, d, step)
    if d.vetGastroMin == nil then return end
    wormsTick(animal, owner, d, step)
    if animal:getThirst() > CD.VET_GASTRO_THIRST_MAX then return end
    d.vetGastroMin = d.vetGastroMin - step * CD.vetRecoveryRate(d)
    if d.vetGastroMin > 0 then return end
    d.vetGastroMin = nil
    d.vetWormsExpoMin = nil
    CD.perfCount("vet.gastroheal")
    CD.notifyOwner(owner, "vetgastrohealed", subject(animal, d))
    CD.transmit(animal)
end

local function rollPct(pct)
    return roll(pct / 100)
end

local function spanMin(lo, hi)
    return ZombRand(lo, hi + 1)
end

-- Gripe canina -------------------------------------------------------------------------------

local function startFlu(animal, owner, d, source)
    if d.vetFluMin ~= nil then return false end
    local now = CD.worldMinutes()
    if CD.vetShielded(d, now) then return false end
    d.vetFluMin = spanMin(CD.VET_FLU_MIN_MIN, CD.VET_FLU_MAX_MIN)
    d.vetFluExpoMin = now + CD.VET_FLU_CONTACT_COOLDOWN_MIN
    dropWork(animal, d)
    whine(animal)
    CD.perfCount("vet.flu")
    vetLog("gripe cao=%s fonte=%s", tostring(d.name), source)
    CD.notifyOwner(owner, "vetflu", subject(animal, d))
    CD.transmit(animal)
    return true
end

-- So o cao gripado varre, e no maximo uma vez por hora: o custo fica com quem esta doente, nao com
-- o mapa inteiro. Vacinado nao espalha, que e o que faz a vacina valer num canil cheio.
local function fluSpread(animal, d, now)
    if d.vetFluQuiet ~= nil then return end
    if d.vetFluExpoMin ~= nil and now < d.vetFluExpoMin then return end
    d.vetFluExpoMin = now + CD.VET_FLU_CONTACT_COOLDOWN_MIN
    local x, y, z = animal:getX(), animal:getY(), math.floor(animal:getZ())
    local range = CD.VET_FLU_CONTACT_RANGE
    CD.regEach(CD.regCompanions(), function(other)
        if other == animal then return end
        if math.floor(other:getZ()) ~= z then return end
        if math.abs(other:getX() - x) > range or math.abs(other:getY() - y) > range then return end
        local od = CD.data(other)
        if od.vetFluMin ~= nil or od.careMode then return end
        if not roll(CD.vetFluChance()) then return end
        startFlu(other, CD.getOwnerPlayer(other), od, "contato")
    end, "vet.fluscan")
end

local function fluTick(animal, owner, d, step, now)
    if d.vetFluMin == nil then
        -- Fome severa abre a porta da gripe: o corpo sem proteina nao segura o bicho.
        if CD.getHunger(animal) < CD.SEVERE_NEED then
            d.vetFluRollMin = nil
            return
        end
        local left = (d.vetFluRollMin or 0) - step
        if left > 0 then
            d.vetFluRollMin = left
            return
        end
        d.vetFluRollMin = CD.VET_FLU_STARVE_ROLL_MIN
        if roll(CD.vetFluChance()) then
            startFlu(animal, owner, d, "fome")
        end
        return
    end
    CD.addCombatStress(animal, CD.VET_FLU_STRESS_PER_DAY * (step / 1440))
    fluSpread(animal, d, now)
    d.vetFluMin = d.vetFluMin - step * CD.vetRecoveryRate(d)
    if d.vetFluMin > 0 then return end
    d.vetFluMin = nil
    d.vetFluQuiet = nil
    d.vetFluExpoMin = nil
    d.vetCourseFlu = nil
    d.vetFluReliefMin = nil
    CD.perfCount("vet.flucured")
    CD.notifyOwner(owner, "vetflucured", subject(animal, d))
    CD.transmit(animal)
end

-- Dirofilariose ------------------------------------------------------------------------------

local function startHeartworm(animal, owner, d, source)
    if d.vetHwMin ~= nil then return false end
    local now = CD.worldMinutes()
    if CD.vetProtected(d, "vetHwPrevUntilMin", now) then return false end
    d.vetHwMin = spanMin(CD.VET_HW_MIN_MIN, CD.VET_HW_MAX_MIN)
    d.vetHwOutMin = nil
    dropWork(animal, d)
    if d.distractUntilMin ~= nil and CD.endDistract then
        CD.endDistract(animal, d)
    end
    CD.stopCombat(animal, d)
    whine(animal)
    CD.perfCount("vet.heartworm")
    vetLog("dirofilariose cao=%s fonte=%s", tostring(d.name), source)
    CD.notifyOwner(owner, "vetheartworm", subject(animal, d))
    CD.transmit(animal)
    return true
end

local function heartwormTick(animal, owner, d, step)
    if d.vetHwMin ~= nil then
        drain(animal, d, step, CD.VET_HW_DRAIN_PER_DAY, drainFloor())
        d.vetHwMin = d.vetHwMin - step * CD.vetRecoveryRate(d)
        if d.vetHwMin > 0 then return end
        d.vetHwMin = nil
        d.vetCourseHw = nil
        CD.perfCount("vet.heartwormcured")
        CD.notifyOwner(owner, "vetheartwormcured", subject(animal, d))
        CD.transmit(animal)
        return
    end
    if CD.vetProtected(d, "vetHwPrevUntilMin", CD.worldMinutes()) then
        d.vetHwOutMin = nil
        return
    end
    -- O mosquito e de fora: entrar em casa zera a conta, e so tempo seguido ao ar livre rola.
    local square = animal:getSquare()
    if square == nil or not square:isOutside() then
        d.vetHwOutMin = nil
        return
    end
    local out = (d.vetHwOutMin or 0) + step
    if out < CD.VET_HW_EXPO_ROLL_MIN then
        d.vetHwOutMin = out
        return
    end
    d.vetHwOutMin = 0
    if roll(CD.vetHeartwormChance()) then
        startHeartworm(animal, owner, d, "ar livre")
    end
end

-- Alergia de pele ----------------------------------------------------------------------------

local function allergyParts()
    local pool = {}
    for i = 1, #CD.HEALTH_EXTERNAL_PARTS do
        pool[i] = CD.HEALTH_EXTERNAL_PARTS[i]
    end
    local count = spanMin(CD.VET_ALG_PARTS_MIN, CD.VET_ALG_PARTS_MAX)
    local picked = {}
    for _ = 1, count do
        picked[#picked + 1] = table.remove(pool, ZombRand(1, #pool + 1))
    end
    return table.concat(picked, ",")
end

local function startAllergy(animal, owner, d, source, key)
    if d.vetAlgMin ~= nil then return false end
    if CD.vetProtected(d, "vetAlgPrevUntilMin", CD.worldMinutes()) then return false end
    d.vetAlgMin = spanMin(CD.VET_ALG_MIN_MIN, CD.VET_ALG_MAX_MIN)
    d.vetAlgParts = allergyParts()
    d.vetAlgSrc = source
    CD.perfCount("vet.allergy")
    vetLog("alergia cao=%s fonte=%s", tostring(d.name), source)
    local args = subject(animal, d)
    args.protein = source
    CD.notifyOwner(owner, key or "vetallergy", args)
    CD.transmit(animal)
    return true
end

local function allergyTick(animal, owner, d, step)
    if d.vetAlgMin == nil then return end
    CD.addCombatStress(animal, CD.VET_ALG_STRESS_PER_DAY * (step / 1440))
    d.vetAlgMin = d.vetAlgMin - step * CD.vetRecoveryRate(d)
    if d.vetAlgMin > 0 then return end
    d.vetAlgMin = nil
    d.vetAlgParts = nil
    d.vetAlgSrc = nil
    d.vetCourseAlg = nil
    CD.perfCount("vet.allergycured")
    CD.notifyOwner(owner, "vetallergycured", subject(animal, d))
    CD.transmit(animal)
end

-- Pulga e carrapato --------------------------------------------------------------------------

local function startInfest(animal, owner, d)
    local name = ZombRand(0, 2) == 0 and "fleas" or "ticks"
    local kind = CD.VET_INFEST_KINDS[name]
    if d[kind.field] ~= nil then return false end
    if CD.vetProtected(d, "vetFleaPrevUntilMin", CD.worldMinutes()) then return false end
    d[kind.field] = CD.VET_INFEST_ACTIVE_MIN
    d[kind.pulse] = spanMin(CD.VET_INFEST_PULSE_MIN_MIN, CD.VET_INFEST_PULSE_MAX_MIN)
    CD.perfCount("vet.infest")
    vetLog("infestacao cao=%s tipo=%s", tostring(d.name), name)
    CD.notifyOwner(owner, kind.notify, subject(animal, d))
    CD.transmit(animal)
    return true
end

-- Passada a fase de coceira o bicho fica quieto no cao, mas continua la ate alguem dar o remedio.
local function infestTick(animal, owner, d, step, name)
    local kind = CD.VET_INFEST_KINDS[name]
    local left = d[kind.field]
    if left == nil or left <= 0 then return end
    d[kind.field] = math.max(0, left - step)
    local pulse = (d[kind.pulse] or 0) - step
    if pulse > 0 then
        d[kind.pulse] = pulse
        return
    end
    d[kind.pulse] = spanMin(CD.VET_INFEST_PULSE_MIN_MIN, CD.VET_INFEST_PULSE_MAX_MIN)
    CD.addCombatStress(animal, CD.VET_FLEA_STRESS * kind.mult)
    if rollPct(CD.VET_FLEA_ALLERGY_PCT * kind.mult) then
        startAllergy(animal, owner, d, name)
    end
end

-- A pinca tira os bichos que se veem; os ovos ficam, e eles voltam quando o prazo acaba, a nao ser que
-- o cao esteja protegido ou em tratamento.
local PICKED = { { flag = "vetPickedFleas", name = "fleas" }, { flag = "vetPickedTicks", name = "ticks" } }

local function pickedTick(animal, owner, d, step)
    if d.vetPickedMin == nil then return end
    local left = d.vetPickedMin - step
    if left > 0 then
        d.vetPickedMin = left
        return
    end
    d.vetPickedMin = nil
    local blocked = d.vetCourseFlea ~= nil or CD.vetProtected(d, "vetFleaPrevUntilMin", CD.worldMinutes())
    for i = 1, #PICKED do
        local row = PICKED[i]
        local kind = CD.VET_INFEST_KINDS[row.name]
        if d[row.flag] ~= nil and not blocked and d[kind.field] == nil then
            d[kind.field] = CD.VET_INFEST_ACTIVE_MIN
            d[kind.pulse] = spanMin(CD.VET_INFEST_PULSE_MIN_MIN, CD.VET_INFEST_PULSE_MAX_MIN)
            CD.perfCount("vet.pickedback")
            vetLog("voltaram depois da pinca cao=%s tipo=%s", tostring(d.name), row.name)
            CD.notifyOwner(owner, kind.notify, subject(animal, d))
        end
        d[row.flag] = nil
    end
    CD.transmit(animal)
end

-- Cursos de tratamento -----------------------------------------------------------------------

-- O remedio nao cura no gole: abre um curso que corre em minutos e so no fim tira a doenca.
local COURSE_CURES = {
    {
        course = "vetCourseFlu", key = "vetflucured",
        clear = function(d)
            if d.vetFluMin == nil then return false end
            d.vetFluMin, d.vetFluQuiet, d.vetFluExpoMin, d.vetFluReliefMin = nil, nil, nil, nil
            return true
        end,
    },
    {
        course = "vetCourseWorms", key = "vetdewormed",
        clear = function(d)
            if d.vetWorms == nil then return false end
            d.vetWorms = nil
            return true
        end,
    },
    {
        course = "vetCourseHw", key = "vetheartwormcured",
        clear = function(d)
            if d.vetHwMin == nil then return false end
            d.vetHwMin, d.vetHwOutMin = nil, nil
            return true
        end,
    },
    {
        course = "vetCourseAlg", key = "vetallergycured",
        clear = function(d)
            if d.vetAlgMin == nil then return false end
            d.vetAlgMin, d.vetAlgParts, d.vetAlgSrc = nil, nil, nil
            return true
        end,
    },
    {
        course = "vetCourseFlea", key = "vetinfestcured",
        clear = function(d)
            if d.vetFleas == nil and d.vetTicks == nil and d.vetPickedMin == nil then return false end
            d.vetFleas, d.vetFleaPulseMin = nil, nil
            d.vetTicks, d.vetTickPulseMin = nil, nil
            d.vetPickedMin, d.vetPickedFleas, d.vetPickedTicks = nil, nil, nil
            return true
        end,
    },
}

local function courseTick(animal, owner, d, step)
    for i = 1, #COURSE_CURES do
        local row = COURSE_CURES[i]
        local left = d[row.course]
        if left ~= nil then
            left = left - step
            if left > 0 then
                d[row.course] = left
            else
                d[row.course] = nil
                if row.clear(d) then
                    CD.perfCount("vet.coursecure")
                    CD.notifyOwner(owner, row.key, subject(animal, d))
                end
                CD.transmit(animal)
            end
        end
    end
end

-- Ajuda de ferida e alivio da gripe duram um tanto de tempo com o cao no mundo, depois saem sozinhos.
local function aidTick(animal, d, step)
    local ended = false
    for i = 1, #CD.VET_AID_TIMERS do
        local field = CD.VET_AID_TIMERS[i]
        local left = d[field]
        if left ~= nil then
            left = left - step
            if left > 0 then
                d[field] = left
            else
                d[field] = nil
                ended = true
            end
        end
    end
    if ended then
        CD.transmit(animal)
    end
end

-- Uma rolagem por cao, na primeira passada dele: sai com uma familia de carne para a vida ou com
-- nenhuma. Cao de save antigo que ja tinha alergia sorteada a mantem.
local function drawAllergen(d)
    if d.vetAllergenDrawn ~= nil then return end
    d.vetAllergenDrawn = 1
    d.vetProteinSeen = nil
    if d.vetAllergen ~= nil then return end
    if not roll(CD.vetAllergyChance()) then return end
    local pool = CD.VET_ALLERGEN_POOL
    d.vetAllergen = pool[ZombRand(1, #pool + 1)]
end

-- A aba Saude mostra as horas que faltam, e o cliente de MP so ve o relogio andar quando o ModData
-- chega: manda de novo quando alguma hora mostrada vira.
local CLOCK_FIELDS = {
    "vetCourseFlu", "vetCourseHw", "vetCourseAlg", "vetCourseFlea", "vetCourseWorms",
    "vetAbxMin", "vetGarlicMin", "vetDewormMin", "vetInfectMin", "vetGastroMin", "vetFluMin", "vetHwMin",
    "vetAlgMin", "vetAidPlantain", "vetAidAloe", "vetAidComfrey", "vetBalanceMin", "vetPickedMin",
}

local function clockSync(animal, d)
    local hours = {}
    for i = 1, #CLOCK_FIELDS do
        local left = d[CLOCK_FIELDS[i]]
        hours[i] = left and math.ceil(left / 60) or 0
    end
    local sig = table.concat(hours, ",")
    if sig == d.vetClockSig then return end
    d.vetClockSig = sig
    CD.perfCount("vet.clocksync")
    CD.transmit(animal)
end

---One disease pass for one dog, at most every VET_TICK_INTERVAL_MIN; the minutes since the last pass are capped and count only while the dog was in play.
---@param animal IsoAnimal
---@param owner IsoPlayer|nil
---@param d table companion ModData
---@param now number world minutes
function CD.tickVetOne(animal, owner, d, now)
    local last = d.vetMin
    if last and (now - last) < CD.VET_TICK_INTERVAL_MIN then return end
    local step = 0
    if last and now > last then
        step = math.min(now - last, CD.UPKEEP_MAX_CATCHUP_MIN)
    end
    -- Mesma conta do upkeep, mesmo furo: cao descarregado volta com todo o vao aplicado de uma vez.
    -- Doenca nao anda em cao que nao estava no mundo.
    if step > 0 and not CD.wasInPlay(animal) then
        step = 0
    end
    d.vetMin = now
    CD.perfCount("vet.pass")
    drawAllergen(d)
    CD.vetApplyLimpVars(animal)
    if d.vetGastroMin == nil then
        d.vetGastroEased = nil
    end
    if not CD.isSick(animal) then
        d.vetToxicEased = nil
    end
    if step <= 0 then return end
    medsTick(animal, owner, d, step)
    if d.vetKind then
        infectionTick(animal, owner, d, step)
        if animal:getHealth() <= 0 then return end
        if d.vetKind then
            advance(animal, owner, d, step)
        end
    end
    gastroTick(animal, owner, d, step)
    dewormTick(animal, owner, d, step)
    courseTick(animal, owner, d, step)
    -- O envenenamento tem hora marcada para acabar; com o equilibrio geral ela chega antes.
    if d.vetBalanceMin ~= nil and CD.isSick(animal) then
        d.sickUntilMin = d.sickUntilMin - step * (CD.VET_BALANCE_RATE - 1)
    end
    aidTick(animal, d, step)
    fluTick(animal, owner, d, step, now)
    heartwormTick(animal, owner, d, step)
    if animal:getHealth() <= 0 then return end
    allergyTick(animal, owner, d, step)
    pickedTick(animal, owner, d, step)
    infestTick(animal, owner, d, step, "fleas")
    infestTick(animal, owner, d, step, "ticks")
    clockSync(animal, d)
end

---Runs the disease pass of every loaded companion that is due.
function CD.tickVet()
    if not CD.vetCareEnabled() then return end
    local now = CD.worldMinutes()
    CD.regEach(CD.regCompanions(), function(a)
        local d = CD.data(a)
        if d.vetMin and (now - d.vetMin) < CD.VET_TICK_INTERVAL_MIN then return end
        CD.tickVetOne(a, CD.getOwnerPlayer(a), d, now)
    end)
end

---Rolls the risks of a bite exchange: fleas or ticks, then a wound, or a fracture when already wounded.
---@param animal IsoAnimal
function CD.vetRollCombat(animal)
    if not CD.vetCareEnabled() then return end
    if not CD.isCompanion(animal) then return end
    local d = CD.data(animal)
    local owner = CD.getOwnerPlayer(animal)
    -- Pulga e carrapato pegam no corpo a corpo, com ferida ou sem: o cao rola no chao com o bicho.
    if roll(CD.vetInfestChance() * aggravation(animal, d)) then
        startInfest(animal, owner, d)
    end
    if d.vetBroken ~= nil or d.vetKind == "sprain" then return end
    local now = CD.worldMinutes()
    if onCooldown(d, now) then return end
    local chance = CD.vetWoundChance() * CD.combatWoundMult(animal) * aggravation(animal, d)
    if d.vetKind then
        -- Lutar em cima da ferida e o que quebra a pata: mesma rolagem, com o agravamento de ferida.
        if roll(chance * CD.VET_AGGR_WOUND) then
            fracture(animal, owner, d, now)
        end
        return
    end
    if roll(chance) then
        lesion(animal, owner, d, now, "combat")
    end
end

---The meat the dog cannot handle is drawn once per dog; from then on every meal of that family
---flares. Called from every food path: hand, bowl, trough and hunt.
---@param animal IsoAnimal
---@param group string|nil protein family of the meal
function CD.vetRollFoodAllergy(animal, group)
    if not CD.vetCareEnabled() or group == nil then return end
    if not CD.isCompanion(animal) then return end
    local d = CD.data(animal)
    if d.vetAllergen ~= group then return end
    -- A primeira crise e quando o dono descobre a carne; a aba Saude passa a mostrar para sempre.
    if startAllergy(animal, CD.getOwnerPlayer(animal), d, group, "vetallergen") and d.vetAllergenKnown == nil then
        d.vetAllergenKnown = 1
        CD.transmit(animal)
    end
end

---Rolls the sprain chance of a fence hop; a dog already hurt is not rolled.
---@param animal IsoAnimal
function CD.vetRollHop(animal)
    if not CD.vetCareEnabled() then return end
    if not CD.isCompanion(animal) then return end
    local d = CD.data(animal)
    if d.vetKind then return end
    local now = CD.worldMinutes()
    if onCooldown(d, now) then return end
    if roll(CD.vetSprainChance() * aggravation(animal, d)) then
        sprain(animal, CD.getOwnerPlayer(animal), d, now)
    end
end

---@param animal IsoAnimal
---@param owner IsoPlayer|nil
---@param d table companion ModData
---@param source string
---@return boolean started
function CD.vetStartGastro(animal, owner, d, source)
    if not CD.vetCareEnabled() then return false end
    local now = CD.worldMinutes()
    if CD.vetShielded(d, now) or d.vetGastroMin ~= nil then return false end
    d.vetGastroMin = ZombRand(CD.VET_GASTRO_MIN_MIN, CD.VET_GASTRO_MAX_MIN + 1)
    dropWork(animal, d)
    CD.perfCount("vet.gastro")
    vetLog("gastro cao=%s fonte=%s", tostring(d.name), source)
    CD.notifyOwner(owner, "vetgastro", subject(animal, d))
    d.vetWormsExpoMin = 0
    CD.transmit(animal)
    return true
end

---@param spoil string "rotten" or "stale"
function CD.vetRollSpoiledFood(animal, owner, spoil)
    if not CD.isCompanion(animal) then return end
    local chance = CD.vetSpoiledChance()
    if spoil == "rotten" then
        chance = CD.VET_GASTRO_ROTTEN_CHANCE
    end
    if roll(chance) then
        CD.vetStartGastro(animal, owner, CD.data(animal), spoil)
    end
end

---One sip of tainted water, be it from the bowl or from the bottle in hand. The cooldown is per dog,
---so refilling the bowl or taking one more sip right after does not stack rolls.
---@param animal IsoAnimal
---@param d table companion ModData
function CD.vetRollWater(animal, d)
    if not CD.vetCareEnabled() then return end
    local now = CD.worldMinutes()
    if d.vetWaterRollMin and (now - d.vetWaterRollMin) < CD.VET_WATER_ROLL_COOLDOWN_MIN then return end
    d.vetWaterRollMin = now
    if roll(CD.vetSpoiledChance()) then
        CD.vetStartGastro(animal, CD.getOwnerPlayer(animal), d, "water")
    end
end

---Water the game itself tainted (a bowl filled from a poisoned source): read only here, at the sip,
---never during the search.
---@param animal IsoAnimal
---@param d table companion ModData
---@param dishMd table ModData of the bowl item
function CD.vetRollDishWater(animal, d, dishMd)
    if dishMd.cdWaterTainted == nil then return end
    CD.vetRollWater(animal, d)
end

---@param animal IsoAnimal
---@param player IsoPlayer the owner doing the dressing
---@param sterile boolean alcohol bandage, or plain bandage plus a disinfectant
---@param dirty boolean a used bandage: holds the wound but infects more, never sterile
---@param dressType string full type that comes back when the dressing is removed
---@return boolean ok
---@return string|nil reason notify key when refused
function CD.vetApplyTreatment(animal, player, sterile, dirty, dressType)
    local d = CD.data(animal)
    if d.vetKind ~= "cut" then return false, "vetnothing" end
    if dirty then
        sterile = false
    end
    local want = sterile and 2 or 1
    if (d.vetDress or 0) >= want then return false, "vetalready" end
    returnDressing(player, d)
    d.vetDress = want
    d.vetDressItem = dressType
    if dirty then
        d.vetDressDirty = 1
    end
    CD.vetApplyLimpVars(animal)
    CD.setLoyalty(animal, math.min(CD.TRUST_MAX, CD.loyalty(animal) + CD.VET_TREAT_LOYALTY))
    CD.perfCount("vet.treat")
    vetLog("tratou cao=%s curativo=%d", tostring(d.name), want)
    local args = subject(animal, d)
    args.sterile = sterile
    CD.notifyOwner(player, "vettreated", args)
    CD.transmit(animal)
    return true
end

---@param animal IsoAnimal
---@param player IsoPlayer
---@return boolean ok
---@return string key notify key
function CD.vetRemoveDressing(animal, player)
    local d = CD.data(animal)
    if (d.vetDress or 0) == 0 then return false, "vetnothing" end
    returnDressing(player, d)
    d.vetDress = 0
    CD.vetApplyLimpVars(animal)
    CD.perfCount("vet.undress")
    vetLog("tirou curativo cao=%s", tostring(d.name))
    CD.transmit(animal)
    return true, "vetundressed"
end

-- Cuidar do cao da lealdade. XP so quando tratou doenca de verdade: dose preventiva em cao sao nao
-- ensina nada.
local function rewardCare(animal, player, treated)
    CD.setLoyalty(animal, math.min(CD.TRUST_MAX, CD.loyalty(animal) + CD.VET_TREAT_LOYALTY))
    if not (treated and player ~= nil) then return end
    local gain = CD.VET_FIRST_AID_XP_MIN
        + (CD.VET_FIRST_AID_XP_MAX - CD.VET_FIRST_AID_XP_MIN) * (ZombRand(0, 10001) / 10000)
    player:getXp():AddXP(Perks.Doctor, gain, false, false, false)
end

---Applies one dose. The item is classified by full type; the consume happens in the caller, after.
---@param animal IsoAnimal
---@param item InventoryItem|string the dose, or its full type
---@param player IsoPlayer|nil whose Doctor and Husbandry shorten the course and earn the XP
---@return boolean ok false means nothing was applied and the item must not be consumed
---@return string key notify key, for the refusal or for the effect
function CD.vetApplyMedicine(animal, item, player)
    local d = CD.data(animal)
    local ft = (type(item) == "string") and item or item:getFullType()
    local def, canonical = CD.vetMedicineDef(ft)
    if def == nil then return false, "vetnothing" end
    local now = CD.worldMinutes()
    local key = def.key
    local treated = true
    if def.id == "abx" or def.id == "humanabx" then
        local stage = 0
        if d.vetKind ~= nil then
            stage = d.vetStage or 0
        end
        if stage < 1 and d.vetFluMin == nil then return false, "vetnoinfection" end
        if d.vetAbxMin ~= nil then return false, "vetalready" end
        d.vetAbxMin = CD.VET_ABX_MIN
        -- O humano cura igual; o preco e a dose chutada, que as vezes vira o estomago.
        if def.id == "humanabx" and rollPct(CD.VET_HUMAN_ABX_GASTRO_PCT) then
            CD.vetStartGastro(animal, CD.getOwnerPlayer(animal), d, "humanabx")
        end
    elseif def.id == "dewormer" then
        if d.vetDewormMin ~= nil then return false, "vetalready" end
        d.vetDewormMin = CD.VET_DEWORM_MIN
        d.vetDewormPrevUntilMin = now + CD.VET_DEWORM_PREV_MIN * CD.vetPrevMult(player)
        treated = d.vetWorms ~= nil
    elseif def.id == "garlic" then
        if d.vetKind == nil or (d.vetStage or 0) < 1 then return false, "vetnoinfection" end
        if d.vetAbxMin ~= nil or d.vetGarlicMin ~= nil then return false, "vetalready" end
        d.vetGarlicMin = CD.VET_GARLIC_MIN
    elseif def.id == "tweezers" then
        if (d.vetFleas or 0) <= 0 and (d.vetTicks or 0) <= 0 then return false, "vetnoneed" end
        if d.vetFleas ~= nil then
            d.vetPickedFleas = 1
        end
        if d.vetTicks ~= nil then
            d.vetPickedTicks = 1
        end
        d.vetFleas, d.vetFleaPulseMin, d.vetTicks, d.vetTickPulseMin = nil, nil, nil, nil
        d.vetPickedMin = CD.VET_TWEEZERS_MIN
    else
        -- Remedio de tabela: abre o curso se a doenca esta la e carimba a janela de protecao.
        -- O portao e o MESMO que o menu usa. Sem ele, um remedio que o menu nunca ofereceria (o
        -- antialergico em cao sao) ainda assim gastava a dose e carimbava protecao, porque o bloco
        -- de protecao la embaixo vale para todo remedio que tenha janela, prophylactic ou nao.
        if not CD.vetMedicineApplies(animal, canonical) then return false, "vetnoneed" end
        local changed = false
        treated = false
        local courses = def.courses
        if courses ~= nil then
            for i = 1, #courses do
                local course = courses[i]
                if CD.vetCourseOpens(d, course) then
                    d[course.field] = math.max(1, course.min / CD.vetTreatMult(player))
                    if def.id == "vaccine" then
                        d.vetFluQuiet = 1
                    end
                    changed, treated = true, true
                end
            end
        end
        local prevent = def.prevent
        if prevent ~= nil then
            local untilMin = now + prevent.min * CD.vetPrevMult(player)
            if d[prevent.field] == nil or d[prevent.field] < untilMin then
                d[prevent.field] = untilMin
                changed = true
            end
        end
        local cuts = def.cuts
        if cuts ~= nil then
            -- O corte e na hora; a marca deixa a aba Saude mostrar o tratamento ate a doenca acabar.
            if cuts.gastro ~= nil and d.vetGastroMin ~= nil then
                d.vetGastroMin = d.vetGastroMin - cuts.gastro
                if d.vetGastroMin <= 0 then
                    d.vetGastroMin = nil
                    d.vetWormsExpoMin = nil
                else
                    d.vetGastroEased = 1
                end
                changed, treated = true, true
            end
            if cuts.toxic ~= nil and CD.isSick(animal) then
                d.sickUntilMin = d.sickUntilMin - cuts.toxic * CD.toxicSeverity(animal)
                d.vetToxicEased = 1
                changed, treated = true, true
            end
        end
        local stress = def.stress
        if stress ~= nil and (d.combatStress or 0) >= stress.min then
            CD.addCombatStress(animal, -stress.relief)
            changed = true
        end
        local aid = def.aid
        if aid ~= nil and d[aid.field] == nil and CD.vetAidFits(d, aid) then
            d[aid.field] = aid.min or 1
            changed, treated = true, true
        end
        local relief = def.relief
        if relief ~= nil and d.vetFluMin ~= nil and d[relief.field] == nil then
            d[relief.field] = relief.min
            changed, treated = true, true
        end
        local balance = def.balance
        if balance ~= nil and d[balance.field] == nil and CD.vetRecovering(animal, d) then
            d[balance.field] = balance.min
            changed, treated = true, true
        end
        if not changed then return false, "vetnoneed" end
    end
    rewardCare(animal, player, treated)
    CD.perfCount("vet.medicate")
    vetLog("remedio cao=%s item=%s -> %s", tostring(d.name), ft, key)
    CD.transmit(animal)
    return true, key
end

---A bath with one bath product. The water, the cloth and the dose are checked and spent by the caller.
---@param animal IsoAnimal
---@param def table one row of CD.VET_BATHS
---@param player IsoPlayer|nil whose skills stretch the protection and earn the XP
---@return boolean ok
---@return string key notify key, for the refusal or for the effect
function CD.vetApplyBath(animal, def, player)
    local d = CD.data(animal)
    local treated = false
    local key = def.key
    if def.infest then
        if d.vetFleas == nil and d.vetTicks == nil then return false, "vetnoneed" end
        d.vetFleas, d.vetFleaPulseMin, d.vetTicks, d.vetTickPulseMin = nil, nil, nil, nil
        d.vetCourseFlea, d.vetPickedMin, d.vetPickedFleas, d.vetPickedTicks = nil, nil, nil, nil
        local untilMin = CD.worldMinutes() + def.prevent.min * CD.vetPrevMult(player)
        if d[def.prevent.field] == nil or d[def.prevent.field] < untilMin then
            d[def.prevent.field] = untilMin
        end
        treated = true
    else
        local calmed = (d.combatStress or 0) >= def.stress.min
        if d.vetAlgMin == nil and not calmed then return false, "vetnoneed" end
        if d.vetAlgMin ~= nil and def.allergyCure then
            d.vetAlgMin, d.vetAlgParts, d.vetAlgSrc, d.vetCourseAlg = nil, nil, nil, nil
            CD.perfCount("vet.allergycured")
            treated = true
            key = "vetallergycured"
        end
        if calmed then
            CD.addCombatStress(animal, -def.stress.relief)
        end
    end
    rewardCare(animal, player, treated)
    CD.perfCount("vet.bath")
    vetLog("banho cao=%s produto=%s", tostring(d.name), def.id)
    CD.transmit(animal)
    return true, key
end

local function debugSetHealthFrac(animal, d, frac)
    animal:setIsInvincible(false)
    animal:setHealth(frac * (d.maxHealth or 1))
    animal:setIsInvincible(true)
end

local function debugNeedCut(animal, owner, d, now)
    if d.vetKind == "cut" then return end
    if d.vetKind ~= nil then
        heal(animal, owner, d)
    end
    lesion(animal, owner, d, now, "debug")
end

---Debug: forces one condition on the dog, chaining what it needs (a fever needs an infected cut).
---@param animal IsoAnimal
---@param id string one of CD.HEALTH_DEBUG_AILMENTS
---@return boolean known id
function CD.vetDebugApply(animal, id)
    local d = CD.data(animal)
    local owner = CD.getOwnerPlayer(animal)
    local now = CD.worldMinutes()
    if id == "cut" then
        if d.vetKind ~= nil then
            heal(animal, owner, d)
        end
        lesion(animal, owner, d, now, "debug")
    elseif id == "sprain" then
        if d.vetKind ~= nil then
            heal(animal, owner, d)
        end
        sprain(animal, owner, d, now)
    elseif id == "fracture" then
        debugNeedCut(animal, owner, d, now)
        if d.vetBroken == nil then
            fracture(animal, owner, d, now)
        end
    elseif id == "bleeding" then
        debugNeedCut(animal, owner, d, now)
        if (d.vetDress or 0) > 0 then
            CD.vetRemoveDressing(animal, owner)
        end
        d.vetBleedMin = 0
    elseif id == "infected" then
        debugNeedCut(animal, owner, d, now)
        if (d.vetStage or 0) < 1 then
            setStage(animal, owner, d, 1)
        end
    elseif id == "fever" then
        debugNeedCut(animal, owner, d, now)
        if (d.vetStage or 0) < 1 then
            setStage(animal, owner, d, 1)
        end
        if (d.vetStage or 0) < 2 then
            setStage(animal, owner, d, 2)
        end
    elseif id == "critical" then
        debugNeedCut(animal, owner, d, now)
        if (d.vetStage or 0) < 1 then
            setStage(animal, owner, d, 1)
        end
        debugSetHealthFrac(animal, d, CD.VET_CRIT_HEALTH_FRAC)
        setCritical(animal, owner, d, true)
    elseif id == "toxic" then
        d.sickUntilMin = now + CD.TOXIC_SICK_MIN * CD.toxicSeverity(animal)
    elseif id == "gastro" then
        CD.vetStartGastro(animal, owner, d, "debug")
    elseif id == "worms" then
        d.vetWorms = 1
        d.vetDewormMin = nil
        d.vetCourseWorms = nil
        CD.notifyOwner(owner, "vetworms", subject(animal, d))
    elseif id == "flu" then
        d.vetImmuneUntilMin, d.vetBoostUntilMin = nil, nil
        d.vetFluMin = nil
        d.vetCourseFlu = nil
        d.vetFluReliefMin = nil
        startFlu(animal, owner, d, "debug")
    elseif id == "heartworm" then
        d.vetHwPrevUntilMin = nil
        d.vetHwMin = nil
        d.vetCourseHw = nil
        startHeartworm(animal, owner, d, "debug")
    elseif id == "allergy" then
        d.vetAlgPrevUntilMin = nil
        d.vetAlgMin = nil
        d.vetCourseAlg = nil
        startAllergy(animal, owner, d, "debug")
    elseif id == "fleas" or id == "ticks" then
        local kind = CD.VET_INFEST_KINDS[id]
        d.vetFleaPrevUntilMin = nil
        d.vetCourseFlea, d.vetPickedMin, d.vetPickedFleas, d.vetPickedTicks = nil, nil, nil, nil
        d[kind.field] = CD.VET_INFEST_ACTIVE_MIN
        d[kind.pulse] = spanMin(CD.VET_INFEST_PULSE_MIN_MIN, CD.VET_INFEST_PULSE_MAX_MIN)
        CD.notifyOwner(owner, kind.notify, subject(animal, d))
    else
        return false
    end
    CD.vetApplyLimpVars(animal)
    CD.transmit(animal)
    return true
end

---Debug: clears one condition, leaving the rest as it is.
---@param animal IsoAnimal
---@param id string one of CD.HEALTH_DEBUG_AILMENTS
---@return boolean known id
function CD.vetDebugClear(animal, id)
    local d = CD.data(animal)
    local owner = CD.getOwnerPlayer(animal)
    if id == "cut" or id == "sprain" or id == "fracture" then
        if d.vetKind ~= nil then
            heal(animal, owner, d)
        end
    elseif id == "bleeding" then
        if d.vetKind == "cut" then
            d.vetBleedMin = CD.VET_BLEED_STOP_MIN
        end
    elseif id == "infected" then
        if (d.vetStage or 0) >= 1 then
            cureInfection(animal, owner, d)
        end
    elseif id == "fever" then
        if (d.vetStage or 0) >= 2 then
            setCritical(animal, owner, d, false)
            d.vetStage = 1
            d.vetStageMin = 0
        end
    elseif id == "critical" then
        if d.vetCrit ~= nil then
            debugSetHealthFrac(animal, d, 0.5)
            setCritical(animal, owner, d, false)
        end
    elseif id == "toxic" then
        d.sickUntilMin = nil
    elseif id == "gastro" then
        d.vetGastroMin = nil
        d.vetWormsExpoMin = nil
    elseif id == "worms" then
        d.vetWorms = nil
        d.vetCourseWorms = nil
    elseif id == "flu" then
        d.vetFluMin, d.vetFluQuiet, d.vetFluExpoMin, d.vetCourseFlu = nil, nil, nil, nil
        d.vetFluReliefMin = nil
    elseif id == "heartworm" then
        d.vetHwMin, d.vetHwOutMin, d.vetCourseHw = nil, nil, nil
    elseif id == "allergy" then
        d.vetAlgMin, d.vetAlgParts, d.vetAlgSrc, d.vetCourseAlg = nil, nil, nil, nil
    elseif id == "fleas" or id == "ticks" then
        local kind = CD.VET_INFEST_KINDS[id]
        d[kind.field], d[kind.pulse] = nil, nil
        if d.vetFleas == nil and d.vetTicks == nil then
            d.vetCourseFlea, d.vetPickedMin, d.vetPickedFleas, d.vetPickedTicks = nil, nil, nil, nil
        end
    else
        return false
    end
    CD.vetApplyLimpVars(animal)
    CD.transmit(animal)
    return true
end

---Debug: clears every wound, infection, sprain, fracture, gut, worm and poisoning, and fills health.
---@param animal IsoAnimal
---@param owner IsoPlayer|nil
function CD.vetClearAll(animal, owner)
    local d = CD.data(animal)
    if d.vetKind ~= nil then
        heal(animal, owner, d)
    end
    d.vetGastroMin = nil
    d.vetWorms = nil
    d.vetWormsExpoMin = nil
    d.vetDewormMin = nil
    d.vetDewormPrevUntilMin = nil
    d.vetAbxMin = nil
    d.vetWaterRollMin = nil
    d.vetLastHitMin = nil
    d.sickUntilMin = nil
    d.vetFluMin, d.vetFluQuiet, d.vetFluExpoMin, d.vetFluRollMin = nil, nil, nil, nil
    d.vetHwMin, d.vetHwOutMin = nil, nil
    d.vetAlgMin, d.vetAlgParts, d.vetAlgSrc = nil, nil, nil
    d.vetFleas, d.vetFleaPulseMin, d.vetTicks, d.vetTickPulseMin = nil, nil, nil, nil
    d.vetCourseFlu, d.vetCourseHw, d.vetCourseAlg, d.vetCourseFlea = nil, nil, nil, nil
    d.vetCourseWorms, d.vetFluReliefMin, d.vetGarlicMin = nil, nil, nil
    d.vetAidPlantain, d.vetAidAloe, d.vetAidComfrey, d.vetSplint = nil, nil, nil, nil
    d.vetPickedMin, d.vetPickedFleas, d.vetPickedTicks, d.vetBalanceMin = nil, nil, nil, nil
    d.vetGastroEased, d.vetToxicEased = nil, nil
    d.wounded = false
    d.woundedCritical = false
    releaseStay(animal, d)
    animal:setIsInvincible(false)
    animal:setHealth(d.maxHealth or 1)
    animal:setIsInvincible(true)
    CD.vetApplyLimpVars(animal)
    CD.transmit(animal)
end
