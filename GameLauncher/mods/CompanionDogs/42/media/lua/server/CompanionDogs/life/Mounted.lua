CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function worldMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

local function advanceMountedNeeds(owner)
    if not CD.upkeepEnabled() then return end
    local pd = CD.playerData(owner)
    local rec = pd.stash
    if not rec then return end
    local now = worldMinutes()
    local last = rec.lastNeedMin
    if not last then
        rec.lastNeedMin = now
        return
    end
    local elapsed = now - last
    if elapsed < CD.UPKEEP_INTERVAL_MIN then return end
    rec.lastNeedMin = now
    elapsed = CD.applyOfflineDebt(owner, elapsed)
    if elapsed <= 0 then return end
    local step = math.min(elapsed, CD.UPKEEP_MAX_CATCHUP_MIN)
    local dDay = step / 1440
    rec.hunger = math.min(1, (rec.hunger or 0) + CD.hungerPerDay() * dDay)
    rec.thirst = math.min(1, (rec.thirst or 0) + CD.thirstPerDay() * dDay)
    owner:transmitModData()
end

local function tickMountedDogs()
    for id, animal in pairs(CD.mountedDogs) do
        local keep = false
        local owner = CD.getOwnerPlayer(animal)
        if owner and CD.isMounted(owner) then
            CD.mountRefresh(animal, owner, CD.data(animal))
            advanceMountedNeeds(owner)
            keep = true
        end
        if not keep then
            local done = true
            if animal then
                done = CD.mountClear(animal, CD.data(animal))
            end
            if done then
                CD.mountedDogs[id] = nil
            end
        end
    end
end

-- O custo e reescrever o mesmo valor no mesmo objeto a cada passe: a memoria pula a repetição e
-- e apagada a cada 30 s, o que reafirma o que a engine possa ter limpado e solta objeto que saiu.
local MEMO_CLEAR_PASSES = 15
local memoPass = 0
local gaitMemo, wildMemo, acceptMemo, invMemo = {}, {}, {}, {}

-- Quem estava carregado na passada anterior. Fome, sede e doença correm pela diferenca de um carimbo
-- contra o relogio do mundo, e o relogio nao para quando o pet descarrega... sem esta lista o pet volta
-- e paga pelo tempo em que nem existia... pet deixado na base enquanto o dono joga longe chegava a
-- levar 0,75 de vida de uma vez ao reaparecer.
local inPlay = nil

---@param animal IsoAnimal
---@return boolean true when the animal was already loaded on the previous sweep
---@nodiscard
function CD.wasInPlay(animal)
    -- Antes da primeira passada a lista nao existe, e ai vale o comportamento de sempre: mecanismo
    -- ausente nao pode mudar regra de jogo calado.
    if inPlay == nil then return true end
    return inPlay[CD.animKey(animal)] == true
end

-- A engine nunca limpa `invincible` nem `shootable` sozinha (campos simples, fora do save): so
-- objeto novo ou o nosso proprio toggle de vida mexe neles, e o toggle restaura no mesmo tick.
-- `ragdollFall` a engine limpa ao fim de um ragdoll, e o memo de 30 s cobre isso.
local function assertGuards(a)
    if invMemo[a] then return end
    invMemo[a] = true
    if not a:isInvincible() then
        a:setIsInvincible(true)
    end
    if a:isShootable() then
        a:setShootable(false)
    end
    CD.suppressFallFlag(a)
end

-- `invincible` nao vai no save: cao relido do apop nasce mortal, e o curral que volta a carregar cobra
-- na hora a fome e a sede das horas em que ficou fora (DesignationZoneAnimal.doMeta), antes de a
-- varredura chegar nele. O construtor avisa ainda sem ModData; o LoadChunk do mesmo carregamento ja
-- ve o cao lido e no mundo, e o curral so roda depois, no fim do IsoWorld.update.
local born = {}

local function queueBorn(chr)
    if instanceof(chr, "IsoAnimal") then
        born[#born + 1] = chr
    end
end

---Makes invincible again every companion the engine created since the last call; the flag is not saved.
function CD.guardBornCompanions()
    if born[1] == nil then return end
    local list = born
    born = {}
    for i = 1, #list do
        local a = list[i]
        if CD.isDog(a) and CD.isCompanion(a) and not a:isInvincible() then
            CD.perfCount("inv.born")
            a:setIsInvincible(true)
        end
    end
end

local function tickCompanionInvincible()
    CD.guardBornCompanions()
    memoPass = memoPass + 1
    if memoPass >= MEMO_CLEAR_PASSES then
        memoPass = 0
        gaitMemo, wildMemo, acceptMemo, invMemo = {}, {}, {}, {}
    end
    local wildInv = CD.wildDogsInvincible()
    local offlineDespawn = isServer() and CD.despawnOnOwnerOffline()
    local seen = {}
    local toStash = {}
    local players, pid, px, py = {}, {}, {}, {}
    CD.eachOnlinePlayer(function(p)
        if p then
            local n = #players + 1
            players[n], pid[n], px[n], py[n] = p, p:getOnlineID(), p:getX(), p:getY()
        end
    end)
    local range = CD.EMIT_RANGE
    if not wildInv then
        CD.perfCount("inv.wildoff")
    end
    local now = getTimestampMs()
    CD.pz("srv.inv.strays", CD.regEach, CD.regStrays(), function(a)
        if not invMemo[a] then
            invMemo[a] = true
            CD.suppressFallFlag(a)
            if wildInv and not a:isInvincible() then
                CD.perfCount("inv.stray.write")
                a:setIsInvincible(true)
            end
        end
        CD.applyGaitScale(a, CD.PATH_RUN_IDLE_SCALE, nil, nil, gaitMemo)
        CD.pz("srv.inv.scav", CD.strayScavenge, a)
        CD.strayRoadTick(a, now, players, px, py)
    end)
    CD.pz("srv.inv.comps", CD.regEach, CD.regCompanions(), function(a)
        assertGuards(a)
        seen[CD.animKey(a)] = true
        local d = CD.data(a)
        -- Guarda de tiro que perdeu a entrada sem devolver a fome (reap, respawn de registro, colo).
        if d.gunHungerSave ~= nil and CD.gunGuarded[a:getOnlineID()] ~= a then
            CD.gunGuardRelease(a)
        end
        CD.floorlessRecoverOne(a, d)
        if d.isPup then
            local dt = a:getData()
            if dt then
                local want = CD.puppySize(a)
                if math.abs(dt:getSize() - want) > 0.01 then
                    dt:setSizeForced(want)
                end
            end
            -- Segura hoursSurvived dois dias abaixo do limite: o grow() nativo cria um animal novo e descarta o ModData.
            local capHours = (CD.MATURITY_DAYS - 2) * 24
            if a:getHoursSurvived() > capHours then
                a:setHoursSurvived(capHours)
            end
        end
        if not wildMemo[a] then
            wildMemo[a] = true
            a:setWild(false)
        end
        local owner = CD.getOwnerPlayer(a)
        -- a aceitaçao fica gravada no animal por jogador. Fora da caixa de relevancia ninguem
        -- interage com o cao, e quem se aproxima recebe no passe seguinte, bem antes de chegar.
        -- Companions x jogadoers num tick so era o stall do servidor cheio.
        local ownerId = owner and owner:getOnlineID()
        local ax, ay = a:getX(), a:getY()
        local seen = acceptMemo[a]
        if not seen then
            seen = {}
            acceptMemo[a] = seen
        end
        for pi = 1, #players do
            local p = pid[pi]
            if not seen[p] and (p == ownerId
               or (math.abs(px[pi] - ax) <= range and math.abs(py[pi] - ay) <= range)) then
                seen[p] = true
                CD.calmAcceptance(a, players[pi])
            end
        end
        local activeForOwner = owner ~= nil and d.companionToken == CD.playerData(owner).token
        local loose = not activeForOwner and not d.breedTarget and not d.careMode
        if loose then
            CD.applyGaitScale(a, CD.PATH_RUN_IDLE_SCALE, nil, d, gaitMemo)
        else
            CD.applyGaitScale(a, nil, nil, d, gaitMemo)
        end
        if offlineDespawn and owner == nil and d.ownerName then
            toStash[#toStash + 1] = a
        elseif loose then
            CD.pz("srv.inv.loiter", CD.tickLoiter, a)
        else
            CD.loiterForget(a)
        end
    end)
    for i = 1, #toStash do CD.offlineStashDog(toStash[i]) end
    -- Depois do stash: cao guardado nesta passada nao volta pelo mesmo objeto, e o respawn ja
    -- recarimba o relogio dele por conta propria.
    inPlay = seen
end

CD.tickMountedDogs = tickMountedDogs
CD.tickCompanionInvincible = tickCompanionInvincible

if not isClient() then
    CD.evAdd(Events.OnCreateLivingCharacter, queueBorn, "srv.bornqueue")
    CD.evAdd(Events.LoadChunk, CD.guardBornCompanions, "srv.bornguard")
end
