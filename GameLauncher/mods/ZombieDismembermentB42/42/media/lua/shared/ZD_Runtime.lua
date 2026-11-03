require "ZD_Shared"
local Impact = require "ZD_Impact"
local Debris = require "ZD_Debris"
require "ZD_Network"
local N = ZD_Network
local ZD = ZombieDismemberment

local syncGeneration = 1
local DEBUG = false

local function log(fmt, ...)
    if DEBUG then print("[ZombieDismemberment] " .. string.format(fmt, ...)) end
end

local errors = {}

local function warn(name, err)
    if errors[name] then return end
    errors[name] = true
    print("[ZombieDismemberment] ERROR " .. name .. ": " .. tostring(err))
end

local function sandbox(name, fallback)
    local root = SandboxVars and SandboxVars.ZombieDismemberment
    if root and root[name] ~= nil then return root[name] end
    return fallback
end

local function dropPiece(zombie, limb, side, cut, previous, attacker, kind)
    if isClient() or isServer() then return end
    local option = limb == "Cloth" and "DropCloth" or "DropParts"
    if not sandbox(option, false) then return end
    local ok, err = pcall(Debris.spawn, zombie, limb, side, cut, previous, attacker, kind)
    if not ok then warn("piece effect failed", err)
    elseif limb == "Cloth" then
        log("cloth drop created=%s max=%s", tostring(err == true), tostring(sandbox("DropMax", 24)))
    end
end

local ourVisuals = {}
for _, itemType in ipairs(ZD.ALL_VISUALS) do ourVisuals[itemType] = true end

local function isOurVisualType(itemType)
    return ourVisuals[itemType] == true
end

local function zombieTextureIndex(zombie)
    local idx = 0
    local ok, err = pcall(function()
        local skin = zombie:getHumanVisual():getSkinTexture()
        local family = tonumber(skin:match("ZedBody0(%d)"))
        local level = tonumber(skin:match("(%d)$"))
        if family and level then
            idx = (family - 1) * 3 + (level - 1)
            if idx < 0 or idx > 11 then idx = 0 end
        end
    end)
    if not ok then warn("skin texture error", err) end
    return idx
end

local function removeAllOurVisuals(visuals)
    for i = visuals:size() - 1, 0, -1 do
        local iv = visuals:get(i)
        local t = iv and iv:getItemType() or nil
        if isOurVisualType(t) then visuals:remove(iv) end
    end
end

local function addVisual(visuals, itemType, texIdx)
    if not itemType then return end
    local iv = ItemVisual:new()
    iv:setItemType(itemType)
    if texIdx ~= nil then iv:setTextureChoice(texIdx) end
    visuals:add(iv)
end

local function visualsMatchState(zombie, state)
    if not zombie then return false end
    local visuals = zombie:getItemVisuals()
    if not visuals then return false end
    local expected = {}
    if ZD.validCut(state.L) then expected[ZD.VISUALS[state.L].L] = true end
    if ZD.validCut(state.R) then expected[ZD.VISUALS[state.R].R] = true end
    if ZD.validLeg(state.LegL) then expected[ZD.VISUALS.WholeLeg.L] = true end
    if ZD.validLeg(state.LegR) then expected[ZD.VISUALS.WholeLeg.R] = true end
    if ZD.validHead(state.Head) then expected[ZD.VISUALS.Head.L] = true end
    local seen = {}
    for i = 0, visuals:size() - 1 do
        local iv = visuals:get(i)
        local t = iv and iv:getItemType() or nil
        if isOurVisualType(t) then seen[t] = true end
    end
    for t in pairs(expected) do if not seen[t] then return false end end
    for t in pairs(seen) do if not expected[t] then return false end end
    return true
end

local mergeStates = ZD.mergeStates

local function hasAnyState(state)
    return type(state) == "table" and (ZD.validCut(state.L) or ZD.validCut(state.R)
        or ZD.validLeg(state.LegL) or ZD.validLeg(state.LegR) or ZD.validHead(state.Head))
end

local function readLiveState(zombie)
    if not zombie then return {} end
    local md = zombie:getModData()
    return ZD.copyState({
        L = md.ZD_L, R = md.ZD_R,
        LegL = md.ZD_LegL, LegR = md.ZD_LegR,
        Head = md.ZD_Head,
    })
end

local function writeLiveState(zombie, id, state)
    if not zombie then return end
    local md = zombie:getModData()
    if id then md.ZD_trueID = tostring(id) end
    local clean = ZD.copyState(state)
    md.ZD_L = clean.L
    md.ZD_R = clean.R
    md.ZD_LegL = clean.LegL
    md.ZD_LegR = clean.LegR
    md.ZD_Head = clean.Head
end

local function stateForZombie(zombie, id)
    if N.enabled() then return N.state(zombie) end
    local globalState = nil
    if id then globalState = ZD.getData().zombies[tostring(id)] end
    return mergeStates(ZD.copyLimbState(globalState), readLiveState(zombie))
end

local function bodyLocationName(iv)
    if not iv then return nil end
    local si = iv:getScriptItem()
    local loc = si and si:getBodyLocation()
    return loc and loc:getTranslationName() or nil
end

local function containsPlain(text, needle)
    return text and needle and string.find(text, needle, 1, true) ~= nil
end

local function isBridgeVisualType(itemType)
    local ft = tostring(itemType or "")
    return string.find(ft, "ZombieDismemberment.ZD_Corpse_", 1, true) == 1
end

local ARM_LOCS = {
    L = {
        ForeArm = {
            LeftWrist=true, Left_MiddleFinger=true, Left_RingFinger=true,
            HandsLeft=true, Hands=true, ForeArm_Left=true,
        },
        UpperArm = {
            LeftWrist=true, Left_MiddleFinger=true, Left_RingFinger=true,
            HandsLeft=true, Hands=true, ForeArm_Left=true,
            Elbow_Left=true, LeftArm=true, ShoulderpadLeft=true,
        },
    },
    R = {
        ForeArm = {
            RightWrist=true, Right_MiddleFinger=true, Right_RingFinger=true,
            HandsRight=true, Hands=true, ForeArm_Right=true,
        },
        UpperArm = {
            RightWrist=true, Right_MiddleFinger=true, Right_RingFinger=true,
            HandsRight=true, Hands=true, ForeArm_Right=true,
            Elbow_Right=true, RightArm=true, ShoulderpadRight=true,
        },
    },
}

local LEG_LOCS = {
    L = {
        Thigh_Left=true, Knee_Left=true, Calf_Left=true, Gaiter_Left=true,
        Shoes=true, Socks=true, AnkleHolster=true,
    },
    R = {
        Thigh_Right=true, Knee_Right=true, Calf_Right=true, Gaiter_Right=true,
        Shoes=true, Socks=true, AnkleHolster=true,
    },
}

local function isTransientDamageVisual(itemType, loc)
    local low = string.lower(tostring(itemType or ""))
    if loc == "Bandage" or loc == "Wound" or loc == "ZedDmg" then return true end
    if containsPlain(low, "bandage_") or containsPlain(low, "wound") then return true end
    return false
end

local function bandageMatchesArm(itemType, side, cut)
    local low = string.lower(tostring(itemType or ""))
    if not containsPlain(low, "bandage_") then return false end
    local prefix = side == "L" and "left" or "right"
    if containsPlain(low, "bandage_" .. prefix .. "hand") then return true end
    if containsPlain(low, "bandage_" .. prefix .. "lowerarm") then return true end
    if cut == "UpperArm" and containsPlain(low, "bandage_" .. prefix .. "upperarm") then return true end
    return false
end

local function bandageMatchesLeg(itemType, side)
    local low = string.lower(tostring(itemType or ""))
    if not containsPlain(low, "bandage_") then return false end
    local prefix = side == "L" and "left" or "right"
    return containsPlain(low, "bandage_" .. prefix .. "upperleg")
        or containsPlain(low, "bandage_" .. prefix .. "lowerleg")
        or containsPlain(low, "bandage_" .. prefix .. "foot")
end

local function woundMatchesArm(itemType, side, cut)
    local low = string.lower(tostring(itemType or ""))
    if not containsPlain(low, "wound_") then return false end
    if side == "L" then
        if containsPlain(low, "wound_lhand_") or containsPlain(low, "wound_lforearm_") then return true end
        if cut == "UpperArm" and containsPlain(low, "wound_luarm_") then return true end
    else
        if containsPlain(low, "wound_rhand_") or containsPlain(low, "wound_rforearm_") then return true end
        if cut == "UpperArm" and containsPlain(low, "wound_ruarm_") then return true end
    end
    return false
end

local function shouldRemoveArm(itemType, loc, side, cut)
    if not itemType or isOurVisualType(itemType) or isBridgeVisualType(itemType) then return false end
    local locs = ARM_LOCS[side] and ARM_LOCS[side][cut]
    if locs and loc and locs[loc] then return true end
    return bandageMatchesArm(itemType, side, cut) or woundMatchesArm(itemType, side, cut)
end

local function shouldRemoveLeg(itemType, loc, side)
    if not itemType or isOurVisualType(itemType) or isBridgeVisualType(itemType) then return false end
    if Impact.isFootwear(itemType, loc) then return true end
    local low = string.lower(tostring(itemType or ""))

    if loc == "Skirt" or containsPlain(low, "skirt") then return true end
    local locs = LEG_LOCS[side]
    if locs and loc and locs[loc] then return true end
    return bandageMatchesLeg(itemType, side)
end

local function cleanupVisualList(visuals, limb, side, cut, label)
    local removed = 0
    if not visuals then return removed end
    for i = visuals:size() - 1, 0, -1 do
        local iv = visuals:get(i)
        local itemType = iv and iv:getItemType() or nil
        local loc = bodyLocationName(iv)
        local match = limb == "Arm"
            and shouldRemoveArm(itemType, loc, side, cut)
            or limb == "Leg" and shouldRemoveLeg(itemType, loc, side)
        if match then
            visuals:remove(iv)
            removed = removed + 1
            log("deleted %s visual %s (%s) from %s%s", tostring(label), tostring(itemType), tostring(loc), side, limb)
        end
    end
    return removed
end

local function wornLocationName(wi)
    if not wi then return nil end
    local loc = wi:getLocation()
    return loc and loc:getTranslationName() or nil
end

local function cleanupWornItems(zombie, limb, side, cut)
    local removed = 0
    local ok, err = pcall(function()
        local worn = zombie:getWornItems()
        if not worn then return end
        for i = worn:size() - 1, 0, -1 do
            local wi = worn:get(i)
            local item = wi and wi:getItem() or nil
            local itemType = item and item:getFullType() or nil
            local loc = wornLocationName(wi)
            local match = limb == "Arm"
                and shouldRemoveArm(itemType, loc, side, cut)
                or limb == "Leg" and shouldRemoveLeg(itemType, loc, side)
            if match and item then
                worn:remove(item)
                local inv = zombie:getInventory()
                if inv then inv:Remove(item) end
                removed = removed + 1
                log("deleted worn item %s (%s) from %s%s", tostring(itemType), tostring(loc), side, limb)
            end
        end
        if removed > 0 then zombie:onWornItemsChanged() end
    end)
    if not ok then warn("worn-item cleanup error", err) end
    return removed
end

local function cleanupAccessories(zombie, limb, side, cut)
    if not zombie then return 0 end
    local removed = 0
    if limb == "Leg" then
        removed = removed + Impact.cleanup(zombie, Impact.isFootwear)
    end
    local ok, err = pcall(function()

        removed = removed + cleanupVisualList(zombie:getItemVisuals(), limb, side, cut, "outfit")

        local hv = zombie:getHumanVisual()
        if hv then
            removed = removed + cleanupVisualList(hv:getBodyVisuals(), limb, side, cut, "body")
        end

        removed = removed + cleanupWornItems(zombie, limb, side, cut)
    end)
    if not ok then warn("accessory cleanup error", err) end
    return removed
end

local function cleanupAccessoriesForState(zombie, state)
    if ZD.validHead(state.Head) then Impact.cleanup(zombie, Impact.isHeadAccessory) end
    if ZD.validCut(state.L) then cleanupAccessories(zombie, "Arm", "L", state.L) end
    if ZD.validCut(state.R) then cleanupAccessories(zombie, "Arm", "R", state.R) end
    if ZD.validLeg(state.LegL) then cleanupAccessories(zombie, "Leg", "L", state.LegL) end
    if ZD.validLeg(state.LegR) then cleanupAccessories(zombie, "Leg", "R", state.LegR) end
end

local LONG_SLEEVE_BLOOD_TYPES = {
    ShirtLongSleeves = true,
    Jumper = true,
    Jacket = true,
    LongJacket = true,
}

local function bloodClothingTypeName(bt)
    if not bt then return nil end
    return bt:name()
end

local function scriptItemHasTrueLongSleeves(si)
    if not si then return false end
    local types = si:getBloodClothingType()
    if not types then return false end

    local hasUpperArm = false
    local hasForeArm = false
    for i = 0, types:size() - 1 do
        local name = bloodClothingTypeName(types:get(i))
        if LONG_SLEEVE_BLOOD_TYPES[name] then return true end
        if name == "UpperArms" or name == "UpperArm_L" or name == "UpperArm_R" then
            hasUpperArm = true
        elseif name == "LowerArms" or name == "ForeArm_L" or name == "ForeArm_R" then
            hasForeArm = true
        end
    end
    return hasUpperArm and hasForeArm
end

local function visualIsTrueLongSleeveGarment(iv)
    if not iv then return false end
    local itemType = iv:getItemType()
    if not itemType or isOurVisualType(itemType) or isBridgeVisualType(itemType) then return false end
    if isTransientDamageVisual(itemType, bodyLocationName(iv)) then return false end

    local si = iv:getScriptItem()
    return scriptItemHasTrueLongSleeves(si)
end

local function itemIsTrueLongSleeveGarment(item)
    if not item then return false end
    local ft = item:getFullType()
    if not ft or isBridgeVisualType(ft) then return false end

    local si = item:getScriptItem()
    return scriptItemHasTrueLongSleeves(si)
end

local function destroyTrueLongSleevesOnFinalBlow(zombie, state)
    if not zombie or type(state) ~= "table" then return 0 end
    if not ZD.validCut(state.L) and not ZD.validCut(state.R) then return 0 end

    local removedVisuals = 0
    local removedItems = 0

    local ok, err = pcall(function()
        local visuals = zombie:getItemVisuals()
        if not visuals then return end
        for i = visuals:size() - 1, 0, -1 do
            local iv = visuals:get(i)
            if visualIsTrueLongSleeveGarment(iv) then
                visuals:remove(iv)
                removedVisuals = removedVisuals + 1
            end
        end
    end)

    if not ok then warn("sleeve visual cleanup error", err) end
    ok, err = pcall(function()
        local worn = zombie:getWornItems()
        local inv = zombie:getInventory()
        if not worn then return end
        for i = worn:size() - 1, 0, -1 do
            local wi = worn:get(i)
            local item = wi and wi:getItem() or nil
            if itemIsTrueLongSleeveGarment(item) then
                worn:remove(item)
                if inv then inv:Remove(item) end
                removedItems = removedItems + 1
            end
        end
        if removedItems > 0 then zombie:onWornItemsChanged() end
    end)
    if not ok then warn("sleeve worn cleanup error", err) end

    if removedVisuals > 0 or removedItems > 0 then
        dropPiece(zombie, "Cloth")
        log("final blow removed true long sleeves: visuals=%d items=%d", removedVisuals, removedItems)
    end
    return removedVisuals + removedItems
end

local function bothArmSidesZD(state)
    return type(state) == "table" and ZD.validCut(state.L) and ZD.validCut(state.R)
end

local function hasLegZD(state)
    return type(state) == "table" and (ZD.validLeg(state.LegL) or ZD.validLeg(state.LegR))
end

local NO_ARMS_GROUND_LOCK_TIMER = 36000.0

local function keepNoArmsZombieGroundLocked(zombie, state)
    if not zombie or not bothArmSidesZD(state) then return false end

    local dead = zombie:isDead()
    local fakeDead = zombie:isFakeDead()
    if dead or fakeDead then return false end

    local md = zombie:getModData()
    local legLoss = hasLegZD(state)
    local onFloor = zombie:isOnFloor()
    local crawling = zombie:isCrawling()

    local locked = md.ZD_noArmsGroundLocked == true
    if not locked and not legLoss and not onFloor and not crawling then
        return false
    end

    if not locked then
        md.ZD_noArmsGroundLocked = true
        log("no-arms ground lock activated: L=%s R=%s LegL=%s LegR=%s",
            tostring(state.L), tostring(state.R), tostring(state.LegL), tostring(state.LegR))
    end

    zombie:setCanWalk(false)
    zombie:setBecomeCrawler(false)

    if crawling then
        zombie:setCrawler(false)
        local ok, err = pcall(function()
            local ground = ZombieOnGroundState.instance()
            if ground then zombie:changeState(ground) end
        end)
        if not ok then warn("ground lock error", err) end
        zombie:setReanimateTimer(NO_ARMS_GROUND_LOCK_TIMER)
        return true
    end

    if not onFloor then
        zombie:setKnockedDown(true)
        return true
    end

    if zombie:getReanimateTimer() < NO_ARMS_GROUND_LOCK_TIMER * 0.75 then
        zombie:setReanimateTimer(NO_ARMS_GROUND_LOCK_TIMER)
    end

    local ok, err = pcall(function()
        local getUp = ZombieGetUpState.instance()
        if getUp and zombie:isCurrentState(getUp) then
            local ground = ZombieOnGroundState.instance()
            if ground then zombie:changeState(ground) end
            zombie:setReanimateTimer(NO_ARMS_GROUND_LOCK_TIMER)
        end
    end)
    if not ok then warn("ground lock error", err) end

    return true
end

local function enforceCrawlerForLegLoss(zombie, state)
    if not zombie or type(state) ~= "table" then return end

    local grappleOnly = zombie:isReanimatedForGrappleOnly()
    if grappleOnly then return end

    if keepNoArmsZombieGroundLocked(zombie, state) then return end

    if not hasLegZD(state) then return end
    zombie:setCanWalk(false)
    if zombie:isDead() then return end

    if zombie:isCrawling() then return end
    local onFloor = zombie:isOnFloor()
    local becoming = zombie:isBecomeCrawler()
    if not becoming then zombie:setBecomeCrawler(true) end
    if not onFloor then zombie:setKnockedDown(true) end
end

local function applyVisualState(zombie, state, force)
    if not zombie or type(state) ~= "table" or ZD.isNPC(zombie) then return end

    if zombie:isUsingWornItems() then
        cleanupAccessoriesForState(zombie, state)
        enforceCrawlerForLegLoss(zombie, state)
        zombie:resetModelNextFrame()
        return
    end
    local md = zombie:getModData()
    local sig = ZD.stateSignature(state)
    writeLiveState(zombie, md.ZD_trueID, state)
    if not force and md.ZD_visualSignature == sig and visualsMatchState(zombie, state) then
        enforceCrawlerForLegLoss(zombie, state)
        return
    end

    local ok, err = pcall(function()
        local visuals = zombie:getItemVisuals()
        if not visuals then return end
        local texIdx = zombieTextureIndex(zombie)

        removeAllOurVisuals(visuals)

        if ZD.validCut(state.L) then addVisual(visuals, ZD.VISUALS[state.L].L, texIdx) end
        if ZD.validCut(state.R) then addVisual(visuals, ZD.VISUALS[state.R].R, texIdx) end

        if ZD.validLeg(state.LegL) then addVisual(visuals, ZD.VISUALS.WholeLeg.L, texIdx) end
        if ZD.validLeg(state.LegR) then addVisual(visuals, ZD.VISUALS.WholeLeg.R, texIdx) end
        if ZD.validHead(state.Head) then addVisual(visuals, ZD.VISUALS.Head.L, texIdx) end

        cleanupAccessoriesForState(zombie, state)
        enforceCrawlerForLegLoss(zombie, state)

        md.ZD_visualSignature = sig
        zombie:resetModelNextFrame()
    end)
    if not ok then warn("visual error", err) end
end

local syncDeathBridgeState

local function saveState(zombie, id, state)
    if isServer() then
        local clean, packet = N.serverSave(zombie, state)
        syncGeneration = syncGeneration + 1
        applyVisualState(zombie, clean, true)
        if syncDeathBridgeState then syncDeathBridgeState(zombie, clean, true) end
        N.serverPublish(packet)
        return
    end
    local d = ZD.getData()
    local clean = ZD.copyState(state)
    local oldID = tostring(id)
    local currentID = ZD.trueZombieID(zombie)
    id = currentID and tostring(currentID) or oldID
    local persistent = ZD.copyLimbState(clean)
    if id ~= oldID then
        log("persistent id changed %s -> %s", oldID, id)
    end
    d.zombies[id] = hasAnyState(persistent) and persistent or nil
    writeLiveState(zombie, id, clean)

    d.revision = (tonumber(d.revision) or 0) + 1
    ModData.add(ZD.GLOBAL_KEY, d)
    syncGeneration = syncGeneration + 1

    applyVisualState(zombie, clean, true)

    if syncDeathBridgeState then syncDeathBridgeState(zombie, clean, true) end
end

local function weaponKind(weapon)
    local kind = Impact.weaponKind(weapon)
    if kind == "Shotgun" and not sandbox("EnableShotguns", true) then return nil end
    return kind
end

local function chanceFor(kind, weapon)
    local c
    if kind == "LongBlade" then
        c = tonumber(sandbox("LongBladeChance", 45)) or 45
        if weapon:getFullType() == "Base.Katana" then c = math.min(100, c + 20) end
    elseif kind == "Axe" then
        c = tonumber(sandbox("AxeChance", 25)) or 25
    elseif kind == "Shotgun" then
        c = tonumber(sandbox("ShotgunChance", 25)) or 25
    else
        return 0
    end
    return math.max(0, math.min(100, c))
end

local function armAvailable(state)
    return state.L ~= "UpperArm" or state.R ~= "UpperArm"
end

local function legAvailable(state)
    return not ZD.validLeg(state.LegL) or not ZD.validLeg(state.LegR)
end

local function chooseArmSide(state)
    local lDone = state.L == "UpperArm"
    local rDone = state.R == "UpperArm"
    if lDone and rDone then return nil end
    if lDone then return "R" end
    if rDone then return "L" end
    return ZombRand(2) == 0 and "L" or "R"
end

local function chooseLegSide(state)
    local lDone = ZD.validLeg(state.LegL)
    local rDone = ZD.validLeg(state.LegR)
    if lDone and rDone then return nil end
    if lDone then return "R" end
    if rDone then return "L" end
    return ZombRand(2) == 0 and "L" or "R"
end

local function chooseArmCut(state, side, damage, critical)
    local current = state[side]
    if current == "UpperArm" then return nil end
    if current == "ForeArm" then return "UpperArm" end

    local upperThreshold = tonumber(sandbox("UpperArmDamage", 1.8)) or 1.8
    if critical or damage >= upperThreshold then return "UpperArm" end
    return "ForeArm"
end

local function chooseLimb(state)
    local arms = armAvailable(state)
    local legs = sandbox("EnableLegs", true) and legAvailable(state)
    if not arms and not legs then return nil end
    if not arms then return "Leg" end
    if not legs then return "Arm" end

    local legChance = tonumber(sandbox("LegTargetChance", 30)) or 30
    legChance = math.max(0, math.min(100, legChance))
    return ZombRand(100) < legChance and "Leg" or "Arm"
end

local function bloodBurst(zombie, limb, side, cut, kind, attacker)
    local impact = sandbox("ImpactBlood", true)
    if impact then
        local amount = limb == "Head" and 28 or (limb == "Leg" and 22 or (cut == "UpperArm" and 18 or 12))
        local sq = getCell():getGridSquare(zombie:getX(), zombie:getY(), zombie:getZ())
        if sq then addBloodSplat(sq, amount) end
    end
    local ok, err = pcall(Debris.blood, zombie, limb, kind, attacker)
    if not ok then warn("blood effect failed", err) end
    if impact then
        if limb == "Head" then
            zombie:addBlood(BloodBodyPartType.Neck, true, true, true)
            zombie:addBlood(BloodBodyPartType.Torso_Upper, true, true, true)
        elseif limb == "Leg" then
            if side == "L" then
                zombie:addBlood(BloodBodyPartType.UpperLeg_L, true, false, false)
                zombie:addBlood(BloodBodyPartType.LowerLeg_L, true, false, false)
            else
                zombie:addBlood(BloodBodyPartType.UpperLeg_R, true, false, false)
                zombie:addBlood(BloodBodyPartType.LowerLeg_R, true, false, false)
            end
        elseif side == "L" then
            zombie:addBlood(BloodBodyPartType.UpperArm_L, true, false, false)
            zombie:addBlood(BloodBodyPartType.ForeArm_L, true, false, false)
        else
            zombie:addBlood(BloodBodyPartType.UpperArm_R, true, false, false)
            zombie:addBlood(BloodBodyPartType.ForeArm_R, true, false, false)
        end
    end
end

local bridgeAttacker
local bridgeUpdate

local function enableBridgeCombat()
    if isClient() or isServer() or not Bridge or not BridgeFight then return end
    if not BridgeFight.update or BridgeFight.update == bridgeUpdate then return end
    local update = BridgeFight.update
    bridgeUpdate = function(body)
        if isClient() or isServer() or not body or body ~= Bridge.body
            or BridgeFight.state ~= "swing" or BridgeFight.hit then return update(body) end
        local previous = bridgeAttacker
        bridgeAttacker = body
        -- Always clear the hit context, including when Bridge's update fails.
        local ok, result = pcall(update, body)
        bridgeAttacker = previous
        if not ok then error(result, 0) end
        return result
    end
    BridgeFight.update = bridgeUpdate
end

local function handleHit(attacker, target, weapon, damage)
    if not sandbox("Enabled", true) then return end
    if not attacker or not target or not weapon then return end
    if not instanceof(target, "IsoZombie") then return end
    local bridgeHit = false
    if not instanceof(attacker, "IsoPlayer") then
        if isClient() or isServer() or not bridgeAttacker then return end
        if attacker ~= getCell():getFakeZombieForHit()
            or weapon ~= bridgeAttacker:getPrimaryHandItem() then return end
        bridgeHit = true
        attacker = bridgeAttacker
    end
    if isClient() and not isServer() then return end
    if ZD.isNPC(target) then return end
    if N.enabled() and N.isGrapple(target) then return end

    local kind = weaponKind(weapon)
    if not kind then return end

    local dmg = tonumber(damage) or 0
    local critical
    if bridgeHit then critical = BridgeFight.swingCrit == true
    else critical = attacker:isCriticalHit() end

    local threshold = tonumber(sandbox("DamageThreshold", 0.75)) or 0.75
    if dmg < threshold and not critical then return end

    local md = target:getModData()
    local frozen = SandboxVars.FrozenZombies
    if frozen and frozen.Enabled == true
        and (md.bSZZFrozen == true or md.bSZZGroundFrozen == true or md.bFrozenBySZZ == true) then return end
    local computedID = N.enabled() and N.identity(target) or ZD.trueZombieID(target)
    local id = md.ZD_trueID
    if N.enabled() then id = computedID end
    if tostring(id) == "0" then md.ZD_trueID = nil; id = nil end
    id = id or computedID
    if not id then return end
    id = tostring(id)
    if not md.ZD_trueID then md.ZD_trueID = id end

    local state = stateForZombie(target, id)
    if not N.enabled() and computedID and tostring(computedID) ~= id then
        state = mergeStates(state, ZD.copyLimbState(ZD.getData().zombies[tostring(computedID)]))
    end

    local shove = not bridgeHit and attacker:isDoShove()
    if kind == "Shotgun" and shove then return end
    if critical and not shove and not ZD.validHead(state.Head)
        and sandbox("EnableDecapitation", true) then
        -- Bridge has no survivor Strength skill; use the base sandbox chance.
        local strengthActor = attacker
        if bridgeHit then strengthActor = nil end
        local decapChance = Impact.decapitationChance(strengthActor, kind,
            sandbox("DecapitationChance", 5), sandbox("DecapitationStrength", true))
        local grappleOnly = target:isReanimatedForGrappleOnly()
        if not grappleOnly and decapChance > 0 and ZombRand(10000) < decapChance * 100 then
            if kind == "LongBlade" then
                local name = string.lower(weapon:getType())
                if containsPlain(name, "sword") or containsPlain(name, "katana") then
                    dropPiece(target, "Head", nil, "Decapitated", state.Head, attacker, "Sword")
                end
            end
            state.Head = "Decapitated"
            Impact.cleanup(target, Impact.isHeadAccessory)
            saveState(target, id, state)
            bloodBurst(target, "Head", nil, "Decapitated", kind, attacker)
            target:setHealth(0)
            log("decapitated zombie %s (weapon=%s chance=%.2f crit=true)",
                id, tostring(weapon:getFullType()), decapChance)
            return
        end
    end
    if ZD.validHead(state.Head) then return end
    local chance = chanceFor(kind, weapon)

    if kind ~= "Shotgun" and critical and sandbox("CriticalAlwaysCuts", true) then chance = 100 end
    if chance <= 0 or ZombRand(100) >= chance then return end
    local limb = chooseLimb(state)
    if not limb then return end

    if limb == "Arm" then
        local side = chooseArmSide(state)
        if not side then return end
        local cut = chooseArmCut(state, side, dmg, critical)
        if not cut then return end

        dropPiece(target, "Arm", side, cut, state[side], attacker, kind)
        cleanupAccessories(target, "Arm", side, cut)
        state[side] = cut
        saveState(target, id, state)
        bloodBurst(target, "Arm", side, cut)
        log("cut %s %s on zombie %s (weapon=%s damage=%.3f crit=%s)", side, cut, id, tostring(weapon:getFullType()), dmg, tostring(critical))
    else
        local side = chooseLegSide(state)
        if not side then return end
        dropPiece(target, "Leg", side, "WholeLeg", state["Leg" .. side], attacker, kind)
        cleanupAccessories(target, "Leg", side, "WholeLeg")
        if side == "L" then state.LegL = "WholeLeg" else state.LegR = "WholeLeg" end
        saveState(target, id, state)
        bloodBurst(target, "Leg", side, "WholeLeg")
        log("cut %s WholeLeg on zombie %s (weapon=%s damage=%.3f crit=%s)", side, id, tostring(weapon:getFullType()), dmg, tostring(critical))
    end
end
Events.OnWeaponHitCharacter.Add(handleHit)

local function onZombieUpdate(zombie)
    if not zombie then return end
    local md = zombie:getModData()
    if ZD.isNPC(zombie, md) then return end
    if N.enabled() then
        if isServer() then
            N.serverObserve(zombie)
            if not N.validUID(md.ZD_MPUID) and not N.hasLiveState(zombie) then return end
        elseif N.clientObserve then N.clientObserve(zombie) end
    end
    local id = md.ZD_trueID
    if N.enabled() then id = N.identity(zombie) end
    if tostring(id) == "0" then md.ZD_trueID = nil; id = nil end
    if not id then
        if not N.enabled() then id = ZD.trueZombieID(zombie) end
        if id then
            id = tostring(id)
            md.ZD_trueID = id
        end
    end
    if not id then return end

    local saved
    if isServer() then saved = N.serverRecord(md.ZD_MPUID)
    elseif not isClient() then saved=ZD.getData().zombies[tostring(id)] end
    local savedLimbs = type(saved) == "table" and (ZD.validCut(saved.L) or ZD.validCut(saved.R)
        or ZD.validLeg(saved.LegL) or ZD.validLeg(saved.LegR) or (N.enabled() and ZD.validHead(saved.Head)))
    local liveCuts = ZD.validCut(md.ZD_L) or ZD.validCut(md.ZD_R)
        or ZD.validLeg(md.ZD_LegL) or ZD.validLeg(md.ZD_LegR) or ZD.validHead(md.ZD_Head)
    if not savedLimbs and not liveCuts then return end

    local state = stateForZombie(zombie, id)
    if not hasAnyState(state) then return end
    if not N.enabled() and not savedLimbs and not zombie:isDead() and not zombie:isReanimatedForGrappleOnly() then
        local persistent = ZD.copyLimbState(state)
        if hasAnyState(persistent) then
            local currentID = ZD.trueZombieID(zombie)
            id = currentID and tostring(currentID) or tostring(id)
            local d = ZD.getData()
            state = mergeStates(state, ZD.copyLimbState(d.zombies[id]))
            d.zombies[id] = ZD.copyLimbState(state)
            d.revision = d.revision + 1
            ModData.add(ZD.GLOBAL_KEY, d)
        end
    end
    writeLiveState(zombie, id, state)
    Debris.observe(zombie)

    if syncDeathBridgeState then syncDeathBridgeState(zombie, state, false) end

    if zombie:isUsingWornItems() then
        enforceCrawlerForLegLoss(zombie, state)
        return
    end

    if md.ZD_syncGeneration == syncGeneration then
        if not visualsMatchState(zombie, state) then
            applyVisualState(zombie, state, true)
        else
            enforceCrawlerForLegLoss(zombie, state)
        end
        return
    end

    md.ZD_syncGeneration = syncGeneration
    applyVisualState(zombie, state, false)
end
Events.OnZombieUpdate.Add(onZombieUpdate)

local DEATH_VISUALS = {
    Head = { L = "ZombieDismemberment.ZD_Corpse_Head" },
    ForeArm = {
        L = "ZombieDismemberment.ZD_Corpse_ForeArm_L",
        R = "ZombieDismemberment.ZD_Corpse_ForeArm_R",
    },
    UpperArm = {
        L = "ZombieDismemberment.ZD_Corpse_UpperArm_L",
        R = "ZombieDismemberment.ZD_Corpse_UpperArm_R",
    },
    WholeLeg = {
        L = "ZombieDismemberment.ZD_Corpse_Leg_L",
        R = "ZombieDismemberment.ZD_Corpse_Leg_R",
    },
}

local deathVisuals = {}
for _, cuts in pairs(DEATH_VISUALS) do
    deathVisuals[cuts.L] = true
    if cuts.R then deathVisuals[cuts.R] = true end
end

local function isDeathVisualType(itemType)
    return deathVisuals[itemType] == true
end

local function removeDeathBridgeItems(character)
    if not character then return end
    local worn = character:getWornItems()
    local inv = character:getInventory()
    if worn then
        for i = worn:size() - 1, 0, -1 do
            local wi = worn:get(i)
            local item = wi and wi:getItem() or nil
            local ft = item and item:getFullType() or nil
            if isDeathVisualType(ft) and item then worn:remove(item) end
        end
    end
    if inv then
        local items = inv:getItems()
        for i = items:size() - 1, 0, -1 do
            local item = items:get(i)
            local ft = item and item:getFullType() or nil
            if isDeathVisualType(ft) then inv:Remove(item) end
        end
    end
end

local function addDeathBridgeItem(character, itemType, texIdx)
    if not character or not itemType then return false end
    local inv = character:getInventory()
    local worn = character:getWornItems()
    if not inv or not worn then return false end

    local item = inv:AddItem(itemType)
    if not item then
        warn("death bridge creation failed", itemType)
        return false
    end

    if texIdx ~= nil then
        local ok, err = pcall(function()
            local vis = item:getVisual()
            if vis then
                vis:setTextureChoice(texIdx)
                item:synchWithVisual()
            end
        end)
        if not ok then warn("death bridge texture error", err) end
    end

    local loc = item:getBodyLocation()
    if not loc then
        warn("death bridge body location missing", itemType)
        inv:Remove(item)
        return false
    end

    N.stampCarrier(character, item)
    worn:setItem(loc, item)
    return true
end

local function deathBridgeMatchesState(zombie, state)
    if not zombie then return false end
    local worn = zombie:getWornItems()
    if not worn then return false end

    local expected = {}
    if ZD.validCut(state.L) then expected[DEATH_VISUALS[state.L].L] = true end
    if ZD.validCut(state.R) then expected[DEATH_VISUALS[state.R].R] = true end
    if ZD.validLeg(state.LegL) then expected[DEATH_VISUALS.WholeLeg.L] = true end
    if ZD.validLeg(state.LegR) then expected[DEATH_VISUALS.WholeLeg.R] = true end
    if ZD.validHead(state.Head) then expected[DEATH_VISUALS.Head.L] = true end

    local seen = {}
    for i = 0, worn:size() - 1 do
        local wi = worn:get(i)
        local item = wi and wi:getItem() or nil
        local ft = item and item:getFullType() or nil
        if isDeathVisualType(ft) then seen[ft] = true end
    end
    for ft in pairs(expected) do if not seen[ft] then return false end end
    for ft in pairs(seen) do if not expected[ft] then return false end end
    return true
end

syncDeathBridgeState = function(zombie, state, force)
    if not zombie or not hasAnyState(state) or ZD.isNPC(zombie) then return end
    local md = zombie:getModData()
    local sig = ZD.stateSignature(state)
    if not force and md.ZD_bridgeSignature == sig and deathBridgeMatchesState(zombie, state) then
        return
    end

    removeDeathBridgeItems(zombie)

    local texIdx = zombieTextureIndex(zombie)
    local count = 0
    if ZD.validCut(state.L) and addDeathBridgeItem(zombie, DEATH_VISUALS[state.L].L, texIdx) then count = count + 1 end
    if ZD.validCut(state.R) and addDeathBridgeItem(zombie, DEATH_VISUALS[state.R].R, texIdx) then count = count + 1 end
    if ZD.validLeg(state.LegL) and addDeathBridgeItem(zombie, DEATH_VISUALS.WholeLeg.L, texIdx) then count = count + 1 end
    if ZD.validLeg(state.LegR) and addDeathBridgeItem(zombie, DEATH_VISUALS.WholeLeg.R, texIdx) then count = count + 1 end
    if ZD.validHead(state.Head) and addDeathBridgeItem(zombie, DEATH_VISUALS.Head.L, texIdx) then count = count + 1 end

    md.ZD_bridgeSignature = sig

    zombie:onWornItemsChanged()
    if zombie:isUsingWornItems() then zombie:resetModelNextFrame() end
    log("death bridge pre-staged: L=%s R=%s LegL=%s LegR=%s visuals=%d",
        tostring(state.L), tostring(state.R), tostring(state.LegL), tostring(state.LegR), count)
end

local function onZombieDead(zombie)
    if not zombie or ZD.isNPC(zombie) then return end
    if N.enabled() then N.recoverCarriers(zombie) end
    local md = zombie:getModData()
    local id = md.ZD_trueID
    if tostring(id) == "0" then md.ZD_trueID = nil; id = nil end
    if N.enabled() then id = N.identity(zombie)
    else id = id or ZD.trueZombieID(zombie) end
    if not id then return end
    id = tostring(id)
    local state = stateForZombie(zombie, id)
    if not hasAnyState(state) then return end
    writeLiveState(zombie, id, state)

    destroyTrueLongSleevesOnFinalBlow(zombie, state)

    applyVisualState(zombie, state, true)

    if syncDeathBridgeState then syncDeathBridgeState(zombie, state, false) end
    if isServer() then
        N.serverDead(zombie)

    end
end
Events.OnZombieDead.Add(onZombieDead)

local CORPSE_VISUALS = DEATH_VISUALS

local function corpseState(corpse)
    if not corpse then return {} end
    local md = corpse:getModData()
    return ZD.copyState({
        L = md.ZD_L, R = md.ZD_R,
        LegL = md.ZD_LegL, LegR = md.ZD_LegR,
        Head = md.ZD_Head,
    })
end

local function removeCorpseZDItems(corpse)
    if not corpse then return end
    local worn = corpse:getWornItems()
    local inv = corpse:getContainer()
    if worn then
        for i = worn:size() - 1, 0, -1 do
            local wi = worn:get(i)
            local item = wi and wi:getItem() or nil
            local ft = item and item:getFullType() or nil
            if isDeathVisualType(ft) then worn:remove(item) end
        end
    end
    if inv then
        local items = inv:getItems()
        for i = items:size() - 1, 0, -1 do
            local item = items:get(i)
            local ft = item and item:getFullType() or nil
            if isDeathVisualType(ft) then inv:Remove(item) end
        end
    end
end

local function addCorpseZDItem(corpse, itemType, texIdx)
    if not corpse or not itemType then return false end
    local inv = corpse:getContainer()
    local worn = corpse:getWornItems()
    if not inv or not worn then return false end

    local item = inv:AddItem(itemType)
    if not item then
        warn("corpse item creation failed", itemType)
        return false
    end

    if texIdx ~= nil then
        local ok, err = pcall(function()
            local vis = item:getVisual()
            if vis then
                vis:setTextureChoice(texIdx)
                item:synchWithVisual()
            end
        end)
        if not ok then warn("corpse item texture error", err) end
    end

    local loc = item:getBodyLocation()
    if not loc then
        warn("corpse item body location missing", itemType)
        inv:Remove(item)
        return false
    end

    N.stampCarrier(corpse, item)
    worn:setItem(loc, item)
    return true
end

local function applyCorpseState(corpse)
    if not corpse or ZD.isNPC(corpse) then return end
    if N.enabled() then N.recoverCarriers(corpse) end
    local state = corpseState(corpse)
    if not hasAnyState(state) then return end

    local texIdx = zombieTextureIndex(corpse)
    removeCorpseZDItems(corpse)
    if ZD.validLeg(state.LegL) or ZD.validLeg(state.LegR) then Impact.cleanup(corpse, Impact.isFootwear) end
    if ZD.validHead(state.Head) then Impact.cleanup(corpse, Impact.isHeadAccessory) end

    local count = 0
    if ZD.validCut(state.L) and addCorpseZDItem(corpse, CORPSE_VISUALS[state.L].L, texIdx) then count = count + 1 end
    if ZD.validCut(state.R) and addCorpseZDItem(corpse, CORPSE_VISUALS[state.R].R, texIdx) then count = count + 1 end
    if ZD.validLeg(state.LegL) and addCorpseZDItem(corpse, CORPSE_VISUALS.WholeLeg.L, texIdx) then count = count + 1 end
    if ZD.validLeg(state.LegR) and addCorpseZDItem(corpse, CORPSE_VISUALS.WholeLeg.R, texIdx) then count = count + 1 end
    if ZD.validHead(state.Head) and addCorpseZDItem(corpse, CORPSE_VISUALS.Head.L, texIdx) then count = count + 1 end

    corpse:invalidateRenderChunkLevel(2)
    corpse:setInvalidateNextRender(true)
    log("corpse state rebuilt: L=%s R=%s LegL=%s LegR=%s visuals=%d",
        tostring(state.L), tostring(state.R), tostring(state.LegL), tostring(state.LegR), count)
end

local function onDeadBodySpawn(corpse)
    local ok, err = pcall(function() applyCorpseState(corpse) end)
    if not ok then warn("corpse rebuild error", err) end
end
Events.OnDeadBodySpawn.Add(onDeadBodySpawn)

local function onReceiveGlobalModData(key, incoming)
    if N.enabled() then return end
    if key ~= ZD.GLOBAL_KEY or type(incoming) ~= "table" then return end
    local localData = ModData.getOrCreate(ZD.GLOBAL_KEY)
    for k in pairs(localData) do localData[k] = nil end
    for k, v in pairs(incoming) do localData[k] = v end
    localData.zombies = localData.zombies or {}
    syncGeneration = syncGeneration + 1
end
Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)

local function saveLivingStates()
    if N.enabled() then return end
    local cell = getCell()
    if not cell then return end
    local zombies = cell:getZombieList()
    local d = ZD.getData()
    local changed = false
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if not zombie:isDead() and not zombie:isReanimatedForGrappleOnly() and not ZD.isNPC(zombie) then
            local state = ZD.copyLimbState(readLiveState(zombie))
            if hasAnyState(state) then
                local id = ZD.trueZombieID(zombie) or zombie:getModData().ZD_trueID
                if id and tostring(id) ~= "0" then
                    id = tostring(id)
                    state = mergeStates(ZD.copyLimbState(d.zombies[id]), state)
                    if ZD.stateSignature(d.zombies[id]) ~= ZD.stateSignature(state) then
                        d.zombies[id] = state
                        changed = true
                    end
                    zombie:getModData().ZD_trueID = id
                end
            end
        end
    end
    if changed then
        d.revision = d.revision + 1
        ModData.add(ZD.GLOBAL_KEY, d)
    end
end
Events.OnSave.Add(saveLivingStates)

local function onGameStart()
    enableBridgeCombat()
    if not N.enabled() then ZD.getData() end
    syncGeneration = syncGeneration + 1
    log("v0.4.0.19 loaded (B42.21; server-authoritative experimental MP)")
end
Events.OnGameStart.Add(onGameStart)

local function clearNetworkVisuals(zombie)
    local visuals = zombie:getItemVisuals()
    if visuals then removeAllOurVisuals(visuals) end
    removeDeathBridgeItems(zombie)
    local md = zombie:getModData()
    md.ZD_visualSignature = nil
    md.ZD_bridgeSignature = nil
    zombie:resetModelNextFrame()
end
ZD_Runtime = {
    apply = applyVisualState, bridge = syncDeathBridgeState, corpse = applyCorpseState,
    update = onZombieUpdate, blood = bloodBurst, clear = clearNetworkVisuals,
}
