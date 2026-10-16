CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.API_VERSION = 11

---@type (fun(animal: IsoAnimal, owner: IsoPlayer))[] called when the dog delivers prey to its owner
CD.onHuntDelivered = CD.onHuntDelivered or {}

---@type (fun(animal: IsoAnimal, needsStress: number): number)[] each return adds to the needs stress
CD.onUpkeepStress = CD.onUpkeepStress or {}

---Sum of what the CD.onUpkeepStress handlers return; anything but a number counts as 0.
---@param animal IsoAnimal
---@param needsStress number stress the upkeep computed from needs
---@return number delta
function CD.upkeepStressDelta(animal, needsStress)
    local total = 0
    for i = 1, #CD.onUpkeepStress do
        local fn = CD.onUpkeepStress[i]
        if type(fn) == "function" then
            local delta = fn(animal, needsStress)
            if type(delta) == "number" then
                total = total + delta
            end
        end
    end
    return total
end

---Rebuilds CD.BREED_ORDER, the CD.BREEDS keys in alphabetical order.
function CD.rebuildBreedOrder()
    local order = {}
    for bk in pairs(CD.BREEDS) do order[#order + 1] = bk end
    table.sort(order)
    CD.BREED_ORDER = order
end

---Registers an addon breed. Required fields and format are in the modding manual.
---@param def table { key, typePrefix, nameKey, xpMult, combatPower, lethalityCurve, geneRange, ... }
---@return table|nil def the CD.BREEDS entry (the existing one if the key repeats); nil when refused
function CD.registerBreed(def)
    if type(def) ~= "table" or not def.key then
        CD.log("registerBreed: recusado, argumento nao e tabela ou nao tem 'key'")
        return nil
    end
    if CD.BREEDS[def.key] then
        CD.log("registerBreed: a chave de raca '" .. tostring(def.key) ..
              "' JA existe; o registro novo foi ignorado (dois addons disputando a mesma chave?)")
        return CD.BREEDS[def.key]
    end
    for _, field in ipairs({ "typePrefix", "nameKey", "xpMult", "combatPower", "lethalityCurve", "geneRange" }) do
        if def[field] == nil then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' recusada, falta o campo '" ..
                  field .. "' (API_VERSION " .. tostring(CD.API_VERSION) .. ")")
            return nil
        end
    end
    if def.huntMaxPrey ~= nil and CD.HUNT_PREY_RANK[def.huntMaxPrey] == nil then
        CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou huntMaxPrey='" ..
              tostring(def.huntMaxPrey) .. "', que nao e tiny/small/large; caindo em 'large' (sem teto)")
        def.huntMaxPrey = nil
    end
    if def.maleChance ~= nil then
        if type(def.maleChance) ~= "number" or def.maleChance < 0 or def.maleChance > 1 then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou maleChance='" ..
                  tostring(def.maleChance) .. "', que nao e um numero de 0 a 1 (0.25 e 25%, nao 25); " ..
                  "caindo no meio a meio")
            def.maleChance = nil
        end
    end
    if def.sterileMale ~= nil and type(def.sterileMale) ~= "boolean" then
        CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou sterileMale que nao e " ..
              "booleano; o macho dela continua cruzando")
        def.sterileMale = nil
    end
    if def.distract ~= nil then
        if type(def.distract) ~= "table" then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou distract que nao e tabela; " ..
                  "o formato e { <tipo> = { chance = <0..1> } } e este foi ignorado")
            def.distract = nil
        else
            for kind, cfg in pairs(def.distract) do
                local err
                if type(cfg) ~= "table" then
                    err = "nao e uma tabela de config"
                elseif cfg.chance ~= nil and type(cfg.chance) ~= "number" then
                    err = "tem chance que nao e numero"
                elseif type(cfg.chance) == "number" and (cfg.chance < 0 or cfg.chance > 1) then
                    err = "tem chance=" .. tostring(cfg.chance) .. ", fora de 0..1 (0.25 e 25%, nao 25)"
                elseif cfg.classes ~= nil and type(cfg.classes) ~= "table" then
                    err = "tem classes que nao e um set tipo { tiny = true }"
                end
                if err then
                    CD.log("registerBreed: raca '" .. tostring(def.key) .. "', distract['" .. tostring(kind) ..
                          "'] " .. err .. "; este tipo foi ignorado")
                    def.distract[kind] = nil
                end
            end
            local empty = true
            for _ in pairs(def.distract) do  -- next() nao existe no Kahlua do PZ
                empty = false
                break
            end
            if empty then
                def.distract = nil
            end
        end
    end
    if def.restPoses ~= nil then
        local poses = {}
        if type(def.restPoses) ~= "table" then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou restPoses que nao e tabela; " ..
                  "o formato e { 'cdRest', { var = 'cdSit', enter = ..., variation = { ... } } } e foi ignorado")
        else
            for i = 1, #def.restPoses do
                local pose = def.restPoses[i]
                if type(pose) == "string" then
                    pose = { var = pose }
                end
                if type(pose) ~= "table" or type(pose.var) ~= "string" then
                    CD.log("registerBreed: raca '" .. tostring(def.key) .. "', restPoses[" .. tostring(i) ..
                          "] nao e nome de variavel nem tabela com 'var'; esta pose foi ignorada")
                else
                    poses[#poses + 1] = pose
                end
            end
        end
        def.restPoses = (#poses > 0) and poses or nil
    end
    if type(def.voices) == "table" and type(CD.VOICE_DEFAULT) == "table" then
        local valid = {}
        for k in pairs(CD.VOICE_DEFAULT) do valid[k] = true end
        for k, v in pairs(def.voices) do
            if not valid[k] then
                local validNames = {}
                for kk in pairs(valid) do validNames[#validNames + 1] = kk end
                table.sort(validNames)
                CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou voices['" .. tostring(k) ..
                      "'], que nao e uma voz do mod; sera ignorado (as validas sao " ..
                      table.concat(validNames, ", ") .. ")")
            elseif CD.SOUND_CATEGORY and CD.SOUND_CATEGORY[v] == nil then
                CD.log("registerBreed: raca '" .. tostring(def.key) .. "' usa o som '" .. tostring(v) ..
                      "' em voices." .. tostring(k) .. " sem te-lo passado por CD.registerVoices; ele vai " ..
                      "tocar por fora do volume e do mute do jogador")
            end
        end
    end
    if def.species ~= nil then
        if type(def.species) ~= "string" then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou species que nao e texto; " ..
                  "sera ignorado e a raca conta como cao (o formato e species = \"cat\")")
            def.species = nil
        elseif CD.SPECIES and CD.SPECIES[def.species] == nil then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou species='" ..
                  tostring(def.species) .. "', que ninguem registrou com CD.registerSpecies; ela nao cruza " ..
                  "com outra especie, mas a UI vai chama-la de cao")
        end
    end
    if type(def.skills) == "table" then
        local known = {}
        for _, s in ipairs(CD.SKILLS) do known[s] = true end
        for k in pairs(def.skills) do
            if not known[k] then
                CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou skills['" .. tostring(k) ..
                      "'], que nao e uma skill do mod; sera ignorado (as validas sao " ..
                      table.concat(CD.SKILLS, ", ") .. ")")
            end
        end
        if def.skills.scent == false and def.alertModeLocked == true then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou skills.scent=false JUNTO com " ..
                  "alertModeLocked=true, que se contradizem; sem Faro nao ha sentinela pra travar, entao o " ..
                  "alertModeLocked nao tem efeito")
        end
    end
    if def.diet ~= nil then
        if type(def.diet) ~= "table" then
            CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou diet que nao e tabela; " ..
                  "o formato e { bad = { <FoodType> = true } } e este foi ignorado")
            def.diet = nil
        else
            for field, kind in pairs(CD.DIET_FIELDS) do
                local sub = def.diet[field]
                if sub ~= nil then
                    if type(sub) ~= "table" then
                        CD.log("registerBreed: raca '" .. tostring(def.key) .. "', diet." .. field ..
                              " nao e uma tabela; o formato e { <chave> = true|false } e este campo foi ignorado")
                        def.diet[field] = nil
                    else
                        -- a lista de renome sai da travessia: por em pairs uma chave nova enquanto se
                        -- itera a tabela e comportamento indefinido
                        local rename = {}
                        for k, v in pairs(sub) do
                            if type(k) ~= "string" then
                                CD.log("registerBreed: raca '" .. tostring(def.key) .. "', diet." .. field ..
                                      " tem uma chave que nao e texto; ela foi ignorada")
                                sub[k] = nil
                            elseif type(v) ~= "boolean" then
                                CD.log("registerBreed: raca '" .. tostring(def.key) .. "', diet." .. field ..
                                      "['" .. k .. "'] nao e true nem false; a chave foi ignorada")
                                sub[k] = nil
                            elseif kind == "parts" and string.lower(k) ~= k then
                                rename[#rename + 1] = k
                            end
                        end
                        for i = 1, #rename do
                            local k = rename[i]
                            sub[string.lower(k)] = sub[k]
                            sub[k] = nil
                        end
                    end
                end
            end
        end
    end
    if def.engineBreed and CD.BREED_BY_ENGINE and CD.BREED_BY_ENGINE[def.engineBreed] then
        CD.log("registerBreed: raca '" .. tostring(def.key) .. "' declarou engineBreed='" ..
              tostring(def.engineBreed) .. "', que a raca '" .. tostring(CD.BREED_BY_ENGINE[def.engineBreed]) ..
              "' ja usa; com o ModData ausente as duas vao resolver para a mesma")
    end
    CD.BREEDS[def.key] = def
    CD.clearDietCache()
    CD.TYPES[def.typePrefix .. "pup"] = true
    CD.TYPES[def.typePrefix .. "female"] = true
    CD.TYPES[def.typePrefix .. "male"] = true
    CD.rebuildBreedOrder()
    CD.rebuildEngineIndex()
    if def.spawns and CD.registerStraySpawns then
        CD.registerStraySpawns(def.spawns)
    end
    return def
end

-- Tipo de animal com `mate` preenchido entra no findFemaleToInseminate e a engine engravida a femea
-- sozinha, por fora do toggle e da sandbox. A engine so faz o parse no primeiro getDef().
Events.OnGameBoot.Add(function()
    for t in pairs(CD.TYPES) do
        local def = AnimalDefinitions.animals[t]
        if type(def) == "table" then
            def.mate = nil
        end
    end
end)
