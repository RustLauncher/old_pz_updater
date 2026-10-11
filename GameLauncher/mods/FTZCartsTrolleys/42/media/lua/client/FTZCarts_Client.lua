-- FTZ Carts & Trolleys (Build 42) - client side
-- Carts are native Build 42 heavy items (tag base:heavyitem): the game already handles grabbing them
-- from the ground into both hands, keeping only one, and dropping them before most actions.
-- This file adds what the game does not do:
--   * the cart looks loaded (model and icon) when something is inside,
--   * the cart is let go when climbing, falling, sitting or getting into a vehicle.
require "FTZCarts_Shared"
require "TimedActions/FTZTakeCartAction"

local CHECK_EVERY = 15 -- ticks

-- states where you cannot keep pushing a cart
local DROP_STATES = {
    "ClimbOverFenceState", "ClimbOverWallState", "ClimbThroughWindowState", "ClimbSheetRopeState",
    "ClimbDownSheetRopeState", "PlayerFallingState", "PlayerFallDownState", "PlayerKnockedDown",
    "PlayerOnGroundState", "PlayerSitOnGroundState", "PlayerSitOnFurnitureState", "PlayerOnBedState",
    "PlayerGetUpState",
}
local dropStateInstances = nil
local function getDropStates()
    if dropStateInstances then return dropStateInstances end
    dropStateInstances = {}
    for _, name in ipairs(DROP_STATES) do
        local cls = _G[name]
        if cls and cls.instance then
            local ok, inst = pcall(cls.instance)
            if ok and inst then table.insert(dropStateInstances, inst) end
        end
    end
    return dropStateInstances
end

local function inDropState(playerObj)
    if playerObj:getVehicle() then return true end
    local state = playerObj:getCurrentState()
    if not state then return false end
    for _, s in ipairs(getDropStates()) do
        if state == s then return true end
    end
    return false
end

-- let go of the cart using the game's own heavy-item drop (server side in multiplayer)
local lastDropRequest = {}
local function dropCart(playerObj)
    local key = playerObj:getPlayerNum()
    local now = getTimestampMs()
    if lastDropRequest[key] and now - lastDropRequest[key] < 1000 then return end
    lastDropRequest[key] = now
    if isClient() then
        sendClientCommand(playerObj, "player", "onDropHeavyItem", { id = playerObj:getOnlineID() })
    elseif forceDropHeavyItems then
        forceDropHeavyItems(playerObj)
    end
end

-- loaded / empty look ------------------------------------------------------------------------
-- The chosen model is stored on the item (the game keeps it in the item's mod data). Each client works
-- it out from the cart contents it can see, so it is right in hands and on the ground.
local DIRTY_ITEM_MODIFY = 16

-- full: true/false from the server (multiplayer, ground carts) or nil to work it out from the contents
local function applyLook(item, full)
    local def = FTZCarts.TYPES[item:getFullType()]
    if not def then return false end
    if full == nil then full = FTZCarts.isFull(item) end
    local model = full and def.modelFull or def.model
    if item:getStaticModel() == model then return false end
    item:setStaticModel(model)
    item:setWorldStaticModel(model)
    local tex = getTexture(full and def.iconFull or def.icon)
    if tex then item:setTexture(tex) end
    return true
end

local function refreshWorldObject(wo)
    pcall(function() wo:invalidateRenderChunkLevel(DIRTY_ITEM_MODIFY) end)
    pcall(function() wo:updateSprite() end)
end

local function refreshHeld(playerObj, item)
    if applyLook(item) then playerObj:resetEquippedHandsModels() end
end

-- carts standing on the ground around the local players (solo: the game knows every cart's contents;
-- multiplayer: the server sends what is loaded, see onServerCommand below)
local SCAN_RADIUS = 12
local function refreshGround(playerObj)
    local cell = getCell()
    local px, py, pz = math.floor(playerObj:getX()), math.floor(playerObj:getY()), math.floor(playerObj:getZ())
    for x = px - SCAN_RADIUS, px + SCAN_RADIUS do
        for y = py - SCAN_RADIUS, py + SCAN_RADIUS do
            local sq = cell:getGridSquare(x, y, pz)
            if sq then
                local wobs = sq:getWorldObjects()
                for i = 0, wobs:size() - 1 do
                    local wo = wobs:get(i)
                    local item = wo and wo:getItem()
                    if FTZCarts.isCart(item) and applyLook(item) then refreshWorldObject(wo) end
                end
            end
        end
    end
end

local tick = 0
local groundTick = 0
local function onTick()
    tick = tick + 1
    if tick < CHECK_EVERY then return end
    tick = 0
    groundTick = groundTick + 1
    local scanGround = groundTick >= 4 -- about once a second
    if scanGround then groundTick = 0 end
    for playerNum = 0, getNumActivePlayers() - 1 do
        local playerObj = getSpecificPlayer(playerNum)
        if playerObj and not playerObj:isDead() then
            local item = playerObj:getPrimaryHandItem()
            if FTZCarts.isCart(item) then
                FTZCarts.applyCapacity(item)
                refreshHeld(playerObj, item)
                if inDropState(playerObj) then dropCart(playerObj) end
            end
            if scanGround and not isClient() then refreshGround(playerObj) end
        end
    end
end

-- right-click on a cart lying on the ground: "Equip in both hands" directly ----------------------
local function equipCartFromGround(worldobjects, wo, playerNum)
    local playerObj = getSpecificPlayer(playerNum)
    local item = wo and wo:getItem()
    if not playerObj or not item or not wo:getSquare() then return end
    if not luautils.walkAdj(playerObj, wo:getSquare()) then return end
    if playerObj:getPrimaryHandItem() then
        ISTimedActionQueue.add(ISUnequipAction:new(playerObj, playerObj:getPrimaryHandItem(), 50))
    end
    if playerObj:getSecondaryHandItem() and playerObj:getSecondaryHandItem() ~= playerObj:getPrimaryHandItem() then
        ISTimedActionQueue.add(ISUnequipAction:new(playerObj, playerObj:getSecondaryHandItem(), 50))
    end
    ISTimedActionQueue.add(FTZTakeCartAction:new(playerObj, wo))
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:getVehicle() then return end
    -- clicked squares and their neighbours (carts are big, the click often lands next to them)
    local seenSq, seenItem, found = {}, {}, {}
    for _, obj in ipairs(worldobjects) do
        local sq = obj and obj:getSquare()
        if sq then
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local s = getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
                    if s and not seenSq[s] then
                        seenSq[s] = true
                        local wobs = s:getWorldObjects()
                        for i = 0, wobs:size() - 1 do
                            local wo = wobs:get(i)
                            local item = wo and wo:getItem()
                            if FTZCarts.isCart(item) and not seenItem[item] then
                                seenItem[item] = true
                                table.insert(found, wo)
                            end
                        end
                    end
                end
            end
        end
    end
    local held = playerObj:getPrimaryHandItem()
    for _, wo in ipairs(found) do
        if wo:getItem() ~= held then
            context:addOptionOnTop(getText("ContextMenu_Equip_Two_Hands") .. " (" .. wo:getItem():getDisplayName() .. ")",
                worldobjects, equipCartFromGround, wo, playerNum)
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnTick.Add(onTick)

-- multiplayer: loaded / empty state of the carts on the ground, sent by the server
local function onServerCommand(module, command, args)
    if module ~= "FTZCarts" or command ~= "Looks" or not args or not args.carts then return end
    local cell = getCell()
    for _, c in pairs(args.carts) do
        local sq = cell:getGridSquare(c.x, c.y, c.z)
        if sq then
            local wobs = sq:getWorldObjects()
            for i = 0, wobs:size() - 1 do
                local wo = wobs:get(i)
                local item = wo and wo:getItem()
                if item and item:getID() == c.id and FTZCarts.isCart(item) then
                    if applyLook(item, c.full == true) then refreshWorldObject(wo) end
                end
            end
        end
    end
end
Events.OnServerCommand.Add(onServerCommand)
