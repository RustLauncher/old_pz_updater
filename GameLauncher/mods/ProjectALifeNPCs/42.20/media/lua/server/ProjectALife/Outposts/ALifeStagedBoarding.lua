require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local Staged = {
    id = "staged_boarding",
    daysPerStage = 4, playerClear = 40, loadedRadius = 110, groundSheets = 2, sheetChance = 0.4,
    fortifyMaxPlanks = 2,
    steps = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } },
    sheets = {},
    metrics = { windows = 0, planks = 0, sheets = 0, upper = 0, topped = 0, upperSkipped = 0, clamped = 0 },
}
ProjectALife.StagedBoarding = Staged

function Staged.active()
    return Gate.on(Staged.id, "Boarding_Staged", true)
end

function Staged.fortifyActive()
    return Staged.active()
end

function Staged.zOf(opening)
    return type(opening) == "table" and (tonumber(opening.z) or 0) or 0
end

function Staged.groundOnly(openings)
    local out = {}
    for _, opening in ipairs(type(openings) == "table" and openings or {}) do
        if Staged.zOf(opening) < 1 then out[#out + 1] = opening
        else Staged.metrics.upperSkipped = Staged.metrics.upperSkipped + 1 end
    end
    return out
end

function Staged.byPosition(a, b)
    local ka = (tonumber(a.x) or 0) * 100000 + (tonumber(a.y) or 0)
    local kb = (tonumber(b.x) or 0) * 100000 + (tonumber(b.y) or 0)
    return ka < kb
end

function Staged.sheetable(openings)
    local out, ground = {}, {}
    for _, opening in ipairs(type(openings) == "table" and openings or {}) do
        if Staged.zOf(opening) >= 1 then out[#out + 1] = opening
        elseif opening.kind ~= "door" then ground[#ground + 1] = opening end
    end
    table.sort(ground, Staged.byPosition)
    for i = 1, math.min(Staged.groundSheets, #ground) do out[#out + 1] = ground[i] end
    return out
end

function Staged.fortifyPlanks(opening, planks)
    if Staged.zOf(opening) >= 1 then return 0 end
    local n = math.max(1, math.floor(tonumber(planks) or 1))
    if n > Staged.fortifyMaxPlanks then
        Staged.metrics.clamped = Staged.metrics.clamped + 1
        n = Staged.fortifyMaxPlanks
    end
    return n
end

function Staged.windowAt(x, y, z)
    local cell = getCell()
    if cell == nil then return nil end
    for _, d in ipairs(Staged.steps) do
        local square = cell:getGridSquare(x + d[1], y + d[2], z)
        local objects = square ~= nil and square:getObjects() or nil
        if objects ~= nil then
            for i = 0, objects:size() - 1 do
                local object = objects:get(i)
                if instanceof(object, "IsoWindow") then return object end
            end
        end
    end
    return nil
end

function Staged.planksTo(window, target, site)
    if window == nil or target <= 0 or IsoBarricade == nil or type(IsoBarricade.AddBarricadeToObject) ~= "function" then return 0 end
    local ok, barricade = pcall(IsoBarricade.AddBarricadeToObject, window, false)
    if not ok or barricade == nil then return 0 end
    if barricade:isMetal() == true or barricade:isMetalBar() == true then return 0 end
    local added, marked = 0, false
    local builder = ProjectALife.OutpostBuilder
    if builder ~= nil and builder.barricadeFresh(barricade) then
        local heat = ProjectALife.BaseHeat
        if heat ~= nil and type(heat.stampNpcBarricade) == "function" then heat.stampNpcBarricade(barricade) end
        if site ~= nil then marked = builder.markBarricade(barricade, site) end
    end
    for _ = 1, 4 do
        if (tonumber(barricade:getNumPlanks()) or 0) >= math.min(4, target) then break end
        barricade:addPlank(nil, nil)
        added = added + 1
    end
    if added > 0 and Gate.dedicated() then barricade:transmitCompleteItemToClients() end
    return added, marked
end

function Staged.sheet(window)
    local builder = ProjectALife.OutpostBuilder
    if window == nil or builder == nil or type(builder.closeSheet) ~= "function" then return false end
    local ok = pcall(builder.closeSheet, window)
    return ok
end

function Staged.planksFor(stage, key)
    local low = math.min(4, (tonumber(stage) or 0) + 1)
    local high = math.min(4, low + 1)
    if Gate.hash01(key) < 0.5 then return low end
    return high
end

function Staged.stageOf(site, hours)
    local created = tonumber(site.createdHours) or hours or 0
    local days = math.max(0, (tonumber(hours) or 0) - created) / 24
    return math.min(3, math.floor(days / Staged.daysPerStage))
end

function Staged.board(x, y, z, planks, material, site)
    if material == "metal" or not Staged.active() then return false end
    local window = Staged.windowAt(x, y, z)
    if window == nil then return false end
    local siteId = type(site) == "table" and tostring(site.id) or "?"
    local key = siteId .. ":" .. tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
    Staged.metrics.windows = Staged.metrics.windows + 1
    if (tonumber(z) or 0) >= 1 then
        Staged.sheet(window)
        Staged.metrics.upper = Staged.metrics.upper + 1
        return true, true
    end
    local hung = Staged.sheets[siteId] or 0
    if type(site) == "table" and hung < Staged.groundSheets and Gate.hash01(key .. ":sheet") < Staged.sheetChance then
        Staged.sheet(window)
        Staged.sheets[siteId] = hung + 1
        Staged.metrics.sheets = Staged.metrics.sheets + 1
    end
    local stage = type(site) == "table" and Staged.stageOf(site, Gate.worldHours()) or 0
    local target = math.min(tonumber(planks) or 4, Staged.planksFor(stage, key))
    local added, marked = Staged.planksTo(window, target, site)
    Staged.metrics.planks = Staged.metrics.planks + added
    return true, true, marked
end

function Staged.topUp(site, stage)
    local builder = ProjectALife.OutpostBuilder
    if builder == nil or type(builder.probeBuilding) ~= "function" then return 0 end
    local square = getCell():getGridSquare(site.x, site.y, 0)
    local building = square ~= nil and square:getBuilding() or nil
    if building == nil then return 0 end
    local ok, probe = pcall(builder.probeBuilding, building)
    if not ok or type(probe) ~= "table" or type(probe.windows) ~= "function" then return 0 end
    local added = 0
    for _, w in ipairs(probe.windows() or {}) do
        if w.object ~= nil then
            if (tonumber(w.z) or 0) == 0 then
                local key = tostring(site.id) .. ":" .. tostring(w.objectX) .. ":" .. tostring(w.objectY) .. ":0"
                added = added + Staged.planksTo(w.object, Staged.planksFor(stage, key), site)
            else
                Staged.sheet(w.object)
            end
        end
    end
    return added
end

function Staged.tick(hours)
    if not Gate.worldReady() or not Staged.active() then return 0 end
    local sites, presets = ProjectALife.OutpostRegistry, ProjectALife.OutpostPresets
    if sites == nil or presets == nil or type(sites.list) ~= "function" or type(presets.get) ~= "function" then return 0 end
    hours = tonumber(hours) or Gate.worldHours()
    local points = Gate.playerPoints()
    local raised = 0
    for _, site in ipairs(sites.list() or {}) do
        local preset = site.state == "garrisoned" and presets.get(site.presetId) or nil
        if type(preset) == "table" and preset.class == "building" then
            local stage = Staged.stageOf(site, hours)
            if stage > (tonumber(site.boardStage) or 0) then
                local nearest = Gate.nearestPlayer(tonumber(site.x) or 0, tonumber(site.y) or 0, points)
                if nearest >= Staged.playerClear and nearest <= Staged.loadedRadius then
                    local okTop, added = pcall(Staged.topUp, site, stage)
                    sites.update(site.id, site.revision, function(record) record.boardStage = stage end)
                    Staged.metrics.topped = Staged.metrics.topped + 1
                    raised = raised + 1
                    print("[A-Life] boarding: outpost " .. tostring(site.id) .. " stage " .. tostring(stage)
                        .. " planks +" .. tostring(okTop and added or 0))
                end
            end
        end
    end
    return raised
end

if type(Events) == "table" and Events.EveryTenMinutes ~= nil then
    Events.EveryTenMinutes.Add(function() pcall(Staged.tick, Gate.worldHours()) end)
end

return Staged
