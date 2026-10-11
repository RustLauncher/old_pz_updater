--[[
    Liga e desliga a receita conforme a sandbox option EnableCrafting.

    POR QUE ISTO EXISTE EM LUA: script .txt nao le SandboxVars. E nao ha portao no
    proprio craftRecipe -- procurei. Os campos de callback que ele aceita sao
    OnTest, OnStart, OnUpdate, OnCreate e OnFailed, e o OnTest, que era o candidato
    obvio pelo nome, e `OnTestItem(item, character)`: um teste por ITEM DE ENTRADA,
    nao um portao da receita. Usa-lo para desligar o craft faria a receita aparecer
    como "faltam ingredientes", que mente sobre o motivo.

    COMO FUNCIONA: a receita nao tem AutoLearn, entao ela nunca e conhecida por
    conta propria. Aqui ela e ENSINADA quando a opcao esta ligada. A lista de
    receitas conhecidas do personagem e mutavel (getKnownRecipes), e e o mesmo
    caminho que profissao e tracos usam -- ver applyProfessionRecipes no engine.

    O nivel de MetalWelding continua sendo cobrado pelo script, em SkillRequired.
    Cada portao no seu lugar: o de jogo no script, onde a interface o mostra ao
    jogador, e o de configuracao aqui.
]]

local WB_Sandbox = require "WB_Sandbox"

local WB_Recipe = {}

--- Precisa bater com o nome do craftRecipe em recipes_wheelbarrow.txt.
local RECIPE = "MakeWheelbarrow"

--- @return boolean se o personagem ja conhece a receita
local function knows(character)
    local known = character:getKnownRecipes()
    if known == nil then return false end
    for i = 0, known:size() - 1 do
        if known:get(i) == RECIPE then return true end
    end
    return false
end

--- Ensina ou esquece a receita, conforme a opcao.
---
--- Roda a cada entrada no jogo, e nao uma vez so: a opcao vive no save e o admin
--- pode muda-la entre sessoes. Desligar tem de tirar a receita de quem ja a tinha,
--- senao a opcao so valeria para personagem novo.
function WB_Recipe.sync(character)
    if character == nil then return end
    local known = character:getKnownRecipes()
    if known == nil then return end

    local enabled = WB_Sandbox.get("EnableCrafting") == true
    local has = knows(character)

    if enabled and not has then
        known:add(RECIPE)
    elseif not enabled and has then
        known:remove(RECIPE)
    end

    if getDebug() then
        print("[Wheelbarrow][RECEITA] " .. RECIPE
            .. (enabled and " disponivel" or " desligada pela sandbox"))
    end
end

local function syncLocalPlayers()
    for i = 0, getNumActivePlayers() - 1 do
        WB_Recipe.sync(getSpecificPlayer(i))
    end
end

-- OnCreatePlayer cobre personagem novo e tela dividida; OnGameStart cobre o
-- carregamento de um save existente, onde OnCreatePlayer nao dispara de novo.
Events.OnCreatePlayer.Add(function(_index, character) WB_Recipe.sync(character) end)
Events.OnGameStart.Add(syncLocalPlayers)

return WB_Recipe
