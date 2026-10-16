require 'MonsterBlackFridge/Core'
local M=MonsterBlackFridge
M.light=M.light or {}
local L=M.light
local active={}
local managed={}
local red,green,blue,radius=26/255,77/255,8/255,2

-- Keep the object's native light slot, so unloading and Nick's plug actions
-- can reach it. Never remove a light by square: another lamp can share it.
local function remove(object,light,cell)
    if not light then return end
    light:setActive(false)
    cell:removeLamppost(light)
    if object:getLightSource()==light then object:setLightSource(nil) end
end

local function create(object,cell,square,r,g,b,range)
    local light=IsoLightSource.new(square:getX(),square:getY(),square:getZ(),r,g,b,range)
    light:setActive(true)
    cell:addLamppost(light)
    object:setLightSource(light)
    return light
end

function L.stop(object)
    managed[object]=nil
    local state=active[object]
    if not state then return false end
    remove(object,state.light,state.cell)
    active[object]=nil
    return true
end

function L.refresh(object,powered)
    local square=object:getSquare()
    local cell=getCell()
    if not square or object:getObjectIndex()<0 or not cell then L.stop(object);return end
    if not M.isMonster(object) then
        -- A sandbox change can turn the same object back into a vanilla fridge.
        -- Restore its native light only if we actually owned the previous one.
        local wasManaged=managed[object]
        L.stop(object)
        if wasManaged and not object:getLightSource() then
            local props=object:getProperties()
            local r,g,b=tonumber(props:get('lightR')),tonumber(props:get('lightG')),tonumber(props:get('lightB'))
            if r and g and b then
                if powered then
                    create(object,cell,square,r/255,g/255,b/255,tonumber(props:get('LightRadius')) or 10)
                else
                    -- Keep a pending restoration across an outage or unplug.
                    managed[object]=true
                end
            end
        end
        return
    end
    local light=object:getLightSource()
    local state=active[object]
    if state and (state.light~=light or state.cell~=cell) then L.stop(object) end
    light=object:getLightSource()
    if not powered then
        L.stop(object)
        light=object:getLightSource()
        if light then remove(object,light,cell) end
        managed[object]=true
        return
    end
    -- The native lighting engine caches position/radius at registration. Moving
    -- a source requires replacing it, not merely changing its coordinates.
    if light and (light:getX()~=square:getX() or light:getY()~=square:getY()
        or light:getZ()~=square:getZ() or light:getRadius()~=radius) then
        remove(object,light,cell)
        active[object]=nil
        light=nil
    end
    if not light then light=create(object,cell,square,red,green,blue,radius) end
    -- RGB changes are synchronized by the native LightingJNI update. Existing
    -- saves and lights recreated by Nick receive the same tint as new objects.
    light:setR(red);light:setG(green);light:setB(blue)
    light:setActive(true)
    if not active[object] then active[object]={light=light,cell=cell} end
    managed[object]=true
    -- No ambient-light feedback loop: the engine blends this fixed emission
    -- with room/daylight. Switching room lights off reveals the green spill.
end

function L.stopAll()
    for object in pairs(managed) do L.stop(object) end
end
Events.OnGameStart.Add(L.stopAll)
Events.OnMainMenuEnter.Add(L.stopAll)
