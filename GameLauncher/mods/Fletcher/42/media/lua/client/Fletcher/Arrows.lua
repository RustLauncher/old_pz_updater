--[[
    Fletcher: noticing the local player's bow shots. With true projectiles on (single player,
    F.projectileMode) a shot is handed to F.launchProjectile (client/Fletcher/Flight.lua) instead.

    The shot itself is the game's ranged attack (the bow is built on it): it consumes the nocked
    arrow and resolves the hit. This file sees each shot (and what it hit) and hands it on:
      singleplayer -> F.resolveShot here (shared/Fletcher/Shots.lua: XP, breakage, where it lands)
      multiplayer  -> a "shot" command to the server, which resolves it with ITS record of the
                      nocked arrow (server/Fletcher/Server.lua), so a client can't make arrows up
]]

require "Fletcher/Core"
require "Fletcher/Skill"
require "Fletcher/Gear"
require "Fletcher/FireLight"
require "Fletcher/Shots"
local F = Fletcher

F.RESOLVE_MS = 400           -- wait this long after the release for a hit to be reported
-- F.SEND_SHOTS = false: tests only (tests/mp_archery.lua), multiplayer shots aren't reported

F.pendingShots = F.pendingShots or {}

local function isBowShot(character, weapon)
    return character and weapon and character:isLocalPlayer() and F.BOWS and F.BOWS[weapon:getFullType()]
end

-- One shot = the bow's nocked arrow leaving the string during an attack. OnWeaponSwing fires every
-- frame of the attack (8 times for one shot), so it only marks "attacking now"; the shot is the
-- loaded -> empty change of the bow, seen once, within SWING_WINDOW_MS of a swing (an unload action
-- also empties the bow, without a swing).
F.SWING_WINDOW_MS = 1500
F.shooters = F.shooters or {}

function F.onWeaponSwing(character, weapon)
    if not isBowShot(character, weapon) or not weapon:isRanged() then return end
    local st = F.shooters[character] or {}
    F.shooters[character] = st
    st.swingAt = getTimestampMs()
end

function F.onWeaponHitCharacter(attacker, target, weapon, damage)
    if not isBowShot(attacker, weapon) then return end
    -- vanilla reports a "hit" on a player it then doesn't hurt (PvP off): the arrow flies past them
    if instanceof(target, "IsoPlayer") and not F.canShootPlayer(attacker, target) then return end
    local st = F.shooters[attacker]
    if st then st.target = target; st.targetAt = getTimestampMs() end
    local shot = F.pendingShots[#F.pendingShots]
    if shot and shot.shooter == attacker and not shot.target then shot.target = target end
end

--- Watch each local player's bow: a loaded -> empty change right after a swing is one shot.
function F.watchBow(player)
    local bow = F.equippedBow and F.equippedBow(player)
    local st = F.shooters[player] or {}
    F.shooters[player] = st
    local loaded = bow ~= nil and bow:isRoundChambered()
    if st.loaded and not loaded and st.bow == bow and st.swingAt and getTimestampMs() - st.swingAt < F.SWING_WINDOW_MS then
        F.shotCount = (F.shotCount or 0) + 1
        local lit = st.lit
        if not isClient() and F.takeLit then lit = F.takeLit(bow) or st.lit end
        if F.projectileMode and F.projectileMode() and F.launchProjectile then
            local ta = F.TEST_AIM                                -- (tests: a set aim point, no spread)
            if ta then
                F.launchFrom({ shooter = player, bow = bow, arrow = st.arrow, fl = st.fl, tx = ta.tx, ty = ta.ty, noSpread = ta.noSpread, aimH = ta.aimH, lit = lit })
            else
                F.launchProjectile(player, bow, st.arrow, nil, nil, lit, st.fl)   -- it flies (client/Fletcher/Flight.lua)
            end
        else
            local dir = player:getForwardDirection()
            local shot = { at = getTimestampMs(), x = player:getX() + 0.5, y = player:getY() + 0.5,
                z = math.floor(player:getZ()), dx = dir:getX(), dy = dir:getY(), shooter = player, arrow = st.arrow, fl = st.fl }
            local adef = F.ARROW_DEFS[st.arrow or ""]
            if adef and adef.fire and not isClient() then
                if F.handLighting and F.handLighting() then shot.lit = lit == true else shot.lit = F.lightFire(player) end
            end
            if st.target and st.targetAt and getTimestampMs() - st.targetAt < F.SWING_WINDOW_MS then shot.target = st.target end
            table.insert(F.pendingShots, shot)
        end
        st.swingAt, st.target = nil, nil
    end
    if loaded then
        st.arrow = bow:getModData().fl_nocked or F.bowArrow(bow)    -- the shot's arrow, read before it leaves
        st.lit = bow:getModData().fl_lit == true                   -- ... and whether it was lit (FireLight.lua)
        st.fl = bow:getModData().fl_nockedFletch                   -- ... and its fletching (Fletching.lua)
    end
    st.loaded, st.bow = loaded, bow
end

--- Multiplayer: the shot as plain data for the server (it finds the target again by online id
--- near where the client saw it, and uses its own record of the nocked arrow).
function F.shotMessage(shot)
    local msg = { x = shot.x, y = shot.y, z = shot.z, dx = shot.dx, dy = shot.dy, arrow = shot.arrow }
    local t = shot.target
    if t then
        msg.target = {
            id = t:getOnlineID(), x = t:getX(), y = t:getY(), z = t:getZ(),
            kind = instanceof(t, "IsoZombie") and "zombie" or (F.isPerson(t) and "player" or (instanceof(t, "IsoAnimal") and "animal" or "other")),
        }
    end
    return msg
end

function F.onArrowTick()
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and p:isLocalPlayer() then pcall(F.watchBow, p) end
    end
    if #F.pendingShots == 0 then return end
    local now = getTimestampMs()
    for i = #F.pendingShots, 1, -1 do
        local shot = F.pendingShots[i]
        if now - shot.at >= F.RESOLVE_MS then
            table.remove(F.pendingShots, i)
            if isClient() then
                if F.SEND_SHOTS ~= false then     -- (tests switch it off to send their own)
                    local ok, msg = pcall(F.shotMessage, shot)
                    if ok then sendClientCommand(shot.shooter, "Fletcher", "shot", msg) end
                    F.lastShot = ok and "sent" or ("error: " .. tostring(msg))
                else
                    F.lastShot = "not sent (SEND_SHOTS off)"
                end
            else
                local ok, res = pcall(F.resolveShot, shot)
                F.lastShot = ok and res or ("error: " .. tostring(res))
            end
        end
    end
end

-- Hooks look the handlers up by name each time. No "already hooked" guard: pzbridge.py reload
-- removes a file's handlers before re-running it (a guard would leave none).
Events.OnWeaponSwing.Add(function(...) F.onWeaponSwing(...) end)
Events.OnWeaponHitCharacter.Add(function(...) F.onWeaponHitCharacter(...) end)
Events.OnTick.Add(function() F.onArrowTick() end)

--- Server -> client commands (module "Fletcher"):
---   ignite { id, kind }   a lit fire arrow hit this zombie / player: its OWNER sets it alight (a
---                         multiplayer client owns the zombies near it; the fire syncs from there)
function F.igniteLocal(id, kind)
    if kind == "player" then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p and p:isLocalPlayer() and p:getOnlineID() == id then p:SetOnFire(); return true end
        end
        return false
    end
    local zl = getCell() and getCell():getZombieList()
    for i = 0, (zl and zl:size() or 0) - 1 do
        local z = zl:get(i)
        if z:getOnlineID() == id then
            if z:isRemoteZombie() or z:isDead() then return false end     -- (not ours: its owner does it)
            z:SetOnFire()
            return true
        end
    end
    return false
end

function F.onServerCommand(module, command, args)
    if module ~= "Fletcher" or type(args) ~= "table" then return end
    if command == "ignite" then F.lastIgnite = { id = args.id, done = F.igniteLocal(args.id, args.kind) } end
end

Events.OnServerCommand.Add(function(...) F.onServerCommand(...) end)     -- by name: reloads apply

return F
