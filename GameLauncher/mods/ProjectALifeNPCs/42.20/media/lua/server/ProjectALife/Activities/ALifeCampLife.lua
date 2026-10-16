require "ProjectALife/Activities/ALifeHavens"
require "ProjectALife/Loot/ALifeStashRoom"

ProjectALife = ProjectALife or {}

local Havens = ProjectALife.Havens

local Camp = {
    order = { "chop_wood", "saw_planks", "build_crate", "forage" },
    presets = { chop_wood = "chop_wood", saw_planks = "saw_planks", build_crate = "build_crate", forage = "forage" },
    settings = {
        woodPerHour = 2, plankPerHour = 1.5, cratePerHour = 0.25, foragePerHour = 0.5,
        woodCap = 40, plankCap = 30, crateCap = 6, forageCap = 20, maxElapsed = 12,
        visibleLogs = 4, visiblePlanks = 6, visibleCrates = 2, renderTiles = 60, renderEveryMs = 8000,
        crateSprite = "carpentry_01_19",
    },
    adapters = {},
    renderedAt = {},
    metrics = { offline = 0, logs = 0, planks = 0, crates = 0, foraged = 0, forageStashed = 0, forageDropped = 0, forageRefused = 0 },
    forageState = {},
    forageDailyCap = 6,
    forageEveryHours = 0.25,
    forageTable = {
        { "Base.BerryBlack", 3, 6, 9 }, { "Base.BerryBlue", 3, 6, 8 }, { "Base.Rosehips", 3, 9, 2 },
        { "Base.Acorn", 3, 9, 2 }, { "Base.Nettles", 2, 3, 6 }, { "Base.Thistle", 2, 4, 9 },
        { "Base.Plantain", 2, 3, 9 }, { "Base.Violets", 2, 3, 6 }, { "Base.MushroomGeneric1", 2, 4, 11 },
        { "Base.MushroomGeneric3", 2, 8, 11 },
    },
}
ProjectALife.CampLife = Camp

function Camp.state(haven)
    haven.chores = type(haven.chores) == "table" and haven.chores or { wood = 0, planks = 0, crates = 0, forage = 0 }
    haven.visible = type(haven.visible) == "table" and haven.visible or { logs = 0, planks = 0, crates = 0 }
    return haven.chores, haven.visible
end

function Camp.crewSize(haven)
    local count = 0
    ProjectALife.ActorRegistry.each(function(record)
        if type(record.memory) == "table" and record.memory.havenId == haven.id and record.lifecycle ~= "dead" then
            count = count + 1
        end
        return false
    end)
    return count
end

function Camp.offline(haven, hours)
    local chores = Camp.state(haven)
    local settings = Camp.settings
    local last = tonumber(haven.choreHours) or tonumber(haven.lastHomeHours) or hours
    haven.choreHours = hours
    local elapsed = math.max(0, math.min(settings.maxElapsed, hours - last))
    if elapsed <= 0 or hours - (tonumber(haven.lastHomeHours) or -math.huge) > Havens.settings.homeHours then return false end
    local crew = Camp.crewSize(haven)
    if crew == 0 then return false end
    chores.wood = math.min(settings.woodCap, chores.wood + elapsed * crew * settings.woodPerHour)
    local sawn = math.min(math.floor(chores.wood / 2), math.floor(elapsed * crew * settings.plankPerHour))
    chores.wood = chores.wood - sawn * 2
    chores.planks = math.min(settings.plankCap, chores.planks + sawn * 3)
    local built = math.min(math.floor(chores.planks / 4), math.floor(elapsed * crew * settings.cratePerHour))
    chores.planks = chores.planks - built * 4
    chores.crates = math.min(settings.crateCap, chores.crates + built)
    chores.forage = math.min(settings.forageCap, chores.forage + elapsed * crew * settings.foragePerHour)
    Camp.metrics.offline = Camp.metrics.offline + 1
    Havens.dirty()
    return true
end

function Camp.choreFor(record, nowMs)
    local index = tonumber(record.memory.groupIndex) or 1
    local slot = math.floor((tonumber(nowMs) or 0) / 90000)
    return Camp.order[(index + slot) % #Camp.order + 1]
end

function Camp.station(haven, record)
    local index = tonumber(record.memory.groupIndex) or 1
    local angle = (index * 2.1 + (tonumber(string.match(tostring(haven.id), "(%d+)")) or 0)) % (2 * math.pi)
    return { x = haven.depot.x + math.cos(angle) * 3.5, y = haven.depot.y + math.sin(angle) * 3.5, z = haven.depot.z }
end

function Camp.spotNear(haven, salt)
    local angle = (salt * 1.7 + (tonumber(string.match(tostring(haven.id), "(%d+)")) or 0)) % (2 * math.pi)
    local radius = 2 + (salt % 3)
    return Havens.squareAt(haven.depot.x + math.cos(angle) * radius, haven.depot.y + math.sin(angle) * radius, haven.depot.z)
end

function Camp.dropItem(haven, fullType, salt)
    local square = Camp.spotNear(haven, salt)
    if square == nil or type(square.AddWorldInventoryItem) ~= "function" then return false end
    if type(square.isFree) == "function" and square:isFree(false) ~= true then return false end
    local item = type(Camp.adapters.newItem) == "function" and Camp.adapters.newItem(fullType)
        or (type(instanceItem) == "function" and instanceItem(fullType) or nil)
    if item == nil then return false end
    return pcall(square.AddWorldInventoryItem, square, item, 0.3 + (salt % 4) * 0.12, 0.3 + (salt % 3) * 0.2, 0)
end

function Camp.forageScale()
    local catalog = ProjectALife.ActivityCatalog
    if catalog == nil or type(catalog.enabled) ~= "function" or not catalog.enabled()
            or catalog.sandbox("Activities_Foraging") == false then return 0 end
    local percent = tonumber(catalog.sandbox("Activities_ForageYieldPercent")) or 100
    return math.max(0, math.min(300, percent)) / 100
end

function Camp.forageInSeason(row, month)
    if row[3] <= row[4] then return month >= row[3] and month <= row[4] end
    return month >= row[3] or month <= row[4]
end

function Camp.foragePick(month, roll)
    local total = 0
    for _, row in ipairs(Camp.forageTable) do
        if Camp.forageInSeason(row, month) then total = total + row[2] end
    end
    if total <= 0 then return nil end
    local remaining = math.max(0, math.min(0.999999, tonumber(roll) or 0)) * total
    for _, row in ipairs(Camp.forageTable) do
        if Camp.forageInSeason(row, month) then
            if remaining < row[2] then return row[1] end
            remaining = remaining - row[2]
        end
    end
    return nil
end

function Camp.forageDeposit(actor, spot, fullType, salt)
    local haven = type(Havens.of) == "function" and Havens.of(actor.memory.havenId) or nil
    local full = false
    if haven ~= nil and type(haven.depot) == "table" then
        local container = Havens.containerAt(haven.depot)
        local state = ProjectALife.ShellState
        if container ~= nil and type(container.AddItem) == "function" and state ~= nil and type(state.createItem) == "function" then
            local item = state.createItem(fullType)
            if item ~= nil then
                local placed, why = ProjectALife.StashRoom.place(container, item)
                if placed then
                    Camp.metrics.forageStashed = Camp.metrics.forageStashed + 1
                    return true
                end
                full = why == "full"
            end
        end
        local stash = Havens.stashOf(haven)
        if not full and stash ~= nil and #stash.items < Havens.settings.stashLimit then
            stash.items[#stash.items + 1] = { type = fullType }
            Havens.dirty()
            Camp.metrics.forageStashed = Camp.metrics.forageStashed + 1
            return true
        end
    end
    if Camp.dropItem({ id = tostring(actor.memory.groupId or actor.uid), depot = { x = spot.x, y = spot.y, z = 0 } }, fullType, salt) then
        Camp.metrics.forageDropped = Camp.metrics.forageDropped + 1
        if full then ProjectALife.StashRoom.metrics.groundFallback = ProjectALife.StashRoom.metrics.groundFallback + 1 end
        return true
    end
    return false
end

function Camp.forageGather(actor, spot)
    if type(isClient) == "function" and isClient() == true then return 0 end
    local scale = Camp.forageScale()
    if scale <= 0 or type(getGameTime) ~= "function" or type(actor) ~= "table" or type(actor.memory) ~= "table"
            or type(spot) ~= "table" or type(ZombRand) ~= "function" then return 0 end
    local time = getGameTime()
    if time == nil or type(time.getWorldAgeHours) ~= "function" or type(time.getMonth) ~= "function" then return 0 end
    local hours = tonumber(time:getWorldAgeHours())
    if hours == nil or hours ~= hours then return 0 end
    local key, day = tostring(actor.memory.groupId or actor.uid), math.floor(hours / 24)
    local state = Camp.forageState[key]
    if state == nil or state.day ~= day then
        state = { day = day, count = 0, nextHours = hours + Camp.forageEveryHours }
        Camp.forageState[key] = state
    end
    if hours < state.nextHours then return 0 end
    state.nextHours = hours + Camp.forageEveryHours
    if state.count >= math.floor(Camp.forageDailyCap * scale + 0.5) then return 0 end
    local fullType = Camp.foragePick(math.floor(time:getMonth()) + 1, ZombRand(1000000) / 1000000)
    if fullType == nil or not Camp.forageDeposit(actor, spot, fullType, state.count + 1) then
        Camp.metrics.forageRefused = Camp.metrics.forageRefused + 1
        return 0
    end
    state.count = state.count + 1
    Camp.metrics.foraged = Camp.metrics.foraged + 1
    return 1
end

function Camp.buildCrate(haven, salt)
    local square = Camp.spotNear(haven, salt + 5)
    if square == nil or type(IsoThumpable) ~= "table" or type(IsoThumpable.new) ~= "function" or type(getCell) ~= "function" then
        return false
    end
    if type(square.isFree) == "function" and square:isFree(false) ~= true then return false end
    local ok = pcall(function()
        local object = IsoThumpable.new(getCell(), square, Camp.settings.crateSprite, false, {})
        if type(object.setIsContainer) == "function" then object:setIsContainer(true) end
        if type(object.setMaxHealth) == "function" then object:setMaxHealth(200) end
        if type(object.setHealth) == "function" then object:setHealth(200) end
        square:AddSpecialObject(object)
        if type(object.transmitCompleteItemToClients) == "function" then object:transmitCompleteItemToClients() end
    end)
    return ok
end

function Camp.render(haven, nowMs)
    if Havens.playerNear(haven.x, haven.y, Camp.settings.renderTiles) ~= true then return 0 end
    if nowMs - (Camp.renderedAt[haven.id] or -math.huge) < Camp.settings.renderEveryMs then return 0 end
    Camp.renderedAt[haven.id] = nowMs
    local chores, visible = Camp.state(haven)
    local settings, made = Camp.settings, 0
    if visible.logs < math.min(settings.visibleLogs, math.floor(chores.wood / 4)) and Camp.dropItem(haven, "Base.Log", visible.logs + 1) then
        visible.logs, made = visible.logs + 1, made + 1
        Camp.metrics.logs = Camp.metrics.logs + 1
    end
    if visible.planks < math.min(settings.visiblePlanks, math.floor(chores.planks / 3)) and Camp.dropItem(haven, "Base.Plank", visible.planks + 11) then
        visible.planks, made = visible.planks + 1, made + 1
        Camp.metrics.planks = Camp.metrics.planks + 1
    end
    if visible.crates < math.min(settings.visibleCrates, math.floor(chores.crates)) and Camp.buildCrate(haven, visible.crates + 21) then
        visible.crates, made = visible.crates + 1, made + 1
        Camp.metrics.crates = Camp.metrics.crates + 1
    end
    if made > 0 then Havens.dirty() end
    return made
end

return Camp
