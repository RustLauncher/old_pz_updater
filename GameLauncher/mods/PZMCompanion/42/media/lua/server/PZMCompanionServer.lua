if not isServer() then return end

local MAX_ENTRIES = 64

local LOG_MS = 60000

local BACKOFF_MS = 10000

local function log(msg)
    print("[PZMCompanion] " .. msg)
end

local last = 0
local lastLog = 0
local lastLogKey = ""
local failures = 0
local lastFailLog = 0
local backoffUntil = 0

local function shareMode()
    local vars = SandboxVars and SandboxVars.PZMCompanion
    local v = vars and tonumber(vars.SharePositions)
    if not v then return 1 end
    return math.floor(v)
end

local function shareIntervalMs()
    local vars = SandboxVars and SandboxVars.PZMCompanion
    local v = vars and tonumber(vars.ShareInterval)
    if not v then v = 1 end
    if v < 1 then v = 1 end
    if v > 10 then v = 10 end
    return math.floor(v) * 1000
end

local function entryFor(p)
    local user = p:getUsername()
    if user == nil then return nil end
    user = tostring(user)
    local name = user
    local okDesc, desc = pcall(function() return p:getDescriptor() end)
    if okDesc and desc and desc.getForename then
        local okName, n = pcall(function() return desc:getForename() end)
        if okName and n and n ~= "" then name = tostring(n) end
    end
    local e = {
        name = name,
        user = user,
        x = p:getX(),
        y = p:getY(),
        z = math.floor(p:getZ() + 0.5),
        dead = p:isDead() == true,
    }

    local okFwd, fx, fy = pcall(function()
        return p:getForwardDirectionX(), p:getForwardDirectionY()
    end)
    if not (okFwd and type(fx) == "number" and type(fy) == "number") then
        okFwd, fx, fy = pcall(function()
            local fwd = p:getForwardDirection()
            return fwd:getX(), fwd:getY()
        end)
    end
    if okFwd and type(fx) == "number" and type(fy) == "number" then
        e.fx = fx
        e.fy = fy
    end
    return e
end

local function gather()
    local players = getOnlinePlayers()
    if not players then return nil, nil end
    local list = {}
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            local e = entryFor(p)
            if e then list[#list + 1] = e end
        end
    end
    return list, players
end

local function packet(now, list)
    return { t = now, every = shareIntervalMs(), list = list }
end

local function broadcast(now, list)
    if #list > MAX_ENTRIES then
        local capped = {}
        for i = 1, MAX_ENTRIES do capped[i] = list[i] end
        list = capped
    end
    sendServerCommand("PZMCompanion", "positions", packet(now, list))
end

local function sendFactions(now, list, players)
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            local f = Faction.getPlayerFaction(p)
            if f then
                local me = tostring(p:getUsername())
                local sub = {}
                for j = 1, #list do
                    if #sub >= MAX_ENTRIES then break end
                    local e = list[j]
                    if e.user ~= me and f:isMember(e.user) then
                        sub[#sub + 1] = e
                    end
                end
                if #sub > 0 then
                    sendServerCommand(p, "PZMCompanion", "positions", packet(now, sub))
                end
            end
        end
    end
end

local function status(now, mode, everyMs, count)
    local key = mode .. ":" .. everyMs .. ":" .. count
    if key == lastLogKey and (mode == 1 or now - lastLog < LOG_MS) then return end
    lastLogKey = key
    lastLog = now
    if mode == 1 then

        log("server: position sharing off (sandbox option)")
    else
        log("server: sharing positions, mode " .. mode .. ", every "
            .. math.floor(everyMs / 1000) .. " s, " .. count .. " players")
    end
end

local function share(now)
    local mode = shareMode()
    if mode ~= 2 and mode ~= 3 then
        status(now, 1, shareIntervalMs(), 0)
        return
    end
    local list, players = gather()
    if not list then return end
    status(now, mode, shareIntervalMs(), #list)

    if #list < 2 then return end
    if mode == 3 then
        broadcast(now, list)
    else
        sendFactions(now, list, players)
    end
end

local function tick()
    local now = getTimestampMs()
    if now < backoffUntil then return end
    if now - last < shareIntervalMs() then return end
    last = now

    local ok, err = pcall(share, now)
    if not ok then
        failures = failures + 1
        backoffUntil = now + BACKOFF_MS
        if failures == 1 or now - lastFailLog >= LOG_MS then
            lastFailLog = now
            log("server: position sharing failed (" .. tostring(err)
                .. "), failure " .. failures .. ", retrying in "
                .. math.floor(BACKOFF_MS / 1000) .. " s")
        end
    end
end

Events.OnTick.Add(tick)

log("server: loaded v1.5")
