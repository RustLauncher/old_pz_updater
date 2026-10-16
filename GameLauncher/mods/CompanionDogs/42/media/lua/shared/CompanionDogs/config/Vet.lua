CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.VET_WOUND_CHANCE_PCT = 0.4
-- Fracao da chance de ferida que cada nivel de Combate tira: no padrao, 0,02 ponto por nivel.
CD.VET_WOUND_COMBAT_CUT_PER_LEVEL = 0.05
CD.VET_LESION_COOLDOWN_MIN = 120
CD.VET_AGGR_WOUND = 1.0
CD.VET_AGGR_LOWHP = 1.5
CD.VET_AGGR_STRESS = 1.3
CD.VET_AGGR_STRESS_MIN = 0.60
CD.VET_AGGR_CAP = 4.0

-- Passo da passada de doenca, em minutos de jogo. Separado do upkeep (3 min) de proposito: fome e
-- sede precisam de resolucao fina, doenca nao, e todo contador daqui acumula o passo, entao alargar
-- so muda quando a transicao acontece, nunca o quanto ela custa.
CD.VET_TICK_INTERVAL_MIN = 15

CD.VET_INFECT_WINDOW_MIN = 60
CD.VET_INFECT_CHANCE = { [0] = 0.20, [1] = 0, [2] = 0 }
CD.VET_INFECT_CHANCE_DIRTY = 0.05

CD.VET_CUT_HEAL_MIN = 2880
CD.VET_CUT_HEAL_DRESSED_MIN = 1440
CD.VET_INFECT_HEAL_MIN = 2880
CD.VET_FRACTURE_HEAL_MIN = 4320
CD.VET_WORK_CURE_MULT = 0.5

CD.VET_CUT_WALK_MULT = 0.9
CD.VET_CUT_RUN_MULT = 0.75
CD.VET_FRACTURE_WALK_MULT = 0.5

CD.VET_BLEED_DRAIN_PER_DAY = 0.9
CD.VET_BLEED_STOP_MIN = 720
CD.VET_SAFE_HEALTH_FLOOR = 0.10

CD.VET_STAGE_MIN = 720
CD.VET_STAGE_DRAIN_PER_DAY = { [1] = 0.25, [2] = 0.5 }
CD.VET_CRIT_HEALTH_FRAC = 0.10
CD.VET_FEVER_WALK_MULT = 0.8
CD.VET_ABX_MIN = 720
-- O comprimido humano e a mesma molecula: cura igual. O que muda e a dose, chutada pelo peso do
-- cao, e dose errada de antibiotico vira estomago.
CD.VET_HUMAN_ABX_GASTRO_PCT = 25.0

CD.VET_SPRAIN_HOP_PCT = 0.5
CD.VET_SPRAIN_HEAL_MIN = 720

CD.VET_GASTRO_MIN_MIN = 1440
CD.VET_GASTRO_MAX_MIN = 2880
CD.VET_GASTRO_ROTTEN_CHANCE = 1.0
CD.VET_GASTRO_SPOIL_PCT = 25.0
CD.VET_WATER_ROLL_COOLDOWN_MIN = 720
CD.VET_GASTRO_THIRST_MAX = 0.5
CD.VET_GASTRO_NEED_MULT = 2.0
-- Verme nao nasce junto do estomago virado: ele se instala enquanto o bicho fica doente. A cada
-- janela destas com o estomago virado, uma rolagem; tratar o estomago antes corta a evolucao.
CD.VET_WORMS_WINDOW_MIN = 360
CD.VET_WORMS_CHANCE_PCT = 10.0
CD.VET_WORMS_HUNGER_MULT = 1.4
-- O vermifugo nao mata o verme no gole: age em VET_DEWORM_ACT_MIN e o resto da dose fica no bicho
-- como protecao. Sem a protecao, dar o comprimido com o estomago ainda virado so adiava o proximo
-- verme por uma janela de incubacao.
CD.VET_DEWORM_MIN = 1440
CD.VET_DEWORM_ACT_MIN = 240
CD.VET_DEWORM_PREV_MIN = 43200
CD.VET_IMMUNE_MIN = 129600
CD.VET_GRASS_GASTRO_CUT_MIN = 480
CD.VET_GRASS_TOXIC_CUT_MIN = 240
CD.VET_SLEEP_REGEN_MULT = 2.0
CD.VET_MEDICATE_TICKS = 110

-- Gripe canina: pega por fome severa ou por contato de um tile com cao gripado, e passa sozinha em
-- dois a quatro dias. Da febre o tempo todo, entao o cao bebe mais e anda mais devagar.
CD.VET_FLU_MIN_MIN = 2880
CD.VET_FLU_MAX_MIN = 5760
CD.VET_FLU_STRESS_PER_DAY = 0.3
-- A mesma chance vale para os dois caminhos: a rolagem diaria do cao faminto e cada hora de contato
-- com um cao gripado. Uma opcao de sandbox so, como nas outras doencas.
CD.VET_FLU_CHANCE_PCT = 15.0
CD.VET_FLU_STARVE_ROLL_MIN = 1440
CD.VET_FLU_CONTACT_COOLDOWN_MIN = 60
CD.VET_FLU_CONTACT_RANGE = 1
CD.VET_FLU_VACCINE_CURE_MIN = 1440
CD.VET_FLU_ABX_CUT = 0.6

-- Dirofilariose: so pega ao ar livre, e o relogio de exposicao zera quando o cao entra. Nao mata
-- rapido, mas derruba o bicho: febre, passo curto e recusa de luta e de truque ate o remedio.
CD.VET_HW_MIN_MIN = 4320
CD.VET_HW_MAX_MIN = 8640
CD.VET_HW_EXPO_ROLL_MIN = 360
CD.VET_HW_EXPO_PCT = 1.5
CD.VET_HW_DRAIN_PER_DAY = 0.25
CD.VET_HW_WALK_MULT = 0.65
CD.VET_HW_RUN_MULT = 0.45
CD.VET_HW_CURE_MIN = 1080
CD.VET_HW_PREV_MIN = 43200

-- Alergia de pele: por carne que o cao nao tolera ou por pulga e carrapato. Coca umas partes do
-- corpo, incomoda e passa sozinha em meio dia ou um dia.
CD.VET_ALG_MIN_MIN = 720
CD.VET_ALG_MAX_MIN = 1440
CD.VET_ALG_PARTS_MIN = 2
CD.VET_ALG_PARTS_MAX = 5
CD.VET_ALG_STRESS_PER_DAY = 0.3
CD.VET_ALG_PROTEIN_PCT = 5.0
-- Familias que o sorteio de alergia pode devolver: nem a racao, que e a base da dieta, nem a carne
-- generica que o jogo nao classifica.
CD.VET_ALLERGEN_POOL = { "Poultry", "Beef", "Venison", "Game", "Fish", "Sausage", "Pork", "Egg", "Insect" }
CD.VET_ALG_CURE_MIN = 360
CD.VET_ALG_PREV_MIN = 2880

-- Pulga e carrapato: vem do corpo a corpo. A fase ativa coca e pode virar alergia; depois dela o
-- bicho fica quieto mas continua no cao ate alguem dar o remedio.
CD.VET_INFEST_COMBAT_PCT = 0.2
CD.VET_INFEST_ACTIVE_MIN = 2880
CD.VET_INFEST_PULSE_MIN_MIN = 60
CD.VET_INFEST_PULSE_MAX_MIN = 180
CD.VET_FLEA_STRESS = 0.02
CD.VET_FLEA_ALLERGY_PCT = 3.0
CD.VET_TICK_MULT = 1.75
CD.VET_INFEST_CURE_MIN = 720
CD.VET_INFEST_PREV_MIN = 43200

CD.VET_TREAT_SKILL_PCT = 0.05
CD.VET_PREV_SKILL_PCT = 0.025
CD.VET_FIRST_AID_XP_MIN = 0.7
CD.VET_FIRST_AID_XP_MAX = 3.2

CD.VET_ITEM_ABX = "Base.CompanionDogsAntibiotic"
CD.VET_ITEM_DEWORMER = "Base.CompanionDogsDewormer"
CD.VET_ITEM_VACCINE = "Base.CompanionDogsVaccine"
CD.VET_ITEM_ANTIHISTAMINE = "Base.CompanionDogsAntihistamine"
CD.VET_ITEM_FLEATICK = "Base.CompanionDogsFleaTickMedicine"
CD.VET_ITEM_HEARTWORM = "Base.CompanionDogsHeartwormMedicine"
CD.VET_ITEM_HUMAN_ABX = "Base.Antibiotics"
CD.VET_ITEM_GRASS = "Base.GrassTuft"

-- Pulga e carrapato correm no mesmo molde e so mudam de intensidade, entao o tick e um so e le a
-- linha da especie aqui.
CD.VET_INFEST_KINDS = {
    fleas = { field = "vetFleas", pulse = "vetFleaPulseMin", mult = 1.0, notify = "vetfleas" },
    ticks = { field = "vetTicks", pulse = "vetTickPulseMin", mult = CD.VET_TICK_MULT, notify = "vetticks" },
}

-- Cada remedio diz o que trata e por quanto tempo protege depois. Antibiotico, vermifugo e alho tem
-- regra propria e entram so pelo id; o resto passa inteiro pelo aplicador generico, que le:
-- `courses` (cada curso abre se um campo de `needs` existe, e nunca com o campo `unless` de pe),
-- `prevent`, `cuts` (minutos tirados do estomago e do envenenamento, este vezes a severidade),
-- `stress`, `aid` (ajuda de ferida em andamento) e `relief` (gripe sem febre). `prophylactic` diz se o
-- remedio tambem pode ser dado em cao sao, so pela protecao.
CD.VET_MEDICINES = {
    [CD.VET_ITEM_ABX] = { id = "abx", key = "vetabxgiven" },
    [CD.VET_ITEM_HUMAN_ABX] = { id = "humanabx", key = "vetabxhuman" },
    [CD.VET_ITEM_DEWORMER] = { id = "dewormer", key = "vetdewormgiven" },
    [CD.VET_ITEM_GRASS] = {
        id = "grass", key = "vetgrass",
        cuts = { gastro = CD.VET_GRASS_GASTRO_CUT_MIN, toxic = CD.VET_GRASS_TOXIC_CUT_MIN },
    },
    [CD.VET_ITEM_VACCINE] = {
        id = "vaccine", key = "vetvaccinated", prophylactic = true,
        courses = { { field = "vetCourseFlu", min = CD.VET_FLU_VACCINE_CURE_MIN, needs = { "vetFluMin" } } },
        prevent = { field = "vetImmuneUntilMin", min = CD.VET_IMMUNE_MIN },
    },
    [CD.VET_ITEM_ANTIHISTAMINE] = {
        id = "antihistamine", key = "vetmedicated",
        courses = { { field = "vetCourseAlg", min = CD.VET_ALG_CURE_MIN, needs = { "vetAlgMin" } } },
        prevent = { field = "vetAlgPrevUntilMin", min = CD.VET_ALG_PREV_MIN },
    },
    [CD.VET_ITEM_FLEATICK] = {
        id = "fleatick", key = "vetmedicated", prophylactic = true,
        courses = { { field = "vetCourseFlea", min = CD.VET_INFEST_CURE_MIN, needs = { "vetFleas", "vetTicks" } } },
        prevent = { field = "vetFleaPrevUntilMin", min = CD.VET_INFEST_PREV_MIN },
    },
    [CD.VET_ITEM_HEARTWORM] = {
        id = "heartworm", key = "vetmedicated", prophylactic = true,
        courses = { { field = "vetCourseHw", min = CD.VET_HW_CURE_MIN, needs = { "vetHwMin" } } },
        prevent = { field = "vetHwPrevUntilMin", min = CD.VET_HW_PREV_MIN },
    },
}

-- Os remedios do Mans Best Friend fazem a mesma coisa e o jogador nao tem como saber que sao de
-- outro mod. Aceitamos os ids dela sem depender do mod: se ele nao estiver instalado, a linha e
-- so uma chave que nunca casa.
CD.VET_MEDICINE_ALIASES = {
    ["MansBestFriend.Meds_Antibiotics"] = CD.VET_ITEM_ABX,
    ["MansBestFriend.Meds_Dewormer"] = CD.VET_ITEM_DEWORMER,
    ["MansBestFriend.Meds_FluVaccine"] = CD.VET_ITEM_VACCINE,
    ["MansBestFriend.Meds_Antihistamine"] = CD.VET_ITEM_ANTIHISTAMINE,
    ["MansBestFriend.Meds_BiteyGard"] = CD.VET_ITEM_FLEATICK,
    ["MansBestFriend.Meds_HeartwormMeds"] = CD.VET_ITEM_HEARTWORM,
    ["MansBestFriend.Meds_HeartwoomMeds"] = CD.VET_ITEM_HEARTWORM,
}

---@param fullType string
---@return table|nil definition
---@return string canonicalType the id of our own item, for an alias
function CD.vetMedicineDef(fullType)
    local canonical = CD.VET_MEDICINE_ALIASES[fullType] or fullType
    return CD.VET_MEDICINES[canonical], canonical
end

---Doctor and Husbandry shorten every treatment course.
---@param player IsoPlayer|nil
---@return number
---@nodiscard
function CD.vetTreatMult(player)
    if player == nil then return 1 end
    local doctor = player:getPerkLevel(Perks.Doctor)
    local husbandry = player:getPerkLevel(Perks.Husbandry)
    return 1 + CD.VET_TREAT_SKILL_PCT * (doctor + husbandry)
end

---The same two skills stretch the protection window instead.
---@param player IsoPlayer|nil
---@return number
---@nodiscard
function CD.vetPrevMult(player)
    if player == nil then return 1 end
    local doctor = player:getPerkLevel(Perks.Doctor)
    local husbandry = player:getPerkLevel(Perks.Husbandry)
    return 1 + CD.VET_PREV_SKILL_PCT * (doctor + husbandry)
end

CD.VET_TREAT_LOYALTY = 4
CD.VET_TREAT_TICKS = 220
CD.VET_TREAT_DOCTOR_CUT = 0.12
CD.VET_TREAT_MIN_FRAC = 0.4
CD.VET_DIAG_HUSBANDRY = 5

CD.PANIC_HYST = 0.10
CD.VET_DEBUG = false

CD.VET_LIMP_FRONT_VAR = "cdLimpFront"
CD.VET_LIMP_BACK_VAR = "cdLimpBack"
CD.VET_FRONT_PAW_CHANCE = 0.6
CD.VET_FEVER_THIRST_MULT = 1.2

-- Partes do corpo do painel de saude, na ordem da lista (desenho e ideia da freylith). Ferida e
-- curativo so caem nas duas patas direitas, que sao as que o rig manca e a textura pinta.
CD.HEALTH_BODY_PARTS = {
    "head", "upperTorso", "lowerTorso",
    "rightFrontLeg", "rightFrontPaw", "leftFrontLeg", "leftFrontPaw",
    "rightBackLeg", "rightBackPaw", "leftBackLeg", "leftBackPaw", "tail",
    "stomach", "lungs", "heart",
}
CD.HEALTH_EXTERNAL_PARTS = {
    "head", "upperTorso", "lowerTorso",
    "rightFrontLeg", "rightFrontPaw", "leftFrontLeg", "leftFrontPaw",
    "rightBackLeg", "rightBackPaw", "leftBackLeg", "leftBackPaw", "tail",
}
-- Males que a janela de debug sabe aplicar e limpar, na ordem do combo.
CD.HEALTH_DEBUG_AILMENTS = {
    { id = "cut", labelKey = "IGUI_PD_HealthCondition_cut" },
    { id = "bleeding", labelKey = "IGUI_PD_HealthCondition_bleeding" },
    { id = "sprain", labelKey = "IGUI_PD_HealthCondition_sprain" },
    { id = "fracture", labelKey = "IGUI_PD_HealthCondition_fracture" },
    { id = "infected", labelKey = "IGUI_PD_HealthCondition_woundInfection" },
    { id = "fever", labelKey = "IGUI_PD_HealthCondition_fever" },
    { id = "critical", labelKey = "IGUI_PD_HealthCondition_critical" },
    { id = "toxic", labelKey = "IGUI_PD_HealthCondition_toxic" },
    { id = "gastro", labelKey = "IGUI_PD_HealthCondition_gastroenteritis" },
    { id = "worms", labelKey = "IGUI_PD_HealthCondition_intestinalParasite" },
    { id = "flu", labelKey = "IGUI_PD_HealthCondition_canineFlu" },
    { id = "heartworm", labelKey = "IGUI_PD_HealthCondition_heartwormDisease" },
    { id = "allergy", labelKey = "IGUI_PD_HealthCondition_skinAllergy" },
    { id = "fleas", labelKey = "IGUI_PD_HealthCondition_fleas" },
    { id = "ticks", labelKey = "IGUI_PD_HealthCondition_ticks" },
}


-- O nome da textura vive no AnimalVisual e e salvo com o animal, mas o MODELO nao: um cao que sai de
-- cena e volta nasce com o modelo da textura base ainda que o nome ja seja o da variante. Guardamos a
-- instancia de modelo da ultima pintura para repintar quando ela troca.
local skinPaint = {}
local SKIN_SETTLE_MS = 2000
-- Cao que ja recebeu var de manqueira ou pele de ferida. O cliente varre todo companheiro uma vez por
-- segundo; sem esta marca, cao sao pagaria a dezena de chamadas de engine deste arquivo a toa.
local limpTouched = {}

---Drives the two limp animation flags from the dog's ModData. Runs on both VMs: the server moves the
---dog with the root motion of whatever clip plays, the client only draws it.
---@param animal IsoAnimal
function CD.vetApplyLimpVars(animal)
    local d = CD.data(animal)
    local key = CD.animKey(animal)
    CD.perfCount("vet.skinscan")
    if d.vetKind == nil and not limpTouched[key] then return end
    CD.perfCount("vet.skinwork")
    local def = CD.getBreedDef(animal)
    local paw = nil
    if d.vetKind ~= nil and CD.vetCareEnabled() and def.limpAnim == true then
        paw = d.vetPaw
    end
    animal:setVariable(CD.VET_LIMP_FRONT_VAR, paw == "front")
    animal:setVariable(CD.VET_LIMP_BACK_VAR, paw == "back")
    local painted = CD.vetApplySkin(animal, def, key)
    if paw == nil and not painted then
        limpTouched[key] = nil
    else
        limpTouched[key] = true
    end
end

---Drops the "already touched" marks so the next pass walks every dog again. The client calls this now
---and then: a dog wounded or healed far from this VM never got a mark here.
function CD.vetForgetLimpMarks()
    limpTouched = {}
end

---The wound and the dressing are texture swaps, the way the game paints bandages on the player: breeds
---declare `bandSkin = { base, front, back, cutFront, cutBack }` and the body texture flips to the cut
---variant while the wound bleeds and to the banded one while it is dressed. Runs on both VMs; only
---touches skins it knows, so pups and rotting bodies are left alone.
---@param animal IsoAnimal
---@param def table|nil breed definition, when the caller already has it
---@param key any|nil animal key, when the caller already has it
---@return boolean true while the dog wears a wound or dressing skin
function CD.vetApplySkin(animal, def, key)
    local skins = (def or CD.getBreedDef(animal)).bandSkin
    if not skins then return false end
    local d = CD.data(animal)
    local want = skins.base
    if CD.vetCondition(animal) == "cut" then
        local variant
        if (d.vetDress or 0) >= 1 then
            variant = skins.front
            if d.vetPaw == "back" then
                variant = skins.back
            end
        else
            variant = skins.cutFront
            if d.vetPaw == "back" then
                variant = skins.cutBack
            end
        end
        if variant then
            want = variant
        end
    end
    local wearing = want ~= skins.base
    key = key or CD.animKey(animal)
    if not wearing and skinPaint[key] == nil then return false end
    local vis = animal:getAnimalVisual()
    local cur = vis:getSkinTexture()
    if cur ~= want and cur ~= skins.base and cur ~= skins.front and cur ~= skins.back
        and cur ~= skins.cutFront and cur ~= skins.cutBack then return wearing end
    local mi = animal:getModelInstance()
    local inst = mi and tostring(mi) or ""
    local st = skinPaint[key]
    local nowMs = getTimestampMs()
    if cur == want then
        if not wearing then
            skinPaint[key] = nil
            return false
        end
        if st == nil or st.want ~= want then
            skinPaint[key] = { want = want, inst = inst, ms = nowMs }
            return true
        end
        if st.inst == inst then return true end
        -- Modelo trocado logo apos a nossa propria troca: adota a instancia nova sem repintar.
        if (nowMs - st.ms) < SKIN_SETTLE_MS then
            st.inst = inst
            return true
        end
    end
    vis:setSkinTextureName(want)
    animal:resetModel()
    animal:resetModelNextFrame()
    CD.perfCount("vet.skinpaint")
    if wearing then
        skinPaint[key] = { want = want, inst = inst, ms = nowMs }
    else
        skinPaint[key] = nil
    end
    if CD.VET_DEBUG then
        CD.log("[CD-VET] pele " .. tostring(cur) .. " -> " .. want .. " cao=" .. tostring(d.name))
    end
    return wearing
end

---Broken paw, sprain or critical stage: the dog does not run, hop fences or fight. Takes the ModData
---table so the per-tick movement code does not pay another getModData.
---@param d table companion ModData
---@return boolean
---@nodiscard
function CD.vetLame(d)
    if not CD.vetCareEnabled() or d.vetKind == nil then return false end
    return d.vetBroken ~= nil or d.vetCrit ~= nil
end

---@param d table companion ModData
---@return boolean
---@nodiscard
function CD.mayRunFrom(d)
    return not CD.vetLame(d)
end

---Gait penalty of everything the dog is carrying, composed by the worst of each source.
---@param d table companion ModData
---@return number walkMult
---@return number|nil runMult nil when the dog cannot run at all
---@nodiscard
function CD.vetGaitMult(d)
    if not CD.vetCareEnabled() then return 1, 1 end
    if CD.vetLame(d) then return CD.VET_FRACTURE_WALK_MULT, nil end
    local w, r = 1, 1
    if d.vetKind ~= nil or d.vetAlgMin ~= nil then
        w, r = CD.VET_CUT_WALK_MULT, CD.VET_CUT_RUN_MULT
    end
    if d.vetHwMin ~= nil then
        if CD.VET_HW_WALK_MULT < w then
            w = CD.VET_HW_WALK_MULT
        end
        if CD.VET_HW_RUN_MULT < r then
            r = CD.VET_HW_RUN_MULT
        end
    end
    if CD.vetFeverFrom(d) then
        w = w * CD.VET_FEVER_WALK_MULT
        r = r * CD.VET_FEVER_WALK_MULT
    end
    return w, r
end

---Hunger and thirst accrual multipliers of the gut conditions.
---@param d table companion ModData
---@return number hungerMult
---@return number thirstMult
---@nodiscard
function CD.vetNeedMult(d)
    if not CD.vetCareEnabled() then return 1, 1 end
    local h, t = 1, 1
    if d.vetGastroMin ~= nil then
        h = h * CD.VET_GASTRO_NEED_MULT
        t = t * CD.VET_GASTRO_NEED_MULT
    end
    if d.vetWorms ~= nil then
        h = h * CD.VET_WORMS_HUNGER_MULT
    end
    if CD.vetFeverFrom(d) then
        t = t * CD.VET_FEVER_THIRST_MULT
    end
    return h, t
end

---A protection window is one timestamp in the future, whatever the medicine was.
---@param d table companion ModData
---@param field string
---@param now number world minutes
---@return boolean
---@nodiscard
function CD.vetProtected(d, field, now)
    local until_ = d[field]
    return until_ ~= nil and now < until_
end

---Fever has three sources: an infected wound at stage 2, the flu and heartworm disease. The steam
---relief takes the flu out while it lasts.
---@param d table companion ModData
---@return boolean
---@nodiscard
function CD.vetFeverFrom(d)
    if d.vetHwMin ~= nil then return true end
    if d.vetFluMin ~= nil and d.vetFluReliefMin == nil then return true end
    return d.vetKind ~= nil and (d.vetStage or 0) >= 2
end

---@param d table companion ModData
---@param now number world minutes
---@return boolean
---@nodiscard
function CD.vetImmuneFrom(d, now)
    return CD.vetProtected(d, "vetImmuneUntilMin", now)
end

---@param d table companion ModData
---@param course table one row of a medicine's `courses`
---@return boolean the dose would start this course now
---@nodiscard
function CD.vetCourseOpens(d, course)
    if d[course.field] ~= nil then return false end
    if course.unless ~= nil and d[course.unless] ~= nil then return false end
    for _, field in ipairs(course.needs) do
        if d[field] ~= nil then return true end
    end
    return false
end

---@param animal IsoAnimal
---@param d table companion ModData
---@param cuts table the medicine's `cuts`
---@return boolean
---@nodiscard
function CD.vetCutsFit(animal, d, cuts)
    if cuts.gastro ~= nil and d.vetGastroMin ~= nil then return true end
    return cuts.toxic ~= nil and CD.isSick(animal)
end

---A wound aid only works on its own kind of injury: skin aids on a clean cut, bone aids on a fracture
---or sprain, "any" on every injury. On an infected cut the healing is paused, so a skin aid would be a
---wasted dose.
---@param d table companion ModData
---@param aid table the medicine's `aid`
---@return boolean
---@nodiscard
function CD.vetAidFits(d, aid)
    if aid.on == "cut" then
        return d.vetKind == "cut" and d.vetBroken == nil and (d.vetStage or 0) == 0
    end
    if aid.on == "bone" then return d.vetBroken ~= nil or d.vetKind == "sprain" end
    if aid.on == "any" then return d.vetKind ~= nil end
    return aid.on == "fracture" and d.vetBroken ~= nil
end

---Vaccine or herbal immunity: while either lasts, wounds don't get infected, bad food or water don't
---upset the stomach and the flu doesn't take hold.
---@param d table companion ModData
---@param now number world minutes
---@return boolean
---@nodiscard
function CD.vetShielded(d, now)
    return CD.vetImmuneFrom(d, now) or CD.vetProtected(d, "vetBoostUntilMin", now)
end

---How much faster the illnesses that pass on their own run out: 1, or the systemic balance rate.
---@param d table companion ModData
---@return number
---@nodiscard
function CD.vetRecoveryRate(d)
    if d.vetBalanceMin ~= nil then return CD.VET_BALANCE_RATE end
    return 1
end

---Something the systemic balance speeds up: a wound, or an illness that passes on its own.
---@param animal IsoAnimal
---@param d table companion ModData
---@return boolean
---@nodiscard
function CD.vetRecovering(animal, d)
    if d.vetKind ~= nil or d.vetGastroMin ~= nil or d.vetFluMin ~= nil then return true end
    if d.vetHwMin ~= nil or d.vetAlgMin ~= nil then return true end
    return CD.isSick(animal)
end

---@param fullType string
---@return table|nil definition
---@return string canonicalType
function CD.vetBathDef(fullType)
    local canonical = CD.VET_BATH_ALIASES[fullType] or fullType
    return CD.VET_BATHS[canonical], canonical
end

---Enough water for a bath, clean or not, in any container.
---@param item InventoryItem
---@return boolean
---@nodiscard
function CD.isBathWater(item)
    if not item:hasComponent(ComponentType.FluidContainer) then return false end
    local fc = item:getFluidContainer()
    if fc:getAmount() < CD.VET_BATH_WATER_L then return false end
    local fluid = fc:getPrimaryFluid():getFluidTypeString()
    return fluid == "Water" or fluid == "TaintedWater" or fluid == "CarbonatedWater"
end

---@param item InventoryItem
---@return boolean
---@nodiscard
function CD.isBathCloth(item)
    return CD.VET_BATH_CLOTHS[item:getFullType()] == true
end

---The water and the cloth a bath needs, searched in bags too.
---@param inv ItemContainer
---@return InventoryItem|nil water
---@return InventoryItem|nil cloth
function CD.vetBathKit(inv)
    return inv:getFirstEvalRecurse(CD.isBathWater), inv:getFirstEvalRecurse(CD.isBathCloth)
end

---Mirror of the server rule for the bath menu. Shampoo needs fleas or ticks; the oatmeal bath needs an
---allergy or some stress to take off.
---@param animal IsoAnimal
---@param fullType string
---@return boolean
---@nodiscard
function CD.vetBathApplies(animal, fullType)
    if not CD.vetCareEnabled() then return false end
    local def = CD.vetBathDef(fullType)
    if def == nil then return false end
    local d = CD.data(animal)
    if def.infest then return d.vetFleas ~= nil or d.vetTicks ~= nil end
    if d.vetAlgMin ~= nil then return true end
    return (d.combatStress or 0) >= def.stress.min
end

---Healing speed of every aid the wound is wearing, multiplied together.
---@param d table companion ModData
---@return number
---@nodiscard
function CD.vetAidHealMult(d)
    local m = 1
    for i = 1, #CD.VET_AIDS do
        local aid = CD.VET_AIDS[i]
        if d[aid.field] ~= nil and aid.heal ~= nil and CD.vetAidFits(d, aid) then
            m = m * aid.heal
        end
    end
    return m
end

---@param d table companion ModData
---@return number multiplier on the chance an open cut gets infected
---@nodiscard
function CD.vetAidInfectMult(d)
    local m = 1
    for i = 1, #CD.VET_AIDS do
        local aid = CD.VET_AIDS[i]
        if d[aid.field] ~= nil and aid.infect ~= nil and CD.vetAidFits(d, aid) then
            m = m * aid.infect
        end
    end
    return m
end

---Mirror of the server rules, so the menu only lists what the dog can take right now.
---@param animal IsoAnimal
---@param fullType string
---@return boolean
---@nodiscard
function CD.vetMedicineApplies(animal, fullType)
    if not CD.vetCareEnabled() then return false end
    local d = CD.data(animal)
    local def = CD.vetMedicineDef(fullType)
    if def == nil then return false end
    if def.id == "abx" or def.id == "humanabx" then
        local stage = 0
        if d.vetKind ~= nil then
            stage = d.vetStage or 0
        end
        return (stage >= 1 or d.vetFluMin ~= nil) and d.vetAbxMin == nil
    end
    if def.id == "dewormer" then
        if d.vetDewormMin ~= nil then return false end
        if d.vetWorms ~= nil then return true end
        return not CD.vetProtected(d, "vetDewormPrevUntilMin", CD.worldMinutes())
    end
    if def.id == "garlic" then
        return d.vetKind ~= nil and (d.vetStage or 0) >= 1 and d.vetAbxMin == nil and d.vetGarlicMin == nil
    end
    if def.id == "tweezers" then
        return (d.vetFleas or 0) > 0 or (d.vetTicks or 0) > 0
    end
    if def.balance ~= nil then
        return d[def.balance.field] == nil and CD.vetRecovering(animal, d)
    end
    local aid = def.aid
    if aid ~= nil and d[aid.field] == nil and CD.vetAidFits(d, aid) then return true end
    if def.cuts ~= nil and CD.vetCutsFit(animal, d, def.cuts) then return true end
    if def.stress ~= nil and (d.combatStress or 0) >= def.stress.min then return true end
    if def.relief ~= nil and d.vetFluMin ~= nil and d[def.relief.field] == nil then return true end
    local courses = def.courses
    if courses ~= nil then
        for i = 1, #courses do
            if CD.vetCourseOpens(d, courses[i]) then return true end
        end
    end
    if def.prophylactic and def.prevent ~= nil then
        local now = CD.worldMinutes()
        if def.prevent.covered ~= nil and CD.vetProtected(d, def.prevent.covered, now) then return false end
        return not CD.vetProtected(d, def.prevent.field, now)
    end
    return false
end

---@param d table companion ModData
---@return number minutes of cure the current wound needs before it closes
---@nodiscard
function CD.vetHealGoal(d)
    local goal = CD.VET_CUT_HEAL_MIN
    if d.vetKind == "sprain" then
        goal = CD.VET_SPRAIN_HEAL_MIN
    elseif (d.vetStage or 0) >= 1 then
        goal = CD.VET_INFECT_HEAL_MIN
    elseif (d.vetDress or 0) >= 1 then
        goal = CD.VET_CUT_HEAL_DRESSED_MIN
    end
    if d.vetBroken ~= nil and goal < CD.VET_FRACTURE_HEAL_MIN then
        goal = CD.VET_FRACTURE_HEAL_MIN
    end
    return goal
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.mayRun(animal)
    return CD.mayRunFrom(CD.data(animal))
end

---Same rule as the vanilla health panel: a bottle at 40% alcohol or more, or a wipe with alcohol power.
---@param item InventoryItem
---@return boolean
---@nodiscard
function CD.isDisinfectant(item)
    if item:hasComponent(ComponentType.FluidContainer) then
        local fc = item:getFluidContainer()
        local amount = fc:getAmount()
        if amount <= 0.15 then return false end
        return fc:getProperties():getAlcohol() / amount + 0.001 >= 0.4
    end
    return item:IsDrainable() and item:getAlcoholPower() >= 4.0
end

---@param item InventoryItem
---@return boolean
---@nodiscard
function CD.isDogBandage(item)
    return item:isCanBandage()
end

CD.TOXIC_REF_SIZE = 1.4
CD.TOXIC_SEVERITY_MIN = 0.6
CD.TOXIC_SEVERITY_MAX = 2.5

---@param animal IsoAnimal
---@return number multiplier applied to the poisoning duration, stress and loyalty penalty; small dogs suffer more
---@nodiscard
function CD.toxicSeverity(animal)
    local dt = animal:getData()
    local size = dt and dt:getSize() or CD.TOXIC_REF_SIZE
    if size <= 0 then
        size = CD.TOXIC_REF_SIZE
    end
    local sev = CD.TOXIC_REF_SIZE / size
    if sev < CD.TOXIC_SEVERITY_MIN then
        sev = CD.TOXIC_SEVERITY_MIN
    elseif sev > CD.TOXIC_SEVERITY_MAX then
        sev = CD.TOXIC_SEVERITY_MAX
    end
    return sev
end
