local CD = CompanionDogs
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 1) then return end

CD.DOB_POLICE_CHANCE = 18
CD.DOB_MILITARY_CHANCE = 22
CD.DOB_HOUSE_CHANCE = 0.5
CD.DOB_STRESS_RELIEF_PER_MIN = 0.010
CD.DOB_RECOIL_FRAC = 0.45
CD.DOB_RELOAD_MULT = 1.15

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
    key = "doberman",
    engineBreed = "doberman",
    typePrefix = "dob",
    nameKey = "IGUI_PD_Breed_doberman",
    limpAnim = true,
    bandSkin = { base = "Doberman", front = "Doberman_BandFront", back = "Doberman_BandBack", cutFront = "Doberman_CutFront", cutBack = "Doberman_CutBack" },
    litter = { 1, 2 },
    xpMult = { scent = 1, combat = 2.0, obedience = 1.5, hunt = 1.2, herding = 1.0 },
    combatPower = 0.52,
    lethalityCurve = { min = 0.30, max = 1.5 },
    canKnockdown = true,
    combatStressMult = 0.25,
    panicThreshold = 0.90,
    geneRange = {
        strength       = { 0.25, 0.45 },
        aggressiveness = { 0.35, 0.55 },
        resistance     = { 0.20, 0.40 },
        stress         = { 0.20, 0.45 },
    },
    -- Os sufixos |db, |dm e |dh sao chave do store de spawn: NUNCA renomear num save vivo.
    spawns = {
        { id = "dobpolice", class = "police", suffix = "|db", breed = "doberman",
          chance = function() return CD.DOB_POLICE_CHANCE * CD.dogSpawnMultiplier() end },
        { id = "dobmil", class = "military", suffix = "|dm", breed = "doberman",
          chance = function() return CD.DOB_MILITARY_CHANCE * CD.dogSpawnMultiplier() end },
        { id = "dobhouse", class = "house", suffix = "|dh", breed = "doberman",
          chance = function() return CD.DOB_HOUSE_CHANCE * CD.dogSpawnMultiplier() end },
    },
})
