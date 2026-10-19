if not isServer() then return end

local ArgosEye = {}

ArgosEye.CHECK_INTERVAL = 60
ArgosEye.POLL_INTERVAL = 2
ArgosEye.AFK_THRESHOLD = 300
ArgosEye.CHAT_FLUSH_SECONDS = 60
ArgosEye.KICK_ENABLED = false

ArgosEye.kickMessage = "You dont have AntiCheat - Download AntiCheat"
ArgosEye.trackedPlayers = {}
ArgosEye.lastPositions = {}
ArgosEye.lastMoveTime = {}
ArgosEye.afkPlayers = {}
ArgosEye.pendingChatLogs = {}
ArgosEye.requestCounter = 0
ArgosEye.baseDir = nil

function ArgosEye.getBaseDir()
    if ArgosEye.baseDir then return ArgosEye.baseDir end
    ArgosEye.baseDir = "ArgosEye"
    return ArgosEye.baseDir
end

function ArgosEye.writeRequest(prefix, jsonStr)
    ArgosEye.requestCounter = ArgosEye.requestCounter + 1
    local filename = prefix .. ArgosEye.requestCounter .. ".json"
    local path = ArgosEye.getBaseDir() .. "/requests/" .. filename
    local writer = getFileWriter(path, true, false)
    if writer then
        writer:write(jsonStr)
        writer:close()
    end
    return filename
end

function ArgosEye.readResponse(filename)
    local respName = filename:gsub("%.json$", "_resp.json")
    local path = ArgosEye.getBaseDir() .. "/responses/" .. respName
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

function ArgosEye.escapeJson(str)
    if not str then return "" end
    str = str:gsub('\\', '\\\\')
    str = str:gsub('"', '\\"')
    str = str:gsub('\n', '\\n')
    str = str:gsub('\r', '\\r')
    str = str:gsub('\t', '\\t')
    return str
end

function ArgosEye.buildPlayerJson(player, isConnected)
    local userId = tostring(player:getSteamID())
    local name = ArgosEye.escapeJson(player:getUsername())
    local isAfk = ArgosEye.afkPlayers[userId] or false

    return string.format(
        '{"userId":"%s","playerName":"%s","playerIp":"0.0.0.0","IsConnected":%s,"IsAfk":%s}',
        userId, name,
        isConnected and "true" or "false",
        isAfk and "true" or "false"
    )
end

function ArgosEye.onPlayerConnect(player)
    if not player then return end
    local steamId = tostring(player:getSteamID())
    ArgosEye.trackedPlayers[steamId] = {
        player = player,
        validated = false,
        pendingFile = nil,
        connectTime = getTimestampMs()
    }

    local json = "[" .. ArgosEye.buildPlayerJson(player, true) .. "]"
    local filename = ArgosEye.writeRequest("player_check_", json)
    ArgosEye.trackedPlayers[steamId].pendingFile = filename

    print("[ArgosEye] Player connecting: " .. player:getUsername() .. " (" .. steamId .. ")")
end

function ArgosEye.onPlayerDisconnect(player)
    if not player then return end
    local steamId = tostring(player:getSteamID())

    local json = "[" .. ArgosEye.buildPlayerJson(player, false) .. "]"
    ArgosEye.writeRequest("player_check_", json)

    ArgosEye.trackedPlayers[steamId] = nil
    ArgosEye.lastPositions[steamId] = nil
    ArgosEye.lastMoveTime[steamId] = nil
    ArgosEye.afkPlayers[steamId] = nil

    print("[ArgosEye] Player disconnected: " .. player:getUsername())
end

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

function ArgosEye.periodicCheck()
    local players = getOnlinePlayers()
    if not players or players:size() == 0 then return end

    local parts = {}
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player then
            table.insert(parts, ArgosEye.buildPlayerJson(player, true))
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
        local userId = entry:match('"userId"%s*:%s*(%d+)')

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
                    print("[ArgosEye] Periodic: HBAN detected " .. userId)
                    if ArgosEye.KICK_ENABLED then
                        data.player:disconnect()
                    end
                end
            end
        end
    end
end

function ArgosEye.sendServerInfo()
    local hostname = ArgosEye.escapeJson(getServerOptions():getOption("PublicName") or "PZ Server")
    local maxPlayers = getServerOptions():getInteger("MaxPlayers") or 16
    local players = getOnlinePlayers()
    local playerCount = players and players:size() or 0

    local json = string.format(
        '{"hostname":"%s","version":"PZ 42","max_players":%d,"current_players":%d}',
        hostname, maxPlayers, playerCount
    )

    ArgosEye.writeRequest("server_info_", json)
end

function ArgosEye.checkAfk()
    local players = getOnlinePlayers()
    if not players then return end

    local now = getTimestampMs()
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player and player:isAlive() then
            local steamId = tostring(player:getSteamID())
            local x = player:getX()
            local y = player:getY()
            local z = player:getZ()

            local last = ArgosEye.lastPositions[steamId]
            if not last then
                ArgosEye.lastPositions[steamId] = {x = x, y = y, z = z}
                ArgosEye.lastMoveTime[steamId] = now
            else
                local dx = math.abs(x - last.x)
                local dy = math.abs(y - last.y)
                if dx > 0.1 or dy > 0.1 then
                    ArgosEye.lastPositions[steamId] = {x = x, y = y, z = z}
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

function ArgosEye.onPlayerDeath(player)
    if not player then return end
    local steamId = tostring(player:getSteamID())
    local json = string.format(
        '{"timestamp":%d,"victimId":"%s"}',
        math.floor(getTimestampMs() / 1000), steamId
    )
    ArgosEye.writeRequest("player_death_", json)
end

function ArgosEye.queueChatLog(player, message, msgType, channel, isCommand)
    if not player or not message or message == "" then return end
    local steamId = tostring(player:getSteamID())
    local name = ArgosEye.escapeJson(player:getUsername())
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

local tickCounter = 0
local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter % (ArgosEye.POLL_INTERVAL * 30) == 0 then
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
    print("[ArgosEye] Server-side AntiCheat mod loaded!")
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
