require "TimedActions/ISBaseTimedAction"

ISCPDForceDoorPrepareAction = ISBaseTimedAction:derive("ISCPDForceDoorPrepareAction")

local function safeCall(object, methodName, ...)
    if not object then return nil end
    local okLookup, method = pcall(function() return object[methodName] end)
    if not okLookup or type(method) ~= "function" then return nil end
    local ok, result = pcall(method, object, ...)
    if ok then return result end
    return nil
end

local function restoreInput(action)
    if not action or not action.character then return end
    if action.aimSuppressionApplied == true then
        safeCall(action.character, "setIgnoreAimingInput", action.wasIgnoringAimingInput == true)
        action.aimSuppressionApplied = false
    end
    if action.movementSuppressionApplied == true then
        safeCall(action.character, "setIgnoreMovement", action.wasIgnoringMovement == true)
        action.movementSuppressionApplied = false
    end
end

local function setTargetOutline(action)
    if action and CyesPushDoors
        and type(CyesPushDoors.setForcedOpeningTargetOutline) == "function" then
        pcall(
            CyesPushDoors.setForcedOpeningTargetOutline,
            action.character,
            action.door
        )
    end
end

local function clearTargetOutline(action)
    if action and CyesPushDoors
        and type(CyesPushDoors.clearForcedOpeningTargetOutline) == "function" then
        pcall(
            CyesPushDoors.clearForcedOpeningTargetOutline,
            action.character,
            action.door
        )
    end
end

function ISCPDForceDoorPrepareAction:new(character, door)
    local action = ISBaseTimedAction.new(self, character)
    action.door = door
    action.maxTime = math.max(1,
        tonumber(CyesPushDoors.Config.FORCED_OPENING_ALIGNMENT_DURATION) or 15)
    action.stopOnWalk = false
    action.stopOnRun = false
    action.stopOnAim = false
    action.blockMovement = true
    action.useProgressBar = true
    action.wasIgnoringAimingInput = false
    action.aimSuppressionApplied = false
    action.wasIgnoringMovement = false
    action.movementSuppressionApplied = false
    return action
end

function ISCPDForceDoorPrepareAction:isValid()
    local character = self.character
    if not character or safeCall(character, "isAlive") ~= true then return false end
    if safeCall(character, "getVehicle") ~= nil then return false end
    if safeCall(character, "isAsleep") == true then return false end
    if safeCall(character, "isSitOnGround") == true then return false end
    if safeCall(character, "isSeated") == true then return false end
    if safeCall(character, "isFalling") == true then return false end
    if safeCall(character, "isKnockedDown") == true then return false end
    if safeCall(character, "isOnFloor") == true then return false end
    if safeCall(character, "isClimbing") == true then return false end
    if safeCall(character, "isDraggingCorpse") == true then return false end
    if not self.door or not CyesPushDoors.isSupportedDoor(self.door) then return false end
    if safeCall(self.door, "getSquare") == nil then return false end
    if CyesPushDoors.getLogicalDoorOpenState(self.door) ~= false then return false end
    local maxDistance = tonumber(CyesPushDoors.Config.FORCED_OPENING_MAX_SERVER_DISTANCE) or 2.25
    return CyesPushDoors.getPlayerDoorDistanceSq(character, self.door)
        <= (maxDistance * maxDistance)
end

function ISCPDForceDoorPrepareAction:waitToStart()
    if not self.character or not self.door then return false end
    safeCall(self.character, "faceThisObject", self.door)
    return safeCall(self.character, "shouldBeTurning") == true
end

function ISCPDForceDoorPrepareAction:start()
    self.wasIgnoringAimingInput = safeCall(self.character, "isIgnoringAimingInput") == true
    self.aimSuppressionApplied = true
    safeCall(self.character, "setIgnoreAimingInput", true)
    safeCall(self.character, "setIsAiming", false)
    self.wasIgnoringMovement = safeCall(self.character, "getIgnoreMovement") == true
    self.movementSuppressionApplied = true
    safeCall(self.character, "setIgnoreMovement", true)
    safeCall(self.character, "faceThisObject", self.door)
    setTargetOutline(self)
end

function ISCPDForceDoorPrepareAction:update()
    safeCall(self.character, "setIgnoreMovement", true)
    safeCall(self.character, "faceThisObject", self.door)
end

function ISCPDForceDoorPrepareAction:stop()
    clearTargetOutline(self)
    restoreInput(self)
    self.door = nil
    ISBaseTimedAction.stop(self)
end

function ISCPDForceDoorPrepareAction:perform()
    restoreInput(self)
    self.door = nil
    ISBaseTimedAction.perform(self)
end

return ISCPDForceDoorPrepareAction
