require "TimedActions/ISBaseTimedAction"
require "BolsasEspecialidades_Study"

ISStudySpecialtyBags = ISBaseTimedAction:derive("ISStudySpecialtyBags")

function ISStudySpecialtyBags:isValid()
    return BolsasEspecialidades.studyBlockReason(self.character, self.item) == nil
end

function ISStudySpecialtyBags:start()
    self.item:setJobType(getText("ContextMenu_BE_Study"))
    self.item:setJobDelta(0)
    self:setActionAnim("Loot")
    self:setOverrideHandModels(nil, self.item)
end

function ISStudySpecialtyBags:update()
    self.item:setJobDelta(self:getJobDelta())
end

function ISStudySpecialtyBags:stop()
    self.item:setJobDelta(0)
    ISBaseTimedAction.stop(self)
end

function ISStudySpecialtyBags:perform()
    self.item:setJobDelta(0)
    ISBaseTimedAction.perform(self)
end

function ISStudySpecialtyBags:complete()
    if not self:isValid() then return false end
    for _, recipe in ipairs(BolsasEspecialidades.studyRecipes) do
        if not self.character:getKnownRecipes():contains(recipe) then
            self.character:learnRecipe(recipe)
        end
    end
    self.item:setJobDelta(0)
    -- Use the same recipe-field synchronization as vanilla ISResearchRecipe.
    sendSyncPlayerFields(self.character, 0x00000001)
    return true
end

function ISStudySpecialtyBags:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    -- Timed actions use 50 cycles per second: 20 seconds at normal speed.
    return 20 * 50
end

function ISStudySpecialtyBags:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.stopOnWalk = true
    o.stopOnRun = true
    o.forceProgressBar = true
    o.maxTime = o:getDuration()
    return o
end
