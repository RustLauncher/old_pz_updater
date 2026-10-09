local SERVER_NAME = "Old School PZ"
local SERVER_IP   = "104.234.119.85"
local SERVER_PORT = 16261

local skipDone = false
local serverAdded = false
local patchDone = false
local menuPatchDone = false
local addRetries = 0

local function isServerInFavorites()
    if not getServerList then return false end
    local ok, servers = pcall(getServerList)
    if not ok or not servers then return false end
    local ok2, result = pcall(function()
        for _, s in ipairs(servers) do
            if s:getIp() == SERVER_IP and s:getPort() == SERVER_PORT then
                return true
            end
        end
        return false
    end)
    return ok2 and result
end

local function tryAddServer()
    if serverAdded then return true end
    if isServerInFavorites() then
        serverAdded = true
        return true
    end
    if not Server or not addServerToAccountList then return false end
    local ok = pcall(function()
        local s = Server.new()
        s:setName(SERVER_NAME)
        s:setIp(SERVER_IP)
        s:setPort(SERVER_PORT)
        s:setServerPassword("")
        addServerToAccountList(s)
    end)
    if ok and isServerInFavorites() then
        serverAdded = true
        return true
    end
    return false
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

    tryAddServer()
    patchMultiplayerUI(ms.multiplayer)
    patchMainMenu()
    ms.bottomPanel:setVisible(false)
    ms.multiplayer:setVisible(true)
    ms.multiplayer:requestServerList()
    removeNewServerItem(ms.multiplayer)
    skipDone = true
end

local function onTick()
    if not skipDone then
        pcall(trySkip)
        return
    end

    if not serverAdded then
        addRetries = addRetries + 1
        pcall(tryAddServer)
        if serverAdded then
            local ms = MainScreen and MainScreen.instance
            if ms and ms.multiplayer then
                pcall(function()
                    ms.multiplayer:refreshList()
                    removeNewServerItem(ms.multiplayer)
                end)
            end
        end
        if addRetries > 300 then
            Events.OnFETick.Remove(onTick)
        end
        return
    end

    pcall(patchMainMenu)
    if menuPatchDone then
        Events.OnFETick.Remove(onTick)
    end
end

Events.OnFETick.Add(onTick)
