local SERVER_NAME = "LatamRust PZ"
local SERVER_IP   = "104.234.119.85"
local SERVER_PORT = 16261

local skipDone = false

local function ensureServerInFavorites()
    local ok, servers = pcall(getServerList)
    if not ok or not servers then return end
    for i = 0, servers:size() - 1 do
        local s = servers:get(i)
        if s:getIp() == SERVER_IP and s:getPort() == SERVER_PORT then
            return
        end
    end
    local s = Server.new()
    s:setName(SERVER_NAME)
    s:setIp(SERVER_IP)
    s:setPort(SERVER_PORT)
    s:setServerPassword("")
    addServerToAccountList(s)
end

local function trySkip()
    if skipDone then return end
    if not MainScreen or not MainScreen.instance then return end
    local ms = MainScreen.instance
    if not ms.multiplayer or not ms.bottomPanel then return end

    skipDone = true
    pcall(ensureServerInFavorites)
    ms.bottomPanel:setVisible(false)
    ms.multiplayer:setVisible(true)
    ms.multiplayer:requestServerList()
end

local function onTick()
    if skipDone then
        Events.OnFETick.Remove(onTick)
        return
    end
    trySkip()
end

Events.OnFETick.Add(onTick)
