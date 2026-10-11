--[[
    Fletcher: vanilla reload / unload with the right arrow, wherever they run.

    In multiplayer the reload's real work runs on the SERVER (ISReloadWeaponAction:serverStart ->
    initVars, loadAmmo only when not isClient()) on the server's own copy of the bow, whose
    AmmoType the client can't set. So, on whichever side these run (the client in singleplayer):
      before initVars / unload: point the bow at its nocked arrow (md.fl_nocked), or, empty, at the
                                arrow to nock (F.arrowFor: the player's preferred type, else best)
      after loadAmmo:           md.fl_nocked = the arrow that went in (the server's record of it is
                                what a multiplayer shot spends: server/Fletcher/Server.lua)
      rack (ISRackFirearm):     ejects a chambered arrow as its AmmoType: pointed at the nocked one first
      after unloading:          md.fl_nocked cleared
      fletching (Fletching.lua): the arrow item the load takes (vanilla takes the first of self.bullets)
                                is read for its fletching -> md.fl_nockedFletch; an unloaded / racked-out
                                arrow (a fresh item vanilla makes) gets it back (F.restoreUnloaded). In
                                multiplayer the client's copy is set from its own bullet list at initVars
                                (the load itself runs on the server, which records its own).
      one at a time:            a launcher that holds an arrow / bolt (F.bowFull) won't reload again
                                (vanilla would put a second one in its 1-round "magazine")
      cocking:                  a launcher with a cocker (the Lever Crossbow) won't reload without it
                                in the inventory: refused at BeginAutomaticReload (with a message)
                                and by isValid (both sides, so the server refuses it too)
      load time:                multiplayer: the server finishes a load on its own timer (vanilla:
                                590 ms for a bolt action), not on our clip: serverStart's timer is
                                set to our clip's length at the player's speed (F.loadMs)
    Wrapped once (ISReloadWeaponAction.fl_wrapped); the wrappers call F.* by name, so a hot reload
    of this file applies.
]]

require "TimedActions/ISReloadWeaponAction"
require "TimedActions/ISUnloadBulletsFromFirearm"
require "TimedActions/ISRackFirearm"
require "Fletcher/Core"
require "Fletcher/Gear"
require "Fletcher/Quiver"
require "Fletcher/Fletching"
local F = Fletcher

--- Point a bow at the arrow it holds, or, empty, at the one it should take next.
function F.prepareBowAmmo(character, gun)
    if not F.isBow(gun) then return end
    local md = gun:getModData()
    if gun:isRoundChambered() or gun:getCurrentAmmoCount() > 0 then
        if md.fl_nocked then F.setBowArrow(gun, md.fl_nocked) end
    elseif character then
        F.setBowArrow(gun, F.arrowFor(character, gun))
    end
end

function F.afterLoadAmmo(gun)
    if F.isBow(gun) and (gun:getCurrentAmmoCount() > 0 or gun:isRoundChambered()) then
        gun:getModData().fl_nocked = F.bowArrow(gun)
    end
end

function F.afterUnload(gun)
    if F.isBow(gun) and gun:getCurrentAmmoCount() == 0 and not gun:isRoundChambered() then
        gun:getModData().fl_nocked = nil
        gun:getModData().fl_nockedFletch = nil
        gun:getModData().fl_lit = nil              -- (unnocked: a lit fire arrow goes out)
    end
end

--- The arrow item a reload will take next (vanilla: the first of self.bullets), or nil
function F.nextBullet(action)
    local b = action and action.bullets
    if not b or b:isEmpty() then return nil end
    return b:get(0)
end

--- The arrow items of a type in a container (its own list, not bags), as a set
local function itemsOfType(container, fullType)
    local set = {}
    local list = container and fullType and container:getItemsFromFullType(fullType)
    for i = 0, (list and list:size() or 0) - 1 do set[list:get(i)] = true end
    return set
end

--- Unload / rack: vanilla gives back a fresh item of the nocked type; give it the nocked fletching.
--- before = itemsOfType taken before the action step; fl = the fletching that was nocked.
function F.restoreUnloaded(character, arrowType, before, fl)
    if not (character and arrowType and fl) then return end
    local list = character:getInventory():getItemsFromFullType(arrowType)
    for i = 0, (list and list:size() or 0) - 1 do
        local it = list:get(i)
        if not before[it] and not F.fletchOf(it) then
            F.setFletch(it, fl)
            if isServer() and syncItemModData then pcall(syncItemModData, character, it) end
            return it
        end
    end
end

--- A launcher holds one arrow / bolt: nocked (chambered) or loaded (magazine count) means full. Vanilla
--- treats it as a gun with a chamber plus a 1-round magazine, so a second reload would load a second
--- arrow behind the nocked one.
function F.bowFull(gun)
    return F.isBow(gun) and (gun:isRoundChambered() or gun:getCurrentAmmoCount() > 0) or false
end

--- Can this character reload this launcher? False (and why) without its cocker.
function F.canCock(character, gun)
    local missing = F.missingCocker(character, gun)
    if not missing then return true end
    return false, getText("IGUI_Fletcher_NeedCocker", getItemNameFromFullType(missing))
end

function F.sayCantCock(character, why)
    if not (why and character and not isServer()) then return end
    if HaloTextHelper and HaloTextHelper.addBadText then
        HaloTextHelper.addBadText(character, why)
    else
        character:Say(why)
    end
end

--- isValid gate for our launchers: the cocker, and full already when the reload was asked for
--- (checked once per action: the load itself fills the launcher mid-action)
function F.reloadValid(action)
    if not F.isBow(action.gun) then return true end
    if not F.canCock(action.character, action.gun) then return false end
    if action.fl_fullAtStart == nil then action.fl_fullAtStart = F.bowFull(action.gun) end
    return not action.fl_fullAtStart
end

--- BeginAutomaticReload gate (R / RB / the radial): false = don't start (and say why if it's the cocker)
function F.reloadBegin(playerObj, gun)
    if not F.isBow(gun) then return true end
    if F.bowFull(gun) then return false end                      -- one arrow / bolt at a time
    local ok, why = F.canCock(playerObj, gun)
    if not ok then F.sayCantCock(playerObj, why); return false end
    return true
end

-- (the wrappers call the gates by name, so a hot reload of this file updates them)
if not ISReloadWeaponAction.fl_gateWrapped then
    ISReloadWeaponAction.fl_gateWrapped = true
    local isValid, begin = ISReloadWeaponAction.isValid, ISReloadWeaponAction.BeginAutomaticReload
    ISReloadWeaponAction.isValid = function(self, ...)
        if not F.reloadValid(self) then return false end
        return isValid(self, ...)
    end
    ISReloadWeaponAction.BeginAutomaticReload = function(playerObj, gun, ...)
        if not F.reloadBegin(playerObj, gun) then return end
        return begin(playerObj, gun, ...)
    end
end

--- How long the load clip of this launcher plays for this character, in ms at ReloadSpeed 1 (the
--- server divides by the character's ReloadSpeed, as the client's animation is sped up by it)
function F.loadMs(character, gun)
    return F.loadSeconds(gun) * 1000 / F.reloadFactor(character, gun)
end

if not ISReloadWeaponAction.fl_timeWrapped and ISReloadWeaponAction.serverStart then
    ISReloadWeaponAction.fl_timeWrapped = true
    local serverStart = ISReloadWeaponAction.serverStart
    ISReloadWeaponAction.serverStart = function(self, ...)
        if not (F.isBow(self.gun) and emulateAnimEvent) then return serverStart(self, ...) end
        local emulate = emulateAnimEvent
        local ms = F.loadMs(self.character, self.gun)
        emulateAnimEvent = function(netAction, time, event, param, ...)
            if event == "loadFinished" then time = ISReloadWeaponAction.getReloadTime(self.character, ms) end
            return emulate(netAction, time, event, param, ...)
        end
        local ok, r = pcall(serverStart, self, ...)
        emulateAnimEvent = emulate
        if not ok then error(r) end
        return r
    end
end

if not ISReloadWeaponAction.fl_wrapped then
    ISReloadWeaponAction.fl_wrapped = true
    local initVars, loadAmmo = ISReloadWeaponAction.initVars, ISReloadWeaponAction.loadAmmo
    ISReloadWeaponAction.initVars = function(self, ...)
        F.prepareBowAmmo(self.character, self.gun)
        local r = initVars(self, ...)
        if F.isBow(self.gun) and isClient() and not F.bowFull(self.gun) then     -- (multiplayer client: predict)
            local b = F.nextBullet(self)
            if b then self.gun:getModData().fl_nockedFletch = F.fletchOf(b) end
        end
        return r
    end
    ISReloadWeaponAction.loadAmmo = function(self, ...)
        local b = F.isBow(self.gun) and not F.bowFull(self.gun) and F.nextBullet(self) or nil
        local fl = b and F.fletchOf(b)
        local r = loadAmmo(self, ...)
        F.afterLoadAmmo(self.gun)
        if b and F.bowFull(self.gun) then
            self.gun:getModData().fl_nockedFletch = fl
            if isServer() and syncItemModData then pcall(syncItemModData, self.character, self.gun) end
        end
        return r
    end
    local rack = ISRackFirearm.rackBullet
    ISRackFirearm.rackBullet = function(self, ...)
        F.prepareBowAmmo(self.character, self.gun)
        local md = F.isBow(self.gun) and self.gun:getModData()
        local arrowType, fl = md and md.fl_nocked, md and md.fl_nockedFletch
        local before = (md and fl) and itemsOfType(self.character:getInventory(), arrowType) or nil
        local r = rack(self, ...)
        F.afterLoadAmmo(self.gun)
        F.afterUnload(self.gun)
        if before and not F.bowFull(self.gun) then F.restoreUnloaded(self.character, arrowType, before, fl) end
        return r
    end
    local uStart, uServerStart, uAnim = ISUnloadBulletsFromFirearm.start, ISUnloadBulletsFromFirearm.serverStart,
        ISUnloadBulletsFromFirearm.animEvent
    ISUnloadBulletsFromFirearm.start = function(self, ...)
        F.prepareBowAmmo(self.character, self.gun)
        return uStart(self, ...)
    end
    if uServerStart then
        ISUnloadBulletsFromFirearm.serverStart = function(self, ...)
            F.prepareBowAmmo(self.character, self.gun)
            return uServerStart(self, ...)
        end
    end
    ISUnloadBulletsFromFirearm.animEvent = function(self, ...)
        F.prepareBowAmmo(self.character, self.gun)
        local md = F.isBow(self.gun) and self.gun:getModData()
        local arrowType, fl = md and md.fl_nocked, md and md.fl_nockedFletch
        local before = (md and fl) and itemsOfType(self.character:getInventory(), arrowType) or nil
        local r = uAnim(self, ...)
        F.afterUnload(self.gun)
        if before then F.restoreUnloaded(self.character, arrowType, before, fl) end
        return r
    end
end

return F
