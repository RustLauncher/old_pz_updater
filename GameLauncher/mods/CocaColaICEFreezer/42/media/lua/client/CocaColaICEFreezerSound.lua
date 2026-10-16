require 'CocaColaICEFreezer/Core'
-- Build 42.20.4: recover vanilla ICE freezer hum after a saved unplugged
-- container is renamed by Nick's Turn Off Fridges. Client audio only.
CocaColaICEFreezerSound = CocaColaICEFreezerSound or {}
local M = CocaColaICEFreezerSound
local targets = {
    appliances_refrigeration_01_20=true, appliances_refrigeration_01_21=true,
    appliances_refrigeration_01_38=true, appliances_refrigeration_01_39=true,
    CocaColaICEFreezer_01_0=true, CocaColaICEFreezer_01_1=true,
    CocaColaICEFreezer_01_2=true, CocaColaICEFreezer_01_3=true,
}
for _,name in ipairs(CocaColaICEFreezer.names) do targets[name]=true end
local tracked = setmetatable({}, {__mode='k'})
local ticks = 0
local sweep = nil

function M.refreshAmbientSound(object, powered)
    if not powered then return end
    local chunk = object:getChunk()
    if chunk and not chunk:hasObjectAmbientEmitter(object) then
        -- The engine owns volume, range, power checks, stopping and deduplication.
        object:checkHaveElectricity()
    end
end

function M.refresh(object)
    if not object then return end
    local sprite = object:getSprite()
    if not object:getSquare() or object:getObjectIndex()<0
        or not sprite or not targets[sprite:getName()] then
        tracked[object]=nil
        return
    end
    tracked[object]=true
    local freezer = nil
    for i=0,object:getContainerCount()-1 do
        local container = object:getContainerByIndex(i)
        if container then
            local kind = container:getType()
            -- Nick's keeps a zero-scale overlay here to block the engine's
            -- powered lid. Never remove that per-object off-state marker.
            if kind=='freezeroff' or kind=='fridgeoff' then return end
            if kind=='freezer' then freezer=container end
        end
    end
    -- A network sprite update can leave the previously cached illuminated lid
    -- on the client. Let the engine rebuild it for the current freezer variant.
    local onOverlay = object:getOnOverlay()
    if onOverlay and onOverlay:getScaleX() ~= 0 then
        local name = sprite:getName()
        local expected = string.gsub(name, '_(%d+)$', '_on_%1')
        local parent = onOverlay:getParentSprite()
        local parentName = parent and parent:getName()
        if parentName and parentName ~= expected and string.match(parentName, '_on_%d+$') then
            local baseName = string.gsub(parentName, '_on_(%d+)$', '_%1')
            if targets[baseName] then object:clearOnOverlay() end
        end
    end
    -- Respect other mods' container types and the native grid/generator predicate.
    if freezer then M.refreshAmbientSound(object,freezer:isPowered()) end
end

function M.scanSquare(square)
    if not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        local sprite=object and object:getSprite()
        if sprite and targets[sprite:getName()] then M.refresh(object) end
    end
end

local function refreshTracked()
    local cell=getCell()
    if not cell then return end
    for object in pairs(tracked) do
        local square=object:getSquare()
        if not square or object:getObjectIndex()<0
            or cell:getGridSquare(square:getX(),square:getY(),square:getZ())~=square then
            tracked[object]=nil
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
    if not player or not player:getSquare() then
        sweep.player=sweep.player+1;sweep.dx=-12;return
    end
    local x=math.floor(player:getX())+sweep.dx
    local y=math.floor(player:getY())
    local z=math.floor(player:getZ())
    for iz=z-1,z+1 do
        for iy=y-12,y+12 do M.scanSquare(cell:getGridSquare(x,iy,iz)) end
    end
    sweep.dx=sweep.dx+1
    if sweep.dx>12 then sweep.player=sweep.player+1;sweep.dx=-12 end
end

function M.onTick()
    ticks=ticks+1
    if ticks%30==0 then refreshTracked() end
    if ticks%180==0 and not sweep then sweep={player=0,dx=-12} end
    sweepColumn()
end

function M.onGameStart()
    ticks=0;sweep={player=0,dx=-12}
    refreshTracked()
end

function M.onObjectRemoved(object) tracked[object]=nil end

Events.LoadGridsquare.Add(M.scanSquare)
Events.OnObjectAdded.Add(M.refresh)
Events.OnObjectAboutToBeRemoved.Add(M.onObjectRemoved)
Events.OnGameStart.Add(M.onGameStart)
Events.OnTick.Add(M.onTick)
