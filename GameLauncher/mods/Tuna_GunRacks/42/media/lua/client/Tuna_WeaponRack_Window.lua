require "ISUI/ISCollapsableWindow"
require "Entity/ISUI/ISBaseEntityWindow"
require "Entity/ISUI/Controls/ISItemSlot"

-- this guard must name EVERY shared symbol below; an older sibling passes a partial one
if not (TunaWRSlots and TunaWRSlots.PIECES
        and TunaWRSlots.infoOf and TunaWRSlots.uiOrderFor
        and TunaWRSlots.place and TunaWRSlots.resolve
        and TunaWRItem
        and TunaWRItem.classify and TunaWRItem.facingOf and TunaWRItem.pieceOf
        and TunaWRItem.boundOf and TunaWRItem.itemsOf
        and TunaWRItem.applyArrangement and TunaWRItem.masterOf
        and TunaWRAccept and TunaWRAccept.Bay) then
    print('[Tuna_WeaponRack] FATAL window loaded before shared/, or against an older ' ..
          'shared module - no window registered')
    return
end

local SLOT_W, SLOT_H, PAD = 76, 76, 10

-- a monotone FLOOR, not the width: this may only ever widen a window
local TITLE_FLOOR_MIN = 260

local FAST_TIME = 18

-- lower only, never raise - and maxTime -1 is the server-timed MP case, left alone
local function hasten(action)
    if action and type(action.maxTime) == 'number' and action.maxTime > FAST_TIME then
        action.maxTime = FAST_TIME
        -- queueList[1].time is capped with it, or a merged batch reverts partway
        local q = action.queueList
        if q and q[1] and type(q[1].time) == 'number' and q[1].time > FAST_TIME then
            q[1].time = FAST_TIME
        end
    end
    return action
end

-- ISItemSlot is a drop TARGET ONLY; the drag source below is ours, not vanilla's
TunaWRSlotBox = ISItemSlot:derive("TunaWRSlotBox")

local DRAG_THRESHOLD = 4

function TunaWRSlotBox:onMouseDown(x, y)
    self.pressed = false
    self.dragStarted = false
    self.dragDist = 0
    if not self.mouseEnabled or self:isLocked() then return end
    if not self.storedItem then return end
    self.pressed = true
end

function TunaWRSlotBox:onMouseMove(dx, dy)
    ISItemSlot.onMouseMove(self, dx, dy)
    if not self.pressed or self.dragStarted then return end
    if not self.storedItem then return end

    self.dragDist = (self.dragDist or 0) + math.abs(dx) + math.abs(dy)
    if self.dragDist <= DRAG_THRESHOLD then return end

    self.dragStarted = true
    ISMouseDrag.dragging = { self.storedItem }
    ISMouseDrag.draggingFocus = self
end

function TunaWRSlotBox:onMouseUp(x, y)
    local dragged = self.dragStarted
    self.pressed = false
    self.dragStarted = false

    if dragged and ISMouseDrag.draggingFocus == self then
        ISMouseDrag.dragging = nil
        ISMouseDrag.draggingFocus = nil
        return
    end

    ISItemSlot.onMouseUp(self, x, y)
end

function TunaWRSlotBox:onMouseMoveOutside(dx, dy)
    ISItemSlot.onMouseMoveOutside(self, dx, dy)
end

-- the parent fires no callback for an EMPTY box, so an empty slot needs this hook
function TunaWRSlotBox:onRightMouseUp(x, y)
    ISItemSlot.onRightMouseUp(self, x, y)
    if not self.mouseEnabled or self:isLocked() then return end
    if ISMouseDrag.dragging ~= nil then return end   -- that was a drop, not a click
    if self.boxOccupied then return end              -- occupied: the parent equipped
    if self.onEmptyRightClick then
        self.onEmptyRightClick(self.functionTarget, self)
    end
end

-- decided at activation, never in prerender: a box can fill under the cursor
function TunaWRSlotBox:activateToolTip()
    local want = (not self.boxOccupied) and self.emptyToolTip or false
    if self.toolTip and self.toolTipText ~= want then self:deactivateToolTip() end
    self.toolTipText = want
    ISItemSlot.activateToolTip(self)
end

-- the drag clears HERE, not in onMouseUp - update runs after all mouse handling
function TunaWRSlotBox:update()
    ISItemSlot.update(self)
    if ISMouseDrag.dragging ~= nil and ISMouseDrag.draggingFocus == self
       and not isMouseButtonDown(0) then
        ISMouseDrag.dragging = nil
        ISMouseDrag.draggingFocus = nil
        self.pressed = false
        self.dragStarted = false
    end
end

function TunaWRSlotBox:new(x, y, width, height, resource, target,
                           onItemDropped, onItemRemove, onVerifyItem, onBoxClicked)
    local o = ISItemSlot.new(self, x, y, width, height, resource, target,
                             onItemDropped, onItemRemove, onVerifyItem, onBoxClicked)
    o.pressed = false
    o.dragStarted = false
    o.dragDist = 0
    return o
end

TunaWeaponRackWindow = ISBaseEntityWindow:derive("TunaWeaponRackWindow")

-- asks about the MASTER: a satellite carries no slot table and would be dead
function TunaWeaponRackWindow.CanOpenWindowFor(_player, _entity)
    if not (_player and _entity) then return false end
    local master = TunaWRItem.masterOf(_entity)
    if master == nil then return false end
    local piece = TunaWRItem.pieceOf(master)
    return piece ~= nil and TunaWRSlots.PIECES[piece] ~= nil
end

function TunaWeaponRackWindow:slots()
    return TunaWRSlots.PIECES[TunaWRItem.pieceOf(self.entity)] or {}
end

function TunaWeaponRackWindow:info()
    return TunaWRSlots.infoOf(TunaWRItem.pieceOf(self.entity))
end

function TunaWeaponRackWindow:createChildren()
    ISBaseEntityWindow.createChildren(self)

    local slots = self:slots()
    local top = self:titleBarHeight() + PAD

    local info  = self:info()
    local order = TunaWRSlots.uiOrderFor(info, TunaWRItem.facingOf(self.entity))

    self.slotUI = {}
    for ui = 1, #slots do
        local s = TunaWRSlotBox:new((ui - 1) * (SLOT_W + PAD) + PAD, top, SLOT_W, SLOT_H,
                                 nil, self,
                                 self.onItemDropped, self.onItemRemove,
                                 self.onVerifyItem, self.onBoxClicked)
        -- everything downstream is AUTHORED index; only the box position is UI order
        s.authored = (order and order[ui]) or ui
        s.onEmptyRightClick = self.onEmptyRightClick
        local def = slots[s.authored]
        if def and def.cat then s.emptyToolTip = getText('IGUI_TunaWR_Store_' .. def.cat) end
        s:initialise()
        s:instantiate()
        s:setCharacter(self.player)
        s:setToolTip(true)
        self:addChild(s)
        self.slotUI[ui] = s
    end

    -- inherited from ISCollapsableWindow, not reimplemented; it reads self.title, so it must run after the title is set
    local titleFloor = TITLE_FLOOR_MIN
    if self.minTitleBarWidth then
        titleFloor = math.max(titleFloor, self:minTitleBarWidth())
    end
    local w = math.max(#slots * (SLOT_W + PAD) + PAD, titleFloor)
    self:setWidth(w)
    self:setHeight(top + SLOT_H + PAD)
    self.minimumWidth  = w
    self.minimumHeight = top + SLOT_H + PAD
end

-- closing unconditionally here breaks every inventory drag; only the WORLD dismisses
function TunaWeaponRackWindow:onMouseDownOutside(x, y)
    if ISMouseDrag.dragging then return end

    local mx, my = getMouseX(), getMouseY()
    local uis = UIManager.getUI()
    for i = 0, uis:size() - 1 do
        local ui = uis:get(i)
        if ui:isPointOver(mx, my) then return end   -- a panel, not the world
    end

    self:close()
end

function TunaWeaponRackWindow:prerender()
    ISBaseEntityWindow.prerender(self)
    if not self.slotUI then return end

    local obj = self.entity
    local cont = obj and obj:getContainer()
    if not cont then return end

    local slots = self:slots()
    local pool = TunaWRItem.itemsOf(cont)
    local byId = {}
    for i = 1, #pool do byId[pool[i].id] = pool[i].item end
    local ids = TunaWRSlots.resolve(slots, TunaWRItem.boundOf(obj, #slots), pool)

    for ui = 1, #self.slotUI do
        local box = self.slotUI[ui]
        local id = ids[box.authored]
        box:setStoredItem(id and byId[id] or nil)
    end
end

function TunaWeaponRackWindow:onVerifyItem(_slot, _item)
    local def = self:slots()[_slot.authored]
    if not def then return false end
    if TunaWRItem.classify(_item) ~= def.cat then return false end

    local cont = self.entity and self.entity:getContainer()
    if not cont then return false end
    -- a reorder is exempt: the engine never consults the predicate for an item already here
    if _item:getContainer() == cont then return true end

    -- asks the ENGINE predicate; a second copy of the count is how the UI comes to disagree
    return TunaWRAccept.Bay(cont, _item) == true
end

-- keepActions=true is load-bearing: without it each drag cancels the previous transfer
function TunaWeaponRackWindow:walkToPiece()
    if not self.player or not self.entity then return false end
    return luautils.walkAdjObject(self.player, self.entity, true, true)
end

function TunaWeaponRackWindow:onItemDropped(_slot, _items)
    local item = _items and _items[1]
    if not item then return end
    local cont = self.entity and self.entity:getContainer()
    if not cont then return end

    if item:getContainer() == cont then
        self:sendArrangement(self:arrangementWith(_slot.authored, item:getID()))
        return
    end

    if not self:walkToPiece() then return end

    ISTimedActionQueue.add(hasten(ISInventoryTransferAction:new(
        self.player, item, item:getContainer(), cont)))
    ISTimedActionQueue.add(TunaWRBindAfter:new(
        self.player, self, cont, _slot.authored, item))
end

function TunaWeaponRackWindow:onItemRemove(_slot, _item) end

function TunaWeaponRackWindow:onBoxClicked(_slot, _isRight, _isShift)
    local item = _slot.storedItem
    if not item then return end
    if not self:walkToPiece() then return end
    local inv = self.player:getInventory()
    ISTimedActionQueue.add(hasten(ISInventoryTransferAction:new(
        self.player, item, item:getContainer(), inv)))
    if _isRight then
        ISTimedActionQueue.add(ISEquipWeaponAction:new(
            self.player, item, FAST_TIME, true, item:isTwoHandWeapon()))
    end
end

function TunaWeaponRackWindow:carriedWeaponFor(cat)
    local p = self.player
    if not p then return nil end

    local function ok(item)
        return item ~= nil and TunaWRItem.classify(item) == cat and item or nil
    end

    local hit = ok(p:getPrimaryHandItem()) or ok(p:getSecondaryHandItem())
    if hit then return hit end

    local found = nil
    pcall(function()
        local att = p:getAttachedItems()
        if not att then return end
        for i = 0, att:size() - 1 do
            local a = att:get(i)
            local it = a and a.getItem and a:getItem() or nil
            if ok(it) then found = it; return end
        end
    end)
    return found
end

function TunaWeaponRackWindow:onEmptyRightClick(_slot)
    local def = self:slots()[_slot.authored]
    if not def then return end

    local cont = self.entity and self.entity:getContainer()
    if not cont then return end

    local item = self:carriedWeaponFor(def.cat)
    if not item then return end
    if item:getContainer() == cont then return end   -- already racked

    if not self:walkToPiece() then return end

    -- the walk was queued BEFORE this, so the player does not disarm then set off
    if self.player:isEquipped(item) then
        ISTimedActionQueue.add(ISUnequipAction:new(self.player, item, FAST_TIME))
    end

    ISTimedActionQueue.add(hasten(ISInventoryTransferAction:new(
        self.player, item, item:getContainer(), cont)))
    ISTimedActionQueue.add(TunaWRBindAfter:new(
        self.player, self, cont, _slot.authored, item))
end

function TunaWeaponRackWindow:arrangementWith(authoredIndex, id)
    local obj = self.entity
    local slots = self:slots()
    local cur = TunaWRSlots.resolve(slots, TunaWRItem.boundOf(obj, #slots),
                                    TunaWRItem.itemsOf(obj:getContainer()))
    return TunaWRSlots.place(slots, cur, authoredIndex, id)
end

function TunaWeaponRackWindow:sendArrangement(ids)
    if ids == nil then
        print('[Tuna_WeaponRack] drop refused: no slot could take the displaced weapon')
        return
    end
    local ok, why = TunaWRItem.applyArrangement(self.player, self.entity, ids)
    if not ok then
        print('[Tuna_WeaponRack] arrangement not applied: ' .. tostring(why))
    end
end

function TunaWeaponRackWindow:new(x, y, width, height, player, entity, entityUiStyle)
    -- the satellite is substituted ONCE here; every downstream reader then sees the master
    entity = TunaWRItem.masterOf(entity) or entity
    local o = ISBaseEntityWindow.new(self, x, y, width, height, player, entity, entityUiStyle)

    local info = TunaWRSlots.infoOf(TunaWRItem.pieceOf(entity))
    if info and info.title then o.title = getText(info.title) end

    o.resizable = false

    -- derived from the authority's range, never typed, or the window outlives the server's reach
    o.panelCloseDistance = math.sqrt(TunaWRItem.RANGE_SQ) - 0.05
    -- the entity header lands on the close button and swallows its clicks
    o.enableHeader = false
    return o
end

TunaWRBindAfter = ISBaseTimedAction:derive("TunaWRBindAfter")

-- the DESTINATION, not any container: a failed transfer leaves the item in the inventory
function TunaWRBindAfter:isValid()
    return self.item:getContainer() == self.cont
end

function TunaWRBindAfter:update() end
function TunaWRBindAfter:start() end
function TunaWRBindAfter:stop() ISBaseTimedAction.stop(self) end

function TunaWRBindAfter:perform()
    self.win:sendArrangement(self.win:arrangementWith(self.authored, self.item:getID()))
    ISBaseTimedAction.perform(self)
end

function TunaWRBindAfter:new(character, win, cont, authored, item)
    local o = ISBaseTimedAction.new(self, character)
    o.win, o.cont, o.authored, o.item = win, cont, authored, item
    o.maxTime = 1
    o.stopOnWalk = false
    o.stopOnRun = false
    return o
end
