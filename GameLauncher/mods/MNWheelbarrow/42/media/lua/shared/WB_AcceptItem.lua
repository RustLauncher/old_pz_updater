--[[
    Guarda-corpo de conteudo do carrinho.

    Este e o UNICO lugar que declara a tabela global MNWheelbarrow, e ela
    existe por um motivo especifico: items_wheelbarrow.txt referencia
    "MNWheelbarrow.AcceptItem" por nome, e scripts .txt so alcancam globais.
    Todo o resto do codigo usa require/return e nao polui o global.

    Duas coisas moram aqui: o que quebraria o jogo, e o TETO DE CARGA LEVE.

    POR QUE O TETO DE CARGA LEVE NAO E A CAPACIDADE: o engine tem UM numero de
    capacidade, comparado contra o peso bruto total. Ele nao consegue dizer "leve
    ate 50, total ate 200". Tentar simular isso mexendo na capacidade conforme o
    conteudo tem um defeito que so aparece na ordem errada: um carrinho com 50 kg
    de livros passaria a recusar um gerador, porque a capacidade teria encolhido
    para 50. Aqui a pergunta e feita por item, e a ordem deixa de importar.

    Item leve nao ganha reducao de peso (ver WB_Weight.lua) -- isso continua sendo
    o que torna o carrinho pouco atraente para tralha. O teto e o que impede o
    absurdo aritmetico de 200 livros.
]]

local WB_Const = require "WB_Const"
local WB_Repack = require "WB_Repack"
local WB_Cart = require "WB_Cart"
local WB_Sandbox = require "WB_Sandbox"
local WB_Trace = require "WB_Trace"
local WB_Weight = require "WB_Weight"

local CORPSES = {
    ["Base.CorpseMale"] = true,
    ["Base.CorpseFemale"] = true,
    ["Base.CorpseAnimal"] = true,
}

--- @return number peso bruto dos itens LEVES ja dentro do container
local function lightWeightInside(container, threshold)
    if container == nil then return 0.0 end
    local total = 0.0
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        -- Peso REAL: dentro do carrinho os itens estao reacondicionados, e somar o
        -- peso comprimido faria o teto de carga leve deixar entrar cinco vezes mais.
        local w = WB_Repack.realWeight(items:get(i))
        if w < threshold then total = total + w end
    end
    return total
end

--[[ ESTE PORTAO NAO RODA NO SERVIDOR EM MULTIPLAYER, e isso e medido.

     Durante uma leva inteira de vinte transferencias: ZERO chamadas no log do
     servidor, dezenas no console do cliente. E nao e falta de amarracao -- uma
     versao desta medicao reafirmava o nome da funcao no compartimento a cada
     varredura, e ela NUNCA precisou escrever: o compartimento ja conhecia o portao
     do lado do servidor. O engine simplesmente nao o consulta la.

     Isso derruba a frase da secao 5 do HANDOFF que dizia o contrario -- ela foi inferida
     da presenca de isItemAllowed no TransactionManager, nao observada.

     A CONSEQUENCIA, dita por inteiro: o teto de carga leve abaixo e uma regra de
     CLIENTE em multiplayer. Para um jogador honesto ela vale, porque a decisao
     inteira acontece do lado dele. Um cliente modificado a ignora.

     Nao ha conserto barato. Enforcar no servidor exigiria o relogio expulsar itens
     ja aceitos -- destruir ou espalhar coisa do jogador por uma regra de
     balanceamento e pior que a regra nao valer. Fica como divida consciente. ]]
MNWheelbarrow = MNWheelbarrow or {}

--- Chamado pelo engine para cada item que o jogador tenta colocar no carrinho.
--- @param container ItemContainer inventario do carrinho (nao usado hoje)
--- @param item InventoryItem item sendo inserido
--- @return boolean true se o item pode entrar
function MNWheelbarrow.AcceptItem(container, item)
    if item == nil then return false end

    -- Carrinho dentro de carrinho: recursao no calculo de peso e capacidade.
    -- Este e o unico bloqueio que existe por necessidade tecnica.
    if WB_Const.HAULER_TYPES[item:getFullType()] then
        return false
    end

    --[[ Cadaver e escolha de jogo, nao limitacao tecnica: tematicamente um carrinho
         de mao e exatamente o que alguem usaria. Fica LIGADO por padrao -- este
         comentario dizia "desligado" e contradizia a option, que nasceu true.

         A leitura passa por WB_Sandbox como todas as outras. Ela era direta em
         SandboxVars, e isso dava DOIS defaults para a mesma option: sem SandboxVars a
         leitura direta devolve false e o espelho devolve true, entao o portao recusava
         o cadaver que o menu de WB_Corpse -- que sempre leu pelo espelho -- acabara de
         oferecer. Nao era defeito hoje porque o portao nao e consultado antes de o save
         carregar, mas era exatamente a fonte dupla que o cabecalho de WB_Sandbox existe
         para impedir. ]]
    --[[ E A RECUSA E TUDO O QUE ESTE RAMO FAZ, porque um `return true` aqui saia por
         cima do reacondicionamento la embaixo.

         O cadaver era ACEITO com os 60 crus, e a conta de capacidade do engine, que vem
         logo depois do portao, comparava 60 contra 38 e recusava. Ou seja AllowCorpses
         ligado nao entregava o cadaver por arrastar -- so pelo menu de arrastar corpo,
         que usa throwGrappledIntoInventory e nao passa por esta conta. Medido em
         tests/test_extremos.lua, que primeiro falhou exatamente aqui.

         Deixar o cadaver ACEITO seguir o caminho de todo mundo conserta isso e nao
         desfaz a razao pela qual o reacondicionamento mora no fim: o que nao pode ser
         comprimido e o item RECUSADO, e recusado continua saindo antes. ]]
    if CORPSES[item:getFullType()] and WB_Sandbox.get("AllowCorpses") ~= true then
        return false
    end

    -- TETO DE CARGA LEVE. O limite de capacidade continua valendo para o total;
    -- este e um segundo teto, so para o que nao conta como pesado.
    local threshold = WB_Sandbox.get("HeavyThreshold")
    -- O item que esta ENTRANDO ainda nao foi reacondicionado, mas realWeight cobre os
    -- dois casos e deixa a regra insensivel a ordem.
    local weight = WB_Repack.realWeight(item)
    if weight < threshold then
        local budget = WB_Sandbox.get("LightCapacity")
        if budget > 0
            and lightWeightInside(container, threshold) + weight > budget then
            return false
        end
    end

    --[[ O ITEM QUE ENTRA E MEDIDO PELO PESO QUE ELE VAI TER, e nao pelo de fora.

         DEPOIS DE TODAS AS RECUSAS, de proposito. Reacondicionar e um efeito
         colateral num predicado, e ele so se justifica para item que vai mesmo
         entrar. Comprimir antes deixaria carrinho-dentro-de-carrinho e cadaver
         recusado saindo daqui comprimidos fora de um carrinho -- estado que a
         invariante de WB_Repack desfaz sozinha, mas que nao ha razao de criar.

         Este portao e o unico ponto do mod que o engine chama ANTES da conta de
         capacidade: TransactionManager.isConsistent chama isItemAllowed nos offsets
         183 e 1136, e compara capacidade nos 1085 e 1257. Nos dois ramos, nessa
         ordem.

         Sem reacondicionar aqui, a comparacao usa 9.0 para um tronco que vai pesar
         1.8 la dentro -- e o jogador ve folga na barra e recebe recusa. Foi
         exatamente a queixa medida em 16/08/2026.

         E A VARREDURA DO CONTEUDO CONTINUA SENDO PRECISA -- nao basta comprimir o
         que entra. Isto foi removido em 16/08/2026 com o argumento de que, comprimindo
         o item ANTES da entrada, nenhum item chegaria cru la dentro e a varredura
         viraria custo por nada. O argumento supoe que TODO item entra por este portao.

         E falso, e foi medido no mesmo dia: o engine consulta este portao em alguns
         caminhos e nao em outros (secao 5 do HANDOFF-MP). O que entra por um caminho sem
         portao fica cru ate a proxima batida do relogio de servidor -- trinta ticks
         --, o peso do conteudo incha, e a comparacao de capacidade que vem logo
         depois recusa cedo.

         Sintoma medido da remocao: uma leva de 20 troncos parava em 17; tentando de
         novo, um a um, enchia ate 21. A diferenca entre os dois e exatamente o tempo
         que o relogio tem para comprimir entre uma transferencia e a seguinte.

         O custo e real e conhecido: este portao e chamado muitas vezes por quadro
         enquanto o jogador arrasta, porque o preditor da interface o consulta por
         item. A varredura e idempotente e curta -- o conteudo de um carrinho sao
         dezenas de itens, nao milhares --, e a alternativa nao e "mais barato", e
         "errado mais barato".

         A conta de capacidade e reducao continua so no servidor: no cliente os
         eventos ja a mantem em dia, e la ela nao e barata. ]]
    local cart = container ~= nil and container:getContainingItem() or nil
    if WB_Cart.is(cart) then
        WB_Repack.sweepCart(cart)
        WB_Repack.repackIncoming(item)
        if isServer() then WB_Weight.refresh(cart) end

        local worldItem = cart:getWorldItem()
        local square = worldItem ~= nil and worldItem:getSquare() or nil
        WB_Trace.log("PORTAO", string.format(
            "%s: dentro=%d peso=%.1f cap=%d reducao=%d%% entrando=%.1f chao=%s",
            item:getFullType(), container:getItems():size(),
            container:getCapacityWeight(), container:getCapacity(),
            cart:getWeightReduction(), item:getUnequippedWeight(),
            square ~= nil
                and string.format("%.1f de 50", square:getTotalWeightOfItemsOnFloor())
                or "carrinho nao esta no chao"))
    end

    return true
end

--[[ Anuncio de carga, so no servidor e sem guarda.

     O engine resolve este portao por NOME, com LuaManager.getFunctionObject sobre a
     string do script (AcceptItemFunction = MNWheelbarrow.AcceptItem) -- ver
     ItemContainer.isItemAllowed, offsets 74-104. Se o global nao existir no
     processo, o engine simplesmente pula o portao, em silencio.

     Uma linha no boot separa "o arquivo nao carregou" de "o engine nao chamou", que
     foi exatamente a duvida que custou uma rodada aqui. ]]
if isServer() then
    print("[WB][SRV] WB_AcceptItem carregado; MNWheelbarrow.AcceptItem = "
        .. tostring(MNWheelbarrow.AcceptItem ~= nil))
end

return MNWheelbarrow
