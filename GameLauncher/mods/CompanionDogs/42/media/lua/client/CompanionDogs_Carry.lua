require "TimedActions/Animals/ISPickupAnimal"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function cdDeepCopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = cdDeepCopy(v) end
    return r
end

if not ISPickupAnimal.cd_carryWrapped then
    local vanillaComplete = ISPickupAnimal.complete
    function ISPickupAnimal:complete()
        local ok = vanillaComplete(self)
        local a, chr = self.animal, self.character
        if a and chr and CD.isDog(a) and CD.isCompanion(a) and CD.isOwnedBy(a, chr) then
            CD.request("carry", nil, {
                onlineID = a:getOnlineID(),
                data = cdDeepCopy(CD.data(a)),
            }, chr)
        end
        return ok
    end
    ISPickupAnimal.cd_carryWrapped = true
end

local stashRequested = {}
local function onCarryVehicleEnter(player)
    if not player then return end
    local pn = player:getPlayerNum()
    if not CD.isMounted(player) then
        stashRequested[pn] = nil
        return
    end
    if stashRequested[pn] then return end
    local inv = player:getInventory()
    local items = inv:getItems()
    local holding = false
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and instanceof(it, "AnimalInventoryItem") then
            holding = true
            break
        end
    end
    if not holding then return end
    stashRequested[pn] = true
    CD.request("stashcarried", nil, {}, player)
end

if isClient() or not isServer() then
    CD.evAdd(Events.OnPlayerUpdate, onCarryVehicleEnter, "cli.carry")
end
