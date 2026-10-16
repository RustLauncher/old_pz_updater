require "ISUI/ISUIElement"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---@type table
CD.DogMoodles = CD.DogMoodles or {}
-- Alias neutro de especie do contrato de addon a tabela é a mesma.
CD.CompanionMoodles = CD.DogMoodles

local function dogIsCaredFor(dog)
    local h, t = 0, 0
    if dog then
        h = CD.getHunger(dog)
        t = dog:getThirst()
    end
    return h < CD.MOODLE_NEGLECT_MAX and t < CD.MOODLE_NEGLECT_MAX
end

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "breedHappy",
    breed = "caramelo",
    nameKey = "IGUI_PD_Moodle_BreedHappy",
    descKey = "IGUI_PD_Moodle_BreedHappy_desc",
    icon = "CD_Moodle_BreedHappy",
    fg = "CD_MoodHappyFG",
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        if CD.getBreed(dog) ~= "caramelo" then return 0 end
        if CD.isDisloyal(dog) then return 0 end
        if not dogIsCaredFor(dog) then return 0 end
        return 1
    end,
    apply = function(player, dog, elapsedMin)
        CD.relieveMood(player, CD.moodleReliefPerMin() * elapsedMin)
    end,
}

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "courage",
    breed = "germanshepherd",
    nameKey = "IGUI_PD_Moodle_GSCourage",
    descKey = "IGUI_PD_Moodle_GSCourage_desc",
    icon = "CD_Moodle_GSCourage",
    fg = "CD_MoodCourageFG",
    tintR = 0.93, tintG = 0.70, tintB = 0.20,
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        if CD.getBreed(dog) ~= "germanshepherd" then return 0 end
        if CD.isDisloyal(dog) then return 0 end
        if not dogIsCaredFor(dog) then return 0 end
        return 1
    end,
    apply = function(player, dog, elapsedMin)
        local n = CD.couragePanicReliefPerMin() * elapsedMin
        if n <= 0 then return end
        local stats = player and player:getStats()
        if stats then
            stats:remove(CharacterStat.PANIC, n)
        end
    end,
}

-- O bonus de XP de raca e uma AURA: o moodle so avisa a borda, e quem concede e o servidor, em
-- memoria (server/systems/CompanionDogs_XPBoost.lua). Escrever no multiplicador do personagem
-- deixava o bonus gravado no save mesmo depois de dispensar o cao ou remover o mod.
local xpOn = {}

local function setOwnerXP(player, pn, id, on, force)
    if not player then return end
    on = on and true or false
    local cur = xpOn[pn]
    if not cur then
        cur = {}
        xpOn[pn] = cur
    end
    if not force and on == (cur[id] == true) then return end
    cur[id] = on or nil
    CD.request("xpboost", nil, { id = id, on = on }, player)
end

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "keennose",
    breed = "retriever",
    nameKey = "IGUI_PD_Moodle_GoldenNose",
    descKey = "IGUI_PD_Moodle_GoldenNose_desc",
    icon = "CD_Moodle_GoldenNose",
    fg = "CD_MoodGoldenNoseFG",
    tintR = 0.56, tintG = 0.80, tintB = 0.26,
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        if CD.getBreed(dog) ~= "retriever" then return 0 end
        if CD.isDisloyal(dog) then return 0 end
        if not dogIsCaredFor(dog) then return 0 end
        return 1
    end,
    apply = function(player, dog, elapsedMin)
        setOwnerXP(player, player:getPlayerNum(), "keennose", true)
    end,
    onDeactivate = function(player)
        if player then
            setOwnerXP(player, player:getPlayerNum(), "keennose", false)
        end
    end,
}

local huskyHeat = {}
local huskyHeatTile = {}
local xpInit = {}
local huskyWarm = {}

local function bodyTemp(player)
    local stats = player and player:getStats()
    if not stats then return 37 end
    return stats:get(CharacterStat.TEMPERATURE) or 37
end

local function clearHuskyHeat(player, pn)
    local hs = huskyHeat[pn]
    if hs then
        local cell = getCell()
        if cell then
            cell:removeHeatSource(hs)
        end
        huskyHeat[pn] = nil
        huskyHeatTile[pn] = nil
    end
    setOwnerXP(player, pn, "warmed", false)
    huskyWarm[pn] = nil
end

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "warmed",
    breed = "husky",
    nameKey = "IGUI_PD_Moodle_Warmed",
    descKey = "IGUI_PD_Moodle_Warmed_desc",
    icon = "CD_Moodle_Warmed",
    fg = "CD_MoodWarmedFG",
    tintR = 0.95, tintG = 0.52, tintB = 0.20,
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        if CD.getBreed(dog) ~= "husky" then return 0 end
        if CD.isDisloyal(dog) then return 0 end
        if not dogIsCaredFor(dog) then return 0 end
        return 1
    end,
    apply = function(player, dog, elapsedMin)
        local pn = player:getPlayerNum()
        setOwnerXP(player, pn, "warmed", true)
        local endN = CD.HUSKY_ENDURANCE_PER_MIN * (elapsedMin or 0)
        local endStats = endN > 0 and player:getStats()
        if endStats then
            endStats:add(CharacterStat.ENDURANCE, endN)
        end
        local t = bodyTemp(player)
        if huskyWarm[pn] then
            if t >= CD.HUSKY_COLD_EXIT then
                huskyWarm[pn] = false
            end
        else
            if t < CD.HUSKY_COLD_ENTER then
                huskyWarm[pn] = true
            end
        end
        if huskyWarm[pn] and dog and dog:getSquare() then
            local x, y, z = math.floor(dog:getX()), math.floor(dog:getY()), math.floor(dog:getZ())
            local tile = x .. "," .. y .. "," .. z
            local cell = getCell()
            if cell and huskyHeatTile[pn] ~= tile then
                if huskyHeat[pn] then
                    cell:removeHeatSource(huskyHeat[pn])
                end
                local hs = IsoHeatSource.new(x, y, z, CD.HUSKY_WARMTH_RADIUS, CD.HUSKY_WARMTH_TEMP)
                cell:addHeatSource(hs)
                huskyHeat[pn] = hs
                huskyHeatTile[pn] = tile
            end
        elseif huskyHeat[pn] then
            local cell = getCell()
            if cell then
                cell:removeHeatSource(huskyHeat[pn])
            end
            huskyHeat[pn] = nil
            huskyHeatTile[pn] = nil
        end
    end,
    onDeactivate = function(player)
        if player then
            clearHuskyHeat(player, player:getPlayerNum())
        end
    end,
}

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "herdinginstinct",
    breed = "bordercollie",
    nameKey = "IGUI_PD_Moodle_CollieHerding",
    descKey = "IGUI_PD_Moodle_CollieHerding_desc",
    icon = "CD_Moodle_CollieHerding",
    fg = "CD_MoodCollieHerdingFG",
    tintR = 0.26, tintG = 0.72, tintB = 0.64,
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        if CD.getBreed(dog) ~= "bordercollie" then return 0 end
        if CD.isDisloyal(dog) then return 0 end
        if not dogIsCaredFor(dog) then return 0 end
        return 1
    end,
    apply = function(player, dog, elapsedMin)
        setOwnerXP(player, player:getPlayerNum(), "herdinginstinct", true)
    end,
    onDeactivate = function(player)
        if player then
            setOwnerXP(player, player:getPlayerNum(), "herdinginstinct", false)
        end
    end,
}

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "sick",
    nameKey = "IGUI_PD_Moodle_Sick",
    descKey = "IGUI_PD_Moodle_Sick_desc",
    icon = "CD_Moodle_Sick",
    fg = "CD_MoodSickFG",
    tintR = 0.52, tintG = 0.60, tintB = 0.28,
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        return CD.isSick(dog) and 1 or 0
    end,
}

-- Um moodle por eixo da saude, e eles convivem: a ferida em quatro estagios, a febre, e cada doenca
-- com o seu. A descricao e uma linha curta propria, nao o texto da ficha: no balao so cabe o essencial.
local function healthMoodle(id, nameKey, icon, fg, r, g, b, cond, descKey)
    CD.DogMoodles[#CD.DogMoodles + 1] = {
        id = id,
        nameKey = nameKey,
        descKey = descKey,
        icon = icon,
        fg = fg,
        tintR = r, tintG = g, tintB = b,
        condition = function(player, dog)
            if not dog or dog:isDead() then return 0 end
            return cond(dog) and 1 or 0
        end,
    }
end

healthMoodle("vet", "IGUI_PD_StatusBleeding", "CD_Moodle_Bleeding", "CD_MoodBleedingFG",
    0.86, 0.26, 0.24, function(dog) return CD.vetBleeding(dog) end, "IGUI_PD_Moodle_Bleeding_desc")
healthMoodle("vethurt", "IGUI_PD_StatusHurt", "CD_Moodle_Hurt", "CD_MoodHurtFG",
    0.88, 0.52, 0.22,
    function(dog) return CD.vetCondition(dog) ~= nil and not CD.vetBleeding(dog) and not CD.vetBroken(dog) end,
    "IGUI_PD_Moodle_Hurt_desc")
healthMoodle("vetbroken", "IGUI_PD_StatusFractured", "CD_Moodle_Fracture", "CD_MoodFractureFG",
    0.75, 0.28, 0.12, function(dog) return CD.vetBroken(dog) end, "IGUI_PD_Moodle_Fracture_desc")
healthMoodle("vetinfected", "IGUI_PD_StatusInfected", "CD_Moodle_Infected", "CD_MoodInfectedFG",
    0.66, 0.30, 0.50, function(dog) return CD.vetInfected(dog) and not CD.vetCritical(dog) end,
    "IGUI_PD_Moodle_Infected_desc")
healthMoodle("vetcritical", "IGUI_PD_StatusCritical", "CD_Moodle_Critical", "CD_MoodCriticalFG",
    0.55, 0.12, 0.30, function(dog) return CD.vetCritical(dog) end, "IGUI_PD_Moodle_Critical_desc")

healthMoodle("vetfever", "IGUI_PD_StatusFever", "CD_Moodle_Fever", "CD_MoodFeverFG",
    0.80, 0.45, 0.20, function(dog) return CD.vetFever(dog) end, "IGUI_PD_Moodle_Fever_desc")

healthMoodle("vetflu", "IGUI_PD_HealthCondition_canineFlu", "CD_Moodle_Flu", "CD_MoodFluFG",
    0.62, 0.72, 0.82, function(dog) return CD.vetFlu(dog) end, "IGUI_PD_Moodle_Flu_desc")
healthMoodle("vetheartworm", "IGUI_PD_HealthCondition_heartwormDisease", "CD_Moodle_Heartworm",
    "CD_MoodHeartwormFG", 0.72, 0.24, 0.34, function(dog) return CD.vetHeartworm(dog) end,
    "IGUI_PD_Moodle_Heartworm_desc")
healthMoodle("vetallergy", "IGUI_PD_HealthCondition_skinAllergy", "CD_Moodle_Allergy",
    "CD_MoodAllergyFG", 0.88, 0.45, 0.62, function(dog) return CD.vetAllergy(dog) end,
    "IGUI_PD_Moodle_Allergy_desc")
healthMoodle("vetticks", "IGUI_PD_HealthCondition_ticks", "CD_Moodle_Ticks", "CD_MoodTicksFG",
    0.58, 0.42, 0.26, function(dog) return CD.vetTicks(dog) end, "IGUI_PD_Moodle_Ticks_desc")
healthMoodle("vetfleas", "IGUI_PD_HealthCondition_fleas", "CD_Moodle_Fleas", "CD_MoodFleasFG",
    0.66, 0.56, 0.34, function(dog) return CD.vetFleas(dog) end, "IGUI_PD_Moodle_Fleas_desc")

healthMoodle("vetgastro", "IGUI_PD_StatusSick", "CD_Moodle_Gastro", "CD_MoodGastroFG",
    0.50, 0.60, 0.25, function(dog) return CD.vetGastro(dog) end, "IGUI_PD_Moodle_Gastro_desc")
healthMoodle("vetworms", "IGUI_PD_VetRow_worms", "CD_Moodle_Worms", "CD_MoodWormsFG",
    0.55, 0.48, 0.30, function(dog) return CD.vetWorms(dog) end, "IGUI_PD_Moodle_Worms_desc")

-- Um moodle por janela de remedio preventivo. Sao todos verdes de proposito: o jogador bate o olho
-- na fileira e sabe o que ainda esta coberto e o que ja venceu. O texto conta os dias que faltam;
-- a chave fixa e o que sobra quando o cao ativo e outro e nao ha relogio para ler.
local function protMoodle(id, nameKey, icon, fg, r, g, b, field, daysKey)
    CD.DogMoodles[#CD.DogMoodles + 1] = {
        id = id,
        nameKey = nameKey,
        descKey = "IGUI_PD_VetRowTip_prev",
        icon = icon,
        fg = fg,
        tintR = r, tintG = g, tintB = b,
        descText = function(player)
            local dog = player and CD.getCompanionAnimal(player)
            local until_ = dog and CD.data(dog)[field]
            if not until_ then return nil end
            local days = math.ceil((until_ - CD.worldMinutes()) / 1440)
            return getText(daysKey, tostring(days))
        end,
        condition = function(player, dog)
            if not dog or dog:isDead() then return 0 end
            return CD.vetPrevented(dog, field) and 1 or 0
        end,
    }
end

protMoodle("vetdewormed", "IGUI_PD_Moodle_Dewormed", "CD_Moodle_Dewormed", "CD_MoodDewormedFG",
    0.34, 0.59, 0.47, "vetDewormPrevUntilMin", "IGUI_PD_Moodle_Dewormed_desc")
protMoodle("vetprothw", "IGUI_PD_Moodle_ProtHeartworm", "CD_Moodle_ProtHeartworm",
    "CD_MoodProtHeartwormFG", 0.34, 0.59, 0.47, "vetHwPrevUntilMin",
    "IGUI_PD_Moodle_ProtHeartworm_desc")
protMoodle("vetprotflea", "IGUI_PD_Moodle_ProtFlea", "CD_Moodle_ProtFlea", "CD_MoodProtFleaFG",
    0.34, 0.59, 0.47, "vetFleaPrevUntilMin", "IGUI_PD_Moodle_ProtFlea_desc")
protMoodle("vetprotalg", "IGUI_PD_Moodle_ProtAllergy", "CD_Moodle_ProtAllergy",
    "CD_MoodProtAllergyFG", 0.34, 0.59, 0.47, "vetAlgPrevUntilMin",
    "IGUI_PD_Moodle_ProtAllergy_desc")

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "vetimmune",
    nameKey = "IGUI_PD_Moodle_Immune",
    descKey = "IGUI_PD_Moodle_Immune_desc",
    icon = "CD_Moodle_Immune",
    fg = "CD_MoodImmuneFG",
    tintR = 0.35, tintG = 0.68, tintB = 0.35,
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        return CD.vetImmune(dog) and 1 or 0
    end,
}

-- A imunidade de ervas e a protecao da vacina com prazo em horas. Com a vacina ativa ela nao
-- aparece: seriam dois escudos iguais dizendo a mesma coisa.
CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "vetboost",
    nameKey = "IGUI_PD_Moodle_Boost",
    descKey = "IGUI_PD_VetRowTip_boost",
    icon = "CD_Moodle_Immune",
    fg = "CD_MoodImmuneFG",
    tintR = 0.35, tintG = 0.68, tintB = 0.35,
    descText = function(player)
        local dog = player and CD.getCompanionAnimal(player)
        local until_ = dog and CD.data(dog).vetBoostUntilMin
        if not until_ then return nil end
        local hours = math.ceil((until_ - CD.worldMinutes()) / 60)
        return getText("IGUI_PD_Moodle_Boost_desc", tostring(hours))
    end,
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        return (CD.vetPrevented(dog, "vetBoostUntilMin") and not CD.vetImmune(dog)) and 1 or 0
    end,
}

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "weak",
    nameKey = "IGUI_PD_Moodle_Weak",
    descKey = "IGUI_PD_Moodle_Weak_desc",
    icon = "CD_Moodle_Weak",
    fg = "CD_MoodWeakFG",
    tintR = 0.60, tintG = 0.56, tintB = 0.66,
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        return CD.isWeak(dog) and 1 or 0
    end,
}

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "hunger",
    nameKey = "IGUI_PD_Moodle_Hunger",
    descKey = "IGUI_PD_Moodle_Hunger_desc",
    icon = "CD_Moodle_Hunger",
    fg = "CD_MoodHungerFG",
    tintR = 0.90, tintG = 0.48, tintB = 0.18,
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        local h = CD.getHunger(dog)
        return h >= CD.HUNGER_WARN and 1 or 0
    end,
}

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "thirst",
    nameKey = "IGUI_PD_Moodle_Thirst",
    descKey = "IGUI_PD_Moodle_Thirst_desc",
    icon = "CD_Moodle_Thirst",
    fg = "CD_MoodThirstFG",
    tintR = 0.30, tintG = 0.58, tintB = 0.86,
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        local t = dog:getThirst()
        return t >= CD.THIRST_WARN and 1 or 0
    end,
}

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "rested",
    timed = true,
    nameKey = "IGUI_PD_Moodle_Rested",
    descKey = "IGUI_PD_Moodle_Rested_desc",
    icon = "CD_Moodle_Rested",
    fg = "CD_MoodRestedFG",
    condition = function(player)
        if not player then return 0 end
        if not CD.restedBuffEnabled or not CD.restedBuffEnabled() then return 0 end
        return CD.restedBuffLeftMin(player) > 0 and 1 or 0
    end,
    apply = function(player, dog, elapsedMin)
        CD.applyRestedBuff(player, elapsedMin)
    end,
}

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "grief",
    timed = true,
    nameKey = "IGUI_PD_Moodle_Grief",
    descKey = "IGUI_PD_Moodle_Grief_desc",
    icon = "CD_Moodle_Grief",
    fg = "CD_MoodGriefFG",
    tintR = 0.42, tintG = 0.46, tintB = 0.62,
    descText = function(player)
        local name = CD.griefName(player)
        if name then return getText("IGUI_PD_Moodle_Grief_desc_named", name) end
        return getText("IGUI_PD_Moodle_Grief_desc")
    end,
    condition = function(player)
        if not player then return 0 end
        return CD.griefLeftMin(player) > 0 and 1 or 0
    end,
    apply = function(player, dog, elapsedMin)
        CD.applyGrief(player, elapsedMin)
    end,
}

local activeByPlayer = {}
local lastMin = {}
local graceLeft = {}
local proxWas = {}

local prevActiveIds = {}
local function commitActive(pn, player, active)
    activeByPlayer[pn] = active
    local nowIds = {}
    local prox = false
    if active then
        for _, it in ipairs(active) do
            nowIds[it.def.id] = true
            if not it.def.timed then
                prox = true
            end
        end
    end
    proxWas[pn] = prox
    local prev = prevActiveIds[pn]
    if prev then
        for _, def in ipairs(CD.DogMoodles) do
            if type(def.onDeactivate) == "function" and prev[def.id] and not nowIds[def.id] then
                def.onDeactivate(player)
            end
        end
    end
    prevActiveIds[pn] = nowIds
end

local function evalTimed(player, elapsed)
    local out
    for _, def in ipairs(CD.DogMoodles) do
        if def.timed then
            local level = 0
            if type(def.condition) == "function" then
                level = def.condition(player, nil) or 0
            end
            if level > 0 then
                out = out or {}
                out[#out + 1] = { def = def, level = level }
                if type(def.apply) == "function" then
                    def.apply(player, nil, elapsed)
                end
            end
        end
    end
    return out
end

local function activeDogInRange(player, pn)
    local dog = CD.getCompanionAnimal(player)
    if not dog then return nil end
    local r = proxWas[pn] and CD.moodleHappyRadiusExit() or CD.moodleHappyRadius()
    if CD.dist2D(dog, player) > r then return nil end
    return dog
end

local function onPlayerUpdate(player)
    if not player then return end
    if not CD.dogMoodlesEnabled() then return end
    local pn = player:getPlayerNum()
    if player:isDead() then
        commitActive(pn, player, nil)
        lastMin[pn] = nil
        return
    end
    if not xpInit[pn] then
        xpInit[pn] = true
        for id in pairs(CD.ownerXPBoosts()) do setOwnerXP(player, pn, id, false, true) end
    end
    -- Nao escrever em maxWeight, maxWeightBase nem maxWeightDelta: campo derivado e compartilhado.
    local now = CD.worldMinutes()
    local prev = lastMin[pn]
    if prev == nil then
        lastMin[pn] = now
        return
    end
    local elapsed = now - prev
    -- O relogio do client de MP recua 24h todo dia as 7h. Reancorar aqui e obrigatorio: um elapsed
    -- negativo cai no throttle abaixo e o lastMin nunca mais atualiza.
    if elapsed < 0 then
        lastMin[pn] = now
        return
    end
    if elapsed < CD.MOODLE_TICK_MIN then return end
    lastMin[pn] = now
    if elapsed > CD.MOODLE_ELAPSED_CAP then
        elapsed = CD.MOODLE_ELAPSED_CAP
    end

    local dog = activeDogInRange(player, pn)
    if not dog then
        local active = evalTimed(player, elapsed)
        local pd = CD.playerData(player)
        local withMe = pd and (pd.stash ~= nil or pd.carried ~= nil)
        local prox
        local prevSet = activeByPlayer[pn]
        if prevSet then
            for _, it in ipairs(prevSet) do
                if not it.def.timed then
                    prox = prox or {}
                    prox[#prox + 1] = it
                end
            end
        end
        local grace = graceLeft[pn] or 0
        if prox and #prox > 0 and (withMe or grace > 0) then
            if not withMe then
                graceLeft[pn] = grace - elapsed
            end
            for _, it in ipairs(prox) do
                if type(it.def.apply) == "function" then
                    it.def.apply(player, nil, elapsed)
                end
                active = active or {}
                active[#active + 1] = it
            end
        else
            graceLeft[pn] = 0
        end
        commitActive(pn, player, active)
        return
    end

    local active
    local proxActive = false
    local noBreed = not CD.breedMoodlesEnabled() or (dog ~= nil and CD.suppressesBreedMoodle(dog))
    for _, def in ipairs(CD.DogMoodles) do
        local level = 0
        if not (noBreed and def.breed) and type(def.condition) == "function" then
            level = def.condition(player, dog) or 0
        end
        if level > 0 then
            active = active or {}
            active[#active + 1] = { def = def, level = level, breed = dog and CD.getBreed(dog) }
            if not def.timed then
                proxActive = true
            end
            if type(def.apply) == "function" then
                def.apply(player, dog, elapsed)
            end
        end
    end
    commitActive(pn, player, active)
    graceLeft[pn] = proxActive and CD.moodleGraceMin() or 0
end

local MOODLE_SIZES = { 32, 48, 64, 80, 96, 128 }
local RIGHT_MARGIN = 10
local COLUMN_GAP = 6
local FALLBACK_TOP_Y = 120

local texCache = {}
local function loadIcon(base, size)
    local key = base .. "_" .. size
    local cached = texCache[key]
    if cached ~= nil then return cached or nil end
    local t = getTexture("media/textures/" .. base .. "_" .. size .. ".png")
        or getTexture("media/textures/" .. base .. "_48.png")
        or getTexture(base .. "_" .. size)
    texCache[key] = t or false
    return t
end

local FRAME_R, FRAME_G, FRAME_B = 0.32, 0.82, 0.36
local frameCache = {}
local function loadFrame(name, size)
    local key = name .. "_" .. size
    local cached = frameCache[key]
    if cached ~= nil then return cached or nil end
    local t = getTexture("media/ui/Moodles/" .. size .. "/" .. name .. ".png")
    frameCache[key] = t or false
    return t
end

local function moodleSize()
    local mui = MoodlesUI.getInstance()
    if mui then
        local w = mui:getWidth()
        if w >= 32 then return w end
    end
    local s = MOODLE_SIZES[getCore():getOptionMoodleSize()] or 48
    return s
end

local ISCDMoodleStack = ISUIElement:derive("ISCDMoodleStack")

function ISCDMoodleStack:new(playerNum)
    local o = ISUIElement:new(0, 0, 48, 48)
    setmetatable(o, self)
    self.__index = self
    o.playerNum = playerNum
    o.draw = false
    o.size = 48
    o.rowStep = 58
    o.items = nil
    return o
end

-- setRenderThisPlayerOnly mora aqui: ISUIElement:instantiate troca o javaObject e a flag do :new se perde.
function ISCDMoodleStack:instantiate()
    ISUIElement.instantiate(self)
    self:setRenderThisPlayerOnly(self.playerNum)
    self.javaObject:setConsumeMouseEvents(false)
end

function ISCDMoodleStack:onMouseDown(x, y) return false end
function ISCDMoodleStack:onMouseDownOutside(x, y) return false end
function ISCDMoodleStack:onRightMouseDown(x, y) return false end
function ISCDMoodleStack:onMouseMove(dx, dy) return false end
function ISCDMoodleStack:onMouseMoveOutside() return false end

function ISCDMoodleStack:prerender()
    self.draw = false
    self:setWidth(0)
    self:setHeight(0)
    if not CD.dogMoodlesEnabled() then return end
    if not CD.Settings.getShowMoodles() then return end
    local items = activeByPlayer[self.playerNum]
    if not items or #items == 0 then return end
    local player = getSpecificPlayer(self.playerNum)
    if not player or player:isDead() then return end

    local size = moodleSize()
    local rowStep = size + 10
    local screenW = getCore():getScreenWidth()
    local iconX = screenW - RIGHT_MARGIN - (size * 2) - COLUMN_GAP

    local topY = FALLBACK_TOP_Y
    local mui = MoodlesUI.getInstance()
    if mui then
        local y = mui:getY()
        local screenH = getCore():getScreenHeight()
        if y >= 0 and y <= screenH * 0.45 then
            topY = y
        end
    end

    self.size = size
    self.rowStep = rowStep
    self.items = items
    self:setX(iconX)
    self:setY(topY)
    self:setWidth(size)
    self:setHeight(#items * rowStep)
    self.draw = true
end

function ISCDMoodleStack:drawMoodleTip(def, ry, size, breed)
    local name = getText(def.nameKey)
    local desc = CD.speciesTextFromKey(breed, def.descKey)
    if type(def.descText) == "function" then
        local dyn = def.descText(getSpecificPlayer(self.playerNum))
        if type(dyn) == "string" and dyn ~= "" then
            desc = dyn
        end
    end
    local tm = getTextManager()
    local font = UIFont.Small
    local fh = tm:getFontHeight(font)
    local tw = math.max(tm:MeasureStringX(font, name), tm:MeasureStringX(font, desc))
    local pad = 6
    local boxW = tw + pad * 2
    local boxH = fh * 2 + pad * 2
    local boxX = -boxW - 8
    local boxY = ry + (size - boxH) / 2
    self:drawRect(boxX, boxY, boxW, boxH, 0.85, 0, 0, 0)
    self:drawRectBorder(boxX, boxY, boxW, boxH, 0.4, 1, 1, 1)
    self:drawText(name, boxX + pad, boxY + pad, 1, 1, 1, 1, font)
    self:drawText(desc, boxX + pad, boxY + pad + fh, 0.82, 0.82, 0.82, 1, font)
end

function ISCDMoodleStack:render()
    if not self.draw or not self.items then return end
    local size = self.size
    local rowStep = self.rowStep
    local bg = loadFrame("_Moodles_BGsolid", size)
    local outline = loadFrame("_Moodles_BGoutline", size)
    local mx = getMouseX() - self:getAbsoluteX()
    local my = getMouseY() - self:getAbsoluteY()
    for i, it in ipairs(self.items) do
        local ry = (i - 1) * rowStep
        if bg and outline then
            local tr, tg, tb = it.def.tintR or FRAME_R, it.def.tintG or FRAME_G, it.def.tintB or FRAME_B
            self:drawTextureScaled(bg, 0, ry, size, size, 1, tr, tg, tb)
            self:drawTextureScaled(outline, 0, ry, size, size, 1, 1, 1, 1)
            local fg = loadIcon(it.def.fg or it.def.icon, size)
            if fg then
                self:drawTextureScaled(fg, 0, ry, size, size, 1, 1, 1, 1)
            end
        else
            local baked = loadIcon(it.def.icon, size)
            if baked then
                self:drawTextureScaled(baked, 0, ry, size, size, 1, 1, 1, 1)
            end
        end
        if mx >= 0 and mx <= size and my >= ry and my <= ry + size then
            self:drawMoodleTip(it.def, ry, size, it.breed)
        end
    end
end

local stacks = {}
local function ensureStack(playerNum)
    if stacks[playerNum] then return end
    local o = ISCDMoodleStack:new(playerNum)
    o:initialise()
    o:instantiate()
    o:addToUIManager()
    o:backMost()
    stacks[playerNum] = o
end

ISCDMoodleStack.prerender = CD.pzWrap("cli.moodle_draw", ISCDMoodleStack.prerender)
ISCDMoodleStack.render = CD.pzWrap("cli.moodle_draw", ISCDMoodleStack.render)

if isClient() or not isServer() then
    CD.evAdd(Events.OnPlayerUpdate, onPlayerUpdate, "cli.moodles")
    Events.OnCreatePlayer.Add(ensureStack)
end
