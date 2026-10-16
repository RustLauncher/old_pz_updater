local CD = CompanionDogs
if not (CD and CD.DogMoodles and CD.API_VERSION and (CD.API_VERSION or 0) >= 5) then return end
if not CD.frScurryXPMult then return end -- shared file didn't load / registered nothing
if CD.cdfr_scurryMoodleWrapped then return end

local function ratIsCaredFor(rat)
    local h = rat:getHunger()
    local t = rat:getThirst()
    return h < CD.MOODLE_NEGLECT_MAX and t < CD.MOODLE_NEGLECT_MAX
end

local xpOn = {}
local function setScurryXP(player, pn, id, on)
    if not player then return end
    on = on and true or false
    if xpOn[pn] == on then return end
    xpOn[pn] = on
    CD.request("xpboost", nil, { id = id, on = on }, player)
end

local FR_COATS = { "frwhite", "frgrey", "frhooded", "frnaked", "frbrown", "frblue" }

for _, coat in ipairs(FR_COATS) do
    local id = "scurry_" .. coat
    CD.DogMoodles[#CD.DogMoodles + 1] = {
        id = id,
        breed = coat,
        nameKey = "IGUI_PD_Moodle_Scurry",
        descKey = "IGUI_PD_Moodle_Scurry_desc",
        icon = "CD_Moodle_Scurry",
        fg = "CD_MoodScurryFG",
        condition = function(player, rat)
            if not rat or rat:isDead() then return 0 end
            if CD.getBreed(rat) ~= coat then return 0 end
            if CD.isDisloyal(rat) then return 0 end
            if not ratIsCaredFor(rat) then return 0 end
            return 1
        end,
        apply = function(player, rat, elapsedMin)
            setScurryXP(player, player:getPlayerNum(), id, true)
        end,
        onDeactivate = function(player)
            if player then
                setScurryXP(player, player:getPlayerNum(), id, false)
            end
        end,
    }
end

CD.cdfr_scurryMoodleWrapped = true
