--[[
    Crossbow tripwire trap (single player, and the server in multiplayer: shared so the server runs it;
    the menu and the kneel are client/Fletcher/Trap.lua). Right-click a loaded crossbow with twine, wire or fishing
    line in the inventory: "Set Tripwire Trap". The character kneels and sets it down facing where they
    face, the wire run out ahead. A zombie that walks into the wire line (F.TRAP.range tiles ahead,
    nothing solid in between) looses the bolt at it as a real flying shot (Flight.lua F.launchFrom),
    with a twang; the crossbow is left uncocked. Pick it up, reload it and set it again.

    The trap is the crossbow lying in the world with md.fl_trap = { yaw (degrees, world angle of the
    line), armed, level (the setter's Archery), key }; the squares holding one are listed in ModData
    F.TRAP_MODDATA (saved), and checked every F.TRAP.every ticks. A square whose crossbow is gone (picked
    up) drops out of the list.
]]
require "TimedActions/ISBaseTimedAction"
require "Fletcher/Core"
require "Fletcher/Gear"
require "Fletcher/Projectile"
local F = Fletcher

F.TRAP = {
    range = 5,          -- tiles of wire ahead
    width = 0.45,       -- tiles either side of the line that trip it
    minAlong = 0.6,     -- (not its own square's edge)
    aimH = 1.0,         -- the bolt's aim on a standing zombie (a crawler: crawlH)
    crawlH = 0.25,
    releaseH = 0.5,     -- the crossbow sits low
    noise = 8,          -- the twang (radius = volume)
    every = 6,          -- ticks between checks
    seconds = 4,        -- setting it
}
F.TRAP_MODDATA = "FletcherTraps"
F.TRAP_WIRES = { "Base.Twine", "Base.Wire", "Base.FishingLine" }

local function registry()
    local md = ModData.getOrCreate(F.TRAP_MODDATA)
    md.traps = md.traps or {}
    return md.traps
end
local function keyOf(x, y, z) return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z) end

function F.isCrossbow(item)
    local def = item and F.bowDef(item)
    return def ~= nil and def.kind == "crossbow"
end

--- The wire a character would use (twine / wire / fishing line), or nil
function F.trapWire(character)
    local inv = character:getInventory()
    for _, t in ipairs(F.TRAP_WIRES) do
        local it = inv:getFirstTypeRecurse(t)
        if it then return it end
    end
end

local function useUp(item)
    if item.getCurrentUses and item:getCurrentUses() > 1 then
        if isServer() and item.UseAndSync then item:UseAndSync() else item:Use() end
        return
    end
    local c = item:getContainer()
    if c then
        c:DoRemoveItem(item)
        if isServer() then sendRemoveItemFromContainer(c, item) end
    end
end

--- Set the trap: the loaded crossbow goes down on the character's square (or x, y, z) with its wire
--- line along yawDeg (default: where the character faces). Uses one wire. Returns the world item.
function F.setTrap(character, bow, yawDeg, x, y, z)
    if not (F.isCrossbow(bow) and bow:isRoundChambered()) then return nil end
    if not yawDeg then
        local f = character:getForwardDirection()
        yawDeg = math.deg(math.atan2(f:getY(), f:getX()))
    end
    x, y, z = x or character:getX(), y or character:getY(), z or character:getZ()
    local sq = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    if not sq then return nil end
    local wire = F.trapWire(character)
    if wire then useUp(wire) end
    if character:getPrimaryHandItem() == bow or character:getSecondaryHandItem() == bow then
        character:removeFromHands(bow)
        if isServer() then sendEquip(character) end
    end
    local c = bow:getContainer()
    if c then
        c:DoRemoveItem(bow)
        if isServer() then sendRemoveItemFromContainer(c, bow) end
    end
    local md = bow:getModData()
    local key = keyOf(x, y, z)
    md.fl_nocked = md.fl_nocked or F.bowArrow(bow)
    md.fl_trap = { yaw = yawDeg, armed = true, level = F.level(character), key = key }
    -- turned BEFORE it goes down: a server sends the item as it is when added (a turn set after
    -- never reaches the clients)
    bow:setWorldZRotation(yawDeg + 90)                    -- (the model runs along +Z, like the arrows)
    local item = sq:AddWorldInventoryItem(bow, x - sq:getX(), y - sq:getY(), 0)
    registry()[key] = true
    return item
end

--- The armed trap's world object on a square, or nil
local function armedOn(sq)
    local w = sq:getWorldObjects()
    for i = 0, w:size() - 1 do
        local wo = w:get(i)
        local it = wo:getItem()
        local t = it and it:getModData().fl_trap
        if t and t.armed and F.isCrossbow(it) and it:isRoundChambered() then return wo, it, t end
    end
end

--- Nothing solid between two points on one floor (walls, doors, fences: anything F.edgeAt stops)
function F.lineClear(x0, y0, x1, y1, z)
    local cell = getCell()
    local n = math.max(1, math.ceil(math.max(math.abs(x1 - x0), math.abs(y1 - y0)) * 4))
    local prev = cell:getGridSquare(math.floor(x0), math.floor(y0), z)
    for i = 1, n do
        local t = i / n
        local sq = cell:getGridSquare(math.floor(x0 + (x1 - x0) * t), math.floor(y0 + (y1 - y0) * t), z)
        if not sq or not prev then return false end
        if sq ~= prev then
            if F.edgeAt(prev, sq, F.TRAP.releaseH) then return false end
            prev = sq
        end
    end
    return true
end

--- The zombie in the trap's wire line, nearest the crossbow, or nil
function F.trapVictim(ox, oy, z, yawDeg)
    local a = math.rad(yawDeg)
    local dx, dy = math.cos(a), math.sin(a)
    local best, bestAlong
    local zl = getCell():getZombieList()
    for i = 0, zl:size() - 1 do
        local zb = zl:get(i)
        if not zb:isDead() and math.floor(zb:getZ()) == z then
            local rx, ry = zb:getX() - ox, zb:getY() - oy
            local along = rx * dx + ry * dy
            if along >= F.TRAP.minAlong and along <= F.TRAP.range and math.abs(rx * dy - ry * dx) <= F.TRAP.width
                    and (not bestAlong or along < bestAlong) and F.lineClear(ox, oy, zb:getX(), zb:getY(), z) then
                best, bestAlong = zb, along
            end
        end
    end
    return best
end

--- Loose the trap's bolt at the zombie: the crossbow left uncocked. Returns the flight.
function F.trapFire(wo, item, t, zombie)
    local sq = wo:getSquare()
    local ox, oy, z = sq:getX() + wo:getOffX(), sq:getY() + wo:getOffY(), sq:getZ()
    local md = item:getModData()
    local bolt = md.fl_nocked or F.bowArrow(item) or "Fletcher.WoodenBolt"
    local fl = md.fl_nockedFletch
    item:setRoundChambered(false)
    if item:getCurrentAmmoCount() > 0 then item:setCurrentAmmoCount(0) end
    md.fl_nocked, md.fl_nockedFletch = nil, nil
    t.armed = false
    addSound(nil, math.floor(ox), math.floor(oy), z, F.TRAP.noise, F.TRAP.noise)
    local crawling = zombie:isCrawling() or zombie:isProne()
    F.lastTrapShot = { zombie = zombie, bolt = bolt }
    local opt = { shooter = (not isServer()) and getPlayer() or nil, bow = item, arrow = bolt, fl = fl, from = { x = ox, y = oy, z = z },
                  tx = zombie:getX(), ty = zombie:getY(), aimH = crawling and F.TRAP.crawlH or F.TRAP.aimH,
                  level = t.level or 0, noSpread = true, releaseH = F.TRAP.releaseH, noXp = true, trap = true }
    if isServer() then
        -- the crossbow's state changed on the server's copy: every client gets it
        if wo.transmitCompleteItemToClients then pcall(function() wo:transmitCompleteItemToClients() end) end
        local ok, r = pcall(F.serverLaunch, opt)
        if not ok then F.lastTrapError = tostring(r); print("[Fletcher] trap shot: " .. tostring(r)) end
        return ok and r or nil
    end
    return F.launchFrom(opt)
end

--- Check every listed trap (loaded squares only); fire the ones tripped. Returns how many fired.
function F.trapTick()
    if isClient() or (not isServer() and not getPlayer()) then return 0 end
    local fired = 0
    local list = registry()
    for key, _ in pairs(list) do
        local x, y, z = key:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
        local sq = x and getCell():getGridSquare(tonumber(x), tonumber(y), tonumber(z))
        if not x then
            list[key] = nil
        elseif sq then                                       -- (unloaded: left for later)
            local wo, item, t = armedOn(sq)
            if not wo then
                list[key] = nil                              -- picked up, or already sprung
            else
                local victim = F.trapVictim(sq:getX() + wo:getOffX(), sq:getY() + wo:getOffY(), sq:getZ(), t.yaw)
                if victim then
                    F.trapFire(wo, item, t, victim)
                    list[key] = nil
                    fired = fired + 1
                end
            end
        end
    end
    return fired
end

local tick = 0
Events.OnTick.Add(function()
    tick = tick + 1
    if tick % F.TRAP.every == 0 then F.trapTick() end
end)

-- setting it: kneel, then put it down. Shared, with the work in complete(): in multiplayer the server
-- builds its own copy of the action from this class and runs complete() (single player runs it here).
FletcherSetTrapAction = ISBaseTimedAction:derive("FletcherSetTrapAction")

function FletcherSetTrapAction:new(character, bow)
    local o = ISBaseTimedAction.new(self, character)
    o.bow = bow
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

function FletcherSetTrapAction:isValid()
    local inv = self.character:getInventory()
    local has = isClient() and inv:containsID(self.bow:getID()) or inv:containsRecursive(self.bow)
    return has and self.bow:isRoundChambered() and F.trapWire(self.character) ~= nil
end

function FletcherSetTrapAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

function FletcherSetTrapAction:perform()
    ISBaseTimedAction.perform(self)
end

function FletcherSetTrapAction:complete()
    F.lastTrapSet = F.setTrap(self.character, self.bow)
    return true
end

function FletcherSetTrapAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return F.TRAP.seconds * 50
end

return F
