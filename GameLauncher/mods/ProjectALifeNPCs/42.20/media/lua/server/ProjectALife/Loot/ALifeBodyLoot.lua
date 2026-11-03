require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Loot/ALifeScavenging"

ProjectALife = ProjectALife or {}

local Loot = {
    settings = {
        perMinute = 3,
        scanMs = 7000,
        scanJitterMs = 2500,
        radius = 9,
        hostileTiles = 15,
        playerRadius = 70,
        reach = 1.5,
        approachMs = 15000,
        searchMs = 3600,
        takeMax = 3,
        cooldownMs = 18000,
        claimMs = 45000,
        skipMs = 90000,
        minScore = 65,
        windowMs = 60000,
        tableCap = 256,
        warmInsulation = 0.35,
    },
    keys = { enabled = "BodyLoot_Enabled", perMinute = "BodyLoot_PerMinute" },
    tools = { "hammer", "saw", "nails", "screwdriver", "axe", "crowbar", "wrench", "knife", "lighter", "matches" },
    states = {},
    nextAt = {},
    claims = {},
    skipped = {},
    windows = {},
    metrics = { scans = 0, started = 0, searched = 0, taken = 0, empty = 0, aborted = 0, refused = 0 },
}
ProjectALife.BodyLoot = Loot

function Loot.option(field, default)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = nil
    if type(vars) == "table" then value = vars[Loot.keys[field]] end
    if value == nil then return default end
    return value
end

function Loot.enabled()
    return Loot.option("enabled", true) ~= false
end

function Loot.perMinute()
    local value = tonumber(Loot.option("perMinute", Loot.settings.perMinute)) or Loot.settings.perMinute
    return math.max(1, math.min(20, math.floor(value)))
end

function Loot.reset()
    Loot.states, Loot.nextAt, Loot.claims, Loot.skipped, Loot.windows = {}, {}, {}, {}, {}
    for name in pairs(Loot.metrics) do Loot.metrics[name] = 0 end
end

function Loot.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Loot.xyz(object)
    if object == nil or type(object.getX) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return object:getX(), object:getY(), object:getZ() end)
    if ok and x ~= nil then return x, y, z end
    return nil
end

function Loot.flat(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function Loot.hash(text)
    local seed = 0
    for index = 1, #text do seed = (seed * 31 + string.byte(text, index)) % 100003 end
    return seed
end

function Loot.busy(shell, actor, now)
    local speech = ProjectALife.Speech
    if speech == nil or type(speech.quietReason) ~= "function" then return false end
    local ok, reason = pcall(speech.quietReason, shell, actor, now)
    return ok and reason ~= nil
end

function Loot.hostiles(actor, shell, now)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.inFight) == "function" and talk.inFight(actor, now) then return true end
    local fear = ProjectALife.ModuleFear
    if fear == nil or type(fear.scan) ~= "function" then return false end
    local ok, scan = pcall(fear.scan, actor, shell, now)
    if ok and type(scan) == "table" and scan.nearest ~= nil and scan.nearest <= Loot.settings.hostileTiles then return true end
    local state = type(fear.actors) == "table" and fear.actors[actor.uid] or nil
    return type(state) == "table" and state.state == "afraid"
end

function Loot.playerNear(shell)
    local presence = ProjectALife.ModuleTalkPresence
    if presence == nil or type(presence.players) ~= "function" then return true end
    local sx, sy = Loot.xyz(shell)
    if sx == nil then return false end
    local ok, list = pcall(presence.players)
    if not ok or type(list) ~= "table" then return true end
    for _, player in ipairs(list) do
        local px, py = Loot.xyz(player)
        if px ~= nil and Loot.flat(px, py, sx, sy) <= Loot.settings.playerRadius then return true end
    end
    return false
end

function Loot.groupKey(actor)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    return tostring(memory.groupId or memory.outpostId or actor.uid)
end

function Loot.windowOpen(actor, now)
    local window = Loot.windows[Loot.groupKey(actor)]
    if window == nil or now - window.atMs >= Loot.settings.windowMs then return true end
    return window.count < Loot.perMinute()
end

function Loot.noteWindow(actor, now)
    local key = Loot.groupKey(actor)
    local window = Loot.windows[key]
    if window == nil or now - window.atMs >= Loot.settings.windowMs then
        window = { atMs = now, count = 0 }
        Loot.windows[key] = window
    end
    window.count = window.count + 1
end

function Loot.prune(now)
    local count = 0
    for _ in pairs(Loot.skipped) do count = count + 1 end
    if count > Loot.settings.tableCap then Loot.skipped = {} end
    for key, claim in pairs(Loot.claims) do
        if now >= claim.untilMs then Loot.claims[key] = nil end
    end
    for key, window in pairs(Loot.windows) do
        if now - window.atMs >= Loot.settings.windowMs then Loot.windows[key] = nil end
    end
    for uid, at in pairs(Loot.nextAt) do
        if now >= at and Loot.states[uid] == nil then Loot.nextAt[uid] = nil end
    end
end

function Loot.bodyData(body)
    if body == nil or type(body.getModData) ~= "function" then return nil end
    if type(body.hasModData) == "function" and body:hasModData() ~= true then return nil end
    local data = body:getModData()
    return type(data) == "table" and data or nil
end

function Loot.ownedByPlayerSide(data, actor, now)
    if data == nil or data.ProjectALifeCorpseOf == nil then return false end
    local registry = ProjectALife.ActorRegistry
    if registry == nil then return false end
    local uid = tostring(data.ProjectALifeCorpseOf)
    local record = nil
    if type(registry.read) == "function" then record = registry.read(uid) end
    if record == nil and type(registry.peek) == "function" then record = registry.peek(uid) end
    if type(record) ~= "table" then return false end
    local memory = type(record.memory) == "table" and record.memory or {}
    local mine = type(actor.memory) == "table" and actor.memory or {}
    if memory.groupId ~= nil and memory.groupId == mine.groupId then return true end
    if type(memory.orderedTo) == "table" and memory.orderedTo.kind == "follow" then return true end
    if type(memory.tolerateUntil) == "table" then
        for _, untilMs in pairs(memory.tolerateUntil) do
            if (tonumber(untilMs) or 0) > now then return true end
        end
    end
    return false
end

function Loot.lootable(body, actor, now)
    local refuse = false
    pcall(function()
        if body:isPlayer() == true or body:isSkeleton() == true then refuse = true end
        if type(body.isReanimate) == "function" and body:isReanimate() == true then refuse = true end
    end)
    if refuse then return false end
    local data = Loot.bodyData(body)
    if data ~= nil and data.ProjectALifeBodyLooted == true then return false end
    if Loot.ownedByPlayerSide(data, actor, now) then
        Loot.metrics.refused = Loot.metrics.refused + 1
        return false
    end
    local hasContainer = false
    pcall(function() hasContainer = body:getContainer() ~= nil end)
    return hasContainer
end

function Loot.pick(actor, shell, now)
    Loot.metrics.scans = Loot.metrics.scans + 1
    local sx, sy, sz = Loot.xyz(shell)
    if sx == nil or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local radius = Loot.settings.radius
    local floorX, floorY, floorZ = math.floor(sx), math.floor(sy), math.floor(sz)
    local best, bestDistance = nil, math.huge
    for dx = -radius, radius do
        for dy = -radius, radius do
            local square = cell:getGridSquare(floorX + dx, floorY + dy, floorZ)
            local bodies = square ~= nil and square:getDeadBodys() or nil
            local total = bodies ~= nil and bodies:size() or 0
            for index = 0, math.min(total, 6) - 1 do
                local body = bodies:get(index)
                local key = tostring(floorX + dx) .. "," .. tostring(floorY + dy) .. "," .. tostring(floorZ) .. ":" .. tostring(index)
                local claim = Loot.claims[key]
                local held = claim ~= nil and claim.uid ~= actor.uid and now < claim.untilMs
                if not held and now >= (Loot.skipped[key] or 0) and Loot.lootable(body, actor, now) then
                    local span = Loot.flat(sx, sy, floorX + dx + 0.5, floorY + dy + 0.5)
                    if span < bestDistance then
                        best = { body = body, key = key, x = floorX + dx + 0.5, y = floorY + dy + 0.5, z = floorZ }
                        bestDistance = span
                    end
                end
            end
        end
    end
    return best
end

function Loot.textOf(item)
    local parts = {}
    for _, method in ipairs({ "getFullType", "getType", "getDisplayCategory" }) do
        local ok, value = pcall(function() return item[method](item) end)
        if ok and value ~= nil then parts[#parts + 1] = tostring(value) end
    end
    return string.lower(table.concat(parts, " "))
end

function Loot.warmNeeded(actor)
    local cold = ProjectALife.Cold
    if cold == nil or type(cold.view) ~= "function" then return false end
    local ok, view = pcall(cold.view, actor)
    return ok and (view == "chilled" or view == "freezing")
end

function Loot.wornOnBody(body, item)
    local worn = false
    pcall(function()
        local list = body:getWornItems()
        for index = 0, list:size() - 1 do
            if list:get(index):getItem() == item then worn = true end
        end
    end)
    return worn
end

function Loot.valueOf(item, shell, actor, body)
    local text = Loot.textOf(item)
    if string.find(text, "projectalife", 1, true) ~= nil or string.find(text, "barehands", 1, true) ~= nil then return 0 end
    local rotten = false
    if type(item.isRotten) == "function" then
        pcall(function() rotten = item:isRotten() == true end)
    end
    if rotten then return 0 end
    local isClothing, isBag, isWeapon = false, false, false
    pcall(function()
        isClothing = instanceof(item, "Clothing")
        isBag = instanceof(item, "InventoryContainer")
        isWeapon = instanceof(item, "HandWeapon")
    end)
    if isBag then return 0 end
    if isClothing then
        if not Loot.warmNeeded(actor) or Loot.wornOnBody(body, item) then return 0 end
        local warm = 0
        pcall(function() warm = tonumber(item:getInsulation()) or 0 end)
        if warm >= Loot.settings.warmInsulation then return 70 end
        return 0
    end
    if isWeapon then
        local broken = false
        pcall(function()
            broken = (tonumber(item:getConditionMax()) or 0) > 0 and (tonumber(item:getCondition()) or 1) <= 0
        end)
        if broken then return 0 end
        local orders = ProjectALife.TalkOrders
        local better = true
        if orders ~= nil and type(orders.better) == "function" then better = orders.better(shell, item) == true end
        if not better then return 0 end
    end
    local scavenging = ProjectALife.Scavenging
    local score = scavenging ~= nil and type(scavenging.scoreItem) == "function" and scavenging.scoreItem(item, nil) or 0
    if score >= Loot.settings.minScore then return score end
    for _, word in ipairs(Loot.tools) do
        if string.find(text, word, 1, true) ~= nil then return 60 end
    end
    return 0
end

function Loot.eventFor(item)
    local scavenging = ProjectALife.Scavenging
    local found = scavenging ~= nil and type(scavenging.foundEventFor) == "function"
        and scavenging.foundEventFor(Loot.textOf(item)) or "FOUND_GEAR"
    if found == "FOUND_AMMO" then return "BODY_LOOT_AMMO" end
    if found == "FOUND_MEDICINE" then return "BODY_LOOT_MEDS" end
    if found == "FOUND_FOOD" or found == "FOUND_WATER" then return "BODY_LOOT_FOOD" end
    if found == "FOUND_WEAPON" then return "BODY_LOOT_WEAPON" end
    return "BODY_LOOT_FOUND"
end

function Loot.say(actor, shell, event)
    local speech, data = ProjectALife.Speech, ProjectALife.DialogueData
    if speech == nil or data == nil then return nil end
    local text = nil
    pcall(function()
        if type(data.load) == "function" then data.load() end
        if not speech.allows(shell, actor, event, nil, nil) then return end
        local context = speech.contextFor(actor, nil)
        context.stance = "neutral"
        local chosen = speech.pick(data.barks[event], context, actor.uid, "bodyloot", nil)
        if chosen == nil then return end
        text = speech.render(chosen.t, {}, shell)
        if not speech.say(shell, text, {}) then text = nil; return end
        speech.remember(actor.uid, "bodyloot", chosen.t)
    end)
    return text
end

function Loot.take(actor, shell, state)
    local scavenging = ProjectALife.Scavenging
    local container = nil
    pcall(function() container = state.body:getContainer() end)
    if container == nil or scavenging == nil or type(scavenging.transfer) ~= "function" then return 0, nil end
    local candidates = {}
    pcall(function()
        local items = container:getItems()
        for index = 0, math.min(items:size(), 96) - 1 do
            local item = items:get(index)
            local value = Loot.valueOf(item, shell, actor, state.body)
            if value > 0 then candidates[#candidates + 1] = { item = item, value = value } end
        end
    end)
    table.sort(candidates, function(a, b) return a.value > b.value end)
    local taken, event = 0, nil
    for _, entry in ipairs(candidates) do
        if taken >= Loot.settings.takeMax then break end
        local ok, moved = pcall(scavenging.transfer, shell,
            { container = container, item = entry.item, x = state.x, y = state.y, z = state.z })
        local sent = moved == nil and type(isClient) == "function" and isClient() == true
        if ok and (moved == true or sent) then
            taken = taken + 1
            if event == nil then event = Loot.eventFor(entry.item) end
        end
    end
    return taken, event
end

function Loot.markDone(state)
    pcall(function()
        local data = state.body:getModData()
        if type(data) == "table" then data.ProjectALifeBodyLooted = true end
    end)
end

function Loot.release(actor, shell, state, now, skip)
    Loot.states[actor.uid] = nil
    if state ~= nil then
        Loot.claims[state.key] = nil
        if skip then Loot.skipped[state.key] = now + Loot.settings.skipMs end
        if state.phase == "search" then
            local animations = ProjectALife.Animations
            if animations ~= nil then pcall(animations.clear, shell) end
        end
    end
end

function Loot.advance(actor, shell, context, state, now)
    local sx, sy, sz = Loot.xyz(shell)
    if sx == nil or math.floor(sz) ~= state.z then
        Loot.metrics.aborted = Loot.metrics.aborted + 1
        Loot.release(actor, shell, state, now, true)
        return nil
    end
    local gap = Loot.flat(sx, sy, state.x, state.y)
    if state.phase == "search" and gap > Loot.settings.reach + 1 then
        Loot.metrics.aborted = Loot.metrics.aborted + 1
        Loot.release(actor, shell, state, now, false)
        return nil
    end
    if state.phase == "go" then
        if now >= state.untilMs then
            Loot.metrics.aborted = Loot.metrics.aborted + 1
            Loot.release(actor, shell, state, now, true)
            return nil
        end
        if gap > Loot.settings.reach then
            return context.startMovement(actor, shell, { x = state.x, y = state.y, z = state.z }, "loot_body", {
                pace = "walk", tolerance = 0.9, timeoutMs = math.min(9000, state.untilMs - now), activity = "moving" })
        end
        state.phase, state.untilMs = "search", now + Loot.settings.searchMs
        pcall(function() shell:faceThisObject(state.body) end)
        local animations = ProjectALife.Animations
        if animations ~= nil then pcall(animations.apply, shell, "search_low") end
    end
    if now < state.untilMs then
        context.setActivity(actor, "scavenging", "search_body")
        return { kind = "idle", intent = "search_body", cooldownUntilMs = now + 400 }
    end
    Loot.metrics.searched = Loot.metrics.searched + 1
    local taken, event = Loot.take(actor, shell, state)
    Loot.markDone(state)
    Loot.noteWindow(actor, now)
    Loot.release(actor, shell, state, now, false)
    Loot.nextAt[actor.uid] = now + Loot.settings.cooldownMs
    if taken > 0 then
        Loot.metrics.taken = Loot.metrics.taken + taken
        Loot.say(actor, shell, event or "BODY_LOOT_FOUND")
    else
        Loot.metrics.empty = Loot.metrics.empty + 1
        Loot.say(actor, shell, "BODY_LOOT_NOTHING")
    end
    return { kind = "idle", intent = "search_body_done", cooldownUntilMs = now + 900 }
end

function Loot.step(actor, shell, context, now)
    if not Loot.enabled() then return nil end
    if type(actor) ~= "table" or type(actor.uid) ~= "string" or shell == nil or type(context) ~= "table" then return nil end
    if type(context.startMovement) ~= "function" or type(context.setActivity) ~= "function" then return nil end
    local state = Loot.states[actor.uid]
    if context.threat ~= nil or Loot.busy(shell, actor, now) or Loot.hostiles(actor, shell, now) then
        if state ~= nil then
            Loot.metrics.aborted = Loot.metrics.aborted + 1
            Loot.release(actor, shell, state, now, false)
        end
        return nil
    end
    if state == nil then
        if now < (Loot.nextAt[actor.uid] or 0) then return nil end
        Loot.nextAt[actor.uid] = now + Loot.settings.scanMs + Loot.hash(actor.uid) % Loot.settings.scanJitterMs
        if not Loot.windowOpen(actor, now) or not Loot.playerNear(shell) then return nil end
        Loot.prune(now)
        local pick = Loot.pick(actor, shell, now)
        if pick == nil then return nil end
        pick.phase, pick.untilMs = "go", now + Loot.settings.approachMs
        state = pick
        Loot.states[actor.uid] = state
        Loot.claims[state.key] = { uid = actor.uid, untilMs = now + Loot.settings.claimMs }
        Loot.metrics.started = Loot.metrics.started + 1
    end
    return Loot.advance(actor, shell, context, state, now)
end

return Loot
