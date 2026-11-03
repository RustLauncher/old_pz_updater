CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.BuildingClasses = {}
CD.BuildingClassOrder = {}
---@param name string
---@param matchFn fun(def: BuildingDef): boolean
---@param opts table|nil { exclusive?: boolean, skipUrbanGate?: boolean }
function CD.registerBuildingClass(name, matchFn, opts)
    if not name or type(matchFn) ~= "function" or CD.BuildingClasses[name] then return end
    opts = opts or {}
    CD.BuildingClasses[name] = {
        match = matchFn,
        exclusive = opts.exclusive == true,
        skipUrbanGate = opts.skipUrbanGate == true,
    }
    CD.BuildingClassOrder[#CD.BuildingClassOrder + 1] = name
end

CD.StraySpawnDefs = {}
---@param list table[] each entry { id, class, chance = fun(): number, breed?, suffix?, gate?, indoor? }
function CD.registerStraySpawns(list)
    if type(list) ~= "table" then return end
    for _, sdef in ipairs(list) do
        if sdef.id and sdef.class and type(sdef.chance) == "function" then
            CD.StraySpawnDefs[#CD.StraySpawnDefs + 1] = sdef
        end
    end
end

CD.registerStraySpawns({
    { id = "caramelo", class = "house",  chance = CD.strayChancePerHouse,                                    indoor = 35 },
    { id = "golden",   class = "house",  chance = CD.goldenStrayChance,    suffix = "|g",  breed = "retriever", indoor = 35 },
    { id = "gs",       class = "police", chance = CD.policeShepherdChance, breed = "germanshepherd",         indoor = 15 },
    { id = "gshouse",  class = "house",  chance = CD.rareHouseChance,      suffix = "|gh", breed = "germanshepherd", indoor = 35 },
    { id = "huskyw",   class = "house",  chance = CD.huskyStrayChance,     suffix = "|h",  breed = "husky", gate = CD.isWinter, indoor = 35 },
    { id = "huskypv",  class = "petvet", chance = CD.huskyPetVetChance,    suffix = "|hv", breed = "husky",  indoor = 85 },
    { id = "huskyh",   class = "house",  chance = CD.huskyHouseChance,     suffix = "|hh", breed = "husky",  indoor = 35 },
    { id = "bcfarm",   class = "farm",   chance = CD.farmBorderChance,     suffix = "|bc", breed = "bordercollie", indoor = 70 },
    { id = "bchouse",  class = "house",  chance = CD.rareHouseChance,      suffix = "|bh", breed = "bordercollie", indoor = 35 },
})

local function checkUrban(sq)
    local zt = sq:getZoneType()
    if zt == "TownZone" or zt == "TownZones" or zt == "TrailerPark" then return true end
    local sz = sq:getSquareZombiesType()
    if sz ~= nil and sz ~= "" and sz ~= "Forest" and sz ~= "DeepForest" then return true end
    local lz = sq:getLootZone()
    if lz ~= nil and lz ~= "" then return true end
    local rg = sq:getSquareRegion()
    if rg ~= nil and rg ~= "" and rg ~= "General" then return true end
    return false
end

---Town or trailer park zone, a zombie type other than forest, a loot zone or a named region.
---@param sq IsoGridSquare|nil
---@return boolean
---@nodiscard
function CD.isUrbanSquare(sq)
    if not sq then return false end
    return checkUrban(sq)
end
