require "ISUI/ISContextMenu"
require "HalloweenEvent/EVHalloween_ItemFunctions"

local HWE = HalloweenEvent
local Items, F = HWE.Items, HWE.Items.Functions
if Items.PailGripTest then return Items.PailGripTest end
local G = {selected={}, arrays={}, applied=setmetatable({}, {__mode="k"})}
Items.PailGripTest = G

local function modelName(base, position, color, left)
    local suffix = color>0 and ("_Variant"..color) or ""
    if position ~= "A" then suffix = suffix.."_Grip"..position end
    if left then suffix = suffix.."_Left" end
    -- gsub also returns a replacement count. Java ArrayList.add accepts only
    -- one argument; returning both caused the confirmed ITEMS13 binding loop.
    local name = base:gsub("_Hand$", suffix.."_Hand")
    return name
end

function G.preload()
    if G.preloaded then return end
    G.preloaded = true
    G.assets = {}
    if type(loadStaticZomboidModel)~="function" or type(getScriptManager)~="function" then return end
    local manager = getScriptManager()
    for _, ft in ipairs(Items.treatContainers) do
        for _, position in ipairs({"A","B","C"}) do
            for color=0,3 do
                local name = modelName(Items.byType[ft].handModel,position,color)
                local script = manager:getModelScript(name)
                if script then
                    local ok, asset = pcall(loadStaticZomboidModel,name,script:getMeshName(),script:getTextureName())
                    if ok and asset then G.assets[#G.assets+1] = asset end
                else HWE.log("ITEMS PAIL_GRIP_MODEL_MISSING model="..name) end
            end
        end
    end
end

function G.apply(item, hand)
    local ft = item:getFullType()
    local position = G.selected[ft] or "A"
    local owner=item:getEquipParent()
    local left=F.bucketTypes[ft] and owner and owner:getSecondaryHandItem()==item and owner:getPrimaryHandItem()~=item
    local key = ft..":"..position..":"..tostring(left==true)
    -- Override the per-item indexed hand array too. Native color selection must
    -- not silently put the normal grip back after an equip or visual refresh.
    if G.applied[item] ~= key and item.setStaticModelsByIndex and ArrayList then
        local array = G.arrays[key]
        if not array then
            array = ArrayList.new()
            for color=0,3 do array:add(modelName(Items.byType[ft].handModel,position,color,left)) end
            G.arrays[key] = array
        end
        item:setStaticModelsByIndex(array)
        G.applied[item] = key
        if owner and owner.resetEquippedHandsModels then owner:resetEquippedHandsModels() end
    end
    local name=position=="A" and hand or hand:gsub("_Hand$","_Grip"..position.."_Hand")
    if left then name=name:gsub("_Hand$","_Left_Hand") end
    return name
end

local function visit(container, callback, depth)
    if not container or (depth or 0)>12 then return end
    local list = container:getItems()
    for i=0,list:size()-1 do
        local item = list:get(i)
        callback(item)
        if item:IsInventoryContainer() then visit(item:getInventory(),callback,(depth or 0)+1) end
    end
end

local function allowed(player)
    if HWE.readSandbox().EnableDebugMenu==false then return false end
    if type(isClient)~="function" or not isClient() then return true end
    local access = tostring(player:getAccessLevel() or ""):lower()
    return access=="admin" or access=="moderator" or access=="overseer"
end

function G.select(player, item, position)
    if not player or not item or not allowed(player) or not F.bucketTypes[item:getFullType()]
        or (position~="A" and position~="B" and position~="C") then return end
    local ft = item:getFullType()
    G.preload()
    G.selected[ft] = position
    visit(player:getInventory(),function(candidate)
        if candidate:getFullType()==ft then F.visual(candidate) end
    end)
    if player.resetEquippedHandsModels then player:resetEquippedHandsModels() end
    HWE.log("ITEMS PAIL_GRIP_TEST type="..ft.." position="..position
        .." effectiveHandModel="..tostring(item:getStaticModel()).." color="..F.bucketVariant(item))
    if player.Say then player:Say(HWE.choiceName(Items.byType[ft])..": "..position) end
end

local function inventoryMenu(playerNum, context, selection)
    local player = getSpecificPlayer(playerNum)
    if not player or not context or not allowed(player) then return end
    for _, value in ipairs(selection or {}) do
        local item = type(value)=="table" and value.items and value.items[1] or value
        if item and item.getFullType and F.bucketTypes[item:getFullType()]
            and item:getContainer()==player:getInventory() then
            local option = context:addOption("Pail grip test")
            local menu = ISContextMenu:getNew(context)
            context:addSubMenu(option,menu)
            for _, position in ipairs({"A","B","C"}) do
                local label = "Position "..position
                if (G.selected[item:getFullType()] or "A")==position then label=label.." *" end
                menu:addOption(label,player,G.select,item,position)
            end
            return
        end
    end
end
if Events and Events.OnFillInventoryObjectContextMenu then Events.OnFillInventoryObjectContextMenu.Add(inventoryMenu) end
if Events and Events.OnGameStart then Events.OnGameStart.Add(G.preload) end
return G
