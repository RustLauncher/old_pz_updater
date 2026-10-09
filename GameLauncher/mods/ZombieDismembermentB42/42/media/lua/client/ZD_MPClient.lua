require "ZD_Network"
if not isClient() or isServer() then return end

local N = ZD_Network
local ZD = ZombieDismemberment
local observed = setmetatable({}, {__mode = "k"})
local byID = setmetatable({}, {__mode = "v"})
local nonce = 0
local lastBatch = 0
local queue = setmetatable({}, {__mode = "v"})
local head = 1
local tail = 0

local function enqueue(zombie, record)
    if record.queued then return end
    tail = tail + 1
    queue[tail] = zombie
    record.queued = tail
end

function N.clientObserve(zombie)
    if ZD.isNPC(zombie) then return end
    if N.isGrapple(zombie) then
        N.recoverCarriers(zombie)
        return
    end
    local id = N.onlineID(zombie)
    if not id then return end
    local md = zombie:getModData()
    local record = observed[zombie]
    if not record or record.id ~= id or (record.uid and md.ZD_MPUID ~= record.uid) then
        record = {id = id, nextQuery = 0, revision = -1}
        observed[zombie] = record
        enqueue(zombie, record)
    end
    byID[id] = zombie
end

local function apply(packet, snapshot)
    if not N.validPacket(packet) then return end
    local zombie = byID[packet.id]
    local record = zombie and observed[zombie]
    if not record or N.onlineID(zombie) ~= packet.id or N.isGrapple(zombie) or ZD.isNPC(zombie) then return end
    local md = zombie:getModData()
    if record.uid and md.ZD_MPUID ~= record.uid then
        observed[zombie] = nil
        N.clientObserve(zombie)
        return
    end
    if snapshot then
        if packet.nonce ~= record.nonce then return end
        if packet.outfit and ZD.trueZombieID(zombie) ~= packet.outfit then
            record.nextQuery = 0
            return
        end
        local dx = zombie:getX() - packet.x
        local dy = zombie:getY() - packet.y
        if dx * dx + dy * dy > 144 or math.abs(zombie:getZ() - packet.z) >= 1 then
            record.nextQuery = 0
            return
        end
    elseif record.uid ~= packet.uid then
        record.nextQuery = 0
        return
    end
    local currentRevision = record.revision
    if md.ZD_MPUID == packet.uid then
        currentRevision = math.max(currentRevision, tonumber(md.ZD_MPRevision) or -1)
    end
    if (record.uid == packet.uid or md.ZD_MPUID == packet.uid) and packet.revision < currentRevision then return end
    local changed = record.uid ~= packet.uid or packet.revision > record.revision
    record.uid = packet.uid
    record.revision = packet.revision
    record.nonce = nil
    record.nextQuery = getTimestampMs() + 120000
    local previous = N.hasLiveState(zombie)
    local clean = N.write(zombie, packet.state, packet.uid, packet.revision)
    if changed and previous and not N.hasState(clean) and ZD_Runtime then
        ZD_Runtime.clear(zombie)
    end
    if changed and N.hasState(clean) and ZD_Runtime then
        ZD_Runtime.apply(zombie, clean, true)
        ZD_Runtime.bridge(zombie, clean, true)
        local impact = packet.impact
        if not snapshot and type(impact) == "table" then
            if (impact.limb == "Head" and clean.Head == "Decapitated")
                or (impact.limb == "Arm" and ZD.validSide(impact.side) and ZD.validCut(impact.cut))
                or (impact.limb == "Leg" and ZD.validSide(impact.side) and impact.cut == "WholeLeg") then
                ZD_Runtime.blood(zombie, impact.limb, impact.side, impact.cut)
            end
        end
    end
end

local function onCommand(module, command, args)
    if module ~= ZD.MODKEY then return end
    if command == "State" then
        apply(args, false)
    elseif command == "Snapshot" and type(args) == "table" and args.v == N.PROTOCOL and type(args.entries) == "table" then
        for i = 1, math.min(#args.entries, N.MAX_BATCH) do
            apply(args.entries[i], true)
        end
    end
end

local function nearestPlayer(zombie, all)
    local best
    local distance = 65537
    for _, player in ipairs(all) do
        local dx = player:getX() - zombie:getX()
        local dy = player:getY() - zombie:getY()
        local currentDistance = dx * dx + dy * dy
        if currentDistance < distance and math.abs(player:getZ() - zombie:getZ()) <= 2 then
            best = player
            distance = currentDistance
        end
    end
    return best
end

local function onTick()
    local now = getTimestampMs()
    if now - lastBatch < 500 then return end
    local all = {}
    for i = 0, 3 do
        local player = getSpecificPlayer(i)
        if player then all[#all + 1] = player end
    end
    if #all == 0 then
        local player = getPlayer()
        if player then all[1] = player end
    end
    if #all == 0 then return end
    lastBatch = now
    for zombie, record in pairs(observed) do
        if N.onlineID(zombie) ~= record.id or not zombie:getCurrentSquare() or ZD.isNPC(zombie) then
            observed[zombie] = nil
            if byID[record.id] == zombie then byID[record.id] = nil end
        elseif now >= record.nextQuery then
            enqueue(zombie, record)
        end
    end
    local groups = {}
    local count = 0
    local scanned = 0
    while head <= tail and count < N.MAX_BATCH and scanned < 256 do
        local index = head
        local zombie = queue[index]
        queue[index] = nil
        head = head + 1
        scanned = scanned + 1
        local record = zombie and observed[zombie]
        if record and record.queued == index then
            record.queued = nil
            if now >= record.nextQuery and N.onlineID(zombie) == record.id then
                local player = nearestPlayer(zombie, all)
                if player then
                    nonce = nonce + 1
                    if nonce > 1000000000 then nonce = 1 end
                    record.nonce = nonce
                    record.nextQuery = now + 5000
                    groups[player] = groups[player] or {}
                    local requests = groups[player]
                    requests[#requests + 1] = {
                        id = record.id, nonce = record.nonce, outfit = ZD.trueZombieID(zombie),
                        x = zombie:getX(), y = zombie:getY(), z = zombie:getZ(),
                    }
                    count = count + 1
                else
                    record.nextQuery = now + 5000
                end
            end
        end
    end
    if head > tail then
        queue = setmetatable({}, {__mode = "v"})
        head = 1
        tail = 0
    elseif head > 2048 then
        local compact = setmetatable({}, {__mode = "v"})
        local count = 0
        for i = head, tail do
            local zombie = queue[i]
            local record = zombie and observed[zombie]
            if record and record.queued == i then
                count = count + 1
                compact[count] = zombie
                record.queued = count
            end
        end
        queue = compact
        head = 1
        tail = count
    end
    for player, requests in pairs(groups) do
        sendClientCommand(player, ZD.MODKEY, "Query", {v = N.PROTOCOL, requests = requests})
    end
end

local function reset()
    observed = setmetatable({}, {__mode = "k"})
    byID = setmetatable({}, {__mode = "v"})
    nonce = 0
    lastBatch = 0
    queue = setmetatable({}, {__mode = "v"})
    head = 1
    tail = 0
end

Events.OnTick.Add(onTick)
Events.OnServerCommand.Add(onCommand)
Events.OnGameStart.Add(reset)
Events.OnDisconnect.Add(reset)
