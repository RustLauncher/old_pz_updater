local CD = CompanionDogs
if not (CD and CD.DogMoodles and (CD.API_VERSION or 0) >= 2) then return end

CD.LAB_XP_MULT = 1.2

---Hunger and thirst both below MOODLE_NEGLECT_MAX.
---@param dog IsoAnimal
---@return boolean
---@nodiscard
local function dogIsCaredFor(dog)
    local h = dog:getHunger()
    local t = dog:getThirst()
    return h < CD.MOODLE_NEGLECT_MAX and t < CD.MOODLE_NEGLECT_MAX
end

local labPerks
---The perks the soft mouth buff raises, built on the first call.
---@return table perks
---@nodiscard
local function resolveLabPerks()
    if labPerks then return labPerks end
    labPerks = { Perks.Butchering, Perks.SmallBlade }
    return labPerks
end

---Raises the Butchering and Small Blade XP multipliers to LAB_XP_MULT, leaving higher ones alone.
---@param player IsoPlayer|nil
local function applyLabXP(player)
    if not player then return end
    local perks = resolveLabPerks()
    local mult = CD.LAB_XP_MULT
    local maxLvl = CD.SKILL_MAX_LEVEL
    local xp = player:getXp()
    for _, p in ipairs(perks) do
        if xp:getMultiplier(p) < mult then
            xp:addXpMultiplier(p, mult, 1, maxLvl)
        end
    end
end

---Puts the Butchering and Small Blade XP multipliers back to 1 when they are at or below LAB_XP_MULT.
---@param player IsoPlayer|nil
local function clearLabXP(player)
    if not player then return end
    local perks = resolveLabPerks()
    local mult = CD.LAB_XP_MULT
    local maxLvl = CD.SKILL_MAX_LEVEL
    local xp = player:getXp()
    for _, p in ipairs(perks) do
        local cur = xp:getMultiplier(p)
        if cur > 0 and cur <= mult then
            xp:addXpMultiplier(p, 1.0, 1, maxLvl)
        end
    end
end

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "softmouth",
    breed = "labrador",
    nameKey = "IGUI_PD_Moodle_SoftMouth",
    descKey = "IGUI_PD_Moodle_SoftMouth_desc",
    icon = "CD_Moodle_SoftMouth",
    fg = "CD_MoodSoftMouthFG",
    tintR = 0.62, tintG = 0.45, tintB = 0.80,
    ---@param player IsoPlayer
    ---@param dog IsoAnimal|nil
    ---@return integer level 1 to show the moodle, 0 to hide it
    ---@nodiscard
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        if CD.getBreed(dog) ~= "labrador" then return 0 end
        if CD.isDisloyal(dog) then return 0 end
        if CD.isSick(dog) then return 0 end
        if not dogIsCaredFor(dog) then return 0 end
        return 1
    end,
    ---@param player IsoPlayer
    ---@param dog IsoAnimal|nil nil while the moodle lingers with the dog out of range
    ---@param elapsedMin number game minutes since the last call
    apply = function(player, dog, elapsedMin)
        applyLabXP(player)
    end,
    ---@param player IsoPlayer
    onDeactivate = function(player)
        clearLabXP(player)
    end,
}

---Breed name, followed by the dog's name when it has one.
---@param args table|nil
---@return string
---@nodiscard
local function labSubject(args)
    local breed = getText("IGUI_PD_Breed_labrador")
    local name = args and args.name
    if name and name ~= "" then return breed .. " " .. name end
    return breed
end

---Shows the extra find halo to the local player.
---@param args table|nil labextra payload with the item full type and the dog name
local function labExtraHalo(args)
    if not CD.showNotifications() then return end
    local player = getPlayer()
    if not player then return end
    local item = args and args.item
    local disp = item
    local sd = ScriptManager.instance:getItem(item)
    if sd then
        disp = sd:getDisplayName()
    end
    HaloTextHelper.addGoodText(player, getText("IGUI_PD_LabExtra", labSubject(args), disp or ""))
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == CD.MODULE and command == "labextra" then
        labExtraHalo(args)
    end
end)

if not CD.LAB_notifyWrapped then
    CD.LAB_notifyWrapped = true
    local vanillaClientNotify = CD.clientNotify
    ---Takes labextra here and hands every other command to the wrapped notifier.
    ---@param command string
    ---@param args table|nil
    ---@param owner IsoPlayer|nil
    CD.clientNotify = function(command, args, owner)
        if command == "labextra" then
            labExtraHalo(args)
            return
        end
        return vanillaClientNotify(command, args, owner)
    end
end
