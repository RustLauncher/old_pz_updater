require "TimedActions/ISBaseTimedAction"
require "WindowArmorTest_Shared"
require "WindowArmorTest_Visual"

-- Install / remove armor on a SINGLE part (window, hood, trunk lid, rear door).
-- mode = "install" | "uninstall", kind = "glass" | "body"
--
-- HOW IT RUNS IN MULTIPLAYER (zombie.core.NetTimedAction):
--   client : isValid / waitToStart / start / update / perform   - progress bar and animation only
--   server : isValid / serverStart / update / complete          - all the real work
-- The engine never calls complete() on a multiplayer client
-- (LuaTimedActionNew.complete: if GameClient.client then return),
-- and in singleplayer both perform() and complete() run locally.
-- So everything that changes the world - the inventory and the armor state -
-- lives in complete(), exactly like vanilla actions do. The client changes nothing
-- by itself: a client that edits inventories on its own looks like cheating
-- to the server and gets kicked with "Malformed packet or suspicious activity".
ISWindowArmorTestAction = ISBaseTimedAction:derive("ISWindowArmorTestAction")

function ISWindowArmorTestAction:isValid()
    local WAT = WindowArmorTest
    if not self.vehicle or self.vehicle:getMovingObjectIndex() < 0 then return false end
    local entry = WAT.getPartArmor(self.vehicle, self.partId)
    if self.mode == "install" then
        return self.item ~= nil
            and self.character:getInventory():contains(self.item)
            and entry == nil
            and WAT.canInstallOn(self.vehicle, self.partId, self.kind)
    end
    return entry ~= nil
end

function ISWindowArmorTestAction:waitToStart()
    self.character:faceThisObject(self.vehicle)
    return self.character:shouldBeTurning()
end

function ISWindowArmorTestAction:update()
    self.character:faceThisObject(self.vehicle)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function ISWindowArmorTestAction:start()
    self:setActionAnim("VehicleWorkOnMid")
end

-- the server side counterpart of start(); nothing to prepare here
function ISWindowArmorTestAction:serverStart()
end

function ISWindowArmorTestAction:stop()
    ISBaseTimedAction.stop(self)
end

-- client side: no world changes here, only finishing the action
function ISWindowArmorTestAction:perform()
    ISBaseTimedAction.perform(self)
end

-- singleplayer and server: this is where the work happens
function ISWindowArmorTestAction:complete()
    local WAT = WindowArmorTest
    local name = WAT.partName(self.partId)

    if self.mode == "install" then
        local item = self.item
        if not item then return false end
        if WAT.getPartArmor(self.vehicle, self.partId) then return false end
        if not WAT.canInstallOn(self.vehicle, self.partId, self.kind) then return false end

        -- kit condition -> armor condition
        local pct = 100
        if item:getConditionMax() > 0 then
            pct = math.floor(item:getCondition() / item:getConditionMax() * 100 + 0.5)
        end
        -- spend the kit (the server owns the inventory in multiplayer)
        self.character:removeFromHands(item)
        local container = item:getContainer() or self.character:getInventory()
        container:DoRemoveItem(item)
        sendRemoveItemFromContainer(container, item)

        WAT.applyInstall(self.vehicle, self.partId, self.kind, pct)
        WAT.updateVisual(self.vehicle)
        WAT.halo(self.character, WAT.text("IGUI_WAT_Installed") .. ": " .. name, 120, 255, 120)
    else
        local cond, kind = WAT.applyUninstall(self.vehicle, self.partId)
        if cond == nil then return false end
        WAT.giveKit(self.character, kind, cond)
        WAT.updateVisual(self.vehicle)
        WAT.halo(self.character, WAT.text("IGUI_WAT_Removed") .. ": " .. name, 255, 255, 255)
    end
    return true
end

function ISWindowArmorTestAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return WindowArmorTest.INSTALL_TIME
end

function ISWindowArmorTestAction:new(character, vehicle, partId, mode, item, kind)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = vehicle
    o.partId = partId
    o.mode = mode
    o.item = item
    o.kind = kind or (item and WindowArmorTest.kindOfItem(item:getFullType())) or "glass"
    o.maxTime = o:getDuration()
    return o
end
