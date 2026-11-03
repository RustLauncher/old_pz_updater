local CRUSH_SPEED_KMH = 5
local CRUSH_RADIUS    = 1.5
local CHECK_EVERY     = 5

local tickCount = 0

local function killZombie(player, z)
    -- crawlers keep crawling after they die unless they're laid flat first
    if z:isCrawling() then
        z:setCrawler(false)
        z:setOnFloor(true)
    end
    z:Kill(player)
end

local function crushZombies(player, vehicle)
    if math.abs(vehicle:getCurrentSpeedKmHour()) < CRUSH_SPEED_KMH then return end

    local vx, vy, vz = vehicle:getX(), vehicle:getY(), vehicle:getZ()
    local radiusSq = CRUSH_RADIUS * CRUSH_RADIUS
    local zombies = getCell():getZombieList()

    for i = zombies:size() - 1, 0, -1 do
        local z = zombies:get(i)
        if z and not z:isDead()
           and (z:isOnFloor() or z:isCrawling())
           and math.floor(z:getZ()) == math.floor(vz) then

            local dx, dy = z:getX() - vx, z:getY() - vy
            if dx * dx + dy * dy <= radiusSq then
                killZombie(player, z)
            end
        end
    end
end

local function onTick()
    tickCount = tickCount + 1
    if tickCount < CHECK_EVERY then return end
    tickCount = 0

    local player = getPlayer()
    if not player then return end

    local vehicle = player:getVehicle()
    if vehicle and vehicle:getDriver() == player then
        crushZombies(player, vehicle)
    end
end

Events.OnTick.Add(onTick)