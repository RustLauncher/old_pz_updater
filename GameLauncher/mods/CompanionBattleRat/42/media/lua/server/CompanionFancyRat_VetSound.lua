if CompanionDogs and CompanionDogs.emitSound and not CompanionDogs.cdfr_vetSoundWrapped then
    local CD = CompanionDogs
    local vanillaEmitSound = CD.emitSound
    function CD.emitSound(animal, sound)
        if sound == "CDDogWhine" and CD.getSpecies and CD.getSpecies(animal) == "fr" then
            sound = "CDFRChatter"
        end
        return vanillaEmitSound(animal, sound)
    end
    CD.cdfr_vetSoundWrapped = true
end
