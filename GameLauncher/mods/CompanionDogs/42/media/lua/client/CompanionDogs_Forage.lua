CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local HUNT_FORAGE_CATEGORIES = { Animals = true, Insects = true, Tracks = true, DeadAnimals = true }
local cache = {}

local function neglected(dog)
    local h = CD.getHunger(dog)
    local t = dog:getThirst()
    local max = CD.MOODLE_NEGLECT_MAX
    return h >= max or t >= max
end

---Forage vision bonus the nearby companion gives; 0 when it is disloyal or neglected. Cached 500 ms per player.
---@param character IsoPlayer|nil
---@return number
function CD.huntForageBonus(character)
    if not character then return 0 end
    local pn = character:getPlayerNum()
    local nowMs = getTimestampMs()
    local c = cache[pn]
    if c and (nowMs - c.ms) < 500 then return c.bonus end
    local bonus = 0
    local dog = CD.findNearbyCompanion(character, CD.moodleHappyRadius())
    if dog and not CD.isDisloyal(dog) and not neglected(dog) then
        if CD.huntEnabled() and CD.huntForageBonusEnabled() and CD.breedCanHunt(dog) then
            bonus = CD.effectiveForageBonus(dog)
        end
        if CD.getBreed(dog) == "retriever" then
            bonus = bonus + CD.goldenForageVisionExtra()
        end
    end
    cache[pn] = { ms = nowMs, bonus = bonus }
    return bonus
end

local origProf = forageSystem.getProfessionVisionBonus
function forageSystem.getProfessionVisionBonus(character)
    return origProf(character) + CD.huntForageBonus(character)
end

local origCat = forageSystem.getCategoryBonus
function forageSystem.getCategoryBonus(character, catDef)
    local base = origCat(character, catDef)
    if catDef and catDef.name and HUNT_FORAGE_CATEGORIES[catDef.name] then
        local extra = 0
        if CD.huntEnabled() and CD.huntForageBonus(character) > 0 then
            extra = CD.huntForageCategoryBonus()
        end
        if extra > 0 then return base * (1 + extra) end
    end
    return base
end
