ProjectALife = ProjectALife or {}

local Sweep = {
    settings = {
        tempoWalk = 0.72,
        tempoPause = 0.22,
        tempoGlance = 0.4,
        doorPauseMs = 900,
        doorPauseSpread = 700,
        roomPauseMs = 500,
        glanceGapMs = 2200,
        glanceGapSpread = 1800,
        glanceMs = 850,
        lookAhead = { 2, 4 },
        outsideGraceMs = 2500,
        idleReleaseMs = 4000,
        squareScanLimit = 400,
    },
    state = setmetatable({}, { __mode = "k" }),
    metrics = { raised = 0, doorPauses = 0, roomPauses = 0, glances = 0, released = 0 },
}
ProjectALife.RoomSweep = Sweep

function Sweep.enabled()
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    return not (type(current) == "table" and current.roomSweep == false)
end

function Sweep.roll(limit)
    if type(ZombRand) == "function" then return ZombRand(limit) end
    return 0
end

function Sweep.now()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Sweep.armedKind(data)
    local itemType = data.ProjectALifeActiveWeaponType
    if type(itemType) ~= "string" or itemType == "" or itemType == "Base.BareHands" then return nil end
    local class = data.ProjectALifeWeaponClass
    if class == "rifle" or class == "handgun" then return "ranged" end
    return "melee"
end

function Sweep.busy(data, now)
    local phase = tostring(data.ProjectALifeCombatPhase or "idle")
    if phase ~= "idle" and phase ~= "" and phase ~= "aborted" then return true end
    local posture = data.ProjectALifeDangerPosture
    if posture ~= nil and posture ~= "relaxed" then return true end
    if data.ProjectALifeHealDoneAtMs ~= nil or data.ProjectALifeDownedUntilMs ~= nil
            or data.ProjectALifeBleedOutAtMs ~= nil then return true end
    if now < (tonumber(data.ProjectALifeHitRunUntilMs) or 0) then return true end
    if data.ProjectALifeRequestedPace == "sprint" then return true end
    return false
end

function Sweep.buildingAhead(shell)
    if type(getCell) ~= "function" or type(shell.getForwardDirection) ~= "function" then return false end
    local cell = getCell()
    local forward = shell:getForwardDirection()
    if cell == nil or forward == nil then return false end
    local x, y, z = shell:getX(), shell:getY(), math.floor(shell:getZ())
    local fx, fy = forward:getX(), forward:getY()
    for _, reach in ipairs(Sweep.settings.lookAhead) do
        local square = cell:getGridSquare(math.floor(x + fx * reach), math.floor(y + fy * reach), z)
        if square ~= nil and square:getBuilding() ~= nil then return true end
    end
    return false
end

function Sweep.roomOf(square)
    if square == nil then return nil end
    local room = square:getRoom()
    if room == nil then return nil end
    return room
end

function Sweep.corners(room)
    local squares = room:getSquares()
    if squares == nil or squares:size() == 0 then return nil end
    local minX, minY, maxX, maxY
    for index = 0, math.min(squares:size(), Sweep.settings.squareScanLimit) - 1 do
        local square = squares:get(index)
        if square ~= nil then
            local x, y = square:getX(), square:getY()
            if minX == nil or x < minX then minX = x end
            if maxX == nil or x > maxX then maxX = x end
            if minY == nil or y < minY then minY = y end
            if maxY == nil or y > maxY then maxY = y end
        end
    end
    if minX == nil then return nil end
    local list = {
        { x = minX + 0.5, y = minY + 0.5 }, { x = maxX + 0.5, y = minY + 0.5 },
        { x = minX + 0.5, y = maxY + 0.5 }, { x = maxX + 0.5, y = maxY + 0.5 },
    }
    return { list = list, cx = (minX + maxX) / 2 + 0.5, cy = (minY + maxY) / 2 + 0.5,
        width = maxX - minX + 1, height = maxY - minY + 1 }
end

function Sweep.raise(shell, data, s, kind)
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.setReadyCarry) == "function" and data.ProjectALifeReadyCarry ~= true then
        pcall(animations.setReadyCarry, shell, true)
        s.raised = true
        Sweep.metrics.raised = Sweep.metrics.raised + 1
    end
    local combat = ProjectALife.Combat
    if kind == "ranged" and combat ~= nil and type(combat.setAimWalk) == "function" then
        if data.ProjectALifeAimWalk ~= true then s.aimed = true end
        combat.setAimWalk(shell, true, "room_sweep")
    end
end

function Sweep.clearAim(data, s)
    if s.glanceX ~= nil and data.ProjectALifeAimAtX == s.glanceX and data.ProjectALifeAimAtY == s.glanceY then
        data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = nil, nil
    end
    s.glanceX, s.glanceY, s.glanceUntil = nil, nil, nil
end

function Sweep.release(shell, data, s, quiet)
    Sweep.clearAim(data, s)
    data.ProjectALifeSweepSlow = nil
    data.ProjectALifeSweepTempo = nil
    if quiet ~= true then
        local animations = ProjectALife.Animations
        if s.raised and animations ~= nil and type(animations.setReadyCarry) == "function" then
            pcall(animations.setReadyCarry, shell, false)
        end
        local combat = ProjectALife.Combat
        if s.aimed and combat ~= nil and type(combat.setAimWalk) == "function" then
            combat.setAimWalk(shell, false, "room_swept")
        end
    end
    Sweep.state[shell] = nil
    Sweep.metrics.released = Sweep.metrics.released + 1
end

function Sweep.pickCorner(shell, s)
    local free = {}
    for index = 1, #s.room.list do
        if s.checked[index] ~= true then free[#free + 1] = index end
    end
    if #free == 0 then return nil end
    local choice = free[1 + Sweep.roll(#free)]
    s.checked[choice] = true
    return s.room.list[choice]
end

function Sweep.tick(shell, data, now)
    if type(data) ~= "table" or data.ProjectALifeActor ~= true or shell == nil then return false end
    now = tonumber(now) or Sweep.now()
    local s = Sweep.state[shell]
    local kind = Sweep.armedKind(data)
    if kind == nil or not Sweep.enabled() then
        if s ~= nil then Sweep.release(shell, data, s) end
        return false
    end
    if Sweep.busy(data, now) then
        if s ~= nil then Sweep.release(shell, data, s, true) end
        return false
    end
    local square = shell:getCurrentSquare()
    if square == nil then return false end
    local inside = square:getBuilding() ~= nil
    if not inside and not Sweep.buildingAhead(shell) then
        if s ~= nil and now - s.activeAtMs > Sweep.settings.outsideGraceMs then Sweep.release(shell, data, s) end
        return false
    end
    local moving = data.ProjectALifePathActive == true
    if s == nil then
        if not moving then return false end
        s = { activeAtMs = now, movedAtMs = now, pauseUntil = 0, nextGlanceAt = now, checked = {}, inside = inside }
        Sweep.state[shell] = s
        Sweep.raise(shell, data, s, kind)
    end
    if moving then
        s.movedAtMs = now
    elseif now - s.movedAtMs > Sweep.settings.idleReleaseMs then
        Sweep.release(shell, data, s)
        return false
    end
    s.activeAtMs = now
    if kind == "ranged" and data.ProjectALifeAimWalk ~= true then
        local combat = ProjectALife.Combat
        if combat ~= nil and type(combat.setAimWalk) == "function" then combat.setAimWalk(shell, true, "room_sweep") end
    end
    local settings = Sweep.settings
    if inside and not s.inside then
        s.pauseUntil = now + settings.doorPauseMs + Sweep.roll(settings.doorPauseSpread)
        s.nextGlanceAt = s.pauseUntil + settings.glanceGapMs
        Sweep.metrics.doorPauses = Sweep.metrics.doorPauses + 1
    end
    s.inside = inside
    local tempo = settings.tempoWalk
    if inside then
        local room = Sweep.roomOf(square)
        if room ~= s.isoRoom then
            local changed = s.isoRoom ~= nil
            s.isoRoom, s.room, s.checked = room, nil, {}
            if room ~= nil then s.room = Sweep.corners(room) end
            if changed then
                s.pauseUntil = math.max(s.pauseUntil, now + settings.roomPauseMs)
                s.nextGlanceAt = s.pauseUntil + 400
                Sweep.metrics.roomPauses = Sweep.metrics.roomPauses + 1
            end
        end
        if now < s.pauseUntil then
            tempo = settings.tempoPause
            if s.room ~= nil and s.glanceX == nil then
                s.glanceX, s.glanceY = s.room.cx, s.room.cy
                data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = s.glanceX, s.glanceY
                s.glanceUntil = s.pauseUntil
            end
        elseif s.glanceUntil ~= nil and now < s.glanceUntil then
            tempo = settings.tempoGlance
            data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = s.glanceX, s.glanceY
        else
            if s.glanceX ~= nil then Sweep.clearAim(data, s) end
            if s.room ~= nil and now >= s.nextGlanceAt then
                local corner = Sweep.pickCorner(shell, s)
                if corner ~= nil then
                    s.glanceX, s.glanceY = corner.x, corner.y
                    s.glanceUntil = now + settings.glanceMs
                    s.nextGlanceAt = now + settings.glanceGapMs + Sweep.roll(settings.glanceGapSpread)
                    data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = s.glanceX, s.glanceY
                    Sweep.metrics.glances = Sweep.metrics.glances + 1
                else
                    s.nextGlanceAt = now + 60000
                end
            end
        end
    elseif now < s.pauseUntil then
        tempo = settings.tempoPause
    end
    data.ProjectALifeSweepSlow = true
    data.ProjectALifeSweepTempo = tempo
    return true
end

return Sweep
