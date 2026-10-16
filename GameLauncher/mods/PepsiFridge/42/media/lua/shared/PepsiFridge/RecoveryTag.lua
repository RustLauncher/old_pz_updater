-- Exact identity for recovery after a missing sprite was resaved.
-- Deferred after all native/mod placement callbacks; this never chooses a style,
-- replaces a MapObjects handler, changes a sprite or edits any container.
require 'PepsiFridge/Core'
local M=PepsiFridge
M.recoveryTag=M.recoveryTag or {}
local T=M.recoveryTag
local pending=setmetatable({},{__mode='k'})
function T.stamp(object)
    if isClient() or not object or not object:getSquare() or object:getObjectIndex()<0 then return false end
    local sprite=object:getSprite()
    local name=sprite and sprite:getName()
    local entry=name and M.tiles[name]
    if not entry or name==entry.vanilla then return false end
    local md=object:getModData()
    if md.movableData~=nil and type(md.movableData)~='table' then return false end
    md.movableData=md.movableData or {}
    local old=md.movableData.VINIFridgeRecovery
    if old~=nil and (type(old)~='table' or old.schema~=1 or old.modId~='PepsiFridge') then return false end
    if old and old.vanilla==entry.vanilla and old.custom==name then return false end
    md.movableData.VINIFridgeRecovery={schema=1,modId='PepsiFridge',vanilla=entry.vanilla,custom=name}
    object:flagForHotSave()
    if isServer() then object:transmitModData() end
    return true
end
local function queue(object) if object and not isClient() then pending[object]=true end end
Events.OnObjectAdded.Add(queue)
Events.LoadGridsquare.Add(function(square)
    if isClient() or not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do queue(objects:get(i)) end
end)
Events.OnTick.Add(function()
    local processed=0
    for object in pairs(pending) do
        T.stamp(object);pending[object]=nil;processed=processed+1
        if processed>=500 then return end
    end
end)
Events.OnMainMenuEnter.Add(function() pending=setmetatable({},{__mode='k'}) end)
