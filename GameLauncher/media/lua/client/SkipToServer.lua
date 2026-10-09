local SERVER_NAME = "LatamRust PZ"
local SERVER_IP   = "104.234.119.85"
local SERVER_PORT = 16261

local skipDone = false
local patchDone = false
local menuPatchDone = false

local HIDE_ITEMS = {
    TUTORIAL = true,
    SOLO = true,
    COOP = true,
    MODS = true,
    CREDITS = true,
    LOAD = true,
    LATESTSAVE = true,
}

local function ensureServerInFavorites()
    if not getServerList then return end
    local servers = getServerList()
    if servers then
        for _, s in ipairs(servers) do
            if s:getIp() == SERVER_IP and s:getPort() == SERVER_PORT then
                return
            end
        end
    end
    if not Server or not addServerToAccountList then return end
    local s = Server.new()
    s:setName(SERVER_NAME)
    s:setIp(SERVER_IP)
    s:setPort(SERVER_PORT)
    s:setServerPassword("")
    addServerToAccountList(s)
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

    local children = ms.bottomPanel:getChildren()
    if not children then return end

    for i = 0, children:size() - 1 do
        local child = children:get(i)
        if child and child.internal and HIDE_ITEMS[child.internal] then
            child:setVisible(false)
            child:setHeight(0)
        end
    end
end

local function trySkip()
    if skipDone then return end
    if not MainScreen or not MainScreen.instance then return end
    local ms = MainScreen.instance
    if not ms.multiplayer or not ms.bottomPanel then return end

    ensureServerInFavorites()
    patchMultiplayerUI(ms.multiplayer)
    patchMainMenu()
    ms.bottomPanel:setVisible(false)
    ms.multiplayer:setVisible(true)
    ms.multiplayer:requestServerList()
    removeNewServerItem(ms.multiplayer)
    skipDone = true
end

local function onTick()
    if skipDone then
        pcall(patchMainMenu)
        Events.OnFETick.Remove(onTick)
        return
    end
    pcall(trySkip)
end

Events.OnFETick.Add(onTick)
