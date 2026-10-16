require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorRule"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Visitors/ALifeVisitorLedger"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local Rule = ProjectALife.VisitorRule
local People = ProjectALife.VisitorPeople
local Instance = ProjectALife.VisitorInstance
local Ledger = ProjectALife.VisitorLedger

local Rules = {
    adapters = {},
    nearTiles = 8,
    ttlMs = 2000,
    scans = {},
    scanCount = 0,
    atoms = {},
    metrics = { ctx = 0, scans = 0, missing = 0 },
}
ProjectALife.VisitorTalkRules = Rules

Rules.optionFields = { ChangeClothes = "changeClothes", Flirt = "flirt", Books = "books", Life = "life",
    Parties = "parties", ProactiveEvents = "proactive" }

function Rules.readPosition(object)
    return object:getX(), object:getY(), object:getZ()
end

function Rules.pos(object)
    if object == nil or type(object.getX) ~= "function" or type(object.getY) ~= "function" then return nil end
    local ok, x, y, z = pcall(Rules.readPosition, object)
    if not ok or x == nil then return nil end
    return x, y, z or 0
end

function Rules.nowMs()
    if type(Rules.adapters.nowMs) == "function" then return Rules.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
    return 0
end

function Rules.worldHours()
    if type(Rules.adapters.hours) == "function" then return tonumber(Rules.adapters.hours()) or 0 end
    if type(getGameTime) ~= "function" then return 0 end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return 0 end
    return tonumber(clock:getWorldAgeHours()) or 0
end

function Rules.playerKey(player)
    local speech = ProjectALife.Speech
    if player == nil or speech == nil or type(speech.playerKey) ~= "function" then return nil end
    return speech.playerKey(player)
end

function Rules.env(record, player, nowMs, extra)
    local env = { record = record, player = player, nowMs = tonumber(nowMs) or Rules.nowMs(), extra = extra or {}, memo = {} }
    env.person = Instance.of(record)
    env.uid = type(record) == "table" and record.uid or nil
    env.key = Rules.playerKey(player)
    env.hours = Rules.worldHours()
    return env
end

function Rules.memo(env, name, build)
    local value = env.memo[name]
    if value == nil then
        value = build(env)
        if value == nil then value = false end
        env.memo[name] = value
    end
    if value == false then return nil end
    return value
end

function Rules.clockOf(env)
    return Rules.memo(env, "clock", function()
        local speech = ProjectALife.Speech
        if speech ~= nil and type(speech.clock) == "function" then return speech.clock() end
        return { hour = 12, daysSurvived = 0 }
    end)
end

function Rules.card(env)
    if env.person == nil then return nil end
    return Rules.memo(env, "card", function() return (People.card(env.person.id)) end)
end

function Rules.indexEntry(env)
    if env.person == nil then return nil end
    return Rules.memo(env, "entry", function()
        local index = People.index()
        return index ~= nil and index.people[env.person.id] or nil
    end)
end

function Rules.row(env)
    if env.rowOverride ~= nil then return env.rowOverride end
    if env.person == nil or env.key == nil then return nil end
    return Instance.vt(env.person, env.key, false)
end

function Rules.shell(env)
    if env.shell ~= nil then return env.shell end
    local talk = ProjectALife.Talk
    if env.uid ~= nil and talk ~= nil and type(talk.shellFor) == "function" then
        env.shell = talk.shellFor(env.uid)
    end
    return env.shell
end

function Rules.trust(env)
    if env.extra.trust ~= nil then return env.extra.trust end
    local cached = env.memo.trust
    if cached ~= nil then return cached end
    local opinion = ProjectALife.NpcOpinion
    local value = 0
    if opinion ~= nil and type(opinion.valueOf) == "function" and env.player ~= nil then
        value = tonumber((opinion.valueOf(env.record, env.player))) or 0
    end
    env.memo.trust = value
    return value
end

function Rules.band(trust)
    if trust < 16 then return "lo" end
    if trust <= 40 then return "mid" end
    return "hi"
end

function Rules.options()
    if type(Rules.adapters.options) == "function" then return Rules.adapters.options() end
    local settings = ProjectALife.Settings
    if settings ~= nil and type(settings.visitors) == "function" then return settings.visitors() end
    return Schema.options()
end

function Rules.adult(env)
    local person = env.person
    if person == nil or person.ad ~= 1 then return false end
    local card = Rules.card(env)
    if card == nil or card.adult ~= true then return false end
    local entry = Rules.indexEntry(env)
    return entry ~= nil and entry.adult == true
end

function Rules.guestRect(env)
    local memory = type(env.record) == "table" and env.record.memory or nil
    local guest = type(memory) == "table" and memory.guest or nil
    if type(guest) == "table" and tonumber(guest.x1) ~= nil then return guest end
    local visit = ProjectALife.SafehouseVisit
    if env.uid ~= nil and visit ~= nil and type(visit.live) == "function" then
        local pending, house = visit.live(env.uid)
        if pending ~= nil and type(house) == "table" and tonumber(house.x1) ~= nil then return house, pending end
    end
    return nil
end

function Rules.inside(env)
    return Rules.memo(env, "inside", function()
        if type(env.extra.inside) == "boolean" then return env.extra.inside end
        local rect = Rules.guestRect(env)
        local x, y, z = Rules.pos(env.player)
        if rect == nil or x == nil then return false end
        local floor = tonumber(rect.z)
        if floor ~= nil and math.floor(z) ~= math.floor(floor) then return false end
        return x >= rect.x1 and x < rect.x2 and y >= rect.y1 and y < rect.y2
    end) == true
end

function Rules.atDoor(env)
    if Rules.inside(env) then return false end
    local visit = ProjectALife.SafehouseVisit
    if env.uid == nil or env.player == nil or visit == nil or type(visit.doorPeer) ~= "function" then return false end
    return visit.doorPeer(env.player, env.uid) ~= nil
end

function Rules.entered(env)
    local person = env.person
    if person == nil then return nil end
    if tonumber(person.ti) ~= nil then return tonumber(person.ti) end
    local memory = type(env.record) == "table" and env.record.memory or nil
    local guest = type(memory) == "table" and memory.guest or nil
    if type(guest) == "table" and tonumber(guest.renewedHours) ~= nil then return tonumber(guest.renewedHours) end
    return nil
end

function Rules.sameFloorNear(sx, sy, sz, ox, oy, oz)
    if math.floor(sz) ~= math.floor(oz) then return false end
    local limit = Rules.nearTiles
    return (sx - ox) * (sx - ox) + (sy - oy) * (sy - oy) <= limit * limit
end

function Rules.sight(a, b)
    local talk = ProjectALife.Talk
    if talk == nil or type(talk.lineOfSight) ~= "function" then return true end
    return talk.lineOfSight(a, b) == true
end

function Rules.scanActor(env, scan, wanted, other, sx, sy, sz, shell)
    local talk = ProjectALife.Talk
    local body = talk ~= nil and type(talk.shellFor) == "function" and talk.shellFor(other.uid) or nil
    local ox, oy, oz = Rules.pos(body)
    if ox == nil or not Rules.sameFloorNear(sx, sy, sz, ox, oy, oz) then return end
    local who = Instance.of(other)
    if who ~= nil and wanted[who.id] then
        scan.partners = scan.partners + 1
        scan.members[#scan.members + 1] = other
    end
    if who ~= nil then
        local index = People.index()
        local entry = index ~= nil and index.people[who.id] or nil
        if entry ~= nil and entry.teen then scan.minor = true end
    end
    if Rules.sight(shell, body) then scan.others = scan.others + 1 end
end

function Rules.scan(env)
    local cached = Rules.scans[env.uid]
    if cached ~= nil and env.nowMs >= cached.at and env.nowMs - cached.at < Rules.ttlMs then return cached end
    local person = env.person
    local scan = { at = env.nowMs, others = 0, partners = 0, members = {}, minor = false, known = 0, unknown = false }
    local wanted = {}
    for _, id in ipairs(person ~= nil and person.with or {}) do
        wanted[id] = true
        scan.known = scan.known + 1
    end
    local shell = Rules.shell(env)
    local sx, sy, sz = Rules.pos(shell)
    local registry = ProjectALife.ActorRegistry
    if sx == nil then scan.unknown = true end
    if sx ~= nil and registry ~= nil and type(registry.each) == "function" then
        local seen = 0
        registry.each(function(other)
            seen = seen + 1
            if other.uid ~= env.uid and other.lifecycle == "active" then
                Rules.scanActor(env, scan, wanted, other, sx, sy, sz, shell)
            end
            return seen > 4000
        end)
    end
    if Rules.scanCount > 64 then Rules.scans, Rules.scanCount = {}, 0 end
    if Rules.scans[env.uid] == nil then Rules.scanCount = Rules.scanCount + 1 end
    Rules.scans[env.uid] = scan
    Rules.metrics.scans = Rules.metrics.scans + 1
    return scan
end

function Rules.weather()
    local seasons = ProjectALife.Seasons
    if seasons == nil or type(seasons.weather) ~= "function" then return nil end
    return seasons.weather()
end

function Rules.roomName(object)
    if object == nil or type(object.getSquare) ~= "function" then return nil end
    local square = object:getSquare()
    if square == nil or type(square.getRoom) ~= "function" then return nil end
    local room = square:getRoom()
    if room == nil or type(room.getName) ~= "function" then return nil end
    local name = room:getName()
    if type(name) ~= "string" then return nil end
    return string.lower(name)
end

function Rules.safeRoom(object)
    local ok, name = pcall(Rules.roomName, object)
    if ok then return name end
    return nil
end

function Rules.holdsWeapon(player)
    if player == nil or type(instanceof) ~= "function" or type(player.getPrimaryHandItem) ~= "function" then return false end
    local ok, armed = pcall(function()
        for _, item in pairs({ player:getPrimaryHandItem(), player:getSecondaryHandItem() }) do
            if item ~= nil and instanceof(item, "HandWeapon") and item:getFullType() ~= "Base.BareHands" then return true end
        end
        return false
    end)
    return ok and armed == true
end

function Rules.flagOf(env, name)
    return Instance.flag(Rules.row(env), name)
end

function Rules.ledgerWho(env)
    if env.person == nil or env.key == nil then return nil end
    return Ledger.who(env.person.id, env.key)
end

function Rules.factIndex(env, factId)
    local card = Rules.card(env)
    if card == nil then return nil end
    for position = 1, #card.facts do
        if card.facts[position].id == factId then return position end
    end
    return nil
end

function Rules.knows(env, factId)
    local index = Rules.factIndex(env, factId)
    if index == nil then return false end
    if Instance.knows(Rules.row(env), index) then return true end
    local who = Rules.ledgerWho(env)
    if who ~= nil then
        for _, piece in ipairs(who.facts) do
            if tonumber(piece) == index then return true end
        end
    end
    return false
end

function Rules.hasCarry(card, kind)
    for _, item in ipairs(card.carry) do
        if string.find(string.lower(item), kind, 1, true) ~= nil then return true end
    end
    return false
end

function Rules.rawCard(personId)
    local index = People.index()
    local entry = index ~= nil and index.people[personId] or nil
    if entry == nil then return nil end
    local Text = ProjectALife.VisitorText
    local result = Text.get(entry.people .. ".alife")
    local record = result ~= nil and result.byId[personId] or nil
    if record == nil then return nil end
    return record.card or {}, record
end

function Rules.partnerNeed(env, name)
    local best = 0
    for _, other in ipairs(Rules.scan(env).members) do
        local who = Instance.of(other)
        if who ~= nil then best = math.max(best, Instance.need(who, name)) end
    end
    return best
end

function Rules.staysNear(env)
    local person, card = env.person, Rules.card(env)
    if person == nil or card == nil then return false end
    local options = Rules.options()
    local cap = math.min(card.arc.stayMax or 1, options.stayHours or 1)
    local entered = Rules.entered(env)
    if entered == nil then return false end
    return env.hours - entered >= cap - 2
end

function Rules.leaving(env)
    local visit = ProjectALife.SafehouseVisit
    if env.uid == nil or visit == nil or type(visit.live) ~= "function" then return false end
    local pending = visit.live(env.uid)
    return pending ~= nil and pending.state == "leaves"
end

function Rules.dirtyScan(env)
    local person = env.person
    return person ~= nil and Instance.need(person, "dirty") >= 5
end

local A = Rules.atoms

function A.trust(env) return Rules.trust(env) end

function A.imin(env)
    local entered = Rules.entered(env)
    if entered == nil then return 0 end
    return math.max(0, (env.hours - entered) * 60)
end

function A.gmin(env)
    if env.person == nil then return 0 end
    return math.max(0, (env.hours - (tonumber(env.person.t0) or env.hours)) * 60)
end

function A.rsec(env)
    local opened = env.extra.opened or (env.session ~= nil and env.session.opened) or env.nowMs
    return math.max(0, (env.nowMs - opened) / 1000)
end

function A.insideSec(env)
    if env.extra.insideSec ~= nil then return env.extra.insideSec end
    local since = env.session ~= nil and env.session.insideSince or nil
    if since == nil or not Rules.inside(env) then return 0 end
    return math.max(0, (env.nowMs - since) / 1000)
end

function A.nearPlayer(env)
    if env.extra.nearPlayer ~= nil then return env.extra.nearPlayer end
    local sx, sy = Rules.pos(Rules.shell(env))
    local px, py = Rules.pos(env.player)
    if sx == nil or px == nil then return 1000 end
    return math.sqrt((sx - px) * (sx - px) + (sy - py) * (sy - py))
end

function A.visits(env)
    if env.person == nil then return 0 end
    local entry = Ledger.entry(env.person.id)
    return entry ~= nil and tonumber(entry.n) or 0
end

function A.lastgap(env)
    if env.person == nil then return 0 end
    local entry = Ledger.entry(env.person.id)
    local last = entry ~= nil and tonumber(entry.l) or nil
    local arrived = tonumber(env.person.t0)
    if last == nil or arrived == nil or last >= arrived then return 0 end
    return math.floor((arrived - last) / 24)
end

function A.day(env) return tonumber(Rules.clockOf(env).daysSurvived) or 0 end

function A.hour(env, arg, node)
    return Rule.inHours(tonumber(Rules.clockOf(env).hour), node.lo, node.hi)
end

function A.night(env) return Rule.inHours(tonumber(Rules.clockOf(env).hour), 21, 5) end
function A.dawn(env) return Rule.inHours(tonumber(Rules.clockOf(env).hour), 5, 7) end
function A.morning(env) return Rule.inHours(tonumber(Rules.clockOf(env).hour), 6, 10) end

function A.rain(env)
    local weather = Rules.weather()
    return weather ~= nil and (tonumber(weather.rain) or 0) > 0.08
end

function A.coldout(env)
    local weather = Rules.weather()
    local seasons = ProjectALife.Seasons
    return weather ~= nil and (tonumber(weather.air) or 20) <= (seasons.coldBelowC or 3)
end

function A.inside(env) return Rules.inside(env) end
function A.door(env) return Rules.atDoor(env) end

function A.partner(env) return Rules.scan(env).partners > 0 end

function A.partnerGone(env)
    local scan = Rules.scan(env)
    return scan.known > 0 and scan.partners == 0
end

function A.alone(env)
    if not Rules.adult(env) then return false end
    local scan = Rules.scan(env)
    if scan.unknown or scan.partners > 0 or scan.others > 0 then return false end
    return true
end

function A.minorPresent(env)
    if type(env.extra.minorPresent) == "boolean" then return env.extra.minorPresent end
    local scan = Rules.scan(env)
    return scan.minor or scan.unknown
end

function A.power(env)
    if type(Rules.adapters.power) == "function" then return Rules.adapters.power(env) == true end
    local shell = Rules.shell(env)
    if shell == nil or type(shell.getSquare) ~= "function" then return false end
    local square = shell:getSquare()
    return square ~= nil and type(square.haveElectricity) == "function" and square:haveElectricity() == true
end

function A.armed(env) return Rules.holdsWeapon(env.player) end

function A.adult(env) return Rules.adult(env) end

function A.wet(env)
    if type(env.extra.wet) == "boolean" then return env.extra.wet end
    return A.rain(env) and not Rules.inside(env)
end

function A.bloody(env)
    if type(env.extra.bloody) == "boolean" then return env.extra.bloody end
    return Rules.dirtyScan(env)
end

function A.staynear(env) return Rules.staysNear(env) end
function A.leaving(env) return Rules.leaving(env) end

function A.clean(env)
    return env.person ~= nil and Instance.cleanState(env.person, env.hours) ~= "dirty"
end

function A.fresh(env)
    return env.person ~= nil and Instance.cleanState(env.person, env.hours) == "fresh"
end

function A.dress(env, arg)
    return env.person ~= nil and Instance.dressState(env.person) == arg
end

function A.room(env, arg) return Rules.safeRoom(Rules.shell(env)) == arg end
function A.pRoom(env, arg) return Rules.safeRoom(env.player) == arg end

function A.poi(env, arg)
    if type(Rules.adapters.poi) == "function" then return Rules.adapters.poi(env, arg) == true end
    local life = ProjectALife.VisitorLife
    if life ~= nil and type(life.hasPoi) == "function" then return life.hasPoi(env.record, arg) == true end
    return false
end

function A.act(env, arg) return env.person ~= nil and env.person.act == arg end
function A.wit(env, arg) return Rules.flagOf(env, "W_" .. arg) end
function A.pwit(env, arg) return Rules.flagOf(env, "P_" .. arg) end

function A.gave(env, arg) return Rules.flagOf(env, "G_" .. arg) end

function A.gaveever(env, arg)
    if Rules.flagOf(env, "G_" .. arg) then return true end
    local who = Rules.ledgerWho(env)
    if who == nil then return false end
    for _, name in ipairs(who.flags) do
        if name == "gave_" .. arg then return true end
    end
    return false
end

function A.mood(env, arg) return env.person ~= nil and env.person.mood == arg end
function A.did(env, arg) return Rules.flagOf(env, "D_" .. arg) end

function A.psex(env, arg)
    local speech = ProjectALife.Speech
    if speech == nil or type(speech.sexOf) ~= "function" then return false end
    return speech.sexOf(env.player) == arg
end

function A.vice(env, arg)
    local card = Rules.card(env)
    return card ~= nil and card.vice == arg
end

function A.carry(env, arg)
    local card = Rules.card(env)
    return card ~= nil and Rules.hasCarry(card, arg)
end

function A.bond(env, arg)
    local person = env.person
    if person == nil then return false end
    local party = Rules.card(env) ~= nil and Rules.card(env).party or nil
    if arg == "none" then return party == nil and #person.with == 0 end
    local raw = Rules.rawCard(person.id)
    return raw ~= nil and raw.bond == arg
end

function A.opt(env, arg)
    local field = Rules.optionFields[arg]
    return field ~= nil and Rules.options()[field] == true
end

function A.belief(env, arg)
    local card = Rules.card(env)
    if card == nil then return false end
    for _, row in ipairs(card.beliefs) do
        if row.id == arg then return true end
    end
    return false
end

function A.want(env, arg)
    local card = Rules.card(env)
    if card == nil then return false end
    for _, row in ipairs(card.wants) do
        if row.id == arg then return true end
    end
    return false
end

function A.knows(env, arg) return Rules.knows(env, arg) end
function A.heard(env, arg) return Rules.knows(env, arg) end
function A.flag(env, arg) return Rules.flagOf(env, arg) end

function A.gflag(env, arg)
    local store = Ledger.store()
    return type(store) == "table" and type(store.vflags) == "table" and store.vflags[arg] ~= nil
end

function A.need(env, arg)
    if env.person == nil then return 0 end
    return Instance.need(env.person, arg)
end

function A.pneed(env, arg) return Rules.partnerNeed(env, arg) end

function A.trait(env, arg)
    local card = Rules.card(env)
    if card == nil then return 0 end
    return card.traits[arg] or 0
end

function A.asked(env, arg)
    local row = Rules.row(env)
    if row == nil then return 0 end
    return (Instance.asked(row, arg))
end

function Rules.ctx(env)
    if env.ctx ~= nil then return env.ctx end
    local ctx = setmetatable({}, {
        __index = function(table, name)
            local atom = Rules.atoms[name]
            if atom == nil then return nil end
            local bound = function(arg, node) return atom(env, arg, node) end
            rawset(table, name, bound)
            return bound
        end,
    })
    env.ctx = ctx
    Rules.metrics.ctx = Rules.metrics.ctx + 1
    return ctx
end

function Rules.test(env, text)
    if text == nil or text == "" then return true end
    local ast = Rule.parse(text)
    if ast == nil then
        Rules.metrics.missing = Rules.metrics.missing + 1
        return false, "rule_invalid"
    end
    local ok, why = Rule.eval(ast, Rules.ctx(env))
    if why ~= nil then Rules.metrics.missing = Rules.metrics.missing + 1 end
    return ok == true, why
end

function Rules.reset()
    Rules.scans, Rules.scanCount = {}, 0
    Rules.metrics = { ctx = 0, scans = 0, missing = 0 }
end

function Rules.qaLine()
    local m = Rules.metrics
    return "[ALIFE-QA] VisitorTalkRules ctx=" .. tostring(m.ctx) .. " scans=" .. tostring(m.scans)
        .. " missing=" .. tostring(m.missing)
end

return Rules
