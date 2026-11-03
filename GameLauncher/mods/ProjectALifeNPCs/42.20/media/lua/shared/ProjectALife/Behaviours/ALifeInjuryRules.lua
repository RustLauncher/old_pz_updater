require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local Rules = {
    tilesPerMile = 150,
    states = { down = "down", dragged = "dragged", healing = "healing", recovering = "recovering" },
    bledOutText = "Looks like they bled out...",
    refusedText = "I told you.. Ughh.. I told you..",
    questions = {
        { id = "who", label = "Who are you?" },
        { id = "group", label = "Where is your group?" },
        { id = "origin", label = "Where do you come from?" },
        { id = "culprit", label = "Who did this to you?" },
        { id = "more", label = "Anything else?" },
    },
    aidKits = {
        { item = "Base.AlcoholBandage", heal = 0.55 },
        { item = "Base.Bandage", heal = 0.45 },
        { item = "Base.Pills", heal = 0.38 },
        { item = "Base.Disinfectant", heal = 0.4 },
        { item = "Base.AlcoholWipes", heal = 0.36 },
    },
    transitions = {
        none = { enter = "down" },
        down = { dragStart = "dragged", aid = "recovering", timeout = "recovering", heal = "none", death = "none", off = "none" },
        dragged = { dragDone = "healing", abort = "down", aid = "recovering", heal = "none", death = "none", off = "none" },
        healing = { healed = "recovering", abort = "down", aid = "recovering", heal = "none", death = "none", off = "none" },
        recovering = { recovered = "none", enter = "down", heal = "none", death = "none", off = "none" },
    },
    lines = {
        INJURED_DOWN = { "Ughh.. my leg..", "Somebody.. help me..", "It hurts.. oh God it hurts..", "Don't leave me here.. please..",
            "Can't get up.. Ahh..", "Anyone.. anyone out there..", "So cold.. Ughh..", "Hold on.. hold on.. Ahh.." },
        INJURED_BEG = { "Please.. help me.. Ughh..", "Don't.. don't go.. please..", "Water.. just a little.. Ahh..",
            "I can't feel it.. please..", "Stay with me.. just a minute.." },
        INJURED_RESCUED = { "Thanks.. thanks.. Ughh..", "Easy.. easy.. my side..", "Okay.. okay.. I'm up.. Ahh.." },
        INJURED_UP = { "Thank you.. Ughh.. I'll go..", "I owe you.. Ahh.. I'm going..", "Okay.. okay.. leaving.. thank you.." },
        INJURED_DEATH = { "Tell them.. Ughh..", "Cold.. so cold..", "Mom.. Ahh.." },
        WOUNDED_HELP = { "Hold on, I got you!", "Easy.. easy.. I'm here, don't move", "Stay with me! Look at me!",
            "Quit squirming, let me see it", "I got ya.. hold still", "Damn it.. how bad is it?",
            "Hang on, hang on!", "Don't you die on me!" },
    },
    answers = {
        who_named = { "%s... Ughh... %s... Don't.. please..", "I'm %s.. %s.. Hurts so bad..", "%s.. with %s.. Ahh.. God.." },
        who_anon = { "Nobody.. Ughh.. just one of %s..", "Does it matter.. %s.. Ahh..", "Ughh.. %s.. that's all.. Please.." },
        outpost = { "Ughh... %s %s... Spare me.. Please..", "%s %s of here.. the outpost.. Ahh.. please..",
            "Ughh.. it's %s %s.. that's all I know.. Please.." },
        crew = { "There's %s of us.. Ughh.. they'll come for me..", "%s of us.. maybe more.. Ahh..", "Ughh.. %s.. we were %s.. please.." },
        alone = { "Just me.. Ughh.. just me..", "Nobody.. it's only me.. Ahh.. please.." },
        town = { "Came up from %s.. Ughh.. long walk..", "%s.. Ahh.. we left %s.. please.." },
        townless = { "Ughh.. I don't.. remember.. please..", "Far.. Ahh.. far from here.. help me.." },
        zombie = { "The dead.. they got me.. Ughh..", "Zombies.. too many.. Ahh.." },
        firearm = { "Somebody with a gun.. didn't see who.. Ughh..", "Shots.. out of nowhere.. Ahh.." },
        melee = { "Somebody swung at me.. Ughh.. didn't see..", "Hit me from behind.. Ahh.." },
        player = { "You.. Ughh.. it was you..", "You did this.. Ahh.. why.." },
        survivor = { "Other survivors.. Ughh.. %s..", "%s.. they didn't stop.. Ahh.." },
        fire = { "Fire.. it burned.. Ughh..", "The flames.. Ahh.. my skin.." },
        unknown = { "Don't know.. it was so fast.. Ughh..", "Everything.. went black.. Ahh.." },
        hunting = { "They're hunting you.. Ughh.. you know that..", "Your trail.. they've got your trail.. Ahh.." },
        morecrew = { "My people.. they'll come.. Ughh.. you should go..", "They'll look for me.. Ahh.. don't be here.." },
        moreplain = { "Water.. please.. leave me something.. Ahh..", "Just.. leave me.. Ughh.. leave me be.." },
    },
}
ProjectALife.InjuryRules = Rules

function Rules.option(name, default, minimum, maximum)
    return Gate.number(name, default, minimum, maximum)
end

function Rules.flag(name, default)
    return Gate.flag(name, default)
end

function Rules.settings()
    return {
        enabled = Gate.flag("Injury_Enabled", true),
        multiplayer = Gate.flag("Injury_MultiplayerEnabled", true),
        rescue = Gate.flag("Injury_Rescue", true),
        rescueDrag = Gate.flag("Injury_RescueDrag", true),
        rescueInView = Gate.flag("Injury_RescueInView", true),
        crawl = Gate.flag("Injury_Crawl", true),
        autoPercent = Gate.number("Injury_AutoPercent", 50, 0, 100),
        downHpPercent = Gate.number("Injury_DownHpPercent", 12, 2, 40),
        deathPercent = Gate.number("Injury_InterrogationDeathPercent", 25, 0, 100),
        repPenalty = Gate.number("Injury_RepPenalty", 3, 0, 20),
        repGain = Gate.number("Injury_RepGain", 4, 0, 20),
        recoverHours = Gate.number("Injury_RecoverHours", 8, 1, 72),
        downHours = Gate.number("Injury_DownHours", 4, 1, 48),
        playerRange = Gate.number("Injury_PlayerRangeTiles", 25, 10, 60),
        leaveTiles = Gate.number("Injury_LeaveTiles", 45, 30, 120),
        rescueTiles = Gate.number("Injury_RescueRange", 15, 5, 40),
        hostileTiles = 12,
        meleeTiles = 4,
        crawlThreatTiles = 14,
        crawlStep = 0.12,
        crawlMax = 20,
        crawlGroupTiles = 25,
        shuffleStep = 0.1,
        shuffleTiles = 1.2,
        shuffleMinMs = 9000,
        shuffleSpanMs = 9000,
        shuffleRadius = 4,
        helpLineGapMs = 6000,
        reviveFraction = 0.35,
        aidFraction = 0.45,
        approachMs = 45000,
        dragMs = 40000,
        healMs = 20000,
        healWorkMs = 6000,
        cooldownMs = 60000,
        dragMin = 6,
        dragMax = 10,
        dragStep = 0.3,
        leaseMs = 3000,
        beatMs = 250,
        barkMinMs = 7000,
        barkSpanMs = 9000,
        reachTiles = 3.5,
        leaveMs = 1200000,
    }
end

function Rules.next(state, event)
    local row = Rules.transitions[state == nil and "none" or state]
    if row == nil then return nil end
    return row[event]
end

function Rules.holds(state)
    return state == "down" or state == "dragged" or state == "healing"
end

function Rules.lying(state)
    return state == "down" or state == "dragged"
end

function Rules.fraction(health, maximum)
    local top = tonumber(maximum) or 0
    if top <= 0 then return 0 end
    local value = (tonumber(health) or 0) / top
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

function Rules.recovered(startFraction, elapsedHours, totalHours)
    local first = math.max(0, math.min(1, tonumber(startFraction) or 0))
    local total = math.max(0.01, tonumber(totalHours) or 1)
    local spent = math.max(0, tonumber(elapsedHours) or 0)
    if spent >= total then return 1, true end
    return first + (1 - first) * spent / total, false
end

function Rules.dies(percent, roll)
    local chance = tonumber(percent) or 0
    if chance <= 0 then return false end
    if chance >= 100 then return true end
    return (tonumber(roll) or 0) < chance
end

function Rules.autoEnters(percent, roll)
    return Rules.dies(percent, roll)
end

function Rules.direction(fromX, fromY, toX, toY)
    local east = (tonumber(toX) or 0) - (tonumber(fromX) or 0)
    local north = -((tonumber(toY) or 0) - (tonumber(fromY) or 0))
    if east == 0 and north == 0 then return "here" end
    local ax, ay = math.abs(east), math.abs(north)
    local slope = 0.4142
    if ax <= slope * ay then
        if north > 0 then return "north" end
        return "south"
    end
    if ay <= slope * ax then
        if east > 0 then return "east" end
        return "west"
    end
    if north > 0 then
        if east > 0 then return "northeast" end
        return "northwest"
    end
    if east > 0 then return "southeast" end
    return "southwest"
end

function Rules.distance(fromX, fromY, toX, toY)
    local dx, dy = (tonumber(toX) or 0) - (tonumber(fromX) or 0), (tonumber(toY) or 0) - (tonumber(fromY) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

function Rules.rangeText(tiles)
    local distance = math.max(0, tonumber(tiles) or 0)
    local half = Rules.tilesPerMile / 2
    if distance < half then return "less than a mile" end
    local miles = math.floor(distance / Rules.tilesPerMile + 0.5)
    if miles <= 1 then return "a mile" end
    return tostring(miles) .. " miles"
end

function Rules.pick(list, roll)
    if type(list) ~= "table" or #list == 0 then return nil end
    local index = (math.floor(tonumber(roll) or 0) % #list) + 1
    return list[index]
end

function Rules.outpostLine(tiles, direction, roll)
    local template = Rules.pick(Rules.answers.outpost, roll)
    return string.format(template, Rules.rangeText(tiles), tostring(direction or "here"))
end

function Rules.attackerClass(kind, byPlayer, byActor)
    if byPlayer == true then return "player" end
    if byActor == true then return "survivor" end
    if kind == "zombie" then return "zombie" end
    if kind == "firearm" then return "firearm" end
    if kind == "blade" or kind == "blunt" or kind == "fists" or kind == "melee" then return "melee" end
    if kind == "fire" then return "fire" end
    return "unknown"
end

function Rules.answer(question, facts, roll)
    facts = type(facts) == "table" and facts or {}
    local answers = Rules.answers
    local faction = tostring(facts.faction or "a survivor")
    if question == "who" then
        if facts.name ~= nil and tostring(facts.name) ~= "" then
            return string.format(Rules.pick(answers.who_named, roll), tostring(facts.name), faction)
        end
        return string.format(Rules.pick(answers.who_anon, roll), faction)
    end
    if question == "group" then
        if type(facts.outpost) == "table" and facts.outpost.distance ~= nil then
            return Rules.outpostLine(facts.outpost.distance, facts.outpost.direction, roll)
        end
        local crew = math.floor(tonumber(facts.crew) or 1)
        if crew <= 1 then return Rules.pick(answers.alone, roll) end
        return string.format(Rules.pick(answers.crew, roll), tostring(crew), tostring(crew))
    end
    if question == "origin" then
        if type(facts.outpost) == "table" and facts.outpost.distance ~= nil then
            return Rules.outpostLine(facts.outpost.distance, facts.outpost.direction, roll + 1)
        end
        if facts.town ~= nil and tostring(facts.town) ~= "" then
            return string.format(Rules.pick(answers.town, roll), tostring(facts.town), tostring(facts.town))
        end
        return Rules.pick(answers.townless, roll)
    end
    if question == "culprit" then
        local class = tostring(facts.attacker or "unknown")
        local pool = answers[class] or answers.unknown
        local text = Rules.pick(pool, roll)
        if class == "survivor" then return string.format(text, faction) end
        return text
    end
    if question == "more" then
        if facts.hunting == true then return Rules.pick(answers.hunting, roll) end
        if (tonumber(facts.crew) or 1) > 1 then return Rules.pick(answers.morecrew, roll) end
        return Rules.pick(answers.moreplain, roll)
    end
    return Rules.pick(answers.moreplain, roll)
end

function Rules.line(event, roll)
    return Rules.pick(Rules.lines[event], roll)
end

function Rules.questionKnown(id)
    for _, row in ipairs(Rules.questions) do
        if row.id == id then return true end
    end
    return false
end

function Rules.kitOf(inventory)
    if inventory == nil or type(inventory.getFirstTypeRecurse) ~= "function" then return nil end
    for _, kit in ipairs(Rules.aidKits) do
        local item = inventory:getFirstTypeRecurse(kit.item)
        if item ~= nil then return item, kit end
    end
    return nil
end

function Rules.nearestPlayer(playerRows, x, y)
    local best, bestSquared
    for _, row in ipairs(type(playerRows) == "table" and playerRows or {}) do
        local dx, dy = (tonumber(row.x) or 0) - x, (tonumber(row.y) or 0) - y
        local squared = dx * dx + dy * dy
        if bestSquared == nil or squared < bestSquared then best, bestSquared = row, squared end
    end
    if best == nil then return nil, nil end
    return best, math.sqrt(bestSquared)
end

function Rules.playerInRange(playerRows, x, y, range)
    local _, distance = Rules.nearestPlayer(playerRows, x, y)
    return distance ~= nil and distance <= range
end

function Rules.pickRescuer(body, candidates, settings)
    local best, bestSquared, why
    for _, row in ipairs(type(candidates) == "table" and candidates or {}) do
        local reason
        if row.alive == false then reason = "dead"
        elseif row.injured == true then reason = "injured"
        elseif row.busy == true then reason = "busy"
        elseif row.cooldown == true then reason = "cooldown"
        elseif row.team ~= true then reason = "not_team"
        elseif math.abs((tonumber(row.z) or 0) - (tonumber(body.z) or 0)) > 0.5 then reason = "floor" end
        if reason == nil then
            local dx, dy = (tonumber(row.x) or 0) - body.x, (tonumber(row.y) or 0) - body.y
            local squared = dx * dx + dy * dy
            if squared > settings.rescueTiles * settings.rescueTiles then reason = "far"
            elseif bestSquared == nil or squared < bestSquared then best, bestSquared = row, squared end
        end
        if reason ~= nil and best == nil then why = why or reason end
    end
    if best == nil then return nil, why or "no_candidates" end
    return best, nil
end

function Rules.unit(dx, dy)
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.0001 then return 1, 0 end
    return dx / length, dy / length
end

function Rules.dragDirection(bodyX, bodyY, threats)
    local sx, sy = 0, 0
    for _, row in ipairs(type(threats) == "table" and threats or {}) do
        local dx, dy = bodyX - (tonumber(row.x) or bodyX), bodyY - (tonumber(row.y) or bodyY)
        local length = math.sqrt(dx * dx + dy * dy)
        local weight = 1 / math.max(1, length)
        if length > 0.0001 then sx, sy = sx + dx / length * weight, sy + dy / length * weight end
    end
    if sx == 0 and sy == 0 then return 1, 0 end
    return Rules.unit(sx, sy)
end

Rules.dragAwayTolerance = 0.2

function Rules.awayFrom(ux, uy, bodyX, bodyY, otherX, otherY, tolerance)
    local tx, ty = Rules.unit((tonumber(otherX) or 0) - bodyX, (tonumber(otherY) or 0) - bodyY)
    return ux * tx + uy * ty <= (tonumber(tolerance) or 0)
end

function Rules.rotate(ux, uy, degrees)
    local radians = degrees * math.pi / 180
    local cosine, sine = math.cos(radians), math.sin(radians)
    return ux * cosine - uy * sine, ux * sine + uy * cosine
end

function Rules.dragTarget(carrierX, carrierY, ux, uy, tiles)
    return carrierX + ux * tiles, carrierY + uy * tiles
end

function Rules.bodyBehind(carrierX, carrierY, ux, uy, gap)
    return carrierX - ux * gap, carrierY - uy * gap
end

function Rules.leaveAnchor(originX, originY, awayX, awayY, tiles, attempt)
    local ux, uy = Rules.unit(originX - awayX, originY - awayY)
    local turn = ((attempt or 0) % 7) * 25 * (((attempt or 0) % 2 == 0) and 1 or -1)
    ux, uy = Rules.rotate(ux, uy, turn)
    local reach = tiles - math.floor((attempt or 0) / 7) * 4
    return originX + ux * reach, originY + uy * reach
end

return Rules
