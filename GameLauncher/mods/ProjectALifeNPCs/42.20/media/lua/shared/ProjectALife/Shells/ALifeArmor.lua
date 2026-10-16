require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Armor = {
    key = "Combat_NpcArmorVsZombies",
    settings = { holeFloor = 30, engine = true },
    kinds = {
        bite = { bite = true, bullet = false, zombie = true, scratch = false },
        scratch = { bite = false, bullet = false, zombie = true, scratch = true },
        laceration = { bite = false, bullet = false, zombie = true, scratch = true },
        blade = { bite = true, bullet = false, zombie = false, scratch = false },
        blunt = { bite = false, bullet = false, zombie = false, scratch = false },
        bullet = { bite = false, bullet = true, zombie = false, scratch = false },
    },
    names = { [0] = "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R", "Torso_Upper",
        "Torso_Lower", "Head", "Neck", "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R" },
    aliases = { head = 8, neck = 9, torso = 6, chest = 6, belly = 7, abdomen = 7, groin = 10, arm = 4, arms = 4,
        upperarm = 4, forearm = 2, hand = 0, hands = 0, leg = 11, legs = 11, thigh = 11, shin = 13, foot = 15, feet = 15 },
    limbs = { [0] = 0, 1, 2, 3, 4, 5, 11, 12, 13, 14, 15, 16 },
    byName = {},
    holed = setmetatable({}, { __mode = "k" }),
    metrics = { strikes = 0, covered = 0, blocked = 0, reduced = 0, broken = 0, engine = 0, model = 0, errors = 0,
        zombie = 0, bullet = 0, blade = 0, blunt = 0 },
}
ProjectALife.Armor = Armor

for index = 0, 16 do Armor.byName[string.lower(Armor.names[index])] = index end

function Armor.enabled()
    local gate = ProjectALife.FeatureGate
    if gate == nil or type(gate.flag) ~= "function" then return true end
    return ProjectALife.FeatureGate.flag("Combat_NpcArmorVsZombies", true)
end

function Armor.reset()
    Armor.holed = setmetatable({}, { __mode = "k" })
    Armor.metrics = { strikes = 0, covered = 0, blocked = 0, reduced = 0, broken = 0, engine = 0, model = 0, errors = 0,
        zombie = 0, bullet = 0, blade = 0, blunt = 0 }
end

function Armor.partIndex(part)
    if part == nil then return nil end
    if type(part) == "number" then
        local whole = math.floor(part)
        if whole >= 0 and whole <= 16 then return whole end
        return nil
    end
    if type(part) ~= "string" and BodyPartType ~= nil and type(BodyPartType.ToIndex) == "function" then
        local ok, value = pcall(BodyPartType.ToIndex, part)
        if ok and type(value) == "number" and value >= 0 and value <= 16 then return math.floor(value) end
    end
    local key = string.lower(tostring(part))
    local found = Armor.byName[key]
    if found == nil then found = Armor.aliases[key] end
    return found
end

function Armor.die(sides)
    if type(ZombRand) == "function" then return ZombRand(sides) end
    return sides - 1
end

function Armor.zonePart(zone)
    local key = string.lower(tostring(zone))
    if key == "head" then return 8 end
    if key == "torso" or key == "body" then return 6 + Armor.die(2) end
    if key == "limb" or key == "limbs" then return Armor.limbs[Armor.die(12)] end
    return nil
end

function Armor.bloodPart(index)
    if BloodBodyPartType == nil or type(BloodBodyPartType.FromIndex) ~= "function" then return nil end
    local ok, part = pcall(BloodBodyPartType.FromIndex, index)
    if ok then return part end
    return nil
end

function Armor.sizeOf(list)
    if list == nil or type(list.size) ~= "function" or type(list.get) ~= "function" then return 0 end
    local ok, size = pcall(list.size, list)
    if ok and type(size) == "number" then return size end
    return 0
end

function Armor.visuals(npc)
    if type(npc.getItemVisuals) ~= "function" then return nil end
    local ok, list = pcall(npc.getItemVisuals, npc)
    if ok then return list end
    return nil
end

function Armor.wornList(npc)
    if type(npc.getWornItems) ~= "function" then return nil end
    local ok, list = pcall(npc.getWornItems, npc)
    if ok then return list end
    return nil
end

function Armor.dressed(npc)
    if npc == nil then return false end
    if Armor.sizeOf(Armor.visuals(npc)) > 0 then return true end
    return Armor.sizeOf(Armor.wornList(npc)) > 0
end

function Armor.visualItem(visual)
    local item
    if type(visual.getInventoryItem) == "function" then
        local ok, value = pcall(visual.getInventoryItem, visual)
        if ok then item = value end
    end
    if item == nil and type(visual.getItemType) == "function" and type(instanceItem) == "function" then
        local okType, kind = pcall(visual.getItemType, visual)
        if okType and kind ~= nil then
            local okMake, made = pcall(instanceItem, kind)
            if okMake then item = made end
        end
    end
    return item
end

function Armor.wornItem(entry)
    if entry ~= nil and type(entry.getItem) == "function" then
        local ok, item = pcall(entry.getItem, entry)
        if ok then return item end
        return nil
    end
    return entry
end

function Armor.items(npc)
    local found, seen = {}, {}
    local visuals = Armor.visuals(npc)
    for index = 0, Armor.sizeOf(visuals) - 1 do
        local ok, visual = pcall(visuals.get, visuals, index)
        local item = ok and visual ~= nil and Armor.visualItem(visual) or nil
        if item ~= nil and not seen[item] then
            seen[item] = true
            found[#found + 1] = item
        end
    end
    local worn = Armor.wornList(npc)
    for index = 0, Armor.sizeOf(worn) - 1 do
        local ok, entry = pcall(worn.get, worn, index)
        local item = ok and Armor.wornItem(entry) or nil
        if item ~= nil and not seen[item] then
            seen[item] = true
            found[#found + 1] = item
        end
    end
    return found
end

function Armor.covers(item)
    local covers = {}
    if type(item.getCoveredParts) ~= "function" then return covers end
    local ok, list = pcall(item.getCoveredParts, item)
    if not ok then return covers end
    for index = 0, Armor.sizeOf(list) - 1 do
        local okGet, part = pcall(list.get, list, index)
        local at = nil
        if okGet and part ~= nil then
            if type(part) == "number" then at = part
            elseif type(part.index) == "function" then
                local okAt, value = pcall(part.index, part)
                if okAt then at = tonumber(value) end
            end
        end
        if at ~= nil then covers[at] = true end
    end
    return covers
end

function Armor.number(item, name)
    if type(item[name]) ~= "function" then return nil end
    local ok, value = pcall(item[name], item)
    if ok then return tonumber(value) end
    return nil
end

function Armor.flagsOf(kind)
    local flags = Armor.kinds[kind]
    if flags == nil then return nil end
    return flags.bite, flags.bullet, flags.zombie, flags.scratch
end

function Armor.itemDefense(item, covers, index, kind)
    if covers[index] ~= true then return 0 end
    local holed = Armor.holed[item]
    if holed ~= nil and holed[index] == true then return 0 end
    local bite, bullet = Armor.flagsOf(kind)
    local value
    local part = Armor.bloodPart(index)
    if part ~= nil and type(item.getDefForPart) == "function" then
        local ok, got = pcall(item.getDefForPart, item, part, bite, bullet)
        if ok then value = tonumber(got) end
    end
    if value == nil then
        local condition = Armor.number(item, "getCondition")
        if condition ~= nil and condition <= 0 then return 0 end
        if bullet then value = Armor.number(item, "getBulletDefense")
        elseif bite then value = Armor.number(item, "getBiteDefense")
        else value = Armor.number(item, "getScratchDefense") end
        if value == nil then return 0 end
        if index == 9 then
            local neck = Armor.number(item, "getNeckProtectionModifier")
            if neck ~= nil and neck < 1 then value = value * neck end
        end
    end
    if value <= 0 then return 0 end
    return value
end

function Armor.modelDefense(npc, index, kind)
    local total = 0
    local items = Armor.items(npc)
    for position = 1, #items do
        local item = items[position]
        total = total + Armor.itemDefense(item, Armor.covers(item), index, kind)
    end
    return math.min(100, total)
end

function Armor.engineDefense(npc, index, kind)
    if Armor.settings.engine ~= true or type(npc.getBodyPartClothingDefense) ~= "function" then return nil end
    local bite, bullet = Armor.flagsOf(kind)
    local ok, value = pcall(npc.getBodyPartClothingDefense, npc, index, bite, bullet)
    value = ok and tonumber(value) or nil
    if value == nil or value ~= value then return nil end
    return math.max(0, math.min(100, value))
end

function Armor.protection(npc, bodyPart, kind)
    local index = Armor.partIndex(bodyPart)
    if index == nil or npc == nil or Armor.kinds[kind] == nil then return 0, "none" end
    local value = Armor.engineDefense(npc, index, kind)
    if value ~= nil then return value, "engine" end
    return Armor.modelDefense(npc, index, kind), "model"
end

function Armor.tear(item, index)
    local holed = Armor.holed[item]
    if holed == nil then
        holed = {}
        Armor.holed[item] = holed
    end
    holed[index] = true
    local loss = Armor.number(item, "getCondLossPerHole") or 1
    local condition = Armor.number(item, "getCondition")
    if condition ~= nil and type(item.setCondition) == "function" then
        pcall(item.setCondition, item, math.max(1, math.floor(condition - math.max(1, loss))))
    end
end

function Armor.wearModel(npc, index, kind, blocked)
    local items = Armor.items(npc)
    local flags = Armor.kinds[kind]
    local zombie = flags.zombie == true
    local torn = 0
    for position = #items, 1, -1 do
        local item = items[position]
        local covers = Armor.covers(item)
        if covers[index] == true and not (Armor.holed[item] ~= nil and Armor.holed[item][index] == true) then
            if blocked then
                local own = Armor.itemDefense(item, covers, index, zombie and kind or "blade")
                local chance = math.max(Armor.settings.holeFloor, 100 - own / 1.5)
                if Armor.die(100) < chance then
                    Armor.tear(item, index)
                    torn = torn + 1
                end
                break
            end
            Armor.tear(item, index)
            torn = torn + 1
            if not zombie then break end
        end
    end
    return torn > 0
end

function Armor.wear(npc, index, kind, blocked, source)
    local flags = Armor.kinds[kind]
    local part = Armor.bloodPart(index)
    local added = false
    if source == "engine" and part ~= nil then
        local ok, result
        if blocked and type(npc.addHoleFromZombieAttacks) == "function" then
            ok, result = pcall(npc.addHoleFromZombieAttacks, npc, part, flags.scratch == true)
        elseif not blocked and type(npc.addHole) == "function" then
            if flags.zombie then
                ok, result = pcall(npc.addHole, npc, part, true)
            else
                ok, result = pcall(npc.addHole, npc, part)
            end
        end
        added = ok == true and result == true
    elseif source == "model" then
        added = Armor.wearModel(npc, index, kind, blocked)
    end
    if added then Armor.metrics.broken = Armor.metrics.broken + 1 end
    return added
end

function Armor.sound(npc, index, kind)
    local flags = Armor.kinds[kind]
    if flags == nil or flags.zombie or type(npc.playWeaponHitArmourSound) ~= "function" then return false end
    return pcall(npc.playWeaponHitArmourSound, npc, index, flags.bullet == true)
end

function Armor.guard(npc, bodyPart, kind)
    if npc == nil or Armor.kinds[kind] == nil or not Armor.enabled() then return false, 0, nil end
    local index = Armor.partIndex(bodyPart)
    if index == nil then return false, 0, nil end
    local defense, source = Armor.protection(npc, index, kind)
    if defense <= 0 then return false, 0, index end
    local metrics = Armor.metrics
    metrics.covered = metrics.covered + 1
    metrics[source] = (metrics[source] or 0) + 1
    if Armor.die(100) < defense then
        metrics.blocked = metrics.blocked + 1
        local flags = Armor.kinds[kind]
        local group = flags.zombie and "zombie" or (flags.bullet and "bullet" or (flags.bite and "blade" or "blunt"))
        metrics[group] = metrics[group] + 1
        Armor.wear(npc, index, kind, true, source)
        Armor.sound(npc, index, kind)
        return true, defense, index
    end
    Armor.wear(npc, index, kind, false, source)
    metrics.reduced = metrics.reduced + 1
    return false, defense, index
end

function Armor.reduce(npc, bodyPart, kind, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 or npc == nil then return amount, "none", 0 end
    local blocked, defense = Armor.guard(npc, bodyPart, kind)
    if blocked then return 0, "blocked", defense end
    if defense > 0 then return amount, "through", defense end
    return amount, "none", 0
end

function Armor.kindOfWeapon(weapon)
    if weapon == nil or type(weapon) ~= "table" and type(weapon) ~= "userdata" then return "blade" end
    if type(weapon.isAimedFirearm) == "function" then
        local ok, aimed = pcall(weapon.isAimedFirearm, weapon)
        if ok and aimed == true then return "bullet" end
    end
    if WeaponCategory ~= nil and type(weapon.isOfWeaponCategory) == "function" then
        for _, name in ipairs({ "BLUNT", "SMALL_BLUNT" }) do
            local category = WeaponCategory[name]
            if category ~= nil then
                local ok, yes = pcall(weapon.isOfWeaponCategory, weapon, category)
                if ok and yes == true then return "blunt" end
            end
        end
    end
    return "blade"
end

function Armor.informed(npc)
    if npc == nil or not Armor.enabled() then return false end
    if Armor.settings.engine == true and type(npc.getBodyPartClothingDefense) == "function" then return true end
    return #Armor.items(npc) > 0
end

function Armor.blocksWeapon(npc, bodyPart, weapon)
    if npc == nil or not Armor.enabled() or not Armor.dressed(npc) then return false, 0, nil end
    local part = Armor.zonePart(tostring(bodyPart))
    if part == nil then
        part = Armor.partIndex(bodyPart)
        if part == nil then part = Armor.zonePart("torso") end
    end
    return Armor.guard(npc, part, Armor.kindOfWeapon(weapon))
end

function Armor.sideOf(npc, zombie)
    if zombie == nil or type(npc.testDotSide) ~= "function" then return "front" end
    local ok, side = pcall(npc.testDotSide, npc, zombie)
    if not ok or side == nil then return "front" end
    return string.lower(tostring(side))
end

function Armor.crawling(zombie)
    if zombie == nil or type(zombie.isCrawling) ~= "function" then return false end
    local ok, value = pcall(zombie.isCrawling, zombie)
    return ok and value == true
end

function Armor.pickPart(npc, zombie)
    if Armor.crawling(zombie) then
        local first = 11
        if Armor.die(10) == 0 then first = 10 end
        return first + Armor.die(17 - first)
    end
    local side = Armor.sideOf(npc, zombie)
    local reach = 10
    if Armor.die(10) == 0 then reach = 11 end
    local part = Armor.die(reach)
    if side == "behind" and Armor.die(100) < 15 then part = 9 end
    if part == 8 or part == 9 then
        local keep = 70
        if side == "behind" then keep = 90 elseif side == "left" or side == "right" then keep = 80 end
        if Armor.die(100) > keep then part = Armor.die(8) end
    end
    return part
end

function Armor.strike(npc, zombie, amount)
    if npc == nil or not Armor.enabled() or not Armor.dressed(npc) then return nil end
    local sim = ProjectALife.ShellSimulation
    if sim == nil or type(sim.woundKind) ~= "function" or type(ZombRand) ~= "function" then return nil end
    local kind = sim.woundKind(ZombRand(100), ZombRand(100))
    local part = Armor.pickPart(npc, zombie)
    local damage, outcome, defense = Armor.reduce(npc, part, kind, amount)
    Armor.metrics.strikes = Armor.metrics.strikes + 1
    return { damage = damage, outcome = outcome, kind = kind, part = part, defense = defense }
end

function Armor.qaLine()
    local m = Armor.metrics
    return "[ALIFE-QA] Armor: blocked=" .. tostring(m.blocked) .. " reduced=" .. tostring(m.reduced)
        .. " broken=" .. tostring(m.broken) .. " strikes=" .. tostring(m.strikes) .. " covered=" .. tostring(m.covered)
        .. " engine=" .. tostring(m.engine) .. " model=" .. tostring(m.model)
        .. " zombie=" .. tostring(m.zombie) .. " bullet=" .. tostring(m.bullet)
        .. " blade=" .. tostring(m.blade) .. " blunt=" .. tostring(m.blunt)
end

return Armor
