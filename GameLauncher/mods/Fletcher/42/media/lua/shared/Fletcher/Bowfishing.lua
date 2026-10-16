--[[
    Fletcher 0.7: bowfishing.

    The Bowfishing Arrow (Fletcher.FishingArrow, def.fishing) is on a line. While a local player aims a
    bow with one nocked at fishable water, fish break the surface near the aim as short splashes
    (client/Fletcher/BowfishingRises.lua; how often follows vanilla's fish count there). An arrow
    landing in water stays on its line (F.fishingResolve: no drop, no breakage; the shot is recorded
    where the shot is resolved: single player, or the server). Landing within F.FISHING.strikeRadius
    of a fish that rose moments before is a strike; either way the shooter reels the arrow back
    (FletcherReelFishAction). At its end (single player: complete(); multiplayer: the client sends
    "reel" and the server runs F.reelInFor) F.reelIn checks the recorded shot,
    then on a strike makes the fish with vanilla's code (Fishing.Fish:createFish, the species of that
    water within the Fishing skill's size limit; FishSchoolManager counts it caught), rolls whether it
    tears free (bigger fish more, Fishing skill less), and pays Fishing XP like a rod (2 x the length
    in cm) plus a little Archery XP. The arrow comes back unless the line snaps.
]]

require "TimedActions/ISBaseTimedAction"
require "Fletcher/Core"
require "Fletcher/Gear"
local F = Fletcher

F.FISHING = {
    arrow = "Fletcher.FishingArrow",
    strikeRadius = 0.9,         -- tiles from a rising fish's spot to the arrow's landing
    riseShowMs = 1800,          -- a fish is up this long (shots landing a little after still count)
    riseLateMs = 400,
    riseMinMs = 1500, riseMaxMs = 4500,   -- between rises where fish are plentiful (fewer fish: longer)
    -- where a fish rises: anywhere in reach where vanilla's fish are (its fish points, the same ones it
    -- draws its ripples round), picked in proportion to the fish count there, a little more likely
    -- near the aim (x (1 + aimPull) at the aim point, fading out by aimNear tiles)
    riseRange = 15,             -- tiles from the archer (and no farther than the bow's range)
    riseSamples = 45,           -- water tiles sampled across the reach for each rise ...
    riseAimSamples = 15,        -- ... and round the aim (so a narrow stretch isn't missed)
    aimPull = 0.5, aimNear = 4,
    shotKeepMs = 15000,         -- a recorded shot waits this long for its reel
    reelStrikeSeconds = 3.5, reelMissSeconds = 1.2,
    escape = { Small = 6, Medium = 16, Big = 30, Legendary = 45 },   -- percent, less 3 per Fishing level
    escapeFloor = 2,
    lineSnap = 5,               -- percent: the line parts and the arrow is lost (misses and escapes)
    archeryXp = 4,
}

function F.isFishingArrow(arrowType)
    local def = F.ARROW_DEFS[arrowType or ""]
    return def ~= nil and def.fishing == true
end

--- Water a fish could be in (vanilla's water flag on the ground floor, outside its no-fish zones)
function F.isFishWater(x, y)
    if not (x and y) then return false end
    local fx, fy = math.floor(x), math.floor(y)
    local sq = getCell() and getCell():getGridSquare(fx, fy, 0)
    if not (sq and sq:getProperties() and sq:getProperties():has(IsoFlagType.water)) then return false end
    return not (Fishing and Fishing.isNoFishZone and Fishing.isNoFishZone(fx, fy))
end

--- Vanilla's fish count at a spot (0 if the fishing system isn't there)
function F.fishAbundance(x, y)
    local ok, n = pcall(function() return FishSchoolManager.getInstance():getFishAbundance(math.floor(x), math.floor(y)) end)
    return ok and tonumber(n) or 0
end

-- shots on the line, where shots are resolved: shooter -> { x, y, z, t, arrow }
F.fishShots = F.fishShots or {}

--- (Shots.lua F.resolveShot, first) A bowfishing arrow that came down in water: on its line, so it
--- isn't dropped, broken or worn; the shot waits for its reel. True if it was one.
function F.fishingResolve(shot)
    if not (shot and F.isFishingArrow(shot.arrow) and not shot.target and not shot.practice) then return false end
    if not F.isFishWater(shot.x, shot.y) or (shot.z and shot.z ~= 0) then return false end
    if shot.shooter then
        F.fishShots[shot.shooter] = { x = shot.x, y = shot.y, z = 0, t = getTimestampMs(), arrow = shot.arrow, fl = shot.fl }
    end
    F.lastFishShot = { x = shot.x, y = shot.y }
    return true
end

--- The fish species of that water this character can land (vanilla's configs: river or lake, under the
--- Fishing skill's size limit; no bait fish), picked evenly
function F.pickFishConfig(character, x, y)
    if not (Fishing and Fishing.fishes) then return nil end
    local lvl = character:getPerkLevel(Perks.Fishing)
    local limit = Fishing.Utils and Fishing.Utils.skillSizeLimit and Fishing.Utils.skillSizeLimit[lvl] or 2
    local river = Fishing.isRiver and Fishing.isRiver(math.floor(x), math.floor(y)) or false
    local list = {}
    for _, cfg in ipairs(Fishing.fishes) do
        if cfg.itemType ~= "Base.BaitFish" and cfg.maxWeight and cfg.maxWeight <= limit
                and ((river and cfg.isRiver) or (not river and cfg.isLake)) then
            list[#list + 1] = cfg
        end
    end
    if #list == 0 then return nil end
    return list[ZombRand(#list) + 1]
end

--- Percent chance a struck fish tears free
function F.escapeChance(character, size)
    local base = F.FISHING.escape[size or "Small"] or F.FISHING.escape.Small
    return math.max(F.FISHING.escapeFloor, base - 3 * character:getPerkLevel(Perks.Fishing))
end

local function sizeOf(fish)
    local n = fish:getModData().fishing_FishSize or 0
    local hand = tostring(fish:getModData().fishing_FishHandItem or "")
    if hand:find("_Big") then return n >= 100 and "Legendary" or "Big" end
    if hand:find("_Medium") then return "Medium" end
    return "Small"
end

--- The reel's end (single player, or the server): the outcome as { caught = item | nil, escaped,
--- arrowBack, reason }. Gives the fish and the arrow back, pays the XP.
function F.reelIn(character, x, y, strike)
    local rec = F.fishShots[character]
    F.fishShots[character] = nil
    local out = { arrowBack = false }
    if not rec or getTimestampMs() - rec.t > F.FISHING.shotKeepMs then out.reason = "no shot"; F.lastReel = out; return out end
    if x and y and IsoUtils.DistanceTo(x, y, rec.x, rec.y) > 3 then out.reason = "elsewhere"; F.lastReel = out; return out end
    local inv = character:getInventory()
    local function give(item)
        inv:AddItem(item)
        if isServer() then sendAddItemToContainer(inv, item) end
    end
    local snap = ZombRand(100) < F.FISHING.lineSnap
    if strike and F.fishAbundance(rec.x, rec.y) > 0 then
        local cfg = F.pickFishConfig(character, rec.x, rec.y)
        local fish = cfg and Fishing.Fish:new(character, nil, true, math.floor(rec.x), math.floor(rec.y)):createFish(cfg)
        if fish then
            local size = sizeOf(fish)
            out.size = size
            if ZombRand(100) < F.escapeChance(character, size) then
                out.escaped = true
            else
                pcall(function() FishSchoolManager.getInstance():catchFish(math.floor(rec.x), math.floor(rec.y)) end)
                give(fish)
                out.caught = fish
                addXp(character, Perks.Fishing, 2 * (fish:getModData().fishing_FishSize or 1))
                F.awardXp(character, F.FISHING.archeryXp)
                snap = false                               -- (a landed fish brings the arrow in with it)
            end
        end
    elseif strike then
        out.reason = "no fish there"
    end
    if not snap then
        give(F.setFletch(instanceItem(rec.arrow or F.FISHING.arrow), rec.fl))
        out.arrowBack = true
    end
    F.lastReel = out
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Reeling the arrow back in (a fish on it or not). Shared: the work is in complete(), where the
-- shot was recorded.
FletcherReelFishAction = ISBaseTimedAction:derive("FletcherReelFishAction")

function FletcherReelFishAction:new(character, x, y, strike)
    local o = ISBaseTimedAction.new(self, character)
    o.x, o.y, o.strike = x, y, strike == true
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = false
    o.maxTime = o:getDuration()
    return o
end

function FletcherReelFishAction:isValid()
    return true
end

function FletcherReelFishAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    if self.x and self.y then self.character:faceLocationF(self.x, self.y) end
end

function FletcherReelFishAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
    if self.strike and not isServer() and self.x and ZombRand(20) == 0 then
        local sq = getCell():getGridSquare(math.floor(self.x), math.floor(self.y), 0)
        if sq then pcall(function() sq:startWaterSplash(true, ZombRandFloat(-0.2, 0.2), ZombRandFloat(-0.2, 0.2)) end) end
    end
end

-- stopped part way (walked off, another action): the fish gets away, the line still comes in
function FletcherReelFishAction:stop()
    F.lastReelEnd = "stopped"
    if not self.settled then
        self.settled = true
        if isClient() then
            sendClientCommand(self.character, "Fletcher", "reel", { x = self.x, y = self.y, strike = false })
        elseif not isServer() then
            F.reelInFor(self.character, { x = self.x, y = self.y, strike = false })
        end
    end
    ISBaseTimedAction.stop(self)
end

-- The outcome is decided where shots are resolved. Single player: complete(). Multiplayer: the
-- client's perform() sends "reel" and the server runs F.reelInFor (a timed action's server copy was
-- dropped now and then when the reel began right after a shot, so this doesn't rely on it).
function FletcherReelFishAction:perform()
    F.lastReelEnd = "performed"
    if isClient() and not self.settled then
        self.settled = true
        sendClientCommand(self.character, "Fletcher", "reel", { x = self.x, y = self.y, strike = self.strike })
    end
    ISBaseTimedAction.perform(self)
end

function FletcherReelFishAction:complete()
    if not isServer() and not isClient() and not self.settled then
        self.settled = true
        F.reelInFor(self.character, { x = self.x, y = self.y, strike = self.strike })
    end
    return true
end

--- Reel in for this character and tell them how it went (single player: said here; a server: sent)
function F.reelInFor(character, args)
    local out = F.reelIn(character, tonumber(args.x), tonumber(args.y), args.strike == true)
    local msg
    if out.caught then
        msg = "+1 " .. out.caught:getName()
    elseif out.escaped then
        msg = getText("IGUI_Fletcher_FishEscaped")
    elseif not out.arrowBack and out.reason == nil then
        msg = getText("IGUI_Fletcher_LineSnapped")
    end
    if msg then
        if isServer() then
            sendServerCommand(character, "Fletcher", "fishSay", { text = msg, caught = out.caught ~= nil })
        else
            if out.caught then character:playSound("PickUpFish") end
            character:Say(msg)
        end
    end
    return out
end

function FletcherReelFishAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return math.floor((self.strike and F.FISHING.reelStrikeSeconds or F.FISHING.reelMissSeconds) * 50 + 0.5)
end

return F
