-- Cosmetic stock/power rendering. Distribution is owned by the server.
require 'PepsiFridge/Core'
require 'PepsiFridgeDepth'
require 'PepsiFridgeAudio'
require 'PepsiFridgeLight'
require 'PepsiFridgeFront'
local M = PepsiFridge
local targets = {
    PepsiFridge_01_0={direction=40,prefix='PepsiFridge_'},
    PepsiFridge_01_1={direction=41,prefix='PepsiFridge_'},
    PepsiFridgeWorn_01_0={direction=40,prefix='PepsiFridgeWorn_'},
    PepsiFridgeWorn_01_1={direction=41,prefix='PepsiFridgeWorn_'},
}
local allTargets = M.tiles
local tracked = setmetatable({}, {__mode='k'})
local ticks = 0
local prefixes = {'PepsiFridge_', 'PepsiFridgeWorn_'}
-- Nick's Turn Off Fridges stores the plug state in the container TYPE. The
-- contents are still there when a fridge/freezer becomes fridgeoff/freezeroff.
local storageTypes = {fridge=true, freezer=true, fridgeoff=true, freezeroff=true}
local unpluggedTypes = {fridgeoff=true, freezeroff=true}

function M.stockLevel(object)
    local weight, capacity, hasItems = 0, 0, false
    for i=0,object:getContainerCount()-1 do
        local container=object:getContainerByIndex(i)
        if container and storageTypes[container:getType()] then
            weight=weight+math.max(0,container:getCapacityWeight())
            capacity=capacity+math.max(0,container:getCapacity())
            hasItems=hasItems or not container:isEmpty()
        end
    end
    if not hasItems then return 0 end
    if capacity<=0 then return 0 end
    local ratio=weight/capacity
    if ratio>=0.30 then return 3 end
    if ratio>=0.20 then return 2 end
    if ratio>=0.10 then return 1 end
    return 0
end

function M.isPowered(object)
    for i=0,object:getContainerCount()-1 do
        local container=object:getContainerByIndex(i)
        if container and unpluggedTypes[container:getType()] then return false end
    end
    -- The native predicate tests square electricity, not the manual plug state.
    return object:checkObjectPowered()
end

local function clearOurOverlay(object)
    local overlay=object:getOverlaySprite()
    local name=overlay and overlay:getName()
    if name then
        for _,prefix in ipairs(prefixes) do
            if string.sub(name,1,#prefix)==prefix then
                object:setOverlaySprite(nil,false)
                return true
            end
        end
    end
end

function M.refreshAmbientSound(object, powered)
    if M.isPepsi(object) and M.audio then return M.audio.refresh(object,powered) end
    if M.audio then M.audio.stop(object) end
    if not powered then return end
    local chunk=object:getChunk()
    -- A fridge loaded as fridgeoff has no FridgeHumLogic. Nick restores its
    -- container type and light on replug, but may not re-register that emitter.
    -- Let the native electricity handler create it only when it is missing.
    -- The native logic owns distance, volume, random hum and stopping on unplug.
    if chunk and not chunk:hasObjectAmbientEmitter(object) then
        object:checkHaveElectricity()
    end
end

function M.refresh(object)
    if not object or not object:getSquare() or object:getObjectIndex()<0 then
        if object and M.audio then M.audio.stop(object) end
        if object and M.light then M.light.stop(object) end
        if object then tracked[object]=nil end
        return
    end
    local sprite=object:getSprite()
    local name=sprite and sprite:getName()
    if not allTargets[name] then
        if M.audio then M.audio.stop(object) end
        if M.light then M.light.stop(object) end
        if tracked[object] then clearOurOverlay(object) end
        tracked[object]=nil
        return
    end
    local powered=M.isPowered(object)
    local displayLit=powered
    if M.light then displayLit=M.light.refresh(object,powered) end
    M.refreshAmbientSound(object,powered)
    tracked[object]=true
    if not M.isPepsi(object) then
        -- Existing saves can contain an overlay from the previous all-Pepsi
        -- version. Restore the native contents overlay only when removing ours.
        if clearOurOverlay(object) and ItemPicker and ItemPicker.updateOverlaySprite then
            ItemPicker.updateOverlaySprite(object)
        end
        return
    end
    M.prepareSprite(sprite)
    if M.prepareDepth then M.prepareDepth(name) end
    local target=targets[name]
    if not target then
        -- Rear views still need the native hum even though no stock is visible.
        clearOurOverlay(object)
        return
    end
    local level=M.stockLevel(object)
    if M.front then M.front.refresh(object) end
    local desired=target.prefix..target.direction..(displayLit and '_light_' or '_stock_')..level
    if M.prepareDepth then M.prepareDepth(desired) end
    local overlay=object:getOverlaySprite()
    if not overlay or overlay:getName()~=desired then
        object:setOverlaySprite(desired,false)
    end
    tracked[object]=true
end

-- Inventory transfers call ItemPicker.updateOverlaySprite AFTER changing their
-- containers. Letting that write the native food_01/food_02 sprite and repairing
-- it on a later tick exposes a visible flash. Intercept only our two fronts at
-- that call site, so the native food overlay is never written during a transfer.
-- Other ItemPicker methods/fields and all other furniture retain their original
-- implementation, including hooks installed by another mod before this one.
function M.installItemPickerHook()
    local previous=ItemPicker
    if not previous or previous==M.itemPickerProxy or not previous.updateOverlaySprite then return end
    local previousUpdate=previous.updateOverlaySprite
    local proxy={}
    proxy.updateOverlaySprite=function(object,...)
        local sprite=object and object:getSprite()
        if sprite and targets[sprite:getName()] then
            M.refresh(object)
            return
        end
        return previousUpdate(object,...)
    end
    setmetatable(proxy,{
        __index=function(_,key) return previous[key] end,
        __newindex=function(_,key,value) previous[key]=value end,
    })
    M.itemPickerProxy=proxy
    ItemPicker=proxy
end

function M.scanSquare(square)
    if not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        local sprite=object:getSprite()
        if sprite and allTargets[sprite:getName()] then M.refresh(object) end
    end
end

local function refreshTracked()
    local cell=getCell()
    if not cell then return end
    for object in pairs(tracked) do
        local sq=object:getSquare()
        if not sq or object:getObjectIndex()<0 or cell:getGridSquare(sq:getX(),sq:getY(),sq:getZ())~=sq then
            if M.audio then M.audio.stop(object) end
            if M.light then M.light.stop(object) end
            tracked[object]=nil
        else
            M.refresh(object)
        end
    end
end

-- Catch nearby squares that loaded before OnGameStart, as well as placed/rotated
-- furniture on multiplayer clients. Each tick scans ONE column around ONE player.
local sweep=nil
local function beginSweep()
    sweep={player=0,dx=-12}
end
local function sweepColumn()
    if not sweep then return end
    local cell=getCell()
    if not cell or sweep.player>=getNumActivePlayers() then sweep=nil;return end
    local player=getSpecificPlayer(sweep.player)
    if not player or not player:getSquare() then
        sweep.player=sweep.player+1;sweep.dx=-12;return
    end
    local px=math.floor(player:getX())+sweep.dx
    local py=math.floor(player:getY())
    local pz=math.floor(player:getZ())
    for z=pz-1,pz+1 do
        for y=py-12,py+12 do M.scanSquare(cell:getGridSquare(px,y,z)) end
    end
    sweep.dx=sweep.dx+1
    if sweep.dx>12 then sweep.player=sweep.player+1;sweep.dx=-12 end
end

function M.onTick()
    ticks=ticks+1
    -- Also recover direct engine/network overlay updates on the next simulation
    -- tick and follow manual power toggles without the old half-second delay.
    -- This visits only discovered Pepsi fridges; unchanged sprites are not set.
    refreshTracked()
    if ticks%180==0 and not sweep then beginSweep() end
    sweepColumn()
end

function M.onContainerUpdate()
    -- This event can carry nil, not necessarily the container that changed.
    refreshTracked()
end
function M.onObjectRemoved(object)
    if M.audio then M.audio.stop(object) end
    if M.light then M.light.stop(object) end
    if tracked[object] then clearOurOverlay(object);tracked[object]=nil end
end
function M.onGameStart()
    M.installItemPickerHook()
    ticks=0;beginSweep();refreshTracked()
end

M.installItemPickerHook()
Events.OnGameBoot.Add(M.installItemPickerHook)
Events.LoadGridsquare.Add(M.scanSquare)
Events.OnObjectAdded.Add(M.refresh)
Events.OnObjectAboutToBeRemoved.Add(M.onObjectRemoved)
Events.OnContainerUpdate.Add(M.onContainerUpdate)
Events.OnGameStart.Add(M.onGameStart)
Events.OnTick.Add(M.onTick)
