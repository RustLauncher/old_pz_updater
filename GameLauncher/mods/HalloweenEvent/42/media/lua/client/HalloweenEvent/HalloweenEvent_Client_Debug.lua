-- ============================================================================
-- HalloweenEvent_Client_Debug.lua
-- B42.21+ debug context integration.
-- ============================================================================

require "ISUI/ISContextMenu"
require "HalloweenEvent/HalloweenEvent_Shared"
require "HalloweenEvent/HalloweenEvent_Client"

local HWE = HalloweenEvent
local Client = HWE.Client

local function debugMenuEnabled()
    return HWE.readSandbox().EnableDebugMenu ~= false
end

local function findClickedZombie(worldObjects)
    if not worldObjects then return nil end
    for _, object in ipairs(worldObjects) do
        if object and instanceof(object, "IsoZombie") and object:isAlive() then
            return object
        end
        if object and object.getSquare then
            local square = object:getSquare()
            local moving = square and square:getMovingObjects()
            if moving then
                for i = 0, moving:size() - 1 do
                    local movingObject = moving:get(i)
                    if movingObject and instanceof(movingObject, "IsoZombie") and movingObject:isAlive() then
                        return movingObject
                    end
                end
            end
        end
    end
    return nil
end

local function newMenu(parent)
    if ISContextMenu and type(ISContextMenu.getNew) == "function" then
        return ISContextMenu:getNew(parent)
    end
    if parent and type(parent.getNew) == "function" then
        return parent:getNew(parent)
    end
    return nil
end

local function addCommand(context, label, command, args, playerNum)
    context:addOption(label, nil, function()
        Client.dispatch(command, args or {}, playerNum)
    end)
end

local function getOrCreateSubmenu(parent, label, debugIcon)
    local option = parent:getOptionFromName(label)
    if option and option.subOption then
        return option, parent:getSubMenu(option.subOption)
    end

    if not option then
        option = debugIcon and parent:addDebugOption(label) or parent:addOption(label)
    end
    local sub = newMenu(parent)
    if not sub then return option, nil end
    parent:addSubMenu(option, sub)
    return option, sub
end

local function sortCostumes(a, b)
    return HWE.costumeName(a) < HWE.costumeName(b)
end

local function groupCostumes()
    local grouped = {}
    for _, category in ipairs(HWE.CostumeCategoryOrder or {}) do
        grouped[category] = {}
    end
    for _, costume in ipairs(HWE.Costumes or {}) do
        local category = costume.category or (costume.isMask and "Masks" or "Characters")
        grouped[category] = grouped[category] or {}
        grouped[category][#grouped[category] + 1] = costume
    end
    for _, list in pairs(grouped) do table.sort(list, sortCostumes) end
    return grouped
end

local function addCostumeAction(menu, costume, command, playerNum)
    if costume.debugGenderChoices then
        local _, choices = getOrCreateSubmenu(menu, HWE.costumeName(costume), false)
        if choices then
            for _, choice in ipairs({{"SpawnRandom",50}, {"SpawnMale",0}, {"SpawnFemale",100}}) do
                local chance = choice[2]
                choices:addOption(HWE.text(choice[1]), nil, function()
                    Client.dispatch(command, {CostumeID=costume.id, FemaleChance=chance}, playerNum)
                end)
            end
        end
        return
    end
    local label = HWE.text("SpawnCostume",HWE.costumeName(costume)) .. (costume.placeholder and HWE.text("BaseSuffix") or "")
    menu:addOption(label, nil, function()
        Client.dispatch(command, { CostumeID = costume.id }, playerNum)
    end)
end

local function costumeGroupMenu(parent, costume)
    if not costume.menuGroup then return parent end
    local _, group = getOrCreateSubmenu(parent, HWE.groupName(costume.menuGroup), false)
    return group
end

local function addCostumeTargetAction(menu, costume, argsBase, playerNum)
    local label = HWE.costumeName(costume) .. (costume.placeholder and HWE.text("BaseSuffix") or "")
    menu:addOption(label, nil, function()
        Client.dispatch("DressZombie", {
            OnlineID = argsBase.OnlineID,
            X = argsBase.X, Y = argsBase.Y, Z = argsBase.Z,
            CostumeID = costume.id
        }, playerNum)
    end)
end

local function addTargetMenu(zombieMenu, zombie, playerNum)
    if not zombie then return end
    local _, targetMenu = getOrCreateSubmenu(zombieMenu, HWE.text("DressTarget"), false)
    if not targetMenu then return end

    local onlineID = HWE.safeCall(zombie, "getOnlineID")
    local argsBase = {
        OnlineID = tonumber(onlineID),
        X = zombie:getX(), Y = zombie:getY(), Z = zombie:getZ()
    }

    local grouped = groupCostumes()
    for _, category in ipairs(HWE.CostumeCategoryOrder or {}) do
        local list = grouped[category]
        if list and #list > 0 then
            local _, sub = getOrCreateSubmenu(targetMenu, HWE.groupName(category), false)
            if sub then
                for _, costume in ipairs(list) do
                    local destination = costumeGroupMenu(sub, costume)
                    if destination then addCostumeTargetAction(destination, costume, argsBase, playerNum) end
                end
            end
        end
    end
end

local function addGalleryMenu(parent, playerNum)
    parent:addOption("Full-screen Costume Showcase", nil, function()
        require "HalloweenEvent/HalloweenEvent_CostumeShowcase"
        HWE.ShowCostumeShowcase()
    end)

    local _, gallery = getOrCreateSubmenu(parent, HWE.text("CostumeGallery"), false)
    if not gallery then return end

    -- Spawn ALL must remain first for quick validation of the whole registry.
    gallery:addOption(HWE.text("SpawnAllCostumes"), nil, function()
        Client.dispatch("SpawnAllCostumes", {}, playerNum)
    end)

    local costumes, masks = {}, {}
    for _, costume in ipairs(HWE.Costumes or {}) do
        if costume.isMask then masks[#masks + 1] = costume
        else costumes[#costumes + 1] = costume end
    end
    table.sort(costumes, sortCostumes)
    table.sort(masks, sortCostumes)
    for _, costume in ipairs(costumes) do
        local destination = gallery
        if costume.category == "Sports Costumes" then
            local _, sports = getOrCreateSubmenu(gallery, HWE.groupName("Sports Costumes"), false)
            destination = sports
        end
        if destination then destination = costumeGroupMenu(destination, costume) end
        if destination then addCostumeAction(destination, costume, "SpawnCostume", playerNum) end
    end
    if #masks > 0 then
        local _, maskMenu = getOrCreateSubmenu(gallery, HWE.groupName("Masks"), false)
        if maskMenu then
            for _, costume in ipairs(masks) do
                addCostumeAction(maskMenu, costume, "SpawnCostume", playerNum)
            end
        end
    end
end

local function addHWE(root, playerNum, zombie)
    local debugLabel = (type(getText) == "function" and getText("ContextMenu_Debug")) or "Debug"
    local debugOption = root:getOptionFromName(debugLabel) or root:getOptionFromName("Debug")
    local debugMenu

    if debugOption and debugOption.subOption then
        debugMenu = root:getSubMenu(debugOption.subOption)
    elseif debugOption then
        debugMenu = newMenu(root)
        if debugMenu then root:addSubMenu(debugOption, debugMenu) end
    else
        debugOption = root:addDebugOption(debugLabel)
        debugMenu = newMenu(root)
        if debugMenu then root:addSubMenu(debugOption, debugMenu) end
    end

    if not debugMenu then
        HWE.log("DEBUG_MENU_FAIL debugSubmenuUnavailable")
        return
    end

    local _, hweMenu = getOrCreateSubmenu(debugMenu, "HWE", true)
    if not hweMenu then
        HWE.log("DEBUG_MENU_FAIL hweSubmenuUnavailable")
        return
    end

    HWE.log("DEBUG_MENU_READY path=Debug/HWE")

    local _, eventMenu = getOrCreateSubmenu(hweMenu, HWE.text("EventControls"), false)
    if eventMenu then
        addCommand(eventMenu, HWE.text("StartEvent"), "StartEvent", {}, playerNum)
        addCommand(eventMenu, HWE.text("EndEvent"), "EndEvent", {}, playerNum)
        addCommand(eventMenu, HWE.text("AutoSchedule"), "ClearManualOverride", {}, playerNum)
        addCommand(eventMenu, HWE.text("EventStatus"), "Status", {}, playerNum)
        addCommand(eventMenu, HWE.text("ResetAnnouncements"), "ResetAnnouncements", {}, playerNum)
    end

    local _, zombieMenu = getOrCreateSubmenu(hweMenu, HWE.text("ZombieControls"), false)
    if zombieMenu then
        addCommand(zombieMenu, HWE.text("DressLoaded"), "DressNow", {}, playerNum)
        -- Test-only, explicit admin command; does not auto-run in normal play.
        addCommand(zombieMenu, "[TEST] Run 400-Zombie Persistence Matrix", "RunPersistenceMatrix", {}, playerNum)
        addCommand(zombieMenu, "[TEST] Persistence Matrix Results", "PersistenceMatrixStatus", {}, playerNum)
        addCommand(zombieMenu, "[TEST] Clear Persistence Matrix", "ClearPersistenceMatrix", {}, playerNum)
        addTargetMenu(zombieMenu, zombie, playerNum)
    end

    addGalleryMenu(hweMenu, playerNum)
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test or not context or not debugMenuEnabled() or not Client then return end
    addHWE(context, playerNum, findClickedZombie(worldObjects))
end

if Events and Events.OnFillWorldObjectContextMenu then
    Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
end

HWE.log("DEBUG_MENU_LOADED version=" .. HWE.VERSION .. " root=Debug/HWE")
return true
