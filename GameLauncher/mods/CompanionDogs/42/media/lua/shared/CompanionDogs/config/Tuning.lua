CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.TUNABLES = {
    { key = "COMPANION_TICK_INTERVAL", def = CD.COMPANION_TICK_INTERVAL, min = 5, max = 60, step = 5,
      label = "Dog thinking interval (ticks)",
      note  = "How often each dog decides what to do (fight, guard, hunt). Lower = reacts faster, more server load. Higher = reacts slower, lighter server. Counted in server ticks, not seconds: a healthy server runs about 16 ticks a second, a full one can drop under 5, so 60 here means anywhere from 4 to 13 seconds." },
    { key = "FOLLOW_TICK_INTERVAL", def = CD.FOLLOW_TICK_INTERVAL, min = 1, max = 10, step = 1,
      label = "Follow update interval (ticks)",
      note  = "How often a following dog corrects its path. Lower = smoother follow, more server load. Higher = laggy follow, lighter server. Counted in server ticks: on a full server running under 5 ticks a second, 8 here is almost 2 seconds." },
    { key = "DENSE_SYNC_MS", def = CD.DENSE_SYNC_MS, min = 50, max = 250, step = 50,
      label = "Moving dog sync (ms)",
      note  = "MP only. Position update rate for dogs following or fighting, sent to every player. Lower = smoother, more packets. Higher = fewer packets, choppier for players standing near someone else's dog. Never fires faster than one server tick." },
    { key = "FOLLOW_STREAM_MS", def = CD.FOLLOW_STREAM_MS, min = 50, max = 250, step = 50,
      label = "Follow stream interval (ms)",
      note  = "MP only. How often players near a following dog receive its smoothed position. Lower = smoother for them, more packets. Higher = fewer packets, slightly choppier for them. Never fires faster than one server tick." },
    { key = "FOLLOW_STREAM_RANGE", def = CD.FOLLOW_STREAM_RANGE, min = 10, max = 60, step = 5,
      label = "Smooth movement range (tiles)",
      note  = "MP only. How far away a player can be and still receive a following dog's smoothed position, a little shorter on diagonals. Lower = far fewer packets on a busy server, distant dogs move in steps. Higher = smooth further out, but the work grows with the area, so doubling this is closer to four times the cost. It also decides when a dog counts as seen by nobody, which is what triggers the slowdown further down this list." },
    { key = "FOLLOW_STREAM_MAX_DOGS", def = CD.FOLLOW_STREAM_MAX_DOGS, min = 4, max = 24, step = 1,
      label = "Max dogs per stream packet",
      note  = "MP only. How many dogs fit in one position update. Lower = smaller packets, extra dogs in a crowd move in steps. Higher = everyone stays smooth in a crowd, bigger packets. Only matters where many dogs gather in one place." },
    { key = "REGION_TTL_MS", def = CD.REGION_TTL_MS, min = 100, max = 5000, step = 100,
      label = "Walkable area memory (ms)",
      note  = "How long a dog remembers where it can walk. Lower = more accurate, more server load. Higher = lighter server, may hold old info. Raise together with the radius below." },
    { key = "REGION_REUSE_TILES", def = CD.REGION_REUSE_TILES, min = 0, max = 12, step = 1,
      label = "Walkable area reuse radius (tiles)",
      note  = "How far a dog moves before recalculating where it can walk. Lower = more accurate, more server load. Higher = lighter server, may get stuck longer. 0 = every step." },
    { key = "COMBAT_REGION_RADIUS", def = CD.COMBAT_REGION_RADIUS, min = 4, max = 20, step = 1,
      label = "Combat search radius (tiles)",
      note  = "How far a dog looks for zombies to attack. Lower = only fights up close, lighter server. Higher = engages sooner, more server load." },
    { key = "COMBAT_REGION_MAX_TILES", def = CD.COMBAT_REGION_MAX_TILES, min = 100, max = 2000, step = 50,
      label = "Combat search max tiles",
      note  = "Search size for reachable zombies. Lower = lighter server, but below 625 dogs may chase zombies they cannot reach. Higher = safer, more server load." },
    { key = "TRICK_SNIFF_SCAN_BUDGET", def = CD.TRICK_SNIFF_SCAN_BUDGET, min = 50, max = 2000, step = 50,
      label = "Sniff squares per pass (per dog)",
      note  = "Squares checked per pass when sniffing. Lower = slower sniff, lighter server. Higher = faster sniff, more server load. Search area stays the same." },
    { key = "TRICK_SNIFF_TICK_QUOTA", def = CD.TRICK_SNIFF_TICK_QUOTA, min = 100, max = 10000, step = 100,
      label = "Sniff squares per tick (all dogs)",
      note  = "Shared sniff limit for every dog. Lower = slower sniffing with many dogs, lighter server. Higher = faster sniffing, more server load." },
    { key = "SCAN_QUIET_STREAK", def = CD.SCAN_QUIET_STREAK, min = 1, max = 20, step = 1,
      label = "Empty checks before resting",
      note  = "Empty zombie checks before a dog starts checking less often. Lower = rests sooner, lighter server. Higher = stays alert longer, more server load." },
    { key = "SCAN_QUIET_SKIP_MAX", def = CD.SCAN_QUIET_SKIP_MAX, min = 0, max = 10, step = 1,
      label = "Max checks skipped when quiet",
      note  = "Max checks a resting dog skips. Lower = reacts faster, more server load. Higher = reacts slower, lighter server. 0 = never rests." },
    { key = "UNREACH_PRUNE_MIN", def = CD.UNREACH_PRUNE_MIN, min = 1, max = 120, step = 1,
      label = "Forget unreachable zombies (game minutes)",
      note  = "How often dogs forget zombies they could not reach. Lower = tries them again sooner, more server load. Higher = ignores them longer, lighter server." },
    { key = "LOADCHUNK_SCANS_PER_SEC", def = CD.LOADCHUNK_SCANS_PER_SEC, min = 4, max = 512, step = 4,
      label = "Stray spawn scans per second",
      note  = "How fast the server looks for places to spawn stray dogs. Lower = lighter server, strays may be lost when busy. Higher = more strays, more server load. Raise only if spawn.qfull stays above zero." },
    { key = "LOADCHUNK_SCANS_PER_TICK", def = CD.LOADCHUNK_SCANS_PER_TICK, min = 1, max = 16, step = 1,
      label = "Stray spawn scans per tick",
      note  = "Scans allowed in the same tick. Lower = smaller stutters, slower spawning. Higher = bigger stutters, faster spawning. Adjust the rate above first." },
    { key = "LOADCHUNK_QUEUE_MAX", def = CD.LOADCHUNK_QUEUE_MAX, min = 256, max = 16384, step = 256,
      label = "Stray spawn queue size",
      note  = "Areas waiting to be scanned. Lower = strays lost sooner when busy. Higher = nothing lost, a bit more memory. Cheap to raise." },
    { key = "LOADCHUNK_DETECT_WEIGHT", def = CD.LOADCHUNK_DETECT_WEIGHT, min = 1, max = 32, step = 1,
      label = "Quick checks per full scan",
      note  = "Quick 'is there a building here?' checks that count as one full scan. Lower = slower spawning, lighter server. Higher = faster spawning, more server load. 1 = off." },
    { key = "LOADCHUNK_MEMO_CONFIRMS", def = CD.LOADCHUNK_MEMO_CONFIRMS, min = 1, max = 5, step = 1,
      label = "Reads before marking an area done",
      note  = "Reads before an area is marked as having no place for strays. Lower = lighter server, strays may feel rare. Higher = more strays, more server load. 1 = old behaviour." },
    { key = "NET_AUTH_REPORT_MS", def = CD.NET_AUTH_REPORT_MS, min = 50, max = 1000, step = 50,
      label = "Moving dog report interval (ms)",
      note  = "MP only. How often the owner's game reports a dog that is moving. Lower = more packets, the server's copy keeps up better. Higher = fewer packets, the server's copy trails further behind and other players see the older position. This is the busy half of the pair with the idle interval below. Never fires faster than one server tick." },
    { key = "NET_AUTH_IDLE_REPORT_MS", def = CD.NET_AUTH_IDLE_REPORT_MS, min = 100, max = 2000, step = 50,
      label = "Idle dog report interval (ms)",
      note  = "MP only. How often the owner's game reports a dog standing still. Lower = more packets. Higher = fewer packets, no visible change." },
    { key = "NET_AUTH_LONE_MULT", def = CD.NET_AUTH_LONE_MULT, min = 1, max = 20, step = 1,
      label = "Unseen dog report slowdown (x)",
      note  = "MP only. A dog that no other player can see reports this many times slower than the two intervals above. Lower = more packets, no visible change. Higher = fewer packets. 1 = off. On a full server most dogs are unseen most of the time, so this is the cheapest saving in the list." },
    { key = "NET_AUTH_LONE_MAX_MS", def = CD.NET_AUTH_LONE_MAX_MS, min = 500, max = 10000, step = 250,
      label = "Unseen dog report cap (ms)",
      note  = "MP only. Slowest an unseen dog will report, whatever the slowdown above works out to. Lower = more packets. Higher = fewer packets, but the server's copy can drift further before another player walks up and sees the dog." },
    { key = "NET_AUTH_GRANT_DIST", def = CD.NET_AUTH_GRANT_DIST, min = 2, max = 28, step = 1,
      label = "Client authority distance (tiles)",
      note  = "MP only. How close the owner must be for their game to control the dog. Lower = server does more of the work, more server load. Higher = owner's game takes over sooner, smoother. Keep it below 30." },
}

CD.TUNABLE_DEFAULTS = {}
for i = 1, #CD.TUNABLES do CD.TUNABLE_DEFAULTS[CD.TUNABLES[i].key] = CD.TUNABLES[i].def end

---@param key string
---@return table|nil spec the CD.TUNABLES entry
---@nodiscard
function CD.tunableSpec(key)
    for i = 1, #CD.TUNABLES do
        if CD.TUNABLES[i].key == key then return CD.TUNABLES[i] end
    end
    return nil
end

---@param key string
---@param v any read with tonumber
---@return integer|nil value rounded and clamped to the knob's range; nil for an unknown key or a non-number
---@nodiscard
function CD.clampTunable(key, v)
    local spec = CD.tunableSpec(key)
    if not spec then return nil end
    v = tonumber(v)
    if v == nil or v ~= v then return nil end
    if v < spec.min then v = spec.min elseif v > spec.max then v = spec.max end
    return math.floor(v + 0.5)
end

-- O default e o valor vivo na primeira aplicacao, nao o do config: a primeira roda no
-- OnInitGlobalModData, depois de todo Lua carregado, entao addon de servidor que sobrescreve a
-- constante no load continua valendo enquanto o admin nao tocar no knob, e o reset volta pra ele.
local baseTaken = false
local function takeBase()
    if baseTaken then return end
    baseTaken = true
    for i = 1, #CD.TUNABLES do
        local spec = CD.TUNABLES[i]
        local live = CD[spec.key]
        if type(live) == "number" then
            spec.def = live
            CD.TUNABLE_DEFAULTS[spec.key] = live
        end
    end
end

---Writes every knob into CD from tbl, or its default when missing; nil resets them all.
---@param tbl table|nil saved knob values
function CD.applyTuning(tbl)
    takeBase()
    for i = 1, #CD.TUNABLES do
        local spec = CD.TUNABLES[i]
        local v = nil
        if tbl ~= nil then
            v = CD.clampTunable(spec.key, tbl[spec.key])
        end
        CD[spec.key] = v or spec.def
    end
    if tbl ~= nil and tbl.PERF_DEBUG ~= nil then
        CD.PERF_DEBUG = tbl.PERF_DEBUG == true
    end
    -- Booleano fica fora do TUNABLES porque aquele contrato e inteiro com min/max.
    if tbl ~= nil and tbl.NET_AUTHORITY ~= nil then
        CD.NET_AUTHORITY = tbl.NET_AUTHORITY == true
    end
    if tbl ~= nil and tbl.PASSIVE_IDLE_ENABLED ~= nil then
        CD.PASSIVE_IDLE_ENABLED = tbl.PASSIVE_IDLE_ENABLED == true
    end
    if tbl ~= nil and tbl.HUNT_ENABLED ~= nil then
        CD.HUNT_ENABLED = tbl.HUNT_ENABLED == true
    end
    CD.perfApplyLevel()
    CD.combatRegionCache = {}
end

---Current value of every knob plus the PERF_DEBUG, NET_AUTHORITY, PASSIVE_IDLE_ENABLED and HUNT_ENABLED switches.
---@return table values
---@nodiscard
function CD.tuningValues()
    local out = {}
    for i = 1, #CD.TUNABLES do
        local k = CD.TUNABLES[i].key
        out[k] = CD[k]
    end
    out.PERF_DEBUG = CD.PERF_DEBUG == true
    out.NET_AUTHORITY = CD.NET_AUTHORITY ~= false
    out.PASSIVE_IDLE_ENABLED = CD.PASSIVE_IDLE_ENABLED ~= false
    out.HUNT_ENABLED = CD.HUNT_ENABLED ~= false
    return out
end

---MP: admin access level, of the local player when none is given; SP: debug mode.
---@param player IsoPlayer|nil
---@return boolean
---@nodiscard
function CD.adminAllowed(player)
    if isClient() or isServer() then
        local adm = false
        local p = player
        if not p then
            p = getPlayer()
        end
        if p then
            adm = string.lower(tostring(p:getAccessLevel() or "")) == "admin"
        else
            adm = isAdmin()
        end
        return adm
    end
    local dbg = getDebug()
    return dbg
end
