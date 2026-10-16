--[[
    Fletcher: the red reticle on a target (true projectiles). Vanilla's reticle turns red over a
    target in range, but with projectiles on the bow's vanilla range is tiny (shared/Fletcher/Gear.lua)
    so it never does. B42's aim marker is a ring on the ground at the target's feet with a line up to
    the cursor; this draws vanilla's red ring (targetReticle03) over it, flat on the ground at the feet
    of the zombie the arrow would go for (F.cursorTarget, the same pick the shot uses) while the player
    aims a bow at it within range. Drawn from OnPreUIDraw with UIManager.DrawTexture: NOT a UI element
    (a full-screen ISUIElement, even with setConsumeMouseEvents(false), counts as the mouse being over
    the UI, and right-click aiming stopped working). Its size is the shot's real spread at the
    target's distance (F.aimMarkTiles), shrinking as the aim settles (F.AIM_STEADY below).
]]

require "Fletcher/Core"
local F = Fletcher

F.AIM_MARK = {
    texture = "media/ui/Reticle/targetReticle03.png",   -- vanilla's red "on target" ring
    tiles = 0.55,                      -- smallest ring width, in tile widths (flattened 2:1 like the ground)
    maxTiles = 3.0,                    -- largest
    sigmas = 1.5,                      -- the ring's radius: this many sigmas of the shot's spread at
                                       -- the target's distance (most arrows land inside it)
    color = { 1.0, 1.0, 1.0, 0.95 },
}

-- Steady aim: a shot loosed the moment the bow is drawn is a snap shot (wider); held on target, the
-- aim settles to steady (tighter) over the settle time, quicker with Archery. Moving doesn't settle
-- (it loses ground). Holding too long brings the shake (Bow.lua FletcherBowTired, x1.3 in shotSpread).
-- The ring above shrinks with it, so the player sees when a shot is good.
F.AIM_STEADY = {
    snap = 1.3,              -- spread x this at the moment of drawing (about the old accuracy)
    steady = 0.85,           -- ... easing to this once settled
    seconds = { 1.6, -0.1 }, -- settle time at Archery 0, per level (0.6 s at 10)
}
F.aimHeld = F.aimHeld or {}      -- local player num -> seconds of settling

--- Spread multiplier for how settled the shooter's aim is (1 for anyone not tracked: other
--- players, tests, the server). F.AIM_STEADY_OVERRIDE (tests) forces it.
function F.aimSteadiness(shooter)
    if F.AIM_STEADY_OVERRIDE then return F.AIM_STEADY_OVERRIDE end
    if not (shooter and shooter.isLocalPlayer and shooter:isLocalPlayer()) then return 1 end
    local held = F.aimHeld[shooter:getPlayerNum()]
    if not held then return 1 end
    local S = F.AIM_STEADY
    local secs = math.max(0.2, S.seconds[1] + S.seconds[2] * F.level(shooter))
    local t = math.min(1, held / secs)
    t = 1 - (1 - t) * (1 - t)                    -- (eases in: most of the settling early)
    return S.snap + (S.steady - S.snap) * t
end

--- Track each local player's settling: a loaded bow or crossbow held aimed, standing
function F.updateAimSteady(dt)
    for pn = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(pn)
        local bow = p and p:getPrimaryHandItem()
        if p and bow and F.bowDef(bow) and p:isAiming() and bow:isRoundChambered() then
            local held = F.aimHeld[pn] or 0
            if p:isPlayerMoving() then held = math.max(0, held - dt * 2) else held = held + dt end
            F.aimHeld[pn] = held
        else
            F.aimHeld[pn] = nil
        end
    end
end

local lastSteady
Events.OnTick.Add(function()
    local now = getTimestampMs()
    local dt = lastSteady and math.min(0.1, (now - lastSteady) / 1000) or 0
    lastSteady = now
    if isGamePaused() then return end
    pcall(F.updateAimSteady, dt)
end)

--- The ring's width in tiles for the shot the player would loose now at target t
function F.aimMarkTiles(player, t)
    local bow = player:getPrimaryHandItem()
    local def = bow and F.bowDef(bow)
    if not def then return F.AIM_MARK.tiles end
    local arrow = bow:getModData().fl_nocked or F.bowArrow(bow)
    local sigma = F.shotSpread(player, F.shotStats(def, F.level(player), arrow, bow, bow:getModData().fl_nockedFletch))
    local tx, ty = F.targetXY(t)
    local d = IsoUtils.DistanceTo(tx, ty, player:getX(), player:getY())
    local r = d * math.tan(math.rad(sigma * F.AIM_MARK.sigmas))
    return math.max(F.AIM_MARK.tiles, math.min(F.AIM_MARK.maxTiles, r * 2))
end

--- Is the local player aiming a bow at a zombie the arrow would go for? (target, or nil)
function F.aimMarkTarget(player)
    if not (player and player:isAiming() and F.projectileMode and F.projectileMode() and F.cursorTarget) then return nil end
    local bow = player:getPrimaryHandItem()
    local def = bow and F.bowDef(bow)
    if not def then return nil end
    local t = F.cursorTarget(player, def.range)
    if t then
        local tx, ty = F.targetXY(t)
        if IsoUtils.DistanceTo(tx, ty, player:getX(), player:getY()) <= def.range then return t end
    end
    return nil
end

-- The vanilla firearm reticle, for bows and crossbows. Vanilla's own (IsoReticle, drawn by Java, not
-- reachable from Lua) is fed by vanilla's hit maths, which never sees a target for a bow (its range
-- is cut to stop vanilla hits), so it stays white with meaningless brackets. While a local player aims
-- a bow with the mouse, vanilla's is hidden (Core:setDisplayCursor(false), restored the moment that
-- stops) and this draws the same thing (IsoReticle.render, B42.21) from the player's own reticle
-- options, fed by Fletcher's aim: the brackets close in as the hit chance on what's under the cursor
-- rises (spread, distance, steady aim, moodles), the aim circle shades from bad to good colour, and
-- the valid-target marker shows on a target the arrow would go for. Controllers keep vanilla's.
F.AIM_RETICLE = {
    enabled = true,
    groundRing = false,       -- the ring at the target's feet (F.AIM_MARK above); vanilla guns have none
    lerp = 0.1,               -- vanilla: the brackets move this share of the way each frame
    minOffset = 5,            -- px (vanilla)
    size = 16,                -- px, every piece (vanilla: a 256 px texture / 16)
}
F.reticleTex = F.reticleTex or {}
local function rtex(name)
    local t = F.reticleTex[name]
    if t == nil then t = getTexture("media/ui/Reticle/" .. name .. ".png") or false; F.reticleTex[name] = t end
    return t or nil
end

-- erf (Abramowitz-Stegun 7.1.26)
local function erf(x)
    local s = x < 0 and -1 or 1
    x = math.abs(x)
    local t = 1 / (1 + 0.3275911 * x)
    local y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-x * x)
    return s * y
end

--- Percent chance the shot loosed now lands on a body-sized target d tiles away (sideways)
function F.reticleChance(player, d)
    local bow = player:getPrimaryHandItem()
    local def = bow and F.bowDef(bow)
    if not def then return 0 end
    local arrow = bow:getModData().fl_nocked or F.bowArrow(bow)
    local sigma = F.shotSpread(player, F.shotStats(def, F.level(player), arrow, bow, bow:getModData().fl_nockedFletch))
    sigma = sigma * (1 + math.max(0, d - def.range) / def.range * F.PROJ.longSpread)   -- (as newProjectile)
    local sd = math.max(1e-4, d * math.tan(math.rad(sigma)))
    return 100 * erf(F.PROJ.radius / (sd * math.sqrt(2)))
end

local function showVanilla()      -- (F.hidVanilla, not a local: a reload mustn't lose it)
    if F.hidVanilla then pcall(function() getCore():setDisplayCursor(true) end); F.hidVanilla = false end
end

function F.drawReticle()
    local R = F.AIM_RETICLE
    local player = getPlayer()
    local bow = player and player:getPrimaryHandItem()
    local on = R.enabled and player and not player:isDead() and player:isAiming() and bow and F.bowDef(bow)
        and F.projectileMode and F.projectileMode() and player:getJoypadBind() == -1 and not isGamePaused()
    if not on then showVanilla(); F.reticleOffset = nil; return end
    local core = getCore()
    if not F.hidVanilla then
        if not core:isDisplayCursor() then return end     -- (something else hid it: leave it alone)
        core:setDisplayCursor(false); F.hidVanilla = true
    end
    local def = F.bowDef(bow)
    local mx, my = getMouseX(), getMouseY()
    local target = F.aimMarkTarget(player)
    local d
    if target then
        local tx, ty = F.targetXY(target)
        d = IsoUtils.DistanceTo(tx, ty, player:getX(), player:getY())
    else
        local ax, ay = F.aimPoint(player, def.range * F.PROJ.maxRangeMul)
        d = IsoUtils.DistanceTo(ax, ay, player:getX(), player:getY())
    end
    local chance = math.max(0, math.min(100, F.reticleChance(player, math.max(1, d))))
    F.reticleLast = { chance = chance, target = target ~= nil, d = d }
    -- brackets: vanilla's offset (mode 0: from the chance; mode 1: from the aim penalty, here how
    -- unsettled the aim still is)
    local maxOff = getCore():getScreenWidth() * core:getOptionMaxCrosshairOffset() / 100
    local k
    if core:getOptionReticleMode() == 1 then
        local S = F.AIM_STEADY
        k = math.max(0, math.min(1, (F.aimSteadiness(player) - S.steady) / math.max(1e-6, S.snap - S.steady)))
    else
        k = 1 - chance / 100
    end
    local want = R.minOffset + (maxOff - R.minOffset) * k
    F.reticleOffset = F.reticleOffset and (F.reticleOffset + (want - F.reticleOffset) * R.lerp) or want
    local off = math.floor(F.reticleOffset)
    local size = R.size * (core:getOptionReticleCameraZoom() and (1 / core:getZoom(player:getPlayerNum())) or 1)
    local x, y = mx - size / 2, my - size / 2
    local rr = getRenderer()
    local function draw(tex, px, py, r, g, b)
        if tex then rr:render(tex, px, py, size, size, r, g, b, 1, nil) end
    end
    local xh = core:getOptionCrosshairTextureIndex()
    draw(rtex("crosshair" .. xh .. "0"), x - off, y, 1, 1, 1)
    draw(rtex("crosshair" .. xh .. "2"), x + off, y, 1, 1, 1)
    draw(rtex("crosshair" .. xh .. "1"), x, y - off, 1, 1, 1)
    draw(rtex("crosshair" .. xh .. "3"), x, y + off, 1, 1, 1)
    if core:getOptionShowAimTexture() then
        local r, g, b = 0.5, 0.5, 0.5
        if target then
            local t = chance < 70 and chance / 140 or 0.5 + (chance - 70) / 30 * 0.5
            local bad, good = core:getBadHighlitedColor(), core:getGoodHighlitedColor()
            r = bad:getR() + (good:getR() - bad:getR()) * t
            g = bad:getG() + (good:getG() - bad:getG()) * t
            b = bad:getB() + (good:getB() - bad:getB()) * t
        end
        draw(rtex(string.format("aimCircle%02d", core:getOptionAimTextureIndex())), x, y, r, g, b)
    end
    local tc = core:getTargetColor()
    if target and core:getOptionShowValidTargetReticleTexture() then
        draw(rtex(string.format("targetReticle%02d", core:getOptionValidTargetReticleTextureIndex())), x, y, tc:getR(), tc:getG(), tc:getB())
    end
    if core:getOptionShowReticleTexture() then
        local r, g, b = 1, 1, 1
        if target then r, g, b = tc:getR(), tc:getG(), tc:getB() end
        draw(rtex(string.format("targetReticle%02d", core:getOptionReticleTextureIndex())), x, y, r, g, b)
    end
end

function F.drawAimMark()
    local player = getPlayer()
    pcall(F.drawReticle)
    local ok, t = pcall(F.aimMarkTarget, player)
    F.aimMarkOn = ok and t ~= nil
    if not F.aimMarkOn or not F.AIM_RETICLE.groundRing then return end
    -- (ViewPoint's 3D view: the ring is placed for the iso screen; the reticle alone shows the target)
    if F.viewpointView and F.viewpointView(player) then return end
    F.aimMarkTex = F.aimMarkTex or getTexture(F.AIM_MARK.texture)
    if not F.aimMarkTex then return end
    local tx, ty, tz = F.targetXY(t)
    local pn, z = player:getPlayerNum(), math.floor(tz)
    local fx, fy = isoToScreenX(pn, tx, ty, z), isoToScreenY(pn, tx, ty, z)
    local ok2, tiles = pcall(F.aimMarkTiles, player, t)
    local w = math.abs(isoToScreenX(pn, tx + 0.5, ty - 0.5, z) - fx) * 2 * (ok2 and tiles or F.AIM_MARK.tiles)
    local h = w / 2
    UIManager.DrawTexture(F.aimMarkTex, fx - w / 2, fy - h / 2, w, h, F.AIM_MARK.color[4])
end

Events.OnPreUIDraw.Add(function() F.drawAimMark() end)     -- by name: reloads apply

return F
