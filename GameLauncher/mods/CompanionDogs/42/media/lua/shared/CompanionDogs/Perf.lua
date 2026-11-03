CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD._perfLv = 0

CD._perfBlk = {}
CD._perfCalls = {}
CD._perfCnt = {}

CD._perfWinBlk = {}
CD._perfWinCalls = {}
CD._perfWinCnt = {}
CD._perfWinGauge = {}

CD._pCur = "other"
CD._pLast = 0
CD._pStack = {}
CD._pDepth = 0

CD._tk = {}
CD._tv = {}
CD._tn = 0

CD._perfPhase = {}

CD._perfLast = { blocks = {}, counters = {}, gauges = {} }

CD._perfCsvBuf = {}
CD._perfCsvRows = 0
CD._perfCsvArmedMs = nil
CD._perfTraceLeft = 0
CD._perfSessionId = nil
CD._perfCalMs = nil
CD._perfCalUs = nil
CD._perfCalSteps = nil
CD._perfSpikeMs = nil
CD._perfAllocPrev = nil
CD._perfDogMin, CD._perfDogMax, CD._perfDogSum, CD._perfDogN = nil, nil, 0, 0

-- So medicao: quantas trocas de estado a engine avisa por segundo, de quem, e quanto custa ouvir.
-- E o que decide se sentinela e trava de grito podem virar evento. Ouvinte so existe com o medidor ligado.
local aiHooked = false
local function onAIStateChange(owner, cur)
    if CD._perfLv < 1 or not owner then return end
    CD.perfEnter("evt.aistate")
    CD.perfCount("evt.aistate")
    if instanceof(owner, "IsoZombie") then
        CD.perfCount("evt.aistate.zombie")
        local t = owner:getTarget()
        if t and instanceof(t, "IsoPlayer") and not instanceof(t, "IsoAnimal") then
            CD.perfCount("evt.aistate.chase")
        end
    elseif instanceof(owner, "IsoAnimal") then
        CD.perfCount("evt.aistate.animal")
        if CD.isDog(owner) then
            CD.perfCount("evt.aistate.dog")
            local name = cur and tostring(cur) or ""
            if string.find(name, "Alerted", 1, true) then
                CD.perfCount("evt.aistate.dogalert")
            elseif string.find(name, "PathFind", 1, true) then
                CD.perfCount("evt.aistate.dogpath")
            end
        end
    end
    CD.perfExit()
end

local function perfAIStateHook(on)
    if on == aiHooked then return end
    aiHooked = on
    if on then
        Events.OnAIStateChange.Add(onAIStateChange)
    else
        Events.OnAIStateChange.Remove(onAIStateChange)
    end
end

---Applies CD.PERF_DEBUG and CD.PERF_LEVEL to the meter.
---@return integer level 0 when off, else 1 or 2
function CD.perfApplyLevel()
    -- Sem isto o primeiro intervalo de tick depois de religar a medicao seria o tempo desligado.
    CD._perfTickPrevMs = nil
    if not CD.PERF_DEBUG then
        CD._perfLv = 0
        perfAIStateHook(false)
        return 0
    end
    local lv = tonumber(CD.PERF_LEVEL) or 1
    if lv < 1 then lv = 1 elseif lv > 2 then lv = 2 end
    CD._perfLv = lv
    perfAIStateHook(true)
    return lv
end

---Adds dt to a zone total and to the trace of the current tick, which keeps up to 4096 entries.
---@param key string zone key
---@param dt number milliseconds
function CD.perfCredit(key, dt)
    local blk = CD._perfBlk
    blk[key] = (blk[key] or 0) + dt
    local n = CD._tn
    if n < 4096 then
        n = n + 1
        CD._tn = n
        CD._tk[n] = key
        CD._tv[n] = dt
    end
end

---Opens a zone: until the matching perfExit, time is credited to key, nested zones excluded.
---@param key string zone key
function CD.perfEnter(key)
    local now = getTimestampMs()
    local d = CD._pDepth
    if d > 0 then
        local dt = now - CD._pLast
        if dt > 0 then
            CD.perfCredit(CD._pCur, dt)
        end
    else
        local ph, k = CD._perfPhase, now % 16
        ph[k] = (ph[k] or 0) + 1
    end
    d = d + 1
    CD._pDepth = d
    CD._pStack[d] = CD._pCur
    CD._pCur = key
    CD._pLast = now
end

---Closes the innermost zone; ignored when no zone is open.
function CD.perfExit()
    local d = CD._pDepth
    if d < 1 then return end
    local now = getTimestampMs()
    local dt = now - CD._pLast
    local cur = CD._pCur
    if dt > 0 then
        CD.perfCredit(cur, dt)
    end
    local c = CD._perfCalls
    c[cur] = (c[cur] or 0) + 1
    CD._pCur = CD._pStack[d]
    CD._pDepth = d - 1
    CD._pLast = now
end

-- Seis argumentos e nao tres: com menos, o call site cai em `function() ... end` e aloca uma
-- closure por chamada mesmo com a medicao desligada.
---@param key string zone the call is credited to
---@param fn function
---@param a any
---@param b any
---@param c any
---@param d any
---@param e any
---@param f any
---@return any r1 first result of fn
---@return any r2 second result of fn; later ones are dropped while measuring
function CD.pz(key, fn, a, b, c, d, e, f)
    if CD._perfLv < 1 then return fn(a, b, c, d, e, f) end
    CD.perfEnter(key)
    local r1, r2 = fn(a, b, c, d, e, f)
    CD.perfExit()
    return r1, r2
end

---Same as pz, but only measured at level 2.
---@param key string zone the call is credited to
---@param fn function
---@param a any
---@param b any
---@param c any
---@param d any
---@param e any
---@param f any
---@return any r1 first result of fn
---@return any r2 second result of fn; later ones are dropped while measuring
function CD.pzd(key, fn, a, b, c, d, e, f)
    if CD._perfLv < 2 then return fn(a, b, c, d, e, f) end
    CD.perfEnter(key)
    local r1, r2 = fn(a, b, c, d, e, f)
    CD.perfExit()
    return r1, r2
end

---Registers fn on an engine event; while measuring, each run is credited to key.
---@param ev table engine event, such as Events.OnTick
---@param fn function
---@param key string zone the handler is credited to
function CD.evAdd(ev, fn, key)
    ev.Add(function(a, b, c, d)
        if CD._perfLv < 1 then return fn(a, b, c, d) end
        CD.perfEnter(key)
        fn(a, b, c, d)
        CD.perfExit()
    end)
end

---Opens a zone that perfOut names when it closes.
---@return boolean|nil t0 token for perfOut, nil while measuring is off
function CD.perfIn()
    if CD._perfLv < 1 then return nil end
    CD.perfEnter("_pending")
    return true
end

---Closes the zone opened by perfIn under the name key.
---@param key string zone key
---@param t0 boolean|nil token from perfIn; nil does nothing
function CD.perfOut(key, t0)
    if not t0 then return end
    if CD._pDepth > 0 then
        CD._pCur = key
    end
    CD.perfExit()
end

---Same as perfIn, but only measured at level 2.
---@return boolean|nil t0 token for perfOut2, nil below level 2
function CD.perfIn2()
    if CD._perfLv < 2 then return nil end
    CD.perfEnter("_pending")
    return true
end

CD.perfOut2 = CD.perfOut

---Adds to a counter, reported as a rate per second.
---@param key string counter key
---@param n number|nil amount to add, 1 when nil
function CD.perfCount(key, n)
    if CD._perfLv < 1 then return end
    CD._perfCnt[key] = (CD._perfCnt[key] or 0) + (n or 1)
end

-- Amostra de VALOR, nao de ocorrencia. Fila e estoque contados por `perfCount` saem no relatorio
-- divididos pela janela, e `spawn.qdepth 103/s` ja foi lido por um admin como 103 spawns por
-- segundo, quando eram 10 chunks na fila a 10 ticks. Gauge sai como media e maximo.
---@param key string gauge key
---@param v number sampled value
function CD.perfGauge(key, v)
    if CD._perfLv < 1 then return end
    local g = CD._perfWinGauge[key]
    if not g then
        CD._perfWinGauge[key] = { sum = v, n = 1, max = v }
        return
    end
    g.sum = g.sum + v
    g.n = g.n + 1
    if v > g.max then
        g.max = v
    end
end

local pathLastMs = {}
local pathLastN = 0

---Counts a path request by subsystem, and a cancel when that subsystem repaths the dog within FOLLOW_PATH_RESOLVE_MS.
---@param animal IsoAnimal
---@param system string subsystem that asked for the path
function CD.pathStatEmit(animal, system)
    if CD.DEBUG_ZPATH then
        CD.zpathEmit(animal, system)
    end
    if (CD._perfLv or 0) < 1 or type(system) ~= "string" then return end
    CD._perfCnt["path.emit"] = (CD._perfCnt["path.emit"] or 0) + 1
    CD._perfCnt["path.emit." .. system] = (CD._perfCnt["path.emit." .. system] or 0) + 1
    local id = animal:getOnlineID()
    -- Chave montada como string: chave numerica calculada nao casa no Kahlua.
    local k = tostring(id) .. "|" .. system
    local now = getTimestampMs()
    local prev = pathLastMs[k]
    if prev and (now - prev) < CD.FOLLOW_PATH_RESOLVE_MS then
        CD._perfCnt["path.cancel." .. system] = (CD._perfCnt["path.cancel." .. system] or 0) + 1
    end
    if prev == nil then
        pathLastN = pathLastN + 1
        if pathLastN > 512 then
            pathLastMs = {}
            pathLastN = 0
        end
    end
    pathLastMs[k] = now
end

---Counts by subsystem a dog whose path was taken over by a sound it answered.
---@param animal IsoAnimal
---@param system string subsystem that owned the path
---@return boolean hijacked always false while measuring is off
function CD.pathStatHijack(animal, system)
    if (CD._perfLv or 0) < 1 or type(system) ~= "string" then return false end
    if not CD.pathHijacked then return false end
    if not CD.pathHijacked(animal) then return false end
    CD._perfCnt["path.hijack." .. system] = (CD._perfCnt["path.hijack." .. system] or 0) + 1
    return true
end
