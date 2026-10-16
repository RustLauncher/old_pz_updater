--[[ Trains -- talking between clients and the server.

    The server owns the clock and who is aboard what; a client only ever
    *asks* (DEV_GUIDE.md, "The server owns the trains; a client asks"). This
    file is the only place that knows how asking works in each of the three
    setups. It is the Shuttlecraft's TREK_Net by way of the Heroes mod:

      * sendClientCommand reaches OnClientCommand on the server, and in
        single player too. So a client always sends and the authority always
        handles, with no special case for single player.
      * sendServerCommand does nothing in single player. So the reply path
        is the one place that needs a branch, and it lives here.
      * shared/, client/ and server/ Lua all load in every process.

    Commands are plain tables of numbers, strings and booleans. The server
    validates every one: a client is a request, never a fact.
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"

TRN = TRN or {}
local C, U = TRN.Config, TRN.Util

local Net = {}
TRN.Net = Net

Net.MODULE = C.NetModule

-- cmd -> function(player, args), run where the authority lives.
Net.serverHandlers = {}
-- cmd -> function(args), run on the client a reply is addressed to.
Net.clientHandlers = {}

--- True where the clock and the riders are authoritative: single player,
--- or a server process. False on any client connected to a server.
function Net.isAuthority()
    return not isClient()
end

--- Asks the server to do something on this player's behalf.
function Net.send(player, cmd, args)
    if not player then return false end
    return U.try("send:" .. tostring(cmd), function()
        sendClientCommand(player, Net.MODULE, cmd, args or {})
        return true
    end) == true
end

function Net.onServer(cmd, fn)
    Net.serverHandlers[cmd] = fn
end

function Net.onClient(cmd, fn)
    Net.clientHandlers[cmd] = fn
end

local function runClient(cmd, args)
    local handler = Net.clientHandlers[cmd]
    if handler then U.try("reply:" .. tostring(cmd), handler, args or {}) end
end

--- Tells one player's client something. In single player there is no
--- network to send over, so the handler runs directly.
function Net.toClient(player, cmd, args)
    if isServer() then
        U.try("sendServerCommand:" .. tostring(cmd), function()
            sendServerCommand(player, Net.MODULE, cmd, args or {})
        end)
    else
        runClient(cmd, args)
    end
end

--- Tells every client.
function Net.toAll(cmd, args)
    if isServer() then
        U.try("sendServerCommandAll:" .. tostring(cmd), function()
            sendServerCommand(Net.MODULE, cmd, args or {})
        end)
    else
        runClient(cmd, args)
    end
end

Events.OnClientCommand.Add(function(module, cmd, player, args)
    if module ~= Net.MODULE then return end
    local handler = Net.serverHandlers[cmd]
    if not handler then
        U.warnOnce("unknownCommand:" .. tostring(cmd), "unknown command " .. tostring(cmd))
        return
    end
    U.try("command:" .. tostring(cmd), handler, player, args or {})
end)

Events.OnServerCommand.Add(function(module, cmd, args)
    if module ~= Net.MODULE then return end
    runClient(cmd, args)
end)

return Net
