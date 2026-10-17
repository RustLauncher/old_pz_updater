-- Native furniture owns collision, containers, saves, pickup and stacking.
-- Its visual uses the SAME model/script as the correctly rendered dropped item.
require "HalloweenEvent/EVHalloween_CoffinPlacement"
local Items=HalloweenEvent.Items
local FX={records={},disabled=false,logged=false,preview={}}
Items.CoffinVisuals=FX
local rotations={0,90,180,270}
local opposite={N="S",S="N",W="E",E="W"}
local function facing(sprite)
    local name=sprite and sprite:getName()
    local index=name and name:match("^evh_coffins_01_([0-3])$")
    return index and rotations[tonumber(index)+1]
end
local function proxy()
    local item=instanceItem(Items.coffinType)
    if item then item:setWorldStaticModel(Items.byType[Items.coffinType].worldModel) end
    return item
end
local function visibility(object,visible)
    if object:getDoRender()==visible then return end
    object:setDoRender(visible)
    -- Stock ISMoveableCursor does this whenever it hides/restores furniture.
    if object:getSquare() then object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_REDRAW) end
end
local function restore()
    for object,record in pairs(FX.records) do
        object:setAnimating(record.wasAnimating)
        object:setSpriteModelName(nil)
        visibility(object,true)
        if object:getSquare() then object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_REDRAW) end
    end
end
local function failed(err)
    FX.disabled=true;restore()
    HalloweenEvent.log("ITEMS COFFIN_3D_FAILED restoredTile=true reason="..tostring(err))
end
function FX.scan(square)
    if FX.disabled or isServer() or not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        if facing(object:getSprite())~=nil then
            local ok,err=pcall(FX.bind,object)
            if not ok then failed(err);return end
        end
    end
end
function FX.bind(object)
    local rotation=facing(object:getSprite())
    if rotation==nil then return end
    -- Lua division formats integers differently between Lua and Kahlua.
    local name="HalloweenEvent.EVHCoffinFurniture"..tostring(math.floor(rotation/90))
    local model=getScriptManager():getSpriteModel(name)
    if not model then error("missing coffin spriteModel "..name) end
    local record=FX.records[object]
    if not record or record.name~=name or object:getSpriteModel()~=model then
        object:setSpriteModelName(name)
        if record then record.name=name
        else FX.records[object]={name=name,wasAnimating=object:isAnimating()} end
        object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_REDRAW)
    end
    -- The highlighted native model is clean; the static chunk bake loses
    -- surface detail. This flag routes ONLY our coffins through the engine's
    -- live furniture pass. No animation clip, highlight, overlay or new object
    -- is created, and native world lighting/depth/stack offsets still apply.
    if not object:isAnimating() then
        object:setAnimating(true)
        object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_REDRAW)
    end
    if not FX.logged then
        FX.logged=true
        HalloweenEvent.log("ITEMS COFFIN_3D_NATIVE model="..model:getModelScriptName()
            .." nativeFurniturePass=true liveFurniturePass=true chunkBake=false nativeStackOffsets=true previewArrowReversed=true")
    end
end
function FX.update()
    if FX.disabled or isServer() then return end
    FX.installCursor()
    local player=getSpecificPlayer(0);local cell=getCell()
    if not player or not cell then return end
    local cursor=cell:getDrag(player:getPlayerNum())
    for object,record in pairs(FX.records) do
        local square=object:getSquare()
        local valid=square and object:getObjectIndex()>=0 and facing(object:getSprite())~=nil
        if not valid or cell:getGridSquare(square:getX(),square:getY(),square:getZ())~=square then
            object:setAnimating(record.wasAnimating)
            if square and object:getObjectIndex()>=0 and facing(object:getSprite())==nil then
                object:setSpriteModelName(nil)
                visibility(object,true)
                object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_REDRAW)
            end
            FX.records[object]=nil
        else
            FX.bind(object)
            -- The engine renders this object's model in the furniture pass.
            -- Its alpha, camera projection, live furniture pass and stack height
            -- follow the same path as ordinary furniture. Never hide its
            -- underlying surface: elevated items inherit that surface alpha.
            if not cursor or cursor.objectHiddenDuringRotate~=object then visibility(object,true) end
        end
    end
end
function FX.render()
    -- Kept for compatibility with prior diagnostic calls. No preview event
    -- draws permanent furniture; that event may stop when the mouse tile
    -- becomes invalid during camera zoom or UI interaction.
end
function FX.preload()
    FX.installCursor()
    if type(loadStaticZomboidModel)~="function" then return end
    local name=Items.byType[Items.coffinType].worldModel
    local script=getScriptManager():getModelScript(name)
    if script then FX.asset=loadStaticZomboidModel(name,script:getMeshName(),script:getTextureName()) end
end
function FX.installCursor()
    local cursor=ISMoveableCursor
    if not cursor or cursor.EVHCoffin3D then return end
    cursor.EVHCoffin3D=true
    local original=cursor.renderObjectThatCanRotate
    cursor.renderObjectThatCanRotate=function(self,x,y,z,rotateIndicator)
        if FX.disabled then return original(self,x,y,z,rotateIndicator) end
        local rotation=facing(self.objectSprite)
        if rotation==nil then return original(self,x,y,z,rotateIndicator) end
        local square=getCell():getGridSquare(x,y,z)
        if not square or type(Render3DItem)~="function" then return original(self,x,y,z,rotateIndicator) end
        local valid=self.colorMod~=ISMoveableCursor.invalidColor
        local key=valid and "valid" or "invalid"
        local item=FX.preview[key]
        if not item then
            item=proxy();if not item then return original(self,x,y,z,rotateIndicator) end
            local color=self.colorMod or ISMoveableCursor.validColor
            item:setCustomColor(true)
            item:setColorRed(color.r);item:setColorGreen(color.g);item:setColorBlue(color.b)
            item:setWorldAlpha(.8)
            FX.preview[key]=item
        end
        local ok,err=pcall(function()
            Render3DItem(item,square,x+.5,y+.5,z+(self.yOffset or 0)/96,rotation)
            if rotateIndicator and self.currentMoveProps then
                local dir=self.currentMoveProps:getFaceDirectionFromSpriteName(self.objectSprite:getName())
                local cx,cy=self:getCenterOfRotation()
                self:renderRotateIndicator(cx,cy,z,dir and IsoDirections.fromString(opposite[dir] or dir))
            end
        end)
        if not ok then failed(err);return original(self,x,y,z,rotateIndicator) end
        return true -- stock cursor skips the separately baked tile ghost
    end
end
if Events.OnObjectAdded then Events.OnObjectAdded.Add(function(object)
    if object and object:getSquare() then FX.scan(object:getSquare()) end
end) end
if Events.LoadGridsquare then Events.LoadGridsquare.Add(FX.scan) end
if Events.OnTick then Events.OnTick.Add(function()
    if FX.disabled then return end
    local ok,err=pcall(FX.update);if not ok then failed(err) end
end) end
if Events.OnGameStart then Events.OnGameStart.Add(function()
    local ok,err=pcall(FX.preload);if not ok then failed(err) end
end) end
return FX
