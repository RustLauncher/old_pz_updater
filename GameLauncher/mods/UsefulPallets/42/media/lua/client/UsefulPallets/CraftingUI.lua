require "UsefulPallets/CraftAction"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISCraftingUI"
require "Entity/ISEntityUI"
require "Entity/ISUI/CraftRecipe/ISHandCraftPanel"
require "Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl"
local WP = UsefulPallets
local serial = 0
local pending = {}

local getContainers = ISInventoryPaneContextMenu.getContainers
function ISInventoryPaneContextMenu.getContainers(character)
    local containers = getContainers(character)
    -- Restrict preview objects to the B42 crafting UI. Building, looting and
    -- every other caller continue to receive exclusively real containers.
    if WP.recipeDiscoveryCharacter == character then
        for _, pallet in ipairs(WP.nearbyRecipePallets(character)) do
            local preview = WP.recipePreview(pallet)
            if preview then containers:add(preview) end
        end
    end
    return containers
end

local updateContainers = ISHandCraftPanel.updateContainers
function ISHandCraftPanel:updateContainers(force)
    local old = WP.recipeDiscoveryCharacter
    WP.recipeDiscoveryCharacter = self.player
    local ok, result = pcall(updateContainers, self, force)
    WP.recipeDiscoveryCharacter = old
    if not ok then error(result) end
    return result
end

local transferIfNeeded = ISInventoryPaneContextMenu.transferIfNeeded
function ISInventoryPaneContextMenu.transferIfNeeded(character, item, ...)
    if WP.recipeItems[item] then return end -- custom preparation retrieves this real unit
    return transferIfNeeded(character, item, ...)
end

local returnItems = ISCraftingUI.ReturnItemsToOriginalContainer
function ISCraftingUI.ReturnItemsToOriginalContainer(character, items)
    local real = {}
    for _, item in ipairs(items) do if not WP.recipeItems[item] then real[#real + 1] = item end end
    return returnItems(character, real)
end

function WP.recipeSelection(logic)
    local inputs, specs, unique, originals, associations = {}, {}, {}, {}, {}
    local recipe, data = logic:getRecipe(), logic:getRecipeData()
    if not data then return inputs, specs end
    local putBack = data:getAllPutBackInputItems()
    local scripts = recipe:getInputs()
    for i = 0, scripts:size() - 1 do
        local input = scripts:get(i)
        if input:getResourceType() == ResourceType.Item then
            local index = recipe:getIndexForIO(input)
            -- IO indices also include outputs. Ask the input's applied-data
            -- cache for the actual selected units, not its candidate pool.
            local items = ArrayList.new()
            local inputData = data:getDataForInputScript(input)
            if inputData then inputData:addAppliedItemsToList(items) end
            inputs[index] = ArrayList.new()
            if items then
                for j = 0, items:size() - 1 do
                    local item = items:get(j)
                    local marker = WP.recipeItems[item]
                    if marker then
                        local spec = unique[item]
                        if not spec then
                            local square = marker.pallet:getSquare()
                            spec = {x = square:getX(), y = square:getY(), z = square:getZ(),
                                objectIndex = marker.pallet:getObjectIndex(), unitIndex = marker.index,
                                count = marker.count, revision = marker.revision, itemType = item:getFullType(),
                                putBack = putBack:contains(item) and not logic:getPlayer():hasTrait(CharacterTrait.DISORGANIZED)}
                            unique[item] = spec
                            originals[#originals + 1] = {spec = spec, pallet = marker.pallet}
                        end
                        local use = copyTable(spec)
                        use.inputIndex = index
                        specs[#specs + 1] = use
                        -- Link duplicates locally; no preview references go into the network plan.
                        associations[use] = spec
                    else
                        inputs[index]:add(item)
                    end
                end
            end
        end
    end
    return inputs, specs, originals, associations
end

local function build(logic, eatPercentage, batch)
    logic:canPerformCurrentRecipe() -- refresh applied input data before reading selections
    local inputs, specs, originals, associations = WP.recipeSelection(logic)
    if #specs == 0 then
        local hasPreview = false
        local containers = logic:getContainers()
        for i = 0, containers:size() - 1 do
            if WP.recipeContainers[containers:get(i)] then hasPreview = true; break end
        end
        -- A batch may spend carried ingredients first and reach pallet stock
        -- only in later iterations. Keep replanning that combined batch.
        if not batch or not hasPreview then return nil end
    end
    serial = serial + 1
    local character, recipe = logic:getPlayer(), logic:getRecipe()
    local token = tostring(character:getPlayerNum()) .. ":" .. tostring(getTimestampMs()) .. ":" .. serial
    local actions = {}
    if not recipe:isCanBeDoneFromFloor() then
        -- Remove descending indices so earlier retrievals do not shift a later selection.
        table.sort(originals, function(a, b)
            if a.pallet == b.pallet then return a.spec.unitIndex > b.spec.unitIndex end
            return a.spec.x .. ":" .. a.spec.y .. ":" .. a.spec.objectIndex
                < b.spec.x .. ":" .. b.spec.y .. ":" .. b.spec.objectIndex
        end)
        local removed = {}
        for i, original in ipairs(originals) do
            local spec, pallet = original.spec, original.pallet
            spec.receipt = token .. ":" .. i
            actions[#actions + 1] = ISUsefulPalletIngredient:new(character, pallet, spec.itemType,
                spec.unitIndex, spec.count - (removed[pallet] or 0), spec.revision, spec.receipt)
            removed[pallet] = (removed[pallet] or 0) + 1
        end
        for _, use in ipairs(specs) do
            use.receipt = associations[use].receipt
        end
    end
    local data = logic:getRecipeData()
    local recipeItem = logic:isUsingRecipeAtHandBenefit() and logic:getUsingRecipeAtHandItem() or nil
    local craft = ISUsefulPalletCraft:new(character, recipe, WP.realRecipeContainers(logic:getContainers()),
        logic:getIsoObject(), logic:getCraftBench(), inputs, recipeItem,
        data and data:getVariableInputRatio() or 1, eatPercentage or 0, specs, token)
    actions[#actions + 1] = craft
    if not recipe:isCanBeDoneFromFloor() then
        for _, original in ipairs(originals) do
            local spec = original.spec
            if spec.putBack then
                actions[#actions + 1] = ISUsefulPalletReturn:new(character, original.pallet,
                    spec.itemType, spec.revision, spec.receipt, token)
            end
        end
    end
    craft.sourceLogic = logic
    return actions, craft
end

local function callWithRealContainers(func, character, logic, ...)
    local containers = ArrayList.new()
    local source = logic:getContainers()
    for i = 0, source:size() - 1 do containers:add(source:get(i)) end
    logic:setContainers(WP.realRecipeContainers(containers))
    local ok, result = pcall(func, character, logic, ...)
    logic:setContainers(containers)
    if not ok then error(result) end
    return result
end

local startMultiple = ISEntityUI.HandcraftStartMultiple
function ISEntityUI.HandcraftStartMultiple(character, logic, force, qty, addToQueue)
    if logic:getPlayer() ~= character or (not force and logic:getPossibleCraftCount(true) < qty) then return end
    local actions, craft = build(logic, nil, qty > 1)
    if not actions then return callWithRealContainers(startMultiple, character, logic, force, qty, addToQueue) end
    craft.force, craft.repeatRemaining = force, qty - 1
    if logic:getRecipe():isAnySurfaceCraft() and not ISEntityUI.WalkToEntity(character, logic:getIsoObject()) then return end
    if addToQueue then for _, action in ipairs(actions) do ISTimedActionQueue.add(action) end end
    -- Plan each repeat after the previous completion, against fresh inventories
    -- and pallet boundaries, rather than reusing already-consumed preview units.
    return actions
end

local startSingle = ISEntityUI.HandcraftStart
function ISEntityUI.HandcraftStart(character, logic, force, addToQueue, eatPercentage)
    if logic:getPlayer() ~= character or (not force and not logic:canPerformCurrentRecipe()) then return end
    local actions, craft = build(logic, eatPercentage)
    if not actions then return callWithRealContainers(startSingle, character, logic, force, addToQueue, eatPercentage) end
    if logic:getRecipe():isAnySurfaceCraft() and not ISEntityUI.WalkToEntity(character, logic:getIsoObject()) then return end
    if not addToQueue then
        -- Single-action callers queue the returned craft themselves. Queue its
        -- ingredient preparation now, just as vanilla transferIfNeeded does.
        craft.postReturns = {}
        local afterCraft = false
        for _, action in ipairs(actions) do
            if action == craft then afterCraft = true
            elseif afterCraft then craft.postReturns[#craft.postReturns + 1] = action
            else ISTimedActionQueue.add(action) end
        end
    else
        for _, action in ipairs(actions) do ISTimedActionQueue.add(action) end
    end
    craft.force = force
    return craft
end

local perform = ISUsefulPalletCraft.perform
function ISUsefulPalletCraft:perform()
    for _, action in ipairs(self.postReturns or {}) do ISTimedActionQueue.add(action) end
    perform(self)
    if not self.cancelled then pending[#pending + 1] = {action = self, time = getTimestampMs()} end
end

local function ready(result)
    for _, expected in ipairs(result.counts or {}) do
        local square = getCell():getGridSquare(expected.x, expected.y, expected.z)
        if not square or expected.objectIndex >= square:getObjects():size() then return false end
        local state = WP.state(square:getObjects():get(expected.objectIndex))
        if not state or state.count ~= expected.count then return false end
    end
    local returnedCounts = {}
    for _, receipt in ipairs(result.returns or {}) do
        local returned = WP.recipeReturnResults[receipt]
        if not returned then return false end
        if returned.success then
            local key = returned.x .. ":" .. returned.y .. ":" .. returned.z .. ":" .. returned.objectIndex
            if not returnedCounts[key] or returnedCounts[key].count < returned.count then returnedCounts[key] = returned end
        end
    end
    for _, returned in pairs(returnedCounts) do
        local square = getCell():getGridSquare(returned.x, returned.y, returned.z)
        local state = square and returned.objectIndex < square:getObjects():size()
            and WP.state(square:getObjects():get(returned.objectIndex))
        if not state or state.count ~= returned.count then return false end
    end
    return true
end

Events.OnTick.Add(function()
    for i = #pending, 1, -1 do
        local entry, action = pending[i], pending[i].action
        local result = WP.recipeResults[action.craftToken]
        local synchronized = result and ready(result)
        if synchronized or getTimestampMs() - entry.time > 15000 then
            table.remove(pending, i)
            WP.recipeResults[action.craftToken] = nil
            for _, receipt in ipairs(result and result.returns or {}) do WP.recipeReturnResults[receipt] = nil end
            WP.forgetRecipeItems(action.character, action.palletInputs)
            if synchronized and result.success and not action.cancelled and (action.repeatRemaining or 0) > 0 then
                local widget = action.onCompleteTarget
                if widget and widget.craftTimes and widget.craftTimes > 0
                    and widget.logic:getRecipe() == action.craftRecipe then
                    -- Refresh cached previews before asking the native widget to
                    -- select the next recipe's real/current inputs.
                    local old = WP.recipeDiscoveryCharacter
                    WP.recipeDiscoveryCharacter = action.character
                    local containers = ISInventoryPaneContextMenu.getContainers(action.character)
                    WP.recipeDiscoveryCharacter = old
                    widget.logic:setContainers(containers)
                    widget:startHandcraft(action.force)
                elseif not widget and action.sourceLogic and action.sourceLogic:getRecipe() == action.craftRecipe then
                    local logic = action.sourceLogic
                    local old = WP.recipeDiscoveryCharacter
                    WP.recipeDiscoveryCharacter = action.character
                    local containers = ISInventoryPaneContextMenu.getContainers(action.character)
                    WP.recipeDiscoveryCharacter = old
                    logic:setContainers(containers)
                    local actions = ISEntityUI.HandcraftStartMultiple(action.character, logic,
                        action.force, action.repeatRemaining, false)
                    for _, nextAction in ipairs(actions or {}) do
                        nextAction:setOnStart(action.onStartFunc, action.onStartTarget)
                        nextAction:setOnComplete(action.onCompleteFunc, action.onCompleteTarget)
                        nextAction:setOnCancel(action.onCancelFunc, action.onCancelTarget)
                        ISTimedActionQueue.add(nextAction)
                    end
                end
            end
        end
    end
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "UsefulPallets" then return end
    if command == "RecipeItem" then
        for player = 0, getNumActivePlayers() - 1 do
            local character = getSpecificPlayer(player)
            if character then
                local receipts = WP.recipeReceipts[character] or {}
                WP.recipeReceipts[character] = receipts
                receipts[args.receipt] = {id = args.id, time = getTimestampMs()}
            end
        end
    elseif command == "RecipeResult" then
        WP.recipeResults[args.token] = args
    elseif command == "RecipeReturn" then
        WP.recipeReturnResults[args.receipt] = args
    end
end)
