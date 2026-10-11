require "TimedActions/ISBaseTimedAction"
require "ArcadiaRefillablePropane_Shared"

ISArcadiaVehiclePropaneAction = ISBaseTimedAction:derive(
    "ISArcadiaVehiclePropaneAction"
)

function ISArcadiaVehiclePropaneAction:resolvePart()
    return ArcadiaRefillablePropane.getFilibusterPropanePart(
        self.vehicle,
        self.partId
    )
end

function ISArcadiaVehiclePropaneAction:resolveItem()
    if not self.itemId or not self.character then return nil end
    local requestedId = tonumber(self.itemId)
    local items = self.character:getInventory():getAllEvalRecurse(function(item)
        return item and item:getID() == requestedId
    end)
    if items and not items:isEmpty() then return items:get(0) end
    return nil
end

function ISArcadiaVehiclePropaneAction:isValid()
    local Depot = ArcadiaRefillablePropane
    local part = self:resolvePart()
    if not part then return false end

    if self.direction == "depot_to_vehicle" or
        self.direction == "vehicle_to_depot" then
        -- A depot can be beside a large truck while its propane part is farther
        -- away.  This transfer is performed from the depot, not at the part.
        if not self.object or self.object:getObjectIndex() == -1 or
            not Depot.isDepotObject(self.object) or
            not Depot.isPlayerAdjacent(self.character, self.object) or
            not Depot.isVehicleNearDepot(self.vehicle, self.object) then
            return false
        end
        if self.direction == "vehicle_to_depot" then
            return Depot.getVehiclePropaneAmount(part) > Depot.MIN_TRANSFER and
                Depot.getDepotMissingUnits(self.object) > Depot.MIN_TRANSFER
        end
        return Depot.getVehiclePropaneMissingUnits(part) > Depot.MIN_TRANSFER and
            Depot.getStoredAmount(self.object) > Depot.MIN_TRANSFER
    end

    -- Direct item-to-vehicle transfers still require the player to reach the
    -- actual propane part.
    if not Depot.isPlayerAdjacentToVehiclePart(self.character, part) then
        return false
    end

    self.item = self:resolveItem()
    if not self.item or
        not self.character:getInventory():containsRecursive(self.item) or
        not Depot.getTargetKind(self.item) then
        return false
    end
    if self.direction == "vehicle_to_item" then
        return Depot.getMissingUnits(self.item) > Depot.MIN_TRANSFER and
            Depot.getVehiclePropaneAmount(part) > Depot.MIN_TRANSFER
    end
    if self.direction == "item_to_vehicle" then
        return Depot.isPropaneSourceItem(self.item) and
            Depot.getVehiclePropaneMissingUnits(part) > Depot.MIN_TRANSFER
    end
    return false
end

function ISArcadiaVehiclePropaneAction:waitToStart()
    self.character:faceThisObject(self.object or self.vehicle)
    return self.character:shouldBeTurning()
end

function ISArcadiaVehiclePropaneAction:start()
    self.item = self:resolveItem()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
    if self.item then
        self.item:setJobType(getText("UI_RPT_VehicleTransferAction"))
        self.item:setJobDelta(0.0)
    end
    self.sound = self.character:playSound("TransferLiquid")
end

function ISArcadiaVehiclePropaneAction:update()
    self.character:faceThisObject(self.object or self.vehicle)
    if self.item then self.item:setJobDelta(self:getJobDelta()) end
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function ISArcadiaVehiclePropaneAction:stop()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    if self.item then self.item:setJobDelta(0.0) end
    ISBaseTimedAction.stop(self)
end

function ISArcadiaVehiclePropaneAction:perform()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    if self.item then self.item:setJobDelta(0.0) end
    ISBaseTimedAction.perform(self)
end

function ISArcadiaVehiclePropaneAction:complete()
    local server = ArcadiaRefillablePropaneServer
    if not server then return false end
    if self.direction == "vehicle_to_item" and
        server.completeVehicleToItem then
        return server.completeVehicleToItem(
            self.character,
            self.vehicle,
            self.partId,
            self.itemId
        )
    end
    if self.direction == "item_to_vehicle" and
        server.completeItemToVehicle then
        return server.completeItemToVehicle(
            self.character,
            self.vehicle,
            self.partId,
            self.itemId
        )
    end
    if self.direction == "depot_to_vehicle" and
        server.completeDepotToVehicle then
        return server.completeDepotToVehicle(
            self.character,
            self.object,
            self.vehicle,
            self.partId
        )
    end
    if self.direction == "vehicle_to_depot" and
        server.completeVehicleToDepot then
        return server.completeVehicleToDepot(
            self.character,
            self.object,
            self.vehicle,
            self.partId
        )
    end
    return false
end

function ISArcadiaVehiclePropaneAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    local Depot = ArcadiaRefillablePropane
    local part = self:resolvePart()
    local amount = 0
    if part and self.direction == "vehicle_to_item" then
        local item = self.item or self:resolveItem()
        amount = item and math.min(
            Depot.getMissingUnits(item),
            Depot.vehiclePropaneToDepotUnits(
                Depot.getVehiclePropaneAmount(part)
            )
        ) or 0
    elseif part and self.direction == "item_to_vehicle" then
        local item = self.item or self:resolveItem()
        amount = item and math.min(
            Depot.getItemStoredUnits(item),
            Depot.vehiclePropaneToDepotUnits(
                Depot.getVehiclePropaneMissingUnits(part)
            )
        ) or 0
    elseif part and self.direction == "depot_to_vehicle" then
        amount = math.min(
            Depot.getStoredAmount(self.object),
            Depot.vehiclePropaneToDepotUnits(
                Depot.getVehiclePropaneMissingUnits(part)
            )
        )
    elseif part and self.direction == "vehicle_to_depot" then
        amount = math.min(
            Depot.getDepotMissingUnits(self.object),
            Depot.vehiclePropaneToDepotUnits(
                Depot.getVehiclePropaneAmount(part)
            )
        )
    end
    return math.min(600, math.max(60, 60 + (amount * 1.5)))
end

function ISArcadiaVehiclePropaneAction:new(
    character,
    vehicle,
    part,
    direction,
    item,
    object
)
    local action = ISBaseTimedAction.new(self, character)
    action.character = character
    action.vehicle = vehicle
    action.partId = part and part:getId() or nil
    action.direction = direction
    action.item = item
    action.itemId = item and item:getID() or nil
    action.object = object
    action.maxTime = action:getDuration()
    return action
end
