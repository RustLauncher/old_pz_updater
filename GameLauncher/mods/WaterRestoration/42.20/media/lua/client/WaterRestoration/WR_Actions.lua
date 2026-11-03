require "WaterRestoration/WR_Power"
require "WaterRestoration/WR_Requirements"
require "TimedActions/ISWearClothing"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "WaterRestoration/WR_Config"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISInventoryTransferUtil"

WR_InteractionAction = ISBaseTimedAction:derive("WR_InteractionAction")

function WR.queueInteraction(character,target,command,duration)
    local blocked=WR.Power.block(command,target,WR.ClientState or {})
    if blocked then WR.showResult(character,blocked);return false end
    if not WR.canMaterials(character,target,command) then
        character:Say(WR.requirementsText(character,target,command));return false
    end
    local toolType=WR.interactionTool(target,command)
    local tool
    if toolType then
        tool=WR.isValveRepair(target,command) and WR.weldingTools(character) or character:getInventory():getFirstTypeRecurse(toolType)
        if not tool then WR.showResult(character,toolType=="PipeWrench" and "NeedPipeWrench" or "NeedScrewdriver");return false end
        if tool:getContainer()~=character:getInventory() then
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(character,tool,tool:getContainer(),character:getInventory()))
        end
        if character:getPrimaryHandItem()~=tool then
            ISTimedActionQueue.add(ISEquipWeaponAction:new(character,tool,25,true,false))
        end
    end
    if WR.isValveRepair(target,command) then
        local _,mask=WR.weldingTools(character)
        if mask:getContainer()~=character:getInventory() then
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(character,mask,mask:getContainer(),character:getInventory()))
        end
        if character:getWornItem(mask:getBodyLocation())~=mask then ISTimedActionQueue.add(ISWearClothing:new(character,mask)) end
    end
    local action=WR_InteractionAction:new(character,target,command,duration)
    action.tool=tool
    ISTimedActionQueue.add(action)
    return true
end

function WR_InteractionAction:isValid()
    if not self.character or not self.target then return false end
    if ((WR.ClientState or {}).revisions or {})[self.target.id]~=nil and ((WR.ClientState or {}).revisions or {})[self.target.id]~=self.expectedRevision then return false end
    if WR.Power.block(self.command,self.target,WR.ClientState or {}) then return false end
    local toolType=WR.interactionTool(self.target,self.command)
    if toolType then
        local hand=self.character:getPrimaryHandItem()
        if not hand or hand:getType()~=toolType or not self.character:getInventory():containsTypeRecurse(toolType) then return false end
    end
    if not WR.canMaterials(self.character,self.target,self.command) then return false end
    if WR.isValveRepair(self.target,self.command) then
        local _,mask=WR.weldingTools(self.character)
        if not mask or self.character:getWornItem(mask:getBodyLocation())~=mask then return false end
    end
    local square = getCell():getGridSquare(self.target.x, self.target.y, self.target.z)
    if not square then return false end
    local dx = self.character:getX() - self.target.x
    local dy = self.character:getY() - self.target.y
    return self.character:getZ() == self.target.z and (dx * dx + dy * dy) <= 9
end

function WR_InteractionAction:waitToStart()
    self.character:faceLocation(self.target.x, self.target.y)
    return self.character:shouldBeTurning()
end

function WR_InteractionAction:start()
    self:setActionAnim(WR.isValveRepair(self.target,self.command) and "BlowTorch" or "Loot")
    if WR.interactionTool(self.target,self.command) then self:setOverrideHandModels(self.character:getPrimaryHandItem(),nil) end
    self.character:reportEvent("EventLootItem")
    local sound = self.target.kind == "valve" and "WR_ValveTurn" or "WR_Computer"
    if self.command == "repairCentral" or self.command == "repairPanel" or self.command == "repairStation" then sound = "WR_ComputerRepair" end
    if (self.command == "maintain" or self.command == "maintainStation") and self.target.kind ~= "valve" then sound = "WR_ComputerRepair" end
    if self.command == "maintain" and self.target.kind == "valve" then sound = "BlowTorch" end
    if self.command == "activateWater" then sound = "GeneratorStarting" end
    if self.command == "activateStation" then sound=nil end
    local preferences = self.character:getModData().WRConsolePreferences
    local preferenceKey=self.target.kind=="distributor" and ("region_"..self.target.id) or self.target.id
    local terminal = preferences and preferences[preferenceKey]
    if sound and (self.target.kind == "valve" or not terminal or terminal.audio ~= false) then
        self.sound = self.character:playSound(sound)
    end
end

function WR_InteractionAction:update()
    self.character:faceLocation(self.target.x, self.target.y)
end

function WR_InteractionAction:stop()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    ISBaseTimedAction.stop(self)
end

function WR_InteractionAction:complete()
    self:applyCommand();return true
end
function WR_InteractionAction:applyCommand()
    if self.applied then return end
    self.applied=true
    local args={target=self.target.id,x=self.target.x,y=self.target.y,z=self.target.z,expectedRevision=self.expectedRevision}
    if isClient() then sendClientCommand("WR",self.command,args)
    elseif WR.Server and WR.Server.handleCommand then WR.Server.handleCommand(self.command,self.character,args) end
end
function WR_InteractionAction:perform()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    self:applyCommand()
    ISBaseTimedAction.perform(self)
end

function WR_InteractionAction:new(character, target, command, duration)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.target = target
    o.command = command
    o.expectedRevision=(((WR.ClientState or {}).revisions or {})[target.id] or 0)
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = target.kind == "valve" and math.max(duration or 0, 361) or duration
    return o
end

WR_ReadManualAction = ISBaseTimedAction:derive("WR_ReadManualAction")

function WR_ReadManualAction:isValid()
    return self.character and self.item and self.character:getInventory():contains(self.item)
end

function WR_ReadManualAction:start()
    self.item:setJobType(getText("ContextMenu_Read") .. " " .. self.item:getName())
    self.item:setJobDelta(0)
    self:setAnimVariable("ReadType", "book")
    self:setOverrideHandModels(nil, self.item)
    self:setActionAnim(CharacterActionAnims.Read)
    self.character:setReading(true)
    self.character:reportEvent("EventRead")
    self.character:playSound("OpenBook")
end

function WR_ReadManualAction:update()
    self.item:setJobDelta(self:getJobDelta())
end

function WR_ReadManualAction:stop()
    self.character:setReading(false)
    self.character:playSound("CloseBook")
    if self.item then self.item:setJobDelta(0) end
    ISBaseTimedAction.stop(self)
end

function WR_ReadManualAction:perform()
    self.character:setReading(false)
    self.character:playSound("CloseBook")
    self.item:setJobDelta(0)
    if isClient() then
        sendClientCommand("WR", "readManual", {})
    elseif WR.Server and WR.Server.handleCommand then
        WR.Server.handleCommand("readManual", self.character, {})
    end
    ISBaseTimedAction.perform(self)
end

function WR_ReadManualAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = 800
    return o
end
