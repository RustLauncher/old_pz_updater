require "UsefulPallets/TransferAction"
local WP = UsefulPallets
WP.recipePreviews = setmetatable({}, {__mode = "k"})
WP.recipeItems = setmetatable({}, {__mode = "k"})
WP.recipeContainers = setmetatable({}, {__mode = "k"})
WP.recipeReceipts = setmetatable({}, {__mode = "k"})
WP.recipeResults = {}
WP.recipeReturnResults = {}

local function equalRecord(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equalRecord(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function recordKey(record)
    return tostring(record.condition) .. ":" .. tostring(record.customName) .. ":" .. tostring(record.name)
end

function WP.recipePreview(pallet)
    local state = WP.state(pallet)
    if not state or state.count == WP.bottomCount(state) then return nil end
    local cached = WP.recipePreviews[pallet]
    if cached and cached.count == state.count and cached.units == state.units
        and cached.revision == (state.stackRevision or 0) and cached.item == state.item
        and cached.bottom == WP.bottomCount(state) then return cached.container end
    local container = ItemContainer.new("UsefulPalletsPreview", pallet:getSquare(), pallet)
    local reusable, entries = {}, {}
    if cached and cached.item == state.item and cached.bottom == WP.bottomCount(state)
        and cached.revision == (state.stackRevision or 0) then
        for _, entry in ipairs(cached.entries or {}) do
            local key = recordKey(entry.record)
            reusable[key] = reusable[key] or {}
            table.insert(reusable[key], entry)
        end
    end
    -- Highest unit first: match the normal pallet's top-first unloading order.
    for index = state.count, WP.bottomCount(state) + 1, -1 do
        local item = instanceItem(state.item)
        if not item then return nil end
        WP.restoreItem(item, state.units and state.units[index] or {})
        local record = WP.captureItem(item)
        local pool = reusable[recordKey(record)]
        for i = pool and #pool or 0, 1, -1 do
            if equalRecord(record, pool[i].record) then
                item = pool[i].item
                table.remove(pool, i)
                break
            end
        end
        -- Retain unchanged preview identities so vanilla manual selections
        -- survive count changes and batches without selecting different metadata.
        entries[#entries + 1] = {item = item, record = record}
        container:AddItem(item)
        WP.recipeItems[item] = {pallet = pallet, index = index, count = state.count,
            revision = state.stackRevision or 0}
    end
    WP.recipeContainers[container] = true
    WP.recipePreviews[pallet] = {container = container, count = state.count, units = state.units,
        revision = state.stackRevision or 0, item = state.item, bottom = WP.bottomCount(state), entries = entries}
    return container
end

function WP.nearbyRecipePallets(character)
    local result = {}
    local square = character:getSquare()
    if not square or character:getVehicle() or character:isDead() then return result end
    for y = -1, 1 do
        for x = -1, 1 do
            local nearby = getCell():getGridSquare(square:getX() + x, square:getY() + y, square:getZ())
            if nearby and square:canReachTo(nearby) then
                local objects = nearby:getObjects()
                for i = 0, objects:size() - 1 do
                    local pallet = objects:get(i)
                    if WP.canReach(character, pallet) then
                        local state = WP.state(pallet)
                        if state and state.count > WP.bottomCount(state) then result[#result + 1] = pallet end
                    end
                end
            end
        end
    end
    return result
end

function WP.realRecipeContainers(containers)
    local result = ArrayList.new()
    for i = 0, containers:size() - 1 do
        local container = containers:get(i)
        if not WP.recipeContainers[container] then result:add(container) end
    end
    return result
end

function WP.recipePallet(spec, character)
    if type(spec.x) ~= "number" or type(spec.y) ~= "number" or type(spec.z) ~= "number"
        or spec.x ~= math.floor(spec.x) or spec.y ~= math.floor(spec.y) or spec.z ~= math.floor(spec.z)
        or math.abs(spec.x) == math.huge or math.abs(spec.y) == math.huge or math.abs(spec.z) == math.huge
        or type(spec.objectIndex) ~= "number" or spec.objectIndex < 0
        or spec.objectIndex ~= math.floor(spec.objectIndex) then return nil end
    local square = getCell():getGridSquare(spec.x, spec.y, spec.z)
    if not square or not character:getSquare() or not character:getSquare():canReachTo(square) then return nil end
    local objects = square:getObjects()
    if spec.objectIndex >= objects:size() then return nil end
    local pallet = objects:get(spec.objectIndex)
    local state = WP.canReach(character, pallet) and WP.state(pallet)
    if not state or state.item ~= spec.itemType or state.count ~= spec.count
        or (state.stackRevision or 0) ~= spec.revision or type(spec.unitIndex) ~= "number"
        or spec.unitIndex ~= math.floor(spec.unitIndex) or spec.unitIndex > state.count
        or spec.unitIndex <= WP.bottomCount(state) then return nil end
    return pallet, state
end

function WP.rememberRecipeItem(character, receipt, item)
    local receipts = WP.recipeReceipts[character] or {}
    WP.recipeReceipts[character] = receipts
    local now = getTimestampMs()
    for key, entry in pairs(receipts) do if now - entry.time > 300000 then receipts[key] = nil end end
    receipts[receipt] = {id = item:getID(), time = now}
    if isServer() then
        sendServerCommand(character, "UsefulPallets", "RecipeItem", {receipt = receipt, id = item:getID()})
    end
end

function WP.resolveRecipeItem(character, receipt)
    local receipts = WP.recipeReceipts[character]
    local entry = receipts and receipts[receipt]
    if not entry or getTimestampMs() - entry.time > 300000 then return nil end
    return character:getInventory():getItemById(entry.id)
end

function WP.forgetRecipeItems(character, specs)
    local receipts = WP.recipeReceipts[character]
    if not receipts then return end
    for _, spec in ipairs(specs) do if spec.receipt then receipts[spec.receipt] = nil end end
end

-- Constructor arguments are also the B42 server reconstruction schema.
ISUsefulPalletIngredient = ISUsefulPalletTransfer:derive("ISUsefulPalletIngredient")
function ISUsefulPalletIngredient:new(character, pallet, itemType, unitIndex, expectedCount, revision, receipt)
    local o = ISUsefulPalletTransfer.new(self, character, pallet, itemType, "take", nil, nil, revision)
    o.unitIndex, o.expectedCount, o.receipt = unitIndex, expectedCount, receipt
    return o
end
function ISUsefulPalletIngredient:isValid()
    if not ISUsefulPalletTransfer.isValid(self) then return false end
    local state = WP.state(self.pallet)
    return state.count == self.expectedCount and type(self.unitIndex) == "number"
        and self.unitIndex == math.floor(self.unitIndex) and self.unitIndex > WP.bottomCount(state)
        and self.unitIndex <= state.count and type(self.receipt) == "string" and #self.receipt <= 128
        and not WP.resolveRecipeItem(self.character, self.receipt)
end
function ISUsefulPalletIngredient:complete()
    if not ISUsefulPalletTransfer.complete(self) then return false end
    WP.rememberRecipeItem(self.character, self.receipt, self.takenItem)
    return true
end
-- The crafting widget assigns callbacks to every queued action. Retrieval is
-- not a completed recipe and must not decrement its batch counter.
function ISUsefulPalletIngredient:setOnStart() end
function ISUsefulPalletIngredient:setOnComplete() end
function ISUsefulPalletIngredient:setOnCancel(func, target) self.onCancelFunc, self.onCancelTarget = func, target end
function ISUsefulPalletIngredient:stop()
    ISUsefulPalletTransfer.stop(self)
    if self.onCancelFunc then self.onCancelFunc(self.onCancelTarget) end
end

ISUsefulPalletReturn = ISUsefulPalletIngredient:derive("ISUsefulPalletReturn")
function ISUsefulPalletReturn:new(character, pallet, itemType, revision, receipt, craftToken)
    local o = ISUsefulPalletTransfer.new(self, character, pallet, itemType, "add", nil, nil, revision)
    o.receipt, o.craftToken = receipt, craftToken
    return o
end
function ISUsefulPalletReturn:isValid()
    self.item = WP.resolveRecipeItem(self.character, self.receipt)
    return ISUsefulPalletTransfer.isValid(self)
end
function ISUsefulPalletReturn:complete()
    local success = ISUsefulPalletTransfer.complete(self)
    WP.forgetRecipeItems(self.character, {{receipt = self.receipt}})
    local state, square = WP.state(self.pallet), self.pallet:getSquare()
    local result = {token = self.craftToken, receipt = self.receipt, success = success,
        count = state and state.count, x = square:getX(), y = square:getY(), z = square:getZ(),
        objectIndex = self.pallet:getObjectIndex()}
    if isServer() then sendServerCommand(self.character, "UsefulPallets", "RecipeReturn", result)
    else WP.recipeReturnResults[self.receipt] = result end
    return success
end
