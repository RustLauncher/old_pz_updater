local CD = CompanionDogs
if not (CD and (CD.API_VERSION or 0) >= 5) then return end
if not (CompanionCat and CompanionCat.COAT_KEYS) then return end

local MODULE = "CompanionCat"

local CATS = CompanionCat.COAT_KEYS

---Display name of the item type, or the type itself when it has none, or ? when nil.
---@param fullType string|nil
---@return string
---@nodiscard
local function preyName(fullType)
    local sm = getScriptManager()
    local def = fullType and sm:FindItem(fullType) or nil
    if def then
        local n = def:getDisplayName()
        if n and n ~= "" then return n end
    end
    return tostring(fullType or "?")
end

---Shows the night gift halo to the cat's owner.
---@param args table|nil { item, name } sent by the server
---@param owner IsoPlayer|nil defaults to the local player
function CD.CatNightGiftNotify(args, owner)
    local player = owner or getPlayer()
    if not player then return end
    if not CD.showNotifications() then return end
    local name = args and args.name
    if not name or name == "" then
        name = getText("IGUI_CC_CatNoun")
    end
    HaloTextHelper.addGoodText(player, getText("IGUI_CC_NightGift", name, preyName(args and args.item)))
end

---Shows the night gift halo when the server sends it.
---@param module string
---@param command string
---@param args table|nil
local function onServerCommand(module, command, args)
    if module ~= MODULE or command ~= "nightgift" then return end
    CD.CatNightGiftNotify(args, getPlayer())
end

CD.evAdd(Events.OnServerCommand, onServerCommand, "cat.nightgift")

local wasAsleep = {}
local pendingGift = {}

---The player's closest cat in the world within radius tiles.
---@param player IsoPlayer|nil
---@param radius number tiles
---@return IsoAnimal|nil
---@nodiscard
local function nearestCat(player, radius)
    if not player or not CD.regCompanionsOf then return nil end
    local best, bestDist = nil, 9999
    local ownKeyed, ownNamed = CD.regCompanionsOf(player)
    for pass = 1, 2 do
        local lst = (pass == 1) and ownKeyed or ownNamed
        if lst then
            for i = 1, #lst do
                local a = lst[i]
                if a and CATS[CD.getBreed(a)] and a:isExistInTheWorld() then
                    local d = CD.dist2D(a, player)
                    if d <= radius and d < bestDist then
                        best, bestDist = a, d
                    end
                end
            end
        end
    end
    return best
end

---After the player wakes and SLEEP_FETCH_DELAY_MS passes, asks the server for the night gift if a cat is near.
---@param player IsoPlayer
local function onPlayerUpdate(player)
    if not player then return end
    local idx = player:getPlayerNum()
    local asleep = player:isAsleep()
    local prev = wasAsleep[idx]

    if prev and not asleep then
        pendingGift[idx] = getTimestampMs() + CD.SLEEP_FETCH_DELAY_MS
    end

    if pendingGift[idx] then
        if asleep then
            pendingGift[idx] = nil
        elseif getTimestampMs() >= pendingGift[idx] then
            pendingGift[idx] = nil
            local cat = nearestCat(player, CD.sleepNearRadius())
            if cat then
                CD.request("catgift", cat, {}, player)
            end
        end
    end

    wasAsleep[idx] = asleep
end

if isClient() or not isServer() then
    CD.evAdd(Events.OnPlayerUpdate, onPlayerUpdate, "cat.nightgift")
end
