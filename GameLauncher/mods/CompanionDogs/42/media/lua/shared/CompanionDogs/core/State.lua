CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---@param animal IsoAnimal
---@return number trust 0 when never set
---@nodiscard
function CD.getTrust(animal)
    return CD.data(animal).trust or 0
end

---TRUST_MAX, or the sandbox tame threshold for a stray when that one is higher.
---@param animal IsoAnimal
---@return number
---@nodiscard
function CD.trustCeiling(animal)
    if CD.isCompanion(animal) then return CD.TRUST_MAX end
    local t = CD.tameThreshold()
    if t > CD.TRUST_MAX then return t end
    return CD.TRUST_MAX
end

---@param animal IsoAnimal
---@param value number clamped to 0..trustCeiling(animal)
function CD.setTrust(animal, value)
    if value < 0 then
        value = 0
    end
    local cap = CD.trustCeiling(animal)
    if value > cap then
        value = cap
    end
    CD.data(animal).trust = value
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.isCompanion(animal)
    return CD.data(animal).companion == true
end

CD.SP_OWNER_MARKER = "cd_sp_owner"

-- Em MP e o username de conexao. Em SP o getUsername e o nome do personagem e muda na morte, entao
-- usa o Steam ID local; o getSteamID do IsoPlayer nao serve, da 0 em SP.
---@param player IsoPlayer|nil
---@return string|nil key nil when player is nil
function CD.ownerKey(player)
    if player == nil then return nil end
    if isServer() or isClient() then
        return player:getUsername()
    end
    local sid = getCurrentUserSteamID()
    if sid == nil or sid == "" then
        sid = CD.SP_OWNER_MARKER
    end
    local pd = CD.playerData(player)
    if pd.spKey == nil then
        local pn = player:getPlayerNum()
        if pn <= 0 then return sid end
        if pd.token ~= nil then return sid end
        local hasDog = false
        if type(pd.companions) == "table" then
            for _ in pairs(pd.companions) do  -- next() nao existe no Kahlua do PZ
                hasDog = true
                break
            end
        end
        if not hasDog and type(pd.kennel) == "table" then
            for _ in pairs(pd.kennel) do
                hasDog = true
                break
            end
        end
        if hasDog then return sid end
        -- O spKey mora no modData do PERSONAGEM, e personagem novo nasce sem ele. Sem consultar o
        -- slot aqui, toda morte do jogador 2 cunha chave nova e deixa os caes do morto sem dono.
        pd.spKey = CD.splitSlotGet(pn)
        if pd.spKey == nil then
            pd.spKey = tostring(getTimestampMs()) .. "-" .. tostring(ZombRand(0, 2147483647))
            -- Grava na hora, e nao so no reparo do lane lento: quem entrasse e morresse dentro do
            -- primeiro minuto de mundo cairia num cunho novo e perderia os caes do mesmo jeito.
            CD.splitSlotBind(pn, pd.spKey)
        end
    end
    local key = sid .. "#" .. pd.spKey
    CD.splitKeyRegister(key)
    return key
end

CD.SPLIT_KEYS = "CompanionDogs_SplitKeys"
CD.splitKeyDone = CD.splitKeyDone or {}

---Records the owner key in the world ModData, once per session.
---@param key string|nil
function CD.splitKeyRegister(key)
    if key == nil or key == "" or CD.splitKeyDone[key] then return end
    CD.splitKeyDone[key] = true
    local s = ModData.getOrCreate(CD.SPLIT_KEYS)
    if s[key] == nil then
        s[key] = true
    end
end

---Whether this owner key was ever registered in this world.
---@param key string|nil
---@return boolean
---@nodiscard
function CD.splitKeySeen(key)
    if key == nil or key == "" then return false end
    return ModData.getOrCreate(CD.SPLIT_KEYS)[key] == true
end

-- O vinculo entre o indice do jogador da tela dividida e o spKey dele, no save e nao na ficha do
-- personagem: e o que sobrevive a morte. A chave e string porque indice calculado nao acha entrada
-- numerica no Kahlua.
CD.SPLIT_SLOTS = "CompanionDogs_SplitSlots"

---The spKey bound to this split-screen player index in the world ModData.
---@param pn integer|nil player index
---@return string|nil spKey
---@nodiscard
function CD.splitSlotGet(pn)
    if pn == nil then return nil end
    local v = ModData.getOrCreate(CD.SPLIT_SLOTS)[tostring(pn)]
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

---@param pn integer|nil player index
---@param spKey string|nil
function CD.splitSlotBind(pn, spKey)
    if pn == nil or spKey == nil or spKey == "" then return end
    ModData.getOrCreate(CD.SPLIT_SLOTS)[tostring(pn)] = spKey
end

---Compares owner keys when the record has one, else the username.
---@param animal IsoAnimal
---@param player IsoPlayer|nil
---@return boolean
function CD.isOwnedBy(animal, player)
    if player == nil then return false end
    local d = CD.data(animal)
    local key = d.ownerKey
    if key ~= nil and key ~= "" then
        return key == CD.ownerKey(player)
    end
    local name = d.ownerName
    return name ~= nil and name ~= "" and name == player:getUsername()
end

---@param animal IsoAnimal
---@return string state STATE_FOLLOW when never set
---@nodiscard
function CD.getState(animal)
    return CD.data(animal).state or CD.STATE_FOLLOW
end

---Auto-feeding and hunting also hold off for FEED_COMMAND_YIELD_MIN game minutes.
---@param animal IsoAnimal
---@param state string one of the CD.STATE_* values
function CD.setState(animal, state)
    local d = CD.data(animal)
    d.state = state
    d.feedYieldUntilMin = CD.worldMinutes() + CD.FEED_COMMAND_YIELD_MIN
end

---Same value as getTrust.
---@param animal IsoAnimal
---@return number
---@nodiscard
function CD.loyalty(animal)
    return CD.getTrust(animal)
end

---@param animal IsoAnimal
---@param value number clamped to 0..trustCeiling(animal)
function CD.setLoyalty(animal, value)
    CD.setTrust(animal, value)
end

---Stress relief left from the last petting: PET_CALM_RELIEF fading to 0 over PET_CALM_DURATION_MIN game minutes.
---@param animal IsoAnimal
---@return number
---@nodiscard
function CD.petCalm(animal)
    local stamp = CD.data(animal).petCalmMin
    if not stamp then return 0 end
    local elapsed = CD.worldMinutes() - stamp
    if elapsed < 0 then
        elapsed = 0
    end
    local c = CD.PET_CALM_RELIEF * (1 - elapsed / CD.PET_CALM_DURATION_MIN)
    if c < 0 then
        c = 0
    end
    return c
end

---Base plus combat stress, minus the petting relief.
---@param animal IsoAnimal
---@return number stress 0..1
---@nodiscard
function CD.getStress(animal)
    local d = CD.data(animal)
    local s = (d.stress or 0) + (d.combatStress or 0) - CD.petCalm(animal)
    if s < 0 then s = 0 elseif s > 1 then s = 1 end
    return s
end

-- Com a guarda de tiro ligada o GOD_MODE zera HUNGER a cada update, e a fome de verdade fica no gunHungerSave.
---@param animal IsoAnimal
---@return number hunger 0..1
---@nodiscard
function CD.getHunger(animal)
    local s = CD.data(animal).gunHungerSave
    if s ~= nil then return s end
    return animal:getHunger()
end

---@param animal IsoAnimal
---@param value number 0..1, clamped
function CD.setStress(animal, value)
    if value < 0 then
        value = 0
    end
    if value > 1 then
        value = 1
    end
    CD.data(animal).stress = value
end

---@param animal IsoAnimal
---@param delta number negative to relieve; the result is clamped to 0..1
function CD.addCombatStress(animal, delta)
    local d = CD.data(animal)
    local v = (d.combatStress or 0) + delta
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    d.combatStress = v
end

CD.CALM_ACCEPTANCE = 100
---Sets the engine's acceptance level of this player to CALM_ACCEPTANCE.
---@param animal IsoAnimal|nil
---@param player IsoPlayer|nil
function CD.calmAcceptance(animal, player)
    if not (animal and player) then return end
    animal:setDebugAcceptance(player, CD.CALM_ACCEPTANCE)
end

CD.BAD_FOOD_TYPES = {
    Candy = true, Sugar = true, Coffee = true, Tea = true,
    Cocoa = true, Chocolate = true, HotPepper = true,
}
CD.BAD_FOOD_NAME_PARTS = {
    "onion", "garlic", "leek", "chive", "shallot", "scallion",
    "grape", "raisin", "chocolate", "cocoa", "coffee", "acorn", "macadamia",
    "avocado", "dough", "gum",
}
