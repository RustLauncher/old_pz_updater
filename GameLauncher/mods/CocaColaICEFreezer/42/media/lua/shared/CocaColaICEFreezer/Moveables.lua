require 'CocaColaICEFreezer/Core'
require 'Moveables/ISMoveableSpriteProps'
local M = CocaColaICEFreezer
local props = ISMoveableSpriteProps
local contexts = setmetatable({}, {__mode='k'})

local function inheritMovableData(item,saved)
    if not item or type(saved)~='table' then return end
    local data=item:getModData()
    if data.movableData~=nil and type(data.movableData)~='table' then return end
    if data.movableData==nil then
        data.movableData=copyTable(saved)
        return
    end
    -- A chained hook may already have added its own fields to the native item.
    -- Restore source fields missing from that partial table, without replacing
    -- any field already owned by another hook or an unexpected data structure.
    for key,value in pairs(saved)do
        if data.movableData[key]==nil then
            data.movableData[key]=type(value)=='table' and copyTable(value) or value
        end
    end
end

-- A powered half and an unplugged half can legitimately use different state
-- sprites. Resolve the same registered freezer part across visual states so
-- the native pickup/rotation grid remains complete during those transitions.
local previousFind = props.findOnSquare
props.findOnSquare = function(self, square, spriteName)
    local object, instance = previousFind(self, square, spriteName)
    if object or not square or not M.isCokeName(spriteName) then return object, instance end
    local entry = M.tiles[spriteName]
    local objects = square:getObjects()
    for i=objects:size()-1,0,-1 do
        local candidate = objects:get(i)
        if M.entry(candidate)==entry and M.isCokeName(candidate:getSprite():getName()) then
            return candidate
        end
    end
end

-- B42's ForceSingleItem path creates a NEW inventory item after collecting the
-- individual tiles. That final item does not inherit movableData by default.
-- Supply saved roll and chosen appearance when the native code creates the
-- final item or another half. No inventory operations are replaced.
local previousInstance = props.instanceItem
props.instanceItem = function(self, ...)
    local item = previousInstance(self, ...)
    local state = contexts[self]
    if item and state then
        inheritMovableData(item,state.saved)
        if state.roll~=nil then M.writeRoll(item,state.roll) end
        if state.style~=nil then M.writeStyle(item,state.style) end
    end
    return item
end

local function pack(...) return {n=select('#',...), ...} end

local function withIdentity(self, state, fn, ...)
    local previous = contexts[self]
    contexts[self] = state
    local results = pack(pcall(fn, self, ...))
    contexts[self] = previous
    if not results[1] then error(results[2]) end
    return unpack(results, 2, results.n)
end

local previousPickup = props.pickUpMoveable
props.pickUpMoveable = function(self, character, square, ...)
    if not M.tiles[self.spriteName] then return previousPickup(self,character,square,...) end
    local object = self:findOnSquare(square,self.spriteName)
    local data=object and object:hasModData() and object:getModData().movableData
    local saved=type(data)=='table' and copyTable(data) or nil
    return withIdentity(self,{roll=M.readRoll(object),style=M.spriteStyle(object),saved=saved},previousPickup,character,square,...)
end

local function itemStyle(item)
    if not item then return end
    local data=item:getModData()
    if type(data.modData)=='table' then inheritMovableData(item,data.modData.movableData) end
    local style=M.readStyle(item)
    if style then return style end
    local name=item.getWorldSprite and item:getWorldSprite()
    if name and M.tiles[name] then return M.isCokeName(name) and 'coke' or 'vanilla' end
end

local previousPlace = props.placeMoveable
props.placeMoveable = function(self, character, square, ...)
    if not M.tiles[self.spriteName] or not self.isMultiSprite or not self.isForceSingleItem then
        return previousPlace(self,character,square,...)
    end
    local item = self:findInInventoryMultiSprite(character,self.name .. ' (1/1)')
    local style=itemStyle(item)
    local data=item and item:hasModData() and item:getModData().movableData
    local saved=type(data)=='table' and copyTable(data) or nil
    return withIdentity(self,{roll=M.readRoll(item),style=style,saved=saved},previousPlace,character,square,...)
end

local previousPlaceInternal=props.placeMoveableInternal
props.placeMoveableInternal=function(self,character,square,item,spriteName,...)
    if M.tiles[spriteName] and item then
        local style=itemStyle(item)
        if style then M.writeStyle(item,style) end
    end
    return previousPlaceInternal(self,character,square,item,spriteName,...)
end
