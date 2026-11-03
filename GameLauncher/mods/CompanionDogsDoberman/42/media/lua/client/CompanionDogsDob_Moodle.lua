-- NAO usar weapon:setHitChance/setAimingTime/setRecoilDelay/setReloadTime: HandWeapon.save()
-- serializa esses campos, entao ficariam gravados no item se o player deslogasse com o buff ativo.
-- E getCombatConfig() e singleton de processo (buffaria todo player do cliente em MP).
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

local steady = {}

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "steadyaim",
    breed = "doberman",
    nameKey = "IGUI_PD_Moodle_SteadyAim",
    descKey = "IGUI_PD_Moodle_SteadyAim_desc",
    icon = "CD_Moodle_SteadyAim",
    fg = "CD_MoodSteadyAimFG",
    tintR = 0.35, tintG = 0.55, tintB = 0.78,
    ---@param player IsoPlayer
    ---@param dog IsoAnimal|nil
    ---@return integer level 1 to show the moodle, 0 to hide it
    ---@nodiscard
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        if CD.getBreed(dog) ~= "doberman" then return 0 end
        if CD.isDisloyal(dog) then return 0 end
        if CD.isSick(dog) then return 0 end
        if not dogIsCaredFor(dog) then return 0 end
        return 1
    end,
    ---Arms the steady aim buffs and takes stress off the player.
    ---@param player IsoPlayer
    ---@param dog IsoAnimal|nil nil while the moodle lingers with the dog out of range
    ---@param elapsedMin number game minutes since the last call
    apply = function(player, dog, elapsedMin)
        steady[player:getPlayerNum()] = true
        local n = CD.DOB_STRESS_RELIEF_PER_MIN * elapsedMin
        if n <= 0 then return end
        local st = player:getStats()
        st:remove(CharacterStat.STRESS, n)
    end,
    ---Disarms the steady aim buffs.
    ---@param player IsoPlayer
    onDeactivate = function(player)
        if player then
            steady[player:getPlayerNum()] = nil
        end
    end,
}

---@param weapon HandWeapon|nil
---@return boolean
---@nodiscard
local function isRangedShot(weapon)
    if not weapon then return false end
    return weapon:isRanged()
end

-- IsoAnimal herda de IsoPlayer: instanceof "IsoPlayer" NAO filtra bicho.
---@param c IsoGameCharacter|nil
---@return boolean
---@nodiscard
local function isRealLocalPlayer(c)
    if not c or not instanceof(c, "IsoPlayer") or instanceof(c, "IsoAnimal") then return false end
    return c:isLocalPlayer()
end

Events.OnPlayerAttackFinished.Add(function(playerObj, weapon)
    if not isRealLocalPlayer(playerObj) then return end
    if not steady[playerObj:getPlayerNum()] then return end
    if not isRangedShot(weapon) then return end
    local frac = CD.DOB_RECOIL_FRAC
    if frac <= 0 then return end
    local rd = playerObj:getRecoilDelay()
    if rd > 0 then
        playerObj:setRecoilDelay(rd * (1 - frac))
    end
end)

if not CD.DOB_reloadWrapped then
    CD.DOB_reloadWrapped = true
    local vanillaSetReloadSpeed = ISReloadWeaponAction.setReloadSpeed
    ---Vanilla reload speed, then scaled by DOB_RELOAD_MULT while steady aim is on.
    ---@param character IsoGameCharacter
    ---@param rack boolean racking the firearm instead of loading it
    ISReloadWeaponAction.setReloadSpeed = function(character, rack)
        vanillaSetReloadSpeed(character, rack)
        if not isRealLocalPlayer(character) then return end
        if not steady[character:getPlayerNum()] then return end
        local mult = CD.DOB_RELOAD_MULT
        if mult == 1 then return end
        local cur = character:getVariableFloat("ReloadSpeed", 1.0)
        character:setVariable("ReloadSpeed", cur * mult)
    end
end
