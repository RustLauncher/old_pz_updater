--[[
    "Carregar no carrinho": move varios itens de uma vez.

    ======================================================================
    O QUE ISTO CONSERTA

    Arrastar 20 troncos para o carrinho movia 5 e parava. Repetir movia mais 4, e
    assim por diante.

    A causa esta em DraggedItems:update, o preditor de lote da interface. Ele soma o
    peso de cada item arrastado e pergunta se o total cabe:

        newTotalWeight = totalWeight + item:getUnequippedWeight()
        container:hasRoomFor(playerObj, newTotalWeight, newWeightAddedToFloor)

    Vinte troncos somam 180 de peso REAL contra os 50 de teto, entao ele corta em 5.
    O preditor assume uma coisa que aqui e falsa: que o peso de um item nao muda ao
    entrar no container. No carrinho ele muda -- cada tronco passa a ocupar 1.8.

    ======================================================================
    POR QUE NAO ENVOLVER O PREDITOR

    ISInventoryPaneDraggedItems e global, entao daria para substituir o update. Mas o
    portao mora no meio de cem linhas que fazem outras cinco coisas -- ordenacao,
    limite de peso do chao, itens proibidos, o caso especial de assento de veiculo.
    Reimplementar isso e assinar a manutencao de codigo de interface do jogo a cada
    atualizacao, e o pedido explicito aqui foi o oposto: sobreviver a updates.

    ======================================================================
    O QUE ESTE ARQUIVO FAZ

    Enfileira UMA transferencia vanilla por item, e nada mais.

    ISInventoryTransferAction revalida capacidade por conta propria, por item
    (linha 110: destContainer:hasRoomFor(character, item)). Entao a regra continua
    sendo do jogo -- o que deixamos de lado e apenas a PREVISAO em lote, que estava
    errada por assumir peso constante. Quando o sexto tronco e transferido, os cinco
    primeiros ja estao reacondicionados e a conta dele fecha.

    Consequencia de desenho: nao ha limite proprio aqui, e nao deve haver. Quem diz
    "chega" e o mesmo hasRoomFor de sempre, item a item. Um limite nosso em paralelo
    seria uma segunda ideia de "cabe", e este projeto ja pagou tres vezes por isso.
]]

local WB_Cart = require "WB_Cart"

local WB_Load = {}

--- Distancia, em squares, para considerar um carrinho largado no chao.
local REACH = 2

--- @return InventoryItem|nil o carrinho para onde carregar
---
--- Prefere o que esta nas maos: se o jogador esta segurando um, e nele que ele quer
--- por as coisas. So depois procura no chao ao redor.
local function targetCart(character)
    local carried = WB_Cart.equipped(character)
    if carried ~= nil then return carried end

    local found = nil
    WB_Cart.forEachOnGround(character, REACH, function(cart)
        if found == nil then found = cart end
    end)
    return found
end

--- @return table itens que ainda nao estao dentro deste carrinho
local function loadable(items, cart)
    local inventory = cart:getInventory()
    local out = {}
    for i = 1, #items do
        local item = items[i]
        -- Sem tabela literal em ipairs e sem furo no meio: o verificador de Lua
        -- recusa as duas coisas, e o defeito que ele previne ja apareceu aqui.
        if item ~= nil and item:getContainer() ~= inventory
            and not WB_Cart.is(item) then
            out[#out + 1] = item
        end
    end
    return out
end

--- @param playerNum number indice de tela de quem abriu o menu
---
--- O NUMERO DO JOGADOR VEM DO MENU, e nao de getSpecificPlayer(0).
---
--- Esta funcao fixava o indice 0 enquanto o handler que monta a opcao -- logo abaixo
--- -- recebe o playerNum e o usa corretamente. Em tela dividida a opcao aparecia para
--- o jogador 2 e a transferencia rodava com o personagem do jogador 1: itens saindo
--- do inventario errado, sem nenhum aviso.
---
--- WB_Corpse.onDropCorpse ja fazia certo; este era o unico fora do padrao.
local function onLoad(playerNum, items, cart)
    local character = getSpecificPlayer(playerNum)
    if character == nil or cart == nil then return end

    for i = 1, #items do
        -- Uma acao por item, a do jogo. Ela revalida a capacidade sozinha, entao a
        -- fila para naturalmente quando o carrinho enche -- sem nenhuma contagem
        -- nossa em paralelo.
        ISTimedActionQueue.add(ISInventoryTransferAction:new(
            character, items[i], items[i]:getContainer(), cart:getInventory()))
    end
end

function WB_Load.onFillInventoryObjectContextMenu(playerNum, context, items)
    local character = getSpecificPlayer(playerNum)
    if character == nil or items == nil then return end

    local cart = targetCart(character)
    if cart == nil then return end

    -- A lista vem com entradas que sao o item OU um agrupamento com .items dentro,
    -- dependendo de a interface ter empilhado iguais. Normalizar aqui evita espalhar
    -- esse detalhe pelo resto do arquivo.
    local flat = {}
    for i = 1, #items do
        local entry = items[i]
        if instanceof(entry, "InventoryItem") then
            flat[#flat + 1] = entry
        elseif entry ~= nil and entry.items ~= nil then
            for j = 1, #entry.items do flat[#flat + 1] = entry.items[j] end
        end
    end

    local pending = loadable(flat, cart)
    if #pending < 2 then return end

    --[[ A ORDEM AQUI E CONTRATO: ISContextMenu:onMouseUp chama
         onSelect(target, param1, param2, ...). Entao target=playerNum e a funcao
         recebe (playerNum, pending, cart) -- nessa ordem, e tools_check_contextmenu.py
         confere que a assinatura bate. ]]
    context:addOption(
        getText("ContextMenu_MNWB_LoadInto") .. " " .. cart:getName(),
        playerNum, onLoad, pending, cart)
end

Events.OnFillInventoryObjectContextMenu.Add(WB_Load.onFillInventoryObjectContextMenu)

return WB_Load
