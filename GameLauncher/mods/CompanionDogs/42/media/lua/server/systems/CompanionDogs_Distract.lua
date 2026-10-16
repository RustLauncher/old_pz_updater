CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.DISTRACTIONS = CD.DISTRACTIONS or {}

---@param name string
---@param handler table { find, drive, gate?, stop? }, all functions
---@return boolean registered
function CD.registerDistraction(name, handler)
    if type(name) ~= "string" or name == "" or type(handler) ~= "table" then
        CD.log("registerDistraction: recusado, precisa de um nome e de uma tabela de handler")
        return false
    end
    if type(handler.find) ~= "function" or type(handler.drive) ~= "function" then
        CD.log("registerDistraction: tipo '" .. name .. "' recusado, faltou find ou drive")
        return false
    end
    for _, opt in ipairs({ "gate", "stop" }) do
        if handler[opt] ~= nil and type(handler[opt]) ~= "function" then
            CD.log("registerDistraction: tipo '" .. name .. "' recusado, " .. opt .. " nao e funcao")
            return false
        end
    end
    if CD.DISTRACTIONS[name] then
        CD.log("registerDistraction: o tipo '" .. name .. "' JA existe; o registro novo foi ignorado " ..
              "(dois addons disputando o mesmo nome?)")
        return false
    end
    CD.DISTRACTIONS[name] = handler
    if CD.DEBUG_DISTRACT then
        CD.log("[CD-DISTRACT] tipo '" .. name .. "' registrado")
    end
    return true
end

local function active(d, now)
    return d.distractUntilMin ~= nil and now < d.distractUntilMin
end

---A breed distraction is running and its time is not up.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
CD.distractActive = function(animal)
    return active(CD.data(animal), CD.worldMinutes())
end

local scanWinMs, scanWinN = 0, 0
local function scanBudgetOk()
    local now = getTimestampMs()
    if (now - scanWinMs) >= 1000 then
        scanWinMs = now
        scanWinN = 0
    end
    if scanWinN >= CD.DISTRACT_SCANS_PER_SEC then return false end
    scanWinN = scanWinN + 1
    return true
end

local function endDistract(animal, d)
    if d.distractUntilMin == nil then return end
    local kind = d.distractKind
    local cfg = kind and CD.breedDistract(animal, kind)
    local ran = d.distractRan == true
    d.distractUntilMin = nil
    d.distractKind = nil
    d.distractRan = nil
    d.distractNextMin = CD.worldMinutes() + ((cfg and cfg.cooldownMin) or CD.DISTRACT_COOLDOWN_MIN)
    local h = kind and CD.DISTRACTIONS[kind]
    if h and type(h.stop) == "function" then
        h.stop(animal, d)
    end
    if ran then
        CD.grantObedienceXP(animal)
    end
    CD.transmit(animal)
end
CD.endDistract = endDistract

local function commonGates(animal, owner)
    if owner:isAsleep() then return false, "dono dormindo" end
    if animal:getVehicle() ~= nil then return false, "dentro de veiculo" end
    local spd = getGameSpeed()
    if spd > 1 and not CD.DISTRACT_IN_FAST_FORWARD then
        return false, "jogo acelerado (velocidade " .. tostring(spd) .. ")"
    end
    return true
end

-- Diagnostico: por que a distracao nao disparou. So com CD.DEBUG_DISTRACT, e com throttle proprio,
-- senao cada bicho ativo escreveria uma linha por passada.
local function dbg(animal, reason)
    if not CD.DEBUG_DISTRACT then return end
    if CD.cooldown(animal, "distractDbg", 3000) then return end
    CD.log("[CD-DISTRACT] " .. tostring(CD.getBreed(animal)) .. " " ..
          tostring(animal:getOnlineID()) .. ": " .. reason)
end

local function rollNew(animal, owner, d, decl, now)
    if d.distractNextMin and now < d.distractNextMin then
        dbg(animal, string.format("em cooldown, faltam %.0f game-min", d.distractNextMin - now))
        return nil
    end
    local passouGates, motivoGate = commonGates(animal, owner)
    if not passouGates then
        dbg(animal, "barrado: " .. tostring(motivoGate))
        return nil
    end
    if not CD.cooledDown(animal, "distractRoll", CD.DISTRACT_ROLL_MS) then
        if CD.DEBUG_DISTRACT and not CD.cooldown(animal, "distractDbgVivo", 10000) then
            CD.log("[CD-DISTRACT] " .. tostring(CD.getBreed(animal)) ..
                  ": vivo, aguardando o intervalo entre sorteios")
        end
        return nil
    end
    for name, cfg in pairs(decl) do
        local h = CD.DISTRACTIONS[name]
        if h == nil then
            dbg(animal, "tipo '" .. tostring(name) .. "' declarado mas SEM handler registrado")
        end
        if h and type(cfg) == "table" then
            local chance = cfg.chance or CD.DISTRACT_CHANCE
            if chance > 0 then
                local passed = true
                if type(h.gate) == "function" then
                    passed = h.gate(animal, cfg) and true or false
                end
                if not passed then
                    dbg(animal, "tipo '" .. tostring(name) .. "' barrado no gate do handler")
                end
                if passed then
                    if not scanBudgetOk() then
                        dbg(animal, "barrado no orcamento global de scan")
                        return nil
                    end
                    CD.stamp(animal, "distractRoll")
                    local found = h.find(animal, cfg)
                    if not found then
                        dbg(animal, "tipo '" .. tostring(name) .. "': scan nao achou alvo no raio")
                    end
                    if found then
                        if ZombRand(0, 1000) < chance * 1000 then
                            d.distractUntilMin = now + (cfg.durationMin or CD.DISTRACT_MIN)
                            d.distractKind = name
                            if CD.DEBUG_DISTRACT then
                                CD.log("[CD-DISTRACT] " .. tostring(CD.getBreed(animal)) ..
                                      ": DISTRAIU com o tipo '" .. tostring(name) .. "'")
                            end
                            CD.notifyOwner(owner, "refused", {
                                reason = "distracted", name = d.name, breed = CD.getBreed(animal),
                            })
                            return name
                        end
                        dbg(animal, string.format("tipo '%s': achou alvo mas a chance de %.0f%% nao passou", tostring(name), chance * 100))
                    end
                    return nil
                end
            end
        end
    end
    return nil
end

---Breed distraction: drives the one running, or rolls a new one when allowed; ends it when the drive lets go.
---@param animal IsoAnimal
---@param owner IsoPlayer
---@param d table companion ModData
---@return boolean true while the distraction owns the dog this tick
function CD.tryDistract(animal, owner, d)
    local decl = CD.getBreedDef(animal).distract
    if decl == nil then
        if CD.DEBUG_DISTRACT and not CD.cooldown(animal, "distractDbgSemDecl", 10000) then
            CD.log("[CD-DISTRACT] " .. tostring(CD.getBreed(animal)) .. ": a raca resolvida nao declara distract")
        end
        return false
    end
    local now = CD.worldMinutes()

    local kind
    if active(d, now) then
        kind = d.distractKind
    else
        if d.distractUntilMin ~= nil then
            endDistract(animal, d)
            return false
        end
        kind = rollNew(animal, owner, d, decl, now)
        if kind == nil then return false end
    end

    local h = CD.DISTRACTIONS[kind]
    local cfg = decl[kind]
    if not h or type(cfg) ~= "table" then
        endDistract(animal, d)
        return false
    end

    local driven = h.drive(animal, owner, d, cfg)
    if driven then
        d.distractRan = true
    end
    if not driven then
        endDistract(animal, d)
    end
    return driven and true or false
end
