require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.CompatRegistry
if ProjectALife.RVInteriorAdapter ~= nil then return ProjectALife.RVInteriorAdapter end
local Adapter = { installed = false, modId = "PROJECTRVInterior42",
    region = { id = "rv_interior", x1 = 22272, y1 = 11776, x2 = 25087, y2 = 12799 } }
ProjectALife.RVInteriorAdapter = Adapter

function Adapter.inside(x, y)
    local r = Adapter.region
    return x ~= nil and y ~= nil and x >= r.x1 and x < r.x2 + 1 and y >= r.y1 and y < r.y2 + 1
end

function Adapter.anchor(player)
    local x, y = Registry.ask(player, "getX"), Registry.ask(player, "getY")
    if not Adapter.inside(x, y) then return nil end
    local playerData = Registry.ask(player, "getModData")
    local id = type(playerData) == "table" and playerData.projectRV_playerId or nil
    if id == nil or type(ModData) ~= "table" or type(ModData.exists) ~= "function"
            or type(ModData.get) ~= "function" then return nil end
    local exists, present = pcall(ModData.exists, "modPROJECTRVInterior")
    if not exists or not present then return nil end
    local ok, data = pcall(ModData.get, "modPROJECTRVInterior")
    if not ok or type(data) ~= "table" then return nil end
    local entry = type(data.Players) == "table" and data.Players[id] or nil
    local parked = type(entry) == "table" and entry.VehicleId and type(data.Vehicles) == "table"
        and data.Vehicles[entry.VehicleId] or nil
    if type(parked) ~= "table" or tonumber(parked.x) == nil or tonumber(parked.y) == nil then return nil end
    return { x = tonumber(parked.x), y = tonumber(parked.y), z = tonumber(parked.z) or 0 }
end

function Adapter.active()
    local compat = ProjectALife.ModCompat
    return compat ~= nil and type(compat.isActive) == "function" and compat.isActive(Adapter.modId)
end

function Adapter.detect()
    local policy, locator = ProjectALife.SpawnPolicy, ProjectALife.PlayerLocator
    return type(policy) == "table" and type(policy.excludedRegions) == "table"
        and type(locator) == "table" and type(locator.anchors) == "table"
end

function Adapter.install()
    if Adapter.installed then return true end
    if not Adapter.active() or not Adapter.detect() then return false end
    local policy, locator = ProjectALife.SpawnPolicy, ProjectALife.PlayerLocator
    Adapter.policy, Adapter.locator = policy, locator
    table.insert(policy.excludedRegions, Adapter.region)
    table.insert(locator.anchors, Adapter.anchor)
    Adapter.installed = true
    return true
end

function Adapter.undo()
    for _, row in ipairs({ { Adapter.policy, "excludedRegions", Adapter.region }, { Adapter.locator, "anchors", Adapter.anchor } }) do
        local list = row[1] and row[1][row[2]]
        for index = #(list or {}), 1, -1 do if list[index] == row[3] then table.remove(list, index) end end
    end
    Adapter.installed = false
end

Registry.register({ id = "RVInterior", mods = { "PROJECTRVInterior42" }, phase = "server",
    detect = Adapter.detect, apply = Adapter.install, undo = Adapter.undo })

return Adapter
