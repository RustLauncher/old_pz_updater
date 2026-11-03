require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifeWatchdog"

ProjectALife = ProjectALife or {}

local Corpses = {
    settings = {
        enabled = true,
        beatMs = 5000,
        squareBudget = 96,
        removeBudget = 2,
        restMs = 60000,
        homeCap = 24,
        serverReachTiles = 25,
    },
    anchorKeys = { "home", "stanceAnchor", "garrisonPost" },
    adapters = {},
    sweeps = {},
    nextAtMs = 0,
    metrics = { beats = 0, homes = 0, squares = 0, removed = 0, claimed = 0, seen = 0 },
}
ProjectALife.ResidentCorpses = Corpses

function Corpses.configure(adapters)
    Corpses.adapters = type(adapters) == "table" and adapters or {}
    if Corpses.adapters.enabled ~= nil then Corpses.settings.enabled = Corpses.adapters.enabled == true end
    return true
end

function Corpses.reset()
    Corpses.adapters = {}
    Corpses.settings.enabled = true
    Corpses.sweeps = {}
    Corpses.nextAtMs = 0
    Corpses.metrics = { beats = 0, homes = 0, squares = 0, removed = 0, claimed = 0, seen = 0 }
end

function Corpses.nowMs()
    if type(Corpses.adapters.nowMs) == "function" then return tonumber(Corpses.adapters.nowMs()) or 0 end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Corpses.cell()
    if type(Corpses.adapters.cell) == "function" then return Corpses.adapters.cell() end
    if type(getCell) ~= "function" then return nil end
    return getCell()
end

function Corpses.anchorOf(memory)
    if type(memory) ~= "table" then return nil end
    for _, key in ipairs(Corpses.anchorKeys) do
        local at = memory[key]
        if type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then return at end
    end
    return nil
end

function Corpses.resident(memory)
    return type(memory) == "table" and memory.visit == nil and memory.guest == nil
end

function Corpses.homeOf(cell, shell, anchor)
    if shell == nil or type(shell.getCurrentSquare) ~= "function" then return nil end
    local here = shell:getCurrentSquare()
    if here == nil or type(here.getBuilding) ~= "function" then return nil end
    local building = here:getBuilding()
    if building == nil or type(building.getDef) ~= "function" then return nil end
    local at = cell:getGridSquare(math.floor(anchor.x), math.floor(anchor.y), math.floor(tonumber(anchor.z) or 0))
    if at == nil or type(at.getBuilding) ~= "function" or at:getBuilding() ~= building then return nil end
    local def = building:getDef()
    if def == nil then return nil end
    local x1, y1, x2, y2 = def:getX(), def:getY(), def:getX2() - 1, def:getY2() - 1
    local z1, z2 = 0, 0
    if type(def.getMinLevel) == "function" then z1 = def:getMinLevel() end
    if type(def.getMaxLevel) == "function" then z2 = def:getMaxLevel() end
    return { key = tostring(x1) .. ":" .. tostring(y1) .. ":" .. tostring(x2) .. ":" .. tostring(y2),
        building = building, square = here, x1 = x1, y1 = y1, x2 = x2, y2 = y2, z1 = z1, z2 = math.max(z1, z2) }
end

function Corpses.homes(cell)
    local watchdog, registry = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    local found, list = {}, {}
    local read = registry.peek or registry.read
    for index = 1, #watchdog.order do
        local uid = watchdog.order[index]
        local binding = watchdog.bindings[uid]
        local actor = binding ~= nil and binding.shell ~= nil and read(uid) or nil
        local anchor = actor ~= nil and actor.lifecycle == "active" and Corpses.resident(actor.memory)
            and Corpses.anchorOf(actor.memory) or nil
        if anchor ~= nil then
            local home = Corpses.homeOf(cell, binding.shell, anchor)
            if home ~= nil and found[home.key] == nil then
                found[home.key] = true
                list[#list + 1] = home
                if #list >= Corpses.settings.homeCap then break end
            end
        end
    end
    return list
end

function Corpses.claimed(home)
    if type(Corpses.adapters.claimed) == "function" then return Corpses.adapters.claimed(home) == true end
    local policy = ProjectALife.SpawnPolicy
    if policy ~= nil and type(policy.inPlayerBase) == "function" then
        local center = { x = (home.x1 + home.x2) / 2, y = (home.y1 + home.y2) / 2, z = 0 }
        local ok, inside = pcall(policy.inPlayerBase, center, 10)
        if ok and inside == true then return true end
    end
    if SafeHouse == nil or type(SafeHouse.isSafeHouse) ~= "function" then return false end
    local ok, house = pcall(SafeHouse.isSafeHouse, home.square, nil, true)
    return ok and house ~= nil
end

function Corpses.nearPlayer(square)
    local locator = ProjectALife.PlayerLocator
    if locator == nil or type(locator.list) ~= "function" or type(locator.position) ~= "function"
            or type(square.getX) ~= "function" or type(square.getY) ~= "function" then return false end
    local x, y = square:getX(), square:getY()
    local reach = tonumber(Corpses.settings.serverReachTiles) or 25
    for _, player in ipairs(locator.list()) do
        local at = locator.position(player)
        if at ~= nil then
            local dx, dy = at.x - x, at.y - y
            if dx * dx + dy * dy <= reach * reach then return true end
        end
    end
    return false
end

function Corpses.watched(square)
    if type(Corpses.adapters.watched) == "function" then return Corpses.adapters.watched(square) == true end
    if type(isServer) == "function" and isServer() then return Corpses.nearPlayer(square) end
    if type(getSpecificPlayer) ~= "function" or type(square.isCanSee) ~= "function" then return false end
    for index = 0, 3 do
        local player = getSpecificPlayer(index)
        if player ~= nil and not (type(player.isAsleep) == "function" and player:isAsleep() == true)
                and square:isCanSee(index) == true then
            return true
        end
    end
    return false
end

function Corpses.ours(body)
    if type(body.hasModData) ~= "function" or body:hasModData() ~= true then return false end
    if type(body.getModData) ~= "function" then return false end
    local data = body:getModData()
    if type(data) ~= "table" then return false end
    for key in pairs(data) do
        if type(key) == "string" and string.sub(key, 1, 11) == "ProjectALif" then return true end
    end
    return false
end

function Corpses.eligible(body)
    if body == nil then return false end
    if type(body.isPlayer) ~= "function" or body:isPlayer() == true then return false end
    if type(body.isZombie) ~= "function" or body:isZombie() ~= true then return false end
    if type(body.isAnimal) == "function" and body:isAnimal() == true then return false end
    if type(body.isFakeDead) == "function" and body:isFakeDead() == true then return false end
    return not Corpses.ours(body)
end

function Corpses.clearSquare(square, budget)
    if type(square.getDeadBodys) ~= "function" or type(square.removeCorpse) ~= "function" then return 0 end
    local bodies = square:getDeadBodys()
    if bodies == nil or type(bodies.size) ~= "function" or bodies:size() == 0 then return 0 end
    if Corpses.watched(square) then
        Corpses.metrics.seen = Corpses.metrics.seen + 1
        return 0
    end
    local removed = 0
    for index = bodies:size() - 1, 0, -1 do
        if budget.removals <= 0 then break end
        local body = bodies:get(index)
        if Corpses.eligible(body) then
            square:removeCorpse(body, false)
            budget.removals = budget.removals - 1
            removed = removed + 1
        end
    end
    Corpses.metrics.removed = Corpses.metrics.removed + removed
    return removed
end

function Corpses.sweep(cell, home, now, budget)
    local state = Corpses.sweeps[home.key]
    if state == nil then
        state = { index = 0, restUntilMs = 0 }
        Corpses.sweeps[home.key] = state
    end
    if now < state.restUntilMs then return 0 end
    if Corpses.claimed(home) then
        Corpses.metrics.claimed = Corpses.metrics.claimed + 1
        state.restUntilMs = now + Corpses.settings.restMs
        return 0
    end
    local width, height = home.x2 - home.x1 + 1, home.y2 - home.y1 + 1
    local floor = width * height
    local total = floor * (home.z2 - home.z1 + 1)
    local removed = 0
    while budget.squares > 0 and budget.removals > 0 do
        if state.index >= total then
            state.index = 0
            state.restUntilMs = now + Corpses.settings.restMs
            break
        end
        local at = state.index
        state.index = at + 1
        budget.squares = budget.squares - 1
        Corpses.metrics.squares = Corpses.metrics.squares + 1
        local within = at % floor
        local square = cell:getGridSquare(home.x1 + within % width, home.y1 + math.floor(within / width),
            home.z1 + math.floor(at / floor))
        if square ~= nil and type(square.getBuilding) == "function" and square:getBuilding() == home.building then
            removed = removed + Corpses.clearSquare(square, budget)
            if budget.removals <= 0 then state.index = at end
        end
    end
    return removed
end

function Corpses.tick(now)
    if Corpses.settings.enabled ~= true then return 0 end
    if type(isClient) == "function" and isClient() then return 0 end
    now = tonumber(now) or Corpses.nowMs()
    if now < Corpses.nextAtMs then return 0 end
    Corpses.nextAtMs = now + Corpses.settings.beatMs
    Corpses.metrics.beats = Corpses.metrics.beats + 1
    local cell = Corpses.cell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return 0 end
    local homes = Corpses.homes(cell)
    Corpses.metrics.homes = #homes
    local budget = { squares = Corpses.settings.squareBudget, removals = Corpses.settings.removeBudget }
    local removed = 0
    for _, home in ipairs(homes) do
        if budget.squares <= 0 or budget.removals <= 0 then break end
        removed = removed + Corpses.sweep(cell, home, now, budget)
    end
    return removed
end

return Corpses
