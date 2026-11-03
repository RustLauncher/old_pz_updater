require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Talk/ALifeTalk"
require "ProjectALife/Talk/ALifeTalkOrderRows"

ProjectALife = ProjectALife or {}

local Orders = {
    settings = {
        enabled = true,
        chancePercent = 100,
        zombieTiles = 4,
        fightPercent = 100,
        surrenderMs = 90000,
        followMs = 120000,
        leaveMs = 30000,
        leaveTiles = 40,
        tickMs = 500,
        holdEveryMs = 2500,
        reach = 14,
        lostMs = 8000,
        frisk = 3.5,
        friskWeapons = 4,
        friskItems = 6,
        robItems = 8,
        crewRadius = 12,
        maxStates = 32,
        partyRadius = 15,
        solidarity = 10,
        fleeDelayMs = 6000,
        fleeMs = 22000,
        fleeTiles = 36,
        reliefGapMs = 4000,
        resistTellMs = 1100,
        carefulMinutes = 15,
        greetPercent = 75,
    },
    keys = { advantage = "Orders_Advantage", group = "Orders_GroupSurrender", careful = "Orders_CarefulMinutes",
        greet = "Talk_GreetOnOpen" },
    classBase = { civilian = 85, worker = 62, rescue = 58, police = 24, military = 14, criminal = 20 },
    kindShift = { hands_up = 0, drop = -5, surrender = -8, rob = -14, out = 14, leave = 10, follow = -12 },
    temperamentShift = { fresh = 10, seasoned = 0, veteran = -12, predator = -22 },
    hardKinds = { hands_up = true, drop = true, surrender = true, rob = true },
    states = {},
    lastTickAtMs = 0,
    metrics = { asked = 0, won = 0, lost = 0, fights = 0, surrendered = 0, cancelledZombie = 0, released = 0,
        frisked = 0, itemsTaken = 0, weaponsDropped = 0, sentAway = 0, followed = 0, adopted = 0, equipped = 0 },
}
ProjectALife.TalkOrders = Orders

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll(maximum)
    if type(ZombRand) == "function" then return ZombRand(maximum) end
    return 0
end

local function registry() return ProjectALife.ActorRegistry end

local function position(object)
    if object == nil or type(object.getX) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return object:getX(), object:getY(), object:getZ() end)
    if ok and x ~= nil then return x, y, z end
    return nil
end

local function distance(a, b)
    local ax, ay = position(a)
    local bx, by = position(b)
    if ax == nil or bx == nil then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function Orders.configure(options)
    options = type(options) == "table" and options or {}
    local s = Orders.settings
    if options.enabled ~= nil then s.enabled = options.enabled ~= false end
    if options.chance ~= nil then s.chancePercent = math.max(0, math.min(200, tonumber(options.chance) or 100)) end
    if options.zombieTiles ~= nil then s.zombieTiles = math.max(1, math.min(8, tonumber(options.zombieTiles) or 4)) end
    if options.fightPercent ~= nil then s.fightPercent = math.max(0, math.min(100, tonumber(options.fightPercent) or 100)) end
    if options.surrenderSeconds ~= nil then
        s.surrenderMs = math.max(10, math.min(600, tonumber(options.surrenderSeconds) or 90)) * 1000
    end
    return s
end

function Orders.reset()
    Orders.states = {}
    Orders.lastTickAtMs = 0
    for name in pairs(Orders.metrics) do Orders.metrics[name] = 0 end
end

function Orders.count(name)
    Orders.metrics[name] = (Orders.metrics[name] or 0) + 1
end

function Orders.classOf(record)
    local rows = ProjectALife.TalkOrderRows
    return rows ~= nil and rows.classOf(record) or nil
end

function Orders.threatOf(player)
    local armed, ranged, aiming = false, false, false
    pcall(function()
        local weapon = player:getPrimaryHandItem()
        if weapon ~= nil and instanceof(weapon, "HandWeapon") and tostring(weapon:getFullType()) ~= "Base.BareHands" then
            armed, ranged = true, weapon:isRanged() == true
        end
        aiming = player:isAiming() == true
    end)
    return armed, ranged, aiming
end

function Orders.option(field, default)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = nil
    if type(vars) == "table" then value = vars[Orders.keys[field]] end
    if value == nil then return default end
    return value
end

function Orders.sensitivity()
    local value = tonumber(Orders.option("advantage", 100)) or 100
    return math.max(0, math.min(300, value)) / 100
end

function Orders.shellArms(shell)
    local ranged, melee = false, false
    pcall(function()
        local held = shell:getPrimaryHandItem()
        if held ~= nil and instanceof(held, "HandWeapon") and tostring(held:getFullType()) ~= "Base.BareHands" then
            if held:isRanged() == true then ranged = true else melee = true end
        end
    end)
    return ranged, melee
end

function Orders.armorOf(shell)
    local total = 0
    pcall(function()
        local worn = shell:getWornItems()
        for index = 0, worn:size() - 1 do
            local item = worn:get(index):getItem()
            if item ~= nil and instanceof(item, "Clothing") then
                total = total + (tonumber(item:getBiteDefense()) or 0) + (tonumber(item:getScratchDefense()) or 0)
            end
        end
    end)
    return math.min(4, math.floor(total / 50))
end

function Orders.gunEmpty(player)
    local empty = false
    pcall(function()
        local weapon = player:getPrimaryHandItem()
        if weapon ~= nil and instanceof(weapon, "HandWeapon") and weapon:isRanged() == true then
            local rounds = tonumber(weapon:getCurrentAmmoCount())
            empty = rounds ~= nil and rounds <= 0
        end
    end)
    return empty
end

function Orders.partyOf(player)
    local count = 0
    local reach = Orders.settings.partyRadius
    local presence = ProjectALife.ModuleTalkPresence
    if presence ~= nil and type(presence.players) == "function" then
        for _, other in ipairs(presence.players()) do
            if other ~= player and distance(other, player) <= reach then count = count + 1 end
        end
    end
    local reg, talk = registry(), ProjectALife.Talk
    local key = ProjectALife.Speech.playerKey(player)
    if reg ~= nil and key ~= nil then
        reg.each(function(other)
            local held = type(other.memory) == "table" and other.memory.orderedTo or nil
            if other.lifecycle == "active" and type(held) == "table" and held.kind == "follow" and held.playerKey == key then
                local shell = talk.shellFor(other.uid)
                if shell ~= nil and distance(shell, player) <= reach then count = count + 1 end
            end
        end)
    end
    return count
end

function Orders.edge(shell, player, crew)
    local armed, ranged, aiming = Orders.threatOf(player)
    local gain = math.min(3, Orders.partyOf(player)) * 8
    if ranged and Orders.gunEmpty(player) then gain = gain - (aiming and 28 or 14) end
    local loss, armor = 6 * math.max(0, #crew - 1), 0
    for _, member in ipairs(crew) do
        local gun, blade = Orders.shellArms(member.shell)
        if gun then loss = loss + 4 elseif blade then loss = loss + 2 end
        armor = armor + Orders.armorOf(member.shell)
    end
    loss = math.min(32, loss + math.min(8, armor))
    local span = distance(player, shell)
    local near = 0
    if span <= 3 then near = 8 elseif span <= 6 then near = 4 elseif span > 20 then near = -12 elseif span > 14 then near = -6 end
    local careful = ProjectALife.ModuleCareful
    local cover = 0
    if careful ~= nil and type(careful.lineOfSight) == "function" then
        local ok, seen = pcall(careful.lineOfSight, shell, player)
        if ok and seen == false then cover = -14 end
    end
    return math.floor((gain - loss + near + cover) * Orders.sensitivity() + 0.5)
end

Orders.repRules = {
    leave = { fear = 25, respect = 25, middle = -15 },
    surrender = { fear = 15, respect = 0, middle = 0 },
    rob = { fear = 20, respect = -10, middle = 0 },
}
Orders.repBand = { fear = -50, respect = 50 }

function Orders.repShift(kind, player)
    local rule = Orders.repRules[kind]
    if rule == nil then return 0 end
    local personal = ProjectALife.PersonalRep
    if personal == nil or type(personal.score) ~= "function" then return 0 end
    local ok, score = pcall(personal.score, player)
    if not ok or type(score) ~= "number" then return 0 end
    if score <= Orders.repBand.fear then return rule.fear end
    if score >= Orders.repBand.respect then return rule.respect end
    return rule.middle
end

function Orders.chanceFor(kind, record, shell, player, context, crew)
    local class = Orders.classOf(record)
    local total = Orders.classBase[class or ""] or 30
    total = total + (Orders.kindShift[kind] or 0)
    local armed, ranged, aiming = Orders.threatOf(player)
    if ranged and aiming then total = total + 28
    elseif ranged then total = total + 14
    elseif armed then total = total + 8
    else total = total - 15 end
    pcall(function()
        local held = shell:getPrimaryHandItem()
        if held ~= nil and instanceof(held, "HandWeapon") and held:isRanged() == true then total = total - 6 end
    end)
    context = type(context) == "table" and context or {}
    total = total + (Orders.temperamentShift[tostring(context.temperament)] or 0)
    total = total + Orders.repShift(kind, player)
    if ProjectALife.NpcOpinion ~= nil and type(ProjectALife.NpcOpinion.orderShift) == "function" then
        local ok, shift = pcall(ProjectALife.NpcOpinion.orderShift, record, player)
        if ok and type(shift) == "number" then total = total + shift end
    end
    local fear = ProjectALife.ModuleFear
    local state = fear ~= nil and type(fear.actors) == "table" and fear.actors[record.uid] or nil
    if type(state) == "table" and state.state == "afraid" then total = total + 20 end
    total = total + Orders.edge(shell, player, type(crew) == "table" and crew or Orders.crew(record, shell))
    local rows = ProjectALife.TalkOrderRows
    local job = rows ~= nil and rows.jobOf(player) or nil
    if job == "law" or job == "military" then
        if class == "civilian" or class == "worker" or class == "rescue" then total = total + 12
        elseif class == "criminal" then total = total + 6 end
    end
    if context.stance == "friendly" then total = total + 10
    elseif context.stance == "careful" then total = total - 5 end
    total = total * Orders.settings.chancePercent / 100
    return math.max(2, math.min(96, math.floor(total + 0.5))), class
end

function Orders.say(record, shell, player, event, context, vars)
    local talk = ProjectALife.Talk
    local ok, text = pcall(talk.bark, record, shell, player, event, context, vars)
    if ok then return text end
    return nil
end

function Orders.crew(record, shell, radius)
    local list = { { record = record, shell = shell } }
    local talk = ProjectALife.Talk
    for _, member in ipairs(talk.groupMembers(record, radius or Orders.settings.crewRadius, shell)) do
        list[#list + 1] = member
    end
    return list
end

function Orders.writeOrdered(uid, value)
    local talk = ProjectALife.Talk
    talk.writeMemory(uid, function(memory) memory.orderedTo = value end)
    local brain = ProjectALife.DecisionLoop
    if brain ~= nil and type(brain.refreshDirective) == "function" then pcall(brain.refreshDirective, uid) end
end

function Orders.pose(shell)
    local animations = ProjectALife.Animations
    if animations == nil or shell == nil then return false end
    return pcall(animations.apply, shell, "surrender")
end

function Orders.beginSurrender(record, shell, player, now, kind)
    local speech, talk = ProjectALife.Speech, ProjectALife.Talk
    local key = speech.playerKey(player)
    if key == nil or shell == nil then return false end
    local count = 0
    for _ in pairs(Orders.states) do count = count + 1 end
    if Orders.states[record.uid] == nil and count >= Orders.settings.maxStates then return false end
    local untilMs = now + Orders.settings.surrenderMs
    Orders.states[record.uid] = { uid = record.uid, playerKey = key, player = player, atMs = now, untilMs = untilMs,
        lastSeenMs = now, holdAtMs = now, kind = kind }
    Orders.count("surrendered")
    Orders.pose(shell)
    talk.hold(record, shell, player, now, 4000)
    Orders.writeOrdered(record.uid, { kind = "surrender", playerKey = key, untilMs = untilMs })
    return true
end

function Orders.surrenderCrew(record, shell, player, now, kind)
    local any = false
    for _, member in ipairs(Orders.crew(record, shell)) do
        if Orders.beginSurrender(member.record, member.shell, player, now, kind) then any = true end
    end
    return any
end

function Orders.memberContext(member, player)
    local ok, context = pcall(ProjectALife.Speech.contextFor, member.record, player)
    context = ok and type(context) == "table" and context or {}
    context.stance = ProjectALife.Talk.stance(member.record, player)
    return context
end

function Orders.canFight(member)
    local class = Orders.classOf(member.record)
    if class == "police" or class == "military" or class == "criminal" then return true end
    local gun, blade = Orders.shellArms(member.shell)
    return gun or blade
end

function Orders.groupSurrender(kind, record, shell, player, context, now)
    local crew = Orders.crew(record, shell)
    local talk = ProjectALife.Talk
    local yes, no = { crew[1] }, {}
    local grouped = Orders.option("group", true) ~= false
    for index = 2, #crew do
        local member = crew[index]
        if not talk.busy(member.record, now) then
            local willing = true
            if grouped then
                local chance = Orders.chanceFor(kind, member.record, member.shell, player,
                    Orders.memberContext(member, player), crew) + Orders.settings.solidarity
                willing = roll(100) < math.min(96, chance)
            end
            if willing then yes[#yes + 1] = member else no[#no + 1] = member end
        end
    end
    Orders.surrenderMembers(yes, player, now, kind)
    for index = 2, math.min(3, #yes) do
        local member = yes[index]
        talk.later(400 + index * 500, function()
            Orders.say(member.record, member.shell, player, "ORD_GROUP_HANDS_UP", Orders.memberContext(member, player))
        end)
    end
    Orders.count("groupYes")
    if #no > 0 then Orders.resistMembers(no, player, now) end
    return yes
end

function Orders.surrenderMembers(list, player, now, kind)
    local any = false
    for _, member in ipairs(list) do
        if Orders.beginSurrender(member.record, member.shell, player, now, kind) then any = true end
    end
    return any
end

function Orders.resistMembers(list, player, now)
    local fighters, runners = {}, {}
    for _, member in ipairs(list) do
        if Orders.canFight(member) and roll(100) < Orders.settings.fightPercent then
            fighters[#fighters + 1] = member
        else
            runners[#runners + 1] = member
        end
    end
    local talk = ProjectALife.Talk
    if #fighters > 0 then
        Orders.count("groupFight")
        local first = fighters[1]
        Orders.say(first.record, first.shell, player, "ORD_RESIST_FIGHT", Orders.memberContext(first, player))
        local uids = {}
        for _, member in ipairs(fighters) do uids[#uids + 1] = member.record.uid end
        talk.later(Orders.settings.resistTellMs, function() Orders.turnUids(uids, player) end)
    end
    if #runners > 0 then
        Orders.count("groupFlee")
        local first = runners[1]
        Orders.say(first.record, first.shell, player, "ORD_RESIST_FLEE", Orders.memberContext(first, player))
        for _, member in ipairs(runners) do Orders.runAway(member.record, member.shell, player, now) end
    end
end

function Orders.markWary(record, key, now)
    local minutes = tonumber(Orders.option("careful", Orders.settings.carefulMinutes)) or 0
    if minutes <= 0 or key == nil then return false end
    local untilMs = now + math.min(240, minutes) * 60000
    return ProjectALife.Talk.writeMemory(record.uid, function(memory)
        memory.carefulPlayerKeys = type(memory.carefulPlayerKeys) == "table" and memory.carefulPlayerKeys or {}
        memory.carefulPlayerKeys[key] = untilMs
        if type(memory.tolerateUntil) == "table" then memory.tolerateUntil[key] = nil end
    end)
end

function Orders.noteRobbery(record, player)
    local reputation, standing = ProjectALife.Reputation, ProjectALife.Standing
    if reputation ~= nil and type(reputation.onPlayerRobbed) == "function" then pcall(reputation.onPlayerRobbed, player, record) end
    if standing ~= nil and type(standing.noteRobbed) == "function" then pcall(standing.noteRobbed, player, record) end
end

function Orders.runAway(record, shell, player, now, robbed)
    local key = ProjectALife.Speech.playerKey(player)
    if key == nil then return false end
    Orders.release(record.uid, "flee", true)
    local x, y = Orders.awayPoint(shell, player, Orders.settings.fleeTiles)
    Orders.writeOrdered(record.uid, { kind = "flee", playerKey = key, x = x, y = y, untilMs = now + Orders.settings.fleeMs })
    Orders.markWary(record, key, now)
    if robbed == true then Orders.noteRobbery(record, player) end
    Orders.count("fled")
    return true
end

function Orders.markRobbed(list, now)
    for _, member in ipairs(list) do
        local state = Orders.states[member.record.uid]
        if state ~= nil then
            state.robbed = true
            state.fleeAtMs = now + Orders.settings.fleeDelayMs
        end
    end
end

function Orders.fleeNow(record, shell, state, now)
    local player = state.player
    Orders.runAway(record, shell, player, now, true)
    local context = Orders.memberContext({ record = record, shell = shell }, player)
    if now - (Orders.lastRunLineAtMs or -1e12) >= Orders.settings.reliefGapMs then
        Orders.lastRunLineAtMs = now
        Orders.say(record, shell, player, "ORD_ROBBED_RUN", context)
        ProjectALife.Talk.later(Orders.settings.fleeMs, function()
            local at = nowMs()
            local again = registry() ~= nil and registry().read(record.uid) or nil
            if again ~= nil and again.lifecycle == "active" and ProjectALife.Speech.alive(shell)
                    and at - (Orders.lastReliefAtMs or -1e12) >= Orders.settings.reliefGapMs then
                Orders.lastReliefAtMs = at
                Orders.say(again, shell, player, "ORD_ROBBED_RELIEF", context)
            end
        end)
    end
    return true
end

function Orders.release(uid, reason, quiet)
    local state = Orders.states[uid]
    if state == nil then return false end
    Orders.states[uid] = nil
    Orders.count("released")
    local shell = ProjectALife.Talk.shellFor(uid)
    local animations = ProjectALife.Animations
    if shell ~= nil and animations ~= nil and type(animations.current) == "table" and animations.current[shell] == "surrender" then
        pcall(animations.clear, shell)
    end
    ProjectALife.Talk.releaseHold(uid, state.playerKey)
    Orders.writeOrdered(uid, nil)
    local talk = ProjectALife.Talk
    local session = talk.states[tostring(state.playerKey) .. ":" .. tostring(uid)]
    if quiet ~= true and type(session) == "table" and session.menuOpen == true and session.sessionId ~= nil
            and state.player ~= nil then
        talk.choiceReply(state.player, { uid = uid, playerKey = state.playerKey, sessionId = session.sessionId,
            ok = false, reason = "surrender_ended", surrendered = false })
    end
    return true
end

function Orders.zombieNear(record, shell, now)
    local fear = ProjectALife.ModuleFear
    if fear == nil or type(fear.scan) ~= "function" then return nil end
    local ok, scan = pcall(fear.scan, record, shell, now)
    if ok and type(scan) == "table" then return scan.nearest end
    return nil
end

function Orders.step(state, record, shell, now)
    local player = state.player
    local alive = false
    pcall(function() alive = player ~= nil and player:isDead() ~= true end)
    if not alive then return Orders.release(record.uid, "player_gone") end
    local talk = ProjectALife.Talk
    if record.activity == "combat" or talk.busy(record, now) then return Orders.release(record.uid, "combat") end
    if state.fleeAtMs ~= nil and now >= state.fleeAtMs then return Orders.fleeNow(record, shell, state, now) end
    if now >= state.untilMs then return Orders.release(record.uid, "expired") end
    local near = distance(player, shell) <= Orders.settings.reach
        and math.floor(select(3, position(player)) or 0) == math.floor(select(3, position(shell)) or 0)
    if near then state.lastSeenMs = now
    elseif now - state.lastSeenMs >= Orders.settings.lostMs then return Orders.release(record.uid, "lost") end
    local nearest = Orders.zombieNear(record, shell, now)
    if nearest ~= nil and nearest <= Orders.settings.zombieTiles then
        Orders.count("cancelledZombie")
        local context = ProjectALife.Speech.contextFor(record, player)
        Orders.release(record.uid, "zombie")
        Orders.say(record, shell, player, "ORD_ZOMBIE_CANCEL", context)
        return true
    end
    if now - state.holdAtMs >= Orders.settings.holdEveryMs then
        state.holdAtMs = now
        talk.hold(record, shell, player, now, 4000)
        Orders.pose(shell)
    end
    return true
end

function Orders.any()
    for _ in pairs(Orders.states) do return true end
    return false
end

function Orders.tick(now)
    if Orders.settings.enabled ~= true or not Orders.any() then return 0 end
    now = now or nowMs()
    if now - Orders.lastTickAtMs < Orders.settings.tickMs then return 0 end
    Orders.lastTickAtMs = now
    local uids = {}
    for uid in pairs(Orders.states) do uids[#uids + 1] = uid end
    local reg, talk = registry(), ProjectALife.Talk
    for _, uid in ipairs(uids) do
        local state = Orders.states[uid]
        local record = reg ~= nil and reg.read(uid) or nil
        local shell = record ~= nil and talk.shellFor(uid) or nil
        if state ~= nil then
            if record == nil or record.lifecycle ~= "active" or shell == nil or not ProjectALife.Speech.alive(shell) then
                Orders.states[uid] = nil
            else
                pcall(Orders.step, state, record, shell, now)
            end
        end
    end
    return #uids
end

function Orders.rebuildDeath(shell)
    local inventoryOk, items = pcall(function() return shell:getInventory():getItems() end)
    if not inventoryOk or items == nil then return false end
    if not pcall(function() ProjectALife.DeathInventory.clear(shell) end) then return false end
    for index = 0, items:size() - 1 do
        pcall(function()
            local item = items:get(index)
            local data = item:getModData()
            local keep = item:IsWeapon() == true and tostring(item:getFullType()) ~= "Base.BareHands"
            if type(data) == "table" and (data.ProjectALifeScavenged == true or data.ProjectALifeIdentityCard == true
                    or data.ProjectALifePocketLoot == true) then keep = true end
            if keep then ProjectALife.DeathInventory.add(shell, item) end
        end)
    end
    return true
end

function Orders.clearHands(shell, item)
    pcall(function()
        if shell:getPrimaryHandItem() == item then shell:setPrimaryHandItem(nil) end
        if shell:getSecondaryHandItem() == item then shell:setSecondaryHandItem(nil) end
    end)
end

function Orders.relocate(source, destination, item)
    if source == nil or destination == nil or item == nil then return false end
    local ok = pcall(function() source:Remove(item) end)
    if not ok then return false end
    local added = nil
    local addOk = pcall(function() added = destination:AddItem(item) end)
    if not addOk or added == nil then
        pcall(function() source:AddItem(item) end)
        return false
    end
    if type(isServer) == "function" and isServer() then
        if type(sendRemoveItemFromContainer) == "function" then pcall(sendRemoveItemFromContainer, source, item) end
        if type(sendAddItemToContainer) == "function" then pcall(sendAddItemToContainer, destination, item) end
    end
    return true
end

function Orders.valueOf(facts)
    if facts.weapon == true then
        if facts.ranged == true then return 100 + math.max(0, math.min(10, tonumber(facts.condition) or 0)) end
        return 85
    end
    facts.worn = false
    local robbery = ProjectALife.ModuleRobbery
    return robbery.valueOf(facts)
end

function Orders.carried(shell, mode)
    local robbery = ProjectALife.ModuleRobbery
    local list = {}
    local ok, items = pcall(function() return shell:getInventory():getItems() end)
    if not ok or items == nil or robbery == nil then return list end
    for index = 0, math.min(items:size(), 256) - 1 do
        pcall(function()
            local item = items:get(index)
            local facts = robbery.factsFor(item, shell)
            local fullType = tostring(facts.fullType or "")
            local bag = instanceof(item, "InventoryContainer")
            local weapon = facts.weapon == true and fullType ~= "Base.BareHands"
            if facts.clothing or facts.keyRing or bag or string.find(fullType, "ProjectALife", 1, true) ~= nil
                    or fullType == "Base.BareHands" then return end
            if mode == "weapons" and not weapon then return end
            if mode == "items" and weapon then return end
            local value = Orders.valueOf(facts)
            if value > 0 then list[#list + 1] = { item = item, value = value, label = tostring(item:getDisplayName()) } end
        end)
    end
    table.sort(list, function(a, b) return a.value > b.value end)
    return list
end

function Orders.frisk(record, shell, player, mode, limit)
    local source, destination = nil, nil
    pcall(function() source, destination = shell:getInventory(), player:getInventory() end)
    local taken = {}
    if source == nil or destination == nil then return taken end
    for _, entry in ipairs(Orders.carried(shell, mode)) do
        if #taken >= limit then break end
        if Orders.relocate(source, destination, entry.item) then
            Orders.clearHands(shell, entry.item)
            taken[#taken + 1] = entry.label
        end
    end
    if #taken > 0 then
        Orders.count("frisked")
        Orders.metrics.itemsTaken = Orders.metrics.itemsTaken + #taken
        Orders.rebuildDeath(shell)
        local animations = ProjectALife.Animations
        pcall(function() if animations ~= nil then animations.refreshWeapon(shell, false) end end)
        pcall(function() shell:resetModelNextFrame() end)
    end
    return taken
end

function Orders.disarm(shell)
    local source = nil
    pcall(function() source = shell:getInventory() end)
    local square = nil
    pcall(function() square = shell:getCurrentSquare() end)
    local dropped = 0
    if source == nil then return 0 end
    local held = nil
    pcall(function() held = { shell:getPrimaryHandItem(), shell:getSecondaryHandItem() } end)
    for index = 1, 2 do
        local item = held ~= nil and held[index] or nil
        local isGun = false
        pcall(function()
            isGun = item ~= nil and instanceof(item, "HandWeapon") and tostring(item:getFullType()) ~= "Base.BareHands"
        end)
        if isGun then
            pcall(function()
                source:Remove(item)
                if type(isServer) == "function" and isServer() and type(sendRemoveItemFromContainer) == "function" then
                    sendRemoveItemFromContainer(source, item)
                end
                Orders.clearHands(shell, item)
                if square ~= nil then square:AddWorldInventoryItem(item, 0.3 + index * 0.2, 0.5, 0) end
                dropped = dropped + 1
            end)
        end
    end
    if dropped > 0 then
        Orders.metrics.weaponsDropped = Orders.metrics.weaponsDropped + dropped
        Orders.rebuildDeath(shell)
        pcall(function() ProjectALife.Animations.refreshWeapon(shell, false) end)
        pcall(function() shell:resetModelNextFrame() end)
    end
    return dropped
end

function Orders.awayPoint(shell, player, tiles)
    local sx, sy = position(shell)
    local px, py = position(player)
    if sx == nil or px == nil then return nil end
    local dx, dy = sx - px, sy - py
    local length = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    return sx + dx / length * tiles, sy + dy / length * tiles
end

function Orders.sendAway(record, shell, player, now)
    local key = ProjectALife.Speech.playerKey(player)
    for _, member in ipairs(Orders.crew(record, shell, Orders.settings.crewRadius * 1.5)) do
        local x, y = Orders.awayPoint(member.shell, player, Orders.settings.leaveTiles)
        if x ~= nil then
            ProjectALife.Talk.releaseHold(member.record.uid, key)
            Orders.writeOrdered(member.record.uid, { kind = "leave", playerKey = key, x = x, y = y,
                untilMs = now + Orders.settings.leaveMs })
        end
    end
    Orders.count("sentAway")
end

function Orders.followMe(record, shell, player, now)
    local key = ProjectALife.Speech.playerKey(player)
    local untilMs = now + Orders.settings.followMs
    for _, member in ipairs(Orders.crew(record, shell)) do
        Orders.writeOrdered(member.record.uid, { kind = "follow", playerKey = key, untilMs = untilMs })
    end
    ProjectALife.Talk.tolerate(record, key, untilMs)
    Orders.count("followed")
end

function Orders.turnUids(uids, player)
    local careful = ProjectALife.ModuleCareful
    local reg = registry()
    local key = ProjectALife.Speech.playerKey(player)
    if careful == nil or reg == nil or type(careful.writeTurned) ~= "function" then return false end
    pcall(careful.writeTurned, reg, uids, key)
    Orders.count("fights")
    return true
end

function Orders.turnCrew(record, shell, player)
    local uids = {}
    for _, member in ipairs(Orders.crew(record, shell, 15)) do uids[#uids + 1] = member.record.uid end
    return Orders.turnUids(uids, player)
end

function Orders.crewCanFight(record, shell)
    for _, member in ipairs(Orders.crew(record, shell)) do
        if Orders.canFight(member) then return true end
    end
    return false
end

function Orders.refuse(kind, record, shell, player, context, now)
    local fight = false
    if Orders.hardKinds[kind] then
        fight = roll(100) < Orders.settings.fightPercent
    else
        local class = Orders.classOf(record)
        local armed, ranged, aiming = Orders.threatOf(player)
        if (class == "police" or class == "military" or class == "criminal") and ranged and aiming then
            fight = roll(100) < 25
        end
    end
    if fight and not Orders.crewCanFight(record, shell) then
        local text = Orders.say(record, shell, player, "ORD_RESIST_FLEE", context)
        for _, member in ipairs(Orders.crew(record, shell)) do
            Orders.runAway(member.record, member.shell, player, now)
        end
        Orders.count("groupFlee")
        return text or "[Backs away]", "refused"
    end
    local text = Orders.say(record, shell, player, fight and "ORD_REFUSE" or "ORD_REFUSE_SOFT", context)
    if fight then Orders.turnCrew(record, shell, player) end
    return text or "[Refuses]", fight and "hostile" or "refused"
end

function Orders.listOf(taken)
    local counts, order = {}, {}
    for _, label in ipairs(taken) do
        if counts[label] == nil then counts[label] = 0; order[#order + 1] = label end
        counts[label] = counts[label] + 1
    end
    local parts = {}
    for _, label in ipairs(order) do
        parts[#parts + 1] = counts[label] > 1 and (label .. " x" .. counts[label]) or label
    end
    return table.concat(parts, ", ")
end

function Orders.robCrew(record, shell, player, now, members)
    local taken = {}
    local left = Orders.settings.robItems
    for _, member in ipairs(members or Orders.crew(record, shell)) do
        if left <= 0 then break end
        local got = Orders.frisk(member.record, member.shell, player, "all", left)
        for _, label in ipairs(got) do taken[#taken + 1] = label end
        left = left - #got
    end
    return taken
end

function Orders.comply(kind, record, shell, player, context, now)
    local event = "ORD_HANDS_UP_OK"
    if kind == "drop" then event = "ORD_DROP_OK"
    elseif kind == "out" or kind == "leave" then event = "ORD_LEAVE_OK"
    elseif kind == "follow" then event = "ORD_FOLLOW_OK"
    elseif kind == "rob" then event = "ORD_ROB_OK" end
    local text = Orders.say(record, shell, player, event, context)
    if kind == "hands_up" then
        Orders.groupSurrender(kind, record, shell, player, context, now)
    elseif kind == "drop" or kind == "surrender" or kind == "rob" then
        local members = Orders.groupSurrender(kind, record, shell, player, context, now)
        for _, member in ipairs(members) do Orders.disarm(member.shell) end
        if kind == "rob" then
            local taken = Orders.robCrew(record, shell, player, now, members)
            if #taken > 0 then
                Orders.markRobbed(members, now)
                text = (text or "") .. " [Received: " .. Orders.listOf(taken) .. "]"
            else
                text = Orders.say(record, shell, player, "ORD_FRISK_EMPTY", context) or "[Nothing left to take]"
            end
        end
    elseif kind == "out" or kind == "leave" then
        Orders.sendAway(record, shell, player, now)
    elseif kind == "follow" then
        Orders.followMe(record, shell, player, now)
    end
    return text or "[Complies]", "ordered"
end

function Orders.handleSurrendered(kind, record, shell, player, context, now)
    local state = Orders.states[record.uid]
    local key = ProjectALife.Speech.playerKey(player)
    if state == nil or state.playerKey ~= key then return nil end
    if kind == "at_ease" then
        local text = Orders.say(record, shell, player, "ORD_AT_EASE", context)
        for _, member in ipairs(Orders.crew(record, shell)) do
            local held = Orders.states[member.record.uid]
            if held ~= nil and held.robbed == true then
                Orders.fleeNow(member.record, member.shell, held, now)
            else
                Orders.release(member.record.uid, "at_ease", true)
            end
        end
        return text or "[Lowers hands]", "ordered"
    end
    if distance(player, shell) > Orders.settings.frisk then
        return Orders.say(record, shell, player, "ORD_FRISK_FAR", context) or "[Wants you closer]", "ordered"
    end
    local mode = kind == "frisk_weapons" and "weapons" or "items"
    local limit = kind == "frisk_weapons" and Orders.settings.friskWeapons or Orders.settings.friskItems
    local taken = Orders.frisk(record, shell, player, mode, limit)
    if #taken == 0 then
        return Orders.say(record, shell, player, "ORD_FRISK_EMPTY", context) or "[Nothing left to take]", "ordered"
    end
    local event = kind == "frisk_weapons" and "ORD_FRISK_WEAPONS" or "ORD_FRISK_ITEMS"
    Orders.markRobbed(Orders.crew(record, shell), now)
    if ProjectALife.NpcOpinion ~= nil and type(ProjectALife.NpcOpinion.note) == "function" then
        pcall(ProjectALife.NpcOpinion.note, "robbery", record, player)
    end
    local text = Orders.say(record, shell, player, event, context) or ""
    return text .. " [Received: " .. Orders.listOf(taken) .. "]", "ordered"
end

function Orders.handle(kind, record, shell, player, context, now)
    if Orders.settings.enabled ~= true or not ProjectALife.Speech.authoritative() then return nil end
    if kind == "frisk_weapons" or kind == "frisk_items" or kind == "at_ease" then
        return Orders.handleSurrendered(kind, record, shell, player, context, now)
    end
    local key = ProjectALife.Speech.playerKey(player)
    if key == nil then return nil end
    local state = Orders.states[record.uid]
    if state ~= nil and state.playerKey == key and Orders.hardKinds[kind] then
        if kind == "rob" then return Orders.handleSurrendered("frisk_items", record, shell, player, context, now) end
        return Orders.say(record, shell, player, "ORD_HANDS_UP_OK", context) or "[Hands stay up]", "ordered"
    end
    Orders.count("asked")
    local chance = Orders.chanceFor(kind, record, shell, player, context)
    Orders.lastRoll = { kind = kind, chance = chance, uid = record.uid }
    if roll(100) < chance then
        Orders.count("won")
        return Orders.comply(kind, record, shell, player, context, now)
    end
    Orders.count("lost")
    if ProjectALife.NpcOpinion ~= nil and type(ProjectALife.NpcOpinion.note) == "function" then
        pcall(ProjectALife.NpcOpinion.note, "threat_failed", record, player)
    end
    return Orders.refuse(kind, record, shell, player, context, now)
end

function Orders.greet(record, shell, player, context, now)
    if Orders.option("greet", true) == false or type(context) ~= "table" then return nil end
    if context.stance ~= "friendly" and context.stance ~= "neutral" then return nil end
    if roll(100) >= Orders.settings.greetPercent then return nil end
    local fear = ProjectALife.ModuleFear
    local state = fear ~= nil and type(fear.actors) == "table" and fear.actors[record.uid] or nil
    if type(state) == "table" and state.state == "afraid" then return nil end
    ProjectALife.Speech.face(shell, player)
    local text = Orders.say(record, shell, player, "TALK_GREET_OPEN", context)
    if text ~= nil then Orders.count("greeted") end
    return text
end

function Orders.handleTalk(event, record, shell, player, context, now, trust)
    if Orders.settings.enabled ~= true then return nil end
    local text = Orders.say(record, shell, player, event, context)
    if text == nil then return nil end
    if trust == true and (context.stance == "friendly" or context.stance == "neutral") then
        local key = ProjectALife.Speech.playerKey(player)
        ProjectALife.Talk.tolerate(record, key, now + 240000)
    end
    return text, "answered"
end

function Orders.decorate(result, uid, player)
    if type(result) ~= "table" then return result end
    local state = Orders.states[uid]
    result.surrendered = state ~= nil and state.playerKey == ProjectALife.Speech.playerKey(player)
    return result
end

function Orders.playerByKey(key)
    local presence = ProjectALife.ModuleTalkPresence
    if presence == nil or type(presence.players) ~= "function" then return nil end
    for _, player in ipairs(presence.players()) do
        if ProjectALife.Speech.playerKey(player) == key then return player end
    end
    return nil
end

function Orders.memberStep(actor, shell, context, now)
    if Orders.settings.enabled ~= true or type(actor) ~= "table" then return nil end
    local memory = type(actor.memory) == "table" and actor.memory or nil
    local held = memory ~= nil and memory.orderedTo or nil
    if type(held) ~= "table" or now >= (tonumber(held.untilMs) or 0) then return nil end
    local start = type(context) == "table" and context.startMovement or nil
    local sx, sy, sz = position(shell)
    if sx == nil then return nil end
    if held.kind == "leave" then
        if tonumber(held.x) ~= nil and type(start) == "function" then
            return start(actor, shell, { x = held.x, y = held.y, z = sz }, "ordered_leave",
                { pace = "walk", timeoutMs = 15000, tolerance = 3 })
        end
        return nil
    end
    local player = Orders.playerByKey(held.playerKey)
    if player == nil then return nil end
    if held.kind == "flee" then
        if type(context.startRetreat) == "function" then
            local retreat = context.startRetreat(actor, shell, player, "player", now, "gun_fear")
            if retreat ~= nil then return retreat end
        end
        if tonumber(held.x) ~= nil and type(start) == "function" then
            return start(actor, shell, { x = held.x, y = held.y, z = sz }, "ordered_flee",
                { pace = "run", timeoutMs = 15000, tolerance = 3 })
        end
        return nil
    end
    if held.kind == "follow" then
        local px, py, pz = position(player)
        local gap = distance(player, shell)
        if gap > 4.5 and type(start) == "function" and px ~= nil then
            local state = start(actor, shell, { x = px, y = py, z = pz }, "ordered_follow",
                { pace = gap > 14 and "run" or "walk", timeoutMs = 6000, tolerance = 3 })
            if state ~= nil then return state end
        end
        return { kind = "idle", intent = "ordered_follow_wait", cooldownUntilMs = now + 500 }
    end
    if held.kind == "surrender" then
        ProjectALife.Speech.face(shell, player)
        Orders.pose(shell)
        if type(context) == "table" and type(context.setActivity) == "function" then
            context.setActivity(actor, "warning", "ordered_surrender")
        end
        return { kind = "idle", intent = "ordered_surrender", cooldownUntilMs = now + 400 }
    end
    return nil
end

function Orders.better(shell, item)
    local weapons = ProjectALife.Weapons
    local current = nil
    pcall(function() current = weapons.current(shell) end)
    if current == nil or current == item then return true end
    local ranged, currentRanged, power, currentPower = false, false, 0, 0
    pcall(function()
        ranged, currentRanged = item:isRanged() == true, current:isRanged() == true
        power, currentPower = tonumber(item:getMaxDamage()) or 0, tonumber(current:getMaxDamage()) or 0
    end)
    if ranged ~= currentRanged then return ranged end
    return power > currentPower
end

function Orders.equipWeapon(shell, item)
    local weapons, animations, talk = ProjectALife.Weapons, ProjectALife.Animations, ProjectALife.Talk
    if weapons == nil or not Orders.better(shell, item) then return false end
    local slot = nil
    pcall(function()
        slot = weapons.slot(item)
        if slot == nil then
            slot = item:isRanged() == true and "primary" or "melee"
            item:getModData().ProjectALifeWeaponSlot = slot
        end
    end)
    if not weapons.select(shell, item, slot) then return false end
    Orders.count("equipped")
    local reach, reachMs, take, takeMs = nil, 0, nil, 0
    pcall(function() reach, reachMs, take, takeMs = animations.drawSequenceFor(shell, item) end)
    if reach ~= nil and animations.apply(shell, reach) == true then
        talk.later(reachMs, function() if take ~= nil then animations.apply(shell, take) end end)
        talk.later(reachMs + takeMs + 150, function() animations.clear(shell) end)
    end
    return true
end

function Orders.wearArmor(shell, item)
    local animations, talk = ProjectALife.Animations, ProjectALife.Talk
    local worn = false
    pcall(function()
        local location = item:getBodyLocation()
        if location == nil or location == "" then return end
        local list = shell:getWornItems()
        if list == nil or list:getItem(location) ~= nil then return end
        list:setItem(location, item)
        shell:setWornItems(list)
        shell:resetModelNextFrame()
        worn = true
    end)
    if not worn then return false end
    Orders.count("equipped")
    if animations ~= nil and animations.apply(shell, "search_mid") == true then
        talk.later(1600, function() animations.clear(shell) end)
    end
    return true
end

function Orders.adopt(keeperUid, snapshots)
    local reg, talk, state = registry(), ProjectALife.Talk, ProjectALife.ShellState
    if type(snapshots) ~= "table" or reg == nil or state == nil or type(isClient) == "function" and isClient() then return 0 end
    local record, shell = reg.read(keeperUid), talk.shellFor(keeperUid)
    if record == nil or shell == nil then return 0 end
    local inventory = nil
    pcall(function() inventory = shell:getInventory() end)
    if inventory == nil then return 0 end
    local adopted, keys = 0, {}
    for _, saved in ipairs(snapshots) do
        local item = state.createItem(saved)
        local isWeapon, isArmor = false, false
        pcall(function()
            isWeapon = item ~= nil and instanceof(item, "HandWeapon")
            isArmor = item ~= nil and instanceof(item, "Clothing") and ((tonumber(item:getBiteDefense()) or 0) > 0
                or (tonumber(item:getScratchDefense()) or 0) > 0)
        end)
        if item ~= nil and (isWeapon or isArmor) then
            pcall(function() item:getModData().ProjectALifeStolen = true end)
            local added = nil
            pcall(function() added = inventory:AddItem(item) end)
            local done = false
            if added ~= nil then
                if isWeapon then done = Orders.equipWeapon(shell, item) else done = Orders.wearArmor(shell, item) end
            end
            if done then
                adopted = adopted + 1
                keys[saved.robberyItemKey or ""] = true
            end
            if added ~= nil and isWeapon then Orders.rebuildDeath(shell) end
        end
    end
    if adopted > 0 then
        Orders.metrics.adopted = Orders.metrics.adopted + adopted
        talk.writeMemory(keeperUid, function(memory)
            if type(memory.stolenLoot) ~= "table" then return end
            local kept = {}
            for _, entry in ipairs(memory.stolenLoot) do
                if not (type(entry) == "table" and keys[entry.robberyItemKey or ""] == true) then kept[#kept + 1] = entry end
            end
            memory.stolenLoot = kept
        end)
    end
    return adopted
end

local function register()
    local talk, rows = ProjectALife.Talk, ProjectALife.TalkOrderRows
    for _, row in ipairs(rows.defs) do
        if row.order ~= nil then
            local kind = row.order
            talk.choiceHandlers[row.id] = function(record, shell, player, context, now)
                return Orders.handle(kind, record, shell, player, context, now)
            end
        elseif row.proBark ~= nil then
            local event, trust = row.proBark, row.jobs ~= nil
            talk.choiceHandlers[row.id] = function(record, shell, player, context, now)
                return Orders.handleTalk(event, record, shell, player, context, now, trust)
            end
        end
    end
    local typed = { HANDS_UP = "hands_up", STOP_FREEZE = "hands_up", DROP_WEAPON = "drop", DEMAND_ITEMS = "rob" }
    for intent, kind in pairs(typed) do
        talk.choiceHandlers[intent] = function(record, shell, player, context, now)
            return Orders.handle(kind, record, shell, player, context, now)
        end
    end
end
register()

return Orders
