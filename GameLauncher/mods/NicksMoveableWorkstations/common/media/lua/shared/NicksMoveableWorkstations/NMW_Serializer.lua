--[[ ====================================================================
  The placement half of the round-trip: after vanilla sets one of our sprites
  back down, make sure it came back a functional station.

  Vanilla's placeMoveableInternal mints the object, runs its own
  TransferComponents(_item, obj) (ISMoveableSpriteProps.lua:2376), adds it to
  the square and transmits it (:2379-2380), then returns it (:2404). We wrap
  that function, scoped to this mod's sprites, and hand the returned object to
  NMW_Reconstruct, which repairs it only if it came back stripped of its entity
  (see that module's header for the version-agnostic reasoning). Where vanilla's
  transfer already restored the station - 42.20 single-square, live state and
  all - the repair is a no-op and we leave it untouched.

  Why the pickup side needs no code: vanilla already moves the entity's
  components obj->item at pickup (:1280) and the Moveable item persists them
  across save/relog/MP through its own saveEntity/loadEntity
  (InventoryItem.java:1856,2169). Single-square live state therefore rides for
  free; every other case is a bare object at placement, which the wrap here
  catches. Adding our own pickup transfer would only duplicate vanilla's on
  current builds.

  Multi-sprite placement calls placeMoveableInternal once per grid cell
  (:1871), so this wrap fires per cell and each cell is repaired on its own -
  no grid bookkeeping here.

  Scoped like NMW_PickupGuard: a wrap on ISMoveableSpriteProps is global, and
  every non-mod sprite is vanilla's business. pcall the repair so a placement
  can never throw.
==================================================================== ]]

require "NicksMoveableWorkstations/NMW_Sprites"
require "NicksMoveableWorkstations/NMW_Reconstruct"

NicksMoveableWorkstations = NicksMoveableWorkstations or {}
local NMW = NicksMoveableWorkstations

local function log(msg) print("[NicksMoveableWorkstations/Serializer] " .. tostring(msg)) end

local function install()
    local placeMoveableInternal = ISMoveableSpriteProps.placeMoveableInternal

    function ISMoveableSpriteProps:placeMoveableInternal(_square, _item, _spriteName)
        local obj = placeMoveableInternal(self, _square, _item, _spriteName)
        if not obj then return obj end

        local station = NMW.reconstruct.stationForSprite(_spriteName)
        if not station then return obj end

        local ok, repaired = pcall(function()
            return NMW.reconstruct.repair(obj, station)
        end)
        if ok and repaired then return repaired end
        return obj
    end
end

if ISMoveableSpriteProps and ISMoveableSpriteProps.placeMoveableInternal then
    install()
    log("loaded, placement repair installed")
else
    log("ISMoveableSpriteProps not loaded - placement repair NOT installed")
end
