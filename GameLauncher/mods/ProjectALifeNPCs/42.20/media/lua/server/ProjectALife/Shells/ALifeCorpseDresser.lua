require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Shells/ALifeProfileHydrator"
require "ProjectALife/Records/ALifeLootRarity"
require "ProjectALife/Records/ALifeLootWear"
require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Dresser = {
    haul = { "Base.TinnedBeans", "Base.WaterBottle", "Base.Bandage" },
    profiles = {},
    metrics = { placed = 0, dressed = 0, failed = 0 },
}
ProjectALife.CorpseDresser = Dresser

function Dresser.plain(square, blood)
    if square == nil or type(createRandomDeadBody) ~= "function" then return nil end
    local ok, body = pcall(createRandomDeadBody, square, blood or 6)
    if not ok then return nil end
    if body == nil and type(square.getDeadBody) == "function" then body = square:getDeadBody() end
    if body ~= nil then Dresser.metrics.placed = Dresser.metrics.placed + 1 end
    return body
end

function Dresser.profilesOf(factionId)
    local catalog = ProjectALife.Catalog
    local current = catalog ~= nil and catalog.current or nil
    if Dresser.catalogRef ~= current then Dresser.profiles, Dresser.catalogRef = {}, current end
    local cached = Dresser.profiles[factionId]
    if cached ~= nil then return cached end
    local list = {}
    local npcs = type(current) == "table" and current.npcs or nil
    for id, profile in pairs(type(npcs) == "table" and npcs or {}) do
        local general = type(profile) == "table" and profile.general or nil
        if type(general) == "table" and general.faction == factionId then list[#list + 1] = id end
    end
    table.sort(list)
    Dresser.profiles[factionId] = list
    return list
end

function Dresser.profileFor(factionId)
    if factionId == nil then return nil end
    local list = Dresser.profilesOf(factionId)
    if #list == 0 then return nil end
    return list[ProjectALife.FeatureGate.roll(#list) + 1]
end

function Dresser.clearWorn(body)
    local worn, bag = body:getWornItems(), body:getContainer()
    if worn == nil or bag == nil then return nil, nil end
    for i = worn:size() - 1, 0, -1 do
        local entry = worn:get(i)
        local item = entry ~= nil and entry:getItem() or nil
        if item ~= nil then bag:Remove(item) end
    end
    worn:clear()
    return worn, bag
end

function Dresser.worn(item, fullType, seed, tag)
    local wear = ProjectALife.LootWear
    if type(wear) ~= "table" then return false end
    local strength = wear.strength()
    if strength <= 0 then return false end
    local kind = wear.kindOf(item, fullType, nil)
    if kind == nil then return false end
    local key = "dead:" .. tostring(seed) .. ":" .. tostring(tag) .. ":" .. tostring(fullType)
    wear.condition(item, kind, key, strength)
    if kind == "firearm" then wear.fill(item, kind, key, strength) end
    return true
end

function Dresser.wear(body, plan, seed)
    local worn, bag = Dresser.clearWorn(body)
    if worn == nil then return false end
    local hydrator = ProjectALife.ProfileHydrator
    local rarity = ProjectALife.LootRarity
    local drop = type(plan.drop) == "table" and plan.drop or {}
    for _, entry in ipairs(type(plan.clothing) == "table" and plan.clothing or {}) do
        local kind = type(entry) == "table" and entry.itemType or nil
        local tier = kind ~= nil and drop.class ~= nil and rarity.armorTier(kind) or nil
        local item = nil
        local banned = kind ~= nil and drop.class ~= nil and ProjectALife.DropPolicy.neverDrops(kind)
        if kind ~= nil and not banned and not (tier ~= nil and drop.rareDrop ~= true) then item = instanceItem(kind) end
        if item ~= nil then
            if drop.class ~= nil then
                rarity.degradeItem(item, rarity.conditionPercent(drop.class, seed, "corpse:" .. tostring(kind),
                    tier ~= nil), tier ~= nil)
                Dresser.worn(item, kind, seed, "cloth")
            end
            if type(hydrator.prepareClothing) == "function" then pcall(hydrator.prepareClothing, item, entry, seed) end
            local location = item:getBodyLocation()
            if location ~= nil and location ~= "" then
                bag:AddItem(item)
                worn:setItem(location, item)
            end
        end
    end
    body:setWornItems(worn)
    local weapons = type(plan.weapons) == "table" and plan.weapons or {}
    local weapon = weapons.primary or weapons.melee
    if weapon ~= nil and weapon ~= "Base.BareHands" then
        local item = instanceItem(weapon)
        if item ~= nil and drop.class ~= nil then
            rarity.degradeItem(item, rarity.conditionPercent(drop.class, seed, "corpse:weapon", false), false)
            Dresser.worn(item, weapon, seed, "weapon")
        end
        if item ~= nil then body:setPrimaryHandItem(item) end
    end
    local share = ProjectALife.DropPolicy.scales(false).supplies / 100
    for _, haul in ipairs(Dresser.haul) do
        if ProjectALife.FeatureGate.roll(2) == 0 and ProjectALife.FeatureGate.chance(share) then bag:AddItem(haul) end
    end
    return true
end

function Dresser.dress(body, factionId, seed, profileId)
    local hydrator = ProjectALife.ProfileHydrator
    profileId = profileId or Dresser.profileFor(factionId)
    if body == nil or hydrator == nil or type(hydrator.plan) ~= "function" or profileId == nil then return false, "no_profile" end
    local ok, plan = pcall(hydrator.plan, { uid = tostring(seed), profileId = profileId, factionId = factionId,
        memory = { identitySeed = seed } })
    if not ok or type(plan) ~= "table" then
        Dresser.metrics.failed = Dresser.metrics.failed + 1
        return false, "no_plan"
    end
    local dressed, result = pcall(Dresser.wear, body, plan, seed)
    if not dressed or result ~= true then
        Dresser.metrics.failed = Dresser.metrics.failed + 1
        return false, "dress_failed"
    end
    if type(body.resetModel) == "function" then body:resetModel() end
    if type(body.invalidateCorpse) == "function" then body:invalidateCorpse() end
    Dresser.metrics.dressed = Dresser.metrics.dressed + 1
    return true
end

function Dresser.blood(square, amount)
    if square == nil or type(addBloodSplat) ~= "function" then return false end
    return pcall(addBloodSplat, square, amount or 8)
end

return Dresser
