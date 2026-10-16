require "OfflineSurvivorSilentDeath/OS_BodyLifecycle"
local OS = OfflineSurvivorSilentDeath
local H = OS.BodyLifecycle
local Admin = {}
OS.AdminCleanup = Admin

-- One bounded job at a time: no full-world scan, no chunk loads, no per-player
-- radius supplied by the network. Permission is checked again on every batch.
function Admin.install(suppress, suppressDragged)
    local job
    local cooldown = {}
    local function reply(player, status, count)
        sendServerCommand(player, OS.MODULE, "AdminCleanupResult", {status=status, count=count or 0})
    end
    local function command(module, name, player)
        if module ~= OS.MODULE or name ~= "AdminRemoveBodies" then return end
        if not H.isAdmin(player) or player:isDead() then return end
        local key = tostring(OS.getSteamId(player))
        local now = getTimestamp()
        if job or now < (cooldown[key] or 0) then reply(player, "busy"); return end
        local radius = math.floor(H.finite(OS.getOption("AdminCleanupRadius", 15)) or 15)
        radius = math.max(1, math.min(radius, 50))
        local x, y = math.floor(player:getX()), math.floor(player:getY())
        job = {player=player, x=x, y=y, z=math.floor(player:getZ()), radius=radius,
            tx=x-radius, ty=y-radius, count=0}
        if suppressDragged then job.count=suppressDragged(job) or 0 end
        cooldown[key] = now + 10
        reply(player, "started")
        print("[Offline Survivor] Admin area cleanup by " .. tostring(player:getUsername())
            .. " at " .. x .. "," .. y .. "," .. job.z .. " radius=" .. radius)
    end
    local function tick()
        if not job then return end
        if not H.isAdmin(job.player) or job.player:isDead() then job=nil; return end
        local cell = getCell()
        if not cell then job=nil; return end
        for _ = 1, 128 do
            if job.tx > job.x + job.radius then
                reply(job.player, "finished", job.count)
                print("[Offline Survivor] Admin area cleanup removed " .. job.count .. " bodies")
                job=nil
                return
            end
            local dx,dy=job.tx-job.x,job.ty-job.y
            local square
            if dx*dx+dy*dy <= job.radius*job.radius then
                square=cell:getGridSquare(job.tx,job.ty,job.z)
            end
            if square then
                local bodies=square:getStaticMovingObjects()
                for i=bodies:size()-1,0,-1 do
                    local body=bodies:get(i)
                    if instanceof(body,"IsoDeadBody") then
                        if H.isProxy(body) then suppress(body) end
                        square:removeCorpse(body,false)
                        job.count=job.count+1
                    end
                end
                local moving=square:getMovingObjects()
                for i=moving:size()-1,0,-1 do
                    local body=moving:get(i)
                    if instanceof(body,"IsoZombie") and H.isProxy(body) then
                        suppress(body)
                        body:removeFromWorld()
                        body:removeFromSquare()
                        job.count=job.count+1
                    end
                end
            end
            job.ty=job.ty+1
            if job.ty>job.y+job.radius then job.ty=job.y-job.radius;job.tx=job.tx+1 end
        end
    end
    Events.OnClientCommand.Add(command)
    Events.OnTick.Add(tick)
    Events.OnInitGlobalModData.Add(function() job=nil;cooldown={} end)
end
return Admin
