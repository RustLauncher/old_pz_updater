local variantModels = {
    ["Base.Tacklebox"] = {
        Tacklebox1 = "Tacklebox_BagAttached",
        Tacklebox2 = "Tacklebox_BagAttached_2",
        Tacklebox3 = "Tacklebox_BagAttached_3",
    },
}

local choiceToVariant = {
    [0] = "Tacklebox1",
    [1] = "Tacklebox2",
    [2] = "Tacklebox3",
}

local bottomLocations = {
    "Bedroll Bottom",
    "Bedroll Bottom Big",
    "Bedroll Bottom ALICE",
}

local function getTextureChoice(item)
    if not item then return nil end
    local okVisual, visual = pcall(function() return item:getVisual() end)
    if not okVisual or not visual then return nil end
    local okChoice, choice = pcall(function() return visual:getTextureChoice() end)
    if okChoice and choice ~= nil and choice >= 0 and choice <= 2 then
        return choice
    end
    return nil
end

local function cacheVariant(item)
    if not item or item:getFullType() ~= "Base.Tacklebox" then
        return nil
    end
    local choice = getTextureChoice(item)
    if choice ~= nil then
        local variant = choiceToVariant[choice]
        if variant then
            local modData = item:getModData()
            modData.bbbVariant = variant
            modData.bbbTextureChoice = choice
            return variant
        end
    end
    return nil
end

local function installHotbarHook()
    if not ISHotbar or not ISHotbar.attachItem then
        return
    end
    if ISHotbar.__BBB_TextureSyncHooked then
        return
    end
    local originalAttachItem = ISHotbar.attachItem
    ISHotbar.attachItem = function(self, item, slot, slotIndex, slotDef, doAnim)
        if item and item:getFullType() == "Base.Tacklebox" then
            cacheVariant(item)
        end
        return originalAttachItem(self, item, slot, slotIndex, slotDef, doAnim)
    end
    ISHotbar.__BBB_TextureSyncHooked = true
end

Events.OnGameStart.Add(installHotbarHook)

local function syncAttachedModels(character)
    if not character then return end
    for _, location in ipairs(bottomLocations) do
        local item = character:getAttachedItem(location)
        if item and item:getFullType() == "Base.Tacklebox" then
            local modData = item:getModData()
            local variant = modData.bbbVariant
            if not variant then
                variant = cacheVariant(item)
            end
            local variants = variantModels[item:getFullType()]
            local desiredModel = variant and variants[variant]
            if desiredModel and item:getStaticModel() ~= desiredModel then
                item:setStaticModel(desiredModel)
            end
        end
    end
end

local tickCounter = 0
local function onPlayerUpdate(character)
    tickCounter = tickCounter + 1
    if tickCounter < 30 then
        return
    end
    tickCounter = 0
    if not character then
        character = getPlayer()
    end
    syncAttachedModels(character)
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)