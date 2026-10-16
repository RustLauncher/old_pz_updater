--[[
    Vehicle Armor Crafting - client side.
      * receives server replies (part state, item handouts, halo notes);
      * shows/hides the 3D armor models on nearby vehicles;
      * in multiplayer asks the server about vehicles it sees for the first time.
    In singleplayer the network part is unused, only the model display remains.
]]
require "WindowArmorTest_Shared"
require "WindowArmorTest_Visual"
require "WindowArmorTest_CraftDebug"

local WAT = WindowArmorTest
local tickCounter = 0
WAT.synced = WAT.synced or {}   -- vehicle id -> true (state already requested from the server)

-- ---------- server replies ----------

local function applyPart(vehicle, partId, kind, cond)
    if not vehicle then return end
    local part = vehicle:getPartById(partId)
    if not part then return end
    if cond and cond > 0 then
        local entry = WAT.getPartEntry(part) or {}
        entry.kind = kind or entry.kind or "glass"
        entry.condition = cond
        WAT.setPartEntry(vehicle, part, entry, false)
    else
        WAT.setPartEntry(vehicle, part, nil, false)
    end
end

local function onServerCommand(module, command, args)
    if module ~= WAT.NET or type(args) ~= "table" then return end
    local player = getPlayer()

    if command == "part" then
        local vehicle = getVehicleById(args.veh)
        applyPart(vehicle, args.part, args.kind, args.cond)
        WAT.updateVisual(vehicle)

    elseif command == "parts" then
        local vehicle = getVehicleById(args.veh)
        if not vehicle then return end
        -- clear everything first, then apply what was sent - this removes stale entries
        for _, rec in ipairs(WAT.armoredParts(vehicle)) do
            WAT.setPartEntry(vehicle, rec.part, nil, false)
        end
        if type(args.list) == "table" then
            for partId, rec in pairs(args.list) do
                applyPart(vehicle, partId, rec.kind, rec.cond)
            end
        end
        WAT.updateVisual(vehicle)

    elseif command == "diag" then
        print("[WindowArmorTest] " .. tostring(args.text))

    elseif command == "halo" then
        WAT.halo(player, args.text, args.r, args.g, args.b)
    end
end

if isClient() then
    Events.OnServerCommand.Add(onServerCommand)
end

-- ---------- model display ----------

-- Walk over the vehicles near the local players
local function refreshVisuals()
    local seen = {}
    local function handle(v)
        if isClient() and not WAT.synced[v:getId()] then
            WAT.synced[v:getId()] = true
            local p = getPlayer()
            if p then sendClientCommand(p, WAT.NET, "sync", { veh = v:getId() }) end
        end
        WAT.updateVisual(v)
    end
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p then
            WAT.forEachNearbyVehicle(p, WAT.SCAN_RADIUS, handle, seen)
            local inside = p:getVehicle()          -- the vehicle the player is sitting in
            if inside and not seen[inside] then
                seen[inside] = true
                handle(inside)
            end
        end
    end
end

local function onTick()
    tickCounter = tickCounter + 1
    if not WAT.visualsInjected then
        pcall(WAT.injectVisuals, false)
        WAT.visualsInjected = true
    end
    if (tickCounter % WAT.SCAN_EVERY) ~= 0 then return end
    local ok, err = pcall(refreshVisuals)
    if not ok then WAT.log("model display error:", err) end
end

Events.OnTick.Add(onTick)

-- request vehicle states again when entering the world
Events.OnCreatePlayer.Add(function()
    WAT.synced = {}
    if WAT.DEBUG then WAT.log(WAT.diagText(getPlayer())) end   -- what the client sees
end)

if WAT.DEBUG and DebugLog and DebugLog.setLogEnabled and DebugType and DebugType.CraftLogic then
    pcall(function() DebugLog.setLogEnabled(DebugType.CraftLogic, true) end)
end

WAT.log("client side loaded")
