if not isServer() then return end

local ArgosEye = {}

ArgosEye.KICK_ENABLED = false
ArgosEye.AFK_THRESHOLD = 300
ArgosEye.CHAT_FLUSH_SECONDS = 60

ArgosEye.trackedPlayers = {}
ArgosEye.lastPositions = {}
ArgosEye.lastMoveTime = {}
ArgosEye.afkPlayers = {}
ArgosEye.pendingChatLogs = {}
ArgosEye.playerIPs = {}
ArgosEye.requestCounter = 0
ArgosEye.serverStartTime = nil
ArgosEye.pendingPeriodicFile = nil

-- ============================================================
-- File I/O helpers (bridge communication)
-- ============================================================

function ArgosEye.writeRequest(prefix, jsonStr)
    ArgosEye.requestCounter = ArgosEye.requestCounter + 1
    local filename = prefix .. ArgosEye.requestCounter .. ".json"
    local path = "ArgosEye/requests/" .. filename
    local writer = getFileWriter(path, true, false)
    if writer then
        writer:write(jsonStr)
        writer:close()
    end
    return filename
end

function ArgosEye.readResponse(filename)
    local respName = filename:gsub("%.json$", "_resp.json")
    local path = "ArgosEye/responses/" .. respName
    local reader = getFileReader(path, false)
    if not reader then return nil end

    local lines = {}
    local line = reader:readLine()
    while line do
        table.insert(lines, line)
        line = reader:readLine()
    end
    reader:close()

    local delWriter = getFileWriter(path, true, false)
    if delWriter then
        delWriter:write("")
        delWriter:close()
    end

    local content = table.concat(lines, "")
    if content == "" then return nil end
    return content
end

-- ============================================================
-- JSON helpers
-- ============================================================

function ArgosEye.escapeJson(str)
    if not str then return "" end
    str = str:gsub('\\', '\\\\')
    str = str:gsub('"', '\\"')
    str = str:gsub('\n', '\\n')
    str = str:gsub('\r', '\\r')
    str = str:gsub('\t', '\\t')
    return str
end

-- ============================================================
-- Player IP from connection logs
-- ============================================================

function ArgosEye.parsePlayerIPs()
    local reader = getFileReader("ArgosEye/player_ips.txt", false)
    if not reader then return end

    local line = reader:readLine()
    while line do
        local steamId, ip = line:match("^(%d+)=([%d%.]+)$")
        if steamId and ip then
            ArgosEye.playerIPs[steamId] = ip
        end
        line = reader:readLine()
    end
    reader:close()
end

-- ============================================================
-- PlayerData JSON (matches Rust plugin exactly)
-- Fields: playerIp, userId, playerName, IsConnected, IsAfk
-- ============================================================

function ArgosEye.buildPlayerJson(player, isConnected)
    if not player then return nil end

    local ok, steamId = pcall(function() return tostring(player:getSteamID()) end)
    if not ok or not steamId then return nil end

    local ok2, name = pcall(function() return player:getUsername() end)
    if not ok2 then name = "unknown" end
    name = ArgosEye.escapeJson(name or "unknown")

    local ip = ArgosEye.playerIPs[steamId] or "0.0.0.0"
    local isAfk = ArgosEye.afkPlayers[steamId] or false

    return string.format(
        '{"playerIp":"%s","userId":"%s","playerName":"%s","IsConnected":%s,"IsAfk":%s}',
        ip, steamId, name,
        isConnected and "true" or "false",
        isAfk and "true" or "false"
    )
end

-- ============================================================
-- ServerData JSON (matches Rust plugin exactly)
-- Fields: hostname, banner, version, description, max_players,
--         url, port, query_port, server_level, server_seed,
--         server_worldsize, server_fps, used_memory, uptime,
--         network_in, network_out
-- ============================================================

function ArgosEye.formatUptime()
    if not ArgosEye.serverStartTime then return "0m 0s" end
    local elapsed = math.floor((getTimestampMs() - ArgosEye.serverStartTime) / 1000)
    local days = math.floor(elapsed / 86400)
    local hours = math.floor((elapsed % 86400) / 3600)
    local mins = math.floor((elapsed % 3600) / 60)
    local secs = elapsed % 60
    if days >= 1 then return string.format("%dd %dh", days, hours) end
    if hours >= 1 then return string.format("%dh %dm", hours, mins) end
    return string.format("%dm %ds", mins, secs)
end

function ArgosEye.sendServerInfo()
    local opts = getServerOptions()
    local hostname = ArgosEye.escapeJson(opts and opts:getOption("PublicName") or "PZ Server")
    local description = ArgosEye.escapeJson(opts and opts:getOption("ServerWelcomeMessage") or "")
    local maxPlayers = opts and opts:getInteger("MaxPlayers") or 16
    local port = opts and opts:getInteger("DefaultPort") or 16261

    local json = string.format(
        '{"hostname":"%s","banner":"","version":"PZ Build 42","description":"%s","max_players":%d,"url":"","port":%d,"query_port":%d,"server_level":"","server_seed":0,"server_worldsize":0,"server_fps":0,"used_memory":0,"uptime":"%s","network_in":"N/A","network_out":"N/A"}',
        hostname, description, maxPlayers, port, port + 1,
        ArgosEye.formatUptime()
    )

    ArgosEye.writeRequest("server_info_", json)
end

-- ============================================================
-- Player connection / disconnection
-- Matches Rust: OnUserApprove / OnPlayerConnected / OnPlayerDisconnected
-- Sends to: /internal_player_state (array of PlayerData)
-- ============================================================

function ArgosEye.onPlayerConnect(player)
    if not player then return end

    ArgosEye.parsePlayerIPs()

    local steamId = tostring(player:getSteamID())
    ArgosEye.trackedPlayers[steamId] = {
        player = player,
        validated = false,
        pendingFile = nil,
        connectTime = getTimestampMs()
    }

    local pjson = ArgosEye.buildPlayerJson(player, true)
    if not pjson then return end

    local json = "[" .. pjson .. "]"
    local filename = ArgosEye.writeRequest("player_check_", json)
    ArgosEye.trackedPlayers[steamId].pendingFile = filename

    print("[ArgosEye] Player connecting: " .. (player:getUsername() or steamId) .. " (" .. steamId .. ") IP: " .. (ArgosEye.playerIPs[steamId] or "unknown"))
end

function ArgosEye.onPlayerDisconnect(player)
    if not player then return end
    local steamId = tostring(player:getSteamID())

    local pjson = ArgosEye.buildPlayerJson(player, false)
    if pjson then
        ArgosEye.writeRequest("player_check_", "[" .. pjson .. "]")
    end

    ArgosEye.trackedPlayers[steamId] = nil
    ArgosEye.lastPositions[steamId] = nil
    ArgosEye.lastMoveTime[steamId] = nil
    ArgosEye.afkPlayers[steamId] = nil

    print("[ArgosEye] Player disconnected: " .. (player:getUsername() or steamId))
end

-- ============================================================
-- Response polling
-- Matches Rust: AntiCheatResponse { ip, valid, hban, hbanMessage, userId }
-- ============================================================

function ArgosEye.pollResponses()
    for steamId, data in pairs(ArgosEye.trackedPlayers) do
        if data.pendingFile and not data.validated then
            local resp = ArgosEye.readResponse(data.pendingFile)
            if resp then
                data.pendingFile = nil
                if resp:find('"error"') then
                    print("[ArgosEye] API error for " .. steamId)
                elseif resp:find('"valid"%s*:%s*false') then
                    print("[ArgosEye] Player " .. steamId .. " has NO anticheat")
                    if ArgosEye.KICK_ENABLED then
                        local player = data.player
                        if player and player:isAlive() then
                            player:disconnect()
                        end
                    end
                elseif resp:find('"hban"%s*:%s*true') then
                    local reason = resp:match('"hbanMessage"%s*:%s*"([^"]*)"') or "Banned by AntiCheat"
                    print("[ArgosEye] HBAN detected " .. steamId .. ": " .. reason)
                    if ArgosEye.KICK_ENABLED then
                        local player = data.player
                        if player and player:isAlive() then
                            player:disconnect()
                        end
                    end
                else
                    data.validated = true
                    print("[ArgosEye] Player " .. steamId .. " validated OK")
                end
            end
        end
    end
end

-- ============================================================
-- Periodic check (matches Rust: VerifyAntiCheatCheck)
-- Sends to: /internal_players_check (array of PlayerData)
-- ============================================================

function ArgosEye.periodicCheck()
    local players = getOnlinePlayers()
    if not players or players:size() == 0 then return end

    local parts = {}
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player then
            local pjson = ArgosEye.buildPlayerJson(player, true)
            if pjson then
                table.insert(parts, pjson)
            end
        end
    end

    if #parts == 0 then return end

    local json = "[" .. table.concat(parts, ",") .. "]"
    local filename = ArgosEye.writeRequest("players_check_", json)
    ArgosEye.pendingPeriodicFile = filename
end

function ArgosEye.pollPeriodicResponse()
    if not ArgosEye.pendingPeriodicFile then return end

    local resp = ArgosEye.readResponse(ArgosEye.pendingPeriodicFile)
    if not resp then return end
    ArgosEye.pendingPeriodicFile = nil

    if resp:find('"error"') then
        print("[ArgosEye] Periodic check API error")
        return
    end

    for entry in resp:gmatch('{[^{}]+}') do
        local valid = entry:find('"valid"%s*:%s*true')
        local hban = entry:find('"hban"%s*:%s*true')
        local oddsUserId = entry:match('"userId"%s*:%s*(%d+)')
        local strUserId = entry:match('"userId"%s*:%s*"(%d+)"')
        local userId = oddsUserId or strUserId

        if userId then
            userId = tostring(userId)
            local data = ArgosEye.trackedPlayers[userId]
            if data and data.player then
                if not valid then
                    print("[ArgosEye] Periodic: " .. userId .. " has NO anticheat")
                    if ArgosEye.KICK_ENABLED then
                        data.player:disconnect()
                    end
                elseif hban then
                    local reason = entry:match('"hbanMessage"%s*:%s*"([^"]*)"') or "Banned"
                    print("[ArgosEye] Periodic: HBAN " .. userId .. ": " .. reason)
                    if ArgosEye.KICK_ENABLED then
                        data.player:disconnect()
                    end
                end
            end
        end
    end
end

-- ============================================================
-- AFK detection (matches Rust: CheckAfkPlayers / DoNotChangeMe = 300f)
-- ============================================================

function ArgosEye.checkAfk()
    local players = getOnlinePlayers()
    if not players then return end

    local now = getTimestampMs()
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player and player:isAlive() then
            local ok, steamId = pcall(function() return tostring(player:getSteamID()) end)
            if ok and steamId then
                local x = player:getX()
                local y = player:getY()

                local last = ArgosEye.lastPositions[steamId]
                if not last then
                    ArgosEye.lastPositions[steamId] = {x = x, y = y}
                    ArgosEye.lastMoveTime[steamId] = now
                else
                    local dx = math.abs(x - last.x)
                    local dy = math.abs(y - last.y)
                    if dx > 0.1 or dy > 0.1 then
                        ArgosEye.lastPositions[steamId] = {x = x, y = y}
                        ArgosEye.lastMoveTime[steamId] = now
                        ArgosEye.afkPlayers[steamId] = nil
                    else
                        local elapsed = (now - (ArgosEye.lastMoveTime[steamId] or now)) / 1000
                        if elapsed >= ArgosEye.AFK_THRESHOLD then
                            ArgosEye.afkPlayers[steamId] = true
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================
-- Player death (matches Rust: OnPlayerDeath)
-- Sends to: /internal_server_death
-- ============================================================

function ArgosEye.onPlayerDeath(player)
    if not player then return end
    local ok, steamId = pcall(function() return tostring(player:getSteamID()) end)
    if not ok then return end

    local json = string.format(
        '{"timestamp":%d,"victimId":"%s","attackerId":"N/A","attackerHealth":"0","victimHealth":"0","weapon":"Unknown","hitBone":"Body","distance":0}',
        math.floor(getTimestampMs() / 1000), steamId
    )
    ArgosEye.writeRequest("player_death_", json)
end

-- ============================================================
-- Chat logging (matches Rust: OnPlayerChat / OnUserCommand)
-- Sends to: /internal_server_chat_logs
-- ============================================================

function ArgosEye.queueChatLog(player, message, msgType, channel, isCommand)
    if not player or not message or message == "" then return end
    local ok, steamId = pcall(function() return tostring(player:getSteamID()) end)
    if not ok then return end
    local ok2, name = pcall(function() return player:getUsername() end)
    if not ok2 then name = "unknown" end

    name = ArgosEye.escapeJson(name or "unknown")
    local msg = ArgosEye.escapeJson(message)
    if #msg > 600 then msg = msg:sub(1, 600) end

    table.insert(ArgosEye.pendingChatLogs, string.format(
        '{"timestamp":%d,"userId":"%s","playerName":"%s","message":"%s","type":"%s","channel":"%s","isCommand":%s}',
        math.floor(getTimestampMs() / 1000), steamId, name, msg, msgType, channel,
        isCommand and "true" or "false"
    ))

    if #ArgosEye.pendingChatLogs > 4000 then
        local excess = #ArgosEye.pendingChatLogs - 4000
        for _ = 1, excess do table.remove(ArgosEye.pendingChatLogs, 1) end
    end
end

function ArgosEye.flushChatLogs()
    if #ArgosEye.pendingChatLogs == 0 then return end
    local json = "[" .. table.concat(ArgosEye.pendingChatLogs, ",") .. "]"
    ArgosEye.pendingChatLogs = {}
    ArgosEye.writeRequest("chat_logs_", json)
end

-- ============================================================
-- Cleanup (matches Rust: Unload / OnServerShutdown)
-- ============================================================

function ArgosEye.cleanup()
    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local player = players:get(i)
            if player then
                local pjson = ArgosEye.buildPlayerJson(player, false)
                if pjson then
                    ArgosEye.writeRequest("player_check_", "[" .. pjson .. "]")
                end
            end
        end
    end
    ArgosEye.flushChatLogs()
end

-- ============================================================
-- Event hooks
-- ============================================================

local tickCounter = 0
local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter % 60 == 0 then
        ArgosEye.pollResponses()
        ArgosEye.pollPeriodicResponse()
    end
end

local function onEveryMinute()
    ArgosEye.periodicCheck()
    ArgosEye.sendServerInfo()
    ArgosEye.checkAfk()
    ArgosEye.flushChatLogs()
end

local function onServerStarted()
    ArgosEye.serverStartTime = getTimestampMs()
    ArgosEye.parsePlayerIPs()

    print("[ArgosEye] Server-side AntiCheat mod loaded! (KICK_ENABLED=" .. tostring(ArgosEye.KICK_ENABLED) .. ")")
    print("[ArgosEye] Make sure ArgosEyeBridge is running.")

    ArgosEye.sendServerInfo()

    Events.OnTick.Add(onTick)
    Events.EveryOneMinute.Add(onEveryMinute)
end

local function onConnected(player)
    ArgosEye.onPlayerConnect(player)
end

local function onDisconnected(player)
    ArgosEye.onPlayerDisconnect(player)
end

local function onDeath(player)
    ArgosEye.onPlayerDeath(player)
end

Events.OnServerStarted.Add(onServerStarted)
Events.OnCreatePlayer.Add(onConnected)
Events.OnPlayerDeath.Add(onDeath)

if Events.OnPlayerDisconnect then
    Events.OnPlayerDisconnect.Add(onDisconnected)
end
