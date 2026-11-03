CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs
CD.Server = CD.Server or {}

-- Aura de aprendizado das racas (Golden, Husky, Border Collie). O client so avisa a borda liga/desliga
-- pelo comando `xpboost`; quem esta ligado mora aqui, em memoria, e some quando a sessao acaba.
-- O bonus e concedido no Events.AddXP, que a engine dispara em SP e no SERVIDOR (nunca em client de
-- MP), que e onde a XP de todas as seis pericias e creditada.

local active = {}
local purgeDone = {}
local granting = false

local function boostLog(msg)
    if not CD.DEBUG_XPBOOST then return end
    CD.log("[CD-XPBOOST] " .. msg)
end

-- A pericia de Forca leva um fator de proteina DENTRO do AddXP, fora do gate de doXPBoost. Sem
-- descontar aqui, o bonus do husky seria multiplicado por ele uma segunda vez.
local function proteinFactor(chr, perk)
    if perk ~= Perks.Strength then return 1 end
    local p = chr:getNutrition():getProteins()
    if p > 50 and p < 300 then return 1.5 end
    if p < -300 then return 0.7 end
    return 1
end

local function bestMultFor(set, perk)
    local best = 0
    local all = CD.ownerXPBoosts()
    for id in pairs(set) do
        local def = all[id]
        if def then
            for _, p in ipairs(def.perks) do
                if p == perk then
                    local m = def.mult()
                    if m > best then
                        best = m
                    end
                end
            end
        end
    end
    return best
end

local function onAddXP(chr, perk, amount)
    if granting or not chr or not perk then return end
    -- IsoAnimal estende IsoPlayer, e mod de NPC tambem ganha XP: em SP os dois cairiam na mesma
    -- ownerKey do jogador e levariam o bonus junto.
    if instanceof(chr, "IsoAnimal") then return end
    if chr:isNpc() then return end
    if amount <= 0 then return end
    local key = CD.ownerKey(chr)
    if not key then return end
    -- Qualquer ganho de XP serve de gancho para a limpeza de save antigo, inclusive de quem esta com
    -- os moodles desligados na sandbox e por isso nunca manda o comando.
    if not purgeDone[key] then
        purgeDone[key] = true
        CD.purgeOwnerXPMultipliers(chr)
    end
    local set = active[key]
    if not set then return end
    local xp = chr:getXp()
    local best = bestMultFor(set, perk)
    if best <= 1 then return end
    -- Livro de pericia ocupa o MESMO slot de multiplicador: o maior vence, sem empilhar.
    local book = xp:getMultiplier(perk)
    if book < 1 then
        book = 1
    end
    if best <= book then return end
    local bonus = amount * (best / book - 1) / proteinFactor(chr, perk)
    if bonus <= 0 then return end
    granting = true
    xp:AddXP(perk, bonus, false, false, false)
    granting = false
    boostLog(string.format("%s %s base=%.2f x%.2f (livro %.2f) bonus=%.2f",
        tostring(key), tostring(perk:getName()), amount, best, book, bonus))
end

---Turns one owner XP boost on or off; turning it on needs breed moodles enabled and a live companion of the boost's breed.
---@param player IsoPlayer
---@param args table { id, on }
CD.Server.xpboost = function(player, args)
    if not player or not args then return end
    local def = CD.ownerXPBoosts()[args.id]
    if not def then return end
    local key = CD.ownerKey(player)
    if not key then return end
    if args.on then
        -- Toggle de sandbox e regra do mundo: raca nao fura, e o servidor nao acredita no client.
        if not CD.breedMoodlesEnabled() then return end
        local dog = CD.getCompanionAnimal(player)
        if not dog or dog:isDead() then return end
        if CD.getBreed(dog) ~= def.breed then return end
        local set = active[key]
        if not set then
            set = {}
            active[key] = set
        end
        if set[args.id] then return end
        set[args.id] = true
        boostLog("liga " .. tostring(args.id) .. " para " .. tostring(key))
    else
        local set = active[key]
        if set and set[args.id] then
            set[args.id] = nil
            boostLog("desliga " .. tostring(args.id) .. " para " .. tostring(key))
            local empty = true
            for _ in pairs(set) do
                empty = false
                break
            end
            if empty then
                active[key] = nil
            end
        end
        CD.purgeOwnerXPMultipliers(player)
    end
end

CD.evAdd(Events.AddXP, onAddXP, "srv.xpboost")
