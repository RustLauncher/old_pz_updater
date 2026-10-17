require "HalloweenEvent/EVHalloween_ItemFunctions"
require "TimedActions/ISEVHalloweenServiceAction"
local Items,F=HalloweenEvent.Items,HalloweenEvent.Items.Functions
local V={world={},lights={},pending={},tick=0,column=-16,frame=0,time=0,warned={},observed={}}
Items.Visuals=V
V.candleAssets={};V.candlePreloadStarted=false;V.candlePreloadReady=false
local function warn(key,message)
    if not V.warned[key] then V.warned[key]=true;HalloweenEvent.log("ITEMS VISUAL_UNAVAILABLE feature="..key.." reason="..tostring(message)) end
end
local function recalcLight()
    if IsoGridSquare and IsoGridSquare.setRecalcLightTime then IsoGridSquare.setRecalcLightTime(-1) end
end
local function dropLight(id)
    F.candleFrames[id]=nil
    F.candlePulse[id]=nil
    if V.candleNextFrame then V.candleNextFrame[id]=nil end
    local rec=V.lights[id]
    if rec then
        pcall(function() rec.light:setActive(false);getCell():removeLamppost(rec.light) end)
        V.lights[id]=nil;recalcLight()
    end
end
local function applyState(item,args)
    if item:getFullType()~=args.fullType then return end
    F.setCharge(item,args.charge);item:setActivated(args.active)
    local md=F.state(item)
    md.bulbLife,md.bulbType,md.lastHours=args.bulbLife,args.bulbType,args.lastHours
    F.visual(item)
end
local function register(item)
    local ft=item:getFullType()
    if ft==F.bowlType or ft==F.potionType or ft==F.doormatType or ft==Items.coffinType or F.lights[ft] or F.bucketTypes[ft] then
        V.world[item:getID()]=item
        local state=V.pending[item:getID()]
        if state then applyState(item,state);V.pending[item:getID()]=nil end
    end
end
function V.scan(square)
    if not square then return end
    if Items.CoffinVisuals then Items.CoffinVisuals.scan(square) end
    local list=square:getWorldObjects()
    for i=0,list:size()-1 do local item=list:get(i):getItem();if item then register(item) end end
end
local function visit(container, callback,depth)
    if not container or (depth or 0)>12 then return end
    local list=container:getItems()
    for i=0,list:size()-1 do
        local item=list:get(i)
        if F.lights[item:getFullType()] or F.bucketTypes[item:getFullType()] or item:getFullType()==Items.coffinType or item:getFullType()==F.bowlType or item:getFullType()==F.doormatType then callback(item) end
        if item:IsInventoryContainer() then visit(item:getInventory(),callback,(depth or 0)+1) end
    end
end
function V.preloadCandles()
    if isServer() or V.candlePreloadStarted then return end
    V.candlePreloadStarted=true;V.candlePreloadTime=V.time
    if type(loadStaticZomboidModel)~="function" then
        V.candlePreloadReady=true;warn("candle_preload","native static model loader unavailable");return
    end
    for _,ft in ipairs({F.pumpkinType,F.catPumpkinType}) do
        local row=Items.byType[ft]
        local names={row.worldModel,row.handModel}
        for level=0,7 do
            local suffix="_Lit"..(level>0 and level or "")
            names[#names+1]=row.worldModel:gsub("_Ground$",suffix.."_Ground")
            names[#names+1]=row.handModel:gsub("_Hand$",suffix.."_Hand")
        end
        for _,name in ipairs(names) do
                local script=getScriptManager():getModelScript(name)
                if script then
                    local ok,asset=pcall(loadStaticZomboidModel,name,script:getMeshName(),script:getTextureName())
                    if ok and asset then V.candleAssets[#V.candleAssets+1]={name=name,asset=asset}
                    else warn("candle_preload",asset) end
                else warn("candle_preload","unresolved "..name) end
        end
    end
    -- Request complete floor and held palettes before animation begins. Do not assert
    -- that opaque model userdata or the world atlas has finished loading.
    V.candlePreloadReady=true
    HalloweenEvent.log("ITEMS CANDLE_PRELOAD_BEGIN assets="..#V.candleAssets.." version="..Items.VERSION)
end
function V.checkCandleAssets()
    if V.candlePreloadReady then return end
    V.preloadCandles()
end

function V.update()
    if isServer() then return end
    V.tick=V.tick+1
    local delta=getGameTime():getRealworldSecondsSinceLastUpdate()
    V.time=V.time+math.min(.1,delta)
    V.checkCandleAssets()
    V.animateCandles()
    if V.tick%20~=0 then return end
    V.frame=(V.frame+1)%4
    local cell=getCell();if not cell then return end
    local centers={}
    for n=0,getNumActivePlayers()-1 do
        local player=getSpecificPlayer(n)
        if player then
            local x,y,z=math.floor(player:getX()),math.floor(player:getY()),math.floor(player:getZ())
            centers[#centers+1]={x=x,y=y,z=z}
            -- Incremental 33x33 scan; one third per update, never the whole map.
            for dx=V.column,math.min(16,V.column+10) do for dy=-16,16 do
                V.scan(cell:getGridSquare(x+dx,y+dy,z))
            end end
            visit(player:getInventory(),function(item)
                local args=V.pending[item:getID()]
                if args then applyState(item,args);V.pending[item:getID()]=nil end
                F.visual(item)
            end)
        end
    end
    V.column=V.column+11;if V.column>16 then V.column=-16 end
    for id,item in pairs(V.world) do
        local world=item:getWorldItem();local sq=world and world:getSquare()
        local near=false
        if sq then for _,p in ipairs(centers) do
            if sq:getZ()==p.z and math.abs(sq:getX()-p.x)<=20 and math.abs(sq:getY()-p.y)<=20 then near=true;break end
        end end
        if not near or cell:getGridSquare(sq:getX(),sq:getY(),sq:getZ())~=sq then
            dropLight(id);V.world[id]=nil;V.observed[id]=nil;V.candleWarm[id]=nil
        else
            local ok,err=pcall(F.visual,item);if not ok then warn("model",err) end
            local seen=V.observed[id]
            if not seen then
                seen={states={},updates=0};V.observed[id]=seen
                HalloweenEvent.log("ITEMS VISUAL_TRACK id="..tostring(id).." type="..item:getFullType()
                    .." effectiveModel="..tostring(item:getWorldStaticModel()).." index="..tostring(item:getModelIndex()))
            end
            seen.states[item:getWorldStaticModel() or "nil"]=true;seen.updates=seen.updates+1
            local cfg=F.lights[item:getFullType()]
            local potion=item:getFullType()==F.potionType
            local lit=potion or (cfg and item:isActivated() and F.canLight(item))
            if not lit then dropLight(id)
            else
                local rec=V.lights[id]
                local key=sq:getX()..":"..sq:getY()..":"..sq:getZ()
                local missing=false
                if rec and cell.getLamppostPositions then
                    local valid,present=pcall(function() return cell:getLamppostPositions():contains(rec.light) end)
                    missing=valid and not present
                end
                if rec and (rec.key~=key or missing) then dropLight(id);rec=nil end
                if not rec then
                    local color=potion and {.15,.32,.12} or cfg.color
                    local okLight,light=pcall(function()
                        local source=IsoLightSource.new(sq:getX(),sq:getY(),sq:getZ(),color[1],color[2],color[3],potion and 2 or cfg.radius)
                        source:setActive(true);cell:addLamppost(source);recalcLight()
                        return source
                    end)
                    if okLight then
                        rec={light=light,key=key};V.lights[id]=rec
                        HalloweenEvent.log("ITEMS FLOOR_LIGHT id="..tostring(id).." type="..item:getFullType()
                            .." x="..sq:getX().." y="..sq:getY().." z="..sq:getZ().." radius="..(potion and 2 or cfg.radius).." recalc=true")
                    else warn("floor_light",light) end
                end
                if rec then rec.item=item end
            end
        end
    end
    -- Delayed packets for objects outside this client's loaded area expire.
    if V.tick%600==0 then V.pending={} end
end

function V.candlePulse(time,id)
    local phase=(id%29)*.37
    return .79+.14*math.sin(time*1.7+phase)+.07*math.sin(time*3.1+phase*.7)
end
-- Build first-use native atlas entries offscreen before changing brightness.
-- These are temporary display proxies, never inventory/world objects. Fuel,
-- activation, saved state and the real item's placement are untouched.
V.candleWarm={}
function V.warmCandle(item)
    if not item:getWorldItem() or type(Render3DItem)~="function" then return false end
    local id=item:getID();local angle=item:getWorldZRotation()%360
    -- InventoryItem exposes setWorldScale but no getWorldScale. These
    -- pumpkins use their script scale; warming never changes the real item.
    local key=angle..":"..item:getWorldXRotation()..":"..item:getWorldYRotation()
    local rec=V.candleWarm[id]
    if not rec or rec.key~=key then
        rec={key=key,item=item,untilTime=V.time+.5,expires=V.time+2,passes=0,models={}}
        V.candleWarm[id]=rec
        for level=0,7 do for phase=0,1 do
            local proxy=instanceItem(item:getFullType())
            if not proxy then rec.models=nil;return false end
            local model=Items.byType[item:getFullType()].worldModel:gsub("_Ground$","_Lit"..(level>0 and level or "").."_Ground")
            proxy:setWorldStaticModel(model)
            proxy:setWorldZRotation(angle+phase*360)
            proxy:setWorldXRotation(item:getWorldXRotation());proxy:setWorldYRotation(item:getWorldYRotation())
            rec.models[#rec.models+1]=proxy
        end end
    end
    if not rec.models then return false end
    if (rec.passes>=2 and V.time>=rec.untilTime) or V.time>=rec.expires then rec.models=nil;return false end
    return true
end
if Events.RenderOpaqueObjectsInWorld then Events.RenderOpaqueObjectsInWorld.Add(function()
    for _,rec in pairs(V.candleWarm) do
        if rec.models and rec.passes<2 then
            local world=rec.item:getWorldItem();local sq=world and world:getSquare()
            if sq then
                local ok,err=pcall(function()
                    for _,proxy in ipairs(rec.models) do
                        -- A negative forced rotation enables the stock atlas.
                        -- The screen position is far outside the view; atlas
                        -- cache keys use model/rotation/scale, not world XY.
                        Render3DItem(proxy,sq,sq:getX()+4096,sq:getY()-4096,sq:getZ(),-1)
                    end
                end)
                if ok then rec.passes=rec.passes+1 else rec.models=nil;warn("candle_warm",err) end
            else rec.models=nil end
        end
    end
end) end
function V.animateCandle(item,character)
    if not item or not F.isCandle(item) or not item:isActivated() or not F.canLight(item) then return end
    local id=item:getID();local pulse=V.candlePulse(V.time,id)
    F.candlePulse[id]=pulse
    local level=math.max(0,math.min(7,math.floor((1-pulse)/.42*7+.5)))
    -- Limit native model/atlas changes to at most one per .15 seconds. Every
    -- lit palette keeps the full body; only the carved features vary.
    V.candleNextFrame=V.candleNextFrame or {}
    if not V.warmCandle(item) and F.candleFrames[id]~=level and V.time>=(V.candleNextFrame[id] or 0) then
        V.candleNextFrame[id]=V.time+.15
        F.candleFrames[id]=level
        F.visual(item)
        if character then character:resetEquippedHandsModels() end
    end
    local cfg=F.lights[item:getFullType()]
    item:setLightStrength(cfg.strength*pulse)
    return pulse
end
function V.animateCandles()
    for n=0,getNumActivePlayers()-1 do
        local player=getSpecificPlayer(n)
        if player and player.getPrimaryHandItem then V.animateCandle(player:getPrimaryHandItem(),player) end
        if player and player.getSecondaryHandItem then V.animateCandle(player:getSecondaryHandItem(),player) end
    end
    -- Native LightingJNI observes each source's RGB changes itself. Do not
    -- reset the global lighting cache for every small candle pulse. Sample
    -- all floor lights together at the same rate as the eye palettes; held
    -- light strength and the eye animation still update above/every tick.
    local updateFloorLight=V.time>=(V.nextCandleLight or 0)
    if updateFloorLight then V.nextCandleLight=V.time+.15 end
    for id,rec in pairs(V.lights) do
        local item=rec.item;local cfg=item and F.lights[item:getFullType()]
        if cfg and cfg.candle and item:isActivated() then
            local pulse=V.animateCandle(item)
            if pulse and (not rec.pulse or (updateFloorLight and math.abs(rec.pulse-pulse)>.003)) then
                rec.light:setR(cfg.color[1]*pulse);rec.light:setG(cfg.color[2]*pulse);rec.light:setB(cfg.color[3]*pulse)
                rec.pulse=pulse
                if not rec.pulseLogged then
                    rec.pulseLogged=true
                    HalloweenEvent.log("ITEMS CANDLE_PULSE id="..tostring(id).." range=0.58..1.00 stableBody=true renderer=native_world_item fullModelPalettes=8 continuousLight=true")
                end
            end
        end
    end
end
function V.toggle(player,item)
    if item:getWorldItem() then register(item) end
    local world=item:getWorldItem();local sq=world and world:getSquare()
    local args={id=item:getID(),on=not item:isActivated(),x=sq and sq:getX(),y=sq and sq:getY(),z=sq and sq:getZ()}
    if isClient() then sendClientCommand(player,"EVHalloweenItems","ToggleLight",args)
    else
        if not Items.Runtime then require "HalloweenEvent/EVHalloween_ItemRuntime" end
        Items.Runtime.handle(player,"ToggleLight",args)
    end
end
function V.audit()
    local checked,lights=0,0
    for id,item in pairs(V.world) do
        local world=item:getWorldItem();local sq=world and world:getSquare()
        if sq then
            checked=checked+1
            local rec=V.lights[id];if rec then lights=lights+1 end
            HalloweenEvent.log("ITEMS PLACED_AUDIT id="..tostring(id).." type="..item:getFullType()
                .." effectiveModel="..tostring(item:getWorldStaticModel()).." index="..tostring(item:getModelIndex())
                .." active="..tostring(item:isActivated()).." floorLight="..tostring(rec~=nil))
        end
    end
    HalloweenEvent.log("ITEMS PLACED_AUDIT_RESULT tracked="..checked.." floorLights="..lights.." version="..Items.VERSION)
end
function EVHalloweenAuditPlaced() V.audit() end
local function service(player,item,mode,supply)
    ISInventoryPaneContextMenu.transferIfNeeded(player,item)
    ISTimedActionQueue.add(ISEVHalloweenServiceAction:new(player,item,mode,supply))
end
function V.tooltip(option,text)
    if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.addToolTip then
        option.toolTip=ISInventoryPaneContextMenu.addToolTip();option.toolTip.description=text
    end
end
function V.explain(option,item)
    if not option.notAvailable then return end
    local cfg=F.lights[item:getFullType()]
    local reason=F.charge(item)<=0 and (cfg.candle and HalloweenEvent.text("NeedCandle") or HalloweenEvent.text("NeedCharge"))
        or (cfg.bulb and F.state(item).bulbLife<=0 and HalloweenEvent.text("NeedBulb"))
    if reason then V.tooltip(option,reason) end
end
function V.options(context,player,item)
    if not F.lights[item:getFullType()] then return end
    local name=item:getDisplayName()
    local option=context:addOption(HalloweenEvent.text(item:isActivated() and "TurnOff" or "TurnOn",name),player,V.toggle,item)
    option.notAvailable=not item:isActivated() and not F.canLight(item)
    V.explain(option,item)
    local inv=player:getInventory();local list=inv:getItems();local supply
    for i=0,list:size()-1 do
        local candidate=list:get(i);local ft=candidate:getFullType()
        if item:getFullType()==Items.lanternType and ft:match("^Base%.LightBulb") and candidate:getCondition()>0 then supply=candidate;break end
        if F.isCandle(item) and ft=="Base.Candle" and candidate:getCurrentUsesFloat()>0 then supply=candidate;break end
    end
    local bulb=item:getFullType()==Items.lanternType
    local replace=context:addOption(bulb and HalloweenEvent.text("ReplaceBulb") or HalloweenEvent.text("ReplaceCandle"),player,service,item,bulb and "Bulb" or "Candle",supply)
    replace.notAvailable=not supply
    if not supply then V.tooltip(replace,bulb and HalloweenEvent.text("CarryBulb") or HalloweenEvent.text("CarryCandle")) end
    if bulb then
        local remove=context:addOption(HalloweenEvent.text("RemoveBulb"),player,service,item,"RemoveBulb")
        remove.notAvailable=F.state(item).bulbLife<=0
    end
end
local function inventoryMenu(n,context,selection)
    local player=getSpecificPlayer(n);if not player or not context then return end
    for _,option in ipairs(context.options or {}) do
        local item=option.target
        if item and item.getFullType and F.lights[item:getFullType()] and option.onSelect==ISInventoryPaneContextMenu.onActivateItem then
            option.notAvailable=not item:isActivated() and not F.canLight(item);V.explain(option,item)
        end
    end
    for _,value in ipairs(selection or {}) do
        local item=type(value)=="table" and value.items and value.items[1] or value
        if item and item.getFullType and F.lights[item:getFullType()] then V.options(context,player,item);return end
    end
end
local function worldMenu(n,context,objects,test)
    if test or not context then return end
    local player=getSpecificPlayer(n);if not player then return end
    local seen={}
    for _,obj in ipairs(objects or {}) do
        local sq=obj:getSquare()
        if sq and not seen[sq] then
            seen[sq]=true
            local list=sq:getWorldObjects()
            for i=0,list:size()-1 do
                local item=list:get(i):getItem()
                if item and F.lights[item:getFullType()] then V.options(context,player,item) end
            end
        end
    end
end
if Events.OnTick then Events.OnTick.Add(function()
    local ok,err=pcall(V.update)
    if not ok then warn("update",err) end
end) end
if Events.LoadGridsquare then Events.LoadGridsquare.Add(V.scan) end
if Events.OnFillInventoryObjectContextMenu then Events.OnFillInventoryObjectContextMenu.Add(inventoryMenu) end
if Events.OnFillWorldObjectContextMenu then Events.OnFillWorldObjectContextMenu.Add(worldMenu) end
if Events.OnServerCommand then Events.OnServerCommand.Add(function(module,command,args)
    if module~="EVHalloweenItems" or command~="LightState" then return end
    local item=V.world[args.id]
    if not item and args.x then item=F.worldItem(getCell():getGridSquare(args.x,args.y,args.z),args.id) end
    if not item then
        for n=0,getNumActivePlayers()-1 do
            local player=getSpecificPlayer(n)
            if player then item=F.find(player:getInventory(),args.id);if item then break end end
        end
    end
    if item then applyState(item,args);register(item) else V.pending[args.id]=args end
end) end
function V.installNativeToggle()
    if not ISInventoryPaneContextMenu or ISInventoryPaneContextMenu.EVHItems11Light then return end
    ISInventoryPaneContextMenu.EVHItems11Light=true
    local activate=ISInventoryPaneContextMenu.onActivateItem
    ISInventoryPaneContextMenu.onActivateItem=function(item,playerNum)
        if item and F.lights[item:getFullType()] then
            local player=getSpecificPlayer(playerNum);if player then V.toggle(player,item) end
            return
        end
        return activate(item,playerNum)
    end
end
if Events.OnGameStart then Events.OnGameStart.Add(function()
    V.installNativeToggle()
    V.preloadCandles()
    HalloweenEvent.log("ITEMS VISUAL_READY version="..Items.VERSION.." indexedModels=true atlasRefresh=true risingBubbleSprites=true warmFloorLights=true")
end) end
local function equipped(character,item)
    if item and F.bucketTypes[item:getFullType()] then
        F.visual(item)
        if character and character.resetEquippedHandsModels then character:resetEquippedHandsModels() end
    end
end
if Events.OnEquipPrimary then Events.OnEquipPrimary.Add(equipped) end
if Events.OnEquipSecondary then Events.OnEquipSecondary.Add(equipped) end
return V
