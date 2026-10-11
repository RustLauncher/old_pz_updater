--[[
    Migracao: desfaz o encolhimento de peso de versoes anteriores do mod.

    HISTORICO -- por que isto existe e nao deve ser removido tao cedo:

    Uma versao anterior contornava o teto de capacidade de 50 reduzindo o peso
    real dos itens dentro do carrinho, com uma marca chamada MNWB_origWeight.
    Ela foi abandonada, e a explicacao registrada aqui estava ERRADA nos dois
    pontos que a sustentavam. Fica registrado porque o erro custou o recurso:

      O SINTOMA era o personagem sumir deixando so a sombra. Isso foi provado
      depois como sendo a tecla F3, que em modo debug e ToggleModelsEnabled e
      colide com a tecla de velocidade do tempo. Nao tinha relacao com peso --
      ver docs/personagem-invisivel.md.

      O MECANISMO alegado era "o jogo escolhe a animacao de carregar pelo PESO
      do item". Nao escolhe. isForceDropHeavyItem testa isHumanCorpse, tipo
      "Generator", a tag HEAVY_ITEM, "Animal" e "CorpseAnimal". Peso nao aparece
      em nenhum ramo. Conferido no bytecode de InventoryItem.

    A tecnica voltou, refeita com invariante e valor derivado do script, em
    WB_Repack.lua. Este arquivo continua existindo pela razao abaixo, que segue
    valendo: a marca ANTIGA e outra, e saves daquela epoca ainda a carregam.

    Este arquivo existe porque saves criados com aquela versao tem itens com o
    peso alterado gravado. Sem esta restauracao, um gerador de 40 ficaria
    pesando 6 para sempre naquele save. A varredura roda junto com o resto e se
    apaga sozinha: assim que um item e restaurado, a marca sai do ModData e ele
    nunca mais e tocado.
]]

local ORIG_KEY = "MNWB_origWeight"

local WB_Legacy = {}

--- Devolve o peso original de um item marcado por uma versao antiga.
--- @return boolean true se algo foi restaurado
function WB_Legacy.restore(item)
    if item == nil or not item:hasModData() then return false end
    local md = item:getModData()
    local original = md[ORIG_KEY]
    if original == nil then return false end

    item:setActualWeight(original)
    md[ORIG_KEY] = nil
    return true
end

--- Varre um container recursivamente restaurando o que estiver marcado.
function WB_Legacy.sweep(container, depth)
    depth = depth or 0
    if container == nil or depth > 3 then return end

    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        WB_Legacy.restore(item)
        if instanceof(item, "InventoryContainer") then
            WB_Legacy.sweep(item:getInventory(), depth + 1)
        end
    end
end

return WB_Legacy
