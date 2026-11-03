require "TimedActions/ISCDBaseDogAction"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

ISCDFeedDog = ISCDBaseDogAction:derive("ISCDFeedDog")

function ISCDFeedDog:isValid()
    return self.character:getInventory():containsRecursive(self.food)
end

function ISCDFeedDog:doEffect()
    if self.cdDone then return end
    self.cdDone = true
    self.animal:getBehavior():setBlockMovement(false)
    local inv = self.character:getInventory()
    if not inv:containsRecursive(self.food) then
        return
    end

    local need
    if CD.isCompanion(self.animal) then
        need = CD.getHunger(self.animal)
    else
        local fpH = CD.feedTrustPerHunger()
        if fpH and fpH > 0 then
            local remaining = CD.tameThreshold() - CD.getTrust(self.animal)
            if remaining < 0 then
                remaining = 0
            end
            need = (remaining + 1) / (100 * fpH)
        end
    end

    local bite = CD.computeBite(self.food, need)
    -- Autor explicito: sem ele o CD.request cai em getPlayer(), q em tela dividida e o jogador errado.
    CompanionDogs.request("feed", self.animal, { hunger = bite.hunger, thirst = bite.thirst, partialFrac = bite.partialFrac, foodId = self.food:getID() }, self.character)
end

function ISCDFeedDog:new(character, animal, food)
    local o = ISBaseTimedAction.new(self, character)
    o.animal = animal
    o.food = food
    o.handModelItem = food
    o.soundName = "PutItemInBag"
    o.cdMaxTicks = 75
    o.cdDuration = 150
    o.maxTime = o:getDuration()
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end
