require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Records/ALifeClothingMaster"
require "ProjectALife/Visitors/ALifeVisitorClothing"
require "ProjectALife/Visitors/ALifeVisitorReact"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local People = ProjectALife.VisitorPeople
local Instance = ProjectALife.VisitorInstance
local Master = ProjectALife.ClothingMaster
local React = ProjectALife.VisitorReact

local Wardrobe = {
    adapters = {},
    jobs = {},
    pending = {},
    queue = {},
    seen = setmetatable({}, { __mode = "k" }),
    cache = {},
    cacheCount = 0,
    caughtCount = {},
    armed = false,
    nextPassMs = 0,
    settings = {
        offAfterMs = 800, holdMs = 3000, swapAfterMs = 400, passMs = 250, maxList = 14, maxExtra = 12, cacheMax = 32,
        retryMs = 20000, retryMax = 20, minorTiles = 8, intruderTiles = 6,
    },
    metrics = { refined = 0, seeded = 0, changes = 0, stages = 0, caught = 0, refused = 0, violations = 0, worn = 0,
        kept = 0, deferred = 0, synced = 0, healed = 0, empty = 0, missing = 0, lastWhy = "-" },
}
ProjectALife.VisitorWardrobe = Wardrobe

if React ~= nil and type(React.events) == "table" and React.events.privacy_caught == nil then
    React.events.privacy_caught = { delta = -4, why = "You walked in on them.", class = "deed", adult = true }
    React.register()
end

function Wardrobe.nowMs()
    if type(Wardrobe.adapters.nowMs) == "function" then return Wardrobe.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Wardrobe.hours()
    if type(Wardrobe.adapters.hours) == "function" then return tonumber(Wardrobe.adapters.hours()) or 0 end
    local director = ProjectALife.VisitorDirector
    if director ~= nil and type(director.hours) == "function" then return tonumber(director.hours()) or 0 end
    if type(getGameTime) == "function" then
        local clock = getGameTime()
        if clock ~= nil and type(clock.getWorldAgeHours) == "function" then return tonumber(clock:getWorldAgeHours()) or 0 end
    end
    return 0
end

function Wardrobe.options()
    if type(Wardrobe.adapters.options) == "function" then return Wardrobe.adapters.options() end
    local director = ProjectALife.VisitorDirector
    if director ~= nil and type(director.options) == "function" then return director.options() end
    return Schema.options(nil)
end

function Wardrobe.canWrite()
    return not (type(isClient) == "function" and isClient() == true)
end

function Wardrobe.fail(why)
    Wardrobe.metrics.lastWhy = tostring(why)
    return false, why
end

function Wardrobe.validType(value)
    return type(value) == "string" and #value <= 80 and string.match(value, "^[%w_]+%.[%w_]+$") ~= nil
end

function Wardrobe.validTint(value)
    return type(value) == "string" and #value <= 32 and string.match(value, "^[%d%.,]*$") ~= nil
end

function Wardrobe.known(itemType)
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator == nil or type(hydrator.itemKnown) ~= "function" then return true end
    return hydrator.itemKnown(itemType) == true
end

function Wardrobe.pairsFrom(entries)
    local list = {}
    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        local itemType = Master.entryType(entry)
        if Wardrobe.validType(itemType) and #list < Wardrobe.settings.maxList then
            local tint = Master.entryTint(entry)
            if not Wardrobe.validTint(tint) then tint = "" end
            list[#list + 1] = { itemType, tint }
        end
    end
    return list
end

function Wardrobe.entriesFrom(list)
    local entries = {}
    if type(list) ~= "table" then return entries end
    for _, row in ipairs(list) do
        local itemType = Master.entryType(row)
        if Wardrobe.validType(itemType) and #entries < Wardrobe.settings.maxList and Wardrobe.known(itemType) then
            local info = Master.layerOf(itemType)
            local tint = Master.entryTint(row)
            if not Wardrobe.validTint(tint) then tint = "" end
            entries[#entries + 1] = { slot = info ~= nil and info.name or "item", itemType = itemType, tint = tint }
        end
    end
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator ~= nil and type(hydrator.renderOrder) == "function" then entries = hydrator.renderOrder(entries) end
    return entries
end

function Wardrobe.copyEntries(entries)
    local result = {}
    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        local itemType = Master.entryType(entry)
        if itemType ~= nil then
            result[#result + 1] = { slot = type(entry) == "table" and entry.slot or nil, itemType = itemType,
                tint = Master.entryTint(entry) }
        end
    end
    return result
end

function Wardrobe.withUnderwear(entries, female)
    local result = Wardrobe.copyEntries(entries)
    local bottom, top = Master.underwearOf(result)
    for _, item in ipairs(Master.underwear(female and "f" or "m")) do
        local info = Master.infoOf(item.itemType)
        if info.name == "underwearbottom" and bottom == nil then
            result[#result + 1] = { slot = item.slot, itemType = item.itemType, tint = "" }
        elseif info.name == "underweartop" and top == nil and female then
            result[#result + 1] = { slot = item.slot, itemType = item.itemType, tint = "" }
        end
    end
    return result
end

function Wardrobe.merge(primary, secondary)
    local result = Wardrobe.copyEntries(primary)
    for _, entry in ipairs(type(secondary) == "table" and secondary or {}) do
        local itemType = Master.entryType(entry)
        local info = Master.infoOf(itemType)
        local clash = false
        for _, held in ipairs(result) do
            if Master.entryType(held) == itemType
                    or Master.collides(info.location, Master.infoOf(Master.entryType(held)).location) ~= nil then
                clash = true
            end
        end
        if not clash then result[#result + 1] = { slot = entry.slot, itemType = itemType, tint = Master.entryTint(entry) } end
    end
    return result
end

function Wardrobe.clonePairs(list)
    local copy = {}
    for position, row in ipairs(type(list) == "table" and list or {}) do copy[position] = { row[1], row[2] } end
    return copy
end

function Wardrobe.rowOf(record)
    local memory = type(record) == "table" and record.memory or nil
    local dress = type(memory) == "table" and memory.dress or nil
    return type(dress) == "table" and dress or nil
end

function Wardrobe.bodyOf(record)
    local dress = Wardrobe.rowOf(record)
    return dress ~= nil and type(dress.body) == "table" and dress.body or nil
end

function Wardrobe.storedList(record)
    local dress = Wardrobe.rowOf(record)
    if dress == nil or type(dress.list) ~= "table" or #dress.list == 0 then return nil end
    return dress.list
end

function Wardrobe.seasonOf(record)
    local dress = Wardrobe.rowOf(record)
    if dress ~= nil and type(dress.season) == "string" then return dress.season end
    local hydrator = ProjectALife.ProfileHydrator
    local season = hydrator ~= nil and type(hydrator.seasonFor) == "function" and hydrator.seasonFor(record) or nil
    return season or "autumn"
end

function Wardrobe.styleId(value)
    if type(value) ~= "string" then return nil end
    local lowered = string.lower(value)
    if lowered == "" or lowered == "none" then return "" end
    local hydrator = ProjectALife.ProfileHydrator
    local faces = hydrator ~= nil and hydrator.faces or nil
    if type(faces) == "table" then
        local found = nil
        local function scan(node)
            if type(node) == "string" then
                if node == value then found = found or node elseif string.lower(node) == lowered then found = found or node end
            elseif type(node) == "table" then
                for _, child in pairs(node) do scan(child) end
            end
        end
        scan(faces.male)
        scan(faces.female)
        scan(faces.beards)
        if found ~= nil then return found end
    end
    return value
end

function Wardrobe.bodyFrom(card)
    local look = type(card.look) == "table" and card.look or {}
    local female = card.sex == "f"
    local skin = tonumber(look.skin)
    local body = { f = female and 1 or 0 }
    if skin ~= nil then body.sk = math.max(0, math.min(4, math.floor(skin) - 1)) end
    local hair = Wardrobe.styleId(look.hair)
    if hair ~= nil then body.hs = hair end
    if type(look.hairColor) == "string" and look.hairColor ~= "" then body.hc = look.hairColor end
    if not female then
        local beard = Wardrobe.styleId(look.beard)
        if beard ~= nil then body.bs = beard end
        if type(look.beardColor) == "string" and look.beardColor ~= "" then body.bc = look.beardColor end
    end
    return body
end

function Wardrobe.applyBody(plan, body)
    local hydrator = ProjectALife.ProfileHydrator
    if body.f ~= nil then plan.female = body.f == 1 or body.f == true end
    if body.sk ~= nil then plan.skin = math.max(0, math.min(4, math.floor(tonumber(body.sk) or 0))) end
    if hydrator ~= nil and type(hydrator.humanSkinTexture) == "function" then
        plan.skinTexture = hydrator.humanSkinTexture(plan.female, plan.skin)
    end
    if body.hs ~= nil then plan.hairStyle = body.hs end
    if body.hc ~= nil then plan.hairColor = body.hc end
    if plan.female then
        plan.beardStyle = ""
    else
        if body.bs ~= nil then plan.beardStyle = body.bs end
        if body.bc ~= nil then plan.beardColor = body.bc elseif body.hc ~= nil then plan.beardColor = body.hc end
    end
end

function Wardrobe.compute(record, card)
    local person = Instance.of(record)
    local season = Wardrobe.seasonOf(record)
    local seed = math.floor(tonumber(person.seed) or tonumber(card.seed) or 0)
    local key = tostring(person.id) .. "|" .. tostring(seed) .. "|" .. season
    local cached = Wardrobe.cache[key]
    if cached ~= nil then return cached, season end
    local dress = type(card.dress) == "table" and card.dress or {}
    local flags = { seed = seed, sex = card.sex, ageBand = card.band, tags = dress.flags }
    local result = Master.pick(season, dress.role, flags)
    if result == nil or #result.entries == 0 then return nil, season end
    local list = Wardrobe.pairsFrom(Wardrobe.withUnderwear(result.entries, card.sex == "f"))
    if Wardrobe.cacheCount >= Wardrobe.settings.cacheMax then Wardrobe.cache, Wardrobe.cacheCount = {}, 0 end
    Wardrobe.cache[key] = list
    Wardrobe.cacheCount = Wardrobe.cacheCount + 1
    return list, season
end

function Wardrobe.listFor(record, card)
    local stored = Wardrobe.storedList(record)
    if stored ~= nil then return stored, "stored" end
    if card == nil then return nil, "no_card" end
    local list = Wardrobe.compute(record, card)
    if list == nil then return nil, "no_pick" end
    return list, "computed"
end

function Wardrobe.extraFor(record, card, worn)
    local dress = Wardrobe.rowOf(record)
    local source = dress ~= nil and type(dress.extra) == "table" and dress.extra or (card ~= nil and card.carry or {})
    local result, onBody = {}, {}
    for _, entry in ipairs(worn or {}) do onBody[entry.itemType] = (onBody[entry.itemType] or 0) + 1 end
    for _, itemType in ipairs(source) do
        if Wardrobe.validType(itemType) and #result < Wardrobe.settings.maxExtra then
            if (onBody[itemType] or 0) > 0 then
                onBody[itemType] = onBody[itemType] - 1
            else
                result[#result + 1] = itemType
            end
        end
    end
    return result
end

function Wardrobe.refine(plan, actor)
    local person = Instance.of(actor)
    if type(plan) ~= "table" or person == nil then return plan end
    local card = People.card(person.id)
    if card ~= nil then
        Wardrobe.applyBody(plan, Wardrobe.bodyFrom(card))
        plan.name = plan.personName or card.name.first
    else
        local body = Wardrobe.bodyOf(actor)
        if body ~= nil then Wardrobe.applyBody(plan, body) else Wardrobe.metrics.missing = Wardrobe.metrics.missing + 1 end
    end
    local list = Wardrobe.listFor(actor, card)
    local entries = list ~= nil and Wardrobe.entriesFrom(list) or {}
    if #entries > 0 then
        plan.clothing = entries
    elseif list ~= nil then
        Wardrobe.metrics.empty = Wardrobe.metrics.empty + 1
    end
    plan.extraItems = Wardrobe.extraFor(actor, card, plan.clothing)
    Wardrobe.metrics.refined = Wardrobe.metrics.refined + 1
    local dress = Wardrobe.rowOf(actor)
    if Wardrobe.canWrite() and card ~= nil and actor.uid ~= nil and Wardrobe.pending[actor.uid] == nil then
        if dress == nil or Wardrobe.storedList(actor) == nil or dress.body == nil
                or (dress.stage ~= nil and Wardrobe.jobs[actor.uid] == nil) then
            Wardrobe.pending[actor.uid] = 0
            Wardrobe.arm()
        end
    end
    return plan
end

function Wardrobe.seed(uid)
    if not Wardrobe.canWrite() then return Wardrobe.fail("client_write_refused") end
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and registry.peek(uid) or nil
    local person = Instance.of(record)
    if person == nil then return Wardrobe.fail("not_a_visitor") end
    local card = People.card(person.id)
    if card == nil then return Wardrobe.fail("loading") end
    local computed, season = Wardrobe.compute(record, card)
    if computed == nil then return Wardrobe.fail("no_pick") end
    local list = Wardrobe.clonePairs(computed)
    local hours = Instance.hours(Wardrobe.hours())
    local body = Wardrobe.bodyFrom(card)
    local extra = Wardrobe.extraFor(record, card)
    local ok, why = Instance.write(uid, function(memory)
        local dress = type(memory.dress) == "table" and memory.dress or {}
        memory.dress = dress
        if type(dress.list) ~= "table" or #dress.list == 0 then
            dress.list, dress.rev, dress.since, dress.season = list, math.max(1, tonumber(dress.rev) or 0), hours, season
        end
        if type(dress.body) ~= "table" then dress.body = body end
        if type(dress.extra) ~= "table" then dress.extra = extra end
    end)
    if ok then Wardrobe.metrics.seeded = Wardrobe.metrics.seeded + 1 end
    return ok, why
end

function Wardrobe.heal(uid)
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and registry.peek(uid) or nil
    local dress = Wardrobe.rowOf(record)
    if dress == nil or dress.stage == nil then return false end
    local final = dress.goal
    if type(final) ~= "table" or #final == 0 then
        local merged = Wardrobe.merge(Wardrobe.entriesFrom(dress.held), Wardrobe.entriesFrom(dress.list))
        final = Wardrobe.pairsFrom(merged)
    end
    local ok = Instance.write(uid, function(memory)
        local row = memory.dress
        if type(row) ~= "table" then return end
        row.list, row.stage, row.held, row.goal = final, nil, nil, nil
        row.rev = (tonumber(row.rev) or 0) + 1
        if type(memory.person) == "table" then Instance.setDressState(memory.person, "dressed") end
    end)
    if ok then Wardrobe.metrics.healed = Wardrobe.metrics.healed + 1 end
    return ok
end

function Wardrobe.dressOf(uid)
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and registry.peek(uid) or nil
    local person = Instance.of(record)
    if person == nil then return nil, "not_a_visitor" end
    local list = Wardrobe.listFor(record, People.card(person.id))
    if list == nil then return nil, "no_dress" end
    return Wardrobe.entriesFrom(list)
end

function Wardrobe.minorNear(record)
    local person = Instance.of(record)
    if person == nil then return true end
    local index = People.index()
    if index == nil then return true end
    for _, id in ipairs(type(person.with) == "table" and person.with or {}) do
        local row = index.people[id]
        if row == nil or row.teen then return true end
    end
    local registry = ProjectALife.ActorRegistry
    local at = record.worldPosition
    if registry ~= nil and type(registry.each) == "function" and type(at) == "table" then
        local limit = Wardrobe.settings.minorTiles
        local found = false
        registry.each(function(other)
            if other.uid ~= record.uid then
                local who = Instance.of(other)
                local row = who ~= nil and index.people[who.id] or nil
                local place = other.worldPosition
                if row ~= nil and row.teen and type(place) == "table" and math.abs((tonumber(place.z) or 0) - (tonumber(at.z) or 0)) < 1.5 then
                    local dx, dy = (tonumber(place.x) or 0) - (tonumber(at.x) or 0), (tonumber(place.y) or 0) - (tonumber(at.y) or 0)
                    if dx * dx + dy * dy <= limit * limit then found = true end
                end
            end
            return found
        end)
        if found then return true end
    end
    return false
end

function Wardrobe.doorState(uid)
    if type(Wardrobe.adapters.doorOpen) == "function" then return Wardrobe.adapters.doorOpen(uid) end
    local life = ProjectALife.VisitorLife
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and registry.peek(uid) or nil
    local memory = record ~= nil and record.memory or nil
    local poi = type(memory) == "table" and type(memory.life) == "table" and memory.life.poi or nil
    if life == nil or type(poi) ~= "table" or type(life.houseOf) ~= "function" or type(life.pois) ~= "function" then return nil end
    local best, bestDistance = nil, math.huge
    for _, other in ipairs(life.pois(life.houseOf(record)) or {}) do
        if other.kind == "door" and other.room == poi.room and (tonumber(other.z) or 0) == (tonumber(poi.z) or 0) then
            local dx, dy = (tonumber(other.x) or 0) - (tonumber(poi.x) or 0), (tonumber(other.y) or 0) - (tonumber(poi.y) or 0)
            if dx * dx + dy * dy < bestDistance then best, bestDistance = other, dx * dx + dy * dy end
        end
    end
    local object = best ~= nil and type(life.objectOf) == "function" and life.objectOf(best) or nil
    if object == nil or type(object.IsOpen) ~= "function" then return nil end
    return object:IsOpen() == true, object
end

function Wardrobe.closeDoor(uid)
    if type(Wardrobe.adapters.closeDoor) == "function" then return Wardrobe.adapters.closeDoor(uid) end
    local open, object = Wardrobe.doorState(uid)
    if open ~= true or object == nil or type(object.ToggleDoorSilent) ~= "function" then return false end
    return pcall(object.ToggleDoorSilent, object)
end

function Wardrobe.privacy(uid, strict)
    local open = Wardrobe.doorState(uid)
    if open == true then
        Wardrobe.closeDoor(uid)
        open = Wardrobe.doorState(uid)
    end
    if open == true then return false, "door_open" end
    if open == nil and strict then return false, "door_unknown" end
    return true
end

function Wardrobe.goalFor(record, card, current, spec)
    local female = card.sex == "f"
    local goal = nil
    if type(spec.to) == "table" and #spec.to > 0 then
        goal = Wardrobe.copyEntries(spec.to)
    elseif spec.top == nil then
        local person = Instance.of(record)
        local dress = Wardrobe.rowOf(record)
        local avoid = {}
        for _, entry in ipairs(current) do avoid[#avoid + 1] = entry.itemType end
        local flags = { seed = math.floor(tonumber(person.seed) or 0) + 7919 * (tonumber(dress ~= nil and dress.rev or 0) or 0),
            sex = card.sex, ageBand = card.band, tags = type(card.dress) == "table" and card.dress.flags or nil }
        local picked = Master.pick(Wardrobe.seasonOf(record), type(card.dress) == "table" and card.dress.role or nil, flags)
        if picked == nil or #picked.entries == 0 then return nil, "no_pick" end
        goal = Wardrobe.copyEntries(picked.entries)
    else
        goal = Wardrobe.copyEntries(current)
    end
    if spec.top ~= nil then
        local itemType = Master.entryType(spec.top)
        if not Wardrobe.validType(itemType) then return nil, "item_invalid" end
        local ok, replaced, why = Master.accepts(goal, itemType)
        if not ok then return nil, why or "item_refused" end
        for _, entry in ipairs(replaced) do
            for position = #goal, 1, -1 do
                if goal[position].itemType == entry.itemType then table.remove(goal, position) end
            end
        end
        goal[#goal + 1] = { slot = Master.infoOf(itemType).name, itemType = itemType, tint = Master.entryTint(spec.top) }
    end
    goal = Wardrobe.withUnderwear(goal, female)
    return goal
end

function Wardrobe.stagesFor(current, goal, show)
    local settings = Wardrobe.settings
    local old, new = Master.splitForBeat(current), Master.splitForBeat(goal)
    if show and old ~= nil and new ~= nil then
        return {
            { name = "bottoms", list = Wardrobe.merge(old.top, new.rest), delay = settings.swapAfterMs, state = "changing" },
            { name = "top_off", list = Wardrobe.copyEntries(new.rest), delay = settings.offAfterMs, state = "topOff",
                held = old.top },
            { name = "top_on", list = goal, delay = settings.holdMs, state = "dressed", final = true },
        }
    end
    return { { name = "swap", list = goal, delay = settings.swapAfterMs, state = "dressed", final = true } }
end

function Wardrobe.change(uid, spec)
    spec = type(spec) == "table" and spec or {}
    if not Wardrobe.canWrite() then return Wardrobe.fail("client_write_refused") end
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and registry.peek(uid) or nil
    local person = Instance.of(record)
    if person == nil then Wardrobe.metrics.refused = Wardrobe.metrics.refused + 1; return Wardrobe.fail("not_a_visitor") end
    if person.ad ~= 1 then Wardrobe.metrics.refused = Wardrobe.metrics.refused + 1; return Wardrobe.fail("adult_only") end
    local options = Wardrobe.options()
    if options.changeClothes == false then Wardrobe.metrics.refused = Wardrobe.metrics.refused + 1; return Wardrobe.fail("option_off") end
    if Wardrobe.jobs[uid] ~= nil then return Wardrobe.fail("busy") end
    local card = People.card(person.id)
    if card == nil then return Wardrobe.fail("loading") end
    if card.adult ~= true then Wardrobe.metrics.refused = Wardrobe.metrics.refused + 1; return Wardrobe.fail("adult_only") end
    if (tonumber(card.traits.tidy) or 0) < 2 then Wardrobe.metrics.refused = Wardrobe.metrics.refused + 1; return Wardrobe.fail("card_refuses") end
    if Wardrobe.minorNear(record) then Wardrobe.metrics.refused = Wardrobe.metrics.refused + 1; return Wardrobe.fail("minor_present") end
    local show = spec.underwear ~= false
    if show then
        local ok, why = Wardrobe.privacy(uid, options.privacyStrict ~= false)
        if not ok then Wardrobe.metrics.refused = Wardrobe.metrics.refused + 1; return Wardrobe.fail(why) end
    end
    local list = Wardrobe.listFor(record, card)
    if list == nil then return Wardrobe.fail("no_dress") end
    local current = Wardrobe.withUnderwear(Wardrobe.entriesFrom(list), card.sex == "f")
    local goal, why = Wardrobe.goalFor(record, card, current, spec)
    if goal == nil then return Wardrobe.fail(why) end
    local female = card.sex == "f"
    local covered, reason = Master.covered(goal, female)
    if not covered then Wardrobe.metrics.violations = Wardrobe.metrics.violations + 1; return Wardrobe.fail("goal_" .. tostring(reason)) end
    local life = record.memory.life
    local job = { stages = Wardrobe.stagesFor(current, goal, show), stage = 1, female = female, goal = Wardrobe.pairsFrom(goal),
        restore = Wardrobe.pairsFrom(current), enforceLife = type(life) == "table" and life.k == "change" }
    job.dueMs = Wardrobe.nowMs() + job.stages[1].delay
    Wardrobe.jobs[uid] = job
    Wardrobe.metrics.changes = Wardrobe.metrics.changes + 1
    Wardrobe.arm()
    return true
end

function Wardrobe.commit(uid, job, stage)
    local covered, reason = Master.covered(stage.list, job.female)
    if not covered then
        Wardrobe.metrics.violations = Wardrobe.metrics.violations + 1
        return false, reason
    end
    local list = Wardrobe.pairsFrom(stage.list)
    local held = stage.held ~= nil and Wardrobe.pairsFrom(stage.held) or nil
    local hours = Instance.hours(Wardrobe.hours())
    local ok, why = Instance.write(uid, function(memory)
        local dress = type(memory.dress) == "table" and memory.dress or {}
        memory.dress = dress
        dress.list = list
        dress.rev = (tonumber(dress.rev) or 0) + 1
        dress.since = hours
        if stage.final then
            dress.stage, dress.held, dress.goal = nil, nil, nil
        else
            dress.stage, dress.held, dress.goal = stage.name, held, job.goal
        end
        if type(memory.person) == "table" then Instance.setDressState(memory.person, stage.state) end
    end)
    if ok then Wardrobe.metrics.stages = Wardrobe.metrics.stages + 1 end
    return ok, why
end

function Wardrobe.stillChanging(record)
    local life = record.memory.life
    return type(life) == "table" and life.k == "change"
end

function Wardrobe.advance(uid, job, now)
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and registry.peek(uid) or nil
    if record == nil or Instance.of(record) == nil or record.lifecycle == "dead" then return true end
    if job.enforceLife and not Wardrobe.stillChanging(record) then
        if job.stage == 1 then return true end
        job.stage, job.dueMs = #job.stages, now
    end
    if now < job.dueMs then return false end
    local stage = job.stages[job.stage]
    if stage == nil then return true end
    local ok = Wardrobe.commit(uid, job, stage)
    if not ok then
        Wardrobe.restore(uid, job)
        return true
    end
    if stage.final then return true end
    job.stage = job.stage + 1
    job.dueMs = now + job.stages[job.stage].delay
    return false
end

function Wardrobe.restore(uid, job)
    local restore = job.restore
    Instance.write(uid, function(memory)
        local dress = memory.dress
        if type(dress) ~= "table" then return end
        dress.list, dress.stage, dress.held, dress.goal = restore, nil, nil, nil
        dress.rev = (tonumber(dress.rev) or 0) + 1
        if type(memory.person) == "table" then Instance.setDressState(memory.person, "dressed") end
    end)
end

function Wardrobe.pump()
    local now = Wardrobe.nowMs()
    if now < Wardrobe.nextPassMs then return end
    Wardrobe.nextPassMs = now + Wardrobe.settings.passMs
    local done = {}
    for uid, job in pairs(Wardrobe.jobs) do
        if Wardrobe.advance(uid, job, now) then done[#done + 1] = uid end
    end
    for _, uid in ipairs(done) do Wardrobe.jobs[uid] = nil end
    local seeds = {}
    for uid, tries in pairs(Wardrobe.pending) do seeds[#seeds + 1] = { uid, tries } end
    for _, row in ipairs(seeds) do
        local uid = row[1]
        Wardrobe.pending[uid] = nil
        local registry = ProjectALife.ActorRegistry
        local record = registry ~= nil and registry.peek(uid) or nil
        local dress = Wardrobe.rowOf(record)
        if dress ~= nil and dress.stage ~= nil and Wardrobe.jobs[uid] == nil then Wardrobe.heal(uid) end
        if record ~= nil and (dress == nil or Wardrobe.storedList(record) == nil or dress.body == nil) then
            local ok, why = Wardrobe.seed(uid)
            if not ok and why == "loading" and row[2] < Wardrobe.settings.retryMax * 4 then Wardrobe.pending[uid] = row[2] + 1 end
        end
    end
    Wardrobe.retryQueue(now)
    Wardrobe.disarm()
end

function Wardrobe.idle()
    for _ in pairs(Wardrobe.jobs) do return false end
    for _ in pairs(Wardrobe.pending) do return false end
    for _ in pairs(Wardrobe.queue) do return false end
    return true
end

function Wardrobe.arm()
    if Wardrobe.armed or type(Events) ~= "table" or type(Events.OnTick) ~= "table" or type(Events.OnTick.Add) ~= "function" then
        return false
    end
    Events.OnTick.Add(Wardrobe.pump)
    Wardrobe.armed = true
    return true
end

function Wardrobe.disarm()
    if not Wardrobe.armed or not Wardrobe.idle() then return false end
    if type(Events) == "table" and type(Events.OnTick) == "table" and type(Events.OnTick.Remove) == "function" then
        Events.OnTick.Remove(Wardrobe.pump)
    end
    Wardrobe.armed = false
    return true
end

function Wardrobe.intruder(record)
    if type(Wardrobe.adapters.intruder) == "function" then return Wardrobe.adapters.intruder(record) end
    local life = ProjectALife.VisitorLife
    if life == nil or type(life.houseOf) ~= "function" or type(life.residents) ~= "function" or type(life.nearest) ~= "function" then
        return nil
    end
    local at = record.worldPosition
    if type(at) ~= "table" then return nil end
    local row = life.nearest(life.residents(life.houseOf(record)), tonumber(at.x) or 0, tonumber(at.y) or 0, tonumber(at.z) or 0)
    return row ~= nil and row.player or nil
end

function Wardrobe.caught(uid, player)
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and registry.peek(uid) or nil
    local person = Instance.of(record)
    if person == nil then return Wardrobe.fail("not_a_visitor") end
    if not Wardrobe.canWrite() then return Wardrobe.fail("client_write_refused") end
    local job = Wardrobe.jobs[uid]
    local dress = Wardrobe.rowOf(record)
    Wardrobe.jobs[uid] = nil
    if dress ~= nil and dress.stage ~= nil then
        local list = dress.list
        if dress.stage == "top_off" then
            local merged = Wardrobe.merge(Wardrobe.entriesFrom(dress.held), Wardrobe.entriesFrom(dress.list))
            local female = job ~= nil and job.female or false
            if Master.covered(merged, female) then
                list = Wardrobe.pairsFrom(merged)
            elseif job ~= nil then
                list = job.restore
            end
        end
        Instance.write(uid, function(memory)
            local row = memory.dress
            if type(row) ~= "table" then return end
            row.list, row.stage, row.held, row.goal = list, nil, nil, nil
            row.rev = (tonumber(row.rev) or 0) + 1
            if type(memory.person) == "table" then Instance.setDressState(memory.person, "dressed") end
        end)
    elseif person.ds ~= "dressed" then
        Instance.write(uid, function(memory)
            if type(memory.person) == "table" then Instance.setDressState(memory.person, "dressed") end
        end)
    end
    Wardrobe.metrics.caught = Wardrobe.metrics.caught + 1
    Wardrobe.caughtCount[uid] = (Wardrobe.caughtCount[uid] or 0) + 1
    local witness = player or Wardrobe.intruder(record)
    local kind = Wardrobe.caughtCount[uid] >= 2 and "privacy_lingered" or "privacy_caught"
    local applied = 0
    if witness ~= nil then
        local talk = ProjectALife.VisitorTalk
        if talk ~= nil and type(talk.reaction) == "function" then
            applied = talk.reaction(witness, uid, kind, nil) or 0
        else
            applied = React.note(kind, registry.peek(uid) or record, witness, nil) or 0
        end
    end
    return true, applied
end

function Wardrobe.wants(record, player, itemType)
    local person = Instance.of(record)
    if person == nil then return false, "not_a_visitor" end
    if Instance.need(person, "cold") >= 2 or Instance.need(person, "dirty") >= 3 then return true, "need" end
    local card = People.card(person.id)
    local pride = card ~= nil and tonumber(card.traits.pride) or 0
    local trust = 0
    local opinion = ProjectALife.NpcOpinion
    if opinion ~= nil and type(opinion.valueOf) == "function" and player ~= nil then
        trust = tonumber((opinion.valueOf(record, player))) or 0
    end
    if pride >= 4 and trust < 20 then return false, "pride" end
    return true, "polite"
end

function Wardrobe.tintOf(item)
    if item == nil or type(item.getVisual) ~= "function" then return "" end
    local ok, text = pcall(function()
        local visual = item:getVisual()
        local color = visual ~= nil and visual:getTint(item:getClothingItem()) or nil
        if color == nil then return "" end
        return string.format("%.2f,%.2f,%.2f", color:getRedFloat(), color:getGreenFloat(), color:getBlueFloat())
    end)
    if ok and Wardrobe.validTint(text) then return text end
    return ""
end

function Wardrobe.typeOf(item)
    if type(item) == "string" then return item end
    if item ~= nil and type(item.getFullType) == "function" then return item:getFullType() end
    return nil
end

function Wardrobe.store(uid, itemType)
    return Instance.write(uid, function(memory)
        local dress = type(memory.dress) == "table" and memory.dress or {}
        memory.dress = dress
        local extra = type(dress.extra) == "table" and dress.extra or {}
        dress.extra = extra
        for _, held in ipairs(extra) do
            if held == itemType then return end
        end
        if #extra < Wardrobe.settings.maxExtra then extra[#extra + 1] = itemType end
    end)
end

function Wardrobe.putOn(uid, card, entries, itemType, tint, replaced)
    local gone, list = {}, {}
    for _, old in ipairs(replaced) do gone[old.itemType] = true end
    for _, entry in ipairs(entries) do
        if not gone[entry.itemType] then list[#list + 1] = entry end
    end
    list[#list + 1] = { slot = Master.infoOf(itemType).name, itemType = itemType, tint = tint }
    if not Master.covered(list, card.sex == "f") then
        Wardrobe.metrics.violations = Wardrobe.metrics.violations + 1
        return false
    end
    local pairsList = Wardrobe.pairsFrom(Wardrobe.entriesFrom(Wardrobe.pairsFrom(list)))
    local hours = Instance.hours(Wardrobe.hours())
    return Instance.write(uid, function(memory)
        local dress = type(memory.dress) == "table" and memory.dress or {}
        memory.dress = dress
        dress.list, dress.since = pairsList, hours
        dress.rev = (tonumber(dress.rev) or 0) + 1
        local extra = type(dress.extra) == "table" and dress.extra or {}
        dress.extra = extra
        for _, old in ipairs(replaced) do
            if #extra < Wardrobe.settings.maxExtra then extra[#extra + 1] = old.itemType end
        end
    end)
end

function Wardrobe.keep(uid, itemType, note)
    Wardrobe.store(uid, itemType)
    Wardrobe.metrics.kept = Wardrobe.metrics.kept + 1
    return true, {}, note or "kept"
end

function Wardrobe.defer(uid, itemType, tint)
    local life = ProjectALife.VisitorLife
    if life == nil or type(life.beginChange) ~= "function" then return Wardrobe.keep(uid, itemType) end
    local began, why = life.beginChange(uid, { top = { itemType, tint } })
    if began == true then
        Wardrobe.metrics.deferred = Wardrobe.metrics.deferred + 1
        return true, {}, "deferred"
    end
    if why == "scan_pending" or why == "no_private_room" then
        Wardrobe.store(uid, itemType)
        Wardrobe.queue[uid] = { itemType = itemType, tint = tint, tries = 0, dueMs = Wardrobe.nowMs() + Wardrobe.settings.retryMs }
        Wardrobe.arm()
        Wardrobe.metrics.deferred = Wardrobe.metrics.deferred + 1
        return true, {}, "queued"
    end
    return Wardrobe.keep(uid, itemType)
end

function Wardrobe.wear(uid, item)
    local itemType = Wardrobe.typeOf(item)
    if not Wardrobe.validType(itemType) then return false, {}, "item_invalid" end
    if not Wardrobe.canWrite() then return false, {}, "client_write_refused" end
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and registry.peek(uid) or nil
    local person = Instance.of(record)
    if person == nil then return false, {}, "not_a_visitor" end
    local card = People.card(person.id)
    if card == nil then return false, {}, "loading" end
    local list = Wardrobe.listFor(record, card)
    if list == nil then return false, {}, "no_dress" end
    local entries = Wardrobe.withUnderwear(Wardrobe.entriesFrom(list), card.sex == "f")
    local ok, replaced, why = Master.accepts(entries, itemType)
    if not ok then return false, {}, why end
    local tint = type(item) == "string" and "" or Wardrobe.tintOf(item)
    if Wardrobe.jobs[uid] ~= nil then return Wardrobe.keep(uid, itemType) end
    if Master.baseKind(itemType) ~= nil then
        if person.ad ~= 1 or card.adult ~= true or Wardrobe.options().changeClothes == false then
            return Wardrobe.keep(uid, itemType)
        end
        return Wardrobe.defer(uid, itemType, tint)
    end
    if not Wardrobe.putOn(uid, card, entries, itemType, tint, replaced) then return false, {}, "write_failed" end
    Wardrobe.metrics.worn = Wardrobe.metrics.worn + 1
    return true, replaced, nil
end

function Wardrobe.sync(actor, shell)
    local hydrator = ProjectALife.ProfileHydrator
    local dress = Wardrobe.rowOf(actor)
    if dress == nil or shell == nil or hydrator == nil or type(hydrator.redress) ~= "function" then return false end
    if type(dress.list) ~= "table" or #dress.list == 0 then return false end
    local fence = ProjectALife.AIFence
    if fence ~= nil and type(fence.drivesBody) == "function" and fence.drivesBody(shell) ~= true then return false end
    local rev = tonumber(dress.rev) or 0
    if Wardrobe.seen[shell] == rev then return false end
    local ident = hydrator.dressIdent[shell]
    if ident == nil then return false end
    local entries = Wardrobe.entriesFrom(dress.list)
    if #entries == 0 then return false end
    local signature = hydrator.dressSignature(ident.uid, ident.seed, entries)
    if hydrator.dressList[shell] == signature then
        Wardrobe.seen[shell] = rev
        return false
    end
    local ok = hydrator.redress(shell, entries, ident)
    if ok then
        Wardrobe.seen[shell] = rev
        Wardrobe.metrics.synced = Wardrobe.metrics.synced + 1
    end
    return ok
end

function Wardrobe.reset()
    Wardrobe.jobs, Wardrobe.pending, Wardrobe.queue, Wardrobe.cache, Wardrobe.caughtCount = {}, {}, {}, {}, {}
    Wardrobe.cacheCount, Wardrobe.nextPassMs = 0, 0
    Wardrobe.seen = setmetatable({}, { __mode = "k" })
    for key, value in pairs(Wardrobe.metrics) do Wardrobe.metrics[key] = type(value) == "number" and 0 or "-" end
    Wardrobe.disarm()
end

function Wardrobe.retryQueue(now)
    local uids = {}
    for uid in pairs(Wardrobe.queue) do uids[#uids + 1] = uid end
    for _, uid in ipairs(uids) do
        local row = Wardrobe.queue[uid]
        if now >= row.dueMs then
            row.tries = row.tries + 1
            local life = ProjectALife.VisitorLife
            local began = life ~= nil and type(life.beginChange) == "function" and life.beginChange(uid, { top = { row.itemType, row.tint } })
            if began == true or row.tries >= Wardrobe.settings.retryMax then
                Wardrobe.queue[uid] = nil
                if began ~= true then Wardrobe.store(uid, row.itemType) end
            else
                row.dueMs = now + Wardrobe.settings.retryMs
            end
        end
    end
end

function Wardrobe.qaLine()
    local m = Wardrobe.metrics
    return "[ALIFE-QA] VisitorWardrobe refined=" .. tostring(m.refined) .. " seeded=" .. tostring(m.seeded)
        .. " changes=" .. tostring(m.changes) .. " stages=" .. tostring(m.stages) .. " caught=" .. tostring(m.caught)
        .. " refused=" .. tostring(m.refused) .. " violations=" .. tostring(m.violations) .. " worn=" .. tostring(m.worn)
        .. " kept=" .. tostring(m.kept) .. " deferred=" .. tostring(m.deferred) .. " synced=" .. tostring(m.synced)
        .. " healed=" .. tostring(m.healed) .. " why=" .. tostring(m.lastWhy)
end

return Wardrobe
