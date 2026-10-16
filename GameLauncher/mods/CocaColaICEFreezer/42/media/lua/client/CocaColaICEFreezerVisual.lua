require 'CocaColaICEFreezer/Core'
local M=CocaColaICEFreezer
M.visual=M.visual or {}
local V=M.visual
local tracked={}
local lights={}
local prepared={}
local tick=0
local sweep
local prefix='CocaColaICEFreezer_Visual_'
local lightR,lightG,lightB,lightRadius=65/255,8/255,5/255,2

local function coke(object)
    local entry=M.entry(object)
    return entry and M.isCokeName(object:getSprite():getName()) and entry or nil
end
local function valid(object)
    local square=object and object:getSquare()
    local cell=getCell()
    return square and cell and object:getObjectIndex()>=0
        and cell:getGridSquare(square:getX(),square:getY(),square:getZ())==square
end

-- Read each inventory independently. The more occupied side controls BOTH
-- pictures; capacities and item lists are never merged, renamed or written.
function V.fraction(object)
    local greatest=0
    for i=0,object:getContainerCount()-1 do
        local c=object:getContainerByIndex(i)
        if c then
            local kind=c:getType()
            if kind=='freezer' or kind=='freezeroff' then
                local capacity=c:getCapacity()
                if capacity>0 then greatest=math.max(greatest,math.max(0,c:getCapacityWeight())/capacity) end
            end
        end
    end
    return greatest
end
function V.level(fraction)
    if fraction>=0.30 then return 2 end
    if fraction>=0.15 then return 1 end
    return 0
end
function V.powered(object)
    for i=0,object:getContainerCount()-1 do
        local c=object:getContainerByIndex(i)
        if c and (c:getType()=='freezeroff' or c:getType()=='fridgeoff') then return false end
    end
    return object:checkObjectPowered()
end
function V.pair(object)
    local e=coke(object)
    if not e or not valid(object) then return {} end
    local x,y,z=M.anchor(object,e)
    local indices=e.facing=='E' and {0,1} or {2,3}
    local pair={}
    for _,index in ipairs(indices) do
        local name='CocaColaICEFreezer_01_'..index
        local target=M.tiles[name]
        local square=getCell():getGridSquare(x+target.dx,y+target.dy,z)
        if square then
            local objects=square:getObjects()
            for i=0,objects:size()-1 do
                local candidate=objects:get(i)
                if M.entry(candidate)==target and coke(candidate) then
                    pair[#pair+1]=candidate
                    break
                end
            end
        end
    end
    return pair
end

function V.prepare(sprite)
    local e=sprite and M.tiles[sprite:getName()]
    if e and M.isCokeName(sprite:getName()) then
        -- Each state is one complete sprite. A separate lit lid or interior
        -- would blend twice when B42 fades or highlights the object.
        sprite:getProperties():unset(IsoFlagType.HasLightOnSprite)
    end
end
local function depth(name)
    if not prepared[name] and TileDepthTextureAssignmentManager then
        getSprite(name)
        TileDepthTextureAssignmentManager.getInstance():assignDepthTextureToSprite('CocaColaICEFreezer',name)
        prepared[name]=true
    end
end
function V.stopLight(object)
    local state=lights[object]
    if not state then return end
    state.light:setActive(false)
    state.cell:removeLamppost(state.light)
    if object:getLightSource()==state.light then object:setLightSource(nil) end
    lights[object]=nil
end
local function light(object)
    local cell=getCell()
    local square=object:getSquare()
    local state=lights[object]
    if state and (state.cell~=cell or state.light~=object:getLightSource()
        or state.light:getX()~=square:getX() or state.light:getY()~=square:getY()
        or state.light:getZ()~=square:getZ() or state.light:getRadius()~=lightRadius
        or not cell:getLamppostPositions():contains(state.light)) then V.stopLight(object);state=nil end
    if not state then
        -- Preserve an unrelated light supplied by another mod. Never remove a
        -- lamp by square coordinates or adopt ownership of its source.
        if object:getLightSource() then return end
        local source=IsoLightSource.new(square:getX(),square:getY(),square:getZ(),lightR,lightG,lightB,lightRadius)
        cell:addLamppost(source)
        object:setLightSource(source)
        state={cell=cell,light=source};lights[object]=state
    end
    -- Keep the intended emission after electricity/other engine updates.
    -- The native lighting update propagates RGB changes to the renderer.
    state.light:setR(lightR);state.light:setG(lightG);state.light:setB(lightB)
    state.light:setActive(true)
end
local function clearInterior(object)
    local overlay=object:getOverlaySprite()
    if overlay and string.sub(overlay:getName(),1,#prefix)==prefix then object:setOverlaySprite(nil,false) end
end
function V.forget(object)
    V.stopLight(object)
    clearInterior(object)
    tracked[object]=nil
end
function V.refresh(object)
    if not object then return end
    if not valid(object) or not coke(object) then V.forget(object);return end
    local pair=V.pair(object)
    local occupancy=0
    for _,part in ipairs(pair) do occupancy=math.max(occupancy,V.fraction(part)) end
    local level=V.level(occupancy)
    for _,part in ipairs(pair) do
        local sprite=part:getSprite()
        V.prepare(sprite)
        local existing=part:getOnOverlay()
        -- Nick's unplug marker must survive. Remove only an ordinary visible
        -- lid cached before installing the new renderer.
        if existing and existing:getScaleX()~=0 then part:clearOnOverlay() end
        local index=M.entry(part).index
        local powered=V.powered(part)
        local name='CocaColaICEFreezer_State_'..(powered and 'on_' or 'off_')..level..'_'..index
        depth(sprite:getName());depth(name)
        local replacement=getSprite(name)
        if replacement and replacement:getSpriteGrid() then
            V.prepare(replacement)
            if sprite~=replacement then part:setSprite(replacement) end
            -- Remove only this mod's legacy interior, preserving unrelated overlays.
            clearInterior(part)
        end
        tracked[part]=true
        -- B42 light sources are anchored to integer world squares. A single
        -- source on one half illuminates the two-tile freezer asymmetrically.
        -- Each powered half uses the original visible intensity. Halving RGB
        -- when adding the second source made the glow too faint after falloff.
        -- Intensity stays fixed if its neighbour unloads or is unplugged.
        if powered then light(part) else V.stopLight(part) end
    end
end
function V.scan(square)
    if not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        if coke(object) then V.refresh(object) end
    end
end
function V.refreshTracked()
    for object in pairs(tracked) do V.refresh(object) end
end
function V.stopAll()
    for object in pairs(tracked) do V.forget(object) end
    for object in pairs(lights) do V.stopLight(object) end
    tracked={};sweep=nil
end
function V.installHook()
    local previous=ItemPicker
    if not previous or previous==V.itemPickerProxy or not previous.updateOverlaySprite then return end
    local update=previous.updateOverlaySprite
    local proxy={updateOverlaySprite=function(object,...)
        if coke(object) then V.refresh(object);return end
        return update(object,...)
    end}
    setmetatable(proxy,{__index=function(_,key)return previous[key]end,
        __newindex=function(_,key,value)previous[key]=value end})
    V.itemPickerProxy=proxy;ItemPicker=proxy
end
function V.onTick()
    tick=tick+1
    if tick%10==0 then V.refreshTracked() end
    if tick%180==0 and not sweep then sweep={player=0,dx=-12} end
    if not sweep then return end
    local cell=getCell()
    if not cell or sweep.player>=getNumActivePlayers() then sweep=nil;return end
    local p=getSpecificPlayer(sweep.player)
    if not p or not p:getSquare() then sweep.player=sweep.player+1;sweep.dx=-12;return end
    for z=math.floor(p:getZ())-1,math.floor(p:getZ())+1 do
        for y=math.floor(p:getY())-12,math.floor(p:getY())+12 do
            V.scan(cell:getGridSquare(math.floor(p:getX())+sweep.dx,y,z))
        end
    end
    sweep.dx=sweep.dx+1
    if sweep.dx>12 then sweep.player=sweep.player+1;sweep.dx=-12 end
end
V.installHook()
Events.OnGameBoot.Add(V.installHook)
Events.OnGameStart.Add(function()
    V.stopAll();prepared={};tick=0;sweep={player=0,dx=-12}
    for i=0,3 do V.prepare(getSprite('CocaColaICEFreezer_01_'..i)) end
    V.installHook()
end)
Events.LoadGridsquare.Add(V.scan)
Events.OnObjectAdded.Add(V.refresh)
Events.OnObjectAboutToBeRemoved.Add(V.forget)
Events.OnContainerUpdate.Add(V.refreshTracked)
Events.OnTick.Add(V.onTick)
Events.OnMainMenuEnter.Add(V.stopAll)
