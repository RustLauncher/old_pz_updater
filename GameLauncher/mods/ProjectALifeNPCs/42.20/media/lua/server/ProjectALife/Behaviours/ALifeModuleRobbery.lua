require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Shells/ALifeShellState"
require "ProjectALife/Decisions/ALifeEncounterScript"
require "ProjectALife/Behaviours/ALifeFrisk"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry

local Robbery = {
    id = "robbery",
    settings = {
        enabled = true,
        chancePercent = 100,

        scanMs = 1000,
        tickMs = 250,
        detectRadius = 55,
        loneRadius = 15,
        cooldownMs = 1200000,
        spotMs = 1500,
        warningMs = 10000,
        weaponGraceMs = 12000,

        searchReach = 3.0,
        searchTimeoutMs = 20000,

        grabberRetryMs = 6000,
        grabberRetries = 2,

        handsUpGraceMs = 30000,

        searchMs = 6000,
        releaseMs = 20000,

        staleMs = 120000,
        followWatchMs = 180000,
        followRadius = 20,
        followHoldMs = 12000,
        carefulMs = 600000,
        moveWarn = 8,
        moveExecute = 15,
        gunRingMin = 5,
        gunRingMax = 8,
        meleeRingMin = 4.5,
        meleeRingMax = 6.5,
        leaveDistance = 60,
        containerRadius = 2,
        maxActive = 4,
        itemsTaken = 3,
        itemsTakenBigCrew = 4,
        bigCrew = 5,
        stolenCap = 12,
        armedReportMs = 1500,
        wordsCooldownMs = 5000,
    },

    chances = { raider = 90, gang = 85, club = 75, outlaw = 75, prison = 70, crime = 75, mercenary = 55 },
    active = {},
    byPlayer = {},
    cooldowns = {},
    watches = {},
    sequence = 0,
    lastScanAtMs = 0,
    lastTickAtMs = 0,
    adapters = {},
    metrics = { started = 0, rolledOff = 0, surrendered = 0, executed = 0, released = 0, followed = 0,
        itemsTaken = 0, interrupted = 0, moves = 0, holds = 0, regrabbed = 0, outOfReach = 0,
        stale = 0 },
}
ProjectALife.ModuleRobbery = Robbery

Robbery.fallbackWords = {
    ROBBERY_SPOT = "Hey you! Stop right there!",
    ROBBERY_HANDS_UP_1 = "Hands up! Don't you move!",
    ROBBERY_HANDS_UP_2 = "I said put your hands up!",
    ROBBERY_HANDS_UP_3 = "Last time! HANDS UP!",
    ROBBERY_WEAPON_DOWN = "PUT THE WEAPON DOWN!",
    ROBBERY_SHUT_UP = "Shut the hell up!",
    ROBBERY_MOVE = "Where the hell do you think you're going?!",
    ROBBERY_SEARCH = "Let's see what you got",
    ROBBERY_TAKE = "Yeah, that's ours now",
    ROBBERY_NOTHING = "Nothing? You're a sorry sight, you know that?",
    ROBBERY_RELEASE = "Don't come after us, go on, get lost",
    ROBBERY_DONT_FOLLOW = "I told you not to follow us!",
    ROBBERY_EXECUTE = "You had your chance!",
}

local function nowMs()
    if type(Robbery.adapters.nowMs) == "function" then return Robbery.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll(maximum)
    if type(Robbery.adapters.roll) == "function" then return Robbery.adapters.roll(maximum) end
    if type(ZombRand) == "function" then return ZombRand(maximum) end
    return math.random(0, maximum - 1)
end

local function position(object)
    if object == nil then return nil end
    local ok, x, y, z = pcall(function() return object:getX(), object:getY(), object:getZ() end)
    if ok and x ~= nil then return x, y, z end
    return nil
end

local function alive(object)
    if object == nil then return false end
    local ok, dead = pcall(function() return object:isDead() end)
    return ok and dead ~= true
end

function Robbery.reset()
    Robbery.active, Robbery.byPlayer, Robbery.cooldowns, Robbery.watches = {}, {}, {}, {}
    Robbery.clientWait = {}
    Robbery.sequence, Robbery.lastScanAtMs, Robbery.lastTickAtMs = 0, 0, 0
    Robbery.metrics = { started = 0, rolledOff = 0, surrendered = 0, executed = 0, released = 0, followed = 0,
        itemsTaken = 0, interrupted = 0, moves = 0, holds = 0, regrabbed = 0, outOfReach = 0,
        stale = 0 }
end

function Robbery.valueOf(facts)
    if type(facts) ~= "table" then return -1 end
    if facts.armor and not facts.worn and not facts.keyRing then return 80 end
    if facts.clothing or facts.worn or facts.keyRing then return -1 end
    if facts.ranged then return 100 + math.max(0, math.min(10, tonumber(facts.condition) or 0)) end
    if facts.ammo then return 70 end
    if facts.medical then return 60 end
    if facts.food and facts.sealed then return 40 end
    if facts.water then return 30 end
    if facts.weapon then return 85 end
    if facts.food then return 25 end
    if facts.utility then return 20 end
    return math.min(15, math.max(1, math.floor((tonumber(facts.weight) or 0.2) * 5)))
end

function Robbery.chooseItems(list, count)
    local candidates = {}
    for _, entry in ipairs(list or {}) do
        if (tonumber(entry.value) or -1) > 0 then candidates[#candidates + 1] = entry end
    end
    table.sort(candidates, function(a, b)
        if a.value == b.value then return tostring(a.key or "") < tostring(b.key or "") end
        return a.value > b.value
    end)
    local chosen = {}
    for index = 1, math.min(count, #candidates) do chosen[index] = candidates[index] end
    return chosen
end

local UTILITY = { Battery = true, Lighter = true, Matches = true, Torch = true, HandTorch = true, Pills = true }

function Robbery.factsFor(item, player)
    local facts = {}
    pcall(function()
        local fullType = tostring(item:getFullType())
        local category = tostring(item:getCategory() or "")
        local display = tostring(item:getDisplayCategory() or "")
        facts.fullType = fullType
        facts.clothing = category == "Clothing" or display == "Clothing" or display == "Accessory"
        facts.worn = item:isEquipped() == true
        facts.keyRing = category == "Key" or display == "Key" or string.find(fullType, "KeyRing", 1, true) ~= nil
        if instanceof(item, "InventoryContainer") and player ~= nil and player:isEquipped(item) then facts.worn = true end
        if instanceof(item, "HandWeapon") then
            facts.weapon = true
            facts.ranged = item:isRanged() == true
            facts.condition = item:getCondition()
        end
        facts.ammo = display == "Ammo" or string.find(fullType, "Bullets", 1, true) ~= nil
            or string.find(fullType, "Shells", 1, true) ~= nil or string.find(fullType, "Clip", 1, true) ~= nil
            or string.find(fullType, "Magazine", 1, true) ~= nil
        facts.medical = display == "FirstAid" or display == "Medical"
        facts.food = category == "Food" or display == "Food"
        facts.sealed = facts.food and (string.find(fullType, "Canned", 1, true) ~= nil or string.find(fullType, "Tinned", 1, true) ~= nil)
        facts.water = string.find(fullType, "Water", 1, true) ~= nil
        local short = string.match(fullType, "%.([^%.]+)$") or fullType
        facts.utility = UTILITY[short] == true
        facts.weight = item:getActualWeight()
        if facts.clothing and not facts.worn and instanceof(item, "Clothing") then
            local protection = (tonumber(item:getBiteDefense()) or 0) + (tonumber(item:getScratchDefense()) or 0)
            facts.armor = protection > 0
        end
    end)
    return facts
end

function Robbery.gatherItems(player, options)
    options = type(options) == "table" and options or {}
    local entries, visited, scanned = {}, {}, 0
    local limit = options.limit ~= nil and math.max(0, math.min(256, math.floor(tonumber(options.limit) or 0))) or math.huge
    local function walk(container, source, depth)
        if container == nil or depth > 3 or scanned >= limit or visited[container]
                or type(container.getItems) ~= "function" then return end
        visited[container] = true
        local ok, items = pcall(function() return container:getItems() end)
        if not ok or items == nil or type(items.size) ~= "function" or type(items.get) ~= "function" then return end
        local sized, size = pcall(items.size, items)
        if not sized or type(size) ~= "number" or size ~= size or size < 0 then return end
        for index = 0, size - 1 do
            if scanned >= limit then return end
            scanned = scanned + 1
            local got, item = pcall(items.get, items, index)
            if got and item ~= nil then
                local facts = Robbery.factsFor(item, player)
                entries[#entries + 1] = { item = item, container = container, source = source,
                    value = Robbery.valueOf(facts), key = facts.fullType, fullType = facts.fullType }
                local isBag = false
                pcall(function() isBag = instanceof(item, "InventoryContainer") end)
                if isBag and type(item.getInventory) == "function" then
                    local read, inner = pcall(item.getInventory, item)
                    if read then walk(inner, source, depth + 1) end
                end
            end
        end
    end
    pcall(function() walk(player:getInventory(), "player", 0) end)
    if options.playerOnly == true then return entries end
    local px, py, pz = position(player)
    if px ~= nil then
        local radius = Robbery.settings.containerRadius
        for dx = -radius, radius do
            for dy = -radius, radius do
                pcall(function()
                    local square = getCell():getGridSquare(math.floor(px) + dx, math.floor(py) + dy, math.floor(pz))
                    if square == nil then return end
                    local objects = square:getObjects()
                    for index = 0, objects:size() - 1 do
                        local object = objects:get(index)
                        if object.getContainerCount ~= nil then
                            for slot = 0, object:getContainerCount() - 1 do
                                walk(object:getContainerByIndex(slot), "world", 1)
                            end
                        end
                    end
                end)
            end
        end
    end
    return entries
end

function Robbery.removeItem(entry, destination, owner)
    if type(isClient) == "function" and isClient() then return false, "client_authority" end
    if destination ~= nil then
        local source = type(entry) == "table" and entry.container or nil
        local item = type(entry) == "table" and entry.item or nil
        local scavenging = ProjectALife.Scavenging
        if type(entry) ~= "table" or entry.source ~= "player" or source == nil or item == nil or owner == nil
                or scavenging == nil or type(scavenging.moveItem) ~= "function"
                or type(source.getItems) ~= "function" or type(source.Remove) ~= "function"
                or type(source.AddItem) ~= "function" or type(source.containsID) ~= "function"
                or type(destination.getItems) ~= "function" or type(destination.Remove) ~= "function"
                or type(destination.AddItem) ~= "function" or type(destination.containsID) ~= "function"
                or type(destination.hasRoomFor) ~= "function" or type(item.getContainer) ~= "function"
                or type(item.getID) ~= "function" then return false, "inventory_api_unavailable" end
        local read, list = pcall(source.getItems, source)
        local got, target = pcall(destination.getItems, destination)
        local roomOk, room = pcall(destination.hasRoomFor, destination, owner, item)
        if not read or list == nil or type(list.contains) ~= "function"
                or not got or target == nil or type(target.contains) ~= "function"
                or not roomOk or room ~= true then return false, "inventory_unavailable" end
        local moved = scavenging.moveItem(source, destination, item, owner)
        if not moved then
            local presentOk, present = pcall(list.contains, list, item)
            local targetOk, targetPresent = pcall(target.contains, target, item)
            local ownedOk, current = pcall(item.getContainer, item)
            return false, presentOk and present == true and targetOk and targetPresent == false
                and ownedOk and current == source and "transfer_refused" or "rollback_failed"
        end
        local shellState = ProjectALife.ShellState
        if shellState ~= nil and type(shellState.noteForeignRemoval) == "function" then
            pcall(shellState.noteForeignRemoval, source, item, "safehouse_give", owner)
        end
        if type(isServer) == "function" and isServer() then
            if type(sendRemoveItemFromContainer) == "function" then pcall(sendRemoveItemFromContainer, source, item) end
            if type(sendAddItemToContainer) == "function" then pcall(sendAddItemToContainer, destination, item) end
        end
        return true
    end
    local server = type(isServer) == "function" and isServer()
    local ok, removed = pcall(function()
        if not entry.container:getItems():contains(entry.item) then return false end
        if entry.source == "player" then
            entry.container:Remove(entry.item)
        else
            entry.container:DoRemoveItem(entry.item)
        end
        return not entry.container:getItems():contains(entry.item)
    end)
    if not ok or not removed then return false end
    local shellState = ProjectALife.ShellState
    if shellState ~= nil and type(shellState.noteForeignRemoval) == "function" then
        pcall(shellState.noteForeignRemoval, entry.container, entry.item, "robbery:" .. tostring(entry.source))
    end

    if server and type(sendRemoveItemFromContainer) == "function" then
        pcall(sendRemoveItemFromContainer, entry.container, entry.item)
    end
    return true
end

local function registry() return ProjectALife.ActorRegistry end

local function tradeAt(container, item)
    if container == nil or item == nil or type(item.getContainer) ~= "function"
            or type(container.getItems) ~= "function" then return false end
    local got, owner = pcall(item.getContainer, item)
    local read, items = pcall(container.getItems, container)
    if not got or owner ~= container or not read or items == nil or type(items.contains) ~= "function" then return false end
    local checked, contains = pcall(items.contains, items, item)
    return checked and contains == true
end

local function tradeEntry(entry)
    if type(entry) ~= "table" or entry.item == nil or entry.container == nil or entry.destination == nil
            or entry.owner == nil or entry.container == entry.destination or type(entry.item.getID) ~= "function" then return false end
    for _, container in ipairs({ entry.container, entry.destination }) do
        for _, name in ipairs({ "getItems", "Remove", "AddItem", "containsID", "hasRoomFor" }) do
            if type(container[name]) ~= "function" then return false end
        end
    end
    local roomOk, room = pcall(entry.destination.hasRoomFor, entry.destination, entry.owner, entry.item)
    local idOk, id = pcall(entry.item.getID, entry.item)
    if not idOk then return false end
    local hasOk, has = pcall(entry.destination.containsID, entry.destination, id)
    return roomOk and room == true and hasOk and has == false and tradeAt(entry.container, entry.item)
end

function Robbery.exchangeItems(cost, offer)
    if type(isClient) == "function" and isClient() then return false, "client_authority" end
    local scavenging, shellState = ProjectALife.Scavenging, ProjectALife.ShellState
    if scavenging == nil or type(scavenging.moveItem) ~= "function" or shellState == nil
            or type(shellState.markScavenged) ~= "function" or not tradeEntry(cost) or not tradeEntry(offer)
            or cost.item == offer.item then return false, "transfer_refused" end
    if type(cost.item.getModData) ~= "function" then return false, "item_persistence_unavailable" end
    local dataOk, data = pcall(cost.item.getModData, cost.item)
    if not dataOk or type(data) ~= "table" then return false, "item_persistence_unavailable" end
    local previous = data.ProjectALifeScavenged
    local markOk, marked = pcall(shellState.markScavenged, cost.item)
    if not markOk or marked ~= true then return false, "item_persistence_unavailable" end
    local movedCost = scavenging.moveItem(cost.container, cost.destination, cost.item, cost.owner)
    if not movedCost then
        local restored = tradeAt(cost.container, cost.item) and tradeAt(offer.container, offer.item)
        if tradeAt(cost.container, cost.item) then data.ProjectALifeScavenged = previous end
        return false, restored and "transfer_refused" or "rollback_failed"
    end
    local movedOffer = scavenging.moveItem(offer.container, offer.destination, offer.item, offer.owner)
    if not movedOffer or not tradeAt(cost.destination, cost.item) or not tradeAt(offer.destination, offer.item) then
        if tradeAt(offer.destination, offer.item) then
            scavenging.moveItem(offer.destination, offer.container, offer.item, cost.owner)
        end
        if tradeAt(cost.destination, cost.item) then
            scavenging.moveItem(cost.destination, cost.container, cost.item, offer.owner)
        end
        local restored = tradeAt(cost.container, cost.item) and tradeAt(offer.container, offer.item)
        if tradeAt(cost.container, cost.item) then data.ProjectALifeScavenged = previous end
        return false, restored and "transfer_refused" or "rollback_failed"
    end
    if type(shellState.noteForeignRemoval) == "function" then
        pcall(shellState.noteForeignRemoval, cost.container, cost.item, "safehouse_trade", cost.owner)
        pcall(shellState.noteForeignRemoval, offer.container, offer.item, "safehouse_trade", offer.owner)
    end
    if type(isServer) == "function" and isServer() then
        for _, entry in ipairs({ cost, offer }) do
            if type(sendRemoveItemFromContainer) == "function" then pcall(sendRemoveItemFromContainer, entry.container, entry.item) end
            if type(sendAddItemToContainer) == "function" then pcall(sendAddItemToContainer, entry.destination, entry.item) end
        end
    end
    return true, "exchanged"
end

function Robbery.shellFor(uid)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.shellFor) == "function" then return talk.shellFor(uid) end
    return nil
end

function Robbery.registerOf(record)
    local speech = ProjectALife.Speech
    if speech == nil then return nil end
    local ok, context = pcall(speech.contextFor, record, nil)
    if ok and context and context.role == "mercenary" then return "mercenary" end
    return ok and context and context.register or nil
end

function Robbery.armedShell(shell)
    local armed = false
    pcall(function()
        local item = shell:getPrimaryHandItem()
        armed = item ~= nil and instanceof(item, "HandWeapon") and item:isRanged() == true
    end)
    return armed
end

function Robbery.playerArmed(player, state, now)
    local armed = false
    pcall(function()
        for _, item in pairs({ player:getPrimaryHandItem(), player:getSecondaryHandItem() }) do
            if item ~= nil and instanceof(item, "HandWeapon") and tostring(item:getFullType()) ~= "Base.BareHands" then
                armed = true
            end
        end
    end)
    if not armed and state ~= nil and state.armedReport == true
            and now - (state.armedReportAtMs or 0) <= Robbery.settings.armedReportMs then
        armed = true
    end
    return armed
end

function Robbery.playerDangerous(player, state, now)
    local dangerous = false
    pcall(function()
        local hands = { player:getPrimaryHandItem(), player:getSecondaryHandItem() }
        for index = 1, 2 do
            local item = hands[index]
            if item ~= nil and instanceof(item, "HandWeapon") and item:isRanged() == true then dangerous = true end
        end
        if not dangerous and player:isAiming() == true and Robbery.playerArmed(player, nil, now) then dangerous = true end
    end)
    if not dangerous and state ~= nil and state.aimReport == true
            and now - (state.aimReportAtMs or 0) <= Robbery.settings.armedReportMs then
        dangerous = true
    end
    return dangerous
end

function Robbery.crewsNear(player)
    local px, py, pz = position(player)
    local crews = {}
    if px == nil or registry() == nil then return crews end
    local reach = Robbery.settings.detectRadius ^ 2
    registry().each(function(record)
        if record.lifecycle ~= "active" then return end
        local memory = type(record.memory) == "table" and record.memory or {}
        local key = memory.groupId or (memory.outpostId ~= nil and ("outpost:" .. tostring(memory.outpostId))) or nil
        if key == nil then return end
        local shell = Robbery.shellFor(record.uid)
        local x, y, z = position(shell)
        if x == nil or not alive(shell) or math.floor(z) ~= math.floor(pz) then return end
        if (x - px) ^ 2 + (y - py) ^ 2 > reach then return end
        local crew = crews[key]
        if crew == nil then
            crew = { key = tostring(key), members = {} }
            crews[key] = crew
        end
        crew.members[#crew.members + 1] = { record = record, shell = shell, distance = math.sqrt((x - px) ^ 2 + (y - py) ^ 2) }
    end)
    return crews
end

function Robbery.forced(crew)
    if type(crew) ~= "table" or type(crew.members) ~= "table" then return false end

    if type(Registry.override) ~= "function" then return false end
    for _, member in ipairs(crew.members) do
        if Registry.override(member.record, "robbery") == "on" then return true end
    end
    return false
end

function Robbery.kos(actor, hook, player, now)
    local warning = ProjectALife.ModuleWarning
    return warning ~= nil and type(warning.kos) == "function" and warning.kos(actor, hook, player, now) == true
end

function Robbery.kosFor(actor, key, now)
    if type(Registry.override) == "function" and Registry.override(actor, "robbery") == "on" then return false end
    return Robbery.kos(actor, "robbery", key, now)
end

function Robbery.overdue(state, now)
    local warning = ProjectALife.ModuleWarning
    if warning == nil or type(warning.expired) ~= "function" then return false end
    if warning.expired(state.startedAtMs, state.progressAtMs, now) ~= true then return false end
    if type(warning.timedOut) == "function" then warning.timedOut("robbery") end
    return true
end

function Robbery.eligible(crew, player, playerKey, now)
    local forced = Robbery.forced(crew)

    if #crew.members < (forced and 1 or 2) then return false, "too_few" end
    if not forced and Robbery.kos(crew.members[1].record, "robbery", playerKey, now) then return false, "kos" end
    local talk, relations, reputation = ProjectALife.Talk, ProjectALife.Relations, ProjectALife.Reputation
    local register = Robbery.registerOf(crew.members[1].record)
    if not forced and Robbery.chances[tostring(register)] == nil then return false, "not_robbers" end
    local personal = ProjectALife.PersonalRep
    if not forced and personal ~= nil and type(personal.robberyMode) == "function"
            and personal.robberyMode(player, crew.members[1].record) == "bargain" then
        return false, "respected"
    end
    local guns, seen = 0, false
    for _, member in ipairs(crew.members) do
        local memory = type(member.record.memory) == "table" and member.record.memory or {}
        if not Registry.allows(member.record, "robbery") then return false, "module_disabled" end
        if talk ~= nil and talk.inCombat(member.record)
                and (memory.combatTargetKind ~= "player" or memory.combatTargetPlayerKey ~= playerKey) then
            return false, "fighting"
        end
        if type(memory.hostileToPlayerKeys) == "table" and memory.hostileToPlayerKeys[playerKey] == true then return false, "grudge" end
        if type(memory.robbery) == "table" then return false, "busy" end
        if Robbery.armedShell(member.shell) then guns = guns + 1 end
        if not seen then
            local careful = ProjectALife.ModuleCareful
            seen = careful == nil or type(careful.lineOfSight) ~= "function" or careful.lineOfSight(member.shell, player) == true
        end
    end

    if not forced and guns < 1 and #crew.members < 3 then return false, "unarmed" end

    if not seen then return false, "unseen" end
    if reputation ~= nil and type(reputation.recordedStatus) == "function" then
        local ok, earned = pcall(reputation.recordedStatus, player, crew.members[1].record)
        if ok and earned == "hostile" then return false, "grudge" end
    end
    if not forced and relations ~= nil and type(relations.playerStance) == "function" then
        local ok, stance = pcall(relations.playerStance, crew.members[1].record, player)
        if ok and stance ~= "hostile" and stance ~= "careful" then return false, "not_hostile" end
    end
    if not forced and not Robbery.outlawCrew(crew) then return false, "not_outlaws" end
    return true, register
end

function Robbery.loneAndOnFoot(player, players)
    local px, py = position(player)
    if px == nil or not alive(player) then return false end
    local inVehicle = false
    pcall(function() inVehicle = player:getVehicle() ~= nil end)
    if inVehicle then return false end
    local reach = Robbery.settings.loneRadius ^ 2
    for _, other in ipairs(players) do
        if other ~= player then
            local ox, oy = position(other)
            if ox ~= nil and alive(other) and (ox - px) ^ 2 + (oy - py) ^ 2 <= reach then return false end
        end
    end
    return true
end

function Robbery.searchPose(uid, searching)
    if uid == nil then return false end
    local animations = ProjectALife.Animations
    if animations == nil then return false end
    local shell = Robbery.shellFor(uid)
    if shell == nil then return false end
    local ok = pcall(function()
        if searching then animations.apply(shell, "search_mid")
        else animations.clear(shell) end
    end)
    return ok
end

function Robbery.stepMs()
    local script = ProjectALife.EncounterScript
    local hold = script ~= nil and script.holdMs() or 8000
    return math.max(1500, math.min(tonumber(Robbery.settings.warningMs) or 10000, math.floor(hold * 4 / 5)))
end

function Robbery.weaponGraceMs()
    return math.min(tonumber(Robbery.settings.weaponGraceMs) or 12000, 2 * Robbery.stepMs())
end

function Robbery.say(state, uid, event, vars)
    local talk, speech, script = ProjectALife.Talk, ProjectALife.Speech, ProjectALife.EncounterScript
    local record = registry() and registry().read(uid) or nil
    local shell = Robbery.shellFor(uid)
    if record == nil or shell == nil or state.player == nil then return nil end
    local said = nil
    if talk ~= nil and speech ~= nil then
        local context = speech.contextFor(record, state.player)
        context.stance = "hostile"
        if script ~= nil then
            said = script.say(state, record, shell, state.player, event, context, vars)
        else
            said = talk.bark(record, shell, state.player, event, context, vars)
        end
    end
    if said == nil and speech ~= nil and Robbery.fallbackWords[event] ~= nil
            and (script == nil or script.mayDraw(state, event)) then
        if speech.say(shell, Robbery.fallbackWords[event], { face = state.player }) then
            said = Robbery.fallbackWords[event]
            if script ~= nil then script.mark(state, event) end
        end
    end
    if said ~= nil and talk ~= nil and type(talk.issueOrder) == "function" then
        pcall(talk.issueOrder, state.player, uid, "robbery", Robbery.settings.handsUpGraceMs)
    end
    return said
end

function Robbery.writeMember(uid, fields)
    local talk = ProjectALife.Talk
    if talk == nil then return false end
    return talk.writeMemory(uid, function(memory)
        if fields == false then
            memory.robbery = nil
            return
        end
        memory.robbery = type(memory.robbery) == "table" and memory.robbery or {}
        for key, value in pairs(fields) do memory.robbery[key] = value end
        if type(fields.playerKey) == "string" and tonumber(fields.atMs) ~= nil then
            memory.robbedAt = type(memory.robbedAt) == "table" and memory.robbedAt or {}
            memory.robbedAt[fields.playerKey] = tonumber(memory.robbedAt[fields.playerKey]) or tonumber(fields.atMs)
        end
    end)
end

function Robbery.broadcastPhase(state, extra)
    local px, py, pz = position(state.player)
    for _, uid in ipairs(state.members) do

        local fields = { id = state.id, playerKey = state.playerKey, phase = state.phase,
            atMs = state.startedAtMs, px = px, py = py, pz = pz,
            surrender = state.surrender == true, frisking = state.frisk ~= nil and uid == state.grabberUid,
            role = uid == state.grabberUid and "grabber" or state.roles[uid], postX = state.posts[uid] and state.posts[uid].x,
            postY = state.posts[uid] and state.posts[uid].y }
        if type(extra) == "table" then for key, value in pairs(extra) do fields[key] = value end end
        Robbery.writeMember(uid, fields)
    end
    state.lastBroadcastAtMs = nowMs()
end

function Robbery.pickGrabber(state, skip)
    local frisk = ProjectALife.Frisk
    if frisk ~= nil and frisk.enabled() then return frisk.pick(state, skip) end
    local hands, rifles = {}, {}
    for _, uid in ipairs(state.members) do
        if uid ~= skip and (uid ~= state.leaderUid or #state.members == 1) then
            if state.roles[uid] == "gun" then rifles[#rifles + 1] = uid else hands[#hands + 1] = uid end
        end
    end
    local pool = #hands > 0 and hands or rifles
    if #pool == 0 then

        return state.leaderUid or state.members[1]
    end
    return pool[1 + roll(#pool)]
end

function Robbery.ringPost(px, py, mx, my, radius, index, count)
    local dx, dy = (mx or px) - px, (my or py) - py
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.5 then
        local angle = (index - 1) / count * math.pi * 2
        dx, dy, length = math.cos(angle), math.sin(angle), 1
    end
    return { x = px + dx / length * radius, y = py + dy / length * radius }
end

function Robbery.awayFrom(state, px, py)
    local flat = math.sqrt((px - state.anchorX) ^ 2 + (py - state.anchorY) ^ 2)
    local lx, ly = position(Robbery.shellFor(state.leaderUid))
    if lx == nil or state.startDist == nil then return flat end
    local gained = math.sqrt((px - lx) ^ 2 + (py - ly) ^ 2) - state.startDist
    if gained < 0 then gained = 0 end
    return math.min(flat, gained + (flat >= Robbery.settings.moveExecute * 2 and flat or 0))
end

function Robbery.start(crew, player, playerKey, register, now, surrender)
    Robbery.sequence = Robbery.sequence + 1
    local px, py = position(player)
    table.sort(crew.members, function(a, b) return a.distance < b.distance end)
    local state = { id = "robbery:" .. tostring(Robbery.sequence), groupKey = crew.key, player = player, playerKey = playerKey,
        register = register, members = {}, roles = {}, posts = {}, phase = "spot", phaseAtMs = now, startedAtMs = now,
        warnings = 0, shouts = 0, handsUp = false, anchorX = px, anchorY = py, taken = {}, movedWarned = false,
        leaderUid = crew.members[1].record.uid, grabberUid = nil, outpostId = nil }
    local leadX, leadY = position(crew.members[1].shell)
    if leadX ~= nil and px ~= nil then state.startDist = math.sqrt((px - leadX) ^ 2 + (py - leadY) ^ 2) end
    local count = #crew.members
    for index, member in ipairs(crew.members) do
        local uid = member.record.uid
        state.members[#state.members + 1] = uid
        local gun = Robbery.armedShell(member.shell)
        state.roles[uid] = gun and "gun" or "melee"
        local memory = type(member.record.memory) == "table" and member.record.memory or {}
        if memory.outpostId ~= nil then state.outpostId = memory.outpostId end
        local minimum = gun and Robbery.settings.gunRingMin or Robbery.settings.meleeRingMin
        local maximum = gun and Robbery.settings.gunRingMax or Robbery.settings.meleeRingMax
        local radius = minimum + (maximum - minimum) * ((index % 3) / 2)
        local mx, my = position(member.shell)
        state.posts[uid] = Robbery.ringPost(px, py, mx, my, radius, index, count)
    end
    state.grabberUid = Robbery.pickGrabber(state)
    Robbery.active[state.id] = state
    Robbery.byPlayer[playerKey] = state.id
    Robbery.metrics.started = Robbery.metrics.started + 1
    local warning = ProjectALife.ModuleWarning
    if warning ~= nil and type(warning.given) == "function" then warning.given("robbery") end
    if surrender then
        state.surrender = true
        state.handsUp = not Robbery.playerArmed(player, nil, now)
        state.phase = surrender == "execute" and "execute_hold" or "spot"
    end
    Robbery.broadcastPhase(state)
    Robbery.say(state, state.leaderUid, "ROBBERY_SPOT")

    if type(isServer) == "function" and isServer() and type(sendServerCommand) == "function" then
        pcall(sendServerCommand, player, "ProjectALife", "robberyWatch", { seconds = 120 })
    end
    return state
end

function Robbery.finish(state, reason)
    if state.frisk ~= nil and ProjectALife.Frisk ~= nil then ProjectALife.Frisk.stop(state, true) end
    Robbery.active[state.id] = nil
    if Robbery.byPlayer[state.playerKey] == state.id then Robbery.byPlayer[state.playerKey] = nil end
    for _, uid in ipairs(state.members) do Robbery.writeMember(uid, false) end
    if state.player ~= nil and ProjectALife.Talk ~= nil and type(ProjectALife.Talk.clearOrders) == "function" then
        pcall(ProjectALife.Talk.clearOrders, state.player)
    end
    state.finishedReason = reason
    if type(isServer) == "function" and isServer() and type(sendServerCommand) == "function" and state.player ~= nil then
        pcall(sendServerCommand, state.player, "ProjectALife", "robberyWatch", { seconds = 0 })
    end
end

function Robbery.execute(state, reason)
    if state.phase == "execute" then return end
    state.phase = "execute"

    if state.frisk ~= nil and ProjectALife.Frisk ~= nil then ProjectALife.Frisk.stop(state, true) end
    Robbery.searchPose(state.grabberUid, false)
    Robbery.metrics.executed = Robbery.metrics.executed + 1
    Robbery.broadcastPhase(state)
    Robbery.say(state, state.leaderUid, "ROBBERY_EXECUTE")
    local careful = ProjectALife.ModuleCareful
    local record = registry() and registry().read(state.leaderUid) or nil
    local shell = Robbery.shellFor(state.leaderUid)
    if careful ~= nil and type(careful.turnGroup) == "function" and record ~= nil and shell ~= nil then
        local script = ProjectALife.EncounterScript
        pcall(careful.turnGroup, record, shell, state.player, script ~= nil and script.enabled())
    end
    Robbery.finish(state, "execute:" .. tostring(reason))
end

function Robbery.take(state)
    local count = #state.members >= Robbery.settings.bigCrew and Robbery.settings.itemsTakenBigCrew or Robbery.settings.itemsTaken
    local keeper, talk = state.grabberUid, ProjectALife.Talk
    local record = registry() and registry().read(keeper)
    if record == nil or talk == nil then return {} end
    local old = record.memory and record.memory.stolenLoot or {}
    count = math.max(0, math.min(count, Robbery.settings.stolenCap - #old))
    local chosen = Robbery.chooseItems(Robbery.gatherItems(state.player), count)
    local taken, saved, removed = {}, {}, {}
    for _, entry in ipairs(chosen) do
        local snapshot = ProjectALife.ShellState.captureItem(entry.item)
        if snapshot and Robbery.removeItem(entry) then
            snapshot.robberyItemKey = tostring(state.id) .. ":" .. tostring(#old + #saved + 1)
            taken[#taken + 1], saved[#saved + 1], removed[#removed + 1] = entry.fullType, snapshot, entry
        end
    end
    if #taken > 0 then
        local stored = talk.writeMemory(keeper, function(memory)
            memory.stolenLoot = type(memory.stolenLoot) == "table" and memory.stolenLoot or {}
            for _, snapshot in ipairs(saved) do memory.stolenLoot[#memory.stolenLoot + 1] = snapshot end
        end)
        if not stored then

            for _, entry in ipairs(removed) do
                pcall(function()
                    entry.container:AddItem(entry.item)
                    if type(isServer) == "function" and isServer() and type(sendAddItemToContainer) == "function" then
                        sendAddItemToContainer(entry.container, entry.item)
                    end
                end)
            end
            state.taken = {}
            return {}
        end
        if state.outpostId ~= nil then
            Robbery.depositAtOutpost(state.outpostId, keeper, saved)
        elseif ProjectALife.TalkOrders ~= nil and type(ProjectALife.TalkOrders.adopt) == "function" then
            pcall(ProjectALife.TalkOrders.adopt, keeper, saved)
        end
    end
    state.taken = taken
    Robbery.metrics.itemsTaken = Robbery.metrics.itemsTaken + #taken
    return taken
end

function Robbery.depositAtOutpost(outpostId, keeperUid, savedItems)
    local talk, actors = ProjectALife.Talk, registry()
    local keeper = actors and actors.read(keeperUid)
    if talk == nil or keeper == nil then return false end

    local pending, seen = {}, {}
    for _, requested in ipairs(savedItems or {}) do
        local key = type(requested) == "table" and requested.robberyItemKey
        if key and not seen[key] then
            for _, saved in ipairs(keeper.memory and keeper.memory.stolenLoot or {}) do
                if type(saved) == "table" and saved.robberyItemKey == key then
                    pending[#pending + 1] = saved; seen[key] = true; break
                end
            end
        end
    end
    if #pending == 0 then return false end
    local sites = ProjectALife.OutpostRegistry
    local site = sites ~= nil and type(sites.read) == "function" and sites.read(tostring(outpostId)) or nil

    local origin = site ~= nil and site.x ~= nil and { x = site.x, y = site.y, z = 0 } or nil
    if origin == nil then return false end
    local deposited, delivered, destination = false, {}, nil
    pcall(function()
        for dx = -6, 6 do
            for dy = -6, 6 do
                local square = getCell():getGridSquare(math.floor(origin.x) + dx, math.floor(origin.y) + dy, math.floor(origin.z or 0))
                if square ~= nil then
                    local objects = square:getObjects()
                    for index = 0, objects:size() - 1 do
                        local object = objects:get(index)
                        local container = object.getContainer ~= nil and object:getContainer() or nil
                        if container ~= nil then
                            destination = container
                            for _, saved in ipairs(pending) do
                                local item = ProjectALife.ShellState.createItem(saved)
                                if item ~= nil and container:AddItem(item) ~= nil then
                                    delivered[#delivered + 1] = { saved = saved, item = item }
                                end
                            end
                            return
                        end
                    end
                end
            end
        end
    end)
    if #delivered > 0 and ProjectALife.Talk ~= nil then
        deposited = ProjectALife.Talk.writeMemory(keeperUid, function(memory)
            local remaining = {}
            for _, saved in ipairs(memory.stolenLoot or {}) do
                local found = false
                for _, entry in ipairs(delivered) do
                    if type(saved) == "table" and saved.robberyItemKey ~= nil
                            and type(entry.saved) == "table" and saved.robberyItemKey == entry.saved.robberyItemKey then found = true; break end
                end
                if not found then remaining[#remaining + 1] = saved end
            end
            memory.stolenLoot = remaining
        end)
        for _, entry in ipairs(delivered) do
            pcall(function()
                if not deposited then destination:Remove(entry.item)
                elseif type(isServer) == "function" and isServer() and type(sendAddItemToContainer) == "function" then
                    sendAddItemToContainer(destination, entry.item)
                end
            end)
        end
    end
    return deposited
end

function Robbery.memberLives(state, uid)
    local record = registry() ~= nil and registry().read(uid) or nil
    if record == nil or record.lifecycle ~= "active" then return false end
    return alive(Robbery.shellFor(uid))
end

function Robbery.release(state, now, px, py)

    Robbery.searchPose(state.grabberUid, false)
    local taken = Robbery.take(state)
    Robbery.say(state, state.grabberUid, #taken > 0 and "ROBBERY_TAKE" or "ROBBERY_NOTHING")
    state.phase, state.phaseAtMs = "release", now
    for _, uid in ipairs(state.members) do
        ProjectALife.Talk.writeMemory(uid, function(memory)
            memory.robberyTruce = memory.robberyTruce or {}
            memory.robberyTruce[state.playerKey] = now + Robbery.settings.followWatchMs
        end)
    end
    local dx, dy = (state.anchorX - px), (state.anchorY - py)
    local ax, ay = position(Robbery.shellFor(state.leaderUid))
    if ax ~= nil then dx, dy = ax - px, ay - py end
    local length = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    Robbery.broadcastPhase(state, { leaveX = px + dx / length * Robbery.settings.leaveDistance,
        leaveY = py + dy / length * Robbery.settings.leaveDistance })
    Robbery.say(state, state.leaderUid, "ROBBERY_RELEASE")
    return true
end

function Robbery.advance(state, now)
    local player = state.player
    if not alive(player) then return Robbery.finish(state, "player_gone") end
    local living, fighting = {}, false
    for _, uid in ipairs(state.members) do
        local record = registry() and registry().read(uid) or nil
        local shell = Robbery.shellFor(uid)
        if record ~= nil and record.lifecycle == "active" and alive(shell) then
            living[#living + 1] = uid
            local talk = ProjectALife.Talk
            local memory = record.memory or {}
            if talk ~= nil and talk.inCombat(record) and state.phase ~= "release"
                    and memory.combatTargetKind ~= "player" then fighting = true end
        end
    end
    if #living == 0 then return Robbery.finish(state, "crew_gone") end
    if fighting then
        Robbery.metrics.interrupted = Robbery.metrics.interrupted + 1
        return Robbery.finish(state, "interrupted")
    end
    state.members = living
    if not registry().read(state.leaderUid) then state.leaderUid = living[1] end

    local phase = state.phase
    local px, py = position(player)
    local handsUp = false
    local talk = ProjectALife.Talk

    if talk ~= nil and type(talk.handsUpSince) == "function" then
        handsUp = talk.handsUpSince(state.playerKey, state.startedAtMs - Robbery.settings.handsUpGraceMs)
    end
    local armed = Robbery.playerArmed(player, state, now)
    local dangerous = Robbery.playerDangerous(player, state, now)

    if phase == "execute_hold" then
        if now - state.phaseAtMs >= 6000 then return Robbery.execute(state, "hostile_surrender") end
        return
    end

    if phase == "release" then
        if now - state.phaseAtMs >= Robbery.settings.releaseMs then
            Robbery.metrics.released = Robbery.metrics.released + 1
            Robbery.watches[state.id] = { members = living, player = player, playerKey = state.playerKey,
                untilMs = now + Robbery.settings.followWatchMs, nearSinceMs = nil,
                anchorX = px, anchorY = py }
            return Robbery.finish(state, "released")
        end
        return
    end

    local moved = Robbery.awayFrom(state, px, py)
    if moved >= Robbery.settings.moveExecute then return Robbery.execute(state, "fled") end
    if moved >= Robbery.settings.moveWarn and not state.movedWarned then
        state.movedWarned = true
        state.warnings = state.warnings + 1
        Robbery.say(state, state.leaderUid, "ROBBERY_MOVE")
    end

    if state.handsUp and dangerous then return Robbery.execute(state, "drew_weapon") end
    if handsUp and not state.handsUp and not dangerous then
        state.handsUp = true
        Robbery.metrics.surrendered = Robbery.metrics.surrendered + 1

        if phase == "spot" or phase == "demand" or phase == "weapon" then
            state.phase, state.phaseAtMs, phase = "search", now, "search"
            state.grabberSentAtMs, state.grabberRetries, state.searchSaid = now, 0, false
            state.grabberUid = Robbery.pickGrabber(state)
            Robbery.broadcastPhase(state)
        end
    end

    if (phase == "spot" or phase == "demand" or phase == "weapon") and not state.handsUp
            and Robbery.overdue(state, now) then
        return Robbery.execute(state, "timeout")
    end

    if phase == "spot" then
        if now - state.phaseAtMs >= Robbery.settings.spotMs then
            state.phase, state.phaseAtMs, state.warnings = armed and "weapon" or "demand", now, 1
            state.progressAtMs = now
            state.weaponDeadlineMs, state.weaponReminded = now + Robbery.weaponGraceMs(), nil
            Robbery.broadcastPhase(state)
            Robbery.say(state, state.leaderUid, armed and "ROBBERY_WEAPON_DOWN" or "ROBBERY_HANDS_UP_1")
        end
    elseif phase == "demand" or phase == "weapon" then
        if armed and not state.handsUp and phase ~= "weapon" then
            state.phase, state.phaseAtMs, state.progressAtMs = "weapon", now, now
            state.weaponDeadlineMs, state.weaponReminded = now + Robbery.weaponGraceMs(), nil
            Robbery.broadcastPhase(state)
            Robbery.say(state, state.leaderUid, "ROBBERY_WEAPON_DOWN")
            return
        end
        if phase == "weapon" and not armed then
            state.phase = "demand"
            state.phaseAtMs = now
            state.progressAtMs = now
            Robbery.broadcastPhase(state)
            Robbery.say(state, state.leaderUid, "ROBBERY_HANDS_UP_1")
        end
        if state.handsUp then
            state.phase, state.phaseAtMs = "search", now
            Robbery.broadcastPhase(state)
            return
        end
        if state.phase == "weapon" then
            if now >= state.weaponDeadlineMs then return Robbery.execute(state, "armed") end
            if not state.weaponReminded and now - state.phaseAtMs >= Robbery.stepMs() then
                state.weaponReminded, state.progressAtMs = true, now
                Robbery.say(state, state.leaderUid, "ROBBERY_WEAPON_DOWN")
            end
            return
        end
        if now - state.phaseAtMs >= Robbery.stepMs() then
            if state.warnings >= 4 then return Robbery.execute(state, "no_hands") end
            state.warnings = state.warnings + 1
            state.phaseAtMs, state.progressAtMs = now, now
            Robbery.say(state, state.leaderUid, state.warnings == 4 and "ROBBERY_HANDS_UP_3" or "ROBBERY_HANDS_UP_2")
        end
    elseif phase == "search" and ProjectALife.Frisk ~= nil and ProjectALife.Frisk.enabled() then
        local verdict = ProjectALife.Frisk.advance(state, now)
        if verdict == "release" then return Robbery.release(state, now, px, py) end
        if verdict == "aborted" then
            if (state.friskAborts or 0) >= ProjectALife.Frisk.maxAborts then return Robbery.execute(state, "frisk_aborted") end
            state.warnings = state.warnings + 1
            Robbery.say(state, state.leaderUid, "ROBBERY_MOVE")
        end
    elseif phase == "search" then

        state.grabberSentAtMs = state.grabberSentAtMs or state.phaseAtMs
        if state.grabberUid == nil or not Robbery.memberLives(state, state.grabberUid) then
            state.grabberUid, state.grabberSentAtMs, state.searchSaid = Robbery.pickGrabber(state), now, false
            Robbery.broadcastPhase(state)
        end
        local grabber = Robbery.shellFor(state.grabberUid)
        local gx, gy = position(grabber)
        local close = gx ~= nil and math.sqrt((gx - px) ^ 2 + (gy - py) ^ 2) <= Robbery.settings.searchReach
        if not close and now - state.grabberSentAtMs >= Robbery.settings.grabberRetryMs
                and (state.grabberRetries or 0) < Robbery.settings.grabberRetries and #state.members > 1 then
            state.grabberRetries = (state.grabberRetries or 0) + 1
            state.grabberUid, state.grabberSentAtMs, state.searchSaid = Robbery.pickGrabber(state, state.grabberUid), now, false
            Robbery.metrics.regrabbed = (Robbery.metrics.regrabbed or 0) + 1
            Robbery.broadcastPhase(state)
        end

        if not close and now - state.phaseAtMs >= Robbery.settings.searchTimeoutMs then
            Robbery.metrics.outOfReach = (Robbery.metrics.outOfReach or 0) + 1
            return Robbery.release(state, now, px, py)
        end
        if not state.searchSaid and close then
            state.searchSaid, state.searchAtMs = true, now
            Robbery.say(state, state.grabberUid, "ROBBERY_SEARCH")

            Robbery.searchPose(state.grabberUid, true)
        end
        if state.searchSaid and close and now - state.searchAtMs >= Robbery.settings.searchMs then
            return Robbery.release(state, now, px, py)
        end
    end
    if now - (state.lastBroadcastAtMs or 0) >= 1000 then Robbery.broadcastPhase(state) end
end

function Robbery.watch(watch, now)
    if now >= watch.untilMs or not alive(watch.player) then return true end
    local px, py = position(watch.player)
    if px == nil then return true end
    if watch.anchorX == nil then watch.anchorX, watch.anchorY = px, py end

    if (px - watch.anchorX) ^ 2 + (py - watch.anchorY) ^ 2 < Robbery.settings.moveWarn ^ 2 then
        watch.nearSinceMs = nil
        return false
    end
    local near = false
    for _, uid in ipairs(watch.members) do
        local x, y = position(Robbery.shellFor(uid))
        if x ~= nil and (x - px) ^ 2 + (y - py) ^ 2 <= Robbery.settings.followRadius ^ 2 then near = true; break end
    end
    if not near then watch.nearSinceMs = nil return false end
    watch.nearSinceMs = watch.nearSinceMs or now
    if now - watch.nearSinceMs < Robbery.settings.followHoldMs then return false end
    Robbery.metrics.followed = Robbery.metrics.followed + 1
    local talk = ProjectALife.Talk
    for index, uid in ipairs(watch.members) do
        if talk ~= nil then
            talk.writeMemory(uid, function(memory)
                memory.carefulPlayerKeys = type(memory.carefulPlayerKeys) == "table" and memory.carefulPlayerKeys or {}
                memory.carefulPlayerKeys[watch.playerKey] = now + Robbery.settings.carefulMs
            end)
        end
        if index == 1 then
            Robbery.say({ player = watch.player }, uid, "ROBBERY_DONT_FOLLOW")
        end
    end
    return true
end

function Robbery.tick(now)
    now = now or nowMs()
    if Robbery.settings.enabled ~= true then return 0 end
    local speech = ProjectALife.Speech
    if speech == nil or not speech.authoritative() then return 0 end
    if now - Robbery.lastTickAtMs < Robbery.settings.tickMs then return 0 end
    Robbery.lastTickAtMs = now
    local processed = 0
    for _, state in pairs(Robbery.active) do
        pcall(Robbery.advance, state, now)
        processed = processed + 1
    end
    for id, watch in pairs(Robbery.watches) do
        local ok, done = pcall(Robbery.watch, watch, now)
        if not ok or done then Robbery.watches[id] = nil end
    end
    if now - Robbery.lastScanAtMs < Robbery.settings.scanMs then return processed end
    Robbery.lastScanAtMs = now
    local count = 0
    for _ in pairs(Robbery.active) do count = count + 1 end
    if count >= Robbery.settings.maxActive then return processed end
    local presence = ProjectALife.ModuleTalkPresence
    local players = presence ~= nil and presence.players() or {}
    for _, player in ipairs(players) do
        local playerKey = speech.playerKey(player)
        if playerKey ~= nil and Robbery.byPlayer[playerKey] == nil then

            local lone = Robbery.loneAndOnFoot(player, players)
            for key, crew in pairs(Robbery.crewsNear(player)) do
                local cooldownKey = tostring(key) .. ":" .. playerKey
                local demanded = Robbery.forced(crew)
                if (lone or demanded) and now >= (Robbery.cooldowns[cooldownKey] or 0) then
                    local ok, register = Robbery.eligible(crew, player, playerKey, now)
                    if ok then
                        Robbery.cooldowns[cooldownKey] = now + Robbery.settings.cooldownMs
                        local chance = (Robbery.chances[register] or 0) * (tonumber(Robbery.settings.chancePercent) or 100) / 100
                        if demanded then chance = 100 end
                        if roll(100) < chance then
                            Robbery.start(crew, player, playerKey, register, now)
                            processed = processed + 1
                            count = count + 1
                            if count >= Robbery.settings.maxActive then return processed end
                            break
                        else
                            Robbery.metrics.rolledOff = Robbery.metrics.rolledOff + 1
                        end
                    end
                end
            end
        end
    end
    return processed
end

local function stateFor(player)
    local speech = ProjectALife.Speech
    local key = speech ~= nil and speech.playerKey(player) or nil
    local id = key ~= nil and Robbery.byPlayer[key] or nil
    return id ~= nil and Robbery.active[id] or nil
end

function Robbery.stale(robbery, now)
    if type(robbery) ~= "table" then return true end
    now = tonumber(now) or nowMs()

    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.authoritative) == "function" and speech.authoritative() then
        local id = robbery.id
        if id == nil or Robbery.active[id] == nil then return true end
    end

    local atMs = tonumber(robbery.atMs)
    if atMs == nil then return true end
    return now - atMs >= (tonumber(Robbery.settings.staleMs) or 120000)
end

function Robbery.forget(actor, reason)
    if type(actor) ~= "table" or actor.uid == nil then return false end
    if type(actor.memory) == "table" then actor.memory.robbery = nil end
    Robbery.writeMember(actor.uid, false)
    Robbery.metrics.stale = (Robbery.metrics.stale or 0) + 1
    pcall(function()
        local blackBox = ProjectALife.BlackBox
        local watchdog = ProjectALife.Watchdog
        local binding = watchdog ~= nil and type(watchdog.bindings) == "table"
            and watchdog.bindings[actor.uid] or nil
        if blackBox ~= nil and binding ~= nil and binding.shell ~= nil then
            blackBox.note(binding.shell, "robbery_stale", tostring(reason or "orphaned"))
        end
    end)
    return true
end

function Robbery.activeFor(actor, playerKey)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    local robbery = memory and memory.robbery or nil
    if type(robbery) ~= "table" then return false end
    if robbery.playerKey ~= playerKey or robbery.phase == "execute" then return false end

    if Robbery.stale(robbery) then
        Robbery.forget(actor, "no_live_holdup")
        return false
    end
    return true
end

function Robbery.noteFar(player, state)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.orderAnswered) == "function" then pcall(talk.orderAnswered, player, state.leaderUid) end
end

function Robbery.onShout(player)
    local state = stateFor(player)
    if state == nil or state.phase == "release" or state.phase == "execute" then return false end
    Robbery.noteFar(player, state)
    state.shouts = state.shouts + 1
    if state.shouts >= 2 then
        Robbery.execute(state, "shouted")
        return true
    end
    state.warnings = state.warnings + 1
    Robbery.say(state, state.leaderUid, "ROBBERY_SHUT_UP")
    return true
end

function Robbery.onPlayerWords(player, text, loud, now)
    local state = stateFor(player)
    if state == nil or state.phase == "release" or state.phase == "execute" then return false end
    if loud == true then return Robbery.onShout(player) end
    Robbery.noteFar(player, state)
    now = now or nowMs()
    if now - (state.wordsAtMs or 0) >= Robbery.settings.wordsCooldownMs then
        state.wordsAtMs = now
        Robbery.say(state, state.leaderUid, "ROBBERY_SHUT_UP")
    end
    return true
end

function Robbery.onPlayerEmote(player, emote)
    local held = stateFor(player)
    if held ~= nil then
        if emote == "surrender" then Robbery.noteFar(player, held) end
        return true
    end
    local speech, relations = ProjectALife.Speech, ProjectALife.Relations
    if emote ~= "surrender" or not speech.authoritative() then return false end
    local key, now = speech.playerKey(player), nowMs()
    if key == nil then return false end
    local best, distance
    for _, crew in pairs(Robbery.crewsNear(player)) do
        for _, member in ipairs(crew.members) do
            if member.distance <= 20 and (distance == nil or member.distance < distance)
                    and relations.hostileToPlayer(member.record, player)
                    and ProjectALife.ModuleCareful.lineOfSight(member.shell, player) then
                best, distance = crew, member.distance
            end
        end
    end
    if best == nil then return false end
    local count = 0
    for _ in pairs(Robbery.active) do count = count + 1 end
    if count >= Robbery.settings.maxActive then return false end
    local cooldown = tostring(best.key) .. ":surrender:" .. key
    if now < (Robbery.cooldowns[cooldown] or 0) then return false end
    Robbery.cooldowns[cooldown] = now + Robbery.settings.cooldownMs
    if not Robbery.outlawCrew(best) then
        Robbery.standDown(best, player, key)
        return true
    end

    local base = "hostile"
    if relations ~= nil and type(relations.baselineStance) == "function" then
        base = relations.baselineStance(best.members[1].record, player) or "hostile"
    end
    Robbery.start(best, player, key, Robbery.registerOf(best.members[1].record), now,
        (base == "careful" or base == "neutral" or base == "friendly") and "rob" or "execute")
    return true
end

function Robbery.outlawCrew(crew)
    local member = crew and crew.members and crew.members[1]
    local catalog, rules = ProjectALife.Catalog, ProjectALife.FactionSpawnRules
    if member == nil or catalog == nil or rules == nil or type(rules.outlaw) ~= "function" then return true end
    local ok, faction = pcall(catalog.faction, member.record.factionId)
    if not ok or type(faction) ~= "table" then return true end
    return rules.outlaw(faction) == true
end

Robbery.standDownLines = {
    "Go on home, it's bad out here",
    "Nobody's arresting you, just get inside, huh",
    "Put that away and get off the street before you get bit",
    "Easy, go on home and lock your door",
    "We ain't here for you, so beat it",
}
Robbery.walkAwayLines = {
    "Just walk away, nice and easy",
    "Go on, get out of here!",
    "Back off slow and we're done",
}

function Robbery.standDown(crew, player, playerKey)
    local speaker = crew.members[1]
    local rules, catalog = ProjectALife.FactionSpawnRules, ProjectALife.Catalog
    local faction = speaker and catalog and catalog.faction(speaker.record.factionId)
    local bloc = tostring(rules ~= nil and type(rules.blocOf) == "function" and rules.blocOf(faction)
        or (faction and faction.relations and faction.relations.bloc) or "")
    local state = rules ~= nil and type(rules.stateBlocs) == "table" and rules.stateBlocs[bloc] == true
    local lines = state and Robbery.standDownLines or Robbery.walkAwayLines
    local speech = ProjectALife.Speech
    if speech ~= nil and speaker ~= nil and speaker.shell ~= nil then
        pcall(speech.say, speaker.shell, lines[1 + roll(#lines)], { face = player })
    end
    local talk = ProjectALife.Talk
    if talk == nil or type(talk.writeMemory) ~= "function" then return end
    for _, member in ipairs(crew.members) do
        talk.writeMemory(member.record.uid, function(memory)
            if type(memory.hostileToPlayerKeys) == "table" then memory.hostileToPlayerKeys[playerKey] = nil end
        end)
    end
    Robbery.metrics.stoodDown = (Robbery.metrics.stoodDown or 0) + 1
end

function Robbery.enroll(state, actor, now)
    if type(state) ~= "table" or type(actor) ~= "table" or state.phase == "execute" then return false end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local key = memory.groupId or (memory.outpostId ~= nil and ("outpost:" .. tostring(memory.outpostId))) or nil
    if key == nil or tostring(key) ~= tostring(state.groupKey) then return false end
    for _, uid in ipairs(state.members) do
        if uid == actor.uid then return true end
    end
    if state.phase == "release" then
        Robbery.writeMember(actor.uid, false)
        ProjectALife.Talk.writeMemory(actor.uid, function(mem)
            mem.robberyTruce = type(mem.robberyTruce) == "table" and mem.robberyTruce or {}
            mem.robberyTruce[state.playerKey] = now + Robbery.settings.followWatchMs
        end)
        state.members[#state.members + 1] = actor.uid
        return true
    end
    local px, py = position(state.player)
    local count = #state.members + 1
    local gun = Robbery.armedShell(Robbery.shellFor(actor.uid))
    local minimum = gun and Robbery.settings.gunRingMin or Robbery.settings.meleeRingMin
    local maximum = gun and Robbery.settings.gunRingMax or Robbery.settings.meleeRingMax
    local radius = minimum + (maximum - minimum) * ((count % 3) / 2)
    state.members[count] = actor.uid
    state.roles[actor.uid] = gun and "gun" or "melee"
    local mx, my = position(Robbery.shellFor(actor.uid))
    if px ~= nil then state.posts[actor.uid] = Robbery.ringPost(px, py, mx, my, radius, count, count) end
    Robbery.metrics.enrolled = (Robbery.metrics.enrolled or 0) + 1
    Robbery.broadcastPhase(state)
    return true
end

function Robbery.consider(actor, player, now)
    if not Robbery.settings.enabled then return false end
    local key = ProjectALife.Speech.playerKey(player)
    if key == nil then return false end
    if Robbery.activeFor(actor, key) then return true end
    if Robbery.kosFor(actor, key, now) then return false end
    if not ProjectALife.Speech.authoritative() then

        if not Registry.allows(actor, "robbery") then return false end
        local demanded = type(Registry.override) == "function"
            and Registry.override(actor, "robbery") == "on"
        if not demanded and Robbery.chances[Robbery.registerOf(actor)] == nil then return false end
        Robbery.clientWait = Robbery.clientWait or {}
        local wait = Robbery.clientWait[actor.uid]
        if wait == nil or wait.key ~= key then
            local size = 0
            for uid, entry in pairs(Robbery.clientWait) do
                if now - entry.untilMs > Robbery.settings.cooldownMs then Robbery.clientWait[uid] = nil else size = size + 1 end
            end
            if size >= 256 then return false end
            wait = { key = key, untilMs = now + 1500 }
            Robbery.clientWait[actor.uid] = wait
        end
        return now < wait.untilMs
    end
    local live = Robbery.byPlayer[key]
    if live ~= nil then return Robbery.enroll(Robbery.active[live], actor, now) end
    local count = 0
    for _ in pairs(Robbery.active) do count = count + 1 end
    if count >= Robbery.settings.maxActive then return false end
    local presence = ProjectALife.ModuleTalkPresence
    if not Robbery.loneAndOnFoot(player, presence and presence.players() or { player }) then return false end
    for group, crew in pairs(Robbery.crewsNear(player)) do
        local mine = false
        for _, member in ipairs(crew.members) do if member.record.uid == actor.uid then mine = true break end end
        local cooldown = tostring(group) .. ":" .. key
        if mine and now >= (Robbery.cooldowns[cooldown] or 0) then
            local allowed, register = Robbery.eligible(crew, player, key, now)
            if not allowed then return false end
            Robbery.cooldowns[cooldown] = now + Robbery.settings.cooldownMs
            if roll(100) < (Robbery.chances[register] or 0) * Robbery.settings.chancePercent / 100 then
                Robbery.start(crew, player, key, register, now)
                return true
            end
        end
    end
    return false
end

function Robbery.onPlayerState(player, args)
    local state = stateFor(player)
    if state == nil or type(args) ~= "table" then return false end
    local now = nowMs()
    state.armedReport = args.armed == true
    state.armedReportAtMs = now

    if args.aiming == true and args.armed == true then
        state.aimReport, state.aimReportAtMs = true, now
        if state.phase ~= "release" and state.phase ~= "execute" then
            Robbery.execute(state, "aimed_at_crew")
        end
    else
        state.aimReport = false
    end
    return true
end

function Robbery.onPlayerAttack(player, record)
    if not ProjectALife.Speech.authoritative() then return end
    local state = stateFor(player)
    if state then
        for _, uid in ipairs(state.members) do
            if uid == record.uid then Robbery.execute(state, "attacked_crew"); return end
        end
    end
    local key = ProjectALife.Speech.playerKey(player)
    local memory = record.memory or {}
    if key and memory.robberyTruce and memory.robberyTruce[key] then
        ProjectALife.ModuleCareful.turnGroup(record, Robbery.shellFor(record.uid), player)
    end
end

function Robbery.evaluate(actor, shell, context)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local robbery = memory.robbery
    if not Registry.allows(actor, "robbery") and not (robbery and robbery.surrender) then return nil end
    if type(robbery) ~= "table" or robbery.phase == nil or robbery.phase == "execute" then return nil end
    local now = tonumber(context and context.now) or nowMs()
    local sx, sy, sz = position(shell)
    if sx == nil then return nil end
    if robbery.phase == "release" then
        if robbery.leaveX ~= nil and type(context.startMovement) == "function" then
            Robbery.metrics.moves = Robbery.metrics.moves + 1
            return context.startMovement(actor, shell, { x = robbery.leaveX, y = robbery.leaveY, z = sz }, "robbery_leave",
                { pace = "walk", timeoutMs = 15000, tolerance = 3 })
        end
        return nil
    end
    local tx, ty = robbery.postX, robbery.postY
    local stand, arrive, tolerance = 1.2, 1.5, 1
    if robbery.role == "grabber" and robbery.phase == "search" and robbery.px ~= nil then
        local frisk = ProjectALife.Frisk
        if frisk ~= nil and frisk.enabled() then stand, arrive, tolerance = frisk.standTiles, 0.8, 0.5 end
        local dx, dy = sx - robbery.px, sy - robbery.py
        local length = math.max(0.01, math.sqrt(dx * dx + dy * dy))
        tx, ty = robbery.px + dx / length * stand, robbery.py + dy / length * stand
    end
    if tx ~= nil and (tx - sx) ^ 2 + (ty - sy) ^ 2 > arrive * arrive and type(context.startMovement) == "function" then
        Robbery.metrics.moves = Robbery.metrics.moves + 1
        local started = context.startMovement(actor, shell, { x = tx, y = ty, z = sz }, "robbery_close",
            { pace = robbery.phase == "spot" and "run" or "walk", timeoutMs = 6000, tolerance = tolerance })
        if started ~= nil then return started end
    end
    if robbery.px ~= nil then
        pcall(function()
            local guard = ProjectALife.AIFence
            if guard ~= nil and type(guard.faceAimPoint) == "function" then guard.faceAimPoint(shell, robbery.px, robbery.py, now) end
            local combat, animations = ProjectALife.Combat, ProjectALife.Animations
            if combat ~= nil and animations ~= nil and type(combat.readyPresetFor) == "function" and type(animations.apply) == "function"
                    and robbery.frisking ~= true
                    and not (type(animations.active) == "table" and animations.active[shell] ~= nil) then
                local preset = combat.readyPresetFor(shell, shell:getPrimaryHandItem(), nil)
                if preset ~= nil then animations.apply(shell, preset) end
            end
        end)
    end
    if type(context.setActivity) == "function" then context.setActivity(actor, "warning", "robbery_hold") end
    Robbery.metrics.holds = Robbery.metrics.holds + 1
    return { kind = "idle", intent = "robbery_hold", cooldownUntilMs = now + 400 }
end

Registry.register({
    id = "robbery",
    kind = "orders",
    dispatch = "decision",

    priority = 3,
    label = "Robbery",
    summary = "An outlaw crew holds up a lone player: weapon down, hands up, three or four valuable items taken, then it leaves. Refusing gets him shot.",
    defaultEnabled = true,
    evaluate = Robbery.evaluate,
})

return Robbery
