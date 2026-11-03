CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local SPAWN_KEY = CD.MODULE .. "_StraySpawns"

local function spawnStore()
    return ModData.getOrCreate(SPAWN_KEY)
end

local processedChunks = {}

local memoVotes = {}

local spawnStats, spawnStatsOrder = {}, {}
local spawnStatsDirty, spawnStatsLastMs = false, 0

---Forgets every building already rolled for strays, so the next chunk loads roll them again.
---@return integer dropped saved building decisions removed
function CD.resetStraySpawns()
    local store = spawnStore()
    local n = 0
    for k in pairs(store) do
        store[k] = nil
        n = n + 1
    end
    for k in pairs(processedChunks) do processedChunks[k] = nil end
    for k in pairs(memoVotes) do memoVotes[k] = nil end
    spawnStats, spawnStatsOrder = {}, {}
    return n
end

CD.Server = CD.Server or {}
---Admin debug: every building rolls for strays again.
---@param player IsoPlayer
---@param args table|nil unused
CD.Server.resetspawns = function(player, args)
    if not CD.debugAllowed(player) then return end
    local n = CD.resetStraySpawns()
    CD.notifyOwner(player, "spawnsreset", { count = n })
end

local function anyRoomNamed(def, keys)
    if not def then return false end
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        local rd = rooms:get(i)
        local nm = rd and rd:getName()
        if nm then
            nm = string.lower(nm)
            for _, k in ipairs(keys) do
                if string.find(nm, k, 1, true) then return true end
            end
        end
    end
    return false
end

local POLICE_ROOM_KEYS = { "police", "prison", "jail", "military", "army", "barracks", "gunstore", "armory" }
local PETVET_ROOM_KEYS = { "petstore", "petshop", "veterinar", "vetrenar", "animalshelter", "kennel", "sanctuary" }
local FARM_ROOM_KEYS = { "barn", "farm", "stable", "coop", "silo", "henhouse", "chickencoop", "cowshed", "stables" }

---Police station, prison, military site or gun store, by room name.
---@param def BuildingDef|nil
---@return boolean
---@nodiscard
function CD.isPoliceLikeBuilding(def) return anyRoomNamed(def, POLICE_ROOM_KEYS) end
---Pet store, vet clinic, animal shelter or kennel, by room name.
---@param def BuildingDef|nil
---@return boolean
---@nodiscard
function CD.isPetVetBuilding(def) return anyRoomNamed(def, PETVET_ROOM_KEYS) end
---Barn, stable, coop, silo or other farm building, by room name.
---@param def BuildingDef|nil
---@return boolean
---@nodiscard
function CD.isFarmBuilding(def) return anyRoomNamed(def, FARM_ROOM_KEYS) end

CD.registerBuildingClass("house", function(def) return def:isResidential() and not def:isShop() end, { exclusive = true })
CD.registerBuildingClass("police", CD.isPoliceLikeBuilding, { exclusive = true })
CD.registerBuildingClass("petvet", CD.isPetVetBuilding, { exclusive = true })
CD.registerBuildingClass("farm", CD.isFarmBuilding, { skipUrbanGate = true })

---@param breedKey string
---@return table kind { atype, breed, kind } for a stray of that breed, sex rolled
---@nodiscard
function CD.makeStrayKind(breedKey)
    local sex = CD.rollBreedSex(breedKey)
    return {
        atype = CD.breedAnimalType(breedKey, sex),
        breed = CD.breedEngineName(breedKey),
        kind  = breedKey,
    }
end

---A random animal type of the default breed.
---@return table kind { atype, breed, kind }
---@nodiscard
function CD.chooseStrayKind()
    local types = CD.SPAWN_TYPES
    return { atype = types[ZombRand(0, #types) + 1], breed = CD.BREED, kind = CD.DEFAULT_BREED }
end

---@param square IsoGridSquare|nil
---@param _ any building def of the winning roll, unused
---@param forceBreedKey string|nil breed to spawn; nil picks a type of the default breed
---@return IsoAnimal|nil
function CD.spawnStray(square, _, forceBreedKey)
    if not square then return nil end
    local kind = forceBreedKey and CD.makeStrayKind(forceBreedKey) or CD.chooseStrayKind()
    if not kind then return nil end
    local a = CD.spawnDog(square:getX(), square:getY(), square:getZ(), kind.atype, kind.breed)
    if a then
        if kind.kind then
            CD.setBreed(a, kind.kind)
        end
        CD.initSkills(a)
        CD.rollBreedGenes(a)
        CD.transmit(a)
    end
    return a
end

local function drawSquare(list, used)
    while list and #list > 0 do
        local sq = table.remove(list, ZombRand(0, #list) + 1)
        local k = sq:getX() .. "," .. sq:getY()
        if not used[k] then
            used[k] = true
            return sq
        end
    end
    return nil
end

local function spawnStat(sdef)
    local species = CD.speciesOf(sdef.breed)
    local label = sdef.id
    if species ~= CD.DEFAULT_SPECIES then
        label = species .. ":" .. sdef.class
    end
    local s = spawnStats[label]
    if not s then
        s = { label = label, rolls = 0, sum = 0, won = 0, born = 0, chance = 0 }
        spawnStats[label] = s
        spawnStatsOrder[#spawnStatsOrder + 1] = s
    end
    return s
end

local function logSpawnStats()
    if not spawnStatsDirty then return end
    local now = getTimestampMs()
    if now - spawnStatsLastMs < CD.DEBUG_SPAWN_BEAT_MS then return end
    spawnStatsLastMs = now
    spawnStatsDirty = false
    CD.log(string.format("[CD-SPAWN] resumo, multiplicador de caes %.2f", CD.dogSpawnMultiplier()))
    for i = 1, #spawnStatsOrder do
        local s = spawnStatsOrder[i]
        CD.log(string.format("[CD-SPAWN]   %s: %d sorteios a %.3f%%, esperado %.2f, ganhou %d, nasceu %d",
                             s.label, s.rolls, s.chance, s.sum / 100, s.won, s.born))
    end
end

-- O sorteio vem ANTES da varredura de squares: com multiplicador baixo quase todo predio perde, e
-- varrer os 64 squares do chunk de um predio que ja perdeu e trabalho jogado fora. A ordem nao muda
-- o sorteio por predio nem a memoria de quem ja foi decidido.
local function rollWinners(buckets, store)
    local winners
    for _, sdef in ipairs(CD.StraySpawnDefs) do
        local set = buckets[sdef.class]
        if set and CD.BuildingClasses[sdef.class] and (not sdef.gate or sdef.gate()) then
            local chance = sdef.chance()
            local suffix = sdef.suffix or ""
            for key, def in pairs(set) do
                local skey = key .. suffix
                if not store[skey] then
                    -- Com chance fracionaria, o ZombRand inteiro arredonda pra cima (0,3% vira 1%).
                    local won = ZombRandFloat(0, 100) < chance
                    if CD.DEBUG_SPAWN then
                        local s = spawnStat(sdef)
                        s.rolls = s.rolls + 1
                        s.sum = s.sum + chance
                        s.chance = chance
                        if won then
                            s.won = s.won + 1
                        end
                        spawnStatsDirty = true
                    end
                    if not won then
                        store[skey] = true
                    else
                        winners = winners or {}
                        winners[#winners + 1] = { sdef = sdef, key = key, skey = skey, def = def }
                    end
                end
            end
        end
    end
    return winners
end

local function placeWinners(winners, candidates, indoorBy, urbanOK, store)
    local used = {}
    for i = 1, #winners do
        local w = winners[i]
        local sdef = w.sdef
        if urbanOK or CD.BuildingClasses[sdef.class].skipUrbanGate then
            local indoorPct = sdef.indoor
            if type(indoorPct) ~= "number" then
                indoorPct = CD.STRAY_INDOOR_PCT
            end
            local sq
            if indoorPct > 0 and ZombRand(0, 100) < indoorPct then
                sq = drawSquare(indoorBy and indoorBy[w.key], used)
            end
            sq = sq or drawSquare(candidates, used)
            if sq and CD.spawnStray(sq, w.def, sdef.breed) then
                store[w.skey] = true
                if CD.DEBUG_SPAWN then
                    local s = spawnStat(sdef)
                    s.born = s.born + 1
                    CD.log(string.format("[CD-SPAWN] nasceu %s em %d,%d, chance %.3f%%",
                                         sdef.id, sq:getX(), sq:getY(), s.chance))
                end
            end
        end
    end
end

local function anyUrban(list)
    if not list then return false end
    for i = 1, #list do
        if CD.isUrbanSquare(list[i]) then return true end
    end
    return false
end

local function allBuildingsDecided(buckets, store)
    for _, sdef in ipairs(CD.StraySpawnDefs) do
        if not sdef.gate or sdef.gate() then
            local set = buckets[sdef.class]
            if set then
                local suffix = sdef.suffix or ""
                for key in pairs(set) do
                    if not store[key .. suffix] then return false end
                end
            end
        end
    end
    return true
end

local function chunkKey(chunk)
    local wx, wy = chunk.wx, chunk.wy
    local ok = type(wx) == "number" and type(wy) == "number"
    if CD._chunkKeyMode == nil then
        CD._chunkKeyMode = ok and "wx/wy" or "square(0,0,0)"
        CD.log("[CD-SPAWN] chave de memo de chunk por " .. CD._chunkKeyMode ..
              (ok and "" or " (fallback: chunk sem square em z=0 fica FORA do memo)"))
    end
    if ok then return (wx * 8) .. "," .. (wy * 8) end
    local sq = chunk:getGridSquare(0, 0, 0)
    return sq and (sq:getX() .. "," .. sq:getY()) or nil
end

local buildingClasses = {}
local buildingClassesN = 0

local function classesFresh()
    local n = #CD.BuildingClassOrder
    if n ~= buildingClassesN then
        buildingClasses = {}
        buildingClassesN = n
    end
    return n
end

local function classifyPeek(key)
    classesFresh()
    return buildingClasses[key]
end

local function classifyBuilding(def, key)
    local n = classesFresh()
    local hit = buildingClasses[key]
    if hit then return hit end
    hit = {}
    local exclusiveTaken = false
    for i = 1, n do
        local cname = CD.BuildingClassOrder[i]
        local cls = CD.BuildingClasses[cname]
        if cls and not (cls.exclusive and exclusiveTaken) then
            if cls.match(def) then
                hit[#hit + 1] = cname
                if cls.exclusive then
                    exclusiveTaken = true
                end
            end
        end
    end
    buildingClasses[key] = hit
    return hit
end

local pendQ, pendHead, pendTail = {}, 1, 0
local scansThisTick = 0

local function memoConfirms()
    local n = CD.LOADCHUNK_MEMO_CONFIRMS
    if type(n) ~= "number" or n < 1 then
        n = 2
    end
    return n
end

local function memoTransient(ckey, counter)
    if not ckey then return end
    local v = (memoVotes[ckey] or 0) + 1
    if v >= memoConfirms() then
        memoVotes[ckey] = nil
        processedChunks[ckey] = true
        CD.perfCount(counter)
    else
        memoVotes[ckey] = v
        CD.perfCount("spawn.vote")
    end
end

local function memoDecided(ckey)
    if not ckey then return end
    memoVotes[ckey] = nil
    processedChunks[ckey] = true
    CD.perfCount("spawn.memo.decided")
end

local function detectChunk(chunk)
    local buckets, pending, anyBuilding, seen, live = {}, nil, false, {}, 0
    for ly = 0, 7 do
        for lx = 0, 7 do
            local sq = chunk:getGridSquare(lx, ly, 0)
            if sq then
                live = live + 1
                local b = sq:getBuilding()
                local def = b and b:getDef()
                if def then
                    local key = def:getX()..","..def:getY()..","..def:getX2()..","..def:getY2()
                    if not seen[key] then
                        seen[key] = true
                        local hit = classifyPeek(key)
                        if hit == nil then
                            pending = pending or {}
                            pending[key] = def
                        else
                            for i = 1, #hit do
                                local cname = hit[i]
                                buckets[cname] = buckets[cname] or {}
                                buckets[cname][key] = def
                                anyBuilding = true
                            end
                        end
                    end
                end
            end
        end
    end
    return buckets, pending, anyBuilding, live
end

local function resolveChunk(chunk, ckey, buckets, pending)
    if pending then
        for key, def in pairs(pending) do
            local hit = classifyBuilding(def, key)
            for i = 1, #hit do
                local cname = hit[i]
                buckets[cname] = buckets[cname] or {}
                buckets[cname][key] = def
            end
        end
    end

    local anyBuilding = false
    for _ in pairs(buckets) do
        anyBuilding = true
        break
    end
    if not anyBuilding then
        memoTransient(ckey, "spawn.memo.nobuild")
        return
    end

    local store = spawnStore()
    if allBuildingsDecided(buckets, store) then
        memoDecided(ckey)
        return
    end

    local winners = rollWinners(buckets, store)
    if not winners then
        CD.perfCount("spawn.roll.skip")
        if allBuildingsDecided(buckets, store) then
            memoDecided(ckey)
        end
        return
    end

    local outdoor, anyFree, indoorBy
    for ly = 0, 7 do
        for lx = 0, 7 do
            local sq = chunk:getGridSquare(lx, ly, 0)
            if sq and not sq:isWaterSquare() and sq:isFree(true) and sq:isSolidFloor() then
                local b = sq:getBuilding()
                if not b and sq:isOutside() then
                    outdoor = outdoor or {}
                    outdoor[#outdoor + 1] = sq
                else
                    anyFree = anyFree or {}
                    anyFree[#anyFree + 1] = sq
                    local def = b and sq:getRoom() and b:getDef()
                    if def then
                        local key = def:getX()..","..def:getY()..","..def:getX2()..","..def:getY2()
                        indoorBy = indoorBy or {}
                        indoorBy[key] = indoorBy[key] or {}
                        local list = indoorBy[key]
                        list[#list + 1] = sq
                    end
                end
            end
        end
    end

    local candidates = outdoor or anyFree
    if not candidates then
        memoTransient(ckey, "spawn.memo.notile")
        return
    end

    local urbanOK = anyUrban(outdoor) or anyUrban(anyFree)
    placeWinners(winners, candidates, indoorBy, urbanOK, store)
end

local function scanBudget()
    local n = CD.LOADCHUNK_SCANS_PER_TICK
    if type(n) ~= "number" or n < 1 then
        n = 1
    end
    return n
end

local function detectCost()
    local w = CD.LOADCHUNK_DETECT_WEIGHT
    if type(w) ~= "number" or w < 1 then
        w = 8
    end
    return 1 / w
end

local scanCredit, lastDrainMs = 0, nil

local function enqueue(e)
    local qmax = CD.LOADCHUNK_QUEUE_MAX
    if (pendTail - pendHead + 1) < qmax then
        pendTail = pendTail + 1
        pendQ[pendTail] = e
        CD.perfCount("spawn.queued")
    else
        CD.perfCount("spawn.qfull")
    end
end

-- Os dois chamadores ja barram multiplicador zero; nada aqui memoriza chunk, entao subir o knob
-- depois volta a valer pra eles.
local function runChunk(chunk, ckey, buckets, pending)
    if not buckets then
        local dcost = detectCost()
        if scanCredit < dcost then return { chunk = chunk, key = ckey } end
        scanCredit = scanCredit - dcost
        CD.perfCount("spawn.detect")

        local anyBuilding, live
        buckets, pending, anyBuilding, live = detectChunk(chunk)
        if live == 0 then
            CD.perfCount("spawn.dead")
            return nil
        end
        if not pending then
            if not anyBuilding then
                memoTransient(ckey, "spawn.memo.nobuild")
                return nil
            end
            if allBuildingsDecided(buckets, spawnStore()) then
                memoDecided(ckey)
                return nil
            end
        end
    end

    local rcost = 1 - detectCost()
    if scansThisTick >= scanBudget() or scanCredit < rcost then
        return { chunk = chunk, key = ckey, buckets = buckets, pending = pending }
    end
    scanCredit = scanCredit - rcost
    scansThisTick = scansThisTick + 1
    CD.perfCount("spawn.scans")
    resolveChunk(chunk, ckey, buckets, pending)
    return nil
end

local function drainPendingChunks()
    scansThisTick = 0
    if CD.DEBUG_SPAWN then
        logSpawnStats()
    end
    -- Knob em zero nao tem backlog que valha: esvaziar de uma vez cala a fila no mesmo tick em que
    -- o admin desliga o spawn, em vez de escoar 4096 chunks de credito em credito.
    if CD.dogSpawnMultiplier() <= 0 then
        CD.perfCount("spawn.mult.zero")
        if pendHead <= pendTail then
            for i = pendHead, pendTail do pendQ[i] = nil end
            pendHead, pendTail = 1, 0
        end
        lastDrainMs = nil
        return
    end
    local now = getTimestampMs()
    local dt = (lastDrainMs and (now - lastDrainMs)) or 0
    lastDrainMs = now
    if dt < 0 then
        dt = 0
    end
    local rate = CD.LOADCHUNK_SCANS_PER_SEC
    if type(rate) ~= "number" or rate <= 0 then
        rate = 8
    end
    scanCredit = scanCredit + dt * rate / 1000
    local ccap = CD.LOADCHUNK_CREDIT_MAX
    if type(ccap) ~= "number" or ccap < 1 then
        ccap = 8
    end
    if scanCredit > ccap then
        scanCredit = ccap
    end

    local dcost = detectCost()
    while pendHead <= pendTail do
        local e = pendQ[pendHead]
        local dead = (not e) or (not e.chunk)
            or (e.key ~= nil and (processedChunks[e.key] or chunkKey(e.chunk) ~= e.key))
        if dead then
            pendQ[pendHead] = nil
            pendHead = pendHead + 1
        else
            local need = e.buckets and (1 - dcost) or dcost
            if scanCredit < need then break end
            if e.buckets and scansThisTick >= scanBudget() then break end
            pendQ[pendHead] = nil
            pendHead = pendHead + 1
            local nx = runChunk(e.chunk, e.key, e.buckets, e.pending)
            if nx then
                enqueue(nx)
                break
            end
        end
    end
    if pendHead > pendTail then
        pendHead, pendTail = 1, 0
    end
    CD.perfGauge("spawn.qdepth", pendTail - pendHead + 1)
end

local function onLoadChunk(chunk)
    if not CD.urbanSpawnEnabled() then return end
    if not chunk then return end
    -- Antes da chave: com o knob em zero, montar a string de memo por chunk carregado era lixo puro.
    if CD.dogSpawnMultiplier() <= 0 then return end

    local ckey = chunkKey(chunk)
    if ckey and processedChunks[ckey] then return end

    local e = runChunk(chunk, ckey, nil, nil)
    if e then
        enqueue(e)
    end
end

if not isClient() then
    Events.OnInitGlobalModData.Add(function() spawnStore() end)
    CD.evAdd(Events.LoadChunk, onLoadChunk, "srv.loadchunk")
    CD.evAdd(Events.OnTick, drainPendingChunks, "srv.spawnqueue")
end
