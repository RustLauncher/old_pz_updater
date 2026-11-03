require "TimedActions/ISBaseTimedAction"

IGRepairWindowAction = ISBaseTimedAction:derive("IGRepairWindowAction")

function IGRepairWindowAction:isValid()
    if not self.window or self.window:getObjectIndex() == -1 then return false end
    if not self.window:isGlassRemoved() then return false end
    
    local inv = self.character:getInventory()
    local hasGlass = (self.glass and inv:contains(self.glass)) 
        or inv:containsTypeRecurse("Base.GlassPanel") 
        or inv:containsTypeRecurse("GlassPanel")
        
    local hasGlue = (self.glue and inv:contains(self.glue)) 
        or inv:containsTypeRecurse("Base.Woodglue") 
        or inv:containsTypeRecurse("Base.Glue") 
        or inv:containsTypeRecurse("Woodglue") 
        or inv:containsTypeRecurse("Glue")
    
    return hasGlass and hasGlue
end

function IGRepairWindowAction:waitToStart()
    self.character:faceThisObject(self.window)
    return self.character:shouldBeTurning()
end

function IGRepairWindowAction:update()
    self.character:faceThisObject(self.window)
end

function IGRepairWindowAction:start()
    self:setActionAnim("Paint")
    if self.glue then
        self:setOverrideHandModels(self.glue, nil)
    end
    self.character:faceThisObject(self.window)
    self.sound = self.character:playSound("Painting")
end

function IGRepairWindowAction:stop()
    if self.sound and self.character:getEmitter() then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function IGRepairWindowAction:perform()
    if self.sound and self.character:getEmitter() then
        self.character:getEmitter():stopSound(self.sound)
    end

    local inv = self.character:getInventory()
    local glass = self.glass 
        or inv:getFirstTypeRecurse("Base.GlassPanel") 
        or inv:getFirstTypeRecurse("GlassPanel")
        
    local glue = self.glue 
        or inv:getFirstTypeRecurse("Base.Woodglue") 
        or inv:getFirstTypeRecurse("Base.Glue") 
        or inv:getFirstTypeRecurse("Woodglue") 
        or inv:getFirstTypeRecurse("Glue")

    -- Consume 1 Glass Panel
    if glass then
        inv:Remove(glass)
    end

    -- Consume 1 unit of Wood Glue or Glue safely
    if glue then
        if instanceof(glue, "DrainableComboItem") then
            glue:Use()
        else
            inv:Remove(glue)
        end
    end

    -- Restore window object completely
    if self.window then
        self.window:setSmashed(false)
        self.window:setGlassRemoved(false)
        self.window:setPermaLocked(false)
        self.window:setIsLocked(false)
    end

    -- Award Build 42 XP safely
    if self.character and self.character:getXp() then
        local glassPerk = Perks.Glassmaking or Perks.FromString("Glassmaking")
        if glassPerk then
            self.character:getXp():AddXP(glassPerk, 15)
        end
        local woodPerk = Perks.Woodwork or Perks.FromString("Woodwork")
        if woodPerk then
            self.character:getXp():AddXP(woodPerk, 5)
        end
    end

    ISBaseTimedAction.perform(self)
end

function IGRepairWindowAction:new(character, window, glass, glue)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character = character
    o.window = window
    o.glass = glass
    o.glue = glue
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = 120
    if character:isTimedActionInstant() then 
        o.maxTime = 1 
    end
    return o
end