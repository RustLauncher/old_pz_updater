local SERVER_NAME = "Old School PZ"
local SERVER_IP   = "104.234.119.85"
local SERVER_PORT = 16261

local skipDone = false
local patchDone = false
local menuPatchDone = false

local function hasOurServer(mp)
    local items = mp.accountList and mp.accountList.items
    if not items then return false end
    for _, entry in ipairs(items) do
        if entry.item and entry.item.type == "server" and entry.item.server then
            local s = entry.item.server
            if s:getIp() == SERVER_IP and s:getPort() == SERVER_PORT then
                return true
            end
        end
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

local function injectServer(mp, origRefresh)
    if not Server or not addServerToAccountList then return end
    local s = Server.new()
    s:setName(SERVER_NAME)
    s:setIp(SERVER_IP)
    s:setPort(SERVER_PORT)
    s:setServerPassword("")
    addServerToAccountList(s)
    origRefresh(mp)
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
            if not hasOurServer(self) then
                pcall(injectServer, self, origRefresh)
            end
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

    patchMultiplayerUI(ms.multiplayer)
    patchMainMenu()
    ms.bottomPanel:setVisible(false)
    ms.multiplayer:setVisible(true)
    ms.multiplayer:requestServerList()
    skipDone = true
end

local function onTick()
    if not skipDone then
        pcall(trySkip)
        return
    end
    pcall(patchMainMenu)
    if menuPatchDone then
        Events.OnFETick.Remove(onTick)
    end
end

Events.OnFETick.Add(onTick)
