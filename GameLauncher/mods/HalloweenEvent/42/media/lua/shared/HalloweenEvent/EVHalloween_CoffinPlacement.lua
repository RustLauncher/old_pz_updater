-- Native furniture setup; the old module name remains for saved compatibility.
require "HalloweenEvent/EVHalloween_Items"
local Items=HalloweenEvent.Items
local C={fullType=Items.legacyCoffinType,nativeType=Items.coffinType,capacity=40,surface=12}
Items.CoffinPlacement=C
function C.configure()
    if C.configured then return true end
    if type(getSprite)~="function" then return false end
    local sprites={}
    for i=0,3 do
        local sprite=getSprite("evh_coffins_01_"..i)
        if not sprite then return false end
        sprites[i+1]=sprite
    end
    -- Coffin storage is explicitly 40; it no longer inherits crate capacity.
    C.capacitySource="coffin:40"
    local facings={"S","W","N","E"}
    for i,sprite in ipairs(sprites) do
        local p=sprite:getProperties()
        p:set("IsMoveAble","true")
        p:set("MoveType","Object")
        p:set("CustomItem",Items.coffinType)
        p:set("PickUpWeight","75")
        p:set("container","crate")
        p:set("ContainerCapacity",tostring(C.capacity))
        p:set("IsStackable","true")
        p:set("IsTable","true")
        p:unset("IsTableTop")
        p:unset("IsSurfaceOffset")
        p:set("Facing",facings[i])
        p:set("Surface",tostring(C.surface))
        p:set("ItemHeight",tostring(C.surface))
        p:CreateKeySet()
    end
    C.configured=true
    HalloweenEvent.log("ITEMS COFFIN_FURNITURE_READY weight=7.5 capacity="..C.capacity
        .." reference="..C.capacitySource.." moveType=Object facings=S/W/N/E surface="..C.surface.." stackLimit=3 visual=native_prop_model")
    return true
end
function C.isCoffin(object)
    local sprite=object and object:getSprite()
    local name=sprite and sprite:getName()
    return name and name:match("^evh_coffins_01_[0-3]$")~=nil or false
end
function C.scan(square)
    if not square or not C.configure() then return end
    local objects=square:getObjects()
    local previous
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        if C.isCoffin(object) then
            -- Saved containers retain capacity. Keep their contents and their
            -- crate type (loot/moveable compatibility); update only capacity.
            for n=0,object:getContainerCount()-1 do
                local container=object:getContainerByIndex(n)
                if container and container:getCapacity()~=C.capacity then container:setCapacity(C.capacity) end
            end
            local oldOffset=object:getRenderYOffset()
            local offset=oldOffset
            if previous then
                local step=oldOffset-previous.oldOffset
                -- Compact existing 19-unit stacks, as well as mixed old/new
                -- stacks. Preserve the base height when on other furniture.
                if math.abs(step-19)<.01 or math.abs(step-C.surface)<.01 then
                    offset=previous.offset+C.surface
                end
            end
            if offset~=oldOffset then
                object:setRenderYOffset(offset)
                if not isServer() then object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_REDRAW) end
            end
            previous={oldOffset=oldOffset,offset=offset}
        else
            local sprite=object:getSprite()
            if sprite and sprite:getProperties():has("IsTable") then previous=nil end
        end
    end
end
function C.initItem(item)
    if not item or item:getFullType()~=Items.coffinType then return false end
    if not C.configure() then return false end
    local name=item:getWorldSprite()
    if not name or not name:match("^evh_coffins_01_[0-3]$") then
        if not item:ReadFromWorldSprite("evh_coffins_01_0") then return false end
    end
    item:setActualWeight(7.5);item:setWeight(7.5)
    return true
end
-- At the prop's actual visual height the native 96-unit ceiling would
-- permit five. Keep the requested three-coffin limit scoped to this furniture.
function C.installStackLimit()
    local props=ISMoveableSpriteProps
    if not props or props.EVHCoffinStackLimit then return end
    local canPlace=props.canPlaceMoveableInternal
    if type(canPlace)~="function" then return end
    props.EVHCoffinStackLimit=true
    props.canPlaceMoveableInternal=function(self,character,square,item,forceTypeObject)
        if self.customItem==Items.coffinType and square then
            local count=0
            local objects=square:getObjects()
            for i=0,objects:size()-1 do
                local object=objects:get(i)
                local sprite=object:getSprite()
                local name=sprite and sprite:getName()
                if object~=self.object and name and name:match("^evh_coffins_01_[0-3]$") then
                    count=count+1
                end
            end
            if count>=3 then return false end
        end
        return canPlace(self,character,square,item,forceTypeObject)
    end
end
function C.audit()
    C.installStackLimit()
    if not C.configure() then
        HalloweenEvent.log("ITEMS COFFIN_FURNITURE_FAILED reason=tile_definitions_unavailable")
        return false
    end
    local item=instanceItem(Items.coffinType)
    local valid=item and instanceof(item,"Moveable") and C.initItem(item)
    HalloweenEvent.log("ITEMS COFFIN_NATIVE_CHECK moveable="..tostring(valid==true)
        .." worldSprite="..tostring(item and item:getWorldSprite()).." capacity="..C.capacity)
    if not isServer() then
        local cell=getCell()
        for n=0,getNumActivePlayers()-1 do
            local player=getSpecificPlayer(n)
            if cell and player then
                local x,y,z=math.floor(player:getX()),math.floor(player:getY()),math.floor(player:getZ())
                for dx=-16,16 do for dy=-16,16 do C.scan(cell:getGridSquare(x+dx,y+dy,z)) end end
            end
        end
    end
    return valid==true
end
if Events.LoadGridsquare then Events.LoadGridsquare.Add(C.scan) end
if Events.OnObjectAdded then Events.OnObjectAdded.Add(function(object)
    if object and C.isCoffin(object) then C.scan(object:getSquare()) end
end) end
if Events.OnGameBoot then Events.OnGameBoot.Add(C.installStackLimit) end
if Events.OnGameStart then Events.OnGameStart.Add(C.audit) end
if Events.OnServerStarted then Events.OnServerStarted.Add(C.audit) end
return C
