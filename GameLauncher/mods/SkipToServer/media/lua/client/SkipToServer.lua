local SERVER_NAME = "LatamRust PZ"
local SERVER_IP   = "104.234.119.85"
local SERVER_PORT = 16261

local function ensureServerInFavorites()
    local servers = getServerList()
    if servers then
        for i = 0, servers:size() - 1 do
            local s = servers:get(i)
            if s:getIp() == SERVER_IP and s:getPort() == SERVER_PORT then
                return
            end
        end
    end
    local s = Server.new()
    s:setName(SERVER_NAME)
    s:setIp(SERVER_IP)
    s:setPort(SERVER_PORT)
    s:setServerPassword("")
    addServerToAccountList(s)
end

local function skipToMultiplayer()
    local ms = MainScreen.instance
    if not ms or not ms.multiplayer then return end

    ensureServerInFavorites()

    ms.bottomPanel:setVisible(false)
    ms.multiplayer:setVisible(true)
    ms.multiplayer:requestServerList()
end

local skipDone = false

local function onMainMenuEnter()
    if skipDone then return end
    skipDone = true
    skipToMultiplayer()
end

Events.OnMainMenuEnter.Add(onMainMenuEnter)
