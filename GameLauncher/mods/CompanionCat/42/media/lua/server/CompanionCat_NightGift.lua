local CD = CompanionDogs
if not (CD and CD.dogRegNow and (CD.API_VERSION or 0) >= 5) then return end
if not (CompanionCat and CompanionCat.COAT_KEYS) then return end

local CATS = CompanionCat.COAT_KEYS

local CHANCE_MIN_PM = 350
local CHANCE_MAX_PM = 1000
local GIFT_XP = 4
local GIFT_COOLDOWN_MIN = 1440

local PREY = {
    { "Base.Worm",           8,      1 },
    { "Base.Cricket",       10,      2 },
    { "Base.Grasshopper",   10,      2 },
    { "Base.Cockroach",     10,      2 },
    { "Base.Centipede",      8,      5 },
    { "Base.Snail",          5,      5 },
    { "Base.Slug",           5,      5 },
    { "Base.Frog",           2,      8 },
    { "Base.DeadMouse",      5,     14 },
    { "Base.DeadRat",        3,     12 },
}

---Draw weight of a prey row at this hunt level, linear from its level 0 weight to its max level weight, times 10.
---@param p table prey row: full type, weight at level 0, weight at max level
---@param lvl integer hunt skill level
---@return integer
---@nodiscard
local function weightAt(p, lvl)
    local max = CD.SKILL_MAX_LEVEL
    if lvl > max then lvl = max elseif lvl < 0 then lvl = 0 end
    return math.floor((p[2] * (max - lvl) + p[3] * lvl) * 10 / max)
end

---Weighted random prey for this hunt level.
---@param lvl integer hunt skill level
---@return string fullType
---@nodiscard
local function pickPrey(lvl)
    local total = 0
    for i = 1, #PREY do total = total + weightAt(PREY[i], lvl) end
    if total <= 0 then return PREY[1][1] end
    local r = ZombRand(total)
    for i = 1, #PREY do
        r = r - weightAt(PREY[i], lvl)
        if r < 0 then return PREY[i][1] end
    end
    return PREY[1][1]
end

---The player's closest owned cat in the world within radius tiles.
---@param player IsoPlayer|nil
---@param radius number tiles
---@return IsoAnimal|nil
---@nodiscard
local function nearestCat(player, radius)
    if not player then return nil end
    local best, bestDist = nil, 9999
    local comps = CD.dogRegNow().companions
    for i = 1, #comps do
        local a = comps[i]
        if a and CATS[CD.getBreed(a)] and a:isExistInTheWorld() and CD.isOwnedBy(a, player) then
            local d = CD.dist2D(a, player)
            if d <= radius and d < bestDist then
                best, bestDist = a, d
            end
        end
    end
    return best
end

---A live cat in the world that is loyal, healthy, fed, watered and below its panic stress.
---@param cat IsoAnimal|nil
---@return boolean
---@nodiscard
local function eligible(cat)
    if not cat or cat:isDead() or not cat:isExistInTheWorld() then return false end
    if not CATS[CD.getBreed(cat)] then return false end
    if CD.isDisloyal(cat) or CD.isSick(cat) then return false end
    if cat:getHunger() >= CD.MOODLE_NEGLECT_MAX then return false end
    if cat:getThirst() >= CD.MOODLE_NEGLECT_MAX then return false end
    if CD.getStress(cat) >= CD.breedPanicThreshold(cat) then return false end
    return true
end

---Tells the owner about the gift: a server command in multiplayer, the halo directly in single player.
---@param owner IsoPlayer
---@param cat IsoAnimal
---@param itemType string full type of the prey
local function notify(owner, cat, itemType)
    local args = { item = itemType, name = CD.data(cat).name }
    if isServer() then
        sendServerCommand(owner, "CompanionCat", "nightgift", args)
    elseif CD.CatNightGiftNotify then
        CD.CatNightGiftNotify(args, owner)
    end
end

---Drops a random prey at the owner's feet, gives the cat hunt XP and notifies the owner.
---@param cat IsoAnimal
---@param owner IsoPlayer
---@param lvl integer hunt skill level
---@return boolean placed false when the owner has no square or the item could not be created
local function deliver(cat, owner, lvl)
    local sq = owner:getCurrentSquare()
    if not sq then return false end
    local itemType = pickPrey(lvl)
    if not sq:AddWorldInventoryItem(itemType, 0.5, 0.5, 0.0) then return false end
    CD.addSkillXP(cat, "hunt", GIFT_XP)
    notify(owner, cat, itemType)
    if CD.DEBUG_ALL then
        CD.log("[CD-CAT] presente noturno: " .. itemType)
    end
    return true
end

-- media/lua/server/ tambem carrega no CLIENTE de MP; sem o gate sai um item fantasma local.
if not isClient() then
    CD.Server = CD.Server or {}
    ---Rolls the night gift of the owned cat sleeping near the player, once per cooldown.
    ---@param player IsoPlayer
    CD.Server.catgift = function(player)
        if not player then return end
        local cat = nearestCat(player, CD.sleepNearRadius())
        if not cat or not eligible(cat) then return end

        local pd = CD.playerData(player)
        local now = CD.worldMinutes()
        if pd.catGiftUntilMin and now < pd.catGiftUntilMin then return end
        pd.catGiftNight, pd.catGiftAt = nil, nil

        pd.catGiftUntilMin = now + GIFT_COOLDOWN_MIN
        player:transmitModData()

        local maxLvl = CD.SKILL_MAX_LEVEL
        local lvl = CD.getSkillLevel(cat, "hunt")
        if lvl > maxLvl then lvl = maxLvl elseif lvl < 0 then lvl = 0 end

        local chance = CHANCE_MIN_PM + math.floor((CHANCE_MAX_PM - CHANCE_MIN_PM) * lvl / maxLvl)
        if ZombRand(1000) >= chance then return end

        if not deliver(cat, player, lvl) then
            pd.catGiftUntilMin = nil
            player:transmitModData()
        end
    end
end
