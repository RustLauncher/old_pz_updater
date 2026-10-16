ProjectALife = ProjectALife or {}

local Locks = {
    TAG = "ProjectALife.RegionLocks.v1",

    regions = {
        { id = "louisville", x1 = 9500, y1 = 0, x2 = 15500, y2 = 6640 },
    },
    unlocked = {},
    adapters = {},
    metrics = { refused = 0, unlocked = 0 },
    loaded = false,
}
ProjectALife.RegionLocks = Locks

function Locks.regionAt(x, y)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return nil end
    for _, region in ipairs(Locks.regions) do
        if x >= region.x1 and x <= region.x2 and y >= region.y1 and y <= region.y2 then
            return region
        end
    end
    return nil
end

local function store()
    if type(Locks.adapters.getOrCreate) == "function" then return Locks.adapters.getOrCreate(Locks.TAG) end
    if ModData ~= nil and type(ModData.getOrCreate) == "function" then
        local ok, value = pcall(ModData.getOrCreate, Locks.TAG)
        if ok and type(value) == "table" then return value end
    end
    return nil
end

function Locks.load()
    if Locks.loaded then return true end
    Locks.loaded = true
    local value = store()
    if type(value) == "table" and type(value.unlocked) == "table" then
        for id, flag in pairs(value.unlocked) do
            if flag == true then Locks.unlocked[id] = true end
        end
    end
    return true
end

local function persist()
    local value = store()
    if type(value) ~= "table" then return false end
    value.unlocked = value.unlocked or {}
    for id in pairs(Locks.unlocked) do value.unlocked[id] = true end
    if type(Locks.adapters.transmit) == "function" then pcall(Locks.adapters.transmit, Locks.TAG) end
    if ModData ~= nil and type(ModData.transmit) == "function" then pcall(ModData.transmit, Locks.TAG) end
    return true
end

function Locks.locked(x, y)
    Locks.load()
    local region = Locks.regionAt(x, y)
    if region == nil then return false end
    return Locks.unlocked[region.id] ~= true
end

function Locks.refuse(x, y)
    if not Locks.locked(x, y) then return false end
    Locks.metrics.refused = Locks.metrics.refused + 1
    return true
end

function Locks.unlock(id)
    if Locks.unlocked[id] == true then return false end
    Locks.unlocked[id] = true
    Locks.metrics.unlocked = Locks.metrics.unlocked + 1
    persist()
    return true
end

function Locks.tick(players)
    Locks.load()
    local opened = 0
    for _, p in ipairs(players or {}) do
        local region = Locks.regionAt(p and p.x, p and p.y)
        if region ~= nil and Locks.unlock(region.id) then opened = opened + 1 end
    end
    return opened
end

function Locks.reset()
    Locks.unlocked, Locks.loaded = {}, false
    Locks.metrics = { refused = 0, unlocked = 0 }
    return true
end

return Locks
