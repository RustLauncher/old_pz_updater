CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- Conducao na mao, compartilhada: servidor e client do dono usam a mesma conta.

-- Pousar em tile sem chao e o NPE de fallenOnKnees->addHole.
---@param sq IsoGridSquare|nil
---@return boolean
---@nodiscard
function CD.squareHasFloor(sq)
    if not sq then return false end
    local ok = sq:isSolidFloor() or sq:getFloor() ~= nil
    return ok
end

-- isBlockedTo cobre parede, janela, porta e escada, mas nao olha solid nem solidtrans. Dentro de
-- casa movel e solidtrans: o A* contorna o que a conducao atravessaria por dentro. O piso tambem
-- entra aqui, senao a conducao serve buraco e beirada de sacada.
---@param sq IsoGridSquare|nil
---@return boolean
---@nodiscard
function CD.steerTileFree(sq)
    return sq ~= nil and not sq:isSolid() and not sq:isSolidTrans() and CD.squareHasFloor(sq)
end

local PROBE_KEY = {
    quina = "steer.probe.fail.quina", porta = "steer.probe.fail.porta",
    janela = "steer.probe.fail.janela", escada = "steer.probe.fail.escada",
    parede = "steer.probe.fail.parede", vazio = "steer.probe.fail.vazio",
    ocupado = "steer.probe.fail.ocupado", outro = "steer.probe.fail.outro",
}

-- So medicao: roda apenas depois que o passo ja foi reprovado, nunca no caminho feliz.
local function stepFailReason(cell, cur, dest, tx, ty, cz)
    local cx, cy = cur:getX(), cur:getY()
    if tx ~= cx and ty ~= cy then
        -- Nao cabe na diagonal mas cabe em L: e quina, nao parede. Esse e o caso do vao de porta,
        -- onde o ortogonal passa e so o angulo reprova, e o unico que um waypoint resolveria.
        local sx = cell:getGridSquare(tx, cy, cz)
        if CD.steerTileFree(sx) and not cur:isBlockedTo(sx) and not sx:isBlockedTo(dest) then return "quina" end
        local sy = cell:getGridSquare(cx, ty, cz)
        if CD.steerTileFree(sy) and not cur:isBlockedTo(sy) and not sy:isBlockedTo(dest) then return "quina" end
    end
    if cur:isDoorBlockedTo(dest) then return "porta" end
    if cur:isWindowBlockedTo(dest) then return "janela" end
    if cur:isStairBlockedTo(dest) then return "escada" end
    if cur:isWallTo(dest) then return "parede" end
    return "outro"
end

-- Transicao de um tile por isBlockedTo, nunca LosUtil: LosUtil e teste de visao, deixa passar
-- cerca e carro, e no passo diagonal reprova qualquer coisa encostada em parede. E a mesma regra
-- que a engine usa no IsoAnimal.canGoThere.
-- Diagonal exige os dois ortogonais livres; square ausente conta como bloqueado.
-- Devolve o square de destino pra quem estiver encadeando passos, ou nil mais o motivo.
---@param cell IsoCell
---@param cur IsoGridSquare
---@param tx integer
---@param ty integer
---@param cz integer
---@return IsoGridSquare|nil dest
---@return string|nil reason why the step failed; nil when it passes
---@nodiscard
function CD.steerStepTo(cell, cur, tx, ty, cz)
    local cx, cy = cur:getX(), cur:getY()
    if tx == cx and ty == cy then return cur end
    local dest = cell:getGridSquare(tx, ty, cz)
    if not CD.steerTileFree(dest) then
        return nil, (dest == nil) and "vazio" or "ocupado"
    end
    if not cur:isBlockedTo(dest) then
        if tx == cx or ty == cy then return dest end
        local sx = cell:getGridSquare(tx, cy, cz)
        local sy = cell:getGridSquare(cx, ty, cz)
        if sx and sy and not cur:isBlockedTo(sx) and not cur:isBlockedTo(sy) then return dest end
    end
    return nil, stepFailReason(cell, cur, dest, tx, ty, cz)
end

---Whether the dog may step from its tile to the tile under (nx, ny).
---@param animal IsoAnimal
---@param nx number
---@param ny number
---@return boolean
---@nodiscard
function CD.steerStepPassable(animal, nx, ny)
    local cur = animal:getCurrentSquare()
    if not cur then return false end
    local cell = getCell()
    if not cell then return false end
    return CD.steerStepTo(cell, cur, math.floor(nx), math.floor(ny), cur:getZ()) ~= nil
end

-- Mesmo teste, devolvendo o motivo. Caminho frio, so pra quem vai registrar a falha.
---@param animal IsoAnimal
---@param nx number
---@param ny number
---@return string|nil reason nil when the step passes
---@nodiscard
function CD.steerStepBlockReason(animal, nx, ny)
    local cur = animal:getCurrentSquare()
    if not cur then return "semtile" end
    local cell = getCell()
    if not cell then return "semcell" end
    local ok, why = CD.steerStepTo(cell, cur, math.floor(nx), math.floor(ny), cur:getZ())
    if ok then return nil end
    return why or "outro"
end

-- Devolve QUANTOS tiles do raio cabem antes de esbarrar, nao um sim/nao. Exigir o caminho inteiro
-- livre desperdica o trecho reto que quase sempre existe: o passo real anda 0,2 a 0,5 tile por tique e
-- a sonda refaz a cada 300 ms, entao comprometer-se com um corredor curto e barato, e o guard de
-- passo continua conferindo cada movimento de verdade.
---@param animal IsoAnimal
---@param tox number
---@param toy number
---@param st table steering state; also caches the probe result
---@param now number real-time ms
---@param keep number distance to stop short of the target, in tiles
---@return number clear tiles of straight line free ahead
function CD.steerCorridorClear(animal, tox, toy, st, now, keep)
    if st._steerProbeMs and (now - st._steerProbeMs) < CD.FOLLOW_STEER_LOS_MS then
        return st._steerClear or 0
    end
    st._steerProbeMs = now
    st._steerClear = 0

    local cur = animal:getCurrentSquare()
    local cell = getCell()
    if not cur or not cell then return 0 end

    local ax, ay = animal:getX(), animal:getY()
    local dx, dy = tox - ax, toy - ay
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1e-3 then return 0 end

    local reach = dist - keep
    local budget = CD.FOLLOW_STEER_PROBE_TILES
    if reach > budget then
        reach = budget
    end
    -- Praticamente em cima do ponto de parada: nao ha o que sondar, e reprovar aqui soltaria um cao
    -- que esta justamente terminando bem a corrida.
    if reach <= 0.5 then
        st._steerClear = reach > 0 and reach or 0
        return st._steerClear
    end

    local cz = cur:getZ()
    local ux, uy = dx / dist, dy / dist
    local cx, cy = cur:getX(), cur:getY()
    local clear, t = 0, 0.5
    while t <= reach do
        local tx, ty = math.floor(ax + ux * t), math.floor(ay + uy * t)
        if tx ~= cx or ty ~= cy then
            local nxt, why = CD.steerStepTo(cell, cur, tx, ty, cz)
            if not nxt then
                CD.perfCount("steer.probe.fail")
                CD.perfCount(PROBE_KEY[why] or PROBE_KEY.outro)
                break
            end
            cur, cx, cy = nxt, tx, ty
        end
        clear = t
        t = t + 0.5
    end
    st._steerClear = clear
    return clear
end

-- st.absX liga o modo ABSOLUTO, obrigatorio no client: o mover da engine puxa a copia remota todo
-- quadro, e somar o passo em cima do que ele deixou se anula com o empurrao (o cao corre parado).
---@param animal IsoAnimal
---@param tx number
---@param ty number
---@param run boolean
---@param st table steering state
---@param now number real-time ms
---@param walkSpd number tiles per second
---@param runSpd number tiles per second
---@param guard function|nil called with (animal, nx, ny); a false result cancels the step
---@return number|nil nx nil when guard cancelled the step
---@return number|nil ny
function CD.steerAdvance(animal, tx, ty, run, st, now, walkSpd, runSpd, guard)
    local dt = now - (st._steerMs or now)
    local maxdt = CD.STEER_MAX_DT_MS
    if dt < 0 then dt = 0 elseif dt > maxdt then dt = maxdt end
    st._steerMs = now
    local x, y = animal:getX(), animal:getY()
    if st.absX then
        -- Divergencia grande e teleporte ou o snap de distToReal, e ai a verdade e a engine.
        if math.abs(st.absX - x) + math.abs(st.absY - y) > CD.STEER_ABS_RESYNC then
            st.absX, st.absY = x, y
        else
            x, y = st.absX, st.absY
        end
    end
    local ddx, ddy = tx - x, ty - y
    local dist = math.sqrt(ddx * ddx + ddy * ddy)
    local wm, rm = CD.vetGaitMult(CD.data(animal))
    if run and rm == nil then
        run = false
    end
    local step = (run and runSpd * rm or walkSpd * wm) * dt / 1000
    local nx, ny
    if dist <= step or dist < 1e-3 then
        nx, ny = tx, ty
    else
        nx, ny = x + ddx / dist * step, y + ddy / dist * step
    end
    if guard and not guard(animal, nx, ny) then return nil end
    if st.absX then
        st.absX, st.absY = nx, ny
    end
    local b = animal:getBehavior()
    if b then
        b:setBlockMovement(true)
    end
    animal:setDeferredMovementEnabled(false)
    animal:setVariable("animalRunning", run and true or false)
    animal:setVariable("animalSpeed", run and CD.runAnimSpeed() or CD.walkAnimSpeed())
    if dist > 1e-3 then
        animal:setForwardDirection(ddx / dist, ddy / dist)
    end
    animal:setX(nx)
    animal:setY(ny)
    animal:setNextX(nx)
    animal:setNextY(ny)
    return nx, ny
end
