--[[
    Fletcher: arrows that stay stuck in zombies (single player). The arrow is the real arrow item,
    attached to the zombie like vanilla's "knife in the back" (AttachedWeaponDefinitions): it shows
    on the body as the zombie moves, and when the zombie dies vanilla keeps it on the corpse AND puts
    it in the corpse's container, so it's looted like anything else.

    Attachment points: vanilla's body attachments are on the FemaleBody / MaleBody model scripts;
    F.STUCK_POINTS adds ours at runtime (ModelAttachment, every load: they aren't in a script) and a
    Human-group location per point ("Fletcher <id>"). One arrow per point: a hit takes the free point
    nearest where it struck (height: head / chest / belly / legs; side: front / back from the zombie's
    facing, left / right for a hit from the side); none free -> md.fl_arrows (shared/Fletcher/Shots.lua).
    The arrow models run +Z from their nock (pivot): a point's offset puts the nock outside the body
    and its rotation turns +Z inward. Offsets are in the bone's space (spine bones: +X up the spine,
    +Z out the front, like vanilla's knife_stomach / knife_in_back).

    Living zombies aren't saved (a reloaded zombie has no mod data or attached items), so stuck arrows
    are also kept in global mod data by the zombie's persistent outfit id and put back when a zombie
    with that id is loaded (F.restoreStuckScan). A zombie the game hasn't saved yet has a temporary id
    that changes when it is (seen: a debug-spawned zombie came back on the same spot with a new id), so
    each record also follows its zombie's position (every scan) and a loaded zombie within
    F.STUCK_MATCH_TILES of a record's spot takes it over. The game also REUSES temporary ids, so an id
    match only counts within F.STUCK_ID_TILES of the record's spot, and a zombie's first arrow always
    starts a new record. Records go when the zombie dies, and after F.STUCK_KEEP_HOURS of game time.
]]

require "Fletcher/Core"
require "Fletcher/Gear"
local F = Fletcher

-- id, bone, offset (nock), rotate (degrees), zone, side. Calibrated in game (2026-10-05) by attaching
-- each alone to a pinned zombie seen front / profile (the white FlightStreak model shows the axis):
-- spine bones +Z = out the front; the head's front points tilted down (240 about Y sticks straight out
-- of the face); upper arms: +Y out of the left arm's side (rot X 90), -Y for the mirrored right one.
F.STUCK_POINTS = {
    { id = "fl_arrow_head_f", bone = "Bip01_Head", off = { 0.31, 0.0, 0.17 }, rot = { 0, 240, 0 }, zone = "head", side = "front" },
    { id = "fl_arrow_head_b", bone = "Bip01_Head", off = { 0.08, 0.0, -0.34 }, rot = { 0, 0, 0 }, zone = "head", side = "back" },
    { id = "fl_arrow_chest_f", bone = "Bip01_Spine1", off = { 0.10, 0.0, 0.40 }, rot = { 0, 180, 0 }, zone = "chest", side = "front" },
    { id = "fl_arrow_chest_b", bone = "Bip01_Spine1", off = { 0.10, 0.0, -0.40 }, rot = { 0, 0, 0 }, zone = "chest", side = "back" },
    { id = "fl_arrow_belly_f", bone = "Bip01_Spine", off = { 0.05, 0.03, 0.40 }, rot = { 0, 180, 0 }, zone = "belly", side = "front" },
    { id = "fl_arrow_belly_b", bone = "Bip01_Spine", off = { 0.05, -0.03, -0.40 }, rot = { 0, 0, 0 }, zone = "belly", side = "back" },
    { id = "fl_arrow_arm_l", bone = "Bip01_L_UpperArm", off = { 0.12, 0.33, 0.0 }, rot = { 90, 0, 0 }, zone = "chest", side = "left" },
    { id = "fl_arrow_arm_r", bone = "Bip01_R_UpperArm", off = { 0.12, -0.33, 0.0 }, rot = { -90, 0, 0 }, zone = "chest", side = "right" },
    { id = "fl_arrow_thigh_l", bone = "Bip01_L_Thigh", off = { 0.15, 0.0, 0.36 }, rot = { 0, 180, 0 }, zone = "legs", side = "left" },
    { id = "fl_arrow_thigh_r", bone = "Bip01_R_Thigh", off = { 0.15, 0.0, 0.36 }, rot = { 0, 180, 0 }, zone = "legs", side = "right" },
}
F.STUCK_BODIES = { "FemaleBody", "MaleBody" }
F.STUCK_KEEP_HOURS = 24 * 14
F.STUCK_MATCH_TILES = 0.6     -- a record with no id match: its zombie stood this close
F.STUCK_ID_TILES = 4.0        -- an id match farther from the record's spot than this: someone else
F.STUCK_MODDATA = "FletcherStuck"

function F.stuckLocation(point) return "Fletcher " .. point.id end

--- Our attachment points on the body models and their locations (idempotent: offsets / rotations
--- are set again, so a reload of this file applies new numbers)
function F.registerStuckPoints()
    local sm = getScriptManager()
    for _, body in ipairs(F.STUCK_BODIES) do
        local ms = sm:getModelScript(body)
        if ms then
            for _, p in ipairs(F.STUCK_POINTS) do
                local a = ms:getAttachmentById(p.id)
                if not a then
                    a = ModelAttachment.new(p.id)
                    ms:addAttachment(a)
                end
                a:setBone(p.bone)
                a:getOffset():set(p.off[1], p.off[2], p.off[3])
                a:getRotate():set(p.rot[1], p.rot[2], p.rot[3])
            end
        end
    end
    local group = AttachedLocations.getGroup("Human")
    for _, p in ipairs(F.STUCK_POINTS) do
        group:getOrCreateLocation(F.stuckLocation(p)):setAttachmentName(p.id)
    end
    F.stuckRegistered = true
end

--- Where on the body a hit at height h (metres) lands
function F.stuckZone(h)
    if h >= 1.45 then return "head" end
    if h >= 1.1 then return "chest" end
    if h >= 0.7 then return "belly" end
    return "legs"
end

--- Which side of the zombie the arrow struck: front / back (along its facing), or left / right
function F.stuckSide(zombie, dx, dy, shooter)
    local f = zombie:getForwardDirection()
    local fx, fy = f:getX(), f:getY()
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 1e-6 then return "front" end
    local along = (dx * fx + dy * fy) / l           -- > 0: the arrow travels the way the zombie faces
    if along > 0.4 then return "back" end
    if along < -0.4 then return "front" end
    -- from the side: the side facing where the arrow came from (right = (-fy, fx), x east, y south)
    local rx, ry = -fy, fx
    return (-(dx * rx + dy * ry)) > 0 and "right" or "left"
end

--- Free points for a hit, best first
function F.stuckCandidates(zombie, zone, side)
    local out, seen = {}, {}
    local function add(p)
        if not seen[p.id] and not zombie:getAttachedItem(F.stuckLocation(p)) then seen[p.id] = true; table.insert(out, p) end
    end
    local lateral = side == "left" or side == "right"
    for _, p in ipairs(F.STUCK_POINTS) do if p.zone == zone and p.side == side then add(p) end end
    if zone == "legs" and not lateral then
        for _, p in ipairs(F.STUCK_POINTS) do if p.zone == "legs" then add(p) end end
    end
    if lateral then
        for _, p in ipairs(F.STUCK_POINTS) do if p.side == side then add(p) end end
        for _, p in ipairs(F.STUCK_POINTS) do if p.zone == zone then add(p) end end
    end
    for _, p in ipairs(F.STUCK_POINTS) do if p.zone == zone then add(p) end end
    for _, p in ipairs(F.STUCK_POINTS) do if p.side == side then add(p) end end
    return out
end

-- the save's record of arrows stuck in living zombies, by persistent outfit id
local function registry()
    local md = ModData.getOrCreate(F.STUCK_MODDATA)
    md.zombies = md.zombies or {}
    return md.zombies
end

local function worldHours() return getGameTime():getWorldAgeHours() end

--- Stick an arrow in a zombie (living, or killed by this arrow). False when there's no free point.
--- Single player, or the server (multiplayer: its copy carries the arrow into the corpse; every
--- client is told to show it, client/Fletcher/NetFlight.lua). Never on a multiplayer client.
function F.stickInZombie(zombie, arrowType, h, dx, dy, shooter, fl)
    if isClient() then return false end
    if not F.stuckRegistered then F.registerStuckPoints() end
    local zone = F.stuckZone(h or 1.2)
    local side = F.stuckSide(zombie, dx or 0, dy or 0, shooter)
    local p = F.stuckCandidates(zombie, zone, side)[1]
    if not p then return false end
    local item = F.setFletch(instanceItem(arrowType), fl)
    if not item then return false end
    zombie:setAttachedItem(F.stuckLocation(p), item)
    F.lastStuck = { point = p.id, zone = zone, side = side, loc = F.stuckLocation(p), arrow = arrowType, fl = fl }
    if isServer() then
        sendServerCommand("Fletcher", "stuck", { id = zombie:getOnlineID(), loc = F.stuckLocation(p), arrow = arrowType, fl = fl })
    end
    if not zombie:isDead() then
        local md = zombie:getModData()
        local reg = registry()
        local key = md.fl_stuckKey or tostring(zombie:getPersistentOutfitID())
        -- this zombie's first arrow starts a new record (an old one under the same id was another
        -- zombie's: the game reuses temporary outfit ids)
        local e = md.fl_stuckKey and reg[key] or { arrows = {} }
        table.insert(e.arrows, { loc = F.stuckLocation(p), type = arrowType, fl = fl })
        e.t, e.x, e.y, e.z = worldHours(), zombie:getX(), zombie:getY(), math.floor(zombie:getZ())
        reg[key] = e
        md.fl_stuckKey, md.fl_stuckChecked = key, true
    end
    return true
end

--- Show an arrow ITEM (already in the player's inventory) stuck in a player where it hit: a free
--- point by height and side, like a zombie's. The player's own client (or single player) does it:
--- a player's attached items are its own and sync from there. Returns the location, or nil.
function F.stickInPlayer(player, item, h, dx, dy)
    if not (player and item) then return nil end
    if not F.stuckRegistered then pcall(F.registerStuckPoints) end
    local p = F.stuckCandidates(player, F.stuckZone(h or 1.2), F.stuckSide(player, dx or 0, dy or 0))[1]
    if not p then return nil end
    player:setAttachedItem(F.stuckLocation(p), item)
    F.lastPlayerStuck = { loc = F.stuckLocation(p), arrow = item:getFullType() }
    return F.stuckLocation(p)
end

--- A zombie with a recorded outfit id (or on a recorded spot) was loaded: its arrows back on it
--- (looked at once per zombie object)
function F.restoreStuck(zombie)
    local md = zombie:getModData()
    if md.fl_stuckChecked then return false end
    md.fl_stuckChecked = true
    local reg = registry()
    local key = tostring(zombie:getPersistentOutfitID())
    local zx, zy = zombie:getX(), zombie:getY()
    local e = reg[key]
    -- the same id far from where the record's zombie was: a reused id, not that zombie
    if e and e.x and IsoUtils.DistanceTo(e.x, e.y, zx, zy) > F.STUCK_ID_TILES then e = nil end
    if e and e.claimed then e = nil end
    if not e then
        -- its id changed when the game saved it: the record whose zombie stood here
        local zz = math.floor(zombie:getZ())
        for k, r in pairs(reg) do
            if r.x and r.z == zz and not r.claimed and IsoUtils.DistanceTo(r.x, r.y, zx, zy) <= F.STUCK_MATCH_TILES then
                e = r
                reg[k] = nil
                reg[key] = r
                break
            end
        end
    end
    if not e then return false end
    e.claimed = true                  -- (this session: one zombie per record)
    md.fl_stuckKey = key
    local n = 0
    for _, a in ipairs(e.arrows) do
        if not zombie:getAttachedItem(a.loc) then
            local item = F.setFletch(instanceItem(a.type), a.fl)
            if item then
                zombie:setAttachedItem(a.loc, item); n = n + 1
                if isServer() then sendServerCommand("Fletcher", "stuck", { id = zombie:getOnlineID(), loc = a.loc, arrow = a.type, fl = a.fl }) end
            end
        end
    end
    return n > 0
end

--- Every so often: zombies loaded since the last look get their recorded arrows back
F.RESTORE_EVERY_MS = 1000
function F.restoreStuckScan()
    if isClient() then return end
    local now = getTimestampMs()
    if F.lastRestoreScan and now - F.lastRestoreScan < F.RESTORE_EVERY_MS and now >= F.lastRestoreScan then return end
    F.lastRestoreScan = now
    local list = getCell() and getCell():getZombieList()
    local reg
    for i = 0, (list and list:size() or 0) - 1 do
        local z = list:get(i)
        if not z:isDead() then
            F.restoreStuck(z)
            local key = z:getModData().fl_stuckKey
            if key then                                   -- the record follows its zombie
                reg = reg or registry()
                local e = reg[key]
                if e then e.x, e.y, e.z = z:getX(), z:getY(), math.floor(z:getZ()) end
            end
        end
    end
end

--- Dead: its arrows are in the corpse now (vanilla), the record goes
function F.forgetStuck(zombie)
    if isClient() or not zombie then return end
    local reg = registry()
    reg[zombie:getModData().fl_stuckKey or tostring(zombie:getPersistentOutfitID())] = nil
end

--- Old records (zombies that never came back) go
function F.pruneStuck()
    local reg, now = registry(), worldHours()
    for k, e in pairs(reg) do
        e.claimed = nil
        if not e.t or now - e.t > F.STUCK_KEEP_HOURS then reg[k] = nil end
    end
end

pcall(F.registerStuckPoints)
Events.OnGameBoot.Add(function() pcall(F.registerStuckPoints) end)
Events.OnGameStart.Add(function() pcall(F.registerStuckPoints); pcall(F.pruneStuck) end)
Events.OnTick.Add(function() F.restoreStuckScan() end)
Events.OnZombieDead.Add(function(z) F.forgetStuck(z) end)

return F
