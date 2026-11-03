CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function worldMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

local function promoteSuccessor(owner, dead)
    if not owner then return end
    local pd = CD.playerData(owner)
    if pd.token ~= nil or pd.dismissed then return end
    local ox, oy = owner:getX(), owner:getY()
    local best, bestD = nil, nil
    local ownKeyed, ownNamed = CD.regCompanionsOf(owner)
    for pass = 1, 2 do
        CD.regEach((pass == 1) and ownKeyed or ownNamed, function(a)
            if a ~= dead and CD.isOwnedBy(a, owner) and CD.data(a).companionToken ~= nil then
                local dx, dy = a:getX() - ox, a:getY() - oy
                local dd = dx * dx + dy * dy
                if not bestD or dd < bestD then
                    best, bestD = a, dd
                end
            end
        end)
    end
    if not best then return end
    local d = CD.data(best)
    CD.setActiveDog(pd, d.companionToken, d.name)
    pd.companions = pd.companions or {}
    pd.companions[d.companionToken] = true
    CD.setState(best, CD.STATE_FOLLOW)
    d.lastUpkeepMin = nil
    d.standDown = true
    if not CD.isDisloyal(best) then
        d.recallUntilMin = worldMinutes() + CD.RECALL_OVERRIDE_MIN
        CD.letMove(best)
        CD.pathStatEmit(best, "recall")
        best:pathToCharacter(owner)
        CD.forcePathfind(best)
    end
    CD.transmit(best)
    owner:transmitModData()
    CD.notifyOwner(owner, "selected", { id = best:getOnlineID(), name = d.name, breed = CD.getBreed(best) })
end
CD.promoteSuccessor = promoteSuccessor

local function clearCompanionSlot(owner, token, name, breed, animal)
    if animal then
        CD.spillBag(animal)
    end
    if not owner then return end
    local pd = CD.playerData(owner)
    local griefLoyalty
    if animal then
        griefLoyalty = CD.loyalty(animal)
    elseif token ~= nil and type(pd.kennel) == "table" and type(pd.kennel[token]) == "table" then
        griefLoyalty = pd.kennel[token].trust
    end
    if token ~= nil and token == pd.token then
        pd.token = nil
        pd.name = nil
    end
    if token ~= nil then
        if type(pd.companions) == "table" then
            pd.companions[token] = nil
        end
        if type(pd.tokenAnchor) == "table" then
            pd.tokenAnchor[token] = nil
        end
        CD.clearKennel(owner, token)
        local lp = CD.phantomLostSince[CD.ownerKey(owner)]
        if lp then
            lp[token] = nil
        end
    end
    local shock, mins = CD.griefFor(griefLoyalty or 0)
    CD.startGrief(owner, shock, mins, name)
    owner:transmitModData()
    CD.notifyOwner(owner, "died", { name = name, breed = breed })
    promoteSuccessor(owner, animal)
end
CD.clearCompanionSlot = clearCompanionSlot

local function permadeath(animal, owner, d)
    if d.diedNotified then return end
    d.diedNotified = true
    clearCompanionSlot(owner, d.companionToken, d.name, CD.getBreed(animal), animal)
    CD.reapDogState(animal:getOnlineID())
    -- Antes do Kill: ele poe o proprio cao como atacante, e a invencibilidade cai na linha de baixo.
    CD.logCompanionDeath(animal, "upkeep")
    animal:setIsInvincible(false)
    animal:setInvulnerable(false)
    CD.releaseFallFlag(animal)
    animal:Kill(animal)
end

local function updateUpkeep(animal, owner, d)
    local now = worldMinutes()
    local last = d.lastUpkeepMin
    if last and (now - last) < CD.UPKEEP_INTERVAL_MIN then return end
    local elapsedMin = (last and now > last) and (now - last) or 0
    d.lastUpkeepMin = now
    elapsedMin = CD.applyOfflineDebt(owner, elapsedMin)
    -- Cao que nao estava carregado na passada anterior acabou de voltar ao mundo, e o vao ai e tempo
    -- em que ele nem existia. Zera em vez de sair fora: assim caem os blocos de tempo (fome, sede,
    -- dreno, regeneracao, lealdade, proteina) e o resto da funcao segue normal, recalculando
    -- estresse, ferimento e aviso. O carimbo ja foi refeito na linha de cima.
    if elapsedMin > 0 and not CD.wasInPlay(animal) then
        elapsedMin = 0
    end

    local hunger = CD.getHunger(animal)
    local thirst = animal:getThirst()
    local health = animal:getHealth()

    local frozen = d.careMode == true

    if elapsedMin > 0 and not frozen then
        local step = math.min(elapsedMin, CD.UPKEEP_MAX_CATCHUP_MIN)
        local dDay = step / 1440
        local hm, tm = CD.vetNeedMult(d)
        hunger = math.min(1, hunger + CD.hungerPerDay() * dDay * hm)
        thirst = math.min(1, thirst + CD.thirstPerDay() * dDay * tm)
        CD.setNeed(animal, "hunger", hunger)
        CD.setNeed(animal, "thirst", thirst)
        -- Reducao de setHealth e bloqueada enquanto invencivel: desliga pra exatamente estes dois statements
        -- adjacentes, sem update da engine entre os bytecodes de Lua, entao nao abre janela de roadkill.
        local severe = CD.SEVERE_NEED
        if hunger > severe or thirst > severe then
            local drain = CD.NEGLECT_HEALTH_LOSS_PER_DAY * dDay
            -- Com a morte desligada no sandbox a negligencia tambem para no piso, como toda doenca.
            local floor = 0
            if not CD.deathEnabled() then
                floor = CD.VET_SAFE_HEALTH_FLOOR * (d.maxHealth or 1)
            end
            if drain > 0 and health > floor then
                local nh = math.max(floor, health - drain)
                animal:setIsInvincible(false)
                animal:setHealth(nh)
                animal:setIsInvincible(true)
                health = nh
            end
        end
    end

    if health <= 0 then
        permadeath(animal, owner, d)
        return
    end

    if elapsedMin > 0 and CD.isSick(animal) and not frozen then
        local base = d.maxHealth or 1
        if base <= 0 then
            base = 1
        end
        local floor = CD.TOXIC_SICK_HEALTH_FLOOR * base
        if health > floor then
            local nh = health - CD.TOXIC_SICK_DRAIN_PER_DAY * (elapsedMin / 1440)
            if nh < floor then
                nh = floor
            end
            animal:setIsInvincible(false)
            animal:setHealth(nh)
            animal:setIsInvincible(true)
            health = nh
        end
    end

    if d.maxHealth and health > d.maxHealth then
        d.maxHealth = health
    end

    if elapsedMin > 0 and CD.healthRegenPerDay() > 0 and not d.inCombat and not CD.blocksRegen(animal) then
        local needMax = CD.healthRegenNeedMax()
        local care = 1
        if needMax > 0 then
            care = math.min(1 - hunger / needMax, 1 - thirst / needMax)
        end
        if care < 0 then care = 0 elseif care > 1 then care = 1 end
        local base = d.maxHealth or 1
        if base <= 0 then
            base = 1
        end
        if care > 0 and health < base then
            local regen = CD.healthRegenPerDay()
            if owner and owner:isAsleep() then
                regen = regen * CD.VET_SLEEP_REGEN_MULT
            end
            local nh = math.min(base, health + regen * (elapsedMin / 1440) * care)
            animal:setHealth(nh)
            health = nh
        end
    end

    if elapsedMin > 0 and not d.inCombat and CD.combatStressRecoveryPerDay() > 0 then
        CD.addCombatStress(animal, -CD.combatStressRecoveryPerDay() * (elapsedMin / 1440))
    end

    if elapsedMin > 0 and not frozen then
        -- o "or 1" e obrigatorio: sem ele o cao BEM ALIMENTADO cai no ramo falso, neglect vira
        -- booleano e a multiplicacao da linha seguinte estoura com __mul not defined for operands
        local neglect = (hunger > CD.HUNGER_WARN or thirst > CD.THIRST_WARN) and CD.NEGLECT_MULT or 1
        local dec = CD.loyaltyDecayPerDay() * (elapsedMin / 1440) * neglect * CD.breedNumber(animal, "loyaltyDecayMult")
        if dec > 0 then
            CD.setLoyalty(animal, CD.loyalty(animal) - dec)
        end
    end

    local loyaltyDeficit = 1 - (CD.loyalty(animal) / CD.TRUST_MAX)
    local needsStress = (CD.STRESS_W_HUNGER * hunger
        + CD.STRESS_W_THIRST * thirst
        + CD.STRESS_W_HEALTH * (1 - health)
        + CD.STRESS_W_LOYALTY * loyaltyDeficit) * CD.stressGeneMult(animal)
    needsStress = needsStress + CD.upkeepStressDelta(animal, needsStress)
    CD.setStress(animal, needsStress)
    animal:setDebugStress(0)
    local stress = CD.getStress(animal)

    local panicAt = CD.breedPanicThreshold(animal)
    if panicAt == math.huge then
        d.panicked = nil
    elseif stress >= panicAt then
        d.panicked = true
    elseif d.panicked and stress <= panicAt - CD.PANIC_HYST then
        d.panicked = nil
    end

    if CD.stressBarkEnabled()
        and stress >= CD.STRESS_BARK_THRESHOLD
        and CD.getAlertMode(animal) == "full"
        and (not d.lastStressBarkMin or (now - d.lastStressBarkMin) >= CD.STRESS_BARK_COOLDOWN_MIN) then
        d.lastStressBarkMin = now
        CD.bark(animal)
        if CD.stressAttractsZombies() then
            addSound(animal, math.floor(animal:getX()), math.floor(animal:getY()), math.floor(animal:getZ()),
                CD.STRESS_BARK_RADIUS, CD.STRESS_BARK_VOLUME)
        end
    end

    if CD.woundedEnabled() then
        local base = d.maxHealth or 1
        if base <= 0 then
            base = 1
        end
        local frac = health / base

        local wasHurt = d.wounded == true
        local wasCrit = d.woundedCritical == true

        local crit = wasCrit
        if not crit and frac <= CD.criticalEnterFrac() then crit = true
        elseif crit and frac >= CD.criticalExitFrac() then crit = false end

        local hurt = wasHurt
        if not hurt and frac <= CD.woundedEnterFrac() then hurt = true
        elseif hurt and frac >= CD.woundedExitFrac() then hurt = false end
        if crit then
            hurt = true
        end

        d.woundedCritical = crit
        d.wounded = hurt

        if crit and not wasCrit then
            CD.notifyOwner(owner, "woundedcritical", { name = d.name, breed = CD.getBreed(animal) })
        elseif hurt and not wasHurt and not crit then
            CD.notifyOwner(owner, "wounded", { name = d.name, breed = CD.getBreed(animal) })
        elseif not hurt and wasHurt then
            CD.notifyOwner(owner, "recovered", { name = d.name, breed = CD.getBreed(animal) })
        end
    else
        d.wounded = false
        d.woundedCritical = false
    end

    if d.sickUntilMin and now >= d.sickUntilMin then
        d.sickUntilMin = nil
    end

    local wasWeak = d.weak == true
    if CD.proteinNeedEnabled() then
        if elapsedMin > 0 and not frozen then
            d.meatDebtMin = (d.meatDebtMin or 0) + elapsedMin
        end
        d.weak = (d.meatDebtMin or 0) >= CD.proteinMaxMinutes()
        if d.weak and not wasWeak then
            CD.notifyOwner(owner, "weak", { name = d.name, breed = CD.getBreed(animal) })
        end
    elseif d.weak then
        d.weak = nil
    end

    local warnKind
    if CD.isDisloyal(animal) then warnKind = "disloyal"
    elseif hunger > CD.HUNGER_WARN then warnKind = "hungry"
    elseif thirst > CD.THIRST_WARN then warnKind = "thirsty" end
    if warnKind ~= d.lastWarn then
        d.lastWarn = warnKind
        if warnKind then
            CD.notifyOwner(owner, "warn", { kind = warnKind, breed = CD.getBreed(animal) })
        end
    end

    local sig = string.format("%d|%.2f|%.2f|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s",
        math.floor(CD.loyalty(animal) + 0.5), stress, d.combatStress or 0,
        tostring(d.sickUntilMin ~= nil), tostring(d.wounded), tostring(d.woundedCritical),
        tostring(d.weak), tostring(d.panicked),
        tostring(d.vetKind), tostring(d.vetStage), tostring(d.vetDress), tostring(d.vetBroken), tostring(CD.vetBleeding(animal)),
        tostring(d.vetGastroMin ~= nil), tostring(d.vetWorms), tostring(d.vetImmuneUntilMin), tostring(d.vetCrit))
    if sig ~= d.upkeepSig then
        d.upkeepSig = sig
        CD.transmit(animal)
    end
end
CD.updateUpkeep = updateUpkeep
