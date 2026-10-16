CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- Bonus de XP que a raca da ao DONO. NUNCA instalar isso com addXpMultiplier: a engine guarda o
-- multiplicador no xpMapMultiplier do personagem, que entra no save (e no players.db do servidor).
-- Ele sobrevive a dispensa do cao e a desinstalacao do mod, e ai ninguem mais tem como tirar.
-- O bonus vive em memoria no servidor (systems/CompanionDogs_XPBoost.lua) e e concedido como XP
-- extra no Events.AddXP.

local defs

local function addPerk(list, perk)
    list[#list + 1] = perk
end

---Owner XP boosts by id, each { breed, perks, mult } where mult() gives the multiplier; built once and cached.
---@return table<string, table> boosts
function CD.ownerXPBoosts()
    if defs ~= nil then return defs end
    defs = {}

    local golden = {}
    addPerk(golden, Perks.PlantScavenging)
    addPerk(golden, Perks.Trapping)
    addPerk(golden, Perks.Aiming)
    defs.keennose = { breed = "retriever", perks = golden, mult = CD.goldenXPMult }

    local husky = {}
    addPerk(husky, Perks.Strength)
    defs.warmed = { breed = "husky", perks = husky, mult = CD.huskyStrengthXPMult }

    local collie = {}
    addPerk(collie, Perks.Husbandry)
    addPerk(collie, Perks.Farming)
    defs.herdinginstinct = { breed = "bordercollie", perks = collie, mult = CD.collieXPMult }

    return defs
end

-- Save gravado ate a 0.7.2: apaga a entrada que aquelas versoes deixavam no personagem. So mexe nos
-- seis pericias das tres racas e so em valor ate o nosso teto; livro de pericia usa o MESMO slot e
-- chega a 3x ou 5x. Roda UMA vez por personagem (flag no modData), server-side, que e a copia que
-- vai para o disco.
---@param player IsoPlayer|nil
function CD.purgeOwnerXPMultipliers(player)
    if not player then return end
    local pd = CD.playerData(player)
    if pd.xpMultPurged then return end
    local xp = player:getXp()
    local map = xp and xp:getMultiplierMap()
    if not map then return end
    pd.xpMultPurged = true
    local hit = 0
    for _, def in pairs(CD.ownerXPBoosts()) do
        local ceiling = def.mult()
        for _, perk in ipairs(def.perks) do
            local cur = xp:getMultiplier(perk)
            if cur > 0 and cur <= ceiling then
                map:remove(perk)
                hit = hit + 1
            end
        end
    end
    if hit > 0 then
        CD.log("[CD-XPBOOST] limpeza de save antigo: " .. hit .. " multiplicador(es) removido(s) de " ..
               tostring(CD.ownerKey(player)))
    end
end
