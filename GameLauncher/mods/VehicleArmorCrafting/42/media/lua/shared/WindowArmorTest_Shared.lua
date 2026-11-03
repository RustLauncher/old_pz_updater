--[[
    Vehicle Armor Crafting - shared data and functions. Works in singleplayer and multiplayer.

    Two kinds of armor (WAT.KINDS):
      * glass - "Glass Armor": one kit = one window (windshield, rear window, door windows)
      * body  - "Body Armor": one plate = hood, trunk lid, van rear door
                or the cargo bed of a pickup

    WHERE THE DATA LIVES
    The armor state is stored in the modData of EACH VEHICLE PART:
        part:getModData().WindowArmorTest = {
            kind = "glass"|"body",
            condition = 0..100,
            glass = { cond = N, type = "Base.FrontWindow1" },  -- remembered state of the part
            covered = { TruckBed = { cond = N, type = ... } }, -- body only: shielded parts
        }
    This is done for multiplayer: the only way to push part data to the clients is
    vehicle:transmitPartModData(part), and it works from the server only. The old format
    (a single table in the vehicle modData) is migrated automatically - see WAT.migrateVehicle.

    WHO DOES WHAT
      * Singleplayer: the client calculates and changes everything itself (isClient() == false).
      * Multiplayer: the server owns the data. The client only asks
        (sendClientCommand "install"/"uninstall"), the server validates, changes the part modData
        and broadcasts it. Items are given/taken by the client on the server's command.
]]

WindowArmorTest = WindowArmorTest or {}
local WAT = WindowArmorTest

-- ================== SETTINGS ==================
WAT.ITEM_TYPE      = "WindowArmorTest.GlassArmorKit"
WAT.BODY_ITEM_TYPE = "WindowArmorTest.BodyArmorPlate"
WAT.NET            = "WindowArmorTest"  -- module name for sendClientCommand/sendServerCommand
WAT.PART_KEY       = "WindowArmorTest"  -- key inside the part modData
WAT.MODDATA_KEY    = "WindowArmorTest"  -- old key in the vehicle modData (migration only)
WAT.DATA_VERSION   = 3
WAT.INSTALL_TIME   = 150   -- how long installing/removing one armor piece takes (action ticks)
WAT.SCAN_RADIUS    = 20    -- radius around the player to look for vehicles
WAT.SCAN_EVERY     = 60    -- how often to scan (in ticks)
WAT.MAX_USE_DIST2  = 36    -- squared distance the server accepts an install from (6 tiles)
WAT.DEBUG          = true  -- write to console.txt
WAT.CRAFT_DEBUG    = false -- detailed crafting trace (wraps the vanilla action)

-- body parts that can take an armor plate
-- EngineDoor - hood, TrunkDoor - trunk lid, DoorRear - van rear doors
WAT.BODY_PARTS = { "EngineDoor", "TrunkDoor", "DoorRear" }
-- if there is no rear door at all (pickups) - put the plate on the cargo bed
WAT.BODY_PARTS_FALLBACK = { "TruckBedOpen", "TruckBed" }
-- parts hidden behind a plate: a rear hit damages both the lid and the trunk behind it,
-- so the plate on the lid shields the trunk too (the damage is charged to the plate)
WAT.BODY_COVERS = {
    TrunkDoor = { "TruckBed", "TruckBedOpen" },
    DoorRear  = { "TruckBed", "TruckBedOpen" },
}

WAT.KINDS = {
    glass = {
        item         = WAT.ITEM_TYPE,
        absorb       = 0.125, -- how many % of the armor is spent per 1 point of part damage
        menuKey      = "ContextMenu_WAT_Menu",
        installAll   = "ContextMenu_WAT_InstallAll",
        removeAll    = "ContextMenu_WAT_RemoveAll",
        noKitKey     = "IGUI_WAT_NoKit",
        noPartKey    = "IGUI_WAT_NoGlass",
    },
    body = {
        item         = WAT.BODY_ITEM_TYPE,
        absorb       = 0.0875,-- the plate is tougher: it wears down slower
        menuKey      = "ContextMenu_WAT_BodyMenu",
        installAll   = "ContextMenu_WAT_BodyInstallAll",
        removeAll    = "ContextMenu_WAT_BodyRemoveAll",
        noKitKey     = "IGUI_WAT_NoPlate",
        noPartKey    = "IGUI_WAT_NoBodyPart",
    },
}
WAT.KIND_ORDER = { "glass", "body" }
-- ===============================================

-- vehicles watched by the protection loop (key - the vehicle object)
WAT.tracked = WAT.tracked or {}

local FALLBACK = {
    ContextMenu_WAT_Menu           = "Glass Armor",
    ContextMenu_WAT_BodyMenu       = "Body Armor",
    ContextMenu_WAT_Install        = "Install",
    ContextMenu_WAT_Remove         = "Remove",
    ContextMenu_WAT_InstallAll     = "Install on all windows",
    ContextMenu_WAT_RemoveAll      = "Remove all armor",
    ContextMenu_WAT_BodyInstallAll = "Install on hood and trunk",
    ContextMenu_WAT_BodyRemoveAll  = "Remove body armor",
    Tooltip_WAT_Kit                = "One kit protects one window. Right click a vehicle from outside -> Glass Armor.",
    Tooltip_WAT_Plate              = "A steel plate for the hood or the trunk lid. Right click a vehicle from outside -> Body Armor.",
    IGUI_WAT_Status                = "Armor",
    IGUI_WAT_Installed             = "Armor installed",
    IGUI_WAT_Removed               = "Armor removed",
    IGUI_WAT_Broken                = "Armor destroyed",
    IGUI_WAT_SmashBlocked          = "The glass is covered by armor",
    IGUI_WAT_NoVehicle             = "No vehicle nearby",
    IGUI_WAT_TooFar                = "Move closer to the vehicle",
    IGUI_WAT_NoKit                 = "No glass armor kit",
    IGUI_WAT_NoGlass               = "Install the glass first",
    IGUI_WAT_NoPlate               = "No armor plate",
    IGUI_WAT_NoBodyPart            = "Install this part first",
    IGUI_WAT_RepairFirst           = "Repair first",
    IGUI_WAT_Busy                  = "Someone is already working on this part",
}

function WAT.text(key)
    local s = getTextOrNull and getTextOrNull(key) or nil
    if s == nil or s == key then
        s = FALLBACK[key] or key
    end
    return s
end

-- Part name taken from the vanilla translations ("Windshield", "Hood", "Trunk Lid", ...)
function WAT.partName(partId)
    local s = getTextOrNull and getTextOrNull("IGUI_VehiclePart" .. partId) or nil
    return s or partId
end

function WAT.log(...)
    if not WAT.DEBUG then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    print("[WindowArmorTest] " .. table.concat(parts, " "))
end

-- ================== SIDES ==================
-- true where the data may be changed directly: singleplayer and the server
function WAT.isAuthority()
    return not isClient()
end

-- true on a dedicated server (no local player, no rendering there)
function WAT.isDedicated()
    return isServer() and not isClient()
end

-- Armor kind by item type ("glass"/"body") or nil
function WAT.kindOfItem(fullType)
    for kind, def in pairs(WAT.KINDS) do
        if def.item == fullType then return kind end
    end
    return nil
end

function WAT.entryKind(entry)
    return (entry and entry.kind) or "glass"
end

function WAT.percent(entry)
    return math.floor((entry and entry.condition or 0) + 0.5)
end

-- ================== PART DATA ==================

-- The armor installed on a part, or nil
function WAT.getPartEntry(part)
    if not part or not part:hasModData() then return nil end
    local e = part:getModData()[WAT.PART_KEY]
    if type(e) ~= "table" then return nil end
    if type(e.condition) ~= "number" or e.condition <= 0 then return nil end
    return e
end

function WAT.getPartArmor(vehicle, partId)
    if not vehicle then return nil end
    return WAT.getPartEntry(vehicle:getPartById(partId))
end
WAT.getWindowArmor = WAT.getPartArmor

-- Broadcast the state of one part to the clients (server only)
function WAT.broadcastPart(vehicle, partId, entry)
    if not isServer() or not vehicle then return end
    sendServerCommand(WAT.NET, "part", {
        veh  = vehicle:getId(),
        part = partId,
        kind = entry and entry.kind or nil,
        cond = entry and entry.condition or nil,
    })
end

-- Write/clear the part data. transmit = broadcast to the clients (server only)
function WAT.setPartEntry(vehicle, part, entry, transmit)
    if not part then return end
    part:getModData()[WAT.PART_KEY] = entry
    if transmit ~= false and vehicle and isServer() then
        vehicle:transmitPartModData(part)
        WAT.broadcastPart(vehicle, part:getId(), entry)
    end
end

-- Every armored part of a vehicle: { { id = partId, part = part, entry = entry }, ... }
function WAT.armoredParts(vehicle)
    local out = {}
    if not vehicle then return out end
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        local e = WAT.getPartEntry(part)
        if e then out[#out + 1] = { id = part:getId(), part = part, entry = e } end
    end
    return out
end

function WAT.hasAnyArmor(vehicle)
    if not vehicle then return false end
    for i = 0, vehicle:getPartCount() - 1 do
        if WAT.getPartEntry(vehicle:getPartByIndex(i)) then return true end
    end
    return false
end

-- Migration of the old format (one table in the vehicle modData) into the part modData.
-- Called on the data owner side only.
function WAT.migrateVehicle(vehicle)
    if not vehicle or not vehicle:hasModData() then return end
    local md = vehicle:getModData()
    local old = md[WAT.MODDATA_KEY]
    if type(old) ~= "table" then return end
    local moved = 0
    if type(old.windows) == "table" then
        for partId, entry in pairs(old.windows) do
            local part = vehicle:getPartById(partId)
            if part and type(entry) == "table" and (entry.condition or 0) > 0 then
                entry.kind = entry.kind or "glass"
                WAT.setPartEntry(vehicle, part, entry)
                moved = moved + 1
            end
        end
    elseif type(old.condition) == "number" and old.condition > 0 then
        -- the very old format: one armor for the whole vehicle -> windshield
        local part = vehicle:getPartById("Windshield")
        if part then
            WAT.setPartEntry(vehicle, part, { kind = "glass", condition = old.condition })
            moved = moved + 1
        end
    end
    md[WAT.MODDATA_KEY] = nil
    WAT.log("armor entries migrated into part modData:", moved, vehicle:getScriptName())
end

-- ================== VEHICLE PARTS ==================

-- Ids of every vehicle part that has a window (works for modded vehicles too)
function WAT.getWindowPartIds(vehicle)
    local ids = {}
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if part and part:getWindow() then
            ids[#ids + 1] = part:getId()
        end
    end
    return ids
end

-- Vehicle parts that can take this kind of armor
function WAT.getPartIds(vehicle, kind)
    if kind == "body" then
        local ids, hasRear = {}, false
        for _, id in ipairs(WAT.BODY_PARTS) do
            if vehicle:getPartById(id) then
                ids[#ids + 1] = id
                if id ~= "EngineDoor" then hasRear = true end
            end
        end
        if not hasRear then                       -- pickup: no rear door, use the cargo bed
            for _, id in ipairs(WAT.BODY_PARTS_FALLBACK) do
                if vehicle:getPartById(id) then ids[#ids + 1] = id break end
            end
        end
        return ids
    end
    return WAT.getWindowPartIds(vehicle)
end

-- Ids of the parts shielded by the armor on partId (see WAT.BODY_COVERS).
-- A part that carries its own armor is protected by that armor, not by this one.
function WAT.coveredPartIds(vehicle, partId)
    local ids = {}
    for _, id in ipairs(WAT.BODY_COVERS[partId] or {}) do
        local p = vehicle:getPartById(id)
        if p and not WAT.getPartEntry(p) then ids[#ids + 1] = id end
    end
    return ids
end

-- The part is installed (for glass - and is actually a window)
function WAT.hasPartItem(vehicle, partId, kind)
    local part = vehicle:getPartById(partId)
    if not part or part:getInventoryItem() == nil then return false end
    if (kind or "glass") == "glass" then
        return part:getWindow() ~= nil
    end
    return true
end

-- Can armor of this kind go on partId? Returns true, or false and the text to show.
-- The part must be installed and not broken (0%); the same goes for the parts
-- the armor shields (a lid plate over a broken trunk would protect nothing).
function WAT.canInstallOn(vehicle, partId, kind)
    kind = kind or "glass"
    if not WAT.hasPartItem(vehicle, partId, kind) then
        return false, WAT.text(WAT.KINDS[kind].noPartKey)
    end
    local ids = { partId }
    if kind == "body" then
        for _, id in ipairs(WAT.coveredPartIds(vehicle, partId)) do ids[#ids + 1] = id end
    end
    for _, id in ipairs(ids) do
        local part = vehicle:getPartById(id)
        if part:getInventoryItem() and part:getCondition() <= 0 then
            return false, WAT.text("IGUI_WAT_RepairFirst") .. ": " .. WAT.partName(id)
        end
    end
    return true
end

function WAT.hasGlass(vehicle, partId)
    return WAT.hasPartItem(vehicle, partId, "glass")
end

-- ================== STATE CHANGES (data owner side) ==================

-- Install armor. condPct - kit condition 0..100. Returns entry or nil.
function WAT.applyInstall(vehicle, partId, kind, condPct)
    local part = vehicle and vehicle:getPartById(partId)
    if not part then return nil end
    if WAT.getPartEntry(part) then return nil end
    kind = kind or "glass"
    local entry = { kind = kind, condition = math.max(1, math.min(100, condPct or 100)) }
    local partItem = part:getInventoryItem()
    if partItem then
        entry.glass = { cond = part:getCondition(), type = partItem:getFullType() }
    end
    WAT.setPartEntry(vehicle, part, entry)
    WAT.tracked[vehicle] = true
    WAT.log("installed", kind, "on", vehicle:getScriptName(), partId, "condition", entry.condition)
    return entry
end

-- Remove armor. Returns (condition 0..100, kind) or nil.
function WAT.applyUninstall(vehicle, partId)
    local part = vehicle and vehicle:getPartById(partId)
    local entry = WAT.getPartEntry(part)
    if not entry then return nil end
    WAT.setPartEntry(vehicle, part, nil)
    if not WAT.hasAnyArmor(vehicle) then WAT.tracked[vehicle] = nil end
    WAT.log("armor removed", vehicle:getScriptName(), partId, "condition", entry.condition)
    return entry.condition, WAT.entryKind(entry)
end

-- kept for compatibility with the old names
function WAT.install(vehicle, partId, item, kind)
    local pct = 100
    if item and item:getConditionMax() > 0 then
        pct = math.floor(item:getCondition() / item:getConditionMax() * 100 + 0.5)
    end
    return WAT.applyInstall(vehicle, partId, kind or (item and WAT.kindOfItem(item:getFullType())) or "glass", pct)
end
WAT.uninstall = WAT.applyUninstall

-- ================== PLAYER SIDE REQUESTS ==================

-- Give the player a kit/plate of the given condition.
-- IMPORTANT: call it only where the data lives (server or singleplayer).
-- sendAddItemToContainer works ONLY on the server (the game code has if GameServer.server),
-- so an item created on the client is unknown to the server: it cannot be dropped,
-- it does not take part in server side actions and it disappears on relog.
function WAT.giveKit(character, kind, condPct)
    if not character then return nil end
    local def = WAT.KINDS[kind or "glass"] or WAT.KINDS.glass
    local inv = character:getInventory()
    local item = inv:AddItem(def.item)
    if item then
        if item:getConditionMax() > 0 then
            item:setCondition(math.max(1, math.floor((condPct or 100) / 100 * item:getConditionMax() + 0.5)))
        end
        sendAddItemToContainer(inv, item)   -- a no-op on the client, hence the server call
    end
    return item
end

-- NOTE: there are no install/uninstall requests from the client any more.
-- The timed action does the work in complete(), which the engine runs in singleplayer
-- and on the server; the clients get the result through transmitPartModData and
-- the "part" broadcast. A client that changes inventories or part data on its own
-- is treated as cheating by a dedicated server.

-- ================== MISC ==================

-- Walk over the vehicles near a character.
-- getCell():getVehicles() returns a Set in B42 - Lua cannot iterate it (no :get(i)),
-- so we walk the squares around the player the way vanilla code does.
function WAT.forEachNearbyVehicle(character, radius, fn, seen)
    if not character then return end
    local sq = character:getCurrentSquare()
    local cell = getCell()
    if not sq or not cell then return end
    local px, py, pz = sq:getX(), sq:getY(), sq:getZ()
    local r = radius or WAT.SCAN_RADIUS
    seen = seen or {}
    for dx = -r, r do
        for dy = -r, r do
            local s = cell:getGridSquare(px + dx, py + dy, pz)
            local v = s and s:getVehicleContainer()
            if v and not seen[v] then
                seen[v] = true
                fn(v)
            end
        end
    end
end

-- The nearest vehicle within radius tiles of the character
function WAT.findNearestVehicle(character, radius)
    local sq = character:getCurrentSquare()
    if not sq then return nil end
    local cell = getCell()
    local px, py, pz = sq:getX(), sq:getY(), sq:getZ()
    local best, bestDist = nil, nil
    for dx = -radius, radius do
        for dy = -radius, radius do
            local s = cell:getGridSquare(px + dx, py + dy, pz)
            local v = s and s:getVehicleContainer()
            if v then
                local ddx, ddy = v:getX() - character:getX(), v:getY() - character:getY()
                local dist = ddx * ddx + ddy * ddy
                if not bestDist or dist < bestDist then
                    best, bestDist = v, dist
                end
            end
        end
    end
    return best
end

function WAT.nearVehicle(character, vehicle)
    if not character or not vehicle then return false end
    local dx, dy = character:getX() - vehicle:getX(), character:getY() - vehicle:getY()
    return (dx * dx + dy * dy) <= WAT.MAX_USE_DIST2
end

-- Floating note above the player. From the server it is sent as a command to their client.
function WAT.halo(character, text, r, g, b)
    if not character then return end
    if WAT.isDedicated() then
        sendServerCommand(character, WAT.NET, "halo", { text = text, r = r or 255, g = g or 255, b = b or 255 })
        return
    end
    if character.setHaloNote then
        character:setHaloNote(text, r or 255, g or 255, b or 255, 300)
    end
end

-- Stub: no visuals on the server, the real version lives in WindowArmorTest_Visual.lua
if not WAT.updateVisual then
    function WAT.updateVisual() end
end

-- ================== DIAGNOSTICS ==================
-- What THIS side can see: item scripts, recipes and the player inventory.
WAT.CRAFT_INPUTS = {
    "Base.MetalPipe", "Base.SheetMetal", "Base.Screws",
    "Base.BlowTorch", "Base.Saw", "Base.SheetMetalSnips", "Base.WeldingMask",
}

-- Latin text on purpose: the game console writes Cyrillic in another encoding and it becomes unreadable
function WAT.diagText(character)
    local sm = getScriptManager()
    local side = isServer() and "SERVER" or (isClient() and "CLIENT" or "SINGLEPLAYER")
    local out = { "[" .. side .. "]" }
    local function yn(v) return v and "yes" or "NO" end
    out[#out + 1] = "item kit: " .. yn(sm and sm:getItem(WAT.ITEM_TYPE) ~= nil)
    out[#out + 1] = "item plate: " .. yn(sm and sm:getItem(WAT.BODY_ITEM_TYPE) ~= nil)
    local ok, made = pcall(instanceItem, WAT.ITEM_TYPE)
    out[#out + 1] = "instanceItem: " .. yn(ok and made ~= nil)
    if sm and sm.getCraftRecipe then
        out[#out + 1] = "recipe by name: " .. yn(sm:getCraftRecipe("WAT_MakeGlassArmorKit") ~= nil)
                        .. "/" .. yn(sm:getCraftRecipe("WAT_MakeBodyArmorPlate") ~= nil)
    end
    -- scan the whole list: shows under which names the recipes are actually registered
    if sm and sm.getAllCraftRecipes then
        local ok2, all = pcall(function() return sm:getAllCraftRecipes() end)
        if ok2 and all then
            local found, total = {}, all:size()
            for i = 0, total - 1 do
                local r = all:get(i)
                local n = r and r:getName() or ""
                if string.find(n, "WAT_", 1, true) then found[#found + 1] = n end
            end
            out[#out + 1] = "craft recipes total: " .. total .. ", ours: " ..
                (#found > 0 and table.concat(found, ",") or "NONE")
        end
    end
    if character then
        local inv = character:getInventory()
        local parts = {}
        parts[#parts + 1] = "kit x" .. inv:getAllTypeRecurse(WAT.ITEM_TYPE):size()
        parts[#parts + 1] = "plate x" .. inv:getAllTypeRecurse(WAT.BODY_ITEM_TYPE):size()
        for _, ft in ipairs(WAT.CRAFT_INPUTS) do
            local n = inv:getAllTypeRecurse(ft):size()
            if n > 0 then parts[#parts + 1] = ft .. " x" .. n end
        end
        out[#out + 1] = "inventory: " .. table.concat(parts, ", ")
    end
    return table.concat(out, " | ")
end

-- WindowArmorTest.diag() in the Lua console: prints the client state and asks for the server one
function WAT.diag()
    local p = getPlayer()
    print("[WindowArmorTest] " .. WAT.diagText(p))
    if isClient() and p then
        sendClientCommand(p, WAT.NET, "diag", {})
        print("[WindowArmorTest] server check requested...")
    end
end

local function giveItems(fullType, count)
    local player = getPlayer()
    if not player then return end
    count = count or 1
    if isClient() then
        -- In multiplayer the item must be created by the SERVER, otherwise only the client has it
        -- (and it can neither be dropped nor used by server side actions).
        -- /additem is an admin command - the vanilla admin panel spawns items the same way.
        for _ = 1, count do
            SendCommandToServer('/additem "' .. player:getUsername() .. '" "' .. fullType .. '"')
        end
        WAT.log("requested from the server:", count, fullType)
        return
    end
    for _ = 1, count do
        player:getInventory():AddItem(fullType)
    end
    WAT.log("given", count, fullType)
end

-- Give everything needed to craft both armor kinds, through the server (for MP testing).
-- Note: items created on the client (inventory:AddItem / AddItems) are unknown to the server -
-- they cannot be dropped and crafting does not work with them, because the server runs the recipe.
WAT.CRAFT_KIT = {
    { "Base.MetalPipe", 2 }, { "Base.SheetMetal", 4 }, { "Base.Screws", 8 },
    { "Base.BlowTorch", 2 }, { "Base.Saw", 1 }, { "Base.BallPeenHammerForged", 1 },
    { "Base.WeldingMask", 1 },
}

function WAT.giveInputs()                                   -- WindowArmorTest.giveInputs()
    for _, e in ipairs(WAT.CRAFT_KIT) do giveItems(e[1], e[2]) end
end

-- Debug console helpers
function WAT.give(count) giveItems(WAT.ITEM_TYPE, count) end          -- WindowArmorTest.give(6)
function WAT.giveBody(count) giveItems(WAT.BODY_ITEM_TYPE, count) end -- WindowArmorTest.giveBody(2)
