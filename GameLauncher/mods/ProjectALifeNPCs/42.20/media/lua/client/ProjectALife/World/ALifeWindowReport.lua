ProjectALife = ProjectALife or {}

local WindowReport = { reported = {}, nextAtMs = 0, intervalMs = 1000, chunkTiles = 8 }
ProjectALife.WindowReport = WindowReport

function WindowReport.chunkWidth()
    if type(getCell) ~= "function" then return nil end
    local ok, tiles = pcall(function() return getCell():getWidthInTiles() end)
    tiles = ok and tonumber(tiles) or nil
    if tiles == nil or tiles <= 0 then return nil end
    return math.floor(tiles / WindowReport.chunkTiles)
end

function WindowReport.send()
    if type(isClient) ~= "function" or not isClient() or type(sendClientCommand) ~= "function"
            or type(getSpecificPlayer) ~= "function" then return 0 end
    local width, sent = nil, 0
    for index = 0, 3 do
        local player = getSpecificPlayer(index)
        local id = player ~= nil and player.getOnlineID ~= nil and tonumber(player:getOnlineID()) or -1
        if player ~= nil and id >= 0 and WindowReport.reported[index] ~= player then
            width = width or WindowReport.chunkWidth()
            if width == nil then return sent end
            sendClientCommand(player, "ProjectALife", "windowWidth", { width = width })
            WindowReport.reported[index] = player
            sent = sent + 1
        end
    end
    return sent
end

function WindowReport.tick()
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    if now < WindowReport.nextAtMs then return end
    WindowReport.nextAtMs = now + WindowReport.intervalMs
    pcall(WindowReport.send)
end

if type(Events) == "table" and Events.OnTick ~= nil and type(Events.OnTick.Add) == "function" then
    Events.OnTick.Add(WindowReport.tick)
end

return WindowReport
