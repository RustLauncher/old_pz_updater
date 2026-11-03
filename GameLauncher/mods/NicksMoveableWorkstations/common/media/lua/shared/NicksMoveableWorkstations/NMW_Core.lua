--[[ ====================================================================
  The whole mod is a .patch.tiles file; this module is its receipt.

  Nothing here changes behaviour. It asks the engine whether the sprite
  properties actually merged and prints one line saying so, because every
  way this mod can fail looks identical from inside the game: a fileNumber
  another mod already claimed, a sprite a patch renamed, and a Workshop copy
  shadowing the deploy all present as "the game loads fine and the pick-up
  entry just isn't there". One grep answers which.

  Shared VM, both halves of a co-op game. Sprite properties are per-VM and
  are not saved, so a server that never merged them refuses pickups its
  clients offer - the second line is worth having in coop-console.txt too.
==================================================================== ]]

require "NicksMoveableWorkstations/NMW_Sprites"

NicksMoveableWorkstations = NicksMoveableWorkstations or {}
local NMW = NicksMoveableWorkstations

local function log(msg) print("[NicksMoveableWorkstations/Core] " .. tostring(msg)) end

-- IsoSpriteManager.getSprite ADDS a blank sprite on a miss rather than returning
-- nil (vanilla CustomTileProps.lua:320 calls it the same unchecked way), so a
-- sprite a game patch renamed arrives here propertyless and counts as unpatched,
-- which is exactly how it should read.
local function isPatched(name)
    local ok, sprite = pcall(function()
        return IsoSpriteManager.instance:getSprite(name)
    end)
    if not ok or not sprite then return false end
    local ok2, props = pcall(function() return sprite:getProperties() end)
    if not ok2 or not props then return false end
    local ok3, has = pcall(function() return props:has("IsMoveAble") end)
    return ok3 and has == true
end

local function verify()
    local stations = NMW.stations
    if not stations then
        log("NMW_Sprites.lua did not load - run tools/make_tiledef.py and redeploy")
        return
    end

    local total, patched, missing = 0, 0, {}
    for i = 1, #stations do
        local sprites = stations[i].sprites
        for j = 1, #sprites do
            total = total + 1
            if isPatched(sprites[j]) then
                patched = patched + 1
            else
                missing[#missing + 1] = stations[i].name .. " " .. sprites[j]
            end
        end
    end

    log("patched " .. tostring(patched) .. "/" .. tostring(total) .. " sprites")
    if #missing > 0 then
        log("NOT patched: " .. table.concat(missing, ", "))
    end
end

-- Vanilla's own CustomTileProps.lua reads sprite properties on this pair, which
-- is the attestation that tile definitions are loaded by then. No vanilla Lua
-- registers OnLoadedTileDefinitions, so nothing proves a mod's handler is
-- installed before it fires.
Events.OnGameStart.Add(verify)
Events.OnServerStarted.Add(verify)

log("loaded")
