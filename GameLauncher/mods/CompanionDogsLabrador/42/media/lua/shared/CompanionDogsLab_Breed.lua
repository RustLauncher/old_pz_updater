local CD = CompanionDogs
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 2) then return end

CD.LAB_HOUSE_RARITY = 3
CD.LAB_OUTDOORS_CHANCE = 20
CD.LAB_EXTRA_CHANCE = 0.60

local OUTDOORS_ROOM_KEYS = { "hunting", "camping", "fishing", "boathouse", "ranger", "woodshed" }
CD.registerBuildingClass("outdoors", function(def)
    if not def then return false end
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        local rd = rooms:get(i)
        local nm = rd and rd:getName()
        if nm then
            nm = string.lower(nm)
            for _, k in ipairs(OUTDOORS_ROOM_KEYS) do
                if string.find(nm, k, 1, true) then return true end
            end
        end
    end
    return false
end, { skipUrbanGate = true })

CD.registerBreed({
    key = "labrador",
    engineBreed = "labrador",
    typePrefix = "lab",
    nameKey = "IGUI_PD_Breed_labrador",
    limpAnim = true,
    bandSkin = { base = "Labrador", front = "Labrador_BandFront", back = "Labrador_BandBack", cutFront = "Labrador_CutFront", cutBack = "Labrador_CutBack" },
    litter = { 1, 3 },
    xpMult = { scent = 1.2, combat = 1, obedience = 1.5, hunt = 2.0, herding = 1.0 },
    combatPower = 0.30,
    lethalityCurve = { min = 0.40, max = 1.3 },
    canKill = true,
    canKnockdown = false,
    combatStressMult = 0.7,
    panicThreshold = 0.80,
    geneRange = {
        strength       = { 0.25, 0.45 },
        aggressiveness = { 0.10, 0.25 },
        resistance     = { 0.25, 0.45 },
        stress         = { 0.30, 0.60 },
    },
    huntFetchLevel = 0,
    huntDeliverTimeoutMin = 15,
    -- Os sufixos |lb e |lk sao chave do store de spawn: NUNCA renomear num save vivo.
    spawns = {
        { id = "labhouse", class = "house", suffix = "|lb", breed = "labrador",
          chance = function() return CD.strayChancePerHouse() / CD.LAB_HOUSE_RARITY end },
        { id = "labout", class = "outdoors", suffix = "|lk", breed = "labrador",
          chance = function() return CD.LAB_OUTDOORS_CHANCE * CD.dogSpawnMultiplier() end },
    },
})
