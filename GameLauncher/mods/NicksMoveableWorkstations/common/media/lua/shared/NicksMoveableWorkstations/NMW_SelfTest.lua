--[[ ====================================================================
  The fail-closed gate: a station is moveable this build only if its
  reconstruction path still works this build.

  A B42 crafting station is a GameEntity, and NMW_Reconstruct rebuilds it after
  a move by exactly two moves: resolve the station's GameEntityScript and drive
  GameEntityFactory.CreateIsoObjectEntity over it (generic/multisquare), or mint
  the swapped Java class (class-swap). Both hinge on names a future B42 patch is
  free to rename or restructure - the entity's script name, the components that
  script declares, the Java class. When one of those moves out from under us the
  reconstruction produces a bare, dead station, and a dead station is a
  save-corrupting bug where a refused pick-up is only an annoyance.

  So before any pick-up is offered, this module asks - per station, on the
  running build - "can I still rebuild you?" and narrows the moveable set to the
  ones that answer yes. It is deliberately a capability probe, not a live
  spawn-and-destroy harness (that was considered and dropped, phase-0 report):
  it queries the same script/class the reconstruction will use, at boot, touching
  nothing in the world, so it can never itself corrupt a save.

  What it proves, keyed off the observed build, never off the build number:
  - all of the station's sprites still carry IsMoveAble (the patch merged);
  - generic/multisquare: getGameEntityScript resolves the entity AND the script
    still declares a crafting component (CraftBench, or CraftRecipe for the
    uiEnabled=false cooking pits and the bandsaw's CraftBench-only case) - which
    is precisely the component set instanceComponents will rebuild
    (GameEntityFactory.java:204-227);
  - class-swap: the swapped Java class is still exposed to Lua.

  It does NOT test multi-square shape completeness - that is a per-pick-up
  property of the world, and NMW_PickupGuard.describesWholeObject already gates
  it at the moment of the click (isMultiSquareFullyLoaded). The two divide
  cleanly: this module answers "is the machinery present," the guard answers
  "is this particular object whole."

  The generator's `moveable` flag is the design intent - the permanent
  exclusions (Advanced-Forge parts, Charcoal Pit) live there and are never even
  probed. This module narrows that candidate set further by build. The guard
  consumes the combined verdict through spriteMoveable(), at call time, and
  falls back to the static flag if this module somehow did not load.

  Erring strict: any probe that cannot positively confirm the capability fails
  the station closed. A wrongly-disabled station is a visible annoyance the
  [IMPORTANT] log names; a wrongly-enabled one breaks a save.
==================================================================== ]]

require "NicksMoveableWorkstations/NMW_Sprites"
require "NicksMoveableWorkstations/NMW_Reconstruct"

NicksMoveableWorkstations = NicksMoveableWorkstations or {}
local NMW = NicksMoveableWorkstations
NMW.selftest = NMW.selftest or {}
local ST = NMW.selftest

ST.ran = false
ST.results = ST.results or {}   -- station record (table identity) -> boolean

local function log(msg) print("[NicksMoveableWorkstations/SelfTest] " .. tostring(msg)) end
local function important(msg) print("[NicksMoveableWorkstations/SelfTest] [IMPORTANT] " .. tostring(msg)) end

-- Same unchecked getSprite path NMW_Core uses: a patch-renamed sprite arrives
-- propertyless and reads as unpatched, which is what we want.
local function isPatched(name)
    local ok, sprite = pcall(function() return IsoSpriteManager.instance:getSprite(name) end)
    if not ok or not sprite then return false end
    local ok2, has = pcall(function() return sprite:getProperties():has("IsMoveAble") end)
    return ok2 and has == true
end

-- A functional crafting entity's script declares CraftBench (most of the roster)
-- or CraftRecipe (the uiEnabled=false cooking pits carry no CraftBench; the
-- bandsaw carries CraftBench but no CraftRecipe). Requiring either catches a
-- patch that strips a station's crafting definition while leaving the sprite.
local function scriptDeclaresFunction(script)
    local wanted = { "CraftBench", "CraftRecipe" }
    for i = 1, #wanted do
        local ok, has = pcall(function()
            return script:containsComponent(ComponentType[wanted[i]])
        end)
        if ok and has then return true end
    end
    return false
end

-- Returns moveable(bool), reason(string on failure). Only called for candidate
-- stations (generator moveable == true).
local function testStation(station)
    local sprites = station.sprites or {}
    for i = 1, #sprites do
        if not isPatched(sprites[i]) then
            return false, "sprite " .. tostring(sprites[i]) .. " not patched"
        end
    end

    if station.kind == "class-swap" then
        local cls = station.classSwap
        if not cls then return false, "no classSwap named" end
        local ok, present = pcall(function() return _G[cls] ~= nil end)
        if not ok or not present then
            return false, "Java class " .. tostring(cls) .. " not exposed"
        end
        return true
    end

    local script = NMW.reconstruct.resolveScript(station)
    if not script then
        return false, "no GameEntityScript for entity " .. tostring(station.entity)
    end
    if not scriptDeclaresFunction(script) then
        return false, "entity " .. tostring(station.entity) .. " declares no CraftBench/CraftRecipe"
    end
    return true
end

local function run()
    local stations = NMW.stations
    if not stations then
        important("NMW_Sprites.lua did not load - no self-test run, guard falls back to static allowlist")
        return
    end

    local candidates, passed = 0, 0
    for i = 1, #stations do
        local station = stations[i]
        if station.moveable ~= true then
            ST.results[station] = false   -- permanent generator exclusion, not a failure
        else
            candidates = candidates + 1
            local ok, reason = false, nil
            local pcOk, r1, r2 = pcall(testStation, station)
            if pcOk then ok, reason = r1, r2 end
            ST.results[station] = ok == true
            if ok == true then
                passed = passed + 1
            else
                important("station '" .. tostring(station.name) .. "' failed round-trip self-test: "
                    .. tostring(reason or "probe threw") .. " - held non-moveable this build")
            end
        end
    end

    ST.ran = true
    log("allowlist: " .. tostring(passed) .. "/" .. tostring(candidates) .. " candidate stations moveable this build")
end

-- station -> verdict, combining generator intent and the build probe. Before the
-- self-test has run (no pick-up is possible that early anyway) it defers to the
-- generator flag, so behaviour matches the pre-self-test guard.
function ST.stationOk(station)
    if not station then return false end
    if station.moveable ~= true then return false end
    if not ST.ran then return true end
    return ST.results[station] == true
end

-- The guard's entry point: sprite name -> may this be picked up. A sprite that
-- is not one of ours is not our business (the wrap is global); allow it.
function ST.spriteMoveable(name)
    if name == nil then return true end
    local station = NMW.reconstruct.stationForSprite(name)
    if not station then return true end
    return ST.stationOk(station)
end

-- Same pair NMW_Core verifies on: the attestation that tile definitions and
-- entity scripts are loaded by then. Both VMs of a co-op game run their own
-- probe against their own build.
Events.OnGameStart.Add(run)
Events.OnServerStarted.Add(run)

log("loaded")
