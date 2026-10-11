--[[
    Fletcher: lighting a nocked fire arrow by hand (0.6.1). Sandbox Fletcher.LightFireArrowsByHand
    (on); off = the old way (lit on release from a lighter or matches carried, Shots.lua F.lightFire).

    With it on, a fire arrow is nocked with its rag dark. "Light Arrow" in the reload radial
    (client/Fletcher/Radial.lua) queues FletcherLightArrowAction: the Fletcher_Bow_LightArrow clip
    (bow_clips.py light: lighter from the pocket to the rag and back), one use of the fire starter,
    and the bow's record says the arrow is lit (md.fl_lit = true). Loosed lit, it flies lit and burns
    what it hits as before; loosed dark, it's a plain (weak) arrow, as an unlit fire arrow always was.

    A lit rag burns for F.LIGHT.burnSeconds; then it's gone and the arrow on the string is a plain
    Fire-hardened Arrow (F.burnOut). Unnocking a lit arrow puts it out: the fire arrow comes back (the
    lighter use was the cost). Burning it out and the shot's lit flag are decided where the bow's
    record lives: single player here; in multiplayer the server (its copy of the bow; the client
    learns through syncItemModData and only shows it).

    The look: the nocked arrow's visual becomes FletcherNocked_FireArrowLit1..3 (cycled: the flame
    flickers; client/Fletcher/Bow.lua F.arrowVisualFor) from the moment the rag catches in the clip
    (F.LIGHT.catchAt), and a small warm light follows the archer while it burns.
]]

require "TimedActions/ISBaseTimedAction"
require "Fletcher/Core"
require "Fletcher/Gear"
require "Fletcher/Shots"
local F = Fletcher

F.LIGHT = {
    seconds = 1.8,          -- the action at speed 1 (the clip's length: bow_clips.LIGHT_SECONDS)
    catchAt = 0.55,         -- share of it where the rag catches (bow_clips.LIGHT_CATCH)
    burnSeconds = 25,       -- a lit rag lasts this long on the string
    spent = "Fletcher.WoodenArrow",   -- what's left on the string when the rag burns away
    flickerMs = 250,        -- the flame's frames
    light = { radius = 4, r = 1.0, g = 0.55, b = 0.2 },
}
F.FIRE_LIT_VISUALS = { "Fletcher.ArrowVisual_FireArrowLit1", "Fletcher.ArrowVisual_FireArrowLit2",
                       "Fletcher.ArrowVisual_FireArrowLit3" }

--- Are fire arrows lit by hand (the sandbox option, on by default)?
function F.handLighting()
    local sv = SandboxVars and SandboxVars.Fletcher
    return not (sv and sv.LightFireArrowsByHand == false)
end

--- A bow with a fire arrow on the string (nocked)
function F.fireNocked(bow)
    if not (bow and F.isBow(bow) and bow:isRoundChambered()) then return false end
    local def = F.ARROW_DEFS[bow:getModData().fl_nocked or F.bowArrow(bow) or ""]
    return def ~= nil and def.fire ~= nil
end

function F.isLit(bow)
    return bow ~= nil and bow:getModData().fl_lit == true
end

--- Can this character light the arrow on its bow now? (hand lighting on, a fire arrow nocked and dark,
--- a lighter or matches with a use left)
function F.canLightArrow(character, bow)
    return F.handLighting() and F.fireNocked(bow) and not F.isLit(bow) and F.fireSource(character) ~= nil
end

-- when each lit bow caught, by this side's clock (bow item -> ms): burning out is timed here
F.litSince = F.litSince or {}
F.lighting = F.lighting or {}        -- character -> { bow, at }: lighting it now (the clip's catch shows the flame)
F.darkSince = F.darkSince or {}      -- bow -> ms: lit, but no fire arrow on the string since then
F.DARK_GRACE_MS = 5000               -- (a shot's report reaches the server after the bow is empty: it reads the flag)

local function sync(character, bow)
    if isServer() and syncItemModData then pcall(syncItemModData, character, bow) end
end

--- Light it (the action's complete): one use of the fire starter. True if lit.
function F.lightArrow(character, bow)
    if not F.canLightArrow(character, bow) then return false end
    if not F.lightFire(character) then return false end
    bow:getModData().fl_lit = true
    F.litSince[bow] = getTimestampMs()
    sync(character, bow)
    F.lastLit = { bow = bow, at = getTimestampMs() }
    return true
end

--- The rag burned away: the arrow on the string is a plain fire-hardened one now
function F.burnOut(character, bow)
    local md = bow:getModData()
    md.fl_lit = nil
    F.litSince[bow] = nil
    if F.fireNocked(bow) then
        md.fl_nocked = F.LIGHT.spent
        if F.setBowArrow then F.setBowArrow(bow, F.LIGHT.spent) end
    end
    sync(character, bow)
    F.lastBurnOut = { bow = bow, at = getTimestampMs() }
end

--- The shot left: whether it was lit (and the bow's record of it cleared). Where the record lives:
--- single player, or the server.
function F.takeLit(bow)
    if not bow then return false end
    local md = bow:getModData()
    local lit = md.fl_lit == true
    md.fl_lit = nil
    F.litSince[bow] = nil
    return lit
end

--- Every so often, where the record lives: lit bows burn out; a bow that lost its fire arrow (shot,
--- unnocked) loses its lit flag.
F.BURN_CHECK_MS = 250
F.nextBurnCheck = 0
function F.fireLightTick()
    if isClient() then return end
    local now = getTimestampMs()
    if now < F.nextBurnCheck then return end
    F.nextBurnCheck = now + F.BURN_CHECK_MS
    local players = {}
    if isServer() then
        local list = getOnlinePlayers()
        for i = 0, (list and list:size() or 0) - 1 do players[#players + 1] = list:get(i) end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then players[#players + 1] = p end
        end
    end
    for _, p in ipairs(players) do
        local bow = p:getPrimaryHandItem()
        if bow and F.isLit(bow) then
            if not F.fireNocked(bow) then
                F.darkSince[bow] = F.darkSince[bow] or now
                if now - F.darkSince[bow] > F.DARK_GRACE_MS then
                    bow:getModData().fl_lit = nil
                    F.litSince[bow], F.darkSince[bow] = nil, nil
                    sync(p, bow)
                end
            else
                F.darkSince[bow] = nil
                F.litSince[bow] = F.litSince[bow] or now          -- (lit before a reload of this file / a load)
                if now - F.litSince[bow] > F.LIGHT.burnSeconds * 1000 then F.burnOut(p, bow) end
            end
        end
    end
end

Events.OnTick.Add(function() F.fireLightTick() end)     -- by name: reloads apply

-- ---------------------------------------------------------------------------------------------
-- The action. Shared (a multiplayer server builds its own copy by class name; the work is in
-- complete(), which runs where the record lives).
FletcherLightArrowAction = ISBaseTimedAction:derive("FletcherLightArrowAction")

function FletcherLightArrowAction:new(character, bow)
    local o = ISBaseTimedAction.new(self, character)
    o.bow = bow
    o.stopOnWalk = false
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = o:getDuration()
    return o
end

function FletcherLightArrowAction:isValid()
    local inv = self.character:getInventory()
    local has = isClient() and inv:containsID(self.bow:getID()) or inv:containsRecursive(self.bow)
    return has and self.character:getPrimaryHandItem() == self.bow and F.canLightArrow(self.character, self.bow)
end

function FletcherLightArrowAction:start()
    self:setActionAnim("FletcherLightArrow")
    self.sound = self.character:playSound("UseLighter")
    if F.lighting then F.lighting[self.character] = { bow = self.bow, at = getTimestampMs(), action = self } end
end

function FletcherLightArrowAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function FletcherLightArrowAction:stop()
    if F.lighting then F.lighting[self.character] = nil end
    ISBaseTimedAction.stop(self)
end

function FletcherLightArrowAction:perform()
    if F.lighting then F.lighting[self.character] = nil end
    ISBaseTimedAction.perform(self)
end

function FletcherLightArrowAction:complete()
    F.lightArrow(self.character, self.bow)
    return true
end

function FletcherLightArrowAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return math.floor(F.LIGHT.seconds * 50 + 0.5)
end

--- Queue it (the radial's "Light Arrow")
function F.queueLightArrow(character, bow)
    if not F.canLightArrow(character, bow) then return false end
    ISTimedActionQueue.add(FletcherLightArrowAction:new(character, bow))
    return true
end

return F
