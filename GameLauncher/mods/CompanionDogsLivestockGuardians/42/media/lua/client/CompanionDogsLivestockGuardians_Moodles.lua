local CD = CompanionDogs
if not (CD and (CD.API_VERSION or 0) >= 5
    and type(CD.DogMoodles) == "table"
    and type(CD.getBreed) == "function") then return end

local function dogIsCaredFor(dog)
    local hunger = dog and (dog:getHunger() or 0) or 0
    local thirst = dog and (dog:getThirst() or 0) or 0
    return hunger < CD.MOODLE_NEGLECT_MAX and thirst < CD.MOODLE_NEGLECT_MAX
end

local function addCourage(breed)
    CD.DogMoodles[#CD.DogMoodles + 1] = {
        id = "cdlg_courage_" .. breed,
        breed = breed,
        nameKey = "IGUI_PD_Moodle_GSCourage",
        descKey = "IGUI_PD_Moodle_GSCourage_desc",
        icon = "CD_Moodle_GSCourage",
        fg = "CD_MoodCourageFG",
        tintR = 0.93,
        tintG = 0.70,
        tintB = 0.20,
        condition = function(player, dog)
            if not dog or dog:isDead() then return 0 end
            if CD.getBreed(dog) ~= breed then return 0 end
            if CD.isDisloyal(dog) then return 0 end
            if CD.isSick(dog) then return 0 end
            if not dogIsCaredFor(dog) then return 0 end
            return 1
        end,
        apply = function(player, dog, elapsedMin)
            local amount = CD.couragePanicReliefPerMin() * elapsedMin
            if amount <= 0 then return end
            local stats = player and player:getStats()
            if stats then stats:remove(CharacterStat.PANIC, amount) end
        end,
    }
end

local function addRegisteredCourage(breed)
    if CD.BREEDS and CD.BREEDS[breed] then addCourage(breed) end
end

addRegisteredCourage("anatolianshepherd")
addRegisteredCourage("greaterswissmountaindog")
