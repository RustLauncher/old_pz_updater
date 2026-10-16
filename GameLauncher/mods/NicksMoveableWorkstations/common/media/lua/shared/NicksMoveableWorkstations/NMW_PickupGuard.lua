--[[ ====================================================================
  Refuses a pick-up the engine cannot complete.

  A B42 crafting station is a GameEntity, and its SpriteConfig - not the
  sprite grid - is what decides how much of the world a removal takes.
  IsoObjectUtils.isObjectMultiSquare reads getSpriteConfig():isValidMultiSquare()
  before it ever looks at a sprite grid (IsoObjectUtils.java:21-32), while
  ISMoveableSpriteProps.isMultiSprite reads only the grid
  (ISMoveableSpriteProps.lua:182). A sprite that is one tile of a larger
  entity is therefore multi-square to Java and single to Lua, and vanilla's
  completeness check, keyed off the Lua flag, never runs on it.

  Both failures land after the item is already in the player's inventory
  (ISMoveableSpriteProps.lua:1318; the removal is at :1402):

  - A lone tile - a forge part the mappers placed as scenery, with no
    neighbours - makes findAllMultiSquareObjects return false
    (SpriteConfig.java:219), safelyRemoveTileObjectFromSquare removes
    nothing, and the item is a duplicate.
  - A complete entity is removed whole, so lifting one tile off a forge
    deletes the forge and hands back a single part.

  The rule: a moveable may be taken only when it describes every square the
  engine will remove - either no multi-square entity at all, or a sprite grid
  with every tile of that entity present.

  On top of that, a fail-closed allowlist. A B42 station is a GameEntity whose
  function is dropped by vanilla's moveable round-trip; the Phase 2 framework
  rebuilds it on placement, and the Phase 3 boot self-test (NMW_SelfTest) proves
  that rebuild still works on the running build before any pick-up is offered. A
  station not on the allowlist is refused outright - a refused pick-up is an
  annoyance, a station that comes back dead is a save-corrupting bug. The
  allowlist has two layers: the generator's `NMW.stations[i].moveable` flag is
  the design intent (the Advanced-Forge parts and Charcoal Pit are held off it
  permanently), and NMW_SelfTest narrows that candidate set to the stations whose
  round-trip it could verify this build. This module reads the combined verdict
  through `NMW.selftest.spriteMoveable` at call time; if that module is absent it
  falls back to the static flag alone.

  And a Tier-2 gate: a station holding a separate linked entity is refused until
  it is emptied. The one case in the roster is the butcher hook with a carcass
  hung on it - a distinct IsoAnimal that re-links by the hook's coordinates, so
  moving the hook would strand it. Refused with the same three wraps, not a dead
  click.

  Scoped to this mod's own sprites. A wrap on ISMoveableSpriteProps is global,
  and every other moveable in the game is vanilla's business or another mod's.

  Three wraps, because refusing at one point alone leaves a hole: the cursor's
  candidate list so a refused object is never offered, canPickUpMoveable so a
  joypad or keybind route cannot reach it, and pickUpMoveable because that one
  is skipped entirely under _forceAllow or a movables cheat (:1166).

  Nothing here says *why* an object was refused. That would mean a new
  InfoPanelFlags entry and a patched getInfoPanelDescription.
==================================================================== ]]

require "NicksMoveableWorkstations/NMW_Sprites"

NicksMoveableWorkstations = NicksMoveableWorkstations or {}
local NMW = NicksMoveableWorkstations

local function log(msg) print("[NicksMoveableWorkstations/PickupGuard] " .. tostring(msg)) end

-- guarded: every sprite this mod touches, the scope of the completeness check
-- below. blocked: the sprites of stations the allowlist holds off (moveable ~=
-- true), refused outright. A sprite can be in both; blocked is the stricter gate.
local guarded, guardedCount = {}, 0
local blocked, blockedCount = {}, 0
do
    local stations = NMW.stations or {}
    for i = 1, #stations do
        local sprites = stations[i].sprites
        local allowed = stations[i].moveable == true
        for j = 1, #sprites do
            if not guarded[sprites[j]] then
                guarded[sprites[j]] = true
                guardedCount = guardedCount + 1
            end
            if not allowed and not blocked[sprites[j]] then
                blocked[sprites[j]] = true
                blockedCount = blockedCount + 1
            end
        end
    end
end

-- Fail-closed: a sprite is moveable only if its station clears the allowlist.
-- NMW_SelfTest owns the live verdict - the generator's `moveable` flag narrowed
-- by a boot-time round-trip probe against the running build - and we read it at
-- call time (a pick-up only happens deep into gameplay, long after the probe).
-- If that module did not load, fall back to the static generator exclusions in
-- `blocked`, i.e. the pre-self-test behaviour.
local function allowedToMove(moveProps)
    local name = moveProps and moveProps.spriteName
    if name == nil then return true end
    if NMW.selftest and NMW.selftest.spriteMoveable then
        return NMW.selftest.spriteMoveable(name)
    end
    return not blocked[name]
end

-- Tier-2 gate: a butcher hook carrying a hung carcass is refused. The carcass
-- is a separate IsoAnimal that re-links by the hook's old coordinates
-- (IsoButcherHook.java:227-231, IsoAnimal.reattachBackToHook:3650), so moving
-- the hook to a new square would orphan it. Vanilla empties a hook with
-- removeHook (dropping the carcass as a body); we ask the player to do that
-- first rather than move an occupied one.
local function occupied(object)
    if not object then return false end
    local ok, is = pcall(function() return instanceof(object, "IsoButcherHook") end)
    if not ok or not is then return false end
    local ok2, animal = pcall(function() return object:getAnimal() end)
    return ok2 and animal ~= nil
end

local function objectOnSquare(moveProps, square)
    local ok, object = pcall(function()
        return moveProps:findOnSquare(square, moveProps.spriteName)
    end)
    if not ok then return nil end
    return object
end

local function describesWholeObject(moveProps, object)
    local name = moveProps.spriteName
    if not object or name == nil or not guarded[name] then return true end

    local ok, config = pcall(function() return object:getSpriteConfig() end)
    if not ok then config = nil end
    if not config then return true end

    local okMulti, isMulti = pcall(function() return config:isValidMultiSquare() end)
    if not okMulti then isMulti = nil end
    if not isMulti then return true end

    if not moveProps.isMultiSprite then return false end

    local okWhole, isWhole = pcall(function() return config:isMultiSquareFullyLoaded() end)
    if not okWhole then isWhole = nil end
    return isWhole == true
end

local function install()
    local canPickUpMoveable = ISMoveableSpriteProps.canPickUpMoveable
    local pickUpMoveable = ISMoveableSpriteProps.pickUpMoveable

    -- Ahead of vanilla's cheat branch (:1080) on purpose. The cheat answers
    -- whether the player is allowed to take the object; this answers whether
    -- the engine can remove it, and granting the item either way duplicates it.
    function ISMoveableSpriteProps:canPickUpMoveable(character, square, object)
        if not allowedToMove(self) then return false end
        local obj = object or objectOnSquare(self, square)
        if occupied(obj) then return false end
        if not describesWholeObject(self, obj) then return false end
        return canPickUpMoveable(self, character, square, object)
    end

    -- canPickUpMoveable is advisory: pickUpMoveable skips it under _forceAllow
    -- or a movables cheat (:1166), and rotation arrives holding _forceAllow.
    function ISMoveableSpriteProps:pickUpMoveable(character, square, createItem, forceAllow)
        if not allowedToMove(self) then return false end
        local obj = objectOnSquare(self, square)
        if occupied(obj) then return false end
        if not describesWholeObject(self, obj) then return false end
        return pickUpMoveable(self, character, square, createItem, forceAllow)
    end
end

-- Without this the refusal is a dead mouse button: the cursor still lists the
-- object, draws its info panel and then drops the click. getObjectList feeds the
-- pickup cursor alone - scrap and repair build their own lists (:998, :1020) -
-- so filtering it hides a refused object from pick-up and nothing else.
--
-- ISMoveableCursor is under media/lua/server, which loads after every shared
-- file, so unlike the two wraps above this one cannot be done at file scope.
local cursorFiltered = false

local function installCursorFilter()
    if cursorFiltered then return end
    if not ISMoveableCursor or not ISMoveableCursor.getObjectList then
        log("ISMoveableCursor not loaded yet - cursor filter deferred")
        return
    end
    cursorFiltered = true

    local getObjectList = ISMoveableCursor.getObjectList

    function ISMoveableCursor:getObjectList()
        local objects = getObjectList(self)
        local kept = {}
        for i = 1, #objects do
            if allowedToMove(objects[i].moveProps)
                    and not occupied(objects[i].object)
                    and describesWholeObject(objects[i].moveProps, objects[i].object) then
                kept[#kept + 1] = objects[i]
            end
        end
        return kept
    end

    log("cursor filter installed")
end

if ISMoveableSpriteProps and ISMoveableSpriteProps.canPickUpMoveable
        and ISMoveableSpriteProps.pickUpMoveable then
    install()
    -- OnGameBoot fires before media/lua/server is loaded, so the cursor is not
    -- there yet; OnGameStart is the first event that can see it. Both are
    -- registered because neither is guaranteed to fire in every VM.
    Events.OnGameBoot.Add(installCursorFilter)
    Events.OnGameStart.Add(installCursorFilter)
    Events.OnServerStarted.Add(installCursorFilter)
    log("loaded, guarding " .. tostring(guardedCount) .. " sprites, "
        .. tostring(blockedCount) .. " held off the allowlist")
else
    log("ISMoveableSpriteProps not loaded - guard NOT installed")
end
