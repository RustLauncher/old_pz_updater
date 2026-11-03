require "TimedActions/ISBaseTimedAction"

ISCPDKickDoorAction = ISBaseTimedAction:derive("ISCPDKickDoorAction")

local VALID_ACTION_ANIMS = {
    CPDKickDoor = true,
    CPDPushFences = true,
    CPDCloseGarages = true,
    CPDPushDoorFail = true,
    CPDPushFencesFail = true,
    CPDCloseGaragesFail = true,
}

local ACTION_DURATIONS = {
    CPDKickDoor = 25,
    CPDPushFences = 25,
    CPDCloseGarages = 25,
    CPDPushDoorFail = 25,
    CPDPushFencesFail = 25,
    CPDCloseGaragesFail = 45,
}

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

function ISCPDKickDoorAction:isValid()
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
    local performingAction = safeCall(character, "getVariableString", "PerformingAction")
    if performingAction ~= nil and performingAction ~= "" and performingAction ~= "false" and performingAction ~= self.actionAnim then return false end
    return true
end

function ISCPDKickDoorAction:new(character, token, actionAnim)
    local action = ISBaseTimedAction.new(self, character)
    action.token = token
    action.actionAnim = VALID_ACTION_ANIMS[actionAnim] == true and actionAnim or "CPDKickDoor"
    action.maxTime = ACTION_DURATIONS[action.actionAnim]
    action.lockMovementUntilComplete = action.actionAnim == "CPDCloseGaragesFail"
    action.stopOnWalk = action.lockMovementUntilComplete ~= true
    action.stopOnRun = action.lockMovementUntilComplete ~= true
    action.stopOnAim = false
    action.blockMovement = true
    action.useProgressBar = false
    action.wasIgnoringAimingInput = false
    action.aimSuppressionApplied = false
    action.wasIgnoringMovement = false
    action.movementSuppressionApplied = false
    return action
end

function ISCPDKickDoorAction:start()
    self.wasIgnoringAimingInput = safeCall(self.character, "isIgnoringAimingInput") == true
    self.aimSuppressionApplied = true
    safeCall(self.character, "setIgnoreAimingInput", true)
    safeCall(self.character, "setIsAiming", false)
    if self.lockMovementUntilComplete == true then
        self.wasIgnoringMovement = safeCall(self.character, "getIgnoreMovement") == true
        self.movementSuppressionApplied = true
        safeCall(self.character, "setIgnoreMovement", true)
    end
    self:setActionAnim(self.actionAnim)
end

function ISCPDKickDoorAction:update()
    if self.lockMovementUntilComplete == true then
        safeCall(self.character, "setIgnoreMovement", true)
    end
end

function ISCPDKickDoorAction:stop()
    restoreAimingInput(self)
    restoreMovementInput(self)
    self.token = nil
    ISBaseTimedAction.stop(self)
end

function ISCPDKickDoorAction:perform()
    restoreAimingInput(self)
    restoreMovementInput(self)
    self.token = nil
    ISBaseTimedAction.perform(self)
end

return ISCPDKickDoorAction
