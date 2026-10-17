-- ============================================================================
-- HalloweenEvent_Client.lua
-- Build 42.21+ client sync. Costume creation remains server-authoritative.
-- ============================================================================

require "HalloweenEvent/HalloweenEvent_Shared"
local HWE = HalloweenEvent
if HWE.Client then return end

local Client = {}
HWE.Client = Client
Client.active = false

local function localPlayer(playerNum)
    playerNum = tonumber(playerNum) or 0
    if type(getSpecificPlayer) == "function" then
        local p = getSpecificPlayer(playerNum)
        if p then return p end
    end
    if type(getPlayer) == "function" then return getPlayer() end
    return nil
end

local function multiplayerClient()
    local client = type(isClient) == "function" and isClient() == true
    local server = type(isServer) == "function" and isServer() == true
    return client and not server
end

local function sendToServer(command, args, playerNum)
    if type(sendClientCommand) ~= "function" then return false end
    local player = localPlayer(playerNum)
    local ok = pcall(sendClientCommand, player, HWE.MOD_ID, command, args or {})
    if not ok then ok = pcall(sendClientCommand, HWE.MOD_ID, command, args or {}) end
    return ok
end

function Client.scanLoadedZombies(forceAll)
    HWE.log("CLIENT_SCAN_SKIPPED server_authoritative force=" .. tostring(forceAll == true))
    return 0
end

function Client.queueRescan(forceAll, attempts)
    return 0
end

function Client.cleanupLoadedZombies()
    return 0
end

function Client.dispatch(command, args, playerNum)
    command = tostring(command or "")
    args = args or {}
    HWE.log("CLIENT_COMMAND command=" .. command)

    -- In single-player the client and server Lua worlds are the same save. Call
    -- the authoritative handler directly so debug actions cannot disappear in
    -- the networking shim. Multiplayer still uses the normal server command.
    if not multiplayerClient() and HWE.Server and type(HWE.Server.handleAdminCommand) == "function" then
        local result = HWE.Server.handleAdminCommand(command, localPlayer(playerNum), args)
        return result ~= false
    end

    return sendToServer(command, args, playerNum)
end

Client.request = Client.dispatch

local function onServerCommand(module, command, args)
    if module ~= HWE.MOD_ID then return end
    args = args or {}
    if command == "EventState" or command == "Status" then
        Client.active = args.active == true
    end
end

if Events and Events.OnServerCommand then Events.OnServerCommand.Add(onServerCommand) end

-- Server-approved FULL presentation snapshots. Requests are tied to the actual
-- observed object and request sequence, while broadcasts have bounded lifetimes.
local observed = setmetatable({}, {__mode="k"})
local visualChecks = setmetatable({}, {__mode="k"})
local pendingStates, queryQueue, awaiting = {}, {}, {}
local visualTick, requestSerial = 0, 0
-- Startup catch-up stays bounded by the server's 32-ID ResolveCostumeVisuals
-- handler. Prioritize the client's *actual* forward view before querying rear
-- or distant zombies, and shorten cadence only while nearby work exists.
local lastVisualQueryTick = -30
local FAST_QUERY_INTERVAL = 12
local BACKGROUND_QUERY_INTERVAL = 30
local QUERY_BATCH_LIMIT = 32
-- v15: Server costume announcements are immediate. Avoid re-querying every
-- already verified costume in a synchronized two-minute burst after login.
-- Periodic fallback still detects a dropped server announcement, and each
-- object is revalidated on native online-ID/persistent-outfit identity change.
local VERIFIED_REFRESH_TICKS = 3600
local VIEW_NEAR_SQ, VIEW_MID_SQ, VIEW_FORWARD_DOT = 625, 3600, 0.35
local queryPriorityStats = {batches=0, fastBatches=0, gallery=0, nearFront=0,
    nearOther=0, mid=0, far=0, maxBacklog=0, maxWaitTicks=0, failed=0,
    verifiedRefreshes=0, farRefreshDeferred=0}
local galleryReceipts = {}
local presentationHolds = setmetatable({}, {__mode="k"})
local function visualNow()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return visualTick * (1000 / 60)
end

local function acknowledge(state, status)
    if not state.Gallery then return end
    local receipt = galleryReceipts[state.Token]
    if not receipt or receipt.revision ~= state.Revision then
        receipt = {revision=state.Revision, expires=visualNow()+30000}
        galleryReceipts[state.Token] = receipt
    end
    if status == "unloaded" then
        if receipt.loaded or receipt.applied or visualNow() < (receipt.nextMissing or 0) then return end
    elseif receipt[status] then return end
    if sendToServer("CostumeVisualAck", {OnlineID=state.OnlineID, Token=state.Token,
        Revision=state.Revision, Status=status}, 0) then
        if status == "unloaded" then
            receipt.nextMissing = visualNow() + 1000
            receipt.missingCount = (receipt.missingCount or 0) + 1
            if receipt.missingCount <= 2 then
                HWE.log("CLIENT_GALLERY_UNLOADED id=" .. state.CostumeID .. " onlineID=" .. state.OnlineID
                    .. " observation=" .. receipt.missingCount)
            end
        else receipt[status] = true end
    end
end

local function releasePresentation(zombie, reason)
    local hold = presentationHolds[zombie]
    if not hold then return end
    -- Restore only a hold we still own; leave later nonzero visibility decisions
    -- alone. No invisible/ghost flags or interaction state are modified.
    for index, old in pairs(hold.alpha) do
        if HWE.safeCall(zombie, "getAlpha", index) == 0 then HWE.tryCall(zombie, "setAlpha", index, old.alpha) end
        if HWE.safeCall(zombie, "getTargetAlpha", index) == 0 then HWE.tryCall(zombie, "setTargetAlpha", index, old.target) end
    end
    presentationHolds[zombie] = nil
    HWE.log("CLIENT_GALLERY_PRESENTATION_RELEASE onlineID=" .. tostring(hold.id) .. " reason=" .. tostring(reason)
        .. " elapsedMs=" .. tostring(math.floor(visualNow() - hold.started)))
end

local function holdPresentation(zombie, state, seen)
    -- Protect mummy's confirmed presentation; hold only brand-new other gallery
    -- subjects, once, while their object-bound recipe reply is in flight.
    if not state.Gallery or state.CostumeID == "BurlapMummy" or seen.held
        or seen.token or not state.GalleryAgeMs or state.GalleryAgeMs > 15000
        or HWE.safeCall(zombie, "isInvisible") == true then return end
    seen.held = true
    if type(zombie.setAlpha) ~= "function" or type(zombie.setTargetAlpha) ~= "function" then return end
    local alpha = {}
    local holding = false
    for index = 0, 3 do
        local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(index) or (index == 0 and localPlayer(0))
        if player then
            local current = tonumber(HWE.safeCall(zombie, "getAlpha", index))
            local target = tonumber(HWE.safeCall(zombie, "getTargetAlpha", index))
            if current and target then
                local okA, resultA = HWE.tryCall(zombie, "setAlpha", index, 0)
                local okT, resultT = HWE.tryCall(zombie, "setTargetAlpha", index, 0)
                if okA and resultA ~= false and okT and resultT ~= false then
                    alpha[index] = {alpha=current,target=target}
                    holding = true
                else
                    HWE.tryCall(zombie, "setAlpha", index, current)
                    HWE.tryCall(zombie, "setTargetAlpha", index, target)
                end
            end
        end
    end
    if holding then
        presentationHolds[zombie] = {id=state.OnlineID, persistent=state.PersistentID, started=visualNow(),
            expires=visualNow()+1500, alpha=alpha}
        HWE.log("CLIENT_GALLERY_PRESENTATION_HOLD onlineID=" .. tostring(state.OnlineID))
    end
end
local stats = {applied=0, alreadyMatched=0, identitySettled=0, duplicate=0, stale=0, unloaded=0, mismatch=0, requestTimeout=0, repaired=0}

local function queueQuery(zombie, id, seen, urgent)
    if queryQueue[id] then
        if urgent then queryQueue[id].urgent = true end
        return
    end
    if awaiting[id] then return end
    queryQueue[id] = {zombie=zombie, expires=visualTick + 300, urgent=urgent == true, queuedAt=visualTick}
    seen.attempts = seen.attempts + 1
    seen.next = visualTick + 180
end

local function acceptVisualState(state, expectedZombie, confirmedPersistent)
    if type(state) ~= "table" then return end
    local id = tonumber(state.OnlineID)
    local costume = HWE.getCostumeByID(state.CostumeID)
    local snapshot = state.Snapshot
    if not id or id < 0 or not costume or not state.Token or not tonumber(state.Revision)
        or type(snapshot) ~= "table" or type(snapshot.Items) ~= "table"
        or #snapshot.Items < 1 or #snapshot.Items > 48 then return end
    local pending = pendingStates[id]
    acknowledge(state, "announced")
    if pending and pending.state.Token == state.Token and
        (tonumber(pending.state.Revision) > tonumber(state.Revision) or
         (tonumber(pending.state.Revision) == tonumber(state.Revision) and
          (not expectedZombie or (pending.zombie == expectedZombie and
           (confirmedPersistent==nil or pending.confirmedPersistent~=nil))))) then
        stats.duplicate = stats.duplicate + 1
        return
    end
    pendingStates[id] = {state=state, zombie=expectedZombie, confirmedPersistent=confirmedPersistent,
        started=visualNow(), expires=visualNow() + (state.Gallery and 20000 or 3000)}
end

local function applyImpaledVisual(zombie, state, seen)
    local wanted = state.ImpaledWeapon
    if wanted == nil then return end -- Earlier hosts did not send attachment state.
    local current = HWE.safeCall(zombie, "getAttachedItem", "Knife in Back")
    local owned = current and seen.impaledID ~= nil and seen.impaledID == HWE.safeCall(current, "getID")
        and HWE.isSantaImpaledType(HWE.safeCall(current, "getFullType"))
    if wanted == false then
        if owned then
            HWE.tryCall(zombie, "removeAttachedItem", current)
            HWE.tryCall(zombie, "resetModelNextFrame")
        end
        seen.impaledID = nil
        return
    end
    local costume = HWE.getCostumeByID(state.CostumeID)
    local itemID = type(wanted) == "table" and tonumber(wanted.ItemID)
    if not costume or not costume.santaKnifeFallback or not itemID or itemID ~= math.floor(itemID)
        or itemID < -2147483648 or itemID > 2147483647 or wanted.Location ~= "Knife in Back"
        or not HWE.isSantaImpaledType(wanted.Type) or tonumber(wanted.Condition) ~= 1 then return end
    if current and HWE.safeCall(current, "getID") == itemID and HWE.safeCall(current, "getFullType") == wanted.Type then
        seen.impaledID = itemID
        return
    end
    if current and not owned then
        if seen.impaledBlockedRevision ~= state.Revision then
            seen.impaledBlockedRevision = state.Revision
            HWE.log("CLIENT_IMPALED_SLOT_OCCUPIED onlineID=" .. tostring(state.OnlineID))
        end
        return -- Preserve other mods' and the engine's unrelated attachments.
    end
    local group = HWE.safeCall(zombie, "getAttachedLocationGroup")
    if not HWE.safeCall(group, "getLocation", "Knife in Back") then return end
    local ok, item
    if type(instanceItem) == "function" then ok, item = pcall(instanceItem, wanted.Type)
    elseif InventoryItemFactory and type(InventoryItemFactory.CreateItem) == "function" then
        ok, item = pcall(InventoryItemFactory.CreateItem, wanted.Type)
    end
    local model = item and HWE.safeCall(item, "getStaticModel")
    if not ok or not item or not model or tostring(model) == "" or HWE.safeCall(item, "getFullType") ~= wanted.Type
        or not HWE.tryCall(item, "setID", itemID) or HWE.safeCall(item, "getID") ~= itemID
        or not HWE.tryCall(item, "setCondition", 1) or HWE.safeCall(item, "getCondition") ~= 1 then
        HWE.log("CLIENT_IMPALED_VISUAL_FAIL onlineID=" .. tostring(state.OnlineID) .. " type=" .. wanted.Type)
        return
    end
    if owned then HWE.tryCall(zombie, "removeAttachedItem", current) end
    if HWE.tryCall(zombie, "setAttachedItem", "Knife in Back", item)
        and HWE.safeCall(zombie, "getAttachedItem", "Knife in Back") == item then
        seen.impaledID = itemID
        HWE.tryCall(zombie, "resetModelNextFrame")
        HWE.log("CLIENT_IMPALED_VISUAL onlineID=" .. tostring(state.OnlineID) .. " type=" .. wanted.Type
            .. " condition=1 model=" .. tostring(HWE.safeCall(item, "getStaticModel")))
    end
    -- This is the server-owned item's presentation copy, with its original ID.
    -- Never add it to inventory or a client death-loot queue.
end

-- v17.1: Native outfits may already match the server's authoritative
-- clothing snapshot. Verify order AND appearance, not merely item names;
-- tint/texture choices can differ even when the costume type is identical.
-- Unknown visual getters are treated conservatively as a mismatch.
local function snapshotAlreadyApplied(zombie, recipe)
    if HWE.verifyCostume(zombie, recipe) ~= true then return false end
    local items = recipe and recipe.visualItems
    if not items or #items == 0 then return false end
    local visuals = HWE.safeCall(zombie, "getItemVisuals")
    if tonumber(HWE.safeCall(visuals, "size")) ~= #items then return false end
    local appearance = recipe.visualAppearance
    local function closeEnough(actual, expected)
        actual = tonumber(actual)
        expected = tonumber(expected)
        return actual ~= nil and expected ~= nil and math.abs(actual-expected) <= 0.015
    end
    for i, itemType in ipairs(items) do
        local visual = HWE.safeCall(visuals, "get", i-1)
        if HWE.safeCall(visual, "getItemType") ~= itemType then return false end
        local wanted = appearance and appearance[i]
        if wanted then
            if wanted.Hue ~= nil and not closeEnough(HWE.safeCall(visual, "getHue"), wanted.Hue) then return false end
            if wanted.BaseTexture ~= nil and HWE.safeCall(visual, "getBaseTexture") ~= wanted.BaseTexture then return false end
            if wanted.TextureChoice ~= nil and HWE.safeCall(visual, "getTextureChoice") ~= wanted.TextureChoice then return false end
            if wanted.Decal ~= nil then
                local decal=HWE.safeCall(visual, "getDecal", HWE.safeCall(visual,"getClothingItem"))
                if decal ~= wanted.Decal then return false end
            end
            if wanted.Tint then
                local tint = HWE.safeCall(visual, "getTint")
                if not tint or not closeEnough(HWE.safeCall(tint,"getRedFloat"), wanted.Tint[1])
                    or not closeEnough(HWE.safeCall(tint,"getGreenFloat"), wanted.Tint[2])
                    or not closeEnough(HWE.safeCall(tint,"getBlueFloat"), wanted.Tint[3]) then return false end
            end
        end
    end
    return true
end

local function onZombieVisualUpdate(zombie)
    if not multiplayerClient() or not zombie or HWE.safeCall(zombie, "isAlive") ~= true then return end
    local id = tonumber(HWE.safeCall(zombie, "getOnlineID"))
    if not id or id < 0 then return end
    local persistent = tonumber(HWE.safeCall(zombie, "getPersistentOutfitID"))
    local seen = observed[zombie]
    local knownCostume = seen and (seen.recipe and seen.recipe.id or seen.expectedVisual and seen.expectedVisual.CostumeID)
    if not seen or seen.id ~= id or not HWE.sameVisualOutfitID(seen.persistent, persistent, knownCostume) then
        seen = {id=id, persistent=persistent, attempts=0, next=visualTick}
        observed[zombie] = seen
        visualChecks[zombie] = nil
        releasePresentation(zombie, "identity_changed")
    elseif seen.persistent ~= persistent then
        seen.persistent = persistent
        HWE.log("CLIENT_VISUAL_HAT_FLAG_SETTLE onlineID=" .. tostring(id))
    end
    local pending = pendingStates[id]
    if pending then
        local state = pending.state
        local dx = (tonumber(HWE.safeCall(zombie, "getX")) or 0) - (tonumber(state.X) or 0)
        local dy = (tonumber(HWE.safeCall(zombie, "getY")) or 0) - (tonumber(state.Y) or 0)
        local nearby = dx*dx+dy*dy <= 625
            and math.abs((tonumber(HWE.safeCall(zombie, "getZ")) or 0) - (tonumber(state.Z) or 0)) < 0.5
        local fresh = seen.token ~= state.Token or not seen.revision or tonumber(state.Revision) >= seen.revision
        if not state.Gallery and pending.zombie == zombie and pending.confirmedPersistent ~= nil
            and fresh and nearby and HWE.sameVisualOutfitID(persistent, pending.confirmedPersistent, state.CostumeID)
            and not HWE.sameVisualOutfitID(persistent, state.PersistentID, state.CostumeID) then
            -- Dedicated clients can retain the original native outfit ID while
            -- the live server object already owns the costume. Only a reply
            -- confirmed against this object's requested token/position may
            -- settle it; unsolicited broadcasts and gallery spawns stay strict.
            HWE.tryCall(zombie, "setPersistentOutfitID", tonumber(state.PersistentID), true)
            persistent = tonumber(HWE.safeCall(zombie, "getPersistentOutfitID"))
            seen.persistent = persistent
            stats.identitySettled = stats.identitySettled + 1
            if HWE.DebugVerboseLogs then
                HWE.log("CLIENT_WORLD_IDENTITY_SETTLE onlineID=" .. tostring(id)
                    .. " verified=" .. tostring(HWE.sameVisualOutfitID(persistent, state.PersistentID, state.CostumeID)))
            end
        end
        local identityMatches = (not pending.zombie or pending.zombie == zombie)
            and HWE.sameVisualOutfitID(persistent, state.PersistentID, state.CostumeID) and nearby
        if identityMatches then
            acknowledge(state, "loaded")
            holdPresentation(zombie, state, seen)
            if (state.CostumeID ~= "BurlapMummy" or (not state.Gallery and pending.confirmedPersistent~=nil))
                and pending.zombie == zombie and HWE.safeCall(zombie, "isFemale") ~= (state.Female == true) then
                -- Native initial packets can temporarily carry the opposite sex.
                -- Only an object/request-bound authoritative reply may correct it.
                HWE.tryCall(zombie, "setFemale", state.Female == true)
                HWE.tryCall(zombie, "resetModelNextFrame")
                HWE.log("CLIENT_VISUAL_GENDER_SETTLE onlineID=" .. tostring(id)
                    .. " expected=" .. tostring(state.Female) .. " actual=" .. tostring(HWE.safeCall(zombie, "isFemale")))
            end
        end
        local matches = identityMatches and HWE.safeCall(zombie, "isFemale") == (state.Female == true)
        -- First attachment needs a trusted reply even while native sex settles.
        if identityMatches and not pending.zombie and not seen.token then
            pendingStates[id] = nil
            seen.expectedVisual = state
            seen.expectedExpires = visualNow() + 20000
            seen.resolved, seen.attempts, seen.next = false, 0, visualTick
            queueQuery(zombie, id, seen, state.Gallery)
        elseif matches then
            local revision = tonumber(state.Revision)
            if seen.token == state.Token and seen.revision and revision <= seen.revision then
                if revision == seen.revision then
                    stats.duplicate = stats.duplicate + 1
                    local verified = seen.recipe and HWE.verifyCostume(zombie, seen.recipe)
                    if seen.recipe and not verified then
                        local ok, err = HWE.applyCostumeVisuals(zombie, seen.recipe, "client_snapshot_repair")
                        verified = ok
                        stats.repaired = stats.repaired + 1
                        HWE.log("CLIENT_VISUAL_REPAIR id=" .. seen.recipe.id .. " verified=" .. tostring(ok) .. " error=" .. tostring(err))
                    end
                    if verified then
                        -- v15.1: A successful safety refresh resolves this object
                        -- again. Without resetting resolved/next, it re-queries
                        -- every 180 ticks and floods the server with duplicates.
                        -- Keep a failed verification eligible for retry.
                        seen.resolved, seen.attempts = true, 0
                        seen.next = visualTick + VERIFIED_REFRESH_TICKS + (id % 43) * 3
                        seen.expectedVisual = nil
                        applyImpaledVisual(zombie, state, seen)
                        acknowledge(state, "applied")
                    end
                    releasePresentation(zombie, "already_verified")
                else stats.stale = stats.stale + 1 end
                pendingStates[id] = nil
            elseif seen.token and seen.token ~= state.Token and not pending.zombie then
                -- A broadcast for another incarnation needs a fresh read-only
                -- query before it can be attached to this observed object.
                pendingStates[id] = nil
                seen.resolved, seen.attempts, seen.next = false, 0, visualTick
                stats.stale = stats.stale + 1
            else
                local costume = HWE.getCostumeByID(state.CostumeID)
                local recipe = HWE.snapshotRecipe(costume, state.Snapshot)
                local alreadyCorrect = snapshotAlreadyApplied(zombie, recipe)
                local ok, err
                if alreadyCorrect then
                    ok = true
                    stats.alreadyMatched = stats.alreadyMatched + 1
                else
                    ok, err = HWE.applyCostumeVisuals(zombie, recipe, "client_sync")
                end
                if ok then
                    seen.token, seen.revision, seen.resolved, seen.recipe = state.Token, revision, true, recipe
                    seen.expectedVisual = nil
                    -- Small deterministic jitter prevents a synchronized
                    -- refresh of hundreds of zombies on the same client tick.
                    seen.attempts, seen.next = 0, visualTick + VERIFIED_REFRESH_TICKS + (id % 43) * 3
                    applyImpaledVisual(zombie, state, seen)
                    local refreshModel = costume.id == "Witch_StraplessDress"
                    visualChecks[zombie] = {recipe=recipe, token=state.Token, revision=revision,
                        female=state.Female, impaled=state.ImpaledWeapon, refreshModel=refreshModel,
                        next=visualTick + (refreshModel and 2 or 30), remaining=2}
                    stats.applied = stats.applied + 1
                    acknowledge(state, "applied")
                    releasePresentation(zombie, "recipe_ready")
                    HWE.log("CLIENT_VISUAL_SYNC id=" .. costume.id .. " onlineID=" .. tostring(id)
                        .. " revision=" .. tostring(revision) .. " verified=true pieces=" .. tostring(#state.Snapshot.Items)
                        .. " nativeAlreadyMatched=" .. tostring(alreadyCorrect))
                else
                    seen.attempts, seen.next = 3, visualTick + 1200
                    releasePresentation(zombie, "recipe_failed")
                    HWE.log("CLIENT_VISUAL_SYNC_FAIL id=" .. costume.id .. " error=" .. tostring(err))
                end
                pendingStates[id] = nil
            end
        elseif not pending.mismatch then
            -- Do not wait 600 ticks and emit a timeout per unloaded broadcast.
            -- Query a loaded mismatch once; its response is tied to this object.
            pending.mismatch = true
            stats.mismatch = stats.mismatch + 1
            -- Keep the security/retry check but avoid hundreds of per-object
            -- strings/prints; loadedMismatch is already counted in the summary.
            -- Enable HWE.DebugVerboseLogs for full identity traces when debugging.
            if HWE.DebugVerboseLogs then
                HWE.log("CLIENT_VISUAL_IDENTITY_WAIT onlineID=" .. tostring(id)
                    .. " expectedPersistent=" .. tostring(state.PersistentID) .. " actualPersistent=" .. tostring(persistent)
                    .. " expectedFemale=" .. tostring(state.Female) .. " actualFemale=" .. tostring(HWE.safeCall(zombie, "isFemale")))
            end
            if seen.attempts < 3 then queueQuery(zombie, id, seen, state.Gallery) end
        end
    end

    local check = visualChecks[zombie]
    if check and visualTick >= check.next then
        if seen.token == check.token and seen.revision == check.revision then
            if check.recipe.id ~= "BurlapMummy" and check.female ~= nil
                and HWE.safeCall(zombie, "isFemale") ~= (check.female == true) then
                HWE.tryCall(zombie, "setFemale", check.female == true)
                HWE.tryCall(zombie, "resetModelNextFrame")
                HWE.log("CLIENT_VISUAL_GENDER_SETTLE onlineID=" .. tostring(id) .. " phase=delayed")
            end
            local verified = HWE.verifyCostume(zombie, check.recipe)
            if not verified then
                local ok, err = HWE.applyCostumeVisuals(zombie, check.recipe, "client_delayed_repair")
                stats.repaired = stats.repaired + 1
                HWE.log("CLIENT_VISUAL_REPAIR id=" .. check.recipe.id .. " verified=" .. tostring(ok) .. " error=" .. tostring(err))
            elseif check.refreshModel then
                HWE.tryCall(zombie, "resetModelNextFrame")
                HWE.log("CLIENT_COSTUME_MODEL_REFRESH id=" .. check.recipe.id .. " onlineID=" .. tostring(id))
            end
            check.refreshModel = nil
            if check.impaled ~= nil then
                applyImpaledVisual(zombie, {CostumeID=check.recipe.id, OnlineID=id,
                    Revision=check.revision, ImpaledWeapon=check.impaled}, seen)
            end
            check.remaining = check.remaining - 1
            check.next = visualTick + 90
            if check.remaining <= 0 then visualChecks[zombie] = nil end
        else visualChecks[zombie] = nil end
    end

    -- Ordinary zombies stop after an explicit no-profile reply. Managed zombies
    -- refresh slowly, to recover a dropped reroll message without log flooding.
    if seen.token and seen.resolved and visualTick >= seen.next then
        local localP=localPlayer(0)
        local px,py=tonumber(HWE.safeCall(localP,"getX")),tonumber(HWE.safeCall(localP,"getY"))
        local zx,zy=tonumber(HWE.safeCall(zombie,"getX")),tonumber(HWE.safeCall(zombie,"getY"))
        local close=px and py and zx and zy and (px-zx)^2+(py-zy)^2 <= VIEW_MID_SQ
        if close then
            seen.resolved, seen.attempts = false, 0
            queryPriorityStats.verifiedRefreshes = queryPriorityStats.verifiedRefreshes + 1
        else
            -- Server broadcasts still apply immediately at any range.
            -- Reconsider faraway verified zombies when the player approaches.
            seen.next=visualTick+300
            queryPriorityStats.farRefreshDeferred=queryPriorityStats.farRefreshDeferred+1
        end
    end
    if not seen.resolved and seen.attempts < 3 and visualTick >= seen.next then
        queueQuery(zombie, id, seen)
    end
end

local function scanPendingGallery()
    local wanted = {}
    local hasPending = false
    for id, pending in pairs(pendingStates) do
        if pending.state.Gallery then
            wanted[id] = pending
            hasPending = true
        end
    end
    for zombie, seen in pairs(observed) do
        if seen.expectedVisual and seen.expectedVisual.Gallery then
            if visualNow() >= (seen.expectedExpires or 0) then seen.expectedVisual = nil
            elseif not wanted[seen.id] then
                wanted[seen.id] = {state=seen.expectedVisual}
                hasPending = true
            end
        end
    end
    -- Kahlua does not provide Lua's next() global in the tested game runtime.
    if not hasPending then return end
    local cell = type(getCell) == "function" and getCell() or nil
    local zombies = HWE.safeCall(cell, "getZombieList")
    if not zombies then return end
    local found = {}
    for i = 0, zombies:size()-1 do
        local zombie = zombies:get(i)
        local id = tonumber(HWE.safeCall(zombie, "getOnlineID"))
        local pending = id and wanted[id]
        if pending then
            found[id] = true
            if HWE.safeCall(zombie, "isAlive") == true then onZombieVisualUpdate(zombie)
            elseif not pending.inactiveLogged then
                pending.inactiveLogged = true
                HWE.log("CLIENT_GALLERY_ENTITY_INACTIVE onlineID=" .. tostring(id)
                    .. " health=" .. tostring(HWE.safeCall(zombie, "getHealth")))
            end
        end
    end
    -- A full native-list scan is distinct from a costume identity/asset mismatch.
    -- Report absence only in a loaded nearby square, after a five-second grace.
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    local px, py, pz = HWE.safeCall(player,"getX"), HWE.safeCall(player,"getY"), HWE.safeCall(player,"getZ")
    local now = visualNow()
    for id, pending in pairs(pendingStates) do
        local state = pending.state
        if state.Gallery and state.CostumeID ~= "BurlapMummy" and not pending.zombie and not found[id]
            and now - pending.started >= 5000 and px and py and pz then
            local x, y, z = tonumber(state.X), tonumber(state.Y), tonumber(state.Z)
            if x and y and z and math.abs(pz-z) < 0.5 and (px-x)^2+(py-y)^2 <= 1024
                and HWE.safeCall(cell,"getGridSquare",math.floor(x),math.floor(y),math.floor(z)) then
                acknowledge(state,"unloaded")
            end
        end
    end
end

local function onVisualTick()
    if not multiplayerClient() then return end
    visualTick = visualTick + 1
    if visualTick % 5 == 0 then scanPendingGallery() end
    for zombie, hold in pairs(presentationHolds) do
        if visualNow() >= hold.expires or HWE.safeCall(zombie, "isAlive") ~= true
            or tonumber(HWE.safeCall(zombie, "getOnlineID")) ~= tonumber(hold.id)
            or not HWE.sameVisualOutfitID(HWE.safeCall(zombie, "getPersistentOutfitID"), hold.persistent) then
            releasePresentation(zombie, "bounded_timeout_or_identity")
        else
            for index in pairs(hold.alpha) do
                HWE.tryCall(zombie, "setAlpha", index, 0)
                HWE.tryCall(zombie, "setTargetAlpha", index, 0)
            end
        end
    end
    for token, receipt in pairs(galleryReceipts) do
        if visualNow() >= receipt.expires then galleryReceipts[token] = nil end
    end
    for id, pending in pairs(pendingStates) do
        if pending.expires <= visualNow() then
            stats.unloaded = stats.unloaded + 1
            pendingStates[id] = nil
        end
    end
    for id, pending in pairs(awaiting) do
        if pending.expires <= visualTick then
            stats.requestTimeout = stats.requestTimeout + 1
            awaiting[id] = nil
        end
    end
    if visualTick % 600 == 0 then
        if HWE.flushLogCounters then HWE.flushLogCounters() end
        local total = 0
        for _, count in pairs(stats) do total = total + count end
        if total > 0 then
            HWE.log("CLIENT_VISUAL_SUMMARY applied=" .. stats.applied .. " nativeAlreadyMatched=" .. stats.alreadyMatched .. " identitySettled=" .. stats.identitySettled .. " duplicate=" .. stats.duplicate
                .. " stale=" .. stats.stale .. " unseenExpired=" .. stats.unloaded
                .. " loadedMismatch=" .. stats.mismatch .. " requestTimeout=" .. stats.requestTimeout
                .. " repaired=" .. stats.repaired)
        end
        for key in pairs(stats) do stats[key] = 0 end
    end
    if visualTick % 600 == 0 then
        local p = queryPriorityStats
        HWE.log("CLIENT_QUERY_PRIORITY_SUMMARY batches=" .. p.batches
            .. " fastBatches=" .. p.fastBatches .. " gallery=" .. p.gallery
            .. " nearFront=" .. p.nearFront .. " nearOther=" .. p.nearOther
            .. " mid=" .. p.mid .. " far=" .. p.far
            .. " maxBacklog=" .. p.maxBacklog .. " maxWaitTicks=" .. p.maxWaitTicks
            .. " failed=" .. p.failed .. " maxPerRequest=" .. QUERY_BATCH_LIMIT
            .. " verifiedRefreshes=" .. p.verifiedRefreshes
            .. " farRefreshDeferred=" .. p.farRefreshDeferred
            .. " refreshIntervalTicks=" .. VERIFIED_REFRESH_TICKS)
        for k in pairs(p) do p[k] = 0 end
    end

    -- Cheap guard: the old client looked at queue metadata each tick, but
    -- native getX/getY/heading calls and sorting should NOT run every tick.
    -- Gallery requests keep their existing immediate-response semantics.
    local urgentNow = false
    if visualTick-lastVisualQueryTick < FAST_QUERY_INTERVAL then
        for _, entry in pairs(queryQueue) do
            if entry.urgent then urgentNow = true; break end
        end
        if not urgentNow then return end
    end

    -- Recompute focus once per scheduled request. This intentionally uses the
    -- local player's view (the server's nearest-player order is not necessarily
    -- the order of this player's visible zombies).
    local player = localPlayer(0)
    local px, py, pz = tonumber(HWE.safeCall(player, "getX")),
        tonumber(HWE.safeCall(player, "getY")), tonumber(HWE.safeCall(player, "getZ"))
    local fx, fy = tonumber(HWE.safeCall(player, "getForwardDirectionX")),
        tonumber(HWE.safeCall(player, "getForwardDirectionY"))
    if fx == nil or fy == nil then
        local direction = HWE.safeCall(player, "getForwardDirection")
        fx = direction and tonumber(HWE.safeCall(direction, "getX")) or nil
        fy = direction and tonumber(HWE.safeCall(direction, "getY")) or nil
    end
    local length = fx and fy and math.sqrt(fx*fx + fy*fy) or 0
    if length > 0.001 then fx, fy = fx/length, fy/length else fx, fy = nil, nil end

    local urgent, nearWork, candidates = false, false, {}
    for id, entry in pairs(queryQueue) do
        local zombie = entry.zombie
        if entry.expires <= visualTick or HWE.safeCall(zombie, "isAlive") ~= true
            or tonumber(HWE.safeCall(zombie, "getOnlineID")) ~= id then
            queryQueue[id] = nil
        else
            local seen, pending = observed[zombie], pendingStates[id]
            local announced = (pending and pending.state) or (seen and seen.expectedVisual)
            local dx = px and ((tonumber(HWE.safeCall(zombie, "getX")) or px)-px) or nil
            local dy = py and ((tonumber(HWE.safeCall(zombie, "getY")) or py)-py) or nil
            local dz = pz and ((tonumber(HWE.safeCall(zombie, "getZ")) or pz)-pz) or 0
            local d2 = dx and dy and dx*dx + dy*dy + dz*dz*100 or math.huge
            local forward = fx and fy and d2 <= VIEW_MID_SQ and
                (dx*fx + dy*fy) / math.max(0.001, math.sqrt(dx*dx + dy*dy)) >= VIEW_FORWARD_DOT
            local gallery = entry.urgent == true or (announced and announced.Gallery == true)
            local rank
            if gallery then rank = 0; urgent = true
            elseif d2 <= VIEW_NEAR_SQ and forward then rank = 1
            elseif d2 <= VIEW_NEAR_SQ then rank = 2
            elseif d2 <= VIEW_MID_SQ and forward then rank = 3
            elseif d2 <= VIEW_MID_SQ then rank = 4
            else rank = 5 end
            if rank <= 2 then nearWork = true end
            candidates[#candidates+1] = {id=id, entry=entry, rank=rank, distance=d2,
                announced=announced, gallery=gallery}
        end
    end
    local cadence = nearWork and FAST_QUERY_INTERVAL or BACKGROUND_QUERY_INTERVAL
    if not urgent and visualTick-lastVisualQueryTick < cadence then return end
    if #candidates == 0 then return end
    table.sort(candidates, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        -- Known-costume requests within the same view band beat vanilla checks.
        if (a.announced ~= nil) ~= (b.announced ~= nil) then return a.announced ~= nil end
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.id < b.id
    end)
    local ids, selected = {}, {}
    for i=1,math.min(#candidates, QUERY_BATCH_LIMIT) do
        local c = candidates[i]
        ids[#ids+1] = c.id
        selected[c.id] = c
    end
    requestSerial = requestSerial + 1
    local observations = {}
    for id, candidate in pairs(selected) do
        local zombie, announced = candidate.entry.zombie, candidate.announced
        local seen = observed[zombie]
        observations[tostring(id)] = {PersistentID=tonumber(HWE.safeCall(zombie,"getPersistentOutfitID")),
            Token=announced and announced.Token or (seen and seen.token),
            X=tonumber(HWE.safeCall(zombie,"getX")),Y=tonumber(HWE.safeCall(zombie,"getY")),
            Z=tonumber(HWE.safeCall(zombie,"getZ"))}
    end
    if sendToServer("ResolveCostumeVisuals", {IDs=ids, RequestID=requestSerial, Observations=observations}, 0) then
        lastVisualQueryTick = visualTick
        local p = queryPriorityStats
        p.batches = p.batches + 1
        if nearWork then p.fastBatches = p.fastBatches + 1 end
        p.maxBacklog = math.max(p.maxBacklog, #candidates)
        for id, candidate in pairs(selected) do
            local entry = candidate.entry
            local rank = candidate.rank
            if rank == 0 then p.gallery = p.gallery + 1
            elseif rank == 1 then p.nearFront = p.nearFront + 1
            elseif rank == 2 then p.nearOther = p.nearOther + 1
            elseif rank <= 4 then p.mid = p.mid + 1
            else p.far = p.far + 1 end
            p.maxWaitTicks = math.max(p.maxWaitTicks, visualTick-(entry.queuedAt or visualTick))
            queryQueue[id] = nil
            awaiting[id] = {zombie=entry.zombie, request=requestSerial, expires=visualTick + 150,
                persistent=tonumber(HWE.safeCall(entry.zombie, "getPersistentOutfitID")),
                observation=observations[tostring(id)]}
        end
    else
        queryPriorityStats.failed = queryPriorityStats.failed + 1
    end
end

local function onVisualServerCommand(module, command, args)
    if module ~= HWE.MOD_ID or not multiplayerClient() then return end
    args = args or {}
    if command == "CostumeVisual" then
        acceptVisualState(args)
        if args.Gallery then scanPendingGallery() end
    elseif command == "CostumeVisualBatch" then
        for _, entry in ipairs(args.Entries or {}) do
            local id = tonumber(entry.OnlineID)
            local expected = id and awaiting[id]
            if expected and expected.request == tonumber(args.RequestID) then
                awaiting[id] = nil
                local zombie = expected.zombie
                if HWE.safeCall(zombie, "isAlive") == true
                    and tonumber(HWE.safeCall(zombie, "getOnlineID")) == id
                    and HWE.sameVisualOutfitID(HWE.safeCall(zombie, "getPersistentOutfitID"), expected.persistent,
                        entry.State and entry.State.CostumeID) then
                    if entry.State then
                        local confirmation, requested = entry.WorldIdentityConfirmed, expected.observation
                        local confirmed = type(confirmation)=="table" and requested and not entry.State.Gallery
                            and requested.Token ~= nil and confirmation.Token==requested.Token
                            and entry.State.Token==requested.Token and confirmation.PersistentID==requested.PersistentID
                            and confirmation.X==requested.X and confirmation.Y==requested.Y and confirmation.Z==requested.Z
                        acceptVisualState(entry.State, zombie, confirmed and expected.persistent or nil)
                        onZombieVisualUpdate(zombie)
                    elseif entry.Found then
                        local seen = observed[zombie]
                        if seen then
                            if seen.expectedVisual or entry.Pending then
                                -- An ordinary lookup can race the costume tag.
                                -- Do not let it cancel a newer visual announcement.
                                seen.resolved, seen.next = false, visualTick
                                if seen.expectedVisual then acceptVisualState(seen.expectedVisual) end
                            else
                                seen.resolved = true
                                seen.token, seen.revision, seen.recipe = nil, nil, nil
                                visualChecks[zombie] = nil
                            end
                        end
                    end
                end
            end
        end
    end
end

if Events and Events.OnZombieCreate then Events.OnZombieCreate.Add(onZombieVisualUpdate) end
if Events and Events.OnZombieUpdate then Events.OnZombieUpdate.Add(onZombieVisualUpdate) end
if Events and Events.OnTick then Events.OnTick.Add(onVisualTick) end
if Events and Events.OnServerCommand then Events.OnServerCommand.Add(onVisualServerCommand) end

HWE.log("CLIENT_RUNTIME_LOADED version=" .. tostring(HWE.VERSION) .. " server_authoritative=true")
return Client
