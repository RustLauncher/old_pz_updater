require "ProjectALife/Activities/ALifeActivityCatalog"
require "ProjectALife/Shells/ALifeProfileHydrator"
require "ProjectALife/Combat/ALifeWeapons"

ProjectALife = ProjectALife or {}
local Catalog = ProjectALife.ActivityCatalog
local Hunt = {}
ProjectALife.ActivityHunting = Hunt

function Hunt.enabled()
    return Catalog.enabled() and (tonumber(Catalog.sandbox("Activities_Hunting")) or 3) >= 2
end

function Hunt.habitatScale(habitat)
    local tiles = type(habitat) == "table" and tonumber(habitat.forest) or nil
    if tiles == nil or tiles ~= tiles or tiles < 0 or tiles > 150 then return 0 end
    if tiles == 0 then return 1 end
    return 0.5
end

function Hunt.seasonScale(month)
    month = tonumber(month)
    if month == 11 or month == 0 or month == 1 then return 0.6 end
    if month == 8 or month == 9 or month == 10 then return 1.2 end
    return 1
end

function Hunt.hourScale(hour)
    hour = tonumber(hour) or 12
    if hour >= 5 and hour < 8 or hour >= 17 and hour < 20 then return 1.3 end
    if hour >= 8 and hour < 17 then return 1 end
    return 0
end

function Hunt.month()
    if type(getGameTime) ~= "function" then return nil end
    local time = getGameTime()
    if time == nil or type(time.getMonth) ~= "function" then return nil end
    return time:getMonth()
end

function Hunt.firearm(kind)
    if type(kind) ~= "string" or type(getScriptManager) ~= "function" then return false end
    local manager = getScriptManager()
    if manager == nil or type(manager.getItem) ~= "function" then return false end
    local item = manager:getItem(kind)
    return item ~= nil and type(item.isRanged) == "function" and item:isRanged() == true
        and type(item.getAmmoType) == "function" and item:getAmmoType() ~= nil
        and ItemTag ~= nil and ItemTag.FIREARM ~= nil and type(item.hasTag) == "function"
        and item:hasTag(ItemTag.FIREARM) == true
end

function Hunt.plannedReady(member, squadId, index)
    if type(member.profileId) ~= "string" or type(squadId) ~= "string" or type(index) ~= "number"
            or type(instanceItem) ~= "function" or type(getGameTime) ~= "function" then return false end
    local hydrator, magazines = ProjectALife.ProfileHydrator, ProjectALife.MagazineState
    if hydrator == nil or type(hydrator.plan) ~= "function" or magazines == nil
            or type(magazines.spawnTotal) ~= "function" then return false end
    local time = getGameTime()
    if time == nil or type(time.getWorldAgeHours) ~= "function" then return false end
    local hours = tonumber(time:getWorldAgeHours())
    if hours == nil or hours ~= hours or math.abs(hours) == math.huge then return false end
    local seed = member.identitySeed or squadId .. ":member:" .. tostring(index)
    local plan = hydrator.plan({ uid = seed, profileId = member.profileId,
        memory = { identitySeed = seed, loadoutDay = math.max(0, math.floor(hours / 24)) } })
    if type(plan) ~= "table" or type(plan.weapons) ~= "table" then return false end
    for _, slot in ipairs({ "primary", "secondary" }) do
        local kind = plan.weapons[slot]
        if Hunt.firearm(kind) then
            local ok, item = pcall(instanceItem, kind)
            if ok and item ~= nil and type(item.getMaxAmmo) == "function" then
                local parts = type(plan.weaponAttachments) == "table" and plan.weaponAttachments[kind] or ""
                for partType in string.gmatch(tostring(parts or "") .. "|", "(.-)|") do
                    if partType ~= "" then
                        local made, part = pcall(instanceItem, partType)
                        if not made or part == nil or type(item.attachWeaponPart) ~= "function"
                                or not pcall(item.attachWeaponPart, item, part, true) then ok = false end
                    end
                end
                local capacity = math.max(0, math.floor(tonumber(item:getMaxAmmo()) or 0))
                if ok and capacity > 0 then
                    if plan.infiniteAmmo == true then return true end
                    local total = math.max(0, math.floor(tonumber(plan.ammo and plan.ammo[slot]) or 0))
                    if plan.ammoMode and plan.ammoMode[slot] == "magazines" then total = total * capacity end
                    if magazines.spawnTotal(nil, total, capacity, item) >= 6 then return true end
                end
            end
        end
    end
    return false
end

function Hunt.memberReady(member, squadId, index)
    if type(member) ~= "table" or (tonumber(member.health) or 100) <= 0 then return false end
    local state = member.shellState
    if state == nil or type(state) == "table" and state.reserve == nil
            and (state.weapons == nil and tonumber(state.version) == 1
                or type(state.weapons) == "table" and #state.weapons == 0 and state.maximumHealth == nil) then
        return Hunt.plannedReady(member, squadId, index)
    end
    if type(state) ~= "table" or type(state.weapons) ~= "table" then return false end
    local reserve = type(state.reserve) == "table" and state.reserve or {}
    for _, weapon in ipairs(state.weapons) do
        if Hunt.firearm(weapon.type) and (tonumber(weapon.condition) or 1) > 0 then
            local rounds = math.max(0, tonumber(weapon.ammo) or 0)
            if weapon.roundChambered == true then rounds = rounds + 1 end
            if weapon.slot == "primary" or weapon.slot == "secondary" then
                rounds = rounds + math.max(0, tonumber(reserve[weapon.slot]) or 0)
            end
            if rounds >= 6 then return true end
            local records, hydrator = ProjectALife.Catalog, ProjectALife.ProfileHydrator
            if records ~= nil and type(records.npc) == "function" and hydrator ~= nil
                    and type(hydrator.bottomless) == "function" then
                local profile = records.npc(member.profileId)
                if profile ~= nil and hydrator.bottomless(profile, profile.general) then return true end
            end
        end
    end
    return false
end

function Hunt.hunters(members, squadId)
    local count = 0
    for index, member in ipairs(type(members) == "table" and members or {}) do
        if Hunt.memberReady(member, squadId, index) then
            count = count + 1
            if count == 2 then break end
        end
    end
    return count
end

function Hunt.offlineYield(hunters, hours, habitat, month, hour, ammo, percent)
    local count = math.max(0, math.min(2, math.floor(tonumber(hunters) or 0)))
    local duration = math.max(0, math.min(3, tonumber(hours) or 0))
    local kills = duration * 0.35 * count * Hunt.habitatScale(habitat)
        * Hunt.seasonScale(month) * Hunt.hourScale(hour)
    kills = math.min(kills, math.max(0, tonumber(ammo) or 0) / 2)
    local scale = math.max(0, math.min(300, tonumber(percent) or 100)) / 100
    return kills * 10 * scale, kills * 2
end

function Hunt.offline(q, task, hour)
    if not Hunt.enabled() or task.activityRendered == true or task.activityYielded == true
            or task.kind ~= "hunt" then return 0, 0 end
    local graph = ProjectALife.RoadGraph
    local node = graph ~= nil and type(graph.nodes) == "table" and graph.nodes[q.nodeId] or nil
    if node == nil or q.nodeId ~= task.dest or Hunt.habitatScale(node.habitat) == 0 then return 0, 0 end
    local assigned, completed, untilHours = tonumber(task.assignedHours), tonumber(task.completedHours), tonumber(task.untilHours)
    if assigned == nil or completed == nil or untilHours == nil or completed < untilHours then return 0, 0 end
    local ammo = type(q.needs) == "table" and tonumber(q.needs.ammo) or 0
    local food, spent = Hunt.offlineYield(Hunt.hunters(q.members, q.id), untilHours - assigned,
        node.habitat, Hunt.month(), hour, ammo, Catalog.sandbox("Activities_HuntYieldPercent"))
    task.activityYielded = true
    return food, spent
end

function Hunt.liveEnabled()
    return Hunt.enabled() and (tonumber(Catalog.sandbox("Activities_Hunting")) or 3) == 3
end

function Hunt.point(body)
    if body == nil or type(body.getX) ~= "function" or type(body.getY) ~= "function"
            or type(body.getZ) ~= "function" then return nil end
    local point = { x = body:getX(), y = body:getY(), z = body:getZ() }
    for _, key in ipairs({ "x", "y", "z" }) do
        local value = point[key]
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
    end
    return point
end

function Hunt.wild(animal)
    if animal == nil or type(instanceof) ~= "function" or not instanceof(animal, "IsoAnimal") then return false end
    if type(animal.isWild) ~= "function" or animal:isWild() ~= true
            or type(animal.isDead) ~= "function" or animal:isDead() ~= false
            or type(animal.isBaby) ~= "function" or animal:isBaby() ~= false
            or type(animal.getHutch) ~= "function" or animal:getHutch() ~= nil
            or type(animal.getDZone) ~= "function" or animal:getDZone() ~= nil
            or type(animal.getAnimalType) ~= "function"
            or type(animal.getOnlineID) ~= "function" or animal:getOnlineID() == -1 then return false end
    local kind = animal:getAnimalType()
    return kind == "doe" or kind == "buck" or kind == "rabdoe" or kind == "rabbuck"
        or kind == "raccoonsow" or kind == "raccoonboar"
end

function Hunt.safeTarget(shell, animal, players, reach)
    if not Hunt.liveEnabled() or not Hunt.wild(animal) or type(players) ~= "table" then return false end
    local from, target = Hunt.point(shell), Hunt.point(animal)
    if from == nil or target == nil or math.floor(from.z) ~= math.floor(target.z) then return false end
    local distance = (from.x - target.x) ^ 2 + (from.y - target.y) ^ 2
    reach = math.max(0, math.min(60, tonumber(reach) or 60))
    if distance > reach * reach then return false end
    local combat, line = ProjectALife.Combat, ProjectALife.LineOfFire
    if combat == nil or type(combat.nearSegment) ~= "function" or line == nil
            or type(line.hasClearBoundary) ~= "function" then return false end
    for _, player in ipairs(players) do
        if type(player.isAnimal) ~= "function" then return false end
        if player:isAnimal() ~= true then
            local point = Hunt.point(player)
            if point == nil then return false end
            if (point.x - target.x) ^ 2 + (point.y - target.y) ^ 2 <= 400 then return false end
            if math.floor(point.z) == math.floor(from.z)
                    and combat.nearSegment(point, from.x, from.y, target.x, target.y, 1) then return false end
        end
    end
    return line.hasClearBoundary(shell, animal) == true
end

function Hunt.resolve(id)
    if type(id) ~= "number" or id ~= id or id < -32768 or id > 32767 or id ~= math.floor(id)
            or type(getAnimal) ~= "function" then return nil end
    local animal = getAnimal(id)
    if not Hunt.wild(animal) or type(animal.getOnlineID) ~= "function" or animal:getOnlineID() ~= id then return nil end
    return animal
end

function Hunt.players()
    local locator = ProjectALife.PlayerLocator
    if locator == nil or type(locator.list) ~= "function" then return nil end
    local players = locator.list()
    if type(players) ~= "table" then return nil end
    if type(getNumActivePlayers) == "function" and type(getSpecificPlayer) == "function" then
        local seen = {}
        for _, player in ipairs(players) do seen[player] = true end
        for index = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(index)
            if player ~= nil and not seen[player] then players[#players + 1] = player; seen[player] = true end
        end
    end
    return players
end

function Hunt.available(session, animal)
    if type(session) ~= "table" then return true end
    if (tonumber(session.shots) or 0) >= 6 or (tonumber(session.kills) or 0) >= 2 then return false end
    if animal == nil then return true end
    if type(animal.getOnlineID) ~= "function" then return false end
    local targets = type(session.targets) == "table" and session.targets or {}
    return (tonumber(targets[tostring(animal:getOnlineID())]) or 0) < 3
end

function Hunt.nearest(shell, players, session)
    if not Hunt.liveEnabled() or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getAnimals) ~= "function" then return nil end
    local animals, from = cell:getAnimals(), Hunt.point(shell)
    if animals == nil or type(animals.size) ~= "function" or type(animals.get) ~= "function" or from == nil then return nil end
    local nearest, best = nil, 3601
    for index = 0, animals:size() - 1 do
        local animal = animals:get(index)
        local point = Hunt.point(animal)
        if point ~= nil then
            local distance = (point.x - from.x) ^ 2 + (point.y - from.y) ^ 2
            if distance < best and Hunt.available(session, animal) and Hunt.safeTarget(shell, animal, players, 60) then nearest, best = animal, distance end
        end
    end
    return nearest
end

function Hunt.loadedHunters(members)
    local watchdog, relay = ProjectALife.Watchdog, ProjectALife.NPCHitRelay
    local weapons, magazines = ProjectALife.Weapons, ProjectALife.MagazineState
    if watchdog == nil or type(watchdog.bindings) ~= "table" or relay == nil
            or type(relay.bindingMatches) ~= "function" or weapons == nil
            or type(weapons.bestReloadableRanged) ~= "function" or type(weapons.slot) ~= "function"
            or magazines == nil or type(magazines.current) ~= "function"
            or type(magazines.reserve) ~= "function" or type(magazines.isInfinite) ~= "function" then return {} end
    local candidates = {}
    for _, record in ipairs(members) do
        local binding = watchdog.bindings[record.uid]
        if record.lifecycle == "active" and binding ~= nil and binding.generation == record.generation
                and relay.bindingMatches(binding, record.uid) then
            local shell = binding.shell
            if shell ~= nil and type(shell.isDead) == "function" and not shell:isDead() then
                local gun = weapons.bestReloadableRanged(shell)
                if gun ~= nil and type(gun.getFullType) == "function" and type(gun.getMaxRange) == "function"
                        and Hunt.firearm(gun:getFullType()) then
                    local rounds = magazines.current(gun) + magazines.reserve(shell, weapons.slot(gun), gun)
                    if rounds >= 6 or magazines.isInfinite(shell) then
                        candidates[#candidates + 1] = { uid = record.uid, generation = record.generation,
                            weapon = gun:getFullType(), range = tonumber(gun:getMaxRange()) or 0 }
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.range == b.range then return tostring(a.uid) < tostring(b.uid) end
        return a.range > b.range
    end)
    while #candidates > 2 do table.remove(candidates) end
    return candidates
end

function Hunt.deadline(hours, tripEnd)
    local finish = math.min(tonumber(tripEnd) or hours + 3, hours + 3)
    if type(getClimateManager) ~= "function" or type(getGameTime) ~= "function" then return finish end
    local climate, time = getClimateManager(), getGameTime()
    if climate == nil or type(climate.getSeason) ~= "function" or time == nil
            or type(time.getTimeOfDay) ~= "function" then return finish end
    local season = climate:getSeason()
    if season == nil or type(season.getDusk) ~= "function" then return finish end
    local dusk, hour = tonumber(season:getDusk()), tonumber(time:getTimeOfDay())
    if dusk == nil or hour == nil or dusk ~= dusk or hour ~= hour then return finish end
    return math.min(finish, hours + math.max(0, dusk + 1 - hour))
end

function Hunt.start(members, hours, untilHours)
    if not Hunt.liveEnabled() or type(members) ~= "table" or #members == 0 then return nil end
    local hunters = Hunt.loadedHunters(members)
    if #hunters == 0 then return nil end
    local anchor = members[1].worldPosition
    if type(anchor) ~= "table" or type(anchor.x) ~= "number" or type(anchor.y) ~= "number" then return nil end
    untilHours = Hunt.deadline(hours, untilHours)
    if untilHours <= hours then return nil end
    local session = { startedHours = hours, lastGameHours = hours, untilHours = untilHours,
        shots = 0, kills = 0, targets = {}, work = {}, memberCount = #members,
        anchor = { x = anchor.x, y = anchor.y, z = anchor.z or 0 } }
    for index, record in ipairs(members) do
        session.work[tostring(record.uid)] = { watch = true, generation = record.generation, index = index }
    end
    for _, hunter in ipairs(hunters) do
        local work = session.work[tostring(hunter.uid)]
        work.watch, work.weapon = false, hunter.weapon
    end
    return session
end

function Hunt.finished(session, members, hours, food)
    if not Hunt.liveEnabled() or type(session) ~= "table" or type(session.work) ~= "table"
            or hours < (tonumber(session.startedHours) or hours) or hours >= (tonumber(session.untilHours) or 0)
            or hours - (tonumber(session.lastGameHours) or hours) >= 1.5
            or (tonumber(session.shots) or 0) >= 6 or (tonumber(session.kills) or 0) >= 2
            or (tonumber(food) or 0) >= 80 then return true end
    local hunters = 0
    for _, record in ipairs(members) do
        local work = session.work[tostring(record.uid)]
        if work == nil or work.generation ~= record.generation then return true end
        if work.watch ~= true and record.lifecycle == "active" then hunters = hunters + 1 end
    end
    return hunters == 0
end

function Hunt.reserveShot(ticket, session, uid, animalId, now)
    local work = type(session) == "table" and type(session.work) == "table" and session.work[uid] or nil
    if type(ticket) ~= "table" or type(work) ~= "table" or work.watch == true
            or ticket.hunt == true or ticket.count ~= 0 or type(ticket.victims) ~= "table"
            or type(now) ~= "number" or now ~= now or math.abs(now) == math.huge
            or type(ticket.atMs) ~= "number" or ticket.atMs ~= ticket.atMs
            or now < ticket.atMs or now - ticket.atMs > 1500 then return false end
    if type(animalId) ~= "number" or animalId ~= animalId or animalId ~= math.floor(animalId)
            or animalId < -32768 or animalId > 32767 then return false end
    if (tonumber(session.shots) or 0) >= 6 or (tonumber(session.kills) or 0) >= 2 then return false end
    local key = tostring(animalId)
    local targets = type(session.targets) == "table" and session.targets or {}
    if (tonumber(targets[key]) or 0) >= 3 then return false end
    ticket.hunt, ticket.count = true, 1
    ticket.victims["animal:" .. key] = true
    session.shots = (tonumber(session.shots) or 0) + 1
    targets[key] = (tonumber(targets[key]) or 0) + 1
    session.targets = targets
    return true
end

function Hunt.kill(animal)
    if type(isClient) ~= "function" or isClient() or not Hunt.wild(animal)
            or type(animal.setAttackedBy) ~= "function" or type(animal.setHealth) ~= "function"
            or type(animal.getOnlineID) ~= "function" or type(getFakeAttacker) ~= "function" then return false end
    local server = type(isServer) == "function" and isServer()
    if server and type(sendServerCommandV) ~= "function" then return false end
    local attacker, id = getFakeAttacker(), animal:getOnlineID()
    if attacker == nil then return false end
    animal:setAttackedBy(attacker)
    animal:setHealth(0)
    if animal:isDead() ~= true then return false end
    if server then sendServerCommandV("animal", "kill", "id", id) end
    return true
end

function Hunt.spook(animal, shell)
    if not Hunt.wild(animal) or type(animal.getBehavior) ~= "function" then return false end
    local behavior = animal:getBehavior()
    if behavior == nil or type(behavior.forceFleeFromChr) ~= "function" then return false end
    behavior:forceFleeFromChr(shell)
    return true
end

return Hunt
