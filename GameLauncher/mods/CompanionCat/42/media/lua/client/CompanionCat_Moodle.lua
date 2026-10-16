local CD = CompanionDogs
if not (CD and CD.DogMoodles and (CD.API_VERSION or 0) >= 5) then return end
if not (CompanionCat and CompanionCat.COAT_KEYS) then return end

local MOODLES = CD.CompanionMoodles or CD.DogMoodles
local CATS = CompanionCat.COAT_KEYS

-- Abaixo de 0.5 e obrigatorio: doVisionCheck compara 1 - lightLevelPenalty com o corte de
-- 50 e, batendo, joga a visao em 1.5 tile. 0.5 pra cima desliga a feature em silencio.
local CAT_DARKNESS_CUT = 0.40
local CAT_DARKNESS_FLOOR = 0.15

---Hunger and thirst both below MOODLE_NEGLECT_MAX.
---@param cat IsoAnimal
---@return boolean
---@nodiscard
local function catIsCaredFor(cat)
    local h = cat:getHunger()
    local t = cat:getThirst()
    return h < CD.MOODLE_NEGLECT_MAX and t < CD.MOODLE_NEGLECT_MAX
end

MOODLES[#MOODLES + 1] = {
    id = "cateye",
    breed = "cat",
    nameKey = "IGUI_PD_Moodle_CatEye",
    descKey = "IGUI_PD_Moodle_CatEye_desc",
    icon = "CD_Moodle_CatEye",
    fg = "CD_MoodCatEyeFG",
    tintR = 0.24, tintG = 0.26, tintB = 0.50,
    ---@param player IsoPlayer
    ---@param cat IsoAnimal|nil
    ---@return integer level 1 to show the moodle, 0 to hide it
    ---@nodiscard
    condition = function(player, cat)
        if not cat or cat:isDead() then return 0 end
        if not CATS[CD.getBreed(cat)] then return 0 end
        if CD.isDisloyal(cat) then return 0 end
        if CD.isSick(cat) then return 0 end
        if not catIsCaredFor(cat) then return 0 end
        return 1
    end,
}

local cache = {}

---Whether the nearest companion in moodle range is a loyal, healthy, fed and watered cat, cached 500 ms per player.
---@param character IsoPlayer
---@return boolean
---@nodiscard
local function catNearby(character)
    local pn = character:getPlayerNum()
    local nowMs = getTimestampMs()
    local c = cache[pn]
    if c and (nowMs - c.ms) < 500 then return c.on end
    local on = false
    local cat = CD.findNearbyCompanion(character, CD.moodleHappyRadius())
    if cat and CATS[CD.getBreed(cat)] and not CD.isDisloyal(cat) and not CD.isSick(cat)
       and catIsCaredFor(cat) then
        on = true
    end
    cache[pn] = { ms = nowMs, on = on }
    return on
end

local origDark = forageSystem.getDarknessEffectReduction
---With a fit cat near, the darkness penalty multiplier drops to CAT_DARKNESS_CUT of vanilla, never below CAT_DARKNESS_FLOOR.
---@param character IsoPlayer
---@return number multiplier on the darkness penalty, 1 being the full penalty
---@nodiscard
function forageSystem.getDarknessEffectReduction(character)
    local v = origDark(character)
    if not catNearby(character) then return v end
    v = v * CAT_DARKNESS_CUT
    if v < CAT_DARKNESS_FLOOR then
        v = CAT_DARKNESS_FLOOR
    end
    return v
end
