ProjectALife = ProjectALife or {}

local Magazines = ProjectALife.MagazineState or {}
ProjectALife.MagazineState = Magazines

function Magazines.ask(object, method)
    if object == nil then return nil end
    local getter = object[method]
    if type(getter) ~= "function" then return nil end
    local value = getter(object)
    return value
end

local function magMetadata(shell)
    local data = Magazines.ask(shell, "getModData")
    return type(data) == "table" and data or nil
end

local function magMaximum(item)
    return math.max(0, math.floor(tonumber(Magazines.ask(item, "getMaxAmmo")) or 0))
end

local function rawMagCurrent(item)
    return math.max(0, math.floor(tonumber(Magazines.ask(item, "getCurrentAmmoCount")) or 0))
end

local function magCurrent(item)
    if item == nil then return 0 end
    local data = Magazines.ask(item, "getModData")
    if type(data) == "table"
            and tonumber(data.ProjectALifeLoadedRounds) ~= nil then
        local raw = rawMagCurrent(item)
        local mirrored = tonumber(data.ProjectALifeEngineLoadedRounds)

        if mirrored ~= nil and raw ~= mirrored then
            data.ProjectALifeLoadedRounds = raw
            data.ProjectALifeEngineLoadedRounds = raw
            return raw
        end
        return math.max(0, math.floor(tonumber(data.ProjectALifeLoadedRounds)))
    end
    local loaded = rawMagCurrent(item)
    if type(data) == "table" then
        data.ProjectALifeLoadedRounds = loaded
        data.ProjectALifeEngineLoadedRounds = loaded
    end
    return loaded
end

local function magSetCurrent(item, rounds)
    if item == nil then return false end
    rounds = math.max(0, math.min(magMaximum(item),
        math.floor(tonumber(rounds) or 0)))
    local wrote = item.setCurrentAmmoCount ~= nil
        and pcall(item.setCurrentAmmoCount, item, rounds)
    local engineRounds = rawMagCurrent(item)
    local data = Magazines.ask(item, "getModData")
    if type(data) == "table" then
        data.ProjectALifeLoadedRounds = rounds
        data.ProjectALifeEngineLoadedRounds = engineRounds
    end
    return wrote and engineRounds == rounds and magCurrent(item) == rounds
end

local function reserveField(slot, suffix)
    return (slot == "secondary" and "ProjectALifeSecondary" or "ProjectALifePrimary") .. suffix
end

local FILL_TO_CAPACITY = {
    boltaction = true,
    boltactionnomag = true,
    revolver = true,
    shotgun = true,
    leveraction = true,
    doublebarrelshotgun = true,
    doublebarrelshotgunsawn = true,
}

local function usesExternalMagazine(item)
    local magazineType = Magazines.ask(item, "getMagazineType")
    return magazineType ~= nil and tostring(magazineType) ~= ""
        and tostring(magazineType) ~= "null"
end

function Magazines.feed(item)
    local kind = type(item)
    if kind ~= "userdata" and kind ~= "table" then return nil end
    return usesExternalMagazine(item) and "detachable" or "internal"
end

local function storeReserve(data, slot, rounds, capacity, feed)
    if data == nil then return false end
    rounds = math.max(0, math.floor(tonumber(rounds) or 0))
    capacity = math.max(1, math.floor(tonumber(capacity) or 1))
    if feed ~= "detachable" and feed ~= "internal" then feed = nil end
    local boxed = feed == "detachable"
    data[reserveField(slot, "AmmoUnits")] = rounds
    data[reserveField(slot, "Magazines")] = boxed and math.floor(rounds / capacity) or 0
    data[reserveField(slot, "LooseRounds")] = boxed and rounds % capacity or rounds
    data[reserveField(slot, "MagazineCapacity")] = capacity
    data[reserveField(slot, "AmmoKind")] = feed
    return true
end

local function magEquippedSlot(shell, item)
    local data = magMetadata(shell)
    if data and data.ProjectALifeEquippedSlot == "secondary" then return "secondary" end
    local itemData = Magazines.ask(item, "getModData")
    if type(itemData) == "table"
            and itemData.ProjectALifeWeaponSlot == "secondary" then return "secondary" end
    return "primary"
end

function Magazines.maximum(item) return item and magMaximum(item) or 0 end
function Magazines.current(item) return item and magCurrent(item) or 0 end

function Magazines.isInfinite(shell)
    local data = magMetadata(shell)
    if data and data.ProjectALifeInfiniteAmmo ~= nil then
        return data.ProjectALifeInfiniteAmmo == true
            or tostring(data.ProjectALifeInfiniteAmmo) == "true"
    end
    if shell == nil or shell.GetVariable == nil then return false end
    local value = shell:GetVariable("ALifeInfiniteAmmo")
    return tostring(value) == "true"
end

function Magazines.reserve(shell, slot, item)
    local data = magMetadata(shell)
    if data == nil then return 0 end
    local capacity = magMaximum(item)
    if capacity <= 0 then capacity = tonumber(data[reserveField(slot, "MagazineCapacity")]) or 1 end
    local rounds = math.max(0, math.floor(tonumber(data[reserveField(slot, "AmmoUnits")]) or 0))
    storeReserve(data, slot, rounds, capacity, Magazines.feed(item))
    return rounds
end

function Magazines.limits()
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    local percent, loads = 100, 0
    if type(current) == "table" then
        percent = tonumber(current.ammoSpawnPercent) or 100
        loads = tonumber(current.ammoReserveLoads) or 0
    elseif type(SandboxVars) == "table" and type(SandboxVars.ALife) == "table" then
        percent = tonumber(SandboxVars.ALife.Ammo_SpawnPercent) or 100
        loads = tonumber(SandboxVars.ALife.Ammo_ReserveLoads) or 0
    end
    return math.max(0, percent), math.max(0, math.floor(loads))
end

function Magazines.reserveCap(item)
    local _, loads = Magazines.limits()
    if loads <= 0 then return nil end
    local capacity = magMaximum(item)
    if capacity <= 0 then capacity = 6 end
    return loads * capacity
end

function Magazines.spawnTotal(shell, total, capacity, item)
    if total <= 0 or Magazines.isInfinite(shell) then return total end
    local percent = Magazines.limits()
    total = math.max(math.min(total, capacity), math.floor(total * percent / 100))
    local cap = Magazines.reserveCap(item)
    if cap ~= nil then total = math.min(total, capacity + cap) end
    return total
end

function Magazines.initialize(shell, item, slot, amount, mode)
    local capacity = magMaximum(item)
    if capacity <= 0 then return false, math.max(0, tonumber(amount) or 0) end
    slot = slot == "secondary" and "secondary" or "primary"
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local total = mode == "magazines" and amount * capacity or amount
    if Magazines.isInfinite(shell) then total = math.max(total, capacity) end
    total = Magazines.spawnTotal(shell, total, capacity, item)
    local loaded = math.min(capacity, total)
    local feed = Magazines.feed(item)
    local external = feed == "detachable"
    local ok = pcall(function()
        item:setContainsClip(external and loaded > 0)
    end)
    ok = ok and magSetCurrent(item, loaded)
    if not ok then return false, total end
    storeReserve(magMetadata(shell), slot, total - loaded, capacity, feed)
    return true, math.max(0, total - loaded)
end

function Magazines.canReload(shell, item)
    local capacity = magMaximum(item)
    if capacity <= 0 or magCurrent(item) >= capacity then return false end
    return Magazines.isInfinite(shell)
        or Magazines.reserve(shell, magEquippedSlot(shell, item), item) > 0
end

function Magazines.beginReload(shell, item)
    if shell == nil or item == nil then return nil, "reload_missing" end
    local capacity, current = magMaximum(item), magCurrent(item)
    if capacity <= 0 then return nil, "reload_not_firearm" end
    if current >= capacity then return nil, "reload_full" end
    local slot = magEquippedSlot(shell, item)
    local infinite = Magazines.isInfinite(shell)
    local reserve = infinite and capacity or Magazines.reserve(shell, slot, item)
    if reserve <= 0 then return nil, "reload_empty" end
    local external = usesExternalMagazine(item)
    local rounds = math.min(capacity - current, reserve)
    if not external then
        local insertAll = Magazines.ask(item, "isInsertAllBulletsReload") == true

        local reload = string.lower(tostring(Magazines.ask(item, "getWeaponReloadType") or ""))
            :gsub("[^a-z]", "")
        if FILL_TO_CAPACITY[reload] then insertAll = true end
        if not insertAll then rounds = math.min(1, rounds) end
    end
    return {
        shell = shell, item = item, slot = slot, capacity = capacity,
        rounds = rounds, infinite = infinite, external = external,
        internal = not external, committed = false,
    }
end

function Magazines.commitReload(transaction)
    if type(transaction) ~= "table" or transaction.committed == true then
        return false, "reload_transaction_invalid"
    end
    local current = magCurrent(transaction.item)
    local loaded = math.min(transaction.capacity,
        current + math.max(0, math.floor(tonumber(transaction.rounds) or 0)))
    local used = loaded - current
    if used <= 0 then return false, "reload_nothing_inserted" end
    local ok = pcall(function()
        transaction.item:setContainsClip(transaction.external and loaded > 0)
    end)
    ok = ok and magSetCurrent(transaction.item, loaded)
    if not ok then return false, "reload_weapon_write_failed" end
    if not transaction.infinite then
        local reserve = Magazines.reserve(transaction.shell, transaction.slot, transaction.item)
        storeReserve(magMetadata(transaction.shell), transaction.slot,
            math.max(0, reserve - used), transaction.capacity,
            Magazines.feed(transaction.item))
    end
    transaction.committed, transaction.loaded = true, used
    return true, used
end

function Magazines.consumeRound(shell, item)
    local current = magCurrent(item)
    if current <= 0 then return false end
    if Magazines.isInfinite(shell) then return true end
    return magSetCurrent(item, current - 1)
end

function Magazines.snapshot(shell)
    local data = magMetadata(shell)
    if data == nil then return nil end
    return {
        primary = math.max(0, tonumber(data.ProjectALifePrimaryAmmoUnits) or 0),
        secondary = math.max(0, tonumber(data.ProjectALifeSecondaryAmmoUnits) or 0),
        primaryCapacity = math.max(0, tonumber(data.ProjectALifePrimaryMagazineCapacity) or 0),
        secondaryCapacity = math.max(0, tonumber(data.ProjectALifeSecondaryMagazineCapacity) or 0),
        infinite = Magazines.isInfinite(shell), equippedSlot = data.ProjectALifeEquippedSlot,
    }
end

function Magazines.restore(shell, state)
    if type(state) ~= "table" then return false end
    local data = magMetadata(shell)
    if data == nil then return false end
    storeReserve(data, "primary", state.primary, state.primaryCapacity, nil)
    storeReserve(data, "secondary", state.secondary, state.secondaryCapacity, nil)
    if state.infinite ~= nil then data.ProjectALifeInfiniteAmmo = state.infinite == true end
    data.ProjectALifeEquippedSlot = state.equippedSlot or data.ProjectALifeEquippedSlot
    return true
end

local Weapons = { adapters = {} }
ProjectALife.Weapons = Weapons
local Jamming = ProjectALife.WeaponJamming or {}
ProjectALife.WeaponJamming = Jamming

local function variable(shell, name)
    local dataOk, data = pcall(function() return shell:getModData() end)
    if dataOk and type(data) == "table" then
        local value = data["Project" .. name]
        if value ~= nil then return value end
    end
    local ok, value = pcall(function() return shell:GetVariable(name) end)
    return ok and value or nil
end

local function metadata(shell)
    local data = Magazines.ask(shell, "getModData")
    return type(data) == "table" and data or nil
end

local function items(shell)
    return Magazines.ask(Magazines.ask(shell, "getInventory"), "getItems")
end

local function isWeapon(item)
    return Magazines.ask(item, "IsWeapon") == true
end

local function itemData(item)
    local data = Magazines.ask(item, "getModData")
    return type(data) == "table" and data or nil
end

local function maximumAmmo(item)
    return math.max(0, tonumber(Magazines.ask(item, "getMaxAmmo")) or 0)
end

local function reloadType(item)
    return (string.lower(tostring(Magazines.ask(item, "getWeaponReloadType") or "")):gsub("[^a-z]", ""))
end

function Jamming.isRevolver(item)
    if item == nil then return false end
    if string.find(reloadType(item), "revolver", 1, true) then return true end
    return string.find(string.lower(tostring(Magazines.ask(item, "getFullType") or "")),
        "revolver", 1, true) ~= nil
end

function Weapons.isRevolver(item)
    return Jamming.isRevolver(item)
end

function Weapons.isAutomatic(item)
    if item == nil then return false end
    local mode = Magazines.ask(item, "getFireMode")
    if string.lower(tostring(mode or "")) ~= "auto" then return false end

    local modes = Magazines.ask(item, "getFireModePossibilities")
    if modes == nil then return false end
    for index = 0, modes:size() - 1 do
        if string.lower(tostring(modes:get(index) or "")) == "auto" then return true end
    end
    return false
end

function Weapons.selectFireMode(item, wanted)
    if item == nil or type(wanted) ~= "string" then return false end
    local modes = Magazines.ask(item, "getFireModePossibilities")
    if modes == nil then return false end
    local available = false
    for index = 0, modes:size() - 1 do
        if tostring(modes:get(index) or "") == wanted then
            available = true
            break
        end
    end
    if not available then return false end
    if tostring(Magazines.ask(item, "getFireMode") or "") == wanted then return true end
    if item.setFireMode == nil or item.setAmmoPerShoot == nil then return false end
    item:setFireMode(wanted)
    item:setAmmoPerShoot(wanted == "Burst" and 3 or 1)
    return true
end

function Weapons.applyFiringDoctrine(shell, item)
    if shell == nil or item == nil then return false end
    local data = Magazines.ask(shell, "getModData")
    local conduct = type(data) == "table" and tostring(data.ProjectALifeConduct or "") or ""
    local wanted = conduct == "sniper" and "Single" or "Auto"
    if not Weapons.selectFireMode(item, wanted) then return false end
    if shell.setFireMode ~= nil then shell:setFireMode(wanted) end
    return true
end

function Weapons.firesPellets(item)
    if item == nil then return false end
    return (tonumber(Magazines.ask(item, "getProjectileCount")) or 1) > 1
end

function Weapons.racksAfterShot(item)
    if item == nil or Jamming.isRevolver(item) then return false end

    return Magazines.ask(item, "isRackAfterShoot") == true
end

function Weapons.racksAfterReload(item)
    if item == nil or maximumAmmo(item) <= 0 then
        return false
    end

    if Jamming.isRevolver(item) then return true end
    local reload = reloadType(item)
    if string.find(reload, "doublebarrel", 1, true) then return false end
    return usesExternalMagazine(item) or Weapons.racksAfterShot(item)
        or string.find(reload, "handgun", 1, true) ~= nil
end

function Weapons.fireIntervalMs(item)
    if Weapons.isAutomatic(item) then
        local multiplier = tonumber(Magazines.ask(item, "getCyclicRateMultiplier")) or 1
        multiplier = math.max(0.25, math.min(4, multiplier))
        return math.max(90, math.min(180, math.floor(120 / multiplier)))
    end
    local delay = tonumber(Magazines.ask(item, "getRecoilDelay"))
    return math.max(480, math.min(1500,
        math.floor((delay or 18) * 34)))
end

function Jamming.isJammed(item)
    return Magazines.ask(item, "isJammed") == true
end

function Jamming.try(shell, item, enabled, chancePercent, suppliedRoll)
    if enabled == false or item == nil or maximumAmmo(item) <= 0
            or Jamming.isRevolver(item) or Jamming.isJammed(item) then
        return false
    end
    local chance = math.max(0, math.min(25, tonumber(chancePercent) or 0))
    if chance <= 0 then return false end
    local roll = tonumber(suppliedRoll)
    if roll == nil and type(Weapons.adapters.randomPercent) == "function" then
        local ok, value = pcall(Weapons.adapters.randomPercent, item, shell)
        if ok then roll = tonumber(value) end
    end
    if roll == nil and type(ZombRand) == "function" then
        roll = ZombRand(10000) / 100
    end
    if roll == nil then return false end
    if roll >= chance then return false end
    local changed = pcall(function() item:setJammed(true) end)
    if not changed then return false end
    local data = metadata(shell)
    if data ~= nil then
        local typeOk, itemType = pcall(function() return item:getFullType() end)
        data.ProjectALifeWeaponJamCount =
            math.max(0, tonumber(data.ProjectALifeWeaponJamCount) or 0) + 1
        data.ProjectALifeWeaponJammed = true
        data.ProjectALifeWeaponJamType = typeOk and tostring(itemType) or nil
        data.ProjectALifeWeaponJamAtMs = type(getTimestampMs) == "function"
            and getTimestampMs() or math.floor(os.time() * 1000)
    end
    return true
end

function Jamming.clear(shell, item)
    if item == nil then return false end
    local cleared = pcall(function() item:setJammed(false) end)
    if not cleared then return false end
    local data = metadata(shell)
    if data ~= nil then
        data.ProjectALifeWeaponJammed = false
        data.ProjectALifeWeaponJamClearedAtMs = type(getTimestampMs) == "function"
            and getTimestampMs() or math.floor(os.time() * 1000)
        data.ProjectALifeWeaponJamClearCount =
            math.max(0, tonumber(data.ProjectALifeWeaponJamClearCount) or 0) + 1
    end
    return true
end

local function weaponClass(item, fullType)
    local lowered = string.lower(tostring(fullType or ""))
    if string.find(lowered, "pistol", 1, true)
            or string.find(lowered, "revolver", 1, true) then return "handgun" end
    if string.find(lowered, "rifle", 1, true)
            or string.find(lowered, "shotgun", 1, true) then return "rifle" end
    if string.find(lowered, "spear", 1, true) then return "spear" end
    local ranged
    if item ~= nil and item.isAimedFirearm ~= nil then ranged = item:isAimedFirearm()
    else ranged = Magazines.ask(item, "isRanged") end
    if ranged == true then return "rifle" end
    return "melee"
end

function Weapons.configure(adapters)
    Weapons.adapters = adapters or {}
end

function Weapons.load(item, available)
    local maximum = item and maximumAmmo(item) or 0
    if maximum <= 0 then return false, math.max(0, tonumber(available) or 0) end
    local rounds = math.min(maximum, math.max(0, math.floor(tonumber(available) or 0)))
    pcall(function() item:setContainsClip(true) end)
    local ok = magSetCurrent(item, rounds)
    return ok, ok and math.max(0, (tonumber(available) or 0) - rounds)
        or math.max(0, tonumber(available) or 0)
end

function Weapons.slot(item)
    local data = itemData(item)
    return data and data.ProjectALifeWeaponSlot or nil
end

function Weapons.firearmsAllowed(shell)
    local data, stamp = metadata(shell), nil
    if data ~= nil then stamp = data.ProjectALifeFirearmsAuthored end
    if stamp == nil and shell ~= nil and shell.GetVariable ~= nil then
        stamp = shell:GetVariable("ALifeFirearmsAuthored")
    end
    return stamp ~= false and stamp ~= "false"
end

function Weapons.barred(shell, item, allowed)
    if allowed == nil then allowed = Weapons.firearmsAllowed(shell) end
    if allowed or item == nil or maximumAmmo(item) <= 0 then return false end
    local data = itemData(item)
    return data == nil or data.ProjectALifeWeaponSlot ~= "melee"
end

local function rangedPreference(item, shell)
    if item == nil then return 0 end
    local firearm = Magazines.ask(item, "isAimedFirearm") == true
    if not firearm and item.isRanged ~= nil then
        firearm = item:isRanged() == true
            or (tonumber(Magazines.ask(item, "getMaxAmmo")) or 0) > 0
    end
    if not firearm then return 1 end
    local loaded = tonumber(Magazines.current(item)) or 0
    if loaded > 0 then return 3 end

    local reloadable = false
    if shell ~= nil then
        reloadable = Magazines.canReload(shell, item) == true
            or Magazines.isInfinite(shell) == true
    else

        reloadable = true
    end
    if reloadable then return 2 end

    return 0
end

function Weapons.current(shell)
    local list = items(shell)
    if list == nil then return nil end
    local count = Magazines.ask(list, "size")
    if count == nil then return nil end
    local fallback, fallbackRank
    local allowed = Weapons.firearmsAllowed(shell)
    for index = 0, count - 1 do
        local item = list:get(index)
        if isWeapon(item) and not Weapons.barred(shell, item, allowed) then
            local rank = rangedPreference(item, shell)
            if fallback == nil or rank > fallbackRank then
                fallback, fallbackRank = item, rank
            end
            local data = itemData(item)
            if data and data.ProjectALifeActiveWeapon == true then return item end
        end
    end
    return fallback
end

function Weapons.select(shell, selected, slot)
    local list = items(shell)
    if list == nil then return false end
    local count = Magazines.ask(list, "size")
    if count == nil then return false end

    if Weapons.barred(shell, selected) then selected = nil end
    for index = 0, count - 1 do
        local item = list:get(index)
        if isWeapon(item) then
            local data = itemData(item)
            if data then data.ProjectALifeActiveWeapon = item == selected end
        end
    end
    if selected == nil then return false end
    local selectedData = itemData(selected)
    if selectedData then
        selectedData.ProjectALifeWeaponSlot = slot or selectedData.ProjectALifeWeaponSlot
        selectedData.ProjectALifeActiveWeapon = true
    end
    local shellData = metadata(shell)
    if shellData then
        shellData.ProjectALifeEquippedSlot = slot or Weapons.slot(selected) or "primary"
        local typeOk, fullType = pcall(function() return selected:getFullType() end)
        shellData.ProjectALifeActiveWeaponType = typeOk and fullType or nil
        shellData.ProjectALifeWeaponClass = weaponClass(
            selected, typeOk and fullType or nil)
    end

    return true
end

local function fullType(item)
    if item == nil or item.getFullType == nil then return "" end
    local value = item:getFullType()
    return tostring(value)
end

local function meleePower(item)
    return tonumber(Magazines.ask(item, "getMaxDamage")) or 0
end

function Weapons.bestMelee(shell)
    local list = items(shell)
    if list == nil then return nil end
    local count = Magazines.ask(list, "size")
    if count == nil then return nil end
    local best, bestPower
    for index = 0, count - 1 do
        local item = list:get(index)
        if isWeapon(item) and maximumAmmo(item) == 0
                and fullType(item) ~= "Base.BareHands" then
            local power = meleePower(item)
            local condition = tonumber(Magazines.ask(item, "getCondition"))
            if power > 0 and (condition == nil or condition > 0)
                    and (best == nil or power > bestPower) then best, bestPower = item, power end
        end
    end
    return best
end

function Weapons.bestReloadableRanged(shell)
    local list = items(shell)
    if list == nil then return nil end
    local count = Magazines.ask(list, "size")
    if count == nil then return nil end

    local best, bestRank
    local allowed = Weapons.firearmsAllowed(shell)
    for index = 0, count - 1 do
        local item = list:get(index)
        if isWeapon(item) and maximumAmmo(item) > 0 and not Weapons.barred(shell, item, allowed) then
            if Magazines.current(item) > 0
                    or Magazines.canReload(shell, item) then
                local rank = rangedPreference(item, shell)
                if best == nil or rank > bestRank then best, bestRank = item, rank end
            end
        end
    end
    return best
end

local function equipMelee(shell)
    local list = items(shell)
    if list == nil then return false end
    local count = Magazines.ask(list, "size")
    if count == nil then return false end

    local best, bestPower
    for index = 0, count - 1 do
        local item = list:get(index)
        if isWeapon(item) and maximumAmmo(item) == 0 then
            local bare = fullType(item) == "Base.BareHands"
            local power = bare and -1 or meleePower(item)
            if best == nil or power > bestPower then best, bestPower = item, power end
        end
    end
    if best == nil then return false end
    return Weapons.select(shell, best, Weapons.slot(best) or "melee")
end

function Weapons.ensureReady(shell)
    if type(Weapons.adapters.ensureReady) == "function" then
        return Weapons.adapters.ensureReady(shell) ~= false
    end
    local item = Weapons.current(shell)
    if item == nil then return true end
    local maximum = maximumAmmo(item)
    if maximum <= 0 then return true end

    if Magazines.current(item) > 0 then return true end

    if Magazines.canReload(shell, item) then return true end
    return equipMelee(shell)
end

function Weapons.addReserve(shell, slot, rounds)
    rounds = math.floor(tonumber(rounds) or 0)
    if shell == nil or rounds <= 0 then return 0 end
    pcall(function() shell:getModData().ProjectALifeDryUntilMs = nil end)
    slot = (slot == "secondary") and "secondary" or "primary"
    local total = 0
    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        local key = slot == "secondary"
            and "ProjectALifeSecondaryAmmoUnits" or "ProjectALifePrimaryAmmoUnits"
        total = math.max(0, math.floor(tonumber(data[key]) or 0)) + rounds
        data[key] = total
    end)
    return total
end

function Weapons.ammoValue(item)
    if item == nil then return 0 end
    local rounds = 0
    pcall(function()

        if item:IsWeapon() == true then return end
        local lowered = string.lower(tostring(item:getFullType() or ""))
        local bare = string.gsub(lowered, "^base%.", "")

        if item.getCurrentAmmoCount ~= nil then
            local held = tonumber(item:getCurrentAmmoCount()) or 0
            if held > 0 then rounds = held return end
        end

        local boxed = {
            bullets9mmbox = 50, bullets38box = 50, bullets357box = 50,
            bullets45box = 50, bullets44box = 20,
            bullets9mmcarton = 600, bullets38carton = 600, bullets357carton = 600,
            bullets45carton = 600, bullets44carton = 240,
            ["556box"] = 20, ["556carton"] = 240,
            ["308box"] = 20, ["308carton"] = 240,
            ["3030box"] = 20, ["3030carton"] = 240,
            ["223box"] = 20, ["223carton"] = 240,
            shotgunshellsbox = 25, shotgunshellscarton = 300,
        }
        local named = boxed[bare]
        if named ~= nil then rounds = named return end
        local loose = {
            bullets9mm = true, bullets38 = true, bullets44 = true,
            bullets45 = true, ["556bullets"] = true, ["308bullets"] = true,
            ["3030bullets"] = true, ["223bullets"] = true,
            shotgunshells = true, bullets357 = true,
        }
        if loose[bare] == true then rounds = 1 end
    end)
    return rounds
end

function Weapons.roundKey(object)
    if object == nil then return nil end
    local ammoType = Magazines.ask(object, "getAmmoType")
    local key = nil
    if type(ammoType) == "string" then
        key = ammoType
    elseif ammoType ~= nil then
        key = Magazines.ask(ammoType, "getItemKey") or tostring(ammoType)
    elseif not isWeapon(object) then
        key = fullType(object)
    end
    if key == nil or tostring(key) == "" then return nil end
    key = string.lower(tostring(key))
    key = string.gsub(key, "^.*[:%.]", "")
    key = string.gsub(string.gsub(key, "carton$", ""), "box$", "")
    key = string.gsub(string.gsub(key, "bullets", ""), "shells", "")
    key = string.gsub(key, "[^%w]", "")
    if key == "" then return nil end
    return key
end

function Weapons.ammoFits(item, gun)
    if item == nil or gun == nil then return false end
    local magazine = Magazines.ask(gun, "getMagazineType")
    if magazine ~= nil and string.lower(tostring(magazine)) == string.lower(fullType(item)) then
        return true
    end
    local wanted = Weapons.roundKey(gun)
    if wanted == nil then return true end
    return Weapons.roundKey(item) == wanted
end

function Weapons.creditFor(shell, item)
    local rounds = Weapons.ammoValue(item)
    if rounds <= 0 then return "primary", 0 end
    local list = items(shell)
    local count = list ~= nil and Magazines.ask(list, "size") or nil
    if count == nil then return "primary", 0 end
    local held = Weapons.current(shell)
    local best = nil
    for index = 0, count - 1 do
        local gun = list:get(index)
        if isWeapon(gun) and maximumAmmo(gun) > 0 and Weapons.ammoFits(item, gun)
                and (best == nil or gun == held) then
            best = gun
        end
    end
    if best == nil then return "primary", 0 end
    local slot = Weapons.slot(best)
    if slot ~= "primary" and slot ~= "secondary" then
        slot = best == held and magEquippedSlot(shell, best) or "primary"
    end
    local cap = Magazines.reserveCap(best)
    if cap ~= nil and Magazines.reserve(shell, slot, best) + rounds > cap then return slot, 0 end
    return slot, rounds
end

function Magazines.setLoaded(item, rounds)
    return magSetCurrent(item, rounds)
end

function Weapons.beginReload(shell, item)
    return Magazines.beginReload(shell, item or Weapons.current(shell))
end

return Weapons
