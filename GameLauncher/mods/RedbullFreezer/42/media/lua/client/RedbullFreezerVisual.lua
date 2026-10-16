require 'RedbullFreezer/Core'
require 'RedbullFreezerLight'
local M = RedbullFreezer
local tracked = setmetatable({}, {__mode='k'})
local ticks, sweep = 0, nil
local prepared = {}
local prefix = 'RedbullFreezer_'

-- These are appearance thresholds only. Never change capacity or real items.
function M.stockLevel(object)
    local weight,capacity=0,0
    for i=0,object:getContainerCount()-1 do
        local container=object:getContainerByIndex(i)
        local kind=container and container:getType()
        if kind=='freezer' or kind=='freezeroff' then
            weight=weight+math.max(0,container:getCapacityWeight())
            capacity=capacity+math.max(0,container:getCapacity())
        end
    end
    if capacity<=0 then return 0 end
    if weight>=capacity*0.30 then return 2 end
    if weight>=capacity*0.15 then return 1 end
    return 0
end

function M.isPowered(object)
    for i=0,object:getContainerCount()-1 do
        local container=object:getContainerByIndex(i)
        local kind=container and container:getType()
        if kind=='freezeroff' or kind=='fridgeoff' then return false end
    end
    return object:checkObjectPowered()
end

local function clearOurOverlay(object)
    local overlay=object:getOverlaySprite()
    local name=overlay and overlay:getName()
    if name and string.sub(name,1,#prefix)==prefix then
        object:setOverlaySprite(nil,false)
    end
end

local function prepareDepth(name)
    if prepared[name] or not TileDepthTextureAssignmentManager then return end
    -- Register texture-only LED sprites before assigning their native depth.
    if not getSprite(name) then return end
    TileDepthTextureAssignmentManager.getInstance():assignDepthTextureToSprite('RedbullFreezer',name)
    prepared[name]=true
end

function M.refresh(object)
    if not object then return end
    if not object:getSquare() or object:getObjectIndex()<0 or not M.entry(object) then
        M.light.stop(object)
        if tracked[object] then clearOurOverlay(object) end
        tracked[object]=nil
        return
    end
    local powered=M.isPowered(object)
    M.light.refresh(object,powered)
    if not M.isRedbull(object) then
        clearOurOverlay(object)
        tracked[object]=nil
        return
    end
    tracked[object]=true
    local sprite=object:getSprite()
    M.prepareSprite(sprite)
    prepareDepth(sprite:getName())
    -- Keep Nick's zero-scale onOverlay plug marker untouched. Our LED uses
    -- only a normal overlay; no HasLightOnSprite flag / double lighting pass.
    local desired=prefix..M.entry(object).direction..(powered and '_light_' or '_stock_')..M.stockLevel(object)
    prepareDepth(desired)
    local overlay=object:getOverlaySprite()
    if not overlay or overlay:getName()~=desired then object:setOverlaySprite(desired,false) end
    if powered then
        -- Restore native electricity audio only if it is missing after replug.
        local chunk=object:getChunk()
        if chunk and not chunk:hasObjectAmbientEmitter(object) then object:checkHaveElectricity() end
    end
end

-- Inventory transfers may invoke native overlays AFTER OnContainerUpdate.
-- Refresh at that exact call site so no vanilla-food flash or empty frame
-- appears. Preserve other mods' wrappers and the rest of ItemPicker's API.
function M.installItemPickerHook()
    local previous=ItemPicker
    if not previous or previous==M.itemPickerProxy or not previous.updateOverlaySprite then return end
    local previousUpdate=previous.updateOverlaySprite
    local proxy={}
    proxy.updateOverlaySprite=function(object,...)
        if M.isRedbull(object) then M.refresh(object);return end
        return previousUpdate(object,...)
    end
    setmetatable(proxy,{
        __index=function(_,key)return previous[key]end,
        __newindex=function(_,key,value)previous[key]=value end,
    })
    M.itemPickerProxy=proxy;ItemPicker=proxy
end

-- Nick owns the plug state and generator bookkeeping. Observe its completed
-- light action so the matching stock/LED state changes without a tick delay.
function M.installNickHook()
    local tof=TurnOffFridges
    if not tof or not tof.applyLight or tof.applyLight==M.nickLightWrapper then return end
    local previous=tof.applyLight
    local function wrapper(object,unplugged,...)
        local result=previous(object,unplugged,...)
        if M.isRedbull(object) then M.refresh(object) end
        return result
    end
    M.nickLightWrapper=wrapper;tof.applyLight=wrapper
end

function M.scanSquare(square)
    if not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        if M.entry(object) then M.refresh(object) end
    end
end

local function refreshTracked()
    local cell=getCell()
    if not cell then return end
    for object in pairs(tracked) do
        local square=object:getSquare()
        if not square or object:getObjectIndex()<0 or cell:getGridSquare(square:getX(),square:getY(),square:getZ())~=square then
            M.light.stop(object);tracked[object]=nil
        else
            M.refresh(object)
        end
    end
end

local function sweepColumn()
    if not sweep then return end
    local cell=getCell()
    if not cell or sweep.player>=getNumActivePlayers() then sweep=nil;return end
    local player=getSpecificPlayer(sweep.player)
    if not player or not player:getSquare() then sweep.player=sweep.player+1;sweep.dx=-12;return end
    local x=math.floor(player:getX())+sweep.dx
    local y,z=math.floor(player:getY()),math.floor(player:getZ())
    for zz=z-1,z+1 do
        for yy=y-12,y+12 do M.scanSquare(cell:getGridSquare(x,yy,zz)) end
    end
    sweep.dx=sweep.dx+1
    if sweep.dx>12 then sweep.player=sweep.player+1;sweep.dx=-12 end
end

function M.onTick()
    ticks=ticks+1
    -- Only customized freezers are retained; light registration is idempotent.
    if ticks%10==0 then refreshTracked() end
    if ticks%180==0 and not sweep then sweep={player=0,dx=-12} end
    sweepColumn()
end
function M.onObjectRemoved(object)
    if not object then return end
    M.light.stop(object)
    if tracked[object] then clearOurOverlay(object);tracked[object]=nil end
end
function M.resetVisuals()
    M.light.stopAll()
    tracked=setmetatable({}, {__mode='k'});prepared={};ticks=0;sweep=nil
end
function M.onGameStart()
    M.installItemPickerHook();M.installNickHook()
    M.resetVisuals();sweep={player=0,dx=-12}
end
M.installItemPickerHook();M.installNickHook()
Events.OnGameBoot.Add(M.installItemPickerHook)
Events.OnGameBoot.Add(M.installNickHook)
Events.LoadGridsquare.Add(M.scanSquare)
Events.OnObjectAdded.Add(M.refresh)
Events.OnObjectAboutToBeRemoved.Add(M.onObjectRemoved)
Events.OnContainerUpdate.Add(refreshTracked)
Events.OnGameStart.Add(M.onGameStart)
Events.OnMainMenuEnter.Add(M.resetVisuals)
Events.OnTick.Add(M.onTick)
