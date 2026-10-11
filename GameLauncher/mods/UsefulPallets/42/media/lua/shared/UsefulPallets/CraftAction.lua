require "UsefulPallets/Crafting"
require "UsefulPallets/Recipes"
require "Entity/TimedActions/ISHandcraftAction"
local WP = UsefulPallets
ISUsefulPalletCraft = ISHandcraftAction:derive("ISUsefulPalletCraft")

local function unitKey(spec)
    return spec.x .. ":" .. spec.y .. ":" .. spec.z .. ":" .. spec.objectIndex .. ":" .. spec.unitIndex
end

-- Preview items never cross the network. Send only real normal inputs and
-- pallet coordinates/indices, or a receipt for a completed one-item retrieval.
function ISUsefulPalletCraft:new(character, craftRecipe, containers, isoObject, craftBench,
        manualInputs, recipeItem, variableInputRatio, eatPercentage, palletInputs, craftToken)
    local o = ISHandcraftAction.new(self, character, craftRecipe, containers, isoObject, craftBench,
        manualInputs, nil, recipeItem, variableInputRatio, eatPercentage)
    o.palletInputs = convertToPZNetTable(palletInputs)
    o.craftToken = craftToken
    return o
end

function ISUsefulPalletCraft:prepare(materialize)
    local inputs, containers = {}, WP.realRecipeContainers(self.containers)
    for index, items in pairs(self.manualInputs or {}) do
        inputs[index] = ArrayList.new()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            inputs[index]:add(self.character:getInventory():getItemById(item:getID()) or item)
        end
    end
    local temporary, resolved, previewContainers = {}, {}, {}
    if type(self.craftToken) ~= "string" or #self.craftToken > 128
        or type(self.palletInputs) ~= "table" or #self.palletInputs > 20000 then return nil, temporary end
    for _, spec in ipairs(self.palletInputs) do
        if type(spec.inputIndex) ~= "number" or not WP.byItem[spec.itemType] then return nil, temporary end
        local inputScript = self.craftRecipe:getIOForIndex(spec.inputIndex)
        if not inputScript or not self.craftRecipe:getInputs():contains(inputScript)
            or inputScript:getResourceType() ~= ResourceType.Item then return nil, temporary end
        local item
        if spec.receipt then
            if self.craftRecipe:isCanBeDoneFromFloor() then return nil, temporary end
            item = WP.resolveRecipeItem(self.character, spec.receipt)
            if not item or item:getFullType() ~= spec.itemType or item:getContainer() ~= self.character:getInventory()
                or item:isFavorite() or self.character:isEquipped(item) then return nil, temporary end
        else
            if not self.craftRecipe:isCanBeDoneFromFloor() then return nil, temporary end
            local pallet, state = WP.recipePallet(spec, self.character)
            if not pallet then return nil, temporary end
            local key = unitKey(spec)
            item = resolved[key]
            if not item then
                if materialize then
                    item = self.character:getInventory():AddItem(spec.itemType)
                    if not item then return nil, temporary end
                    temporary[#temporary + 1] = {item = item, pallet = pallet, state = state, index = spec.unitIndex}
                else
                    local container = previewContainers[pallet]
                    if not container then
                        container = ItemContainer.new("UsefulPalletsPreview", pallet:getSquare(), pallet)
                        previewContainers[pallet] = container
                        containers:add(container)
                    end
                    item = instanceItem(spec.itemType)
                    if not item then return nil, temporary end
                    container:AddItem(item)
                end
                WP.restoreItem(item, state.units and state.units[spec.unitIndex] or {})
                resolved[key] = item
            end
        end
        inputs[spec.inputIndex] = inputs[spec.inputIndex] or ArrayList.new()
        inputs[spec.inputIndex]:add(item)
    end
    local logic = HandcraftLogic.new(self.character, self.craftBench, self.isoObject)
    logic:setContainers(containers)
    logic:setRecipe(self.craftRecipe)
    logic:setTargetVariableInputRatio(self.variableInputRatio)
    logic:setManualSelectInputs(true)
    logic:clearManualInputs()
    for index, items in pairs(inputs) do
        local input = self.craftRecipe:getIOForIndex(index)
        if not input or not logic:setManualInputsFor(input, items) then return nil, temporary end
    end
    if not logic:canPerformCurrentRecipe() then return nil, temporary end
    return logic, temporary, inputs, containers
end

function ISUsefulPalletCraft:isValid()
    if not ISHandcraftAction.isValid(self) then return false end
    if isClient() then
        for _, spec in ipairs(self.palletInputs) do
            if spec.receipt and not WP.resolveRecipeItem(self.character, spec.receipt) then
                self.receiptWait = self.receiptWait or getTimestampMs()
                return getTimestampMs() - self.receiptWait < 15000
            end
        end
    end
    return self:prepare(false) ~= nil
end

function ISUsefulPalletCraft:waitToStart()
    for _, spec in ipairs(self.palletInputs) do
        if spec.receipt and not WP.resolveRecipeItem(self.character, spec.receipt) then
            self.receiptWait = self.receiptWait or getTimestampMs()
            if getTimestampMs() - self.receiptWait < 15000 then return true end
            self:forceStop()
            return false
        end
    end
    return false
end

function ISUsefulPalletCraft:serverStart()
    self.logic = self:prepare(false)
end

function ISUsefulPalletCraft:start()
    local logic, _, inputs, containers = self:prepare(false)
    if not logic then self:forceStop(); return end
    -- Reuse vanilla animation/model/callback setup without retaining ephemeral
    -- containers or items in any constructor field serialized by B42.
    local savedInputs, savedContainers = self.manualInputs, self.containers
    self.manualInputs, self.containers = inputs, containers
    ISHandcraftAction.start(self)
    self.manualInputs, self.containers = savedInputs, savedContainers
end

local function dispose(character, temporary, commit)
    local groups = {}
    local inventory = character:getInventory()
    for _, entry in ipairs(temporary) do
        if commit then
            local group = groups[entry.pallet]
            if not group then
                local state = entry.state
                local units = {}
                for i = 1, state.count do units[i] = copyTable(state.units and state.units[i] or {}) end
                group = {state = state, units = units, removed = {}}
                groups[entry.pallet] = group
            end
            if inventory:contains(entry.item) then
                -- A kept ingredient stays on the pallet with vanilla's updated properties.
                group.units[entry.index] = WP.captureItem(entry.item)
            else
                group.removed[#group.removed + 1] = entry.index
            end
        end
        if inventory:contains(entry.item) then inventory:Remove(entry.item) end
    end
    local counts = {}
    for pallet, group in pairs(groups) do
        table.sort(group.removed, function(a, b) return a > b end)
        for _, index in ipairs(group.removed) do table.remove(group.units, index) end
        local state = group.state
        state.count, state.units = #group.units, group.units
        if state.count == 0 then state.item = nil end
        local sprite = #group.removed > 0 and WP.spriteFor(state.kind, state.item, state.count, WP.bottomCount(state))
            or pallet:getSprite():getName()
        if #group.removed > 0 then state.vanillaIntact = nil end
        pallet:getModData().UsefulPallets = state
        pallet:transmitModData()
        if sprite ~= pallet:getSprite():getName() then
            pallet:setSpriteFromName(sprite)
            pallet:transmitUpdatedSpriteToClients()
            pallet:getSquare():RecalcProperties()
            pallet:getSquare():RecalcAllWithNeighbours(true)
        end
        local square = pallet:getSquare()
        counts[#counts + 1] = {x = square:getX(), y = square:getY(), z = square:getZ(),
            objectIndex = pallet:getObjectIndex(), count = state.count}
    end
    return counts
end

-- Same recipe execution steps as B42 ISHandcraftAction.performRecipe. Keeping
-- its success result lets us clean up temporary direct-use inputs safely.
local function executeVanilla(action)
    local logic, character = action.logic, action.character
    if not logic:performCurrentRecipe() then return false end
    local items = ArrayList.new()
    logic:getCreatedOutputItems(items)
    UsefulPalletsRecipes.prepareOutputs(action.craftRecipe, items)
    for i = 0, items:size() - 1 do Actions.addOrDropItem(character, items:get(i)) end
    local data = logic:getRecipeData()
    local callbackOK, callbackError = pcall(data.luaCallOnCreate, data, character)
    data:processDestroyAndUsedItems(character)
    if items:size() == 1 then
        local modData = items:get(0):getModData()
        local used = data:getAllConsumedItems()
        for i = 0, used:size() - 1 do
            local itemType = used:get(i):getFullType()
            modData[itemType] = (modData[itemType] or 0) + 1
        end
    end
    if not callbackOK then error(callbackError) end
    return true
end

function ISUsefulPalletCraft:performRecipe()
    local logic, temporary = self:prepare(true)
    local success, counts = false, {}
    if logic then
        self.logic = logic
        if self.eatPercentage > 0 then logic:getRecipeData():setEatPercentage(self.eatPercentage) end
        local ok, result = pcall(executeVanilla, self)
        -- Even if an external recipe callback raises after consuming inputs,
        -- account for consumed units before reporting the failure; never refill them.
        counts = dispose(self.character, temporary, true)
        success = ok and result == true
        if not ok then print("Useful Pallets recipe failed: " .. tostring(result)) end
    else
        dispose(self.character, temporary, false)
    end
    local forget, returns = {}, {}
    for _, spec in ipairs(self.palletInputs) do
        if spec.receipt and spec.putBack and WP.resolveRecipeItem(self.character, spec.receipt) then
            returns[#returns + 1] = spec.receipt
        else
            forget[#forget + 1] = spec
        end
    end
    WP.forgetRecipeItems(self.character, forget)
    self.recipeSucceeded = success
    local result = {token = self.craftToken, success = success, counts = counts, returns = returns}
    if isServer() then sendServerCommand(self.character, "UsefulPallets", "RecipeResult", result)
    else WP.recipeResults[self.craftToken] = result end
end

function ISUsefulPalletCraft:complete()
    -- Vanilla's completion does not revalidate ingredients on the server.
    -- Our execution builds fresh logic and checks reach, counts and layers.
    if not ISHandcraftAction.isValid(self) then return false end
    return ISHandcraftAction.complete(self)
end

function ISUsefulPalletCraft:stop()
    self.cancelled = true
    WP.forgetRecipeItems(self.character, self.palletInputs)
    ISHandcraftAction.stop(self)
end
