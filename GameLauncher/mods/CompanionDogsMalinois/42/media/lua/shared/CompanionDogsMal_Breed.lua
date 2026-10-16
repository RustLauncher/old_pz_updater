local CD = CompanionDogs
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 11) then return end

CD.MAL_POLICE_CHANCE = 15
CD.MAL_MILITARY_CHANCE = 15
CD.MAL_HOUSE_CHANCE = 0.5

-- Mesma regra do addon Doberman: registerBuildingClass fica com o primeiro que chegar, entao os dois
-- addons podem declarar "military" com ou sem o outro carregado.
local MILITARY_ROOM_KEYS = { "armory", "armoury", "barracks", "military", "checkpoint", "guardpost", "bunker" }
CD.registerBuildingClass("military", function(def)
    if not def then return false end
    if def:isResidential() then return false end
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        local rd = rooms:get(i)
        local nm = rd and rd:getName()
        if nm then
            nm = string.lower(nm)
            for _, k in ipairs(MILITARY_ROOM_KEYS) do
                if string.find(nm, k, 1, true) then return true end
            end
        end
    end
    return false
end, { skipUrbanGate = true })

CD.registerBreed({
    key = "malinois",
    engineBreed = "malinois",
    typePrefix = "mal",
    nameKey = "IGUI_PD_Breed_malinois",
    limpAnim = true,
    bandSkin = { base = "Malinois", front = "Malinois_BandFront", back = "Malinois_BandBack", cutFront = "Malinois_CutFront", cutBack = "Malinois_CutBack" },
    litter = { 1, 2 },
    xpMult = { scent = 2.0, combat = 1.5, obedience = 1.2, hunt = 1.0, herding = 1.0 },
    combatPower = 0.48,
    lethalityCurve = { min = 0.40, max = 1.3 },
    canKnockdown = true,
    combatStressMult = 0.25,
    panicThreshold = 0.90,
    geneRange = {
        strength       = { 0.30, 0.50 },
        aggressiveness = { 0.30, 0.50 },
        resistance     = { 0.30, 0.50 },
        stress         = { 0.20, 0.50 },
    },
    -- Os sufixos |ml, |mm e |mh sao chave do store de spawn: NUNCA renomear num save vivo.
    spawns = {
        { id = "malpolice", class = "police", suffix = "|ml", breed = "malinois",
          chance = function() return CD.MAL_POLICE_CHANCE * CD.dogSpawnMultiplier() end },
        { id = "malmil", class = "military", suffix = "|mm", breed = "malinois",
          chance = function() return CD.MAL_MILITARY_CHANCE * CD.dogSpawnMultiplier() end },
        { id = "malhouse", class = "house", suffix = "|mh", breed = "malinois",
          chance = function() return CD.MAL_HOUSE_CHANCE * CD.dogSpawnMultiplier() end },
    },
})
