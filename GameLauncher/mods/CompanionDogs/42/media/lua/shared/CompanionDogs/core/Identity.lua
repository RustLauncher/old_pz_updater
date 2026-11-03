CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---@param animal any
---@return boolean
---@nodiscard
function CD.isDog(animal)
    -- Instanceof e nao `if not animal`: o cao no colo vira AnimalInventoryItem, que nao tem getAnimalType.
    if not instanceof(animal, "IsoAnimal") then return false end
    local t = animal:getAnimalType()
    return t ~= nil and CD.TYPES[t] == true
end

CD.NPC_MARKER_VARS = { "IsHDXStrangerNPC", "NoZombieHandling", "SurvivorNPC" }

local function markedBandit(o)
    return o:getVariableBoolean("Bandit") or o:getVariableString("Bandit") == "true"
end

-- No servidor a engine ignora setVariable em zumbi e o Bandits nunca grava o brain nele: a ficha so existe no cluster.
local function clusterBrain(o)
    if not GetBanditClusterData then return nil end
    local id = BanditUtils.GetZombieID(o)
    return GetBanditClusterData(id)[id]
end

local function friendlyBrain(brain)
    if brain.loyal or brain.recruited then return true end
    local prog = brain.program
    if prog and prog.stage == "Surrender" then return true end
    return not (brain.hostile or brain.hostileP)
end

local function friendlyBandit(o, onServer)
    if onServer then
        local brain = clusterBrain(o)
        return brain ~= nil and friendlyBrain(brain)
    end
    if not markedBandit(o) then return false end
    local brain = o:getModData().brain
    return brain == nil or friendlyBrain(brain)
end

---Bandits NPC: the server reads its cluster data, other VMs the Bandit variable.
---@param o IsoZombie
---@return boolean
---@nodiscard
function CD.isBanditNPC(o)
    if isServer() then return clusterBrain(o) ~= nil end
    return markedBandit(o)
end

---Loyal, recruited, surrendering or not hostile. Off the server a marked NPC whose brain has not arrived counts as friendly.
---@param o IsoZombie
---@return boolean
---@nodiscard
function CD.isFriendlyBanditNPC(o)
    return friendlyBandit(o, isServer())
end

---A known NPC mod marker (read off the server only) or a friendly Bandits NPC.
---@param o IsoZombie|nil
---@return boolean
---@nodiscard
function CD.isFriendlyNPC(o)
    if not o then return false end
    local onServer = isServer()
    if not onServer then
        for i = 1, #CD.NPC_MARKER_VARS do
            local name = CD.NPC_MARKER_VARS[i]
            if o:getVariableBoolean(name) or o:getVariableString(name) == "true" then return true end
        end
    end
    return friendlyBandit(o, onServer)
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return table the CompanionDogs subtable of the ModData, created on first call
function CD.data(animal)
    if CD._perfLv and CD._perfLv > 1 then
        CD._perfCnt["call.getModData"] = (CD._perfCnt["call.getModData"] or 0) + 1
    end
    local md = animal:getModData()
    md.CompanionDogs = md.CompanionDogs or {}
    return md.CompanionDogs
end

---Syncs the animal's ModData over the network; a value that is not an IsoAnimal is ignored.
---@param animal any
function CD.transmit(animal)
    if instanceof(animal, "IsoAnimal") then
        animal:transmitModData()
    end
end

---@param animal IsoAnimal
---@param d table the already resolved CD.data(animal)
---@param on boolean
function CD.setInCombat(animal, d, on)
    on = on and true or false
    if (d.inCombat and true or false) == on then return end
    d.inCombat = on
    CD.transmit(animal)
end

---@param player IsoPlayer
---@return table the CompanionDogs subtable of the player's ModData, created on first call
function CD.playerData(player)
    if CD._perfLv and CD._perfLv > 1 then
        CD._perfCnt["call.playerModData"] = (CD._perfCnt["call.playerModData"] or 0) + 1
    end
    local md = player:getModData()
    md.CompanionDogs = md.CompanionDogs or {}
    return md.CompanionDogs
end

-- pd.dismissed marca "sem cao ativo por escolha" e so vale enquanto pd.token e nil. Toda escrita de
-- token passa por aqui: dispensa que sobrevivesse a uma promocao deixaria o jogador sem companheiro.
---@param pd table the player's CompanionDogs mod data
---@param token number
---@param name string|nil
function CD.setActiveDog(pd, token, name)
    pd.token = token
    pd.name = name
    pd.dismissed = nil
end

---Every dog bonded to the player, loaded or not.
---@param player IsoPlayer
---@return integer
---@nodiscard
function CD.companionCount(player)
    local c = CD.playerData(player).companions
    if type(c) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(c) do n = n + 1 end
    return n
end

---@param player IsoPlayer
---@return boolean false when the sandbox sets no limit
---@nodiscard
function CD.atCompanionLimit(player)
    local m = CD.maxCompanions()
    if not m or m <= 0 then return false end
    return CD.companionCount(player) >= m
end

---Whether the active token still leads to a dog: one loaded, the stash record or the carried one; false without a token.
---@param player IsoPlayer
---@return boolean
function CD.hasRecoverableCompanion(player)
    local pd = CD.playerData(player)
    if pd.token == nil then return false end
    if CD.getCompanionAnimal(player) ~= nil then return true end
    local rec = pd.stash
    if rec ~= nil and rec.data ~= nil and rec.data.companionToken == pd.token then return true end
    local car = pd.carried
    return car ~= nil and car.data ~= nil and car.data.companionToken == pd.token
end

---Searches the inventory, and bags nested up to six deep, for a carried dog with this token.
---@param player IsoPlayer|nil
---@param tok number|nil companion token
---@return boolean
function CD.carriedTokenAnywhere(player, tok)
    if not player or tok == nil then return false end
    local function scan(cont, depth)
        if not cont or depth > 6 then return false end
        local items = cont:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it then
                if instanceof(it, "AnimalInventoryItem") then
                    local a = it:getAnimal()
                    if a and CD.isDog(a) and CD.isOwnedBy(a, player) and CD.data(a).companionToken == tok then return true end
                elseif instanceof(it, "InventoryContainer") then
                    if scan(it:getInventory(), depth + 1) then return true end
                end
            end
        end
        return false
    end
    return scan(player:getInventory(), 0)
end

---Recursive copy of a table; any other value comes back as is.
---@param t any
---@return any
---@nodiscard
function CD.deepCopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = CD.deepCopy(v) end
    return r
end

---Stamps a uid on the record when it has none.
---@param d table|nil companion ModData or a stored copy of it
---@return string|nil uid nil when d is not a table
function CD.ensureUidData(d)
    if type(d) ~= "table" then return nil end
    if not d.uid then
        d.uid = tostring(getTimestampMs()) .. "-" .. tostring(ZombRand(0, 2147483647))
    end
    return d.uid
end

---@param animal IsoAnimal
---@return string uid
function CD.ensureUid(animal)
    return CD.ensureUidData(CD.data(animal))
end

---@param animal any
---@return string|nil sex "female", "male" or "pup", read from the animal type; nil otherwise
---@nodiscard
function CD.animalSex(animal)
    local t = instanceof(animal, "IsoAnimal") and animal:getAnimalType()
    if not t then return nil end
    if string.sub(t, -6) == "female" then return "female" end
    if string.sub(t, -4) == "male" then return "male" end
    if string.sub(t, -3) == "pup" then return "pup" end
    return nil
end

---Hunger and thirst both under BREED_NEED_CRITICAL.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.isWellFed(animal)
    local h = CD.getHunger(animal)
    local t = animal:getThirst()
    local max = CD.BREED_NEED_CRITICAL
    return h < max and t < max
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.isPregnant(animal)
    return CD.data(animal).pregnant == true
end

---Pregnant and inside the last BREED_NEARTERM_FRAC of the gestation.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.isNearTerm(animal)
    local d = CD.data(animal)
    if not d.pregnant or not d.gestEndMin then return false end
    return (d.gestEndMin - CD.worldMinutes()) <= CD.gestationMinutes() * CD.BREED_NEARTERM_FRAC
end

---Translated pregnancy label; does not check that the dog is pregnant.
---@param animal IsoAnimal
---@return string
---@nodiscard
function CD.pregnancyLabel(animal)
    return CD.isNearTerm(animal) and getText("IGUI_PD_NearTerm") or getText("IGUI_PD_Pregnant")
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.isPuppy(animal)
    return CD.data(animal).isPup == true
end

---Translated age word: the species word for a young one on a pup, Adult otherwise.
---@param animal IsoAnimal
---@return string
---@nodiscard
function CD.ageNoun(animal)
    return CD.isPuppy(animal) and CD.youngNoun(animal) or getText("IGUI_PD_Adult")
end

---Translated sex word, marked sterile for a male of a sterile breed; a pup uses its stored sex.
---@param animal IsoAnimal
---@return string|nil nil when the sex is unknown
---@nodiscard
function CD.sexNoun(animal)
    local s = CD.animalSex(animal)
    if s == "pup" then
        s = CD.data(animal).sex
    end
    if s == "female" then return getText("IGUI_PD_Sex_Female") end
    if s == "male" then
        if CD.breedSterileMale(CD.getBreed(animal)) then
            return getText("IGUI_PD_Sex_Male") .. " (" .. getText("IGUI_PD_Sterile") .. ")"
        end
        return getText("IGUI_PD_Sex_Male")
    end
    return nil
end

-- Sem servidor a engine nao aloca onlineID de animal (IsoAnimal.init, gate GameServer.server): em SP todos compartilham o mesmo.
---@param animal IsoAnimal
---@return integer key online id in MP, animal id in SP
---@nodiscard
function CD.animKey(animal)
    if isServer() or isClient() then return animal:getOnlineID() end
    return animal:getAnimalID()
end
