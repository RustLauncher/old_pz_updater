-- World-save wardrobe cache for Build 42 zombies.
-- Live ItemVisuals and zombie modData are not reliable population-save data.
-- This only restores a *confidently matched* returning zombie; it never
-- replaces, spawns or deletes zombies, and never changes native outfit IDs.
local HWE = HalloweenEvent
local P = {}
local DATA_KEY = "HalloweenEvent_Wardrobe_v1"
local CELL = 4
local MAX_ENTRIES = 12000
-- Diagnostics count the outcome of EXISTING lookups only. No extra zombie
-- scans, remote calls, visual operations, or relaxed identity matching.
local function emptyDiagnostics()
    return { attempts=0, matched=0, noBucket=0, floor=0, gender=0,
        claimed=0, identity=0, distance=0, nameConflict=0,
        ambiguous=0, unavailableCostume=0, missingPosition=0,
        blockedWorn=0, other=0, reconciled=0, reconcileAmbiguous=0, anchorMatched=0 }
end
local diagnostics = emptyDiagnostics()
-- Only bounded aggregates; no per-zombie diagnostic spam and no broad scans.
local recordDiagnostics = {created=0, updated=0, full=0,
    identity=0, gallery=0, emptySnapshot=0, nearbyHold=0,
        crowdedHold=0, repeatedHold=0}
local function noteRecord(reason)
    recordDiagnostics[reason] = (recordDiagnostics[reason] or 0) + 1
end

local function tally(key)
    diagnostics[key] = (diagnostics[key] or 0) + 1
end
local store, index, tracked, claimed, cursor
tracked = setmetatable({}, {__mode="k"})
claimed = setmetatable({}, {__mode="v"})
cursor = 0

local function safe(z, method, ...)
    return HWE.safeCall(z, method, ...)
end
local function bucket(x, y, z)
    return math.floor(x / CELL) .. ":" .. math.floor(y / CELL) .. ":" .. math.floor(z)
end
-- Session-local holds prevent the same unresolved zombie from retrying a save
-- on every movement/revision pass; this cache is never itself persisted.
local saveHolds = setmetatable({}, {__mode="k"})
local function squaredDistance(e,x,y)
    local d = (x-e.X)^2+(y-e.Y)^2
    local ax,ay = tonumber(e.AnchorX),tonumber(e.AnchorY)
    if ax and ay then
        local ad=(x-ax)^2+(y-ay)^2
        if ad < d then return ad end
    end
    return d
end
local function rowKeys(e)
    local a=bucket(e.X,e.Y,e.Z)
    local ax,ay,az=tonumber(e.AnchorX),tonumber(e.AnchorY),tonumber(e.AnchorZ)
    local b=ax and ay and az and bucket(ax,ay,az)
    return a, b ~= a and b or nil
end

-- B42 persistent *outfit* IDs are appearance seeds, not zombie identities.
-- Bit 15 changes when a hat falls off. Preserve the seed and gender bits.
local function sameAppearance(a, b)
    a, b = tonumber(a), tonumber(b)
    if not a or not b or a == 0 or b == 0 then return false end
    local ah, bh = math.floor(a / 65536), math.floor(b / 65536)
    return ah == bh and ((a % 65536) % 32768) == ((b % 65536) % 32768)
end

local function availableRecord(id, entry, zombie)
    if not entry or entry.GallerySpiffo == true then return false end
    local owner = claimed[id]
    return not owner or owner == zombie or safe(owner, "getCurrentSquare") == nil
end

-- The conservative recovery path reads only the same 3x3 buckets as P.find.
-- It never deletes ledger records or guesses from a matching costume name.
local function recoverByAnchor(db, zombie, x, y, z, female, nativeID, nativeName)
    local seen, candidates = {}, {}
    for dx=-1,1 do for dy=-1,1 do
        for id in pairs(index[bucket(x + dx*CELL, y + dy*CELL, z)] or {}) do
            if not seen[id] then
                seen[id] = true
                local e = db.Entries[id]
                if availableRecord(id, e, zombie) and e.Female == female
                    and math.abs(z-e.Z) < 0.2 and HWE.getCostumeByID(e.CostumeID) then
                    local dist = squaredDistance(e,x,y)
                    local sameID = sameAppearance(nativeID, e.OriginalID)
                    local compatibleName = nativeName == "" or e.OriginalName == ""
                        or nativeName == e.OriginalName
                    -- Same outfit seed may have moved between saves, but
                    -- because seeds repeat we REQUIRE spatial separation.
                    -- If B42 replaced the native outfit ID, only an almost
                    -- exact, uniquely occupied position can establish an anchor.
                    if (sameID and compatibleName and dist <= 9.0)
                        or (dist <= 0.09 and compatibleName) then
                        candidates[#candidates+1] = {id=id, entry=e, dist=dist,
                            sameID=sameID}
                    end
                end
            end
        end
    end end
    table.sort(candidates, function(a,b) return a.dist < b.dist end)
    local first, second = candidates[1], candidates[2]
    if not first then return nil, nil, false end
    local gap = second and (second.dist - first.dist) or math.huge
    -- Never use distance alone when two zombies could occupy the same area.
    -- A different-ID recovery must be almost position-identical and have
    -- no other nearby competitor (including same-seed outfits).
    local unique = first.sameID and gap > 2.25
        or (not first.sameID and first.dist <= 0.09 and gap > 1.0)
    if not unique then return nil, nil, true end
    return first.entry, first.id, false
end

-- An uncertain nearby appearance is not evidence of a *new* zombie.
-- Hold its new save instead of creating another duplicate ledger row.
-- We do NOT claim an uncertain entry or replace its saved outfit.
local function uncertainReturningAppearance(db, zombie, x, y, z, female, nativeID, nativeName)
    local seen = {}
    for dx=-1,1 do for dy=-1,1 do
        for id in pairs(index[bucket(x+dx*CELL,y+dy*CELL,z)] or {}) do
            if not seen[id] then
                seen[id] = true
                local e = db.Entries[id]
                if availableRecord(id,e,zombie) and e.Female == female
                    and math.abs(z-e.Z) < 0.2 and
                    (nativeName == "" or e.OriginalName == "" or nativeName == e.OriginalName)
                    and ((sameAppearance(nativeID,e.OriginalID)
                            and squaredDistance(e,x,y) <= 16.0)
                        or squaredDistance(e,x,y) <= 0.09) then
                    return true
                end
            end
        end
    end end
    return false
end

-- v15: Delete only EXACT duplicate ledger rows. Outfit template IDs are not
-- zombie identity: a zombie not loaded this session is never stale evidence.
-- No distance/age-based expiry, no deletion of unique or protected gallery rows.
local function sameValue(a, b, depth)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    if depth > 8 then return false end -- treat unknown/deep structures as unique
    for k, v in pairs(a) do
        if not sameValue(v, b[k], depth + 1) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function eligibleExactDuplicate(e)
    return type(e) == "table" and e.GallerySpiffo ~= true
        and tonumber(e.OriginalID) ~= nil and tonumber(e.OriginalID) ~= 0
        and type(e.Snapshot) == "table" and type(e.Snapshot.Items) == "table"
        and #e.Snapshot.Items > 0 and tonumber(e.X) and tonumber(e.Y) and tonumber(e.Z)
        and type(e.CostumeID) == "string"
end

-- Linear startup sweep (typically ~9k rows). Candidate bucketing is ONLY
-- an acceleration: full recursive equality decides whether rows can merge.
-- Prefer the oldest ID to minimize potential references from an old save.
local function removeExactDuplicateRows(entries)
    local lookup, removed = {}, {}
    local count, compared = 0, 0
    for id, entry in pairs(entries) do
        if eligibleExactDuplicate(entry) then
            local key = tostring(entry.X) .. "|" .. tostring(entry.Y) .. "|"
                .. tostring(entry.Z) .. "|" .. tostring(entry.OriginalID) .. "|"
                .. tostring(entry.CostumeID) .. "|" .. tostring(entry.Female)
            local peers = lookup[key]
            if not peers then
                peers = {}
                lookup[key] = peers
            end
            local peerMatch
            for _, peer in ipairs(peers) do
                compared = compared + 1
                if sameValue(entry, peer.entry, 0) then
                    peerMatch = peer
                    break
                end
            end
            if peerMatch then
                local currentNumeric, peerNumeric = tonumber(id), tonumber(peerMatch.id)
                if currentNumeric and peerNumeric and currentNumeric < peerNumeric then
                    removed[peerMatch.id] = true
                    peerMatch.id, peerMatch.entry = id, entry
                else
                    removed[id] = true
                end
                count = count + 1
            else
                peers[#peers+1] = {id=id, entry=entry}
            end
        end
    end
    for id in pairs(removed) do entries[id] = nil end
    return count, compared
end

local function load()
    if store then return store end
    if not ModData or type(ModData.getOrCreate) ~= "function" then return nil end
    local ok, data = pcall(ModData.getOrCreate, DATA_KEY)
    if not ok or type(data) ~= "table" then return nil end
    store = data
    if type(store.Entries) ~= "table" then store.Entries = {} end
    store.NextID = tonumber(store.NextID) or 0
    -- Preserve every unmatched/unloaded zombie. Only truly identical, full
    -- saved entries are merged. No arbitrary age or distance cutoff.
    local exactRemoved, exactCompared = removeExactDuplicateRows(store.Entries)
    index = {}
    store.Count = 0
    local named, persistentIDs, missingBoth, pruned, protected = 0, 0, 0, 0, 0
    for id, entry in pairs(store.Entries) do
        if type(entry) == "table" and type(entry.CostumeID) == "string"
            and tonumber(entry.X) and tonumber(entry.Y) and tonumber(entry.Z)
            and type(entry.Snapshot) == "table" and type(entry.Snapshot.Items) == "table" then
            local key = bucket(entry.X, entry.Y, entry.Z)
            local hasName = type(entry.OriginalName) == "string" and entry.OriginalName ~= ""
            local hasID = tonumber(entry.OriginalID) ~= nil and tonumber(entry.OriginalID) ~= 0
            local isGallerySpiffo = entry.GallerySpiffo == true and entry.CostumeID == "SpiffoMascot"
            -- Old releases accumulated thousands of entries that had NO
            -- matching identity and could never be restored. These filled the
            -- 6000-record cap, silently preventing new gallery Spiffos being
            -- saved. Retain only usable identities or explicit gallery anchors.
            if not hasName and not hasID and not isGallerySpiffo then
                store.Entries[id] = nil
                pruned = pruned + 1
            else
                index[key] = index[key] or {}
                index[key][tostring(id)] = true
                local _, stable = rowKeys(entry)
                if stable then
                    index[stable] = index[stable] or {}
                    index[stable][tostring(id)] = true
                end
                store.Count = store.Count + 1
                if hasName then named = named + 1 end
                if hasID then persistentIDs = persistentIDs + 1 end
                if not hasName and not hasID then missingBoth = missingBoth + 1 end
                if isGallerySpiffo then protected = protected + 1 end
            end
        else
            store.Entries[id] = nil
        end
    end
    HWE.log("WARDROBE_EXACT_COMPACTION removed=" .. exactRemoved
        .. " compared=" .. exactCompared .. " policy=full_record_equality_only"
        .. " unloadedRetained=true galleryProtected=true")
    local anchors, zones = 0, {}
    for _,e in pairs(store.Entries) do
        if type(e)=="table" and e.AnchorX ~= nil then anchors=anchors+1 end
        if type(e)=="table" and tonumber(e.X) and tonumber(e.Y) and tonumber(e.Z) then
            local area=math.floor(e.X/16)..":"..math.floor(e.Y/16)..":"..math.floor(e.Z)
            zones[area]=(zones[area] or 0)+1
        end
    end
    local zonesCount, denseZones=0,0
    for _,n in pairs(zones) do
        zonesCount=zonesCount+1
        if n>=20 then denseZones=denseZones+1 end
    end
    HWE.log("WARDROBE_LEDGER_AUDIT anchored="..anchors.." records="..store.Count
        .." populatedZones="..zonesCount.." crowdedZones="..denseZones
        .." destructivePruning=false")
    HWE.log("WARDROBE_LOADED count=" .. store.Count .. " cap=" .. MAX_ENTRIES
        .. " originalNames=" .. named .. " originalIDs=" .. persistentIDs
        .. " missingBoth=" .. missingBoth .. " prunedUnmatchable=" .. pruned
        .. " protectedSpiffos=" .. protected)
    return store
end
local function unlink(id, entry)
    if not index or not entry then return end
    local a,b=rowKeys(entry)
    for _,key in ipairs(b and {a,b} or {a}) do
        local ids=index[key]
        if ids then
            ids[id]=nil
            local remaining=false
            for _ in pairs(ids) do remaining=true;break end
            if not remaining then index[key]=nil end
        end
    end
end
local function link(id,entry)
    local a,b=rowKeys(entry)
    for _,key in ipairs(b and {a,b} or {a}) do
        index[key]=index[key] or {}
        index[key][id]=true
    end
end

-- B42 may reconstruct a long-populated cell with different outfit seeds.
-- Without a unique native zombie ID, a crowded previously saved cell cannot
-- safely prove an unmatched object is genuinely new. Preserve all old records
-- and withhold *only its new save*, not the living zombie or its costume.
local function uncertainCrowdedArea(db,zombie,x,y,z,female)
    if (db.Count or 0) < MAX_ENTRIES*0.70 then return false end
    local n, seen = 0, {}
    for dx=-1,1 do for dy=-1,1 do
        for id in pairs(index[bucket(x+dx*CELL,y+dy*CELL,z)] or {}) do
            if not seen[id] then
                seen[id]=true
                local e=db.Entries[id]
                if e and e.GallerySpiffo ~= true and e.Female == female
                    and math.abs(z-e.Z)<0.2 and squaredDistance(e,x,y) <= 25 then
                    n=n+1
                    if n>=5 then return true end
                end
            end
        end
    end end
    return false
end

-- No full-world zombie scans, serialization passes or heavyweight visual work.
-- Already-captured snapshots are copied only when their visual revision changes.
function P.record(zombie, costume, snapshot, allowGallery)
    local db = load()
    if not db or not zombie or not costume then return false end
    local md = safe(zombie, "getModData")
    local x, y, z = tonumber(safe(zombie, "getX")), tonumber(safe(zombie, "getY")), tonumber(safe(zombie, "getZ"))
    if not md or not x or not y or not z then return false end
    if md.HalloweenEventGalleryTest == true and allowGallery ~= true then
        noteRecord("gallery")
        return false
    end
    local existingID = md.HalloweenEventWardrobeID and tostring(md.HalloweenEventWardrobeID)
    local existing = existingID and db.Entries[existingID]
    local wasGallerySpiffo = existing and existing.GallerySpiffo == true
        and costume.id == "SpiffoMascot"
    local isGallerySpiffo = wasGallerySpiffo or (allowGallery == true
        and md.HalloweenEventGalleryTest == true and costume.id == "SpiffoMascot")
    -- Ordinary zombies still require a native identity. Admin-created
    -- Spiffos may also be tracked via a dedicated, bounded location record.
    local originalID = tonumber(md.HalloweenEventOriginalPersistentID) or 0
    local originalName = tostring(md.HalloweenEventOriginalOutfitName or "")
    if originalID == 0 and originalName == "" and not isGallerySpiffo then
        noteRecord("identity")
        return false
    end
    snapshot = snapshot or md.HalloweenEventVisualSnapshot
    if type(snapshot) ~= "table" or type(snapshot.Items) ~= "table" or #snapshot.Items == 0 then
        noteRecord("emptySnapshot")
        return false
    end
    local id = md.HalloweenEventWardrobeID and tostring(md.HalloweenEventWardrobeID)
    local entry = id and db.Entries[id]
    if not entry then
        local hold=saveHolds[zombie]
        local revision=md.HalloweenEventVisualRevision
        if hold and hold.revision==revision and (x-hold.x)^2+(y-hold.y)^2 <= 25 then
            noteRecord("repeatedHold")
            return false
        end
        -- The native outfit seed may be reused for a returning zombie even
        -- when its position no longer passes the safe restore match. The
        -- prior record stays untouched; do not multiply records for this
        -- uncertain reappearance. New zombies away from old anchors save
        -- normally. Existing md-linked zombies always update normally.
        if not isGallerySpiffo and uncertainReturningAppearance(db, zombie,
            x, y, z, safe(zombie, "isFemale") == true, originalID, originalName) then
            saveHolds[zombie]={x=x,y=y,revision=revision,reason="nearby"}
            noteRecord("nearbyHold")
            return false
        end
        -- Dense known-population areas are a specific source of duplicate
        -- records when B42 reconstitutes existing zombies after a restart.
        -- Do not claim an uncertain other zombie or erase its costume.
        if not isGallerySpiffo and uncertainCrowdedArea(db,zombie,
            x,y,z,safe(zombie,"isFemale")==true) then
            saveHolds[zombie]={x=x,y=y,revision=revision,reason="crowded"}
            noteRecord("crowdedHold")
            return false
        end
        if db.Count >= MAX_ENTRIES then
            -- Do not discard/replace a different zombie's saved outfit.
            noteRecord("full")
            return false
        end
        db.NextID = db.NextID + 1
        id = tostring(db.NextID)
        entry = {}
        db.Entries[id] = entry
        db.Count = db.Count + 1
        md.HalloweenEventWardrobeID = id
        saveHolds[zombie]=nil
        noteRecord("created")
    else
        noteRecord("updated")
        unlink(id, entry)
    end
    -- Anchor never drifts with live movement or re-uploads. For legacy rows
    -- the previously saved coordinate is the best available starting anchor.
    if entry.AnchorX == nil then
        entry.AnchorX, entry.AnchorY, entry.AnchorZ = entry.X or x, entry.Y or y, entry.Z or z
    end
    entry.CostumeID = costume.id
    entry.GallerySpiffo = (entry.GallerySpiffo == true) or isGallerySpiffo
    entry.X, entry.Y, entry.Z = x, y, z
    entry.OriginalID = originalID
    entry.OriginalName = originalName
    entry.Female = safe(zombie, "isFemale") == true
    if entry.Revision ~= md.HalloweenEventVisualRevision or entry.Snapshot == nil then
        entry.Snapshot = snapshot
        entry.Revision = md.HalloweenEventVisualRevision
    end
    link(id, entry)
    tracked[zombie] = id
    claimed[id] = zombie
    return true
end

-- Record exactly one non-match reason per attempted lookup. Categories are
-- ordered by the closest useful evidence among the buckets ALREADY searched.
-- They are diagnostics, not authorization to apply a costume.
function P.find(zombie)
    local db = load()
    if not db or not zombie then return nil end
    tally("attempts")
    local x, y, z = tonumber(safe(zombie, "getX")), tonumber(safe(zombie, "getY")), tonumber(safe(zombie, "getZ"))
    if not x or not y or not z then
        tally("missingPosition")
        return nil
    end
    local persistent = tonumber(safe(zombie, "getPersistentOutfitID"))
    local name = tostring(safe(zombie, "getOutfitName") or "")
    local female = safe(zombie, "isFemale") == true
    local best, bestID, score, ambiguous = nil, nil, nil, false
    local galleryBest, galleryID, galleryScore = nil, nil, nil
    local seen = {}
    local hasBucket, hasFloor, hasGender, hasUnclaimed = false, false, false, false
    local hasIdentity, hasDistanceFailure, hasNameConflict = false, false, false
    for dx=-1,1 do for dy=-1,1 do
        local key = bucket(x + dx*CELL, y + dy*CELL, z)
        for id in pairs(index[key] or {}) do
            if not seen[id] then
                seen[id] = true
                local e = db.Entries[id]
                if e then
                    hasBucket = true
                    if math.abs(z-e.Z) < 0.2 then
                        hasFloor = true
                        if e.Female == female then
                            hasGender = true
                            local owner = claimed[id]
                            if not owner or owner == zombie or safe(owner, "getCurrentSquare") == nil then
                                hasUnclaimed = true
                                local dist = squaredDistance(e,x,y)
                                local sameID = sameAppearance(persistent,e.OriginalID)
                                local sameName = name ~= "" and e.OriginalName ~= "" and name == e.OriginalName
                                if sameID or sameName then hasIdentity = true end
                                local conflicts = sameID and name ~= "" and e.OriginalName ~= "" and not sameName
                                if conflicts then hasNameConflict = true end
                                -- Identical to the previous patch's strict rules.
                                local fit = (sameID and dist <= 0.64 and
                                    (name == "" or e.OriginalName == "" or sameName)) or
                                    (sameName and dist <= 0.16)
                                if (sameID or sameName) and not fit and not conflicts then
                                    hasDistanceFailure = true
                                end
                                -- Gallery Spiffos have no dependable native
                                -- identity after B42 reconstructs population.
                                -- Reserve ONLY a known, previously stamped
                                -- Spiffo, matching gender and within 1.5 tiles.
                                -- The gallery pool is never used for ordinary
                                -- costume records or unrecognized zombies.
                                if e.GallerySpiffo == true and e.CostumeID == "SpiffoMascot"
                                    and dist <= 2.25 and (galleryScore == nil or dist < galleryScore) then
                                    galleryBest, galleryID, galleryScore = e, id, dist
                                end
                                if fit then
                                    local rank = dist + (sameID and 0 or 100)
                                    if not score or rank < score - 0.01 then
                                        best, bestID, score, ambiguous = e, id, rank, false
                                    elseif math.abs(rank-score) <= 0.01 then
                                        ambiguous = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end end
    -- Explicit gallery anchors take precedence over unrelated nearby ordinary
    -- zombies that happen to have the same non-unique persistent-outfit ID.
    -- The existing one-claim-per-entry reservation prevents double matches.
    if galleryBest then
        tally("matched")
        return galleryBest, galleryID
    end
    if ambiguous then tally("ambiguous"); return nil end
    if not best then
        local found, foundID, uncertain = recoverByAnchor(db, zombie,
            x, y, z, female, persistent, name)
        if found then
            tally("matched")
            tally("reconciled")
            if found.AnchorX and (x-found.AnchorX)^2+(y-found.AnchorY)^2 <
                (x-found.X)^2+(y-found.Y)^2 then tally("anchorMatched") end
            return found, foundID
        end
        if uncertain then tally("reconcileAmbiguous") end
        if not hasBucket then tally("noBucket")
        elseif not hasFloor then tally("floor")
        elseif not hasGender then tally("gender")
        elseif not hasUnclaimed then tally("claimed")
        elseif hasNameConflict then tally("nameConflict")
        elseif hasDistanceFailure or hasIdentity then tally("distance")
        elseif hasUnclaimed then tally("identity")
        else tally("other") end
        return nil
    end
    if not HWE.getCostumeByID(best.CostumeID) then
        tally("unavailableCostume")
        return nil
    end
    tally("matched")
    if best.AnchorX and (x-best.AnchorX)^2+(y-best.AnchorY)^2 <
        (x-best.X)^2+(y-best.Y)^2 then tally("anchorMatched") end
    return best, bestID
end

-- Called only after a confident match was found but the existing server-side
-- safety check prevented application. No extra visual checks are introduced.
function P.noteWornSkip()
    tally("blockedWorn")
end

-- Report and reset the previous window from the server's existing summary tick.
function P.drainDiagnostics()
    if diagnostics.attempts == 0 then return nil end
    local finished = diagnostics
    diagnostics = emptyDiagnostics()
    return finished
end

-- Also available when no lookup was attempted in this interval. This is the
-- honest 'did our save system fill up?' evidence the earlier logs lacked.
function P.drainRecordDiagnostics()
    local counts = recordDiagnostics
    recordDiagnostics = {created=0, updated=0, full=0,
        identity=0, gallery=0, emptySnapshot=0, nearbyHold=0,
        crowdedHold=0, repeatedHold=0}
    local db = load()
    if db then
        counts.count = db.Count or 0
        counts.cap = MAX_ENTRIES
        return counts
    end
    return nil
end

function P.claim(zombie, id)
    if not zombie or not id then return end
    local md = safe(zombie, "getModData")
    if md then md.HalloweenEventWardrobeID = id end
    tracked[zombie] = id
    claimed[id] = zombie
end

function P.onDeath(zombie)
    local db = load()
    if not db or not zombie then return end
    local md = safe(zombie, "getModData")
    local id = md and md.HalloweenEventWardrobeID and tostring(md.HalloweenEventWardrobeID) or tracked[zombie]
    local entry = id and db.Entries[id]
    if entry then
        unlink(id, entry)
        db.Entries[id] = nil
        db.Count = math.max(0, db.Count - 1)
        claimed[id] = nil
    end
    tracked[zombie] = nil
    saveHolds[zombie] = nil
end

-- Amortize movement/backfill over ordinary ticks; never inspect a full horde
-- in one tick. No snapshot work unless the zombie's revision changed.
function P.maintain(list, limit)
    if not list then return end
    local count = tonumber(safe(list, "size")) or 0
    if count == 0 then return end
    for i=1, math.min(limit or 16, count) do
        local zombie = safe(list, "get", cursor % count)
        cursor = cursor + 1
        if zombie and safe(zombie, "isAlive") == true then
            local md = safe(zombie, "getModData")
            if md and md.HalloweenEventCostumed == true and md.HalloweenEventSpawnQueued ~= true then
                local costume = HWE.getCostumeByID(md.HalloweenEventCostumeID)
                local id = md.HalloweenEventWardrobeID and tostring(md.HalloweenEventWardrobeID)
                local entry = id and load() and store.Entries[id]
                local x, y = tonumber(safe(zombie, "getX")), tonumber(safe(zombie, "getY"))
                if costume and x and y and (not entry or math.abs(x-entry.X) > 0.5
                    or math.abs(y-entry.Y) > 0.5 or entry.Revision ~= md.HalloweenEventVisualRevision) then
                    P.record(zombie, costume, nil,
                        md.HalloweenEventGalleryTest == true and costume.id == "SpiffoMascot")
                end
            end
        end
    end
    cursor = cursor % count
end

return P
