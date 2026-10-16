-- Retained Dr Pepper fluids keep their proportional consumption effects while
-- the artwork mod is disabled. No Core, sprite, icon or loot code is imported.
if getActivatedMods():contains('DrPepperFridge') then return end
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISTakeWaterAction"

ViniRecoveryDrPepperDrinks = ViniRecoveryDrPepperDrinks or {}
local M = ViniRecoveryDrPepperDrinks
M.CAN_VOLUME = 0.3
M.defaults = {
    DrinkThirst = 9, DrinkHunger = 3.6, DietDrinkHunger = 0,
    DrinkFatigue = 10, DrinkStress = 20,
    DrinkUnhappiness = 20, DrinkBoredom = 0,
    RegularLootMultiplier = 1, DietLootMultiplier = 1,
}

function M.option(key)
    local options = SandboxVars and SandboxVars.DrPepperFridge
    local value = options and tonumber(options[key])
    if not value or value ~= value then value = M.defaults[key] or 0 end
    return math.max(0, math.min(100, value))
end

-- Quantities follow the fluid, not the can's item ID. Diluting or transferring a
-- drink therefore cannot duplicate its bonuses, and a water refill grants none.
function M.amounts(container)
    if not container or container:isEmpty() then return 0, 0 end
    local regular, diet = Fluid.Get("DrPepperRegular"), Fluid.Get("DrPepperDiet")
    local amount = container:getAmount()
    return regular and amount * container:getRatioForFluid(regular) or 0,
        diet and amount * container:getRatioForFluid(diet) or 0
end

-- Shared calculation for consumption and UI, in the game's familiar points.
function M.effectsForVolumes(regularVolume, dietVolume)
    local regular = math.max(0, regularVolume) / M.CAN_VOLUME
    local diet = math.max(0, dietVolume) / M.CAN_VOLUME
    local fraction = regular + diet
    return {
        Thirst = M.option("DrinkThirst") * fraction,
        Hunger = M.option("DrinkHunger") * regular + M.option("DietDrinkHunger") * diet,
        Fatigue = M.option("DrinkFatigue") * fraction,
        Stress = M.option("DrinkStress") * fraction,
        Unhappiness = M.option("DrinkUnhappiness") * fraction,
        Boredom = M.option("DrinkBoredom") * fraction,
    }
end

local function reduce(stats, name, amount, getter, setter, body)
    if amount <= 0 then return end
    if CharacterStat and CharacterStat[name] and stats.remove then
        stats:remove(CharacterStat[name], amount)
    elseif getter and setter and body[getter] and body[setter] then
        -- Older B42 builds use the legacy Stats/BodyDamage accessors.
        body[setter](body, math.max(0, body[getter](body) - amount))
    end
end

function M.apply(character, regularVolume, dietVolume)
    if getActivatedMods():contains('DrPepperFridge') then return end
    if not character or (isClient and isClient()) then return end
    regularVolume, dietVolume = math.max(0, regularVolume), math.max(0, dietVolume)
    if regularVolume + dietVolume <= 0 then return end
    local effects = M.effectsForVolumes(regularVolume, dietVolume)
    local stats = character:getStats()
    local body = character:getBodyDamage()
    reduce(stats, "THIRST", effects.Thirst / 100,
        "getThirst", "setThirst", stats)
    reduce(stats, "HUNGER", effects.Hunger / 100,
        "getHunger", "setHunger", stats)
    reduce(stats, "FATIGUE", effects.Fatigue / 100,
        "getFatigue", "setFatigue", stats)
    reduce(stats, "STRESS", effects.Stress / 100,
        "getStress", "setStress", stats)
    reduce(stats, "UNHAPPINESS", effects.Unhappiness,
        "getUnhappynessLevel", "setUnhappynessLevel", body)
    reduce(stats, "BOREDOM", effects.Boredom,
        "getBoredomLevel", "setBoredomLevel", body)
    if isServer and isServer() and syncPlayerStats and SyncPlayerStatsPacket
        and SyncPlayerStatsPacket.getBitMaskForStat and CharacterStat then
        local mask = 0
        for _, name in ipairs({ "THIRST", "HUNGER", "FATIGUE", "STRESS", "UNHAPPINESS", "BOREDOM" }) do
            mask = mask + SyncPlayerStatsPacket.getBitMaskForStat(CharacterStat[name])
        end
        if mask > 0 then syncPlayerStats(character, mask) end
    end
end

function M.install()
    if M.wrappedUpdateEat == ISDrinkFluidAction.updateEat then return end
    local previous = ISDrinkFluidAction.updateEat
    M.wrappedUpdateEat = function(self, delta)
        if isClient and isClient() then return previous(self, delta) end
        local beforeRegular, beforeDiet = M.amounts(self.fluidContainer)
        local result = previous(self, delta)
        if beforeRegular > 0 or beforeDiet > 0 then
            local afterRegular, afterDiet = M.amounts(self.fluidContainer)
            M.apply(self.character,
                math.max(0, beforeRegular - afterRegular),
                math.max(0, beforeDiet - afterDiet))
        end
        return result
    end
    ISDrinkFluidAction.updateEat = M.wrappedUpdateEat
end

M.install()

-- Neutral script hunger would otherwise select the vanilla water-drinking
-- duration. Keep these cans at the native soda duration instead.
local previousNew = ISDrinkFluidAction.new
if M.wrappedNew ~= previousNew then
    M.wrappedNew = function(self, character, item, percentage)
        local action = previousNew(self, character, item, percentage)
        local id = action.item and action.item:getFullType()
        if (id == "DrPepper.CanRegular" or id == "DrPepper.CanDiet") and action.maxTime == 460 then
            local regular, diet = M.amounts(action.fluidContainer)
            if regular + diet > 0 then action.maxTime = 232 end
        end
        return action
    end
    ISDrinkFluidAction.new = M.wrappedNew
end

-- Preserve the same behavior if a player pours the soda into a world fluid
-- container and drinks from it. Filling another vessel never grants benefits.
local previousTransfer = ISTakeWaterAction.transferFluid
if M.wrappedTransferFluid ~= previousTransfer then
    M.wrappedTransferFluid = function(self, amount)
        if self.item or (isClient and isClient()) or not self.waterObject
            or not self.waterObject.getFluidContainer then
            return previousTransfer(self, amount)
        end
        local container = self.waterObject:getFluidContainer()
        local beforeRegular, beforeDiet = M.amounts(container)
        local result = previousTransfer(self, amount)
        if beforeRegular > 0 or beforeDiet > 0 then
            local afterRegular, afterDiet = M.amounts(container)
            M.apply(self.character, math.max(0, beforeRegular - afterRegular),
                math.max(0, beforeDiet - afterDiet))
        end
        return result
    end
    ISTakeWaterAction.transferFluid = M.wrappedTransferFluid
end
