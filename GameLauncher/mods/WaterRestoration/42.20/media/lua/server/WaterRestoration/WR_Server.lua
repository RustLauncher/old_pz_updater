require "WaterRestoration/WR_Config"
require "WaterRestoration/WR_Regions"
require "WaterRestoration/WR_Requirements"
require "WaterRestoration/WR_Power"
require "WaterRestoration/WR_Service"

WR.Server = WR.Server or {}
WR._serverReady = false
Events.OnServerStarted.Add(function() WR._serverReady = true end)
local Server = WR.Server

local function log(message)
    print("[WaterRestoration] " .. tostring(message))
end

local function currentWorldDay()
    return getGameTime():getWorldAgeHours() / 24
end

local function currentApocalypseDay()
    return currentWorldDay() + (getSandboxOptions():getTimeSinceApo() - 1) * 30
end

local function ensureBooleanTable(value, ids)
    local result = type(value) == "table" and value or {}
    for _, id in ipairs(ids) do
        if result[id] == nil then result[id] = false end
    end
    return result
end

function Server.getData()
    local data = ModData.getOrCreate(WR.DATA_KEY)
    data.version = 5
    WR.Power.data(data)
    data.revisions=data.revisions or {}
    data.regions=data.regions or {}
    for _,r in ipairs(WR.REGIONS) do data.regions[r.id]=data.regions[r.id] or {repaired=false,activated=false} end
    if data.centralRepaired == nil then data.centralRepaired = data.tableRepaired == true end
    if data.waterActive == nil then data.waterActive = false end
    if data.wasActivated == nil then data.wasActivated = data.waterActive == true end
    if data.maintenanceRequired == nil then data.maintenanceRequired = false end
    if data.manualSpawned == nil then data.manualSpawned = false end
    data.panels = ensureBooleanTable(data.panels, WR.PANEL_IDS)
    data.valves = ensureBooleanTable(data.valves, WR.VALVE_IDS)
    data.maintenance = ensureBooleanTable(data.maintenance, WR.ALL_IDS)
    data.servicedAt = data.servicedAt or {}
    if data.wasActivated then
        local started = data.activatedAt or ((data.maintenanceDueAt or (currentWorldDay() + 30)) - 30)
        for _, id in ipairs(WR.ALL_IDS) do
            if data.servicedAt[id] == nil then data.servicedAt[id] = started end
        end
        data.maintenanceDueAt = WR.nextService(data)
    end
    if data.originalWaterShutModifier == nil then
        data.originalWaterShutModifier = getSandboxOptions():getWaterShutModifier()
    end
    WR.Service.update(data)
    return data
end

local function manualRead(player)
    return player and player:getModData().WRManualRead == true
end

local function snapshotFor(player)
    local data = Server.getData()
    local dueText = nil
    if data.waterActive and data.maintenanceDueAt then
        local remaining = math.max(0, math.ceil(data.maintenanceDueAt - currentWorldDay()))
        dueText = getText("IGUI_WR_MaintenanceDue", remaining)
    end
    local normal=data.originalService==true
    local panels,valves,regions,conditions={},{},{},{}
    for _,id in ipairs(WR.PANEL_IDS) do panels[id]=normal or data.panels[id] end
    for _,id in ipairs(WR.VALVE_IDS) do valves[id]=normal or data.valves[id] end
    for _,id in ipairs(WR.ALL_IDS) do conditions[id]=normal and 100 or WR.condition(data,id,currentWorldDay()) end
    for _,r in ipairs(WR.REGIONS) do regions[r.id]=normal and {repaired=true,activated=true,servicedAt=currentWorldDay(),originalService=true} or data.regions[r.id] end
    return {
        originalService=normal, originalRemainingDays=WR.Service.remaining(data),
        originalWaterShutModifier=data.originalWaterShutModifier,restorationStarted=data.restorationStarted,
        generator = data.generator,
        gridPower = WR.Power.gridAvailable(data),
        revisions = data.revisions,
        regions = regions,
        regionalMode = true,
        networkReady = normal or (WR.Network.job==nil and WR.Network.error==nil and getSandboxOptions():getWaterShutModifier()==1000000),
        manualRead = manualRead(player),
        centralRepaired = normal or data.centralRepaired,
        panels = panels,
        valves = valves,
        waterActive = normal or data.waterActive,
        maintenanceRequired = data.maintenanceRequired,
        maintenance = data.maintenance,
        maintenanceDueText = dueText,
        wasActivated = data.wasActivated,
        conditions = conditions,
        remainingDays = data.wasActivated and math.max(0, data.maintenanceDueAt - currentWorldDay()) or 21,
        waterModifier = getSandboxOptions():getWaterShutModifier(),
        serverDay = currentWorldDay(),
    }
end

function Server.sendState(player)
    local state = snapshotFor(player)
    if isServer() then
        if player then sendServerCommand(player, "WR", "state", state) end
    elseif WR.ClientState then
        WR.ClientState = state
    end
end

local function broadcastState()
    ModData.transmit(WR.DATA_KEY)
    if isServer() and WR._serverReady then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            Server.sendState(players:get(i))
        end
    else
        Server.sendState(getPlayer())
    end
end

local function result(player, message, remaining)
    if isServer() then
        sendServerCommand(player, "WR", "result", { message = message, remaining = remaining })
    else
        WR.showResult(player, message, remaining)
    end
end
local function remaining(values, ids)
    local count = 0
    for _, id in ipairs(ids) do if not values[id] then count = count + 1 end end
    return count
end

local function targetNearPlayer(player, targetId, expectedKind)
    local target = WR.TARGETS[targetId]
    if not player or not target or target.kind ~= expectedKind then return nil end
    if player:getZ() ~= target.z then return nil end
    local dx = player:getX() - target.x
    local dy = player:getY() - target.y
    if dx * dx + dy * dy > 16 then return nil end
    return target
end

local function hasSkillsAndTools(player, scrapNeeded)
    local req = WR.getRequirements()
    local inv = player:getInventory()
    return player:getPerkLevel(Perks.Electricity) >= req.electricity
        and player:getPerkLevel(Perks.Mechanics) >= req.mechanics
        and player:getPerkLevel(Perks.Strength) >= req.strength
        and inv:containsTypeRecurse("Screwdriver")
        and WR.countElectronicScrap(inv) >= scrapNeeded
end

local function consumeScrap(player, amount)
    local items = WR.getElectronicScrap(player:getInventory())
    if #items < amount then return false end
    for i = 1, amount do
        local item = items[i]
        local container = item:getContainer()
        if isServer() then sendRemoveItemFromContainer(container, item) end
        container:Remove(item)
    end
    return true
end

local function allTrue(values, ids)
    for _, id in ipairs(ids) do
        if not values[id] then return false end
    end
    return true
end

local function applyWaterState(enabled, data)
    local options = getSandboxOptions()
    if data.originalService then
        -- Clear only our old restriction zones; vanilla keeps its own deadline.
        WR.Network.sync(data,false)
        if options:getWaterShutModifier()~=data.originalWaterShutModifier then
            options:set("WaterShutModifier",data.originalWaterShutModifier)
            if options.toLua then options:toLua() end
            if SandboxVars then SandboxVars.WaterShutModifier=data.originalWaterShutModifier end
            if isServer() and GameServer and GameServer.sendOptionsToClients then GameServer.sendOptionsToClients() end
        end
        return true
    end
    enabled=enabled and WR.Power.available(data)
    local modifier
    local ok,any=WR.Network.sync(data,enabled)
    if not ok then
        options:set("WaterShutModifier",-1)
        log("ERROR regional water blocked: "..tostring(any))
        return false
    end
    if enabled and any then
        -- Keep the vanilla mains enabled until this mod deliberately stops them
        -- for maintenance. This is the same value used by established water-toggle
        -- mods and avoids the supply expiring in exceptionally long saves.
        modifier = 1000000
    else
        modifier = -1
    end
    if options:getWaterShutModifier()==modifier then data.appliedWaterModifier=modifier;return true end
    options:set("WaterShutModifier", modifier)
    data.appliedWaterModifier = options:getWaterShutModifier()
    if data.appliedWaterModifier ~= modifier then
        log("ERROR water option rejected; actual=" .. tostring(data.appliedWaterModifier))
        return false
    end
    -- Refresh the live Lua sandbox table as well as the underlying option. In
    -- singleplayer, fixtures consult both values depending on the interaction.
    pcall(function() options:toLua() end)
    if SandboxVars then SandboxVars.WaterShutModifier = modifier end
    if options.saveCurrentGameBinFile then pcall(function() options:saveCurrentGameBinFile() end) end
    if isServer() and GameServer and GameServer.sendOptionsToClients then
        pcall(function() GameServer.sendOptionsToClients() end)
    end
    log((enabled and "water enabled; modifier=" or "water disabled; modifier=") .. tostring(modifier))
    return true
end

function Server.refreshNetwork()
    local data=Server.getData()
    applyWaterState(data.waterActive,data)
    broadcastState()
end

local function fail(player, code)
    log("action rejected: "..tostring(code or "InvalidAction"))
    result(player, code or "InvalidAction")
    Server.sendState(player)
end

function Server.handleCommand(command, player, args)
    args = type(args) == "table" and args or {}
    local data = Server.getData()
    local req = WR.getRequirements()
    if data.waterActive and data.maintenanceDueAt and currentWorldDay() >= data.maintenanceDueAt then
        data.waterActive = false
        data.maintenanceRequired = true
        applyWaterState(false, data)
        broadcastState()
    end

    if command=="repairStation" or command=="activateStation" or command=="maintainStation" or command=="inspectStation" then
        local r=WR.REGION_BY_ID[args.target]
        local x,y,z=tonumber(args.x),tonumber(args.y),tonumber(args.z)
        if not player or not r or not x or not y or not z then return fail(player) end
        if math.abs(x-r.x)>40 or math.abs(y-r.y)>40 or z<0 or z>2
            or player:getZ()~=z or (player:getX()-x)^2+(player:getY()-y)^2>9 then return fail(player) end
        local sq=getCell():getGridSquare(x,y,z)
        local actual=WR.stationTarget(sq)
        if not actual or actual.id~=r.id then return fail(player) end
        local station=data.regions[r.id]
        -- Replace coordinates previously learned from a light switch with the actual console.
        station.terminal={x=x,y=y,z=z}
        if command=="inspectStation" then
            Server.sendState(player)
            if isServer() then sendServerCommand(player,"WR","openStation",{target=r.id,x=x,y=y,z=z})
            elseif WR.StationPanel then WR.StationPanel.open(player,{id=r.id,x=x,y=y,z=z,kind="distributor"}) end
            return
        end
        if not manualRead(player) or not data.centralRepaired then return fail(player) end
        if command=="repairStation" then
            if station.repaired then return fail(player) end
            if not hasSkillsAndTools(player,req.stationScrap) or not consumeScrap(player,req.stationScrap) then return fail(player,"RequirementsMissing") end
            station.repaired=true
            station.terminal={x=x,y=y,z=z}
            result(player,"StationRepaired")
        elseif command=="activateStation" then
            if not data.waterActive or not station.repaired or station.activated or WR.stationCondition(station,currentWorldDay())<=0 then return fail(player,"StationUnavailable") end
            station.activated=true;station.servicedAt=currentWorldDay()
            result(player,"StationActivated")
        else
            if not station.activated or WR.stationCondition(station,currentWorldDay())>=99.99 then return fail(player) end
            if not hasSkillsAndTools(player,req.maintenanceScrap) or not consumeScrap(player,req.maintenanceScrap) then return fail(player,"RequirementsMissing") end
            station.servicedAt=currentWorldDay()
            result(player,"MaintenanceComplete")
        end
        if not applyWaterState(data.waterActive,data) then data.waterActive=false;data.maintenanceRequired=true;applyWaterState(false,data);result(player,"WaterFailed") end
        broadcastState()
        return
    end
    if command == "resyncWater" then
        if not targetNearPlayer(player, "central", "central") or not data.waterActive then return fail(player) end
        if applyWaterState(true, data) then result(player, "WaterResynced") else result(player, "WaterFailed") end
        Server.sendState(player)
        return
    end
    if command == "inspectPlant" then
        local id = args.target or "central"
        local target = WR.TARGETS[id]
        if not target or (target.kind ~= "central" and target.kind ~= "panel")
                or not targetNearPlayer(player, id, target.kind)
                or (not data.originalService and id == "central" and not data.centralRepaired)
                or (not data.originalService and target.kind == "panel" and not data.panels[id]) then return fail(player) end
        Server.sendState(player)
        if isServer() then sendServerCommand(player, "WR", "openPanel", {target=id})
        elseif WR.PlantPanel then WR.PlantPanel.open(player, id) end
        return
    end
    if command == "requestState" then
        Server.sendState(player)
        return
    end

    if command == "readManual" then
        if not player:getInventory():containsTypeRecurse("WaterPlantManual") then return fail(player, "ManualMissing") end
        player:getModData().WRManualRead = true
        if player.transmitModData then player:transmitModData() end
        result(player, "ManualLearned")
        Server.sendState(player)
        return
    end

    if command == "repairCentral" then
        if not targetNearPlayer(player, args.target, "central") or data.centralRepaired or not manualRead(player) then return fail(player) end
        if not hasSkillsAndTools(player, req.centralScrap) or not consumeScrap(player, req.centralScrap) then return fail(player, "RequirementsMissing") end
        data.centralRepaired = true
        result(player, "CentralRepaired")
    elseif command == "repairPanel" then
        local target = targetNearPlayer(player, args.target, "panel")
        if not target or data.panels[target.id] or not data.centralRepaired or not manualRead(player) then return fail(player) end
        if not hasSkillsAndTools(player, req.panelScrap) or not consumeScrap(player, req.panelScrap) then return fail(player, "RequirementsMissing") end
        data.panels[target.id] = true
        result(player, "PanelRepaired", remaining(data.panels, WR.PANEL_IDS))
    elseif command == "turnValve" then
        local target = targetNearPlayer(player, args.target, "valve")
        if not target or data.valves[target.id] or not allTrue(data.panels, WR.PANEL_IDS) then return fail(player) end
        if not WR.hasPipeWrench(player) then return fail(player, "NeedPipeWrench") end
        data.valves[target.id] = true
        result(player, "Valve_"..target.id)
    elseif command == "maintain" then
        local target = WR.TARGETS[args.target]
        if not target or not targetNearPlayer(player, args.target, target.kind)
                or not data.wasActivated or not manualRead(player)
                or WR.condition(data, target.id, currentWorldDay()) >= 99.99 then return fail(player) end
        if WR.isValveRepair(target,command) then
            if not WR.canMaterials(player,target,command) then return fail(player,"ValveRequirementsMissing") end
            local bars=WR.itemsOfType(player:getInventory(),"MetalBar")
            local torch=WR.weldingTools(player)
            for i=1,2 do local item=bars[i];local container=item:getContainer()
                if isServer() then sendRemoveItemFromContainer(container,item) end
                container:Remove(item)
            end
            torch:Use()
        else
            if not hasSkillsAndTools(player,req.maintenanceScrap) or not consumeScrap(player,req.maintenanceScrap) then return fail(player,"RequirementsMissing") end
        end
        data.servicedAt[target.id] = currentWorldDay()
        data.maintenance[target.id] = true
        data.maintenanceDueAt = WR.nextService(data)
        result(player, "MaintenanceComplete")
    elseif command == "activateWater" then
        log("activation requested; active=" .. tostring(data.waterActive) .. " central=" .. tostring(data.centralRepaired)
            .. " panels=" .. tostring(allTrue(data.panels, WR.PANEL_IDS)) .. " valves=" .. tostring(allTrue(data.valves, WR.VALVE_IDS)))
        if data.waterActive or not targetNearPlayer(player, args.target, "central") or not data.centralRepaired
                or not allTrue(data.panels, WR.PANEL_IDS) or not allTrue(data.valves, WR.VALVE_IDS) then return fail(player) end
        if data.wasActivated then
            for _, id in ipairs(WR.ALL_IDS) do
                if WR.condition(data, id, currentWorldDay()) <= 0 then return fail(player, "MaintenanceIncomplete") end
            end
        end
        if not applyWaterState(true, data) then return fail(player, "WaterFailed") end
        if not data.wasActivated then
            data.activatedAt = currentWorldDay()
            for _, id in ipairs(WR.ALL_IDS) do data.servicedAt[id] = currentWorldDay() end
        end
        data.waterActive = true
        data.wasActivated = true
        data.maintenanceRequired = false
        data.maintenanceDueAt = WR.nextService(data)
        for _, id in ipairs(WR.COMPUTER_IDS) do data.maintenance[id] = false end
        result(player, "WaterActivated")
    else
        return
    end

    log("completed command=" .. command .. " target=" .. tostring(args.target))
    broadcastState()
end

local function onClientCommand(module, command, player, args)
    if module == "WR" then Server.handleCommand(command, player, args) end
end

local function checkMaintenance()
    local data = Server.getData()
    if not data.wasActivated then return end
    if data.waterActive and currentWorldDay() >= data.maintenanceDueAt then
        data.waterActive = false
        data.maintenanceRequired = true
        applyWaterState(false, data)
        log("maintenance due; water stopped")
    end
    if data.waterActive then
        if not applyWaterState(true,data) then data.waterActive=false;data.maintenanceRequired=true;applyWaterState(false,data) end
    end
    broadcastState()
end

local manualCreationFailed = false

local function trySpawnManual(square, allowFallback)
    if manualCreationFailed then return end
    if not square or not WR.isInsideOffice(square:getX(), square:getY(), square:getZ()) then return end
    local data = Server.getData()
    if data.manualSpawned then return end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        for c = 0, object:getContainerCount() - 1 do
            local container = object:getContainerByIndex(c)
            if container then
                -- Do not duplicate a manual already present in an office container.
                if container:containsTypeRecurse("WaterPlantManual") then
                    data.manualSpawned = true
                    broadcastState()
                    return
                end
                local name = string.lower(tostring(container:getType() or ""))
                local preferred = string.find(name, "desk") or string.find(name, "filing")
                    or string.find(name, "office") or string.find(name, "counter")
                    or string.find(name, "shelf") or string.find(name, "shelves")
                if preferred or allowFallback == true then
                    local ok, item = pcall(function() return container:AddItem(WR.MANUAL_ITEM) end)
                    if not ok or not item then
                        manualCreationFailed = true
                        log("manual creation failed; retries disabled until restart: " .. tostring(item))
                        return
                    end
                    if item then
                        data.manualSpawned = true
                        if isServer() then sendAddItemToContainer(container, item) end
                        broadcastState()
                        log("operations manual spawned at " .. square:getX() .. "," .. square:getY() .. "," .. square:getZ() .. " container=" .. name)
                        return
                    end
                end
            end
        end
    end
end

local function scanLoadedOffices()
    if manualCreationFailed or Server.getData().manualSpawned then return end
    local cell = getCell()
    if not cell then return end
    local area = WR.OFFICE_AREA
    local fallback = nil
    for z = area.minZ, area.maxZ do
        for x = area.minX, area.maxX do
            for y = area.minY, area.maxY do
                local square = cell:getGridSquare(x, y, z)
                if square then
                    trySpawnManual(square, false)
                    if Server.getData().manualSpawned then return end
                    if not fallback then
                        local objects = square:getObjects()
                        for i = 0, objects:size() - 1 do
                            if objects:get(i):getContainerCount() > 0 then
                                fallback = square
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    -- Some map furniture uses generic container names. Keep the book obtainable.
    if fallback then trySpawnManual(fallback, true) end
end

local function onInitGlobalModData()
    local data = Server.getData()
    checkMaintenance()
    applyWaterState(data.waterActive, data)
    log("state initialized; active=" .. tostring(data.waterActive) .. " activated=" .. tostring(data.wasActivated)
        .. " central=" .. tostring(data.centralRepaired) .. " pendingPanels=" .. tostring(remaining(data.panels, WR.PANEL_IDS))
        .. " pendingValves=" .. tostring(remaining(data.valves, WR.VALVE_IDS))
        .. " waterModifier=" .. tostring(getSandboxOptions():getWaterShutModifier()))
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.OnClientCommand.Add(onClientCommand)
Events.LoadGridsquare.Add(trySpawnManual)
Events.EveryOneMinute.Add(scanLoadedOffices)
Events.EveryHours.Add(checkMaintenance)

Events.EveryOneMinute.Add(function()
    local data = Server.getData()
    if data.originalService~=data.appliedOriginalPhase then
        data.appliedOriginalPhase=data.originalService
        applyWaterState(data.waterActive,data);broadcastState()
    elseif data.originalService then broadcastState()
    elseif data.wasActivated then checkMaintenance() end
end)

Server.broadcastState=broadcastState
Server.applyWaterState=applyWaterState
