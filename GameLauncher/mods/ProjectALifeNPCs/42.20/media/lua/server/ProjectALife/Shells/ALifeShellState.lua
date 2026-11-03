require "ProjectALife/Combat/ALifeWeapons"

require "ProjectALife/Shells/ALifeDeathInventory"

ProjectALife = ProjectALife or {}

local ShellState = { maximumWeapons = 8, maximumCarriedItems = 24 }
ProjectALife.ShellState = ShellState
local Weapons = ProjectALife.Weapons
local Magazines = ProjectALife.MagazineState

local function itemType(item)
    if item == nil or item.getFullType == nil then return nil end
    local value = item:getFullType()
    return type(value) == "string" and value or nil
end

local function isWeapon(item)
    return item ~= nil and item.IsWeapon ~= nil and item:IsWeapon() == true
end

local function itemState(item)
    local state = { type = itemType(item) }
    if state.type == nil then return nil end
    pcall(function() state.scavenged = item:getModData().ProjectALifeScavenged == true end)
    pcall(function()
        local data = item:getModData()
        state.recoveredFrom = data.ProjectALifeRecoveredFrom
        state.recoveredItemID = data.ProjectALifeRecoveredItemID
        if state.recoveredFrom then state.recoveredName = item:getName() end
    end)
    local ok, value = pcall(function() return item:getCondition() end)
    if ok then state.condition = tonumber(value) end
    pcall(function()
        if item:getModData().ProjectALifeBreakOnDrop == true then state.breakOnDrop = true end
    end)

    ok, value = pcall(function() return item:getCurrentAmmoCount() end)
    if ok then state.ammo = tonumber(value) end
    if isWeapon(item) then
        ok, value = pcall(function() return item:getAllWeaponParts() end)
        if ok and value ~= nil then
            state.parts = {}
            pcall(function()
                for index = 0, math.min(value:size(), 8) - 1 do
                    local part = value:get(index)
                    local kind = itemType(part)
                    if kind ~= nil then
                        state.parts[#state.parts + 1] = { type = kind,
                            condition = tonumber(part:getCondition()) }
                    end
                end
            end)
        end
        ok, value = pcall(function() return item:isContainsClip() end)
        if ok then state.containsClip = value == true end
        ok, value = pcall(function() return item:isRoundChambered() end)
        if ok then state.roundChambered = value == true end
        ok, value = pcall(function() return item:isJammed() end)
        if ok then state.jammed = value == true end
    end
    ok, value = pcall(function() return item:getCurrentUsesFloat() end)
    if ok then state.currentUses = tonumber(value) end
    return state
end

function ShellState.restoreBroken(item)
    local policy = ProjectALife.DropPolicy
    if policy ~= nil and type(policy.hasBreakHandler) == "function" and policy.hasBreakHandler(item) then
        item:setCondition(1)
        return "floored"
    end
    if type(item.setConditionWhileLoading) == "function" then
        item:setConditionWhileLoading(0)
        return "loading"
    end
    if policy ~= nil and type(policy.issue) == "function" then
        policy.issue(item, 0)
        return "flag"
    end
    item:setCondition(1)
    item:getModData().ProjectALifeBreakOnDrop = true
    return "flag"
end

local function applyItemState(item, state, parts, intoShell)
    if type(state.recoveredFrom) == "string" then
        pcall(function()
            local data = item:getModData()
            data.ProjectALifeRecoveredFrom = state.recoveredFrom
            data.ProjectALifeRecoveredItemID = state.recoveredItemID
            if type(state.recoveredName) == "string" then item:setName(state.recoveredName) end
        end)
    end
    if state.scavenged == true then
        pcall(function() item:getModData().ProjectALifeScavenged = true end)
    end
    if tonumber(state.condition) then
        pcall(function()
            if intoShell == true and tonumber(state.condition) <= 0 then
                ShellState.restoreBroken(item)
            else

                local restored, policy = math.max(0, math.floor(state.condition)), ProjectALife.DropPolicy
                if policy ~= nil and type(policy.breakSafe) == "function" then restored = policy.breakSafe(item, restored) end
                item:setCondition(restored)
                if state.breakOnDrop == true then item:getModData().ProjectALifeBreakOnDrop = true end
            end

            item:getModData().ProjectALifeIssuedCondition = true
        end)
    end
    for index, saved in ipairs(parts or (type(state.parts) == "table" and state.parts or {})) do
        if index > 8 then break end
        local ok, attached = pcall(function()
            local part = instanceItem(saved.type)
            if part == nil then return false end
            if tonumber(saved.condition) then
                local kept, policy = saved.condition, ProjectALife.DropPolicy
                if policy ~= nil and type(policy.breakSafe) == "function" then kept = policy.breakSafe(part, kept) end
                part:setCondition(kept)
            end
            item:attachWeaponPart(part, true)
            return true
        end)
        if not ok or not attached then return false end
    end
    if tonumber(state.ammo) then
        pcall(function() item:setCurrentAmmoCount(math.max(0, math.floor(state.ammo))) end)
    end
    if tonumber(state.ammo) and isWeapon(item) then

        pcall(function() item:setContainsClip(state.containsClip == true
            or (state.containsClip == nil and state.ammo > 0)) end)
        pcall(function() item:setRoundChambered(state.roundChambered == true
            or (state.roundChambered == nil and state.ammo > 0)) end)
        pcall(function() item:setJammed(state.jammed == true) end)
    end
    if tonumber(state.currentUses) then
        pcall(function() item:setCurrentUsesFloat(math.max(0, state.currentUses)) end)
    end
    return true
end

ShellState.captureItem = itemState
function ShellState.createItem(saved)
    local fullType = type(saved) == "table" and saved.type or saved
    if type(fullType) ~= "string" or fullType == "" then return nil end
    local ok, item = pcall(instanceItem, fullType)
    if not ok or item == nil then return nil end
    if type(saved) == "table" and not applyItemState(item, saved) then return nil end
    return item
end

function ShellState.markScavenged(item)
    if item == nil then return false end
    local ok = pcall(function()
        item:getModData().ProjectALifeScavenged = true
    end)
    return ok
end

function ShellState.noteForeignRemoval(container, item, by, at)
    if item == nil or container == nil then return 0 end
    if type(isClient) == "function" and isClient() then return 0 end
    local weapons = {}
    if isWeapon(item) then weapons[1] = item end
    pcall(function()
        if not instanceof(item, "InventoryContainer") or item.getInventory == nil then return end
        local inner = item:getInventory():getItems()
        for index = 0, math.min(inner:size(), 64) - 1 do
            local packed = inner:get(index)
            if isWeapon(packed) then weapons[#weapons + 1] = packed end
        end
    end)
    if #weapons == 0 then return 0 end
    local owner, holder = "world", nil
    pcall(function()
        local character = container:getCharacter()
        if character ~= nil and instanceof(character, "IsoZombie") then
            owner = "npc"
        elseif character ~= nil and instanceof(character, "IsoPlayer") then
            owner, holder = "player:" .. tostring(character:getUsername()), character
        else
            holder = container:getOutermostContainer():getParent()
            if holder ~= nil and instanceof(holder, "IsoDeadBody") then owner = "corpse"
            elseif holder ~= nil and instanceof(holder, "BaseVehicle") then owner = "vehicle" end
        end
    end)
    if owner == "npc" then return 0 end
    local kind, uid, place = "?", "-", "?"
    pcall(function() kind = tostring(container:getType()) end)
    if at ~= nil then
        pcall(function() uid = tostring(at:getModData().ProjectALifeUID or "-") end)
    end
    local point = holder or at
    if point ~= nil then
        pcall(function()
            place = tostring(math.floor(point:getX())) .. "," .. tostring(math.floor(point:getY()))
                .. "," .. tostring(math.floor(point:getZ()))
        end)
    end
    for _, weapon in ipairs(weapons) do
        local id = "?"
        pcall(function() id = tostring(weapon:getID()) end)
        print("[ALIFE-ITEMS] foreign_weapon_removed by=" .. tostring(by) .. " item=" .. tostring(itemType(weapon))
            .. " id=" .. id .. " owner=" .. owner .. " container=" .. kind .. " at=" .. place .. " actor=" .. uid)
    end
    return #weapons
end

local function scavenged(item)
    if item == nil or item.getModData == nil then return false end
    local data = item:getModData()
    return type(data) == "table" and data.ProjectALifeScavenged == true
end

function ShellState.capture(shell)
    if shell == nil then return nil, "shell_state_missing" end
    local state = { version = 1, weapons = {}, carried = {} }
    local dataOk, data = pcall(function() return shell:getModData() end)
    if dataOk and type(data) == "table" then state.reserve = Magazines.snapshot(shell) end
    local healthOk, health = pcall(function() return shell:getHealth() end)
    if not healthOk then return nil, "shell_health_unavailable" end
    state.health = tonumber(health)
    if dataOk and type(data) == "table" then
        state.maximumHealth = tonumber(data.ProjectALifeMaximumHealth)
    end
    local inventoryOk, inventory = pcall(function() return shell:getInventory() end)
    local itemsOk, items = pcall(function() return inventory and inventory:getItems() end)
    if not inventoryOk or not itemsOk or items == nil then
        return nil, "shell_inventory_unavailable"
    end
    local primary = Weapons.current(shell)
    local countOk, count = pcall(function() return items:size() end)
    if not countOk then return nil, "shell_inventory_unavailable" end

    local carried = {}
    local scavenging = ProjectALife.Scavenging
    if scavenging ~= nil and type(scavenging.carried) == "function" then
        carried = scavenging.carried(shell, inventory)
    end
    if #carried == 0 then
        for index = 0, count - 1 do carried[#carried + 1] = items:get(index) end
    end
    for _, item in ipairs(carried) do
        if isWeapon(item) and #state.weapons < ShellState.maximumWeapons then
            local value = itemState(item)
            if value then
                value.equipped = item == primary
                value.slot = Weapons.slot(item)
                state.weapons[#state.weapons + 1] = value
            end
        elseif scavenged(item) and #state.carried < ShellState.maximumCarriedItems then
            local value = itemState(item)
            if value then state.carried[#state.carried + 1] = value end
        end
    end
    return state
end

local function inventoryWeapons(items)
    local result = {}
    local countOk, count = pcall(function() return items:size() end)
    if not countOk then return result end
    for index = 0, count - 1 do
        local item = items:get(index)
        if isWeapon(item) then result[#result + 1] = item end
    end
    return result
end

function ShellState.apply(shell, state)
    if state == nil then return true, 0 end
    if type(state) ~= "table" or tonumber(state.version) ~= 1 then
        return false, "shell_state_version_invalid"
    end
    local inventoryOk, inventory = pcall(function() return shell:getInventory() end)
    local itemsOk, items = pcall(function() return inventory and inventory:getItems() end)
    if not inventoryOk or not itemsOk or items == nil then
        return false, "shell_inventory_unavailable"
    end
    local errors = 0
    if tonumber(state.health) then
        local restoredHealth = tonumber(state.health)
        local dataOk, data = pcall(function() return shell:getModData() end)
        local currentMaximum = dataOk and type(data) == "table"
            and tonumber(data.ProjectALifeMaximumHealth) or nil
        if currentMaximum ~= nil then
            if tonumber(state.maximumHealth) and state.maximumHealth > 0 then
                restoredHealth = currentMaximum * math.max(0,
                    math.min(1, restoredHealth / state.maximumHealth))
            elseif currentMaximum > 10 and restoredHealth <= 10 then

                restoredHealth = restoredHealth * 20
            end
        end
        local ok = pcall(function()
            local value = math.max(0.01, restoredHealth)
            if currentMaximum then value = math.min(value, currentMaximum) end
            if ProjectALife.ShellSimulation then ProjectALife.ShellSimulation.setHealth(shell, value)
            else shell:setHealth(value) end
        end)
        if not ok then errors = errors + 1 end
    end

    if type(state.reserve) == "table" and not Magazines.restore(shell, state.reserve) then
        errors = errors + 1
    end

    if type(state.weapons) == "table" then
        local existing, created = inventoryWeapons(items), {}
        local complete = true
        for index, saved in ipairs(state.weapons) do
            if index > ShellState.maximumWeapons then break end
            local ok, item = pcall(function() return inventory:AddItem(saved.type) end)
            if not ok or item == nil or not isWeapon(item) then
                complete = false
                errors = errors + 1
                break
            end
            created[#created + 1] = {
                item = item, equipped = saved.equipped == true, slot = saved.slot,
            }
            local parts = saved.parts
            if parts == nil then

                for _, issued in ipairs(existing) do
                    if itemType(issued) == saved.type then parts = itemState(issued).parts break end
                end
            end
            if not applyItemState(item, saved, parts, true) then
                complete = false
                errors = errors + 1
                break
            end
            local itemDataOk, itemData = pcall(function() return item:getModData() end)
            if itemDataOk and type(itemData) == "table" then
                itemData.ProjectALifeWeaponSlot = saved.slot
            end
        end
        if complete then
            for _, item in ipairs(existing) do pcall(function() inventory:Remove(item) end) end
            pcall(function() ProjectALife.DeathInventory.clear(shell) end)
            local equipped, equippedSlot
            for _, entry in ipairs(created) do
                pcall(function() ProjectALife.DeathInventory.add(shell, entry.item) end)
                if entry.equipped or equipped == nil then
                    equipped, equippedSlot = entry.item, entry.slot
                end
            end
            Weapons.select(shell, equipped, equippedSlot)
        else
            for _, entry in ipairs(created) do pcall(function() inventory:Remove(entry.item) end) end
        end
    end

    for index, saved in ipairs(type(state.carried) == "table" and state.carried or {}) do
        if index > ShellState.maximumCarriedItems then break end
        local ok, item = pcall(function() return inventory:AddItem(saved.type) end)
        if ok and item ~= nil then
            applyItemState(item, saved, nil, true)
            ShellState.markScavenged(item)
            pcall(function() ProjectALife.DeathInventory.add(shell, item) end)
        else
            errors = errors + 1
        end
    end
    return true, errors
end

return ShellState
