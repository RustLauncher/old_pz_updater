-- ============================================================================
-- HalloweenEvent_Shared.lua
-- Build 42.21+
-- ============================================================================

HalloweenEvent = HalloweenEvent or {}
local HWE = HalloweenEvent
HWE.VERSION = "0.6.5-fix18-native-test"
HWE.MOD_ID = "HalloweenEvent"

require "HalloweenEvent/HalloweenEvent_Text"
require "HalloweenEvent/HalloweenEvent_Costumes"
require "HalloweenEvent/HalloweenEvent_NativeOutfits"
require "HalloweenEvent/HalloweenEvent_Schedule"

function HWE.safeCall(obj, method, ...)
    if not obj then return nil end
    local fn = obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, obj, ...)
    if ok then return result end
    return nil
end

function HWE.tryCall(obj, method, ...)
    if not obj then return false, "nil object" end
    local fn = obj[method]
    if type(fn) ~= "function" then return false, "missing method: " .. tostring(method) end
    local ok, result = pcall(fn, obj, ...)
    if ok then return true, result end
    return false, result
end

-- PersistentOutfits.NO_HAT_BIT is 32768. Hat loss changes that flag, not the
-- native identity. Preserve every other bit, including the signed female bit.
-- Keep mummy's established strict identity path untouched.
function HWE.sameVisualOutfitID(a, b, costumeID)
    a, b = tonumber(a), tonumber(b)
    if not a or not b then return false end
    if a == b then return true end
    if costumeID == "BurlapMummy" then return false end
    return a - (a % 65536 >= 32768 and 32768 or 0)
        == b - (b % 65536 >= 32768 and 32768 or 0)
end

function HWE.isSantaImpaledType(fullType)
    for _, allowed in ipairs(HWE.SantaImpaledWeapons or {}) do
        if allowed == fullType then return true end
    end
    return false
end

-- Normal dressing in a very dense cell can produce thousands of log lines,
-- each with string creation/formatting cost, even if frame-time is bounded.
-- Preserve important failures, event state and all once-per-interval summaries.
-- Aggregated routine counters remain in the log for diagnosis.
local routinePrefixes={
    DEATH_LOOT_PREPARED=true, VISUAL_SYNC_SENT=true,
    COSTUME_VISUAL_APPLIED=true, DEATH_LOOT_CONTAINER_QUEUED=true,
    VISUAL_ITEM_RESOLVED=true, COSTUME_ACCESSORY_SELECTED=true,
    COSTUME_GENDER_ASSET=true, CLIENT_VISUAL_SYNC=true,
    CLIENT_VISUAL_GENDER_SETTLE=true, SANTA_HALLOWEEN_FALLBACK=true,
}
local routineCounts={}
HWE.DebugVerboseLogs=false -- Set true in a Lua debugging session for full traces.
-- Server-authoritative sandbox setting: absent in existing saves = OFF.
-- Read the raw sandbox flag here (not readSandbox) to avoid allocating a
-- configuration table on every zombie dressing/visual synchronization log.
function HWE.isDebugLoggingEnabled()
    local sb = SandboxVars and SandboxVars.HalloweenEvent
    return sb ~= nil and sb.EnableDebugLogging == true
end

-- Keep actionable errors visible even when routine logging is disabled.
-- Non-error informational lines and summaries are exclusively opt-in.
local criticalLogMarkers = {"_FAIL", "_ERROR", "_WARN", "_EXCEPTION", "_UNAVAILABLE", "FATAL"}
local function isCriticalLog(s)
    for _, marker in ipairs(criticalLogMarkers) do
        if s:find(marker, 1, true) then return true end
    end
    return false
end

function HWE.log(msg)
    -- OFF by default, including saves made before this sandbox option existed.
    -- Game/engine errors are unaffected by this mod's console setting.
    if not HWE.isDebugLoggingEnabled() then
        local s = tostring(msg)
        if isCriticalLog(s) then print("[HalloweenEvent] " .. s) end
        return
    end
    local s=tostring(msg)
    local prefix=s:match("^([A-Z0-9_]+)")
    if prefix and routinePrefixes[prefix] and not HWE.DebugVerboseLogs then
        routineCounts[prefix]=(routineCounts[prefix] or 0)+1
        return
    end
    print("[HalloweenEvent] " .. s)
end
function HWE.flushLogCounters()
    if not HWE.isDebugLoggingEnabled() then
        -- If an admin turns logging off mid-session, forget pending counters.
        for name in pairs(routineCounts) do routineCounts[name]=nil end
        return
    end
    local names={}
    for name in pairs(routineCounts) do names[#names+1]=name end
    if #names==0 then return end
    table.sort(names)
    local parts={}
    for _,name in ipairs(names) do
        parts[#parts+1]=name.."="..routineCounts[name]
        routineCounts[name]=nil
    end
    print("[HalloweenEvent] ROUTINE_LOG_SUMMARY "..table.concat(parts," "))
end

require "HalloweenEvent/HalloweenEvent_CostumeFilter"

function HWE.rollPercent(pct)
    pct = tonumber(pct) or 0
    if pct <= 0 then return false end
    if pct >= 100 then return true end
    return ZombRand(1, 101) <= pct
end

function HWE.rand(min, max)
    min, max = tonumber(min) or 1, tonumber(max) or 1
    min, max = math.floor(min), math.floor(max)
    if min > max then min, max = max, min end
    return ZombRand(min, max + 1)
end

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    return math.max(minValue, math.min(maxValue, value))
end

local function parseScheduleString(str, defM, defD, defH, defMin)
    if type(str) ~= "string" then return defM, defD, defH, defMin end
    local nums = {}
    for n in str:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
    if #nums >= 4 then return nums[1], nums[2], nums[3], nums[4] end
    if #nums == 3 then return nums[1], nums[2], nums[3], 0 end
    if #nums == 2 then return nums[1], nums[2], defH, defMin end
    return defM, defD, defH, defMin
end

function HWE.readSandbox()
    local sb = SandboxVars and SandboxVars.HalloweenEvent or {}
    local sm, sd, sh, smin = parseScheduleString(sb.StartSchedule, 10, 15, 0, 0)
    local em, ed, eh, emin = parseScheduleString(sb.EndSchedule, 10, 31, 23, 59)
    local minBag = clamp(sb.MinBagCandy, 1, 5)
    local maxBag = clamp(sb.MaxBagCandy, 1, 5)
    if minBag > maxBag then minBag, maxBag = maxBag, minBag end

    local function defaulted(value, default)
        return value == nil and default or value
    end

    return {
        EnableEvent = (sb.EnableEvent ~= false),
        UseCalendarTrigger = (sb.UseCalendarTrigger ~= false),
        ScheduleClock = tonumber(sb.ScheduleClock)==2 and 2 or 1,
        StartSchedule = sb.StartSchedule or "10/15 00:00",
        EndSchedule = sb.EndSchedule or "10/31 23:59",
        EventStartMessage = sb.EventStartMessage or "The Halloween Event has Started",
        EventEndMessage = sb.EventEndMessage or "The Halloween Event has Ended",
        EnableDebugMenu = (sb.EnableDebugMenu ~= false),
        EnableDebugLogging = (sb.EnableDebugLogging == true),
        CostumeBlacklist = tostring(sb.CostumeBlacklist or ""),
        CostumeChancePercent = clamp(defaulted(sb.CostumeChancePercent, 100), 0, 100),
        NaturalSpawnTotalWeight = math.max(0, tonumber(defaulted(sb.NaturalSpawnTotalWeight, 1.0)) or 1.0),
        CandyDropChancePercent = clamp(defaulted(sb.CandyDropChancePercent, 70), 0, 100),
        BagChancePercent = clamp(defaulted(sb.BagChancePercent, 30), 0, 100),
        CollectibleContainerChancePercent = clamp(defaulted(sb.CollectibleContainerChancePercent, 2), 0, 100),
        BagCandyChancePercent = clamp(defaulted(sb.BagCandyChancePercent, 65), 0, 100),
        MinBagCandy = minBag,
        MaxBagCandy = maxBag,
        WorldDecorationChancePercent = clamp(defaulted(sb.WorldDecorationChancePercent, 3), 0, 100),
        MaxDecorationsPerContainer = math.floor(clamp(defaulted(sb.MaxDecorationsPerContainer, 1), 0, 2)),
        DecorationChanceOnZombiePercent = clamp(defaulted(sb.DecorationChanceOnZombiePercent, 2), 0, 100),
        StartMonth = sm, StartDay = sd, StartHour = sh, StartMinute = smin,
        EndMonth = em, EndDay = ed, EndHour = eh, EndMinute = emin,
    }
end

local DAYS_BEFORE_MONTH = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }
local function dateToMinutes(m, d, h, min)
    m = clamp(m, 1, 12)
    d = clamp(d, 1, 31)
    h = clamp(h, 0, 23)
    min = clamp(min, 0, 59)
    local totalDays = (DAYS_BEFORE_MONTH[m] or 0) + (d - 1)
    return (totalDays * 24 + h) * 60 + min
end

function HWE.isCalendarActive(cfg)
    if cfg.ScheduleClock==2 then return HWE.Schedule.active(cfg) end
    local gt = type(getGameTime) == "function" and getGameTime() or nil
    if not gt then return false end

    local currentMonth = (HWE.safeCall(gt, "getMonth") or 0) + 1
    local currentDay = HWE.safeCall(gt, "getDayPlusOne") or ((HWE.safeCall(gt, "getDay") or 0) + 1)
    local currentHour = HWE.safeCall(gt, "getHour") or 0
    local currentMinute = HWE.safeCall(gt, "getMinutes") or 0

    local nowMinutes = dateToMinutes(currentMonth, currentDay, currentHour, currentMinute)
    local startMinutes = dateToMinutes(cfg.StartMonth, cfg.StartDay, cfg.StartHour, cfg.StartMinute)
    local finishMinutes = dateToMinutes(cfg.EndMonth, cfg.EndDay, cfg.EndHour, cfg.EndMinute)

    if finishMinutes >= startMinutes then
        return nowMinutes >= startMinutes and nowMinutes <= finishMinutes
    end
    return nowMinutes >= startMinutes or nowMinutes <= finishMinutes
end

function HWE.buildNaturalFamilies(zombie, excludeID)
    local costumes = HWE.Costumes or {}
    local female = HWE.safeCall(zombie, "isFemale") == true
    local families, byID, total = {}, {}, 0
    for _, costume in ipairs(costumes) do
        local genderOK = (costume.femaleOnly ~= true or female) and (costume.maleOnly ~= true or not female)
        local weight = math.max(0, math.floor(tonumber(costume.naturalWeight) or 100))
        if genderOK and costume.natural == true and costume.id ~= excludeID and weight > 0
            and HWE.CostumeFilter.isAllowed(costume) then
            local id = costume.poolFamily or costume.id
            local family = byID[id]
            if not family then
                family = {id=id, weight=weight, costumes={}, groups={}, byGroup={}}
                families[#families + 1], byID[id] = family, family
                total = total + weight
            end
            family.costumes[#family.costumes + 1] = costume
            local groupID = costume.poolGroup or id
            local group = family.byGroup[groupID]
            if not group then
                group = {id=groupID, costumes={}, weight=0}
                family.groups[#family.groups + 1], family.byGroup[groupID] = group, group
            end
            local variantWeight = math.max(1, math.floor(tonumber(costume.variantWeight) or 100))
            group.costumes[#group.costumes + 1] = costume
            group.weight = group.weight + variantWeight
        end
    end
    return families, total
end

local function pickFromFamilies(zombie, excludeID)
    local families, total = HWE.buildNaturalFamilies(zombie, excludeID)
    if total == 0 then return nil end
    local roll = ZombRand(1, total + 1)
    for _, family in ipairs(families) do
        roll = roll - family.weight
        if roll <= 0 then
            local group = family.groups[#family.groups == 1 and 1 or ZombRand(1, #family.groups + 1)]
            local variantRoll = ZombRand(1, group.weight + 1)
            for _, costume in ipairs(group.costumes) do
                variantRoll = variantRoll - math.max(1, math.floor(tonumber(costume.variantWeight) or 100))
                if variantRoll <= 0 then return costume end
            end
        end
    end
    return nil
end

-- Automatic event spawning uses only explicitly approved natural costumes.
-- Debug/gallery spawning can still address every profile by ID.
function HWE.pickRandomCostume(zombie)
    return pickFromFamilies(zombie, nil)
end

function HWE.pickDifferentCostume(zombie, currentCostumeID)
    return pickFromFamilies(zombie, currentCostumeID) or HWE.pickRandomCostume(zombie)
end

function HWE.getCostumeByOutfit(outfitName)
    if not outfitName or outfitName == "" then return nil end
    for _, costume in ipairs(HWE.Costumes or {}) do
        for _, name in ipairs(costume.outfits or { costume.outfit }) do
            if name == outfitName then return costume end
        end
    end
    return nil
end

-- Natural-spawn detection deliberately ignores approximation profiles such as
-- Goth/Punk/Tourist. Those names can occur on ordinary vanilla zombies and
-- must not be mistaken for an HWE costume.
function HWE.getNaturalCostumeByOutfit(outfitName)
    if not outfitName or outfitName == "" then return nil end
    for _, costume in ipairs(HWE.Costumes or {}) do
        if costume.natural == true and costume.approx ~= true and costume.isMask ~= true and costume.detectByOutfit ~= false
            and HWE.CostumeFilter.isAllowed(costume) then
            for _, name in ipairs(costume.outfits or { costume.outfit }) do
                if name == outfitName then return costume end
            end
        end
    end
    return nil
end

function HWE.isHalloweenOutfitName(outfitName)
    return HWE.getCostumeByOutfit(outfitName) ~= nil
end

function HWE.getCostumeFemaleChance(zombie, costume, preserveGender)
    if costume and costume.femaleOnly == true then return 100 end
    if costume and costume.maleOnly == true then return 0 end
    if preserveGender and zombie then
        return HWE.safeCall(zombie, "isFemale") == true and 100 or 0
    end
    return 50
end

local function outfitName(zombie)
    return tostring(HWE.safeCall(zombie, "getOutfitName") or "")
end

function HWE.captureOriginalOutfit(zombie, md)
    if not zombie or not md then return end
    if md.HalloweenEventSnapshotVersion == HWE.VERSION then return end
    local current = outfitName(zombie)
    local persistentID = tonumber(HWE.safeCall(zombie, "getPersistentOutfitID") or 0) or 0
    md.HalloweenEventSnapshotVersion = HWE.VERSION
    if HWE.isHalloweenOutfitName(current) then
        md.HalloweenEventOriginalOutfitName = ""
        md.HalloweenEventOriginalPersistentID = 0
    else
        md.HalloweenEventOriginalOutfitName = current
        md.HalloweenEventOriginalPersistentID = persistentID
    end
end

function HWE.applyCostume(zombie, costume, options)
    options = options or {}
    if not zombie or not costume or not costume.outfit then return false end
    if HWE.safeCall(zombie, "isAlive") ~= true then return false end
    if costume.femaleOnly == true and HWE.safeCall(zombie, "isFemale") ~= true then
        HWE.log("COSTUME_APPLY_GENDER_SKIP id=" .. tostring(costume.id))
        return false
    end
    if costume.maleOnly == true and HWE.safeCall(zombie, "isFemale") == true then return false end

    local md = HWE.safeCall(zombie, "getModData")
    if not md then return false end

    if md.HalloweenEventCostumed == true
        and md.HalloweenEventManagedVersion == HWE.VERSION
        and md.HalloweenEventCostumeID == costume.id then
        return true
    end

    if not options.skipSnapshot then HWE.captureOriginalOutfit(zombie, md) end

    local target = tostring(costume.outfit)
    local okNamed, namedErr = HWE.tryCall(zombie, "dressInNamedOutfit", target)
    local applied = okNamed == true
    local persistentErr = nil

    if not applied then
        local okPersistent, err = HWE.tryCall(zombie, "dressInPersistentOutfit", target)
        applied = okPersistent == true
        persistentErr = err
    end

    if not applied then
        HWE.log("COSTUME_APPLY_FAIL id=" .. tostring(costume.id)
            .. " outfit=" .. target
            .. " named=" .. tostring(namedErr)
            .. " persistent=" .. tostring(persistentErr))
        return false
    end

    HWE.tryCall(zombie, "setDressInRandomOutfit", false)
    HWE.tryCall(zombie, "resetModelNextFrame")

    md.HalloweenEventCostumed = true
    md.HalloweenEventCostumeID = costume.id
    md.HalloweenEventCostumeOutfit = target
    md.HalloweenEventManagedVersion = HWE.VERSION
    md.HalloweenEventManagedSpawn = options.managedSpawn == true
    md.HalloweenEventVisualRevision = (tonumber(md.HalloweenEventVisualRevision) or 0) + 1
    md.HalloweenEventLootAwarded = nil
    md.HalloweenEventLootPrepared = nil
    md.HalloweenEventSpawnQueued = nil
    md.HalloweenEventSeenVersion = HWE.VERSION

    HWE.log("COSTUME_APPLIED id=" .. tostring(costume.id)
        .. " outfit=" .. target
        .. " actual=" .. outfitName(zombie)
        .. " reason=" .. tostring(options.reason or "unknown"))
    return true
end

function HWE.tagSpawnedCostume(zombie, costume, originalName, originalID)
    if not zombie or not costume then return false end
    if HWE.safeCall(zombie, "isAlive") ~= true then return false end
    local md = HWE.safeCall(zombie, "getModData")
    if not md then return false end
    md.HalloweenEventCostumed = true
    md.HalloweenEventCostumeID = costume.id
    md.HalloweenEventCostumeOutfit = costume.outfit
    md.HalloweenEventManagedVersion = HWE.VERSION
    md.HalloweenEventManagedSpawn = true
    md.HalloweenEventSnapshotVersion = HWE.VERSION
    md.HalloweenEventOriginalOutfitName = tostring(originalName or "")
    md.HalloweenEventOriginalPersistentID = tonumber(originalID or 0) or 0
    md.HalloweenEventLootAwarded = nil
    md.HalloweenEventLootPrepared = nil
    md.HalloweenEventSpawnQueued = nil
    md.HalloweenEventSeenVersion = HWE.VERSION
    HWE.tryCall(zombie, "setDressInRandomOutfit", false)
    HWE.tryCall(zombie, "resetModelNextFrame")
    return true
end

-- Diagnostic-only visual check. Never reject or destroy a zombie because a
-- clothing read is unavailable during the same frame the outfit was assigned.
function HWE.hasWornType(zombie, fullType)
    local worn = HWE.safeCall(zombie, "getWornItems")
    if not worn then return nil end
    local size = tonumber(HWE.safeCall(worn, "size"))
    if not size then return nil end
    for i = 0, size - 1 do
        local wornItem = HWE.safeCall(worn, "get", i)
        if wornItem then
            local item = HWE.safeCall(wornItem, "getItem") or wornItem
            local actual = item and HWE.safeCall(item, "getFullType")
            if tostring(actual or "") == tostring(fullType) then return true end
        end
    end
    return false
end

function HWE.visualTypes(zombie)
    local visuals = HWE.safeCall(zombie, "getItemVisuals")
    local result = {}
    local count = visuals and tonumber(HWE.safeCall(visuals, "size")) or 0
    for i = 0, (count or 0) - 1 do
        local visual = HWE.safeCall(visuals, "get", i)
        result[#result + 1] = tostring(HWE.safeCall(visual, "getItemType") or "?")
    end
    return result
end

function HWE.hasVisualType(zombie, fullType)
    for _, actual in ipairs(HWE.visualTypes(zombie)) do
        if actual == fullType then return true end
    end
    return false
end

function HWE.verifyCostume(zombie, costume)
    local expected = costume and (costume.visualItems or costume.additionalItems or costume.verifyAnyTypes)
    if not expected or #expected == 0 then return nil end
    if costume.visualItems or costume.additionalItems then
        for _, fullType in ipairs(expected) do
            if not HWE.hasVisualType(zombie, fullType) then return false end
        end
        if costume.visualItems and costume.optionalItems and costume.visualMode == "replace" then
            local allowed, seen, optionalCount = {}, {}, 0
            for _, fullType in ipairs(expected) do allowed[fullType] = "required" end
            for _, fullType in ipairs(costume.optionalItems) do allowed[fullType] = "optional" end
            for _, actual in ipairs(HWE.visualTypes(zombie)) do
                if not allowed[actual] or seen[actual] then return false end
                seen[actual] = true
                if allowed[actual] == "optional" then optionalCount = optionalCount + 1 end
            end
            return optionalCount <= 1
        end
        return costume.visualMode ~= "replace" or #HWE.visualTypes(zombie) == #expected
    end
    for _, fullType in ipairs(expected) do
        if HWE.hasVisualType(zombie, fullType) then return true end
    end
    return false
end

-- Walking zombies use their ItemVisuals list. WornItems verification can give
-- a false success while the zombie still renders a robe. Preflight every asset
-- before touching the list, then retain the native backing clothes for masks.
local resolvedLogged = {}
local genderLogged = {}
function HWE.applyCostumeVisuals(zombie, costume, context)
    local expected = costume and costume.visualItems
    if not expected or #expected == 0 then return nil end
    local visuals = HWE.safeCall(zombie, "getItemVisuals")
    if not visuals then return false, "getItemVisuals unavailable" end
    if not ItemVisual or type(ItemVisual.new) ~= "function" then
        return false, "ItemVisual constructor unavailable"
    end
    local staged, slots = {}, {}
    for itemIndex, fullType in ipairs(expected) do
        local ok, visual = pcall(function() return ItemVisual.new() end)
        if not ok or not visual then return false, "ItemVisual create failed: " .. fullType end
        local setOK, setErr = HWE.tryCall(visual, "setItemType", fullType)
        if not setOK then return false, tostring(setErr) end
        local script = HWE.safeCall(visual, "getScriptItem")
        local clothing = HWE.safeCall(visual, "getClothingItem")
        local slot = script and HWE.safeCall(script, "getBodyLocation")
        local logKey = (tostring(context or ""):match("^[^_]+") or "unknown") .. ":" .. costume.id .. ":" .. fullType
        if not resolvedLogged[logKey] or not script or not clothing then
            HWE.log("VISUAL_ITEM_RESOLVED context=" .. tostring(context)
                .. " id=" .. tostring(costume.id) .. " type=" .. fullType
                .. " script=" .. tostring(script ~= nil) .. " clothing=" .. tostring(clothing ~= nil)
                .. " location=" .. tostring(slot))
            resolvedLogged[logKey] = script ~= nil and clothing ~= nil
        end
        if not script or not clothing then return false, "unresolved clothing asset: " .. fullType end
        if costume.auditGenderAssets then
            local female = HWE.safeCall(zombie, "isFemale") == true
            local genderKey = logKey .. ":" .. tostring(female)
            if not genderLogged[genderKey] then
                -- Texture-only clothing can legitimately have no mesh model.
                -- Report both models; never equate a missing mesh with nakedness.
                HWE.log("COSTUME_GENDER_ASSET id=" .. tostring(costume.id) .. " type=" .. fullType
                    .. " female=" .. tostring(female)
                    .. " hasModel=" .. tostring(HWE.safeCall(clothing, "hasModel"))
                    .. " maleModel=" .. tostring(HWE.safeCall(clothing, "getMaleModel"))
                    .. " femaleModel=" .. tostring(HWE.safeCall(clothing, "getFemaleModel")))
                genderLogged[genderKey] = true
            end
        end
        local initOK, initErr = HWE.tryCall(visual, "pickUninitializedValues", clothing)
        if not initOK then return false, tostring(initErr) end
        local appearance = costume.visualAppearance and costume.visualAppearance[itemIndex]
        local tint = appearance and appearance.Tint or (costume.visualTints and costume.visualTints[fullType])
        -- Roll only for a fresh recipe. Network snapshots provide fixed appearance.
        local choices = costume.visualTintChoices and costume.visualTintChoices[fullType]
        if not appearance and choices and #choices > 0 then
            tint = choices[ZombRand(1, #choices + 1)]
        end
        if tint and ImmutableColor and type(ImmutableColor.new) == "function" then
            local tintOK, color = pcall(function() return ImmutableColor.new(tint[1], tint[2], tint[3]) end)
            if tintOK then HWE.tryCall(visual, "setTint", color) end
        end
        if appearance then
            if appearance.Hue ~= nil then HWE.tryCall(visual, "setHue", appearance.Hue) end
            if appearance.BaseTexture ~= nil then HWE.tryCall(visual, "setBaseTexture", appearance.BaseTexture) end
            if appearance.TextureChoice ~= nil then HWE.tryCall(visual, "setTextureChoice", appearance.TextureChoice) end
            if appearance.Decal then HWE.tryCall(visual, "setDecal", appearance.Decal) end
        end
        if (costume.id=="JasonSlasher" and fullType=="Base.Boilersuit"
            and tostring(context or ""):find("client",1,true)~=1)
            or (costume.id=="Witch_StraplessDress" and fullType=="Base.Dress_SmallStrapless" and tint) then
            -- Live ItemVisual tint and InventoryItem color are separate. Bind
            -- the authoritative coveralls to a real clothing item so native
            -- corpse conversion carries both, instead of default white RGB.
            local item=instanceItem(fullType)
            local nativeVisual=item and item:getVisual()
            local color=(costume.id=="Witch_StraplessDress" and ImmutableColor.new(tint[1],tint[2],tint[3])) or visual:getTint(clothing)
            if not item or not nativeVisual or not color then return false,"Costume colored clothing item unavailable" end
            nativeVisual:copyFrom(visual);nativeVisual:setInventoryItem(item)
            item:setCustomColor(true)
            item:setColorRed(color:getRedFloat())
            item:setColorGreen(color:getGreenFloat())
            item:setColorBlue(color:getBlueFloat())
            local nativeColor=item:getColor():scaleCopy(1)
            nativeColor:set(color:getRedFloat(),color:getGreenFloat(),color:getBlueFloat(),1)
            item:setColor(nativeColor)
            if costume.id=="Witch_StraplessDress" then nativeVisual:setTint(color) end
            visual=nativeVisual
        end
        staged[#staged + 1] = visual
        if slot then slots[tostring(slot)] = true end
    end

    -- Preserve the persistent outfit ID for save/network identity, but prevent
    -- its deferred initialisation from overwriting the exact visuals.
    local persistentID = tonumber(HWE.safeCall(zombie, "getPersistentOutfitID") or 0) or 0
    local freezeOK = HWE.tryCall(zombie, "setPersistentOutfitID", persistentID, true)
    HWE.tryCall(zombie, "setDressInRandomOutfit", false)
    if costume.visualMode == "replace" then
        local clearOK, clearErr = HWE.tryCall(visuals, "clear")
        if not clearOK then return false, tostring(clearErr) end
        -- Clear the old Fix5 worn records as well: they are not the live visual
        -- source and must not retain the temporary robe as inventory clothing.
        local isClientPresentation = tostring(context or ""):find("client", 1, true) == 1
        local worn = not isClientPresentation and HWE.safeCall(zombie, "getWornItems") or nil
        local inventory = HWE.safeCall(zombie, "getInventory")
        for i = (tonumber(HWE.safeCall(worn, "size")) or 0) - 1, 0, -1 do
            local entry = HWE.safeCall(worn, "get", i)
            local item = entry and HWE.safeCall(entry, "getItem")
            if item and inventory then HWE.tryCall(inventory, "DoRemoveItem", item) end
        end
        if not isClientPresentation then HWE.tryCall(zombie, "clearWornItems") end
    else
        -- Java remove(number) can select remove(Object), return false, and
        -- silently retain duplicates. Rebuild using retained visual objects.
        local retained = {}
        for i = 0, (tonumber(HWE.safeCall(visuals, "size")) or 0) - 1 do
            local old = HWE.safeCall(visuals, "get", i)
            local script = old and HWE.safeCall(old, "getScriptItem")
            local slot = script and HWE.safeCall(script, "getBodyLocation")
            local slotName = tostring(slot or ""):lower():gsub("^base:", "")
            local conflict = (slot and slots[tostring(slot)]) or (costume.isMask and
                (slotName == "hat" or slotName == "fullhat" or slotName == "mask"
                 or slotName == "maskeyes" or slotName == "eyes"))
            if not conflict then retained[#retained + 1] = old end
        end
        local clearOK, clearErr = HWE.tryCall(visuals, "clear")
        if not clearOK then return false, tostring(clearErr) end
        for _, old in ipairs(retained) do HWE.tryCall(visuals, "add", old) end
    end
    for _, visual in ipairs(staged) do
        local ok, err = HWE.tryCall(visuals, "add", visual)
        if not ok then return false, tostring(err) end
    end
    HWE.tryCall(zombie, "resetModelNextFrame")
    local verified = HWE.verifyCostume(zombie, costume)
    HWE.log("COSTUME_VISUAL_APPLIED context=" .. tostring(context)
        .. " id=" .. tostring(costume.id) .. " onlineID=" .. tostring(HWE.safeCall(zombie, "getOnlineID"))
        .. " usingWorn=" .. tostring(HWE.safeCall(zombie, "isUsingWornItems"))
        .. " persistentInit=" .. tostring(freezeOK)
        .. " verified=" .. tostring(verified) .. " types=" .. table.concat(HWE.visualTypes(zombie), ","))
    if verified then
        local md = HWE.safeCall(zombie, "getModData")
        if md then md.HalloweenEventVisualRecipeVersion = HWE.VERSION end
        return true, nil
    end
    return false, "visual verification incomplete"
end

-- Full server snapshot: item types plus their chosen tint/texture. This also
-- covers working vanilla profiles and saved/streamed zombies, not just masks.
function HWE.captureVisualSnapshot(zombie)
    local visuals = HWE.safeCall(zombie, "getItemVisuals")
    local items, appearance = {}, {}
    for i = 0, (tonumber(HWE.safeCall(visuals, "size")) or 0) - 1 do
        local visual = HWE.safeCall(visuals, "get", i)
        local itemType = HWE.safeCall(visual, "getItemType")
        if not itemType then return nil end
        items[#items + 1] = tostring(itemType)
        local tint = HWE.safeCall(visual, "getTint")
        local color
        if tint then
            local r = tonumber(HWE.safeCall(tint, "getRedFloat"))
            local g = tonumber(HWE.safeCall(tint, "getGreenFloat"))
            local b = tonumber(HWE.safeCall(tint, "getBlueFloat"))
            if r and g and b then color = {r,g,b} end
        end
        appearance[#appearance + 1] = {Tint=color,
            Hue=tonumber(HWE.safeCall(visual, "getHue")),
            BaseTexture=tonumber(HWE.safeCall(visual, "getBaseTexture")),
            TextureChoice=tonumber(HWE.safeCall(visual, "getTextureChoice")),
            Decal=HWE.safeCall(visual, "getDecal", HWE.safeCall(visual, "getClothingItem"))}
    end
    if #items == 0 then return nil end
    return {Items=items, Appearance=appearance}
end

function HWE.snapshotRecipe(costume, snapshot)
    if not costume or not snapshot or type(snapshot.Items) ~= "table" or #snapshot.Items == 0 then return nil end
    return {id=costume.id, visualMode="replace", visualItems=snapshot.Items,
        visualAppearance=snapshot.Appearance}
end

return HWE
