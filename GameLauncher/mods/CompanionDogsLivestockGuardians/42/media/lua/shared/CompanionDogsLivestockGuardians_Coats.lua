local CD = CompanionDogs
if not (CD and (CD.API_VERSION or 0) >= 5) then return end

CompanionDogsLivestockGuardiansCoats = CompanionDogsLivestockGuardiansCoats or {}

local Coats = CompanionDogsLivestockGuardiansCoats

Coats.MOD_DATA_KEY = "CDLG_AnatolianCoat"
Coats.TEXTURES = {
    "AnatolianShepherd",
    "AnatolianShepherd_02",
}

local ANATOLIAN_TYPES = {
    anatolianpup = true,
    anatolianfemale = true,
    anatolianmale = true,
}

local SCAN_INTERVAL_TICKS = 30
local REPLACEMENT_CACHE_SCANS = 20
local scanTicks = 0
local scanNumber = 0
local recentCoatsByAnimalId = {}

local function animalType(animal)
    local value = nil
    pcall(function() value = animal:getAnimalType() end)
    return value
end

function Coats.isAnatolian(animal)
    return animal ~= nil and ANATOLIAN_TYPES[animalType(animal)] == true
end

function Coats.normalize(coat)
    for _, texture in ipairs(Coats.TEXTURES) do
        if coat == texture then return texture end
    end
    return nil
end

local function isAuthoritative()
    if isServer and isServer() then return true end
    return not (isClient and isClient())
end

local function animalId(animal)
    local value = nil
    pcall(function() value = animal:getAnimalID() end)
    value = tonumber(value)
    return value and value >= 0 and value or nil
end

local function currentCoat(animal)
    local value = nil
    pcall(function()
        local visual = animal:getAnimalVisual()
        if visual then value = visual:getSkinTexture() end
    end)
    return Coats.normalize(value)
end

local function storedCoat(animal)
    local value = nil
    pcall(function() value = animal:getModData()[Coats.MOD_DATA_KEY] end)
    return Coats.normalize(value)
end

local function remember(animal, coat)
    local id = animalId(animal)
    if not id or not coat then return end
    recentCoatsByAnimalId[id] = {
        coat = coat,
        expiresAfter = scanNumber + REPLACEMENT_CACHE_SCANS,
    }
end

local function rememberedCoat(animal)
    local id = animalId(animal)
    local entry = id and recentCoatsByAnimalId[id] or nil
    if entry and entry.expiresAfter >= scanNumber then return entry.coat end
    return nil
end

local function randomCoat()
    return Coats.TEXTURES[ZombRand(#Coats.TEXTURES) + 1]
end

local function motherCoat(animal)
    local mother = nil
    pcall(function() mother = animal:getMother() end)
    if not Coats.isAnatolian(mother) then return nil end

    local coat = storedCoat(mother) or rememberedCoat(mother) or currentCoat(mother)
    if coat then remember(mother, coat) end
    return coat
end

local function isFemaleAdult(animal)
    return animalType(animal) == "anatolianfemale"
end

function Coats.chooseAuthoritativeCoat(animal)
    local coat = storedCoat(animal)
    if coat then return coat end

    coat = rememberedCoat(animal)
    if coat then return coat end

    coat = motherCoat(animal)
    if coat then return coat end

    -- AnimalDefinitions natively randomizes the comma-separated female list.
    -- Preserve that choice; males and motherless pups need an explicit roll.
    if isFemaleAdult(animal) then
        coat = currentCoat(animal)
        if coat then return coat end
    end

    return randomCoat()
end

local function storeAuthoritativeCoat(animal, coat)
    local changed = false
    pcall(function()
        local modData = animal:getModData()
        if modData[Coats.MOD_DATA_KEY] ~= coat then
            modData[Coats.MOD_DATA_KEY] = coat
            changed = true
        end
    end)
    if changed and isServer and isServer() then
        pcall(function() animal:transmitModData() end)
    end
end

local function applyCoat(animal, coat)
    if not coat then return false end

    local changed = false
    pcall(function()
        if animal:isDead() then return end
        local visual = animal:getAnimalVisual()
        if visual and visual:getSkinTexture() ~= coat then
            visual:setSkinTextureName(coat)
            animal:resetModel()
            animal:resetModelNextFrame()
            changed = true
        end
    end)
    return changed
end

function Coats.reconcile(animal)
    if not Coats.isAnatolian(animal) then return nil end

    local coat = storedCoat(animal)
    if not coat then
        if isAuthoritative() then
            coat = Coats.chooseAuthoritativeCoat(animal)
            storeAuthoritativeCoat(animal, coat)
        else
            -- This briefly preserves the coat through a native stage actor
            -- replacement while the server's ModData update is in flight.
            coat = rememberedCoat(animal)
        end
    end

    if coat then
        remember(animal, coat)
        applyCoat(animal, coat)
    end
    return coat
end

local function pruneReplacementCache()
    for id, entry in pairs(recentCoatsByAnimalId) do
        if entry.expiresAfter < scanNumber then recentCoatsByAnimalId[id] = nil end
    end
end

function Coats.reconcileLoadedAnimals()
    local cell = getCell and getCell() or nil
    local animals = cell and cell:getAnimals() or nil
    if not animals then return end

    scanNumber = scanNumber + 1
    for index = 0, animals:size() - 1 do
        Coats.reconcile(animals:get(index))
    end
    pruneReplacementCache()
end

local function onTick()
    scanTicks = scanTicks + 1
    if scanTicks < SCAN_INTERVAL_TICKS then return end
    scanTicks = 0
    Coats.reconcileLoadedAnimals()
end

if Events and Events.OnGameStart then Events.OnGameStart.Add(Coats.reconcileLoadedAnimals) end
if Events and Events.OnTick then Events.OnTick.Add(onTick) end
