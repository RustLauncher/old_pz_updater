local SERVER_NAME = "LatamRust PZ"
local SERVER_IP   = "104.234.119.85"
local SERVER_PORT = 16261

local skipDone = false
local patchDone = false

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

    local origRefresh = mp.refreshList
    if origRefresh then
        mp.refreshList = function(self)
            origRefresh(self)
            local items = self.accountList and self.accountList.items
            if items then
                for i = #items, 1, -1 do
                    if items[i] and items[i].item and items[i].item.type == "new_server" then
                        table.remove(items, i)
                    end
                end
            end
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
    ms.bottomPanel:setVisible(false)
    ms.multiplayer:setVisible(true)
    ms.multiplayer:requestServerList()
    skipDone = true
end

local function onTick()
    if skipDone then
        Events.OnFETick.Remove(onTick)
        return
    end
    pcall(trySkip)
end

Events.OnFETick.Add(onTick)
