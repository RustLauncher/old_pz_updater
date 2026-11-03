require "ProjectALife/Shells/ALifeProfileHydrator"
require "ProjectALife/Records/ALifeDropPolicy"
require "ProjectALife/Records/ALifeLootRarity"
require "ProjectALife/Records/ALifeLootWear"
require "ProjectALife/Compat/ALifeFeatureGate"

require "ProjectALife/Shells/ALifeDeathInventory"
require "ProjectALife/Compat/ALifeInterop"

ProjectALife = ProjectALife or {}

local Hydrator = ProjectALife.ProfileHydrator
local Interop = ProjectALife.Interop
local DeathDrops = { adapters = {}, enabled = true,
    metrics = { breaksClamped = 0, handsCleared = 0, attachedCleared = 0 } }
ProjectALife.DeathDrops = DeathDrops

local function rollPercent(chance)
    if type(DeathDrops.adapters.rollPercent) == "function" then
        return DeathDrops.adapters.rollPercent(chance) == true
    end
    local value
    if type(ZombRandFloat) == "function" then value = ZombRandFloat(0, 100)
    elseif type(ZombRandBetween) == "function" then value = ZombRandBetween(0, 100)
    else value = math.random(0, 99) end
    return value < math.max(0, math.min(100, tonumber(chance) or 0))
end

DeathDrops.kinds = { "weapons", "armor", "ammo", "other" }
DeathDrops.dayMs = 86400000

function DeathDrops.freshTally(stamp)
    local tally = { stamp = stamp, deaths = 0, considered = {}, dropped = {} }
    local wear = ProjectALife.LootWear
    if type(wear) == "table" then tally.wear = wear.newTally() end
    for _, kind in ipairs(DeathDrops.kinds) do
        tally.considered[kind], tally.dropped[kind] = 0, 0
    end
    return tally
end

function DeathDrops.stamp()
    if type(getTimestampMs) ~= "function" then return 0 end
    return math.floor((tonumber(getTimestampMs()) or 0) / DeathDrops.dayMs)
end

function DeathDrops.current()
    local stamp = DeathDrops.stamp()
    if type(DeathDrops.tally) ~= "table" or DeathDrops.tally.stamp ~= stamp then
        DeathDrops.tally = DeathDrops.freshTally(stamp)
    end
    return DeathDrops.tally
end

function DeathDrops.note(kind, kept)
    local tally = DeathDrops.current()
    kept = kept == true
    tally.considered[kind] = (tally.considered[kind] or 0) + 1
    if kept then tally.dropped[kind] = (tally.dropped[kind] or 0) + 1 end
    return kept
end

function DeathDrops.qaLine()
    local tally = DeathDrops.current()
    local percents = ProjectALife.DropPolicy.percents()
    local dropped, considered = {}, {}
    for index, kind in ipairs(DeathDrops.kinds) do
        dropped[index], considered[index] = tostring(tally.dropped[kind]), tostring(tally.considered[kind])
    end
    return "[ALIFE-QA] Loot: master=" .. tostring(percents.master)
        .. " dropped(weapons,armor,ammo,other)=" .. table.concat(dropped, ",")
        .. " considered=" .. table.concat(considered, ",") .. " deaths=" .. tostring(tally.deaths)
end

function DeathDrops.wearQaLine()
    local tally = DeathDrops.current().wear
    local wear = ProjectALife.LootWear
    if type(tally) ~= "table" or type(wear) ~= "table" then return nil end
    local function rows(list) return table.concat({ list[1], list[2], list[3], list[4] }, "/") end
    local fill = tally.mags > 0 and (100 * tally.magFill / tally.mags) or 0
    return "[ALIFE-QA] LootWear: wear=" .. tostring(wear.percent()) .. " corpses=" .. tostring(tally.corpses)
        .. " guns broken/low/mid/ok=" .. rows(tally.guns)
        .. " mags=" .. tostring(tally.mags) .. " avgFill=" .. string.format("%.0f", fill) .. "%"
        .. " armor broken/low/mid/ok=" .. rows(tally.armor)
        .. " ammoRoundsDropped=" .. tostring(tally.dropped) .. " vs issued=" .. tostring(tally.issued)
        .. " melee=" .. rows(tally.melee) .. " clothes=" .. rows(tally.clothing)
        .. " looseAmmoKept=" .. tostring(tally.looseKept) .. "/" .. tostring(tally.loose)
end

function DeathDrops.wearStrength()
    local wear = ProjectALife.LootWear
    if type(wear) ~= "table" then return 0 end
    return wear.strength()
end

function DeathDrops.keeps(chance)
    if chance == nil then return true end
    chance = tonumber(chance) or 0
    if chance >= 100 then return true end
    if chance <= 0 then return false end
    return rollPercent(chance)
end

function DeathDrops.never(fullType)
    local policy = ProjectALife.DropPolicy
    return type(policy.neverDrops) == "function" and policy.neverDrops(fullType) == true
end

function DeathDrops.flags(item)
    if type(item.hasModData) == "function" and item:hasModData() ~= true then return nil end
    if type(item.getModData) ~= "function" then return nil end
    local ok, data = pcall(item.getModData, item)
    if ok and type(data) == "table" then return data end
    return nil
end

function DeathDrops.configure(adapters)
    DeathDrops.adapters = adapters or {}
    DeathDrops.enabled = DeathDrops.adapters.enabled ~= false
    DeathDrops.metrics = { breaksClamped = 0, handsCleared = 0, attachedCleared = 0 }
    DeathDrops.tally = DeathDrops.freshTally(DeathDrops.stamp())
end

function DeathDrops.plan(actor)
    local profile, profileError = Hydrator.plan(actor)
    if profile == nil then return nil, profileError end
    local policy = ProjectALife.DropPolicy
    local scale = policy.scales(profile.drop.weaponExplicit == true)
    local eligible = DeathDrops.enabled and profile.drop.weapon == true
    return {
        keepWeapon = eligible,
        weaponChance = eligible and policy.scaled(profile.drop.weaponChance, scale.weapon) or 0,
        weaponCondition = profile.drop.weaponCondition,
        weaponConditionExplicit = profile.drop.weaponConditionExplicit == true,
        weaponTypes = profile.weapons,
        armorChance = DeathDrops.enabled and policy.scaled(profile.drop.armorChance, scale.armor) or 0,
        armorCondition = profile.drop.armorCondition,
        rareDrop = profile.drop.rareDrop == true,
        rareRating = profile.drop.rareRating,
        rareChance = scale.armor,
        scarceCarried = profile.drop.scarceCarried == true,
        guarded = profile.drop.class ~= nil,
        dropAmmo = DeathDrops.enabled and profile.drop.ammo,
        magazineMax = math.max(0, math.floor(profile.drop.magazineMax)),
        magazineChance = policy.scaled(profile.drop.magazineChance, scale.ammo),
        ammoItemChance = scale.ammo,
        suppliesChance = scale.supplies,
        scale = scale,
        wear = DeathDrops.wearStrength(),
        wearKey = tostring(type(actor) == "table" and actor.uid or "?") .. ":"
            .. tostring(type(actor) == "table" and actor.generation or 0),
        ammo = profile.ammo or {},
        ammoMode = profile.ammoMode or {},
        honestAmmo = DeathDrops.honestAmmo(),
    }
end

function DeathDrops.honestAmmo()
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    if type(current) == "table" and current.ammoHonestDrops ~= nil then
        return current.ammoHonestDrops ~= false
    end
    return true
end

function DeathDrops.carried(shell)
    local ok, data = pcall(function() return shell:getModData() end)
    if not ok or type(data) ~= "table" then return nil end
    local primary = tonumber(data.ProjectALifePrimaryAmmoUnits)
    local secondary = tonumber(data.ProjectALifeSecondaryAmmoUnits)
    if primary == nil and secondary == nil then return nil end
    return { primary = math.max(0, primary or 0), secondary = math.max(0, secondary or 0) }
end

local function itemType(item)
    local ok, value = pcall(function() return item:getFullType() end)
    if ok and value ~= nil then return tostring(value) end
    ok, value = pcall(function() return item:getType() end)
    return ok and tostring(value) or ""
end

local function matchesWeapon(item, weaponTypes)
    local candidate = itemType(item)
    for _, kind in pairs(weaponTypes or {}) do
        if candidate == tostring(kind) or candidate == tostring(kind):gsub("^Base%.", "") then
            return true
        end
    end
    return false
end

function DeathDrops.conditionFor(maximum, rating)
    return ProjectALife.DropPolicy.conditionFor(maximum, rating)
end

local function setCondition(item, rating)
    pcall(function()

        local data = item:getModData()
        if data.ProjectALifeWorn == true then return end
        if data.ProjectALifeIssuedCondition == true then

            if data.ProjectALifeBreakOnDrop == true then
                data.ProjectALifeBreakOnDrop = nil
                if ProjectALife.DropPolicy.hasBreakHandler(item) then
                    DeathDrops.metrics.breaksClamped = DeathDrops.metrics.breaksClamped + 1
                    item:setCondition(math.max(1, tonumber(item:getCondition()) or 1))
                    return
                end
                if not ProjectALife.LootRarity.mayBreak(item) then
                    item:setCondition(math.max(1, tonumber(item:getCondition()) or 1))
                    return
                end
                item:setCondition(0)
            end
            return
        end
        local authored = DeathDrops.conditionFor(item:getConditionMax(), rating)
        local clamped
        authored, clamped = ProjectALife.DropPolicy.breakSafe(item, authored)
        if clamped then DeathDrops.metrics.breaksClamped = DeathDrops.metrics.breaksClamped + 1 end

        local firearm, current = false, nil
        if item.isAimedFirearm ~= nil then firearm = item:isAimedFirearm() == true end
        pcall(function() current = tonumber(item:getCondition()) end)
        if firearm and current ~= nil and current < authored then authored = current end
        item:setCondition(authored)
    end)
end

local function authoredClothing(item)
    local ok, data = pcall(function() return item:getModData() end)
    return ok and type(data) == "table"
        and data.ProjectALifeAuthoredClothing == true
end

local function removeWornVisual(shell, item)

    local dead = false
    pcall(function() dead = shell:isDead() == true end)
    if dead then return end
    pcall(function()
        local visual = item:getVisual()
        local worn = shell:getItemVisuals()
        if visual ~= nil and worn ~= nil then worn:remove(visual) end
    end)
end

function DeathDrops.detach(shell)
    local cleared = 0
    for _, hand in ipairs({ "Primary", "Secondary" }) do
        local getter, setter = shell["get" .. hand .. "HandItem"], shell["set" .. hand .. "HandItem"]
        if type(getter) == "function" and type(setter) == "function" then
            local ok, held = pcall(getter, shell)
            if ok and held ~= nil then
                local done = pcall(setter, shell, nil)
                if done then cleared = cleared + 1 end
            end
        end
    end
    DeathDrops.metrics.handsCleared = DeathDrops.metrics.handsCleared + cleared
    local attached = 0
    if type(shell.getAttachedItems) == "function" and type(shell.removeAttachedItem) == "function" then
        local ok, list = pcall(shell.getAttachedItems, shell)
        if ok and list ~= nil and type(list.size) == "function" and type(list.get) == "function" then
            local found = {}
            for index = 0, list:size() - 1 do
                local entry = list:get(index)
                local item = entry ~= nil and type(entry.getItem) == "function" and entry:getItem() or nil
                if item ~= nil then found[#found + 1] = item end
            end
            for _, item in ipairs(found) do
                if pcall(shell.removeAttachedItem, shell, item) then attached = attached + 1 end
            end
        end
    end
    DeathDrops.metrics.attachedCleared = DeathDrops.metrics.attachedCleared + attached
    return cleared + attached
end

function DeathDrops.roundsIn(inventory)
    local wear, total = ProjectALife.LootWear, 0
    local items = inventory:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if (tonumber(wear.ask(item, "getMaxAmmo")) or 0) > 0 then
            total = total + math.max(0, tonumber(wear.ask(item, "getCurrentAmmoCount")) or 0)
        elseif ProjectALife.DropPolicy.isAmmo(itemType(item)) then
            total = total + 1
        end
    end
    return total
end

function DeathDrops.wearStart(shell, plan, inventory)
    plan.wearOn = false
    local wear = ProjectALife.LootWear
    if type(wear) ~= "table" or (tonumber(plan.wear) or 0) <= 0 then return false end
    local ok, data = false, nil
    if type(shell.getModData) == "function" then ok, data = pcall(shell.getModData, shell) end
    if ok and type(data) == "table" and data.ProjectALifeLootWorn == plan.wearKey then return false end
    plan.wearOn = true
    local carried = DeathDrops.carried(shell)
    plan.issued = DeathDrops.roundsIn(inventory)
        + (carried ~= nil and (carried.primary + carried.secondary) or 0)
    return true
end

function DeathDrops.stolenItem(item)
    local stolen = false
    pcall(function()
        local data = item:getModData()
        stolen = type(data) == "table" and data.ProjectALifeStolen == true
    end)
    return stolen
end

function DeathDrops.wearItem(item, plan, index, fullType, hint)
    local wear = ProjectALife.LootWear
    if plan.wearOn ~= true or type(wear) ~= "table" then return true end
    if DeathDrops.stolenItem(item) then return true end
    local kind = wear.kindOf(item, fullType, hint)
    if kind == nil then return true end
    local key = plan.wearKey .. ":" .. tostring(index) .. ":" .. tostring(fullType)
    local tally = DeathDrops.current().wear
    if kind == "loose" then
        tally.loose = tally.loose + 1
        if not wear.keepLoose(key, plan.wear) then return false end
        tally.looseKept = tally.looseKept + 1
        return true
    end
    if kind == "magazine" then
        local after, capacity = wear.fill(item, kind, key, plan.wear)
        if after ~= nil and capacity > 0 then wear.noteMag(tally, after / capacity) end
        return true
    end
    local strength = plan.wear
    if plan.weaponConditionExplicit == true and (kind == "firearm" or kind == "melee") then strength = 0 end
    local fraction = wear.condition(item, kind, key, strength)
    if fraction ~= nil then wear.note(tally, kind, fraction) end
    if kind == "firearm" then
        local after, capacity, _, detachable = wear.fill(item, kind, key, plan.wear)
        if detachable == true and after ~= nil and capacity > 0 then wear.noteMag(tally, after / capacity) end
    end
    return true
end

function DeathDrops.wearFinish(shell, plan, inventory)
    if plan.wearOn ~= true then return false end
    local tally = DeathDrops.current().wear
    tally.corpses = tally.corpses + 1
    tally.issued = tally.issued + (tonumber(plan.issued) or 0)
    tally.dropped = tally.dropped + DeathDrops.roundsIn(inventory)
    local ok, data = false, nil
    if type(shell.getModData) == "function" then ok, data = pcall(shell.getModData, shell) end
    if ok and type(data) == "table" then data.ProjectALifeLootWorn = plan.wearKey end
    return true
end

function DeathDrops.dropFill(plan, capacity, rounds, slot, number)
    local wear = ProjectALife.LootWear
    if plan.wearOn ~= true or type(wear) ~= "table" then return rounds end
    local key = plan.wearKey .. ":" .. tostring(slot) .. ":mag:" .. tostring(number)
    local put = wear.rounds(rounds, capacity, wear.ammo.magazine, key, "fill", plan.wear)
    wear.noteMag(DeathDrops.current().wear, put / math.max(1, capacity))
    return put
end

function DeathDrops.dropLoose(plan, rounds, slot)
    local wear = ProjectALife.LootWear
    if plan.wearOn ~= true or type(wear) ~= "table" then return rounds end
    return wear.reserve(rounds, plan.wearKey .. ":" .. tostring(slot) .. ":loose", "reserve", plan.wear)
end

function DeathDrops.dropMagazines(inventory, plan)
    if not plan.dropAmmo then return 0 end
    local dropped = 0
    for _, slot in ipairs({ "primary", "secondary" }) do
        local kind = (plan.weaponTypes or {})[slot]
        if kind and kind ~= "none" and type(instanceItem) == "function" then
            pcall(function()
                local gun = instanceItem(kind)
                if not gun or not gun:isRanged() then return end
                local capacity = math.max(1, math.min(300, tonumber(gun:getMaxAmmo()) or 1))
                local count = tonumber((plan.ammo or {})[slot]) or 0
                if (plan.ammoMode or {})[slot] ~= "magazines" then count = math.ceil(count / capacity) end
                count = math.max(0, math.min(100, math.floor(count)))
                local left = nil
                if plan.honestAmmo == true then
                    count = DeathDrops.honestCount(count, capacity, plan, slot)
                    left = type(plan.carried) == "table" and tonumber(plan.carried[slot]) or nil
                end
                local magazineType = gun:getMagazineType()
                for number = 1, count do
                    local rounds = left ~= nil and math.min(capacity, left) or capacity
                    if rounds > 0 and DeathDrops.note("ammo", rollPercent(plan.magazineChance)) then
                        if left ~= nil then left = left - rounds end
                        if magazineType and magazineType ~= "" then
                            local magazine = inventory:AddItem(magazineType)
                            if magazine then
                                local put = DeathDrops.dropFill(plan, capacity, rounds, slot, number)
                                magazine:setCurrentAmmoCount(math.min(put, magazine:getMaxAmmo()))
                                dropped = dropped + 1
                            end
                        else
                            local ammoType = gun:getAmmoType()
                            local key = ammoType and ammoType:getItemKey()
                            if key then
                                rounds = DeathDrops.dropLoose(plan, rounds, slot .. number)
                                for _ = 1, rounds do inventory:AddItem(instanceItem(key)) end
                                dropped = dropped + 1
                            end
                        end
                    end
                end
            end)
        end
    end
    return dropped
end

function DeathDrops.honestCount(count, capacity, plan, slot)
    local most = math.floor(tonumber(plan.magazineMax) or 0)
    if most >= 1 then count = math.min(count, most) end
    local carried = type(plan.carried) == "table" and tonumber(plan.carried[slot]) or nil
    if carried ~= nil then count = math.min(count, math.ceil(math.max(0, carried) / capacity)) end
    return math.max(0, count)
end

local function defaultApply(shell, plan)
    local ok = pcall(function()
        local inventory = shell:getInventory()
        local items = inventory and inventory:getItems() or nil
        if items == nil then return end

        local scavenging = ProjectALife.Scavenging
        if scavenging ~= nil and type(scavenging.bagFor) == "function" then
            local bag = scavenging.bagFor(shell, inventory)
            if bag ~= nil and bag ~= inventory then
                local packed = bag:getItems()
                for index = packed:size() - 1, 0, -1 do
                    local carried = packed:get(index)
                    bag:Remove(carried)
                    ProjectALife.DeathInventory.put(inventory, carried)
                end
            end
        end
        pcall(DeathDrops.wearStart, shell, plan, inventory)
        for index = items:size() - 1, 0, -1 do
            local item = items:get(index)
            local candidateType = itemType(item)
            local kind, before = nil, items:size()
            if DeathDrops.stolenItem(item) then
                kind = nil
            elseif candidateType == "Base.BareHands" or candidateType == "Base.Maggots" then

                inventory:Remove(item)
            elseif plan.guarded and (ProjectALife.LootRarity.denied(candidateType)
                    or DeathDrops.never(candidateType)) then
                removeWornVisual(shell, item)
                inventory:Remove(item)
            elseif authoredClothing(item) then
                kind = "armor"
                local tier = plan.guarded and ProjectALife.LootRarity.armorTier(candidateType) or nil
                if tier ~= nil then
                    if plan.rareDrop and DeathDrops.keeps(plan.rareChance) then
                        ProjectALife.LootRarity.degradeItem(item, (tonumber(plan.rareRating) or 2) * 10, true)
                        ProjectALife.LootRarity.metrics.rareKept = ProjectALife.LootRarity.metrics.rareKept + 1
                        pcall(DeathDrops.wearItem, item, plan, index, candidateType)
                    else
                        removeWornVisual(shell, item)
                        inventory:Remove(item)
                    end
                elseif rollPercent(plan.armorChance) then
                    setCondition(item, plan.armorCondition)
                    pcall(DeathDrops.wearItem, item, plan, index, candidateType)
                else
                    removeWornVisual(shell, item)
                    inventory:Remove(item)
                end
            elseif matchesWeapon(item, plan.weaponTypes) then
                kind = "weapons"
                local data = item:getModData()
                if data and data.ProjectALifeRecoveredFrom ~= nil then

                elseif plan.keepWeapon and not (plan.scarceCarried
                        and ProjectALife.LootRarity.scarceWeapon(candidateType))
                        and DeathDrops.keeps(plan.weaponChance) then
                    setCondition(item, plan.weaponCondition)
                    pcall(DeathDrops.wearItem, item, plan, index, candidateType)
                else
                    inventory:Remove(item)
                end
            else
                kind = DeathDrops.thin(inventory, item, candidateType, plan, index)
            end
            if kind ~= nil then DeathDrops.note(kind, items:size() >= before) end
        end
        if plan.honestAmmo == true and plan.carried == nil then plan.carried = DeathDrops.carried(shell) end
        DeathDrops.dropMagazines(inventory, plan)
        pcall(DeathDrops.wearFinish, shell, plan, inventory)
        DeathDrops.detach(shell)

        pcall(function() ProjectALife.DeathInventory.clear(shell) end)
        local survivors = inventory:getItems()
        for index = 0, survivors:size() - 1 do
            local item = survivors:get(index)
            local candidateType = itemType(item)

            if candidateType ~= "Base.BareHands" and candidateType ~= "Base.Maggots"
                    and not authoredClothing(item) then
                pcall(function() ProjectALife.DeathInventory.add(shell, item) end)
            end
        end
    end)
    return ok
end

function DeathDrops.thin(inventory, item, candidateType, plan, index)
    if plan.suppliesChance == nil then return nil end
    local data = DeathDrops.flags(item)
    if data ~= nil and (data.ProjectALifeIdentityCard == true or data.ProjectALifeRecoveredFrom ~= nil) then
        return nil
    end
    if string.find(candidateType, "^Base%.IDcard_") ~= nil then return nil end
    local kind, chance = "other", plan.suppliesChance
    local weapon = false
    if type(item.IsWeapon) == "function" then
        local ok, value = pcall(item.IsWeapon, item)
        weapon = ok and value == true
    end
    if weapon then
        kind, chance = "weapons", 0
        if plan.keepWeapon then chance = plan.weaponChance end
    elseif ProjectALife.DropPolicy.isAmmo(candidateType) then
        kind, chance = "ammo", plan.ammoItemChance
    end
    if not DeathDrops.keeps(chance) then
        inventory:Remove(item)
    elseif plan.wearOn == true then
        local hint = kind == "ammo" and "ammo" or nil
        local ok, keep = pcall(DeathDrops.wearItem, item, plan, index or 0, candidateType, hint)
        if ok and keep == false then inventory:Remove(item) end
    end
    return kind
end

function DeathDrops.rolled(shell, actor, set)
    if type(actor) ~= "table" or actor.uid == nil or type(shell.getModData) ~= "function" then return false end
    local key = tostring(actor.uid) .. ":" .. tostring(actor.generation or 0)
    local ok, data = pcall(shell.getModData, shell)
    if not ok or type(data) ~= "table" then return false end
    if set == true then
        data.ProjectALifeDropsRolled = key
        return true
    end
    return data.ProjectALifeDropsRolled == key
end

function DeathDrops.process(shell, actor)
    ProjectALife.DeathInventory.restore(shell)
    if type(DeathDrops.adapters.process) == "function" then
        local ok, result = pcall(DeathDrops.adapters.process, shell, actor)
        if ok and result ~= false then Interop.looted(shell, actor, nil) end
        return ok and result ~= false
    end
    if DeathDrops.rolled(shell, actor, false) then return true, "already_rolled" end
    local plan, planError = DeathDrops.plan(actor)
    if plan == nil then return false, planError end
    local applied = defaultApply(shell, plan)
    if not applied then pcall(DeathDrops.detach, shell) end
    if applied then
        DeathDrops.rolled(shell, actor, true)
        local tally = DeathDrops.current()
        tally.deaths = tally.deaths + 1
        Interop.looted(shell, actor, plan)
    end
    return applied, plan
end

return DeathDrops
