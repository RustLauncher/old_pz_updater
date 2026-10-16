require 'PepsiFridge/Core'
require 'Moveables/ISMoveableSpriteProps'
local M=PepsiFridge
local props=ISMoveableSpriteProps
local states=setmetatable({},{__mode='k'})
local function pack(...)return {n=select('#',...),...}end
local function empty(t)for _ in pairs(t)do return false end;return true end
local function copyIdentity(data,state)
    if data.movableData~=nil and type(data.movableData)~='table' then return end
    local saved=type(data.modData)=='table' and data.modData.movableData or state.saved
    if type(saved)~='table' then saved=state.saved end
    if data.movableData==nil then data.movableData=copyTable(saved)
    else
        for key,value in pairs(saved)do if data.movableData[key]==nil then
            data.movableData[key]=type(value)=='table' and copyTable(value) or value
        end end
    end
    data.movableData[M.styleDataKey]=state.style
end

-- Native IsoThumpable pickup nests movableData. Mirror that same complete data
-- at the top level BEFORE native sendAddItemToContainer serializes its item.
local previousSave=props.saveThumpableParameters
props.saveThumpableParameters=function(self,data,object,...)
    local results=pack(previousSave(self,data,object,...))
    local state=states[object]
    if state then copyIdentity(data,state)end
    return unpack(results,1,results.n)
end

-- Native pickup owns inventory, health, weight, break tests and packets.
-- Temporarily give its Source the selected style BEFORE it copies/sends data.
-- Finally restore the Source key on success or failure, so a failed attempt
-- never freezes untouched map furniture to the current spawn choice.
local previous=props.pickUpMoveableInternal
props.pickUpMoveableInternal=function(self,character,square,object,...)
    local style=M.spriteStyle(object)
    if not style then return previous(self,character,square,object,...)end
    local source=object:getModData()
    local original=source.movableData
    if original~=nil and type(original)~='table' then return previous(self,character,square,object,...)end
    local oldStyle=original and original[M.styleDataKey]
    -- Clone before any Source mutation: an unsupported foreign value or a
    -- copy failure cannot leave a temporary owned key on a surviving object.
    local saved=original and copyTable(original) or {}
    saved[M.styleDataKey]=style
    M.writeStyle(object,style)
    local temporary=source.movableData
    local previousState=states[object]
    local state={style=style,saved=saved}
    states[object]=state
    local results=pack(pcall(previous,self,character,square,object,...))
    states[object]=previousState
    temporary[M.styleDataKey]=oldStyle
    if original==nil and source.movableData==temporary and empty(temporary)then source.movableData=nil end
    if not results[1]then error(results[2])end
    local item=results[2]
    -- Retain the result contract for other wrappers; the packet already carries
    -- identity in the ordinary copy or the scoped thumpable-save hook above.
    if item then copyIdentity(item:getModData(),state)end
    return unpack(results,2,results.n)
end

local previousPlace=props.placeMoveableInternal
props.placeMoveableInternal=function(self,character,square,item,spriteName,...)
    if not M.tiles[spriteName] or not item then return previousPlace(self,character,square,item,spriteName,...) end
    local name=item and item:getWorldSprite()
    local entry=name and M.tiles[name]
    if M.tiles[spriteName] and entry then
        local data=item:getModData()
        if data.movableData==nil and type(data.modData)=='table' and type(data.modData.movableData)=='table' then
            data.movableData=copyTable(data.modData.movableData)
        end
        -- Pre-update inventory items have no style key yet. Their worldSprite
        -- already records the player's selection, even after a settings change.
        local style=name==entry.worn and 'worn' or (name==entry.pepsi and 'pepsi' or 'vanilla')
        M.writeStyle(item,M.readStyle(item) or style)
    end
    return previousPlace(self,character,square,item,spriteName,...)
end
