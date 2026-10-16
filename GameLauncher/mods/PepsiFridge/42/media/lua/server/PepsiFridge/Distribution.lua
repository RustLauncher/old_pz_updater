require 'PepsiFridge/Core'
if isClient() then return end
local M = PepsiFridge
local worldSeed
local function seed()
    if worldSeed==nil then
        local data=ModData.getOrCreate('PepsiFridge')
        if type(data.seed)~='number' then data.seed=ZombRand(1000000) end
        worldSeed=data.seed
    end
    return worldSeed
end

function M.apply(object)
    if not object or not object:getSquare() or object:getObjectIndex()<0 then return end
    local entry=M.entry(object)
    if not entry then return end
    local square=object:getSquare()
    local current=object:getSprite():getName()
    local roll=M.readRoll(object) or M.rollAt(square:getX(),square:getY(),square:getZ(),seed())
    local desired=entry.vanilla
    local fixedStyle=M.savedStyle(object)
    local wornRoll=M.readWornRoll(object)
    local legacyClean=M.isLegacyClean(object) or (current==entry.pepsi and wornRoll==nil)
    if fixedStyle then
        desired=entry[fixedStyle]
    elseif roll<M.percent() then
        -- Clean Pepsi fridges from older saves have no wear roll. Keep them
        -- clean even if the spawn chance changes and later changes back.
        if legacyClean then
            desired=entry.pepsi
        else
            wornRoll=wornRoll or M.wornRollAt(square:getX(),square:getY(),square:getZ(),seed())
            desired=wornRoll<M.wornPercent() and entry.worn or entry.pepsi
        end
    end
    local replacement=getSprite(desired)
    -- getSprite can return a blank sprite on a miss. Check actual tile properties.
    if not replacement or not replacement:getProperties():has('IsMoveAble') then return end
    if desired==entry.pepsi or desired==entry.worn then M.prepareSprite(replacement) end
    local changed=M.writeRoll(object,roll)
    if fixedStyle and M.writeStyle(object,fixedStyle) then changed=true end
    if legacyClean and M.markLegacyClean(object) then changed=true end
    if wornRoll~=nil and M.writeWornRoll(object,wornRoll) then changed=true end
    if current~=desired then
        local unplugged=false
        for i=0,object:getContainerCount()-1 do
            local kind=object:getContainerByIndex(i):getType()
            if kind=='fridgeoff' or kind=='freezeroff' then unplugged=true end
        end
        -- Nick uses onOverlay as a suppression marker while unplugged.
        if not unplugged then object:clearOnOverlay() end
        object:setOverlaySprite(nil,false)
        object:setSprite(replacement)
        square:RecalcAllWithNeighbours(true)
        if isServer() then object:transmitUpdatedSpriteToClients() end
        if desired==entry.vanilla and ItemPicker and ItemPicker.updateOverlaySprite then
            ItemPicker.updateOverlaySprite(object)
        end
    end
    if changed and isServer() then object:transmitModData() end
end

function M.distributeSquare(square)
    if not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do M.apply(objects:get(i)) end
end
MapObjects.OnNewWithSprite(M.names,M.apply,20)
MapObjects.OnLoadWithSprite(M.names,M.apply,20)
Events.OnObjectAdded.Add(M.apply)
Events.LoadGridsquare.Add(M.distributeSquare)
Events.OnInitGlobalModData.Add(function()worldSeed=nil end)
