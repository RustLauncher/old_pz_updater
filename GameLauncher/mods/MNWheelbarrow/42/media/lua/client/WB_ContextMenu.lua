--[[
    O desvio do EQUIPAR, e so ele.

    ESTE ARQUIVO NAO ACRESCENTA NENHUMA OPCAO AO MENU, e a ausencia e a regra e nao
    uma falta. O mod nao compete com o jogo base pelo menu: ele troca o que as opcoes
    JA existentes fazem quando o item e um carrinho. O jogador continua vendo os
    rotulos de sempre, no lugar de sempre.

    Todos os desvios de LARGAR moram em WB_Placement, junto com os de pegar:

        pegar    ISGrabItemAction.new, onGrabItems
        largar   ISInventoryTransferAction.new (arrastar e o menu de soltar),
                 ISInventoryPaneContextMenu.dropItem,
                 ISDropWorldItemAction.new (o cursor de posicionamento)

    O QUE HAVIA AQUI E POR QUE SAIU (17/08/2026): uma opcao propria, "Largar o
    carrinho de mao". Ela existia porque, na epoca, o jogo base nao oferecia largar
    com a nossa mecanica -- os caminhos dele punham o carrinho no chao sem a acao
    cronometrada, logo sem a janela em que interromper derruba a carga.

    Quando os tres caminhos do jogo passaram a rodar a nossa acao, ela virou uma
    segunda entrada fazendo exatamente o mesmo que a do jogo, ao lado dela. E o
    argumento contra isso ja estava escrito neste proprio cabecalho, para o PEGAR:
    duas opcoes identicas sao pior que uma, porque o jogador fica escolhendo entre
    coisas que nao diferem. Aplicar o mesmo criterio ao largar foi decisao do Marcos.

    Sobra o desvio do equipar, que nao e uma opcao nova: e a opcao "Equipar com as
    duas maos" do jogo passando a levar tempo.

    Fica em client/ porque menu de contexto e interface.
]]

require "TimedActions/ISWheelbarrowPickUp"

local WB_Cart = require "WB_Cart"

local WB_ContextMenu = {}

--[[
    Equipar pelo menu do jogo passa a usar a acao cronometrada.

    O primeiro corte deixou a acao so nas opcoes proprias, e o resultado foi o
    esperado em retrospecto: o jogador usou "Equip Two Hands", que e a opcao
    obvia e continua instantanea, e cancelar nao derramou nada. A punicao existia
    num caminho que ninguem percorria.

    Em vez de esconder a opcao do jogo -- que e a boa, e que o proprio Marcos
    preferiu por ser mais intuitiva -- trocamos o que ela FAZ quando o item e um
    carrinho. Assim so ha um jeito de por o carrinho nas maos, e ele leva tempo.

    O envelope preserva o comportamento original para todo o resto: qualquer
    outro item continua no caminho do jogo, e outros mods que tambem envolvam
    esta funcao continuam encadeados.
]]
Events.OnGameStart.Add(function()
    if ISInventoryPaneContextMenu == nil then return end

    local original = ISInventoryPaneContextMenu.OnTwoHandsEquip
    ISInventoryPaneContextMenu.OnTwoHandsEquip = function(items, player)
        local character = getSpecificPlayer(player)
        -- getActualItems desempacota os grupos empilhados da lista do menu; sem
        -- isso o primeiro elemento pode ser a tabela do grupo, e nao um item.
        local actual = ISInventoryPane.getActualItems(items)
        local first = actual and actual[1]

        if character ~= nil and WB_Cart.is(first) then
            ISTimedActionQueue.add(
                ISWheelbarrowPickUp:new(character, nil, first))
            return
        end
        return original(items, player)
    end
end)

return WB_ContextMenu
