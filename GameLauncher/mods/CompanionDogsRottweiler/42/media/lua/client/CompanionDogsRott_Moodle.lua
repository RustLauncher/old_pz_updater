local CD = CompanionDogs
if not (CD and CD.DogMoodles and (CD.API_VERSION or 0) >= 1) then return end

---Hunger and thirst both below MOODLE_NEGLECT_MAX.
---@param dog IsoAnimal
---@return boolean
---@nodiscard
local function dogIsCaredFor(dog)
    local h = dog:getHunger()
    local t = dog:getThirst()
    return h < CD.MOODLE_NEGLECT_MAX and t < CD.MOODLE_NEGLECT_MAX
end

local fighting = {}
local swingStart = {}

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "frontline",
    breed = "rottweiler",
    nameKey = "IGUI_PD_Moodle_FrontLine",
    descKey = "IGUI_PD_Moodle_FrontLine_desc",
    icon = "CD_Moodle_FrontLine",
    fg = "CD_MoodFrontLineFG",
    tintR = 0.78, tintG = 0.24, tintB = 0.20,
    ---@param player IsoPlayer
    ---@param dog IsoAnimal|nil
    ---@return integer level 1 to show the moodle, 0 to hide it
    ---@nodiscard
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        if CD.getBreed(dog) ~= "rottweiler" then return 0 end
        if CD.isDisloyal(dog) then return 0 end
        if CD.isSick(dog) then return 0 end
        if not dogIsCaredFor(dog) then return 0 end
        return 1
    end,
    ---Flags the owner as fighting while the dog is in combat, which gates the endurance refund.
    ---@param player IsoPlayer
    ---@param dog IsoAnimal|nil nil while the moodle lingers with the dog out of range
    apply = function(player, dog)
        fighting[player:getPlayerNum()] = (dog and CD.data(dog).inCombat == true) or nil
    end,
    ---Drops the fighting flag and any swing still being measured.
    ---@param player IsoPlayer
    onDeactivate = function(player)
        if player then
            local pn = player:getPlayerNum()
            fighting[pn] = nil
            swingStart[pn] = nil
        end
    end,
}

---No weapon counts as melee.
---@param weapon HandWeapon|nil
---@return boolean
---@nodiscard
local function isMeleeSwing(weapon)
    if not weapon then return true end
    return not weapon:isRanged()
end

Events.OnWeaponSwing.Add(function(character, weapon)
    -- IsoAnimal herda de IsoPlayer: instanceof "IsoPlayer" NAO filtra bicho.
    if not character or not instanceof(character, "IsoPlayer") or instanceof(character, "IsoAnimal") then return end
    if not character:isLocalPlayer() then return end
    local pn = character:getPlayerNum()
    if not fighting[pn] then return end
    if not isMeleeSwing(weapon) then return end
    local st = character:getStats()
    swingStart[pn] = st:get(CharacterStat.ENDURANCE)
end)

Events.OnPlayerAttackFinished.Add(function(playerObj, weapon)
    if not playerObj or instanceof(playerObj, "IsoAnimal") or not playerObj:isLocalPlayer() then return end
    local pn = playerObj:getPlayerNum()
    local e0 = swingStart[pn]
    if e0 == nil then return end
    swingStart[pn] = nil
    if not fighting[pn] then return end
    if not isMeleeSwing(weapon) then return end
    local st = playerObj:getStats()
    local cost = e0 - st:get(CharacterStat.ENDURANCE)
    if cost > 0 then
        st:add(CharacterStat.ENDURANCE, cost * CD.ROTT_FRONTLINE_REFUND_FRAC)
    end
end)
