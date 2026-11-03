require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/World/ALifeSeasons"

ProjectALife = ProjectALife or {}

local Cold = {
    settings = {
        comfortC = 14, wearBonusC = 14, wearDivisor = 2.2, wetPenaltyC = 6, slope = 4.5,
        seekAt = 40, chilledAt = 35, freezingAt = 70, warmAt = 12, sickAt = 55,
        minStepHours = 0.03, maxStepHours = 2, riseRate = 0.8, fallRate = 2, warmBonusPerHour = 8,
        wetRainRate = 1.2, wetSnowRate = 0.8, wetGroundRate = 0.15, wetDryRate = 0.3, wetBuildRate = 0.6,
        sickMinHours = 18, sickSpreadHours = 36, immuneHours = 36, sickWarmRecovery = 0.5,
        expelMinMs = 40000, expelSpreadMs = 70000, barkGapMs = 90000, expelBarkGapMs = 25000,
        sneezeRadius = 7, sneezeVolume = 10, coughRadius = 5, coughVolume = 6,
        aimSick = 0.9, aimFreezing = 0.95, paceSick = 0.94, paceFreezing = 0.97,
        drainSick = 1.25, recoverSick = 0.8,
        sampleStep = 3, scanRadius = 18, seekRadius = 30, buildingRadius = 40,
        holdMaxMs = 480000, goMaxMs = 120000, seekCooldownMs = 120000, scanTtlMs = 30000,
        persistHours = 0.25, dressGapMs = 600000, hotAboveC = 31,
    },
    keys = {
        coldEnabled = "Cold_Enabled", coldSeverity = "Cold_Severity", coldChance = "Cold_ChancePercent",
        coldSneezeNoise = "Cold_SneezeNoise", coldSeek = "Cold_SeekWarmth",
    },
    defaults = { coldEnabled = true, coldSeverity = 100, coldChance = 6, coldSneezeNoise = true, coldSeek = true },
    states = {},
    fireCache = {},
    metrics = { advanced = 0, chilled = 0, freezing = 0, colds = 0, recovered = 0, sneezes = 0, coughs = 0,
        seeks = 0, arrivals = 0, warmed = 0, dressed = 0, barks = 0, scans = 0, noises = 0 },
}
ProjectALife.Cold = Cold

function Cold.option(field)
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    if type(current) == "table" and current[field] ~= nil then return current[field] end
    if type(SandboxVars) == "table" and type(SandboxVars.ALife) == "table" then
        local value = SandboxVars.ALife[Cold.keys[field]]
        if value ~= nil then return value end
    end
    return Cold.defaults[field]
end

function Cold.enabled()
    return Cold.option("coldEnabled") ~= false
end

function Cold.severity()
    local value = tonumber(Cold.option("coldSeverity")) or 100
    return math.max(0, math.min(300, value)) / 100
end

function Cold.clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function Cold.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Cold.hours()
    if type(getGameTime) ~= "function" then return 0 end
    local time = getGameTime()
    if time == nil or type(time.getWorldAgeHours) ~= "function" then return 0 end
    return tonumber(time:getWorldAgeHours()) or 0
end

function Cold.seed(uid, salt)
    local id = tostring(uid or "") .. tostring(salt or "")
    local seed = 0
    for index = 1, #id do seed = (seed * 31 + string.byte(id, index)) % 2147483647 end
    return (seed % 1000) / 1000
end

function Cold.season()
    return ProjectALife.Seasons.current()
end

function Cold.weather(now)
    return ProjectALife.Seasons.weather(now)
end

function Cold.snowAware()
    if Cold.snowMod == nil then
        Cold.snowMod = false
        local compat = ProjectALife.ModCompat
        if compat ~= nil and type(compat.isActive) == "function" and compat.isActive("ImmersiveSnow") then
            Cold.snowMod = true
        elseif type(ISnow) == "table" then
            Cold.snowMod = true
        end
    end
    return Cold.snowMod
end

function Cold.sky(now)
    return ProjectALife.Seasons.sky(now)
end

function Cold.airAt(shell, w)
    local climate = w ~= nil and w.climate or nil
    if climate == nil or type(climate.getAirTemperatureForCharacter) ~= "function" then return w and w.air or nil end
    local ok, value = pcall(climate.getAirTemperatureForCharacter, climate, shell)
    value = ok and tonumber(value) or nil
    if value == nil then return w.air end
    return value
end

function Cold.outside(shell)
    if type(shell.isOutside) ~= "function" then return true end
    local ok, outside = pcall(shell.isOutside, shell)
    return not ok or outside ~= false
end

function Cold.sumWorn(worn)
    local sum = 0
    for index = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(index)
        if item ~= nil and instanceof(item, "Clothing") then
            sum = sum + (tonumber(item:getInsulation()) or 0)
        end
    end
    return sum
end

function Cold.warmthOf(shell)
    if type(shell.getWornItems) ~= "function" then return 0.3 end
    local ok, worn = pcall(shell.getWornItems, shell)
    if not ok or worn == nil then return 0.3 end
    local okSum, sum = pcall(Cold.sumWorn, worn)
    if not okSum then return 0.3 end
    return Cold.clamp(sum / Cold.settings.wearDivisor, 0, 1)
end

function Cold.stateFor(actor, hours)
    local existing = Cold.states[actor.uid]
    if existing ~= nil and existing.generation == actor.generation then return existing end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local saved = type(memory.cold) == "table" and memory.cold or {}
    local state = {
        uid = actor.uid, generation = actor.generation,
        chill = Cold.clamp(tonumber(saved.c) or 0, 0, 100), wet = Cold.clamp(tonumber(saved.w) or 0, 0, 1),
        sickUntil = tonumber(saved.s) or 0, immuneUntil = tonumber(saved.i) or 0,
        lastH = hours, persistedH = hours, warmth = 0.3, warmthH = -10,
        nextExpelMs = 0, nextBarkMs = 0, nextExpelBarkMs = 0, seekCooldownMs = 0, dressAtMs = 0,
        level = 0, sentLevel = 0, stamp = "",
    }
    Cold.states[actor.uid] = state
    return state
end

function Cold.sickNow(state, hours)
    return state ~= nil and state.sickUntil > hours
end

function Cold.persist(actor, state, context, hours, force)
    if not force and hours - state.persistedH < Cold.settings.persistHours then return end
    state.persistedH = hours
    if type(context) ~= "table" or type(context.persistMemory) ~= "function" then return end
    context.persistMemory(actor, "cold", {
        c = math.floor(state.chill), w = math.floor(state.wet * 100) / 100,
        s = state.sickUntil, i = state.immuneUntil, h = hours,
    })
end

function Cold.stamp(shell, state, hours)
    local s = Cold.settings
    local scale = Cold.clamp(Cold.severity(), 0, 2)
    local aim, pace, drain, recover, label = 1, 1, 1, 1, ""
    if Cold.sickNow(state, hours) then
        aim, pace = 1 - (1 - s.aimSick) * scale, 1 - (1 - s.paceSick) * scale
        drain, recover, label = 1 + (s.drainSick - 1) * scale, 1 - (1 - s.recoverSick) * scale, "sick"
    elseif state.chill >= s.freezingAt then
        aim, pace = 1 - (1 - s.aimFreezing) * scale, 1 - (1 - s.paceFreezing) * scale
        label = "freezing"
    elseif state.chill >= s.chilledAt then
        label = "chilled"
    end
    state.drain, state.recover = drain, recover
    if state.stamp == label then return end
    state.stamp = label
    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        data.ProjectALifeColdAim = aim < 1 and aim or nil
        data.ProjectALifeColdPace = pace < 1 and pace or nil
        data.ProjectALifeCold = label ~= "" and label or nil
    end)
end

function Cold.drainScale(uid)
    local state = Cold.states[uid]
    return state ~= nil and state.drain or 1
end

function Cold.recoveryScale(uid)
    local state = Cold.states[uid]
    return state ~= nil and state.recover or 1
end

function Cold.forget(uid)
    Cold.states[uid] = nil
end

function Cold.reset()
    Cold.states, Cold.fireCache, Cold.snowMod = {}, {}, nil
    ProjectALife.Seasons.reset()
end

function Cold.say(actor, shell, state, event, now, gapKey)
    local key = gapKey or "nextBarkMs"
    if now < (state[key] or 0) then return false end
    local speech = ProjectALife.Speech
    if speech == nil or type(speech.bark) ~= "function" then return false end
    local ok, text = pcall(speech.bark, actor, shell, event, {})
    if not ok or text == nil then return false end
    local gap = key == "nextExpelBarkMs" and Cold.settings.expelBarkGapMs or Cold.settings.barkGapMs
    state[key] = now + gap + ZombRand(math.floor(gap / 2))
    Cold.metrics.barks = Cold.metrics.barks + 1
    return true
end

function Cold.advance(actor, shell, state, dt, hours, context, now)
    local s = Cold.settings
    local w = Cold.weather(now)
    if w == nil then return end
    local air = Cold.airAt(shell, w)
    if air == nil then return end
    Cold.metrics.advanced = Cold.metrics.advanced + 1
    local outside = Cold.outside(shell)
    if hours - state.warmthH > 0.5 then
        state.warmth, state.warmthH = Cold.warmthOf(shell), hours
    end
    local gain = 0
    if outside then
        gain = w.rain * s.wetRainRate + (w.snowing and w.snow * s.wetSnowRate or 0)
        if w.ground > 0.15 and air < 4 then
            gain = gain + w.ground * s.wetGroundRate * (Cold.snowAware() and 1 or 0.5)
        end
    end
    if gain > 0 then
        state.wet = math.min(1, state.wet + gain * dt * s.wetBuildRate)
    else
        state.wet = math.max(0, state.wet - dt * s.wetDryRate * (air > 12 and 2 or 1))
    end
    local severity = Cold.severity()
    local effective = air + s.wearBonusC * state.warmth - s.wetPenaltyC * state.wet
    local target = Cold.clamp((s.comfortC - effective) * s.slope * severity, 0, 100)
    local before = state.chill
    if target > state.chill then
        state.chill = state.chill + (target - state.chill) * math.min(1, dt * s.riseRate * math.max(0.25, severity))
    else
        local fall = (state.chill - target) * math.min(1, dt * s.fallRate)
        if target <= 1 then fall = fall + dt * s.warmBonusPerHour end
        state.chill = math.max(target, state.chill - fall)
    end
    state.chill = Cold.clamp(state.chill, 0, 100)
    if before < s.chilledAt and state.chill >= s.chilledAt then Cold.metrics.chilled = Cold.metrics.chilled + 1 end
    if before < s.freezingAt and state.chill >= s.freezingAt then Cold.metrics.freezing = Cold.metrics.freezing + 1 end
    local level = state.chill >= s.freezingAt and 2 or (state.chill >= s.chilledAt and 1 or 0)
    if level > state.level then
        state.level = level
        if level == 2 then Cold.say(actor, shell, state, "SHIVER", now)
        else Cold.say(actor, shell, state, "COLD", now) end
    elseif level < state.level then
        state.level = level
    end
    local sick = Cold.sickNow(state, hours)
    if sick then
        if state.chill < 25 then state.sickUntil = state.sickUntil - dt * s.sickWarmRecovery end
        if state.sickUntil <= hours then
            state.sickUntil = 0
            state.immuneUntil = hours + s.immuneHours
            Cold.metrics.recovered = Cold.metrics.recovered + 1
            Cold.say(actor, shell, state, "SICK_RECOVERED", now)
            Cold.persist(actor, state, context, hours, true)
        end
    elseif state.chill >= s.sickAt and hours >= state.immuneUntil then
        local chance = (tonumber(Cold.option("coldChance")) or 6) / 100
        local hazard = chance * (state.chill - 45) / 55 * (1 + state.wet * 0.5)
        if chance > 0 and ZombRand(10000) < math.floor(hazard * dt * 10000) then
            state.sickUntil = hours + s.sickMinHours + ZombRand(s.sickSpreadHours)
            state.nextExpelMs = now + 8000 + ZombRand(20000)
            Cold.metrics.colds = Cold.metrics.colds + 1
            Cold.say(actor, shell, state, "SICK_COMPLAINT", now)
            Cold.persist(actor, state, context, hours, true)
        end
    end
    Cold.stamp(shell, state, hours)
    Cold.persist(actor, state, context, hours, false)
    if outside and air >= s.hotAboveC and w.rain < 0.1 then Cold.say(actor, shell, state, "HOT", now) end
end

function Cold.vocal(shell, kind)
    local policy = ProjectALife.AudioPolicy
    if policy == nil or type(policy.allowsNPC) ~= "function" or not policy.allowsNPC() then return false end
    return pcall(function()
        local prefix = shell:getDescriptor():getVoicePrefix()
        local emitter = shell:getEmitter()
        local name = tostring(prefix) .. (kind == "sneeze" and "SneezeHeavy" or "Cough")
        if emitter:isPlaying(name) then return end
        emitter:playVocals(name)
    end)
end

function Cold.noise(shell, kind)
    if Cold.option("coldSneezeNoise") == false then return false end
    local combat = ProjectALife.Combat
    if combat == nil or type(combat.worldNoise) ~= "function" then return false end
    local s = Cold.settings
    local ok = pcall(combat.worldNoise, shell, kind == "sneeze" and s.sneezeRadius or s.coughRadius,
        kind == "sneeze" and s.sneezeVolume or s.coughVolume)
    if ok then Cold.metrics.noises = Cold.metrics.noises + 1 end
    return ok
end

function Cold.expel(actor, shell, state, context, now)
    local kind = ZombRand(100) < 60 and "sneeze" or "cough"
    local animated = false
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.apply) == "function" then
        local ok, applied = pcall(animations.apply, shell, kind)
        animated = ok and applied == true
    end
    Cold.vocal(shell, kind)
    Cold.noise(shell, kind)
    if kind == "sneeze" then Cold.metrics.sneezes = Cold.metrics.sneezes + 1
    else Cold.metrics.coughs = Cold.metrics.coughs + 1 end
    if ZombRand(100) < 70 then
        Cold.say(actor, shell, state, kind == "sneeze" and "SNEEZE" or "COUGH", now, "nextExpelBarkMs")
    end
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "cold_" .. kind) end
    return { kind = "idle", intent = "cold_" .. kind, cooldownUntilMs = now + (animated and 1800 or 600) }
end

function Cold.dressPass(shell)
    local inventory, list = shell:getInventory(), shell:getWornItems()
    if inventory == nil or list == nil then return false end
    local group = list:getBodyLocationGroup()
    local items = inventory:getItems()
    local best, bestValue, bestLocation = nil, 0.12, nil
    for index = 0, math.min(items:size(), 80) - 1 do
        local item = items:get(index)
        if item ~= nil and instanceof(item, "Clothing") and not list:contains(item) then
            local value = tonumber(item:getInsulation()) or 0
            local location = item:getBodyLocation()
            if value > bestValue and location ~= nil and list:getItem(location) == nil then
                local clear = true
                for slot = 0, list:size() - 1 do
                    local worn = list:getItemByIndex(slot)
                    local wornLocation = worn ~= nil and list:getLocation(worn) or nil
                    if wornLocation ~= nil and group:isExclusive(location, wornLocation) then clear = false; break end
                end
                if clear then best, bestValue, bestLocation = item, value, location end
            end
        end
    end
    if best == nil then return false end
    list:setItem(bestLocation, best)
    shell:setWornItems(list)
    shell:resetModelNextFrame()
    return true
end

function Cold.dress(actor, shell, state, now)
    if now < state.dressAtMs then return false end
    state.dressAtMs = now + Cold.settings.dressGapMs
    local ok, worn = pcall(Cold.dressPass, shell)
    if ok and worn == true then
        state.warmthH = -10
        Cold.metrics.dressed = Cold.metrics.dressed + 1
        Cold.say(actor, shell, state, "DRESS_WARM", now)
        return true
    end
    return false
end

function Cold.positionOf(shell)
    local ok, x, y, z = pcall(function() return shell:getX(), shell:getY(), shell:getZ() end)
    if not ok or x == nil then return nil end
    return x, y, z
end

function Cold.squareAt(x, y, z)
    local square
    pcall(function() square = getCell():getGridSquare(x, y, z) end)
    return square
end

function Cold.scan(x, y, z, w, now)
    local key = tostring(math.floor(x / 8)) .. ":" .. tostring(math.floor(y / 8)) .. ":" .. tostring(math.floor(z))
    local cached = Cold.fireCache[key]
    if cached ~= nil and now - cached.atMs < Cold.settings.scanTtlMs then return cached.list end
    Cold.metrics.scans = Cold.metrics.scans + 1
    local s = Cold.settings
    local list = {}
    local cell = nil
    pcall(function() cell = getCell() end)
    if cell ~= nil and type(cell.getHeatSourceHighestTemperature) == "function" then
        local cx, cy = math.floor(x / 8) * 8 + 4, math.floor(y / 8) * 8 + 4
        local base = w ~= nil and w.air or 10
        local hits = {}
        for dx = -s.scanRadius, s.scanRadius, s.sampleStep do
            for dy = -s.scanRadius, s.scanRadius, s.sampleStep do
                local ok, value = pcall(cell.getHeatSourceHighestTemperature, cell, base, cx + dx, cy + dy, math.floor(z))
                if ok and tonumber(value) ~= nil and value > base + 3 then
                    hits[#hits + 1] = { x = cx + dx, y = cy + dy, z = math.floor(z), heat = value }
                end
            end
        end
        table.sort(hits, function(left, right) return left.heat > right.heat end)
        for _, hit in ipairs(hits) do
            local near = false
            for _, kept in ipairs(list) do
                if (kept.x - hit.x) ^ 2 + (kept.y - hit.y) ^ 2 <= 36 then near = true; break end
            end
            if not near then list[#list + 1] = hit end
            if #list >= 6 then break end
        end
    end
    local fires = ProjectALife.Campfires
    if fires ~= nil and type(fires.active) == "table" then
        for _, entry in pairs(fires.active) do
            if type(entry) == "table" and tonumber(entry.x) ~= nil and math.floor(tonumber(entry.z) or 0) == math.floor(z) then
                local square = Cold.squareAt(entry.x, entry.y, entry.z)
                local okLit, lit = false, false
                if square ~= nil and type(fires.litSquare) == "function" then okLit, lit = pcall(fires.litSquare, square) end
                if okLit and lit == true then
                    list[#list + 1] = { x = entry.x + 0.5, y = entry.y + 0.5, z = entry.z, heat = 99, exact = true }
                end
            end
        end
    end
    if cached == nil then
        Cold.fireCount = (Cold.fireCount or 0) + 1
        if Cold.fireCount > 256 then Cold.fireCache, Cold.fireCount = {}, 1 end
    end
    Cold.fireCache[key] = { atMs = now, list = list }
    return list
end

function Cold.nearestFire(shell, w, now)
    local x, y, z = Cold.positionOf(shell)
    if x == nil then return nil end
    local best, bestDistance = nil, Cold.settings.seekRadius ^ 2
    for _, fire in ipairs(Cold.scan(x, y, z, w, now)) do
        local distance = (fire.x - x) ^ 2 + (fire.y - y) ^ 2
        if distance < bestDistance then best, bestDistance = fire, distance end
    end
    return best
end

function Cold.spotAround(fire, uid)
    local base = math.floor(Cold.seed(uid, "ring") * 8)
    for ring = 2, 3 do
        for step = 0, 7 do
            local angle = ((base + step) % 8) * math.pi / 4
            local x = math.floor(fire.x + math.cos(angle) * ring)
            local y = math.floor(fire.y + math.sin(angle) * ring)
            local square = Cold.squareAt(x, y, math.floor(fire.z))
            local valid = false
            if square ~= nil then
                pcall(function()
                    valid = square:isFree(false) == true and square:TreatAsSolidFloor() == true
                end)
            end
            local fires = ProjectALife.Campfires
            if valid and fires ~= nil and type(fires.litSquare) == "function" then
                local okLit, lit = pcall(fires.litSquare, square)
                if okLit and lit == true then valid = false end
            end
            if valid then return { x = x + 0.5, y = y + 0.5, z = math.floor(fire.z) } end
        end
    end
    return nil
end

function Cold.groupHolds(actor)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if memory.stance ~= nil and memory.stance ~= "" then return true end
    local ordered = memory.orderedTo
    if type(ordered) == "table" and Cold.nowMs() < (tonumber(ordered.untilMs) or 0) then return true end
    return false
end

function Cold.release(actor, state)
    state.phase, state.target, state.sitAtMs = nil, nil, nil
    local entrances = ProjectALife.Entrances
    if state.claimed and entrances ~= nil and type(entrances.release) == "function" then
        entrances.release(actor.uid)
    end
    state.claimed = false
end

function Cold.chooseTarget(actor, shell, state, context, now)
    local w = Cold.weather(now)
    local fire = Cold.nearestFire(shell, w, now)
    if fire ~= nil then
        local spot = Cold.spotAround(fire, actor.uid)
        if spot ~= nil then return { kind = "fire", x = spot.x, y = spot.y, z = spot.z, fx = fire.x, fy = fire.y } end
    end
    local life = ProjectALife.ModuleIdleLife
    if life == nil or type(life.pickBuilding) ~= "function" then return nil end
    local id, _, building = life.pickBuilding(shell, Cold.settings.buildingRadius)
    if id == nil then return nil end
    local opening, destination = life.interiorSpot(actor, shell, building, now)
    if opening == nil then return nil end
    state.claimed = true
    return { kind = "house", id = id, x = destination.x, y = destination.y, z = destination.z }
end

function Cold.arrived(shell, target)
    local x, y = Cold.positionOf(shell)
    if x == nil then return false end
    if target.kind == "house" then
        local life = ProjectALife.ModuleIdleLife
        local here = life ~= nil and type(life.buildingIdAt) == "function" and life.buildingIdAt(shell) or nil
        return here ~= nil and here == target.id
    end
    local dx, dy = (target.fx or target.x) - x, (target.fy or target.y) - y
    return dx * dx + dy * dy <= 20
end

function Cold.seek(actor, shell, state, context, now, hours)
    local s = Cold.settings
    if Cold.option("coldSeek") == false then return nil end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if Cold.groupHolds(actor) then
        if state.phase ~= nil then Cold.release(actor, state) end
        return nil
    end
    local solo = (tonumber(memory.groupSize) or 1) <= 1
    local lead = solo or memory.groupRole == "leader" or state.chill >= s.freezingAt
    if state.phase == nil then
        if state.chill < s.seekAt or not lead or now < state.seekCooldownMs then return nil end
        local target = Cold.chooseTarget(actor, shell, state, context, now)
        if target == nil then
            state.seekCooldownMs = now + 45000
            Cold.dress(actor, shell, state, now)
            return nil
        end
        state.phase, state.target, state.phaseAtMs = "go", target, now
        Cold.metrics.seeks = Cold.metrics.seeks + 1
        Cold.say(actor, shell, state, "SEEK_WARMTH", now)
    end
    local target = state.target
    if state.phase == "go" then
        if Cold.arrived(shell, target) then
            state.phase, state.phaseAtMs = "stay", now
            Cold.metrics.arrivals = Cold.metrics.arrivals + 1
            Cold.say(actor, shell, state, "WARMING", now)
        elseif now - state.phaseAtMs > s.goMaxMs or state.chill < s.warmAt then
            state.seekCooldownMs = now + s.seekCooldownMs
            Cold.release(actor, state)
            return nil
        else
            return context.startMovement(actor, shell, { x = target.x, y = target.y, z = target.z }, "warmth",
                { pace = "walk", tolerance = 1.2, timeoutMs = 12000,
                    activity = "moving" })
        end
    end
    if state.phase == "stay" then
        if state.chill <= s.warmAt or now - state.phaseAtMs > s.holdMaxMs then
            Cold.metrics.warmed = Cold.metrics.warmed + 1
            state.seekCooldownMs = now + s.seekCooldownMs
            if state.chill <= s.warmAt then Cold.say(actor, shell, state, "WARMED_UP", now) end
            pcall(function()
                local animations = ProjectALife.Animations
                if animations ~= nil then animations.clear(shell) end
            end)
            Cold.release(actor, state)
            return nil
        end
        if target.kind == "fire" and not Cold.arrived(shell, target) then
            state.phase, state.phaseAtMs, state.sitAtMs = "go", now, nil
            return nil
        end
        if ZombRand(100) < 25 then return nil end
        if target.kind == "fire" then
            local settled = true
            pcall(function()
                local animations = ProjectALife.Animations
                if animations == nil then return end
                if state.sitAtMs == nil then
                    if animations.apply(shell, "sit_down") == true then
                        state.sitAtMs = now
                        settled = false
                    end
                elseif now - state.sitAtMs < 2400 then
                    settled = false
                else
                    animations.apply(shell, "warm_hands")
                end
            end)
            if not settled then
                pcall(function() shell:faceLocationF(target.fx or target.x, target.fy or target.y) end)
                if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "warming") end
                return { kind = "idle", intent = "warming", cooldownUntilMs = now + 600 }
            end
        end
        pcall(function() shell:faceLocationF(target.fx or target.x, target.fy or target.y) end)
        if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "warming") end
        return { kind = "idle", intent = "warming", cooldownUntilMs = now + 2500 + ZombRand(1500) }
    end
    return nil
end

function Cold.ambient(actor, shell, state, now)
    local w = Cold.weather(now)
    if w == nil then return false end
    local outside = Cold.outside(shell)
    local event = nil
    if outside and w.snowing then event = "SNOW_FALLING"
    elseif outside and w.rain > 0.5 and w.wind > 25 then event = "WEATHER_STORM"
    elseif outside and w.rain > 0.1 then event = "WEATHER_RAIN"
    elseif outside and w.fog > 0.6 then event = "WEATHER_FOG"
    elseif state.wet >= 0.6 then event = "WET"
    elseif outside and w.ground > 0.3 and w.air < 3 and ZombRand(100) < 60 then event = "SNOW_GROUND"
    elseif state.chill >= Cold.settings.chilledAt and ZombRand(100) < 50 then event = "COLD"
    elseif ZombRand(100) < 60 then event = "SEASON_" .. string.upper(Cold.season()) end
    if event == nil then return false end
    return Cold.say(actor, shell, state, event, now)
end

function Cold.act(actor, shell, state, context, now, hours)
    if state.nextAmbientMs == nil then state.nextAmbientMs = now + 60000 + ZombRand(180000) end
    if now >= state.nextAmbientMs then
        state.nextAmbientMs = now + 240000 + ZombRand(360000)
        Cold.ambient(actor, shell, state, now)
    end
    if Cold.sickNow(state, hours) and now >= state.nextExpelMs then
        state.nextExpelMs = now + Cold.settings.expelMinMs + ZombRand(Cold.settings.expelSpreadMs)
        return Cold.expel(actor, shell, state, context, now)
    end
    if state.level >= 2 and state.phase == nil and ZombRand(100) < 6 then
        local animations = ProjectALife.Animations
        if animations ~= nil then
            local ok, applied = pcall(animations.apply, shell, "shiver")
            if ok and applied == true then
                return { kind = "idle", intent = "cold_shiver", cooldownUntilMs = now + 2000 }
            end
        end
    end
    if state.level >= 1 and state.phase == nil and now >= state.dressAtMs then Cold.dress(actor, shell, state, now) end
    return Cold.seek(actor, shell, state, context, now, hours)
end

function Cold.busy(shell, actor, now)
    local speech = ProjectALife.Speech
    if speech == nil or type(speech.quietReason) ~= "function" then return false end
    local ok, reason = pcall(speech.quietReason, shell, actor, now)
    return ok and reason ~= nil
end

function Cold.step(actor, shell, context, now)
    if not Cold.enabled() then return nil end
    if type(actor) ~= "table" or type(actor.uid) ~= "string" or shell == nil or type(context) ~= "table" then return nil end
    local hours = Cold.hours()
    local state = Cold.stateFor(actor, hours)
    local dt = hours - state.lastH
    if dt < 0 then
        state.lastH = hours
    elseif dt >= Cold.settings.minStepHours then
        state.lastH = hours
        Cold.advance(actor, shell, state, math.min(dt, Cold.settings.maxStepHours), hours, context, now)
    end
    if context.threat ~= nil or Cold.busy(shell, actor, now) then
        if state.phase ~= nil then Cold.release(actor, state) end
        return nil
    end
    return Cold.act(actor, shell, state, context, now, hours)
end

function Cold.view(record)
    local uid = type(record) == "table" and record.uid or nil
    local state = uid ~= nil and Cold.states[uid] or nil
    local hours = Cold.hours()
    if state == nil then
        local saved = type(record) == "table" and type(record.memory) == "table" and record.memory.cold or nil
        if type(saved) ~= "table" then return "well" end
        if (tonumber(saved.s) or 0) > hours then return "sick" end
        local chill = tonumber(saved.c) or 0
        if chill >= Cold.settings.freezingAt then return "freezing" end
        if chill >= Cold.settings.chilledAt then return "chilled" end
        return "well"
    end
    if Cold.sickNow(state, hours) then return "sick" end
    if state.chill >= Cold.settings.freezingAt then return "freezing" end
    if state.chill >= Cold.settings.chilledAt then return "chilled" end
    return "well"
end

return Cold
