CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.isDisloyal(animal)
    return CD.isCompanion(animal) and CD.loyalty(animal) < CD.effectiveLoyaltyFloor(animal)
end

---Low health as flagged by the upkeep, with hysteresis; vet wounds are separate.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.isWounded(animal)
    return CD.data(animal).wounded == true
end

---Food poisoning: true until sickUntilMin, in world minutes.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.isSick(animal)
    local u = CD.data(animal).sickUntilMin
    return u ~= nil and CD.worldMinutes() < u
end

---Health under the critical threshold, as flagged by the upkeep.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.isWoundedCritical(animal)
    return CD.data(animal).woundedCritical == true
end

---Protein debt reached its limit; always false with the protein need off.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.isWeak(animal)
    if not CD.proteinNeedEnabled() then return false end
    return CD.data(animal).weak == true
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return string|nil kind "cut" for an open wound, "sprain" for a sprained paw; nil when healthy or vet care is off
---@return number|nil stage 0 = clean, 1 = infected, 2 = infected with fever
---@nodiscard
function CD.vetCondition(animal)
    if not CD.vetCareEnabled() then return nil end
    local d = CD.data(animal)
    if d.vetKind == nil then return nil end
    return d.vetKind, d.vetStage or 0
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.vetInfected(animal)
    local _, stage = CD.vetCondition(animal)
    return stage ~= nil and stage >= 1
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.vetBroken(animal)
    return CD.vetCondition(animal) ~= nil and CD.data(animal).vetBroken ~= nil
end

-- Critico e estado de vida, nao estagio: infeccao com a vida abaixo de um decimo. Flag carimbado pelo tick.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.vetCritical(animal)
    return CD.vetInfected(animal) and CD.data(animal).vetCrit ~= nil
end

-- Ferida sem curativo: sangra devagar e nao recupera vida ate ser enfaixada.
---An undressed cut bleeds for VET_BLEED_STOP_MIN and then clots on its own; a dressing stops it at once.
function CD.vetBleeding(animal)
    if CD.vetCondition(animal) ~= "cut" then return false end
    local d = CD.data(animal)
    return (d.vetDress or 0) == 0 and (d.vetBleedMin or 0) < CD.VET_BLEED_STOP_MIN
end

---A prophylactic window is open: while it lasts, that condition cannot take hold.
---@param animal IsoAnimal
---@param field string the ModData field holding the absolute world minute the window closes
---@return boolean
---@nodiscard
function CD.vetPrevented(animal, field)
    return CD.vetCareEnabled() and CD.vetProtected(CD.data(animal), field, CD.worldMinutes())
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.vetGastro(animal)
    return CD.vetCareEnabled() and CD.data(animal).vetGastroMin ~= nil
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.vetWorms(animal)
    return CD.vetCareEnabled() and CD.data(animal).vetWorms ~= nil
end

---Vaccine immunity only; the herbal boost does not count.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.vetImmune(animal)
    return CD.vetCareEnabled() and CD.vetImmuneFrom(CD.data(animal), CD.worldMinutes())
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.vetFlu(animal)
    return CD.vetCareEnabled() and CD.data(animal).vetFluMin ~= nil
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.vetHeartworm(animal)
    return CD.vetCareEnabled() and CD.data(animal).vetHwMin ~= nil
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.vetAllergy(animal)
    return CD.vetCareEnabled() and CD.data(animal).vetAlgMin ~= nil
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.vetFleas(animal)
    return CD.vetCareEnabled() and CD.data(animal).vetFleas ~= nil
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.vetTicks(animal)
    return CD.vetCareEnabled() and CD.data(animal).vetTicks ~= nil
end

---Fever of any origin: infected wound at stage 2, flu or heartworm disease.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.vetFever(animal)
    return CD.vetCareEnabled() and CD.vetFeverFrom(CD.data(animal))
end

---Lame (fracture or critical stage) or sick with heartworm.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.vetRefusesFight(animal)
    return CD.vetLame(CD.data(animal)) or CD.vetHeartworm(animal)
end

---Poisoning, infection, bleeding, gastroenteritis, flu, heartworm or worms.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.blocksRegen(animal)
    return CD.isSick(animal) or CD.vetInfected(animal) or CD.vetBleeding(animal) or CD.vetGastro(animal)
        or CD.vetFlu(animal) or CD.vetHeartworm(animal) or CD.vetWorms(animal)
end

---Poisoning, infection, gastroenteritis, flu or heartworm.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.blocksBreeding(animal)
    return CD.isSick(animal) or CD.vetInfected(animal) or CD.vetGastro(animal)
        or CD.vetFlu(animal) or CD.vetHeartworm(animal)
end

---Poisoning, fever or allergy.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.suppressesBreedMoodle(animal)
    return CD.isSick(animal) or CD.vetFever(animal) or CD.vetAllergy(animal)
end

---Poisoning, gastroenteritis or fever pause the breed's passive effect.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.blocksBreedPassive(animal)
    return CD.isSick(animal) or CD.vetGastro(animal) or CD.vetFever(animal)
end

---Poisoning or gastroenteritis: a meal restores no health.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.blocksFeedBonus(animal)
    return CD.isSick(animal) or CD.vetGastro(animal)
end

---Any wound, gastroenteritis, flu or heartworm.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.vetRefusesWork(animal)
    return CD.vetCondition(animal) ~= nil or CD.vetGastro(animal)
        or CD.vetFlu(animal) or CD.vetHeartworm(animal)
end

-- Entrar e imediato; sair depende do flag que o upkeep baixa so abaixo do limiar menos a histerese.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.isPanicked(animal)
    if CD.data(animal).panicked == true then return true end
    return CD.getStress(animal) >= CD.breedPanicThreshold(animal)
end

---Pays off protein debt, and clears weak once the debt drops under the limit.
---@param d table|nil companion ModData; anything but a table is ignored
---@param points number|nil protein points eaten, CD.PROTEIN_MEAL_POINTS making a full meal; nil counts as a full meal
function CD.markProteinMeal(d, points)
    if type(d) ~= "table" then return end
    local full = CD.proteinMaxMinutes()
    local per = CD.PROTEIN_MEAL_POINTS
    local frac = 1
    if points ~= nil then
        if per <= 0 then return end
        frac = points / per
        if frac > 1 then
            frac = 1
        end
    end
    if frac <= 0 then return end
    local debt = (d.meatDebtMin or 0) - full * frac
    if debt < 0 then
        debt = 0
    end
    d.meatDebtMin = debt
    if debt < full then
        d.weak = nil
    end
end

---Hunger reduction of a protein food, times 100 and rounded; 0 when the breed does not count it as protein.
---@param item InventoryItem
---@param breedKey string|nil breed whose diet decides; nil uses the base diet
---@return integer
---@nodiscard
function CD.proteinPoints(item, breedKey)
    if not CD.isProteinFood(item, breedKey) then return 0 end
    local hc = item:getHungerChange()
    return math.floor(math.abs(hc) * 100 + 0.5)
end

---@param animal IsoAnimal
---@return string|nil reason "disloyal", "panicked", "wounded", "critical", "sick", "lame" or "bleeding"; nil when nothing blocks
---@nodiscard
function CD.refusalReason(animal)
    if CD.isDisloyal(animal) then return "disloyal" end
    if CD.isPanicked(animal) then return "panicked" end
    if CD.isWoundedCritical(animal) then return "wounded" end
    if CD.vetCritical(animal) then return "critical" end
    if CD.vetHeartworm(animal) then return "sick" end
    if CD.vetRefusesFight(animal) then return "lame" end
    if CD.vetGastro(animal) and not CD.vetCondition(animal) then return "sick" end
    if CD.vetRefusesWork(animal) then return "bleeding" end
    return nil
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return integer tier 0 calm, 1 nervous, 2 panicked, 3 terrified
---@nodiscard
function CD.panicTier(animal)
    local s = CD.getStress(animal)
    if s >= CD.PANIC_TIER3_FRAC then return 3
    elseif CD.isPanicked(animal) then return 2
    elseif s >= CD.PANIC_TIER1_FRAC then return 1 end
    return 0
end

---The most urgent condition, for the label next to the dog's name.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return table|nil badge { key, r, g, b }; nil when there is nothing to show
---@nodiscard
function CD.statusBadge(animal)
    if CD.vetCritical(animal) then
        return { key = "IGUI_PD_StatusCritical", r = 0.70, g = 0.12, b = 0.30 }
    end
    if CD.isWoundedCritical(animal) then
        return { key = "IGUI_PD_StatusWoundedCritical", r = 0.90, g = 0.30, b = 0.26 }
    end
    if CD.vetFever(animal) then
        return { key = "IGUI_PD_StatusFever", r = 0.85, g = 0.40, b = 0.55 }
    end
    if CD.vetInfected(animal) then
        return { key = "IGUI_PD_StatusInfected", r = 0.78, g = 0.32, b = 0.62 }
    end
    local tier = CD.panicTier(animal)
    if tier >= 3 then
        return { key = "IGUI_PD_StatusTerrified", r = 0.92, g = 0.22, b = 0.18 }
    end
    if tier >= 2 then
        return { key = "IGUI_PD_StatusPanicked", r = 0.95, g = 0.45, b = 0.20 }
    end
    if CD.isDisloyal(animal) then
        return { key = "IGUI_PD_StatusDisloyal", r = 0.95, g = 0.80, b = 0.25 }
    end
    if CD.vetBroken(animal) then
        return { key = "IGUI_PD_StatusFractured", r = 0.90, g = 0.45, b = 0.18 }
    end
    if CD.vetCondition(animal) == "sprain" then
        return { key = "IGUI_PD_StatusSprained", r = 0.90, g = 0.60, b = 0.30 }
    end
    if CD.vetCondition(animal) then
        if (CD.data(animal).vetDress or 0) >= 1 then
            return { key = "IGUI_PD_StatusHurt", r = 0.90, g = 0.55, b = 0.25 }
        end
        return { key = "IGUI_PD_StatusBleeding", r = 0.90, g = 0.22, b = 0.22 }
    end
    if CD.vetGastro(animal) then
        return { key = "IGUI_PD_StatusSick", r = 0.60, g = 0.70, b = 0.30 }
    end
    if CD.vetAllergy(animal) then
        return { key = "IGUI_PD_StatusAllergy", r = 0.88, g = 0.45, b = 0.62 }
    end
    if CD.vetTicks(animal) then
        return { key = "IGUI_PD_StatusTicks", r = 0.58, g = 0.42, b = 0.26 }
    end
    if CD.vetFleas(animal) then
        return { key = "IGUI_PD_StatusFleas", r = 0.66, g = 0.56, b = 0.34 }
    end
    if CD.isWounded(animal) then
        return { key = "IGUI_PD_StatusWounded", r = 0.94, g = 0.66, b = 0.24 }
    end
    if tier >= 1 then
        return { key = "IGUI_PD_StatusNervous", r = 0.95, g = 0.85, b = 0.30 }
    end
    return nil
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.alertModeLocked(animal)
    return CD.breedFlag(animal, "alertModeLocked")
end

---@param animal IsoAnimal
---@return string mode "full", "quiet" or "silent"; always "full" when the breed locks it
---@nodiscard
function CD.getAlertMode(animal)
    if CD.alertModeLocked(animal) then return "full" end
    local d = CD.data(animal)
    if d.alertMode == "full" or d.alertMode == "quiet" or d.alertMode == "silent" then
        return d.alertMode
    end
    if d.alertSilent == true then return "silent" end
    return "full"
end

---Ignored when the breed locks the alert mode.
---@param animal IsoAnimal
---@param mode string "full", "quiet" or "silent"; anything else is ignored
function CD.setAlertMode(animal, mode)
    if mode ~= "full" and mode ~= "quiet" and mode ~= "silent" then return end
    if CD.alertModeLocked(animal) then return end
    local d = CD.data(animal)
    d.alertMode = mode
    d.alertSilent = (mode == "silent")
end

---@param animal IsoAnimal
---@param silent boolean true sets "silent", false sets "full"
function CD.setSentinelSilent(animal, silent)
    CD.setAlertMode(animal, silent and "silent" or "full")
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.getAutoProtect(animal)
    return CD.data(animal).autoProtect == true
end

---@param animal IsoAnimal
---@param on boolean
function CD.setAutoProtect(animal, on)
    CD.data(animal).autoProtect = (on == true) or nil
end

---Rounds to CD.FOLLOW_KEEP_STEP and clamps to CD.FOLLOW_KEEP_MIN..CD.FOLLOW_KEEP_MAX.
---@param v number|nil
---@return number|nil keep nil when v is not a number
---@nodiscard
function CD.snapFollowKeep(v)
    if type(v) ~= "number" then return nil end
    local lo, hi = CD.FOLLOW_KEEP_MIN, CD.FOLLOW_KEEP_MAX
    local step = CD.FOLLOW_KEEP_STEP
    v = math.floor(v / step + 0.5) * step
    if v < lo then v = lo elseif v > hi then v = hi end
    return v
end

-- Variantes From(d): quem ja tem o getModData na mao (todo o caminho quente do follow tem) le por elas. A
-- versao que recebe o animal refaz o getModData, e num servidor cheio isso e milhares de chamadas por segundo
-- so pra reler um campo que o chamador ja segurava.
---@param d table|nil companion ModData
---@return number keep follow distance in tiles
---@nodiscard
function CD.followKeepFrom(d)
    local v = CD.snapFollowKeep(d and d.followKeep)
    return v or CD.FOLLOW_START_DIST
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return number keep follow distance in tiles
---@nodiscard
function CD.followKeep(animal)
    return CD.followKeepFrom(CD.data(animal))
end

---Stores the snapped distance; the default distance is stored as nil.
---@param animal IsoAnimal
---@param v number|nil tiles; nil is ignored
function CD.setFollowKeep(animal, v)
    v = CD.snapFollowKeep(v)
    if not v then return end
    CD.data(animal).followKeep = (v ~= CD.FOLLOW_START_DIST) and v or nil
end

---Gap, in tiles, past which the dog runs: CD.FOLLOW_RUN_DIST or the keep distance plus 2, whichever is larger.
---@param d table companion ModData
---@return number
---@nodiscard
function CD.followRunFrom(d)
    local run = CD.FOLLOW_RUN_DIST
    local keep = CD.followKeepFrom(d) + 2
    if keep > run then return keep end
    return run
end

---Gap, in tiles, at which straight-line follow steering engages: the keep distance plus a fixed margin.
---@param d table companion ModData
---@return number
---@nodiscard
function CD.followSteerArmFrom(d)
    return CD.followKeepFrom(d) + (CD.FOLLOW_STEER_ARM_DIST - CD.FOLLOW_START_DIST)
end

---Always false for breeds that cannot hunt.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.getHuntMode(animal)
    if not CD.breedCanHunt(animal) then return false end
    return CD.data(animal).huntMode == true
end

---Turning it on is ignored for breeds that cannot hunt.
---@param animal IsoAnimal
---@param on boolean
function CD.setHuntMode(animal, on)
    if on and not CD.breedCanHunt(animal) then return end
    CD.data(animal).huntMode = (on == true) or nil
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.getCareMode(animal)
    return CD.data(animal).careMode == true
end

---@param d table companion data record
function CD.clearCareFields(d)
    d.careMode = nil
    d.careX, d.careY, d.careZ = nil, nil, nil
    d.careGoalTx, d.careGoalTy = nil, nil
    d.careBackTx, d.careBackTy = nil, nil
    d.careHop, d.careHopTx, d.careHopTy = nil, nil, nil
    d.carePatrolTx, d.carePatrolTy, d.carePatrolMin = nil, nil, nil
    d.lastCareCalmMin, d.lastCareAlertMin = nil, nil
    d.careHold, d.careWantTx, d.careWantTy = nil, nil, nil
    d.careReassertMs, d.careReassertN, d.careBackoffMs, d.careHijacks = nil, nil, nil, nil
    d.combatHold, d.combatHijacks = nil, nil
end

---On anchors the care spot and drops alert, combat, hunt, forage, feeding, recall and attack state; off clears every care field.
---@param animal IsoAnimal
---@param on boolean
---@param x number|nil care spot; nil keeps the stored one
---@param y number|nil required when x is given
---@param z number|nil defaults to 0
function CD.setCareMode(animal, on, x, y, z)
    local d = CD.data(animal)
    if on == true then
        d.careMode = true
        if x then
            d.careX, d.careY, d.careZ = math.floor(x), math.floor(y), math.floor(z or 0)
        end
        d.alertTier = nil
        d.inCombat, d.retreating = nil, nil
        d.autoFeeding, d.autoFeedKind = nil, nil
        d.hunting, d.huntTargetId, d.huntGoingSinceMin = nil, nil, nil
        d.forageGoingSinceMin = nil
        d.recallUntilMin, d.attackUntilMin, d.attackArmed = nil, nil, nil
    else
        CD.clearCareFields(d)
    end
end

---On the server sends the command to the owner's client, stamping args.__to; elsewhere runs CD.clientNotify locally.
---@param owner IsoPlayer|nil
---@param command string
---@param args table|nil
function CD.notifyOwner(owner, command, args)
    if not owner then return end
    if isServer() then
        -- O pacote do servidor pro client e roteado por CONEXAO e nao carrega indice de jogador: na
        -- tela dividida os dois locais recebem o mesmo evento. A autoria tem que viajar no corpo.
        args = args or {}
        args.__to = owner:getUsername()
        sendServerCommand(owner, CD.MODULE, command, args)
    elseif CD.clientNotify then
        CD.clientNotify(command, args, owner)
    end
end

---Counts the kill on the dog and on its owner's zombie kill stat.
---@param animal IsoAnimal
function CD.recordDogZombieKill(animal)
    local d = CD.data(animal)
    d.zombieKills = (d.zombieKills or 0) + 1
    if not CD.countDogKillsForPlayer() then return end
    local owner = CD.getOwnerPlayer(animal)
    if not owner then return end
    if isServer() then
        local me = getPlayer()
        if not (me and owner:getUsername() == me:getUsername()) then
            owner:setZombieKills(owner:getZombieKills() + 1)
        end
    end
    CD.notifyOwner(owner, "dogzombiekill", {})
end
