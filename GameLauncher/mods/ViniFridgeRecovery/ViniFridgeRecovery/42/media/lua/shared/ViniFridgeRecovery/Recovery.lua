-- Optional companion: active families are untouched. Disabled families receive
-- vanilla-backed aliases BEFORE chunks/items are deserialized, including distant
-- chunks. Only the server changes world objects; clients register display aliases.
local definitions=require 'ViniFridgeRecovery/Definitions'
ViniFridgeRecovery=ViniFridgeRecovery or {}
local R=ViniFridgeRecovery
require 'ViniFridgeRecovery/Protection'
R.aliases={}
R.nativeByOwner={}
R.disabled={}
R.warnings={}
R.ownedAliases=R.ownedAliases or {}
local allNames={}
for _,family in ipairs(definitions) do
    for _,record in ipairs(family.records) do if record.native then allNames[#allNames+1]=record.name end end
end
local function warn(key,message)
    if R.warnings[key] then return end
    R.warnings[key]=true
    print('[VINI Furniture Recovery] '..message)
end
local function nativeSprite(name)
    local sprite=getSprite(name)
    return sprite and sprite:getName()==name and sprite:getProperties():has('IsMoveAble') and sprite or nil
end
local function unavailable(sprite)
    return not sprite or not sprite:getProperties():has('IsMoveAble')
        and (sprite:hasNoTextures() or sprite:getName()=='' or sprite:getName()==nil)
end
local function register(manager)
    local previous=R.ownedAliases
    R.aliases={};R.nativeByOwner={};R.disabled={};R.warnings={}
    R.ownedAliases={}
    local active=getActivatedMods()
    for _,family in ipairs(definitions) do
        if not active:contains(family.id) then
            local permitted=true
            local lookedUp={}
            -- Refuse the entire family before mutating any registry entry. Never
            -- reinterpret another mod's tile ID, even if this world once used VINI.
            for _,record in ipairs(family.records) do
                local numeric=manager:getSprite(record.numeric)
                -- Offset-zero static lookup returns the existing named pointer
                -- or nil WITHOUT creating a placeholder. Native bytecode proves
                -- this branch returns before any manager/AddSprite call.
                local named=IsoSprite.getSprite(manager,record.name,0)
                lookedUp[record.name]=named
                local own=previous[record.name]
                if numeric and numeric~=own or named and named~=own then
                    permitted=false
                    warn(family.id..'-collision','Another sprite owns a required '..family.id..' slot; this family was not registered. Keep its original mod enabled and check tile-definition conflicts.')
                    R.protect('Required registry slot/name is already owned for '..family.id)
                    break
                end
                if record.native and not nativeSprite(record.native) then
                    permitted=false
                    warn(family.id..'-native','Native furniture sprite missing; this family was not registered: '..record.native)
                    R.protect('Native fallback unavailable for '..family.id..': '..record.native)
                    break
                end
            end
            if permitted then
                local grids={}
                R.disabled[family.id]=true
                R.nativeByOwner[family.id]=R.nativeByOwner[family.id] or {}
                for _,record in ipairs(family.records) do
                    local alias=manager:getSprite(record.numeric) or lookedUp[record.name]
                    if not alias then alias=manager:AddSprite(record.name,record.numeric) end
                    local beforeID=alias:getID()
                    alias:setName(record.name)
                    R.ownedAliases[record.name]=alias
                    assert(alias:getID()==record.numeric,'Recovery alias ID mismatch: name='..record.name..' expected='..tostring(record.numeric)..' before='..tostring(beforeID)..' actual='..tostring(alias:getID())..' expectedType='..type(record.numeric)..' actualType='..type(alias:getID())..' numericPointerMatches='..tostring(manager:getSprite(record.numeric)==alias))
                    if record.native then
                        local native=nativeSprite(record.native)
                        alias:getProperties():Clear()
                        alias:getProperties():AddProperties(native:getProperties())
                        -- Alias names have no branded _on_ texture family. The
                        -- one native-backed texture is sufficient until the
                        -- authoritative object receives its canonical sprite.
                        alias:getProperties():unset(IsoFlagType.HasLightOnSprite)
                        if TurnOffFridges and TurnOffFridges.clearFridgeProperty then
                            TurnOffFridges.clearFridgeProperty(alias:getProperties())
                        end
                        alias:getProperties():CreateKeySet()
                        if not isServer() then
                            alias:LoadSingleTexture(record.native)
                            assert(not alias:hasNoTextures(),'Recovery texture missing: '..record.native)
                        end
                        local entry={owner=family.id,native=record.native,alias=alias,numeric=record.numeric}
                        R.aliases[record.name]=entry
                        R.nativeByOwner[family.id][record.native]=true
                        local pos=record.properties.SpriteGridPos
                        if pos and pos~='None' then
                            local x,y=pos:match('^(%d+),(%d+)$')
                            assert(x and y,'Invalid recorded fridge grid position')
                            x,y=tonumber(x),tonumber(y)
                            local key=record.sheet..':'..record.properties.Facing
                            grids[key]=grids[key] or {width=0,height=0,members={}}
                            local grid=grids[key]
                            grid.width=math.max(grid.width,x+1);grid.height=math.max(grid.height,y+1)
                            grid.members[#grid.members+1]={x=x,y=y,alias=alias}
                        end
                    end
                    -- Auxiliary light/stock artwork has no interaction properties
                    -- or texture. It retains its numeric identity without drawing.
                end
                for _,group in pairs(grids) do
                    local grid=IsoSpriteGrid.new(group.width,group.height,1)
                    for _,part in ipairs(group.members) do grid:setSprite(part.x,part.y,0,part.alias) end
                    assert(grid:validate(),'Incomplete recovery fridge grid')
                    for _,part in ipairs(group.members) do part.alias:setSpriteGrid(grid) end
                end
            end
        end
    end
end
function R.register(manager)
    local ok,problem=pcall(register,manager)
    if not ok then R.protect('Unexpected registration failure: '..tostring(problem)) end
    return ok and not R.blocked
end
local function exactOriginal(object)
    local sprite=object:getSprite()
    local name=sprite and sprite:getName()
    local alias=name and R.aliases[name]
    if alias then return alias.native end
    if not unavailable(sprite) or not object:hasModData() then return end
    local movable=object:getModData().movableData
    if type(movable)~='table' then return end
    local saved=movable.VINIFridgeRecovery
    if type(saved)=='table' and saved.schema==1 and R.disabled[saved.modId] then
        local entry=R.aliases[saved.custom]
        if entry and entry.owner==saved.modId and entry.native==saved.vanilla then return saved.vanilla end
    end
    -- Old releases sometimes kept an independent spriteName while replacing
    -- sprite. Only a saved exact face AND its own roll prove recovery identity.
    local stored=object:getSpriteName()
    for owner,natives in pairs(R.nativeByOwner) do
        if type(movable[owner..'Roll'])=='number' then
            local entry=R.aliases[stored]
            if entry and entry.owner==owner then return entry.native end
            if natives[stored] then return stored end
        end
    end
end
function R.restoreObject(object)
    if R.blocked or isClient() or not object or not object:getSquare() or object:getObjectIndex()<0 then return false end
    local name=exactOriginal(object)
    local native=name and nativeSprite(name)
    if not native then return false end
    -- This does not remove/recreate objects or touch container types, capacities,
    -- item lists, food temperature/age, custom colors or unrelated modData.
    local overlay=object:getOverlaySprite()
    if overlay and R.aliases[overlay:getName()] then object:setOverlaySprite(nil,false) end
    local on=object:getOnOverlay()
    if on and on:getScaleX()~=0 then
        local parent=on:getParentSprite()
        if parent and R.aliases[parent:getName()] then object:clearOnOverlay() end
    end
    -- Save both the canonical registered ID and exact canonical spriteName.
    object:setSprite(name);object:setSprite(native)
    object:getSquare():RecalcAllWithNeighbours(true)
    object:flagForHotSave()
    if isServer() then object:transmitUpdatedSpriteToClients() end
    return true
end
function R.normalizeItem(item)
    if R.blocked or not item or not instanceof(item,'Moveable') then return false end
    local entry=R.aliases[item:getWorldSprite()]
    if not entry then return false end
    local native=nativeSprite(entry.native)
    if not native then return false end
    local condition,weight=item:getCondition(),item:getActualWeight()
    local weightFlag=item:isCustomWeight()
    local color,colorFlag=item:getColor(),item:isCustomColor()
    local name,nameFlag=item:getName(),item:isCustomName()
    if not item:ReadFromWorldSprite(entry.native) then return false end
    item:setCondition(condition);item:setActualWeight(weight);item:setCustomWeight(weightFlag)
    item:setColor(color);item:setCustomColor(colorFlag)
    if nameFlag then item:setName(name);item:setCustomName(true) end
    -- Native ReadFromWorldSprite updates (1/1) and split-part names/grid anchors.
    return true
end
function R.scanItems(container,visited)
    if not container then return false end
    visited=visited or {}
    if visited[container] then return false end
    visited[container]=true
    local items=container:getItems()
    local changed=false
    for i=0,items:size()-1 do
        local item=items:get(i)
        if R.normalizeItem(item) then changed=true end
        if instanceof(item,'InventoryContainer') and R.scanItems(item:getInventory(),visited) then changed=true end
    end
    return changed
end
function R.scanSquare(square)
    if R.blocked or isClient() or not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        R.restoreObject(object)
        for n=0,object:getContainerCount()-1 do
            local container=object:getContainerByIndex(n)
            if R.scanItems(container) and isServer() then sendItemsInContainer(object,container) end
        end
    end
    local dropped=square:getWorldObjects()
    for i=0,dropped:size()-1 do
        local worldItem=dropped:get(i)
        if R.normalizeItem(worldItem:getItem()) then
            worldItem:updateSprite();worldItem:flagForHotSave()
            if isServer() then worldItem:transmitCompleteItemToClients() end
        end
    end
end
Events.OnLoadedTileDefinitions.Add(R.register)
Events.OnGameStart.Add(function()
    if TurnOffFridges and TurnOffFridges.clearFridgeProperty then
        for _,entry in pairs(R.aliases) do TurnOffFridges.clearFridgeProperty(entry.alias:getProperties()) end
    end
end)
-- Exact item/fluid types stay defined while Dr Pepper is disabled, so native
-- deserialization preserves those saved objects. Copies of the current original
-- scripts are identical when both mods are active. Only the disabled-primary
-- presentation uses native models/icons; no custom artwork pack is required.
local function prepareFallbackItems()
    if getActivatedMods():contains('DrPepperFridge') then return end
    for _,spec in ipairs({{'CanRegular','Pop2','Base.PopCanRed'},{'CanDiet','Pop','Base.PopCanDiet'}}) do
        local item=ScriptManager.instance:getItem('DrPepper.'..spec[1])
        if item then
            item:DoParam('Icon = '..spec[2])
            item:DoParam('StaticModel = '..spec[3])
            item:DoParam('WorldStaticModel = '..spec[3])
        end
    end
    for _,name in ipairs({'BeAPepper','Original','Refreshment','GoodTimes','PeppersDelight'}) do
        local item=ScriptManager.instance:getItem('DrPepper.Poster'..name)
        if item then item:DoParam('Icon = Moveable_wallobject') end
    end
end
Events.OnInitWorld.Add(prepareFallbackItems)
MapObjects.OnLoadWithSprite(allNames,R.restoreObject,5)
Events.LoadGridsquare.Add(R.scanSquare)
Events.OnObjectAdded.Add(R.restoreObject)
local ticks=0
Events.OnCreatePlayer.Add(function(index,player)
    if player and not isServer() then R.scanItems(player:getInventory()) end
end)
Events.OnGameStart.Add(function()
    if isServer() then return end
    for i=0,getNumActivePlayers()-1 do
        local player=getSpecificPlayer(i)
        if player then R.scanItems(player:getInventory()) end
    end
end)
Events.OnPlayerUpdate.Add(function(player)
    ticks=ticks+1
    -- Player inventories are client-owned in MP; aliases remain valid in the
    -- server's stored data. Full ItemContainer packets carry world-container
    -- normalization. Never send an item-stats packet that omits worldSprite.
    if ticks%120==0 and player and not isServer() then R.scanItems(player:getInventory()) end
end)
return R
