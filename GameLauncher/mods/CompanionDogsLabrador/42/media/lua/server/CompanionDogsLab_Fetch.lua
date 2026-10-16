local CD = CompanionDogs
if not (CD and CD.onHuntDelivered and (CD.API_VERSION or 0) >= 2) then return end

local EXTRAS = {
    "Base.SmallAnimalBone",
    "Base.ChickenFeather",
    "Base.Twigs",
    "Base.WildEggs",
}

---Hunger and thirst both below MOODLE_NEGLECT_MAX.
---@param dog IsoAnimal
---@return boolean
---@nodiscard
local function caredFor(dog)
    local h = dog:getHunger()
    local t = dog:getThirst()
    return h < CD.MOODLE_NEGLECT_MAX and t < CD.MOODLE_NEGLECT_MAX
end

CD.onHuntDelivered[#CD.onHuntDelivered + 1] = function(animal, owner)
    if not animal or not owner then return end
    if CD.getBreed(animal) ~= "labrador" then return end
    if CD.isDisloyal(animal) or CD.isSick(animal) then return end
    if not caredFor(animal) then return end
    if ZombRand(0, 1000) >= CD.LAB_EXTRA_CHANCE * 1000 then return end

    local sq = owner:getCurrentSquare()
    if not sq then return end
    local ft = EXTRAS[ZombRand(1, #EXTRAS + 1)]
    -- Larga no chao: um AddItem no inventario de um jogador REMOTO nao replica em MP, item de mundo replica.
    sq:AddWorldInventoryItem(ft, 0.5, 0.5, 0.0)
    CD.notifyOwner(owner, "labextra", {
        id = animal:getOnlineID(),
        breed = "labrador",
        name = CD.data(animal).name,
        item = ft,
    })
end
