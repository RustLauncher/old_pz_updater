local CD = CompanionDogs
if not (CD and CD.onUpkeepStress and (CD.API_VERSION or 0) >= 3) then return end

CD.onUpkeepStress[#CD.onUpkeepStress + 1] = function(animal)
    if CD.getBreed(animal) ~= "pug" then return 0 end
    return CD.pugHeatRatio(animal) * CD.PUG_HEAT_STRESS_MAX
end
