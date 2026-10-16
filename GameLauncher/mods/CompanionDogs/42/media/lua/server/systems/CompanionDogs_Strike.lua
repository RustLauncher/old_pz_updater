CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function bark(animal)
    if CD.cooldown(animal, "bark", CD.BARK_COOLDOWN_MS) then return false end
    CD.emitSound(animal, CD.breedVoice(animal, "bark"))
    return true
end

---@param animal IsoAnimal
---@return boolean barked false while the bark cooldown runs
CD.barkOnce = function(animal) return bark(animal) end

local function strikeExchange(animal, z)
    local zdead = z == nil or z:isDead() or z:getHealth() <= 0 or not CD.isThreatZombie(z)
    if zdead or not CD.inWorldNow(z) then return end
    -- A engine so atribui onlineId ao zumbi fora dos estados de queda, staggerback, hit-reaction e
    -- fake-dead, e o mod derruba zumbi. Sem id nao ha chave de ledger nem alvo pra delegar a morte.
    local zid = z:getOnlineID()
    if isServer() and zid == -1 then return end
    if isServer() and zid ~= -1 and CD.zdmg then
        local prec = CD.zdmg[zid]
        if prec and prec.pend then
            if (getTimestampMs() - prec.pend) < CD.ZKILL_ACK_MS then return end
            if (prec.tries or 1) >= 2 then
                CD.zdmg[zid] = nil
            else
                prec.pend = nil
            end
            if CD.DMG_DEBUG then
                CD.log("[CD-DMG] kill-SEM-RESPOSTA z=" .. tostring(zid) .. " tentativas=" .. tostring(prec.tries or 1))
            end
        end
    end
    local now = getTimestampMs()
    if CD.cooldown(animal, "hit", CD.HIT_COOLDOWN_MS) then return end

    CD.emitSound(animal, CD.BITE_SOUND)
    CD.emitAnim(animal)

    if CD.breedCanKnockdown(animal)
        and CD.cooledDown(animal, "knock", CD.knockdownCooldownMs())
        and ZombRand(0, 1000) < CD.knockdownChance(animal) * 1000 then
        if CD.emitKnockdown(z) then
            CD.stamp(animal, "knock")
        end
    end

    local xpRate = CD.combatXPRate(animal)
    local killed = false
    local canKill = CD.breedCanKill(animal)
    local dmg = CD.effectiveHitDamage(animal)
    local hp0 = z:getHealth()
    -- Dedicado: o setHealth parcial server-side nao gruda, o client dono reenvia a vida a cada 200ms e
    -- o server aplica verbatim. Ledger proprio por onlineID e Kill delegado ao client dono.
    local useLedger = isServer() and zid ~= -1
    local remaining
    if useLedger then
        CD.zdmg = CD.zdmg or {}
        local rec = CD.zdmg[zid]
        if not rec or (now - (rec.t or now)) > CD.ZDMG_STALE_MS then
            rec = { hp = z:getHealth() }
        end
        rec.hp = math.min(rec.hp, z:getHealth()) - dmg
        rec.t = now
        CD.zdmg[zid] = rec
        remaining = rec.hp
    else
        remaining = z:getHealth() - dmg
    end
    local ledger = remaining
    if remaining <= 0 and canKill then
        if not useLedger then
            killed = true
            z:setHealth(0)
            z:Kill(animal)
        else
            local ownr = CD.getOwnerPlayer(animal)
            local rec = CD.zdmg[zid]
            if rec then
                rec.hp = 0
            end
            if ownr then
                killed = true
                if rec then
                    rec.pend = getTimestampMs()
                    rec.tries = (rec.tries or 0) + 1
                end
                z:setHealth(0)
                z:Kill(animal)
                sendServerCommand(ownr, CD.MODULE, "killzombie", { id = zid, zx = z:getX(), zy = z:getY(), zz = z:getZ() })
            end
            CD.perfCount("dmg.kill")
            if CD.DMG_DEBUG then
                CD.log(string.format("[CD-DMG] kill cao=%s z=%s em=(%.1f,%.1f,%d) dono=%s enviado=%s tentativa=%d",
                    tostring(animal:getOnlineID()), tostring(zid), z:getX(), z:getY(), math.floor(z:getZ()),
                    ownr and tostring(ownr:getUsername()) or "NIL", ownr and "S" or "N", (rec and rec.tries) or 0))
            end
        end
    else
        if not canKill and remaining < CD.SUBLETHAL_HEALTH_FLOOR then
            remaining = CD.SUBLETHAL_HEALTH_FLOOR
            if useLedger then
                CD.zdmg[zid].hp = remaining
            end
            ledger = remaining
        end
        z:setHealth(math.max(remaining, 0))
    end
    CD.perfCount("dmg.strike")
    if CD.DMG_DEBUG then
        local hp1 = z:getHealth()
        CD.log(string.format("[CD-DMG] golpe cao=%s z=%s dmg=%.2f hp=%.2f->%.2f ledger=%.2f lgr=%s mata=%s letal=%s mult=%.2f",
            tostring(animal:getOnlineID()), tostring(zid), dmg, hp0, hp1, ledger,
            useLedger and "S" or "N", canKill and "S" or "N", killed and "S" or "N",
            CD.hitDamage()))
    end
    CD.addSkillXP(animal, "combat", CD.COMBAT_XP_PER_STRIKE * xpRate)
    if killed then
        CD.addSkillXP(animal, "combat", CD.COMBAT_XP_PER_KILL * xpRate)
        CD.recordDogZombieKill(animal)
    end
    CD.vetRollCombat(animal)

    CD.addCombatStress(animal, CD.effectiveCombatStress(animal))
    CD.transmit(animal)
end
CD.strikeExchange = strikeExchange

CD.ZDMG_SWEEP_MIN = 10
---Drops damage ledger entries with no kill pending once they sit idle for ZDMG_SWEEP_MIN.
function CD.zdmgSweep()
    local t = CD.zdmg
    if not t then return end
    local now = CD.worldMinutes()
    local cut = CD.ZDMG_SWEEP_MIN
    for zid, rec in pairs(t) do
        if not rec.pend and (now - (rec.t or now)) > cut then
            t[zid] = nil
        end
    end
end
CD.bark = bark
