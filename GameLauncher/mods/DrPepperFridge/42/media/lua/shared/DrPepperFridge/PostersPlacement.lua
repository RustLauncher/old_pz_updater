require 'DrPepperFridge/Posters'
require 'DrPepperFridge/PosterIds'
require 'Moveables/ISMoveableSpriteProps'
local P = DrPepperPosters
local Move = ISMoveableSpriteProps
if Move.DrPepperPostersPlacementPatched then return end
Move.DrPepperPostersPlacementPatched = true

-- An inventory item's exact Dr Pepper script type proves its design. A raw
-- world alias name does not. Keep this identity rule local to item handling;
-- P.spriteInfo must never treat an unmarked old world alias as ownership.
local function aliasIndex(name)
    local prefix=DrPepperPosterIds.legacyPrefix
    if type(name)~='string' or string.sub(name,1,#prefix)~=prefix then return nil end
    local index=tonumber(string.sub(name,#prefix+1))
    if index and index>=0 and index<=9 and index==math.floor(index) and name==prefix..index then return index end
end
local function matchingItem(item,index)
    return item and item.getFullType and item:getFullType()==P.itemType(math.floor(index/2)+1)
end
function DrPepperPosterIds.normalizeInventoryPoster(item)
    if not item or not item.getWorldSprite then return nil end
    local index=aliasIndex(item:getWorldSprite())
    if not index or not matchingItem(item,index) then return nil end
    local canonical=getSprite(P.prefix..index)
    if not canonical or canonical:getID()~=1275854848+index
            or not canonical:getProperties():has('IsMoveAble') then return nil end
    -- This keeps the same inventory object, condition and modData. Re-read
    -- canonical moveable metadata, retaining the item's actual pickup weight.
    local weight=item:getActualWeight()
    if not item:ReadFromWorldSprite(P.prefix..index) then return nil end
    item:setActualWeight(weight)
    return index
end
local function canonicalPlacement(self,item,spriteName)
    local index=aliasIndex(spriteName)
    if not index then return self,spriteName end
    if not matchingItem(item,index) then return nil,nil end
    return Move.new(P.prefix..index),P.prefix..index
end

-- Vanilla finishes ReadFromWorldSprite before returning this method's item.
-- Normalize that result before pickup inserts/transmits it. The global item
-- factory is untouched; unrelated moveables and incorrect pairings pass through.
local instance=Move.instanceItem
function Move:instanceItem(spriteOverride)
    local item=instance(self,spriteOverride)
    DrPepperPosterIds.normalizeInventoryPoster(item)
    return item
end
local canPlace = Move.canPlaceMoveableInternal
function Move:canPlaceMoveableInternal(character, square, item, forceTypeObject)
    DrPepperPosterIds.normalizeInventoryPoster(item)
    local props,name=canonicalPlacement(self,item,self.spriteName)
    if not props then return false end
    if P.spriteInfo(name) and not P.wallAvailable(square, props.facing, nil, true) then return false end
    return canPlace(props, character, square, item, forceTypeObject)
end

-- Check before the native method consumes the inventory item. Even its debug
-- forceAllow path must not erase a poster after an invalid placement attempt.
local place = Move.placeMoveable
function Move:placeMoveable(character, square, originalSprite, forceAllow)
    local item=self:findInInventory(character,originalSprite)
    local old=aliasIndex(originalSprite)
    if not item and old then
        -- rotateMoveable keeps the old world source name after pickup has
        -- already normalized the temporary inventory item. Match its exact
        -- canonical face and Dr script type before consuming that item.
        local canonicalItem=self:findInInventory(character,P.prefix..old)
        if matchingItem(canonicalItem,old) then item=canonicalItem;originalSprite=P.prefix..old end
    end
    local normalized=DrPepperPosterIds.normalizeInventoryPoster(item)
    if normalized then originalSprite=P.prefix..normalized end
    local props,name=canonicalPlacement(self,item,self.spriteName)
    if not props then return false end
    if P.spriteInfo(name) and not P.wallAvailable(square, props.facing, nil, true) then return false end
    return place(props, character, square, originalSprite, forceAllow)
end

-- Stamp the source item before vanilla copies its metadata and transmits the
-- placed object. Use the final rotated sprite, not the item's original face.
local placeInternal=Move.placeMoveableInternal
function Move:placeMoveableInternal(character,square,item,spriteName)
    DrPepperPosterIds.normalizeInventoryPoster(item)
    local props,name=canonicalPlacement(self,item,spriteName)
    if not props then return nil end
    spriteName=name
    local design,facing=P.spriteInfo(spriteName)
    if design and item then
        local md=item:getModData()
        md.DrPepperPoster=P.designs[design]
        md.DrPepperPosterSpriteIndex=(design-1)*2+(facing=='S' and 1 or 0)
        md.DrPepperPosterPlayerPlaced=true
    end
    local object=placeInternal(props,character,square,item,spriteName)
    if design and object then
        DrPepperPosterIds.stamp(object,(design-1)*2+(facing=='S' and 1 or 0),true)
        if isClient() or isServer() then object:transmitModData() end
    elseif design and props.type=='WallOverlay' then
        -- Vanilla attaches E/S overlays to their wall and returns no object.
        -- Record attachment identity on the wall without stamping its primary
        -- sprite as a Dr Pepper poster.
        local wall=props:getWallForFacing(square,props.facing)
        local attached=wall and wall:getAttachedAnimSprite()
        if attached then
            for n=0,attached:size()-1 do
                if attached:get(n):getParentSprite():getName()==spriteName then
                    local md=wall:getModData()
                    md.DrPepperPosterAttachments=md.DrPepperPosterAttachments or {}
                    md.DrPepperPosterAttachments[spriteName]=true
                    if isClient() or isServer() then wall:transmitModData() end
                    break
                end
            end
        end
    end
    return object
end

