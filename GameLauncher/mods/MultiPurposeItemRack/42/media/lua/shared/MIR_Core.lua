MultiPurposeItemRack = MultiPurposeItemRack or {}

local MIR = MultiPurposeItemRack

MIR.module = "MultiPurposeItemRack"
MIR.rackType = "MultiPurposeItemRack.RackSection"
-- The installed rack item is a logical carrier. Its board is rendered by the
-- client beside the wooden pegs, avoiding Build 42's stale world-item atlas.
MIR.rackModel = "MIR_PegboardRack_V8_Render"
MIR.hiddenRackModel = "MIR_RackCarrierHidden_V3"
-- A dedicated helper type prevents Render3DItem from inheriting Base.Plank's
-- already-cached model and atlas entry. It exists only as a transient client
-- render object and is never placed in an inventory or in the world.
MIR.boardRenderItemType = "MultiPurposeItemRack.BoardRenderHelperV8"
MIR.rackModels = {
    full = MIR.rackModel,
    negative = "MIR_PegboardRack_V10_TrimNegative_Render",
    positive = "MIR_PegboardRack_V10_TrimPositive_Render",
    both = "MIR_PegboardRack_V10_TrimBoth_Render",
}
MIR.boardRenderItemTypes = {
    full = MIR.boardRenderItemType,
    negative = "MultiPurposeItemRack.BoardRenderHelperV10TrimNegative",
    positive = "MultiPurposeItemRack.BoardRenderHelperV10TrimPositive",
    both = "MultiPurposeItemRack.BoardRenderHelperV10TrimBoth",
}
MIR.pegRenderItemType = "Base.Plank"
MIR.pegModel = "MIR_RoundPegV2_World"
-- This value differs from both v0.1.20 scales, forcing one clean invalidation
-- for already-installed test racks. The hidden model applies its own tiny scale
-- as well, leaving the carrier invisible after that one migration redraw.
MIR.carrierWorldScale = 0.000137
MIR.schemaVersion = 1
MIR.captureRange = 2

MIR.rules = {
    "exact", "handgun", "shotgun", "longgun", "firearm", "melee",
    "weapon", "tool", "bag", "clothing", "medical", "food", "drink",
    "literature", "ammo", "any",
}

MIR.ruleLabels = {
    exact = "IGUI_MIR_RuleExact",
    handgun = "IGUI_MIR_RuleHandgun",
    shotgun = "IGUI_MIR_RuleShotgun",
    longgun = "IGUI_MIR_RuleLongGun",
    firearm = "IGUI_MIR_RuleFirearm",
    melee = "IGUI_MIR_RuleMelee",
    weapon = "IGUI_MIR_RuleWeapon",
    tool = "IGUI_MIR_RuleTool",
    bag = "IGUI_MIR_RuleBag",
    clothing = "IGUI_MIR_RuleClothing",
    medical = "IGUI_MIR_RuleMedical",
    food = "IGUI_MIR_RuleFood",
    drink = "IGUI_MIR_RuleDrink",
    literature = "IGUI_MIR_RuleLiterature",
    ammo = "IGUI_MIR_RuleAmmo",
    any = "IGUI_MIR_RuleAny",
}

local ruleRank = {
    exact = 1, handgun = 2, shotgun = 2, longgun = 2, melee = 2,
    tool = 2, bag = 2, clothing = 2, medical = 2, food = 2,
    drink = 2, literature = 2, ammo = 2, firearm = 3, weapon = 4, any = 5,
}

local function call(object, method, fallback)
    if not object or not object[method] then return fallback end
    local ok, value = pcall(function() return object[method](object) end)
    if ok then return value end
    return fallback
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function contains(value, needle)
    return string.find(lower(value), needle, 1, true) ~= nil
end

function MIR.isRackItem(item)
    return item and call(item, "getFullType", "") == MIR.rackType
end

function MIR.isRackWorldObject(object)
    return MIR.isRackItem(MIR.itemFromWorldObject(object))
end

function MIR.itemFromWorldObject(object)
    if not object or not object.getItem then return nil end
    local ok, item = pcall(function() return object:getItem() end)
    return ok and item or nil
end

function MIR.hideRackCarrier(item)
    if not MIR.isRackItem(item) then return false end
    local modelApplied = false
    if item.setWorldStaticModel then
        local ok = pcall(function() item:setWorldStaticModel(MIR.hiddenRackModel) end)
        modelApplied = modelApplied or ok
    end
    if item.setStaticModel then
        local ok = pcall(function() item:setStaticModel(MIR.hiddenRackModel) end)
        modelApplied = modelApplied or ok
    end
    if item.setWorldScale then
        pcall(function() item:setWorldScale(MIR.carrierWorldScale) end)
    end
    return modelApplied
end

function MIR.itemId(item)
    return tonumber(call(item, "getID", -1)) or -1
end

function MIR.worldItemId(object)
    return MIR.itemId(MIR.itemFromWorldObject(object))
end

function MIR.isExtendedPlacedWorldItem(object)
    local item = MIR.itemFromWorldObject(object)
    if not item then return false end

    -- Build 42 can lose the world flag when its multiplayer placement packet is
    -- rejected. The versioned client stamp is written only by the 3D editor and
    -- cleared by the normal drop action, so legacy metadata cannot qualify.
    if call(object, "isExtendedPlacement", false) == true then return true end
    return tonumber(item:getModData().MIRPlacementMarker) == 2
end

function MIR.worldItemKey(object, item)
    item = item or MIR.itemFromWorldObject(object)
    local id = MIR.itemId(item)
    if id > 0 then return "id:" .. tostring(id) end
    return object
end

function MIR.eachWorldItem(square, visitor)
    if not square or not visitor then return end
    local seen = {}
    local function scan(objects)
        if not objects then return end
        for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            local item = MIR.itemFromWorldObject(object)
            if item then
                local key = MIR.worldItemKey(object, item)
                if not seen[key] then
                    seen[key] = true
                    visitor(object, item)
                end
            end
        end
    end
    scan(square:getWorldObjects())
    scan(square:getObjects())
end

function MIR.ensureRackData(item)
    if not MIR.isRackItem(item) then return nil end
    local root = item:getModData()
    if type(root.MIR) ~= "table" then root.MIR = {} end
    local data = root.MIR
    data.version = MIR.schemaVersion
    if type(data.slots) ~= "table" then data.slots = {} end
    return data
end

function MIR.resetRackData(item)
    if not MIR.isRackItem(item) then return false end
    local root = item:getModData()
    local data = MIR.ensureRackData(item)
    local changed = #data.slots > 0 or data.wallSide ~= nil
        or data.boardHidden ~= nil or data.pegsHidden ~= nil
        or root.MIRSlotId ~= nil or root.MIRExtendedPlaced ~= nil
        or root.MIRPlacementMarker ~= nil
    data.slots = {}
    data.wallSide = nil
    data.boardHidden = nil
    data.pegsHidden = nil
    root.MIRSlotId = nil
    root.MIRExtendedPlaced = nil
    root.MIRPlacementMarker = nil
    return changed
end

function MIR.validRule(rule)
    for _, value in ipairs(MIR.rules) do
        if value == rule then return true end
    end
    return false
end

function MIR.ruleRank(rule)
    return ruleRank[rule] or 99
end

function MIR.ruleName(rule)
    local key = MIR.ruleLabels[rule]
    return key and getText(key) or tostring(rule)
end

function MIR.itemName(item)
    return tostring(call(item, "getDisplayName", call(item, "getType", "Item")))
end

local itemTagCache = {}

local function resolveItemTag(tag)
    if not ItemTag or not ResourceLocation or not ItemTag.get or not ResourceLocation.of then
        return tag
    end
    if not itemTagCache[tag] then
        itemTagCache[tag] = ItemTag.get(ResourceLocation.of(tag))
    end
    return itemTagCache[tag]
end

local function hasTag(item, tag)
    if not item or not item.hasTag then return false end
    local resolved = resolveItemTag(tag)
    return resolved ~= nil and item:hasTag(resolved) == true
end

local function classification(item)
    local fullType = lower(call(item, "getFullType", ""))
    local displayCategory = lower(call(item, "getDisplayCategory", ""))
    local subCategory = lower(call(item, "getSubCategory", ""))
    local reloadType = lower(call(item, "getWeaponReloadType", ""))
    local attachment = lower(call(item, "getAttachmentType", ""))
    local itemType = lower(call(item, "getType", ""))
    local ranged = call(item, "isRanged", false) == true
        or call(item, "getRanged", false) == true
        or hasTag(item, "base:firearm")
    local handWeapon = instanceof and instanceof(item, "HandWeapon")
    local clothing = (instanceof and instanceof(item, "Clothing"))
        or displayCategory == "clothing"
    local food = (instanceof and instanceof(item, "Food"))
        or displayCategory == "food"
    local literature = displayCategory == "literature"
        or contains(fullType, "book") or contains(fullType, "magazine")
    local ammo = displayCategory == "ammo" or hasTag(item, "base:ammo")
        or contains(itemType, "ammo") or contains(itemType, "bullets")
    local medical = displayCategory == "firstaid" or displayCategory == "medical"
        or hasTag(item, "base:medical")
    local drink = call(item, "isWaterSource", false) == true
        or displayCategory == "water" or displayCategory == "drink"
    local bag = call(item, "getCapacity", 0) > 0
        and (displayCategory == "bag" or contains(attachment, "back"))
    local handgun = ranged and (contains(reloadType, "handgun")
        or contains(reloadType, "revolver") or contains(attachment, "holster"))
    local shotgun = ranged and contains(reloadType, "shotgun")
    local longgun = ranged and not handgun and not shotgun
    local melee = handWeapon and not ranged
    local tool = displayCategory == "tool" or hasTag(item, "base:tool")
        or hasTag(item, "base:hammer") or hasTag(item, "base:saw")

    return {
        handgun = handgun, shotgun = shotgun, longgun = longgun,
        firearm = ranged, melee = melee, weapon = handWeapon or ranged,
        tool = tool, bag = bag, clothing = clothing, medical = medical,
        food = food, drink = drink, literature = literature, ammo = ammo,
    }
end

function MIR.isHandgun(item)
    return classification(item).handgun == true
end

function MIR.slotPegCount(slot)
    local saved = tonumber(slot and slot.pegCount)
    if saved == 1 or saved == 2 then return saved end
    if not slot then return 2 end
    local name = lower(slot.preferredFullType or slot.preferredName)
    if slot.rule == "handgun" or contains(name, "pistol")
        or contains(name, "revolver") or contains(name, "m1911")
        or contains(name, "deagle") then
        return 1
    end
    return 2
end

function MIR.matches(item, slot)
    if not item or not slot then return false end
    local fullType = call(item, "getFullType", "")
    if fullType == slot.preferredFullType then return true end
    if slot.rule == "exact" then return false end
    if slot.rule == "any" then return not MIR.isRackItem(item) end
    return classification(item)[slot.rule] == true
end

function MIR.availableRules(item)
    local result = { "exact" }
    local classes = classification(item)
    for _, rule in ipairs(MIR.rules) do
        if rule ~= "exact" and rule ~= "any" and classes[rule] then
            result[#result + 1] = rule
        end
    end
    result[#result + 1] = "any"
    return result
end

function MIR.squareKey(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

function MIR.distanceSquared(a, b)
    if not a or not b then return math.huge end
    local dx = a:getX() - b:getX()
    local dy = a:getY() - b:getY()
    local dz = (a:getZ() - b:getZ()) * 3
    return dx * dx + dy * dy + dz * dz
end

function MIR.findWorldItem(x, y, z, itemId)
    local square = getCell():getGridSquare(tonumber(x), tonumber(y), tonumber(z))
    if not square then return nil end
    local found = nil
    MIR.eachWorldItem(square, function(object)
        if not found and MIR.worldItemId(object) == tonumber(itemId) then found = object end
    end)
    return found
end

local sideOrder = { "west", "north", "east", "south" }

local function hasWall(square, north)
    if not square then return false end
    local ok, wall = pcall(function() return square:getWall(north) end)
    if ok and wall then return true end
    local flag = north and IsoFlagType.collideN or IsoFlagType.collideW
    ok, wall = pcall(function() return square:has(flag) end)
    return ok and wall == true
end

function MIR.wallSide(square, directionIndex)
    if not square then return nil end
    local east = getCell():getGridSquare(square:getX() + 1, square:getY(), square:getZ())
    local south = getCell():getGridSquare(square:getX(), square:getY() + 1, square:getZ())
    local available = {
        west = hasWall(square, false),
        north = hasWall(square, true),
        east = hasWall(east, false),
        south = hasWall(south, true),
    }
    local preferred = sideOrder[tonumber(directionIndex) or 2]
    if preferred and available[preferred] then return preferred end
    for _, side in ipairs(sideOrder) do
        if available[side] then return side end
    end
    return nil
end

function MIR.wallPose(square, side)
    if not square or not side then return nil end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    -- A dropped world model starts flat. Opposing wall planes need opposing
    -- tilt axes; applying one X tilt and then turning it with Z produces the
    -- edge-on slivers seen on east/west walls.
    local poses = {
        north = { x = x + 0.50, y = y + 0.06, z = z + 0.43, rotX = 270, rotY = 0, rotZ = 0 },
        south = { x = x + 0.50, y = y + 0.94, z = z + 0.43, rotX = 90, rotY = 0, rotZ = 0 },
        west = { x = x + 0.06, y = y + 0.50, z = z + 0.43, rotX = 0, rotY = 90, rotZ = 0 },
        east = { x = x + 0.94, y = y + 0.50, z = z + 0.43, rotX = 0, rotY = 270, rotZ = 0 },
    }
    return poses[side]
end

-- Treat an installed rack as the one-tile wall segment it occupies. Two rack
-- sections are linked only when those segments touch on the same floor. This
-- joins straight runs and racks wrapping around a corner without linking
-- back-to-back racks, nearby racks across a room, or racks on another storey.
function MIR.wallSegment(x, y, z, side)
    x, y, z, side = tonumber(x), tonumber(y), tonumber(z), tostring(side or "")
    if not x or not y or not z then return nil end
    if side == "north" then
        return { ax = x, ay = y, bx = x + 1, by = y, z = z, side = side, axis = "h" }
    elseif side == "south" then
        return { ax = x, ay = y + 1, bx = x + 1, by = y + 1, z = z, side = side, axis = "h" }
    elseif side == "west" then
        return { ax = x, ay = y, bx = x, by = y + 1, z = z, side = side, axis = "v" }
    elseif side == "east" then
        return { ax = x + 1, ay = y, bx = x + 1, by = y + 1, z = z, side = side, axis = "v" }
    end
    return nil
end

local function samePoint(ax, ay, bx, by)
    return ax == bx and ay == by
end

function MIR.wallSegmentsAdjacent(a, b)
    if not a or not b or a.z ~= b.z then return false end

    if not MIR.wallSegmentsSharedEndpoint(a, b) then return false end

    -- Parallel racks must face the same side of the wall. Perpendicular racks
    -- may share an endpoint, which is the intended around-the-corner case.
    if a.axis == b.axis then return a.side == b.side end
    return true
end

function MIR.wallSegmentsSharedEndpoint(first, second)
    if not first or not second or first.z ~= second.z then return nil end
    if samePoint(first.ax, first.ay, second.ax, second.ay)
        or samePoint(first.ax, first.ay, second.bx, second.by) then
        return "a"
    end
    if samePoint(first.bx, first.by, second.ax, second.ay)
        or samePoint(first.bx, first.by, second.bx, second.by) then
        return "b"
    end
    return nil
end

function MIR.trimVariantForEnds(side, trimA, trimB)
    local negativeIsA = side == "north" or side == "west"
    local trimNegative, trimPositive
    if negativeIsA then
        trimNegative, trimPositive = trimA, trimB
    else
        trimNegative, trimPositive = trimB, trimA
    end
    if trimNegative and trimPositive then return "both" end
    if trimNegative then return "negative" end
    if trimPositive then return "positive" end
    return "full"
end

function MIR.hasWallSide(square, side)
    if not square then return false end
    if side == "north" then return hasWall(square, true) end
    if side == "west" then return hasWall(square, false) end
    if side == "south" then
        local neighbour = getCell():getGridSquare(
            square:getX(), square:getY() + 1, square:getZ())
        return hasWall(neighbour, true)
    end
    if side == "east" then
        local neighbour = getCell():getGridSquare(
            square:getX() + 1, square:getY(), square:getZ())
        return hasWall(neighbour, false)
    end
    return false
end

function MIR.rackCornerTrimVariant(rackWorld)
    local square = rackWorld and rackWorld:getSquare() or nil
    local rackSegment = MIR.rackSegment(rackWorld)
    if not square or not rackSegment then return "full" end

    local trimA, trimB = false, false
    for x = square:getX() - 1, square:getX() + 1 do
        for y = square:getY() - 1, square:getY() + 1 do
            local candidateSquare = getCell():getGridSquare(x, y, square:getZ())
            if candidateSquare then
                for _, side in ipairs(sideOrder) do
                    local candidate = MIR.wallSegment(x, y, square:getZ(), side)
                    if candidate.axis ~= rackSegment.axis
                        and MIR.hasWallSide(candidateSquare, side) then
                        local endpoint = MIR.wallSegmentsSharedEndpoint(rackSegment, candidate)
                        if endpoint == "a" then trimA = true end
                        if endpoint == "b" then trimB = true end
                    end
                end
            end
        end
    end
    return MIR.trimVariantForEnds(rackSegment.side, trimA, trimB)
end

function MIR.rackSegment(rackWorld)
    local square = rackWorld and rackWorld:getSquare() or nil
    local item = MIR.itemFromWorldObject(rackWorld)
    local data = item and MIR.ensureRackData(item) or nil
    if not square or not data then return nil end
    return MIR.wallSegment(square:getX(), square:getY(), square:getZ(), data.wallSide)
end

function MIR.racksAreAdjacent(first, second)
    if first == second then return false end
    return MIR.wallSegmentsAdjacent(MIR.rackSegment(first), MIR.rackSegment(second))
end

function MIR.collectAdjacentRacks(selected)
    if not MIR.isRackWorldObject(selected) or not selected:getSquare() then return {} end

    local result, queue, seen = { selected }, { selected }, {}
    seen[MIR.worldItemKey(selected, MIR.itemFromWorldObject(selected))] = true
    local head = 1
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        local square = current:getSquare()
        if square then
            local z = square:getZ()
            for x = square:getX() - 1, square:getX() + 1 do
                for y = square:getY() - 1, square:getY() + 1 do
                    local candidateSquare = getCell():getGridSquare(x, y, z)
                    if candidateSquare then
                        MIR.eachWorldItem(candidateSquare, function(candidate, item)
                            if MIR.isRackItem(item) then
                                local key = MIR.worldItemKey(candidate, item)
                                if not seen[key] and MIR.racksAreAdjacent(current, candidate) then
                                    seen[key] = true
                                    result[#result + 1] = candidate
                                    queue[#queue + 1] = candidate
                                end
                            end
                        end)
                    end
                end
            end
        end
    end

    table.sort(result, function(a, b)
        local as, bs = a:getSquare(), b:getSquare()
        if as:getZ() ~= bs:getZ() then return as:getZ() < bs:getZ() end
        if as:getY() ~= bs:getY() then return as:getY() < bs:getY() end
        if as:getX() ~= bs:getX() then return as:getX() < bs:getX() end
        return MIR.worldItemId(a) < MIR.worldItemId(b)
    end)
    return result
end

local wallYaw = { north = 0, west = 90, south = 180, east = 270 }

function MIR.rackYaw(rackWorld)
    local item = MIR.itemFromWorldObject(rackWorld)
    local data = item and MIR.ensureRackData(item) or nil
    if data and wallYaw[data.wallSide] ~= nil then return wallYaw[data.wallSide] end
    local pose = MIR.pose(rackWorld)
    return pose and pose.rotZ or 0
end

function MIR.pose(worldObject)
    if not worldObject or not worldObject:getSquare() then return nil end
    local square = worldObject:getSquare()
    local item = worldObject:getItem()
    return {
        x = square:getX() + (tonumber(call(worldObject, "getOffX", 0)) or 0),
        y = square:getY() + (tonumber(call(worldObject, "getOffY", 0)) or 0),
        z = square:getZ() + (tonumber(call(worldObject, "getOffZ", 0)) or 0),
        rotX = tonumber(call(item, "getWorldXRotation", 0)) or 0,
        rotY = tonumber(call(item, "getWorldYRotation", 0)) or 0,
        rotZ = tonumber(call(item, "getWorldZRotation", 0)) or 0,
    }
end

function MIR.captureRelativeValues(rackWorld, target)
    local rack = MIR.pose(rackWorld)
    if not rack or not target then return nil end
    local yaw = MIR.rackYaw(rackWorld)
    local angle = math.rad(-yaw)
    local dx, dy = target.x - rack.x, target.y - rack.y
    return {
        localX = dx * math.cos(angle) - dy * math.sin(angle),
        localY = dx * math.sin(angle) + dy * math.cos(angle),
        localZ = target.z - rack.z,
        rotX = target.rotX,
        rotY = target.rotY,
        rotZ = target.rotZ - yaw,
    }
end

function MIR.captureRelativePose(rackWorld, targetWorld)
    return MIR.captureRelativeValues(rackWorld, MIR.pose(targetWorld))
end

function MIR.restorePose(rackWorld, slot)
    local rack = MIR.pose(rackWorld)
    if not rack or not slot then return nil end
    local yaw = MIR.rackYaw(rackWorld)
    local angle = math.rad(yaw)
    return {
        x = rack.x + slot.localX * math.cos(angle) - slot.localY * math.sin(angle),
        y = rack.y + slot.localX * math.sin(angle) + slot.localY * math.cos(angle),
        z = rack.z + slot.localZ,
        rotX = slot.rotX or 0,
        rotY = slot.rotY or 0,
        rotZ = (slot.rotZ or 0) + yaw,
    }
end

function MIR.slotLabel(slot)
    return tostring(slot.preferredName or slot.preferredFullType or "Item")
        .. " — " .. MIR.ruleName(slot.rule)
end

return MIR
