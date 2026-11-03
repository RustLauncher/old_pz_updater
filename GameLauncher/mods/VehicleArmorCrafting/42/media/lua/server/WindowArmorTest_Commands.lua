--[[
    Vehicle Armor Crafting - server side of the network exchange.
    The client never changes the data itself: it asks the server (sendClientCommand),
    the server validates the request, changes the part modData and answers the client.

    Installing and removing armor is done by the timed action itself: the engine runs
    its complete() on the server, so no client request is involved. What is left here
    is the state exchange.

    Client commands:
      sync   { veh }                       - send the state of every part of a vehicle
      diag   { }                           - report what the server can see (debug)

    Server replies:
      part   { veh, part, kind, cond }     - state of one part (broadcast to everyone)
      parts  { veh, list }                 - state of a whole vehicle (answer to sync)
      halo   { text, r, g, b }             - floating note above the player
]]
require "WindowArmorTest_Shared"
require "WindowArmorTest_CraftDebug"

if isClient() then return end

local WAT = WindowArmorTest
local Commands = {}

function Commands.sync(player, args)
    local vehicle = getVehicleById(args.veh)
    if not vehicle then return end
    local list = {}
    for _, rec in ipairs(WAT.armoredParts(vehicle)) do
        list[rec.id] = { kind = WAT.entryKind(rec.entry), cond = rec.entry.condition }
    end
    sendServerCommand(player, WAT.NET, "parts", { veh = args.veh, list = list })
end

-- Diagnostics: the client asks the server to report what it can see
function Commands.diag(player, args)
    local text = WAT.diagText(player)
    WAT.log(text)
    sendServerCommand(player, WAT.NET, "diag", { text = text })
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= WAT.NET then return end
    local fn = Commands[command]
    if not fn then return end
    local ok, err = pcall(fn, player, args or {})
    if not ok then WAT.log("command error", command, err) end
end)

-- While multiplayer is being debugged: switch on the crafting log,
-- otherwise the reason behind "progress runs, no item" is printed nowhere.
if WAT.DEBUG and DebugLog and DebugLog.setLogEnabled and DebugType and DebugType.CraftLogic then
    pcall(function() DebugLog.setLogEnabled(DebugType.CraftLogic, true) end)
end

WAT.log("server commands loaded")
Events.OnServerStarted.Add(function() WAT.log(WAT.diagText(nil)) end)
