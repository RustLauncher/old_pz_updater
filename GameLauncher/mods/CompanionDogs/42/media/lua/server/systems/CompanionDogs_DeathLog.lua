CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local HIT_WINDOW_MS = 10000

-- Golpe de arma que chegou ao Hit do cao e o ghost.onHit anulou, por animKey.
local lastHit = {}

local function yn(b)
    return b and "S" or "N"
end

local function marked(c, name)
    return c:getVariableBoolean(name) or c:getVariableString(name) == "true"
end

local function who(c, dog)
    if c == nil then return "ninguem" end
    if c == dog then return "o-proprio" end
    if instanceof(c, "IsoAnimal") then return "animal:" .. tostring(c:getAnimalType()) end
    if instanceof(c, "IsoZombie") then
        if CD.isBanditNPC(c) then
            return CD.isFriendlyBanditNPC(c) and "npc-bandits-amigo" or "npc-bandits-hostil"
        end
        for i = 1, #CD.NPC_MARKER_VARS do
            local name = CD.NPC_MARKER_VARS[i]
            if marked(c, name) then return "npc:" .. name end
        end
        if c:getModData().ProjectALifeUID ~= nil then return "npc-alife" end
        return "zumbi"
    end
    if instanceof(c, "IsoPlayer") then return "jogador:" .. tostring(c:getUsername()) end
    return tostring(c)
end

local function heldType(chr)
    local it = chr and chr:getPrimaryHandItem()
    return it and it:getFullType() or "-"
end

---Remembers the last weapon hit the dog shrugged off, for the death report; hits less than HIT_WINDOW_MS apart add up.
---@param dog IsoAnimal
---@param wielder IsoGameCharacter|nil
---@param weapon HandWeapon|nil
---@param damage number|nil
function CD.noteDogHit(dog, wielder, weapon, damage)
    local key = CD.animKey(dog)
    local now = getTimestampMs()
    local h = lastHit[key]
    if h == nil then
        h = { n = 0, ms = now }
        lastHit[key] = h
    end
    if now - h.ms > HIT_WINDOW_MS then
        h.n = 0
    end
    h.n = h.n + 1
    h.ms = now
    h.who = who(wielder, dog)
    h.weapon = weapon and weapon:getFullType() or "-"
    h.dmg = tonumber(damage) or 0
end

-- isDead() tambem da morto com o BodyDamage zerado, e a engine nao atualiza o BodyDamage de animal:
-- parte ferida ali e escrita de fora, como o dano que o Bandits manda pelo PlayerDamage.
---@param animal IsoAnimal
---@param via string where the death was seen, for the log line
function CD.logCompanionDeath(animal, via)
    local d = CD.data(animal)
    if d.deathLogged then return end
    d.deathLogged = true
    local key = CD.animKey(animal)
    local h = lastHit[key]
    lastHit[key] = nil
    local hit = "nenhum"
    if h then
        hit = string.format("%s:%s:%dms:dano=%.2f:golpes=%d", h.weapon, h.who, getTimestampMs() - h.ms, h.dmg, h.n)
    end
    local body, hurtParts = -1, 0
    local bd = animal:getBodyDamage()
    if bd then
        body = bd:getHealth()
        local parts = bd:getBodyParts()
        for i = 0, parts:size() - 1 do
            if parts:get(i):getHealth() < 100 then
                hurtParts = hurtParts + 1
            end
        end
    end
    local owner = CD.getOwnerPlayer(animal, d)
    local ownerName, dist, ownerWeapon, aiming = "-", -1, "-", false
    if owner then
        ownerName = tostring(owner:getUsername())
        local dx, dy = owner:getX() - animal:getX(), owner:getY() - animal:getY()
        dist = math.sqrt(dx * dx + dy * dy)
        ownerWeapon = heldType(owner)
        aiming = owner:isAiming()
    end
    local cell = getCell()
    local ol = cell and cell:getObjectList()
    local atk = animal:getAttackedBy()
    CD.log(string.format("[CD-DEATH] cao=%s raca=%s via=%s vida=%.3f corpo=%.1f partes=%d inv=%s god=%s"
        .. " fogo=%s atropelado=%s veiculo=%s atacante=%s arma-atacante=%s golpe-anulado=%s na-celula=%s"
        .. " estado=%s combate=%s fome=%.2f sede=%.2f dono=%s dist=%.1f arma-dono=%s mirando=%s modo=%s"
        .. " mult=%.1f em=(%.1f,%.1f,%d)",
        tostring(d.name), tostring(CD.getBreed(animal)), via, animal:getHealth(), body, hurtParts,
        yn(animal:isInvincible()), yn(animal:isGodMod()), yn(animal:isOnFire()), yn(animal:isRoadKill()),
        yn(animal:getVehicle() ~= nil), who(atk, animal), heldType(atk), hit,
        yn(ol ~= nil and ol:contains(animal)), tostring(CD.getState(animal)), yn(d.inCombat),
        animal:getHunger(), animal:getThirst(), ownerName, dist, ownerWeapon, yn(aiming),
        isServer() and "servidor" or "SP", getGameTime():getMultiplier(),
        animal:getX(), animal:getY(), math.floor(animal:getZ())))
end

local function onCharacterDeath(chr)
    if not CD.isDog(chr) or not CD.isCompanion(chr) then return end
    CD.logCompanionDeath(chr, "evento")
end

if not isClient() then
    CD.evAdd(Events.OnCharacterDeath, onCharacterDeath, "srv.deathlog")
end
