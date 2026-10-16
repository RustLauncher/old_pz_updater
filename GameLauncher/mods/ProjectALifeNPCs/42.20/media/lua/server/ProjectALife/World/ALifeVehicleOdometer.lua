ProjectALife = ProjectALife or {}

local Odometer = { settings = { intervalMs = 500, staleMs = 4000, smoothing = 0.6 } }
ProjectALife.Odometer = Odometer

local floor_, sqrt_ = math.floor, math.sqrt
local tracks = {}
local scratchVector = nil

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return floor_(os.time() * 1000)
end

local function forwardScratch()
    if scratchVector == nil then
        local ok, made = pcall(function() return Vector3f.new() end)
        if ok then scratchVector = made end
    end
    return scratchVector
end

function Odometer.read(player)
    if player == nil then return nil end
    local out
    pcall(function()
        local vehicle = player:getVehicle()
        if vehicle == nil then return end
        local fx, fy = 0, 0
        local vec = forwardScratch()
        if vec ~= nil then
            vehicle:getForwardVector(vec)
            fx, fy = vec:x(), vec:z()
        end
        out = {
            vehicle  = vehicle,
            id       = vehicle:getId(),
            x        = vehicle:getX(),
            y        = vehicle:getY(),
            z        = vehicle:getZ(),
            square   = vehicle:getSquare(),
            kmh      = vehicle:getCurrentSpeedKmHour(),      
            absKmh   = vehicle:getCurrentAbsoluteSpeedKmHour(),
            speed2D  = vehicle:getSpeed2D(),
            angleZ   = vehicle:getAngleZ(),                  
            fx       = fx,
            fy       = fy,
            driving  = vehicle:isDriver(player) == true,
            engineOn = vehicle:isEngineRunning() == true,
        }
    end)
    return out
end

function Odometer.forget(id)
    if id ~= nil then tracks[tostring(id)] = nil end
end

function Odometer.sample(player, now)
    now = tonumber(now) or nowMs()
    local read = Odometer.read(player)
    if read == nil then return nil end
    local key = tostring(read.id)
    local track = tracks[key]
    if track == nil then
        track = { tiles = 0, lastX = read.x, lastY = read.y, lastMs = now,
                  hx = 0, hy = 0, sign = 0 }
        tracks[key] = track
    end
    if now - track.lastMs >= Odometer.settings.intervalMs then

        if now - track.lastMs > Odometer.settings.staleMs then
            track.lastX, track.lastY = read.x, read.y
        end
        local dx, dy = read.x - track.lastX, read.y - track.lastY
        local step = sqrt_(dx * dx + dy * dy)
        if step > 0.05 then
            track.tiles = track.tiles + step
            local ix, iy = dx / step, dy / step
            local keep = Odometer.settings.smoothing
            track.hx = track.hx * keep + ix * (1 - keep)
            track.hy = track.hy * keep + iy * (1 - keep)
            local norm = sqrt_(track.hx * track.hx + track.hy * track.hy)
            if norm > 0.0001 then
                track.hx, track.hy = track.hx / norm, track.hy / norm
            end
            if track.sign == 0 and (read.fx ~= 0 or read.fy ~= 0) then
                if read.fx * ix + read.fy * iy >= 0 then
                    track.sign = 1
                else
                    track.sign = -1
                end
            end
        end
        track.lastX, track.lastY, track.lastMs = read.x, read.y, now
    end
    read.tiles = track.tiles          
    read.hx, read.hy = track.hx, track.hy   
    read.forwardSign = track.sign
    return read
end

function Odometer.armed(read, tilesNeeded, kmhNeeded)
    if read == nil or read.driving ~= true then return false end
    if read.absKmh < (tonumber(kmhNeeded) or 25) then return false end
    if read.tiles < (tonumber(tilesNeeded) or 250) then return false end
    if read.hx == 0 and read.hy == 0 then return false end
    return ProjectALife.Road.isRoadSquare(read.square)
end
