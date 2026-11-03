local CD = CompanionDogs
if not (CD and (CD.API_VERSION or 0) >= 5
    and type(CD.registerStraySpawns) == "function"
    and type(CD.StraySpawnDefs) == "table") then return end

CompanionDogsLivestockGuardians = CompanionDogsLivestockGuardians or {}
local LG = CompanionDogsLivestockGuardians

LG.FARM_POOL_NAME = "bordercollie-farm"
LG.FARM_POOL_SENTINEL = "__cdlg_bordercollie_farm_pool__"
LG.FarmSpawnBreeds = LG.FarmSpawnBreeds or {}
LG.FarmSpawnBreeds.bordercollie = true
LG.FarmSpawnBreeds.anatolianshepherd = true
LG.FarmSpawnBreeds.greaterswissmountaindog = true

local function addFarmBreed(breedKey)
    if type(breedKey) == "string" and breedKey ~= ""
        and breedKey ~= LG.FARM_POOL_SENTINEL then
        LG.FarmSpawnBreeds[breedKey] = true
    end
end

function LG.registerFarmSpawnBreed(breedKey)
    addFarmBreed(breedKey)
end

local function explicitlySharesFarmPool(sdef)
    local pool = sdef.sharedPool or sdef.sharedWith
    return pool == LG.FARM_POOL_NAME or pool == "bcfarm"
end

local function exactlyMatchesBorderCollieFarm(sdef)
    return sdef.class == "farm"
        and sdef.chance == CD.farmBorderChance
        and sdef.suffix == "|bc"
        and sdef.indoor == 70
end

local function sharesFarmPool(sdef)
    if type(sdef) ~= "table" then return false end
    return sdef.id == "bcfarm"
        or explicitlySharesFarmPool(sdef)
        or exactlyMatchesBorderCollieFarm(sdef)
end

function LG.refreshFarmSpawnPool()
    local defs = CD.StraySpawnDefs
    if type(defs) ~= "table" then return false end

    local canonical
    for i = 1, #defs do
        if defs[i].id == "bcfarm" then
            canonical = defs[i]
            break
        end
    end
    if not canonical then
        for i = 1, #defs do
            if sharesFarmPool(defs[i]) then
                canonical = defs[i]
                break
            end
        end
    end
    if not canonical then return false end

    for i = #defs, 1, -1 do
        local sdef = defs[i]
        if sharesFarmPool(sdef) then
            addFarmBreed(sdef.breed)
            if sdef ~= canonical then table.remove(defs, i) end
        end
    end
    canonical.breed = LG.FARM_POOL_SENTINEL
    return true
end

function LG.getFarmSpawnPool()
    local pool = {}
    for breedKey in pairs(LG.FarmSpawnBreeds) do
        if type(CD.BREEDS) ~= "table" or CD.BREEDS[breedKey] then
            pool[#pool + 1] = breedKey
        end
    end
    table.sort(pool)
    return pool
end

function LG.chooseFarmSpawnBreed()
    local pool = LG.getFarmSpawnPool()
    if #pool == 0 then return "bordercollie" end
    return pool[ZombRand(0, #pool) + 1]
end

if CD.registerStraySpawns ~= LG._wrappedRegisterStraySpawns then
    local previousRegisterStraySpawns = CD.registerStraySpawns
    LG._previousRegisterStraySpawns = previousRegisterStraySpawns
    LG._wrappedRegisterStraySpawns = function(list)
        previousRegisterStraySpawns(list)
        LG.refreshFarmSpawnPool()
    end
    CD.registerStraySpawns = LG._wrappedRegisterStraySpawns
end
LG.refreshFarmSpawnPool()

function LG.installFarmSpawnSelector()
    if type(CD.makeStrayKind) ~= "function" then return false end
    if CD.makeStrayKind == LG._wrappedMakeStrayKind then return true end

    local previousMakeStrayKind = CD.makeStrayKind
    LG._previousMakeStrayKind = previousMakeStrayKind
    LG._wrappedMakeStrayKind = function(breedKey)
        if breedKey == LG.FARM_POOL_SENTINEL then
            breedKey = LG.chooseFarmSpawnBreed()
        end
        return previousMakeStrayKind(breedKey)
    end
    CD.makeStrayKind = LG._wrappedMakeStrayKind
    return true
end

local function installFarmPool()
    LG.refreshFarmSpawnPool()
    LG.installFarmSpawnSelector()
end

if Events and Events.OnGameBoot then Events.OnGameBoot.Add(installFarmPool) end
if Events and Events.OnInitGlobalModData then
    Events.OnInitGlobalModData.Add(installFarmPool)
end
