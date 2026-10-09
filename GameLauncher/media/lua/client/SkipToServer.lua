local SERVER_NAME = "Old School PZ"
local SERVER_IP   = "104.234.119.85"
local SERVER_PORT = 16261

local skipDone = false
local patchDone = false
local menuPatchDone = false
local serverConfirmed = false
local tickCount = 0

local function patchTabs(mp)
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
end

local function stripAddServer(mp)
    local items = mp.accountList and mp.accountList.items
    if not items then return end
    for i = #items, 1, -1 do
        if items[i] and items[i].item and items[i].item.type == "new_server" then
            table.remove(items, i)
        end
    end
end

local function hasServer(mp)
    local items = mp.accountList and mp.accountList.items
    if not items then return false end
    for _, entry in ipairs(items) do
        if entry.item and entry.item.type == "server" then
            return true
        end
    end
    return false
end

local function patchMainMenu()
    if menuPatchDone then return end
    if not MainScreen or not MainScreen.instance then return end
    local ms = MainScreen.instance
    if not ms.bottomPanel then return end
    menuPatchDone = true
    local hide = {
        ms.tutorialOption,
        ms.survivalOption,
        ms.onlineCoopOption,
        ms.modsOption,
        ms.creditOption,
        ms.loadOption,
        ms.latestSaveOption,
        ms.workshopOption,
    }
    for _, item in ipairs(hide) do
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

    patchTabs(ms.multiplayer)
    patchMainMenu()
    ms.bottomPanel:setVisible(false)
    ms.multiplayer:setVisible(true)
    ms.multiplayer:requestServerList()
    stripAddServer(ms.multiplayer)
    skipDone = true
end

local function tryEnsureServer()
    if serverConfirmed then return end
    if not MainScreen or not MainScreen.instance then return end
    local ms = MainScreen.instance
    local mp = ms.multiplayer
    if not mp then return end

    if hasServer(mp) then
        serverConfirmed = true
        stripAddServer(mp)
        return
    end

    if Server and addServerToAccountList then
        local s = Server.new()
        s:setName(SERVER_NAME)
        s:setIp(SERVER_IP)
        s:setPort(SERVER_PORT)
        s:setServerPassword("")
        addServerToAccountList(s)
        mp:refreshList()
        stripAddServer(mp)
        if hasServer(mp) then
            serverConfirmed = true
        end
    end
end

local function onTick()
    tickCount = tickCount + 1

    if not skipDone then
        pcall(trySkip)
        return
    end

    pcall(patchMainMenu)

    if not serverConfirmed and tickCount < 600 then
        if tickCount % 10 == 0 then
            pcall(tryEnsureServer)
        end
        return
    end

    Events.OnFETick.Remove(onTick)
end

Events.OnFETick.Add(onTick)
