require 'DrPepperFridge/Core'
if isClient() then return end
local M=DrPepperFridge
local worldSeed
local pending=setmetatable({},{__mode='k'})
local function seed()
    if worldSeed==nil then
        local data=ModData.getOrCreate('DrPepperFridge')
        if type(data.seed)~='number' then data.seed=ZombRand(1000000) end
        worldSeed=data.seed
    end
    return worldSeed
end
function M.apply(object,placed)
    if not object or not object:getSquare() or object:getObjectIndex()<0 or not M.entry(object) then return true end
    local parts=M.parts(object)
    -- World loading waits for both halves. The native B.T.M. places ONE tile at
    -- a time, so placement may resolve a single half. A later mate inherits its
    -- saved style; both pieces use the same coordinate anchor and random rolls.
    if #parts~=2 and not placed then return false end
    if #parts==0 then return true end
    local x,y,z=M.anchor(object)
    local roll,wornRoll,kind
    for _,part in ipairs(parts) do
        roll=roll or M.readRoll(part);wornRoll=wornRoll or M.readWornRoll(part)
        kind=kind or M.savedStyle(part)
    end
    roll=roll or M.rollAt(x,y,z,seed())
    wornRoll=wornRoll or M.rollAt(x,y,z,tostring(seed())..':worn')
    kind=kind or (roll<M.percent() and (wornRoll<M.wornPercent() and 'worn' or 'clean') or 'vanilla')
    local replacements={}
    for i,part in ipairs(parts) do
        local replacement=getSprite(M.entry(part)[kind])
        if not replacement or not replacement:getProperties():has('IsMoveAble') then return false end
        replacements[i]=replacement
    end
    for i,part in ipairs(parts) do
        local changed=M.writeRoll(part,M.dataKey,roll)
        if M.writeRoll(part,M.wornDataKey,wornRoll) then changed=true end
        if M.writeRoll(part,M.styleDataKey,kind) then changed=true end
        local replacement=replacements[i]
        if kind~='vanilla' then M.prepareSprite(replacement) end
        if part:getSprite():getName()~=replacement:getName() then
            local unplugged=false
            for n=0,part:getContainerCount()-1 do
                local t=part:getContainerByIndex(n):getType()
                if t=='fridgeoff' or t=='freezeroff' then unplugged=true end
            end
            if not unplugged then part:clearOnOverlay() end
            part:setOverlaySprite(nil,false);part:setSprite(replacement)
            part:getSquare():RecalcAllWithNeighbours(true)
            if isServer() then part:transmitUpdatedSpriteToClients() end
            if kind=='vanilla' and ItemPicker and ItemPicker.updateOverlaySprite then ItemPicker.updateOverlaySprite(part) end
        end
        if changed and isServer() then part:transmitModData() end
    end
    return true
end
local function enqueue(object,placed)
    if M.entry(object) then
        local state=pending[object] or {attempts=0}
        state.placed=state.placed or placed==true
        pending[object]=state
    end
end
local function flush()
    local batch=pending;pending=setmetatable({},{__mode='k'})
    for object,state in pairs(batch) do
        if not M.apply(object,state.placed) and state.attempts<60 then
            state.attempts=state.attempts+1;pending[object]=state
        end
    end
end
function M.distributeSquare(square)
    if not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do enqueue(objects:get(i)) end
end
-- Deferring avoids reacting before vanilla placement has copied movableData.
MapObjects.OnNewWithSprite(M.names,function(object)enqueue(object)end,20)
MapObjects.OnLoadWithSprite(M.names,function(object)enqueue(object)end,20)
Events.OnObjectAdded.Add(function(object)enqueue(object,true)end)
Events.LoadGridsquare.Add(M.distributeSquare)
Events.OnTick.Add(flush)
Events.OnInitGlobalModData.Add(function() worldSeed=nil;pending=setmetatable({},{__mode='k'}) end)
