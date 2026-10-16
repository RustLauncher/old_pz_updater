CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs
CD.Server = CD.Server or {}

-- Autoridade de posicao do cao entregue ao client do dono. O client nao consegue pedir A* pra animal
-- (CanUsePathfindState e isLocalPlayer), entao so recebe o caso que a conducao reta resolve.

local held = {}
CD.netAuthHeldMap = held

-- Posse que o SERVIDOR revogou e ainda espera a posicao final do client. O pacote nativo da revogacao
-- fica retido enquanto a ficha esta aqui: mandado antes, ele leva a posicao velha do servidor.
local pending = {}

local REVOKE_KEY = {
    ocupado = "netauth.revoke.ocupado", andar = "netauth.revoke.andar",
    longe = "netauth.revoke.longe", silencio = "netauth.revoke.silencio",
    abandono = "netauth.revoke.abandono", passo = "netauth.revoke.passo",
    tile = "netauth.revoke.tile", sumiu = "netauth.revoke.sumiu",
    reap = "netauth.revoke.reap", removido = "netauth.revoke.removido",
    parado = "netauth.revoke.parado", bloqueado = "netauth.revoke.bloqueado",
    dono = "netauth.revoke.dono", outro = "netauth.revoke.outro",
    parede = "netauth.revoke.parede", quina = "netauth.revoke.quina",
    porta = "netauth.revoke.porta", janela = "netauth.revoke.janela",
    escada = "netauth.revoke.escada", vazio = "netauth.revoke.vazio",
    semtile = "netauth.revoke.semtile", semcell = "netauth.revoke.semcell",
}
local DENY_KEY = {
    ocupado = "netauth.deny.ocupado", andar = "netauth.deny.andar",
    degelo = "netauth.deny.degelo", longe = "netauth.deny.longe",
    corredor = "netauth.deny.corredor",
}

local function deny(why)
    -- perfCount indexa a tabela com a chave, e chave nil em atribuicao Lua e erro, nao no-op.
    CD.perfCount(DENY_KEY[why] or "netauth.deny.outro")
    return false
end

---@param id number online ID of the dog
---@return number|nil playerId online ID of the player whose client drives the dog; nil while the server does
---@nodiscard
function CD.netAuthHolder(id)
    local r = held[id]
    return r and r.pid or nil
end

-- O admin pode subir a cadencia de report acima do timeout fixo, e ai todo cao parado seria retomado
-- por silencio. A janela acompanha a cadencia EM VIGOR pro cao, nao o knob global, porque a cadencia
-- de cao sem plateia e mais lenta que o knob.
local function authTimeout(r, now)
    local fixed = CD.NET_AUTH_TIMEOUT_MS
    local irep = (r and r.irep) or CD.NET_AUTH_IDLE_REPORT_MS
    -- Apertar a cadencia encurta a janela na hora, mas o client so acelera quando o pacote chegar.
    -- Sem a folga, o cao seria retomado por silencio exatamente quando alguem chega perto dele.
    if r and r.graceIrep and now and now < (r.graceMs or 0) and r.graceIrep > irep then
        irep = r.graceIrep
    end
    local idle = irep + 300
    if idle > fixed then return idle end
    return fixed
end

-- Quem consome a posicao do cao: o dono nao, ele ja tem. Sem OUTRO jogador por perto o report so
-- alimenta a logica do servidor, que aguenta cadencia baixa; num servidor cheio esse e o caso da
-- maioria dos caes na maior parte do tempo. Os valores saem MULTIPLICADOS dos knobs do admin, nao
-- fixos por cima deles, senao mexer no painel deixaria de valer justamente no caso mais comum.
local function cadenceFor(lone)
    local rep = CD.NET_AUTH_REPORT_MS
    local irep = CD.NET_AUTH_IDLE_REPORT_MS
    if not lone then return rep, irep end
    local mult = CD.NET_AUTH_LONE_MULT
    local maxMs = CD.NET_AUTH_LONE_MAX_MS
    rep = rep * mult
    irep = irep * mult
    if rep > maxMs then
        rep = maxMs
    end
    if irep > maxMs then
        irep = maxMs
    end
    return rep, irep
end

local function refreshCadence(r, animal, now)
    if r.loneMs and (now - r.loneMs) < CD.NET_AUTH_LONE_CHECK_MS then return end
    r.loneMs = now
    local lone = true
    local viewers, nv, vx, vy, vid = CD.streamViewers(now)
    if viewers and nv > 0 then
        local ax, ay = animal:getX(), animal:getY()
        local range = CD.FOLLOW_STREAM_RANGE
        for v = 1, nv do
            if vid[v] ~= r.pid and (math.abs(vx[v] - ax) + math.abs(vy[v] - ay)) <= range then
                lone = false
                break
            end
        end
    end
    local rep, irep = cadenceFor(lone)
    if r.rep == rep and r.irep == irep then return end
    if r.irep and irep < r.irep then
        r.graceIrep = r.irep
        r.graceMs = now + r.irep + 500
    end
    r.rep, r.irep = rep, irep
    CD.perfCount(lone and "netauth.cadence.lone" or "netauth.cadence.visto")
    if r.player then
        sendServerCommand(r.player, CD.MODULE, "netauth",
                          { id = r.id, on = true, tune = true, rep = rep, irep = irep })
    end
end

local function grant(animal, d, owner, id, now)
    -- Posse de volta antes de a devolucao anterior fechar: o pacote nativo perdeu a razao de existir.
    pending[id] = nil
    local rep0, irep0 = cadenceFor(false)
    held[id] = { id = id, animal = animal, player = owner, pid = owner:getOnlineID(),
                 sinceMs = now, reportMs = now, seenMs = now, rep = rep0, irep = irep0,
                 x = animal:getX(), y = animal:getY(), z = animal:getZ(), rejects = 0 }
    d._followStreaming = nil
    d.followPathTile = nil
    -- A conducao do servidor e ticada fora do followOwner: sem soltar aqui, ela continua empurrando.
    CD.followSteering[id] = nil
    CD.standUp(animal)
    animal:setVariable("bPathfind", false)
    animal:stopAllMovementNow()
    local b = animal:getBehavior()
    if b then
        b:setBlockMovement(true)
    end
    animal:setDeferredMovementEnabled(false)
    -- A cadencia vai junto da concessao: o client tem VM propria e nunca ve a tabela de tuning.
    sendServerCommand(owner, CD.MODULE, "netauth", { id = id, on = true, keep = CD.followKeepFrom(d),
                                                    rep = CD.NET_AUTH_REPORT_MS,
                                                    irep = CD.NET_AUTH_IDLE_REPORT_MS })
    CD.perfCount("netauth.grant")
end

local function coolOff(d, r, now)
    -- Escala so quando a posse foi CURTA, e a escala expira sozinha. Escalar em toda devolucao vira
    -- catraca: o degelo grande impede a posse longa que zeraria a conta.
    local lastYield = d._netAuthYieldMs
    if lastYield and (now - lastYield) > CD.NET_AUTH_MISS_DECAY_MS then
        d._netAuthMiss = nil
    end
    d._netAuthYieldMs = now
    if (now - (r.sinceMs or now)) >= CD.NET_AUTH_FLAP_MS then
        d._netAuthMiss = nil
    else
        d._netAuthMiss = math.min((d._netAuthMiss or 0) + 1, 3)
    end
    local mult = 1
    for _ = 1, (d._netAuthMiss or 0) do mult = mult * 2 end
    local cool = CD.NET_AUTH_REGRANT_MS * mult
    local capMs = CD.NET_AUTH_REGRANT_MAX_MS
    if cool > capMs then
        cool = capMs
    end
    d._netAuthCoolMs = now + cool
end

-- Fecha a espera pela posicao final: e aqui que o pacote nativo sai, ja com a correcao aplicada se ela
-- chegou a tempo.
local function settle(id)
    local p = pending[id]
    if not p then return end
    pending[id] = nil
    local animal = p.animal
    if animal and animal:isExistInTheWorld() then
        animal:sendExtraUpdateToClients()
    end
end

local function revoke(id, why)
    local r = held[id]
    if not r then return end
    held[id] = nil
    local animal = r.animal
    local alive = animal and animal:isExistInTheWorld()
    if alive then
        local d = CD.data(animal)
        if d then
            d.followPathTile = nil
            coolOff(d, r, getTimestampMs())
        end
        CD.letMove(animal)
    end
    -- Com dono pra responder, o pacote nativo espera a devolucao. Sem dono nao ha quem devolva, entao
    -- sai na hora, como sempre saiu.
    if alive and r.player then
        settle(id)
        pending[id] = { animal = animal, pid = r.pid, sinceMs = getTimestampMs(),
                        x = r.x, y = r.y, z = r.z, reportMs = r.reportMs }
    elseif alive then
        animal:sendExtraUpdateToClients()
    end
    if r.player then
        sendServerCommand(r.player, CD.MODULE, "netauth", { id = id, on = false })
    else
        sendServerCommand(CD.MODULE, "netauth", { id = id, on = false })
    end
    CD.perfCount("netauth.revoke")
    CD.perfCount(REVOKE_KEY[why] or REVOKE_KEY.outro)
end
CD.netAuthRevoke = revoke

-- Desligar a autoridade nao basta: quem ja esta com a posse continua conduzindo o cao no client.
---@param why string|nil revoke reason key; "outro" when nil
function CD.netAuthRevokeAll(why)
    local ids = {}
    for id in pairs(held) do ids[#ids + 1] = id end
    for i = 1, #ids do revoke(ids[i], why or "outro") end
end

local function meter(d, r, now)
    if not (CD._perfLv and CD._perfLv > 0) then return end
    local dt = now - (d._netAuthMeterMs or now)
    d._netAuthMeterMs = now
    if dt <= 0 or dt >= 2000 then return end
    CD.perfCount("netauth.follow.ms", dt)
    if r then
        CD.perfCount("netauth.held.ms", dt)
    end
end

-- Chamado de dentro do followOwner, o unico ponto onde o servidor ja decidiu que o cao esta apenas
-- seguindo o dono. E isso que mantem combate, caca, guarda e cuidador fora deste caminho.
---@param animal IsoAnimal
---@param d table companion ModData
---@param owner IsoPlayer
---@return boolean held true while the owner's client drives the dog's position
function CD.netAuthUpdate(animal, d, owner)
    if not CD.NET_AUTHORITY or not isServer() then return false end
    local id = animal:getOnlineID()
    local now = getTimestampMs()
    local r = held[id]
    local gap = CD.dist2D(animal, owner)
    local sameZ = math.floor(owner:getZ()) == math.floor(animal:getZ())
    local busy = d.fenceHop or d.fenceSteer or d.fenceTraversal or d.breedTarget
        or CD.combatMaintainDogs[id] ~= nil or (isServer() and CD.landGlide and CD.landGlide[id] ~= nil)

    meter(d, r, now)

    if r then
        r.seenMs = now
        if busy then
            revoke(id, "ocupado")
            return false
        end
        if not sameZ then
            revoke(id, "andar")
            return false
        end
        if gap > CD.NET_AUTH_REVOKE_DIST then
            revoke(id, "longe")
            return false
        end
        if (now - r.reportMs) > authTimeout(r, now) then
            revoke(id, "silencio")
            return false
        end
        refreshCadence(r, animal, now)
        -- blockMovement se limpa sozinho depois de ~8000 game-units.
        local b = animal:getBehavior()
        if b then
            b:setBlockMovement(true)
        end
        return true
    end

    if busy then return deny("ocupado") end
    if not sameZ then return deny("andar") end
    if d._netAuthCoolMs and now < d._netAuthCoolMs then return deny("degelo") end
    if gap > CD.NET_AUTH_GRANT_DIST then return deny("longe") end
    -- Sem a sonda, a posse era concedida dentro de casa e devolvida no primeiro movel.
    local keep = CD.followKeepFrom(d)
    if gap > keep then
        local clear = CD.steerCorridorClear(animal, owner:getX(), owner:getY(), d, now, keep)
        local need = gap - keep
        local minClear = CD.FOLLOW_STEER_MIN_CLEAR
        if need > minClear then
            need = minClear
        end
        if need > 0 and clear < need then return deny("corredor") end
    end
    grant(animal, d, owner, id, now)
    return true
end

local function authAlive(r, now)
    local a = r.animal
    if not a or not a:isExistInTheWorld() then return false end
    if (now - r.reportMs) > authTimeout(r, now) then return false end
    -- seenMs so avanca enquanto o followOwner continua passando pela ficha.
    if r.seenMs and (now - r.seenMs) > CD.NET_AUTH_SEEN_MS then return false end
    return true
end

-- Pega o cao que PAROU de receber followOwner: combate assumiu, o dono caiu, o cao foi guardado.
---Server only. Also sends the held-back native update of a revoked dog whose client never sent the final position.
function CD.tickNetAuthority()
    if not isServer() then return end
    local now = getTimestampMs()
    for id, r in pairs(held) do
        if not authAlive(r, now) then
            revoke(id, "abandono")
        end
    end
    -- Client que nao devolveu a tempo: solta o pacote nativo com o que o servidor tem.
    for id, p in pairs(pending) do
        if (now - p.sinceMs) >= CD.NET_AUTH_YIELD_WAIT_MS then
            CD.perfCount("netauth.handoff.late")
            settle(id)
        end
    end
end

-- Conferencia e escrita de uma posicao vinda do client. Vale tanto pra posse viva quanto pra
-- devolucao que chega depois da revogacao: a checagem e a mesma, so o que se faz com a recusa muda.
-- Devolve false mais o motivo quando recusa.
local function writeReported(r, animal, args, now, meterLag)
    local nx, ny, nz = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not nx or not ny or not nz then return false end
    if nx ~= nx or ny ~= ny or nz ~= nz then return false end

    local dt = now - r.reportMs
    if dt < 0 then
        dt = 0
    end
    local budget = CD.NET_AUTH_MAX_SPEED * (dt / 1000) + 0.5
    local cap = CD.NET_AUTH_MAX_JUMP
    if budget > cap then
        budget = cap
    end
    local step = math.sqrt((nx - r.x) * (nx - r.x) + (ny - r.y) * (ny - r.y))
    if step > budget or math.abs(nz - r.z) > 1.01 then
        CD.perfCount("netauth.reject.passo")
        return false, "passo"
    end

    local cell = getCell()
    local sq = cell and cell:getGridSquare(math.floor(nx), math.floor(ny), math.floor(nz))
    if not CD.steerTileFree(sq) then
        CD.perfCount("netauth.reject.tile")
        return false, "tile"
    end

    if meterLag and dt > 0 and dt < 3000 then
        CD.perfCount("netauth.lag.sum", dt)
        CD.perfCount("netauth.lag.n")
    end
    r.reportMs, r.x, r.y, r.z = now, nx, ny, nz
    local d = CD.data(animal)
    local run = args.r == true and CD.mayRunFrom(d)
    animal:setX(nx)
    animal:setY(ny)
    animal:setNextX(nx)
    animal:setNextY(ny)
    animal:setZ(nz)
    local fx, fy = tonumber(args.fx), tonumber(args.fy)
    if fx and fy and (fx * fx + fy * fy) > 1e-6 then
        animal:setForwardDirection(fx, fy)
    end
    animal:setVariable("animalRunning", run)
    animal:setVariable("animalSpeed", run and CD.runAnimSpeed() or CD.walkAnimSpeed())
    if d then
        d.running = run or nil
    end
    return true
end

-- Unica porta em que um client escreve posicao de entidade do mundo. Tudo aqui e conferido.
local function netposApply(player, args)
    if not player or type(args) ~= "table" then return end
    local id = tonumber(args.id)
    if not id then return end
    local r = held[id]
    if not r or r.pid ~= player:getOnlineID() then return end
    local animal = r.animal
    if not animal or not animal:isExistInTheWorld() then
        revoke(id, "sumiu")
        return
    end

    local ok, why = writeReported(r, animal, args, getTimestampMs(), true)
    if not ok then
        if not why then return end
        r.rejects = (r.rejects or 0) + 1
        if r.rejects >= 3 then
            revoke(id, why)
        end
        return
    end
    r.rejects = 0
    CD.perfCount("netauth.pos")
end

---The owner's client reports the position of a dog it drives; speed and tile are checked before it is written.
---@param player IsoPlayer
---@param args table|nil { id, x, y, z, r, fx, fy }
CD.Server.netpos = function(player, args)
    return CD.pz("srv.netpos", netposApply, player, args)
end

-- Sinal de vida do cao parado: renova o prazo de silencio e nada mais. A posicao continua a do
-- ultimo netpos, que e a mesma que o client esta segurando.
---@param player IsoPlayer
---@param args table|nil { id }
CD.Server.netka = function(player, args)
    if not player or type(args) ~= "table" then return end
    local id = tonumber(args.id)
    if not id then return end
    local r = held[id]
    if not r or r.pid ~= player:getOnlineID() then return end
    if not r.animal or not r.animal:isExistInTheWorld() then
        revoke(id, "sumiu")
        return
    end
    r.reportMs = getTimestampMs()
    CD.perfCount("netauth.ka")
end

---The client hands the dog back with its final position; also closes a handback the server started.
---@param player IsoPlayer
---@param args table|nil { id, x, y, z, r, fx, fy, why }
CD.Server.netyield = function(player, args)
    if not player or type(args) ~= "table" then return end
    local id = tonumber(args.id)
    if not id then return end
    local r = held[id]
    if not r then
        -- Devolucao do que o SERVIDOR ja revogou. E o caminho comum: o combate assumir tira a posse
        -- pelo watchdog, e sem esta posicao o pacote nativo levaria a copia atrasada do servidor.
        local p = pending[id]
        if not p or p.pid ~= player:getOnlineID() then return end
        local animal = p.animal
        if animal and animal:isExistInTheWorld() and args.x then
            local nx, ny = tonumber(args.x), tonumber(args.y)
            local ox, oy = animal:getX(), animal:getY()
            if writeReported(p, animal, args, getTimestampMs(), false) then
                CD.perfCount("netauth.handoff.n")
                CD.perfCount("netauth.handoff.tiles",
                             math.sqrt((nx - ox) * (nx - ox) + (ny - oy) * (ny - oy)))
            else
                CD.perfCount("netauth.handoff.reject")
            end
        end
        settle(id)
        return
    end
    if r.pid ~= player:getOnlineID() then return end
    -- A posicao final passa pela MESMA conferencia de um report. Recusada, a devolucao segue assim
    -- mesmo: soltar o cao importa mais que aproveitar o ultimo passo.
    if args.x then
        netposApply(player, args)
    end
    revoke(id, tostring(args.why or "yield"))
    -- A posicao final ja veio nesta mesma mensagem: nao ha o que esperar.
    settle(id)
end
