if isClient() then return end

--[[ Trains -- crops in the cars (DESIGN.md 12; the author, 2026-10-11: "the
    garden car should be a green house with harvestable plants so people can
    do gardening").

    Runs in single player and on any server. A crop here is vanilla's own:
    a plant of its farming system (SFarmingSystem, SPlantGlobalObject), dug,
    sown and grown by the calls vanilla's own Lua makes, so that everything a
    player does to a crop anywhere they can do to one in a car: look at it,
    water it, cure it, pick it, dig its bed again and sow something else.
    This file is the three things vanilla does not do for a crop in a car:

      * **sowing one that is already grown** (G.sow), as vanilla does for the
        crops its map comes with (MOFarming.lua, NewPlant): dug, seeded, and
        grown a stage at a time with the water each stage wants, until there
        is something to pick. TRN_Build calls it for each bed of a greenhouse
        car as the room is raised;
      * **the greenhouse rule** (G.spare). Vanilla takes health from every
        crop that is indoors, a point each time it looks, unless the crop is
        a houseplant or its square is in a room the *map* names a greenhouse
        (SFarmingSystem.changeHealth, sandbox KillInsideCrops, on in every
        preset). A room of ours is no room of the map's, so every crop in
        every car would be dead in two days. What that rule took is given
        back, straight after vanilla's pass, for every crop on the ground the
        cars' insides stand on: **a crop in a car grows as in a greenhouse**,
        whoever sowed it and in whichever car;
      * **looking after the greenhouse car's own beds** (G.tend), where the
        sandbox's Garden says so: every ten minutes of the world's, each is
        watered to what it wants, cured, kept from failing, and a ripe crop
        is kept from going over. A crop is a thing of the farming system's,
        not of the square's, so this reaches a car nobody is in.

    **None of it has been seen in the game.** What is read is vanilla's Lua,
    on the build named in DEV_GUIDE.md; what a crop under a roof three
    storeys up is to the engine (`isOutside`), and whether erosion grows
    anything on a bed's soil, are not.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Setup"
require "TRN/TRN_Clock"
require "TRN/TRN_Rooms"
require "Farming/SFarmingSystem"

TRN = TRN or {}
local C, U, K, R = TRN.Config, TRN.Util, TRN.Clock, TRN.Rooms

local G = {}
TRN.Garden = G

G.stats = { sown = 0, spared = 0, tended = 0, passes = 0 }
G.hooked = false

--- Vanilla's farming, or nil where there is none (it is the server's: a
--- client of a server has only a mirror).
local function system()
    return U.try("garden.system", function()
        return SFarmingSystem and SFarmingSystem.instance or nil
    end)
end

--- True once vanilla's farming is there to sow in.
function G.ready()
    return system() ~= nil
end

--- What vanilla knows of a crop by the name it is sown by, or nil.
local function propsOf(seed)
    return U.try("garden.props", function()
        return farming_vegetableconf and farming_vegetableconf.props and farming_vegetableconf.props[seed] or nil
    end)
end

--- The water a crop wants now: what it needs, and no more than it can take.
local function wanted(plant)
    local need = plant.waterNeeded or 0
    local most = plant.waterNeededMax or 100
    if most < need then most = need end
    return math.min(100, (need + most) / 2)
end

--- True for a crop that stands on the ground the cars' insides are on.
local function inACar(plant)
    return type(plant.x) == "number" and type(plant.y) == "number" and R.ground(plant.x, plant.y)
end

--- Every crop there is, as a list: vanilla's own count runs from 1.
local function crops(sys)
    local out = {}
    local n = U.try("garden.count", function() return sys:getLuaObjectCount() end) or 0
    for i = 1, n do
        local plant = U.try("garden.at", function() return sys:getLuaObjectByIndex(i) end)
        if plant then out[#out + 1] = plant end
    end
    return out
end

---------------------------------------------------------------------------
-- Sowing
---------------------------------------------------------------------------
--- A crop of vanilla's on a square, dug and sown and grown: "ripe" until
--- there is something to pick, anything else `C.Garden.young` stages.
--- Returns true when it stands. Never where a furrow already is: that one
--- is somebody's.
function G.sow(sq, seed, stage)
    local sys = system()
    if not sys or not sq then return false end
    local prop = propsOf(seed)
    if not prop then
        U.warnOnce("garden.seed:" .. tostring(seed), "the game's farming has no crop called '%s': a bed is left bare",
                   tostring(seed))
        return false
    end
    local done = U.try("garden.sow", function()
        if sys:getLuaObjectOnSquare(sq) then return false end
        sys:plow(sq)
        local plant = sys:getLuaObjectOnSquare(sq)
        if not plant then error("the furrow was not dug") end
        plant.exterior = false
        plant:seed(seed, 0)
        -- Sown out of its season a crop is marked to fail (SPlantGlobalObject.seed, `cursed`).
        -- Under glass there is no season.
        plant.cursed = false
        plant.health = C.Garden.health
        local steps = (stage == "ripe") and C.Garden.most or (C.Garden.young - 1)
        for _ = 1, steps do
            -- A stage past full grown is a crop gone over: never grown that far.
            if plant.hasVegetable or (plant.nbOfGrow or 0) > (prop.fullGrown or 0) then break end
            plant.waterLvl = wanted(plant)
            sys:growPlant(plant, nil, true)
        end
        plant.waterLvl = wanted(plant)
        plant.lastWaterHour = sys.hoursElapsed or 0
        local sprite = farming_vegetableconf.getSpriteName(plant)
        if sprite then plant:setSpriteName(sprite) end
        plant:setObjectName(farming_vegetableconf.getObjectName(plant))
        plant:saveData()
        return true
    end) == true
    if done then G.stats.sown = G.stats.sown + 1 end
    return done
end

---------------------------------------------------------------------------
-- The greenhouse rule
---------------------------------------------------------------------------
--- Gives back what vanilla's rule against crops indoors has just taken from
--- every crop in a car, and the sun's share it withheld: exactly the two
--- lines of SFarmingSystem.changeHealth that ask whether a square is in a
--- greenhouse, answered yes. Returns how many crops.
function G.spare(sys)
    local kills = U.try("garden.kills", function()
        return getSandboxOptions():getOptionByName("KillInsideCrops"):getValue() == true
    end)
    if kills ~= true then return 0 end
    local sunny = U.try("garden.weather", function() return getWorld():getWeather() == "sunny" end) == true
    local n = 0
    for _, plant in ipairs(crops(sys)) do
        local prop = propsOf(plant.typeOfSeed)
        if inACar(plant) and plant.state ~= "plow" and plant.exterior ~= true and not (prop and prop.isHouseplant)
           and U.try("garden.alive", function() return plant:isAlive() end) == true then
            -- Vanilla's own multiplier, as it stands after its pass.
            local bad = 1
            if plant.cursed then bad = bad * 2 end
            if plant.hasWeeds then bad = bad * 2 end
            if type(plant.naturalLight) == "number" and plant.naturalLight > 0 then bad = bad / plant.naturalLight end
            plant.health = (plant.health or 0) + bad + (sunny and (0.25 / bad) or 0)
            n = n + 1
        end
    end
    G.stats.spared = G.stats.spared + n
    return n
end

--- Hangs the rule on vanilla's pass, once. True when it is hung.
function G.hook()
    if G.hooked then return true end
    local ok = U.try("garden.hook", function()
        if not SFarmingSystem or type(SFarmingSystem.changeHealth) ~= "function" then return false end
        local vanilla = SFarmingSystem.changeHealth
        SFarmingSystem.changeHealth = function(self, ...)
            vanilla(self, ...)
            U.try("garden.spare", function() G.spare(self) end)
        end
        return true
    end)
    if ok == true then
        G.hooked = true
        U.log("garden: a crop in a car grows as in a greenhouse (hung on the game's farming)")
    end
    return G.hooked
end

---------------------------------------------------------------------------
-- Looking after the greenhouse car's beds
---------------------------------------------------------------------------
--- Waters, cures and keeps every crop of a greenhouse car that is looked
--- after. Returns how many it did anything for.
function G.tend()
    G.hook()
    local sys = system()
    if not sys or not K.state or not K.state.gardens then return 0 end
    if TRN.Setup.garden() ~= "tended" then return 0 end
    G.stats.passes = G.stats.passes + 1
    local now = sys.hoursElapsed or 0
    local n = 0
    for _, plant in ipairs(crops(sys)) do
        if inACar(plant) and plant.state == "seeded"
           and U.try("garden.alive", function() return plant:isAlive() end) == true then
            local index, slot = R.slot(plant.x, plant.y)
            if index and K.state.gardens[index .. ":" .. slot] then
                local did = false
                if (plant.waterLvl or 0) < (plant.waterNeeded or 0) then
                    plant.waterLvl, plant.lastWaterHour, did = wanted(plant), now, true
                end
                for _, ill in ipairs({ "mildewLvl", "aphidLvl", "fliesLvl", "slugsLvl" }) do
                    if (plant[ill] or 0) > 0 then plant[ill], did = 0, true end
                end
                if (plant.health or 0) < C.Garden.keep then plant.health, did = C.Garden.keep, true end
                -- Past full grown the next stage is a crop gone over: put off, for as long as it is looked at.
                local prop = propsOf(plant.typeOfSeed)
                if prop and (plant.nbOfGrow or 0) > (prop.fullGrown or 0)
                   and (plant.nextGrowing or 0) - now < C.Garden.hold then
                    plant.nextGrowing, did = now + C.Garden.hold, true
                end
                if did then
                    U.try("garden.save", function() plant:saveData() end)
                    n = n + 1
                end
            end
        end
    end
    G.stats.tended = G.stats.tended + n
    return n
end

--- What this machine has done for the crops in the cars, for TRN_Status().
function G.status()
    local sys = system()
    local n = 0
    if sys then
        for _, plant in ipairs(crops(sys)) do
            if inACar(plant) then n = n + 1 end
        end
    end
    U.log("status: garden: %s; %d crop(s) in the cars now, %d sown by the mod, %d crop(s) spared the rule against "
          .. "crops indoors, %d looked after in %d pass(es); the sandbox's Garden: %s",
          G.hooked and "hung on the game's farming" or "NOT hung on the game's farming", n, G.stats.sown, G.stats.spared,
          G.stats.tended, G.stats.passes, TRN.Setup.garden())
end

G.hook()
Events.EveryTenMinutes.Add(function() U.try("garden.tend", G.tend) end)

return G
