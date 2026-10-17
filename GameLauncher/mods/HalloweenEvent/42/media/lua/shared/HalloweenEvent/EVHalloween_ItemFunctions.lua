-- Item Pack 13: state belongs to each item, never to its shared ScriptItem.
require "HalloweenEvent/EVHalloween_Items"
local Items = HalloweenEvent.Items
local F = {}
Items.Functions = F
F.bowlType = "HalloweenEvent.EVHalloween_Decor_HalloweenCandyBowl"
F.potionType = "HalloweenEvent.EVHalloween_Decor_WitchesCauldron"
F.pumpkinType = "HalloweenEvent.EVHalloween_Decor_JackOLanternGrin"
F.catPumpkinType = "HalloweenEvent.EVHalloween_Decor_JackOLanternCat"
F.doormatType = "HalloweenEvent.EVHalloween_Decor_TombstoneCracked"
F.candleFrames = {}
F.candlePulse = {}
F.candleModels={}
F.candleModelsApplied=setmetatable({},{__mode="k"})
function F.candleModelArrays(item)
    if F.candleModelsApplied[item] or not ArrayList then return end
    local ft=item:getFullType()
    local arrays=F.candleModels[ft]
    if not arrays then
        local row=Items.byType[ft]
        arrays={world=ArrayList.new(),hand=ArrayList.new()}
        arrays.world:add(row.worldModel);arrays.hand:add(row.handModel)
        for level=0,7 do
            local suffix="_Lit"..(level>0 and level or "")
            local hand=row.handModel:gsub("_Hand$",suffix.."_Hand")
            local world=row.worldModel:gsub("_Ground$",suffix.."_Ground")
            arrays.world:add(world);arrays.hand:add(hand)
        end
        F.candleModels[ft]=arrays
    end
    item:setWorldStaticModelsByIndex(arrays.world)
    item:setStaticModelsByIndex(arrays.hand)
    F.candleModelsApplied[item]=true
end
F.bucketTypes = {["HalloweenEvent.EVHalloween_WitchCauldron"]=true,["HalloweenEvent.EVHalloween_PumpkinTreatPail"]=true,["HalloweenEvent.EVHalloween_PumpkinTreatBucket"]=true}
function F.carryCapacity()
    if F.nativeCarryCapacity then return F.nativeCarryCapacity end
    local reference=instanceItem("Base.HalloweenCandyBucket")
    local capacity=reference and reference:getCapacity()
    if type(capacity)=="number" and capacity>0 then
        F.nativeCarryCapacity=capacity
        HalloweenEvent.log("ITEMS CARRY_REFERENCE type=Base.HalloweenCandyBucket baseCapacity="..capacity.." weight=0.5 reduction=50")
        return capacity
    end
    -- Vanilla B42 base capacity is 2; Organized displays 3. A base value of
    -- 3 displays 4 for that character and does not match the reference bucket.
    return 2
end
F.lights = {
    [Items.lanternType] = {hours=24, strength=.55, radius=5, color={0.85,0.70,0.42}, bulb=true},
    [F.pumpkinType] = {hours=8, strength=.35, radius=3, color={1.0,0.72,0.38}, candle=true},
    [F.catPumpkinType] = {hours=8, strength=.35, radius=3, color={1.0,0.72,0.38}, candle=true},
}
function F.isCandle(item) local cfg=F.lights[item:getFullType()];return cfg and cfg.candle end

-- Record the installed vanilla values, rather than silently assuming that a
-- reference mod or another B42 build has the same drain/light parameters.
function F.auditFuelReferences(manager)
    HalloweenEvent.log("ITEMS FUEL_CONFIG batteryHours="..F.lights[Items.lanternType].hours
        .." bulbHours=120 candleHours=8 clock=authoritative_game_hours nativeDrain=false")
    for _,name in ipairs({"Base.Lantern_CraftedElectric","Base.Lantern_HurricaneLit","Base.Torch"}) do
        local script=manager:getItem(name)
        -- Only the proven ScriptItem getter is used. Light getters belong to
        -- InventoryItem, not ScriptItem, and must not be probed through pcall.
        HalloweenEvent.log("ITEMS FUEL_REFERENCE type="..name.." registered="..tostring(script~=nil)
            .." useDelta="..tostring(script and script:getUseDelta() or "unavailable"))
    end
end

function F.state(item)
    local md = item:getModData()
    md.EVHLight = md.EVHLight or {bulbLife=1, bulbType="Base.LightBulb"}
    return md.EVHLight
end

-- Keep the pumpkin's original normal item class for existing saves. Its candle
-- reserve lives in item modData; only the battery lantern is a native drainable.
function F.charge(item)
    if F.isCandle(item) then
        local state=F.state(item)
        return state.candleCharge==nil and 1 or state.candleCharge
    end
    return item:getCurrentUsesFloat()
end
function F.setCharge(item,value)
    value=math.max(0,math.min(1,value))
    if F.isCandle(item) then F.state(item).candleCharge=value
    else item:setCurrentUsesFloat(value) end
end

function F.canLight(item)
    local cfg = F.lights[item:getFullType()]
    return cfg and F.charge(item) > 0
        and (not cfg.bulb or F.state(item).bulbLife > 0)
end

-- Same capacity-weight measure used by the vanilla inventory capacity display.
-- Empty, <=25%, <=60%, and >60%; filling arbitrary contents still fills the bowl.
function F.fillStage(item)
    local inv = item:getInventory()
    local capacity = inv:getCapacity()
    local weight = inv:getCapacityWeight()
    if weight <= 0 or capacity <= 0 then return 0 end
    local ratio = math.min(1, weight/capacity)
    return ratio <= .25 and 1 or (ratio <= .60 and 2 or 3)
end

-- Native icon/model arrays share one saved index. Adopt it for legacy items;
-- initialization runs once through the recognized OnCreate script hook.
function F.bucketVariant(item,created)
    local md=item:getModData()
    if md.EVHBucketVariant==nil then
        local index=created and -1 or item:getModelIndex()
        md.EVHBucketVariant=index>=0 and index<=3 and index or (type(ZombRand)=="function" and ZombRand(4) or 0)
        HalloweenEvent.log("ITEMS BUCKET_COLOR_SET id="..tostring(item:getID()).." type="..item:getFullType().." variant="..md.EVHBucketVariant)
    end
    return md.EVHBucketVariant
end

function F.visual(item, frame)
    local ft = item:getFullType()
    local entry = Items.byType[ft]
    if not entry then return false end
    if ft==Items.coffinType and Items.CoffinPlacement then Items.CoffinPlacement.initItem(item) end
    if F.bucketTypes[ft] then
        -- Saved InventoryContainers retain their old values. Match the candy
        -- bucket on the item and its contents container without touching items.
        local capacity=F.carryCapacity()
        if item:getCapacity()~=capacity then item:setCapacity(capacity) end
        if item:getWeightReduction()~=50 then item:setWeightReduction(50) end
        if item:getActualWeight()~=.5 then item:setActualWeight(.5) end
        if item:getWeight()~=.5 then item:setWeight(.5) end
        local inventory=item:getInventory()
        if inventory:getCapacity()~=capacity then inventory:setCapacity(capacity) end
    end
    local cfg=F.lights[ft]
    if cfg and cfg.candle then F.candleModelArrays(item) end
    -- The native hand light also needs to stop when the replaceable bulb fails.
    if cfg and item.setLightStrength then
        local pulse=cfg.candle and (F.candlePulse[item:getID()] or 1) or 1
        item:setLightStrength(F.canLight(item) and cfg.strength*pulse or 0)
    end
    local suffix, index = "", 0
    if ft == F.bowlType then
        local stage = F.fillStage(item)
        suffix = stage > 0 and ("_Fill"..stage) or ""
        index = stage
    elseif F.bucketTypes[ft] then
        index=F.bucketVariant(item)
        suffix=index>0 and ("_Variant"..index) or ""
    elseif ft == F.doormatType then
        index=item:getModData().EVHDoormatVariant or 0
        suffix=index==1 and "_Variant1" or ""
    elseif F.lights[ft] and item:isActivated() and F.canLight(item) then
        -- Held and floor candles use one complete model: the carved features
        -- stay attached to the body in every camera/atlas rendering mode.
        suffix, index = "_Lit", 1
        if cfg.candle then
            local level=F.candleFrames[item:getID()] or 0
            suffix="_Lit"..(level>0 and level or "")
            index=level+1
        end
    end
    local model = entry.worldModel:gsub("_Ground$", suffix.."_Ground")
    local candle=cfg and cfg.candle
    local indexed = ft==F.bowlType or ft==F.potionType or ft==F.doormatType or F.bucketTypes[ft] or F.lights[ft]
    -- Use B42's indexed variation path and modern model setter together.
    -- Getter/model-state diagnostics distinguish a rejected override from a
    -- renderer redraw problem in the next native game test.
    local changedIndex=indexed and item:getModelIndex()~=index
    if changedIndex then item:setModelIndex(index) end
    if changedIndex or item:getWorldStaticModel() ~= model then
        item:setWorldStaticModel(model)
        if candle then
            -- B42's world-item atlas validates rotations/scale, but does not
            -- validate a changed model name/index. A full turn is visually
            -- identical and invalidates the stale atlas without relocating or
            -- resizing the item. The eight complete meshes have identical
            -- body geometry and UVs; only the carved-face UV palette differs.
            local angle=item:getWorldZRotation()
            local base=angle%360
            item:setWorldZRotation(angle==base and base+360 or base)
            local world=item:getWorldItem()
            if world then
                world:updateSprite()
                if FBORenderChunk and world.invalidateRenderChunkLevel then
                    world:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_REDRAW)
                end
            end
        else
            local md=item:getModData();local angle=item:getWorldZRotation()
            if md.EVHRenderBaseAngle==nil or (angle~=md.EVHRenderBaseAngle and angle~=md.EVHRenderBaseAngle+360) then
                md.EVHRenderBaseAngle=angle
            end
            md.EVHRenderPhase=not md.EVHRenderPhase
            item:setWorldZRotation(md.EVHRenderBaseAngle+(md.EVHRenderPhase and 360 or 0))
            local world=item:getWorldItem()
            if world then world:updateSprite() end
        end
        if ft==F.bowlType then
            HalloweenEvent.log("ITEMS BOWL_FILL id="..tostring(item:getID()).." stage="..tostring(F.fillStage(item))
                .." used="..tostring(item:getInventory():getCapacityWeight()).." capacity="..tostring(item:getInventory():getCapacity()))
        end
    end
    if entry.handModel and ft ~= F.potionType and not (candle and item:getWorldItem()) then
        local hand = entry.handModel:gsub("_Hand$", suffix.."_Hand")
        if F.bucketTypes[ft] and Items.PailGripTest then hand = Items.PailGripTest.apply(item,hand) end
        if item.setStaticModel and item:getStaticModel() ~= hand then item:setStaticModel(hand) end
    end
    if (F.bucketTypes[ft] or ft==F.doormatType) and item.setTexture and type(getTexture)=="function" then
        local icon="Item_"..item:getType()..suffix..".png"
        local texture=getTexture("media/textures/"..icon)
        if texture then item:setTexture(texture) end
    end
    return true
end

-- Native drain is disabled on these two scripts: one authoritative game-hour
-- clock handles held AND floor lights. Persisted timestamps account for reloads
-- and unloaded chunks without keeping Java world objects alive.
function F.stepFuel(item, now)
    local cfg = F.lights[item:getFullType()]
    if not cfg then return false end
    local state = F.state(item)
    local previous = state.lastHours or now
    local elapsed = math.max(0, now-previous)
    state.lastHours = now
    if not item:isActivated() then return false end
    local old = F.charge(item)
    local usable = F.canLight(item)
    local consumed = usable and math.min(elapsed, old*cfg.hours,
        cfg.bulb and math.max(0,state.bulbLife)*120 or math.huge) or 0
    F.setCharge(item,math.max(0,old-consumed/cfg.hours))
    if cfg.bulb then state.bulbLife = math.max(0,state.bulbLife-consumed/120) end
    if not F.canLight(item) then item:setActivated(false) end
    F.visual(item)
    return consumed > 0 or not usable
end

function F.find(container, id, depth)
    if not container or (depth or 0) > 12 then return nil end
    local list = container:getItems()
    for i=0,list:size()-1 do
        local item = list:get(i)
        if item:getID() == id then return item end
        if item:IsInventoryContainer() then
            local found = F.find(item:getInventory(),id,(depth or 0)+1)
            if found then return found end
        end
    end
end

function F.worldItem(square, id)
    if not square then return nil end
    local list = square:getWorldObjects()
    for i=0,list:size()-1 do
        local world = list:get(i)
        local item = world:getItem()
        if item and item:getID() == id then return item end
    end
end

function F.setDoormatVariant(item,index)
    if item:getFullType()~=F.doormatType or (index~=0 and index~=1) then return false end
    item:getModData().EVHDoormatVariant=index
    F.visual(item);return true
end
function F.init(item)
    if F.bucketTypes[item:getFullType()] then F.bucketVariant(item) end
    if item:getFullType()==F.doormatType and item:getModData().EVHDoormatVariant==nil then
        F.setDoormatVariant(item,type(ZombRand)=="function" and ZombRand(2) or 0)
    end
    if F.lights[item:getFullType()] then F.state(item) end
    F.visual(item)
end

-- Called by native item creation for new items. Old saved IDs remain unchanged.
function EVHalloweenCreateItem(item)
    item:setWorldZRotation(0)
    if F.bucketTypes[item:getFullType()] then F.bucketVariant(item,true) end
    F.init(item)
end
return F
