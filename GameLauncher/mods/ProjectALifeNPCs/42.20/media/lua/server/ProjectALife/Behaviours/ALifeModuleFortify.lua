require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Outposts/ALifeOutpostBuilder"
require "ProjectALife/Outposts/ALifePlanks"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry

local Fortify = {
    id = "fortify",
    settings = {

        entranceClearance = 3,

        workMs = 2600,

        cooldownMs = 45000,
    },
    metrics = { offers = 0, boarded = 0, refused = 0, sheets = 0 },

    boarded = {},
}
ProjectALife.ModuleFortify = Fortify

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function memoryOf(actor)
    return type(actor) == "table" and type(actor.memory) == "table" and actor.memory or {}
end

function Fortify.siteOf(actor)
    local memory = memoryOf(actor)
    if memory.outpostSquadId ~= nil then return nil end
    if type(memory.outpostId) == "string" then return memory.outpostId end
    local encounter = memory.encounter
    if type(encounter) == "string" and string.sub(encounter, 1, 8) == "outpost:" then
        return string.sub(encounter, 9)
    end
    return nil
end

function Fortify.staged()
    local staged = ProjectALife.StagedBoarding
    if staged ~= nil and type(staged.fortifyActive) == "function" and staged.fortifyActive() then return staged end
    return nil
end

function Fortify.pick(openings, entrance, clearance, from)
    local staged = Fortify.staged()
    if staged ~= nil then openings = staged.groundOnly(openings) end
    local best, bestScore
    for _, opening in ipairs(type(openings) == "table" and openings or {}) do
        if opening.barricaded ~= true then
            local skip = opening.kind == "door" and type(entrance) ~= "table"

            pcall(function()
                if opening.object ~= nil and opening.object:getModData().ProjectALifeOwnWay == true then skip = true end
            end)
            if opening.kind == "door" and type(entrance) == "table" then
                local ex = (tonumber(opening.x) or 0) - (tonumber(entrance.x) or 0)
                local ey = (tonumber(opening.y) or 0) - (tonumber(entrance.y) or 0)

                if ex * ex + ey * ey <= (tonumber(clearance) or 3) ^ 2 then skip = true end
            end

            if not skip then
                local dx = (tonumber(opening.x) or 0) - (tonumber(from and from.x) or 0)
                local dy = (tonumber(opening.y) or 0) - (tonumber(from and from.y) or 0)
                local distance = math.sqrt(dx * dx + dy * dy)
                local score = (opening.kind == "window" and 40 or 0) - distance
                if bestScore == nil or score > bestScore then best, bestScore = opening, score end
            end
        end
    end
    return best
end

local function openingsAround(shell)
    local found = {}
    pcall(function()
        local square = shell:getCurrentSquare()
        local building = square and square:getBuilding() or nil
        if building == nil then return end
        local probe = ProjectALife.OutpostBuilder.probeBuilding(building)
        if probe == nil then return end
        for _, opening in ipairs(probe.windows()) do found[#found + 1] = opening end
        for _, opening in ipairs(probe.doors()) do found[#found + 1] = opening end
    end)
    return found
end

function Fortify.board(shell, opening, planks)
    if shell == nil or type(opening) ~= "table" or opening.object == nil then return false end
    local store = ProjectALife.Planks
    if store == nil or store.held({ shell }) <= 0 then return false end
    local staged = Fortify.staged()
    if staged ~= nil then
        planks = staged.fortifyPlanks(opening, planks)
        if planks <= 0 then return false end
    end

    if type(isClient) == "function" and isClient() == true then
        local fires = ProjectALife.Campfires
        return fires ~= nil and type(fires.requestShelter) == "function"
            and fires.requestShelter(shell, "board", { x = opening.x, y = opening.y, z = opening.z }, planks) == true
    end
    local done = false
    pcall(function()
        if IsoBarricade == nil or type(IsoBarricade.AddBarricadeToObject) ~= "function" then return end
        local barricade = IsoBarricade.AddBarricadeToObject(opening.object, shell)
        if barricade == nil then return end
        local heat = ProjectALife.BaseHeat
        if heat ~= nil and type(heat.stampNpcBarricade) == "function" then heat.stampNpcBarricade(barricade) end
        local taken = store.take({ shell }, math.max(1, math.floor(tonumber(planks) or 1)))
        for _ = 1, taken do
            barricade:addPlank(nil, nil)
        end
        pcall(function() barricade:transmitCompleteItemToClients() end)
        done = taken > 0
    end)
    return done
end

function Fortify.openCount(openings, entrance, clearance)
    local count = 0
    for _, opening in ipairs(type(openings) == "table" and openings or {}) do
        local clear = false
        if type(entrance) == "table" then
            local dx, dy = (opening.x or 0) - (entrance.x or 0), (opening.y or 0) - (entrance.y or 0)
            clear = dx * dx + dy * dy <= (tonumber(clearance) or 0) ^ 2
        end
        if opening.barricaded ~= true and not clear then count = count + 1 end
    end
    return count
end

function Fortify.hangSheets(shell, siteId, openings)
    if siteId == nil or type(openings) ~= "table" then return 0 end
    local staged = Fortify.staged()
    if staged ~= nil then openings = staged.sheetable(openings) end
    local hung = 0
    for _, opening in ipairs(openings) do
        pcall(function()
            local window = opening.object
            if window == nil or instanceof == nil or not instanceof(window, "IsoWindow") then return end
            local ready, changed = ProjectALife.OutpostBuilder.closeSheet(window)
            if ready and changed then hung = hung + 1 end
        end)
    end
    Fortify.metrics.sheets = (Fortify.metrics.sheets or 0) + hung
    return hung
end

function Fortify.reset()
    Fortify.boarded = {}
    Fortify.metrics = { offers = 0, boarded = 0, refused = 0, sheets = 0 }
end

function Fortify.evaluate(actor, shell, context)
    if not Registry.allows(actor, "fortify") then return nil end
    local siteId = Fortify.siteOf(actor)
    if siteId == nil then return nil end
    local now = tonumber(context and context.now) or nowMs()
    local memory = memoryOf(actor)
    if now < (tonumber(memory.fortifyNextAtMs) or 0) then return nil end

    local registry = ProjectALife.OutpostRegistry
    local site = registry ~= nil and type(registry.read) == "function" and registry.read(siteId) or nil
    local entrance = site ~= nil and site.mainEntrance or nil
    local from
    pcall(function() from = { x = shell:getX(), y = shell:getY() } end)
    local openings = openingsAround(shell)

    Fortify.hangSheets(shell, siteId, openings)
    local opening = Fortify.pick(openings, entrance, Fortify.settings.entranceClearance, from)
    if opening == nil then
        if type(context.persistMemory) == "function" then
            context.persistMemory(actor, function(m) m.fortifyNextAtMs = now + Fortify.settings.cooldownMs end)
        end
        return nil
    end
    Fortify.metrics.offers = Fortify.metrics.offers + 1

    local dx = (from and from.x or 0) - opening.x
    local dy = (from and from.y or 0) - opening.y
    if dx * dx + dy * dy > 2.5 * 2.5 or math.floor(shell:getZ()) ~= opening.z then

        if type(context.startMovement) ~= "function" then return nil end
        return context.startMovement(actor, shell,
            { x = opening.x, y = opening.y, z = opening.z }, "fortify", {
                kind = "movement", activity = "moving", intent = "fortify_opening",
                pace = "walk", timeoutMs = 12000,
            })
    end

    if type(context.persistMemory) == "function" then
        context.persistMemory(actor, function(m) m.fortifyNextAtMs = now + Fortify.settings.cooldownMs end)
    end

    local store = ProjectALife.Planks
    local share = store ~= nil and store.plan(Fortify.openCount(openings, entrance, Fortify.settings.entranceClearance),
        store.held({ shell }))[1] or nil
    if share ~= nil and Fortify.board(shell, opening, share) then
        Fortify.boarded[siteId] = (Fortify.boarded[siteId] or 0) + 1
        Fortify.metrics.boarded = Fortify.metrics.boarded + 1
        local voice = ProjectALife.Voice
        if voice ~= nil then pcall(voice.play, shell, "BREACH") end
        local animations = ProjectALife.Animations

        if animations ~= nil then pcall(animations.apply, shell, "board_up") end
        if type(context.setActivity) == "function" then
            context.setActivity(actor, "working", "fortify_opening")
        end
        return { kind = "idle", intent = "fortify_opening", cooldownUntilMs = now + Fortify.settings.workMs }
    end
    Fortify.metrics.refused = Fortify.metrics.refused + 1
    return nil
end

Registry.register({
    id = "fortify",
    kind = "upkeep",
    dispatch = "decision",

    priority = 78,
    label = "Fortify the building",
    summary = "A garrison boards up its own windows and doors from the inside, leaving its entrance clear.",
    defaultEnabled = true,
    evaluate = Fortify.evaluate,
})

return Fortify
