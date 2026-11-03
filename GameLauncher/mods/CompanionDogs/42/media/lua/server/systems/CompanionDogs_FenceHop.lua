CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local landSettling = {}
local FENCE_DIRS
local function fenceDirs()
    if not FENCE_DIRS then
        FENCE_DIRS = {
            { dx = 0, dy = -1, dir = IsoDirections.N }, { dx = 0, dy = 1, dir = IsoDirections.S },
            { dx = -1, dy = 0, dir = IsoDirections.W }, { dx = 1, dy = 0, dir = IsoDirections.E },
        }
    end
    return FENCE_DIRS
end

local function edgeKey(ax, ay, bx, by)
    return string.format("%d:%d:%d:%d", math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by))
end

---A low hoppable fence on the edge between the adjacent tiles, crossed by the one-tile step dx, dy.
---@param from IsoGridSquare|nil
---@param to IsoGridSquare|nil
---@param dx integer -1, 0 or 1
---@param dy integer -1, 0 or 1
---@return boolean
---@nodiscard
function CD.lowFenceCrossable(from, to, dx, dy)
    local ok = false
    if from and to then
        if dx > 0 then     ok = to:has(IsoFlagType.HoppableW)
        elseif dx < 0 then ok = from:has(IsoFlagType.HoppableW)
        elseif dy > 0 then ok = to:has(IsoFlagType.HoppableN)
        else               ok = from:has(IsoFlagType.HoppableN)
        end
    end
    return ok
end

local function fenceEdge(from, to, dx, dy)
    local ok = false
    if from and to then
        if dx > 0 then     ok = to:has(IsoFlagType.HoppableW) or to:has(IsoFlagType.TallHoppableW)
        elseif dx < 0 then ok = from:has(IsoFlagType.HoppableW) or from:has(IsoFlagType.TallHoppableW)
        elseif dy > 0 then ok = to:has(IsoFlagType.HoppableN) or to:has(IsoFlagType.TallHoppableN)
        else               ok = from:has(IsoFlagType.HoppableN) or from:has(IsoFlagType.TallHoppableN)
        end
    end
    return ok
end

local function fenceCrossable(from, to, dx, dy)
    if CD.lowFenceCrossable(from, to, dx, dy) then return true end
    if not CD.FENCE_HOP_TALL then return false end
    if not (from and to) then return false end
    local owner, tall, trans
    if dx > 0 then     owner, tall, trans = to,   IsoFlagType.TallHoppableW, IsoFlagType.WallWTrans
    elseif dx < 0 then owner, tall, trans = from, IsoFlagType.TallHoppableW, IsoFlagType.WallWTrans
    elseif dy > 0 then owner, tall, trans = to,   IsoFlagType.TallHoppableN, IsoFlagType.WallNTrans
    else               owner, tall, trans = from, IsoFlagType.TallHoppableN, IsoFlagType.WallNTrans
    end
    if not (owner:has(tall) and owner:has(trans)) then return false end
    if from:has(IsoFlagType.CantClimb) or to:has(IsoFlagType.CantClimb) then return false end
    if from:getBuilding() ~= nil or to:getBuilding() ~= nil then return false end
    if from:isSolid() or from:isSolidTrans() or to:isSolid() or to:isSolidTrans() then return false end
    return true
end

---Adjacent tile past a crossable fence that brings the dog at least FENCE_HOP_MIN_GAIN closer to ref.
---@param animal IsoAnimal
---@param ref IsoGameCharacter|table what the dog heads for; any object with getX and getY
---@param d table|nil companion ModData, for the recross and back-step blocks
---@param now number timestamp in ms
---@param crossPred function|nil edge test called as (from, to, dx, dy); nil uses the low and tall fence test
---@return IsoGridSquare|nil landing nil when no fence qualifies
---@return integer|nil dx
---@return integer|nil dy
---@return string|nil edge key of the fence edge
---@nodiscard
function CD.findFenceCrossing(animal, ref, d, now, crossPred)
    local cur = animal:getCurrentSquare()
    if not cur then return nil end
    local cell = getCell()
    local cross = crossPred or fenceCrossable
    local ox, oy = ref:getX(), ref:getY()
    local cx, cy = cur:getX() + 0.5, cur:getY() + 0.5
    local curGap = (ox - cx) * (ox - cx) + (oy - cy) * (oy - cy)
    local minGain = CD.FENCE_HOP_MIN_GAIN
    local blockedKey = (d and d.recrossUntilMs and now < d.recrossUntilMs) and d.recrossEdge or nil
    local bd = (d and d.backBlockUntilMs and now < d.backBlockUntilMs) and d.backBlockDir or nil
    for _, e in ipairs(fenceDirs()) do
        local adj = (not (bd and e.dx == bd.dx and e.dy == bd.dy))
            and cell:getGridSquare(cur:getX() + e.dx, cur:getY() + e.dy, cur:getZ()) or nil
        if adj then
            if cross(cur, adj, e.dx, e.dy) then
                local key = edgeKey(cur:getX(), cur:getY(), adj:getX(), adj:getY())
                local ax, ay = adj:getX() + 0.5, adj:getY() + 0.5
                if key ~= blockedKey and CD.squareHasFloor(adj)
                   and (ox - ax) * (ox - ax) + (oy - ay) * (oy - ay) <= curGap - minGain then
                    return adj, e.dx, e.dy, key
                end
            end
        end
    end
    return nil
end

---Walks open tiles from the dog toward ref and returns the first crossable fence on the way.
---@param animal IsoAnimal
---@param ref IsoGameCharacter|table what the dog heads for; any object with getX and getY
---@param maxTiles integer|nil steps to look ahead; 5 when nil
---@param d table|nil companion ModData, for the recross and back-step blocks
---@param now number timestamp in ms
---@param crossPred function|nil edge test called as (from, to, dx, dy); nil uses the low and tall fence test
---@return IsoGridSquare|nil landing nil when no fence is found before a wall or the step limit
---@return integer|nil dx
---@return integer|nil dy
---@return string|nil edge key of the fence edge
---@return IsoGridSquare|nil from the tile the hop starts from
---@nodiscard
function CD.findFenceTowardOwner(animal, ref, maxTiles, d, now, crossPred)
    local cur = animal:getCurrentSquare()
    if not cur then return nil end
    local cell = getCell()
    local cz = cur:getZ()
    local cross = crossPred or fenceCrossable
    local tx, ty = math.floor(ref:getX()), math.floor(ref:getY())
    local blockedKey = (d and d.recrossUntilMs and now < d.recrossUntilMs) and d.recrossEdge or nil
    local bd = (d and d.backBlockUntilMs and now < d.backBlockUntilMs) and d.backBlockDir or nil
    local ax, ay, aSq = cur:getX(), cur:getY(), cur
    for _ = 1, (maxTiles or 5) do
        local ddx, ddy = tx - ax, ty - ay
        if ddx == 0 and ddy == 0 then return nil end
        local px, py = 0, 0
        if math.abs(ddx) >= math.abs(ddy) then
            px = (ddx > 0) and 1 or -1
        else
            py = (ddy > 0) and 1 or -1
        end
        local steps = { { px, py } }
        if ddx ~= 0 and px == 0 then
            steps[#steps + 1] = { (ddx > 0) and 1 or -1, 0 }
        end
        if ddy ~= 0 and py == 0 then
            steps[#steps + 1] = { 0, (ddy > 0) and 1 or -1 }
        end
        for _, s in ipairs(steps) do
            if not (bd and s[1] == bd.dx and s[2] == bd.dy) then
                local bSq = cell:getGridSquare(ax + s[1], ay + s[2], cz)
                if bSq and CD.squareHasFloor(bSq) and cross(aSq, bSq, s[1], s[2]) then
                    local key = edgeKey(aSq:getX(), aSq:getY(), bSq:getX(), bSq:getY())
                    if key ~= blockedKey then return bSq, s[1], s[2], key, aSq end
                end
            end
        end
        local nb = cell:getGridSquare(ax + px, ay + py, cz)
        if not nb then return nil end
        local wall = false
        if aSq then
            wall = aSq:isWallTo(nb) or nb:isSolid() or nb:isSolidTrans()
        end
        if wall then return nil end
        ax, ay, aSq = ax + px, ay + py, nb
    end
    return nil
end

---A wall, or a solid neighbor, blocks the step from sq to the adjacent nb.
---@param sq IsoGridSquare
---@param nb IsoGridSquare
---@return boolean
---@nodiscard
CD.regWallBetween = function(sq, nb)
    return sq:isWallTo(nb) or nb:isSolid() or nb:isSolidTrans()
end
---A closed door or a vehicle blocks the step from sq to the adjacent nb.
---@param sq IsoGridSquare
---@param nb IsoGridSquare
---@return boolean
---@nodiscard
CD.regBlockedBetween = function(sq, nb)
    return sq:isDoorBlockedTo(nb)
        or nb:isVehicleIntersecting()
end

CD.combatRegionCache = {}
CD.combatUnreach = {}
---Tiles the dog can walk to from where it stands, by breadth-first steps; cached per dog for REGION_TTL_MS.
---@param animal IsoAnimal
---@return table|nil region { set, sx, sy, z, radius, truncated, drift, stamp }; set maps tile key to steps; nil off a square
function CD.combatReachRegion(animal)
    local cur = animal:getCurrentSquare()
    if not cur then return nil end
    local now = getTimestampMs()
    local cz = cur:getZ()
    local sx, sy = cur:getX(), cur:getY()
    local aid = animal:getOnlineID()
    local KS = CD.TILEKEY_STRIDE
    local c = CD.combatRegionCache[aid]
    if c and c.z == cz and (now - c.stamp) < CD.REGION_TTL_MS then
        if c.sx == sx and c.sy == sy then
            c.drift = 0
            return c
        end
        local reuse = CD.REGION_REUSE_TILES
        if reuse > 0 and not c.truncated then
            local dx, dy = sx - c.sx, sy - c.sy
            if dx < 0 then
                dx = -dx
            end
            if dy < 0 then
                dy = -dy
            end
            local drift = (dx > dy) and dx or dy
            if drift <= reuse and c.set[sx * KS + sy] then
                c.drift = drift
                return c
            end
        end
    end
    local cell = getCell()
    if not cell then return nil end
    local radius = CD.COMBAT_REGION_RADIUS
    local maxTiles = CD.COMBAT_REGION_MAX_TILES
    local vaultLow = CD.COMBAT_FENCE_HOP and ((not isServer()) or CD.COMBAT_FENCE_HOP_MP)
    local set = { [sx * KS + sy] = 0 }
    local queue = { cur }
    local qdepth = { 0 }
    local qi, count, truncated = 1, 1, false
    while qi <= #queue do
        local sq = queue[qi]
        local cd0 = qdepth[qi]
        qi = qi + 1
        local cx0, cy0 = sq:getX(), sq:getY()
        for _, e in ipairs(fenceDirs()) do
            local nx, ny = cx0 + e.dx, cy0 + e.dy
            if math.abs(nx - sx) <= radius and math.abs(ny - sy) <= radius then
                local nkey = nx * KS + ny
                if not set[nkey] then
                    local nb = cell:getGridSquare(nx, ny, cz)
                    if nb then
                        local canEnter
                        if fenceCrossable(sq, nb, e.dx, e.dy) then
                            canEnter = vaultLow and CD.lowFenceCrossable(sq, nb, e.dx, e.dy) and CD.squareHasFloor(nb)
                        else
                            local wall = CD.regWallBetween(sq, nb) or CD.regBlockedBetween(sq, nb)
                            canEnter = not wall and CD.squareHasFloor(nb)
                        end
                        if canEnter then
                            if count >= maxTiles then truncated = true
                            else
                                set[nkey] = cd0 + 1
                                count = count + 1
                                queue[#queue + 1] = nb
                                qdepth[#qdepth + 1] = cd0 + 1
                            end
                        end
                    end
                end
            end
        end
    end
    c = { stamp = now, z = cz, set = set, sx = sx, sy = sy, radius = radius, truncated = truncated, drift = 0 }
    CD.combatRegionCache[aid] = c
    return c
end

---Starts the scripted hop onto toSq, or one tile further when that lands closer to owner; lame dogs and floorless tiles are refused.
---@param animal IsoAnimal
---@param toSq IsoGridSquare
---@param dx integer
---@param dy integer
---@param owner IsoGameCharacter|nil what the dog heads for, owner or zombie; nil keeps toSq
---@param key string|nil edge key, blocked for a recross after landing
function CD.startFenceHop(animal, toSq, dx, dy, owner, key)
    local d = CD.data(animal)
    if CD.vetLame(d) then return end
    CD.clearClimbVars(animal)
    animal:stopAllMovementNow()
    local cell = getCell()
    local fz = toSq:getZ()
    -- Nunca pousar num tile sem chao: a engine trata como suspenso e roda o caminho de queda humano (NPE).
    if not CD.squareHasFloor(toSq) then return end
    local cx, cy, ex, ey = toSq:getX() + 0.5, toSq:getY() + 0.5, toSq:getX(), toSq:getY()
    local beyond = cell:getGridSquare(toSq:getX() + dx, toSq:getY() + dy, fz)
    local openBeyond = beyond ~= nil and not beyond:isSolid() and not beyond:isSolidTrans()
                       and not fenceEdge(toSq, beyond, dx, dy)
                       and not toSq:isWallTo(beyond)
                       and CD.squareHasFloor(beyond)
    if openBeyond and owner then
        local ox, oy = owner:getX(), owner:getY()
        local bx, by = beyond:getX() + 0.5, beyond:getY() + 0.5
        if (ox - bx) ^ 2 + (oy - by) ^ 2 < (ox - cx) ^ 2 + (oy - cy) ^ 2 then
            cx, cy, ex, ey = bx, by, beyond:getX(), beyond:getY()
        end
    end
    local dir = (dx > 0 and IsoDirections.E) or (dx < 0 and IsoDirections.W) or (dy > 0 and IsoDirections.S) or IsoDirections.N
    d.fenceHop = { sx = animal:getX(), sy = animal:getY(), sz = animal:getZ(),
                   cx = cx, cy = cy, ex = ex, ey = ey, z = fz, prog = 0, edge = key, dir = dir,
                   startMs = getTimestampMs() }
    CD.fenceHopping[animal:getOnlineID()] = animal
    d.backBlockDir = { dx = -dx, dy = -dy }
    d.backBlockUntilMs = getTimestampMs() + CD.FENCE_BACKBLOCK_MS
    CD.emitEatVar(animal, true, CD.JUMP_ANIM_VAR)
    animal:setVariable("animalRunning", false)
    animal:setDir(dir)
    if dx ~= 0 or dy ~= 0 then
        animal:setForwardDirection(dx, dy)
    end
    if isServer() then
        local dirIdx = dir and dir:ordinal()   -- IsoDirections nao tem index(); ordinal() faz round-trip com o fromIndex() do client
        sendServerCommand(CD.MODULE, "fencehop", {
            id = animal:getOnlineID(),
            sx = d.fenceHop.sx, sy = d.fenceHop.sy, sz = d.fenceHop.sz,
            cx = cx, cy = cy, z = fz, dir = dirIdx, dx = dx, dy = dy,
            step = CD.FENCE_HOP_STEP, arc = CD.FENCE_HOP_ARC,
        })
        animal:sendExtraUpdateToClients()
    end
end

-- devolve true quando o pulo acabou e o registro deve sair de CD.fenceHopping
local function fenceHopStep(id, animal)
    if not animal:isExistInTheWorld() then return true end
    local d = CD.data(animal)
    local h = d and d.fenceHop
    if not h then return true end
    h.prog = h.startMs and math.min(1, (getTimestampMs() - h.startMs) / CD.FENCE_HOP_DURATION_MS)
             or math.min(1, h.prog + CD.FENCE_HOP_STEP)
    local p = h.prog
    local ph = p * p * (3 - 2 * p)
    local arc = CD.FENCE_HOP_ARC * 4 * p * (1 - p)
    local nx = h.sx + (h.cx - h.sx) * ph
    local ny = h.sy + (h.cy - h.sy) * ph
    local nz = h.sz + (h.z - h.sz) * ph + arc
    animal:setX(nx)
    animal:setY(ny)
    animal:setNextX(nx)
    animal:setNextY(ny)
    animal:setZ(nz)
    if h.dir then
        animal:setDir(h.dir)
    end
    if not h.cleared and p >= CD.FENCE_HOP_LAND_BLEND then
        h.cleared = true
        CD.emitEatVar(animal, false, CD.JUMP_ANIM_VAR)
    end
    if p >= 1 then
        animal:setX(h.cx)
        animal:setY(h.cy)
        animal:setNextX(h.cx)
        animal:setNextY(h.cy)
        animal:setZ(h.z)
        local s = getCell():getGridSquare(h.ex, h.ey, h.z)
        if s and CD.squareHasFloor(s) then
            animal:setCurrent(s)
        end
        d.fenceHop = nil
        CD.emitEatVar(animal, false, CD.JUMP_ANIM_VAR)
        animal:setVariable("ClimbFence", false)
        animal:setVariable("climbDown", false)
        animal:setVariable("ClimbingFence", false)
        local now = getTimestampMs()
        d.fenceHopUntilMs = now + CD.FENCE_HOP_COOLDOWN_MS
        if h.edge then
            d.recrossEdge = h.edge
            d.recrossUntilMs = now + CD.FENCE_RECROSS_BLOCK_MS
        end
        d.fenceTraversal = nil
        CD.letMove(animal)
        local careHop = d.careHop
        local careTx, careTy = d.careHopTx, d.careHopTy
        local combatLanding = d.combatHop and isServer()
        d.combatHop = nil
        d.careHop = nil
        d.careHopTx, d.careHopTy = nil, nil
        if combatLanding then
            CD.landGlide[id] = { animal = animal, startMs = now, combat = true, care = careHop, tx = careTx, ty = careTy }
        elseif careHop then
            CD.landGlide[id] = nil
        elseif CD.FENCE_LAND_GLIDE and isServer() then
            CD.landGlide[id] = { animal = animal, startMs = now }
        end
        if not combatLanding and not careHop then
            local owner = CD.getOwnerPlayer(animal)
            if owner and owner:getCurrentSquare()
               and math.floor(owner:getZ()) == math.floor(animal:getZ())
               and CD.dist2D(animal, owner) <= CD.TELEPORT_DIST then
                CD.letMove(animal)
                local run = CD.mayRun(animal)
                animal:setVariable("animalRunning", run)
                animal:setVariable("animalSpeed", run and CD.runAnimSpeed() or CD.walkAnimSpeed())
                local ddx, ddy = owner:getX() - animal:getX(), owner:getY() - animal:getY()
                local dl = math.sqrt(ddx * ddx + ddy * ddy)
                if dl > 0.01 then
                    animal:setForwardDirection(ddx / dl, ddy / dl)
                end
                CD.pathStatEmit(animal, "cerca")
                animal:pathToCharacter(owner)
                CD.forcePathfind(animal)
                d.running = true
                d.followPathTile = { x = math.floor(owner:getX()), y = math.floor(owner:getY()), z = math.floor(owner:getZ()) }
                d.followPathMs = now
                d.followLastX, d.followLastY, d.followStallMs = animal:getX(), animal:getY(), now
            end
        end
        if isServer() then
            sendServerCommand(CD.MODULE, "fencehopend", { id = id, x = h.cx, y = h.cy, z = h.z })
            animal:sendExtraUpdateToClients()
            landSettling[id] = { animal = animal, untilMs = now + CD.FENCE_LAND_PUSH_MS, lastMs = now }
            if CD.FENCE_LAND_USE_STREAM then
                CD.landStreaming[id] = { animal = animal, untilMs = now + CD.FENCE_LAND_STREAM_MS }
            end
        end
        return true
    end
    return false
end

---Moves every dog mid-hop one step along its arc; a dog that lands rolls the sprain chance.
function CD.tickFenceHops()
    for id, animal in pairs(CD.fenceHopping) do
        if fenceHopStep(id, animal) then
            CD.fenceHopping[id] = nil
            CD.vetRollHop(animal)
        end
    end
end

---Server only: sends extra position updates of a dog that just landed, every 50 ms for FENCE_LAND_PUSH_MS.
function CD.tickFenceLandPush()
    if not isServer() then
        landSettling = {}
        return
    end
    local now = getTimestampMs()
    for id, rec in pairs(landSettling) do
        local a = rec.animal
        if not a or not a:isExistInTheWorld() or now >= rec.untilMs then
            landSettling[id] = nil
        elseif not rec.lastMs or (now - rec.lastMs) >= 50 then
            rec.lastMs = now
            a:sendExtraUpdateToClients()
        end
    end
end

---Cancels any hop in progress and clears the climb and jump animation flags.
---@param animal IsoAnimal
function CD.clearClimbVars(animal)
    animal:setVariable("ClimbFence", false)
    animal:setVariable("ClimbingFence", false)
    animal:setVariable("climbDown", false)
    CD.emitEatVar(animal, false, CD.JUMP_ANIM_VAR)
    local d = CD.data(animal)
    d.fenceHop = nil
    d.fenceTraversal = nil
    d.backBlockDir = nil
    d.backBlockUntilMs = nil
    d.fenceSteer = nil
    local oid = animal:getOnlineID()
    CD.fenceHopping[oid] = nil
    CD.fenceSteering[oid] = nil
    CD.landGlide[oid] = nil
end

