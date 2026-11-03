--[[
    Vehicle Armor Crafting - the protection itself (windows, hood, trunk, rear doors).

    Vanilla code (VehicleWindow.damage) lowers the glass condition on every hit and
    removes the glass from the vehicle at 0. That call cannot be hooked from Lua, so:
      1) every tick we compare the condition of armored parts with the remembered one;
         if it dropped - restore it and charge the damage to THAT part's armor;
      2) if the glass was smashed by a single strong hit (gone, condition = 0) -
         put an identical window back (the shards on the ground stay there).
    The hood and the trunk lid work the same way: while the plate holds, their condition stays.
    A plate on the trunk lid / rear doors also shields the trunk behind it (WAT.BODY_COVERS).
    Parts without armor break as usual.

    This file runs in singleplayer and ON THE SERVER in multiplayer (the client never gets here).
    All changes reach the clients through vehicle:transmitPartModData / transmitPartCondition.
]]
require "WindowArmorTest_Shared"
require "WindowArmorTest_Visual"

if isClient() then return end -- in multiplayer the protection is calculated on the server only

local WAT = WindowArmorTest
local tickCounter = 0

-- All players: the online list in multiplayer, the local ones in singleplayer
local function eachPlayer(fn)
    if isServer() then
        local players = getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do
                local p = players:get(i)
                if p then fn(p) end
            end
        end
        return
    end
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p then fn(p) end
    end
end

local function nearestPlayer(vehicle, maxDist)
    local best, bestDist = nil, maxDist * maxDist
    eachPlayer(function(p)
        if not p:isDead() then
            local dx, dy = p:getX() - vehicle:getX(), p:getY() - vehicle:getY()
            local d = dx * dx + dy * dy
            if d <= bestDist then best, bestDist = p, d end
        end
    end)
    return best
end

-- Only the "armor destroyed" message is shown. There is deliberately no message
-- while the armor is merely taking damage: it would pop up on every hit.
-- The remaining condition is visible in the vehicle menu instead.
local function notifyDestroyed(vehicle, partId)
    local p = nearestPlayer(vehicle, 20)
    if not p then return end
    WAT.halo(p, WAT.text("IGUI_WAT_Broken") .. ": " .. WAT.partName(partId), 255, 80, 80)
end

-- Protect a single part. Returns the absorbed damage.
-- The remembered state is holder[key]; holder lives in the modData of owner
-- (the armored part itself, or the plate that shields this part).
-- canRestore - put the part back if a single hit removed it (smashed glass).
local function protectPart(vehicle, part, owner, holder, key, canRestore)
    local item = part:getInventoryItem()
    local cond = part:getCondition()
    local saved = holder[key]

    if item then
        if saved and cond < saved.cond then
            -- the part took damage -> restore its condition
            part:setCondition(saved.cond)
            if isServer() then vehicle:transmitPartCondition(part) end
            WAT.log("absorbed", saved.cond - cond, "on", part:getId())
            return saved.cond - cond
        elseif (not saved) or saved.cond ~= cond or saved.type ~= item:getFullType() then
            -- the part was installed / repaired -> remember the new state
            holder[key] = { cond = cond, type = item:getFullType() }
            if isServer() then vehicle:transmitPartModData(owner) end
        end
    elseif saved then
        if canRestore and cond <= 0 and saved.cond > 0 then
            -- the glass was smashed in one hit -> put an identical one back
            local newItem = instanceItem(saved.type)
            if newItem then
                part:setInventoryItem(newItem)
                part:setCondition(saved.cond)
                if isServer() then
                    vehicle:transmitPartItem(part)
                    vehicle:transmitPartCondition(part)
                end
                WAT.log("restored smashed", part:getId(), "->", saved.type, saved.cond)
                return saved.cond
            end
        end
        -- the part was removed through mechanics (or could not be restored) -> just forget it
        holder[key] = nil
        if isServer() then vehicle:transmitPartModData(owner) end
    end
    return 0
end

-- Protect the parts hidden behind a body plate (the trunk behind the lid).
-- Returns the absorbed damage.
local function protectCovered(vehicle, rec)
    local entry = rec.entry
    if WAT.entryKind(entry) ~= "body" then return 0 end
    local ids = WAT.coveredPartIds(vehicle, rec.id)
    if #ids == 0 and not entry.covered then return 0 end
    entry.covered = entry.covered or {}

    -- forget parts that are no longer shielded (got their own armor)
    local keep = {}
    for _, id in ipairs(ids) do keep[id] = true end
    for id in pairs(entry.covered) do
        if not keep[id] then entry.covered[id] = nil end
    end

    local total = 0
    for _, id in ipairs(ids) do
        total = total + protectPart(vehicle, vehicle:getPartById(id), rec.part, entry.covered, id, false)
    end
    return total
end

local function protectVehicle(vehicle)
    if vehicle:getMovingObjectIndex() < 0 then       -- the vehicle is unloaded
        WAT.tracked[vehicle] = nil
        WAT.forgetVisual(vehicle)
        return
    end

    local list = WAT.armoredParts(vehicle)
    if #list == 0 then
        WAT.tracked[vehicle] = nil
        WAT.updateVisual(vehicle)
        return
    end

    for _, rec in ipairs(list) do
        local entry = rec.entry
        local absorbed = protectPart(vehicle, rec.part, rec.part, entry, "glass", true)
                       + protectCovered(vehicle, rec)
        if absorbed > 0 then
            local def = WAT.KINDS[WAT.entryKind(entry)] or WAT.KINDS.glass
            entry.condition = math.max(0, (entry.condition or 0) - absorbed * def.absorb)
            WAT.log("armor", rec.id, "condition", entry.condition)
            if entry.condition <= 0 then
                WAT.setPartEntry(vehicle, rec.part, nil)
                WAT.updateVisual(vehicle)
                WAT.log("armor destroyed", vehicle:getScriptName(), rec.id)
                notifyDestroyed(vehicle, rec.id)
            else
                if isServer() then
                    vehicle:transmitPartModData(rec.part)
                    WAT.broadcastPart(vehicle, rec.id, entry)   -- clients see the new condition
                end
            end
        end
    end

    if not WAT.hasAnyArmor(vehicle) then
        WAT.tracked[vehicle] = nil
        WAT.updateVisual(vehicle)
    end
end

-- Find armored vehicles near the players.
-- getCell():getVehicles() returns a Set which Lua cannot iterate, so we walk the squares.
local function rescan()
    local seen = {}
    local function look(v)
        if WAT.tracked[v] then return end
        WAT.migrateVehicle(v)
        if WAT.hasAnyArmor(v) then
            WAT.tracked[v] = true
                WAT.log("now watching:", v:getScriptName())
        end
    end
    eachPlayer(function(p)
        WAT.forEachNearbyVehicle(p, WAT.SCAN_RADIUS, look, seen)
        local inside = p:getVehicle()
        if inside and not seen[inside] then
            seen[inside] = true
            look(inside)
        end
    end)
end

local function onTick()
    tickCounter = tickCounter + 1

    if (tickCounter % WAT.SCAN_EVERY) == 0 then
        local ok, err = pcall(rescan)
        if not ok then WAT.log("vehicle scan error:", err) end
    end

    -- a copy of the list, because protectVehicle may remove entries
    local list = {}
    for v in pairs(WAT.tracked) do list[#list + 1] = v end
    for _, v in ipairs(list) do
        local ok, err = pcall(protectVehicle, v)
        if not ok then WAT.log("protection error:", err) end
    end
end

Events.OnTick.Add(onTick)
WAT.log("protection loaded (" .. (isServer() and "server" or "singleplayer") .. ")")
