CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- Lado client da autoridade de posiçao: enquanto o servidor concede, quem move o cão e esta maquina,
-- com o dono como alvo local. Bateu em qualquer coisa, devolve, porque A* de animal so existe la.

local owned = {}

local YIELD_KEY = {
    quina = "netauth.cli.block.quina", porta = "netauth.cli.block.porta",
    janela = "netauth.cli.block.janela", escada = "netauth.cli.block.escada",
    parede = "netauth.cli.block.parede", vazio = "netauth.cli.block.vazio",
    ocupado = "netauth.cli.block.ocupado", outro = "netauth.cli.block.outro",
}

-- janela de observacao depois da devolucao, so no nivel 2 do medidor, cobre o instante em que a
-- reproducao troca de dono, que e onde o salto aparece e onde nenhum dos outros detectores olha.
local yieldWatch = {}

---@param id integer animal online id
---@return boolean true while the server lets this client move the dog
---@nodiscard
function CD.netAuthOwned(id)
    return owned[id] ~= nil
end

local function ownerOf(animal)
    -- getOwnerPlayer le o ModData direto: animal nil estoura. O yieldBack chama com o pet ja sumido.
    if not animal then return nil end
    local p = CD.getOwnerPlayer(animal)
    if p and p:isLocalPlayer() then return p end
    return nil
end

local function yieldBack(id, why)
    local o = owned[id]
    if not o then return end
    owned[id] = nil
    local animal = getAnimal(id)
    -- A posicao final vai junto: com cadencia lenta a copia do servidor pode estar alguns tiles atras,
    -- e sem isto a devolucao terminaria num salto visivel de volta pro ultimo aviso.
    local args = { id = id, why = why }
    if animal and animal:isExistInTheWorld() then
        args.x, args.y, args.z = animal:getX(), animal:getY(), animal:getZ()
    end
    if animal and CD.restoreDogNetState then
        CD.restoreDogNetState(animal)
    end
    CD.sendAs(ownerOf(animal), "netyield", args)
end

---Server grant, cadence tune or revoke of the right to move a dog from this client; a revoke sends the final position back.
---@param args table server payload { id, on, tune, keep, rep, irep }
function CD.onNetAuth(args)
    if not args then return end
    local id = tonumber(args.id)
    if not id then return end
    if args.on == true then
        -- Ajuste de cadencia numa posse que ja existe. Recriar a ficha aqui zeraria a posicao
        -- pretendida e devolveria o cao pro empurrao do mover por um quadro.
        local cur = owned[id]
        if cur and args.tune == true then
            cur.rep = tonumber(args.rep) or cur.rep
            cur.irep = tonumber(args.irep) or cur.irep
            if args.keep then
                cur.keep = tonumber(args.keep) or cur.keep
            end
            return
        end
        CD.clearFollowStreamFor(id)
        local a = getAnimal(id)
        local st = {}
        if a then
            st.absX, st.absY = a:getX(), a:getY()
        end
        owned[id] = { keep = tonumber(args.keep) or CD.FOLLOW_START_DIST,
                      rep = tonumber(args.rep), irep = tonumber(args.irep),
                      st = st, reportMs = 0, run = false }
    else
        local o = owned[id]
        owned[id] = nil
        if o then
            local animal = getAnimal(id)
            -- A posicao final vai mesmo quando quem cortou foi o servidor. Ele segura o pacote nativo
            -- esperando por ela; sem isto o cao volta pro ultimo aviso, que com cadencia lenta fica ate
            -- NET_AUTH_REPORT_STEP atras do que este client acabou de desenhar.
            local args = { id = id, why = "revogado" }
            if animal and animal:isExistInTheWorld() then
                args.x, args.y, args.z = animal:getX(), animal:getY(), animal:getZ()
            end
            if animal and CD.restoreDogNetState then
                CD.restoreDogNetState(animal)
            end
            if CD._perfLv > 1 and args.x then
                local now = getTimestampMs()
                yieldWatch[id] = { x = args.x, y = args.y, ms = now,
                                   untilMs = now + CD.JUMP_YIELD_WATCH_MS }
            end
            CD.sendAs(ownerOf(animal), "netyield", args)
        end
    end
end

-- `force` tem piso proprio. Sem ele, um cao pairando em cima do ponto de parada com o dono em
-- movimento alterna parado/andando a cada quadro e o aviso de troca de marcha sai por QUADRO.
local function report(id, o, animal, now, force, idle)
    if force and (now - o.reportMs) < CD.NET_AUTH_FORCE_MIN_MS then
        force = false
    end
    -- Parado ainda precisa dar sinal de vida, senao o servidor conclui silencio e retoma. A cadencia
    -- veio na concessao: e o servidor que tem o valor tunado, esta VM so tem o default do arquivo.
    local every
    if idle then every = o.irep or CD.NET_AUTH_IDLE_REPORT_MS
    else every = o.rep or CD.NET_AUTH_REPORT_MS end
    local x, y = animal:getX(), animal:getY()
    if not force and (now - o.reportMs) < every then
        -- Gatilho por DISTANCIA. Cadencia lenta por tempo puro deixa a copia do servidor varios tiles
        -- atras com o cao correndo, e e nela que a decisao de combate e o instante da devolucao se
        -- apoiam. Assim o erro fica limitado no ESPACO, e cao rapido avisa mais que cao lento sozinho.
        if not o.repX then return end
        if (math.abs(x - o.repX) + math.abs(y - o.repY)) < CD.NET_AUTH_REPORT_STEP then
            return
        end
    end
    o.reportMs = now
    local fx, fy = 0, 1
    local f = animal:getForwardDirection()
    if f then
        fx, fy = f:getX(), f:getY()
    end
    -- Cao parado sem delta nenhum so precisa renovar o prazo de silencio: id basta. Gente deixa cao
    -- estacionado na base por horas, e cada um mandava posicao inteira a cada irep.
    if idle and not force and o.repX == x and o.repY == y and o.repFx == fx and o.repFy == fy
       and o.repRun == (o.run == true) then
        CD.sendAs(ownerOf(animal), "netka", { id = id })
        return
    end
    o.repX, o.repY = x, y
    o.repFx, o.repFy = fx, fy
    o.repRun = o.run == true
    CD.sendAs(ownerOf(animal), "netpos", {
        id = id, x = x, y = y, z = animal:getZ(),
        fx = fx, fy = fy, r = o.run == true,
    })
end

-- Divergencia grande e teleporte, e ai a verdade e a engine.
local function holdAbs(animal, st)
    if not st.absX then
        st.absX, st.absY = animal:getX(), animal:getY()
        return
    end
    local x, y = animal:getX(), animal:getY()
    if math.abs(st.absX - x) + math.abs(st.absY - y) > CD.STEER_ABS_RESYNC then
        st.absX, st.absY = x, y
        return
    end
    animal:setX(st.absX)
    animal:setY(st.absY)
    animal:setNextX(st.absX)
    animal:setNextY(st.absY)
end

local function driveOne(id, o, now)
    local animal = getAnimal(id)
    if not animal or not animal:isExistInTheWorld() then
        yieldBack(id, "sumiu")
        return
    end
    local owner = ownerOf(animal)
    if not owner then
        yieldBack(id, "dono")
        return
    end
    if math.floor(owner:getZ()) ~= math.floor(animal:getZ()) then
        yieldBack(id, "andar")
        return
    end

    local keep = o.keep
    local ox, oy = owner:getX(), owner:getY()
    local dx, dy = ox - animal:getX(), oy - animal:getY()
    local gap = math.sqrt(dx * dx + dy * dy)
    if gap > CD.NET_AUTH_REVOKE_DIST then
        yieldBack(id, "longe")
        return
    end

    local runDist = keep + 2
    local far = CD.FOLLOW_RUN_DIST
    if far > runDist then
        runDist = far
    end

    -- Mesma histerese do servidor, senao a troca de clipe pisca em cima do ponto de parada.
    local run = o.run == true
    if gap > runDist then run = true
    elseif owner:isRunning() or owner:isSprinting() then run = true
    elseif gap <= keep + 1 then run = false end
    run = run and CD.mayRun(animal)

    if gap <= keep then
        o.run = false
        o.st._steerMs = now
        o.moveMs = now
        animal:setVariable("animalRunning", false)
        animal:setVariable("animalSpeed", 1.0)
        animal:setVariable("cdNetGait", false)
        animal:setVariable("cdGlide", false)
        -- Sem segurar, o mover arrasta o cao parado e ele desliza sozinho.
        holdAbs(animal, o.st)
        report(id, o, animal, now, false, true)
        return
    end

    local metering = CD._perfLv and CD._perfLv > 0
    if metering and o.st.absX then
        local drag = math.abs(o.st.absX - animal:getX()) + math.abs(o.st.absY - animal:getY())
        if drag < CD.STEER_ABS_RESYNC then
            CD.perfCount("netauth.cli.drag", drag)
        end
        CD.perfCount("netauth.cli.gap", gap)
        CD.perfCount("netauth.cli.gap.n")
    end
    local prevX, prevY = o.st.absX, o.st.absY
    local prevMs = o.st._steerMs

    -- Contra o ULTIMO ENVIADO, nao contra o quadro anterior: o ramo de cao parado reescreve o.run
    -- todo quadro, entao comparar com ele acusa troca de marcha que nunca chegou a ser enviada.
    local runFlip = (o.repRun ~= nil and run ~= o.repRun)
    o.run = run
    animal:setVariable("cdGlide", true)
    animal:setVariable("cdNetGait", true)
    animal:setMaxTwist(0)
    CD.applyGaitScale(animal,
        CD.FOLLOW_STEER_RUN_SPEED / CD.FOLLOW_STEER_RUN_RATE,
        CD.FOLLOW_STEER_WALK_SPEED / CD.FOLLOW_STEER_WALK_RATE)

    local tx, ty = ox - dx / gap * keep, oy - dy / gap * keep
    local nx = CD.steerAdvance(animal, tx, ty, run, o.st, now,
                               CD.FOLLOW_STEER_WALK_SPEED,
                               CD.FOLLOW_STEER_RUN_SPEED,
                               CD.steerStepPassable)
    if not nx then
        -- Motivo fino so aqui, no caminho frio: parede e quina de porta pedem decisoes opostas.
        local why = "bloqueado"
        if metering then
            local r2 = CD.steerStepBlockReason(animal, tx, ty)
            if r2 then
                why = r2
                CD.perfCount(YIELD_KEY[r2] or YIELD_KEY.outro)
            end
        end
        yieldBack(id, why)
        return
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0.0001 then
        CD.snapDogFacing(animal, nil, dx / len, dy / len)
    end

    -- Avanco ENTREGUE, nao comandado: a diferenca entre os dois e o "corre parado".
    if metering and prevX then
        local adx, ady = o.st.absX - prevX, o.st.absY - prevY
            local adv = math.sqrt(adx * adx + ady * ady)
        local fdt = prevMs and (now - prevMs) or 0
        if fdt > 0 and fdt < CD.STEER_MAX_DT_MS then
            CD.perfCount("netauth.cli.adv", adv)
            CD.perfCount("netauth.cli.drive.ms", fdt)
            CD.perfCount("netauth.cli.frames")
        end
    end

    -- conduçao que nao tira o cao do lugar devolve: animal andando de mentira e pior que cao do servidor.
    local rx, ry = animal:getX(), animal:getY()
    -- Descontinuidade no cão que o PROPRIO dono conduz: e o que ele ve na tela, e nao passa pelo
    -- stream separa o passo grande demais (drive) do resync que solta a ancora (resync).
    if CD._perfLv > 1 then
        if o.jx then
            local jd = math.abs(rx - o.jx) + math.abs(ry - o.jy)
            if jd >= CD.JUMP_WATCH_TILES then
                CD.perfCount("jump.cli")
                CD.perfCount(jd >= CD.STEER_ABS_RESYNC and "jump.cli.resync" or "jump.cli.drive")
            end
        end
        o.jx, o.jy = rx, ry
    end
    if not o.lastX or (math.abs(rx - o.lastX) + math.abs(ry - o.lastY)) >= CD.NET_AUTH_STALL_EPS then
        o.lastX, o.lastY, o.moveMs = rx, ry, now
    elseif (now - (o.moveMs or now)) >= CD.NET_AUTH_STALL_MS then
        CD.perfCount("netauth.stall")
        yieldBack(id, "parado")
        return
    end

    report(id, o, animal, now, runFlip)
end

local function tickYieldWatch(now)
    for id, w in pairs(yieldWatch) do
        local animal = getAnimal(id)
        if not animal or not animal:isExistInTheWorld() or now >= w.untilMs then
            yieldWatch[id] = nil
        else
            local x, y = animal:getX(), animal:getY()
            local dt = now - w.ms
            local dx, dy = x - w.x, y - w.y
            local dist = math.sqrt(dx * dx + dy * dy)
            w.x, w.y, w.ms = x, y, now
            if dt > 0 and dt <= CD.JUMP_WATCH_MAX_DT_MS
                and dist >= CD.JUMP_WATCH_TILES and dist * 1000 >= CD.JUMP_WATCH_SPEED * dt then
                CD.perfCount("jump.cli")
                CD.perfCount("jump.cli.yield")
                if dist >= 4 then CD.perfCount("jump.cli.yield.far")
                elseif dist >= 1.5 then CD.perfCount("jump.cli.yield.mid")
                else CD.perfCount("jump.cli.yield.near") end
                yieldWatch[id] = nil
            end
        end
    end
end

local function tickNetAuthClient()
    local now = getTimestampMs()
    for id, o in pairs(owned) do
        driveOne(id, o, now)
    end
    local watching = false
    for _ in pairs(yieldWatch) do  -- next() nao existe no Kahlua do PZ
        watching = true
        break
    end
    if watching then
        if CD._perfLv > 1 then
            tickYieldWatch(now)
        else
            yieldWatch = {}
        end
    end
end

if isClient() then
    CD.evAdd(Events.OnTick, tickNetAuthClient, "cli.netauth")
end
