require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Shells/ALifeWounds"

ProjectALife = ProjectALife or {}

local Blood = {
    options = { enabled = "Blood_Enabled", percent = "Blood_Percent", melee = "Blood_MeleeKillPercent" },
    defaults = { percent = 200, melee = 300 },
    settings = {
        perSecond = 60,
        perSquare = 24,
        perHit = 8,
        perDeath = 24,
        dripBelow = 0.30,
        dripMinMs = 1500,
        dripMaxMs = 3000,
        dripPerMinute = 16,
        dripRecheckMs = 1000,
        poolBase = 3,
        poolSpread = 4,
        hitBase = 0.6,
        hitScale = 8,
        stainScale = 10,
        stainCap = 6,
        wallFraction = 0.12,
        wallMeleeFraction = 0.30,
        minFraction = 0.03,
        soakHit = 0.5,
        soakHitCap = 0.2,
        soakKill = 0.35,
    },
    weights = { blade = 1.3, blunt = 1.1, fists = 0.5, firearm = 0.7, zombie = 0.9, unknown = 0.7, vehicle = 0.9 },
    melee = { blade = true, blunt = true },
    levels = { [1] = 0, [2] = 0.5, [3] = 1, [4] = 1.25, [5] = 1.5 },
    sizes = { small = { 0, 8 }, medium = { 8, 8 }, large = { 16, 5 } },
    partNames = { "Head", "Neck", "Torso_Upper", "Torso_Lower", "UpperArm_L", "UpperArm_R", "ForeArm_L",
        "ForeArm_R", "Hand_L", "Hand_R", "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Back" },
    handNames = { "Hand_R", "ForeArm_R", "UpperArm_R", "Torso_Upper", "Hand_L", "ForeArm_L" },
    offsets = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } },
    metrics = { bloodSplats = 0, bloodPools = 0, bloodDrips = 0, bloodSkippedCap = 0, bloodSkippedOff = 0,
        bloodStains = 0, bloodWalls = 0, bloodAttackers = 0 },
    window = { at = 0, used = 0 },
    squareUsed = {},
    squareStamp = 0,
    lastHp = setmetatable({}, { __mode = "k" }),
    dirX = setmetatable({}, { __mode = "k" }),
    dirY = setmetatable({}, { __mode = "k" }),
    dripNext = setmetatable({}, { __mode = "k" }),
    dripStart = setmetatable({}, { __mode = "k" }),
    dripCount = setmetatable({}, { __mode = "k" }),
    pooled = setmetatable({}, { __mode = "k" }),
}
ProjectALife.Blood = Blood

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll(limit)
    if type(ZombRand) == "function" and limit > 0 then return ZombRand(limit) end
    return 0
end

function Blood.clear()
    Blood.window.at, Blood.window.used = 0, 0
    Blood.squareUsed, Blood.squareStamp = {}, 0
    for key in pairs(Blood.metrics) do Blood.metrics[key] = 0 end
end

function Blood.percent()
    local gate = ProjectALife.FeatureGate
    if gate == nil then return Blood.defaults.percent end
    return gate.number(Blood.options.percent, Blood.defaults.percent, 100, 500)
end

function Blood.meleePercent()
    local gate = ProjectALife.FeatureGate
    if gate == nil then return Blood.defaults.melee end
    return gate.number(Blood.options.melee, Blood.defaults.melee, 100, 800)
end

function Blood.active()
    local gate = ProjectALife.FeatureGate
    if gate == nil or not gate.flag(Blood.options.enabled, true) then return false end
    return Blood.percent() > 100
end

function Blood.levelScale()
    local level
    if type(SandboxVars) == "table" then level = tonumber(SandboxVars.BloodLevel) end
    if level == nil then return 1 end
    local scale = Blood.levels[level]
    if scale == nil then return 1 end
    return scale
end

function Blood.decalsOff()
    if type(isServer) == "function" and isServer() == true then return false end
    if type(getCore) ~= "function" then return false end
    local ok, core = pcall(getCore)
    if not ok or core == nil or type(core.getOptionBloodDecals) ~= "function" then return false end
    local read, value = pcall(core.getOptionBloodDecals, core)
    return read and tonumber(value) == 0
end

function Blood.ready()
    if not Blood.active() then return nil end
    local scale = Blood.levelScale()
    if scale <= 0 or Blood.decalsOff() then
        Blood.metrics.bloodSkippedOff = Blood.metrics.bloodSkippedOff + 1
        return nil
    end
    return scale
end

function Blood.rounded(value)
    local whole = math.floor(value)
    if roll(100) < (value - whole) * 100 then whole = whole + 1 end
    return whole
end

function Blood.squareOf(body)
    if body == nil or type(body.getCurrentSquare) ~= "function" then return nil end
    local ok, square = pcall(body.getCurrentSquare, body)
    if ok then return square end
    return nil
end

function Blood.squareAt(square, wx, wy, wz)
    local cell
    if type(square.getCell) == "function" then cell = square:getCell() end
    if cell == nil and type(getCell) == "function" then cell = getCell() end
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    return cell:getGridSquare(wx, wy, wz)
end

function Blood.reach(home, square)
    if square == nil then return false end
    if square == home then return true end
    if type(square.isSolidFloor) == "function" and square:isSolidFloor() ~= true then return false end
    if type(home.isBlockedTo) == "function" and home:isBlockedTo(square) == true then return false end
    if type(home.getRoom) == "function" and type(square.getRoom) == "function"
            and home:getRoom() ~= square:getRoom() then return false end
    return true
end

function Blood.awayFrom(attacker, target)
    local dx, dy = 0, 0
    if attacker ~= nil and target ~= nil and type(attacker.getX) == "function" and type(target.getX) == "function" then
        local ok = pcall(function()
            dx = target:getX() - attacker:getX()
            dy = target:getY() - attacker:getY()
        end)
        if not ok then dx, dy = 0, 0 end
    end
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.05 then
        dx, dy = roll(2001) / 1000 - 1, roll(2001) / 1000 - 1
        length = math.sqrt(dx * dx + dy * dy)
        if length < 0.05 then return 1, 0 end
    end
    return dx / length, dy / length
end

function Blood.keyOf(square)
    return (square:getZ() * 100000 + square:getX()) * 100000 + square:getY()
end

function Blood.allow(square, now)
    local window = Blood.window
    if now < window.at or now - window.at >= 1000 then window.at, window.used = now, 0 end
    if window.used >= Blood.settings.perSecond then
        Blood.metrics.bloodSkippedCap = Blood.metrics.bloodSkippedCap + 1
        return false
    end
    if now < Blood.squareStamp or now - Blood.squareStamp >= 60000 then
        Blood.squareUsed, Blood.squareStamp = {}, now
    end
    local key = Blood.keyOf(square)
    local used = Blood.squareUsed[key] or 0
    if used >= Blood.settings.perSquare then
        Blood.metrics.bloodSkippedCap = Blood.metrics.bloodSkippedCap + 1
        return false
    end
    Blood.squareUsed[key] = used + 1
    window.used = window.used + 1
    return true
end

function Blood.typeFor(size)
    local band = Blood.sizes[size] or Blood.sizes.small
    return band[1] + roll(band[2])
end

function Blood.sizeFor(fraction, melee)
    local large = math.min(0.7, fraction * (melee and 1.2 or 0.6))
    local medium = math.min(0.6, 0.25 + fraction * 1.5)
    local pick = roll(1000) / 1000
    if pick < large then return "large" end
    if pick < large + medium then return "medium" end
    return "small"
end

function Blood.splat(square, px, py, size, now)
    if square == nil then return false end
    if not Blood.allow(square, now) then return false end
    local placed = false
    local chunk
    if type(square.getChunk) == "function" then chunk = square:getChunk() end
    if chunk ~= nil and type(chunk.addBloodSplat) == "function" then
        placed = pcall(chunk.addBloodSplat, chunk, px, py, square:getZ(), Blood.typeFor(size))
    elseif type(addBloodSplat) == "function" then
        placed = pcall(addBloodSplat, square, 1, px - square:getX(), py - square:getY())
    end
    if placed then Blood.metrics.bloodSplats = Blood.metrics.bloodSplats + 1 end
    return placed
end

function Blood.inside(square, value, axis)
    local low = square:getX()
    if axis == "y" then low = square:getY() end
    if value < low + 0.1 then return low + 0.1 end
    if value > low + 0.9 then return low + 0.9 end
    return value
end

function Blood.spread(home, x, y, dx, dy, size, now)
    local distance = 0.2 + roll(100) / 100 * 1.2
    local lateral = (roll(71) - 35) / 100
    local px = x + dx * distance - dy * lateral
    local py = y + dy * distance + dx * lateral
    local square = home
    local fx, fy = math.floor(px), math.floor(py)
    if fx ~= home:getX() or fy ~= home:getY() then
        local other = Blood.squareAt(home, fx, fy, home:getZ())
        if Blood.reach(home, other) then square = other end
    end
    return Blood.splat(square, Blood.inside(square, px, "x"), Blood.inside(square, py, "y"), size, now)
end

function Blood.stainMore(target, zone, fraction, pct, scale)
    if type(target.addBlood) ~= "function" or BloodBodyPartType == nil then return 0 end
    local settings = Blood.settings
    local wanted = math.floor(fraction * settings.stainScale * (pct - 100) / 100 * scale + 0.5)
    if wanted > settings.stainCap then wanted = settings.stainCap end
    local painted = 0
    local names = Blood.partNames
    local zoned = ProjectALife.Health ~= nil and ProjectALife.Health.bloodZones or nil
    for _ = 1, wanted do
        local name = names[1 + roll(#names)]
        if type(zoned) == "table" and type(zoned[tostring(zone)]) == "table" and roll(2) == 0 then
            local list = zoned[tostring(zone)]
            name = list[1 + roll(#list)]
        end
        local part = BloodBodyPartType[name]
        if part ~= nil then
            target:addBlood(part, true, true, false)
            painted = painted + 1
        end
    end
    if painted > 0 then Blood.metrics.bloodStains = Blood.metrics.bloodStains + painted end
    return painted
end

function Blood.wall(body, count)
    if type(isServer) == "function" and isServer() == true then return false end
    if type(body.splatBlood) ~= "function" then return false end
    body:splatBlood(count, 0.3)
    Blood.metrics.bloodWalls = Blood.metrics.bloodWalls + 1
    return true
end

function Blood.soak(attacker, fraction, kill, pct, scale)
    if attacker == nil or type(attacker.addBlood) ~= "function" then return false end
    local wounds = ProjectALife.Wounds
    if wounds == nil or type(wounds.isNpcShell) ~= "function" or not wounds.isNpcShell(attacker) then return false end
    if type(attacker.isDead) == "function" and attacker:isDead() == true then return false end
    local settings = Blood.settings
    local factor = (pct - 100) / 100 * scale
    local delta = math.min(settings.soakHitCap, fraction * settings.soakHit) * factor
    local parts = 0
    if fraction >= 0.1 then parts = 1 end
    if kill then
        delta = settings.soakKill * factor
        parts = 3
    end
    if BloodBodyPartType ~= nil then
        for index = 1, parts do
            local part = BloodBodyPartType[Blood.handNames[index]]
            if part ~= nil then attacker:addBlood(part, false, true, false) end
        end
    end
    if type(attacker.getPrimaryHandItem) == "function" then
        local weapon = attacker:getPrimaryHandItem()
        if weapon ~= nil and type(weapon.setBloodLevel) == "function" and type(weapon.getBloodLevel) == "function" then
            weapon:setBloodLevel(math.min(1, math.max(0, (tonumber(weapon:getBloodLevel()) or 0) + delta)))
        end
    end
    Blood.metrics.bloodAttackers = Blood.metrics.bloodAttackers + 1
    return true
end

function Blood.weightFor(kind, weapon)
    local weight = Blood.weights[kind] or Blood.weights.unknown
    if kind == "firearm" and weapon ~= nil and type(weapon.getAmmoType) == "function" then
        local ok, ammo = pcall(weapon.getAmmoType, weapon)
        if ok and string.find(string.lower(tostring(ammo)), "shotgun", 1, true) ~= nil then weight = 1.2 end
    end
    return weight
end

function Blood.onHit(attacker, target, zone, remaining, maximum, now, weapon, attack)
    local scale = Blood.ready()
    if scale == nil or target == nil then return false end
    now = tonumber(now) or nowMs()
    local pct = Blood.percent()
    local settings = Blood.settings
    local limit = tonumber(maximum) or 0
    if limit <= 0 then limit = 1 end
    local left = tonumber(remaining) or 0
    local before = Blood.lastHp[target]
    if before == nil then before = limit end
    Blood.lastHp[target] = left
    local fraction = (before - left) / limit
    if fraction < settings.minFraction then fraction = settings.minFraction end
    if fraction > 1 then fraction = 1 end
    local kind = tostring(attack)
    local melee = Blood.melee[kind] == true
    local weight = Blood.weightFor(kind, weapon)
    local dx, dy = Blood.awayFrom(attacker, target)
    Blood.dirX[target], Blood.dirY[target] = dx, dy
    local home = Blood.squareOf(target)
    if home == nil then return false end
    local count = Blood.rounded((settings.hitBase + fraction * settings.hitScale * weight) * pct / 100 * scale)
    if count > settings.perHit then count = settings.perHit end
    local x, y = target:getX(), target:getY()
    for _ = 1, count do
        Blood.spread(home, x, y, dx, dy, Blood.sizeFor(fraction, melee), now)
    end
    Blood.stainMore(target, zone, fraction, pct, scale)
    if (zone == "head" and fraction >= settings.wallFraction) or (melee and fraction >= settings.wallMeleeFraction) then
        Blood.wall(target, 2)
    end
    if melee then Blood.soak(attacker, fraction, false, pct, scale) end
    return true
end

function Blood.bleeding(data)
    if data.ProjectALifeBleedOutAtMs ~= nil then return true end
    local list = data.ProjectALifeInjuries
    local wounds = ProjectALife.Wounds
    if type(list) ~= "table" or wounds == nil or type(wounds.bleeding) ~= "function" then return false end
    local hours = 0
    if ProjectALife.Health ~= nil and type(ProjectALife.Health.worldHours) == "function" then
        hours = ProjectALife.Health.worldHours()
    end
    for index = 1, #list do
        if wounds.bleeding(list[index], hours) then return true end
    end
    return false
end

function Blood.drip(shell, data, now)
    if shell == nil or type(data) ~= "table" or not Blood.active() then return false end
    now = tonumber(now) or nowMs()
    local settings = Blood.settings
    local due = Blood.dripNext[shell]
    if due ~= nil and now < due and due - now <= settings.dripMaxMs then return false end
    Blood.dripNext[shell] = now + settings.dripRecheckMs
    local sim = ProjectALife.ShellSimulation
    if sim == nil then return false end
    local maximum = tonumber(sim.maximumFor(shell)) or 0
    local health = tonumber(sim.trueHealth(shell)) or 0
    if maximum <= 0 or health <= 0 or health > maximum * settings.dripBelow then return false end
    if not Blood.bleeding(data) then return false end
    local start = Blood.dripStart[shell]
    if start == nil or now < start or now - start >= 60000 then
        Blood.dripStart[shell], Blood.dripCount[shell] = now, 0
    end
    if Blood.dripCount[shell] >= settings.dripPerMinute then
        Blood.metrics.bloodSkippedCap = Blood.metrics.bloodSkippedCap + 1
        return false
    end
    local scale = Blood.ready()
    if scale == nil then return false end
    local home = Blood.squareOf(shell)
    if home == nil then return false end
    Blood.dripNext[shell] = now + settings.dripMinMs + roll(settings.dripMaxMs - settings.dripMinMs + 1)
    local size = "small"
    if data.ProjectALifeBleedOutAtMs ~= nil and roll(100) < 40 then size = "medium" end
    local px = Blood.inside(home, shell:getX() + (roll(41) - 20) / 100, "x")
    local py = Blood.inside(home, shell:getY() + (roll(41) - 20) / 100, "y")
    if Blood.splat(home, px, py, size, now) then
        Blood.dripCount[shell] = Blood.dripCount[shell] + 1
        Blood.metrics.bloodDrips = Blood.metrics.bloodDrips + 1
        return true
    end
    return false
end

function Blood.neighbours(home, wanted, dx, dy)
    local ranked = {}
    for index = 1, #Blood.offsets do
        local offset = Blood.offsets[index]
        ranked[#ranked + 1] = { offset[1], offset[2], (offset[1] * dx + offset[2] * dy) * 0.8 + roll(100) / 100 }
    end
    table.sort(ranked, function(a, b) return a[3] > b[3] end)
    local found = {}
    for index = 1, #ranked do
        if #found >= wanted then break end
        local row = ranked[index]
        local square = Blood.squareAt(home, home:getX() + row[1], home:getY() + row[2], home:getZ())
        if square ~= nil and square ~= home and Blood.reach(home, square) then found[#found + 1] = square end
    end
    return found
end

function Blood.onDeath(shell)
    if shell == nil or Blood.pooled[shell] then return false end
    local scale = Blood.ready()
    if scale == nil then return false end
    local wounds = ProjectALife.Wounds
    if wounds == nil or type(wounds.isNpcShell) ~= "function" or not wounds.isNpcShell(shell) then return false end
    local home = Blood.squareOf(shell)
    if home == nil and type(getCell) == "function" then
        local cell = getCell()
        if cell ~= nil then home = cell:getGridSquare(math.floor(shell:getX()), math.floor(shell:getY()), math.floor(shell:getZ())) end
    end
    if home == nil then return false end
    Blood.pooled[shell] = true
    local data = shell:getModData()
    local kind = type(data) == "table" and tostring(data.ProjectALifeLastAttackKind) or "unknown"
    local melee = Blood.melee[kind] == true
    local pct = Blood.percent()
    local share = pct
    if melee then share = Blood.meleePercent() end
    local settings = Blood.settings
    local count = Blood.rounded((settings.poolBase + roll(settings.poolSpread)) * share / 100 * scale)
    if count > settings.perDeath then count = settings.perDeath end
    local now = nowMs()
    local dx, dy = Blood.dirX[shell], Blood.dirY[shell]
    if dx == nil or dy == nil then dx, dy = Blood.awayFrom(nil, shell) end
    local squares = { home }
    local others = Blood.neighbours(home, 1 + roll(2), dx, dy)
    for index = 1, #others do squares[#squares + 1] = others[index] end
    local x, y = shell:getX(), shell:getY()
    local made = 0
    for index = 1, count do
        local square = squares[1]
        if #squares > 1 and roll(100) >= 50 then square = squares[2 + roll(#squares - 1)] end
        local size = "medium"
        local pick = roll(100)
        if melee then
            if pick < 50 then size = "large" elseif pick >= 90 then size = "small" end
        else
            if pick < 15 then size = "large" elseif pick >= 70 then size = "small" end
        end
        local px, py = x + (roll(81) - 40) / 100, y + (roll(81) - 40) / 100
        if square ~= home then px, py = square:getX() + 0.15 + roll(71) / 100, square:getY() + 0.15 + roll(71) / 100 end
        if Blood.splat(square, Blood.inside(square, px, "x"), Blood.inside(square, py, "y"), size, now) then made = made + 1 end
    end
    if made > 0 then Blood.metrics.bloodPools = Blood.metrics.bloodPools + 1 end
    if melee then
        Blood.wall(shell, 3)
        local health = ProjectALife.Health
        local attacker = health ~= nil and type(health.lastAttacker) == "table" and health.lastAttacker[shell] or nil
        Blood.soak(attacker, 1, true, pct, scale)
    end
    return made > 0
end

return Blood
