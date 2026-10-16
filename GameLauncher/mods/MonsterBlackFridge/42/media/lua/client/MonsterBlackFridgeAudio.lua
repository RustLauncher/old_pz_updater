require 'MonsterBlackFridge/Core'
local M=MonsterBlackFridge
M.audio=M.audio or {}
local A=M.audio
local active={}
local sounds={'FridgeHumA','FridgeHumB','FridgeHumC','FridgeHumD','FridgeHumE','FridgeHumF'}

function A.stop(object)
    local state=active[object]
    if not state then return end
    state.emitter:stopAll()
    state.world:returnOwnershipOfEmitter(state.emitter)
    active[object]=nil
end

local function nearby(square)
    for i=0,getNumActivePlayers()-1 do
        local player=getSpecificPlayer(i)
        if player and player:getSquare() then
            local dx=player:getX()-(square:getX()+0.5)
            local dy=player:getY()-(square:getY()+0.5)
            local dz=(player:getZ()-square:getZ())*3
            if dx*dx+dy*dy+dz*dz<=225 then return true end
        end
    end
    return false
end

function A.refresh(object,powered)
    local square=object:getSquare()
    if not M.isMonster(object) or not square or object:getObjectIndex()<0 then
        A.stop(object)
        return
    end
    local chunk=object:getChunk()
    -- The shared native ambient queue plays only 16 nearby objects. A large
    -- group of fridges competes for those slots as the listener walks around.
    -- Own one spatial emitter per nearby Monster, using the unchanged native
    -- sounds. Remove only this object's ambient entry to prevent duplicate hum.
    if chunk and chunk:hasObjectAmbientEmitter(object) then chunk:removeObjectAmbientEmitter(object) end
    if not powered or not nearby(square) then A.stop(object);return end
    local state=active[object]
    if not state then
        local world=getWorld()
        local emitter=world:getFreeEmitter(square:getX()+0.5,square:getY()+0.5,square:getZ())
        world:takeOwnershipOfEmitter(emitter)
        local roll=M.readRoll(object) or M.rollAt(square:getX(),square:getY(),square:getZ(),0)
        state={world=world,emitter=emitter,sound=sounds[roll%6+1]}
        active[object]=state
    end
    local emitter=state.emitter
    emitter:setPos(square:getX()+0.5,square:getY()+0.5,square:getZ())
    if not emitter:isPlaying(state.sound) then
        state.instance=emitter:playSoundImpl(state.sound,false,nil)
        state.generator=nil
    end
    local generator=object:hasGridPower() and 0 or 1
    if state.instance and state.instance~=0 and state.generator~=generator then
        emitter:setParameterValueByName(state.instance,'Generator',generator)
        state.generator=generator
    end
    emitter:tick()
end

function A.stopAll()
    for object in pairs(active) do A.stop(object) end
end
Events.OnGameStart.Add(A.stopAll)
Events.OnMainMenuEnter.Add(A.stopAll)
