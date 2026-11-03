require "ZD_Network"
if not isServer() then return end

local N = ZD_Network
local ZD = ZombieDismemberment
local zombies = setmetatable({}, {__mode = "v"})
local throttle = setmetatable({}, {__mode = "k"})

local function data()
    local d = ModData.getOrCreate(N.KEY)
    d.nextUID = tonumber(d.nextUID) or 0
    d.records = d.records or {}
    return d
end

function N.serverIdentity(zombie)
    local md = zombie:getModData()
    if not N.validUID(md.ZD_MPUID) then
        local d = data()
        d.nextUID = d.nextUID + 1
        md.ZD_MPUID = "mp:" .. string.format("%.0f", d.nextUID)
        md.ZD_MPRevision = 0
    end
    return md.ZD_MPUID
end

function N.serverState(zombie)
    local md = zombie:getModData()
    local stored = N.validUID(md.ZD_MPUID) and data().records[md.ZD_MPUID] or nil
    return ZD.mergeStates(stored and stored.state, N.read(zombie))
end

function N.serverRecord(uid)
    local record = N.validUID(uid) and data().records[uid]
    return record and record.state
end

function N.serverObserve(zombie)
    if ZD.isNPC(zombie) then return end
    local id = N.onlineID(zombie)
    if id then zombies[id] = zombie end
    local md = zombie:getModData()
    if not N.validUID(md.ZD_MPUID) then return end
    local record = data().records[md.ZD_MPUID]
    if record then
        record.x = zombie:getX()
        record.y = zombie:getY()
        record.z = zombie:getZ()
    end
end

function N.serverSave(zombie, state)
    local uid = N.serverIdentity(zombie)
    local d = data()
    local old = d.records[uid]
    local previous = old and old.state or N.read(zombie)
    local clean = ZD.mergeStates(previous, state)
    local revision = math.max(tonumber(zombie:getModData().ZD_MPRevision) or 0, old and old.revision or 0) + 1
    N.write(zombie, clean, uid, revision)
    d.records[uid] = {state = clean, revision = revision, x = zombie:getX(), y = zombie:getY(), z = zombie:getZ()}
    local packet = N.packet(zombie, clean, uid, revision)
    packet.impact = N.impact(previous, clean)
    return clean, packet
end

function N.serverPublish(packet)
    if N.validPacket(packet) then sendServerCommand(ZD.MODKEY, "State", packet) end
end

function N.serverDead(zombie)
    local uid = zombie:getModData().ZD_MPUID
    if N.validUID(uid) then data().records[uid] = nil end
end

local function onCommand(module, command, player, args)
    if module ~= ZD.MODKEY or command ~= "Query" or not player or type(args) ~= "table" then return end
    if args.v ~= N.PROTOCOL or type(args.requests) ~= "table" or #args.requests > N.MAX_BATCH then return end
    local now = getTimestampMs()
    if throttle[player] and now - throttle[player] < 150 then return end
    throttle[player] = now
    local missing = {}
    local needsScan = false
    for _, request in ipairs(args.requests) do
        if type(request) == "table" and N.number(request.id, -32768, 32767) and request.id ~= -1 then
            local zombie = zombies[request.id]
            if not zombie or N.onlineID(zombie) ~= request.id then
                missing[request.id] = true
                needsScan = true
            end
        end
    end
    if needsScan then
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local zombie = list:get(i)
            local id = N.onlineID(zombie)
            if id and missing[id] and not ZD.isNPC(zombie) then zombies[id] = zombie end
        end
    end
    local entries = {}
    for _, request in ipairs(args.requests) do
        if type(request) == "table" and N.number(request.id, -32768, 32767) and request.id ~= -1
            and N.number(request.nonce, 1, 1000000000) and N.number(request.x, -1000000, 1000000)
            and N.number(request.y, -1000000, 1000000) and N.number(request.z, -32, 32) then
            local zombie = zombies[request.id]
            local matchesRequest = zombie and N.onlineID(zombie) == request.id and not N.isGrapple(zombie) and not ZD.isNPC(zombie)
            if matchesRequest and request.outfit then
                matchesRequest = ZD.trueZombieID(zombie) == request.outfit
            end
            if matchesRequest then
                local dx = zombie:getX() - request.x
                local dy = zombie:getY() - request.y
                if dx * dx + dy * dy <= 144 and math.abs(zombie:getZ() - request.z) < 1 then
                    local playerDX = player:getX() - zombie:getX()
                    local playerDY = player:getY() - zombie:getY()
                    if playerDX * playerDX + playerDY * playerDY <= 65536 and math.abs(player:getZ() - zombie:getZ()) <= 2 then
                        local uid = N.serverIdentity(zombie)
                        local state = N.serverState(zombie)
                        local revision = tonumber(zombie:getModData().ZD_MPRevision) or 0
                        entries[#entries + 1] = N.packet(zombie, state, uid, revision, request.nonce)
                    end
                end
            end
        end
    end
    if #entries > 0 then
        sendServerCommand(player, ZD.MODKEY, "Snapshot", {v = N.PROTOCOL, entries = entries})
    end
end

Events.OnInitGlobalModData.Add(data)
Events.OnServerStarted.Add(data)
Events.OnClientCommand.Add(onCommand)
