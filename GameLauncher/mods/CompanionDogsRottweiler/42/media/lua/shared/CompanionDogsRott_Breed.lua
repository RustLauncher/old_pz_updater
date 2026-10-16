local CD = CompanionDogs
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 1) then return end

CD.ROTT_INDUSTRIAL_CHANCE = 30
CD.ROTT_HOUSE_RARITY = 6
CD.ROTT_FRONTLINE_REFUND_FRAC = 0.35

-- sem "storage" puro: ele casa a garagem das casas (garagestorage) e o fundo de quase toda loja
local INDUSTRIAL_ROOM_KEYS = { "warehouse", "storageunit", "factory", "industrial", "workshop", "junkyard", "scrapyard", "loadingbay", "shipping" }
CD.registerBuildingClass("industrial", function(def)
    if not def then return false end
    if def:isResidential() then return false end
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        local rd = rooms:get(i)
        local nm = rd and rd:getName()
        if nm then
            nm = string.lower(nm)
            for _, k in ipairs(INDUSTRIAL_ROOM_KEYS) do
                if string.find(nm, k, 1, true) then return true end
            end
        end
    end
    return false
end, { skipUrbanGate = true })

CD.registerBreed({
    key = "rottweiler",
    engineBreed = "rottweiler",
    typePrefix = "rott",
    nameKey = "IGUI_PD_Breed_rottweiler",
    limpAnim = true,
    bandSkin = { base = "Rottweiler", front = "Rottweiler_BandFront", back = "Rottweiler_BandBack", cutFront = "Rottweiler_CutFront", cutBack = "Rottweiler_CutBack" },
    litter = { 1, 2 },
    xpMult = { scent = 1.5, combat = 2.0, obedience = 1, hunt = 1, herding = 1.2 },
    combatPower = 0.6,
    lethalityCurve = { min = 0.40, max = 1.3 },
    canKnockdown = true,
    combatStressMult = 0.20,
    panicThreshold = 0.90,
    geneRange = {
        strength       = { 0.30, 0.50 },
        aggressiveness = { 0.30, 0.50 },
        resistance     = { 0.30, 0.50 },
        stress         = { 0.20, 0.50 },
    },
    -- Os sufixos |rw e |r sao chave do store de spawn: NUNCA renomear num save vivo.
    spawns = {
        { id = "rottind", class = "industrial", suffix = "|rw", breed = "rottweiler",
          chance = function() return CD.ROTT_INDUSTRIAL_CHANCE * CD.dogSpawnMultiplier() end },
        { id = "rotthouse", class = "house", suffix = "|r", breed = "rottweiler",
          chance = function() return CD.strayChancePerHouse() / CD.ROTT_HOUSE_RARITY end },
    },
})
