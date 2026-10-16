--[[ ====================================================================
  Restores a moved B42 crafting station to a functional entity.

  A B42 station's function lives in game-entity components on the IsoObject
  (CraftBench/CraftRecipe/UiConfig/...) or, for the butcher hook, in a
  swapped-in IsoButcherHook Java class. Vanilla's moveable round-trip carries
  those components across pickup->placement via GameEntityFactory.TransferComponents
  (ISMoveableSpriteProps.lua:1280 at pickup, :2376 at placement) - but that
  helper refuses multi-square objects (GameEntityFactory.java:31-42), and on
  builds before the :1280 call existed it carried nothing at all. Either way a
  station can arrive back on the ground stripped of its entity: function gone,
  and EvolvedRecipe.getResultItem NPEs on the missing CraftBench.

  This module is the repair. It is deliberately VERSION-AGNOSTIC: it keys off
  the observed result of the placement, never off the build number. After
  vanilla places the object we ask one question - did it come back alive? - and
  rebuild only if not. Where vanilla's own transfer already restored the entity
  (42.20 single-square) the check passes and we touch nothing; everywhere else
  (older builds, every multi-square cell, the class-swap hook) the same repair
  fires. The build that varies is exactly the build we don't need to name.

  The rebuild is uniform per object, which is what lets multi-square work with
  no grid logic here: vanilla calls placeMoveableInternal once per grid cell
  (ISMoveableSpriteProps.lua:1871), so each cell reaches us as its own bare
  object, and GameEntityFactory.CreateIsoObjectEntity -> instanceComponents
  splits master vs slave per object off its SpriteConfig
  (GameEntityFactory.java:204-227). We drive that call the same way vanilla's
  own build path does (ISBuildIsoEntity.lua:677).

  Function never depends on live state or on the multi-square split landing:
  CreateIsoObjectEntity always yields at least a functional-but-fresh station.
  Live state (fuel/heat/mid-craft/contents) rides along only where vanilla's
  component transfer carried it - single-square. That is honest and the same on
  every build.

  Pure functions, no event wiring - NMW_Serializer drives these at the placement
  wrap point. pcall everything: a getter a future patch renames must degrade the
  station to "not repaired" (fail-closed, the guard/self-test refuse it), never
  throw inside a timed action.
==================================================================== ]]

require "NicksMoveableWorkstations/NMW_Sprites"

NicksMoveableWorkstations = NicksMoveableWorkstations or {}
local NMW = NicksMoveableWorkstations
NMW.SCHEMA = NMW.SCHEMA or 1
NMW.reconstruct = NMW.reconstruct or {}
local R = NMW.reconstruct

local function log(msg) print("[NicksMoveableWorkstations/Reconstruct] " .. tostring(msg)) end

-- sprite name -> station record, built once from the generated roster.
local stationForSprite = {}
do
    local stations = NMW.stations or {}
    for i = 1, #stations do
        local sprites = stations[i].sprites
        for j = 1, #sprites do
            stationForSprite[sprites[j]] = stations[i]
        end
    end
end

function R.stationForSprite(name)
    return name and stationForSprite[name] or nil
end

-- GameEntityScript for a station, resolved by its entity name and cached.
-- getScript accepts the bare name in vanilla's own entity roster; the
-- Base-qualified form is a fallback for a module-scoped lookup. A nil here is
-- the fail-closed signal - the station cannot be rebuilt and stays refused.
local scriptCache = {}
function R.resolveScript(station)
    if not station or not station.entity then return nil end
    local cached = scriptCache[station.entity]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local ok, script = pcall(function()
        local sm = getScriptManager()
        local s = sm:getGameEntityScript(station.entity)
        if not s then s = sm:getGameEntityScript("Base." .. station.entity) end
        return s
    end)
    if not ok or not script then
        scriptCache[station.entity] = false
        return nil
    end
    scriptCache[station.entity] = script
    return script
end

-- Whether a placed object still needs repair. class-swap wants its Java class
-- back (components alone don't restore the hook's behaviour); everything else
-- wants its entity components. hasComponents()==false is the unambiguous "came
-- back dead" tell - TransferComponents moves all-or-nothing, so a half-built
-- object doesn't occur.
function R.needsRebuild(obj, station)
    if not obj or not station then return false end
    if station.kind == "class-swap" then
        local cls = station.classSwap
        if not cls then return false end
        local ok, is = pcall(function() return instanceof(obj, cls) end)
        return ok and not is
    end
    local ok, has = pcall(function() return obj:hasComponents() end)
    if not ok then return false end
    return not has
end

-- Mirror BuildRecipeCode.butcheringHook.OnCreate / MOButcherHook.ReplaceExistingObject
-- (buildRecipeCode.lua:442, MOButcherHook.lua:3): mint the Java class on the
-- square, add it, tear the placeholder down. IsoButcherHook.new(sq) hardcodes
-- the sprite (crafted_04_120) and self-registers with the cell process list
-- (IsoButcherHook.java:37-41). Returns the new object so the caller can retrust it.
local function classSwapRebuild(obj, station)
    local ok, result = pcall(function()
        local sq = obj:getSquare()
        if not sq then return nil end
        local swapped = IsoButcherHook.new(sq)
        sq:AddTileObject(swapped)
        -- placeholder removal, transmitted so clients drop it too
        sq:transmitRemoveItemFromSquare(obj)
        obj:removeFromWorld()
        obj:removeFromSquare()
        obj:setSquare(nil)
        if isServer() then swapped:transmitCompleteItemToClients() end
        return swapped
    end)
    if not ok or not result then
        log("class-swap rebuild failed for " .. tostring(station.name))
        return obj
    end
    return result
end

-- Rebuild entity components in place from the station's own GameEntityScript,
-- exactly as vanilla's build path does (ISBuildIsoEntity.lua:677). isFirstTime
-- is false: this is a re-placement, not a first construction, so we must not
-- re-run onFirstCreation. The object is already on its square (post
-- AddSpecialObject), which is what a multi-square cell needs to see its
-- neighbours. Re-transmit because vanilla already transmitted the bare object.
local function genericRebuild(obj, station)
    local script = R.resolveScript(station)
    if not script then
        log("no GameEntityScript for " .. tostring(station.name) .. " (" .. tostring(station.entity) .. ")")
        return obj
    end
    local ok = pcall(function()
        GameEntityFactory.CreateIsoObjectEntity(obj, script, false)
        if isServer() then obj:transmitCompleteItemToClients() end
    end)
    if not ok then
        log("component rebuild failed for " .. tostring(station.name))
    end
    return obj
end

-- Stamp a reconstructed object as ours, carrying the schema it was written
-- under - an audit marker for "did we rebuild this", nothing keys off it.
local function stamp(obj)
    pcall(function()
        local md = obj:getModData()
        md.NMW_reconstructed = true
        md.NMW_schema = NMW.SCHEMA
    end)
end

-- The one entry point: given a freshly placed object and the station its sprite
-- belongs to, guarantee it is a functional station. Returns the functional
-- object, which for a class-swap is a NEW object (the placeholder is gone).
function R.repair(obj, station)
    if not obj or not station then return obj end
    if not R.needsRebuild(obj, station) then return obj end

    local result
    if station.kind == "class-swap" then
        result = classSwapRebuild(obj, station)
    else
        result = genericRebuild(obj, station)
    end
    stamp(result)
    return result
end

log("loaded")
