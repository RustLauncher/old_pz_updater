local SERVER_NAME = "LatamRust PZ"
local SERVER_IP   = "104.234.119.85"
local SERVER_PORT = 16261

local skipDone = false
local serverAdded = false
local patchDone = false
local menuPatchDone = false

local function isServerInFavorites()
    if not getServerList then return false end
    local servers = getServerList()
    if not servers then return false end
    for _, s in ipairs(servers) do
        if s:getIp() == SERVER_IP and s:getPort() == SERVER_PORT then
            return true
        end
    end
    return false
end

local function ensureServerInFavorites()
    if serverAdded then return end
    if not getServerList or not Server or not addServerToAccountList then return end
    if isServerInFavorites() then
        serverAdded = true
        return
    end
    local s = Server.new()
    s:setName(SERVER_NAME)
    s:setIp(SERVER_IP)
    s:setPort(SERVER_PORT)
    s:setServerPassword("")
    addServerToAccountList(s)
    serverAdded = true
end

local function removeNewServerItem(mp)
    local items = mp.accountList and mp.accountList.items
    if not items then return end
    for i = #items, 1, -1 do
        if items[i] and items[i].item and items[i].item.type == "new_server" then
            table.remove(items, i)
        end
    end
end

local function patchMultiplayerUI(mp)
    if patchDone then return end
    patchDone = true

    local tabs = mp.tabs
    if tabs and tabs.viewList then
        local toRemove = nil
        for _, view in ipairs(tabs.viewList) do
            if view.view == mp.leftInternetPanel then
                toRemove = view.view
                break
            end
        end
        if toRemove then
            tabs:removeView(toRemove)
        end
    end

    if MultiplayerUI and MultiplayerUI.refreshList then
        local origRefresh = MultiplayerUI.refreshList
        MultiplayerUI.refreshList = function(self)
            origRefresh(self)
            removeNewServerItem(self)
        end
    end
end

local function patchMainMenu()
    if menuPatchDone then return end
    if not MainScreen or not MainScreen.instance then return end
    local ms = MainScreen.instance
    if not ms.bottomPanel then return end
    menuPatchDone = true

    local items = {
        ms.tutorialOption,
        ms.survivalOption,
        ms.onlineCoopOption,
        ms.modsOption,
        ms.creditOption,
        ms.loadOption,
        ms.latestSaveOption,
        ms.workshopOption,
    }
    for _, item in ipairs(items) do
        if item then
            item:setVisible(false)
        end
    end
end

local function trySkip()
    if skipDone then return end
    if not MainScreen or not MainScreen.instance then return end
    local ms = MainScreen.instance
    if not ms.multiplayer or not ms.bottomPanel then return end

    pcall(ensureServerInFavorites)
    patchMultiplayerUI(ms.multiplayer)
    patchMainMenu()
    ms.bottomPanel:setVisible(false)
    ms.multiplayer:setVisible(true)
    ms.multiplayer:requestServerList()
    removeNewServerItem(ms.multiplayer)
    skipDone = true
end

local function retryAddServer()
    if serverAdded then return end
    pcall(ensureServerInFavorites)
    if serverAdded and MainScreen and MainScreen.instance and MainScreen.instance.multiplayer then
        MainScreen.instance.multiplayer:refreshList()
    end
end

local function onTick()
    if not skipDone then
        pcall(trySkip)
        return
    end
    pcall(retryAddServer)
    if serverAdded and menuPatchDone then
        Events.OnFETick.Remove(onTick)
    end
end

Events.OnFETick.Add(onTick)
