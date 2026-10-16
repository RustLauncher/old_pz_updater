require "WaterRestoration/WR_GeneratorPanel"
require "WaterRestoration/WR_Requirements"
require "WaterRestoration/WR_Config"
require "WaterRestoration/WR_Actions"
require "WaterRestoration/WR_PlantPanel"
require "WaterRestoration/WR_Regions"
require "WaterRestoration/WR_StationPanel"

WR.ClientState = WR.ClientState or {}

local function requestState()
    if isClient() then
        sendClientCommand("WR", "requestState", {})
    elseif WR.Server then
        WR.Server.sendState(getPlayer())
    end
end

local function onServerCommand(module, command, args)
    if module ~= "WR" then return end
    if command == "state" and type(args) == "table" then
        WR.ClientState = args
        local ok,why=WR.Network.sync(args)
        if not ok then print("[WaterRestoration] Client regional zones pending: "..tostring(why)) end
    elseif command == "result" and args and args.message then
        WR.showResult(getPlayer(), args.message, args.remaining)
    elseif command=="openGenerator" then
        WR.GeneratorPanel.open(getPlayer(),{id="generator",kind="generator",x=args.x,y=args.y,z=0})
    elseif command=="openStation" then
        WR.StationPanel.open(getPlayer(),{id=args.target,x=args.x,y=args.y,z=args.z,kind="distributor"})
    elseif command == "openPanel" then
        WR.PlantPanel.open(getPlayer(), args.target or "central")
    end
end

local function addDisabled(context, label, description)
    local option = context:addOption(label, nil, nil)
    option.notAvailable = true
    if description then
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = description
        option.toolTip = tooltip
    end
    return option
end

local function queueInteraction(playerObj, target, command, duration)
    WR.queueInteraction(playerObj,target,command,duration)
end

local function requirementsText(playerObj, scrapNeeded)
    local req = WR.getRequirements()
    local inv = playerObj:getInventory()
    local electricity = playerObj:getPerkLevel(Perks.Electricity)
    local mechanics = playerObj:getPerkLevel(Perks.Mechanics)
    local strength = playerObj:getPerkLevel(Perks.Strength)
    local scrap = WR.countElectronicScrap(inv)
    local screwdriver = inv:containsTypeRecurse("Screwdriver")
    return string.format(
        "%s %d/%d\n%s %d/%d\n%s %d/%d\n%s %d/%d\n%s %s",
        getText("IGUI_WR_Electricity"), electricity, req.electricity,
        getText("IGUI_WR_Mechanics"), mechanics, req.mechanics,
        getText("IGUI_WR_Strength"), strength, req.strength,
        getText("IGUI_WR_ElectronicsScrap"), scrap, scrapNeeded,
        getText("IGUI_WR_Screwdriver"), screwdriver and getText("IGUI_WR_Yes") or getText("IGUI_WR_No")
    )
end

local function canRepair(playerObj, scrapNeeded)
    local req = WR.getRequirements()
    local inv = playerObj:getInventory()
    return playerObj:getPerkLevel(Perks.Electricity) >= req.electricity
        and playerObj:getPerkLevel(Perks.Mechanics) >= req.mechanics
        and playerObj:getPerkLevel(Perks.Strength) >= req.strength
        and WR.countElectronicScrap(inv) >= scrapNeeded
        and inv:containsTypeRecurse("Screwdriver")
end

local function allCompleted(state, ids)
    for _, id in ipairs(ids) do
        if not state[id] then return false end
    end
    return true
end

local function addAction(context, playerObj, target, label, command, duration, scrapNeeded)
    local option = context:addOption(label, playerObj, queueInteraction, target, command, duration)
    local description=WR.requirementsText(playerObj,target,command)
    if description~="" then
        local tooltip=ISWorldObjectContextMenu.addToolTip();tooltip.description=description;option.toolTip=tooltip
    end
    option.notAvailable=not WR.canMaterials(playerObj,target,command)
    return option
end

local function onFillWorldObjectContextMenu(playerIndex, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then return true end
    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj then return end

    local target = nil
    -- Vanilla supplies the objects under this context click. ClickObject.tile
    -- is an internal Java field, not exposed to Kahlua in B42.
    local candidates=worldobjects or {}
    for _,object in ipairs(candidates) do
        local square=object and object:getSquare()
        if square then
            local generator=WR.Power.target(object)
            if generator then target=generator;break end
            local plant=WR.findTargetAt(square:getX(),square:getY(),square:getZ())
            if plant and (plant.kind=="valve" or WR.isConsoleObject(object)) then target=plant end
            if not target then target=WR.stationTargetObject(object) end
            if target then break end
        end
    end
    if not target then return end

    local state = WR.ClientState or {}
    local repairedPanels = state.panels or {}
    local turnedValves = state.valves or {}
    local maintenance = state.maintenance or {}
    local req = WR.getRequirements()
    if state.originalService then
        local label=getText("ContextMenu_WR_InspectTerminal")
        context:addOption(label,playerObj,function(p,t)
            local command=t.kind=="generator" and "inspectGenerator" or (t.kind=="distributor" and "inspectStation" or "inspectPlant")
            if t.kind=="valve" then WR.showResult(p,"OriginalService");return end
            local args={target=t.id,x=t.x,y=t.y,z=t.z}
            if isClient() then sendClientCommand("WR",command,args) else WR.Server.handleCommand(command,p,args) end
        end,target)
        if target.kind=="central" and WR.Laptop then
            local laptop
            WR.Laptop.walk(playerObj:getInventory(),function(item) if not laptop and WR.Laptop.isLaptop(item) then laptop=item end end)
            if laptop then context:addOption(getText("IGUI_WR_Link_Connect"),playerObj,function(p,item) WR.Laptop.request(p,item,"pairWater") end,laptop) end
        end
        addDisabled(context,getText("IGUI_WR_Result_OriginalService"));return
    end

    if target.kind=="generator" then
        context:addOption(getText("IGUI_WR_Gen_View"),playerObj,function(p,t)
            local a={target=t.id,x=t.x,y=t.y,z=t.z}
            if isClient() then sendClientCommand("WR","inspectGenerator",a) else WR.Server.handleCommand("inspectGenerator",p,a) end
        end,target)
        WR.GeneratorPanel.addContext(context,playerObj,target);return
    end
    if (target.kind=="central" or target.kind=="panel") and not WR.Power.available(state) then
        context:addOption(getText("ContextMenu_WR_InspectTerminal"),playerObj,function(p) WR.showResult(p,"NoPlantPower") end);return
    end
    if target.kind=="valve" and not allCompleted(repairedPanels,WR.PANEL_IDS) then
        context:addOption(getText("ContextMenu_WR_TurnValve"),playerObj,function(p) WR.showResult(p,"ComputersFirst") end);return
    end
    if target.kind=="distributor" then
        context:addOption(getText("ContextMenu_WR_RegionalStation"),playerObj,function(player,t)
            local args={target=t.id,x=t.x,y=t.y,z=t.z}
            if isClient() then sendClientCommand("WR","inspectStation",args)
            else WR.Server.handleCommand("inspectStation",player,args) end
        end,target)
        return
    end
    if target.kind == "central" then
        if state.centralRepaired and WR.Laptop then
            local laptop
            WR.Laptop.walk(playerObj:getInventory(),function(item) if not laptop and WR.Laptop.isLaptop(item) then laptop=item end end)
            if laptop and (WR.Laptop.data(laptop).links or {}).water then addDisabled(context,getText("IGUI_WR_Link_AlreadyPaired"))
            elseif laptop then context:addOption(getText("IGUI_WR_Link_Connect"),playerObj,function(player,item) WR.Laptop.request(player,item,"pairWater") end,laptop)
            else addDisabled(context,getText("IGUI_WR_Link_Connect"),getText("IGUI_WR_Link_BringLaptop")) end
        end
        if state.centralRepaired then
            context:addOption(getText("ContextMenu_WR_InspectPlant"), playerObj, function(player)
                if isClient() then sendClientCommand("WR", "inspectPlant", {target="central"})
                else WR.Server.handleCommand("inspectPlant", player, {target="central"}) end
            end)
        end
        if state.manualRead and state.wasActivated and ((state.conditions or {}).central or 100) < 99.99 then
            addAction(context, playerObj, target, getText("ContextMenu_WR_MaintainCentral"), "maintain", 400, req.maintenanceScrap)
        end
        if not state.manualRead then
            addDisabled(context, getText("ContextMenu_WR_RepairCentral"), getText("IGUI_WR_NeedManual"))
        elseif not state.centralRepaired then
            addAction(context, playerObj, target, getText("ContextMenu_WR_RepairCentral"), "repairCentral", 600, req.centralScrap)
        elseif not state.waterActive and allCompleted(repairedPanels, WR.PANEL_IDS)
                and allCompleted(turnedValves, WR.VALVE_IDS)
                and (not state.maintenanceRequired or allCompleted(maintenance, WR.COMPUTER_IDS)) then
            addAction(context, playerObj, target, getText("ContextMenu_WR_ActivateWater"), "activateWater", 300)
        elseif not state.waterActive and state.wasActivated then
            addAction(context, playerObj, target, getText("ContextMenu_WR_ActivateWater"), "activateWater", 300)
        elseif state.waterActive then
            addDisabled(context, getText("ContextMenu_WR_SystemOperational"), state.maintenanceDueText)
        else
            addDisabled(context, getText("ContextMenu_WR_CheckCentral"), getText("IGUI_WR_SequenceIncomplete"))
        end
    elseif target.kind == "panel" then
        if repairedPanels[target.id] then
            context:addOption(getText("ContextMenu_WR_InspectTerminal"), playerObj, function(player, id)
                if isClient() then sendClientCommand("WR", "inspectPlant", {target=id})
                else WR.Server.handleCommand("inspectPlant", player, {target=id}) end
            end, target.id)
        end
        if not state.centralRepaired then
            addDisabled(context, getText("ContextMenu_WR_RepairPanel"), getText("IGUI_WR_CentralFirst"))
        elseif not repairedPanels[target.id] then
            addAction(context, playerObj, target, getText("ContextMenu_WR_RepairPanel"), "repairPanel", 450, req.panelScrap)
        elseif state.wasActivated and (state.conditions[target.id] or 100) < 99.99 then
            addAction(context, playerObj, target, getText("ContextMenu_WR_MaintainPanel"), "maintain", 350, req.maintenanceScrap)
        else
            addDisabled(context, getText("ContextMenu_WR_PanelConnected"))
        end
    elseif target.kind == "valve" then
        if not allCompleted(repairedPanels, WR.PANEL_IDS) then
            addDisabled(context, getText("ContextMenu_WR_TurnValve"), getText("IGUI_WR_PanelsFirst"))
        elseif not turnedValves[target.id] then
            addAction(context, playerObj, target, getText("ContextMenu_WR_TurnValve"), "turnValve", 300)
        elseif state.wasActivated and (state.conditions[target.id] or 100) < 99.99 then
            addAction(context, playerObj, target, getText("ContextMenu_WR_MaintainValve"), "maintain", 300, 0)
        else
            addDisabled(context, getText("ContextMenu_WR_ValveOpen"))
        end
    end
end

local function flattenItems(items)
    local result = {}
    for _, entry in ipairs(items or {}) do
        if instanceof(entry, "InventoryItem") then
            table.insert(result, entry)
        elseif type(entry) == "table" and entry.items then
            for _, item in ipairs(entry.items) do table.insert(result, item) end
        end
    end
    return result
end

local function onFillInventoryObjectContextMenu(playerIndex, context, items)
    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj or WR.ClientState.manualRead then return end
    for _, item in ipairs(flattenItems(items)) do
        if item:getFullType() == WR.MANUAL_ITEM then
            context:addOption(getText("ContextMenu_WR_ReadManual"), playerObj,
                function(character, manual)
                    ISTimedActionQueue.add(WR_ReadManualAction:new(character, manual))
                end, item)
            return
        end
    end
end

Events.OnGameStart.Add(requestState)
Events.OnCreatePlayer.Add(function() requestState() end)
Events.OnServerCommand.Add(onServerCommand)
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
