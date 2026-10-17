-- ============================================================================
-- HalloweenEvent_Server.lua
-- Build 42.21+ server-authoritative event and costume system.
-- World conversions dress the existing zombie. Only the gallery creates zombies.
-- ============================================================================

require "HalloweenEvent/HalloweenEvent_Shared"
local Announcement = require "HalloweenEvent/HalloweenEvent_AnnouncementServer"
local ScheduleControl = require "HalloweenEvent/HalloweenEvent_ScheduleControl"
local RewardItems = require "HalloweenEvent/EVHalloween_Items"
local ItemLoot = require "HalloweenEvent/EVHalloween_ItemLoot"
-- EXPERIMENTAL NATIVE OUTFIT BRANCH. v16 is the preserved rollback point.
-- Preserve the entire wardrobe code and existing saved records unchanged, but
-- disable every record lookup, write, death removal and background maintenance.
-- Re-enable only with a separate migration/recovery patch; do not delete data.
local USE_WARDROBE_LEDGER = false
local LegacyWardrobe = USE_WARDROBE_LEDGER and require "HalloweenEvent/HalloweenEvent_Persistence" or nil
local Wardrobe = LegacyWardrobe or {
    find=function() return nil end, claim=function() end, record=function() return false end,
    maintain=function() end, onDeath=function() end, noteWornSkip=function() end,
    drainDiagnostics=function() return nil end, drainRecordDiagnostics=function() return nil end
}

local Matrix = require "HalloweenEvent/HalloweenEvent_PersistenceMatrix"
local HWE = HalloweenEvent
if HWE.Server then return end

local Server = {}
HWE.Server = Server
Server.active = false
Server.runtimeManualOverride = nil
Server.config = HWE.readSandbox()
Server._lastStateReason = "startup"
Server._tick = 0
Server._sweepCursor = 0
Server._spawningCostume = false
Server._pendingDress = {}
Server._visualChecks = {}
Server._galleryDelivery = {}
Server._gallerySpawns = {}
Server._galleryRecoveries = {}
Server._visualStats = {checked=0, repaired=0, failed=0}
Server._wardrobeStats = {queued=0, restored=0, failed=0}
Server._nativeStats = {tried=0, accepted=0, fallback=0, nativeReload=0, nativeAlready=0, failed=0}

Server._earlyDressStats = {immediateRestored=0, immediateDressed=0, queuedRestored=0,
    queuedDressed=0, immediateFailed=0, ticksBudgetExhausted=0, maxPending=0}
Server._earlyDressBudget = {tick=-1, count=0, start=0}
-- Cached player-aware ordering for already deferred costume work. Never
-- expand the native/model mutation time budget when a player is nearby.
Server._queuePriorityDirty = false
Server._queuePriorityTick = -1
Server._queuePlayerPositions = {}
Server._queuePriorityStats = {sorts=0, playerSamples=0, near=0, mid=0,
    far=0, unknown=0, nearWaitTotal=0, nearWaitMax=0, directionPlayers=0,
    nearFront=0, nearOther=0, nearFrontWaitTotal=0, nearFrontWaitMax=0}

local REAL_VANILLA_CANDY = {
    "Base.Chocolate", "Base.CandyPackage", "Base.Lollipop",
    "Base.MintCandy", "Base.Modjeska", "Base.Jujubes"
}

local EVENT_CONTAINERS = RewardItems.treatContainers

local VANILLA_TREAT_BAGS = {
    -- B42 full types. The previous Bag_PlasticBag / Bag_Lunchbox names do not
    -- exist and were producing repeated create-failed log spam.
    "Base.Plasticbag", "Base.Lunchbox", "Base.Bag_Schoolbag"
}

local EVENT_DECOR = RewardItems.rewards

-- Most of the 700+ fresh costumes used to be delayed for hundreds of ticks.
-- Keep burst work bounded in milliseconds instead of applying only 4/tick.
-- Limited +18% budget headroom, not an unlimited catch-up burst.
local MAX_PENDING_PER_TICK = 48
local PENDING_WORK_BUDGET_MS = 26
local EARLY_DRESS_LIMIT_PER_TICK = 64
local EARLY_DRESS_BUDGET_MS = 35
-- Reconciliation is fallback-only. OnZombieCreate handles normal/Horde Manager
-- spawns immediately; this slow sweep only catches unusual streamed-in zombies.
local NATURAL_SWEEP_TICKS = 600
local NATURAL_SWEEP_COUNT = 16
local PENDING_DELAY_TICKS = 1
-- Initial nearby group first. Re-sort only for new work / meaningful player
-- movement, and very infrequently to prevent distant-job starvation.
local PRIORITY_NEAR_SQ = 25 * 25
local PRIORITY_MID_SQ = 60 * 60
local PRIORITY_MOVE_SQ = 6 * 6
-- Approximate forward cone using server-authoritative character direction,
-- without expensive LOS/raycast checks. 0.35 is approximately a 140-degree cone.
local PRIORITY_FRONT_DOT = 0.35
local PRIORITY_TURN_DOT = 0.94
local PRIORITY_REFRESH_TICKS = 20
local WARDROBE_MAINTENANCE_TICKS = 30
-- Failed dressing preserves the source zombie; never create a replacement.
local prepareDeathLoot
local applyCostumeBalance

local function safeCall(obj, method, ...)
    return HWE.safeCall(obj, method, ...)
end

-- The server Lua tree can also be loaded by the local co-op client. Never let
-- that client copy mutate zombies; only SP or the actual server is authoritative.
local function isAuthoritative()
    local client = type(isClient) == "function" and isClient() == true
    local server = type(isServer) == "function" and isServer() == true
    return (not client) or server
end

local function isAdmin(player)
    local client = type(isClient) == "function" and isClient() == true
    local server = type(isServer) == "function" and isServer() == true
    if not client and not server then return true end
    if not player then return false end
    if safeCall(player, "isCoopHost") == true then return true end
    local level = tostring(safeCall(player, "getAccessLevel") or ""):lower()
    if level == "admin" or level == "moderator" or level == "overseer" or level == "gm" then return true end
    local ok, result = pcall(function() return player:isAdmin() end)
    return ok and result == true
end

local function getZombieList()
    local cell = type(getCell) == "function" and getCell() or nil
    return cell and safeCall(cell, "getZombieList") or nil
end

local function snapshotOriginal(zombie)
    local md = safeCall(zombie, "getModData")
    if not md then return "", 0 end

    local existing = tostring(md.HalloweenEventOriginalOutfitName or "")
    local existingID = tonumber(md.HalloweenEventOriginalPersistentID or 0) or 0
    -- The native ID is a more useful identity than the display name. Many
    -- normal vanilla outfits are also HalloweenEvent profile names, so the
    -- older name filter incorrectly discarded BOTH identity fields.
    if existing ~= "" or existingID ~= 0 then return existing, existingID end

    local current = tostring(safeCall(zombie, "getOutfitName") or "")
    local currentID = tonumber(safeCall(zombie, "getPersistentOutfitID") or 0) or 0
    local ordinaryName = (current ~= "" and not HWE.isHalloweenOutfitName(current)) and current or ""
    -- Keep the ID even when the outfit happens to have a Halloween profile.
    -- Keep the name blank for those outfits to avoid false name-only matches.
    md.HalloweenEventOriginalOutfitName = ordinaryName
    md.HalloweenEventOriginalPersistentID = currentID
    md.HalloweenEventSnapshotVersion = HWE.VERSION
    return ordinaryName, currentID
end

local function callAddZombiesInOutfit(x, y, z, outfit, femaleChance)
    if type(addZombiesInOutfit) ~= "function" then
        return nil, "addZombiesInOutfit unavailable"
    end

    Server._spawningCostume = true
    local ok, result = pcall(addZombiesInOutfit, x, y, z, 1, outfit, femaleChance)
    Server._spawningCostume = false

    if not ok then return nil, tostring(result) end
    if not result or type(result.size) ~= "function" or result:size() < 1 then
        return nil, "spawn returned no zombies"
    end
    return result, nil
end

local function getReplacement(result)
    if not result then return nil end
    for i = 0, result:size() - 1 do
        local zombie = result:get(i)
        if zombie and safeCall(zombie, "isAlive") == true then return zombie end
    end
    return nil
end

local NetworkZombiePackerClass = nil
do
    local ok, cls = pcall(function()
        if luajava and luajava.bindClass then
            return luajava.bindClass("zombie.popman.NetworkZombiePacker")
        end
        return nil
    end)
    if ok then NetworkZombiePackerClass = cls end
end

local function notifyZombieDeleted(zombie)
    if not zombie or not NetworkZombiePackerClass then return false end
    if not (type(isServer) == "function" and isServer() == true) then return false end

    local ok, packer = pcall(function()
        return NetworkZombiePackerClass:getInstance()
    end)
    if not ok or not packer then return false end

    local sent = pcall(function()
        packer:deleteZombie(zombie)
    end)
    return sent == true
end

local function removeZombie(zombie)
    if not zombie then return true end

    -- Gallery failure cleanup only. World conversions never call this path.
    notifyZombieDeleted(zombie)

    local manager = VirtualZombieManager and VirtualZombieManager.instance or nil
    if manager then
        local ok, removed = HWE.tryCall(manager, "removeZombieFromWorld", zombie)
        if ok and removed ~= false then return true end
    end

    -- Fallback only for environments where the virtual manager is unavailable.
    local okWorld = HWE.tryCall(zombie, "removeFromWorld")
    local okSquare = HWE.tryCall(zombie, "removeFromSquare")
    return okWorld or okSquare
end

-- Snapshots and revisions belong to the existing object, not a newly spawned
-- substitute. The token also protects against reused network IDs.
local visualSerial = 0
local visualEpoch = tostring(type(getTimestampMs) == "function" and getTimestampMs() or {})
local function saveVisualState(zombie, costume)
    local md = safeCall(zombie, "getModData")
    local snapshot = HWE.captureVisualSnapshot(zombie)
    if not md or not snapshot then return false end
    if not md.HalloweenEventVisualToken then
        visualSerial = visualSerial + 1
        md.HalloweenEventVisualToken = visualEpoch .. ":" .. tostring(visualSerial)
    end
    md.HalloweenEventVisualRevision = (tonumber(md.HalloweenEventVisualRevision) or 0) + 1
    md.HalloweenEventVisualSnapshot = snapshot
    md.HalloweenEventVisualRecipeVersion = HWE.VERSION
    return true
end

local function visualState(zombie, costume)
    local md = safeCall(zombie, "getModData")
    if not md or not md.HalloweenEventVisualSnapshot then return nil end
    local impaled = false
    local attached = costume.santaKnifeFallback and safeCall(zombie, "getAttachedItem", "Knife in Back")
    if attached and safeCall(attached, "getID") == md.HalloweenEventSantaKnifeAttachmentID
        and HWE.isSantaImpaledType(safeCall(attached, "getFullType")) then
        impaled = {Type=safeCall(attached, "getFullType"), ItemID=safeCall(attached, "getID"),
            Location="Knife in Back", Condition=safeCall(attached, "getCondition")}
    end
    return {OnlineID=safeCall(zombie, "getOnlineID"), CostumeID=costume.id,
        PersistentID=safeCall(zombie, "getPersistentOutfitID"), Female=safeCall(zombie, "isFemale") == true,
        Token=md.HalloweenEventVisualToken, Revision=md.HalloweenEventVisualRevision,
        Snapshot=md.HalloweenEventVisualSnapshot, ImpaledWeapon=impaled, Gallery=md.HalloweenEventGalleryTest == true,
        GalleryAgeMs=md.HalloweenEventGalleryCreatedAt and math.max(0,
            (type(getTimestampMs) == "function" and getTimestampMs() or Server._tick*(1000/60)) - md.HalloweenEventGalleryCreatedAt),
        X=safeCall(zombie, "getX"), Y=safeCall(zombie, "getY"), Z=safeCall(zombie, "getZ")}
end

local function nearPlayer(player, zombie)
    local px, py = tonumber(safeCall(player, "getX")), tonumber(safeCall(player, "getY"))
    local zx, zy = tonumber(safeCall(zombie, "getX")), tonumber(safeCall(zombie, "getY"))
    if not px or not py or not zx or not zy then return false end
    return (px-zx)^2 + (py-zy)^2 <= 10000
end

local function deliveryNow()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return Server._tick * (1000 / 60)
end

local function containsObject(collection, object)
    if not collection then return nil end
    local found = safeCall(collection, "contains", object)
    if type(found) == "boolean" then return found end
    -- ArrayList fallback; never treat an unavailable Set API as an empty list.
    local size = tonumber(safeCall(collection, "size"))
    if not size then return nil end
    if size == 0 then return false end
    for i = 0, size - 1 do
        local ok, value = HWE.tryCall(collection, "get", i)
        if not ok then return nil end
        if value == object then return true end
    end
    return false
end

local function galleryPresence(zombie)
    local cell = type(getCell) == "function" and getCell() or nil
    local square = safeCall(zombie, "getCurrentSquare")
    local manager = VirtualZombieManager and VirtualZombieManager.instance
    local moving
    if square then moving = containsObject(safeCall(square, "getMovingObjects"), zombie) end
    return {
        world=safeCall(zombie, "isExistInTheWorld"),
        zombies=containsObject(safeCall(cell, "getZombieList"), zombie),
        objects=containsObject(safeCall(cell, "getObjectList"), zombie),
        adding=containsObject(safeCall(cell, "getAddList"), zombie),
        removing=containsObject(safeCall(cell, "getRemoveList"), zombie),
        moving=moving,
        reused=safeCall(manager, "isReused", zombie),
        square=square ~= nil
    }
end

local function presenceFields(p)
    return " serverInWorld=" .. tostring(p.world) .. " cellZombie=" .. tostring(p.zombies)
        .. " cellObject=" .. tostring(p.objects) .. " pendingAdd=" .. tostring(p.adding)
        .. " pendingRemove=" .. tostring(p.removing) .. " squareMoving=" .. tostring(p.moving)
        .. " reused=" .. tostring(p.reused) .. " square=" .. tostring(p.square)
end

local function physicallyPresent(p)
    return p.world == true or p.objects == true or p.moving == true
end

local function unregistered(p)
    return p.world == false and p.objects == false and p.adding == false
        and p.removing == false and (p.moving == false or not p.square)
        and type(p.reused) == "boolean" and (p.reused == false or p.zombies == false)
end

local function nearGalleryRequest(entry)
    local px, py = tonumber(safeCall(entry.player, "getX")), tonumber(safeCall(entry.player, "getY"))
    local pz = tonumber(safeCall(entry.player, "getZ"))
    return px and py and entry.x and entry.y and pz == entry.z and (px-entry.x)^2 + (py-entry.y)^2 <= 1024
end

local function allWatchersUnloaded(entry)
    if not entry or not entry.request or entry.request.superseded or (entry.request.attempt or 0) >= 1 then return false end
    local count, now = 0, deliveryNow()
    for _, watcher in pairs(entry.watchers) do
        count = count + 1
        if watcher.loaded or watcher.applied or (watcher.missingCount or 0) < 2
            or now - (watcher.lastMissing or 0) > 3000 then return false end
    end
    return count > 0 and now - entry.started >= 5000 and now - entry.started < 15000
end

-- Confirm presentation, not just successful creation in the server VM. Retry
-- announcements for this SAME zombie; never allocate a replacement on a timeout.
local function trackGalleryDelivery(zombie, costume, state, players)
    local existing = Server._galleryDelivery[state.Token]
    if existing and existing.revision == state.Revision then return end
    local entry = {zombie=zombie, costume=costume, token=state.Token, revision=state.Revision,
        onlineID=tonumber(state.OnlineID), started=deliveryNow(), step=1, watchers={}}
    local watchers = 0
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if nearPlayer(player, zombie) then
            entry.watchers[player] = {announced=false, loaded=false, applied=false}
            watchers = watchers + 1
        end
    end
    -- Count during population: the tested Kahlua runtime has no next() global.
    if watchers > 0 then
        Server._galleryDelivery[state.Token] = entry
        HWE.log("GALLERY_DELIVERY_TRACKED id=" .. costume.id .. " onlineID=" .. tostring(state.OnlineID)
            .. " watchers=" .. tostring(watchers))
    end
end

local function nudgeZombieNetwork()
    -- This documented class is not always exposed to Lua. Capability-check it;
    -- no luajava binding or fabricated network packet is required.
    local cls = NetworkZombiePacker or NetworkZombiePackerClass
    if not cls then return false end
    local ok, packer = pcall(function() return cls.getInstance() end)
    if not ok or not packer then return false end
    local called, result = HWE.tryCall(packer, "setExtraUpdate")
    return called and result ~= false
end

local function processGalleryDelivery()
    local schedule = {250,750,2000,5000,10000}
    for token, entry in pairs(Server._galleryDelivery) do
        local zombie = entry.zombie
        local md = safeCall(zombie, "getModData")
        local alive = safeCall(zombie, "isAlive") == true
        if not alive or not md or md.HalloweenEventVisualToken ~= token
            or md.HalloweenEventVisualRevision ~= entry.revision
            or tonumber(safeCall(zombie, "getOnlineID")) ~= entry.onlineID then
            HWE.log("GALLERY_DELIVERY_CANCEL id=" .. entry.costume.id .. " onlineID=" .. tostring(entry.onlineID)
                .. " reason=" .. (alive and "identity_changed" or "dead_or_unloaded"))
            Server._galleryDelivery[token] = nil
        else
            local elapsed = deliveryNow() - entry.started
            local waiting = false
            for player, watcher in pairs(entry.watchers) do
                if not watcher.applied then
                    waiting = true
                    if elapsed >= 15000 then
                        HWE.log("GALLERY_DELIVERY_UNCONFIRMED id=" .. entry.costume.id
                            .. " onlineID=" .. tostring(entry.onlineID) .. " announced=" .. tostring(watcher.announced)
                            .. " loaded=" .. tostring(watcher.loaded) .. " serverAlive=true"
                            .. presenceFields(galleryPresence(zombie))
                            .. " x=" .. tostring(safeCall(zombie, "getX")) .. " y=" .. tostring(safeCall(zombie, "getY"))
                            .. " action=kept_same_zombie")
                    elseif schedule[entry.step] and elapsed >= schedule[entry.step] and nearPlayer(player, zombie) then
                        local state = visualState(zombie, entry.costume)
                        if state and type(sendServerCommand) == "function" then
                            pcall(sendServerCommand, player, HWE.MOD_ID, "CostumeVisual", state)
                        end
                    end
                end
            end
            if not waiting or elapsed >= 15000 then Server._galleryDelivery[token] = nil
            elseif schedule[entry.step] and elapsed >= schedule[entry.step] then
                local nudged = nudgeZombieNetwork()
                HWE.log("GALLERY_DELIVERY_RETRY id=" .. entry.costume.id .. " onlineID=" .. tostring(entry.onlineID)
                    .. " attempt=" .. tostring(entry.step) .. " networkExtraUpdate=" .. tostring(nudged))
                entry.step = entry.step + 1
            end
        end
    end
end

local function broadcastCostumeVisual(zombie, costume, skipCheck)
    local md = safeCall(zombie, "getModData")
    if not md then return end
    if not md.HalloweenEventVisualSnapshot and not saveVisualState(zombie, costume) then return end
    if not skipCheck then
        Server._visualChecks[#Server._visualChecks + 1] = {zombie=zombie, costume=costume,
            token=md.HalloweenEventVisualToken, revision=md.HalloweenEventVisualRevision,
            due=Server._tick + 30, remaining=2}
    end
    local state = visualState(zombie, costume)
    local id = state and tonumber(state.OnlineID)
    if type(isServer) ~= "function" or not isServer() or not id or id < 0 then return end
    local players = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    if not players or type(sendServerCommand) ~= "function" then return end
    if state.Gallery then trackGalleryDelivery(zombie, costume, state, players) end
    -- Unloaded recipients resolve the recipe when they actually stream it in.
    local recipients = 0
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if nearPlayer(player, zombie) then
            local ok, err = pcall(sendServerCommand, player, HWE.MOD_ID, "CostumeVisual", state)
            if ok then recipients = recipients + 1
            else HWE.log("VISUAL_SYNC_SEND_FAIL error=" .. tostring(err)) end
        end
    end
    HWE.log("VISUAL_SYNC_SENT id=" .. costume.id .. " onlineID=" .. tostring(id)
        .. " revision=" .. tostring(state.Revision) .. " recipients=" .. tostring(recipients))
end

-- Resolve optional pieces only on the authority when a costume is dressed.
-- The existing full ItemVisual snapshot carries that choice through clients,
-- repair checks and reloads. Those paths must never roll another accessory.
local function chooseDressRecipe(costume)
    if not costume.additionalItems and not costume.optionalItems then return costume end
    local items = {}
    for _, fullType in ipairs(costume.visualItems or costume.additionalItems or {}) do
        items[#items + 1] = fullType
    end
    if costume.additionalItems then
        for _, fullType in ipairs(costume.additionalItems) do
            if not ItemVisual or type(ItemVisual.new) ~= "function" then return nil, "ItemVisual unavailable" end
            local ok, visual = pcall(function() return ItemVisual.new() end)
            if not ok or not visual or not HWE.tryCall(visual, "setItemType", fullType)
                or not safeCall(visual, "getScriptItem") or not safeCall(visual, "getClothingItem") then
                return nil, "unresolved required accessory: " .. fullType
            end
        end
    end
    local selected = "none"
    if costume.optionalItems and #costume.optionalItems > 0 and HWE.rollPercent(costume.optionalChance) then
        local fullType = costume.optionalItems[ZombRand(1, #costume.optionalItems + 1)]
        local ok, visual = pcall(function() return ItemVisual.new() end)
        if ok and visual and HWE.tryCall(visual, "setItemType", fullType)
            and safeCall(visual, "getScriptItem") and safeCall(visual, "getClothingItem") then
            items[#items + 1], selected = fullType, fullType
        else HWE.log("COSTUME_OPTIONAL_SKIP id=" .. costume.id .. " type=" .. fullType .. " reason=unresolved") end
    end
    HWE.log("COSTUME_ACCESSORY_SELECTED id=" .. costume.id .. " optional=" .. selected
        .. " required=" .. table.concat(costume.additionalItems or {}, ","))
    return {id=costume.id, visualItems=items,
        visualMode=costume.visualItems and "replace" or "append",
        visualTints=costume.visualTints, visualTintChoices=costume.visualTintChoices, auditGenderAssets=true}
end

local function restoreExactVisualRecipe(zombie, costume)
    if not costume then return end
    local md = safeCall(zombie, "getModData")
    if not md or md.HalloweenEventVisualRecipeVersion == HWE.VERSION then return end
    if safeCall(zombie, "isUsingWornItems") == true then
        if md.HalloweenEventWornSourceLogged ~= HWE.VERSION then
            md.HalloweenEventWornSourceLogged = HWE.VERSION
            HWE.log("WORN_VISUAL_SOURCE_PRESERVED onlineID=" .. tostring(safeCall(zombie, "getOnlineID")))
        end
        return
    end
    -- Preserve correct existing visuals and accessory choices during migration,
    -- including the protected mummy; only changed/incomplete recipes are dressed.
    local currentCorrect = HWE.verifyCostume(zombie, costume)
    if costume.additionalItems and currentCorrect then
        local savedRecipe = HWE.snapshotRecipe(costume, md.HalloweenEventVisualSnapshot)
        currentCorrect = savedRecipe and HWE.verifyCostume(zombie, savedRecipe) or
            (not savedRecipe and #HWE.visualTypes(zombie) >= 2)
    end
    if (costume.visualMode == "replace" or costume.additionalItems) and currentCorrect then
        if costume.id=="JasonSlasher" then
            -- Preserve the exact native/saved tint while linking its clothing
            -- item color before death; migration must not reroll coveralls.
            local recipe=HWE.snapshotRecipe(costume,HWE.captureVisualSnapshot(zombie))
            local ok,err=HWE.applyCostumeVisuals(zombie,recipe,"server_restore_color")
            if not ok then HWE.log("VISUAL_RESTORE_FAIL id="..costume.id.." error="..tostring(err));return end
        end
        saveVisualState(zombie, costume)
        broadcastCostumeVisual(zombie, costume)
        return
    end
    local savedRecipe = HWE.snapshotRecipe(costume, md.HalloweenEventVisualSnapshot)
    local snapshotHasAdditions = savedRecipe ~= nil
    for _, required in ipairs(costume.additionalItems or {}) do
        local found = false
        for _, actual in ipairs(savedRecipe and savedRecipe.visualItems or {}) do
            if actual == required then found = true; break end
        end
        if not found then snapshotHasAdditions = false; break end
    end
    local additions, err
    if (costume.additionalItems and not snapshotHasAdditions) or (not savedRecipe and costume.optionalItems) then
        additions, err = chooseDressRecipe(costume)
        if not additions then HWE.log("VISUAL_RESTORE_FAIL id=" .. costume.id .. " error=" .. tostring(err)); return end
    end
    local recipe = costume.visualItems and chooseDressRecipe(costume) or savedRecipe
    if not recipe then
        if additions and #additions.visualItems > 0 then
            local ok, additionErr = HWE.applyCostumeVisuals(zombie, additions, "server_restore_accessory")
            if not ok then HWE.log("VISUAL_RESTORE_FAIL id=" .. costume.id .. " error=" .. tostring(additionErr)); return end
        end
        saveVisualState(zombie, costume)
        broadcastCostumeVisual(zombie, costume)
        return
    end
    local ok, err = HWE.applyCostumeVisuals(zombie, recipe, "server_restore")
    if ok and additions and #additions.visualItems > 0 then ok, err = HWE.applyCostumeVisuals(zombie, additions, "server_restore_accessory") end
    if ok then
        saveVisualState(zombie, costume)
        broadcastCostumeVisual(zombie, costume)
    else HWE.log("VISUAL_RESTORE_FAIL id=" .. costume.id .. " error=" .. tostring(err)) end
end

local function tryNativePersistentDress(zombie, costume, context, recipe)
    -- Native costume names are defined in media/clothing/clothing.xml before
    -- zombie population construction; a Lua ItemVisual-only outfit is NOT an ID.
    local name = tostring(costume.nativeOutfit or costume.outfit or "")
    if name == "" then return false end
    local manager = OutfitManager and OutfitManager.instance
    local finder = safeCall(zombie,"isFemale") == true and "FindFemaleOutfit" or "FindMaleOutfit"
    if manager and not safeCall(manager, finder, name) then
        Server._nativeStats.failed = Server._nativeStats.failed + 1
        return false
    end
    Server._nativeStats.tried = Server._nativeStats.tried + 1
    -- API both generates the persistent outfit ID and applies its native
    -- appearance. Do not construct bitfields / assume a stable index ordering.
    local oldID = tonumber(safeCall(zombie, "getPersistentOutfitID")) or 0
    local ok = HWE.tryCall(zombie, "dressInPersistentOutfit", name)
    local id = tonumber(safeCall(zombie, "getPersistentOutfitID")) or 0
    local actual = tostring(safeCall(zombie,"getOutfitName") or "")
    if not ok or id == 0 or (actual ~= name and id == oldID) then
        Server._nativeStats.failed = Server._nativeStats.failed + 1
        return false
    end
    HWE.tryCall(zombie, "setPersistentOutfitID", id, true)
    HWE.tryCall(zombie, "setDressInRandomOutfit", false)
    -- Optional accessories and precise tint cannot be encoded by a single
    -- static XML outfit. Apply those from the existing tested recipe, keeping
    -- the native persistent ID so the engine can reconstruct its base outfit.
    local needsRecipe = (costume.visualItems and
            (costume.visualTints or costume.visualTintChoices or
             not HWE.verifyCostume(zombie, recipe))) or
        costume.additionalItems or costume.optionalItems
    if needsRecipe then
        if costume.visualItems then
            local applied = HWE.applyCostumeVisuals(zombie, recipe, context.."_native_exact")
            if not applied then
                Server._nativeStats.failed=Server._nativeStats.failed+1
                return false
            end
        elseif costume.additionalItems then
            local required = {id=costume.id, visualMode="append", visualItems=costume.additionalItems}
            HWE.applyCostumeVisuals(zombie, required, context.."_native_accessory")
        end
    end
    Server._nativeStats.accepted = Server._nativeStats.accepted + 1
    return true
end

local function dressExisting(zombie, costume, context, preparedRecipe)
    if costume.femaleOnly and safeCall(zombie, "isFemale") ~= true then return false, "female-only profile" end
    if costume.maleOnly and safeCall(zombie, "isFemale") == true then return false, "male-only profile" end
    if safeCall(zombie, "isUsingWornItems") == true then return false, "worn-items visual source unsupported; original clothing retained" end
    local recipe, recipeErr = preparedRecipe or chooseDressRecipe(costume)
    if not recipe then return false, recipeErr end
    if tryNativePersistentDress(zombie, costume, context, recipe) then return true end
    -- Native outfit unsupported/incomplete: maintain v16's fully tested visual
    -- recipe path. Never despawn or delete the original zombie on failure.
    Server._nativeStats.fallback = Server._nativeStats.fallback + 1
    if costume.visualItems then return HWE.applyCostumeVisuals(zombie, recipe, context) end
    -- Working vanilla costumes retain the engine's complete clothing selection.
    -- Preserve old visual objects in case named dressing fails or returns naked.
    local visuals = safeCall(zombie, "getItemVisuals")
    if not visuals then return false, "getItemVisuals unavailable" end
    local backup = {}
    for i = 0, visuals:size() - 1 do backup[#backup + 1] = visuals:get(i) end
    local humanVisual = safeCall(zombie, "getHumanVisual")
    local ok, err = HWE.tryCall(humanVisual, "dressInNamedOutfit", costume.outfit, visuals)
    if not ok then ok, err = HWE.tryCall(zombie, "dressInNamedOutfit", costume.outfit) end
    if ok and visuals:size() >= 2 and recipe.visualItems and #recipe.visualItems > 0 then
        ok, err = HWE.applyCostumeVisuals(zombie, recipe, context .. "_accessory")
    end
    if not ok or visuals:size() < 2 then
        HWE.tryCall(visuals, "clear")
        for _, visual in ipairs(backup) do HWE.tryCall(visuals, "add", visual) end
        return false, err or "native outfit incomplete"
    end
    local persistentID = tonumber(safeCall(zombie, "getPersistentOutfitID")) or 0
    HWE.tryCall(zombie, "setPersistentOutfitID", persistentID, true)
    HWE.tryCall(zombie, "setDressInRandomOutfit", false)
    HWE.tryCall(zombie, "resetModelNextFrame")
    return true
end

local function dressWorldZombie(zombie, costume, reason, preparedRecipe)
    local md = safeCall(zombie, "getModData")
    if not md or safeCall(zombie, "isAlive") ~= true then return false end
    local oldName, oldID = snapshotOriginal(zombie)
    local onlineID = safeCall(zombie, "getOnlineID")
    local ok, err = dressExisting(zombie, costume, "server_dress", preparedRecipe)
    md.HalloweenEventSpawnQueued = nil
    if not ok then
        HWE.log("COSTUME_DRESS_FAIL id=" .. costume.id .. " onlineID=" .. tostring(onlineID)
            .. " reason=" .. tostring(reason) .. " error=" .. tostring(err) .. " source=preserved")
        return false
    end
    -- tagSpawnedCostume clears loot flags for NEW zombies. An in-place reroll
    -- must retain those flags, or candy/containers get queued a second time.
    local lootPrepared, lootAwarded = md.HalloweenEventLootPrepared, md.HalloweenEventLootAwarded
    HWE.tagSpawnedCostume(zombie, costume, oldName, oldID)
    md.HalloweenEventLootPrepared, md.HalloweenEventLootAwarded = lootPrepared, lootAwarded
    saveVisualState(zombie, costume)
    Wardrobe.record(zombie, costume)
    if prepareDeathLoot then prepareDeathLoot(zombie, costume) end
    broadcastCostumeVisual(zombie, costume)
    -- Normal successful dressing is already covered by startup summaries.
    -- Avoid rebuilding a zombie's full visual type list just for logging.
    return true
end

-- Hide Anywhere: Zombies prepares its discovery HUD before a live zombie
-- exists. Pick one costume now, and keep the same recipe for preview and spawn.
 -- This is separate from the persistence-matrix test system.
function Server.prepareHiddenAppearance(appearance)
    if type(appearance) ~= "table" or Server.active ~= true then return nil end
    if not HWE.rollPercent(Server.config and Server.config.CostumeChancePercent) then
        -- A failed event roll must also suppress OnZombieCreate's independent
        -- roll, otherwise a normal HUD preview becomes a costumed live zombie.
        return {selected=false,suppress=true}
    end
    local f = appearance.female
    if f == nil then f = appearance.Female end
    if f == nil then f = appearance.isFemale end
    if f == nil and type(appearance.gender)=="string" then
        f = appearance.gender:lower() == "female"
    end
    -- The encounter does not have an IsoZombie yet; only the gender decision
    -- is required by the natural-costume picker.
    local phantom = {isFemale=function() return f == true end}
    local costume = HWE.pickRandomCostume(phantom)
    if not costume then return nil end
    local recipe,err = chooseDressRecipe(costume)
    if not recipe then
        HWE.log("HIDDEN_PREPARE_SKIP id="..tostring(costume.id).." error="..tostring(err))
        return nil
    end
    local prepared = {selected=true,costumeID=costume.id,recipe=recipe}
    if type(recipe.visualItems)=="table" and #recipe.visualItems>0 then
        -- Preselect tint variants once, before the preview and live zombie are
        -- dressed. Without this they can independently roll different colors.
        local appearances={}
        for i,fullType in ipairs(recipe.visualItems) do
            local tint=recipe.visualTints and recipe.visualTints[fullType]
            local choices=recipe.visualTintChoices and recipe.visualTintChoices[fullType]
            if type(choices)=="table" and #choices>0 then
                tint=choices[ZombRand(1,#choices+1)]
            end
            if type(tint)=="table" then
                appearances[i]={Tint={tonumber(tint[1]) or 1,tonumber(tint[2]) or 1,tonumber(tint[3]) or 1}}
            end
        end
        recipe.visualAppearance=appearances
        prepared.snapshot={Items=recipe.visualItems, Appearance=appearances}
        prepared.visualMode=recipe.visualMode
    end
    HWE.log("HIDDEN_PREPARE_OK id="..tostring(costume.id)
        .." outfit="..tostring(costume.outfit).." female="..tostring(f)
        .." previewPieces="..tostring(prepared.snapshot and #prepared.snapshot.Items or 0))
    return prepared
end

function Server.applyHiddenAppearance(zombie,prepared)
    if type(prepared)~="table" or not zombie then return false end
    if prepared.suppress==true and prepared.selected~=true then
        for i=#Server._pendingDress,1,-1 do
            local entry=Server._pendingDress[i]
            if entry and entry.zombie==zombie then table.remove(Server._pendingDress,i) end
        end
        local md=safeCall(zombie,"getModData")
        if md then md.HalloweenEventSpawnQueued=nil;md.HalloweenEventSeenVersion=HWE.VERSION end
        return true
    end
    if prepared.selected~=true then return false end
    local costume = HWE.getCostumeByID(prepared.costumeID)
    if not costume then return false end
    local ok = dressWorldZombie(zombie,costume,"hide_anywhere_discovery",prepared.recipe)
    if ok then
        -- OnZombieCreate may have already queued a random costume while HAZ
        -- constructed this zombie. Remove that stale job so it cannot override
        -- the exact same costume the player just saw in the discovery HUD.
        for i=#Server._pendingDress,1,-1 do
            local entry=Server._pendingDress[i]
            if entry and entry.zombie==zombie then table.remove(Server._pendingDress,i) end
        end
        local md=safeCall(zombie,"getModData")
        if md then
            md.HalloweenEventSpawnQueued=nil
            md.HalloweenEventSeenVersion=HWE.VERSION
        end
        HWE.log("HIDDEN_SPAWN_COSTUME_OK id="..costume.id
            .." onlineID="..tostring(safeCall(zombie,"getOnlineID")))
    else
        HWE.log("HIDDEN_SPAWN_COSTUME_FAIL id="..costume.id)
    end
    return ok
end

-- Isolated admin-only matrix: no changes to normal conversion rates or queues.
local function runPersistenceMatrixCase(job)
    local zombie, costume, variant = job.zombie, job.costume, job.variant
    if safeCall(zombie, "isAlive") ~= true then
        Matrix.onDressed(job, false, "dead_before_test", nil, nil)
        return
    end
    local before = Matrix.stamp(zombie)
    if not dressWorldZombie(zombie, costume, "persistence_matrix") then
        Matrix.onDressed(job, false, "dress_failed", before, nil)
        return
    end
    local target = Matrix.stamp(zombie) -- exact costume immediately after normal application
    local outcomes = {}
    local function call(label, obj, method, ...)
        local ok, result = HWE.tryCall(obj, method, ...)
        outcomes[#outcomes+1] = label..":"..tostring(ok)
        return ok, result
    end
    local md = safeCall(zombie, "getModData")
    local nativeID = tonumber(safeCall(zombie, "getPersistentOutfitID")) or 0
    local visuals = md and HWE.snapshotRecipe(costume, md.HalloweenEventVisualSnapshot)
    local function flag(bit) return math.floor(variant / (2^bit)) % 2 == 1 end
    -- Each experiment is a unique, reproducible combination of 5 engine paths:
    -- unchanged ID/force setter, suppress random reroll, schedule model reset,
    -- explicit visuals write, native persistent rebuild followed by exact visual
    -- reapplication. 2^5=32 combinations, balanced over all costume profiles.
    if flag(0) then
        if nativeID~=0 then call("persistent_id_flag_false", zombie, "setPersistentOutfitID", nativeID, false)
        else outcomes[#outcomes+1]="persistent_id_skipped:zero" end
    end
    if flag(1) then call("random_outfit_false", zombie, "setDressInRandomOutfit", false) end
    if flag(2) then call("reset_model", zombie, "resetModelNextFrame") end
    if flag(4) then call("native_rebuild", zombie, "dressInPersistentOutfit") end
    if (flag(3) or flag(4)) and visuals then
        local ok,err=HWE.applyCostumeVisuals(zombie, visuals, "server_matrix_visual_reapply")
        outcomes[#outcomes+1]="reapply:"..tostring(ok)..(ok and "" or (":"..tostring(err)))
    end
    -- Observations must describe the ACTUAL post-method appearance; do not
    -- hide failed variants by force-repairing them after measurement.
    local finalTypes = Matrix.stamp(zombie)
    Matrix.onDressed(job, target ~= "" and finalTypes==target, table.concat(outcomes, ";"), before, finalTypes, target)
end

local function spawnCostumeAt(x, y, z, costume, femaleChance, reason, request)
    x, y, z = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0)
    -- Exact recipes use a known registered vanilla backing spawn, so missing
    -- HWE XML definitions cannot silently stop Pirate/Cowboy/etc from spawning.
    local backing = (costume.id == "BurlapMummy" and costume.outfit) or ((costume.visualItems or costume.noFirearms) and "Tourist") or costume.outfit
    local result, err = callAddZombiesInOutfit(x, y, z, backing, femaleChance)
    local zombie = getReplacement(result)
    if not zombie then
        HWE.log("SPAWN_COSTUME_FAIL id=" .. costume.id .. " error=" .. tostring(err))
        return 0
    end
    local ok, dressErr = dressExisting(zombie, costume, "server_spawn")
    if not ok then
        HWE.log("SPAWN_COSTUME_REJECT id=" .. costume.id .. " error=" .. tostring(dressErr))
        removeZombie(zombie)
        return 0
    end
    -- Gallery test zombies also have real server-side outfits. Keep the
    -- original persistent ID for a future safe identity match; older gallery
    -- samples discarded it, so reloaded Spiffos were indistinguishable from
    -- ordinary zombies and got a fresh random costume.
    local galleryOriginalID = tonumber(safeCall(zombie, "getPersistentOutfitID")) or 0
    HWE.tagSpawnedCostume(zombie, costume, "", galleryOriginalID)
    local md = safeCall(zombie, "getModData")
    md.HalloweenEventGalleryTest = true
    md.HalloweenEventGalleryCreatedAt = deliveryNow()
    md.HalloweenEventSantaKnifeQueued, md.HalloweenEventSantaKnifeAttachmentID = nil, nil
    -- A fresh native allocation can reuse an old Java object. Its announcement
    -- must get a new token, even if a previous moddata table survived pooling.
    md.HalloweenEventVisualToken = nil
    md.HalloweenEventVisualRevision = 0
    saveVisualState(zombie, costume)
    -- Spiffo-only restart test: keep a wardrobe snapshot for this one gallery
    -- costume, using its native persistent ID + position + gender. No relaxed
    -- position matching or generic gallery snapshot spam for other costumes.
    if costume.id == "SpiffoMascot" then
        local recorded = Wardrobe.record(zombie, costume, nil, true)
        HWE.log("SPIFFO_GALLERY_RECORD saved=" .. tostring(recorded)
            .. " nativeID=" .. tostring(galleryOriginalID)
            .. " onlineID=" .. tostring(safeCall(zombie, "getOnlineID")))
    end
    if prepareDeathLoot then prepareDeathLoot(zombie, costume) end
    broadcastCostumeVisual(zombie, costume)
    local presence = galleryPresence(zombie)
    if request and costume.id ~= "BurlapMummy" then
        local delivery = Server._galleryDelivery[md.HalloweenEventVisualToken]
        if delivery then
            delivery.request = {player=request.player, attempt=request.attempt or 0, x=x, y=y, z=z,
                femaleChance=safeCall(zombie, "isFemale") == true and 100 or 0, reason=reason}
        end
        if (request.attempt or 0) == 0 then
            for _, pool in ipairs({Server._gallerySpawns, Server._galleryRecoveries}) do
                for _, entry in pairs(pool) do
                    if entry.player == request.player and entry.costume.id == costume.id then entry.superseded = true end
                end
            end
            for token, older in pairs(Server._galleryDelivery) do
                if token ~= md.HalloweenEventVisualToken and older.request and older.request.player == request.player
                    and older.costume.id == costume.id then older.request.superseded = true end
            end
        end
        if not physicallyPresent(presence) then
            Server._gallerySpawns[md.HalloweenEventVisualToken] = {
                zombie=zombie, costume=costume, player=request.player, attempt=request.attempt or 0,
                onlineID=tonumber(safeCall(zombie, "getOnlineID")), persistent=safeCall(zombie, "getPersistentOutfitID"),
                token=md.HalloweenEventVisualToken, revision=md.HalloweenEventVisualRevision,
                x=x, y=y, z=z, femaleChance=safeCall(zombie, "isFemale") == true and 100 or 0,
                reason=reason, due=deliveryNow()+250, deadline=deliveryNow()+2000, expires=deliveryNow()+5000
            }
        end
    end
    HWE.log("SPAWN_COSTUME_OK id=" .. costume.id .. " onlineID=" .. tostring(safeCall(zombie, "getOnlineID"))
        .. " visual=true pieces=" .. tostring(#HWE.visualTypes(zombie))
        .. " reason=" .. tostring(reason or "gallery")
        .. " female=" .. tostring(safeCall(zombie, "isFemale"))
        .. " persistent=" .. tostring(safeCall(zombie, "getPersistentOutfitID"))
        .. " x=" .. tostring(safeCall(zombie, "getX")) .. " y=" .. tostring(safeCall(zombie, "getY"))
        .. presenceFields(presence) .. " types=" .. table.concat(HWE.visualTypes(zombie), ","))
    return 1
end

-- Native creation and client delivery are distinct. A timeout alone never
-- authorizes a respawn. New gallery allocations can recover when unregistered,
-- or when every watcher repeatedly confirms absence in a loaded nearby square.
-- Any client-loaded receipt blocks recovery; cleanup must finish before retry.
local function processGallerySpawns()
    local retries = {}
    local now = deliveryNow()
    for token, entry in pairs(Server._galleryRecoveries) do
        if now >= entry.due then
            local p = galleryPresence(entry.zombie)
            local md = safeCall(entry.zombie, "getModData")
            local identity = safeCall(entry.zombie, "getOnlineID") == entry.disposedID
                and (md and md.HalloweenEventVisualToken or nil) == entry.disposedToken
            local settled = p.world == false and p.zombies == false and p.objects == false
                and p.adding == false and p.removing == false and (p.moving == false or not p.square)
            if now < entry.deadline and not entry.superseded and identity and settled and nearGalleryRequest(entry) then
                Server._galleryRecoveries[token] = nil
                retries[#retries+1] = entry
            elseif entry.superseded or not identity or now >= entry.deadline then
                Server._galleryRecoveries[token] = nil
                HWE.log("GALLERY_NATIVE_RECOVERY_BLOCKED id=" .. entry.costume.id
                    .. " onlineID=" .. tostring(entry.onlineID)
                    .. " reason=" .. (entry.superseded and "newer_command" or "cleanup_pending_or_object_recycled") .. presenceFields(p))
            else entry.due = now + 250 end
        end
    end
    for token, entry in pairs(Server._gallerySpawns) do
        if now >= entry.due then
            local zombie = entry.zombie
            local md = safeCall(zombie, "getModData")
            local delivery = Server._galleryDelivery[token]
            local loaded = entry.clientLoaded == true
            if delivery then
                for _, watcher in pairs(delivery.watchers) do
                    if watcher.loaded or watcher.applied then loaded = true; break end
                end
            end
            local valid = safeCall(zombie, "isAlive") == true and md
                and md.HalloweenEventVisualToken == token and md.HalloweenEventVisualRevision == entry.revision
                and tonumber(safeCall(zombie, "getOnlineID")) == entry.onlineID
                and safeCall(zombie, "getPersistentOutfitID") == entry.persistent
            local presence = galleryPresence(zombie)
            local missingConfirmed = entry.clientUnloaded and allWatchersUnloaded(delivery)
            if entry.superseded or not valid or loaded or (physicallyPresent(presence) and not missingConfirmed) then
                Server._gallerySpawns[token] = nil
                HWE.log("GALLERY_WORLD_CHECK id=" .. entry.costume.id .. " onlineID=" .. tostring(entry.onlineID)
                    .. " result=" .. (entry.superseded and "newer_command" or not valid and "identity_or_alive_changed"
                        or loaded and "client_loaded" or "registered") .. presenceFields(presence))
            elseif now >= entry.expires then
                Server._gallerySpawns[token] = nil
                HWE.log("GALLERY_NATIVE_RECOVERY_BLOCKED id=" .. entry.costume.id
                    .. " onlineID=" .. tostring(entry.onlineID) .. " reason=recovery_window_elapsed" .. presenceFields(presence))
            elseif now < entry.deadline then
                entry.due = now + 250
            else
                Server._gallerySpawns[token] = nil
                local registeredButUndelivered = missingConfirmed and presence.zombies == true
                    and presence.objects == true and presence.moving == true and presence.square
                    and presence.adding == false and presence.removing == false and presence.reused == false
                    and tonumber(safeCall(zombie, "getZ")) == entry.z
                    and nearGalleryRequest({player=entry.player, z=entry.z,
                        x=tonumber(safeCall(zombie, "getX")), y=tonumber(safeCall(zombie, "getY"))})
                local canRetry = entry.attempt < 1 and (unregistered(presence) or registeredButUndelivered)
                    and nearGalleryRequest(entry)
                if canRetry then
                    -- The native reuse path already handled this object. Do not
                    -- remove it twice or edit the virtual manager's reuse lists.
                    local removed = presence.reused == true or removeZombie(zombie)
                    local after = galleryPresence(zombie)
                    -- Also require removal from the zombie registry. Unknown
                    -- membership or a failed cleanup cannot create a substitute.
                    local cleared = removed and after.world == false and after.zombies == false
                        and after.objects == false and after.adding == false
                        and (after.moving == false or not after.square)
                    local queuedCleanup = registeredButUndelivered and removed
                        and after.removing == true and after.adding == false
                    if cleared or queuedCleanup then
                        Server._galleryDelivery[token] = nil
                        local disposedMD = safeCall(zombie, "getModData")
                        entry.disposedID = safeCall(zombie, "getOnlineID")
                        entry.disposedToken = disposedMD and disposedMD.HalloweenEventVisualToken
                        entry.due, entry.deadline = now + 250, now + 1500
                        Server._galleryRecoveries[token] = entry
                        HWE.log("GALLERY_NATIVE_RECOVERY id=" .. entry.costume.id .. " onlineID=" .. tostring(entry.onlineID)
                            .. " reason=" .. (registeredButUndelivered and "clients_confirmed_unloaded" or "never_registered")
                            .. " oldAllocationCleared=true attempt=1"
                            .. " alreadyPooled=" .. tostring(presence.reused == true) .. presenceFields(after))
                    else
                        HWE.log("GALLERY_NATIVE_RECOVERY_BLOCKED id=" .. entry.costume.id
                            .. " onlineID=" .. tostring(entry.onlineID) .. " reason=cleanup_unconfirmed" .. presenceFields(after))
                    end
                else
                    HWE.log("GALLERY_NATIVE_RECOVERY_BLOCKED id=" .. entry.costume.id
                        .. " onlineID=" .. tostring(entry.onlineID) .. " reason=guard_or_attempt_limit" .. presenceFields(presence))
                end
            end
        end
    end
    -- Wait a separate tick and for the native remove queue to drain. Reusing a
    -- pooled Java object in the cleanup tick could let an old removal delete it.
    for _, entry in ipairs(retries) do
        local count = spawnCostumeAt(entry.x, entry.y, entry.z, entry.costume, entry.femaleChance,
            entry.reason, {player=entry.player, attempt=1})
        HWE.log("GALLERY_NATIVE_RECOVERY_RESULT id=" .. entry.costume.id .. " spawned=" .. tostring(count))
    end
end


local function queueDressing(zombie, costume, force, reason)
    if not zombie or safeCall(zombie, "isAlive") ~= true then return false end
    local md = safeCall(zombie, "getModData")
    if not md or (md.HalloweenEventGalleryTest == true and reason ~= "target" and reason ~= "reroll_loaded") then return false end
    if md.HalloweenEventSpawnQueued == true then return false end
    if not force and md.HalloweenEventSeenVersion == HWE.VERSION then return false end

    md.HalloweenEventSpawnQueued = true
    md.HalloweenEventSeenVersion = HWE.VERSION
    Server._pendingDress[#Server._pendingDress + 1] = {
        phase = "dress",
        zombie = zombie,
        costume = costume,
        force = force == true,
        due = Server._tick + ((force == true) and 0 or PENDING_DELAY_TICKS),
        reason = reason or "natural",
        queuedAt = Server._tick
    }
    Server._queuePriorityDirty = true
    return true
end

-- Returns true only when the wardrobe recipe has actually been applied.
-- This is shared by the pre-render path and the bounded fallback queue, so
-- neither route may assign a second/random costume to a matched zombie.
local function applyPendingCostume(entry)
    local zombie = entry.zombie
    local md = zombie and safeCall(zombie, "getModData")
    if not zombie or not md or safeCall(zombie, "isAlive") ~= true then return false end
    local costume = entry.costume or HWE.pickRandomCostume(zombie)
    if entry.phase ~= "wardrobe_restore" and costume and entry.reason ~= "target"
        and not HWE.CostumeFilter.isAllowed(costume) then
        costume = HWE.pickRandomCostume(zombie)
    end
    if entry.phase == "wardrobe_restore" then
        local saved = entry.wardrobe
        local recipe = saved and costume and HWE.snapshotRecipe(costume, saved.Snapshot)
        local ok, err = recipe and HWE.applyCostumeVisuals(zombie, recipe, "server_wardrobe_restore")
        md.HalloweenEventSpawnQueued = nil
        if ok then
            HWE.tagSpawnedCostume(zombie, costume, saved.OriginalName, saved.OriginalID)
            Wardrobe.claim(zombie, entry.wardrobeID)
            saveVisualState(zombie, costume)
            Wardrobe.record(zombie, costume)
            if prepareDeathLoot then prepareDeathLoot(zombie, costume) end
            broadcastCostumeVisual(zombie, costume)
            if saved.GallerySpiffo == true then
                HWE.log("WARDROBE_SPIFFO_RESTORED onlineID=" .. tostring(safeCall(zombie, "getOnlineID")))
            end
            Server._wardrobeStats.restored = Server._wardrobeStats.restored + 1
            return true
        end
        Server._wardrobeStats.failed = Server._wardrobeStats.failed + 1
        HWE.log("WARDROBE_RESTORE_FAILED costume=" .. tostring(costume and costume.id)
            .. " error=" .. tostring(err or "missing snapshot") .. " source=preserved")
        return false
    elseif costume then
        local success = dressWorldZombie(zombie, costume, entry.reason)
        if success then md.HalloweenEventSeenVersion = HWE.VERSION end
        return success
    end
    md.HalloweenEventSpawnQueued = nil
    return false
end

-- OnZombieCreate occurs while the zombie is being spawned. Try to finish its
-- visual recipe before it enters the client render stream. A strict per-tick
-- count AND wall-clock budget protect large Horde Manager/population bursts.
local function immediateBudgetAvailable()
    local budget = Server._earlyDressBudget
    if budget.tick ~= Server._tick then
        budget.tick, budget.count, budget.start = Server._tick, 0, deliveryNow()
    end
    if budget.count >= EARLY_DRESS_LIMIT_PER_TICK
        or deliveryNow() - budget.start >= EARLY_DRESS_BUDGET_MS then
        return false
    end
    budget.count = budget.count + 1
    return true
end

-- When the server can see connected players, do one linear pass to cache
-- zombie distances, then sort once. The existing reverse iteration will now
-- dress the closest valid zombie first. Other clients do not participate in
-- dressing and no extra world/zombie scans are needed.
local function reorderPendingNearPlayers()
    local queue = Server._pendingDress
    if #queue < 2 then return end
    local players = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    local size = players and tonumber(safeCall(players, "size")) or 0
    local positions = {}
    for i = 0, math.min(size or 0, 64) - 1 do
        local player = safeCall(players, "get", i)
        local x, y, z = tonumber(safeCall(player, "getX")),
            tonumber(safeCall(player, "getY")), tonumber(safeCall(player, "getZ"))
        if x and y and x > 0 and y > 0 then
            -- Prefer scalar getters: getForwardDirection() exposes a mutable
            -- internal Vector2, and some B42 builds omit that overload.
            local fx = tonumber(safeCall(player, "getForwardDirectionX"))
            local fy = tonumber(safeCall(player, "getForwardDirectionY"))
            if fx == nil or fy == nil then
                local vec = safeCall(player, "getForwardDirection")
                fx = vec and tonumber(safeCall(vec, "getX")) or nil
                fy = vec and tonumber(safeCall(vec, "getY")) or nil
            end
            local magnitude = fx and fy and math.sqrt(fx*fx+fy*fy) or 0
            if magnitude > 0.001 then
                fx, fy = fx/magnitude, fy/magnitude
            else
                fx, fy = nil, nil -- unknown heading: distance-only fallback
            end
            positions[#positions + 1] = {x=x, y=y, z=z or 0, fx=fx, fy=fy}
        end
    end
    if #positions == 0 then return end
    local moved = #positions ~= #Server._queuePlayerPositions
    if not moved then
        for i, p in ipairs(positions) do
            local previous = Server._queuePlayerPositions[i]
            local rotated = previous and p.fx and p.fy and previous.fx and previous.fy
                and (p.fx*previous.fx+p.fy*previous.fy) < PRIORITY_TURN_DOT
            local headingChanged = previous and ((p.fx == nil) ~= (previous.fx == nil))
            if not previous or previous.z ~= p.z or rotated or headingChanged
                or (p.x-previous.x)^2+(p.y-previous.y)^2 >= PRIORITY_MOVE_SQ then
                moved = true
                break
            end
        end
    end
    local refreshDue = Server._tick - Server._queuePriorityTick >= PRIORITY_REFRESH_TICKS
    if not moved and not Server._queuePriorityDirty and not refreshDue then return end

    Server._queuePlayerPositions = positions
    Server._queuePriorityTick = Server._tick
    Server._queuePriorityDirty = false
    Server._queuePriorityStats.sorts = Server._queuePriorityStats.sorts + 1
    Server._queuePriorityStats.playerSamples = math.max(Server._queuePriorityStats.playerSamples, #positions)
    local directionCount = 0
    for _, p in ipairs(positions) do if p.fx then directionCount = directionCount + 1 end end
    Server._queuePriorityStats.directionPlayers = math.max(Server._queuePriorityStats.directionPlayers, directionCount)
    for _, entry in ipairs(queue) do
        local z = entry.zombie
        local x, y, zz = tonumber(safeCall(z, "getX")), tonumber(safeCall(z, "getY")),
            tonumber(safeCall(z, "getZ"))
        local nearest, forward = nil, false
        if x and y then
            for _, p in ipairs(positions) do
                local dx, dy = x-p.x, y-p.y
                local dz = (zz or 0) - p.z
                local d2 = dx*dx+dy*dy+(dz*10)^2
                local dot = p.fx and p.fy and ((dx*p.fx+dy*p.fy)
                    / math.max(0.001, math.sqrt(dx*dx+dy*dy))) or nil
                local isForward = dot ~= nil and dot >= PRIORITY_FRONT_DOT
                -- Closest player decides range; within an equivalent band,
                -- prefer a player who is facing this zombie (MP safety).
                if not nearest or d2 < nearest then
                    nearest, forward = d2, isForward
                elseif nearest and math.abs(d2-nearest) < 4 and isForward then
                    forward = true
                end
            end
        end
        local tier = (not nearest and 3)
            or (nearest <= PRIORITY_NEAR_SQ and 0)
            or (nearest <= PRIORITY_MID_SQ and 1) or 2
        -- Escalate very old distant work without compromising startup priority.
        local age = Server._tick - (entry.queuedAt or Server._tick)
        if age >= 360 then tier = math.min(tier, 0)
        elseif age >= 180 then tier = math.min(tier, 1) end
        entry._priorityTier = tier
        entry._priorityFacing = forward and tier <= 1
        entry._priorityDistance = nearest or math.huge
    end
    -- Furthest first, nearest last: the queue is consumed back-to-front.
    table.sort(queue, function(a, b)
        if a._priorityTier ~= b._priorityTier then
            return a._priorityTier > b._priorityTier
        end
        -- With equal distance bands, dress zombies in the player's forward
        -- cone before zombies behind them, even when the rear zombie is closer.
        if a._priorityFacing ~= b._priorityFacing and a._priorityTier <= 1 then
            return (not a._priorityFacing) and b._priorityFacing
        end
        if a._priorityDistance ~= b._priorityDistance then
            return a._priorityDistance > b._priorityDistance
        end
        if a.phase ~= b.phase then
            return a.phase ~= "wardrobe_restore" -- restore wins a tie
        end
        return (a.queuedAt or 0) > (b.queuedAt or 0)
    end)
end

local function processPendingCostumes()
    if #Server._pendingDress == 0 then return end
    -- Include priority ordering in the same wall-clock budget as dressing.
    local processed, started = 0, deliveryNow()
    reorderPendingNearPlayers()
    -- Budget applies to the full set of expensive native model mutations, not
    -- just iteration count. Preserve the queued recipe and the one-tick settle
    -- delay when the early stage cannot run synchronously.
    for i = #Server._pendingDress, 1, -1 do
        if processed >= MAX_PENDING_PER_TICK then break end
        if processed > 0 and deliveryNow() - started >= PENDING_WORK_BUDGET_MS then
            Server._earlyDressStats.ticksBudgetExhausted = Server._earlyDressStats.ticksBudgetExhausted + 1
            break
        end
        local entry = Server._pendingDress[i]
        if entry.due <= Server._tick then
            table.remove(Server._pendingDress, i)
            processed = processed + 1
            local stats = Server._queuePriorityStats
            local tier = entry._priorityTier
            if tier == 0 then
                stats.near = stats.near + 1
                local waited = math.max(0, Server._tick - (entry.queuedAt or Server._tick))
                stats.nearWaitTotal = stats.nearWaitTotal + waited
                stats.nearWaitMax = math.max(stats.nearWaitMax, waited)
                if entry._priorityFacing then
                    stats.nearFront = stats.nearFront + 1
                    stats.nearFrontWaitTotal = stats.nearFrontWaitTotal + waited
                    stats.nearFrontWaitMax = math.max(stats.nearFrontWaitMax, waited)
                else
                    stats.nearOther = stats.nearOther + 1
                end
            elseif tier == 1 then stats.mid = stats.mid + 1
            elseif tier == 2 then stats.far = stats.far + 1
            else stats.unknown = stats.unknown + 1 end
            applyPendingCostume(entry)
        end
    end
end


local function queueWardrobeRestore(zombie)
    if not zombie or safeCall(zombie, "isAlive") ~= true then return false end
    local md = safeCall(zombie, "getModData")
    if not md or md.HalloweenEventSpawnQueued or md.HalloweenEventCostumed
        or md.HalloweenEventMatrixTrialID then return false end
    local record, recordID = Wardrobe.find(zombie)
    local costume = record and HWE.getCostumeByID(record.CostumeID)
    if not costume then return false end
    -- Do not change costume if this might actually be a player/worn-items
    -- entity or an already managed zombie. A record is only a lookup hint.
    if safeCall(zombie, "isUsingWornItems") == true then
        Wardrobe.noteWornSkip()
        return false
    end
    -- Reserve before queuing: two zombies in the same cell must not claim the
    -- same appearance record while waiting for the four-per-tick budget.
    Wardrobe.claim(zombie, recordID)
    md.HalloweenEventSpawnQueued = true
    md.HalloweenEventSeenVersion = HWE.VERSION
    Server._wardrobeStats.queued = Server._wardrobeStats.queued + 1
    local entry = {
        phase="wardrobe_restore", zombie=zombie, costume=costume, wardrobe=record,
        wardrobeID=recordID, due=Server._tick+PENDING_DELAY_TICKS,
        reason="wardrobe_restore", queuedAt=Server._tick
    }
    if immediateBudgetAvailable() then
        if applyPendingCostume(entry) then
            Server._earlyDressStats.immediateRestored = Server._earlyDressStats.immediateRestored + 1
            return true
        end
        -- A failed pre-render attempt gets exactly one normal queued retry;
        -- don't roll a different costume or release the reserved ledger ID.
        Server._earlyDressStats.immediateFailed = Server._earlyDressStats.immediateFailed + 1
        md.HalloweenEventSpawnQueued = true
    end
    Server._pendingDress[#Server._pendingDress+1] = entry
    Server._queuePriorityDirty = true
    Server._earlyDressStats.queuedRestored = Server._earlyDressStats.queuedRestored + 1
    local count = #Server._pendingDress
    if count > Server._earlyDressStats.maxPending then Server._earlyDressStats.maxPending = count end
    return true
end

function Server.scanLoadedZombies(cfg, forceAll, rerollManaged)
    if not isAuthoritative() then return 0, 0 end
    cfg = cfg or Server.config or HWE.readSandbox()
    local zombies = getZombieList()
    if not zombies then
        HWE.log("SCAN_RESULT loaded=0 reason=no_zombie_list")
        return 0, 0
    end

    local size = zombies:size()
    local queued = 0
    local skipped, galleryIncluded, wornSkipped = 0, 0, 0
    local candidates = {}

    -- Snapshot first; dressing happens after the scan, on the same objects.
    for i = 0, size - 1 do
        local zombie = zombies:get(i)
        if zombie and safeCall(zombie, "isAlive") == true then
            local md = safeCall(zombie, "getModData")
            local managed = md and md.HalloweenEventCostumed == true
            local usingWorn = safeCall(zombie, "isUsingWornItems") == true
            if USE_WARDROBE_LEDGER and not managed and queueWardrobeRestore(zombie) then
                skipped = skipped + 1
                managed = true -- skip a new random roll; restore is already queued
            end
            if managed and md.HalloweenEventCostumed == true then
                restoreExactVisualRecipe(zombie, HWE.getCostumeByID(md.HalloweenEventCostumeID))
                -- Preserve HWE zombies across patch-version bumps. A version bump
                -- should not create a full replacement wave by itself.
                md.HalloweenEventManagedVersion = HWE.VERSION
            end
            if md and md.HalloweenEventMatrixTrialID then
                skipped = skipped + 1
            elseif usingWorn then
                skipped, wornSkipped = skipped + 1, wornSkipped + 1
            elseif md and md.HalloweenEventGalleryTest == true and not rerollManaged then
                skipped = skipped + 1
            elseif managed and not rerollManaged then
                -- Force Start means "ignore costume chance for ordinary zombies";
                -- it must not reroll zombies that are already managed.
                skipped = skipped + 1
            else
                local dress = forceAll == true or rerollManaged == true or HWE.rollPercent(cfg.CostumeChancePercent)
                if dress then
                    local currentID = md and md.HalloweenEventCostumeID or nil
                    local costume = rerollManaged and HWE.pickDifferentCostume(zombie, currentID) or HWE.pickRandomCostume(zombie)
                    if costume then
                        candidates[#candidates + 1] = { zombie=zombie, costume=costume }
                        if md and md.HalloweenEventGalleryTest then galleryIncluded = galleryIncluded + 1 end
                    end
                elseif md then
                    md.HalloweenEventSeenVersion = HWE.VERSION
                end
            end
        end
    end

    for _, item in ipairs(candidates) do
        if queueDressing(item.zombie, item.costume, forceAll == true or rerollManaged == true, rerollManaged and "reroll_loaded" or (forceAll and "force_loaded" or "scan_loaded")) then
            queued = queued + 1
        end
    end

    HWE.log("SCAN_RESULT loaded=" .. tostring(size)
        .. " candidates=" .. tostring(#candidates)
        .. " queued=" .. tostring(queued)
        .. " skipped=" .. tostring(skipped)
        .. " galleryIncluded=" .. tostring(galleryIncluded)
        .. " wornSkipped=" .. tostring(wornSkipped)
        .. " force=" .. tostring(forceAll == true)
        .. " rerollManaged=" .. tostring(rerollManaged == true))
    return queued, size
end

function Server.sweepLoadedZombies()
    if not isAuthoritative() or not Server.active then return 0 end
    local zombies = getZombieList()
    if not zombies then return 0 end

    local size = zombies:size()
    if size <= 0 then return 0 end
    local index = Server._sweepCursor % size
    local inspected, queued = 0, 0

    while inspected < math.min(NATURAL_SWEEP_COUNT, size) do
        local zombie = zombies:get(index)
        if zombie and safeCall(zombie, "isAlive") == true then
            local md = safeCall(zombie, "getModData")
            if md and md.HalloweenEventGalleryTest ~= true
                and not md.HalloweenEventMatrixTrialID and md.HalloweenEventSpawnQueued ~= true then
                local managed = md.HalloweenEventCostumed == true
                if managed then
                    restoreExactVisualRecipe(zombie, HWE.getCostumeByID(md.HalloweenEventCostumeID))
                    applyCostumeBalance(zombie, HWE.getCostumeByID(md.HalloweenEventCostumeID))
                    md.HalloweenEventManagedVersion = HWE.VERSION
                end
                if USE_WARDROBE_LEDGER and not managed and queueWardrobeRestore(zombie) then
                    queued = queued + 1
                elseif not managed and md.HalloweenEventSeenVersion ~= HWE.VERSION then
                    local outfit = tostring(safeCall(zombie, "getOutfitName") or "")
                    local existing = (HWE.NativeOutfits and HWE.NativeOutfits.fromName(outfit))
                        or HWE.getNaturalCostumeByOutfit(outfit)
                    if existing then
                        HWE.tagSpawnedCostume(zombie, existing, "", 0)
                        restoreExactVisualRecipe(zombie, existing)
                        if prepareDeathLoot then prepareDeathLoot(zombie, existing) end
                        HWE.log("NATURAL_COSTUME_ALREADY_PRESENT id=" .. tostring(existing.id) .. " outfit=" .. outfit)
                    elseif HWE.rollPercent(Server.config.CostumeChancePercent) then
                        local costume = HWE.pickRandomCostume(zombie)
                        if costume and queueDressing(zombie, costume, false, "sweep") then
                            queued = queued + 1
                        end
                    else
                        md.HalloweenEventSeenVersion = HWE.VERSION
                    end
                end
            end
        end
        inspected = inspected + 1
        index = (index + 1) % size
    end

    Server._sweepCursor = index
    if queued > 0 then HWE.log("SWEEP_RESULT inspected=" .. tostring(inspected) .. " queued=" .. tostring(queued)) end
    return queued
end

-- ============================================================================
-- Death loot
-- ============================================================================

local function instanceItem(fullType)
    local factory = _G and _G.instanceItem or nil
    if type(factory) ~= "function" then return nil end
    local ok, item = pcall(factory, fullType)
    return ok and item or nil
end

local function addDeathItem(zombie, fullType)
    local item = instanceItem(fullType)
    if not item then
        HWE.log("DEATH_LOOT_ITEM_CREATE_FAILED type=" .. tostring(fullType))
        return false
    end
    local ok, err = HWE.tryCall(zombie, "addItemToSpawnAtDeath", item)
    if not ok then
        HWE.log("DEATH_LOOT_ITEM_FAILED type=" .. tostring(fullType) .. " error=" .. tostring(err))
        return false
    end
    return true
end

local function stripFirearms(zombie)
    local removed, visited = 0, {}
    local function stripContainer(container, depth)
        if not container or visited[container] or depth > 4 then return end
        visited[container] = true
        local items = safeCall(container, "getItems")
        for i = (tonumber(safeCall(items, "size")) or 0) - 1, 0, -1 do
            local item = safeCall(items, "get", i)
            if safeCall(item, "isRanged") == true then
                if HWE.tryCall(container, "DoRemoveItem", item) then removed = removed + 1 end
            else stripContainer(safeCall(item, "getItemContainer"), depth + 1) end
        end
    end
    local attached = safeCall(zombie, "getAttachedItems")
    for i = (tonumber(safeCall(attached, "size")) or 0) - 1, 0, -1 do
        local item = safeCall(attached, "getItemByIndex", i)
        if safeCall(item, "isRanged") == true then
            if HWE.tryCall(zombie, "removeAttachedItem", item) then removed = removed + 1 end
        end
    end
    for _, hand in ipairs({{"getPrimaryHandItem","setPrimaryHandItem"}, {"getSecondaryHandItem","setSecondaryHandItem"}}) do
        if safeCall(safeCall(zombie, hand[1]), "isRanged") == true then
            if HWE.tryCall(zombie, hand[2], nil) then removed = removed + 1 end
        end
    end
    stripContainer(safeCall(zombie, "getInventory"), 0)
    if removed > 0 then
        HWE.tryCall(zombie, "resetModelNextFrame")
        HWE.log("POLICE_FIREARMS_REMOVED onlineID=" .. tostring(safeCall(zombie, "getOnlineID")) .. " records=" .. removed)
    end
end

local function santaImpaledWeapon()
    local pool = HWE.SantaImpaledWeapons or {}
    if #pool == 0 then return nil end
    local first = ZombRand(1, #pool + 1)
    for offset = 0, #pool - 1 do
        local fullType = pool[(first + offset - 1) % #pool + 1]
        local item = instanceItem(fullType)
        local model = item and safeCall(item, "getStaticModel")
        if item and model and tostring(model) ~= "" and safeCall(item, "getID") ~= nil
            and HWE.tryCall(item, "setCondition", HWE.SantaImpaledCondition or 1)
            and safeCall(item, "getCondition") == (HWE.SantaImpaledCondition or 1) then return item end
        HWE.log("SANTA_IMPALED_ITEM_SKIP type=" .. fullType .. " model=" .. tostring(model))
    end
    return nil
end

applyCostumeBalance = function(zombie, costume)
    if not zombie or not costume then return end
    if costume.noFirearms then stripFirearms(zombie) end
    if safeCall(zombie, "isAlive") ~= true then return end
    local md = safeCall(zombie, "getModData")
    if not md then return end
    local masked = false
    for _, mask in ipairs(costume.optionalItems or {}) do
        if HWE.hasVisualType(zombie, mask) then masked = true; break end
    end
    local attachedKnife = safeCall(zombie, "getAttachedItem", "Knife in Back")
    local owned = md.HalloweenEventSantaKnifeAttachmentID and attachedKnife
        and safeCall(attachedKnife, "getID") == md.HalloweenEventSantaKnifeAttachmentID
    if not costume.santaKnifeFallback or masked then
        if owned then
            HWE.tryCall(zombie, "removeAttachedItem", attachedKnife)
            md.HalloweenEventSantaKnifeAttachmentID = nil
            HWE.tryCall(zombie, "resetModelNextFrame")
        end
        return
    end
    if owned then
        if HWE.isSantaImpaledType(safeCall(attachedKnife, "getFullType")) then return end
        -- Upgrade only our FIX12 butter knife; never remove a foreign attachment.
        HWE.tryCall(zombie, "removeAttachedItem", attachedKnife)
        attachedKnife = safeCall(zombie, "getAttachedItem", "Knife in Back")
        if attachedKnife then return end
        md.HalloweenEventSantaKnifeAttachmentID = nil
    end
    if md.HalloweenEventSantaKnifeQueued then return end
    local group = safeCall(zombie, "getAttachedLocationGroup")
    local location = safeCall(group, "getLocation", "Knife in Back")
    local weapon = santaImpaledWeapon()
    if not weapon then return end
    if not attachedKnife and location then
        local ok = HWE.tryCall(zombie, "setAttachedItem", "Knife in Back", weapon)
        if ok and safeCall(zombie, "getAttachedItem", "Knife in Back") == weapon then
            md.HalloweenEventSantaKnifeAttachmentID = safeCall(weapon, "getID")
            HWE.tryCall(zombie, "resetModelNextFrame")
            HWE.log("SANTA_HALLOWEEN_FALLBACK id=" .. costume.id .. " mode=attached type=" .. safeCall(weapon, "getFullType")
                .. " condition=" .. tostring(safeCall(weapon, "getCondition")) .. " model=" .. tostring(safeCall(weapon, "getStaticModel"))
                .. " attachment=" .. tostring(safeCall(location, "getAttachmentName")))
            return
        end
    end
    -- Attached weapons become corpse loot. Only queue the same nearly broken
    -- item when the attachment slot is unavailable; no second attached copy.
    if HWE.tryCall(zombie, "addItemToSpawnAtDeath", weapon) then
        md.HalloweenEventSantaKnifeQueued = true
        HWE.log("SANTA_HALLOWEEN_FALLBACK id=" .. costume.id .. " mode=corpse_queue type=" .. safeCall(weapon, "getFullType")
            .. " condition=" .. tostring(safeCall(weapon, "getCondition")))
    end
end

local function fillContainerWithCandy(container, count)
    local itemContainer = container and (safeCall(container, "getItemContainer") or safeCall(container, "getInventory"))
    if not itemContainer then return 0 end
    local added = 0
    for _ = 1, count do
        local candy = REAL_VANILLA_CANDY[ZombRand(1, #REAL_VANILLA_CANDY + 1)]
        local ok = pcall(function() itemContainer:AddItem(candy) end)
        if ok then added = added + 1 end
    end
    return added
end

local function addDeathContainer(zombie, cfg)
    local fullType
    if HWE.rollPercent(cfg.CollectibleContainerChancePercent or 0) then
        fullType = ItemLoot.choose(EVENT_CONTAINERS)
        if not fullType then fullType=VANILLA_TREAT_BAGS[ZombRand(1,#VANILLA_TREAT_BAGS+1)] end
    else
        fullType = VANILLA_TREAT_BAGS[ZombRand(1, #VANILLA_TREAT_BAGS + 1)]
    end

    local item = instanceItem(fullType)
    if not item then
        HWE.log("DEATH_LOOT_CONTAINER_CREATE_FAILED type=" .. tostring(fullType))
        return false
    end

    local candyCount = 0
    if HWE.rollPercent(cfg.BagCandyChancePercent or 0) then
        candyCount = fillContainerWithCandy(item, HWE.rand(cfg.MinBagCandy, cfg.MaxBagCandy))
    end

    local ok, err = HWE.tryCall(zombie, "addItemToSpawnAtDeath", item)
    if not ok then
        HWE.log("DEATH_LOOT_CONTAINER_QUEUE_FAILED type=" .. tostring(fullType) .. " error=" .. tostring(err))
        return false
    end
    HWE.log("DEATH_LOOT_CONTAINER_QUEUED type=" .. tostring(fullType) .. " candy=" .. tostring(candyCount))
    return true
end

prepareDeathLoot = function(zombie, costume)
    if not zombie or not costume then return 0 end
    applyCostumeBalance(zombie, costume)
    local md = safeCall(zombie, "getModData")
    if not md or md.HalloweenEventLootPrepared == true then return 0 end

    -- addItemToSpawnAtDeath must be queued while the zombie is alive. Doing
    -- this from OnZombieDead is too late for the corpse inventory build.
    md.HalloweenEventLootPrepared = true
    local cfg = Server.config or HWE.readSandbox()
    local awarded = 0

    if HWE.rollPercent(cfg.CandyDropChancePercent or 0) then
        local count = HWE.rand(1, 3)
        for _ = 1, count do
            if addDeathItem(zombie, REAL_VANILLA_CANDY[ZombRand(1, #REAL_VANILLA_CANDY + 1)]) then awarded = awarded + 1 end
        end
    end
    if HWE.rollPercent(cfg.BagChancePercent or 0) and addDeathContainer(zombie, cfg) then awarded = awarded + 1 end
    if HWE.rollPercent(cfg.DecorationChanceOnZombiePercent or 0) then
        local ft=ItemLoot.choose(EVENT_DECOR)
        if ft and addDeathItem(zombie,ft) then awarded=awarded+1 end
    end

    HWE.log("DEATH_LOOT_PREPARED costume=" .. tostring(costume.id) .. " queuedItems=" .. tostring(awarded))
    return awarded
end

local function preserveJasonDeathColor(zombie, md)
    if not md or md.HalloweenEventCostumeID~="JasonSlasher" then return end
    local snapshot=md.HalloweenEventVisualSnapshot
    local tint
    for index,fullType in ipairs(snapshot and snapshot.Items or {}) do
        if fullType=="Base.Boilersuit" then
            local appearance=snapshot.Appearance and snapshot.Appearance[index]
            tint=appearance and appearance.Tint
            break
        end
    end
    local r,g,b=tonumber(tint and tint[1]),tonumber(tint and tint[2]),tonumber(tint and tint[3])
    if not r or not g or not b or not (r>=0 and r<=1 and g>=0 and g<=1 and b>=0 and b<=1) then
        HWE.log("JASON_DEATH_COLOR_SKIPPED reason=no_saved_tint")
        return
    end
    -- DoZombieInventory creates NEW worn items before OnZombieDead. Its
    -- visual copy does not carry the live item's customColor/RGB fields.
    -- Repair the actual worn coveralls, shared with the corpse inventory,
    -- before the body and its network packet are built. Keep damage/texture.
    local worn=safeCall(zombie,"getWornItems")
    for i=0,(tonumber(safeCall(worn,"size")) or 0)-1 do
        local item=safeCall(worn,"getItemByIndex",i)
        if safeCall(item,"getFullType")=="Base.Boilersuit" then
            local ok,err=pcall(function()
                local visual=item:getVisual()
                local color=item:getColor():scaleCopy(1)
                color:set(r,g,b,1)
                item:setColorRed(r);item:setColorGreen(g);item:setColorBlue(b)
                item:setColor(color);item:setCustomColor(true)
                visual:setTint(ImmutableColor.new(r,g,b))
            end)
            HWE.log(ok and ("JASON_DEATH_COLOR_PRESERVED rgb="..r..","..g..","..b)
                or ("JASON_DEATH_COLOR_FAILED error="..tostring(err)))
        end
    end
end

local function onZombieDead(zombie)
    Wardrobe.onDeath(zombie)
    local md = safeCall(zombie, "getModData")
    preserveJasonDeathColor(zombie,md)
    local costume = md and HWE.getCostumeByID(md.HalloweenEventCostumeID)
    if costume then applyCostumeBalance(zombie, costume) end
    if not zombie then return end
    local md = safeCall(zombie, "getModData")
    if md and md.HalloweenEventCostumed == true and md.HalloweenEventLootPrepared ~= true then
        HWE.log("DEATH_LOOT_NOT_PREPARED costume=" .. tostring(md.HalloweenEventCostumeID or "unknown"))
    end
end

-- ============================================================================
-- Event state / commands
-- ============================================================================

function Server.status()
    return {
        active = Server.active == true,
        manualOverride = Server.runtimeManualOverride,
        version = HWE.VERSION,
        costumes = #(HWE.Costumes or {}),
        reason = Server._lastStateReason
    }
end

function Server.cleanupLoadedZombies()
    local zombies = getZombieList()
    if not zombies then return 0 end

    -- Ending the event stops NEW costume conversion but does not despawn/redress
    -- zombies already in costume. This avoids a second full replacement wave
    -- when the event is stopped and started again.
    local preserved = 0
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        local md = zombie and safeCall(zombie, "getModData")
        if zombie and md and md.HalloweenEventCostumed == true then
            md.HalloweenEventManagedVersion = HWE.VERSION
            if not md.HalloweenEventWardrobeID then
                local existingCostume = HWE.getCostumeByID(md.HalloweenEventCostumeID)
                if existingCostume then Wardrobe.record(zombie, existingCostume) end
            end
            md.HalloweenEventSpawnQueued = nil
            md.HalloweenEventInactivePreserved = true
            preserved = preserved + 1
        end
    end

    -- Cancelling pending dressing never removes or spawns a zombie.
    local pending = Server._pendingDress or {}
    for _, entry in ipairs(pending) do
        if entry.phase ~= "wardrobe_restore" and entry.zombie then
            local md = safeCall(entry.zombie, "getModData")
            if md then md.HalloweenEventSpawnQueued = nil end
        end
    end
    local keptRestores = {}
    for _, entry in ipairs(Server._pendingDress) do
        if entry.phase == "wardrobe_restore" then keptRestores[#keptRestores+1] = entry end
    end
    Server._pendingDress = keptRestores

    HWE.log("CLEANUP_RESULT preserved=" .. tostring(preserved)
        .. " behavior=keep_existing_costumes")
    return preserved
end

function Server.setActive(active, reason, forceLoaded)
    if not isAuthoritative() then return false end
    active = active == true
    Server.config = HWE.readSandbox()
    Server._lastStateReason = reason or "state_change"

    local changed = Server.active ~= active
    if changed and not active then Server.cleanupLoadedZombies() end
    Server.active = active
    Announcement.transition(active, changed, Server.config)

    if changed then
        Server._sweepCursor = 0
        if not active then
            -- Event shutdown must not cancel restoration of existing costumes.
            local existingRestores = {}
            for _, entry in ipairs(Server._pendingDress) do
                if entry.phase == "wardrobe_restore" then existingRestores[#existingRestores+1] = entry end
            end
            Server._pendingDress = existingRestores
        end
    end

    HWE.log("EVENT_STATE active=" .. tostring(active) .. " reason=" .. tostring(reason or "state_change") .. " changed=" .. tostring(changed))

    if active and forceLoaded then
        -- Queue the conversion and let OnTick spread it over a few frames.
        -- This spreads visual updates over a few frames without spawning zombies.
        Server.scanLoadedZombies(Server.config, true, false)
    end

    -- Never broadcast before networking is ready. At startup getOnlinePlayers()
    -- is empty/unavailable, which avoids the GameServer.udpEngine NPE seen in logs.
    local players = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    if type(sendServerCommand) == "function" and players and type(players.size) == "function" and players:size() > 0 then
        pcall(sendServerCommand, HWE.MOD_ID, "EventState", {
            active = active, reason = reason or "state_change", version = HWE.VERSION
        })
    end
    return changed
end

function Server.refresh(reason)
    if not isAuthoritative() then return Server.active end
    Server.config = HWE.readSandbox()
    local desired,edgeReason,clearManual,rollover=ScheduleControl.evaluate(Server.config,Server.active)
    if clearManual then Server.runtimeManualOverride=nil end
    if rollover and Server.active then Server.setActive(false,"schedule_end",false) end

    -- The minute event is only a calendar/config check. Do not reset queues,
    -- rebroadcast, or log when the active state has not changed.
    if desired == Server.active then
        -- Also reconcile an inactive save on startup, so its next start announces.
        Announcement.transition(desired, false, Server.config)
        return desired
    end

    Server.setActive(desired, edgeReason or reason or "refresh", desired == true)
    return desired
end

function Server.startEvent(reason)
    local cfg=HWE.readSandbox()
    if not cfg.EnableEvent then
        HWE.log("START_EVENT_BLOCKED masterDisabled=true")
        return false
    end
    Server.runtimeManualOverride = true
    ScheduleControl.force(true,cfg)
    Server.setActive(true, reason or "manual_start", true)
    HWE.log("START_EVENT_RESULT active=" .. tostring(Server.active))
end

function Server.endEvent(reason)
    Server.runtimeManualOverride = false
    ScheduleControl.force(false,HWE.readSandbox())
    Server.setActive(false, reason or "manual_end", false)
end

function Server.clearManualOverride(reason)
    Server.runtimeManualOverride = nil
    ScheduleControl.resume()
    HWE.log("MANUAL_OVERRIDE_CLEARED reason=" .. tostring(reason or "admin"))
    Server.refresh("clear_override")
end

function Server.cleanSlate()
    Server.runtimeManualOverride=nil
    ScheduleControl.clean(HWE.readSandbox())
    Server.setActive(false,"clean_slate",false)
end

function Server.spawnCostume(player, costume, requestedFemaleChance)
    if not player or not costume then return 0 end
    local femaleChance = HWE.getCostumeFemaleChance(nil, costume, false)
    local requested = tonumber(requestedFemaleChance)
    if costume.femaleOnly ~= true and costume.maleOnly ~= true and (requested == 0 or requested == 100) then
        femaleChance = requested
    end
    return spawnCostumeAt(player:getX() + 2.0, player:getY() + 1.5, player:getZ(), costume, femaleChance, "gallery_single", {player=player})
end

function Server.spawnCostumeByID(player, costumeID, requestedFemaleChance)
    local costume = HWE.getCostumeByID(costumeID)
    if not costume then
        HWE.log("GALLERY_UNKNOWN_COSTUME id=" .. tostring(costumeID))
        return 0
    end
    return Server.spawnCostume(player, costume, requestedFemaleChance)
end

function Server.spawnCostumeGallery(player)
    if not player then return 0 end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local spawned = 0
    for idx, costume in ipairs(HWE.Costumes or {}) do
        local col = (idx - 1) % 6
        local row = math.floor((idx - 1) / 6)
        local sx = px + (col * 2.0) - 5.0
        local sy = py + (row * 2.5) + 3.0
        local femaleChance = HWE.getCostumeFemaleChance(nil, costume, false)
        spawned = spawned + spawnCostumeAt(sx, sy, pz, costume, femaleChance, "gallery_all", {player=player})
    end
    HWE.log("GALLERY_SPAWN_ALL profiles=" .. tostring(#(HWE.Costumes or {})) .. " spawned=" .. tostring(spawned))
    return spawned
end

local function findLoadedZombieByOnlineID(onlineID)
    local targetID = tonumber(onlineID)
    local zombies = getZombieList()
    if targetID == nil or not zombies then return nil end
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie and safeCall(zombie, "isAlive") == true then
            if tonumber(safeCall(zombie, "getOnlineID") or -1) == targetID then return zombie end
        end
    end
    return nil
end

local function findLoadedZombieNear(x, y, z)
    x, y, z = tonumber(x), tonumber(y), tonumber(z or 0)
    local zombies = getZombieList()
    if not x or not y or not zombies then return nil end
    local best, bestDistance = nil, 2.0
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie and safeCall(zombie, "isAlive") == true then
            local zx = tonumber(safeCall(zombie, "getX") or 0)
            local zy = tonumber(safeCall(zombie, "getY") or 0)
            local zz = tonumber(safeCall(zombie, "getZ") or 0)
            if math.abs(zz - z) < 0.5 then
                local d = math.abs(zx - x) + math.abs(zy - y)
                if d < bestDistance then best, bestDistance = zombie, d end
            end
        end
    end
    return best
end

function Server.handleAdminCommand(command, player, args)
    if not isAuthoritative() then return false end
    command, args = tostring(command or ""), args or {}

    if command=="AnnouncementSync" then return Announcement.sync(player) end
    if command=="AnnouncementSeen" then return Announcement.acknowledge(player,args) end

    if command=="ScheduleClock" then
        -- Read-only clock response, sent to the requesting client only.
        local now=HWE.Schedule.now()
        if player and now and type(sendServerCommand)=="function" then
            Server._clockRequests=Server._clockRequests or {}
            local id=tostring(safeCall(player,"getOnlineID") or player)
            local last=Server._clockRequests[id]
            if not last or now<last or now-last>=5 then
                Server._clockRequests[id]=now
                pcall(sendServerCommand,player,HWE.MOD_ID,"ScheduleClock",{epoch=now,zone="UTC"})
            end
        end
        return true
    end

    if command == "SyncState" or command == "Status" then
        local status = Server.status()
        if type(sendServerCommand) == "function" then pcall(sendServerCommand, HWE.MOD_ID, "Status", status) end
        return true
    end

    if command == "CostumeVisualAck" then
        local entry = args.Token and Server._galleryDelivery[tostring(args.Token)]
        local watcher = entry and entry.watchers[player]
        if not watcher or entry.onlineID ~= tonumber(args.OnlineID) or entry.revision ~= tonumber(args.Revision) then return false end
        local status = tostring(args.Status or "")
        if status == "announced" then watcher.announced = true
        elseif status == "unloaded" then
            local now = deliveryNow()
            if watcher.loaded or watcher.applied or not nearPlayer(player, entry.zombie)
                or now - entry.started < 5000 or now - entry.started >= 15000 then return false end
            if not watcher.lastMissing or now - watcher.lastMissing >= 1000 then
                watcher.missingCount = (watcher.missingCount or 0) + 1
                watcher.lastMissing = now
                watcher.announced = true
            end
            if allWatchersUnloaded(entry) and not Server._gallerySpawns[entry.token] then
                local request, zombie = entry.request, entry.zombie
                local md = safeCall(zombie, "getModData")
                if md and md.HalloweenEventGalleryTest and safeCall(zombie, "isAlive") == true
                    and md.HalloweenEventVisualToken == entry.token and md.HalloweenEventVisualRevision == entry.revision then
                    Server._gallerySpawns[entry.token] = {
                        zombie=zombie, costume=entry.costume, player=request.player, attempt=request.attempt,
                        onlineID=entry.onlineID, persistent=safeCall(zombie, "getPersistentOutfitID"),
                        token=entry.token, revision=entry.revision, x=request.x, y=request.y, z=request.z,
                        femaleChance=request.femaleChance, reason=request.reason, clientUnloaded=true,
                        due=now+250, deadline=now+250, expires=now+5000
                    }
                    HWE.log("GALLERY_CLIENT_ABSENCE_CONFIRMED id=" .. entry.costume.id .. " onlineID=" .. entry.onlineID)
                end
            end
        elseif status == "loaded" then watcher.announced, watcher.loaded = true, true
        elseif status == "applied" then
            if not watcher.applied then
                HWE.log("GALLERY_DELIVERY_CONFIRMED id=" .. entry.costume.id .. " onlineID=" .. tostring(entry.onlineID)
                    .. " revision=" .. tostring(entry.revision) .. " elapsedMs=" .. tostring(math.floor(deliveryNow()-entry.started)))
            end
            watcher.announced, watcher.loaded, watcher.applied = true, true, true
        else return false end
        if status == "loaded" or status == "applied" then
            local native = Server._gallerySpawns[entry.token]
            if native then native.clientLoaded = true end
        end
        return true
    end

    if command == "ResolveCostumeVisuals" then
        if not player or type(args.IDs) ~= "table" or not tonumber(args.RequestID) then return false end
        local result, requested = {}, {}
        for i = 1, math.min(#args.IDs, 32) do
            local id = tonumber(args.IDs[i])
            if id and id >= 0 then requested[id] = true end
        end
        local zombies = getZombieList()
        if zombies then
            for i = 0, zombies:size() - 1 do
                local zombie = zombies:get(i)
                local id = zombie and tonumber(safeCall(zombie, "getOnlineID"))
                if id and requested[id] and safeCall(zombie, "isAlive") == true and nearPlayer(player, zombie) then
                    local md = safeCall(zombie, "getModData")
                    local isMatrix = md and md.HalloweenEventMatrixTrialID ~= nil
                    local costume = not isMatrix and md and HWE.getCostumeByID(md.HalloweenEventCostumeID)
                    if costume then restoreExactVisualRecipe(zombie, costume) end
                    local state = costume and visualState(zombie, costume)
                    local observation = type(args.Observations)=="table" and args.Observations[tostring(id)]
                    local confirmed
                    if state and not state.Gallery and type(observation)=="table" and observation.Token==state.Token then
                        local x,y,z,persistent=tonumber(observation.X),tonumber(observation.Y),tonumber(observation.Z),tonumber(observation.PersistentID)
                        if x and y and z and persistent and persistent==math.floor(persistent)
                            and (x-state.X)^2+(y-state.Y)^2<=64 and math.abs(z-state.Z)<0.5 then
                            confirmed={Token=state.Token,PersistentID=persistent,X=x,Y=y,Z=z}
                        end
                    end
                    result[#result + 1] = {OnlineID=id, Found=true, Pending=md and md.HalloweenEventSpawnQueued == true,
                        State=state, WorldIdentityConfirmed=confirmed}
                    requested[id] = nil
                end
            end
        end
        -- Explicit no-profile/missing results end ordinary-zombie probe retries.
        for id in pairs(requested) do result[#result + 1] = {OnlineID=id, Found=false} end
        if type(sendServerCommand) == "function" then
            pcall(sendServerCommand, player, HWE.MOD_ID, "CostumeVisualBatch", {Entries=result, RequestID=args.RequestID})
        end
        return true
    end

    if not isAdmin(player) then
        HWE.log("COMMAND_REJECTED not_admin command=" .. command)
        return false
    end

    if command == "CleanSlate" then
        Server.cleanSlate()
        return true
    elseif command == "SandboxApplied" then
        -- Native sandbox packet and this command may arrive in either order.
        Server._sandboxApply={expected=args,due=(HWE.Schedule.now() or 0)+1,expires=(HWE.Schedule.now() or 0)+6}
        return true
    elseif command == "ResetAnnouncements" then
        return Announcement.reset(player,HWE.readSandbox())
    elseif command == "StartEvent" then
        return Server.startEvent("admin")~=false
    elseif command == "EndEvent" then
        Server.endEvent("admin")
        return true
    elseif command == "ClearManualOverride" then
        Server.clearManualOverride("admin")
        return true
    elseif command == "DressNow" then
        local queued = Server.scanLoadedZombies(Server.config, true, true)
        HWE.log("DRESS_NOW_RESULT queued=" .. tostring(queued))
        return queued > 0
    elseif command == "RunPersistenceMatrix" then
        return Matrix.start(player, getZombieList())
    elseif command == "PersistenceMatrixStatus" then
        Matrix.status()
        return true
    elseif command == "ClearPersistenceMatrix" then
        return Matrix.clear(getZombieList())
    elseif command == "SpawnAllCostumes" then
        return Server.spawnCostumeGallery(player) > 0
    elseif command == "SpawnCostume" then
        local spawned = Server.spawnCostumeByID(player, args.CostumeID, args.FemaleChance)
        HWE.log("SPAWN_COSTUME_COMMAND_RESULT id=" .. tostring(args.CostumeID) .. " spawned=" .. tostring(spawned))
        return spawned > 0
    elseif command == "DressZombie" then
        local costume = HWE.getCostumeByID(args.CostumeID)
        if not costume then return false end
        local zombie = args.OnlineID ~= nil and findLoadedZombieByOnlineID(args.OnlineID) or nil
        if not zombie then zombie = findLoadedZombieNear(args.X, args.Y, args.Z) end
        if not zombie then
            HWE.log("DRESS_TARGET_NOT_FOUND costume=" .. tostring(costume.id))
            return false
        end
        local queued = queueDressing(zombie, costume, true, "target")
        HWE.log("DRESS_TARGET_RESULT costume=" .. tostring(costume.id) .. " queued=" .. tostring(queued))
        return queued
    end

    HWE.log("COMMAND_UNKNOWN command=" .. command)
    return false
end

local function onClientCommand(module, command, player, args)
    if not isAuthoritative() or module ~= HWE.MOD_ID then return end
    if command == "MatrixClientResult" then
        -- No gameplay authority: diagnostic response only, tied to a pending
        -- server-issued trial + online ID. Ignore arbitrary client payloads.
        if isAdmin(player) then Matrix.receiveClientProbe(player, args) end
        return
    end
    if command ~= "ResolveCostumeVisuals" and command ~= "CostumeVisualAck" then HWE.log("CLIENT_COMMAND command=" .. tostring(command)) end
    Server.handleAdminCommand(command, player, args)
end

local function onZombieCreate(zombie)
    if not isAuthoritative() or not zombie or Server._spawningCostume then return end
    -- Inspect a confirmed test subject BEFORE any automatic random dress or
    -- ledger restoration. One shot, without modifying its reloaded outfit.
    if Matrix.observeCreated(zombie, Server._tick) then return end
    local savedMD = safeCall(zombie, "getModData")
    local savedCostume = savedMD and HWE.getCostumeByID(savedMD.HalloweenEventCostumeID)
    if safeCall(zombie, "isUsingWornItems") == true then
        if savedCostume then restoreExactVisualRecipe(zombie, savedCostume) end
        return
    end
    if savedCostume and safeCall(zombie, "isAlive") == true then
        if savedCostume.recipeRevision and savedMD.HalloweenEventVisualRecipeVersion ~= HWE.VERSION then
            restoreExactVisualRecipe(zombie, savedCostume)
            applyCostumeBalance(zombie, savedCostume)
            return
        end
        local recipe = ((savedMD.HalloweenEventVisualRecipeVersion == HWE.VERSION or
            savedMD.HalloweenEventVisualRecipeVersion == "0.6.5-fix16" or
            savedMD.HalloweenEventVisualRecipeVersion == "0.6.5-fix15" or
            savedMD.HalloweenEventVisualRecipeVersion == "0.6.5-fix14" or
            savedMD.HalloweenEventVisualRecipeVersion == "0.6.5-fix13" or
            savedMD.HalloweenEventVisualRecipeVersion == "0.6.5-fix12" or
            savedMD.HalloweenEventVisualRecipeVersion == "0.6.5-fix11" or
            savedMD.HalloweenEventVisualRecipeVersion == "0.6.5-fix10" or
            savedMD.HalloweenEventVisualRecipeVersion == "0.6.5-fix9" or
            savedMD.HalloweenEventVisualRecipeVersion == "0.6.5-fix8" or
            savedMD.HalloweenEventVisualRecipeVersion == "0.6.5-fix7") and
            HWE.snapshotRecipe(savedCostume, savedMD.HalloweenEventVisualSnapshot)) or
            (savedCostume.visualItems and savedCostume)
        if recipe then
            local ok, err = HWE.applyCostumeVisuals(zombie, recipe, "server_reload")
            if ok then
                saveVisualState(zombie, savedCostume)
                broadcastCostumeVisual(zombie, savedCostume)
            else HWE.log("VISUAL_RESTORE_FAIL id=" .. savedCostume.id .. " error=" .. tostring(err)) end
        else restoreExactVisualRecipe(zombie, savedCostume) end
        applyCostumeBalance(zombie, savedCostume)
        return
    end
    -- Test whether the engine actually restores a native HWE outfit identity
    -- BEFORE the event chance roll. This works even with the event disabled.
    local nativeName = tostring(safeCall(zombie,"getOutfitName") or "")
    local recovered = HWE.NativeOutfits and HWE.NativeOutfits.fromName(nativeName)
    if recovered and safeCall(zombie,"isAlive") == true then
        Server._nativeStats.nativeReload = Server._nativeStats.nativeReload + 1
        HWE.tagSpawnedCostume(zombie, recovered, "", 0)
        if not HWE.verifyCostume(zombie, recovered) then
            restoreExactVisualRecipe(zombie, recovered)
        end
        if prepareDeathLoot then prepareDeathLoot(zombie, recovered) end
        saveVisualState(zombie, recovered)
        broadcastCostumeVisual(zombie, recovered)
        return
    end
    -- Ledger is dormant for this experiment; stored v16 data remains intact.
    if USE_WARDROBE_LEDGER and queueWardrobeRestore(zombie) then return end
    if not Server.active then return end
    if safeCall(zombie, "isAlive") ~= true then return end

    local md = safeCall(zombie, "getModData")
    if not md or md.HalloweenEventCostumed == true or md.HalloweenEventGalleryTest == true then return end
    if md.HalloweenEventSpawnQueued == true or md.HalloweenEventSeenVersion == HWE.VERSION then return end

    local outfit = tostring(safeCall(zombie, "getOutfitName") or "")
    local existing = (HWE.NativeOutfits and HWE.NativeOutfits.fromName(outfit))
        or HWE.getNaturalCostumeByOutfit(outfit)
    if existing then
        HWE.tagSpawnedCostume(zombie, existing, "", 0)
                        restoreExactVisualRecipe(zombie, existing)
        if prepareDeathLoot then prepareDeathLoot(zombie, existing) end
        HWE.log("NATURAL_COSTUME_ALREADY_PRESENT id=" .. tostring(existing.id) .. " outfit=" .. outfit .. " reason=create")
        return
    end

    if not HWE.rollPercent(Server.config.CostumeChancePercent) then
        md.HalloweenEventSeenVersion = HWE.VERSION
        return
    end

    local costume = HWE.pickRandomCostume(zombie)
    if costume then
        if immediateBudgetAvailable() then
            if dressWorldZombie(zombie, costume, "create_immediate") then
                md.HalloweenEventSeenVersion = HWE.VERSION
                Server._earlyDressStats.immediateDressed = Server._earlyDressStats.immediateDressed + 1
                return
            end
            Server._earlyDressStats.immediateFailed = Server._earlyDressStats.immediateFailed + 1
        end
        if queueDressing(zombie, costume, false, "create") then
            Server._earlyDressStats.queuedDressed = Server._earlyDressStats.queuedDressed + 1
            local count = #Server._pendingDress
            if count > Server._earlyDressStats.maxPending then Server._earlyDressStats.maxPending = count end
            -- Counted in STARTUP_DRESS_SUMMARY; no per-zombie text log.
        end
    else
        md.HalloweenEventSeenVersion = HWE.VERSION
    end
end

function Server.pollScheduleClock()
    if not isAuthoritative() then return end
    local now=HWE.Schedule.now()
    if not now or Server._scheduleClockSecond==now then return end
    Server._scheduleClockSecond=now
    if Server._sandboxApply and now>=Server._sandboxApply.due then
        local pending=Server._sandboxApply
        local sb=SandboxVars and SandboxVars.HalloweenEvent or {}
        local matches=true
        for _,field in ipairs({"EnableEvent","UseCalendarTrigger","ScheduleClock","StartSchedule","EndSchedule"}) do
            if pending.expected[field]~=nil and tostring(pending.expected[field])~=tostring(sb[field]) then matches=false end
        end
        if matches then
            ScheduleControl.noteApplied();Server._sandboxApply=nil
        elseif now>=pending.expires then
            Server._sandboxApply=nil
            HWE.log("SANDBOX_APPLY_WAIT_EXPIRED currentServerSettingsRetained=true")
        end
    end
    local sb=SandboxVars and SandboxVars.HalloweenEvent or {}
    local mode=tonumber(sb.ScheduleClock)==2 and 2 or 1
    Server._scheduleClockMode=mode
    if mode==2 then
        local key=tostring(sb.StartSchedule)..":"..tostring(sb.EndSchedule)..":"..tostring(sb.EnableEvent)
            ..":"..tostring(sb.UseCalendarTrigger)..":"..tostring(Server.runtimeManualOverride)
        if key~=Server._scheduleDiagnostic then
            Server._scheduleDiagnostic=key
            local cfg=HWE.readSandbox()
            local window,err=HWE.Schedule.resolve(cfg,now)
            HWE.log("SCHEDULE_CHECK clock=UTC now="..HWE.Schedule.format(now)
                .." enabled="..tostring(cfg.EnableEvent).." automatic="..tostring(cfg.UseCalendarTrigger)
                .." manualOverride="..tostring(Server.runtimeManualOverride)
                .." start="..string.format("%q",tostring(cfg.StartSchedule):sub(1,120))
                .." end="..string.format("%q",tostring(cfg.EndSchedule):sub(1,120))
                ..(err and (" invalid="..err) or (" windowStart="..HWE.Schedule.format(window.start)
                    .." windowEnd="..HWE.Schedule.format(window.finish).." inWindow="..tostring(window.active))))
        end
    else Server._scheduleDiagnostic=nil end
    -- Both clocks need config reconciliation and boundary checks. Game time
    -- is still sampled from GameTime, never from this wall-clock gate.
    Server.refresh(mode==2 and "UTC_clock" or "game_clock")
end

local function onTick()
    if not isAuthoritative() then return end
    Server._tick = Server._tick + 1
    processPendingCostumes()
    Matrix.tick(runPersistenceMatrixCase, Server._tick)
    processGallerySpawns()
    processGalleryDelivery()
    local checks = Server._visualChecks
    for i = #checks, 1, -1 do
        local entry = checks[i]
        if Server._tick >= entry.due then
            local zombie, costume = entry.zombie, entry.costume
            local md = safeCall(zombie, "getModData")
            if safeCall(zombie, "isAlive") == true and md and md.HalloweenEventCostumeID == costume.id
                and md.HalloweenEventVisualToken == entry.token and md.HalloweenEventVisualRevision == entry.revision then
                applyCostumeBalance(zombie, costume)
                local recipe = HWE.snapshotRecipe(costume, md.HalloweenEventVisualSnapshot)
                local verified = recipe and HWE.verifyCostume(zombie, recipe)
                if not verified then
                    local ok, err = HWE.applyCostumeVisuals(zombie, recipe, "server_delayed_repair")
                    Server._visualStats.repaired = Server._visualStats.repaired + 1
                    if not ok then Server._visualStats.failed = Server._visualStats.failed + 1 end
                    HWE.log("SERVER_VISUAL_REPAIR id=" .. costume.id .. " verified=" .. tostring(ok)
                        .. " error=" .. tostring(err))
                    if ok then broadcastCostumeVisual(zombie, costume, true) end
                end
                -- Healthy checks produce one summary, never repeated broadcasts.
                entry.remaining = entry.remaining - 1
                entry.due = Server._tick + 90
                if entry.remaining <= 0 then
                    Server._visualStats.checked = Server._visualStats.checked + 1
                    table.remove(checks, i)
                end
            else
                table.remove(checks, i)
            end
        end
    end
    if USE_WARDROBE_LEDGER and Server._tick % WARDROBE_MAINTENANCE_TICKS == 0 then
        Wardrobe.maintain(getZombieList(), 16)
    end
    if Server._tick % 120 == 0 then
        local native = Server._nativeStats
        HWE.log("NATIVE_OUTFIT_SUMMARY attempts="..native.tried
            .." accepted="..native.accepted.." fallback="..native.fallback
            .." nativeReload="..native.nativeReload.." failed="..native.failed
            .." registry="..tostring(HWE.NativeOutfits and HWE.NativeOutfits.customCount or 0)
            .." ledgerEnabled="..tostring(USE_WARDROBE_LEDGER))
        for key in pairs(native) do native[key]=0 end
        local early = Server._earlyDressStats
        HWE.log("STARTUP_DRESS_SUMMARY immediateRestored=" .. early.immediateRestored
            .. " immediateDressed=" .. early.immediateDressed
            .. " queuedRestored=" .. early.queuedRestored
            .. " queuedDressed=" .. early.queuedDressed
            .. " immediateFailed=" .. early.immediateFailed
            .. " timeBudgetTicks=" .. early.ticksBudgetExhausted
            .. " peakQueue=" .. early.maxPending
            .. " pendingNow=" .. tostring(#Server._pendingDress)
            .. " maxPerTick=" .. tostring(MAX_PENDING_PER_TICK))
        for key in pairs(early) do early[key] = 0 end
        local priority = Server._queuePriorityStats
        HWE.log("STARTUP_PRIORITY_SUMMARY playersSeen=" .. priority.playerSamples
            .. " sorts=" .. priority.sorts
            .. " nearApplied=" .. priority.near
            .. " midApplied=" .. priority.mid
            .. " farApplied=" .. priority.far
            .. " unknownApplied=" .. priority.unknown
            .. " nearAvgWaitTicks=" .. (priority.near > 0 and math.floor(priority.nearWaitTotal / priority.near + 0.5) or 0)
            .. " nearMaxWaitTicks=" .. priority.nearWaitMax
            .. " directionPlayers=" .. priority.directionPlayers
            .. " nearFrontApplied=" .. priority.nearFront
            .. " nearOtherApplied=" .. priority.nearOther
            .. " nearFrontAvgWaitTicks=" .. (priority.nearFront > 0 and math.floor(priority.nearFrontWaitTotal / priority.nearFront + 0.5) or 0)
            .. " nearFrontMaxWaitTicks=" .. priority.nearFrontWaitMax
            .. " workBudgetMs=" .. PENDING_WORK_BUDGET_MS
            .. " pendingNow=" .. tostring(#Server._pendingDress))
        for key in pairs(priority) do priority[key] = 0 end
    end
    if Server._tick % NATURAL_SWEEP_TICKS == 0 then
        if HWE.flushLogCounters then HWE.flushLogCounters() end
        local wardrobeStats = Server._wardrobeStats
        if wardrobeStats.queued + wardrobeStats.restored + wardrobeStats.failed > 0 then
            HWE.log("WARDROBE_SUMMARY queued=" .. wardrobeStats.queued
                .. " restored=" .. wardrobeStats.restored .. " failed=" .. wardrobeStats.failed)
            wardrobeStats.queued, wardrobeStats.restored, wardrobeStats.failed = 0, 0, 0
        end
        -- One small aggregate line per interval; no per-zombie diagnostics.
        local diag = Wardrobe.drainDiagnostics()
        if diag then
            HWE.log("WARDROBE_MATCH_SUMMARY attempts=" .. diag.attempts
                .. " matched=" .. diag.matched
                .. " noBucket=" .. diag.noBucket
                .. " floor=" .. diag.floor
                .. " gender=" .. diag.gender
                .. " claimed=" .. diag.claimed
                .. " identity=" .. diag.identity
                .. " distance=" .. diag.distance
                .. " nameConflict=" .. diag.nameConflict
                .. " ambiguous=" .. diag.ambiguous
                .. " unavailable=" .. diag.unavailableCostume
                .. " noPosition=" .. diag.missingPosition
                .. " wornSkip=" .. diag.blockedWorn
                .. " other=" .. diag.other
                .. " reconciled=" .. (diag.reconciled or 0)
                .. " reconcileAmbiguous=" .. (diag.reconcileAmbiguous or 0)
                .. " anchorMatched=" .. (diag.anchorMatched or 0))
        end
        -- Record/overflow telemetry, once per existing sweep interval.
        -- This adds no new zombie scans or ItemVisual construction.
        local writes = Wardrobe.drainRecordDiagnostics()
        if writes then
            HWE.log("WARDROBE_CAPACITY_SUMMARY records=" .. writes.count
                .. " cap=" .. writes.cap
                .. " created=" .. writes.created
                .. " updated=" .. writes.updated
                .. " rejectedCap=" .. writes.full
                .. " rejectedNoIdentity=" .. writes.identity
                .. " skippedGallery=" .. writes.gallery
                .. " rejectedEmptySnapshot=" .. writes.emptySnapshot
                .. " heldNearby=" .. (writes.nearbyHold or 0)
                .. " heldCrowded=" .. (writes.crowdedHold or 0)
                .. " repeatedHold=" .. (writes.repeatedHold or 0))
            if writes.full > 0 or writes.count >= writes.cap * 0.9 then
                HWE.log("WARDROBE_CAPACITY_WARNING records=" .. writes.count
                    .. " cap=" .. writes.cap
                    .. " rejected=" .. writes.full
                    .. " note=engine_42_21_can_change_native_outfit_ids")
            end
        end
        Server.sweepLoadedZombies()
        local stats = Server._visualStats
        if stats.checked + stats.repaired + stats.failed > 0 then
            HWE.log("SERVER_VISUAL_SUMMARY checked=" .. stats.checked .. " repaired=" .. stats.repaired
                .. " failed=" .. stats.failed .. " pendingDress=" .. tostring(#Server._pendingDress))
            stats.checked, stats.repaired, stats.failed = 0, 0, 0
        end
    end
end

if Events and Events.OnGameStart then Events.OnGameStart.Add(function()
    if isAuthoritative() then Server.refresh("game_start") end
end) end
if Events and Events.OnServerStarted then Events.OnServerStarted.Add(function()
    if isAuthoritative() then Server.refresh("server_start") end
end) end
if Events and Events.EveryOneMinute then Events.EveryOneMinute.Add(function()
    if isAuthoritative() then Server.refresh("minute_tick") end
end) end
if Events and Events.OnZombieDead then Events.OnZombieDead.Add(function(zombie)
    if isAuthoritative() then onZombieDead(zombie) end
end) end
if Events and Events.OnZombieCreate then Events.OnZombieCreate.Add(onZombieCreate) end
if Events and Events.OnTick then Events.OnTick.Add(onTick) end
if Events then
    -- Dedicated servers and local paused games emit different tick events.
    -- The real-second gate above deduplicates when both fire in one frame.
    if Events.OnTick then Events.OnTick.Add(Server.pollScheduleClock) end
    if Events.OnTickEvenPaused then Events.OnTickEvenPaused.Add(Server.pollScheduleClock) end
end
if Events and Events.OnClientCommand then Events.OnClientCommand.Add(onClientCommand) end

HWE.log("SERVER_INITIALIZED version=" .. HWE.VERSION .. " costumes=" .. tostring(#(HWE.Costumes or {})) .. " pipeline=native-persistent-experiment+fast-visual-fallback+ledger-disabled networkDeleteAPI=" .. tostring(NetworkZombiePackerClass ~= nil))
local maleFamilies, maleWeight = HWE.buildNaturalFamilies(nil)
local femaleFamilies, femaleWeight = HWE.buildNaturalFamilies({isFemale=function() return true end})
HWE.log("COSTUME_POOL_WEIGHTS maleFamilies=" .. #maleFamilies .. " maleTotal=" .. maleWeight
    .. " femaleFamilies=" .. #femaleFamilies .. " femaleTotal=" .. femaleWeight
    .. " default=100 firefighter=25 sports=100/4_sports/16_variants chicken=70_worker+30_show witch=70_corset+30_dress")
return Server
