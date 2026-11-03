local D = {}
local pieces = {}
local tracked = {}
local nextCheck = 0
local flights = {}
local serial = 0
local bleeders = {}
local bleeding = {}
local particles = {}
local bloodSprite
local bloodInstance
local launch
local nextBleed = 0
local bleedWindow = -1
local bloodWindow = -1
local bloodSpent = 0
local burstSpent = 0
local canPass

local hair = {
    M = {
        Picard = true,
        CrewCut = true,
        Baldspot = true,
        Recede = true,
        Hat = true,
        Messy = true,
        Short = true,
        Donny = true,
        Mullet = true,
        Metal = true,
        Fabian = true,
        PonyTail = true,
        FabianCurly = true,
        MessyCurly = true,
        MulletCurly = true,
        ShortAfroCurly = true,
        ShortHatCurly = true,
        CentreParting = true,
        LeftParting = true,
        RightParting = true,
        CentrePartingLong = true,
        Cornrows = true,
        Fresh = true,
        LibertySpikes = true,
        MohawkFan = true,
        MohawkShort = true,
        MohawkSpike = true,
        MohawkFlat = true,
        FlatTop = true,
        Buffont = true,
        GreasedBack = true,
        Spike = true,
        LongBraids = true,
        PonyTailBraids = true,
        LongBraids02 = true,
        Braids = true,
        Grungey = true,
        GrungeyBehindEars = true,
        HatLong = true,
        HatLongBraided = true,
        HatLongCurly = true,
    },
    F = {
        Demi = true,
        Spike = true,
        Hat = true,
        OverEye = true,
        Bob = true,
        Bun = true,
        Back = true,
        Long = true,
        Kate = true,
        Long2 = true,
        PonyTail = true,
        Longcurly = true,
        Long2curly = true,
        BobCurly = true,
        BunCurly = true,
        HatCurly = true,
        KateCurly = true,
        OverEyeCurly = true,
        RachelCurly = true,
        ShortCurly = true,
        Rachel = true,
        CentreParting = true,
        CentrePartingLong = true,
        LeftParting = true,
        RightParting = true,
        TopCurls = true,
        Grungey = true,
        GrungeyParted = true,
        Cornrows = true,
        MohawkFan = true,
        MohawkShort = true,
        MohawkSpike = true,
        LibertySpikes = true,
        MohawkFlat = true,
        FlatTop = true,
        Buffont = true,
        GreasedBack = true,
        Fresh = true,
        Grungey02 = true,
        GrungeyBehindEars = true,
        OverLeftEye = true,
        LongBraids = true,
        LongBraids02 = true,
        Braids = true,
        PonyTailBraids = true,
        HatLong = true,
        HatLongCurly = true,
        HatLongBraided = true,
    },
}

local function options()
    return SandboxVars and SandboxVars.ZombieDismemberment or {}
end

local function limit(value, fallback, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or fallback))
end

local function enabled(item, opts)
    if opts.Enabled == false then return false end
    if item:getFullType():sub(1, 33) == "ZombieDismemberment.ZD_Drop_Gore_" then
        return opts.HeadBurst == true and limit(opts.HeadGoreCount, 6, 0, 8) > 0
    end
    if item:getFullType():sub(1, 33) == "ZombieDismemberment.ZD_Drop_Head_" then
        return opts.HeadDrops == true and opts.DropParts == true and (opts.DropPerZombie or 3) ~= 1
    end
    if item:getFullType() == "ZombieDismemberment.ZD_Drop_Cloth" then
        return opts.DropCloth == true
    end
    return opts.DropParts == true and (opts.DropPerZombie or 3) ~= 1
end

local function bloodBudget(opts, now, burst)
    local window = math.floor(now / 1000)
    if window ~= bloodWindow then bloodWindow, bloodSpent, burstSpent = window, 0, 0 end
    local total = math.floor(limit(opts.BloodBudget, 96, 0, 256))
    local maximum = total
    if not burst and (opts.HeadBurst or opts.NeckBlood) then
        local count = opts.HeadBurst and math.floor(limit(opts.HeadBurstCount, 32, 0, 64)) or 0
        local reserve = math.min(math.max(count, opts.NeckBlood and 6 or 0), math.floor(total / 3))
        maximum = total - math.max(0, reserve - burstSpent)
    end
    if bloodSpent >= maximum then return false end
    bloodSpent = bloodSpent + 1
    if burst then burstSpent = burstSpent + 1 end
    return true
end

local function bloodParticle(sq, x, y, z, dx, dy, opts, now, burst, priority)
    local maximum = burst == true and 64 or (burst and 32 or 16)
    local particle
    if priority then
        if limit(opts.BloodBudget, 96, 0, 256) < 1 then return end
        bloodBudget(opts, now, burst)
        if #particles >= maximum then
            local oldest = 1
            for i = 1, #particles do
                if not particles[i].priority then oldest = i; break end
            end
            particle = table.remove(particles, oldest)
        end
    elseif #particles >= maximum or not bloodBudget(opts, now, burst) then
        return
    end
    if not bloodSprite then
        bloodSprite = IsoSprite.new()
        bloodSprite:setFromCache("Giblet", "00", 3)
        bloodInstance = bloodSprite:newInstance()
    end
    local alpha = burst and 0.9 or 0.6
    local duration = burst == "neck" and 650 or (burst and limit(opts.HeadBurstDuration, 900, 250, 1500) or 500)
    particle = particle or {}
    particle.sq, particle.x, particle.y, particle.z = sq, x, y, z
    particle.startX, particle.startY, particle.startZ = x, y, z
    particle.dx, particle.dy = dx, dy
    particle.born, particle.burst, particle.duration = now, burst, duration
    particle.priority = priority
    if particle.color then particle.color:set(1, 1, 1, alpha)
    else particle.color = ColorInfo.new(1, 1, 1, alpha) end
    particle.scale = burst == true and limit(opts.HeadBurstScale, 3, 1, 5) or 1
    particles[#particles + 1] = particle
end

local function bloodMark(sq, x, y, opts, now)
    if not bloodBudget(opts, now) then return false end
    addBloodSplat(sq, 1, math.max(0.001, math.min(0.999, x - sq:getX())),
        math.max(0.001, math.min(0.999, y - sq:getY())))
    return true
end

local function frozen(md)
    return md.bSZZFrozen == true or md.bSZZGroundFrozen == true or md.bFrozenBySZZ == true
end

local function bloodPatch(sq, x, y, radius, md, opts, now, fromX, fromY, maximum)
    local amount = math.min(md.ZD_BleedMarks, math.floor(limit(opts.BleedAmount, 12, 1, 16)))
    if md.ZD_DropPoolStarted then
        amount = math.min(amount, math.max(1, math.ceil(limit(opts.DropPoolMarks, 9, 1, 24) / 3)))
    end
    if maximum then amount = math.min(amount, maximum) end
    local emitted = 0
    for i = 1, amount do
        local angle = (md.ZD_BleedMarks + i) * 2.399963
        local px, py = x, y
        local spread
        if fromX then
            local t = i / (amount + 1)
            px, py = fromX + (x - fromX) * t, fromY + (y - fromY) * t
            spread = radius * 0.5
        elseif i % 2 == 1 then
            spread = radius * 0.12
        else
            spread = radius * math.sqrt(((md.ZD_BleedMarks + i * 17) % 31 + 1) / 32)
        end
        px, py = px + math.cos(angle) * spread, py + math.sin(angle) * spread
        local target = getCell():getGridSquare(math.floor(px), math.floor(py), sq:getZ())
        if canPass(sq, target) then
            if not bloodMark(target, px, py, opts, now) then break end
            emitted = emitted + 1
        end
    end
    md.ZD_BleedMarks = md.ZD_BleedMarks - emitted
    return emitted > 0
end

local function observePiece(obj, opts, now)
    if bleeding[obj] then return end
    local item = obj:getItem()
    if item:getFullType() == "ZombieDismemberment.ZD_Drop_Cloth" then return end
    local md = item:getModData()
    local duration = limit(opts.DropPoolTime, 4, 0, 15)
    if not md.ZD_DropPoolStarted then
        md.ZD_DropPoolStarted = true
        if opts.DropPools and duration > 0 and now - md.ZD_DropBorn < duration * 1000 then
            md.ZD_BleedUntil = now + duration * 1000
            md.ZD_BleedMarks = math.floor(limit(opts.DropPoolMarks, 9, 0, 24))
        end
        obj:getSquare():flagForHotSave()
    end
    if opts.Enabled == false or not opts.DropPools or duration == 0
        or limit(opts.DropPoolMarks, 9, 0, 24) == 0 or type(md.ZD_BleedUntil) ~= "number"
        or md.ZD_BleedUntil <= now or (md.ZD_BleedMarks or 0) < 1
        or #bleeders >= math.floor(limit(opts.BloodMaxZombies, 16, 0, 64)) then return end
    bleeders[#bleeders + 1] = {object = obj, untilTime = md.ZD_BleedUntil, nextMark = now}
    bleeding[obj] = true
end

local function bleedPosition(zombie, md)
    local x, y = zombie:getX(), zombie:getY()
    if zombie:isOnFloor() and (md.ZD_LegL == "WholeLeg" or md.ZD_LegR == "WholeLeg") then
        local fx, fy = zombie:getForwardDirectionX(), zombie:getForwardDirectionY()
        local side = md.ZD_LegL == md.ZD_LegR and 0 or (md.ZD_LegL == "WholeLeg" and 0.12 or -0.12)
        x, y = x - fx * 0.45 - fy * side, y - fy * 0.45 + fx * side
    end
    return x, y
end

function D.observe(zombie)
    if isClient() or isServer() then return end
    local opts = options()
    if opts.Enabled == false or not opts.CrawlBlood and not opts.PoolBlood or bleeding[zombie]
        or limit(opts.BleedTime, 20, 0, 120) == 0 or limit(opts.BleedMarks, 768, 0, 2048) == 0 then return end
    local md = zombie:getModData()
    if type(md.ZD_BleedUntil) ~= "number" or md.ZD_BleedUntil <= getTimestampMs()
        or (md.ZD_BleedMarks or 0) < 1 or zombie:isDead() or frozen(md) then return end
    if #bleeders >= math.floor(limit(opts.BloodMaxZombies, 16, 0, 64)) then return end
    local x, y = bleedPosition(zombie, md)
    local entry = {zombie = zombie, x = x, y = y, z = zombie:getZ(), untilTime = md.ZD_BleedUntil, nextMark = getTimestampMs(),
        lastX = x, lastY = y}
    bleeders[#bleeders + 1] = entry
    bleeding[zombie] = true
end

function D.blood(zombie, limb, kind, attacker)
    if isClient() or isServer() then return end
    local opts = options()
    if opts.Enabled == false or not opts.CrawlBlood and not opts.PoolBlood and not opts.HeadBurst and not opts.NeckBlood and not opts.CutBlood then return end
    local now = getTimestampMs()
    local sq = zombie:getSquare()
    if not sq or getCell():getGridSquare(zombie:getX(), zombie:getY(), sq:getZ()) ~= sq then return end
    local md = zombie:getModData()
    if frozen(md) then return end
    if limb == "Head" then
        local count = math.floor(limit(opts.HeadBurstCount, 32, 0, 64))
        local core = math.min(6, count)
        local height = zombie:isOnFloor() and 0.12 or 0.6
        if opts.HeadBurst and kind == "Shotgun" then
            for i = 1, core do
                local angle = i * math.pi * 2 / core
                local distance = 0.7 + (i % 5) * 0.14
                bloodParticle(sq, zombie:getX(), zombie:getY(), sq:getZ() + height,
                    math.cos(angle) * distance, math.sin(angle) * distance, opts, now, true, true)
            end
        end
        if opts.NeckBlood then
            local fx, fy = zombie:getForwardDirectionX(), zombie:getForwardDirectionY()
            local height = zombie:isOnFloor() and 0.12 or 0.65
            local x = zombie:getX() + (zombie:isOnFloor() and fx * 0.35 or 0)
            local y = zombie:getY() + (zombie:isOnFloor() and fy * 0.35 or 0)
            local origin = getCell():getGridSquare(math.floor(x), math.floor(y), sq:getZ())
            if canPass(sq, origin) then
                for i = 1, 6 do
                    local spread = (i - 3.5) * 0.04
                    bloodParticle(origin, x, y, sq:getZ() + height,
                        fx * 0.16 - fy * spread, fy * 0.16 + fx * spread, opts, now, "neck")
                end
            end
        end
        if not opts.HeadBurst or kind ~= "Shotgun" then return end
        if opts.DropFlight ~= false and attacker then
            local count = math.floor(limit(opts.HeadGoreCount, 6, 0, 8))
            local maximum = math.floor(limit(opts.DropMax, 24, 0, 128))
            for i = 1, count do
                if #flights >= 8 or #pieces + #flights >= maximum or not bloodBudget(opts, now, true) then break end
                local item = instanceItem("ZombieDismemberment.ZD_Drop_Gore_" .. ((i - 1) % 3))
                if item then
                    item:getModData().ZD_DropBorn = now
                    launch(item, zombie, attacker, kind, nil, "Gore", opts, now)
                end
            end
        end
        for i = core + 1, count do
            local angle = (i - core - 0.5) * math.pi * 2 / (count - core)
            local distance = 0.7 + (i % 5) * 0.14
            bloodParticle(sq, zombie:getX(), zombie:getY(), sq:getZ() + height,
                math.cos(angle) * distance, math.sin(angle) * distance, opts, now, true)
        end
    else
        local cutMarks = math.floor(limit(opts.CutBloodMarks, 12, 0, 64))
        if opts.CutBlood and cutMarks > 0 then
            local marks = {ZD_BleedMarks = cutMarks}
            while marks.ZD_BleedMarks > 0 do
                if not bloodPatch(sq, zombie:getX(), zombie:getY(), 0.18, marks, opts, now) then break end
            end
            local height = zombie:isOnFloor() and 0.1 or 0.55
            for i = 1, 3 do
                local angle = i * math.pi * 2 / 3
                bloodParticle(sq, zombie:getX(), zombie:getY(), sq:getZ() + height,
                    math.cos(angle) * 0.15, math.sin(angle) * 0.15, opts, now)
            end
        end
        if (opts.CrawlBlood or opts.PoolBlood) and not zombie:isDead()
            and limit(opts.BleedTime, 20, 0, 120) > 0 and limit(opts.BleedMarks, 768, 0, 2048) > 0 then
            if md.ZD_BleedUntil == nil then
                md.ZD_BleedUntil = now + limit(opts.BleedTime, 20, 0, 120) * 1000
                md.ZD_BleedMarks = math.floor(limit(opts.BleedMarks, 768, 0, 2048))
            end
            D.observe(zombie)
        end
    end
end

local function updateBlood(opts, now)
    for i = #particles, 1, -1 do
        local particle = particles[i]
        local sq = particle.sq
        local t = (now - particle.born) / particle.duration
        if t >= 1 or opts.Enabled == false
            or particle.burst == "neck" and not opts.NeckBlood
            or particle.burst == true and not opts.HeadBurst
            or not opts.DropBlood and not opts.HeadBurst and not opts.NeckBlood and not opts.CutBlood
            or getCell():getGridSquare(sq:getX(), sq:getY(), sq:getZ()) ~= sq then
            table.remove(particles, i)
        else
            local x, y = particle.startX + particle.dx * t, particle.startY + particle.dy * t
            if particle.burst then
                local target = getCell():getGridSquare(math.floor(x), math.floor(y), sq:getZ())
                if canPass(sq, target) then sq, particle.sq = target, target end
            end
            particle.x = math.max(sq:getX() + 0.001, math.min(sq:getX() + 0.999, x))
            particle.y = math.max(sq:getY() + 0.001, math.min(sq:getY() + 0.999, y))
            local rise = (particle.burst == "neck" and 0.3 or (particle.burst and 0.18 or 0)) * 4 * t * (1 - t)
            particle.z = math.max(sq:getApparentZ(particle.x - sq:getX(), particle.y - sq:getY()), particle.startZ + rise - 0.7 * t * t)
            particle.color:set(1, 1, 1, (particle.burst and 0.9 or 0.6) * (1 - t))
        end
    end
    if now < nextBleed then return end
    nextBleed = now + 250
    local window = math.floor(now / 1000)
    if window ~= bleedWindow then
        bleedWindow = window
        if #bleeders > 1 then table.insert(bleeders, 1, table.remove(bleeders)) end
    end
    local maximum = math.floor(limit(opts.BloodMaxZombies, 16, 0, 64))
    for i = #bleeders, 1, -1 do
        local entry = bleeders[i]
        if entry.object then
            local obj = entry.object
            local item = obj:getItem()
            local md = item:getModData()
            local sq = obj:getSquare()
            if opts.Enabled == false or not opts.DropPools or not enabled(item, opts) or i > maximum
                or limit(opts.DropPoolTime, 4, 0, 15) == 0 or limit(opts.DropPoolMarks, 9, 0, 24) == 0
                or md.ZD_BleedUntil ~= entry.untilTime or type(md.ZD_BleedMarks) ~= "number"
                or now >= entry.untilTime or md.ZD_BleedMarks < 1 or item:getWorldItem() ~= obj or not sq
                or getCell():getGridSquare(sq:getX(), sq:getY(), sq:getZ()) ~= sq then
                bleeding[obj] = nil
                table.remove(bleeders, i)
            elseif now >= entry.nextMark and sq:getFloor() then
                local duration = limit(opts.DropPoolTime, 4, 1, 15) * 1000
                local quota = limit(opts.DropPoolMarks, 9, 1, 24)
                local growth = math.max(0, math.min(1, math.max(1 - (entry.untilTime - now) / duration, 1 - md.ZD_BleedMarks / quota)))
                local radius = limit(opts.PoolRadius, 0.8, 0.15, 1.0) * 0.5 * (0.25 + 0.75 * growth)
                if bloodPatch(sq, sq:getX() + obj:getOffX(), sq:getY() + obj:getOffY(), radius, md, opts, now) then
                    entry.nextMark = now + limit(opts.BleedInterval, 250, 250, 3000)
                    sq:flagForHotSave()
                end
            end
        else
            local zombie = entry.zombie
            local md = zombie:getModData()
            local sq = zombie:getSquare()
            if opts.Enabled == false or not opts.CrawlBlood and not opts.PoolBlood or i > maximum or zombie:isDead() or frozen(md)
                or limit(opts.BleedTime, 20, 0, 120) == 0 or limit(opts.BleedMarks, 768, 0, 2048) == 0
                or md.ZD_BleedUntil ~= entry.untilTime or type(md.ZD_BleedMarks) ~= "number"
                or now >= entry.untilTime or md.ZD_BleedMarks < 1 or not sq
                or getCell():getGridSquare(zombie:getX(), zombie:getY(), sq:getZ()) ~= sq then
                bleeding[zombie] = nil
                table.remove(bleeders, i)
            else
                local x, y = bleedPosition(zombie, md)
                local z = zombie:getZ()
                local dx, dy = x - entry.x, y - entry.y
                local distance = dx * dx + dy * dy
                local stepX, stepY = x - entry.lastX, y - entry.lastY
                entry.lastX, entry.lastY = x, y
                if z ~= entry.z or distance > 9 then
                    entry.x, entry.y, entry.z = x, y, z
                    entry.nextMark = now + limit(opts.BleedInterval, 250, 250, 3000)
                elseif now >= entry.nextMark and sq:getFloor() then
                    local spacing = limit(opts.CrawlSpacing, 0.2, 0.1, 1.0)
                    local moving = opts.CrawlBlood and (zombie:isCrawling() or zombie:isOnFloor()) and distance >= spacing * spacing
                    local pooling = opts.PoolBlood and zombie:isOnFloor() and stepX * stepX + stepY * stepY < 0.01
                    if moving or pooling then
                        local radius = 0.28
                        if pooling and not moving then
                            local duration = limit(opts.BleedTime, 20, 1, 120) * 1000
                            local quota = limit(opts.BleedMarks, 768, 1, 2048)
                            local growth = math.max(0, math.min(1, math.max(1 - (entry.untilTime - now) / duration, 1 - md.ZD_BleedMarks / quota)))
                            radius = limit(opts.PoolRadius, 0.8, 0.15, 1.0) * (0.25 + 0.75 * growth)
                        end
                        local fromX, fromY
                        if moving then fromX, fromY = entry.x, entry.y end
                        local interval = limit(opts.BleedInterval, 250, 250, 3000)
                        local remaining = entry.untilTime - now
                        local quota = md.ZD_BleedMarks
                        local amount = math.max(1, math.floor(quota * interval / remaining))
                        local origin = getCell():getGridSquare(math.floor(x), math.floor(y), sq:getZ())
                        if canPass(sq, origin) and bloodPatch(origin, x, y, radius, md, opts, now, fromX, fromY, amount) then
                            local emitted = quota - md.ZD_BleedMarks
                            entry.nextMark = now + math.max(interval, remaining * emitted / quota)
                            if moving then entry.x, entry.y = x, y end
                        end
                    elseif not opts.CrawlBlood or not zombie:isCrawling() and not zombie:isOnFloor() then
                        entry.x, entry.y = x, y
                    end
                end
            end
        end
    end
end

local function ground(obj)
    local sq = obj:getSquare()
    local x, y = obj:getOffX(), obj:getOffY()
    obj:setOffset(x, y, math.max(0, sq:getApparentZ(x, y) - sq:getZ()))
    obj:getItem():getModData().ZD_DropFlying = nil
    sq:flagForHotSave()
end

local function distant(x, y, distance)
    if distance == 0 then return false end
    local hasPlayer = false
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player then
            hasPlayer = true
            local dx = player:getX() - x
            local dy = player:getY() - y
            if dx * dx + dy * dy <= distance * distance then return false end
        end
    end
    return hasPlayer
end

local function remove(obj)
    local sq = obj:getSquare()
    local item = obj:getItem()
    if not sq or item:getWorldItem() ~= obj or not sq:getWorldObjects():contains(obj)
        or getCell():getGridSquare(sq:getX(), sq:getY(), sq:getZ()) ~= sq then return end
    sq:transmitRemoveItemFromSquare(obj)
    obj:removeFromWorld()
    obj:removeFromSquare()
    obj:setSquare(nil)
    item:setWorldItem(nil)
end

local function room(maximum, born)
    while #pieces + #flights >= maximum do
        local obj = pieces[1]
        local flight = flights[1]
        local pieceBorn = obj and obj:getItem():getModData().ZD_DropBorn
        local flightBorn = flight and flight.item:getModData().ZD_DropBorn
        if flightBorn and (not pieceBorn or flightBorn < pieceBorn) then
            if born and born < flightBorn then return false end
            table.remove(flights, 1)
        else
            if born and born < pieceBorn then return false end
            table.remove(pieces, 1)
            tracked[obj] = nil
            remove(obj)
        end
    end
    return true
end

local function expired(obj, opts, now)
    local item = obj:getItem()
    if not enabled(item, opts) then return true end
    local life = limit(opts.DropLife, 180, 0, 3600)
    if life > 0 and now - item:getModData().ZD_DropBorn >= life * 1000 then return true end
    return distant(obj:getX(), obj:getY(), limit(opts.DropDistance, 50, 0, 200))
end

local function clean(opts, now)
    if now < nextCheck then return end
    nextCheck = now + 1000
    local count = #pieces
    local write = 1
    for i = 1, count do
        local obj = pieces[i]
        local item = obj:getItem()
        local sq = obj:getSquare()
        local live = sq and item:getWorldItem() == obj and sq:getWorldObjects():contains(obj)
        if live and getCell():getGridSquare(sq:getX(), sq:getY(), sq:getZ()) ~= sq then live = false end
        if not live or expired(obj, opts, now) then
            if live then remove(obj) end
            tracked[obj] = nil
        else
            observePiece(obj, opts, now)
            pieces[write] = obj
            write = write + 1
        end
    end
    for i = write, count do pieces[i] = nil end
    room(math.floor(limit(opts.DropMax, 24, 0, 128)) + 1)
end

local function track(obj, opts, now)
    if tracked[obj] then return end
    local item = obj:getItem()
    if not item or item:getFullType():sub(1, 28) ~= "ZombieDismemberment.ZD_Drop_" then return end
    local born = item:getModData().ZD_DropBorn
    if type(born) ~= "number" then return end
    if item:getModData().ZD_DropFlying then ground(obj) end
    if expired(obj, opts, now) then remove(obj); return end
    local maximum = math.floor(limit(opts.DropMax, 24, 0, 128))
    if maximum == 0 then remove(obj); return end
    if not room(maximum, born) then remove(obj); return end
    local i = #pieces + 1
    while i > 1 and pieces[i - 1]:getItem():getModData().ZD_DropBorn > born do
        pieces[i] = pieces[i - 1]
        i = i - 1
    end
    pieces[i] = obj
    tracked[obj] = true
    obj:setNoPicking(true)
    obj:setOutlineOnMouseover(false)
    observePiece(obj, opts, now)
end

local function floor(sq)
    return sq and sq:getFloor() and sq:TreatAsSolidFloor() and not sq:isSolid() and not sq:isSolidTrans()
end

canPass = function(from, to)
    if not floor(to) then return false end
    if from == to then return true end
    local dx, dy = to:getX() - from:getX(), to:getY() - from:getY()
    if math.abs(dx) > 1 or math.abs(dy) > 1 or from:isBlockedTo(to) then return false end
    if dx ~= 0 and dy ~= 0 then
        local cell = getCell()
        local a = cell:getGridSquare(from:getX() + dx, from:getY(), from:getZ())
        local b = cell:getGridSquare(from:getX(), from:getY() + dy, from:getZ())
        return floor(a) and floor(b) and not from:isBlockedTo(a) and not from:isBlockedTo(b)
            and not a:isBlockedTo(to) and not b:isBlockedTo(to)
    end
    return true
end

local function land(flight, opts, now)
    if flight.gore then return end
    local sq = getCell():getGridSquare(flight.x, flight.y, flight.z)
    if sq ~= flight.sq or not floor(sq) or not enabled(flight.item, opts) then return end
    local item = flight.item
    if item:getWorldItem() then return end
    local x = math.max(0.001, math.min(0.999, flight.x - sq:getX()))
    local y = math.max(0.001, math.min(0.999, flight.y - sq:getY()))
    item:setWorldZRotation(flight.rotation)
    sq:AddWorldInventoryItem(item, x, y, math.max(0, sq:getApparentZ(x, y) - sq:getZ()), false)
    track(item:getWorldItem(), opts, now)
end

launch = function(item, zombie, attacker, kind, side, limb, opts, now)
    if not attacker or limb == "Cloth" then return false end
    local dx = zombie:getX() - attacker:getX()
    local dy = zombie:getY() - attacker:getY()
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return false end
    local sq = zombie:getSquare()
    if not floor(sq) then return false end
    if distant(zombie:getX(), zombie:getY(), limit(opts.DropDistance, 50, 0, 200)) then return true end
    if #flights >= 8 then
        if limb == "Gore" then return true end
        land(table.remove(flights, 1), opts, now)
    end
    if not room(math.floor(limit(opts.DropMax, 24, 0, 128)), now) then return true end
    serial = (serial + 1) % 1024
    local seed = ((serial * 37 + math.floor(zombie:getX()) * 11
        + math.floor(zombie:getY()) * 7 + (side == "R" and 13 or 0)) % 101 + 101) % 101 / 100
    local angle = (seed - 0.5) * 0.55
    local cos, sin = math.cos(angle), math.sin(angle)
    dx, dy = (dx * cos - dy * sin) / length, (dx * sin + dy * cos) / length
    local shotgun = kind == "Shotgun"
    local distance = shotgun and (1.6 + seed * 0.65) or (0.5 + seed * 0.4)
    if limb == "Leg" then distance = distance * 0.8 end
    if limb == "Gore" then
        angle = serial * 2.399963
        dx, dy = math.cos(angle), math.sin(angle)
        distance = 0.7 + seed * 0.9
    end
    local height = zombie:isOnFloor() and 0.08 or ((limb == "Head" or limb == "Gore") and 0.65 or (limb == "Leg" and 0.18 or 0.33))
    local x, y = zombie:getX(), zombie:getY()
    flights[#flights + 1] = {
        item = item, gore = limb == "Gore", sq = sq, startX = x, startY = y, x = x, y = y, z = sq:getZ(),
        dx = dx * distance, dy = dy * distance, height = height, drawZ = height + math.max(0, sq:getApparentZ(x - sq:getX(), y - sq:getY()) - sq:getZ()),
        arc = limb == "Gore" and 0.4 or (shotgun and 0.28 or 0.16),
        duration = limb == "Gore" and 0.9 or (shotgun and 0.7 or 0.55),
        time = 0, wait = 0, rotation = now % 360, startRotation = now % 360,
        spin = (seed < 0.5 and -1 or 1) * (160 + seed * 220),
        nextBlood = 0.15,
    }
    return true
end

local function updateFlights(opts, now)
    if #flights == 0 then return end
    local dt = math.max(0, math.min(0.05, getGameTime():getRealworldSecondsSinceLastUpdate()))
    local life = limit(opts.DropLife, 180, 0, 3600)
    for i = #flights, 1, -1 do
        local flight = flights[i]
        if getCell():getGridSquare(flight.x, flight.y, flight.z) ~= flight.sq
            or not enabled(flight.item, opts)
            or life > 0 and now - flight.item:getModData().ZD_DropBorn >= life * 1000 then
            table.remove(flights, i)
        elseif opts.DropFlight == false then
            table.remove(flights, i)
            land(flight, opts, now)
        elseif not flight.drawn then
            flight.wait = flight.wait + dt
            if flight.wait >= 0.5 then
                table.remove(flights, i)
                land(flight, opts, now)
            end
        else
            flight.drawn = false
            flight.wait = 0
            flight.time = math.min(flight.duration, flight.time + dt)
            local t = flight.time / flight.duration
            local x, y = flight.startX + flight.dx * t, flight.startY + flight.dy * t
            local sq = getCell():getGridSquare(x, y, flight.z)
            if not canPass(flight.sq, sq) then
                table.remove(flights, i)
                land(flight, opts, now)
            else
                flight.sq, flight.x, flight.y = sq, x, y
                flight.rotation = ((flight.startRotation + flight.spin * t) % 360 + 360) % 360
                flight.drawZ = math.max(0, sq:getApparentZ(x - sq:getX(), y - sq:getY()) - sq:getZ())
                    + flight.height * (1 - t) + 4 * flight.arc * t * (1 - t)
                if not flight.gore and opts.DropBlood and flight.time >= flight.nextBlood then
                    flight.nextBlood = flight.nextBlood + 0.2
                    bloodParticle(sq, x, y, flight.z + flight.drawZ, flight.dx * 0.04, flight.dy * 0.04, opts, now)
                    bloodMark(sq, x, y, opts, now)
                end
                if t == 1 then
                    table.remove(flights, i)
                    land(flight, opts, now)
                end
            end
        end
    end
end

function D.spawn(zombie, limb, side, cut, previous, attacker, kind)
    if isClient() or isServer() then return end
    local opts = options()
    if opts.Enabled == false or limit(opts.DropMax, 24, 0, 128) < 1 then return end
    local itemType
    local headModel, headColor
    if limb == "Cloth" then
        if not opts.DropCloth then return end
        itemType = "ZombieDismemberment.ZD_Drop_Cloth"
    else
        if not opts.DropParts or (opts.DropPerZombie or 3) == 1
            or opts.DropPerZombie == 2 and zombie:getModData().ZD_DropMade then return end
        local part
        if limb == "Arm" and (side == "L" or side == "R") then
            if cut == "ForeArm" and not previous then part = "Fore" end
            if cut == "UpperArm" and previous ~= "UpperArm" then
                part = previous == "ForeArm" and "Upper" or "Arm"
            end
        elseif limb == "Head" and cut == "Decapitated" and not previous and opts.HeadDrops and kind == "Sword" then
            part = "Head"
        elseif limb == "Leg" and cut == "WholeLeg" and not previous
            and (side == "L" or side == "R") then
            part = "Leg"
        end
        if not part then return end
        local visual = zombie:getHumanVisual()
        local skin = visual:getSkinTexture()
        local family, level = skin:match("ZedBody0([1-4])_level([1-3])$")
        if not family then return end
        local index = (tonumber(family) - 1) * 3 + tonumber(level) - 1
        if part == "Head" and opts.HeadHair then
            local sex = zombie:isFemale() and "F" or "M"
            local style = visual:getHairModel()
            if hair[sex][style] then
                headModel = "ZombieDismemberment.ZDDrop_Hair_" .. sex .. "_" .. style .. "_" .. index
                headColor = visual:getHairColor()
            end
        end
        itemType = "ZombieDismemberment.ZD_Drop_" .. part .. (part == "Head" and "" or side)
            .. (zombie:isFemale() and "_F_" or "_M_") .. index
    end
    local sq = zombie:getSquare()
    if not sq or not sq:getFloor() then return end
    local worldX, worldY = zombie:getX(), zombie:getY()
    if limb == "Cloth" then
        for i = 1, 4 do
            local dx = i == 1 and 0.9 or (i == 3 and -0.9 or 0)
            local dy = i == 2 and 0.9 or (i == 4 and -0.9 or 0)
            local other = getCell():getGridSquare(worldX + dx, worldY + dy, sq:getZ())
            if canPass(sq, other) then
                sq, worldX, worldY = other, worldX + dx, worldY + dy
                break
            end
        end
    end
    local item = instanceItem(itemType)
    if not item then return end
    if headModel then
        item:setWorldStaticModel(headModel)
        item:setColorRed(headColor:getRedFloat())
        item:setColorGreen(headColor:getGreenFloat())
        item:setColorBlue(headColor:getBlueFloat())
        item:setCustomColor(true)
    end
    local now = getTimestampMs()
    item:getModData().ZD_DropBorn = now
    item:setWorldZRotation(now % 360)
    local x = math.max(0.001, math.min(0.999, worldX - sq:getX()))
    local y = math.max(0.001, math.min(0.999, worldY - sq:getY()))
    clean(opts, now)
    if opts.DropFlight ~= false and launch(item, zombie, attacker, kind, side, limb, opts, now) then
        local made = flights[#flights] and flights[#flights].item == item
        if limb ~= "Cloth" and made then zombie:getModData().ZD_DropMade = true end
        return made == true
    end
    sq:AddWorldInventoryItem(item, x, y, math.max(0, sq:getApparentZ(x, y) - sq:getZ()), false)
    track(item:getWorldItem(), opts, now)
    if limb ~= "Cloth" and item:getWorldItem() then zombie:getModData().ZD_DropMade = true end
    return item:getWorldItem() ~= nil
end

local function isPiece(item)
    return item and item:getFullType():sub(1, 28) == "ZombieDismemberment.ZD_Drop_"
end

local function filterGrabMenu(context)
    for i = #context.options, 1, -1 do
        local option = context.options[i]
        local remove = false
        if option.subOption then
            local sub = context:getSubMenu(option.subOption)
            if sub and #sub.options > 0 then
                filterGrabMenu(sub)
                remove = #sub.options == 0
            end
        end
        local callback, field = option.onSelect, "param1"
        if callback == ISContextMenu.onGetUpAndThen then callback, field = option.param1, "param3" end
        if callback == ISWorldObjectContextMenu.onGrabWItem then
            local obj = option[field]
            remove = obj and isPiece(obj:getItem())
        elseif callback == ISWorldObjectContextMenu.onGrabAllWItems or callback == ISWorldObjectContextMenu.onGrabHalfWItems then
            local kept = {}
            for _, obj in ipairs(option[field]) do
                if not isPiece(obj:getItem()) then kept[#kept + 1] = obj end
            end
            option[field] = kept
            remove = #kept == 0
        end
        if remove then
            table.insert(context.optionPool, option)
            table.remove(context.options, i)
            context.numOptions = context.numOptions - 1
            for n = i, #context.options do context.options[n].id = n end
            context:calcHeight()
        end
    end
end

local function adopt(item)
    if isClient() or isServer() then return end
    if item:getFullType():sub(1, 28) ~= "ZombieDismemberment.ZD_Drop_"
        or type(item:getModData().ZD_DropBorn) ~= "number" then return end
    local obj = item:getWorldItem()
    if not obj then return end
    local opts = options()
    local now = getTimestampMs()
    clean(opts, now)
    track(obj, opts, now)
end

if not isClient() and not isServer() then
    require "TimedActions/ISDropWorldItemAction"
    require "TimedActions/ISTransferAction"
    require "TimedActions/ISDropVehicleItemAction"
    local complete = ISDropWorldItemAction.complete
    function ISDropWorldItemAction:complete()
        local result = complete(self)
        adopt(self.item)
        return result
    end
    local vehicleComplete = ISDropVehicleItemAction.complete
    function ISDropVehicleItemAction:complete()
        local result = vehicleComplete(self)
        adopt(self.item)
        return result
    end
    local transfer = ISTransferAction.transferItem
    function ISTransferAction:transferItem(character, item, srcContainer, destContainer, square)
        local result = transfer(self, character, item, srcContainer, destContainer, square)
        adopt(result)
        return result
    end
    Events.OnGameStart.Add(function()
        require "TimedActions/ISGrabItemAction"
        require "TimedActions/ISInventoryTransferAction"
        require "ISUI/ISInventoryPane"
        local bulkTransfer = ISInventoryPane.transferItemsByWeight
        function ISInventoryPane:transferItemsByWeight(items, container)
            for _, item in ipairs(items) do
                if isPiece(item) then
                    local kept = {}
                    for _, other in ipairs(items) do
                        if not isPiece(other) then kept[#kept + 1] = other end
                    end
                    return bulkTransfer(self, kept, container)
                end
            end
            return bulkTransfer(self, items, container)
        end
        local grabValid = ISGrabItemAction.isValid
        function ISGrabItemAction:isValid()
            if self.item and isPiece(self.item:getItem()) then return false end
            return grabValid(self)
        end
        local transferValid = ISInventoryTransferAction.isValid
        function ISInventoryTransferAction:isValid()
            if isPiece(self.item) then return false end
            return transferValid(self)
        end
        Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldobjects, test)
            if not test then filterGrabMenu(context) end
        end)
    end)
    Events.OnTick.Add(function()
        if isClient() or isServer() then return end
        if isGamePaused() then return end
        local now = getTimestampMs()
        local opts = options()
        if #particles > 0 or #bleeders > 0 then updateBlood(opts, now) end
        updateFlights(opts, now)
        clean(opts, now)
    end)
    Events.RenderOpaqueObjectsInWorld.Add(function()
        if isClient() or isServer() then return end
        local opts = options()
        if opts.Enabled == false then return end
        if opts.DropBlood or opts.HeadBurst or opts.NeckBlood or opts.CutBlood then
            local now = getTimestampMs()
            for i = 1, #particles do
                local particle = particles[i]
                local sq = particle.sq
                if now - particle.born < particle.duration and (not particle.burst or particle.burst == true and opts.HeadBurst or particle.burst == "neck" and opts.NeckBlood)
                    and getCell():getGridSquare(sq:getX(), sq:getY(), sq:getZ()) == sq then
                    bloodInstance:setScale(particle.scale, particle.scale)
                    bloodSprite:render(bloodInstance, nil, particle.x, particle.y, particle.z, IsoDirections.N, 0, 0, particle.color, false)
                end
            end
        end
        if opts.DropFlight == false then return end
        for i = 1, #flights do
            local flight = flights[i]
            if enabled(flight.item, opts)
                and getCell():getGridSquare(flight.x, flight.y, flight.z) == flight.sq then
                Render3DItem(flight.item, flight.sq, flight.x, flight.y, flight.z + flight.drawZ, flight.rotation)
                flight.drawn = true
            end
        end
    end)
    Events.OnSave.Add(function()
        if isClient() or isServer() then return end
        local opts, now = options(), getTimestampMs()
        for i = #flights, 1, -1 do land(table.remove(flights, i), opts, now) end
    end)
    Events.LoadGridsquare.Add(function(sq)
        if isClient() or isServer() then return end
        local opts = options()
        local now = getTimestampMs()
        clean(opts, now)
        local objects = sq:getWorldObjects()
        for i = objects:size() - 1, 0, -1 do track(objects:get(i), opts, now) end
    end)
end

return D