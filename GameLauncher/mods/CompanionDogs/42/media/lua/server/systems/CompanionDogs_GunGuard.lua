CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local gunGuarded = {}
local gunGuardUntil = {}
local gunGuardTick = 0
local clientAimHintUntil = {}

-- Quem tem arma de fogo na mao vem do OnEquipPrimary (no servidor o EquipPacket passa pelo mesmo
-- setter); so esses sao sondados. A varredura completa cobre quem conecta ja armado.
local armed = {}

local function rangedInHand(player)
    local w = player:getPrimaryHandItem()
    return w ~= nil and instanceof(w, "HandWeapon") and w:isRanged()
end

local function onEquipPrimary(chr, item)
    if not chr or not instanceof(chr, "IsoPlayer") or instanceof(chr, "IsoAnimal") then return end
    CD.perfCount("gunguard.equip")
    local id = chr:getOnlineID()
    if item ~= nil and instanceof(item, "HandWeapon") and item:isRanged() then
        armed[id] = chr
    else
        armed[id] = nil
    end
end

-- Jogadores com arma de fogo na mao, por id: e o unico barulho que faz um cao SEGUINDO valer a
-- trava de posicao. Grito e porta so dao um passo, que o seguir desfaz sozinho.
---@return table<integer, IsoPlayer> armed by online ID; the live table, not a copy
---@nodiscard
function CD.armedPlayers()
    return armed
end

local function isAimingThreat(player, id)
    if player:isAiming()
        or player:isAttacking()
        or player:isPerformingHostileAnimation() then return true end
    return (clientAimHintUntil[id] or 0) >= gunGuardTick
end

CD.Server = CD.Server or {}
---The client says its player is aiming; counts as armed and aiming for GUN_AIM_HINT_TTL guard ticks.
---@param player IsoPlayer
function CD.Server.aimhint(player)
    if not player then return end
    local id = player:getOnlineID()
    clientAimHintUntil[id] = gunGuardTick + CD.GUN_AIM_HINT_TTL
    armed[id] = player
end

-- Passagem de bala no SP: o GOD_MODE que tiraria o cao da hit list e no-op sem -debug, entao o cao
-- sai da objectList da cell no frame do disparo e volta no tick seguinte.
local ghost = { removed = {} }
function ghost.onFire(owner, weapon)
    if not owner or not weapon then return end
    if isServer() then return end
    local ranged = instanceof(weapon, "HandWeapon") and weapon:isRanged()
    if not ranged then return end
    local cell = getCell()
    if not cell then return end
    CD.regEach(CD.regCompanions(), function(a)
        if a:isGodMod() then return end
        local ol = cell:getObjectList()
        -- O registro pode estar atrasado e listar cao que ja saiu do mundo (colo, guardado): so volta
        -- no readd o que esta remocao de fato tirou.
        if ol and ol:remove(a) then
            ghost.removed[#ghost.removed + 1] = a
            ghost.any = true
        end
    end)
end

function ghost.readd()
    if not ghost.any then return end
    local cell = getCell()
    if not cell then return end
    ghost.any = false
    local list = ghost.removed
    ghost.removed = {}
    local ol = cell:getObjectList()
    for i = 1, #list do
        if ol then
            ol:add(list[i])
        end
    end
end

-- OnWeaponHitCharacter dispara dentro de IsoGameCharacter.Hit, antes do `if (avoidDamage) return 0`:
-- setar aqui faz o Hit devolver 0 e o hitConsequences nunca roda.
function ghost.onHit(wielder, victim, weapon, damage)
    if victim and CD.isDog(victim) and CD.isCompanion(victim) then
        victim:setAvoidDamage(true)
        CD.noteDogHit(victim, wielder, weapon, damage)
    end
end

local function setGunGuard(animal, on)
    local d = CD.data(animal)
    if on then
        if animal then
            animal:setInvulnerable(true)
        end
        if d.gunHungerSave == nil then
            if animal then
                d.gunHungerSave = animal:getHunger()
            end
            CD.transmit(animal)
        end
    else
        if animal then
            animal:setInvulnerable(false)
        end
        if d.gunHungerSave ~= nil then
            local h = d.gunHungerSave
            d.gunHungerSave = nil
            CD.setNeed(animal, "hunger", h)
            CD.transmit(animal)
        end
    end
end

-- O relogio anda por tick (hold e TTL do aimhint contam nele); so a sondagem da mao de cada
-- jogador anda em passo maior. Quem protege o cao no quadro do tiro e o client do atirador e o
-- invencivel do servidor, aqui e a trava de posicao, que aguenta 2 ticks de atraso.
local sweepPhase = 0
local rescanPhase = 0
local function tickGunGuard()
    gunGuardTick = gunGuardTick + 1
    sweepPhase = sweepPhase + 1
    if sweepPhase < CD.GUN_GUARD_SWEEP_TICKS then return end
    sweepPhase = 0
    local cell = getCell()
    if not cell then return end
    rescanPhase = rescanPhase + CD.GUN_GUARD_SWEEP_TICKS
    if rescanPhase >= CD.GUN_GUARD_RESCAN_TICKS then
        rescanPhase = 0
        local fresh = {}
        CD.eachOnlinePlayer(function(p)
            if p then
                CD.perfCount("gunguard.hands")
                local id = p:getOnlineID()
                if rangedInHand(p) then
                    if not armed[id] then
                        CD.perfCount("gunguard.rescan.fix")
                    end
                    fresh[id] = p
                end
            end
        end)
        armed = fresh
    end
    local aimers = nil
    for id, p in pairs(armed) do
        CD.perfCount("gunguard.armed")
        if isAimingThreat(p, id) then
            aimers = aimers or {}
            aimers[#aimers + 1] = { x = p:getX(), y = p:getY(), z = math.floor(p:getZ()) }
        end
    end

    if aimers then
        local R = CD.GUN_RISK_RADIUS
        local R2 = R * R
        local hold = CD.GUN_GUARD_HOLD_TICKS
        local comps = CD.regCompanions()
        for i = 1, #comps do
            local a = comps[i]
            if a:isExistInTheWorld() then
                local ax, ay, az = a:getX(), a:getY(), math.floor(a:getZ())
                local near = false
                for j = 1, #aimers do
                    local p = aimers[j]
                    if p.z == az then
                        local dx, dy = ax - p.x, ay - p.y
                        if dx * dx + dy * dy <= R2 then
                            near = true
                            break
                        end
                    end
                end
                if near then
                    local id = a:getOnlineID()
                    if a:isShootable() then
                        a:setShootable(false)
                    end
                    if not gunGuarded[id] then
                        gunGuarded[id] = a
                        setGunGuard(a, true)
                    end
                    gunGuardUntil[id] = gunGuardTick + hold
                end
            end
        end
    end

    for id, a in pairs(gunGuarded) do
        if (gunGuardUntil[id] or 0) <= gunGuardTick then
            setGunGuard(a, false)
            gunGuarded[id] = nil
            gunGuardUntil[id] = nil
        end
    end
end
CD.gunGuarded, CD.gunGuardUntil = gunGuarded, gunGuardUntil
CD.tickGunGuard = tickGunGuard

---@param animal IsoAnimal
function CD.gunGuardRelease(animal)
    setGunGuard(animal, false)
end

if not isClient() then
    Events.OnEquipPrimary.Add(onEquipPrimary)
    CD.evAdd(Events.OnWeaponSwingHitPoint, ghost.onFire, "srv.ghostfire")
    CD.evAdd(Events.OnTick, ghost.readd, "srv.ghostreadd")
    CD.evAdd(Events.OnWeaponHitCharacter, ghost.onHit, "srv.ghosthit")
end
