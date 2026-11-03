-- FTZ Carts & Trolleys - multiplayer server: tells nearby players which carts on the ground are loaded
-- (clients cannot see what is inside a cart they do not hold) and keeps capacities in line with the sandbox.
if not isServer() then return end
require "FTZCarts_Shared"

local SCAN_RADIUS = 12
local EVERY_MS = 2000
local nextScan = 0

local function scanAround(player, cell)
    local list = {}
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for x = px - SCAN_RADIUS, px + SCAN_RADIUS do
        for y = py - SCAN_RADIUS, py + SCAN_RADIUS do
            local sq = cell:getGridSquare(x, y, pz)
            if sq then
                local wobs = sq:getWorldObjects()
                for i = 0, wobs:size() - 1 do
                    local wo = wobs:get(i)
                    local item = wo and wo:getItem()
                    if FTZCarts.isCart(item) then
                        FTZCarts.applyCapacity(item)
                        table.insert(list, { x = x, y = y, z = pz, id = item:getID(), full = FTZCarts.isFull(item) })
                    end
                end
            end
        end
    end
    return list
end

local function onTick()
    local now = getTimestampMs()
    if now < nextScan then return end
    nextScan = now + EVERY_MS
    local players = getOnlinePlayers()
    if not players then return end
    local cell = getCell()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            -- carts held by players
            local held = p:getPrimaryHandItem()
            if FTZCarts.isCart(held) then FTZCarts.applyCapacity(held) end
            local list = scanAround(p, cell)
            if #list > 0 then
                sendServerCommand(p, "FTZCarts", "Looks", { carts = list })
            end
        end
    end
end

Events.OnTick.Add(onTick)
