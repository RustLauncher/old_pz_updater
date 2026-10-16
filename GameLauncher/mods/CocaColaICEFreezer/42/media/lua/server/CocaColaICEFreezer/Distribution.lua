require 'CocaColaICEFreezer/Core'
if isClient() then return end
local M = CocaColaICEFreezer
local worldSeed

local function seed()
    if worldSeed == nil then
        local data = ModData.getOrCreate('CocaColaICEFreezer')
        if type(data.seed) ~= 'number' then data.seed = ZombRand(1000000) end
        worldSeed = data.seed
    end
    return worldSeed
end

local function group(object, entry)
    local x,y,z = M.anchor(object,entry)
    local members = {}
    local cell = getCell()
    for part = 0,1 do
        local px = x+(entry.facing=='S' and part or 0)
        local py = y+(entry.facing=='E' and part or 0)
        local ownSquare = object:getSquare()
        local square
        if ownSquare:getX()==px and ownSquare:getY()==py then
            square = ownSquare
        elseif cell then
            square = cell:getGridSquare(px,py,z)
        end
        if square then
            local objects = square:getObjects()
            for i = 0,objects:size()-1 do
                local candidate = objects:get(i)
                local other = M.entry(candidate)
                if other and other.facing == entry.facing then
                    local ax,ay,az = M.anchor(candidate,other)
                    if ax==x and ay==y and az==z then
                        members[#members+1] = {object=candidate,entry=other}
                    end
                end
            end
        end
    end
    return members,x,y,z
end

function M.apply(object)
    if not object or not object:getSquare() or object:getObjectIndex()<0 then return end
    local entry = M.entry(object)
    if not entry then return end
    local members,x,y,z = group(object,entry)
    local roll,fixedStyle
    -- Anchor is first. Its saved roll also resolves inconsistent legacy pairs.
    for _,member in ipairs(members) do
        roll = roll or M.readRoll(member.object)
        fixedStyle = fixedStyle or M.savedStyle(member.object)
        if roll~=nil and fixedStyle~=nil then break end
    end
    roll = roll or M.rollAt(x,y,z,seed())
    local style=fixedStyle or (roll<M.percent() and 'coke' or 'vanilla')
    local coke = style=='coke'
    for _,member in ipairs(members) do
        local obj, tile = member.object, member.entry
        local desired = coke and tile.coke or tile.vanilla
        local replacement = getSprite(desired)
        -- A missing/unloaded custom tile must never erase an existing freezer.
        if replacement and replacement:getSpriteGrid() then
            local dataChanged = M.writeRoll(obj,roll)
            if fixedStyle and M.writeStyle(obj,style) then dataChanged=true end
            if obj:getSprite():getName() ~= desired and not (coke and M.isCokeName(obj:getSprite():getName())) then
                obj:clearOnOverlay()
                obj:setSprite(replacement)
                obj:getSquare():RecalcAllWithNeighbours(true)
                if isServer() then obj:transmitUpdatedSpriteToClients() end
            end
            if dataChanged and isServer() then obj:transmitModData() end
        end
    end
end

function M.scanSquare(square)
    if not square then return end
    local objects = square:getObjects()
    for i = 0,objects:size()-1 do
        local object = objects:get(i)
        if M.entry(object) then M.apply(object) end
    end
end

MapObjects.OnNewWithSprite(M.names, M.apply, 20)
MapObjects.OnLoadWithSprite(M.names, M.apply, 20)
Events.OnObjectAdded.Add(M.apply)
Events.LoadGridsquare.Add(M.scanSquare)
Events.OnInitGlobalModData.Add(function() worldSeed = nil end)
