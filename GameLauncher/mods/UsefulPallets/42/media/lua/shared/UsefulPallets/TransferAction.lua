require "TimedActions/ISBaseTimedAction"
require "UsefulPallets/Config"
require "UsefulPallets/Sources"

ISUsefulPalletTransfer = ISBaseTimedAction:derive("ISUsefulPalletTransfer")
local WP = UsefulPallets

function WP.canReach(character, pallet)
    if not pallet or not pallet:isExistInTheWorld() then return false end
    local square = pallet:getSquare()
    local playerSquare = character:getSquare()
    return square and playerSquare and square:getZ() == playerSquare:getZ()
        and playerSquare:isAdjacentTo(square) and not square:isSomethingTo(playerSquare)
        and not character:getVehicle() and not character:isDead()
        and SafeHouse.isSafehouseAllowLoot(square, character) or false
end

-- A multiplayer client can see the new sprite before the pallet's saved data arrives:
-- a pallet that was never loaded has none, and state() refuses to invent contents for a
-- loaded sprite. The server validates again in complete(), so the client waits instead of
-- cancelling the whole queue.
function WP.awaitingSync(pallet)
    if not isClient() then return false end
    local sprite = pallet:getSprite() and pallet:getSprite():getName()
    return sprite ~= nil and (WP.vanilla[sprite] ~= nil or WP.loadedSprites[sprite] ~= nil)
        and pallet:getModData().UsefulPallets == nil
end

-- Returns false plus the failing check, so a rejected transfer can be traced in the log.
function ISUsefulPalletTransfer:isValid()
    if not WP.canReach(self.character, self.pallet) then return false, "pallet out of reach" end
    local state = WP.state(self.pallet)
    if state then
        if self.revision ~= (state.stackRevision or 0) then return false, "stack revision changed" end
        if (self.layer == "top") ~= (state.kind == "stacked") then return false, "wrong layer" end
        if not WP.canTransfer(state, self.itemType, self.direction) then
            return false, "cannot " .. tostring(self.direction) .. " " .. tostring(self.itemType)
                .. " (count " .. tostring(state.count) .. ", holds " .. tostring(state.item) .. ")"
        end
    elseif not WP.awaitingSync(self.pallet) then
        return false, "pallet data unreadable"
    end
    if self.direction == "add" then
        -- The server removes the source item while this client action is still waiting for its
        -- confirmation. Once started, an item that left its container is the transfer in
        -- progress, not a failure; the server checks the item itself in complete().
        if isClient() and self.started and self.item and not self.item:getContainer() then return true end
        if not WP.canLoadItem(self.character, self.item, self.itemType) then
            return false, "source item " .. tostring(self.item and self.item:getFullType()) .. " not usable"
        end
        return true
    end
    local script = ScriptManager.instance:getItem(self.itemType)
    if script and self.character:getInventory():hasRoomFor(self.character, script:getActualWeight()) then return true end
    return false, "no room in inventory"
end

function ISUsefulPalletTransfer:waitToStart()
    self.character:faceThisObject(self.pallet)
    return self.character:shouldBeTurning()
end

function ISUsefulPalletTransfer:update()
    self.character:faceThisObject(self.pallet)
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
end

function ISUsefulPalletTransfer:start()
    self.started = true
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

function ISUsefulPalletTransfer:stop()
    ISBaseTimedAction.stop(self)
end

function ISUsefulPalletTransfer:perform()
    ISBaseTimedAction.perform(self)
end

function ISUsefulPalletTransfer:complete()
    -- B42 calls complete on the server without isValid; validate again here.
    local valid, reason = self:isValid()
    if not valid then
        print("UsefulPallets: " .. tostring(self.direction) .. " rejected on the server: " .. tostring(reason))
        return false
    end
    local state = WP.state(self.pallet)
    if not state then
        print("UsefulPallets: " .. tostring(self.direction) .. " rejected on the server: pallet data unreadable")
        return false
    end
    local inventory = self.character:getInventory()
    local nextCount = state.count + (self.direction == "add" and 1 or -1)
    local nextItem = nextCount > 0 and self.itemType or nil
    -- Any successful contents change adopts the working-stack identity.
    local sprite = WP.spriteFor(state.kind, nextItem, nextCount, WP.bottomCount(state))
    if not sprite or not IsoSpriteManager.instance:getSprite(sprite) then return false end
    local units = {}
    for i = 1, state.count do units[i] = state.units and state.units[i] or {} end
    if self.direction == "add" then
        units[#units + 1] = {
            condition = self.item:getCondition(),
            customName = self.item:isCustomName(),
            name = self.item:isCustomName() and self.item:getName() or nil,
            modData = self.item:hasModData() and copyTable(self.item:getModData()) or nil,
        }
        local source = self.item:getContainer()
        sendRemoveItemFromContainer(source, self.item)
        source:Remove(self.item)
    else
        local added = inventory:AddItem(self.itemType)
        if not added then return false end
        local unitIndex = self.unitIndex or #units
        local unit = units[unitIndex]
        if unit.condition then added:setCondition(unit.condition) end
        if unit.customName then added:setName(unit.name); added:setCustomName(true) end
        if unit.modData then added:copyModData(unit.modData) end
        table.remove(units, unitIndex)
        self.takenItem = added
        sendAddItemToContainer(inventory, added)
    end
    self.pallet:getModData().UsefulPallets = {
        version = WP.VERSION, kind = state.kind, item = nextItem, count = nextCount, units = units, topPallet = state.topPallet, stackRevision = state.stackRevision, bottomCount = state.bottomCount,
    }
    local changedSprite = self.pallet:getSprite():getName() ~= sprite
    if changedSprite then self.pallet:setSpriteFromName(sprite) end
    self.pallet:transmitModData()
    if changedSprite then
        self.pallet:transmitUpdatedSpriteToClients()
        self.pallet:getSquare():RecalcProperties()
        self.pallet:getSquare():RecalcAllWithNeighbours(true)
    end
    return true
end

function ISUsefulPalletTransfer:getDuration()
    return self.character:isTimedActionInstant() and 1 or WP.TRANSFER_TIME
end

-- Keep fields named exactly like constructor parameters for B42 network reconstruction.
function ISUsefulPalletTransfer:new(character, pallet, itemType, direction, item, layer, revision)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.pallet = pallet
    o.itemType = itemType
    o.direction = direction
    o.item = item
    local state = WP.state(pallet)
    o.layer = layer or (state and state.kind == "stacked" and "top" or "bottom")
    o.revision = revision or (state and state.stackRevision) or 0
    o.maxTime = o:getDuration()
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end
