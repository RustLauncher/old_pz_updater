local CD = CompanionDogs
if not (CD and CD.DogMoodles and (CD.API_VERSION or 0) >= 3) then return end

---Hunger and thirst both below MOODLE_NEGLECT_MAX.
---@param dog IsoAnimal
---@return boolean
---@nodiscard
local function dogIsCaredFor(dog)
    local h = dog:getHunger()
    local t = dog:getThirst()
    return h < CD.MOODLE_NEGLECT_MAX and t < CD.MOODLE_NEGLECT_MAX
end

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "shadow",
    breed = "pug",
    nameKey = "IGUI_PD_Moodle_Shadow",
    descKey = "IGUI_PD_Moodle_Shadow_desc",
    icon = "CD_Moodle_Shadow",
    fg = "CD_MoodShadowFG",
    tintR = 0.92, tintG = 0.52, tintB = 0.68,
    ---Also hidden while the air at the dog is in the pug heat band.
    ---@param player IsoPlayer
    ---@param dog IsoAnimal|nil
    ---@return integer level 1 to show the moodle, 0 to hide it
    ---@nodiscard
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        if CD.getBreed(dog) ~= "pug" then return 0 end
        if CD.isDisloyal(dog) then return 0 end
        if CD.isSick(dog) then return 0 end
        if not dogIsCaredFor(dog) then return 0 end
        if CD.pugHeatRatio(dog) > 0 then return 0 end
        return 1
    end,
    ---Relieves mood at PUG_RELIEF_MULT times the moodle rate and takes stress off the player.
    ---@param player IsoPlayer
    ---@param dog IsoAnimal|nil nil while the moodle lingers with the dog out of range
    ---@param elapsedMin number game minutes since the last call
    apply = function(player, dog, elapsedMin)
        CD.relieveMood(player, CD.moodleReliefPerMin() * CD.PUG_RELIEF_MULT * elapsedMin)
        local n = CD.PUG_STRESS_PER_MIN * elapsedMin
        if n <= 0 then return end
        local stats = player:getStats()
        stats:remove(CharacterStat.STRESS, n)
    end,
}
