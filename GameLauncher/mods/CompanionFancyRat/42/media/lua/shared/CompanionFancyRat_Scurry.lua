local CD = CompanionDogs
if not (CD and CD.ownerXPBoosts and CD.API_VERSION and (CD.API_VERSION or 0) >= 5) then return end
if CD.cdfr_scurryWrapped then return end

CD.FR_SCURRY_XP_MULT = 1.2

function CD.frScurryXPMult()
    return CD.FR_SCURRY_XP_MULT
end

local FR_SCURRY_PERKS = {}
if Perks then
    if Perks.Nimble then FR_SCURRY_PERKS[#FR_SCURRY_PERKS + 1] = Perks.Nimble end
    if Perks.Lightfoot then FR_SCURRY_PERKS[#FR_SCURRY_PERKS + 1] = Perks.Lightfoot end
    if Perks.Sneak then FR_SCURRY_PERKS[#FR_SCURRY_PERKS + 1] = Perks.Sneak end
end


local FR_COATS = { "frwhite", "frgrey", "frhooded", "frnaked", "frbrown", "frblue" }

local boosts = CD.ownerXPBoosts()
for _, coat in ipairs(FR_COATS) do
    boosts["scurry_" .. coat] = { breed = coat, perks = FR_SCURRY_PERKS, mult = CD.frScurryXPMult }
end

CD.cdfr_scurryWrapped = true
