require "TimedActions/ISBaseTimedAction"

ISCPDForceDoorAction = ISBaseTimedAction:derive("ISCPDForceDoorAction")

local function safeCall(object, methodName, ...)
    if not object then return nil end
    local okLookup, method = pcall(function() return object[methodName] end)
    if not okLookup or type(method) ~= "function" then return nil end
    local ok, result = pcall(method, object, ...)
    if ok then return result end
    return nil
end

local function restoreAimingInput(action)
    if not action or not action.character or action.aimSuppressionApplied ~= true then return end
    safeCall(action.character, "setIgnoreAimingInput", action.wasIgnoringAimingInput == true)
    action.wasIgnoringAimingInput = nil
    action.aimSuppressionApplied = false
end

local function restoreMovementInput(action)
    if not action or not action.character or action.movementSuppressionApplied ~= true then return end
    safeCall(action.character, "setIgnoreMovement", action.wasIgnoringMovement == true)
    action.wasIgnoringMovement = nil
    action.movementSuppressionApplied = false
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

function ISCPDForceDoorAction:new(character, door, actionAnim, useCustomAnimation)
    local action = ISBaseTimedAction.new(self, character)
    action.door = door
    action.useCustomAnimation = useCustomAnimation == true
        and CyesPushDoors.getForcedOpeningAnimationSide(actionAnim) ~= nil
    action.actionAnim = action.useCustomAnimation and tostring(actionAnim) or nil
    action.requestSent = false
    action.contactDelta = tonumber(CyesPushDoors.Config.FORCED_OPENING_CONTACT_DELTA) or 0.57
    action.maxTime = tonumber(CyesPushDoors.Config.FORCED_OPENING_ACTION_DURATION) or 25
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

function ISCPDForceDoorAction:isValid()
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
    if not self.door or not CyesPushDoors.isSupportedDoor(self.door) then return false end
    if safeCall(self.door, "getSquare") == nil then return false end

    if self.requestSent ~= true then
        if CyesPushDoors.getLogicalDoorOpenState(self.door) ~= false then return false end
        local maxDistance = tonumber(CyesPushDoors.Config.FORCED_OPENING_MAX_SERVER_DISTANCE) or 2.25
        if CyesPushDoors.getPlayerDoorDistanceSq(character, self.door) > (maxDistance * maxDistance) then
            return false
        end
    end
    return true
end

function ISCPDForceDoorAction:waitToStart()
    if not self.character or not self.door then return false end
    safeCall(self.character, "faceThisObject", self.door)
    return safeCall(self.character, "shouldBeTurning") == true
end

function ISCPDForceDoorAction:start()
    self.wasIgnoringAimingInput = safeCall(self.character, "isIgnoringAimingInput") == true
    self.aimSuppressionApplied = true
    safeCall(self.character, "setIgnoreAimingInput", true)
    safeCall(self.character, "setIsAiming", false)
    self.wasIgnoringMovement = safeCall(self.character, "getIgnoreMovement") == true
    self.movementSuppressionApplied = true
    safeCall(self.character, "setIgnoreMovement", true)
    if self.useCustomAnimation == true and self.actionAnim then
        self:setActionAnim(self.actionAnim)
    end
    setTargetOutline(self)
end

function ISCPDForceDoorAction:update()
    safeCall(self.character, "setIgnoreMovement", true)
    if self.requestSent ~= true and self:getJobDelta() >= self.contactDelta then
        self.requestSent = true
        clearTargetOutline(self)
        CyesPushDoors.requestForcedDoorOpening(
            self.character,
            self.door,
            self.actionAnim,
            self.useCustomAnimation
        )
    end
end

function ISCPDForceDoorAction:stop()
    clearTargetOutline(self)
    restoreAimingInput(self)
    restoreMovementInput(self)
    self.door = nil
    ISBaseTimedAction.stop(self)
end

function ISCPDForceDoorAction:perform()
    if self.requestSent ~= true then
        self.requestSent = true
        clearTargetOutline(self)
        CyesPushDoors.requestForcedDoorOpening(
            self.character,
            self.door,
            self.actionAnim,
            self.useCustomAnimation
        )
    else
        clearTargetOutline(self)
    end
    restoreAimingInput(self)
    restoreMovementInput(self)
    self.door = nil
    ISBaseTimedAction.perform(self)
end

return ISCPDForceDoorAction
